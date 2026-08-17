import Foundation
import PacerKit

/// Local persistence for runs done without an account (Demo Mode works with
/// zero sign-in). Summaries are stored as JSON in the app's Documents
/// directory and shown in History alongside cloud sessions.
struct LocalRunRecord: Codable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var mode: String
    var requestedTargetSpm: Int?
    var averageCadence: Double?
    var peakCadence: Double?
    var onBeatPercent: Double?
    var playlistName: String?
    var cadenceSource: String
    var samples: [SessionRecorder.SamplePoint]
    var songsPlayed: [SessionRecorder.SongPlay]
    var targetChanges: [SessionRecorder.TargetChange]

    init(summary: SessionRecorder.Summary, playlistName: String?) {
        self.id = UUID()
        self.startedAt = summary.startedAt
        self.endedAt = summary.endedAt
        self.mode = summary.mode.rawValue
        self.requestedTargetSpm = summary.requestedTargetSpm
        self.averageCadence = summary.averageCadence
        self.peakCadence = summary.peakCadence
        self.onBeatPercent = summary.onBeatPercent
        self.playlistName = playlistName
        self.cadenceSource = summary.cadenceSource.rawValue
        self.samples = summary.samples
        self.songsPlayed = summary.songsPlayed
        self.targetChanges = summary.targetChanges
    }
}

enum LocalSessionStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("run-sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ record: LocalRunRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let url = directory.appendingPathComponent("\(record.id.uuidString).json")
        try data.write(to: url, options: .atomic)
    }

    static func loadAll() -> [LocalRunRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(LocalRunRecord.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func delete(id: UUID) {
        let url = directory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }
}
