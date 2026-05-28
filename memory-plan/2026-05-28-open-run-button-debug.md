# OPEN/RUN 按钮失效 — 调试记录

## 问题描述
Session Cove 的 OPEN/RUN/resume 按钮点击无反应。一级菜单（底部 dock 的卡片按钮）和二级菜单都不生效。

## 排查历史

### 第一轮：TTY 格式错误
- `ps -eo tty=,args=` 输出 `ttys001  claude --resume <id>`
- 错误地拼接为 `/dev/ttyttys001`（双重 tty 前缀）
- 修复：改为 `/dev/\(tty)` → `/dev/ttys001`

### 第二轮：AppleScript 语法错误
- iTerm2 不支持 `set frontmost of theWindow to true`（报错 -10000）
- 终端手动验证：`osascript` 执行报错
- 修复：改用 ping-island 的写法：
```applescript
set targetWindowId to (id of theWindow)
set resolvedWindow to first window whose id is targetWindowId
select theTab
select theSession
select resolvedWindow
activate
```
- 终端手动验证通过（返回 "ok"）

### 第三轮：session.status 条件过严
- 原代码 `if session.status == .active` 才尝试 focus
- 但 status 基于文件修改时间（30秒），开着的 terminal 如果没操作就变成 recentlyIdle
- 修复：去掉 status 条件，永远先尝试 focus

### 第四轮：semaphore 可能死锁
- 用 DispatchSemaphore 在 background thread wait + main dispatch 执行 AppleScript
- 怀疑可能死锁
- 修复：改为纯异步（background 查 TTY → main 执行 AppleScript）

### 第五轮：CWD 匹配 lsof 阻塞
- 用 `lsof -a -p <pid> -d cwd` 获取进程工作目录
- lsof 可能阻塞或超时
- 修复：去掉 lsof，只用 session ID 匹配

### 第六轮（Agent 诊断）：`.onTapGesture` 拦截 Button
- **根因**：`HarborSessionDockCard` 整个卡片有 `.onTapGesture(perform: onTap)`
- macOS SwiftUI 中父级 `.onTapGesture` 会抢在子 `Button` 之前响应
- 子 Button 的 `onResume` action 永远不会被触发
- **修复**：
  1. 拆分点击区域 — `.onTapGesture` 只放在信息区域
  2. Button 加 `.contentShape(Capsule())`
  3. 加 `acceptsFirstMouse` = true

### 第七轮：修复后仍然无反应
- 上述所有修复都已应用
- `swift build -c release` 编译通过
- 重启后点击按钮仍然无反应
- **尚未确认的问题**：
  - 按钮 action 是否真的被调用了？（看 Console.app 有无 `[SessionResumer]` 日志）
  - NSAppleScript 从非激活 NSPanel 执行是否需要特殊权限？
  - SwiftUI Button 在 `.plain` buttonStyle + NSPanel 中是否真的能响应？

## 当前代码状态

### SessionResumer.swift（当前版本）
- 入口：`resume(session:)`
- 流程：background 查 ps → main 执行 AppleScript
- TTY 匹配：`ps -eo tty=,args=` 搜索 session.id
- Focus：select theTab + select theSession + select resolvedWindow + activate
- Fallback：开新 iTerm2 窗口 `claude --resume <id>`
- 每步都有 `print("[SessionResumer] ...")` 日志

### HarborSessionDock.swift（当前版本）
- 卡片拆成两个区域：
  - Info 区域（标题、时间）→ `.onTapGesture(perform: onTap)` 打开详情
  - Action 行（branch + RUN 按钮）→ Button 直接处理 `onResume`
- Button 有 `.contentShape(Capsule())` 和 `.buttonStyle(.plain)`

### CoveWindowController.swift
- PassThroughHostingView 加了 `acceptsFirstMouse(for:) -> true`

### 调用链
```
Button(action: onResume) 
  → HarborSessionDock(onResume: { onResume(session) })
    → HarborMapOverviewView: HarborSessionDock(onResume: { viewModel.resumeSession($0) })
      → CoveViewModel.resumeSession(_ session:) { SessionResumer.resume(session: session) }
        → SessionResumer.resume(session:)
```

## 下一步排查方向

### 1. 确认按钮 action 是否被调用
- 在 `CoveViewModel.resumeSession()` 加 print
- 或者在 Button action 闭包里加 print
- 运行后点击，查看 Console.app 或 Xcode 控制台

### 2. 可能的 SwiftUI/NSPanel 问题
- NSPanel 设置为 `nonActivating` 时，Button 可能不响应
- 需要检查 panel 的 `styleMask` 和 `becomesKeyOnlyIfNeeded`
- 可能需要 `panel.makeKey()` 或修改 panel level

### 3. 可能的 hit testing 问题
- CoveWindowController 可能有 pass-through hit testing 逻辑
- 如果 hit test 返回 nil，点击会穿透窗口
- 需要确认 RUN 按钮区域的 hit test 是否正确返回 view

### 4. 测试方法
```bash
# 启动 app
/Users/lipu/Work/Session-cove/.build/arm64-apple-macosx/release/SessionCove &

# 查看日志
log stream --predicate 'process == "SessionCove"' --level debug

# 或直接在终端看 stdout
# （如果从终端启动，print 会输出到 stdout）
```

### 5. 最简验证
在 Button action 里加一个系统通知或音效来确认点击是否到达：
```swift
Button(action: {
    NSSound.beep()  // 如果听到声音就说明 action 被调用了
    onResume()
}) { ... }
```

## 参考：ping-island 的实现
- 使用 Unix domain socket bridge，不是文件轮询
- iTerm2 focus 用 `select resolvedWindow` 模式
- 权限 "Always" 设 `destination: "localSettings"` 写入 settings.json
- 按钮不在 NSPanel 中（ping-island 用的是标准 NSWindow）

## 文件索引
| 文件 | 作用 |
|------|------|
| `SessionCove/Services/SessionResumer.swift` | 核心 resume 逻辑 |
| `SessionCove/UI/Components/HarborSessionDock.swift` | Dock 卡片 UI + 按钮 |
| `SessionCove/UI/Views/HarborMapOverviewView.swift` | 主地图 + 传递 onResume |
| `SessionCove/Core/CoveViewModel.swift` | resumeSession 方法 |
| `SessionCove/UI/Window/CoveWindowController.swift` | NSPanel 配置 |
| `SessionCove/Services/Hooks/ClaudePermissionHook.swift` | Hook 脚本（已修复 alwaysAllow） |
