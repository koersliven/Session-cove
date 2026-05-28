# Session Cove 一级页面海岛栏目化 UI 改造建议

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`
参考截图：用户提供的当前一级页面、二级页面截图

## 1. 用户目标

用户希望保留当前交互和信息架构，但把一级页面每一个项目栏目从“冷冰冰的文件框/列表卡片”改造成更统一的海岛风格：

- 一级页面仍然是 overview / roster，不回到复杂大地图。
- 每个项目栏目都应该像一个小岛/浮岛/码头，而不是普通文件夹卡片。
- 保留 ping-island 式轻量、高密度、可快速扫描的结构。
- 视觉语言要回到 Session Cove 的核心概念：项目是岛，session 是岛上的 crew / Claude 章鱼。
- 解决当前大量白底图、贴纸感、粗糙感。

## 2. 当前截图问题判断

### 2.1 一级页面的问题

当前一级页面已经学了 ping-island 的 roster 结构，但视觉上仍偏“黑色 SaaS 列表”：

- 每个项目是深色矩形卡片，像文件框/任务列表。
- 顶部有一点 `IslandHeaderStrip`，但只是很薄的装饰带，不能让用户感知“这是一个岛”。
- 项目名、session 行、数字 badge 的层级都像工程面板，而不是海岛世界。
- 视觉主体是文字和框，不是 island object。
- 左侧 mascot 只是 icon，和项目地形没有视觉接地关系。
- 各项目栏目之间的差异很弱，看起来是一组同质文件夹。

当前代码对应点：

- `HarborRosterView` 使用整体深色背景。
- `ProjectSessionGroupView` 用 `RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.03))` 作为项目容器。
- `IslandHeaderStrip` 只有 `36px` 高，而且主要是水纹和状态点。
- `SessionRosterRow` 是标准 row 列表。

结论：架构方向对，但视觉皮肤没有完成“岛屿化”。

### 2.2 二级页面的问题

二级页面更接近原始海岛概念：

- 有大海背景。
- 有项目岛屿。
- mascot 站在岛上。
- session dock 横向排列。

但它和一级页面语言割裂：

- 一级页面是 ping-island 黑色 roster。
- 二级页面是 full island scene。
- 两者像两个不同产品拼接在一起。

用户说“一个是仿照 ping-island 做的，一个是做成海岛元素”，这个判断准确。现在需要把两者融合成同一套“轻量海岛 roster”语言。

### 2.3 白底图和粗糙感问题

当前资源目录只有：

- `claude_attention.png`
- `claude_idle.png`
- `claude_sleeping.png`
- `claude_working.png`
- `island.png`

虽然之前对 mascot 做过透明化，但用户仍感受到白底图/贴纸感，说明问题可能有三类：

1. PNG 边缘去底不干净：白边、灰边、半透明残留。
2. 图片本身风格不统一：AI 生成图和 SwiftUI 像素组件混用，像贴图贴在 UI 上。
3. 图像没有“接地”：mascot/island 不共享光源、比例、阴影、像素网格。

UI 层面建议：不要继续依赖大尺寸 AI PNG 作为核心 UI 元件。一级页面里的岛屿栏目最好以 SwiftUI Canvas / PixelGrid / 小型 tiles 生成，只把 mascot PNG 作为临时资源，逐步替换为统一像素精灵。

## 3. 设计原则

### 3.1 保留当前架构，不推翻为大地图

当前架构应保留：

- Compact bar：轻量入口和 permission signal。
- Harbor roster：一级页面，展示所有 project islands。
- Project island：二级页面，展示单项目更多 session。
- Session focus：三级页面，展示单 session。
- Permission ping：小卡片审批。

本次只改一级页面视觉，不改变信息架构。

### 3.2 一级页面不是地图，而是“海岛目录”

不要把一级页面做成自由散落大地图，否则会再次出现布局复杂、遮挡、信息密度低的问题。

更适合的方向是：

> Island Roster / Harbor Ledger：每一行仍然是一个项目栏目，但栏目本身是一座横向小岛。

它既有 ping-island 的列表效率，又有 Session Cove 的世界观。

### 3.3 信息先行，装饰服务信息

每个项目栏目必须一眼看出：

- 项目名。
- active / idle / archived 状态。
- session 数量。
- 最近 session。
- 是否有 permission pending。

海岛元素要编码这些信息，不只是装饰。

### 3.4 像素风要“干净”，不是“更多细节”

用户已经多次反感 blurry / distorted / noisy 的海底元素。本轮不要增加复杂珊瑚、水母、鱼群。建议：

- 大块低频像素形状。
- 清晰 2px/4px 网格。
- 少量状态色。
- 少量水纹和泡泡。
- 不要高频噪点。

## 4. 一级页面新的视觉模型

### 4.1 页面整体：Harbor Board

一级页面可以命名为 Harbor Board：一个贴在屏幕上的迷你海港板，不是完整场景。

结构保持当前：

```text
+------------------------------------------------+
| header: mascot + SESSION COVE + active count   |
|------------------------------------------------|
| project island shelf 1                         |
| project island shelf 2                         |
| project island shelf 3                         |
| ...                                            |
+------------------------------------------------+
```

但视觉从“卡片列表”改为“浮岛 shelf”：

- 背景仍是深海渐变，但更浅一点，避免全黑 SaaS 感。
- 每个栏目是一个 horizontal island slab。
- 栏目之间用水流间隔，而不是普通卡片 spacing。
- active 项目像有灯塔/小营地亮着。
- idle 项目是普通沙滩。
- archived 项目更暗、更沉，像远处小礁石。

### 4.2 每个项目栏目：ProjectIslandShelf

建议替换当前 `ProjectSessionGroupView` 的外观为 `ProjectIslandShelf`。

每个栏目由 4 层组成：

```text
Layer 0: water lane background
Layer 1: island silhouette / sand + grass shelf
Layer 2: project metadata and session rows
Layer 3: state accents / permission beacon / hover outline
```

#### Layer 0：水道背景

- 不是矩形透明背景，而是淡淡的水道。
- 用 4px/8px 网格画少量 horizontal foam marks。
- inactive 时 opacity 很低，hover 时水纹稍亮。

#### Layer 1：横向小岛轮廓

把项目卡片底部或左侧变成横向岛屿：

- 左侧：一个较圆的小岛头，承载 mascot。
- 中间：长条沙洲，承载项目名和 session rows。
- 右侧：小码头/浮标，承载 count badge。

形态可以用 SwiftUI Canvas 画 pixel polygon，不建议用 PNG。

建议尺寸：

- 每个栏目高度：`86-112px`。
- 岛屿可视高度：`58-76px`。
- 左侧 mascot 区：`48-56px` 宽。
- session rows 最多显示 2-3 行，超过用 `+N docked`。

#### Layer 2：信息排版

保留当前信息架构，但换皮：

```text
[mascot on tiny grass]  PROJECT NAME                  [3 crew]
                        /path/folder · 3 chats        [active dot]
                        [recent session row 1]
                        [recent session row 2]
```

项目名仍然清晰、可扫描。不要让岛屿装饰抢走项目名。

#### Layer 3：状态编码

状态不要只靠小圆点，要融入岛：

| 状态 | 岛屿表现 | 文本/标记 |
|---|---|---|
| active | 草地更绿，有小灯/营火，mascot working | `CODING` / green beacon |
| recently idle | 沙滩偏暖，水纹弱，mascot idle | `IDLE` / sand marker |
| archived | 岛屿偏冷灰，半沉，mascot sleeping | `SLEEP` / dim marker |
| permission pending | 岛上出现黄色信号塔/旗帜，外框 amber pixel blink | `APPROVAL` / amber beacon |

## 5. 一级栏目具体组件建议

### 5.1 `ProjectIslandShelfView`

替换或重构当前 `ProjectSessionGroupView`。

建议 API：

```swift
struct ProjectIslandShelfView: View {
    let island: ProjectIsland
    let hasPendingPermission: Bool
    let onProjectTap: () -> Void
    let onSessionTap: (SessionRecord) -> Void
}
```

内部拆分：

```swift
ProjectIslandShelfView
├─ IslandShelfBackground       // 水道 + 岛屿轮廓，allowsHitTesting(false)
├─ IslandShelfHeader           // mascot + project name + count/status
├─ IslandShelfSessionRows      // 最近 2-3 个 session
└─ PermissionBeacon            // pending 时显示
```

### 5.2 `IslandShelfBackground`

不要继续用 `RoundedRectangle` 当主体。

建议用 Canvas 画：

- 外层水道：深蓝透明，边缘不规则 4px pixel step。
- 沙滩主体：sand color 横向椭圆/多边形。
- 草地区：左侧或上方一块绿色 patch。
- 底部暗边：ink shadow，增强像素游戏实体感。
- 少量 foam pixels：只在上下边缘，不铺满。

注意：所有背景装饰 `.allowsHitTesting(false)`。

### 5.3 `IslandCrewIcon`

当前一级页面 mascot 像单独 icon，建议改为“站在岛上”：

- mascot 底部加 2-3px 深色接触阴影。
- mascot 脚下加草地 patch。
- 不要让 mascot 漂浮在纯黑卡片上。
- 若 PNG 有白边，一级页面先用 SwiftUI `PixelOctopusSprite` 的 fallback/vector 版本或强制加 mask，不要直接显示脏边 PNG。

### 5.4 `SessionPebbleRow`

session row 不要像文件列表，可以变成“码头木牌/浮标标签”：

- 每行高度 18-22px。
- 左侧小状态方块像浮标。
- 背景用半透明深海蓝，不是普通 hover rectangle。
- hover 时变成泡沫高亮边。
- active session 行可以有 1px green top edge。

### 5.5 `CrewCountDock`

当前数字 badge 像 SaaS 计数器。建议改成右侧小码头：

- 右侧 28x24 小 wooden dock / buoy。
- 显示 `x3` 或 `3`。
- active 时旁边有 green lamp。
- pending 时变 amber bell。

### 5.6 Header 也要统一

当前 `SESSION COVE` header 仍偏工具栏。建议改为：

```text
[Claude mascot in tiny lifebuoy] SESSION COVE     [3 ACTIVE] [X]
```

视觉上是“港口招牌”，不是 SaaS titlebar：

- title 背后加小木牌/像素牌匾。
- active count 是浮标，不是 capsule。
- 关闭按钮可以保留，但做成小圆浮标或像素 buoy。

## 6. 与二级页面的统一方式

二级页面现在是完整 project island scene，方向可以保留，但需要和一级页面建立连续性：

- 一级的 `ProjectIslandShelf` 是二级大岛的缩略版。
- 点击一级栏目时，视觉上从 shelf 进入 full island。
- 状态色、mascot 状态、permission beacon 在一级和二级一致。
- `active / idle / archived / permission` 四种 mood 共享同一套 `IslandMood`。

建议统一组件：

```swift
enum IslandVisualState {
    case active
    case idle
    case archived
    case attention
}
```

一级和二级都从它派生颜色、灯光、mascot state。

## 7. 图片/素材处理策略

### 7.1 先停止新增白底 PNG

短期规则：

- 一级页面不再引入新的 AI PNG。
- 栏目背景、岛屿轮廓、码头、浮标全部用 SwiftUI Canvas / PixelGridSprite 生成。
- PNG 只用于 mascot，如果边缘还脏，就临时缩小、加描边、加接触阴影，降低贴纸感。

### 7.2 检查现有 PNG 的 alpha 和边缘

对现有资源做一次自动检查：

- 四角 alpha 是否为 0。
- 边缘是否有接近白色但 alpha > 0 的残留像素。
- 图像是否有半透明白 halo。

如果存在白边：

- 不要在 UI 里继续放大使用。
- 重新生成/重抠透明图。
- 或把 mascot 改为纯 SwiftUI pixel sprite。

### 7.3 岛屿资源建议转为程序化

`island.png` 如果有白底或风格不统一，应从一级页面移除。一级页面推荐程序化小岛：

- 可根据宽度自适应，不变形。
- 可根据状态换色。
- 不会有白底。
- 像素边缘可控。

二级大岛可以暂时保留 PNG，但需要检查白底；中期也应转为 `PixelIslandSprite` 程序化版本或更干净的透明资源。

## 8. 色彩与质感建议

当前一级页面太黑，建议降低黑色 HUD 感：

### 8.1 背景

- 顶部：`#0E3143` 左右的深海蓝。
- 底部：`#061827`。
- 避免纯黑/近黑大面积面板。

### 8.2 岛屿

- sand：暖沙色，偏 muted，不要太黄。
- grass：深青绿，不要荧光绿。
- rock：蓝灰/棕灰，用于 archived。
- shadow：深蓝黑，固定 3-4px pixel shadow。

### 8.3 状态色

- active：green beacon，但面积小。
- permission：amber/yellow，作为唯一强提醒色。
- archived：低饱和蓝灰。
- hover：foam cyan 边，不要用白色大块高亮。

## 9. 字体与文字建议

保持 monospaced / pixel utility 感，但减少全大写造成的冷硬：

- 顶部标题可以全大写：`SESSION COVE`。
- 项目名不一定全大写；可保留原始大小写，首字母或路径更易读。
- 状态标签可全大写：`CODING` / `IDLE` / `SLEEP` / `APPROVAL`。
- session title 不要全大写，保留可读性。

当前代码 `island.displayName.uppercased()` 会加重机械感。建议一级项目名改回原始 `displayName`，只在状态 badge 使用大写。

## 10. 动效建议

动效要少而明确：

- Hover 项目栏目：水纹亮一点、岛底 shadow 上移 1px、foam edge 出现。
- Active 项目：小灯塔/营火每 1.5s 轻微闪烁。
- Permission pending：amber beacon blink，但不要全卡片闪。
- 展开二级页面：可以用轻微 scale/opacity，不做复杂地图飞行动画。

避免：

- 大面积漂浮动画。
- 背景生物游动。
- 高频粒子/泡泡。

## 11. 分阶段落地计划

### P0：修掉白底/贴纸感的基础问题

1. 检查 `Resources/*.png` alpha 和白边。
2. 一级页面不要放大有脏边的 PNG。
3. 给 mascot 加统一接触阴影和草地基座。
4. 暂停新增 AI 生成贴图。

验收：截图里不再出现明显白色矩形/白边贴纸。

### P1：把一级项目卡片换成 island shelf

1. 新增 `ProjectIslandShelfView`。
2. 新增 `IslandShelfBackground`。
3. 用 Canvas 替代 `RoundedRectangle` 卡片背景。
4. 把 current project header + session rows 放到 island shelf 上。
5. 保留点击区域和当前路由逻辑。

验收：一级每个项目都像一个可点击小岛栏目，而不是文件框。

### P2：把 session rows 改成 dock/pebble 标签

1. `SessionRosterRow` 改名或替换为 `SessionPebbleRow`。
2. 只显示最近 2-3 个 session。
3. 超出显示 `+N docked`。
4. active / idle / archived 状态使用浮标/灯点编码。

验收：仍然能快速扫描 session，但视觉像海港码头标签。

### P3：统一一级/二级 visual state

1. 抽出 `IslandVisualState`。
2. 一级 shelf 和二级 full island 共用状态色。
3. permission beacon 在一级/二级一致。
4. active/idle/archived mood 一致。

验收：从一级点进二级时，像同一座岛的缩略版和展开版。

### P4：细节 polish

1. 调整 header 为 harbor sign。
2. 减少全大写项目名。
3. 加 hover 水纹和 permission beacon 动效。
4. 做 2-3 个不同 island shelf 形状，避免每栏完全一样。

验收：整体更像 pixel-game utility，而不是 SaaS roster。

## 12. 不建议做的方向

- 不要把一级页面改回全屏自由散布地图。
- 不要继续堆珊瑚、水母、鱼群来“增加海洋感”。
- 不要用更多 AI PNG 贴图解决栏目视觉。
- 不要牺牲信息密度，只做大岛艺术图。
- 不要把每个 session 都变成大 mascot；一级页面最多显示项目代表 mascot + 小 crew tags。
- 不要改变 permission / session resume / navigation 架构。

## 13. 目标效果一句话

一级页面应该从现在的：

> 深色工程文件列表 + 一点海岛装饰

变成：

> 一个轻量、可扫描的像素海港目录；每个项目栏目都是一座横向小岛，session 像停靠在岛边的 crew/dock 标签，permission 是岛上的黄色信号灯。

这样既保留 ping-island 的快速工具感，又不会丢掉 Session Cove 的海岛世界观。

## 14. DeepSeek 改造后的最新问题补充

日期：2026-05-28
来源：用户最新截图与反馈

DeepSeek 这一轮整体方向已经比之前好：一级页面开始接近海岛栏目，二级页面也保留了海岛场景。但最新截图里仍有三个必须优先修掉的视觉问题。

### 14.1 Compact bar 仍有矩形裁切底纹

#### 用户可见问题

compact bar 的主体虽然是胶囊形，但细看仍能看到一个矩形的裁切底纹/背景块。视觉效果像：

- 胶囊 bar 外面还有一层不可见或半透明矩形容器。
- 背景不是完全穿透的。
- 破坏了 ping-island 式轻量悬浮感。
- 让 compact bar 看起来像被截在一个 rectangular hosting view 里，而不是自然悬浮的对象。

#### 可能原因

当前 `CompactBarView` 内部有：

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background { Capsule().fill(...) }
.contentShape(Capsule())
```

同时 `CoveRootView` 给 compact 设置：

```swift
.frame(width: 300, height: 50)
```

如果 root view、hosting view、window content view、或上层容器仍有默认背景/材质/半透明 fill，就会在胶囊外露出矩形底纹。

#### UI 修正方向

compact bar 应该是“唯一可见实体”，外部完全透明：

1. `CompactBarView` 不要使用 `maxWidth/maxHeight: .infinity` 填满再画胶囊，改为内容驱动或固定胶囊尺寸。
2. 胶囊外层不能有任何 `Rectangle` / `RoundedRectangle` / material / `.background(Color...)`。
3. `CoveRootView` compact 分支外部不要再包背景。
4. `NSHostingView` 和 `NSPanel` 继续保持 clear，但同时要确认 SwiftUI root 没有默认矩形背景。
5. 如果为命中区域需要 `contentShape`，只允许是 `Capsule()`，不要让矩形 background 承担点击区。

#### 建议验收

- 截图放大后，compact bar 胶囊外没有任何可见矩形色块。
- 在浅色、深色、复杂桌面背景上都看不到 rectangular crop。
- 鼠标点击胶囊外 1-5px 区域应落到背后应用，不应被 bar 拦截。

### 14.2 小章鱼偏小，存在灰色二维格子底纹

#### 用户可见问题

一级页面和 compact bar 里的小章鱼：

- 尺寸偏小，存在感弱。
- 图像周围有灰色二维格子/棋盘底纹。
- 这种格子像透明背景预览图被直接导入了 UI，属于明显素材事故。
- 灰格会让章鱼看起来像贴纸或截图，而不是游戏世界里的角色。

#### 代码线索

当前 compact bar 中章鱼尺寸为：

```swift
PixelOctopusSprite(state: mascotState)
    .frame(width: 32, height: 28)
```

permission ping card 中为：

```swift
PixelOctopusSprite(state: .attention)
    .frame(width: 28, height: 24)
```

这两个尺寸对当前 UI 来说都偏小。

`PixelOctopusSprite` 优先显示 PNG：

```swift
if let image = imageForState {
    Image(nsImage: image)
        .resizable()
        .interpolation(.none)
        .antialiased(false)
        .scaledToFit()
}
```

如果 PNG 自身含有灰色棋盘背景，而不是透明 alpha，那么 `MascotImage.loadCropped` 只按 alpha 裁切无法去掉它，因为棋盘格像素本身是不透明的。

#### UI 修正方向

这是 P0 级素材问题，应先修素材，再调布局。

1. 重新检查四个 mascot PNG：
   - `claude_working.png`
   - `claude_sleeping.png`
   - `claude_attention.png`
   - `claude_idle.png`
2. 如果灰色二维格子存在于 RGB 像素中，不能只靠 alpha crop，必须重新抠图或重导出透明 PNG。
3. 导出后做自动校验：
   - 四角 alpha = 0。
   - 边缘无接近灰白棋盘色残留。
   - 非角色区域 alpha 应为 0，而不是灰白色不透明像素。
4. 在修干净前，一级页面和二级页面应优先使用 `PixelGridSprite` fallback 版章鱼，避免脏 PNG 继续进入 UI。
5. 章鱼尺寸建议统一放大：
   - compact bar：从 `32x28` 调整到约 `40x36` 或 `42x38`。
   - permission ping card：从 `28x24` 调整到约 `36x32`。
   - 一级项目栏目：代表 mascot 建议 `44-52px` 高，必须站在草地基座上。
   - 二级岛屿页面：根据岛屿比例保持更大，不要小到像 icon。

#### 视觉原则

章鱼是 Session Cove 的角色核心，不应该只是状态小图标。它需要满足：

- 清晰可识别耳机和橙色身体。
- 和岛屿有接触阴影，不能漂浮。
- 没有白底、灰底、透明棋盘底纹。
- 不要过度可爱，但要有角色感。

### 14.3 二级菜单也出现同样章鱼底纹问题

#### 用户可见问题

二级页面里的小章鱼同样有灰色二维格子底纹。这说明问题不是单个 view 的背景，而是共享 mascot asset 或 `PixelOctopusSprite` 渲染链路的问题。

#### 处理原则

不要在一级和二级分别 patch。应该统一从组件层修：

1. `PixelOctopusSprite` 的 PNG 输入必须是干净透明图。
2. 如果检测到图片背景不透明且疑似棋盘格，直接 fallback 到程序化 pixel sprite。
3. 所有使用章鱼的地方共享同一套尺寸规范和接地阴影规范。

建议新增一个统一 wrapper：

```swift
struct CoveMascotView: View {
    let state: PixelMascotState
    let scale: MascotScale
    let grounded: Bool
}
```

`MascotScale` 可定义：

```swift
enum MascotScale {
    case compact      // 40x36
    case ping         // 36x32
    case shelf        // 48x44
    case island       // 64x58+
}
```

这样不要在各页面散落 `.frame(width: 28, height: 24)` / `.frame(width: 32, height: 28)` 这种魔法数。

### 14.4 更新后的优先级

把原计划的 P0 调整为以下顺序：

#### P0-A：清理 mascot 灰色棋盘底纹

- 重新导出或处理四个 mascot PNG。
- 如果无法立刻修干净，临时强制走 `PixelGridSprite` fallback。
- 对一级、二级、compact、permission card 全部生效。

#### P0-B：放大 mascot 并统一尺寸系统

- compact：约 `40x36`。
- ping card：约 `36x32`。
- project shelf：约 `48x44`。
- second-level island：按岛屿比例放大到真正像角色，而不是 icon。

#### P0-C：消除 compact bar 的矩形裁切底纹

- compact 外围必须完全透明。
- 胶囊外不得出现任何 rectangular visual background。
- 命中区域也应限制在胶囊附近，避免透明矩形挡点击。

#### P1：继续推进项目栏目海岛化

在 P0 修完之前，不建议继续增加更多岛屿细节。因为灰棋盘底纹和 compact 裁切问题属于“第一眼就破功”的基础质量问题，会抵消后续设计 polish。

### 14.5 新增验收标准

新增以下验收项：

1. Compact bar 放大截图检查：胶囊外没有矩形底纹或裁切阴影。
2. Compact bar 桌面实测：胶囊外点击不拦截背后应用。
3. 四个 mascot 状态在透明/深色/浅色背景上检查：没有灰色棋盘格、没有白底、没有白边。
4. 一级页面每个 mascot 都比当前版本更大，至少能清楚识别耳机、眼睛、身体轮廓。
5. 二级页面 mascot 使用同一个干净组件，不再单独出现灰格底纹。
6. Permission ping card 中章鱼不能小于 `36x32`，且不能带棋盘格。
7. 所有 mascot 都有接地阴影或草地基座，不再像浮在 UI 上的图片。