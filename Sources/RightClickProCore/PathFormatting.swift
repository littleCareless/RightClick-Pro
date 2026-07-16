import Foundation

public enum PathFormatting {
    public static func urlEncoded(_ url: URL) -> String {
        url.absoluteString
    }

    public static func shellEscaped(_ url: URL) -> String {
        let path = url.path
        guard !path.isEmpty else { return "''" }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func homeRelative(_ url: URL) -> String {
        let home = NSHomeDirectory()
        let path = url.path
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        } else if path == home {
            return "~"
        }
        return path
    }
}
