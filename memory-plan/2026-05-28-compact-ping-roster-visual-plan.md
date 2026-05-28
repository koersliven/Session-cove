# Session Cove Compact / Permission Ping / Harbor Roster 视觉与交互方案

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 当前问题判断

当前第三轮实现方向整体正确：

- 默认展开从 full harbor map 转向 `HarborRosterView`。
- 修复了 `Always` 权限持久化方向。
- 引入了 compact / ping / expanded 这种更接近动态岛的小工具形态。

但当前视觉和交互仍有几个明显问题：

### 1.1 Compact bar 仍然像矩形，有裁切残留

当前 `CoveWindowController` 使用固定大面板承载所有状态。即使 compact 内容本身是 `300x50`，外层透明面板仍可能产生矩形残留、阴影污染或裁切边缘感。

这会让用户觉得：

> 不是一个真正的 dynamic island，而是一个大透明窗口里放了一个小矩形。

### 1.2 白底 mascot 不能直接进 UI

白底 PNG 的 alpha 不为 0，`MascotImage.loadCropped` 只能按 alpha 裁剪，无法自动去掉白色背景。

结果：

- 公仔像贴纸一样贴在深色 compact bar 上。
- 破坏像素世界感。
- 和用户希望的 ping-island / Dave-style 工具感不一致。

结论：

> UI 中必须使用透明背景 mascot。白底图只能作为生成参考或素材预览，不应该用于产品界面。

### 1.3 权限申请不应该放大到主页面

权限请求应像 ping-island 的轻量审批条 / dynamic-island ping，而不是打开完整主界面。

用户希望：

- 不打断工作流。
- 不把软件放大成完整窗口。
- 直接知道 tool / project / command。
- 直接点 Deny / Allow / Session / Always。

### 1.4 像素风要更工具化，不能太萌

当前方向应避免：

- 过度可爱。
- 大眼萌。
- plush toy。
- 白底贴纸。
- 噪音过多的海洋生物。

应更接近：

- ping-island 的克制小工具感。
- Dave the Diver 的清晰层级和深海氛围。
- Slock 类小型效率工具的直接、轻量、快速操作。

## 2. 推荐最终交互结构

建议 Session Cove 收敛为三层结构。

### Layer 1：Compact Pixel Notch

常驻状态。

目标：

- 一眼知道 Claude Code 有没有事。
- 不像普通矩形 app。
- 不占屏、不抢焦点。

推荐尺寸：

- 宽：`280-340`
- 高：`44-52`

内容：

```text
[octopus] CODING · project-name      [2]
```

或 pending permission：

```text
[! octopus] APPROVAL · Bash          [!]
```

视觉建议：

- 不用系统 `Capsule`，改成 pixel notch / stepped capsule。
- 角落用像素台阶，而不是连续圆角。
- 1px 深色外边 + 1px 高光内边。
- 深海蓝 / 墨蓝为主。
- 状态色只在小区域出现。
- mascot 使用透明 PNG 或程序化 sprite，绝不使用白底图。

### Layer 2：Permission Ping Card

收到权限请求时出现。

目标：

- 像系统通知 / dynamic-island 扩展。
- 不进入主页面。
- 不渲染 harbor / map / sea life。

推荐尺寸：

- 宽：`320-380`
- 高：`150-220`

结构：

```text
┌──────────────────────────────┐
│ 🐙 APPROVAL · Bash            │  compact notch
└──────────────────────────────┘
       ┌────────────────────┐
       │ Bash wants access   │
       │ npm install ...     │
       │                    │
       │ Deny Allow Session │
       │ Always             │
       └────────────────────┘
```

内容：

- tool name
- project name
- command/path 摘要
- 四个按钮：Deny / Allow / Session / Always
- 可选 attention mascot

关键要求：

- 不打开完整 expanded view。
- 不改变成 520x520 或 1040x700 大窗。
- 用户点完后立即收回。
- 决策仍走 `CoveViewModel.decideHookRequest` 和 `ClaudePermissionHook.resolve`。

### Layer 3：Harbor Roster

用户主动点击 compact 时打开。

目标：

- 代替 full harbor map 成为默认主界面。
- 清楚列出项目和会话状态。
- 保留 Cove 像素氛围，但不要让用户“找”。

推荐尺寸：

- 宽：`500-620`
- 高：按内容动态，最多 `480-520`

结构：

```text
SESSION COVE        3 ACTIVE
────────────────────────────
● session-cove       2 sessions
  └ working on UI refactor       now
  └ idle captain log             5m

○ ping-island        1 session
  └ analysis notes               1h
```

视觉建议：

- 像素 HUD / command palette / dock manifest。
- 每行使用小透明 mascot 或状态点。
- active 使用青绿光点。
- permission 使用琥珀灯。
- 背景只保留低对比水纹 / scanline / 小气泡。
- 不渲染完整 `PixelSeaLifeLayer`。
- 不布局 6 个大岛。

## 3. 透明 mascot 资源方案

目标生成并替换四态 PNG：

- `claude_working.png`
- `claude_sleeping.png`
- `claude_attention.png`
- `claude_idle.png`

风格要求：

- 透明背景。
- 橙色 / 珊瑚橙块状像素章鱼。
- 深蓝色耳机。
- 成熟克制，不卖萌。
- 不要大眼萌。
- 不要 plush toy。
- 不要白底。
- 不要文字、logo、水印、边框。
- 小尺寸下仍清晰。
- 适合深色 macOS compact bar。

四态定义：

### working

- 专注工作。
- 身体略微前倾。
- 触手像在操作终端 / 键盘。
- 可有极少量蓝色状态像素。

### sleeping

- 呼呼大睡。
- 身体侧躺或蜷缩。
- 眼睛闭合。
- 少量克制 Z / 呼吸气泡。
- 不要过萌。

### attention

- 权限请求 / 需要用户注意。
- 身体稍微挺直。
- 琥珀色提示灯或小像素感叹号。
- 警觉但不夸张。

### idle

- 中性站立或轻微漂浮。
- 冷静友好。
- 放松但不卖萌。

## 4. 技术改造建议

### 4.1 窗口尺寸不要固定大画布

优先方案：按 mode 精确设置 NSPanel 尺寸。

推荐：

- compact：`300x50`
- ping：`380x220`
- expanded：`560x500`

原因：

- 最干净。
- 避免透明大画布残留。
- 不需要复杂 pass-through hitTest。
- 现在 full harbor map 已经不作为默认界面，resize 成本可接受。

备选方案：固定大窗口 + pass-through hosting view。

但这需要：

- 自定义 `PassThroughHostingView`。
- 只让实际内容区域 hitTest。
- root 背景完全 clear。
- shadow 不能污染透明区域。

复杂度更高，不建议优先做。

### 4.2 compact / ping 不使用白底图

短期：

- 继续用 `PixelOctopusSprite` 或替换为透明 PNG。

中期：

- `MascotImage` 增加四态：working / sleeping / attention / idle。
- `PixelOctopusSprite` 根据 state 选择对应 PNG。
- 如果 PNG 缺失，fallback 到程序化 sprite。

### 4.3 PermissionPingCard 拆出独立组件

不要复用大卡片式 `PermissionInterruptionView`。

新增建议：

- `PermissionPingCard.swift`
- 可复用 `HookApprovalPanel` 的决策逻辑，但布局要更小。
- 展示 tool/project/summary/button。

### 4.4 HarborRoster 美化

当前信息方向是对的，下一步重点是视觉：

- 改成 pixel command palette。
- row hover 高亮像终端选择器。
- active 状态用小光点。
- permission 状态用 amber beacon。
- 背景低噪音，不使用高复杂海洋生物。

## 5. 推荐执行顺序

1. 生成并替换透明四态 mascot PNG。
2. 修改 `MascotImage` / `PixelOctopusSprite`，支持四态 PNG + fallback。
3. 窗口恢复按 mode 精确尺寸：compact / ping / expanded。
4. 将 permission UI 改成真正的小 `PermissionPingCard`。
5. 美化 `HarborRosterView`。
6. 构建验证：

```bash
cd /Users/lipu/Work/session-cove
swift build
./scripts/bundle.sh
pkill -x "Session Cove" || true
open ".build/release/Session Cove.app"
```

## 6. 不要做的事

- 不要再把白底公仔放进 UI。
- 不要为了权限请求展开完整主界面。
- 不要默认渲染 full harbor map。
- 不要继续增加粗糙海洋生物。
- 不要把 mascot 做得过萌。
- 不要破坏 hook、SessionWatcher、SessionResumer、active detection。
- 不要改 Deny / Allow / Session / Always 四个决策。

## 7. 补充：同文件夹多会话展示层与顶部海岛元素

日期补充：2026-05-28
来源：用户基于最新截图提出的新问题。

### 7.1 当前新问题

用户指出：当前一个文件夹下可能有 3 个 Claude 对话 / session，但 UI 需要一个更明确的展示层来引导用户可以点击这些对话。

也就是说，`HarborRosterView` 不应该只是把 session 文本列出来，而应该在同一个 project / folder 下形成一个清楚的“会话展示层”：

- 用户一眼知道这个文件夹下面有几个对话。
- 每个对话都应该看起来可点击。
- active / idle / sleeping / attention 状态要清楚。
- 不要让用户猜哪里能点。
- 不要依赖完整大地图来表达多会话。

### 7.2 推荐设计：Project Row + Session Strip

对于一个文件夹 / project，推荐改成两层：

```text
┌──────────────────────────────────────┐
│  pixel island header / project name   │
│  session-cove                3 chats  │
├──────────────────────────────────────┤
│ [🐙 working] UI refactor       now     │
│ [🐙 idle]    Captain log       5m      │
│ [🐙 sleep]   Old session       1h      │
└──────────────────────────────────────┘
```

关键点：

- project 层负责“这是哪个文件夹”。
- session strip / session rows 负责“这个文件夹下有哪些可点击会话”。
- 每个 session row / card 都应该有明确 hover 高亮和点击反馈。
- `3 chats` / `3 sessions` badge 必须明显。
- 当前活跃会话放第一位。
- pending permission 会话置顶，并用 amber attention 状态突出。

### 7.3 顶部海岛元素：只做装饰层，不拦截会话点击

用户希望每个文件夹的展示方式在顶部区域加一点海岛元素，对应截图第二张图顶部那块区域。

推荐做法：

- 在 project row 顶部放一个低高度的 `IslandHeaderStrip`。
- 高度约 `44-72px`，不要太高。
- 内容可以是：
  - 小岛剪影
  - 小码头
  - 小旗帜
  - 水纹 / 浮标
  - project 状态灯
- 这个顶部海岛元素只承担“项目氛围”和“文件夹分组”的视觉职责。
- 它不能遮挡下面具体 session row 的点击。
- 它不能成为新的 full map。

实现原则：

```swift
ZStack(alignment: .top) {
    IslandHeaderStrip(...)
        .allowsHitTesting(false)
    VStack {
        ProjectHeader(...)
        SessionRows(...)
    }
}
```

或者：

```swift
IslandHeaderStrip(...)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
```

关键要求：

- 所有装饰层默认 `.allowsHitTesting(false)`。
- 只有 session row、button、project row 本身可以点击。
- 装饰层不参与 hover，不拦截 mouse event。
- 如果海岛元素上未来要有可点击按钮，必须单独做小 hit target，不要让整块 header 可点击。

### 7.4 顶部海岛元素的视觉边界

不要回到之前 full harbor map 的问题。顶部海岛元素应该是轻量的。

推荐：

- 低对比。
- 小面积。
- 不使用复杂 sea life。
- 不放多个完整大章鱼。
- 每个 project 最多一个 lead mascot 或小状态灯。
- 更多 session 用 session rows 表达，而不是堆在岛上。

禁止：

- 每个文件夹 row 顶部都画复杂大岛。
- 顶部海岛遮挡 session rows。
- 让海岛装饰层成为鼠标事件拦截层。
- 把 3 个 session 全部画成岛上的大章鱼。

### 7.5 同文件夹 3 个对话的推荐交互

对于一个 folder 下有 3 个 session：

1. Project row 显示：`project name + 3 sessions + active count`。
2. 顶部 `IslandHeaderStrip` 只做文件夹氛围。
3. 下方展示 3 个 session row/card：
   - 透明四态 mascot 小图标。
   - session title / latest message summary。
   - last active time。
   - status badge。
   - Open / Resume 操作。
4. hover 某个 session 时：
   - row 背景高亮。
   - mascot 稍微亮起或切状态。
   - 不移动整个 island header。
5. 点击 session 时进入 `SessionDetailView / Captain Log`。

### 7.6 新生成透明 PNG 必须纳入改造计划

本轮已经生成并替换了四态透明 PNG：

- `SessionCove/Resources/claude_working.png`
- `SessionCove/Resources/claude_sleeping.png`
- `SessionCove/Resources/claude_attention.png`
- `SessionCove/Resources/claude_idle.png`

并且已同步：

- `Package.swift` resource 列表。
- `MascotImage.working / sleeping / attention / idle`。
- `PixelOctopusSprite` 的状态映射。

后续所有 compact、permission ping、HarborRoster、SessionDetail 的 mascot 展示，必须优先引用这四张透明 PNG。

后续禁止重新使用白底图作为 UI 资源。白底图只允许作为参考图或文档预览。

### 7.7 建议新增组件

建议后续实现新增：

- `IslandHeaderStrip.swift`
  - 输入：`ProjectIsland`、状态、session count。
  - 输出：轻量像素岛屿装饰条。
  - 默认 `.allowsHitTesting(false)`。

- `ProjectSessionGroupView.swift`
  - 输入：`ProjectIsland`。
  - 输出：project header + island header strip + session rows。
  - 管理同文件夹多个 session 的展示和点击。

- `SessionRosterRow.swift`
  - 输入：`SessionRecord`。
  - 输出：透明 mascot + title + status + time + open/resume。
  - 明确 hover / selected / attention 样式。

### 7.8 更新后的 HarborRoster 目标

`HarborRosterView` 不再只是项目列表，也不是 full harbor map。它应该是：

> Pixel dock manifest：每个文件夹是一张小岛档案卡，每个对话是一条可点击的 crew/session row。

验收标准：

- 一个文件夹下 3 个对话时，用户不用思考就知道有 3 个可点项。
- 顶部海岛元素增加像素氛围，但不会拦截 session rows 点击。
- 透明四态 mascot 正常显示，无白底贴纸感。
- active / idle / sleeping / attention 状态清晰。
- 点击任意 session row 进入 Captain Log。
