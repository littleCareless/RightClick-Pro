import Foundation
import Testing
@testable import RightClickProCore

@Suite struct RenameTemplateParserTests {
    @Test func testNameVariable() async throws {
        let template = RenameTemplate(pattern: "{name}_backup.{ext}")
        let url = URL(fileURLWithPath: "/Users/test/document.swift")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        #expect(result == "document_backup.swift")
    }

    @Test func testExtensionVariable() async throws {
        let template = RenameTemplate(pattern: "{name}.bak.{ext}")
        let url = URL(fileURLWithPath: "/Users/test/photo.jpg")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        #expect(result == "photo.bak.jpg")
    }

    @Test func testIndexVariable() async throws {
        let template = RenameTemplate(pattern: "file_{n}.txt")
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 5)
        #expect(result == "file_5.txt")
    }

    @Test func testIndexVariableWithPadding() async throws {
        let template = RenameTemplate(pattern: "file_{n:03}.txt")
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 5)
        #expect(result == "file_005.txt")
    }

    @Test func testDateVariable() async throws {
        let template = RenameTemplate(pattern: "{name}_{date}.{ext}")
        let url = URL(fileURLWithPath: "/Users/test/photo.jpg")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        // Date format is YYYYMMDD, so it should contain 8 digits
        #expect(result.contains("_"))
        #expect(result.hasSuffix(".jpg"))
    }

    @Test func testParentVariable() async throws {
        let template = RenameTemplate(pattern: "{parent}_{name}.{ext}")
        let url = URL(fileURLWithPath: "/Users/test/src/file.swift")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        #expect(result.contains("src_"))
        #expect(result.hasSuffix("file.swift"))
    }

    @Test func testFindAndReplace() async throws {
        let template = RenameTemplate(pattern: "{name}.{ext}", findText: "old", replaceText: "new")
        let url = URL(fileURLWithPath: "/Users/test/old_file.txt")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        #expect(result == "new_file.txt")
    }

    @Test func testMultipleFilesPreview() async throws {
        let template = RenameTemplate(pattern: "{n:02}_{name}.{ext}")
        let files = [
            URL(fileURLWithPath: "/Users/test/a.txt"),
            URL(fileURLWithPath: "/Users/test/b.txt"),
            URL(fileURLWithPath: "/Users/test/c.txt")
        ]
        let previews = RenameTemplateParser.preview(template: template, files: files, startingIndex: 1)
        #expect(previews.count == 3)
        #expect(previews[0].newFileName == "01_a.txt")
        #expect(previews[1].newFileName == "02_b.txt")
        #expect(previews[2].newFileName == "03_c.txt")
    }

    @Test func testUnknownVariable() async throws {
        let template = RenameTemplate(pattern: "{unknown}")
        let url = URL(fileURLWithPath: "/Users/test/file.txt")
        let result = RenameTemplateParser.apply(template: template, to: url, index: 1)
        #expect(result == "{unknown}")
    }
}
