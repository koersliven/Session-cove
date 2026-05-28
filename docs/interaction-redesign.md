# Session Cove 交互重构分析

## 结论先行

Session Cove 当前的问题，不是“章鱼再往下移动 10px”能解决的。真正的问题是：现在把会话状态直接翻译成了“岛上摆很多章鱼”，导致主地图、项目详情和会话详情都在重复同一种拥挤表达。

Ping Island 的核心价值不是某个具体 UI 样式，而是它的交互哲学：默认安静、按注意力排序、只在需要用户行动时展开。Session Cove 应该吸收这个思想，但不要复制它的黑色列表界面。Cove 应该保留像素海湾世界观，同时把信息架构重做成“动态岛入口 + 海湾总览 + 项目岛钻取 + 会话房间 + 权限打断场景”。

推荐的新原则：

- overview = awareness：总览只告诉用户哪里有事，不承载全部信息。
- island = project context：岛代表项目，不是所有会话的陈列架。
- crew dock / roster = many sessions：多个会话用码头、头像卡、睡眠舱、数量气泡表达。
- mascot = current / important session：完整章鱼只给当前、活跃或需要注意的会话。
- interruption = permission request：权限请求是最高优先级场景，应该自动进入可决策状态。

## 1. Ping Island 做得好的地方

### 1.1 它是 attention-first，不是 dashboard-first

Ping Island 默认保持很小，只在以下情况展开：

- agent 需要 approval
- agent 需要用户输入
- agent 需要人工介入
- session 完成或异常
- 用户主动 hover / click

它不是把所有 session 同时摊开，而是先判断“现在最需要用户注意什么”。这点是 Cove 最该学习的。

### 1.2 它有明确模式

Ping Island 的模式大致是：

- compact / closed
- hover preview
- opened session list
- focused chat / session
- notification / approval interruption

这让用户不需要在同一个画面里同时理解所有东西。每个模式只服务一个目标。

### 1.3 它用 representation density 处理复杂度

多 session 不等于画很多 mascot。Ping Island 会用列表、行、badge、hover preview、展开行来改变信息密度。重要 session 才得到更强表达。

### 1.4 它的 mascot 是状态演员，不是布局主体

mascot 用来表达 idle / working / warning 等状态，增加品牌感，但它不承担所有信息架构。Cove 当前的问题正好相反：章鱼承担了太多布局和状态表达。

### 1.5 它的浮窗行为轻量

Ping Island 的 floating notch 不应该像一个巨大的隐形窗口挡在屏幕上。它的 hit test 只让真实 panel 区域接收点击，其他区域让点击穿透。这一点对 Cove 很重要。

## 2. Session Cove 应该学什么

### 2.1 默认不要展示“完整地图”

Cove 现在的 compact bar 只是一个黑色 capsule 文本条，视觉上还不是“像素海湾入口”。它应该变成一个小型 living cove：

- 一个小海湾/小岛剪影
- 一个 lead Claude octopus
- active / idle / attention 状态
- 一个 session/project count badge
- pending permission 时出现感叹号或电报码气泡

它应该像 Ping Island closed notch 一样，先呈现“最重要状态”，而不是呈现全量数据。

### 2.2 展开后也不要立刻画满所有项目和章鱼

Cove 当前主地图最多画 6 个岛，每个岛最多画 4 只章鱼。这个设计导致用户看到的是“很多贴纸”，而不是一个自然世界。

新的海湾总览应该只画 3-5 个最重要项目岛：

- pending permission 项目优先
- active 项目其次
- 最近项目再次
- 其余项目进入 `+N`、远处浮标、航线节点或列表抽屉

每个岛只展示：

- 1 个 lead mascot
- session 数量 badge
- active/recent/sleep 状态 pips
- 小码头/小屋/旗帜/灯塔等状态设施

不要在总览里展示每个 session 的完整章鱼身体。

### 2.3 项目岛详情不是“放大版主地图”

现在项目详情页会在大岛上放最多 8 只章鱼，然后底部再放 session card。这实际上重复了主地图的拥挤问题。

新的项目岛应该分层：

- 岛上只站 1-3 个当前重要会话
- 其他会话进入 dock roster
- archived 会话进入 sleeping huts / archive cave
- recent idle 会话进入 docked boat / campfire
- pending approval 会话拥有最高视觉优先级

这样岛会像一个基地，而不是一个摆满贴纸的画布。

### 2.4 会话详情应变成 agent room / captain log

当前会话详情更像普通表单卡片：Topic、metadata、resume button。它没有充分利用 Cove 世界观，也没有承接 Ping Island 的 focused chat 思路。

新的会话详情应该是“agent room / captain log”：

- 左侧/顶部：当前 mascot 角色状态
- 主体：当前任务、最近活动、最后消息摘要
- 次级信息：project path、branch、session id、last active
- 操作：Open / Resume terminal
- 如果有 permission：直接显示审批 HUD

它不应该再展示一堆重复装饰，而应该让用户明确“这个 agent 正在做什么，我能做什么”。

### 2.5 权限请求应该是打断场景，不是角落 panel

现在 Cove 的 permission panel 在主地图右下角出现。它有正确的按钮，但信息层级不够强：用户需要自己理解是哪个项目、哪个会话、什么命令在请求。

新的 permission flow 应该是：

1. hook 检测到 pending request。
2. compact 状态自动进入 attention，必要时展开。
3. 直接聚焦相关项目岛或 session focus。
4. mascot 进入 attention / warning 状态。
5. 显示 game HUD 风格审批卡。
6. 按钮保持四个：Deny / Allow / Session / Always。
7. 决策后回到之前上下文，或折叠回 compact。

用户必须一眼知道：

- 哪个项目在请求
- 哪个 session 在请求
- 请求的 tool / command / path 是什么
- 四个按钮分别会造成什么范围的授权

## 3. Session Cove 不应该直接复制什么

不要直接复制 Ping Island 的：

- 黑色 SaaS 式列表界面
- 纯文本 session rows
- chat/dashboard 的视觉语言
- mascot 只作为小 icon 的弱世界观

Cove 的优势应该是像素海湾场景，所以要保留：

- 海洋、岛、码头、船、营地、睡眠舱等世界元素
- Claude octopus 作为角色
- 像素 HUD 风格的审批与状态
- ambient status toy 的感觉

但要去掉：

- 白底 PNG / sticker 感
- 粗糙、模糊、扭曲的低质量海洋生物
- 每个 session 都画成完整章鱼的机械映射
- 在主地图和详情页重复堆 mascot 的做法

## 4. 当前 Cove 的主要问题

### 4.1 compact mode 不是产品入口，只是状态文本条

当前 `CompactBarView` 显示 water icon、islands/sessions 文本、active count。它能用，但不像 Cove，也没有 lead mascot 或 attention-first 逻辑。

问题：

- 不像像素世界入口
- 没有代表性 session / project
- pending permission 不够突出
- 没有 hover preview / notification open reason

### 4.2 主地图仍然是 dashboard 思维

`CoveMapView` 会展示最多 6 个岛，并且每个岛内部继续展示多个 mascot。虽然布局算法避免了重叠，但它解决的是几何问题，不是信息架构问题。

问题：

- 6 个岛同时出现，信息密度偏高
- 每个岛最多 4 个章鱼，视觉上像贴纸集合
- top bar / bottom legend 增加 dashboard 感
- permission panel 放在角落，缺少打断场景的戏剧性和清晰性

### 4.3 项目详情重复了主地图的问题

`IslandSessionListView` 在大岛上最多放 8 个 mascot，同时底部还有横向 session cards。用户会觉得章鱼仍然在漂浮/拥挤，因为我们仍然把 session 直接映射成 mascot。

问题：

- 岛上 8 个 mascot 很难自然接地
- hover 后尺寸变化会加重漂浮感
- 底部 cards 和岛上 mascot 表达重复
- “BASE / N SESSION OCTOPUSES” 强化了错误心智：session = octopus body

### 4.4 会话详情脱离像素世界

`SessionDetailView` 使用普通 SwiftUI 表单式卡片、SF Symbol、圆角渐变按钮，与 Cove 主地图的像素 HUD 风格不一致。

问题：

- 看起来像另一个普通 app 页面
- mascot hero 是装饰，没有承载状态或操作
- 缺少 captain log / agent room 的场景感
- 没有把 permission / activity / terminal focus 聚合成一个会话操作中心

### 4.5 海洋生物层增加噪音

`PixelSeaLifeLayer` 用字符网格画 reef、kelp、jellyfish、seahorse、fishSchool。它们是程序化像素块，但质量不稳定，容易显得扭曲、糊、像噪点。

问题：

- Dave the Diver 的氛围来自高质量资产和分层，而不是简单放很多小图案
- 当前 sea life 抢注意力，但没有服务 session state
- 如果质量不够，应先降噪，而不是继续加元素

### 4.6 floating panel 还不够“轻”

`CovePanel` 是 borderless nonactivating panel，但没有像 Ping Island 那样做更精确的 pass-through hit testing。展开状态下 1040x700 的整块区域就是交互窗口。

问题：

- 展开时可能像一块大窗口，而不是轻量浮层
- 没有 hover preview / click intent / notification reason 区分
- global click monitor 简单地外部点击折叠，但缺少更细的浮窗行为模型

## 5. 推荐的新交互模型

### 5.1 Compact Cove / Dynamic Island Entry

目标：默认安静，像一个活的小海湾。

内容：

- 小型像素海湾 capsule
- lead mascot：代表最需要注意的 session
- 中心短文本：如 `CODING in session-cove` / `1 APPROVAL` / `3 agents active`
- 右侧 count badge 或 bell
- pending permission 时变成黄色 attention 状态

行为：

- click：展开 harbor overview
- hover：显示轻量 preview，不进入完整 dashboard
- notification：自动展开到 interruption scene

### 5.2 Expanded Harbor Overview

目标：让用户知道“哪些项目在动，哪里需要我”。

内容：

- 3-5 个 project islands
- 每个岛一个 lead mascot
- active/recent/sleep pips
- session count bubble
- pending permission island 高亮
- 远处浮标表示更多项目 `+N`

行为：

- click island：进入 project island drill-in
- hover island：显示 project summary tooltip / preview card
- pending approval：点击或自动进入 permission flow

### 5.3 Project Island Drill-in

目标：展示某个项目的会话结构，但不拥挤。

内容：

- 大岛/base
- 1-3 个重要 mascot：pending、active、recent
- dock roster：所有 session 的小头像卡/船位
- sleeping huts：archived grouped count
- project stats HUD

行为：

- click mascot/card：进入 session focus
- hover card：对应 mascot 或 dock slot 高亮
- resume/open 按钮直接出现在 session card 上

### 5.4 Session / Agent Focus View

目标：成为单个 agent 的操作中心。

内容：

- captain log / agent room 场景
- mascot avatar + state
- task/topic 摘要
- last active / branch / project path
- terminal focus / resume button
- recent activity / approval history
- 如果 pending approval：审批 HUD 固定在主区域

行为：

- back：回到 project island
- open/resume：跳到 terminal
- permission decision：决策后留在当前 session 或回到 compact，由来源决定

### 5.5 Permission Interruption Flow

目标：像游戏事件一样明确打断，但不失控。

内容：

- 黄色 attention tint
- project island / mascot spotlight
- toolName + summary + path
- Deny / Allow / Session / Always

行为：

- compact 时收到请求：自动打开小 permission capsule 或展开到 focused interruption
- overview 时收到请求：聚焦相关岛
- project/session view 时收到请求：如果同项目，原地显示；如果不同项目，用 notification banner 提示切换
- 决策后：回到上一个 open reason 对应状态

## 6. 推荐的新视觉模型

### 6.1 减少完整章鱼数量

规则建议：

- compact：1 只 lead mascot
- harbor overview：每岛最多 1 只 mascot
- project island：最多 3 只 mascot
- session focus：1 只主 mascot

其余 session 用：

- count bubbles
- dock slots
- tiny portraits
- sleeping huts
- small boats
- status pips

### 6.2 建立岛屿分层，而不是继续调 anchor

每个岛应该有明确层级：

1. water shadow / foam layer
2. island back layer
3. walkable ground mask / anchor layer
4. mascot layer
5. foreground grass / rocks / dock layer
6. HUD / badge layer

如果没有 foreground layer，mascot 很容易像贴在图片上。真正的接地感不是只靠脚下阴影，而是靠“前景遮挡 + 地面锚点 + zIndex”。

### 6.3 海洋氛围先降噪，再升级

短期建议：

- 暂时减少 jellyfish / seahorse / reef 的出现频率
- 只保留低对比度水纹、气泡、远处剪影
- 不再增加字符网格海洋生物

中期建议：

- 使用统一风格的手绘/生成后人工筛选 pixel assets
- 分为 background / midground / foreground 三层
- 让海洋生物作为环境，而不是注意力中心

### 6.4 HUD 保持像素化，但减少 dashboard 味

现在 top bar、bottom legend、metadata card 偏 dashboard。可以改成游戏 HUD：

- 木牌/浮标/电报码牌
- 小旗帜表达 active
- 灯塔闪烁表达 attention
- 船坞牌表达 session roster

## 7. 实现路线图

### Phase 1：重建交互结构

目标：先改信息架构，不做像素微调。

任务：

- 给 `CoveViewModel` 增加明确 UI mode：compact、hoverPreview、harborOverview、projectIsland、sessionFocus、permissionInterruption
- 增加 open reason：click、hover、notification、boot、unknown
- pending permission 时自动进入 attention/interruption 逻辑
- compact view 改为 lead mascot + count/bell + current status

验收标准：

- 用户在 compact 状态即可知道是否有事
- 权限请求不再只是角落 panel
- 主地图不再是唯一展开内容

### Phase 2：降低视觉拥挤

目标：停止把每个 session 都画成完整章鱼。

任务：

- harbor overview 每岛只展示 1 个 lead mascot
- project island 最多展示 3 个 mascot
- 其他 session 进入 dock roster / badge
- 删除或弱化 `BASE / N SESSION OCTOPUSES` 这种文案

验收标准：

- 多 session 项目不再像贴纸堆
- 用户能明确哪个 mascot 是当前重点
- 地图看起来更像海湾，而不是状态表

### Phase 3：像素资产与层级

目标：解决“贴上去”和“糊/扭曲”的观感。

任务：

- 为 island 增加 foreground overlay / walkable mask
- mascot 只站在明确 walkable anchors 上
- 降低低质量 sea life 的透明度或移除
- 准备统一风格的 dock、hut、boat、flag、permission beacon 资产

验收标准：

- mascot 被场景包住，而不是贴在场景上
- sea life 不抢主信息
- 整体更接近 coherent pixel-game world

### Phase 4：真实 session / permission polish

目标：把 hook、session state、terminal focus 做成顺滑闭环。

任务：

- permission request 定位到具体 project/session
- approval HUD 显示 tool、summary、path、scope explanation
- 决策后根据来源恢复上一状态
- session focus 增加 recent activity / captain log
- floating panel 增加更精确 hit region / pass-through 行为

验收标准：

- 用户能在 1 秒内完成审批判断
- 决策后 UI 不迷路
- Cove 像 ambient tool，不像挡屏大窗口

## 8. 建议优先级

最高优先级：

1. compact cove 重新设计
2. permission interruption flow
3. 主地图每岛只保留 lead mascot
4. project drill-in 引入 dock roster

暂缓：

- 继续调 4-8 个 mascot 的 anchor
- 继续增加海洋生物
- 大规模生成更多装饰素材
- 先做复杂动画

原因很简单：现在的问题是交互层级，而不是单个 sprite 的位置。

## 9. 最终推荐方向

Session Cove 最好不要做“会话地图 dashboard”，而应该做“会呼吸的像素海湾状态岛”。

它的核心体验应该是：

- 平时是一只小章鱼守着一个小海湾，安静告诉你有几个 agent 在工作。
- 有事时它像 Ping Island 一样主动冒出来，但以 Cove 自己的像素游戏语言表达。
- 展开后不是把所有会话铺满，而是让用户快速知道哪个项目、哪个 agent、哪件事需要处理。
- 进入项目后，岛是上下文；码头/船/小屋管理多会话；章鱼只代表真正重要的角色。
- 进入 session 后，是 agent room / captain log，而不是普通 metadata 表单。

这会比继续微调章鱼位置更接近用户想要的“优秀的灵动岛/悬浮小软件 + 像素游戏世界”。
