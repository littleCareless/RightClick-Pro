import Foundation
import Testing
@testable import RightClickProCore

@Suite struct TreeFormatterTests {
    @Test func testSingleFile() async throws {
        let url = URL(fileURLWithPath: "/Users/test/src/file.swift")
        let result = TreeFormatter.format([url])
        #expect(result.contains("file.swift"))
    }

    @Test func testMultipleFilesInSameDirectory() async throws {
        let files = [
            URL(fileURLWithPath: "/Users/test/src/a.swift"),
            URL(fileURLWithPath: "/Users/test/src/b.swift")
        ]
        let result = TreeFormatter.format(files)
        #expect(result.contains("src/"))
        #expect(result.contains("a.swift"))
        #expect(result.contains("b.swift"))
    }

    @Test func testTreeStructureWithSubdirectories() async throws {
        let files = [
            URL(fileURLWithPath: "/Users/test/src/a.swift"),
            URL(fileURLWithPath: "/Users/test/src/b/c.swift")
        ]
        let result = TreeFormatter.format(files)
        #expect(result.contains("src/"))
        #expect(result.contains("a.swift"))
        #expect(result.contains("b/"))
        #expect(result.contains("c.swift"))
    }

    @Test func testCommonParentDirectory() async throws {
        let files = [
            URL(fileURLWithPath: "/Users/test/project/src/main.swift"),
            URL(fileURLWithPath: "/Users/test/project/src/utils/helper.swift")
        ]
        let result = TreeFormatter.format(files)
        // Should show tree from common parent
        #expect(result.contains("src/"))
        #expect(result.contains("main.swift"))
        #expect(result.contains("utils/"))
        #expect(result.contains("helper.swift"))
    }
}
