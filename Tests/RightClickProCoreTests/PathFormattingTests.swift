import Foundation
import Testing
@testable import RightClickProCore

@Suite struct PathFormattingTests {
    @Test func testURLEncoded() async throws {
        let url = URL(fileURLWithPath: "/Users/test/file with spaces.txt")
        let result = PathFormatting.urlEncoded(url)
        #expect(result == "file:///Users/test/file%20with%20spaces.txt")
    }

    @Test func testURLEncodedWithoutSpaces() async throws {
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let result = PathFormatting.urlEncoded(url)
        #expect(result == "file:///Users/test/file.txt")
    }

    @Test func testShellEscapedWithSpaces() async throws {
        let url = URL(fileURLWithPath: "/Users/test/file with spaces.txt")
        let result = PathFormatting.shellEscaped(url)
        #expect(result == "'/Users/test/file with spaces.txt'")
    }

    @Test func testShellEscapedWithoutSpaces() async throws {
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let result = PathFormatting.shellEscaped(url)
        #expect(result == "'/Users/test/file.txt'")
    }

    @Test func testHomeRelativeInHomeDirectory() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent("coding/test.swift").path
        let result = PathFormatting.homeRelative(URL(fileURLWithPath: path))
        #expect(result.hasPrefix("~/"))
        #expect(result.contains("coding/test.swift"))
    }

    @Test func testHomeRelativeOutsideHomeDirectory() async throws {
        let url = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let result = PathFormatting.homeRelative(url)
        #expect(result == "/opt/homebrew/bin/brew")
    }
}
