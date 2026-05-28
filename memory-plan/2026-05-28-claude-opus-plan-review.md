# Claude-opus 方案 Review 与建议

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 总体判断

重新看完当前代码库，也核对了 Claude-opus 这版 plan 后，整体判断是：

> 它指出的问题基本准确，尤其是 P0 Always bug 和 1040x700 全量 harbor 渲染导致卡顿这两点；但 P2「移除 harbor 地图，改成列表式」不建议理解成彻底放弃 Cove 世界观，而应该改成「列表为主、像素海湾为壳」的 hybrid。

## 2. 当前代码库状态

当前代码已经比之前继续前进了一点：

- `CoveViewModel` 已经有 `CoveUIMode` / `CoveOpenReason`，并且现在还有 `modeBeforeInterruption`，说明 interruption 后恢复上下文的方向已经开始做了。
- `SessionDetailView` 已经不是旧表单了，现在已经改成了 `Agent Room / Captain Log` 风格。
- `PermissionInterruptionView` 已存在，说明第一版「全屏 / 大面板权限打断」也已经有了。
- `CoveWindowController` 仍然是 compact `300x50`，expanded 固定 `1040x700`。
- `CoveMapView` 仍然渲染完整海湾地图、最多 6 个岛、路径、背景、bottom dock。
- `ClaudePermissionHook` 的 bridge 脚本里，`Always` 的确依赖 `permission_suggestions`，如果没有 suggestions 就只输出一次性 `allow`。

## 3. 对 Claude-opus plan 的逐项 review

### P0：修 “Always” bug

结论：同意，而且这是最高优先级。

当前代码逻辑大致是：

```python
suggestions = payload.get("permission_suggestions")
if value in ("allowSession", "alwaysAllow") and isinstance(suggestions, list) and suggestions:
    ...
```

如果 payload 没有 `permission_suggestions`，`alwaysAllow` 会退化成：

```json
{"behavior": "allow"}
```

这就解释了为什么 Always 下次还会问。

Claude Code hooks 文档中，`permission_suggestions` 是 optional；`updatedPermissions` 可以包含 `addRules`，格式类似：

```json
{
  "type": "addRules",
  "rules": [{ "toolName": "Bash", "ruleContent": "..." }],
  "behavior": "allow",
  "destination": "localSettings"
}
```

推荐修法：

1. 优先 echo Claude 给的 `permission_suggestions`。
2. 如果 suggestions 缺失，基于 `tool_name` / `tool_input` 构造 conservative fallback。
3. `allowSession` 写 `destination: "session"`。
4. `alwaysAllow` 写 `destination: "localSettings"`，而不是 `userSettings`，避免全局过宽。
5. 对 Bash 要谨慎：如果能从 command 提取，就用 command 作为 `ruleContent`；不要无脑允许整个 Bash。
6. 对非 Bash 工具，可以 fallback 到只匹配 `toolName`，但也要谨慎。

这是必须先做的，因为它是实际功能 bug，不是体验问题。

### P1：权限 ping 小窗

结论：同意方向，但建议替代当前“大型 PermissionInterruptionView”，而不是再加一层。

当前 pending permission 会进入 `.permissionInterruption`，窗口随 `isExpanded` 变成 `1040x700`。这和“轻量动态岛”目标冲突。

建议改成：

- compact bar 保持 `300x50`。
- pending permission 时窗口尺寸变成约 `360x230` 或 `380x240`。
- compact bar 下方弹出 permission card。
- 里面复用 `HookApprovalPanel`。
- 不渲染 harbor map。
- 不渲染大岛。
- 不渲染海洋生物。
- 操作后回到之前状态。

也就是说：

> 权限请求应该是 ping 小窗，而不是展开整个 Cove。

必须保留四个按钮：

- Deny
- Allow
- Session
- Always

这比当前 `PermissionInterruptionView` 更符合 ping-island 的轻量逻辑。

### P2：简化展开视图，移除 harbor 地图，改成列表式

结论：部分同意，但不建议“完全移除 Cove 感”。

Claude-opus 说得对：当前 `CoveMapView` 的问题是用户要“找”。`1040x700`、岛屿、路径、海洋生物、多个状态层全部出现，性能和认知负担都偏高。

但如果直接改成普通列表，会失去 Session Cove 的差异化。更推荐：

> 展开视图改成 Harbor Roster：列表为主，像素海湾为壳。

具体形态：

- 窗口宽度不要 1040，先降到 `520-640`。
- 高度按内容动态，最多例如 `520`。
- 顶部是 compact-like header。
- 主体是 project / session roster。
- 每行：小 octopus / 项目名 / session 数 / active badge / latest session title / Open。
- 右侧或背景保留非常低成本像素装饰：小水纹、小浮标、小岛 icon。
- 不再渲染完整 `PixelSeaLifeLayer`。
- 不再布局 6 个大岛。
- 点击项目进入 project roster/detail。
- 点击 session 进入 captain log。

这更接近 ping-island 的信息效率，同时保留 Cove 的产品味道。

### P3：加入 Chat/Q&A 能力

结论：方向对，但优先级不应该太靠前。

现在先做 Chat/Q&A 会把 scope 拉大很多，因为它涉及：

- JSONL 解析历史。
- prompt / assistant message extraction。
- tmux 或 terminal keystroke send。
- native runtime socket 或 hook response。
- AskUserQuestion / Elicitation 类型事件。
- session 级输入框和状态同步。

当前 Session Cove 的核心问题还没完全解决：Always bug、权限小窗、窗口尺寸、列表清晰度。

所以 P3 应该放到第三阶段，先做只读 Captain Log，再考虑可输入。

## 4. 建议的新优先级

### P0：修 Always 权限持久化

原因：真实功能 bug，且风险可控。

改动文件：

- `SessionCove/Services/Hooks/ClaudePermissionHook.swift`

要点：

- bridge script 内新增 fallback permission update builder。
- `alwaysAllow` 没 suggestions 时也输出 `updatedPermissions`。
- `allowSession` 没 suggestions 时写 session destination。
- 构造规则要保守，尤其 Bash。

### P1：把 permission interruption 改成轻量 ping 小窗

原因：解决卡顿、不打断用户，也更像 dynamic island。

改动文件：

- `SessionCove/UI/Window/CoveWindowController.swift`
- `SessionCove/UI/Views/CoveRootView.swift`
- `SessionCove/UI/Views/PermissionInterruptionView.swift`
- `SessionCove/UI/Components/HookApprovalPanel.swift`

建议：

- 增加 `preferredWindowSize` 或根据 `uiMode` 算尺寸。
- `.permissionInterruption` 不再用 `1040x700`。
- card 约 `360x220`。
- `HookApprovalPanel` 可以继续复用，但要适配小窗。

### P2：把 expanded harbor 改成 Roster，而不是大地图

原因：解决眼花缭乱和性能。

改动文件：

- `SessionCove/UI/Views/CoveMapView.swift`
- 可能新增 `SessionCove/UI/Views/HarborRosterView.swift`

建议：

- 不再渲染完整大海湾地图作为默认 expanded view。
- expanded 默认显示 project / session rows。
- 每行保留小 mascot 和像素 HUD 风格。
- 背景保留轻量 Cove 氛围。
- 大地图可以作为以后可选 `Map mode`，但不是默认入口。

### P3：Captain Log 增强

这个其实已经部分完成了。下一步可以补：

- 最近几条 JSONL 消息摘要。
- changed files / tool activity，如果能从 transcript 提取。
- pending question / approval inline form。

### P4：Chat/Q&A

最后做，因为它是新能力，不是当前痛点修复。

## 5. 不同意或需要修正的地方

### 5.1 “移除 harbor 地图”不要一步到位

不建议直接把 Cove 改成纯列表。更好的说法是：

> 默认 expanded 不再是 full harbor map，而是 harbor roster；full map 可以隐藏、后置或作为 decorative mode。

否则 Session Cove 会变成 ping-island 的弱复制。

### 5.2 权限 UI 不该直接复制 ChatView 底部 bar

ping-island 是 chat/session-first，Cove 是 compact ambient-first。

所以 Cove 更适合：

- compact 下方 ping card。
- session focus 内 inline approval HUD。
- project / roster 中显示 attention badge。

而不是一律放在 ChatView 底部。

### 5.3 Q&A 不要现在做

Q&A 很诱人，但它会把工程复杂度拉到另一个层级。当前最应该先让：

- Always 真生效。
- 权限请求轻量。
- 展开视图不卡、不乱。

这些做好后再加 Q&A。

## 6. 最推荐的下一步

如果现在开始动代码，推荐顺序是：

1. 修 Always bug。
2. 把 `permissionInterruption` 窗口改成小 ping card。
3. 把默认 expanded view 从 `CoveMapView` 换成 `HarborRosterView`。
4. 保留 `CoveMapView` 文件，但先不作为默认入口。
5. 运行 `swift build`。
6. 打包并打开应用查看。

这条路线最稳：先修功能，再降性能负担，再优化视觉信息架构。
