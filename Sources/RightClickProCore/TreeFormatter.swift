import Foundation

public enum TreeFormatter {
    private struct TreeNode {
        var name: String
        var children: [String: TreeNode] = [:]
        var isFile: Bool = false
    }

    public static func format(_ urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        let commonPrefix = commonParentDirectory(urls)
        var root = TreeNode(name: commonPrefix.lastPathComponent.isEmpty ? "/" : commonPrefix.lastPathComponent)
        for url in urls {
            let relative = String(url.path.dropFirst(commonPrefix.path.count)).drop(while: { $0 == "/" })
            if relative.isEmpty { continue }
            let parts = relative.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            insertPath(parts: parts, into: &root, fullURL: url)
        }
        var lines: [String] = [root.name + "/"]
        let sortedChildren = root.children.sorted(by: { $0.key < $1.key })
        for (index, pair) in sortedChildren.enumerated() {
            let isLast = index == sortedChildren.count - 1
            buildLines(node: pair.value, prefix: "", isLast: isLast, lines: &lines)
        }
        return lines.joined(separator: "\n")
    }

    private static func insertPath(parts: [String], into root: inout TreeNode, fullURL: URL) {
        guard let firstName = parts.first else { return }
        if root.children[firstName] == nil {
            root.children[firstName] = TreeNode(name: firstName)
        }
        if parts.count == 1 {
            root.children[firstName]?.isFile = !fullURL.hasDirectoryPath
        } else {
            var child = root.children[firstName]!
            insertPath(parts: Array(parts.dropFirst()), into: &child, fullURL: fullURL)
            root.children[firstName] = child
        }
    }

    private static func buildLines(node: TreeNode, prefix: String, isLast: Bool, lines: inout [String]) {
        let connector = isLast ? "└── " : "├── "
        if node.isFile {
            lines.append(prefix + connector + node.name)
        } else {
            lines.append(prefix + connector + node.name + "/")
            let childPrefix = prefix + (isLast ? "    " : "│   ")
            let sortedChildren = node.children.sorted(by: { $0.key < $1.key })
            for (index, pair) in sortedChildren.enumerated() {
                let childIsLast = index == sortedChildren.count - 1
                buildLines(node: pair.value, prefix: childPrefix, isLast: childIsLast, lines: &lines)
            }
        }
    }

    public static func commonParentDirectory(_ urls: [URL]) -> URL {
        guard let first = urls.first else {
            return URL(fileURLWithPath: "/")
        }
        let paths = urls.map { Array($0.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)) }
        var commonCount = paths[0].count
        for path in paths.dropFirst() {
            commonCount = min(commonCount, path.count)
            for i in 0..<commonCount {
                if path[i] != paths[0][i] {
                    commonCount = i
                    break
                }
            }
        }
        if commonCount == 0 { return URL(fileURLWithPath: "/") }
        let commonPath = "/" + paths[0].prefix(commonCount).joined(separator: "/")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir), !isDir.boolValue {
            return URL(fileURLWithPath: commonPath).deletingLastPathComponent()
        }
        if first.path.hasPrefix(commonPath + "/") || first.path == commonPath, isDir.boolValue {
            return URL(fileURLWithPath: commonPath)
        }
        return URL(fileURLWithPath: commonPath).deletingLastPathComponent()
    }
}
