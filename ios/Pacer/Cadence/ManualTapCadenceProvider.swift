import Foundation
import PacerKit

/// The user taps a big button once per step; PacerKit's TapCadenceCalculator
/// turns tap intervals into SPM. Demonstrates the whole pipeline on any
/// device with zero sensors.
final class ManualTapCadenceProvider: CadenceProviding, @unchecked Sendable {
    let id: CadenceSource = .tap
    let label = "Manual Tap"

    private let lock = NSLock()
    private var calculator = TapCadenceCalculator()
    private var timer: Timer?
    private var continuation: AsyncStream<CadenceSample>.Continuation?
    private var stream: AsyncStream<CadenceSample>?

    var cadenceStream: AsyncStream<CadenceSample> {
        if let stream { return stream }
        let (newStream, continuation) = AsyncStream.makeStream(of: CadenceSample.self)
        self.stream = newStream
        self.continuation = continuation
        return newStream
    }

    /// Called from the tap button.
    func registerTap() {
        let now = Date()
        let spm: Double? = lock.withLock {
            calculator.tap(at: now)
            return calculator.currentSpm(now: now)
        }
        if let spm {
            continuation?.yield(CadenceSample(capturedAt: now, spm: spm, source: .tap))
        }
    }

    func start() async throws {
        guard timer == nil else { return }
        _ = cadenceStream
        // Emit idle (zero) samples when tapping stops so the engine notices.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            let (idle, spm): (Bool, Double?) = self.lock.withLock {
                (self.calculator.isIdle(now: now), self.calculator.currentSpm(now: now))
            }
            if idle {
                self.continuation?.yield(CadenceSample(capturedAt: now, spm: 0, source: .tap))
            } else if let spm {
                self.continuation?.yield(CadenceSample(capturedAt: now, spm: spm, source: .tap))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lock.withLock { calculator.reset() }
        continuation?.finish()
        continuation = nil
        stream = nil
    }
}
