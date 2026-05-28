# Session Cove 一级岛屿地图与二级比例纠偏计划

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`
来源：用户最新截图与反馈；当前 `HarborRosterView` / `IslandSessionListView` / `ProjectIslandView` 代码复核

## 1. 本轮用户目标

用户明确指出：当前二级页面这种海岛场景方向是好看的，希望一级页面也能采用这种风格，但仍保持 ping-island 式一级菜单的轻量、高效、不卡顿。

目标可以概括为：

1. **一级页面改成岛屿地图**：不是黑色 roster，也不只是横向 island shelf；要能看到多个项目岛分布在海面上。
2. **保留一级菜单效率**：像 ping-island 一样快速扫项目、快速选中、快速进入，不做重动画、不做复杂大地图。
3. **选中/运行状态高亮**：有会话未关闭、正在 run、或被选中的岛屿要高亮。
4. **底部展示选中岛屿中的会话**：像当前二级页面底部 dock 一样展示会话卡片，默认最多展示 8 个，支持左右滑动；超过 8 个默认隐藏/摘要，不一次性渲染太多。
5. **修正二级页面比例**：当前二级页章鱼比岛还大，岛被遮住；需要重新定义岛屿、章鱼、底部会话栏的尺寸关系。

## 2. 当前代码与视觉问题

### 2.1 当前一级页面仍是 list/shelf，而不是岛屿地图

当前 `HarborRosterView` 已经使用了 `ProjectIslandShelfView`：

```swift
LazyVStack(spacing: 10) {
    ForEach(sortedIslands) { island in
        ProjectIslandShelfView(...)
    }
}
```

这比黑色矩形列表有进步，但仍不是用户想要的“岛屿地图”。用户现在明确倾向：一级页面应该像二级页面那样是海面里的岛，而不是纵向项目栏。

结论：上一份 `ProjectIslandShelf` 方案需要升级为 **HarborMapOverview**：一级是轻量岛屿地图，底部是选中岛屿会话 dock。

### 2.2 当前二级页面视觉方向对，但比例失衡

`IslandSessionListView` 当前结构：

```swift
ZStack {
    PixelOceanBackground()
    VStack(spacing: 0) {
        header
        projectBase
        sessionDock
    }
}
```

这是正确方向。

但在 `projectBase` 中：

```swift
PixelIslandSprite(mood: baseMood)
    .frame(width: islandFrame.width, height: islandFrame.height)

ForEach(Array(featuredSessions.prefix(3).enumerated())) { ...
    GroundedMascot(... size: isHovered ? 60 : 48 ...)
}
```

而 `baseIslandFrame`：

```swift
let width = min(size.width * 0.72, 820)
let height = min(size.height * 0.50, 320)
```

在当前 520x480 左右的窗口内，扣掉 header 和 dock 后，projectBase 实际高度有限，岛屿高度可能并不大；多个 48-60px 的 mascot 叠在岛上，就会显得章鱼比岛大，甚至盖住岛。

### 2.3 `ProjectIslandView` 中也存在比例风险

`ProjectIslandView` 中：

```swift
PixelIslandSprite(mood: mood)
    .frame(width: 410 * scale, height: 200 * scale)

GroundedMascot(... size: 48 * scale ...)
```

理论比例是 mascot 高度约为岛高度的 24%，还能接受。但如果 island sprite 本身有效可见区域偏小，或者 mascot 资源实际视觉高度接近 frame 高度，就会看起来过大。

新的比例规则不能只看 frame，要看视觉占比。

## 3. 新方向：一级页面改为轻量 HarborMapOverview

### 3.1 不是 full-screen 大地图，而是 ping-island 式“迷你岛屿地图”

一级页面窗口尺寸仍建议保持当前 expanded 尺寸附近，例如 `520x480`。不要为了地图变成全屏或大窗口。

布局建议：

```text
+------------------------------------------------+
| compact-like header / harbor sign              |  48-56px
|------------------------------------------------|
|                                                |
|          island A        island B              |
|                                                |  250-290px
|     island C       selected island D           |
|                                                |
|------------------------------------------------|
| selected island session dock                   |  118-140px
| [session][session][session] ... max 8 visible  |
+------------------------------------------------+
```

核心是：

- 中间是项目岛地图。
- 底部是选中岛屿的 session dock。
- 不选中时默认选 activeCount 最高/最近的岛。
- 这保留了 ping-island 的一级菜单效率：打开一级后直接看到项目概况和当前最重要项目的会话。

### 3.2 一级页面的信息架构

一级页面的层级：

1. Header：应用名、active project/session 总数、关闭按钮。
2. Map area：最多优先展示若干项目岛，按重要性排序。
3. Selected island label：选中岛名、路径、session 数。
4. Bottom session dock：选中岛屿的会话，默认最多 8 个，横向滑动。

不再使用纵向项目列表作为主结构。

### 3.3 岛屿数量与密度

为了性能和可读性：

- 默认地图区最多显示 **6 个项目岛**。
- 如果项目超过 6 个，显示前 5 个 + 一个 `+N MORE` 小礁石/浮标入口。
- 排序优先级：
  1. 有 pending permission 的项目。
  2. activeCount > 0 的项目。
  3. recently idle 的项目。
  4. 最近修改时间。
- 进入 `+N MORE` 可以暂时展开为紧凑列表或分页地图，但第一版不必做复杂分页。

这能保证一级页面不卡、不乱、不变成密密麻麻的图标地图。

### 3.4 岛屿布局方案：固定锚点，避免运行时复杂 packing

为了性能最优，不要在一级页面做力导向布局或复杂 collision relaxation。

使用固定 anchor slots：

```swift
let mapSlots = [
    CGPoint(x: 0.28, y: 0.34),
    CGPoint(x: 0.68, y: 0.30),
    CGPoint(x: 0.48, y: 0.54),
    CGPoint(x: 0.22, y: 0.70),
    CGPoint(x: 0.76, y: 0.68),
    CGPoint(x: 0.50, y: 0.82)
]
```

每个岛根据状态选择大小：

| 岛类型 | 建议尺寸 | 场景 |
|---|---:|---|
| selected | 150-170w x 82-96h | 当前选中岛 |
| active | 132-150w x 72-86h | 有 running/open session |
| recent | 118-132w x 64-76h | 最近活跃 |
| archived | 96-112w x 52-64h | 归档/冷项目 |
| more | 70-86w x 44-52h | `+N MORE` |

### 3.5 选中与运行状态高亮

状态表现：

| 状态 | 岛屿表现 |
|---|---|
| selected | 泡沫描边 + 轻微上浮 + 底部 label 连接线 |
| active/running | 草地更亮 + 小绿灯/营火 + 1-2 个工作 pips |
| permission pending | 黄色 beacon/旗帜 + amber pixel ring |
| recent idle | 普通沙洲 + 暖色小灯 |
| archived | 更小、更暗、偏蓝灰 |

注意：高亮要克制，不能让所有岛都发光。一级页面只能有一个 selected 主高亮。

## 4. 底部会话 dock 设计

### 4.1 默认展示选中岛屿的会话

底部 dock 的内容跟随 selected island：

- 默认选中 pending/active/最近项目。
- 用户点击地图中的岛后，底部 dock 切换到该岛 session。
- session 仍可点击进入 session focus。
- session card 上保留 resume/open 操作。

### 4.2 最多 8 个会话，支持横向滑动

用户要求：默认最多展示 8 个，支持左右滑动，多了隐藏。

建议解释为：

- 数据层只取排序后的前 8 个用于 dock。
- UI 用 `ScrollView(.horizontal)` + `LazyHStack`。
- 如果该岛 session 超过 8 个，末尾显示 `+N hidden` 卡片，而不是继续渲染更多。
- 第一版不提供无限滚动，避免性能问题。

伪代码：

```swift
let dockSessions = selectedIsland.sessions
    .sorted(by: sessionPriority)
    .prefix(8)

ScrollView(.horizontal, showsIndicators: false) {
    LazyHStack(spacing: 8) {
        ForEach(dockSessions) { session in
            HarborSessionDockCard(session: session)
        }
        if selectedIsland.sessions.count > 8 {
            HiddenSessionsCard(count: selectedIsland.sessions.count - 8)
        }
    }
}
```

### 4.3 dock card 尺寸

在 520px 宽窗口内：

- card 宽度：`150-170px`。
- card 高度：`86-104px`。
- 同屏可见约 2.7-3.2 个，横滑看更多。
- 不要把 8 个强行挤在同屏，否则信息不可读。

### 4.4 session 排序

排序优先：

1. active / running。
2. pending permission 相关。
3. recently idle。
4. lastModified 新。
5. archived。

## 5. 二级页面比例修正

### 5.1 目标比例

二级页面中，岛应该是主舞台，章鱼是岛上的角色，不能反客为主。

建议视觉比例：

| 元素 | 相对 island visual height |
|---|---:|
| 单个主 mascot | 18%-22% |
| hover/attention mascot | 不超过 25% |
| 多 mascot 场景 | 每个 16%-20% |
| badge / flag | 不超过 10%-14% |

如果二级岛有效可见高度约 180px，那么 mascot 高度建议：

- normal：34-40px。
- hover/attention：42-46px。
- 不建议 60px。

### 5.2 当前代码应调整的点

`IslandSessionListView.sessionMascot` 当前：

```swift
GroundedMascot(
    size: isHovered ? 60 : 48,
    ...
)
.frame(width: 74, height: 74)
```

建议改为：

```swift
let mascotSize = isHovered ? 44 : 38
GroundedMascot(... size: mascotSize ...)
    .frame(width: 58, height: 58)
```

或者按岛高动态计算：

```swift
let mascotSize = min(isHovered ? 46 : 40, islandFrame.height * 0.22)
```

### 5.3 岛屿应变大/更靠上，给底部 dock 留稳定空间

当前 `baseIslandFrame`：

```swift
width = min(size.width * 0.72, 820)
height = min(size.height * 0.50, 320)
y = size.height * 0.54 - height / 2
```

建议：

- 宽度：`min(size.width * 0.82, 860)`。
- 高度：`min(size.height * 0.56, 330)`。
- y：略上移，`size.height * 0.49 - height / 2`。

这样岛更像舞台，章鱼不再遮住核心岛形。

### 5.4 mascot anchor 下移要谨慎

不要为了让章鱼“站在岛上”继续盲目调 anchor。问题不是 anchor 一点点偏差，而是整体比例：

- 先缩小 mascot。
- 再增大岛。
- 最后微调 anchor。

如果继续只调 anchor，会反复出现“站不住/遮岛/漂浮”的局部修修补补。

## 6. 性能约束

一级岛屿地图必须轻量：

1. 只渲染前 6 个项目岛。
2. 底部 dock 只渲染前 8 个 session + hidden card。
3. 使用固定 anchors，不做动态碰撞算法。
4. 水纹/泡沫用少量静态 Canvas，不做持续动画。
5. 只给 selected / pending / active 少量动画，且动画不超过 opacity/scale/offset。
6. 避免 TimelineView、粒子、复杂 shader。
7. `LazyHStack` 用于底部横滑 dock。
8. 如果项目/会话数量很多，不在一级一次性创建所有复杂 view。

## 7. 新组件建议

建议新建/重构：

```text
SessionCove/UI/Views/HarborMapOverviewView.swift
SessionCove/UI/Components/MapProjectIslandNode.swift
SessionCove/UI/Components/HarborMapLayout.swift
SessionCove/UI/Components/HarborSessionDock.swift
SessionCove/UI/Components/HarborSessionDockCard.swift
SessionCove/UI/Components/HiddenSessionsCard.swift
```

职责：

- `HarborMapOverviewView`：替代当前 `HarborRosterView` 的主要 UI。
- `MapProjectIslandNode`：地图里的单个项目岛。
- `HarborMapLayout`：固定 slot 和排序逻辑。
- `HarborSessionDock`：底部横滑会话栏。
- `HarborSessionDockCard`：单个会话卡片。
- `HiddenSessionsCard`：超过 8 个后的摘要入口。

## 8. 状态管理建议

`CoveViewModel` 需要轻量保存一级选中岛：

```swift
var highlightedIslandID: ProjectIsland.ID?
```

默认选择逻辑：

```swift
pendingIsland ?? activeIsland ?? mostRecentIsland ?? firstIsland
```

点击岛屿：

- 第一次点击：更新 `highlightedIslandID`，底部 dock 切换。
- 双击或点击岛上 `OPEN`：进入 `.projectIsland` 二级页面。

为了保持 ping-island 快速性，也可以：

- 单击岛：选中。
- 单击底部 dock session：进入 session。
- 岛 label/箭头按钮：进入二级项目页。

这样避免误触导致页面跳转过重。

## 9. 与现有架构的关系

保留：

- compact bar。
- permission ping card。
- `.harborOverview` 作为一级页面 mode。
- `.projectIsland` 作为二级页面 mode。
- `.sessionFocus` 作为三级页面 mode。
- hook / session resume / Deny Allow Session Always。

替换：

- `.harborOverview` 下的 `HarborRosterView` 视觉主体。
- `ProjectIslandShelfView` 可以保留为 fallback / compact list / more panel，但不再作为一级默认主视觉。

## 10. 分阶段实施计划

### P0：先修二级比例

目的：当前用户已经认可二级页面风格，但比例明显错。先把章鱼和岛关系修正，避免继续在错误比例上扩展一级地图。

步骤：

1. 调整 `IslandSessionListView.baseIslandFrame`：岛更大、更靠上。
2. 调整 `sessionMascot`：normal 约 38-40px，hover/attention 约 44-46px。
3. 调整 mascot anchors，仅做最后微调。
4. 确认底部 dock 不遮挡岛。

验收：

- 岛是主舞台，章鱼站在岛上而不是盖住岛。
- 章鱼不超过岛视觉高度 25%。
- 二级页面仍然好看。

### P1：实现一级 HarborMapOverview 基础版

步骤：

1. 新增 `HarborMapOverviewView`。
2. 中间地图区使用 `PixelOceanBackground` 或轻量版本。
3. 取前 6 个项目，按固定 slots 布局。
4. 每个项目用 `MapProjectIslandNode` 显示岛、名字、active count、pending beacon。
5. 点击岛只选中，不直接跳转。
6. 底部显示 selected island 的 session dock。

验收：

- 一级页面一眼是岛屿地图。
- active / selected / pending 岛有明确高亮。
- 打开不卡顿。

### P2：底部 session dock 完成

步骤：

1. `HarborSessionDock` 横向滚动。
2. 默认只取前 8 个 session。
3. 超过 8 个显示 `+N hidden`。
4. session card 点击进入 session focus 或 resume。
5. 保持 card 尺寸稳定，避免横向布局抖动。

验收：

- 选中不同岛，底部 dock 正确切换。
- 8 个以内可横滑查看。
- 超过 8 个不会一次性渲染一堆卡片。

### P3：进入二级页面交互

步骤：

1. 给 selected island 增加 `OPEN ISLAND` 或小箭头入口。
2. 或支持双击岛进入 `.projectIsland`。
3. 保留底部 session 直接进入 session 的快速路径。

验收：

- 一级页面既能快速看 session，也能进入二级岛详情。
- 不会因为单击岛就频繁跳页面。

### P4：视觉 polish

步骤：

1. selected 岛泡沫描边。
2. active 岛小绿灯/营火。
3. pending 岛 amber beacon。
4. very subtle hover scale。
5. more island/reef 入口。

验收：

- 像游戏海岛地图，但没有卡顿。
- 仍保持 ping-island 的轻量工具感。

## 11. 明确不做

- 不做全屏大地图。
- 不一次性展示所有项目岛。
- 不做复杂动态避让/力导向布局。
- 不做大量持续动画、粒子、鱼群、水母。
- 不让一级页面变成纯装饰，必须保留快速访问 session 的效率。
- 不把二级页面里的章鱼继续放大。

## 12. 最终验收标准

### 一级页面

- 打开后中间是多个项目岛，不是黑色列表。
- 默认选中最重要的项目岛。
- active/running 岛高亮，pending 岛 amber 高亮。
- 底部显示选中岛屿的 session dock。
- dock 默认最多 8 个 session，超过显示隐藏摘要。
- 横向滑动流畅。
- 项目很多/会话很多时仍不卡顿。

### 二级页面

- 岛屿明显可见，是视觉主体。
- 章鱼比岛小，站在岛上，不遮住岛。
- mascot normal 不超过岛视觉高度约 22%，hover 不超过 25%。
- 底部 session dock 与岛之间留出清晰空间。

### 交互

- compact bar / permission ping / click-through 修复不回退。
- Deny / Allow / Session / Always 不变。
- session resume 不变。
- 一级地图点击岛屿只切换底部 dock；进入二级需要明确操作。

## 13. 一句话方向

把一级页面从“项目列表”升级为“轻量项目岛屿地图”：中间用少量固定锚点岛屿表达项目状态，底部用横滑 dock 承载会话效率；同时缩小二级页面章鱼、放大岛屿，让岛重新成为舞台。

## 14. Compact bar 底部矩形阴影补充修复

日期：2026-05-28
来源：用户最新截图反馈

### 14.1 问题描述

用户指出：compact bar 底部明细仍然能看到一个矩形的底纹/阴影。这个问题和之前的“compact bar 外围矩形底纹”类似，但更细：

- 胶囊主体看起来已经不再拉满窗口。
- 但底部仍有一块横向矩形阴影或背景残留。
- 视觉上像 capsule 的阴影被绘制到 rectangular bounds 里，或者上层 `frame(width: 300, height: 50)` / `NSHostingView` 底部仍有可见材质。
- 这会破坏 compact bar 的轻量悬浮感。

### 14.2 当前代码高风险点

当前 `CompactBarView` 中仍有：

```swift
.background {
    Capsule()
        .fill(...)
        .overlay(Capsule().stroke(...))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
}
```

其中 `.shadow(radius: 8, y: 4)` 很可能是底部矩形阴影感的来源。SwiftUI shadow 会在 view 的 rectangular bounds 内进行离屏合成，即使主体是 capsule，阴影扩散/裁切也可能看起来像一块矩形暗底。

同时 `CoveRootView` compact 分支仍固定：

```swift
CompactBarView(viewModel: viewModel)
    .frame(width: 300, height: 50)
```

如果 capsule 内容本身小于 300x50，而阴影在这个固定矩形内被裁切，就会在底部留下可见矩形痕迹。

### 14.3 修复原则

Compact bar 的可见形态只能有两个部分：

1. 胶囊本体。
2. 极轻的贴合胶囊形状的暗边/接触阴影。

不能出现：

- rectangular shadow。
- rectangular material。
- rectangular blur。
- capsule 外的半透明底板。
- 因固定 frame 裁切造成的底部横条。

### 14.4 建议修复方案

#### 方案 A：去掉 SwiftUI shadow，改用 capsule 形状内描边/下沿深色线

优先建议。直接移除：

```swift
.shadow(color: .black.opacity(0.3), radius: 8, y: 4)
```

改成更像像素 UI 的下沿暗边：

```swift
.overlay(alignment: .bottom) {
    Capsule()
        .stroke(Color.black.opacity(0.28), lineWidth: 2)
        .offset(y: 1)
        .mask(Capsule())
}
```

或更简单：

```swift
.overlay(
    Capsule()
        .stroke(Color.black.opacity(0.25), lineWidth: 1)
        .offset(y: 1)
)
```

这样阴影仍跟随 capsule，不会产生矩形离屏阴影。

#### 方案 B：将 shadow 放到精确尺寸 capsule wrapper 上，不放在 300x50 root frame 内

如果必须保留 shadow，确保 shadow 只作用于 capsule wrapper 的实际 bounds，不被 300x50 外层 frame 裁切。

但从截图看，当前问题就是 shadow/crop，建议不要使用模糊 shadow。

#### 方案 C：增加 debug 背景验证

临时在 debug build 中给外层 root 加红色 1px border 或透明检查层，确认矩形底纹来源：

- 如果红框尺寸是 300x50，底纹正好在此范围内，说明是 root frame / hosting area 问题。
- 如果底纹跟随 capsule 的 shadow bounds，说明是 `.shadow` 问题。

验证完必须移除 debug border。

### 14.5 验收标准

1. 放大截图检查：compact bar 下方不再有横向矩形暗块。
2. 胶囊外只允许完全透明，或极轻且贴合胶囊形状的暗边。
3. 在浅色桌面、深色桌面、复杂窗口背景上都看不到矩形 shadow crop。
4. `PassThroughHostingView` 的点击穿透不回退：胶囊外点击仍落到背后应用。
5. Permission ping 状态下，顶部 compact bar 也不能出现底部矩形阴影。