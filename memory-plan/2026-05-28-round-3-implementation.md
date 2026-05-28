# Session Cove 第三轮实施记录

日期：2026-05-28
依据：`memory-plan/2026-05-28-claude-opus-plan-review.md`

## P0: "Always" 权限持久化 bug

**文件:** `SessionCove/Services/Hooks/ClaudePermissionHook.swift`

**根因:** bridge 脚本 `output_decision` 只在 payload 含 `permission_suggestions` 时才输出 `updatedPermissions`。Claude 的 hook payload 经常不带该字段，导致 `alwaysAllow` 退化成一次性 `{"behavior": "allow"}`，下次再问。

**修复:** 新增 `build_fallback_permission()` 函数：
- `alwaysAllow` → 构造 `updatedPermissions`，`destination: "localSettings"`
- `allowSession` → `destination: "session"`
- Bash 特殊处理：提取命令前缀（git/ls/npm/swift 等），不无脑允许整个 Bash
- 非 Bash 工具按 toolName 构造规则

## P1: 权限 Ping 小窗

**新增枚举:** `CoveFrameSize` — `.compact`(300x50) / `.ping`(360x220) / `.expanded`(520x480)

**改动文件:**
- `CoveViewModel.swift` — `isExpanded` / `frameSize` 计算属性；`toggle()`/`back()` 适配 ping 模式；`updatePendingHookRequest` 恢复逻辑简化
- `CoveRootView.swift` — 三分支：compact / ping(compactBar+HookApprovalPanel) / expanded
- `CoveWindowController.swift` — 面板固定 520x520，不再 resize
- `CompactBarView.swift` — 点击统一走 `toggle()`，不再手动设 permissionInterruption

**行为:**
- 权限请求来 → 窗口从 compact bar 弹开 360x220 ping 卡片
- 审批完毕 → 回到 compact
- ping 模式下点击外部不会关闭（需要用户决策）

## P2: Harbor Roster 列表视图

**新增文件:** `SessionCove/UI/Views/HarborRosterView.swift`

**设计:**
- 列表为主，像素海湾为壳（不渲染完整 harbor 地图/海洋生物层大岛）
- Header: octopus + "SESSION COVE" + active 数 + 关闭按钮
- 每行：octopus + 项目名(大写) + 文件夹名 + active dot + session 数
- 展开显示最近 3 条 session（标题 + 相对时间）
- 空状态：sleeping octopus + 提示文字

**CoveRootView:** 默认 expanded view 从 `CoveMapView` 改为 `HarborRosterView`，`CoveMapView` 保留但不再作为默认入口

## 窗口动画重写

**核心理念变更:** 窗口不再 resize（macOS `NSPanel.setFrame(animate:)` 是卡顿根源）

- 面板固定尺寸 520x520，居中于屏幕顶部
- 内容用 SwiftUI `spring(response: 0.35, dampingFraction: 0.86)` 展开/收缩
- `VStack` + `Spacer(minLength: 0)` + `.frame(alignment: .top)` 实现内容顶对齐
- 超出内容区域的透明部分自动穿透点击
- 移除 `observeExpansion()`、`updatePanelFrame()`、`sizeForFrame()`
- `setupGlobalClickMonitor` 仅在 `isExpanded` 时关闭面板

## 公仔图片更新

- `reference/claude_working.png` / `claude_sleeping.png` 实际为 AVIF 格式
- 用 ffmpeg 转换为 PNG 后替换 `SessionCove/Resources/` 下对应文件

## 构建验证

```
swift build && ./scripts/bundle.sh && open ".build/release/Session Cove.app"
```
