import Foundation
import Testing
@testable import PacerKit

@Suite("CadenceEngine")
struct CadenceEngineTests {
    @Test("locks an initial target on stable 160 SPM")
    func initialLock() {
        let engine = CadenceEngine()
        let result = feed(engine, constantSeries(160, 20))

        #expect(result.decisions.count == 1)
        #expect(result.decisions.first?.decision?.kind == .initialLock)
        #expect(engine.currentTarget == 160)
        #expect(result.updates.last?.state == .locked)
    }

    @Test("holds a steady target on noisy 160 SPM (±3 SPM jitter)")
    func noisyStable() throws {
        let engine = CadenceEngine()
        let result = feed(engine, noisySeries(160, 60, noise: 3))

        // Only the initial lock — noise must not cause retargets.
        #expect(result.decisions.count == 1)
        #expect(result.decisions.first?.decision?.kind == .initialLock)
        let target = try #require(engine.currentTarget)
        #expect(target >= 158 && target <= 162)
    }

    @Test("retargets on a sustained 160 → 170 transition within 15 s")
    func sustainedTransition() throws {
        let engine = CadenceEngine()
        feed(engine, noisySeries(160, 30, noise: 2))
        #expect(engine.currentTarget != nil)

        let t0 = 30.0 * 0.6
        var retargetAt: Date?
        for (i, spm) in noisySeries(170, 40, noise: 2, seed: 7).enumerated() {
            let update = engine.addSample(makeSample(t: t0 + Double(i) * 0.6, spm: spm))
            if update.decision?.kind == .retarget, retargetAt == nil {
                retargetAt = update.at
            }
        }

        let when = try #require(retargetAt)
        let elapsed = when.timeIntervalSince(at(t0))
        #expect(elapsed <= 15)
        #expect(elapsed >= 4) // must not be instant
        let target = try #require(engine.currentTarget)
        #expect(target >= 167 && target <= 172)
    }

    @Test("ignores a brief spike")
    func briefSpike() {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 30))

        // 3-second spike to 185, then back — shorter than the sustain window.
        let t0 = 30.0 * 0.6
        let spike = constantSeries(185, 5) + constantSeries(160, 30)
        let result = feed(engine, spike, startAt: t0)

        let retargets = result.decisions.filter { $0.decision?.kind == .retarget }
        #expect(retargets.isEmpty)
        #expect(engine.currentTarget == 160)
    }

    @Test("follows gradual acceleration 150 → 175 with a few discrete retargets")
    func gradualAcceleration() throws {
        let engine = CadenceEngine()
        // Accelerate 150→175 over ~2 minutes (0.125 SPM per 600 ms sample).
        let series = (0..<200).map { 150 + Double($0) * 0.125 }
        let result = feed(engine, series)

        let retargets = result.decisions.filter { $0.decision?.kind == .retarget }
        #expect(retargets.count >= 2) // follows the trend…
        #expect(retargets.count <= 8) // …without thrashing
        let target = try #require(engine.currentTarget)
        #expect(target >= 168)
    }

    @Test("follows gradual deceleration 175 → 155")
    func gradualDeceleration() throws {
        let engine = CadenceEngine()
        let series = (0..<160).map { 175 - Double($0) * 0.125 }
        feed(engine, series)
        let target = try #require(engine.currentTarget)
        #expect(target <= 160 && target >= 152)
    }

    @Test("detects stopping via zero-cadence samples")
    func stopViaZero() {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 20))
        let update = engine.addSample(makeSample(t: 20 * 0.6, spm: 0))
        #expect(update.state == .stopped)
        #expect(update.decision?.kind == .stop)
    }

    @Test("detects stopping via sample silence (tick timeout)")
    func stopViaSilence() {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 20))
        let lastT = 19.0 * 0.6
        let update = engine.tick(now: at(lastT + 5))
        #expect(update.state == .stopped)
        #expect(update.decision?.kind == .stop)
    }

    @Test("resumes cleanly after a stop and re-locks")
    func resumeAfterStop() throws {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 20))
        engine.addSample(makeSample(t: 20 * 0.6, spm: 0))
        #expect(engine.currentState == .stopped)

        let result = feed(engine, constantSeries(172, 20), startAt: 60)
        let kinds = result.decisions.compactMap { $0.decision?.kind }
        #expect(kinds.contains(.resume))
        #expect(kinds.contains(.initialLock))
        #expect(engine.currentState == .locked)
        let target = try #require(engine.currentTarget)
        #expect(target >= 170)
    }

    @Test("discards physically implausible samples")
    func implausibleSamples() {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 20))
        engine.addSample(makeSample(t: 20 * 0.6, spm: 900)) // sensor glitch
        engine.addSample(makeSample(t: 21 * 0.6, spm: 15)) // sub-walking glitch (>0, <min)
        #expect(engine.currentTarget == 160)
        #expect(engine.currentState == .locked)
    }

    @Test("does not retarget for a small drift below the threshold")
    func smallDrift() {
        let engine = CadenceEngine()
        feed(engine, constantSeries(160, 20))
        let result = feed(engine, constantSeries(162, 40), startAt: 20 * 0.6)
        let retargets = result.decisions.filter { $0.decision?.kind == .retarget }
        #expect(retargets.isEmpty)
        #expect(engine.currentTarget == 160)
    }

    @Test("respects a custom sustain window")
    func customSustain() throws {
        var config = CadenceEngineConfig()
        config.sustain = 2
        let engine = CadenceEngine(config: config)
        feed(engine, constantSeries(160, 20))

        var retargetAt: Date?
        let t0 = 20.0 * 0.6
        for (i, spm) in constantSeries(170, 20).enumerated() {
            let u = engine.addSample(makeSample(t: t0 + Double(i) * 0.6, spm: spm))
            if u.decision?.kind == .retarget, retargetAt == nil { retargetAt = u.at }
        }
        let when = try #require(retargetAt)
        #expect(when.timeIntervalSince(at(t0)) <= 9)
    }
}
