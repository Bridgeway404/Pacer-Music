import Foundation
import PacerKit

/// Fully offline music source backed by the bundled, procedurally generated
/// audio loops (see scripts/generate-demo-audio.mjs — synthesized drums and
/// bass authored by this project, so Pacer owns the recordings outright and
/// may legally tempo-shift them). Each track's BPM is exact because we
/// synthesized it.
///
/// Playback goes through DemoTempoEngine (AVAudioEngine +
/// AVAudioUnitTimePitch), which is what actually proves the "same song
/// speeds up with your cadence" concept.
final class DemoMusicProvider: MusicProviding {
    let id: MusicProviderID = .demo
    let label = "Demo Mode"
    let capabilities = MusicProviderCapabilities(
        bpmMetadata: true,
        playbackControl: true,
        tempoShift: true,
        limitations: [
            "Synthesized demo audio only — showcases the tempo engine, not your library."
        ]
    )

    static let demoTracks: [PacerTrack] = [
        PacerTrack(
            id: "demo-82", provider: .demo, providerTrackID: "demo-82",
            name: "Half-Time Roller", artist: "Pacer Demo", bpm: 82, audioResource: "demo-82"
        ),
        PacerTrack(
            id: "demo-120", provider: .demo, providerTrackID: "demo-120",
            name: "Warmup Groove", artist: "Pacer Demo", bpm: 120, audioResource: "demo-120"
        ),
        PacerTrack(
            id: "demo-140", provider: .demo, providerTrackID: "demo-140",
            name: "Steady State", artist: "Pacer Demo", bpm: 140, audioResource: "demo-140"
        ),
        PacerTrack(
            id: "demo-150", provider: .demo, providerTrackID: "demo-150",
            name: "Cruise Control", artist: "Pacer Demo", bpm: 150, audioResource: "demo-150"
        ),
        PacerTrack(
            id: "demo-160", provider: .demo, providerTrackID: "demo-160",
            name: "Tempo Runner", artist: "Pacer Demo", bpm: 160, audioResource: "demo-160"
        ),
        PacerTrack(
            id: "demo-170", provider: .demo, providerTrackID: "demo-170",
            name: "Negative Split", artist: "Pacer Demo", bpm: 170, audioResource: "demo-170"
        ),
        PacerTrack(
            id: "demo-180", provider: .demo, providerTrackID: "demo-180",
            name: "Kick Finish", artist: "Pacer Demo", bpm: 180, audioResource: "demo-180"
        ),
    ]

    private let tempoEngine: DemoTempoEngine
    private(set) var currentTrack: PacerTrack?

    init(tempoEngine: DemoTempoEngine) {
        self.tempoEngine = tempoEngine
    }

    var isAuthorized: Bool { true }

    func authorize() async throws {}

    func playlists() async throws -> [PacerPlaylist] {
        [
            PacerPlaylist(
                id: "demo-playlist",
                provider: .demo,
                providerPlaylistID: "demo-playlist",
                name: "Pacer Demo Mix",
                tracks: Self.demoTracks
            )
        ]
    }

    func tracks(inPlaylist playlistID: String) async throws -> [PacerTrack] {
        Self.demoTracks
    }

    func play(track: PacerTrack) async throws {
        guard let resource = track.audioResource else {
            throw MusicProviderError.notFound("Demo track has no audio resource")
        }
        try tempoEngine.load(resourceName: resource, sourceBpm: track.bpm ?? 120)
        try tempoEngine.play()
        currentTrack = track
    }

    func pause() async {
        tempoEngine.pause()
    }

    func resume() async throws {
        try tempoEngine.play()
    }

    func skipToNext() async throws {
        // The coordinator picks the next track via the sequencer and calls
        // play(track:) — the demo provider has no independent queue.
    }

    func stopPlayback() async {
        tempoEngine.stop()
        currentTrack = nil
    }

    var playbackState: PacerPlaybackState {
        PacerPlaybackState(
            isPlaying: tempoEngine.status.state == .playing,
            track: currentTrack,
            position: 0
        )
    }
}
