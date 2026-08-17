import Foundation
import MusicKit
import PacerKit

/// Apple Music via MusicKit — the first-class streaming integration.
///
/// What Apple officially permits (verified against MusicKit as of 2026):
///  - Authorization, library/playlist browsing, catalog metadata.
///  - Full-quality playback of subscription content through
///    `ApplicationMusicPlayer`, including background playback with the
///    audio background mode.
///  - Queue control (set queue, play/pause/skip).
///
/// What Apple does NOT provide or permit — and Pacer therefore does not do:
///  - No BPM/tempo metadata on catalog items (MusicKit exposes none).
///    Track BPMs must come from manual tagging (user_track_overrides) or
///    other legitimate sources; unknown-BPM tracks rank low but stay usable.
///  - No tempo/rate manipulation of protected streams. ApplicationMusicPlayer
///    exposes no supported time-stretch control, and circumventing that (or
///    DRM) is off the table. Pacer's Apple Music mode is therefore a
///    cadence-aware track SELECTION engine; true tempo-shifting lives in
///    Demo Mode with audio we own.
///
/// Requirements to light this up on a device: an Apple Developer account
/// with the MusicKit app service enabled for the bundle ID, a device signed
/// into an Apple Music subscription, and NSAppleMusicUsageDescription
/// (already configured). Playback does not work in the iOS Simulator.
final class AppleMusicProvider: MusicProviding {
    let id: MusicProviderID = .appleMusic
    let label = "Apple Music"
    let capabilities = MusicProviderCapabilities(
        bpmMetadata: false,
        playbackControl: true,
        tempoShift: false,
        limitations: [
            "MusicKit exposes no BPM metadata — tag track BPMs manually for best matching.",
            "Protected streams cannot be tempo-shifted; Pacer selects tracks instead.",
            "Requires an active Apple Music subscription; not available in the Simulator.",
        ]
    )

    /// MusicKit items keyed by PacerTrack id, so the sequencer can hand back
    /// a PacerTrack and we can still enqueue the real MusicKit track.
    private var libraryTracks: [String: Track] = [:]
    private var libraryPlaylists: [String: Playlist] = [:]
    private(set) var currentTrack: PacerTrack?

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    func authorize() async throws {
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            throw MusicProviderError.notAuthorized(
                "Apple Music access was not granted. Enable it in Settings → Privacy → Media & Apple Music."
            )
        }
    }

    func playlists() async throws -> [PacerPlaylist] {
        guard isAuthorized else {
            throw MusicProviderError.notAuthorized("Connect Apple Music first.")
        }
        var request = MusicLibraryRequest<Playlist>()
        request.limit = 50
        let response = try await request.response()
        var result: [PacerPlaylist] = []
        for playlist in response.items {
            let pid = playlist.id.rawValue
            libraryPlaylists[pid] = playlist
            result.append(
                PacerPlaylist(
                    id: "apple:\(pid)",
                    provider: .appleMusic,
                    providerPlaylistID: pid,
                    name: playlist.name,
                    artworkURL: playlist.artwork?.url(width: 300, height: 300)
                )
            )
        }
        return result
    }

    func tracks(inPlaylist playlistID: String) async throws -> [PacerTrack] {
        let rawID = playlistID.replacingOccurrences(of: "apple:", with: "")
        guard let playlist = libraryPlaylists[rawID] else {
            throw MusicProviderError.notFound("Playlist not loaded — fetch playlists first.")
        }
        let detailed = try await playlist.with([.tracks])
        var result: [PacerTrack] = []
        for track in detailed.tracks ?? [] {
            let tid = "apple:\(track.id.rawValue)"
            libraryTracks[tid] = track
            result.append(
                PacerTrack(
                    id: tid,
                    provider: .appleMusic,
                    providerTrackID: track.id.rawValue,
                    name: track.title,
                    artist: track.artistName,
                    artworkURL: track.artwork?.url(width: 300, height: 300),
                    durationMs: track.duration.map { Int($0 * 1000) },
                    bpm: nil // MusicKit provides no tempo metadata
                )
            )
        }
        return result
    }

    func play(track: PacerTrack) async throws {
        guard let musicTrack = libraryTracks[track.id] else {
            throw MusicProviderError.notFound("Track not in the loaded library cache.")
        }
        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [musicTrack])
        try await player.play()
        currentTrack = track
    }

    func pause() async {
        ApplicationMusicPlayer.shared.pause()
    }

    func resume() async throws {
        try await ApplicationMusicPlayer.shared.play()
    }

    func skipToNext() async throws {
        try await ApplicationMusicPlayer.shared.skipToNextEntry()
    }

    func stopPlayback() async {
        ApplicationMusicPlayer.shared.stop()
        currentTrack = nil
    }

    var playbackState: PacerPlaybackState {
        let player = ApplicationMusicPlayer.shared
        return PacerPlaybackState(
            isPlaying: player.state.playbackStatus == .playing,
            track: currentTrack,
            position: player.playbackTime
        )
    }
}
