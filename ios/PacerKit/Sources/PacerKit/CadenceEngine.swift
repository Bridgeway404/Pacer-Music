import Foundation

/// CadenceEngine — turns a noisy stream of raw SPM samples into a stable
/// musical target.
///
/// Design goals (see docs/ARCHITECTURE.md):
///  - Smooth ~8–12 s of history so one-off jitters don't move the target.
///  - Hysteresis: ignore differences below `changeThresholdSpm`.
///  - Sustained-change detection: a meaningful change must persist for
///    `sustain` seconds before the target moves.
///  - React to a real sustained pace change within ~10–15 s end to end.
///
/// The engine is fully deterministic: all time comes from sample timestamps
/// and explicit `tick(now:)` calls. It never reads the wall clock, which
/// makes it trivially unit-testable.
///
/// This is the production port of the TypeScript reference implementation in
/// /web/src/core/cadence/engine.ts; the test suites are kept behaviorally
/// identical.
public struct CadenceEngineConfig: Sendable {
    /// Smoothing window over raw samples, seconds.
    public var window: TimeInterval = 10
    /// Number of most-recent samples fed to the median pre-filter.
    public var medianWindow: Int = 5
    /// EMA alpha applied to the median-filtered signal.
    public var emaAlpha: Double = 0.3
    /// Minimum |smoothed − target| (SPM) considered a real change.
    public var changeThresholdSpm: Double = 4
    /// How long a candidate change must persist before we retarget, seconds.
    public var sustain: TimeInterval = 5
    /// Samples required before the first target locks.
    public var minSamplesForLock: Int = 5
    /// No samples for this long ⇒ runner is considered stopped, seconds.
    public var stopTimeout: TimeInterval = 4
    /// Raw samples outside [minValidSpm, maxValidSpm] are discarded (0 = stop signal).
    public var minValidSpm: Double = 40
    public var maxValidSpm: Double = 240

    public init() {}
}

public enum CadenceEngineState: String, Sendable {
    /// Never received a sample.
    case idle
    /// Receiving samples, no target locked yet.
    case acquiring
    /// Target established.
    case locked
    /// Runner stopped (no/zero samples).
    case stopped
}

public struct CadenceDecision: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case initialLock = "initial_lock"
        case retarget
        case stop
        case resume
    }

    public let at: Date
    public let kind: Kind
    public let targetSpm: Int?
    public let previousTargetSpm: Int?
    public let reason: String
}

public struct CadenceEngineUpdate: Sendable {
    public let at: Date
    public let rawSpm: Double?
    public let smoothedSpm: Double?
    public let targetSpm: Int?
    public let state: CadenceEngineState
    /// Present only on the updates where a decision was made.
    public let decision: CadenceDecision?
    /// Candidate retarget in progress (for diagnostics UI).
    public let pending: (candidateSpm: Int, since: TimeInterval)?
}

public final class CadenceEngine {
    public let config: CadenceEngineConfig

    private var window: RollingWindow
    private var ema: Double?
    private var smoothed: Double?
    private var target: Int?
    private var state: CadenceEngineState = .idle
    private var pendingSince: Date?
    private var lastSampleAt: Date?
    private var sampleCount = 0
    private var lastRaw: Double?

    public init(config: CadenceEngineConfig = CadenceEngineConfig()) {
        self.config = config
        self.window = RollingWindow(window: config.window)
    }

    public var currentState: CadenceEngineState { state }
    public var currentTarget: Int? { target }
    public var currentSmoothed: Double? { smoothed }

    /// Feed one raw sample. Returns the resulting engine view.
    @discardableResult
    public func addSample(_ sample: CadenceSample) -> CadenceEngineUpdate {
        let now = sample.capturedAt

        // Zero SPM is an explicit "no steps" signal.
        if sample.spm <= 0 {
            lastSampleAt = now
            return handleStop(now: now, reason: "zero-cadence sample")
        }

        // Discard physically implausible readings entirely.
        if sample.spm < config.minValidSpm || sample.spm > config.maxValidSpm {
            return snapshot(at: now, decision: nil)
        }

        lastRaw = sample.spm
        lastSampleAt = now
        sampleCount += 1
        window.push(t: now, value: sample.spm)

        // Median pre-filter kills single-sample spikes; EMA smooths the rest.
        if let med = Filters.median(window.lastValues(config.medianWindow)) {
            ema = Filters.emaStep(previous: ema, next: med, alpha: config.emaAlpha)
            smoothed = ema
        }

        var decision: CadenceDecision?

        if state == .idle || state == .stopped {
            let wasStopped = state == .stopped
            state = .acquiring
            if wasStopped {
                decision = makeDecision(at: now, kind: .resume, previous: target, reason: "cadence resumed after stop")
            }
        }

        if state == .acquiring {
            if sampleCount >= config.minSamplesForLock, window.count >= config.minSamplesForLock,
               let smoothed {
                let locked = Int(smoothed.rounded())
                let previous = target
                target = locked
                state = .locked
                pendingSince = nil
                decision = makeDecision(
                    at: now,
                    kind: .initialLock,
                    previous: previous,
                    reason: "locked initial cadence at \(locked) SPM after \(sampleCount) samples"
                )
            }
            return snapshot(at: now, decision: decision)
        }

        // state == .locked: hysteresis + sustained-change detection.
        guard let smoothedValue = smoothed, let currentTarget = target else {
            return snapshot(at: now, decision: decision)
        }
        let diff = smoothedValue - Double(currentTarget)
        if abs(diff) >= config.changeThresholdSpm {
            if let since = pendingSince {
                if now.timeIntervalSince(since) >= config.sustain {
                    let previous = currentTarget
                    target = Int(smoothedValue.rounded())
                    pendingSince = nil
                    decision = makeDecision(
                        at: now,
                        kind: .retarget,
                        previous: previous,
                        reason: String(
                            format: "sustained change: smoothed %.1f SPM vs target %d SPM for ≥%.0fs",
                            smoothedValue, previous, config.sustain
                        )
                    )
                }
            } else {
                pendingSince = now
            }
        } else {
            // Back inside the tolerance band — abandon any pending change.
            pendingSince = nil
        }

        return snapshot(at: now, decision: decision)
    }

    /// Advance wall time without a sample (drive from a UI timer).
    /// Detects the "runner stopped producing samples" case.
    @discardableResult
    public func tick(now: Date) -> CadenceEngineUpdate {
        if let last = lastSampleAt,
           state != .stopped, state != .idle,
           now.timeIntervalSince(last) >= config.stopTimeout {
            return handleStop(now: now, reason: "no samples for \(Int(config.stopTimeout))s")
        }
        return snapshot(at: now, decision: nil)
    }

    public func reset() {
        window.clear()
        ema = nil
        smoothed = nil
        target = nil
        state = .idle
        pendingSince = nil
        lastSampleAt = nil
        sampleCount = 0
        lastRaw = nil
    }

    private func handleStop(now: Date, reason: String) -> CadenceEngineUpdate {
        var decision: CadenceDecision?
        if state != .stopped, state != .idle {
            state = .stopped
            pendingSince = nil
            window.clear()
            ema = nil
            smoothed = nil
            sampleCount = 0
            // Keep `target` so music can hold tempo briefly; the orchestrator
            // decides whether to pause playback on stop.
            decision = makeDecision(at: now, kind: .stop, previous: target, reason: reason)
        }
        return snapshot(at: now, decision: decision)
    }

    private func makeDecision(
        at: Date, kind: CadenceDecision.Kind, previous: Int?, reason: String
    ) -> CadenceDecision {
        CadenceDecision(at: at, kind: kind, targetSpm: target, previousTargetSpm: previous, reason: reason)
    }

    private func snapshot(at: Date, decision: CadenceDecision?) -> CadenceEngineUpdate {
        var pending: (candidateSpm: Int, since: TimeInterval)?
        if let pendingSince, let smoothed {
            pending = (candidateSpm: Int(smoothed.rounded()), since: at.timeIntervalSince(pendingSince))
        }
        return CadenceEngineUpdate(
            at: at,
            rawSpm: lastRaw,
            smoothedSpm: smoothed,
            targetSpm: target,
            state: state,
            decision: decision,
            pending: pending
        )
    }
}
