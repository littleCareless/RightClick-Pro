import Foundation

public struct ConfigurationBootstrapResult: Equatable, Sendable {
    public var paths: RightClickProStoragePaths
    public var config: RightClickProConfig
    public var bookmarks: DirectoryBookmarkCatalog
    public var didCreateConfig: Bool
    public var didCreateBookmarks: Bool

    public init(
        paths: RightClickProStoragePaths,
        config: RightClickProConfig,
        bookmarks: DirectoryBookmarkCatalog,
        didCreateConfig: Bool,
        didCreateBookmarks: Bool
    ) {
        self.paths = paths
        self.config = config
        self.bookmarks = bookmarks
        self.didCreateConfig = didCreateConfig
        self.didCreateBookmarks = didCreateBookmarks
    }
}

public struct ConfigurationBootstrapper {
    private static let defaultDirectoryBootstrapMarkerName = ".default-directory-bootstrap-v1"

    private let fileManager: FileManager
    private let processHomeDirectoryOverride: URL?
    private let realUserHomeDirectoryOverride: URL?

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            processHomeDirectory: nil,
            realUserHomeDirectory: nil
        )
    }

    init(
        fileManager: FileManager = .default,
        processHomeDirectory: URL?,
        realUserHomeDirectory: URL?
    ) {
        self.fileManager = fileManager
        self.processHomeDirectoryOverride = processHomeDirectory
        self.realUserHomeDirectoryOverride = realUserHomeDirectory
    }

    public func bootstrap(paths: RightClickProStoragePaths = .defaultForCurrentProcess()) throws -> ConfigurationBootstrapResult {
        let configStore = JSONFileStore<RightClickProConfig>(url: paths.configURL, fileManager: fileManager)
        let bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL, fileManager: fileManager)
        let logStore = JSONLineOperationLog(url: paths.operationLogURL, fileManager: fileManager)

        let defaultBookmarks = defaultBookmarks()
        let didCreateBookmarks = !fileManager.fileExists(atPath: paths.bookmarksURL.path)
        let originalBookmarks = try bookmarkStore.load(default: defaultBookmarks)
        let sanitizedBookmarks = sanitizeBookmarks(originalBookmarks)
        // 默认目录只在首次初始化或旧版本迁移时补齐，之后尊重用户删除。
        let shouldInjectDefaultBookmarks = didCreateBookmarks || !fileManager.fileExists(
            atPath: defaultDirectoryBootstrapMarkerURL(for: paths).path
        )
        let bookmarks = shouldInjectDefaultBookmarks
            ? repairDefaultBookmarks(sanitizedBookmarks, defaults: defaultBookmarks)
            : sanitizedBookmarks
        if didCreateBookmarks || bookmarks != originalBookmarks {
            try bookmarkStore.save(bookmarks)
        }

        let didCreateConfig = !fileManager.fileExists(atPath: paths.configURL.path)
        let originalConfig = try configStore.load(default: defaultConfig(bookmarks: bookmarks))
        let config = repairDefaultConfig(originalConfig, bookmarks: bookmarks, defaultBookmarkIDs: defaultBookmarks.bookmarks.map(\.id))
        if didCreateConfig || config != originalConfig {
            try configStore.save(config)
        }

        if shouldInjectDefaultBookmarks {
            try Data("1\n".utf8).write(
                to: defaultDirectoryBootstrapMarkerURL(for: paths),
                options: [.atomic]
            )
        }

        if !fileManager.fileExists(atPath: paths.operationLogURL.path) {
            try logStore.append(
                OperationRecord(
                    actionID: "bootstrap",
                    kind: .unsupported,
                    status: .success,
                    destinationPaths: [paths.baseURL.path],
                    message: "RightClick Pro 默认配置已自动注入"
                )
            )
        }

        return ConfigurationBootstrapResult(
            paths: paths,
            config: config,
            bookmarks: bookmarks,
            didCreateConfig: didCreateConfig,
            didCreateBookmarks: didCreateBookmarks
        )
    }

    private func defaultDirectoryBootstrapMarkerURL(for paths: RightClickProStoragePaths) -> URL {
        paths.baseURL.appendingPathComponent(Self.defaultDirectoryBootstrapMarkerName)
    }

    public func defaultBookmarks() -> DirectoryBookmarkCatalog {
        let home = realUserHomeDirectory
        let candidates: [(String, String, URL)] = [
            ("desktop", "桌面", home.appendingPathComponent("Desktop")),
            ("downloads", "下载", home.appendingPathComponent("Downloads"))
        ]

        let bookmarks = candidates
            .filter { fileManager.fileExists(atPath: $0.2.path) }
            .map { id, displayName, url in
                DirectoryBookmark(id: id, displayName: displayName, path: url.path)
            }

        return DirectoryBookmarkCatalog(bookmarks: bookmarks)
    }

    private func repairDefaultBookmarks(
        _ catalog: DirectoryBookmarkCatalog,
        defaults: DirectoryBookmarkCatalog
    ) -> DirectoryBookmarkCatalog {
        var repaired = catalog
        var existingIDs = Set(catalog.bookmarks.map(\.id))

        for bookmark in defaults.bookmarks where existingIDs.insert(bookmark.id).inserted {
            repaired.bookmarks.append(bookmark)
        }

        return repaired
    }

    private func repairDefaultConfig(
        _ config: RightClickProConfig,
        bookmarks: DirectoryBookmarkCatalog,
        defaultBookmarkIDs: [String]
    ) -> RightClickProConfig {
        var repaired = config
        let bookmarkIDs = Set(bookmarks.bookmarks.map(\.id))
        let directoryIDs = defaultBookmarkIDs.filter { bookmarkIDs.contains($0) }

        appendMissing(directoryIDs, to: &repaired.shortcutDirectoryIDs)
        appendMissingDirectoryActions(for: directoryIDs, bookmarks: bookmarks, to: &repaired.actions)
        appendMissingCommandActions(for: repaired.commandTemplates, to: &repaired.actions)
        appendMissingNewActions(to: &repaired.actions)  // Step 4: Add migration for 13 new actions
        repairDefaultDeveloperEntrypointTargets(in: &repaired.developerEntrypoints)

        return repaired
    }

    private func appendMissing(_ ids: [String], to existingIDs: inout [String]) {
        var seenIDs = Set(existingIDs)
        for id in ids where seenIDs.insert(id).inserted {
            existingIDs.append(id)
        }
    }

    private func appendMissingDirectoryActions(
        for directoryIDs: [String],
        bookmarks: DirectoryBookmarkCatalog,
        to actions: inout [RightClickProAction]
    ) {
        var existingActionIDs = Set(actions.map(\.id))
        var order = (actions.map(\.order).max() ?? 0) + 10

        for id in directoryIDs {
            guard let bookmark = bookmarks.bookmark(id: id) else {
                continue
            }

            for action in defaultDirectoryActions(for: bookmark, startingAt: order) where existingActionIDs.insert(action.id).inserted {
                actions.append(action)
                order += 10
            }
        }
    }

    private func defaultDirectoryActions(for bookmark: DirectoryBookmark, startingAt order: Int) -> [RightClickProAction] {
        [
            RightClickProAction(
                id: "open-directory-\(bookmark.id)",
                title: "前往\(bookmark.displayName)",
                kind: .openDirectory,
                visibility: [.container, .toolbar],
                placement: .submenu,
                group: .commonDirectories,
                order: order,
                payload: ActionPayload(directoryID: bookmark.id)
            ),
            RightClickProAction(
                id: "move-to-\(bookmark.id)",
                title: "移动到\(bookmark.displayName)",
                kind: .moveToDirectory,
                visibility: [.selection],
                placement: .submenu,
                group: .moveToCommonDirectory,
                order: order + 10,
                payload: ActionPayload(directoryID: bookmark.id)
            ),
            RightClickProAction(
                id: "copy-to-\(bookmark.id)",
                title: "复制到\(bookmark.displayName)",
                kind: .copyToDirectory,
                visibility: [.selection],
                placement: .submenu,
                group: .copyToCommonDirectory,
                order: order + 20,
                payload: ActionPayload(directoryID: bookmark.id)
            )
        ]
    }

    private func appendMissingCommandActions(
        for templates: [CommandTemplate],
        to actions: inout [RightClickProAction]
    ) {
        var existingActionIDs = Set(actions.map(\.id))
        var order = (actions.map(\.order).max() ?? 0) + 10

        for template in templates {
            let actionID = "run-\(template.id)"
            guard existingActionIDs.insert(actionID).inserted else {
                continue
            }
            actions.append(commandAction(for: template, id: actionID, order: order))
            order += 10
        }
    }

    private func commandAction(for template: CommandTemplate, id: String, order: Int) -> RightClickProAction {
        RightClickProAction(
            id: id,
            title: template.title,
            kind: .runCommand,
            visibility: [.selection, .container],
            placement: .submenu,
            group: .commandTemplates,
            order: order,
            payload: ActionPayload(commandTemplateID: template.id)
        )
    }

    // Step 4: Migration for 13 new actions (copy-file-name, copy-parent-path, etc.)
    private func appendMissingNewActions(to actions: inout [RightClickProAction]) {
        var existingActionIDs = Set(actions.map(\.id))
        var order = (actions.map(\.order).max() ?? 0) + 10

        let newClipboardActions: [(id: String, title: String, kind: ActionKind, order: Int)] = [
            ("copy-file-name", "复制文件名（不含扩展名）", .copyFileName, order),
            ("copy-parent-path", "复制父目录路径", .copyParentPath, order + 5),
            ("copy-path-as-url", "复制为 URL", .copyPathAsURL, order + 10),
            ("copy-path-as-shell-escaped", "复制为 shell 转义", .copyPathAsShellEscaped, order + 15),
            ("copy-path-as-home-relative", "复制为 Home 相对路径", .copyPathAsHomeRelative, order + 20),
            ("copy-as-tree", "复制为 tree 文本", .copyAsTree, order + 25),
            ("clipboard-history", "剪贴板历史", .clipboardHistory, 5),  // Special order at top
            ("batch-rename", "批量重命名", .batchRename, order + 30)
        ]

        for actionDef in newClipboardActions {
            if existingActionIDs.insert(actionDef.id).inserted {
                actions.append(
                    RightClickProAction(
                        id: actionDef.id,
                        title: actionDef.title,
                        kind: actionDef.kind,
                        visibility: [.selection],
                        placement: .submenu,
                        group: .fileOperations,
                        order: actionDef.order
                    )
                )
            }
        }

        // New developer entrypoints
        let newDeveloperApps: [(id: String, title: String, bundleId: String, entrypointID: String)] = [
            ("iterm2", "在 iTerm2 打开", "com.googlecode.iterm2", "developer-iterm2"),
            ("zed", "在 Zed 打开", "dev.zed.Zed", "developer-zed"),
            ("xcode", "在 Xcode 打开", "com.apple.dt.Xcode", "developer-xcode"),
            ("warp", "在 Warp 打开", "dev.warp.Warp-Stable", "developer-warp"),
            ("ghostty", "在 Ghostty 打开", "com.mitchellh.ghostty", "developer-ghostty")
        ]

        for app in newDeveloperApps {
            let actionID = "open-\(app.id)"
            if existingActionIDs.insert(actionID).inserted {
                actions.append(
                    RightClickProAction(
                        id: actionID,
                        title: app.title,
                        kind: .openInApp,
                        visibility: [.selection, .container, .toolbar],
                        placement: .submenu,
                        group: .developerEntrypoints,
                        order: order + 40,
                        payload: ActionPayload(developerEntrypointID: app.entrypointID)
                    )
                )
                order += 10
            }
        }
    }

    private func repairDefaultDeveloperEntrypointTargets(in entrypoints: inout [DeveloperEntrypoint]) {
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: RightClickProConfig.defaultDeveloperEntrypoints().map { ($0.id, $0) }
        )

        for index in entrypoints.indices {
            guard
                let defaultEntrypoint = defaultsByID[entrypoints[index].id],
                entrypoints[index].title == defaultEntrypoint.title,
                entrypoints[index].bundleIdentifier == defaultEntrypoint.bundleIdentifier,
                entrypoints[index].targetMode == .currentDirectory
            else {
                continue
            }

            entrypoints[index].targetMode = .dynamic
        }
    }

    /// Rewrites bookmarks that still point inside the host app sandbox container
    /// (e.g. `~/Library/Containers/.../Data/Desktop`) to the real user home
    /// equivalent. Runs on every bootstrap so existing installs self-heal without
    /// requiring the user to wipe their configuration.
    private func sanitizeBookmarks(_ catalog: DirectoryBookmarkCatalog) -> DirectoryBookmarkCatalog {
        let containerRoot = processHomeDirectory.standardizedFileURL.path
        let realHome = realUserHomeDirectory.standardizedFileURL.path
        guard containerRoot != realHome else {
            return catalog
        }
        var didChange = false
        let sanitized = catalog.bookmarks.map { bookmark -> DirectoryBookmark in
            let bookmarkPath = URL(fileURLWithPath: bookmark.path).standardizedFileURL.path
            guard let relativePath = relativePath(of: bookmarkPath, under: containerRoot) else {
                return bookmark
            }
            let newPath = relativePath.isEmpty
                ? realHome
                : (realHome as NSString).appendingPathComponent(relativePath)
            didChange = true
            return DirectoryBookmark(
                id: bookmark.id,
                displayName: bookmark.displayName,
                path: newPath,
                bookmarkDataBase64: bookmark.bookmarkDataBase64,
                addedAt: bookmark.addedAt
            )
        }
        guard didChange else { return catalog }
        return DirectoryBookmarkCatalog(schemaVersion: catalog.schemaVersion, bookmarks: sanitized)
    }

    private func relativePath(of path: String, under root: String) -> String? {
        if path == root {
            return ""
        }
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(rootPrefix) else {
            return nil
        }
        return String(path.dropFirst(rootPrefix.count))
    }

    /// Resolves the real user home directory, bypassing the App Sandbox
    /// container redirection that `homeDirectoryForCurrentUser` returns when
    /// the process is sandboxed. Falls back to the FileManager value when the
    /// real path cannot be determined.
    private var realUserHomeDirectory: URL {
        UserHomeDirectoryResolver.realUserHomeDirectory(
            processHomeDirectory: processHomeDirectory,
            override: realUserHomeDirectoryOverride
        )
    }

    private var processHomeDirectory: URL {
        processHomeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
    }

    public func defaultConfig(bookmarks: DirectoryBookmarkCatalog) -> RightClickProConfig {
        let directoryIDs = bookmarks.bookmarks.map(\.id)
        return RightClickProConfig(
            shortcutDirectoryIDs: directoryIDs,
            actions: defaultActions(bookmarks: bookmarks)
        )
    }

    private func defaultActions(bookmarks: DirectoryBookmarkCatalog) -> [RightClickProAction] {
        var actions: [RightClickProAction] = []
        var order = 10

        actions.append(
            RightClickProAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container],
                placement: .rootMenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        actions.append(
            RightClickProAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        actions.append(
            RightClickProAction(
                id: "copy-file-path",
                title: "复制文件路径",
                kind: .copyFilePath,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        // New clipboard extensions (Step 2)
        actions.append(
            RightClickProAction(
                id: "copy-file-name",
                title: "复制文件名（不含扩展名）",
                kind: .copyFileName,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "copy-parent-path",
                title: "复制父目录路径",
                kind: .copyParentPath,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "copy-path-as-url",
                title: "复制为 URL",
                kind: .copyPathAsURL,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "copy-path-as-shell-escaped",
                title: "复制为 shell 转义",
                kind: .copyPathAsShellEscaped,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "copy-path-as-home-relative",
                title: "复制为 Home 相对路径",
                kind: .copyPathAsHomeRelative,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "copy-as-tree",
                title: "复制为 tree 文本",
                kind: .copyAsTree,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 5

        actions.append(
            RightClickProAction(
                id: "clipboard-history",
                title: "剪贴板历史",
                kind: .clipboardHistory,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: 5  // Special order at top per PRD
            )
        )

        actions.append(
            RightClickProAction(
                id: "batch-rename",
                title: "批量重命名",
                kind: .batchRename,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order
            )
        )
        order += 10

        for bookmark in bookmarks.bookmarks {
            actions.append(contentsOf: defaultDirectoryActions(for: bookmark, startingAt: order))
            order += 30
        }

        for template in RightClickProConfig.defaultFileTemplates() {
            actions.append(
                RightClickProAction(
                    id: "create-\(template.id)",
                    title: "新建\(template.title)",
                    kind: .createFile,
                    visibility: [.container],
                    placement: template.id == "template-md" ? .rootMenu : .submenu,
                    group: .createFile,
                    order: order,
                    payload: ActionPayload(templateID: template.id)
                )
            )
            order += 10
        }

        for entrypoint in RightClickProConfig.defaultDeveloperEntrypoints() {
            actions.append(
                RightClickProAction(
                    id: "open-\(entrypoint.id)",
                    title: entrypoint.title,
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    order: order,
                    payload: ActionPayload(developerEntrypointID: entrypoint.id)
                )
            )
            order += 10
        }

        // New developer entrypoints (Step 2 - iTerm2, Zed, Xcode, Warp, Ghostty)
        let newDeveloperApps: [(id: String, title: String, bundleId: String)] = [
            ("iterm2", "在 iTerm2 打开", "com.googlecode.iterm2"),
            ("zed", "在 Zed 打开", "dev.zed.Zed"),
            ("xcode", "在 Xcode 打开", "com.apple.dt.Xcode"),
            ("warp", "在 Warp 打开", "dev.warp.Warp-Stable"),
            ("ghostty", "在 Ghostty 打开", "com.mitchellh.ghostty")
        ]
        for app in newDeveloperApps {
            actions.append(
                RightClickProAction(
                    id: "open-\(app.id)",
                    title: app.title,
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    order: order,
                    payload: ActionPayload(developerEntrypointID: "developer-\(app.id)")
                )
            )
            order += 10
        }

        for template in RightClickProConfig.defaultCommandTemplates() {
            actions.append(commandAction(for: template, id: "run-\(template.id)", order: order))
            order += 10
        }

        return actions
    }
}
