import Foundation

/// Pure math behind the Manual Tap cadence provider: the user taps once per
/// step (or every other footfall with `stepsPerTap = 2`) and we derive SPM
/// from the median tap interval. The app layer owns timers/UI.
public struct TapCadenceCalculator: Sendable {
    public var stepsPerTap: Double
    public var windowTaps: Int
    /// If no tap for this long the runner is considered stopped, seconds.
    public var idleTimeout: TimeInterval

    private var tapTimes: [Date] = []

    public init(stepsPerTap: Double = 1, windowTaps: Int = 8, idleTimeout: TimeInterval = 3) {
        self.stepsPerTap = stepsPerTap
        self.windowTaps = windowTaps
        self.idleTimeout = idleTimeout
    }

    public mutating func tap(at time: Date) {
        tapTimes.append(time)
        if tapTimes.count > windowTaps {
            tapTimes.removeFirst(tapTimes.count - windowTaps)
        }
    }

    public mutating func reset() {
        tapTimes.removeAll()
    }

    public var lastTapAt: Date? { tapTimes.last }

    /// Current SPM estimate from recent tap intervals (nil if <2 usable taps).
    public func currentSpm(now: Date) -> Double? {
        let usable = tapTimes.filter { now.timeIntervalSince($0) <= idleTimeout * 2 }
        guard usable.count >= 2 else { return nil }
        var intervals: [TimeInterval] = []
        for i in 1..<usable.count {
            intervals.append(usable[i].timeIntervalSince(usable[i - 1]))
        }
        guard let med = Filters.median(intervals), med > 0 else { return nil }
        return (60 / med) * stepsPerTap
    }

    public func isIdle(now: Date) -> Bool {
        guard let last = tapTimes.last else { return true }
        return now.timeIntervalSince(last) >= idleTimeout
    }
}

/// Pure math behind the simulated runner: holds a target SPM, drifts toward
/// it at a bounded ramp rate, and adds triangular noise. The app layer owns
/// timers and turns steps into `CadenceSample`s.
public struct SimulatedRunnerCore: Sendable {
    public var targetSpm: Double
    public private(set) var currentSpm: Double
    /// Max SPM change per second while ramping toward the target.
    public var rampSpmPerSecond: Double
    /// Noise amplitude, SPM.
    public var noiseSpm: Double

    public init(initialSpm: Double = 154, rampSpmPerSecond: Double = 2.5, noiseSpm: Double = 2) {
        self.targetSpm = initialSpm
        self.currentSpm = initialSpm
        self.rampSpmPerSecond = rampSpmPerSecond
        self.noiseSpm = noiseSpm
    }

    /// Instantly jump (for demos of spikes).
    public mutating func jump(to spm: Double) {
        currentSpm = spm
        targetSpm = spm
    }

    /// Advance by `dt` seconds; `unitRandom` supplies randomness in [0, 1)
    /// so tests can inject a deterministic generator.
    /// Returns the noisy SPM observation (0 when stopped).
    public mutating func step(dt: TimeInterval, unitRandom: () -> Double) -> Double {
        let maxDelta = rampSpmPerSecond * dt
        let delta = targetSpm - currentSpm
        currentSpm += abs(delta) <= maxDelta ? delta : (delta < 0 ? -maxDelta : maxDelta)

        if targetSpm <= 0, currentSpm <= 1 {
            currentSpm = 0
            return 0
        }
        // Sum of two uniforms ≈ triangular noise, good enough for a fake runner.
        let noise = (unitRandom() + unitRandom() - 1) * noiseSpm * 1.6
        return max(0, currentSpm + noise)
    }
}
