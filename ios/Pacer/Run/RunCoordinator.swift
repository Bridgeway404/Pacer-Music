import Foundation
import PacerKit

/// Which cadence source drives the run.
enum CadenceProviderKind: String, CaseIterable, Identifiable {
    case coreMotion = "iPhone Motion"
    case simulator = "Simulator"
    case tap = "Manual Tap"

    var id: String { rawValue }
}

/// Which music source plays.
enum MusicSourceKind: String, CaseIterable, Identifiable {
    case demo = "Demo Mode"
    case appleMusic = "Apple Music"

    var id: String { rawValue }
}

/// How the music currently relates to the runner — drives the status pill.
enum MusicSyncState: String {
    case waiting = "Waiting for cadence"
    case matching = "On your beat"
    case catchingUp = "Catching up"
    case slowingDown = "Slowing down"
    case selecting = "Choosing tracks"
    case stopped = "Paused"
}

struct DiagnosticsEvent: Identifiable {
    let id = UUID()
    let at: Date
    let text: String
}

/// RunCoordinator — the conductor of a run session.
///
///     CadenceProvider → CadenceEngine → target SPM
///        → (Follow Me: engine target | Pace Me: user target)
///        → Sequencer (Up Next) + TempoEngine / MusicProvider
///
/// All business rules live in PacerKit; this class only wires platform
/// services together and exposes observable state to SwiftUI.
@MainActor
@Observable
final class RunCoordinator {
    enum RunState: String {
        case idle, running, paused, ended
    }

    // MARK: Configuration
    var mode: RunMode = .followMe {
        didSet { handleModeChange() }
    }
    var providerKind: CadenceProviderKind = .simulator
    var musicSource: MusicSourceKind = .demo
    /// Pace Me user-selected target.
    var paceTargetSpm: Int = 165 {
        didSet { handlePaceTargetChange(oldValue: oldValue) }
    }

    // MARK: Live state
    private(set) var runState: RunState = .idle
    private(set) var rawSpm: Double?
    private(set) var smoothedSpm: Double?
    private(set) var engineTargetSpm: Int?
    private(set) var engineState: CadenceEngineState = .idle
    private(set) var pendingRetarget: (candidateSpm: Int, since: TimeInterval)?
    private(set) var startedAt: Date?
    private(set) var elapsed: TimeInterval = 0
    private(set) var syncState: MusicSyncState = .waiting
    private(set) var lastDecision: CadenceDecision?
    private(set) var diagnostics: [DiagnosticsEvent] = []
    private(set) var beatPulse: Int = 0

    // MARK: Music state
    private(set) var trackPool: [PacerTrack] = []
    private(set) var currentTrack: PacerTrack?
    private(set) var upNext: [RankedTrack] = []
    private(set) var isMusicPlaying = false
    private(set) var tempoStatus = TempoEngineStatus()
    private(set) var recentlyPlayedIDs: [String] = []
    private(set) var skippedIDs: [String] = []
    private(set) var lastSummary: SessionRecorder.Summary?
    private(set) var lastError: String?

    /// The musical target the system is currently aiming at.
    var musicalTargetSpm: Int? {
        mode == .paceMe ? paceTargetSpm : engineTargetSpm
    }

    /// Pace Me helper: signed gap between target and current smoothed cadence.
    var paceGapSpm: Int? {
        guard mode == .paceMe, let smoothed = smoothedSpm, smoothed > 0 else { return nil }
        return paceTargetSpm - Int(smoothed.rounded())
    }

    // MARK: Internals
    private var engine = CadenceEngine()
    private var recorder: SessionRecorder?
    private var provider: (any CadenceProviding)?
    private var consumeTask: Task<Void, Never>?
    private var ticker: Timer?
    private var beatTimer: Timer?

    let tempoEngine = DemoTempoEngine()
    private lazy var demoProvider = DemoMusicProvider(tempoEngine: tempoEngine)
    private lazy var appleProvider = AppleMusicProvider()
    let tapProvider = ManualTapCadenceProvider()
    let simulatorProvider = SimulatedCadenceProvider()

    var activeMusicProvider: any MusicProviding {
        if musicSource == .demo {
            return demoProvider
        }
        return appleProvider
    }

    init() {
        tempoEngine.onStatusChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.tempoStatus = status
            }
        }
        trackPool = DemoMusicProvider.demoTracks
        refreshQueue()
    }

    // MARK: - Run lifecycle

    func startRun() async {
        guard runState == .idle || runState == .ended else { return }
        lastError = nil
        engine = CadenceEngine()
        recorder = SessionRecorder(
            startedAt: Date(),
            mode: mode,
            requestedTargetSpm: mode == .paceMe ? paceTargetSpm : nil,
            cadenceSource: cadenceSource(for: providerKind)
        )
        startedAt = Date()
        elapsed = 0
        recentlyPlayedIDs = []
        skippedIDs = []
        lastSummary = nil

        let provider = makeProvider()
        self.provider = provider
        do {
            try await provider.start()
        } catch {
            lastError = error.localizedDescription
            log("cadence provider failed: \(error.localizedDescription)")
            self.provider = nil
            return
        }

        runState = .running
        syncState = .waiting
        log("run started — \(mode.displayName), \(provider.label), \(musicSource.rawValue)")

        consumeTask = Task { [weak self] in
            for await sample in provider.cadenceStream {
                await self?.ingest(sample: sample)
            }
        }

        let ticker = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickSecond()
            }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        await loadTrackPool()
        if mode == .paceMe {
            await retargetMusic(to: paceTargetSpm, reason: "pace me target")
        }
        startBeatClock()
    }

    func endRun() async {
        guard runState == .running || runState == .paused else { return }
        provider?.stop()
        provider = nil
        consumeTask?.cancel()
        consumeTask = nil
        ticker?.invalidate()
        ticker = nil
        stopBeatClock()
        await activeMusicProvider.stopPlayback()
        isMusicPlaying = false
        runState = .ended
        syncState = .stopped

        if let recorder {
            let summary = recorder.summary(endedAt: Date())
            lastSummary = summary
            await persist(summary: summary)
        }
        recorder = nil
        log("run ended")
    }

    func togglePause() async {
        switch runState {
        case .running:
            runState = .paused
            await activeMusicProvider.pause()
            isMusicPlaying = false
            syncState = .stopped
        case .paused:
            runState = .running
            try? await activeMusicProvider.resume()
            isMusicPlaying = true
            syncState = .waiting
        default:
            break
        }
    }

    // MARK: - Music controls

    func togglePlayback() async {
        if isMusicPlaying {
            await activeMusicProvider.pause()
            isMusicPlaying = false
        } else {
            do {
                if activeMusicProvider.playbackState.track == nil {
                    await playBestTrack(reason: "user pressed play")
                } else {
                    try await activeMusicProvider.resume()
                }
                isMusicPlaying = true
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func skip() async {
        if let current = currentTrack {
            skippedIDs.append(current.id)
            log("skipped \(current.name)")
        }
        await playBestTrack(reason: "user skipped")
    }

    // MARK: - Sample pipeline

    private func ingest(sample: CadenceSample) async {
        guard runState == .running else { return }
        let update = engine.addSample(sample)
        apply(update: update, raw: sample.spm)
    }

    private func tickSecond() {
        guard runState == .running else { return }
        if let startedAt {
            elapsed = Date().timeIntervalSince(startedAt)
        }
        let update = engine.tick(now: Date())
        apply(update: update, raw: nil)
    }

    private func apply(update: CadenceEngineUpdate, raw: Double?) {
        rawSpm = update.rawSpm
        smoothedSpm = update.smoothedSpm
        engineTargetSpm = update.targetSpm
        engineState = update.state
        pendingRetarget = update.pending

        if let raw {
            recorder?.recordSample(t: update.at, raw: raw, smoothed: update.smoothedSpm)
        }

        if let decision = update.decision {
            lastDecision = decision
            recorder?.recordDecision(decision)
            log("engine: \(decision.reason)")

            switch decision.kind {
            case .initialLock, .retarget:
                if mode == .followMe, let target = decision.targetSpm {
                    Task { await self.retargetMusic(to: target, reason: decision.reason) }
                }
            case .stop:
                syncState = .waiting
                if musicSource == .demo {
                    tempoEngine.pause()
                    isMusicPlaying = false
                    log("music paused — runner stopped")
                }
            case .resume:
                if musicSource == .demo, runState == .running {
                    try? tempoEngine.play()
                    isMusicPlaying = true
                }
            }
        }

        updateSyncState()
    }

    // MARK: - Music targeting

    private func retargetMusic(to targetSpm: Int, reason: String) async {
        refreshQueue()
        guard isMusicPlaying || musicSource == .demo else { return }

        if musicSource == .demo {
            let target = Double(targetSpm)
            let currentMatch = BpmMatcher.match(cadenceSpm: target, trackBpm: currentTrack?.bpm)
            // Stay on the current loop if a musically small stretch reaches
            // the target; otherwise let the sequencer pick a closer track.
            if let match = currentMatch, (0.8...1.25).contains(match.recommendedPlaybackRate) {
                tempoEngine.setTargetBpm(match.recommendedTargetTempo, ramp: 2.5)
                log("tempo-shift → \(Int(match.recommendedTargetTempo.rounded())) BPM (rate \(String(format: "%.2f", match.recommendedPlaybackRate))) — \(reason)")
            } else if isMusicPlaying {
                await playBestTrack(reason: "target \(targetSpm) SPM outside stretch range")
            }
        } else {
            // Apple Music: no tempo manipulation is permitted — the queue
            // adapts and the next selection happens on skip/track end.
            log("queue reranked for \(targetSpm) SPM — \(reason)")
        }
    }

    private func playBestTrack(reason: String) async {
        guard let target = musicalTargetSpm ?? engineTargetSpm else {
            syncState = .waiting
            return
        }
        let context = SequencerContext(
            targetSpm: Double(target),
            currentTrack: currentTrack,
            recentlyPlayedIDs: recentlyPlayedIDs,
            skippedIDs: skippedIDs
        )
        guard let next = Sequencer.pickNextTrack(trackPool, context: context) else { return }
        do {
            try await activeMusicProvider.play(track: next.track)
            currentTrack = next.track
            recentlyPlayedIDs.append(next.track.id)
            if recentlyPlayedIDs.count > 10 {
                recentlyPlayedIDs.removeFirst(recentlyPlayedIDs.count - 10)
            }
            isMusicPlaying = true
            recorder?.recordSongStart(
                t: Date(), trackID: next.track.id, name: next.track.name, artist: next.track.artist
            )
            log("now playing \(next.track.name) — \(reason)")

            // Demo mode: immediately stretch the fresh track onto the target.
            if musicSource == .demo,
               let match = BpmMatcher.match(cadenceSpm: Double(target), trackBpm: next.track.bpm) {
                tempoEngine.setTargetBpm(match.recommendedTargetTempo, ramp: 1.5)
            }
            refreshQueue()
        } catch {
            lastError = error.localizedDescription
            log("playback failed: \(error.localizedDescription)")
        }
    }

    private func refreshQueue() {
        let target = musicalTargetSpm ?? 160
        let context = SequencerContext(
            targetSpm: Double(target),
            currentTrack: currentTrack,
            recentlyPlayedIDs: recentlyPlayedIDs,
            skippedIDs: skippedIDs
        )
        upNext = Sequencer.buildQueue(trackPool, context: context, length: 5)
    }

    private func loadTrackPool() async {
        do {
            let playlists = try await activeMusicProvider.playlists()
            if let first = playlists.first {
                if first.tracks.isEmpty {
                    trackPool = try await activeMusicProvider.tracks(inPlaylist: first.providerPlaylistID)
                } else {
                    trackPool = first.tracks
                }
            }
        } catch {
            lastError = error.localizedDescription
            log("could not load playlists: \(error.localizedDescription)")
            if musicSource == .demo {
                trackPool = DemoMusicProvider.demoTracks
            }
        }
        refreshQueue()
    }

    private func updateSyncState() {
        guard runState == .running else {
            syncState = .stopped
            return
        }
        guard let target = musicalTargetSpm else {
            syncState = .waiting
            return
        }
        if musicSource == .demo {
            guard let current = tempoStatus.currentBpm, isMusicPlaying else {
                syncState = .waiting
                return
            }
            // Compare against the perceived tempo (multiplier-aware).
            let match = BpmMatcher.match(cadenceSpm: Double(target), trackBpm: currentTrack?.bpm)
            let perceivedNow = current * (match?.multiplier ?? 1)
            let gap = perceivedNow - Double(target)
            if abs(gap) <= 2 {
                syncState = .matching
            } else {
                syncState = gap < 0 ? .catchingUp : .slowingDown
            }
        } else {
            syncState = isMusicPlaying ? .selecting : .waiting
        }
    }

    // MARK: - Mode / target changes

    private func handleModeChange() {
        recorder?.recordUserTargetChange(
            t: Date(),
            targetSpm: mode == .paceMe ? paceTargetSpm : (engineTargetSpm ?? paceTargetSpm)
        )
        log("mode → \(mode.displayName)")
        guard runState == .running else {
            refreshQueue()
            return
        }
        if mode == .paceMe {
            Task { await retargetMusic(to: paceTargetSpm, reason: "switched to Pace Me") }
        } else if let target = engineTargetSpm {
            Task { await retargetMusic(to: target, reason: "switched to Follow Me") }
        }
    }

    private func handlePaceTargetChange(oldValue: Int) {
        guard mode == .paceMe, paceTargetSpm != oldValue else { return }
        recorder?.recordUserTargetChange(t: Date(), targetSpm: paceTargetSpm)
        guard runState == .running else {
            refreshQueue()
            return
        }
        Task { await retargetMusic(to: paceTargetSpm, reason: "user set \(paceTargetSpm) SPM") }
    }

    // MARK: - Persistence

    private func persist(summary: SessionRecorder.Summary) async {
        let playlistName = musicSource == .demo ? "Pacer Demo Mix" : "Apple Music"
        if SupabaseService.shared.isSignedIn {
            do {
                _ = try await SupabaseService.shared.saveSession(summary, playlistName: playlistName)
                log("run saved to Supabase")
                return
            } catch {
                lastError = "Cloud save failed — kept locally. (\(error.localizedDescription))"
                log("cloud save failed: \(error.localizedDescription)")
            }
        }
        do {
            try LocalSessionStore.save(LocalRunRecord(summary: summary, playlistName: playlistName))
            log("run saved locally")
        } catch {
            lastError = "Could not save run: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func makeProvider() -> any CadenceProviding {
        switch providerKind {
        case .coreMotion: return CoreMotionCadenceProvider()
        case .simulator: return simulatorProvider
        case .tap: return tapProvider
        }
    }

    private func cadenceSource(for kind: CadenceProviderKind) -> CadenceSource {
        switch kind {
        case .coreMotion: .coreMotion
        case .simulator: .simulator
        case .tap: .tap
        }
    }

    private func startBeatClock() {
        stopBeatClock()
        scheduleNextBeat()
    }

    private func scheduleNextBeat() {
        let bpm = tempoStatus.currentBpm ?? Double(musicalTargetSpm ?? 160)
        let interval = 60.0 / max(40, bpm)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.runState == .running else { return }
                if self.isMusicPlaying {
                    self.beatPulse &+= 1
                }
                self.scheduleNextBeat()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        beatTimer = timer
    }

    private func stopBeatClock() {
        beatTimer?.invalidate()
        beatTimer = nil
    }

    private func log(_ text: String) {
        diagnostics.append(DiagnosticsEvent(at: Date(), text: text))
        if diagnostics.count > 200 {
            diagnostics.removeFirst(diagnostics.count - 200)
        }
    }
}
