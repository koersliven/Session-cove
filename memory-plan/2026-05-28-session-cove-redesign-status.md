# Session Cove 重构计划、进度与记忆

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 当前产品方向

Session Cove 是一个 macOS SwiftUI 菜单栏 / 悬浮面板应用，用像素游戏海湾场景表达 Claude Code 工作状态：

- 工作目录 / 项目 = island
- Claude 会话 = octopus mascot
- 权限请求 = attention / interruption event
- 多会话管理 = dock / roster / badge，而不是把所有 session 都画成完整章鱼

当前重新定义后的核心方向：

> Session Cove 不应该继续做“会话地图 dashboard”，而应该做“会呼吸的像素海湾状态岛”。

关键交互层级：

- overview = awareness：总览只告诉用户哪里有事，不承载全部信息。
- island = project context：岛代表项目，不是所有会话的陈列架。
- crew dock / roster = many sessions：多个会话用码头、头像卡、睡眠舱、数量气泡表达。
- mascot = current / important session：完整章鱼只给当前、活跃或需要注意的会话。
- interruption = permission request：权限请求是最高优先级场景，应该自动进入可决策状态。

完整设计分析见：`docs/interaction-redesign.md`

## 2. 从 ping-island 得到的关键结论

分析对象：`/Users/lipu/Work/ping-island`

ping-island 的核心不是某种具体视觉，而是 attention-first 的产品哲学：

- 默认保持 compact
- 只在 approval、input、intervention、completion 等需要用户注意时展开
- hover / click / notification 有不同 open reason
- 多 session 不全部画出来，而是改变 representation density
- mascot 只是状态演员，不承担整个信息架构
- 浮窗应该轻量，真实 panel 外区域尽量不阻塞点击

Session Cove 应该学习：

1. attention-first hierarchy
2. 明确 UI modes
3. 用 badge / roster / rows / pips 管理多会话复杂度
4. mascot 只突出当前或重要会话
5. 权限请求靠近上下文，立即可决策

Session Cove 不应该直接复制：

- ping-island 的黑色 SaaS 列表 UI
- 纯文本 session rows
- chat/dashboard 视觉语言
- 弱世界观 mascot icon

Cove 要保留像素海湾世界观，但要减少贴纸感和 dashboard 感。

## 3. 用户长期偏好和约束

用户明确偏好：

- 中文沟通为主。
- 不要白底 PNG / sticker 感。
- 要像 coherent pixel-game world，不要普通 SaaS dashboard。
- 可爱但不要过度可爱。
- Claude mascot 是橙色块状像素章鱼，带蓝色耳机。
- mascot 状态包括 working / sleeping / attention / idle。
- 喜欢 Dave the Diver 式水下氛围：珊瑚、水母、海马、海草，但当前程序化海洋生物被认为模糊、扭曲、噪音大。
- 强烈不喜欢视觉元素像贴上去、飘在空中、不接地。
- 权限审批决策必须保持：Deny / Allow / Session / Always。
- 不要继续陷入“章鱼 anchor 微调”，应该重构交互层级。

工程约束：

- 不要影响之前的 hook。
- 保留之前的会话管理。
- 保留唤起 / resume 能力。
- 保留活跃对话检测能力。
- 视觉重构不能破坏 ClaudePermissionHook、SessionWatcher、SessionResumer 等核心能力。

## 4. 已完成的第一轮重构

第一轮目标：先建立新的交互结构，降低拥挤度，不破坏底层能力。

### 4.1 引入明确 UI mode

文件：`SessionCove/Core/CoveViewModel.swift`

新增：

```swift
enum CoveUIMode: Equatable, Sendable {
    case compact
    case harborOverview
    case projectIsland
    case sessionFocus
    case permissionInterruption
}

enum CoveOpenReason: Equatable, Sendable {
    case click
    case hover
    case notification
    case boot
    case unknown
}
```

当前不再只靠 `isExpanded + selectedIsland + selectedSession` 隐式判断 UI 状态。

保留兼容：

```swift
var isExpanded: Bool {
    uiMode != .compact
}
```

### 4.2 保留核心能力

这些能力仍然保留：

- `WindowManager.setup()` 中仍执行 `ClaudePermissionHook.install()`。
- `WindowManager.setup()` 中仍执行 `viewModel.startHookPolling()`。
- `CoveViewModel.startWatching()` 仍通过 `SessionWatcher` 扫描 session。
- `CoveViewModel.rebuildIslands()` 仍根据 `lastModified` 和 `activeThreshold` 检测 active / recentlyIdle / archived。
- `CoveViewModel.resumeSession(_:)` 仍调用 `SessionResumer.resume(session:)`。
- `CoveViewModel.decideHookRequest(_:)` 仍调用 `ClaudePermissionHook.resolve(...)`。
- `HookApprovalPanel` 中 Deny / Allow / Session / Always 保持存在。

### 4.3 compact 入口重做

文件：`SessionCove/UI/Views/CompactBarView.swift`

从普通文字胶囊改为 attention-first 入口：

- 展示 lead octopus。
- pending permission 时 mascot 进入 `.attention`。
- 中心文字根据状态显示：
  - `APPROVAL · TOOLNAME`
  - `CODING · PROJECT`
  - `N SESSIONS IN COVE`
  - `SESSION COVE`
- 右侧 badge 显示 `!`、active count 或 island count。
- 点击 pending permission 时进入 `.permissionInterruption`。
- 非 pending 状态点击仍 toggle 展开。

### 4.4 新增权限打断场景

新增文件：`SessionCove/UI/Views/PermissionInterruptionView.swift`

作用：

- pending permission 时进入专门 interruption scene。
- 左侧显示相关 project island、attention mascot、project/session context。
- 右侧复用 `HookApprovalPanel`，保留 Deny / Allow / Session / Always。
- 提供 `OPEN ACTIVE SESSION` / `RESUME SESSION` 操作，继续走 `viewModel.resumeSession(session)`。
- 不替换 hook 数据流，只是更改呈现层。

### 4.5 CoveRootView 按 UI mode 分发

文件：`SessionCove/UI/Views/CoveRootView.swift`

现在 expanded view 根据 `viewModel.uiMode` 切换：

- `.compact` -> `CompactBarView`
- `.harborOverview` -> `CoveMapView`
- `.projectIsland` -> `IslandSessionListView`
- `.sessionFocus` -> `SessionDetailView`
- `.permissionInterruption` -> `PermissionInterruptionView`

### 4.6 主地图降低拥挤度

文件：`SessionCove/UI/Views/ProjectIslandView.swift`

调整：

- 每个 project island 只展示 1 个 lead mascot。
- 其他 session 用 `+N` crew badge 表达。
- pending permission 时 lead mascot 进入 attention 状态。
- `PixelAttentionRing` 从 private 改为 internal，供 `PermissionInterruptionView` 复用。

这一步解决了主地图每岛多个章鱼造成的贴纸堆问题。

### 4.7 项目详情降低拥挤度

文件：`SessionCove/UI/Views/IslandSessionListView.swift`

调整：

- 文案从 `BASE / N SESSION OCTOPUSES` 改为 `PROJECT BASE / N CREW SLOTS`。
- 岛上最多展示 3 个 featured mascots。
- 其他 session 进入 `+N AT DOCK` badge。
- 底部 session cards / dock 仍保留，且每张卡仍可 `OPEN` / `GO`。
- session 选择仍进入 `viewModel.selectSession(session)`。

## 5. 已验证状态

已运行：

```bash
cd /Users/lipu/Work/session-cove
swift build
./scripts/bundle.sh
pkill -x "Session Cove" || true
open ".build/release/Session Cove.app"
```

结果：

- `swift build` 成功。
- app bundle 生成成功。
- 旧实例已关闭。
- 新版应用已启动。

第一轮中间出现过一次 Swift 类型推断错误，已修复后复跑构建通过。

## 6. 当前待注意问题

### 6.1 `CoveMapView` 仍保留旧 permission panel

当前 `CoveMapView` 里仍有右下角旧 `HookApprovalPanel` fallback。

下一轮建议：

- 移除主地图右下角旧 permission panel；或
- 仅作为 debug fallback 保留；或
- 在 `.harborOverview` 下改成小型 notification beacon，不再显示完整审批面板。

原因：现在已有 `PermissionInterruptionView`，旧 panel 会造成重复信息层级。

### 6.2 `SessionDetailView` 仍像普通表单页

当前 session detail 还没有重构为 agent room / captain log。

下一轮重点应该改这里。

### 6.3 hover preview 尚未实现

虽然已经有 `CoveOpenReason.hover`，但 hover preview 还没有实际 UI。

可以后置，不影响第二轮主线。

### 6.4 floating panel pass-through 还未处理

`CovePanel` 仍是普通 borderless nonactivating panel，尚未做类似 ping-island 的 precise hit region / pass-through hosting view。

这个应该在 interaction polish 阶段做，不要抢第二轮主线。

### 6.5 海洋生物仍可能显得噪音大

`PixelSeaLifeLayer` 仍保留程序化 reef / kelp / jellyfish / seahorse / fishSchool。

建议后续降低出现频率、透明度，或先移除低质量元素。

## 7. 第二轮建议计划

第二轮目标：把“会话详情”和“权限上下文”做成真正的 agent room / captain log，并清理重复 permission UI。

建议顺序：

### Step 1：清理重复 permission UI

文件：`SessionCove/UI/Views/CoveMapView.swift`

目标：

- 不再在 harbor overview 右下角显示完整 `HookApprovalPanel`。
- pending request 时，harbor 只负责突出相关 island / beacon。
- 真正审批进入 `.permissionInterruption`。

风险控制：

- 不改 `HookApprovalPanel` 本身。
- 不改 `ClaudePermissionHook`。
- 不改 `decideHookRequest`。

### Step 2：重构 SessionDetailView 为 Agent Room / Captain Log

文件：`SessionCove/UI/Views/SessionDetailView.swift`

目标视觉：

- 像素 HUD + 船舱 / 控制室 / captain log。
- mascot 是当前 agent avatar，不再只是装饰。
- 信息分区：
  - 当前状态：working / idle / sleeping / attention
  - topic / title
  - project path
  - session id
  - last active
  - active/recent/archive 状态
  - resume/open terminal 操作
- 如果当前 session 对应 pending permission，直接显示审批 HUD。

必须保留：

- `viewModel.resumeSession(session)`。
- `viewModel.back()`。
- session metadata 展示。
- pending permission 决策仍走 `HookApprovalPanel`。

### Step 3：让 PermissionInterruptionView 更清晰

文件：`SessionCove/UI/Views/PermissionInterruptionView.swift`

可以增强：

- 展示 request summary / tool / project path 更清楚。
- 如果找不到 matching session，不要误导，只显示 project context。
- 决策后根据 previous mode 回到合理页面。

### Step 4：补足 UI mode 的导航一致性

文件：`SessionCove/Core/CoveViewModel.swift`

可以增强：

- 记录 `previousModeBeforeInterruption`。
- permission 决策后回到 previous mode，而不是简单 harbor/project/session。
- 为 hover preview 留入口，但不急着完整实现。

### Step 5：构建、打包、启动验证

命令：

```bash
cd /Users/lipu/Work/session-cove
swift build
./scripts/bundle.sh
pkill -x "Session Cove" || true
open ".build/release/Session Cove.app"
```

验收：

- 构建通过。
- app 能启动。
- compact 点击正常。
- harbor overview 正常。
- project drill-in 正常。
- session focus 正常。
- resume/open 按钮仍存在。
- pending permission 仍可 Deny / Allow / Session / Always。

## 8. 不要做的事

第二轮不要做：

- 不要改 ClaudePermissionHook 的协议和文件路径。
- 不要改 `~/.claude/settings.json` hook 注册逻辑。
- 不要删除 SessionWatcher。
- 不要删除 SessionResumer。
- 不要把 Deny / Allow / Session / Always 改名或减少。
- 不要继续大规模调 mascot anchor。
- 不要继续增加低质量 sea life。
- 不要把 Cove 改成纯列表 dashboard。

## 9. 关键文件索引

设计文档：

- `docs/interaction-redesign.md`

核心状态：

- `SessionCove/Core/CoveViewModel.swift`

窗口和启动：

- `SessionCove/App/WindowManager.swift`
- `SessionCove/UI/Window/CovePanel.swift`
- `SessionCove/UI/Window/CoveWindowController.swift`

主要 UI：

- `SessionCove/UI/Views/CoveRootView.swift`
- `SessionCove/UI/Views/CompactBarView.swift`
- `SessionCove/UI/Views/CoveMapView.swift`
- `SessionCove/UI/Views/ProjectIslandView.swift`
- `SessionCove/UI/Views/IslandSessionListView.swift`
- `SessionCove/UI/Views/SessionDetailView.swift`
- `SessionCove/UI/Views/PermissionInterruptionView.swift`

权限和 hook：

- `SessionCove/UI/Components/HookApprovalPanel.swift`
- `SessionCove/Services/Hooks/ClaudePermissionHook.swift`

会话能力：

- `SessionCove/Services/SessionWatcher.swift`
- `SessionCove/Services/SessionResumer.swift`
- `SessionCove/Models/SessionRecord.swift`
- `SessionCove/Models/ProjectIsland.swift`

像素组件：

- `SessionCove/UI/Components/PixelArtSprites.swift`
- `SessionCove/UI/Components/AnimatedMascot.swift`
- `SessionCove/UI/Components/MascotImage.swift`

## 10. 推荐接续语境

如果下一个会话继续做第二轮，可以直接从这里开始：

> 继续 Session Cove 第二轮重构。先读 `memory-plan/2026-05-28-session-cove-redesign-status.md` 和 `docs/interaction-redesign.md`。不要破坏 hook、session watcher、resume、active detection。优先清理 `CoveMapView` 旧 permission panel，然后把 `SessionDetailView` 改成 agent room / captain log。最后运行 `swift build`、bundle 并打开应用。
