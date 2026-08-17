import Foundation
import Testing
@testable import PacerKit

@Suite("SessionRecorder")
struct SessionRecorderTests {
    @Test("computes average and peak cadence from moving samples only")
    func averageAndPeak() {
        var rec = SessionRecorder(startedAt: at(0), mode: .followMe, cadenceSource: .simulator)
        rec.recordSample(t: at(1), raw: 150, smoothed: 150)
        rec.recordSample(t: at(2), raw: 160, smoothed: 158)
        rec.recordSample(t: at(3), raw: 170, smoothed: 165)
        rec.recordSample(t: at(4), raw: 0, smoothed: nil) // stopped — excluded

        let summary = rec.summary(endedAt: at(5))
        #expect(summary.averageCadence == 160)
        #expect(summary.peakCadence == 170)
    }

    @Test("tracks on-beat percentage against the active follow-me target")
    func onBeatFollowMe() {
        var rec = SessionRecorder(startedAt: at(0), mode: .followMe, cadenceSource: .simulator)
        rec.recordDecision(
            CadenceDecision(at: at(1), kind: .initialLock, targetSpm: 160, previousTargetSpm: nil, reason: "lock")
        )
        rec.recordSample(t: at(2), raw: 160, smoothed: 160) // on beat
        rec.recordSample(t: at(3), raw: 162, smoothed: 161) // on beat (within 5)
        rec.recordSample(t: at(4), raw: 172, smoothed: 171) // off beat
        rec.recordSample(t: at(5), raw: 174, smoothed: 173) // off beat

        let summary = rec.summary(endedAt: at(6))
        #expect(summary.onBeatPercent == 50)
    }

    @Test("uses the user target for pace-me on-beat tracking")
    func onBeatPaceMe() {
        var rec = SessionRecorder(
            startedAt: at(0), mode: .paceMe, requestedTargetSpm: 170, cadenceSource: .simulator
        )
        rec.recordSample(t: at(1), raw: 168, smoothed: 168) // on beat vs 170
        rec.recordSample(t: at(2), raw: 150, smoothed: 151) // off beat

        let summary = rec.summary(endedAt: at(3))
        #expect(summary.onBeatPercent == 50)
        #expect(summary.requestedTargetSpm == 170)
    }

    @Test("records follow-me target changes but not pace-me engine chatter")
    func targetChanges() {
        var follow = SessionRecorder(startedAt: at(0), mode: .followMe, cadenceSource: .simulator)
        follow.recordDecision(
            CadenceDecision(at: at(1), kind: .initialLock, targetSpm: 158, previousTargetSpm: nil, reason: "lock")
        )
        follow.recordDecision(
            CadenceDecision(at: at(30), kind: .retarget, targetSpm: 168, previousTargetSpm: 158, reason: "sustained")
        )
        #expect(follow.summary(endedAt: at(60)).targetChanges.count == 2)

        var pace = SessionRecorder(startedAt: at(0), mode: .paceMe, requestedTargetSpm: 170, cadenceSource: .simulator)
        pace.recordDecision(
            CadenceDecision(at: at(1), kind: .initialLock, targetSpm: 158, previousTargetSpm: nil, reason: "lock")
        )
        pace.recordUserTargetChange(t: at(20), targetSpm: 175)
        let changes = pace.summary(endedAt: at(60)).targetChanges
        #expect(changes.count == 1)
        #expect(changes.first?.targetSpm == 175)
    }

    @Test("downsamples long cadence traces for persistence")
    func downsampling() {
        var rec = SessionRecorder(startedAt: at(0), mode: .followMe, cadenceSource: .simulator)
        for i in 0..<5000 {
            rec.recordSample(t: at(Double(i)), raw: 160, smoothed: 160)
        }
        let summary = rec.summary(endedAt: at(5000))
        #expect(summary.samples.count == 600)
        #expect(rec.downsampled(maxPoints: 100).count == 100)
    }

    @Test("records songs played")
    func songs() {
        var rec = SessionRecorder(startedAt: at(0), mode: .followMe, cadenceSource: .simulator)
        rec.recordSongStart(t: at(1), trackID: "demo-1", name: "Warmup Groove", artist: "Pacer Demo")
        rec.recordSongStart(t: at(200), trackID: "demo-4", name: "Tempo Runner", artist: "Pacer Demo")
        let summary = rec.summary(endedAt: at(300))
        #expect(summary.songsPlayed.map(\.trackID) == ["demo-1", "demo-4"])
    }
}
