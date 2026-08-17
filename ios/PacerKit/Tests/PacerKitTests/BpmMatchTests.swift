import Foundation
import Testing
@testable import PacerKit

@Suite("BpmMatcher")
struct BpmMatchTests {
    @Test("returns a perfect 1x match when BPM equals cadence")
    func perfectMatch() throws {
        let m = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 170))
        #expect(m.multiplier == 1)
        #expect(m.difference == 0)
        #expect(m.score == 1)
        #expect(m.isGoodMatch)
        #expect(m.perceivedBpm == 170)
    }

    @Test("matches half-time: 85 BPM track for a 170 SPM runner via 2x")
    func halfTime() throws {
        let m = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 85))
        #expect(m.multiplier == 2)
        #expect(m.perceivedBpm == 170)
        #expect(m.difference == 0)
        #expect(m.isGoodMatch)
    }

    @Test("matches double-time: 340 BPM material perceived at 0.5x")
    func doubleTime() throws {
        let m = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 340))
        #expect(m.multiplier == 0.5)
        #expect(m.perceivedBpm == 170)
        #expect(m.isGoodMatch)
    }

    @Test("slightly prefers a direct 1x match over an equally-close 2x match")
    func prefersDirect() throws {
        let direct = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 168))
        let half = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 85.99))
        #expect(direct.score > half.score)
    }

    @Test("reports a poor match for musically unrelated tempi")
    func poorMatch() throws {
        let m = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 140))
        #expect(!m.isGoodMatch)
        #expect(m.score < 0.2)
    }

    @Test("respects a custom tolerance")
    func customTolerance() throws {
        var strictPrefs = BpmMatchPreferences()
        strictPrefs.toleranceSpm = 3
        var loosePrefs = BpmMatchPreferences()
        loosePrefs.toleranceSpm = 8
        let strict = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 165, preferences: strictPrefs))
        let loose = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 165, preferences: loosePrefs))
        #expect(!strict.isGoodMatch)
        #expect(loose.isGoodMatch)
    }

    @Test("computes recommended target tempo and playback rate for tempo-shifting")
    func recommendedTempo() throws {
        // 150 BPM demo track, runner at 165 SPM, 1x match:
        // play the track at 165 BPM ⇒ rate 1.1.
        let m = try #require(BpmMatcher.match(cadenceSpm: 165, trackBpm: 150))
        #expect(m.multiplier == 1)
        #expect(abs(m.recommendedTargetTempo - 165) < 0.001)
        #expect(abs(m.recommendedPlaybackRate - 1.1) < 0.001)
    }

    @Test("computes recommended tempo through a 2x multiplier")
    func recommendedTempoHalfTime() throws {
        // 82 BPM track, runner at 170 ⇒ perceived 164 via 2x; to sync
        // perfectly the track itself should play at 85 BPM ⇒ rate 85/82.
        let m = try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: 82))
        #expect(m.multiplier == 2)
        #expect(abs(m.recommendedTargetTempo - 85) < 0.001)
        #expect(abs(m.recommendedPlaybackRate - 85.0 / 82.0) < 0.001)
    }

    @Test("returns nil for unknown or invalid inputs")
    func invalidInputs() {
        #expect(BpmMatcher.match(cadenceSpm: 170, trackBpm: nil) == nil)
        #expect(BpmMatcher.match(cadenceSpm: 170, trackBpm: 0) == nil)
        #expect(BpmMatcher.match(cadenceSpm: 170, trackBpm: -10) == nil)
        #expect(BpmMatcher.match(cadenceSpm: 0, trackBpm: 150) == nil)
        #expect(BpmMatcher.match(cadenceSpm: .nan, trackBpm: 150) == nil)
    }

    @Test("score decays monotonically with distance")
    func monotonicDecay() throws {
        let scores = try [170.0, 172, 175, 180, 190].map {
            try #require(BpmMatcher.match(cadenceSpm: 170, trackBpm: $0)).score
        }
        for i in 1..<scores.count {
            #expect(scores[i] <= scores[i - 1])
        }
    }

    @Test("supports custom multipliers (e.g. 1.5x triplet feel)")
    func customMultipliers() throws {
        var prefs = BpmMatchPreferences()
        prefs.multipliers = [0.5, 1, 1.5, 2]
        let m = try #require(BpmMatcher.match(cadenceSpm: 180, trackBpm: 120, preferences: prefs))
        #expect(m.multiplier == 1.5)
        #expect(m.perceivedBpm == 180)
    }
}
