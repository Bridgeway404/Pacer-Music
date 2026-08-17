import Foundation

/// Playlist intelligence: given a target cadence and a track pool, rank
/// tracks by how well they'd serve the runner *right now* and build an
/// adaptive "Up Next" queue.
public struct SequencerWeights: Sendable {
    /// Weight of the BPM compatibility score.
    public var bpmMatch: Double = 1
    /// Max penalty for a track played recently (scaled by recency).
    public var recentlyPlayed: Double = 0.45
    /// Penalty for a track the user skipped this session.
    public var skipped: Double = 0.75
    /// Max penalty for a jarring perceived-BPM jump from the current track.
    public var transition: Double = 0.2
    /// Perceived-BPM jump (SPM) at which the transition penalty saturates.
    public var transitionSaturationSpm: Double = 30
    /// Flat score for tracks with unknown BPM (kept, but ranked low).
    public var unknownBpmScore: Double = 0.15

    public init() {}
}

public struct SequencerContext: Sendable {
    public var targetSpm: Double
    /// Track currently playing (excluded from ranking, used for transition cost).
    public var currentTrack: PacerTrack?
    /// Track ids played recently, most recent last.
    public var recentlyPlayedIDs: [String]
    /// Track ids the user skipped this session.
    public var skippedIDs: [String]
    public var bpmPreferences: BpmMatchPreferences
    public var weights: SequencerWeights

    public init(
        targetSpm: Double,
        currentTrack: PacerTrack? = nil,
        recentlyPlayedIDs: [String] = [],
        skippedIDs: [String] = [],
        bpmPreferences: BpmMatchPreferences = BpmMatchPreferences(),
        weights: SequencerWeights = SequencerWeights()
    ) {
        self.targetSpm = targetSpm
        self.currentTrack = currentTrack
        self.recentlyPlayedIDs = recentlyPlayedIDs
        self.skippedIDs = skippedIDs
        self.bpmPreferences = bpmPreferences
        self.weights = weights
    }
}

public struct RankedTrack: Sendable, Identifiable {
    public let track: PacerTrack
    public let score: Double
    public let match: BpmMatch?
    public let reasons: [String]

    public var id: String { track.id }
}

public enum Sequencer {
    /// Rank every candidate track for the given context, best first.
    public static func rankTracks(_ tracks: [PacerTrack], context: SequencerContext) -> [RankedTrack] {
        let weights = context.weights
        let recent = context.recentlyPlayedIDs
        let skipped = Set(context.skippedIDs)
        let currentMatch = context.currentTrack.flatMap {
            BpmMatcher.match(cadenceSpm: context.targetSpm, trackBpm: $0.bpm, preferences: context.bpmPreferences)
        }

        var ranked: [RankedTrack] = []
        for track in tracks {
            if let current = context.currentTrack, track.id == current.id { continue }

            var reasons: [String] = []
            let match = BpmMatcher.match(
                cadenceSpm: context.targetSpm, trackBpm: track.bpm, preferences: context.bpmPreferences
            )
            var score: Double

            if let match {
                score = match.score * weights.bpmMatch
                reasons.append(
                    String(
                        format: "%.0f perceived BPM (%gx) vs %.0f SPM target",
                        match.perceivedBpm, match.multiplier, context.targetSpm
                    )
                )

                // Avoid whiplash transitions between consecutive tracks.
                if let currentMatch {
                    let jump = abs(match.perceivedBpm - currentMatch.perceivedBpm)
                    let penalty = min(1, jump / weights.transitionSaturationSpm) * weights.transition
                    if penalty > 0.01 {
                        score -= penalty
                        reasons.append(String(format: "transition jump %.0f BPM from current track", jump))
                    }
                }
            } else {
                score = weights.unknownBpmScore
                reasons.append("BPM unknown")
            }

            if let recentIndex = recent.lastIndex(of: track.id) {
                // Most recently played ⇒ full penalty; decays for older plays.
                let recency = Double(recentIndex + 1) / Double(recent.count)
                score -= weights.recentlyPlayed * recency
                reasons.append("played recently")
            }

            if skipped.contains(track.id) {
                score -= weights.skipped
                reasons.append("skipped this session")
            }

            ranked.append(RankedTrack(track: track, score: score, match: match, reasons: reasons))
        }

        return ranked.sorted { $0.score > $1.score }
    }

    /// Build the visible "Up Next" queue (top N ranked tracks).
    public static func buildQueue(
        _ tracks: [PacerTrack], context: SequencerContext, length: Int = 5
    ) -> [RankedTrack] {
        Array(rankTracks(tracks, context: context).prefix(length))
    }

    /// Pick the next track to play (or nil if nothing is available).
    public static func pickNextTrack(_ tracks: [PacerTrack], context: SequencerContext) -> RankedTrack? {
        rankTracks(tracks, context: context).first
    }
}
