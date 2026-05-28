# Session Cove 窗口点击拦截与权限弹窗问题 Debug

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 用户反馈

当前存在两个严重交互问题：

1. 每次权限审批都会跳出来一个“大图 / 大面板”，并且阻塞桌面光标点击其他区域。ping-island 不会有这个问题。
2. 即使在 compact bar 状态下，周围其他区域好像也被覆盖了。其他应用只要进入这个透明区域就无法点击，像有一层隐藏透明窗口拦截了点击。

结合截图，当前视觉上确实能看到 Session Cove 位于屏幕顶部，但其真实窗口区域远大于可见 compact bar。用户在这个不可见区域点击其他应用时，被 Session Cove 的透明 `NSPanel` 截获。

## 2. Root Cause

### 2.1 固定 520x520 NSPanel 是主要根因

当前 `CoveWindowController.swift`：

```swift
private let panelSize = NSSize(width: 520, height: 520)
...
let contentRect = NSRect(
    x: screenFrame.midX - panelSize.width / 2,
    y: screenFrame.maxY - panelSize.height,
    width: panelSize.width,
    height: panelSize.height
)
...
hosting.frame = NSRect(origin: .zero, size: panelSize)
panel.contentView = hosting
```

这意味着：

- 无论 UI 是 compact、ping 还是 expanded，真实 AppKit 窗口都是 `520x520`。
- compact 只是 SwiftUI 内容显示为 `300x50`，但下面仍然有一个 `520x520` 的透明 `NSPanel`。
- macOS 事件命中基于真实窗口区域，不基于 SwiftUI 可见像素。
- 所以透明区域也会吃掉鼠标事件。

第三轮文档中写了“超出内容区域的透明部分自动穿透点击”，但当前实现没有对应技术支持。透明并不等于可点击穿透。

### 2.2 `NSHostingView` 默认整块区域接收 hitTest

当前代码：

```swift
let hosting = NSHostingView(rootView: rootView)
hosting.frame = NSRect(origin: .zero, size: panelSize)
panel.contentView = hosting
```

`NSHostingView` 占满 `520x520`。即使 SwiftUI 的 `VStack` 只有顶部部分有内容，hosting view 仍然覆盖整个 window content area。

没有自定义：

- `hitTest(_:)`
- pass-through hosting view
- content rect 命中判断
- `ignoresMouseEvents` 动态控制

所以透明区域不会自动把点击传给背后的应用。

### 2.3 `CovePanel.ignoresMouseEvents = false` 全局接收鼠标

当前 `CoveWindowController.swift`：

```swift
panel.ignoresMouseEvents = false
```

当前 `CovePanel.swift`：

```swift
isOpaque = false
backgroundColor = .clear
hasShadow = false
```

这些只是让窗口透明，不会让它点击穿透。

只要 `ignoresMouseEvents = false`，整个真实窗口区域都会参与事件命中。

### 2.4 `CoveRootView` 顶部对齐但仍占满无限 frame

当前 `CoveRootView.swift`：

```swift
VStack(spacing: 0) {
    contentView
    Spacer(minLength: 0)
}
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
```

这保证内容顶对齐，但也使 root view 在 `NSHostingView` 内占满 `520x520`。因此 SwiftUI 视图树和 AppKit hosting view 都没有告诉系统“只有顶部 compact/ping 是可点击区域”。

### 2.5 权限弹窗看起来像“大图”的原因

当前 `.permissionInterruption` 被映射为 `.ping`：

```swift
var frameSize: CoveFrameSize {
    switch uiMode {
    case .compact: .compact
    case .permissionInterruption: .ping
    default: .expanded
    }
}
```

但物理窗口仍是 `520x520`。`pingView` 虽然内容是：

```swift
.frame(width: 360)
.fixedSize(horizontal: false, vertical: true)
```

外层仍然是一个 520x520 的 panel。加上：

```swift
.background(
    RoundedRectangle(cornerRadius: 16)
        .fill(Color(...))
        .shadow(...)
)
```

用户感知上就不是“小 ping”，而是“打开了一个大浮窗 / 大图”。

此外 `HookApprovalPanel` 内部固定：

```swift
.frame(width: 320)
```

并包含 42x42 mascot、summary、project path、四个按钮。它本身不算特别大，但放在固定 520x520 面板里会显得是一个完整 app 窗口。

## 3. 与 ping-island 的关键差异

ping-island 的轻量感来自两个层面：

1. **真实窗口尺寸接近可见内容尺寸**
   - compact 就是真 compact。
   - notification / permission 只打开必要尺寸。
   - 不用一个长期 520x520 透明大画布覆盖桌面。

2. **hitTest 只在真实 notch/panel 区域生效**
   - 真实内容外的点击传给背后的应用。
   - 用户不会感觉被一个透明窗口挡住。

Session Cove 目前只做到了视觉透明，没有做到事件穿透。

## 4. 改进路线选择

### 方案 A：推荐路线 — 按 UI mode 精确 resize 真实 NSPanel

恢复 / 重写窗口尺寸管理，让物理窗口尺寸等于当前可见内容尺寸。

推荐尺寸：

- compact：`300x50`
- ping：`360x220` 或按内容高度 `360x180-240`
- expanded roster：`520x480` 或 `560x500`

优点：

- 最直接解决透明区域拦截点击问题。
- 不需要复杂 hitTest。
- compact 状态真实窗口只有 300x50，不会阻塞周围区域。
- ping 状态真实窗口只有小卡片，不会像主页面。
- 与 ping-island 行为更接近。

缺点：

- 需要重新实现 `updatePanelFrame`。
- `NSPanel.setFrame(..., animate:)` 可能有卡顿；但现在默认 expanded 已经是 roster，不再渲染 full harbor map，卡顿风险比之前低。

建议实现方式：

- 不使用系统 `animate: true`。
- 使用立即 `setFrame(display: true, animate: false)`。
- 动画交给 SwiftUI 内容 opacity / scale / spring。
- 窗口 frame 变化只做快速 snap，避免 AppKit 动画卡顿。
- 以顶部中心为 anchor，改变高度时保持 top edge 不动。

伪代码：

```swift
private func size(for frameSize: CoveFrameSize) -> NSSize {
    switch frameSize {
    case .compact: NSSize(width: 300, height: 50)
    case .ping: NSSize(width: 360, height: 220)
    case .expanded: NSSize(width: 520, height: 480)
    }
}

private func updatePanelFrame(for frameSize: CoveFrameSize) {
    guard let panel = covePanel, let screen = panel.screen ?? NSScreen.screens.first else { return }
    let screenFrame = screen.visibleFrame
    let newSize = size(for: frameSize)
    let newFrame = NSRect(
        x: screenFrame.midX - newSize.width / 2,
        y: screenFrame.maxY - newSize.height,
        width: newSize.width,
        height: newSize.height
    )
    panel.setFrame(newFrame, display: true, animate: false)
    hostingView?.frame = NSRect(origin: .zero, size: newSize)
}
```

需要观察 `viewModel.frameSize`：

- 可用 `withObservationTracking` 或 Combine-like 手动定时检查。
- 当前是 `@Observable`，可以在 `CoveRootView` `.onChange(of: viewModel.frameSize)` 回调到 controller 不方便；更推荐 controller 内用 observation tracking。
- 简化方案：在 `CoveRootView` 注入 `onFrameSizeChange` callback。

### 方案 B：保留固定大窗口，但实现 PassThroughHostingView

如果坚持固定 520x520，不 resize，那必须做真正 pass-through。

新增 AppKit view：

```swift
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var activeHitRects: [NSRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeHitRects.contains(where: { $0.contains(point) }) else {
            return nil
        }
        return super.hitTest(point)
    }
}
```

根据当前 `frameSize` 更新 activeHitRects：

- compact：顶部居中 `300x50`
- ping：顶部居中 `360x220`
- expanded：顶部居中 `500x460`

优点：

- 不 resize window，理论上避免 AppKit frame 卡顿。
- 透明区域可以点击穿透。

缺点：

- 实现更复杂。
- SwiftUI 内部按钮、hover、scroll 事件可能受 hit rect 影响，需要仔细调坐标。
- 仍可能有视觉残留、shadow 裁切、截图中边界感。
- 固定大窗口在 Mission Control / Space / 全屏行为上更容易出怪问题。

### 方案 C：双窗口架构

用两个 panel：

- CompactPanel：只负责常驻 compact bar，真实尺寸 300x50。
- PopoverPanel：只在 ping/expanded 时显示，真实尺寸按内容变化。

优点：

- 语义清晰。
- compact 永远不阻塞大区域。
- permission ping 可以是独立小窗，像系统 popover。

缺点：

- 生命周期更复杂。
- 两个窗口之间的 z-order、focus、click outside、Space 行为需要处理。
- 对当前代码改动较大。

## 5. 推荐选择

推荐先做 **方案 A：按 mode 精确 resize 真实 NSPanel**。

原因：

- 最快解决用户当前两个痛点。
- 代码复杂度最低。
- 与 ping-island 的真实行为最接近。
- 现在不再默认渲染 full harbor map，resize 卡顿风险可控。
- 如果后续仍有 resize 卡顿，再升级到方案 B 或 C。

不要继续使用“固定 520x520 + 假设透明自动穿透”的方案。这个假设已经被用户反馈和代码验证推翻。

## 6. 具体技术路线

### Step 1：恢复物理窗口尺寸切换

文件：`SessionCove/UI/Window/CoveWindowController.swift`

改动：

- 移除固定 `panelSize = 520x520` 作为唯一窗口尺寸。
- 新增 `size(for:)`。
- 新增 `updatePanelFrame(for:)`。
- 初始化时使用 `.compact` 尺寸。
- 监听 `viewModel.frameSize`，变化时更新 window frame 和 hosting frame。

验收：

- compact 状态真实 window 只有 300x50。
- 鼠标点击 compact 外但原 520x520 区域内的其他 App，可以正常点击。

### Step 2：不要使用 AppKit resize 动画

改动：

- `panel.setFrame(..., animate: false)`。
- SwiftUI 内部继续保留轻微 opacity/scale transition。
- 如果肉眼觉得跳变明显，再加很短的 SwiftUI content transition，不加 AppKit frame animation。

验收：

- 权限请求出现不明显卡顿。
- 不再弹出“大图”。

### Step 3：重做 pingView 为真正小卡片

文件：`SessionCove/UI/Views/CoveRootView.swift`

改动：

- `pingView` 不要有大块 rounded window background。
- 结构为：compact bar + 小 `PermissionPingCard`。
- 只显示 tool、summary、project、四个按钮。
- 高度控制在 180-220。

可以新增：

- `SessionCove/UI/Views/PermissionPingCard.swift`

验收：

- pending permission 时只出现 compact 下方小卡片。
- 不进入 main roster。
- 不渲染 map。
- 不阻塞卡片外区域点击。

### Step 4：global click monitor 逻辑修正

当前：

```swift
guard let self, self.viewModel.isExpanded else { return }
self.viewModel.closeToCompact()
```

当前 `isExpanded` 对 `.permissionInterruption` 是 false，所以权限 ping 不会被外部点击关闭。这一点可以保留。

但 expanded roster 需要继续外部点击关闭。

建议：

- `.harborOverview/.projectIsland/.sessionFocus` 外部点击关闭。
- `.permissionInterruption` 外部点击不关闭，因为需要用户决策。
- compact 不处理。

### Step 5：如果 resize 后仍有透明区域拦截，再加 PassThroughHostingView

如果方案 A 后仍出现少量透明区域拦截，再追加：

- `PassThroughHostingView`
- `hitTest(_:)` 根据当前内容 rect 返回 nil

但它作为 fallback，不作为第一选择。

## 7. 验收标准

### Compact 状态

- 只能点击 compact bar 本体。
- compact 周围、下方、左右区域都能点击背后的 App。
- 不再有不可见 520x520 阻塞区域。
- 视觉上不再有矩形残留。

### Permission ping 状态

- 权限请求来时，只弹出小卡片。
- 小卡片尺寸约 360x200。
- 不打开 main roster。
- 不显示大图、大岛、大海湾。
- 卡片外区域不阻塞背后 App 点击，除了卡片真实窗口区域。
- Deny / Allow / Session / Always 正常工作。

### Expanded roster 状态

- 用户主动点击 compact 才进入。
- 窗口尺寸约 520x480。
- 外部点击关闭。
- 不影响 hook、SessionWatcher、SessionResumer、active detection。

## 8. 不要做的事

- 不要继续依赖固定 520x520 透明窗口。
- 不要以为 `backgroundColor = .clear` 就能点击穿透。
- 不要让权限请求进入 expanded roster。
- 不要在 permission ping 中渲染完整 `HookApprovalPanel` 的大布局，如果它太高，应拆小版。
- 不要破坏现有 hook、Always 修复、四个审批按钮。

## 9. 推荐下一步执行

下一步实现建议：

1. 修改 `CoveWindowController`，恢复按 `CoveFrameSize` 真实 resize。
2. 初始化窗口为 compact 尺寸。
3. 在 `frameSize` 变化时 snap 到 compact / ping / expanded 尺寸。
4. 将 `pingView` 拆成真正轻量 `PermissionPingCard`。
5. 运行：

```bash
cd /Users/lipu/Work/session-cove
swift build
./scripts/bundle.sh
pkill -x "Session Cove" || true
open ".build/release/Session Cove.app"
```

6. 手动验证点击穿透：
   - compact 旁边点击桌面/App 是否可点击。
   - permission ping 卡片外是否可点击其他应用。
   - expanded 外部点击是否关闭。

## 10. 补充：装饰海岛层必须不拦截点击

日期补充：2026-05-28

用户进一步指出：每个文件夹顶部可以增加一点海岛元素，放在 project/session group 的顶部区域，用来增强像素风格；但这个装饰层不能影响下面具体会话的点击。

这和当前透明窗口拦截问题属于同一类风险：

> 视觉上看似只是装饰，但如果 SwiftUI / AppKit 视图参与 hit testing，就会挡住用户真正想点的 session row 或其他 app。

### 10.1 实现要求

后续新增任何顶部海岛 / 水纹 / 浮标 / 装饰图层，都必须默认：

```swift
.allowsHitTesting(false)
.accessibilityHidden(true)
```

适用对象：

- `IslandHeaderStrip`
- background water texture
- decorative island silhouette
- floating buoy / reef / bubble
- non-interactive mascot shadow
- project card 背景插画

### 10.2 可点击区域必须显式限定

只有这些元素可以接收点击：

- compact bar 本体
- permission card 按钮
- project row / project card 可点击区域
- session row / session card 可点击区域
- Open / Resume / Back 等明确按钮

装饰图层不能隐式覆盖这些元素。

### 10.3 与窗口 hit-test 修复的关系

窗口级别仍然要先解决：

- compact 真实窗口尺寸只包住 compact。
- ping 真实窗口尺寸只包住 ping card。
- expanded 真实窗口尺寸只包住 roster。

视图级别还需要补充：

- 装饰层 `.allowsHitTesting(false)`。
- session rows 的 `.contentShape(Rectangle())` 明确点击区域。
- hover / click 状态放在 session row 上，而不是背景装饰上。

### 10.4 验收标准

- 鼠标点在顶部海岛装饰上，如果不是 project row 的明确点击区域，不应触发错误行为。
- 鼠标点在 session row 上，不应被上方装饰层挡住。
- 鼠标点在窗口外区域，应传给背后的 app。
- 同一 folder 下多个 session 时，所有 session row 都能独立 hover / click。
