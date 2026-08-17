import Foundation
import PacerKit

/// Timer-driven wrapper around PacerKit's SimulatedRunnerCore — a realistic
/// fake runner for the Simulator, demos, and algorithm tuning. Change the
/// simulated pace live from the diagnostics panel.
final class SimulatedCadenceProvider: CadenceProviding, @unchecked Sendable {
    let id: CadenceSource = .simulator
    let label = "Cadence Simulator"

    private let lock = NSLock()
    private var core: SimulatedRunnerCore
    private var timer: Timer?
    private var continuation: AsyncStream<CadenceSample>.Continuation?
    private var stream: AsyncStream<CadenceSample>?
    private let interval: TimeInterval

    init(initialSpm: Double = 154, interval: TimeInterval = 0.6) {
        self.core = SimulatedRunnerCore(initialSpm: initialSpm)
        self.interval = interval
    }

    var cadenceStream: AsyncStream<CadenceSample> {
        if let stream { return stream }
        let (newStream, continuation) = AsyncStream.makeStream(of: CadenceSample.self)
        self.stream = newStream
        self.continuation = continuation
        return newStream
    }

    /// Where the simulated runner is trying to be. 0 = stop running.
    var targetSpm: Double {
        get { lock.withLock { core.targetSpm } }
        set { lock.withLock { core.targetSpm = newValue } }
    }

    var currentSpm: Double {
        lock.withLock { core.currentSpm }
    }

    func jump(to spm: Double) {
        lock.withLock { core.jump(to: spm) }
    }

    func start() async throws {
        guard timer == nil else { return }
        _ = cadenceStream
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let spm = self.lock.withLock {
                self.core.step(dt: self.interval, unitRandom: { Double.random(in: 0..<1) })
            }
            self.continuation?.yield(
                CadenceSample(capturedAt: Date(), spm: (spm * 10).rounded() / 10, source: .simulator)
            )
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        continuation?.finish()
        continuation = nil
        stream = nil
    }
}
