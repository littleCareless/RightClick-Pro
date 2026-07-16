# Finder 增强：13 项新功能

## Goal

把 RightClick Pro 从"文件操作右键菜单"升级为"类 Windows 资源管理器 + VSCode 文件管理器"的完整体验。一次性补齐 13 项功能。

## Requirements

### A. 剪贴板扩展（6 项，全在 Finder 扩展本地处理）

1. **复制文件名（不含扩展名）** — `.copyFileName`
   - `foo.swift` → `foo`
   - 无扩展名文件 → 复制整个文件名
   - 多文件 → 换行分隔
   - 位置：`fileOperations` 分组，紧跟 `copyFilePath` 之后

2. **复制父目录路径** — `.copyParentPath`
   - `/a/b/c.txt` → `/a/b`
   - 多文件 → 去重后换行分隔
   - 位置：`fileOperations` 分组

3. **复制为 URL** — `.copyPathAsURL`
   - `/a/b c.txt` → `file:///a/b%20c.txt`
   - 位置：`fileOperations` 分组

4. **复制为 shell 转义** — `.copyPathAsShellEscaped`
   - `/a/b c.txt` → `'/a/b c.txt'` 或 `/a/b\ c.txt`
   - 用单引号包裹（POSIX 推荐方式）
   - 位置：`fileOperations` 分组

5. **复制为 Home 相对路径** — `.copyPathAsHomeRelative`
   - `/Users/zhangning/coding/x.swift` → `~/coding/x.swift`
   - 非 home 子目录 → 退化为绝对路径
   - 位置：`fileOperations` 分组

6. **复制为 tree 文本** — `.copyAsTree`
   - 多文件 → 计算公共父目录 → 生成 `tree` 样式输出
   - 例：
     ```
     src/
     ├── a.swift
     └── b/
         └── c.swift
     ```
   - 位置：`fileOperations` 分组

### B. 开发者入口扩展（5 项，复用 `.openInApp`）

7. **在 iTerm2 打开** — bundleIdentifier: `com.googlecode.iterm2`
8. **在 Zed 打开** — bundleIdentifier: `dev.zed.Zed`（待查）
9. **在 Xcode 打开** — bundleIdentifier: `com.apple.dt.Xcode`
10. **在 Warp 打开** — bundleIdentifier: `dev.warp.Warp-Stable`
11. **在 Ghostty 打开** — bundleIdentifier: `com.mitchellh.ghostty`（待查）

   位置：`developerEntrypoints` 分组，排在现有 Terminal/VSCode/Cursor 之后
   仅 installed 的应用才在 bootstrap 时注入（避免菜单里出现没装的 app）

### C. 智能批量重命名（1 项，走 XPC 委托主 app）

12. **智能批量重命名** — `.batchRename`
    - 触发流程：
      1. 用户在 Finder 选中 N 个文件 → 右键 → "批量重命名"
      2. Finder 扩展通过 `DistributedNotification` 通知主 app（同 `runCommand` 模式）
      3. 主 app 弹出 sheet，显示：
         - 原始文件名列表（左列）
         - 模板输入框 + 预览（右列，实时更新）
         - 查找替换输入框（可选）
         - "应用" / "取消" 按钮
      4. 用户确认 → 主 app 执行重命名 → 记录到 `operation-log.jsonl`（支持撤销）
    - 模板语法（最小集）：
      - `{name}` — 原文件名（不含扩展名）
      - `{ext}` — 扩展名
      - `{date}` — 文件修改日期 `YYYYMMDD`
      - `{n}` — 序号（从 1 开始）
      - `{n:03}` — 补零序号（001, 002, ...）
      - `{parent}` — 父目录名
    - 位置：`fileOperations` 分组
    - 主 app UI 文件：新建 `BatchRenameWindow.swift`（参考 `CommandRunWindow.swift`）

### D. 剪贴板历史（1 项，submenu 模式）

13. **剪贴板历史** — `.clipboardHistory`
    - 数据源：所有"复制类"操作都写入历史（包括系统 `NSPasteboard` 监听 + 我们自己的 action）
    - 存储：`~/Library/Application Support/com.iheeleme.rightclickpro/clipboard-history.json`
    - 容量：最近 20 条，FIFO
    - 触发方式：右键 → "剪贴板历史" → 子菜单列出最近条目（每条显示前 40 字符）→ 点击某条 → 写入 `NSPasteboard.general`
    - 实现：
      - 新建 `ClipboardHistoryStore.swift`（参考 `CutClipboardStore.swift` 模式）
      - 在 `handleCopyFilePathLocally` 系列方法里，每次复制都调用 `historyStore.append(_:)`
      - Finder 扩展拦截 `.clipboardHistory` → 从 store 读取 → 构建动态子菜单
    - 位置：`fileOperations` 分组顶部（`order: 5`）

## Acceptance Criteria

- [ ] 13 个新 action 全部在 Finder 右键菜单可见
- [ ] 6 个复制类 action 写入剪贴板的同时写入历史
- [ ] 剪贴板历史子菜单能显示最近 20 条并粘贴
- [ ] 5 个开发者入口：未安装的 app 不出现在菜单
- [ ] 批量重命名 sheet 在主 app 弹出，模板预览实时更新
- [ ] 重命名操作记录到 `operation-log.jsonl`，可撤销
- [ ] 老用户 bootstrap 时自动注入 13 个新 action（配置迁移）
- [ ] 全部 60+ 个既有测试通过 + 新功能有单元测试
- [ ] Release build + 安装到 `/Applications` + 真实 Finder 验证

## Definition of Done

- 全部测试通过
- Release build 通过 `scripts/package-macos.sh`
- 已安装到 `/Applications` 并在真实 Finder 中验证
- 配置迁移：老用户 bootstrap 时自动注入新 action

## Technical Approach

### 核心扩展点

- `ActionKind` 新增 7 个 case：`.copyFileName`, `.copyParentPath`, `.copyPathAsURL`, `.copyPathAsShellEscaped`, `.copyPathAsHomeRelative`, `.copyAsTree`, `.batchRename`
- `.clipboardHistory` 不需要新 case —— 用 `.runCommand` 风格拦截 + 动态 submenu（或者新增 `.clipboardHistory` case 也行，更清晰）
- 5 个开发者入口 = 5 条 `.openInApp` action，无新 case

### 执行路径分流

| Action | 处理位置 | 原因 |
|--------|----------|------|
| 6 个复制类 | Finder 扩展本地 | NSPasteboard 直接可用，无需 XPC |
| 5 个开发者入口 | XPC ActionRunner | 复用现有 `.openInApp` 路径 |
| 批量重命名 | 主 app | 需要 sheet UI |
| 剪贴板历史 | Finder 扩展本地 | 读 store + 动态 submenu |

### 关键新文件

- `Sources/RightClickProCore/ClipboardHistoryStore.swift` — 剪贴板历史持久化
- `Sources/RightClickProCore/RenameTemplateParser.swift` — 重命名模板解析
- `Sources/RightClickProCore/PathFormatting.swift` — URL/shell/home-relative 格式化
- `Sources/RightClickProCore/TreeFormatter.swift` — tree 文本生成
- `Sources/RightClickProAppPreview/BatchRenameWindow.swift` — 重命名 sheet UI

### 配置迁移

在 `ConfigurationBootstrapper.repairDefaultConfig` 里加检测：如果 actions 里没有 `copy-file-name` 等 ID，就 append 进去。确保老用户升级后自动拿到新功能。

## Decision (ADR-lite)

### 批量重命名 UI 走主 app

**Context**: Finder 扩展进程难以弹复杂 sheet
**Decision**: 复用 `runCommand` 的 `DistributedNotification` 模式委托主 app
**Consequences**: 主 app 必须运行才能用此功能（首次触发时可自动 launch 主 app，参考 `launchMainAppForCommandWindow`）

### 剪贴板历史用 submenu

**Context**: 需要 UI 展示历史条目
**Decision**: 右键菜单里 "剪贴板历史" → 动态 submenu 列出最近 20 条
**Consequences**: 不需要 menu bar 额外入口；20 条上限避免菜单过长

### 多格式复制用独立 action 而非 payload 变体

**Context**: 4 种格式（URL/shell/home/tree）
**Decision**: 4 个独立 action，每个有独立图标和标题
**Consequences**: 菜单占 4 行，但用户一眼能看到所有选项，比 submenu 更快

## Out of Scope

- 正则表达式重命名（v2 再做）
- 剪贴板历史搜索 / 收藏 / 分类
- 文件内容 hash（MD5/SHA） —— 另开任务
- EXIF 查看
- 压缩 / 解压（独立任务）
- 本地化（仍硬编码中文）

## Technical Notes

- `NSPasteboard.general.clearContents()` + `setString(_:forType:)` 在 Finder 扩展可用（已验证）
- `FIFinderSyncController` 的 `menu(for:)` 返回的 `NSMenu` 支持 `NSMenuItem.submenu`，可以做动态 submenu
- 开发者入口 bundleIdentifier 需要运行时验证（用 `NSWorkspace.urlForApplication(withBundleIdentifier:)` 检测是否安装）
- tree 格式化算法：构建路径前缀树 → DFS 打印（参考 `tree` 命令的 `─├──└` 样式）
- 重命名模板的 `{n:03}` 解析：用 `Scanner` 或 regex 提取宽度参数
- 配置迁移：在 `repairDefaultConfig` 里检查 action ID 是否存在，不存在就 append

---

## 进度 & 下次接手

**会话 1 完成（2026-07-16）**：

### ✅ 已完成

1. **ActionKind 扩展** — `ActionModels.swift` 添加了 8 个新 case（copyFilePath + 7 个新）
2. **穷举 switch 全部修复** — MenuBuilder / ActionRunner (×2) / DisplayExtensions (×2) 共 5 个 switch 都已加新 case，**当前可编译通过**
3. **核心工具模块创建**（4 个新文件）：
   - `Sources/RightClickProCore/PathFormatting.swift` — URL/shell/home-relative 格式化 ✅ 编译通过
   - `Sources/RightClickProCore/TreeFormatter.swift` — tree 层级文本生成 ✅ 编译通过
   - `Sources/RightClickProCore/ClipboardHistoryStore.swift` — 剪贴板历史持久化（File-backed + InMemory）✅ 编译通过
   - `Sources/RightClickProCore/RenameTemplateParser.swift` — 重命名模板解析 ⚠️ **有编译错误**（Regex API 用法不对，需要改用 `NSRegularExpression` 或正确的 `Regex` 用法）

### 🚧 下次会话的最小任务（按顺序）

**Step 1: 修复 `RenameTemplateParser.swift` 编译错误**

`Regex` 在 Swift 6 strict concurrency 模式下有问题。建议改用 `NSRegularExpression`：

```swift
let regex = try NSRegularExpression(pattern: #"\{(\w+)(?::(\d+))?\}"#)
let nsString = template.pattern as NSString
let matches = regex.matches(in: template.pattern, range: NSRange(location: 0, length: nsString.length))
for match in matches.reversed() {
    let variable = nsString.substring(with: match.range(at: 1))
    let width = match.range(at: 2).location != NSNotFound ? Int(nsString.substring(with: match.range(at: 2))) : nil
    let replacement = value(for: variable, url: url, index: index, width: width)
    nsString.replaceCharacters(in: match.range, with: replacement)
}
```

**Step 2: 添加默认 action**

在 `ActionModels.swift:281` 的 `defaultActions()` 方法里添加 13 个新 action（含 5 个开发者入口）。
在 `ConfigurationBootstrapper.swift:314` 的 `defaultActions(bookmarks:)` 方法里也添加（保持一致）。

开发者入口 bundleIdentifier：
- iTerm2: `com.googlecode.iterm2`
- Zed: `dev.zed.Zed`（**待验证**，可能是 `com.zed.Zed`）
- Xcode: `com.apple.dt.Xcode`
- Warp: `dev.warp.Warp-Stable`
- Ghostty: `com.mitchellh.ghostty`（**待验证**）

**Step 3: FinderSyncController 本地处理器**

在 `sendToActionRunner(_:)` 方法里拦截新 action（参考现有的 `handleCopyFilePathLocally`）：

```swift
private func handleCopyActionsLocally(_ request: ActionRequest) -> Bool {
    guard let action = cachedConfig.actions.first(where: { $0.id == request.actionID }) else {
        return false
    }
    let selectedItems = request.context.selectedItems
    let content: String?
    switch action.kind {
    case .copyFileName:
        content = selectedItems.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: "\n")
    case .copyParentPath:
        let parents = Set(selectedItems.map { $0.deletingLastPathComponent().path })
        content = parents.joined(separator: "\n")
    case .copyPathAsURL:
        content = selectedItems.map { PathFormatting.urlEncoded($0) }.joined(separator: "\n")
    case .copyPathAsShellEscaped:
        content = selectedItems.map { PathFormatting.shellEscaped($0) }.joined(separator: "\n")
    case .copyPathAsHomeRelative:
        content = selectedItems.map { PathFormatting.homeRelative($0) }.joined(separator: "\n")
    case .copyAsTree:
        content = TreeFormatter.format(selectedItems)
    default:
        return false
    }
    if let content {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        try? clipboardHistoryStore?.append(ClipboardHistoryEntry(content: content, sourceActionID: action.id))
        return true
    }
    return false
}
```

**Step 4: 配置迁移**

在 `ConfigurationBootstrapper.repairDefaultConfig` 里加检测：如果 actions 里没有 `copy-file-name` 等 ID，就 append 进去。

**Step 5: 测试 + 构建 + 安装**

- `swift test` 确认 60+ 个测试通过
- 为新模块写单元测试（PathFormatting / TreeFormatter / ClipboardHistoryStore / RenameTemplateParser）
- `bash scripts/package-macos.sh release`
- `cp -R "dist/staging/RightClick Pro.app" /Applications/ && xattr -cr ...`
- `pluginkit -a ... && pluginkit -e use -i com.iheeleme.rightclickpro.FinderExtension`
- 真实 Finder 验证

### 📋 后续（下次会话之后）

- **BatchRenameWindow** — 主 app 弹 sheet UI（参考 `CommandRunWindow.swift`）
- **批量重命名 XPC 路由** — FinderSyncController 拦截 `.batchRename` → DistributedNotification → 主 app
- **剪贴板历史 submenu** — FinderSyncController 拦截 `.clipboardHistory` → 从 store 读取 → 构建动态 NSMenu.submenu
- **开发者入口条件注入** — bootstrap 时检查 `NSWorkspace.urlForApplication(withBundleIdentifier:)`

### 📁 关键文件引用

| 文件 | 作用 |
|------|------|
| `Sources/RightClickProCore/ActionModels.swift:11` | ActionKind enum 定义 |
| `Sources/RightClickProCore/ActionModels.swift:281` | 默认 action 列表 |
| `Sources/RightClickProCore/ConfigurationBootstrapper.swift:314` | bootstrap 默认 action |
| `Sources/RightClickProCore/ConfigurationBootstrapper.swift:120` | repairDefaultConfig 迁移点 |
| `Sources/RightClickProCore/MenuBuilder.swift:34` | 图标解析 |
| `Sources/RightClickProCore/ActionRunner.swift:106` | XPC 执行（新 action 在这里走 fallback） |
| `Sources/RightClickProFinderExtension/FinderSyncController.swift:313` | 本地拦截点 |
| `Sources/RightClickProAppPreview/DisplayExtensions.swift` | 3 个穷举 switch |
| `~/Library/Application Support/com.iheeleme.rightclickpro/config.json` | 运行时配置 |

