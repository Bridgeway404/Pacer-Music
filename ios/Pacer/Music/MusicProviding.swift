import Foundation
import PacerKit

/// Abstraction over music sources (Demo, Apple Music, later Spotify).
///
/// Provider-specific restrictions (DRM, missing tempo metadata,
/// subscription-only playback) stay inside a provider implementation and
/// never leak into the cadence engine or sequencer. Capabilities are
/// declared explicitly so the UI can adapt honestly to what each provider
/// is allowed to do.
struct MusicProviderCapabilities: Sendable {
    /// Can we retrieve BPM/tempo metadata from the provider?
    let bpmMetadata: Bool
    /// Can we start/stop/skip playback through an official API?
    let playbackControl: Bool
    /// Can we legally change the playback tempo of the audio?
    let tempoShift: Bool
    /// Honest notes about what limits apply (surfaced in diagnostics/docs).
    let limitations: [String]
}

struct PacerPlaybackState: Sendable {
    var isPlaying: Bool
    var track: PacerTrack?
    var position: TimeInterval
}

protocol MusicProviding: AnyObject {
    var id: MusicProviderID { get }
    var label: String { get }
    var capabilities: MusicProviderCapabilities { get }

    /// Request whatever authorization the provider needs. Throws on denial.
    func authorize() async throws
    var isAuthorized: Bool { get }

    func playlists() async throws -> [PacerPlaylist]
    func tracks(inPlaylist playlistID: String) async throws -> [PacerTrack]

    // Playback surface — only where officially supported.
    func play(track: PacerTrack) async throws
    func pause() async
    func resume() async throws
    func skipToNext() async throws
    func stopPlayback() async
    var playbackState: PacerPlaybackState { get }
}

enum MusicProviderError: LocalizedError {
    case notAuthorized(String)
    case unsupported(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized(let why): why
        case .unsupported(let why): why
        case .notFound(let why): why
        }
    }
}
