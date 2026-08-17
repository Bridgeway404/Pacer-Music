import Foundation
import Supabase
import PacerKit

/// Supabase backend access (project "Pacer", ref hpxrgcvvvovofpbgjbie).
///
/// Only the *publishable* key ships in the binary — it is designed to be
/// public; every table is protected by Row Level Security, so this key can
/// only ever act as the signed-in user. No service-role/secret key exists
/// anywhere in the app.
enum SupabaseConfig {
    static let url = URL(string: "https://hpxrgcvvvovofpbgjbie.supabase.co")!
    static let publishableKey = "sb_publishable_utvM4ejhpKlbK9K-KvWCgw_RqHuf4X1"
}

@MainActor
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient
    private(set) var userID: UUID?
    private(set) var userEmail: String?
    var isSignedIn: Bool { userID != nil }

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey
        )
        Task { await observeAuth() }
    }

    private func observeAuth() async {
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                userID = session?.user.id
                userEmail = session?.user.email
            case .signedOut:
                userID = nil
                userEmail = nil
            default:
                break
            }
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Run session persistence

    struct RunSessionRow: Codable, Identifiable {
        var id: UUID?
        var userId: UUID
        var startedAt: Date
        var endedAt: Date?
        var mode: String
        var requestedTargetSpm: Int?
        var averageCadence: Double?
        var peakCadence: Double?
        var onBeatPercent: Double?
        var playlistName: String?
        var cadenceSource: String?
        var songsPlayed: [SongPlayJSON]
        var targetChanges: [TargetChangeJSON]

        enum CodingKeys: String, CodingKey {
            case id
            case userId = "user_id"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case mode
            case requestedTargetSpm = "requested_target_spm"
            case averageCadence = "average_cadence"
            case peakCadence = "peak_cadence"
            case onBeatPercent = "on_beat_percent"
            case playlistName = "playlist_name"
            case cadenceSource = "cadence_source"
            case songsPlayed = "songs_played"
            case targetChanges = "target_changes"
        }
    }

    struct SongPlayJSON: Codable {
        var trackId: String
        var name: String
        var artist: String
        var startedAt: Date

        enum CodingKeys: String, CodingKey {
            case trackId = "track_id"
            case name
            case artist
            case startedAt = "started_at"
        }
    }

    struct TargetChangeJSON: Codable {
        var t: Date
        var targetSpm: Int
        var reason: String

        enum CodingKeys: String, CodingKey {
            case t
            case targetSpm = "target_spm"
            case reason
        }
    }

    private struct CadenceSampleRow: Codable {
        var sessionId: UUID
        var capturedAt: Date
        var rawSpm: Double
        var smoothedSpm: Double?
        var source: String

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case capturedAt = "captured_at"
            case rawSpm = "raw_spm"
            case smoothedSpm = "smoothed_spm"
            case source
        }
    }

    private struct DecisionRow: Codable {
        var sessionId: UUID
        var decidedAt: Date
        var decisionType: String
        var reason: String?
        var targetSpm: Double?
        var previousTargetSpm: Double?

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case decidedAt = "decided_at"
            case decisionType = "decision_type"
            case reason
            case targetSpm = "target_spm"
            case previousTargetSpm = "previous_target_spm"
        }
    }

    private struct InsertedID: Codable {
        var id: UUID
    }

    /// Persist a finished run (session row + downsampled cadence trace +
    /// engine decisions). Returns the new session id.
    func saveSession(_ summary: SessionRecorder.Summary, playlistName: String?) async throws -> UUID {
        guard let userID else {
            throw NSError(
                domain: "Pacer", code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to save runs to the cloud"]
            )
        }

        let row = RunSessionRow(
            id: nil,
            userId: userID,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            mode: summary.mode.rawValue,
            requestedTargetSpm: summary.requestedTargetSpm,
            averageCadence: summary.averageCadence.map { ($0 * 100).rounded() / 100 },
            peakCadence: summary.peakCadence.map { ($0 * 100).rounded() / 100 },
            onBeatPercent: summary.onBeatPercent.map { ($0 * 100).rounded() / 100 },
            playlistName: playlistName,
            cadenceSource: summary.cadenceSource.rawValue,
            songsPlayed: summary.songsPlayed.map {
                SongPlayJSON(trackId: $0.trackID, name: $0.name, artist: $0.artist, startedAt: $0.startedAt)
            },
            targetChanges: summary.targetChanges.map {
                TargetChangeJSON(t: $0.t, targetSpm: $0.targetSpm, reason: $0.reason)
            }
        )

        let inserted: InsertedID = try await client
            .from("run_sessions")
            .insert(row, returning: .representation)
            .single()
            .execute()
            .value

        let sessionID = inserted.id

        let sampleRows = summary.samples.map {
            CadenceSampleRow(
                sessionId: sessionID,
                capturedAt: $0.t,
                rawSpm: ($0.raw * 100).rounded() / 100,
                smoothedSpm: $0.smoothed.map { s in (s * 100).rounded() / 100 },
                source: summary.cadenceSource.rawValue
            )
        }
        if !sampleRows.isEmpty {
            try await client.from("cadence_samples").insert(sampleRows).execute()
        }

        let decisionRows = summary.decisions.map {
            DecisionRow(
                sessionId: sessionID,
                decidedAt: $0.at,
                decisionType: $0.kind.rawValue,
                reason: $0.reason,
                targetSpm: $0.targetSpm.map(Double.init),
                previousTargetSpm: $0.previousTargetSpm.map(Double.init)
            )
        }
        if !decisionRows.isEmpty {
            try await client.from("playback_decisions").insert(decisionRows).execute()
        }

        return sessionID
    }

    func fetchSessions(limit: Int = 50) async throws -> [RunSessionRow] {
        try await client
            .from("run_sessions")
            .select()
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }
}
