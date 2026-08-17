import Foundation

/// Shared domain types for Pacer.
///
/// PacerKit is framework-free Swift (Foundation only): no SwiftUI, no
/// CoreMotion, no MusicKit. The app layer adapts platform services
/// (CMPedometer, ApplicationMusicPlayer, AVAudioEngine) to these types,
/// which keeps every algorithm unit-testable on any platform.

/// Where a cadence sample came from.
public enum CadenceSource: String, Sendable, Codable, CaseIterable {
    case coreMotion = "core_motion"
    case simulator
    case tap
    case native
    case unknown
}

/// A single cadence observation in steps-per-minute.
public struct CadenceSample: Sendable, Equatable {
    /// Timestamp of the observation (seconds since reference date is fine;
    /// the engine only uses differences).
    public let capturedAt: Date
    /// Raw steps-per-minute. 0 means "no steps detected".
    public let spm: Double
    public let source: CadenceSource

    public init(capturedAt: Date, spm: Double, source: CadenceSource) {
        self.capturedAt = capturedAt
        self.spm = spm
        self.source = source
    }
}

/// The two primary Pacer run modes.
public enum RunMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case followMe = "follow_me"
    case paceMe = "pace_me"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .followMe: "Follow Me"
        case .paceMe: "Pace Me"
        }
    }
}

/// Music providers Pacer knows about.
public enum MusicProviderID: String, Sendable, Codable, CaseIterable {
    case demo
    case appleMusic = "apple_music"
    case spotify
}

/// Provider-agnostic track metadata.
/// (Named PacerTrack to avoid colliding with MusicKit.Track in the app layer.)
public struct PacerTrack: Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: MusicProviderID
    public let providerTrackID: String
    public let name: String
    public let artist: String
    public let artworkURL: URL?
    public let durationMs: Int?
    /// Known BPM of the recording, when legally/API-accessibly available.
    public let bpm: Double?
    /// For bundled/user audio the app may tempo-shift: local resource name.
    public let audioResource: String?

    public init(
        id: String,
        provider: MusicProviderID,
        providerTrackID: String,
        name: String,
        artist: String,
        artworkURL: URL? = nil,
        durationMs: Int? = nil,
        bpm: Double? = nil,
        audioResource: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerTrackID = providerTrackID
        self.name = name
        self.artist = artist
        self.artworkURL = artworkURL
        self.durationMs = durationMs
        self.bpm = bpm
        self.audioResource = audioResource
    }
}

/// Provider-agnostic playlist metadata.
public struct PacerPlaylist: Sendable, Equatable, Identifiable {
    public let id: String
    public let provider: MusicProviderID
    public let providerPlaylistID: String
    public let name: String
    public let artworkURL: URL?
    public var tracks: [PacerTrack]

    public init(
        id: String,
        provider: MusicProviderID,
        providerPlaylistID: String,
        name: String,
        artworkURL: URL? = nil,
        tracks: [PacerTrack] = []
    ) {
        self.id = id
        self.provider = provider
        self.providerPlaylistID = providerPlaylistID
        self.name = name
        self.artworkURL = artworkURL
        self.tracks = tracks
    }
}
