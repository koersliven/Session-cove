# Session Cove 当前窗口阻塞与权限大窗回归改造计划

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 当前用户可见症状

用户最新反馈集中在三个严重交互问题：

1. 每次 Claude permission approval 仍然弹出一个很大的 ocean / island / permission 场景窗口。
2. 这个窗口会挡住桌面或其他应用的点击，像有一层透明窗口盖在上面。
3. 即使回到 compact bar 状态，bar 附近仍疑似有不可见区域拦截鼠标事件。

这不是单纯的视觉问题，而是 AppKit 窗口物理 frame、`NSHostingView` hit testing、SwiftUI 路由/运行版本之间共同造成的交互层级问题。

## 2. 截图证据解读

用户截图里出现了这些元素：

- 大面积 `PixelOceanBackground` 风格海底背景。
- 大岛屿图形与 attention ring。
- 右侧完整权限决策 panel。
- 顶部 `PERMISSION SIGNAL` 标题。
- `< COVE` / `X` 按钮。

这些元素与当前源码中的 `PermissionInterruptionView` 完全对应：

- `PixelOceanBackground()`：`SessionCove/UI/Views/PermissionInterruptionView.swift`
- `Text("PERMISSION SIGNAL")`：同文件 header
- `PixelAttentionRing()` + `PixelIslandSprite(...)`：同文件 context column
- `HookApprovalPanel(...)`：同文件 decision column

因此截图证明：运行中的 app 仍在展示旧的大型 permission interruption 场景，或者运行的是包含旧路由/旧 bundle 的版本。

## 3. 当前代码实际 findings

### 3.1 当前源码中 `CoveRootView` 已经不直接路由到 `PermissionInterruptionView`

当前 `SessionCove/UI/Views/CoveRootView.swift` 的路由是按 `viewModel.frameSize` 分三类：

```swift
switch viewModel.frameSize {
case .compact:
    CompactBarView(viewModel: viewModel)
        .frame(width: 300, height: 50)
case .ping:
    pingView
case .expanded:
    expandedView
        .frame(width: 500, height: 460)
        .padding(.top, 10)
}
```

其中 `pingView` 使用的是 `PermissionPingCard`：

```swift
if let request = viewModel.pendingHookRequest {
    PermissionPingCard(request: request) { decision in
        viewModel.decideHookRequest(decision)
    }
    .padding(.horizontal, 16)
    .padding(.top, 6)
    .padding(.bottom, 10)
}
```

`grep` 当前源码未发现 `PermissionInterruptionView(` 调用点。

结论：

- 代码层面看，最新源码已经不应该通过 `CoveRootView` 展示旧大窗。
- 如果用户运行中仍看到旧大窗，高概率是运行了旧 bundle / 旧进程，或 Xcode/SPM 打开的不是当前源码构建产物。
- 另一个可能是当前构建缓存或多个 app 副本并存，`open` 打开了旧 `.app`。

### 3.2 旧大窗组件仍然保留在源码中，容易造成回归/误用

`SessionCove/UI/Views/PermissionInterruptionView.swift` 仍存在，且完整保留旧大窗实现：

```swift
struct PermissionInterruptionView: View {
    var body: some View {
        ZStack {
            PixelOceanBackground()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                interruptionStage
                Spacer(minLength: 8)
            }
        }
    }
}
```

该文件还保留：

```swift
Text("PERMISSION SIGNAL")
```

以及：

```swift
HookApprovalPanel(request: request) { decision in
    viewModel.decideHookRequest(decision)
}
```

结论：

- 虽然当前 `CoveRootView` 不再调用它，但它仍参与编译。
- 后续任何人修改路由、合并分支、或恢复 map mode 时都可能误把权限请求重新接回这里。
- 需要把它显式废弃、重命名为 debug/demo-only，或从默认编译路径移除。

### 3.3 当前窗口动态尺寸实现比上一版前进了一步，但仍缺少可靠验证

当前 `SessionCove/UI/Window/CoveWindowController.swift` 已经使用动态尺寸：

```swift
private static func size(for frameSize: CoveFrameSize) -> NSSize {
    switch frameSize {
    case .compact: NSSize(width: 300, height: 50)
    case .ping:    NSSize(width: 360, height: 230)
    case .expanded: NSSize(width: 520, height: 480)
    }
}
```

并且在 frame size 变化时：

```swift
panel.setFrame(newFrame, display: true, animate: false)
hostingView?.frame = NSRect(origin: .zero, size: newSize)
```

触发路径来自 `CoveRootView`：

```swift
.onChange(of: viewModel.frameSize) { _, newSize in
    onFrameSizeChange?(newSize)
}
```

结论：

- 这比之前固定 `520x520` 透明窗口方案正确。
- 但目前没有 debug log / overlay 证明运行时真的收到了 `.ping` / `.compact` 变化，也没有打印实际 `panel.frame`。
- 如果用户看到旧大窗，首先要确认当前运行 app 的实际代码版本；其次要确认 `updatePanelFrame` 是否被调用。

### 3.4 `CoveViewModel` 的 permission 状态逻辑合理，但 `toggle()` 可能让 pending permission 被隐藏

当前 `CoveViewModel.frameSize`：

```swift
var frameSize: CoveFrameSize {
    switch uiMode {
    case .compact: .compact
    case .permissionInterruption: .ping
    default: .expanded
    }
}
```

pending request 到来时：

```swift
uiMode = .permissionInterruption
openReason = .notification
```

这意味着当前源码理论上应进入 `.ping`，不是 expanded。

但 `toggle()` 在 permission interruption 状态会：

```swift
if uiMode == .permissionInterruption {
    closeToCompact()
}
```

风险：

- 用户点 compact/ping bar 时，pending permission 还在，但 UI 可被收回 compact。
- 这不是“大窗”根因，但会让审批状态层级混乱。
- 更合理的行为是：permission pending 时点击 compact bar 不关闭审批，而是保持 ping 或把焦点放到 ping card。

### 3.5 透明区域拦截的根因仍然是 AppKit hit-test，不是 global click monitor

当前 `CovePanel`：

```swift
isOpaque = false
backgroundColor = .clear
```

当前 `CoveWindowController`：

```swift
panel.ignoresMouseEvents = false
let hosting = NSHostingView(rootView: rootView)
panel.contentView = hosting
```

这些意味着：

- 透明背景不会自动点击穿透。
- `NSHostingView` 的整个 frame 都可以参与 hit testing。
- 只要真实 window frame 比可见内容大，就会挡住背后的 app。

当前已经尝试让真实 frame 等于 mode size，但如果 frame 更新失效、旧进程仍运行、或 `NSHostingView`/content view 没有同步，就会复现透明拦截。

`NSEvent.addGlobalMonitorForEvents` 只是观察全局点击并在 expanded 时关闭，不会吞掉事件；它不是主要阻塞来源。

### 3.6 装饰层局部处理基本正确，但 roster 仍有全尺寸背景

`IslandHeaderStrip` 已经：

```swift
.allowsHitTesting(false)
.accessibilityHidden(true)
```

`SessionRosterRow` 和 project header 都有明确 `contentShape(Rectangle())`。

但 `HarborRosterView` 顶层仍有：

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(...)
```

这在 expanded 窗口内是合理的；问题不在 roster 内部，而在真实 NSPanel 是否只包住 expanded 视图。如果 expanded 后没缩回 compact，则透明/背景区域仍会挡住桌面。

### 3.7 Always 权限持久化修复已在当前代码中出现

`ClaudePermissionHook.swift` 当前 bridge script 已加入：

```python
def build_fallback_permission(payload, value):
    destination = "session" if value == "allowSession" else "localSettings"
    ...
    return [{"toolName": tool_name, "ruleContent": rule_content, "destination": destination}]
```

并在无 `permission_suggestions` 时：

```python
hook_output["decision"]["updatedPermissions"] = build_fallback_permission(payload, value)
```

结论：Always bug 的核心修复已在当前源码中，不应在这轮窗口修复里改动 hook protocol。

## 4. 根因假设排序

### 高置信：用户运行的不是当前最新源码构建产物

理由：

- 当前源码里没有 `PermissionInterruptionView(` 调用点。
- 截图出现的 `PERMISSION SIGNAL`、大海底背景、大岛、右侧 `HookApprovalPanel` 全部来自旧 `PermissionInterruptionView`。
- 这与当前 `CoveRootView -> pingView -> PermissionPingCard` 路由矛盾。

需要验证：

- 是否有多个 `Session Cove.app` 副本。
- 是否旧进程未杀掉。
- Xcode 是否运行了旧 DerivedData 构建。
- `swift build && ./scripts/bundle.sh` 后打开的是否确实是 `.build/release/Session Cove.app`。

### 高置信：旧 `PermissionInterruptionView` 保留导致回归风险

即使当前没有调用，只要文件存在且名称像正式页面，就可能被后续 agent 或 merge 重新接回默认路由。它应该从默认权限路径中彻底降级。

### 中高置信：窗口 frame resize 缺少运行时可观测性

当前实现看起来正确，但没有日志/overlay。用户反馈说明真实运行时可能不是 `300x50` / `360x230`。需要加不可误判的 runtime evidence：

- 每次 frame size 变化打印：mode、target size、actual `panel.frame`、hosting frame。
- Debug overlay 显示 `frameSize` 与 `window.frame`。

### 中置信：即使 resize 生效，仍需要 `PassThroughHostingView` 作为安全网

如果某些情况下 window frame 仍大于可见区域，或者 SwiftUI layout 在 content view 内有透明 padding，那么 `NSHostingView` 仍可能吃掉点击。

推荐最终加入 window-level 或 hosting-view-level hit-test 防线，而不是只依赖尺寸。

### 中置信：permission pending 下 `toggle()` 关闭 ping 会削弱交互层级

这不会制造旧大窗，但会让 pending 权限从 attention-first 变成可被隐藏的小状态。建议调整。

## 5. 改造目标

目标不是继续美化海底地图，而是先恢复 ping-island 式工具感：

1. Permission request 默认只显示小 ping card，不显示大海湾/大岛/地图。
2. Compact 状态真实窗口只占 `300x50`，不能有附近透明拦截。
3. Permission ping 状态真实窗口只占 `360x230` 左右，卡片外区域可点击背后 app。
4. Expanded roster 仅由用户主动打开，且外部点击可以关闭。
5. Deny / Allow / Session / Always 四个决策和 hook 解析保持不变。

## 6. 具体修复计划

### Step A：先验证运行版本，消除旧 bundle 干扰

执行前先做一次干净启动：

```bash
cd /Users/lipu/Work/session-cove
swift build
./scripts/bundle.sh
pkill -x "Session Cove" || true
open ".build/release/Session Cove.app"
```

如果仍然出现 `PERMISSION SIGNAL` 大窗，说明当前运行路径仍有旧代码或另有入口调用旧视图。

建议追加临时 runtime 标识：

- 在 `CoveRootView` 的 compact 或 ping 小角落显示 `build: ping-card route`。
- 或在 `CoveWindowController.updatePanelFrame` 打印日志。

验收：能确认当前运行的是最新源码构建产物。

### Step B：彻底移除旧 permission route 的可用性

处理 `PermissionInterruptionView.swift`：

选项 1（推荐）：重命名为 `LegacyPermissionInterruptionView`，并加明确注释：不允许作为默认 permission route。

选项 2：从 target 编译中排除/删除，直到未来真的需要 full map mode。

选项 3：保留但加 debug-only 条件编译，例如 `#if DEBUG_LEGACY_PERMISSION_SCENE`。

默认产品路径必须保证：

```swift
.permissionInterruption -> CoveFrameSize.ping -> PermissionPingCard
```

不能再走：

```swift
.permissionInterruption -> PermissionInterruptionView
```

### Step C：强化物理窗口尺寸更新

当前 `updatePanelFrame` 已经有基本实现，但需要补强：

1. 初始化时立即调用一次 `updatePanelFrame(for: viewModel.frameSize)`，不要只依赖初始 `.compact` 假设。
2. 在 `onFrameSizeChange` 中打印或记录实际 frame：

```swift
#if DEBUG
print("[CoveWindow] frameSize=\(newSize) target=\(newFrame) actual=\(panel.frame) hosting=\(hostingView?.frame ?? .zero)")
#endif
```

3. 同步 content view frame：

```swift
hostingView?.frame = NSRect(origin: .zero, size: newSize)
panel.contentView?.frame = NSRect(origin: .zero, size: newSize)
```

4. 保持顶部中心 anchor，frame height 改变时顶部 y 不跳动。

验收：

- `.compact` 实际 panel frame 为 `300x50`。
- `.ping` 实际 panel frame 为 `360x230`。
- `.expanded` 实际 panel frame 为 `520x480`。

### Step D：加入 `PassThroughHostingView` 作为第二道保险

即使 Step C 后理论上不需要，建议加入更稳的 host hit-test：

```swift
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRectProvider: (() -> [NSRect])?

    override func hitTest(_ point: NSPoint) -> NSView? {
        let rects = hitTestRectProvider?() ?? [bounds]
        guard rects.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return super.hitTest(point)
    }
}
```

如果真实 window 已经精确 resize，则 hit rect 可直接是 `bounds`。

如果将来为了动画短暂保留大 window，则 hit rect 必须是实际可见内容区域：

- compact：bar rect。
- ping：bar + permission card rect。
- expanded：roster rect。

注意：不要直接设置 `panel.ignoresMouseEvents = true`，否则按钮也不能点。

### Step E：调整 permission pending 的 toggle 行为

当前 `toggle()` 在 `.permissionInterruption` 时会关闭到 compact。建议改为：

- 如果 `pendingHookRequest != nil` 且当前是 `.permissionInterruption`，点击 compact/ping bar 不关闭，保持 ping。
- 如果用户明确点 close（未来可选），也不应丢失 pending，只是可以最小化但仍显示 attention badge。

建议最小改法：

```swift
func toggle() {
    if uiMode == .permissionInterruption {
        return
    } else if isExpanded {
        closeToCompact()
    } else {
        presentHarbor(reason: .click)
    }
}
```

这能保证审批请求不会被普通点击隐藏。

### Step F：保持 roster 装饰层不抢事件

当前 `IslandHeaderStrip` 已正确设置 `.allowsHitTesting(false)`。后续扩展时保持规则：

- 所有水纹、岛屿装饰、泡泡、光效默认 `.allowsHitTesting(false)`。
- 只有 compact bar、permission card 按钮、project row、session row 接受点击。
- 不要在大背景上加隐式 `contentShape`。

## 7. 手动 QA 清单

### Compact 状态

- 启动 app 后只看到 `300x50` compact bar。
- 点击 compact 左侧、右侧、下方 1-200px 区域，背后的 App 能收到点击。
- 鼠标移过 compact 周围不会出现不可见 hover/阻塞。

### Permission ping 状态

- 触发 Claude permission request。
- 只出现 compact bar 下方小 `PermissionPingCard`。
- 不出现 `PERMISSION SIGNAL`。
- 不出现大海底背景、大岛、大 attention ring。
- 点击 ping card 外的桌面/其他 App 可以操作背后 App。
- 点击 Deny / Allow / Session / Always 都能 resolve hook。
- `Always` 后下一次同类 permission 不应反复询问，除非 Claude 规则匹配本身不同。

### Expanded roster 状态

- 只有用户主动点击 compact bar 才打开 roster。
- expanded 真实窗口约 `520x480`。
- 点击外部关闭 roster。
- project row 和 session row 可正常 hover/click。
- IslandHeaderStrip 装饰不挡住 session row。

### 运行版本验证

- Debug 日志显示 `frameSize=ping` 时 target/actual 均为 `360x230`。
- Debug 日志显示 `frameSize=compact` 时 target/actual 均为 `300x50`。
- 应用内临时 build marker 与当前源码一致。

## 8. 非目标

本轮不要做这些事：

- 不改 Claude hook 协议。
- 不重写 Always fallback，当前代码已经有修复。
- 不新增海底生物、珊瑚、水母等装饰。
- 不继续微调 mascot anchor。
- 不把 permission approval 放回 full harbor map。
- 不依赖“透明背景自动点击穿透”这个错误假设。

## 9. 推荐下一步编码顺序

1. 加 runtime build/frame debug 标识，确认用户运行的是当前 bundle。
2. 废弃或 debug-gate `PermissionInterruptionView`，消除默认路由回归风险。
3. 补强 `CoveWindowController.updatePanelFrame` 的日志、初始化调用、contentView frame 同步。
4. 加 `PassThroughHostingView` 作为安全网。
5. 调整 pending permission 下 `toggle()` 不关闭 ping。
6. 构建并用真实 Claude permission request 做手动 QA。

## 10. 当前结论

从当前源码看，DeepSeek/第三轮的核心方向已经部分落地：`PermissionPingCard`、`CoveFrameSize`、动态 `setFrame`、`HarborRosterView` 都存在。

但用户截图与当前源码矛盾很大：截图对应的是旧 `PermissionInterruptionView`，而当前源码没有调用它。因此第一优先级不是继续猜 UI，而是确认运行版本与实际入口；同时把旧大窗组件从默认产品路径中彻底隔离。

透明点击拦截仍按 AppKit 真实 window/hit-test 问题处理：真实窗口必须贴合可见内容，并用 pass-through hosting view 做兜底。