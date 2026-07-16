import Foundation

public struct ClipboardHistoryEntry: Codable, Equatable, Sendable {
    public var id: String
    public var content: String
    public var timestamp: Date
    public var sourceActionID: String?

    public init(id: String = UUID().uuidString, content: String, timestamp: Date = Date(), sourceActionID: String? = nil) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.sourceActionID = sourceActionID
    }
}

public protocol ClipboardHistoryStoring {
    func load() throws -> [ClipboardHistoryEntry]
    func append(_ entry: ClipboardHistoryEntry) throws
    func clear() throws
}

public final class FileBackedClipboardHistoryStore: ClipboardHistoryStoring {
    private let url: URL
    private let maxEntries: Int
    private let lock = NSLock()

    public init(url: URL, maxEntries: Int = 20) {
        self.url = url
        self.maxEntries = maxEntries
    }

    public func load() throws -> [ClipboardHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        return try JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)
    }

    public func append(_ entry: ClipboardHistoryEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        var entries: [ClipboardHistoryEntry] = []
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try? Data(contentsOf: url)
            if let data, !data.isEmpty {
                entries = (try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)) ?? []
            }
        }
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: url, options: .atomic)
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

public final class InMemoryClipboardHistoryStore: ClipboardHistoryStoring {
    private let maxEntries: Int
    private let lock = NSLock()
    private var _entries: [ClipboardHistoryEntry] = []

    public var entries: [ClipboardHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    public init(maxEntries: Int = 20) {
        self.maxEntries = maxEntries
    }

    public func load() throws -> [ClipboardHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    public func append(_ entry: ClipboardHistoryEntry) throws {
        lock.lock()
        defer { lock.unlock() }
        _entries.insert(entry, at: 0)
        if _entries.count > maxEntries {
            _entries = Array(_entries.prefix(maxEntries))
        }
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        _entries = []
    }
}
