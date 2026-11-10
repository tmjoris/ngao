import Foundation
import NgaoCore

/// Outbox rows as one JSON file in Application Support with complete file protection: the
/// file is unreadable while the device is locked, and it is excluded from backups because
/// idempotency keys are only meaningful on the device that created them.
actor FileOutboxStorage: OutboxStorage {
    private let url: URL
    private var cache: [IdempotencyKey: TransferMachine]?

    init(url: URL) {
        self.url = url
    }

    static func `default`() -> FileOutboxStorage {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return FileOutboxStorage(url: support.appendingPathComponent("outbox.json"))
    }

    func load() async throws -> [TransferMachine] {
        if let cache { return Array(cache.values) }
        guard let data = try? Data(contentsOf: url) else {
            cache = [:]
            return []
        }
        let rows = try decoder.decode([TransferMachine].self, from: data)
        cache = Dictionary(uniqueKeysWithValues: rows.map { ($0.intent.id, $0) })
        return rows
    }

    func save(_ machine: TransferMachine) async throws {
        if cache == nil { _ = try await load() }
        cache?[machine.intent.id] = machine
        let data = try encoder.encode(Array(cache?.values ?? [:].values))
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
