import Foundation
import AVFoundation

/// TempoEngine status shared with the UI/diagnostics.
struct TempoEngineStatus {
    enum State: String { case idle, loading, playing, paused, stopped }

    var state: State = .idle
    /// BPM of the source material.
    var sourceBpm: Double?
    /// BPM the engine is ramping toward.
    var targetBpm: Double?
    /// BPM actually sounding right now (mid-ramp values included).
    var currentBpm: Double?
    /// currentBpm / sourceBpm — the effective time-stretch rate.
    var playbackRate: Double = 1
    /// AVAudioUnitTimePitch preserves pitch while changing rate.
    var pitchPreserved: Bool = true
}

/// DemoTempoEngine — native pitch-preserving tempo shifting with
/// AVAudioEngine + AVAudioUnitTimePitch.
///
/// This is the proof of Pacer's core concept: the SAME song smoothly speeds
/// up or slows down to follow the runner's cadence.
///
/// Legal scope: ONLY used for audio we are permitted to manipulate — the
/// bundled synthesized loops (authored by this project) or user-provided
/// files the user represents they may use. Never for protected Apple
/// Music/Spotify streams; those providers get track *selection* instead
/// (see AppleMusicProvider).
///
/// `AVAudioUnitTimePitch.rate` performs pitch-preserving time-stretching in
/// the range 1/32…32; we clamp to a musically sane 0.6…1.6 and ease toward
/// the target rate in small steps for a smooth, non-jarring transition.
final class DemoTempoEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    private var buffer: AVAudioPCMBuffer?
    private var loadedResource: String?

    private let lock = NSLock()
    private var _status = TempoEngineStatus()
    private var rampTimer: Timer?

    /// Rate clamp: keeps stretched audio musical.
    private let minRate = 0.6
    private let maxRate = 1.6
    /// Ramp step cadence.
    private let rampStepInterval: TimeInterval = 0.08

    var onStatusChange: ((TempoEngineStatus) -> Void)?

    var status: TempoEngineStatus {
        lock.withLock { _status }
    }

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
    }

    /// Load a bundled wav (Resources/Audio/<name>.wav) and remember its BPM.
    func load(resourceName: String, sourceBpm: Double) throws {
        if loadedResource == resourceName { return }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
            throw NSError(
                domain: "Pacer", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bundled audio \(resourceName).wav not found"]
            )
        }
        try load(url: url, sourceBpm: sourceBpm)
        loadedResource = resourceName
    }

    /// Load any local audio file the user is permitted to use.
    func load(url: URL, sourceBpm: Double) throws {
        setStatus { s in
            s.state = .loading
            s.sourceBpm = sourceBpm
            s.targetBpm = sourceBpm
            s.currentBpm = sourceBpm
            s.playbackRate = 1
        }
        let file = try AVAudioFile(forReading: url)
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        else {
            throw NSError(
                domain: "Pacer", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer"]
            )
        }
        try file.read(into: buffer)
        player.stop()
        self.file = file
        self.buffer = buffer
        self.loadedResource = nil
        timePitch.rate = 1
        setStatus { $0.state = .paused }
    }

    func play() throws {
        guard let buffer else { return }
        try configureAudioSession()
        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            // Seamless loop: the synthesized loops are exact bar multiples.
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            player.play()
        }
        setStatus { $0.state = .playing }
    }

    func pause() {
        player.pause()
        setStatus { $0.state = .paused }
    }

    func stop() {
        rampTimer?.invalidate()
        rampTimer = nil
        player.stop()
        engine.pause()
        setStatus { s in
            s.state = .stopped
            if let source = s.sourceBpm {
                s.currentBpm = source
                s.targetBpm = source
                s.playbackRate = 1
            }
        }
    }

    /// Glide the audible tempo toward `bpm` over `ramp` seconds using an
    /// ease-in-out curve. The clamp keeps extreme requests musical.
    func setTargetBpm(_ bpm: Double, ramp: TimeInterval = 2.5) {
        let current = status
        guard let sourceBpm = current.sourceBpm, sourceBpm > 0 else { return }
        let clamped = min(sourceBpm * maxRate, max(sourceBpm * minRate, bpm))
        let start = current.currentBpm ?? sourceBpm
        let delta = clamped - start

        setStatus { $0.targetBpm = clamped }
        rampTimer?.invalidate()

        if abs(delta) < 0.1 || ramp <= 0 {
            applyBpm(clamped)
            return
        }

        let steps = max(1, Int((ramp / rampStepInterval).rounded()))
        var step = 0
        let timer = Timer(timeInterval: rampStepInterval, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            step += 1
            let t = Double(step) / Double(steps)
            // Ease-in-out for a musical, non-jarring transition.
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            self.applyBpm(start + delta * eased)
            if step >= steps {
                self.applyBpm(clamped)
                timer.invalidate()
                self.rampTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
    }

    private func applyBpm(_ bpm: Double) {
        guard let sourceBpm = status.sourceBpm, sourceBpm > 0 else { return }
        let rate = Float(bpm / sourceBpm)
        timePitch.rate = rate
        setStatus { s in
            s.currentBpm = bpm
            s.playbackRate = Double(rate)
        }
    }

    private func configureAudioSession() throws {
        // .playback keeps audio alive with the screen locked (with the
        // audio background mode enabled in project.yml).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func setStatus(_ mutate: (inout TempoEngineStatus) -> Void) {
        let snapshot: TempoEngineStatus = lock.withLock {
            mutate(&_status)
            return _status
        }
        onStatusChange?(snapshot)
    }
}
