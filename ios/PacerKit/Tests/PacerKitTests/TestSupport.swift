import Foundation
@testable import PacerKit

/// Deterministic test harness shared across suites — mirrors the TypeScript
/// reference tests in /web/src/core so both implementations stay behaviorally
/// aligned.

let epoch = Date(timeIntervalSinceReferenceDate: 0)

func at(_ seconds: TimeInterval) -> Date {
    epoch.addingTimeInterval(seconds)
}

func makeSample(t: TimeInterval, spm: Double) -> CadenceSample {
    CadenceSample(capturedAt: at(t), spm: spm, source: .simulator)
}

/// Small deterministic PRNG (mulberry32) — identical to the TS test helper.
final class Mulberry32 {
    private var state: UInt32
    init(seed: UInt32) { state = seed }

    func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}

struct FeedResult {
    let updates: [CadenceEngineUpdate]
    var decisions: [CadenceEngineUpdate] { updates.filter { $0.decision != nil } }
}

@discardableResult
func feed(
    _ engine: CadenceEngine,
    _ series: [Double],
    startAt: TimeInterval = 0,
    interval: TimeInterval = 0.6
) -> FeedResult {
    var updates: [CadenceEngineUpdate] = []
    for (i, spm) in series.enumerated() {
        updates.append(engine.addSample(makeSample(t: startAt + Double(i) * interval, spm: spm)))
    }
    return FeedResult(updates: updates)
}

func constantSeries(_ spm: Double, _ count: Int) -> [Double] {
    Array(repeating: spm, count: count)
}

func noisySeries(_ spm: Double, _ count: Int, noise: Double, seed: UInt32 = 42) -> [Double] {
    let rng = Mulberry32(seed: seed)
    return (0..<count).map { _ in spm + (rng.next() * 2 - 1) * noise }
}

func testTrack(_ id: String, bpm: Double?) -> PacerTrack {
    PacerTrack(
        id: id,
        provider: .demo,
        providerTrackID: id,
        name: "Track \(id)",
        artist: "Test",
        durationMs: 180_000,
        bpm: bpm
    )
}
