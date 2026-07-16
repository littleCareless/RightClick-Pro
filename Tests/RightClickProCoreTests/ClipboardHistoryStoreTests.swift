import Foundation
import Testing
@testable import RightClickProCore

@Suite struct ClipboardHistoryStoreTests {
    @Test func testAppendAndLoad() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-clipboard-\(UUID().uuidString).json")
        let store = FileBackedClipboardHistoryStore(url: tempURL, maxEntries: 5)

        let entry1 = ClipboardHistoryEntry(content: "test content 1", sourceActionID: "copy-file-path")
        try? store.append(entry1)

        let loaded = try? store.load()
        #expect(loaded?.count == 1)
        #expect(loaded?.first?.content == "test content 1")

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func testFIFOEviction() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-clipboard-fifo-\(UUID().uuidString).json")
        let store = FileBackedClipboardHistoryStore(url: tempURL, maxEntries: 3)

        for i in 1...5 {
            let entry = ClipboardHistoryEntry(content: "content \(i)", sourceActionID: "test-action")
            try? store.append(entry)
        }

        let loaded = try? store.load()
        #expect(loaded?.count == 3)
        // Most recent first (FIFO with insert at 0)
        #expect(loaded?.first?.content == "content 5")
        #expect(loaded?.last?.content == "content 3")

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func testClear() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-clipboard-clear-\(UUID().uuidString).json")
        let store = FileBackedClipboardHistoryStore(url: tempURL)

        let entry = ClipboardHistoryEntry(content: "test", sourceActionID: "test")
        try? store.append(entry)
        try? store.clear()

        let loaded = try? store.load()
        #expect(loaded?.isEmpty ?? true)

        // Cleanup
        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test func testInMemoryStore() async throws {
        let store = InMemoryClipboardHistoryStore(maxEntries: 3)

        for i in 1...5 {
            let entry = ClipboardHistoryEntry(content: "content \(i)", sourceActionID: "test")
            try? store.append(entry)
        }

        let entries = try? store.load()
        #expect(entries?.count == 3)
        #expect(entries?.first?.content == "content 5")
    }
}
