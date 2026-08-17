import Foundation
import Testing
@testable import PacerKit

@Suite("Filters")
struct FiltersTests {
    @Test("median handles odd and even lengths")
    func medianBasics() {
        #expect(Filters.median([3, 1, 2]) == 2)
        #expect(Filters.median([4, 1, 3, 2]) == 2.5)
        #expect(Filters.median([]) == nil)
    }

    @Test("median is robust to a single outlier")
    func medianOutlier() {
        #expect(Filters.median([160, 161, 159, 400, 160]) == 160)
    }

    @Test("emaStep initializes and converges")
    func ema() {
        #expect(Filters.emaStep(previous: nil, next: 160, alpha: 0.3) == 160)
        #expect(abs(Filters.emaStep(previous: 160, next: 170, alpha: 0.3) - 163) < 0.001)
        var v: Double? = 150
        for _ in 0..<50 { v = Filters.emaStep(previous: v, next: 170, alpha: 0.3) }
        #expect(v! > 169.5)
    }

    @Test("rolling window evicts values outside the time window")
    func rollingWindowEvicts() {
        var w = RollingWindow(window: 5)
        w.push(t: at(0), value: 1)
        w.push(t: at(2), value: 2)
        w.push(t: at(6), value: 3) // evicts t=0
        #expect(w.values == [2, 3])
        #expect(w.count == 2)
    }

    @Test("rolling window returns the last N values")
    func rollingWindowLastN() {
        var w = RollingWindow(window: 60)
        for (i, v) in [1.0, 2, 3, 4, 5].enumerated() { w.push(t: at(Double(i)), value: v) }
        #expect(w.lastValues(3) == [3, 4, 5])
        #expect(w.lastValues(10) == [1, 2, 3, 4, 5])
    }
}

@Suite("TapCadenceCalculator")
struct TapCadenceTests {
    @Test("derives SPM from evenly spaced taps (170 SPM)")
    func evenTaps() throws {
        var calc = TapCadenceCalculator()
        let interval = 60.0 / 170.0
        for i in 0..<8 { calc.tap(at: at(Double(i) * interval)) }
        let spm = try #require(calc.currentSpm(now: at(7 * interval)))
        #expect(abs(spm - 170) < 1)
    }

    @Test("handles steps-per-tap scaling (tap every other footfall)")
    func stepsPerTap() throws {
        var calc = TapCadenceCalculator(stepsPerTap: 2)
        let interval = (60.0 / 170.0) * 2
        for i in 0..<8 { calc.tap(at: at(Double(i) * interval)) }
        let spm = try #require(calc.currentSpm(now: at(7 * interval)))
        #expect(abs(spm - 170) < 1)
    }

    @Test("median interval keeps one hesitation from skewing the estimate")
    func hesitation() throws {
        var calc = TapCadenceCalculator()
        let interval = 60.0 / 160.0
        var t = 0.0
        for _ in 0..<6 {
            calc.tap(at: at(t))
            t += interval
        }
        calc.tap(at: at(t + 0.9)) // one long hesitation
        let spm = try #require(calc.currentSpm(now: at(t + 0.9)))
        #expect(spm > 150)
    }

    @Test("returns nil with fewer than 2 taps")
    func tooFewTaps() {
        var calc = TapCadenceCalculator()
        #expect(calc.currentSpm(now: at(0)) == nil)
        calc.tap(at: at(0))
        #expect(calc.currentSpm(now: at(0)) == nil)
    }

    @Test("reports idle after the timeout")
    func idle() {
        var calc = TapCadenceCalculator()
        #expect(calc.isIdle(now: at(0)))
        calc.tap(at: at(0))
        #expect(!calc.isIdle(now: at(1)))
        #expect(calc.isIdle(now: at(4)))
    }
}

@Suite("SimulatedRunnerCore")
struct SimulatedRunnerTests {
    @Test("ramps gradually toward a new target")
    func ramps() {
        var core = SimulatedRunnerCore(initialSpm: 154, rampSpmPerSecond: 2.5, noiseSpm: 0)
        core.targetSpm = 170
        var seconds = 0.0
        while core.currentSpm < 169.9, seconds < 60 {
            _ = core.step(dt: 0.6, unitRandom: { 0.5 })
            seconds += 0.6
        }
        // 16 SPM at 2.5 SPM/s ≈ 6.4 s
        #expect(seconds > 5 && seconds < 10)
    }

    @Test("adds bounded noise around the current cadence")
    func noise() {
        var core = SimulatedRunnerCore(initialSpm: 160, rampSpmPerSecond: 2.5, noiseSpm: 2)
        let rng = Mulberry32(seed: 3)
        for _ in 0..<100 {
            let v = core.step(dt: 0.6, unitRandom: { rng.next() })
            #expect(abs(v - 160) < 4.5)
        }
    }

    @Test("winds down to zero when target is zero")
    func stops() {
        var core = SimulatedRunnerCore(initialSpm: 160, rampSpmPerSecond: 50, noiseSpm: 2)
        core.targetSpm = 0
        var last = 999.0
        for _ in 0..<20 { last = core.step(dt: 0.6, unitRandom: { 0.5 }) }
        #expect(last == 0)
        #expect(core.currentSpm == 0)
    }
}
