import Foundation

/// SessionRecorder — accumulates everything that happens during a run so it
/// can be summarized and persisted (run_sessions / cadence_samples /
/// playback_decisions in Supabase).
public struct SessionRecorder: Sendable {
    public struct SamplePoint: Sendable, Codable, Equatable {
        public let t: Date
        public let raw: Double
        public let smoothed: Double?
    }

    public struct SongPlay: Sendable, Codable, Equatable {
        public let trackID: String
        public let name: String
        public let artist: String
        public let startedAt: Date
    }

    public struct TargetChange: Sendable, Codable, Equatable {
        public let t: Date
        public let targetSpm: Int
        public let reason: String
    }

    public struct Summary: Sendable, Equatable {
        public let startedAt: Date
        public let endedAt: Date
        public let mode: RunMode
        public let requestedTargetSpm: Int?
        public let averageCadence: Double?
        public let peakCadence: Double?
        /// Fraction of samples within `onBeatToleranceSpm` of the active target.
        public let onBeatPercent: Double?
        public let samples: [SamplePoint]
        public let songsPlayed: [SongPlay]
        public let targetChanges: [TargetChange]
        public let decisions: [CadenceDecision]
        public let cadenceSource: CadenceSource
    }

    public let startedAt: Date
    public let mode: RunMode
    public let requestedTargetSpm: Int?
    public let cadenceSource: CadenceSource
    /// A sample counts as "on beat" when within this many SPM of the target.
    public var onBeatToleranceSpm: Double = 5

    private(set) var samples: [SamplePoint] = []
    private(set) var songsPlayed: [SongPlay] = []
    private(set) var targetChanges: [TargetChange] = []
    private(set) var decisions: [CadenceDecision] = []
    private var activeTarget: Int?
    private var onBeatCount = 0
    private var movingSampleCount = 0

    public init(
        startedAt: Date,
        mode: RunMode,
        requestedTargetSpm: Int? = nil,
        cadenceSource: CadenceSource
    ) {
        self.startedAt = startedAt
        self.mode = mode
        self.requestedTargetSpm = requestedTargetSpm
        self.cadenceSource = cadenceSource
        if mode == .paceMe, let requestedTargetSpm {
            activeTarget = requestedTargetSpm
        }
    }

    public mutating func recordSample(t: Date, raw: Double, smoothed: Double?) {
        samples.append(SamplePoint(t: t, raw: raw, smoothed: smoothed))
        guard raw > 0 else { return }
        movingSampleCount += 1
        if let target = activeTarget, let smoothed, abs(smoothed - Double(target)) <= onBeatToleranceSpm {
            onBeatCount += 1
        }
    }

    public mutating func recordDecision(_ decision: CadenceDecision) {
        decisions.append(decision)
        if decision.kind == .initialLock || decision.kind == .retarget, let target = decision.targetSpm {
            // In Pace Me the musical target is user-controlled; the engine's
            // targets are informational only.
            if mode == .followMe {
                activeTarget = target
                targetChanges.append(TargetChange(t: decision.at, targetSpm: target, reason: decision.reason))
            }
        }
    }

    /// For Pace Me: the user moved the target slider.
    public mutating func recordUserTargetChange(t: Date, targetSpm: Int) {
        activeTarget = targetSpm
        targetChanges.append(TargetChange(t: t, targetSpm: targetSpm, reason: "user set target"))
    }

    public mutating func recordSongStart(t: Date, trackID: String, name: String, artist: String) {
        songsPlayed.append(SongPlay(trackID: trackID, name: name, artist: artist, startedAt: t))
    }

    public func summary(endedAt: Date) -> Summary {
        let moving = samples.filter { $0.raw > 0 }
        let avg = Filters.mean(moving.map(\.raw))
        let peak = moving.map(\.raw).max()
        let onBeat: Double? = movingSampleCount > 0
            ? Double(onBeatCount) / Double(movingSampleCount) * 100
            : nil
        return Summary(
            startedAt: startedAt,
            endedAt: endedAt,
            mode: mode,
            requestedTargetSpm: requestedTargetSpm,
            averageCadence: avg,
            peakCadence: peak,
            onBeatPercent: onBeat,
            samples: downsampled(maxPoints: 600),
            songsPlayed: songsPlayed,
            targetChanges: targetChanges,
            decisions: decisions,
            cadenceSource: cadenceSource
        )
    }

    /// Keep persisted traces bounded: at most `maxPoints`, evenly strided.
    public func downsampled(maxPoints: Int) -> [SamplePoint] {
        guard samples.count > maxPoints, maxPoints > 0 else { return samples }
        let stride = Double(samples.count) / Double(maxPoints)
        return (0..<maxPoints).map { samples[Int(Double($0) * stride)] }
    }
}
