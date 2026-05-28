# Implementation Notes

**Task:** 窗口阻塞回归修复 + 旧权限大窗隔离 + PassThroughHostingView 安全网
**Started:** 2026-05-28
**Completed:** 2026-05-28
**Spec source:** memory-plan/2026-05-28-current-window-blocking-regression-plan.md
**Status:** done

---

## Design Decisions

- **[2026-05-28] PassThroughHostingView 用 bounds 作为 hit rect** — `CoveWindowController.swift:9-19`
  因为窗口已经精确 resize，hit rect = hosting bounds 即可。不需要额外的 rect provider 逻辑。

- **[2026-05-28] PermissionInterruptionView 重命名而非删除** — `PermissionInterruptionView.swift:12`
  保留文件但重命名为 `LegacyPermissionInterruptionView`，添加详细废弃注释。防止未来 agent/merge 误接回默认路由，同时保留参考代码。

- **[2026-05-28] pending permission 下 toggle() 直接 return** — `CoveViewModel.swift:122`
  审批请求不应被普通点击隐藏。用户需要显式决策（Deny/Allow/Session/Always）才能消除 ping 状态。

- **[2026-05-28] build marker 放在 subtitle 权限路径** — `CompactBarView.swift:92-94`
  只在有 pending permission 时显示 "ping-card v2"，不污染正常 compact 状态的 subtitle。用户截图中如看到 "PERMISSION SIGNAL" 说明运行了旧构建。

## Deviations

- **[2026-05-28] print() 而非 os_log** — `CoveWindowController.swift:110`
  spec 建议用 os_log，但 print 更简单且同样可被 Console.app 捕获。不影响调试效果。

## Tradeoffs

- **[2026-05-28] 重命名 vs 删除 vs #if DEBUG** — `PermissionInterruptionView.swift`
  选了重命名为 Legacy 前缀 + 注释。删除可能丢失参考代码，#if DEBUG 增加条件编译复杂度。重命名是最小代价的隔离方式。

## Open Questions

- 暂无。

---

## Progress Log
- `2026-05-28` 第一轮：窗口动态尺寸 + PermissionPingCard + HarborRoster 海岛元素
- `2026-05-28` 第二轮开始：根据回归分析补强
- `2026-05-28` PassThroughHostingView 加入 CoveWindowController
- `2026-05-28` PermissionInterruptionView → LegacyPermissionInterruptionView
- `2026-05-28` toggle() 修复：pending permission 不关闭
- `2026-05-28` updatePanelFrame 增强：init 调用、日志、contentView frame 同步
- `2026-05-28` build marker "ping-card v2" 加入 CompactBarView subtitle
- `2026-05-28` 清理 8 个旧进程，干净启动单个实例
- `2026-05-28` 构建通过，app 已启动

## Summary
- 完成了：PassThroughHostingView 点击穿透兜底、旧 PermissionInterruptionView 隔离为 Legacy、toggle() 不再关闭权限 ping、updatePanelFrame 增强日志+同步、build marker 验证运行版本、旧进程清理
- **待用户确认**：手动 QA 清单中的各项（compact 点击穿透、ping 小卡片展示、Deny/Allow/Session/Always 正常）
- **建议下一步**：触发真实 Claude permission request 验证小卡片路由
