import Foundation

/// Pure signal-processing helpers used by the cadence engine.
public enum Filters {
    /// Median of a collection. Returns nil for empty input.
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Arithmetic mean. Returns nil for empty input.
    public static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Exponential moving average step.
    /// `alpha` in (0, 1]: higher = more responsive, lower = smoother.
    public static func emaStep(previous: Double?, next: Double, alpha: Double) -> Double {
        guard let previous, previous.isFinite else { return next }
        return previous + alpha * (next - previous)
    }
}

/// Fixed-duration rolling window of timestamped values.
/// Values older than `window` relative to the newest entry are evicted.
public struct RollingWindow: Sendable {
    public struct Entry: Sendable, Equatable {
        public let t: Date
        public let value: Double
    }

    private(set) var buffer: [Entry] = []
    public let window: TimeInterval

    public init(window: TimeInterval) {
        self.window = window
    }

    public mutating func push(t: Date, value: Double) {
        buffer.append(Entry(t: t, value: value))
        evict(now: t)
    }

    /// Drop entries older than the window relative to `now`.
    public mutating func evict(now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        buffer.removeAll { $0.t < cutoff }
    }

    public var values: [Double] { buffer.map(\.value) }

    /// The most recent `n` values (fewer if not available).
    public func lastValues(_ n: Int) -> [Double] {
        buffer.suffix(n).map(\.value)
    }

    public var count: Int { buffer.count }

    public var newestTimestamp: Date? { buffer.last?.t }

    public mutating func clear() {
        buffer.removeAll()
    }
}
