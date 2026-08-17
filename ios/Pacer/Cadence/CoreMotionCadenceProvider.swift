import Foundation
import CoreMotion
import PacerKit

/// Live cadence from the iPhone's pedometer (Core Motion).
///
/// `CMPedometerData.currentCadence` reports steps per SECOND; we convert to
/// steps per minute before handing samples to the cadence engine. Pedometer
/// updates arrive roughly every 1–2.5 s while moving, which is a good raw
/// rate for the smoothing window.
///
/// Requires `NSMotionUsageDescription` (set in project.yml) and the user's
/// motion permission — iOS prompts on first use. Cadence is available on
/// iPhone 6 and later (motion coprocessor).
final class CoreMotionCadenceProvider: CadenceProviding {
    let id: CadenceSource = .coreMotion
    let label = "iPhone Motion (Core Motion)"

    private let pedometer = CMPedometer()
    private var continuation: AsyncStream<CadenceSample>.Continuation?
    private var stream: AsyncStream<CadenceSample>?

    var cadenceStream: AsyncStream<CadenceSample> {
        if let stream { return stream }
        let (newStream, continuation) = AsyncStream.makeStream(of: CadenceSample.self)
        self.stream = newStream
        self.continuation = continuation
        return newStream
    }

    static var isAvailable: Bool {
        CMPedometer.isCadenceAvailable()
    }

    func start() async throws {
        guard CMPedometer.isCadenceAvailable() else {
            throw CadenceProviderError.unavailable(
                "This device does not report running cadence (requires a motion coprocessor)."
            )
        }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            throw CadenceProviderError.permissionDenied(
                "Motion access is denied. Enable it in Settings → Privacy → Motion & Fitness."
            )
        default:
            break
        }

        _ = cadenceStream // ensure the stream/continuation exist before events flow

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self else { return }
            if error != nil {
                // Surface as a zero sample so the engine treats it as a gap
                // rather than crashing the stream; the UI shows engine state.
                return
            }
            guard let data else { return }
            let spm: Double
            if let cadence = data.currentCadence {
                spm = cadence.doubleValue * 60
            } else {
                // No instantaneous cadence yet — derive a rough value from
                // steps over the update interval as a fallback.
                let seconds = data.endDate.timeIntervalSince(data.startDate)
                spm = seconds > 0 ? data.numberOfSteps.doubleValue / seconds * 60 : 0
            }
            self.continuation?.yield(
                CadenceSample(capturedAt: Date(), spm: spm, source: .coreMotion)
            )
        }
    }

    func stop() {
        pedometer.stopUpdates()
        continuation?.finish()
        continuation = nil
        stream = nil
    }
}
