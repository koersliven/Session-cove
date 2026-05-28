# Session Cove 章鱼公仔与一级海岛菜单纠偏计划

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`
来源：用户最新截图与反馈；DeepSeek P0 修复记录；当前源码复核

## 1. 本轮结论

DeepSeek 的 P0 修复解决了“灰色棋盘底纹”和“compact bar 矩形底纹”的一部分技术问题，但引入了两个新的核心问题：

1. **章鱼角色退化**：为了去掉 PNG 棋盘底纹，直接禁用 PNG，强制使用程序化 `PixelGridSprite`，导致章鱼变回早期简陋、丑、低完成度的小图标。这不符合用户已有的参考公仔形象，也不符合 Session Cove 的角色核心。
2. **一级菜单没有真正海岛化**：当前 `HarborRosterView` 仍然是黑色渐变背景 + 深色矩形卡片 + 列表行。虽然加了一点海岛装饰，但本质还是 ping-island 风格黑色 roster，没有把每个项目栏目做成海岛。

本轮正确方向不是“回退到最简单的程序化像素图”，而是：

> 使用用户认可的参考公仔形象，重新制作干净透明、边缘可控的高质量 mascot 资源；同时真正实现一级菜单的 ProjectIslandShelf，而不是在黑色列表上贴一点岛屿装饰。

## 2. 当前失败点复核

### 2.1 程序化章鱼过于简陋

当前源码中 `PixelOctopusSprite` 已经改为只走 `PixelGridSprite`：

```swift
PixelGridSprite(rows: fallbackMap) { token in ... }
```

并且原 PNG 路径被绕开。这消除了灰色棋盘格，但代价很大：

- 角色轮廓太粗糙。
- 只有 16x13 左右的网格信息量，无法表现用户认可的公仔质感。
- 耳机、身体、表情缺少细节。
- 放大后更像调试占位 sprite，而不是正式 mascot。
- 和之前参考公仔形象断裂。

结论：`PixelGridSprite` 可以作为 fallback/debug，不应作为正式 mascot。

### 2.2 一级菜单仍是黑色 roster

当前 `HarborRosterView` 顶层仍是深色渐变背景：

```swift
.background(
    LinearGradient(
        stops: [
            .init(color: Color(red: 0.04, green: 0.12, blue: 0.20), location: 0),
            .init(color: Color(red: 0.02, green: 0.07, blue: 0.14), location: 1)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
)
```

当前项目容器仍是矩形卡片：

```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(.white.opacity(0.03))
)
```

当前 session row 也是普通 hover row：

```swift
.background(
    RoundedRectangle(cornerRadius: 4)
        .fill(isHovered ? .white.opacity(0.08) : .clear)
)
```

结论：一级菜单还没有实现上一份 plan 里的 `ProjectIslandShelf`，只是把旧黑色列表轻微装饰了一下。

### 2.3 “清理底纹”不等于“放弃参考图”

DeepSeek 的处理逻辑是：PNG 有灰色棋盘底纹，所以完全不用 PNG。

这个方向不对。正确逻辑应该是：

1. 灰色棋盘底纹是素材导出/抠图质量问题。
2. 应修复素材，或从参考图重新生成透明高质量 mascot。
3. 不应退回简陋的程序化 fallback。
4. 若短期无法修好 PNG，也要用更高分辨率、更像参考公仔的 vector/pixel-art 手绘 sprite，而不是 16x13 调试网格。

## 3. 正确目标

### 3.1 Mascot 目标

章鱼应回到用户认可的参考公仔方向：

- 橙色/珊瑚色块状章鱼身体。
- 深蓝耳机明确可见。
- 可爱但不过度幼稚。
- 有像素游戏质感，但不是低信息量简笔图。
- 透明背景干净，无白底、无灰格、无 halo。
- 在 compact、一级菜单、二级页面都像同一个角色。

### 3.2 一级菜单目标

一级菜单应从：

> 黑色工程列表 + 少量海岛装饰

改为：

> 海港目录；每个项目栏目都是横向小岛，session 是停靠在岛边的码头标签/crew pebble。

保留当前信息架构：

- header
- project list
- recent sessions
- active/idle/archived
- pending permission attention

但视觉上不再是黑色文件框。

## 4. Mascot 修复方案

### 4.1 不允许把 `PixelGridSprite` 当正式角色

新的硬规则：

- `PixelGridSprite` fallback 只允许用于资源加载失败、debug、测试。
- 正式 UI 默认必须使用高质量参考公仔资源或高质量手绘 sprite。
- 不能为了消除棋盘格牺牲角色完成度。

### 4.2 资源来源优先级

当前可用参考资源：

- `reference/claude_working.png`
- `reference/claude_sleeping.png`
- `reference/mascot-backup-2026-05-28/claude_working.png`
- `reference/mascot-backup-2026-05-28/claude_sleeping.png`
- `SessionCove/Resources/claude_working.png`
- `SessionCove/Resources/claude_sleeping.png`
- `SessionCove/Resources/claude_attention.png`
- `SessionCove/Resources/claude_idle.png`

优先策略：

1. 先从 `reference/claude_working.png` 等用户认可参考图中选择角色形象源。
2. 对源图重新抠透明，清理灰格/白边，而不是直接弃用。
3. 若只有 working/sleeping 两个高质量参考，则先恢复这两个；attention/idle 可以从 working 派生姿态或用轻微表情/符号叠加。
4. 只有在资源完全不可用时，才临时 fallback 到更精细的手绘 sprite，不使用当前 16x13 简陋网格。

### 4.3 透明化质量门禁

每个 mascot PNG 必须通过以下检查：

1. 四角 alpha = 0。
2. 边缘 2-4px 内无大面积灰白棋盘 RGB 残留。
3. 背景区域 alpha 必须为 0，不是灰色不透明。
4. 角色边缘允许轻微深色描边，不允许白 halo。
5. 在深海蓝背景、浅色桌面、透明 checker 测试图上都不出现灰格。

建议增加脚本检查：

```bash
python scripts/check_mascot_alpha.py SessionCove/Resources/claude_*.png
```

输出：

- image size
- corner alpha
- suspicious non-transparent background pixels count
- near-white/near-gray edge residue count

### 4.4 如果 PNG 仍脏，做“颜色键控 + 连通域”而不是放弃

如果参考图已经有灰色棋盘背景，可用算法处理：

1. 从四角采样背景颜色集合，识别 checker 两种灰色。
2. flood-fill 外部背景区域。
3. 把外部背景 alpha 设为 0。
4. 只保留与角色连通的非背景像素。
5. 对边缘做 1px 深色描边或 alpha feather，避免白边。

关键：只清外部背景，不改角色内部颜色。

### 4.5 统一 `CoveMascotView`

恢复高质量图后，不要让各页面直接散落 `PixelOctopusSprite(...).frame(...)`。

建议新增：

```swift
struct CoveMascotView: View {
    let state: PixelMascotState
    let scale: MascotScale
    let grounded: Bool
}

enum MascotScale {
    case compact
    case ping
    case shelf
    case row
    case island
    case approval
}
```

职责：

- 统一选择素材。
- 统一尺寸。
- 统一接地阴影。
- 统一 attention 标记。
- 统一 fallback 策略。

尺寸建议：

| 场景 | 建议尺寸 | 说明 |
|---|---:|---|
| compact | 42x38 | 是入口主角，不要小到像 icon |
| ping | 38x34 | 轻量但清楚 |
| shelf | 50x46 | 站在项目小岛上 |
| row | 24x22 | session 行里只作小 crew 标记 |
| island | 72x64+ | 二级页面主角色 |
| approval | 52x48 | 审批上下文强调 |

### 4.6 不要把 island PNG 也一刀切禁用

DeepSeek 同时让 `PixelIslandSprite` 移除 PNG 依赖，只用程序化像素岛。这个方向可以部分保留，但需要注意：

- 一级栏目背景适合程序化，因为要自适应宽度。
- 二级主岛如果已有高质量参考，可以继续使用干净透明资源。
- 不应为了技术纯净牺牲视觉完成度。

## 5. 一级菜单海岛化方案

### 5.1 当前实现必须替换的部分

需要重点替换 `HarborRosterView.swift` 里的三处：

1. 顶层黑色渐变背景。
2. `ProjectSessionGroupView` 的矩形卡片背景。
3. `SessionRosterRow` 的普通列表行 hover 背景。

不是调颜色就够了，而是结构替换。

### 5.2 新结构：HarborLagoonRoster

一级页面整体从黑色 HUD 改成小型海港水域：

```text
+------------------------------------------------+
| harbor sign header                             |
|------------------------------------------------|
| water lane                                     |
|   project island shelf                         |
| water lane                                     |
|   project island shelf                         |
| water lane                                     |
+------------------------------------------------+
```

背景不要纯黑：

- 深海蓝仍可保留，但要有水域感。
- 加非常克制的水纹/泡沫线。
- 减少黑色面板感。
- 不要铺满珊瑚、鱼、水母。

### 5.3 新项目栏目：ProjectIslandShelf

每个项目栏目不再是 `RoundedRectangle`，而是横向小岛：

```text
       grass patch / mascot
     ___^^^^____                         buoy count
  __/ sand shelf \____________________     [3]
 /  project name      session pebble  \
 \____________________session pebble__/
      dark pixel underside / water foam
```

视觉层级：

1. `WaterLaneBackground`：栏目所在水道。
2. `IslandShelfShape`：横向沙洲 + 草地 patch + 像素暗边。
3. `MascotPerch`：章鱼站在草地上，有接触阴影。
4. `ProjectLabel`：项目名和路径，不再全大写。
5. `SessionPebbleRows`：最近 2-3 个 session，像码头木牌/浮标。
6. `CrewCountBuoy`：右侧数量浮标。
7. `PermissionBeacon`：pending 时黄色灯塔/旗帜。

### 5.4 移除文件框感的具体规则

硬规则：

- `ProjectSessionGroupView` 不得再使用 `.background(RoundedRectangle(...).fill(.white.opacity(...)))` 作为主体。
- project card 不得再看起来像半透明黑色文件夹。
- session rows 不得再是普通 rectangular hover list。
- 项目名不再默认 `uppercased()`，保留项目自然名称以减少机器面板感。
- 装饰层必须 `.allowsHitTesting(false)`，点击只落在 island shelf / session pebble 上。

### 5.5 状态如何体现为海岛，而非 badge

| 状态 | 当前问题 | 新表现 |
|---|---|---|
| active | 只是绿色 dot | 草地更亮，小灯/营火亮，water foam 更清晰 |
| idle/recent | 只是文字/弱状态 | 普通沙洲，mascot idle，低亮度水纹 |
| archived | 像普通黑卡 | 岛屿偏灰蓝，半沉感，mascot sleeping |
| permission | 只是感叹号或 amber 边 | 岛上黄色 beacon/旗帜，栏目边缘少量 amber 闪烁 |

## 6. 分阶段纠偏顺序

### P0：恢复 mascot 角色质量

目标：消除灰格，但不能接受简陋章鱼。

步骤：

1. 回看 `reference/claude_working.png`、`reference/claude_sleeping.png` 和备份图，确认最接近用户认可的公仔形象。
2. 用脚本重新抠透明并清理棋盘背景。
3. 生成/恢复至少 working、sleeping 两个干净资源。
4. attention/idle 可先从 working 派生：attention 加 `!` beacon，idle 降低动态/眼神变化。
5. 修改 `PixelOctopusSprite` 或新增 `CoveMascotView`，默认使用高质量干净资源。
6. 只在资源加载失败时 fallback 到程序化 sprite。

验收：

- compact bar 里的章鱼明显像参考公仔，不再是 16x13 简陋图标。
- 无灰棋盘、无白底、无白边。
- 耳机和橙色身体清楚。
- 用户截图中第一眼不觉得丑/粗糙。

### P1：真正替换一级菜单项目卡片为 island shelf

目标：一级页面不再是黑色 roster。

步骤：

1. 新增 `ProjectIslandShelfView`。
2. 用 `IslandShelfShape` 替代项目 `RoundedRectangle` 背景。
3. 把 mascot 放到左侧草地 perch 上。
4. 把项目名、路径、session 数量排在沙洲上。
5. 最近 session 最多显示 2-3 条，改为 `SessionPebbleRow`。
6. 右侧 count 改成 `CrewCountBuoy`。
7. pending permission 加 `PermissionBeacon`。

验收：

- 一级页面截图中，每个栏目都能被识别为一座横向小岛。
- 不再像文件夹/黑色任务列表。
- 背景是深海水域，不是黑色 HUD 面板。
- 信息密度仍然保留，项目名和 session 仍清楚。

### P2：统一一级与二级视觉语言

目标：一级 shelf 是二级 full island 的缩略表达。

步骤：

1. 抽出 `IslandVisualState` / `IslandMood`。
2. 一级 shelf 与二级 island 共用 sand/grass/water/accent 色。
3. 章鱼尺寸和接地逻辑通过 `CoveMascotView` 统一。
4. permission beacon 在一级、二级、ping card 中一致。

验收：

- 点击一级进入二级时，不像从黑色列表跳到另一个游戏场景。
- 两级页面是同一个世界的不同信息密度表达。

### P3：compact bar 保持干净悬浮

目标：保留已修好的 compact bar 无矩形底纹，但替换回高质量 mascot。

步骤：

1. 保留胶囊内容驱动布局。
2. 替换 compact 内的简陋 `PixelGridSprite` 为高质量 mascot。
3. 确认 `PassThroughHostingView` 和 hit-test 不受影响。
4. 维持 50px 窗口高度，如果 mascot 更高，可让 mascot 局部溢出但不扩大点击窗口，或微调为 52px。

验收：

- 胶囊外仍无矩形底纹。
- 章鱼质量恢复。
- 点击穿透仍正常。

## 7. 明确禁止的错误修复

1. 禁止再用“强制程序化简陋 sprite”作为正式 mascot 方案。
2. 禁止只把黑色 roster 调成蓝色就声称海岛化完成。
3. 禁止继续在 `RoundedRectangle` 卡片上贴一条岛屿装饰条冒充 island shelf。
4. 禁止新增更多低质量 PNG 贴图堆叠。
5. 禁止为了视觉效果破坏窗口尺寸、hit-test、permission 四按钮、session resume 等核心交互。

## 8. 工程实现建议

### 8.1 组件拆分

建议新增/重构：

```text
SessionCove/UI/Components/CoveMascotView.swift
SessionCove/UI/Components/IslandShelfShape.swift
SessionCove/UI/Components/WaterLaneBackground.swift
SessionCove/UI/Components/CrewCountBuoy.swift
SessionCove/UI/Components/PermissionBeacon.swift
SessionCove/UI/Views/ProjectIslandShelfView.swift
SessionCove/UI/Views/SessionPebbleRow.swift
```

### 8.2 `HarborRosterView` 替换点

把：

```swift
ProjectSessionGroupView(...)
```

替换为：

```swift
ProjectIslandShelfView(...)
```

把：

```swift
SessionRosterRow(...)
```

替换为：

```swift
SessionPebbleRow(...)
```

### 8.3 资源处理脚本

建议新增：

```text
scripts/clean_mascot_alpha.py
scripts/check_mascot_alpha.py
```

工作流：

1. 输入 reference 高质量图。
2. 自动清理背景。
3. 输出到 `SessionCove/Resources/claude_*.png`。
4. 执行校验。
5. app 使用清理后的资源。

## 9. 最终验收标准

### Mascot

- 看起来是用户已有参考公仔的延续，而不是简陋 debug sprite。
- compact、一级、二级、approval 中角色一致。
- 无灰色棋盘底纹、无白底、无白边。
- 在小尺寸下仍可识别耳机、身体、表情。

### 一级菜单

- 截图一眼能看出是“项目海岛列表”。
- 每个项目栏目是横向小岛，不是黑色文件框。
- 黑色 HUD 感显著降低。
- session 是码头/浮标/pebble 标签，不是普通文件行。
- active、idle、archived、permission 状态融入岛屿表现。

### 交互

- compact bar 继续没有矩形底纹。
- click-through 继续正常。
- permission ping 继续小卡片，不回到大地图。
- Deny / Allow / Session / Always 不变。
- session resume 不变。

## 10. 一句话纠偏方向

不要在“脏 PNG”和“丑陋程序化占位图”之间二选一。

正确方案是：**用参考公仔重新产出干净透明的正式 mascot；用真正的 ProjectIslandShelf 替换黑色 roster 卡片。**