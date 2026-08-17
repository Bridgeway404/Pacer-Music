import Foundation
import PacerKit

/// Anything that can produce live cadence samples: Core Motion, the
/// simulator, or manual tapping. Providers push raw samples; all
/// smoothing/decision logic lives in PacerKit's CadenceEngine.
protocol CadenceProviding: AnyObject {
    var id: CadenceSource { get }
    var label: String { get }
    /// Stream of raw samples. A new stream is created per start().
    var cadenceStream: AsyncStream<CadenceSample> { get }
    func start() async throws
    func stop()
}

enum CadenceProviderError: LocalizedError {
    case unavailable(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): why
        case .permissionDenied(let why): why
        }
    }
}
