# Action Extension Patterns

> **Purpose**: How to safely add new actions to the RightClick Pro system without breaking existing behavior.

---

## Why This Spec?

Adding a new action touches 6+ files across the system. Missing one step causes:
- Menu items that don't appear
- Actions that fail silently
- Migration bugs for existing users
- Compilation errors from unhandled switch cases

This spec captures the complete contract for adding actions safely.

---

## Action Types

| Type | Handled By | Example |
|------|------------|---------|
| **File operation** | ActionRunner (XPC) | `.copy`, `.delete`, `.move` |
| **App launcher** | ActionRunner (XPC) | `.openInVSCode`, `.openTerminal` |
| **Local-only** | FinderSyncController | `.copyFilePath`, `.copyFileName` |
| **UI-triggered** | Main app sheet | `.batchRename`, `.clipboardHistory` |

**Decision Rule**: 
- Needs file system access → ActionRunner
- Needs Finder context (selected paths) but no file mutation → FinderSyncController local
- Needs user input → Main app UI

---

## Adding a New Action: Complete Checklist

### Step 1: Define ActionKind Case

**File**: `Sources/RightClickProCore/ActionModels.swift`

```swift
public enum ActionKind: String, Codable, Sendable {
    // ... existing cases
    case copyFileName  // Add new case
}
```

**Fix all exhaustive switches** (5 locations):
1. `ActionKind.displayTitle` - User-facing name
2. `ActionKind.systemImageName` - Icon
3. `MenuBuilder.buildAction` - Menu item creation
4. `ActionRunner.run` - Execution logic (or mark `.unsupported` for local/UI)
5. `DisplayExtensions.swift` - Preview display

**Critical**: Swift compiler will catch missing cases, but you must handle all 5.

---

### Step 2: Add Default Action Definition

**File**: `Sources/RightClickProCore/ActionModels.swift` (around line 281 in `defaultActions()`)

```swift
Action(
    id: "copy-file-name",
    kind: .copyFileName,
    order: 25,
    isEnabled: true
)
```

**Order Convention**:
- Clipboard operations: 5-30 (top of menu)
- File operations: 40-60
- App launchers: 70+ (grouped by category)
- Special (history, rename): 5, 100+ (placement varies)

**Increment by 5-10** to leave room for future insertions.

---

### Step 3: Add to ConfigurationBootstrapper

**File**: `Sources/RightClickProCore/ConfigurationBootstrapper.swift` (around line 314 in `defaultActions(bookmarks:)`)

**Mirror the same action definition** as in ActionModels.swift.

**Why both?** 
- `ActionModels.defaultActions()` is the canonical source
- `ConfigurationBootstrapper.defaultActions(bookmarks:)` injects bookmark-specific actions (e.g., developer tools with bundleIdentifier checks)

---

### Step 4: Implement Handling Logic

#### Option A: ActionRunner (XPC path)

**File**: `Sources/RightClickProCore/ActionRunner.swift`

```swift
case .copyFileName:
    let fileName = url.deletingPathExtension().lastPathComponent
    try NSPasteboard.general.setString(fileName, forType: .string)
    return .success(message: "已复制文件名: \(fileName)")
```

**When to use**: 
- File mutations (copy, delete, move, rename)
- App launching (needs NSWorkspace)
- Operations that need Authorization

#### Option B: FinderSyncController Local (no XPC)

**File**: `Sources/RightClickProFinderExtension/FinderSyncController.swift`

```swift
private func handleCopyActionsLocally(_ action: Action, urls: [URL]) -> Bool {
    switch action.kind {
    case .copyFileName:
        let names = urls.map { $0.deletingPathExtension().lastPathComponent }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setStringList(names)
        return true
    // ... other copy actions
    default:
        return false
    }
}
```

**Call site** (in `sendToActionRunner`, before XPC routing):

```swift
if handleCopyActionsLocally(action, urls: selectedURLs) {
    try? clipboardHistoryStore?.append(action.kind, urls)
    return
}
// ... existing XPC routing
```

**When to use**:
- Clipboard operations (NSPasteboard available in Finder extension)
- Read-only operations that don't need Authorization
- Operations that benefit from low latency (no XPC round-trip)

#### Option C: Main App UI

**File**: `Sources/RightClickProApp/` (new window/sheet)

**Mark as `.unsupported` in ActionRunner**:

```swift
case .batchRename, .clipboardHistory:
    return .unsupported  // Routed elsewhere
```

**Trigger mechanism** (DistributedNotification or other IPC):

```swift
// In FinderSyncController
case .batchRename:
    DistributedNotificationCenter.default().post(
        name: .init("com.iheeleme.rightclickpro.batchRename"),
        object: nil,
        userInfo: ["paths": urls.map(\.path)]
    )
```

**When to use**:
- Requires user input (batch rename templates)
- Needs complex UI (clipboard history submenu)
- Long-running operations that shouldn't block Finder

---

### Step 5: Configuration Migration (CRITICAL)

**File**: `Sources/RightClickProCore/ConfigurationBootstrapper.swift`

**Problem**: Existing users have config.json with old action lists. New actions won't appear unless migrated.

**Solution**: Add to `repairDefaultConfig`:

```swift
private func appendMissingNewActions(to actions: inout [Action]) {
    let newActions = Self.defaultActions(bookmarks: [])  // Or with bookmarks if needed
    let existingIDs = Set(actions.map(\.id))
    
    for action in newActions where !existingIDs.contains(action.id) {
        actions.append(action)
    }
}
```

**Call it**:

```swift
public func repairDefaultConfig() throws {
    // ... existing migration logic
    
    appendMissingNewActions(to: &config.actions)
    
    // ... save config
}
```

**Verification**: After installation, check `~/Library/Application Support/com.iheeleme.rightclickpro/config.json` contains all new action IDs.

---

### Step 6: Developer Entry Points (App Launchers)

**Problem**: Don't show actions for apps the user hasn't installed.

**Solution**: Runtime bundleIdentifier check in `ConfigurationBootstrapper.defaultActions(bookmarks:)`:

```swift
let iterm2 = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
if iterm2 != nil {
    actions.append(Action(id: "open-iterm2", kind: .openInITerm2, order: 70, isEnabled: true))
}
```

**Known Bundle IDs** (as of 2026-07-16):

| App | Bundle Identifier |
|-----|-------------------|
| iTerm2 | `com.googlecode.iterm2` |
| VS Code | `com.microsoft.VSCode` |
| Xcode | `com.apple.dt.Xcode` |
| Warp | `dev.warp.Warp-Stable` |
| Ghostty | `com.mitchellh.ghostty` |
| Zed | `dev.zed.Zed` (verify at runtime) |

**Verification**: `lsappinfo info -only LSBundleIdentifier=<bundle_id>`

---

## Swift 6 Strict Concurrency: Regex Patterns

**Problem**: `static let regex = /pattern/` fails to compile (Regex not Sendable).

**Solution**: Use `NSRegularExpression`:

```swift
// ❌ Wrong - Swift 6 compile error
static let templateRegex = /\{(\w+)(?::(\d+))?\}/

// ✅ Correct
private static let templateRegex: NSRegularExpression = {
    let pattern = #"\{(\w+)(?::(\d+))?\}"#
    return try! NSRegularExpression(pattern: pattern)
}()
```

**Range handling** (avoid invalidation during replacement):

```swift
let nsString = input as NSString
var result = ""
var lastEnd = 0

// Iterate backwards or build incrementally
for match in matches.reversed() {
    let range = match.range
    result = nsString.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd)) + replacement + result
    lastEnd = range.location + range.length
}
```

---

## Testing Requirements

### Unit Tests (Required)

**File**: `Tests/RightClickProCoreTests/<Module>Tests.swift`

**Minimum coverage**:
- 2-3 happy path cases
- 1 edge case (empty input, special characters)
- 1 error case (invalid input, missing resource)

**Example**:

```swift
func testCopyFileName_singleFile() throws {
    let url = URL(fileURLWithPath: "/Users/test/document.txt")
    let result = try PathFormatting.fileName(for: url)
    XCTAssertEqual(result, "document")
}

func testCopyFileName_multipleFiles() throws {
    let urls = [
        URL(fileURLWithPath: "/Users/test/a.txt"),
        URL(fileURLWithPath: "/Users/test/b.pdf")
    ]
    let result = try PathFormatting.fileNames(for: urls)
    XCTAssertEqual(result, ["a", "b"])
}
```

### Integration Tests (Recommended)

**File**: `Tests/RightClickProCoreTests/ConfigurationBootstrapperTests.swift`

```swift
func testMigrationAddsNewActions() throws {
    var config = Configuration(actions: [
        Action(id: "old-action", kind: .copyFilePath, order: 1, isEnabled: true)
    ])
    
    let bootstrapper = ConfigurationBootstrapper(configURL: tempURL)
    try bootstrapper.repairDefaultConfig()
    
    let migrated = try bootstrapper.loadConfig()
    XCTAssertTrue(migrated.actions.contains { $0.id == "copy-file-name" })
    XCTAssertTrue(migrated.actions.contains { $0.id == "clipboard-history" })
}
```

---

## Common Mistakes

### ❌ Wrong: Forgetting to update all 5 switch statements

**Symptom**: Compilation error "Switch must be exhaustive"

**Fix**: Search for `switch action.kind` or `switch kind` and update all locations.

### ❌ Wrong: Adding action to ActionModels but not ConfigurationBootstrapper

**Symptom**: New users get the action, existing users don't (no migration)

**Fix**: Always add to both `defaultActions()` and `defaultActions(bookmarks:)`.

### ❌ Wrong: Handling clipboard action in ActionRunner

**Symptom**: Action works but has 100ms latency (XPC round-trip)

**Fix**: Clipboard operations should be local in FinderSyncController.

### ❌ Wrong: Hardcoding app bundleIdentifier without runtime check

**Symptom**: Menu shows "Open in iTerm2" for users who don't have iTerm2

**Fix**: Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` in ConfigurationBootstrapper.

### ❌ Wrong: Using Swift Regex for static patterns

**Symptom**: Swift 6 compile error "Type 'Regex<...>' does not conform to 'Sendable'"

**Fix**: Use `NSRegularExpression` with `static let` or `private static let`.

---

## Verification Checklist

After implementing a new action:

- [ ] All 5 switch statements updated (compiles cleanly)
- [ ] Action added to `ActionModels.defaultActions()`
- [ ] Action added to `ConfigurationBootstrapper.defaultActions(bookmarks:)` (if bookmark-specific)
- [ ] Migration logic in `repairDefaultConfig` (if existing users need it)
- [ ] Handling logic implemented (ActionRunner OR FinderSyncController OR Main app)
- [ ] Unit tests added (2-3 cases minimum)
- [ ] `swift test` passes (all existing + new tests)
- [ ] `scripts/package-macos.sh release` builds successfully
- [ ] Installed app shows new action in Finder menu
- [ ] Runtime config.json contains new action ID

---

## Design Decisions

### Why separate local vs XPC handling?

**Context**: Some actions (clipboard operations) need Finder context but not file system Authorization.

**Options**:
1. Route all actions through ActionRunner (XPC)
2. Handle clipboard operations locally in FinderSyncController
3. Split based on Authorization needs

**Decision**: Option 2 - handle clipboard locally.

**Rationale**:
- Lower latency (no XPC round-trip)
- NSPasteboard available in Finder extension process
- Reduces XPC payload for high-frequency operations

**Trade-off**: Duplicates some logic between FinderSyncController and ActionRunner.

---

### Why NSRegularExpression over Swift Regex?

**Context**: Swift 6 strict concurrency requires all static let to be Sendable.

**Options**:
1. Use Swift Regex with non-static let (recompile on each call)
2. Use NSRegularExpression (Sendable-compatible)
3. Disable strict concurrency for regex patterns

**Decision**: Option 2 - NSRegularExpression.

**Rationale**:
- Compile once, reuse many times (performance)
- Compatible with Swift 6 Sendable requirements
- Well-tested Foundation API

**Trade-off**: More verbose API (NSRange vs Range<String.Index>).

---

## Related Specs

- [Error Handling](./error-handling.md) - XPC result mapping
- [Directory Structure](./directory-structure.md) - File ownership
- [Quality Guidelines](./quality-guidelines.md) - Testing requirements

---

**Last Updated**: 2026-07-16  
**Session**: 07-16-finder-tree (会话 2)
