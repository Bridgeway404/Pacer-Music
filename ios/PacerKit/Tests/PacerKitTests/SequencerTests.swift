import Foundation
import Testing
@testable import PacerKit

@Suite("Sequencer")
struct SequencerTests {
    let library: [PacerTrack] = [
        testTrack("t150", bpm: 150),
        testTrack("t160", bpm: 160),
        testTrack("t170", bpm: 170),
        testTrack("t180", bpm: 180),
        testTrack("t85", bpm: 85), // half-time 170
        testTrack("t128", bpm: 128),
        testTrack("tNull", bpm: nil),
    ]

    @Test("ranks the closest BPM first for the target cadence")
    func closestFirst() {
        let ranked = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 160))
        #expect(ranked.first?.track.id == "t160")
    }

    @Test("treats an 85 BPM track as strong for a 170 SPM target (2x)")
    func halfTimeStrong() throws {
        let ranked = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 170))
        let ids = ranked.map(\.track.id)
        #expect(ids[0] == "t170")
        #expect(ids[1] == "t85")
        #expect(ranked[1].match?.multiplier == 2)
    }

    @Test("excludes the current track from the ranking")
    func excludesCurrent() {
        let ranked = Sequencer.rankTracks(
            library,
            context: SequencerContext(targetSpm: 170, currentTrack: testTrack("t170", bpm: 170))
        )
        #expect(!ranked.contains { $0.track.id == "t170" })
    }

    @Test("penalizes recently played tracks")
    func recentlyPlayedPenalty() throws {
        let fresh = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 160))
        let afterPlay = Sequencer.rankTracks(
            library,
            context: SequencerContext(targetSpm: 160, recentlyPlayedIDs: ["t160"])
        )
        #expect(fresh.first?.track.id == "t160")
        #expect(afterPlay.first?.track.id != "t160")
        let t160 = try #require(afterPlay.first { $0.track.id == "t160" })
        #expect(t160.reasons.contains("played recently"))
    }

    @Test("penalizes skipped tracks harder than recently played ones")
    func skippedPenalty() throws {
        let ranked = Sequencer.rankTracks(
            library,
            context: SequencerContext(targetSpm: 160, recentlyPlayedIDs: ["t150"], skippedIDs: ["t160"])
        )
        let skipped = try #require(ranked.first { $0.track.id == "t160" })
        let recent = try #require(ranked.first { $0.track.id == "t150" })
        // t160 is a perfect BPM match, t150 is 10 off — yet the skip penalty
        // should drag t160 down at least near t150's level.
        #expect(skipped.score < recent.score + 0.15)
        #expect(skipped.reasons.contains("skipped this session"))
    }

    @Test("avoids jarring transitions from the current track")
    func transitionPenalty() throws {
        // Target 170; current track perceived at 170 — the 180 track costs a
        // transition penalty relative to 85 (perceived 170).
        let ranked = Sequencer.rankTracks(
            library,
            context: SequencerContext(targetSpm: 170, currentTrack: testTrack("cur", bpm: 170))
        )
        let t85 = try #require(ranked.first { $0.track.id == "t85" })
        let t180 = try #require(ranked.first { $0.track.id == "t180" })
        #expect(t85.score > t180.score)
        #expect(t180.reasons.joined(separator: " ").contains("transition jump"))
    }

    @Test("keeps unknown-BPM tracks in the pool but ranks them low")
    func unknownBpmLow() throws {
        let ranked = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 160))
        let unknownIndex = try #require(ranked.firstIndex { $0.track.id == "tNull" })
        #expect(ranked[unknownIndex].match == nil)
        #expect(unknownIndex > 2)
    }

    @Test("adapts the ordering when the target cadence changes")
    func adaptsToTarget() {
        let at150 = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 150))
        let at180 = Sequencer.rankTracks(library, context: SequencerContext(targetSpm: 180))
        #expect(at150.first?.track.id == "t150")
        #expect(at180.first?.track.id == "t180")
    }

    @Test("buildQueue returns at most the requested length")
    func queueLength() {
        let queue = Sequencer.buildQueue(library, context: SequencerContext(targetSpm: 160), length: 3)
        #expect(queue.count == 3)
    }

    @Test("pickNextTrack picks the best available next track")
    func picksNext() throws {
        let next = try #require(
            Sequencer.pickNextTrack(
                library,
                context: SequencerContext(
                    targetSpm: 170,
                    currentTrack: testTrack("t170", bpm: 170),
                    recentlyPlayedIDs: ["t85"]
                )
            )
        )
        #expect(["t85", "t180", "t160"].contains(next.track.id))
        #expect(next.track.id != "t170")
    }

    @Test("pickNextTrack returns nil when only the current track exists")
    func emptyPool() {
        let only = [testTrack("t1", bpm: 160)]
        let next = Sequencer.pickNextTrack(only, context: SequencerContext(targetSpm: 160, currentTrack: only[0]))
        #expect(next == nil)
    }
}
