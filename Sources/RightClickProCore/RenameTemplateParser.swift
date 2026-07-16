import Foundation

public struct RenameTemplate {
    public var pattern: String
    public var findText: String
    public var replaceText: String

    public init(pattern: String, findText: String = "", replaceText: String = "") {
        self.pattern = pattern
        self.findText = findText
        self.replaceText = replaceText
    }
}

public struct RenamePreview: Equatable, Sendable {
    public var originalURL: URL
    public var newFileName: String
    public var newURL: URL
}

public enum RenameTemplateParser {
    public static func preview(template: RenameTemplate, files: [URL], startingIndex: Int = 1) -> [RenamePreview] {
        files.enumerated().map { index, url in
            let newFileName = apply(template: template, to: url, index: startingIndex + index)
            let newURL = url.deletingLastPathComponent().appendingPathComponent(newFileName)
            return RenamePreview(originalURL: url, newFileName: newFileName, newURL: newURL)
        }
    }

    public static func apply(template: RenameTemplate, to url: URL, index: Int) -> String {
        let patternString = #"\{(\w+)(?::(\d+))?\}"#
        guard let regex = try? NSRegularExpression(pattern: patternString) else {
            return template.pattern
        }

        let nsString = template.pattern as NSString
        let matches = regex.matches(in: template.pattern, range: NSRange(location: 0, length: nsString.length))

        // Build result by replacing variables with values
        var result = ""
        var lastIndex = 0

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }

            // Add text before this match
            let matchRange = match.range
            if matchRange.location > lastIndex {
                let preRange = NSRange(location: lastIndex, length: matchRange.location - lastIndex)
                result += nsString.substring(with: preRange)
            }

            // Extract variable and width
            let variable = nsString.substring(with: match.range(at: 1))
            let width: Int?
            if match.numberOfRanges >= 3, match.range(at: 2).location != NSNotFound {
                let widthStr = nsString.substring(with: match.range(at: 2))
                width = Int(widthStr)
            } else {
                width = nil
            }

            // Get replacement value
            let replacement = value(for: variable, url: url, index: index, width: width)
            result += replacement

            lastIndex = matchRange.location + matchRange.length
        }

        // Add remaining text after last match
        if lastIndex < nsString.length {
            let remainingRange = NSRange(location: lastIndex, length: nsString.length - lastIndex)
            result += nsString.substring(with: remainingRange)
        }

        // If no matches were found, return original pattern
        if matches.isEmpty {
            result = template.pattern
        }

        if !template.findText.isEmpty {
            result = result.replacingOccurrences(of: template.findText, with: template.replaceText)
        }
        return result
    }

    private static func value(for variable: String, url: URL, index: Int, width: Int?) -> String {
        switch variable {
        case "name": return namePart(url)
        case "ext": return extensionPart(url)
        case "date": return dateString(url)
        case "parent": return url.deletingLastPathComponent().lastPathComponent
        case "n":
            let n = String(index)
            if let width = width, width > n.count {
                return String(repeating: "0", count: width - n.count) + n
            }
            return n
        default: return "{\(variable)}"
        }
    }

    private static func namePart(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name
    }

    private static func extensionPart(_ url: URL) -> String {
        url.pathExtension
    }

    private static func dateString(_ url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
