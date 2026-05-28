# Session Cove RUN/RESUME 与 Terminal 状态修复复盘

日期：2026-05-28
项目路径：`/Users/lipu/Work/session-cove`

## 1. 本轮修复目标

本轮主要修复两个实际使用中断问题：

1. 一级菜单 RUN / 二级菜单 RESUME 点击后没有实际唤起或聚焦 Terminal/iTerm2。
2. 明明 Claude Terminal 还开着，但过一会儿 Session Cove 把会话识别成 idle / 黄灯。

最终结果：

- RUN / RESUME 点击链路恢复。
- 已打开的 iTerm2 Claude 会话可以通过 TTY 正确聚焦。
- 只要 Claude 进程还活着，会话保持 active，不再因为 jsonl 文件 30 秒未更新就变黄。

## 2. 排查过程

### 2.1 第一阶段：确认按钮 action 是否触发

最初怀疑点是 NSPanel / nonactivating window / PassThroughHostingView 导致 SwiftUI `Button` action 根本没有触发。

为确认点击链路，在 `CoveViewModel.resumeSession(_:)` 中加入日志：

```swift
print("[CoveViewModel] resumeSession tapped: \(session.id)")
```

用户测试后确认：

```text
[CoveViewModel] resumeSession tapped: ...
[SessionResumer] resume called for session: ...
```

结论：

- Button action 已触发。
- NSPanel hit testing 不是 RUN/RESUME 无响应的根因。
- 问题在 `SessionResumer` 后续逻辑。

### 2.2 第二阶段：定位 SessionResumer 卡点

`SessionResumer.resume(session:)` 入口日志能打印，但最初没有后续 TTY lookup 结果，说明卡在：

```swift
findSessionTTY(session: session)
```

原代码中 `ps` 管道读取顺序是：

```swift
try process.run()
process.waitUntilExit()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
```

这个顺序存在经典死锁风险：

- `ps -eo tty=,args=` 输出较大。
- stdout pipe 缓冲区被写满。
- `ps` 等待父进程读取 pipe。
- 父进程在 `waitUntilExit()` 等 `ps` 退出。
- 双方互等，表现为只打印入口日志，后续没有动作。

修复后改为：

```swift
try process.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

并加入：

```swift
print("[SessionResumer] Starting TTY lookup")
print("[SessionResumer] ps exited with status: \(process.terminationStatus)")
```

用户验证后日志完整：

```text
[SessionResumer] Starting TTY lookup
[SessionResumer] ps exited with status: 0
[SessionResumer] TTY lookup result: ttys003
[SessionResumer] Executing focus script for TTY: /dev/ttys003
[SessionResumer] Successfully focused iTerm2 session
```

结论：RUN/RESUME 唤起失败的真正卡点是 `ps` pipe 读取顺序，而不是按钮和 AppleScript。

### 2.3 第三阶段：修复 iTerm2 聚焦路径

`SessionResumer` 当前逻辑：

1. 通过 `ps -eo tty=,args=` 找到包含 session id 的 Claude 进程。
2. 取该进程 TTY，例如 `ttys003`。
3. 转为 `/dev/ttys003`。
4. 用 iTerm2 AppleScript 遍历 windows / tabs / sessions。
5. 匹配 `tty of theSession`。
6. 找到后执行：

```applescript
select theTab
select theSession
select resolvedWindow
activate
```

注意：之前已确认不要使用：

```applescript
set frontmost of theWindow to true
```

这个写法会导致 iTerm2 AppleScript error `-10000`。

当前验证表明：

```text
[SessionResumer] Successfully focused iTerm2 session
```

说明 iTerm2 聚焦链路有效。

### 2.4 第四阶段：修复 active / idle 误判

用户反馈：Terminal 明明还开着，但过一会儿 Session Cove 会把会话识别为 idle / 黄灯。

定位到 `CoveViewModel.refresh()` 原先直接按 jsonl 文件 `lastModified` 判定状态：

```swift
let activeThreshold: TimeInterval = 30
let recentThreshold: TimeInterval = 24 * 60 * 60

if age < activeThreshold {
    status = .active
} else if age < recentThreshold {
    status = .recentlyIdle
} else {
    status = .archived
}
```

这个逻辑的问题：

- Claude Terminal 还开着，但如果暂时没有写 `.jsonl`，30 秒后就会变 idle。
- 这不符合用户心智：只要 Terminal/Claude 进程还存在，就应该是 active/running。

修复后 `refresh()` 改为：

```swift
var scanned = SessionScanner.scan()
let candidateIds = Set(scanned.flatMap { $0.sessions.map(\.id) })
let activeIds = ProcessDetector.shared.detectActiveSessionIds(candidateIds: candidateIds)
ProcessDetector.shared.applyStatuses(activeIds: activeIds, to: &scanned)
self.islands = scanned
```

新的状态语义：

```text
当前进程中仍存在该 Claude session id
→ active

否则 lastModified < 24h
→ recentlyIdle

否则
→ archived
```

## 3. 代码改动清单

### 3.1 `SessionCove/UI/Window/CovePanel.swift`

为了增强 nonactivating panel 内按钮点击可靠性，加入：

```swift
override var canBecomeKey: Bool { true }
override var canBecomeMain: Bool { false }

override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown || event.type == .rightMouseDown {
        makeKey()
    }
    super.sendEvent(event)
}
```

说明：

- 这不是 RUN/RESUME 最终根因，但保留是合理的。
- 作用是让 panel 在鼠标事件进入时成为 key window，提高 Button / TextInput 交互稳定性。
- 不改变 panel 的主窗口行为。

### 3.2 `SessionCove/Core/CoveViewModel.swift`

`resumeSession(_:)` 增加点击确认日志：

```swift
func resumeSession(_ session: SessionRecord) {
    print("[CoveViewModel] resumeSession tapped: \(session.id)")
    SessionResumer.resume(session: session)
}
```

`refresh()` 改为使用进程检测结果应用状态：

```swift
@MainActor
func refresh() async {
    var scanned = SessionScanner.scan()
    let candidateIds = Set(scanned.flatMap { $0.sessions.map(\.id) })
    let activeIds = ProcessDetector.shared.detectActiveSessionIds(candidateIds: candidateIds)
    ProcessDetector.shared.applyStatuses(activeIds: activeIds, to: &scanned)
    self.islands = scanned
}
```

### 3.3 `SessionCove/Services/SessionResumer.swift`

关键修复：

- `ps` pipe 改为先读取 stdout，再 `waitUntilExit()`。
- 增加 TTY lookup 日志。
- 保持 iTerm2 TTY focus AppleScript。

核心片段：

```swift
try process.run()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
process.waitUntilExit()
```

而不是：

```swift
try process.run()
process.waitUntilExit()
let data = pipe.fileHandleForReading.readDataToEndOfFile()
```

### 3.4 `SessionCove/Services/ProcessDetector.swift`

修复和增强：

1. 同样修复 `ps` pipe 读取顺序，避免潜在阻塞。
2. 增加 `candidateIds` 参数，允许匹配当前扫描出的 session ids。
3. 支持两种 active 检测：
   - `--resume <sessionId>`。
   - 命令行中直接包含 candidate session id。
4. 新增/保留 `applyStatuses(activeIds:to:)`，将进程检测和 lastModified 结合。

当前逻辑：

```swift
if activeIds.contains(session.id) {
    status = .active
} else if now.timeIntervalSince(session.lastModified) < recentThreshold {
    status = .recentlyIdle
} else {
    status = .archived
}
```

## 4. 验证记录

### 4.1 构建验证

执行：

```bash
cd /Users/lipu/Work/session-cove
swift build -c release
```

结果：成功。

### 4.2 RUN/RESUME 验证

用户从终端启动 app 后，点击一级菜单 RUN 和二级菜单 RESUME，日志显示：

```text
[CoveViewModel] resumeSession tapped: 2ea210cc-9c38-4ad3-85d5-aa579c338801
[SessionResumer] resume called for session: 2ea210cc-9c38-4ad3-85d5-aa579c338801 project: /Users/lipu/Work/Session-cove
[SessionResumer] Starting TTY lookup
[SessionResumer] ps exited with status: 0
[SessionResumer] TTY lookup result: ttys003
[SessionResumer] Executing focus script for TTY: /dev/ttys003
[SessionResumer] Successfully focused iTerm2 session
```

结论：

- Button action 已触发。
- TTY lookup 成功。
- iTerm2 session 聚焦成功。

### 4.3 active 状态验证建议

手动验证步骤：

1. 启动 Session Cove：

```bash
pkill -x SessionCove
cd /Users/lipu/Work/session-cove
swift run SessionCove
```

2. 点击 RUN / RESUME 打开或聚焦 Claude Terminal。
3. 不操作 Claude，等待 1-2 分钟。
4. 观察该 session / island 是否仍保持 active，而不是变黄。
5. 关闭对应 Terminal 后，等待下一轮刷新，才应该降级为 recentlyIdle。

## 5. 当前保留的临时日志

当前代码仍有一些诊断日志：

- `[CoveViewModel] resumeSession tapped: ...`
- `[SessionResumer] resume called ...`
- `[SessionResumer] Starting TTY lookup`
- `[SessionResumer] ps exited with status: ...`
- `[SessionResumer] TTY lookup result: ...`
- `[SessionResumer] Successfully focused iTerm2 session`

短期建议保留，直到 RUN/RESUME 和 active 状态稳定一段时间。

后续产品化可以改为：

- 成功路径少打或不打日志。
- 失败路径保留详细日志。
- 或引入 debug flag 控制。

## 6. 后续注意事项

### 6.1 不要再把 active 判定退回纯 lastModified

纯 `lastModified < 30s` 只能表示“最近有输出”，不能表示“terminal 仍在运行”。

正确 active 判断应优先基于进程存在性：

```text
process alive > recent file modification > archive age
```

### 6.2 所有读取大量 Process stdout 的地方都要避免先 wait 再 read

以下顺序危险：

```swift
process.run()
process.waitUntilExit()
readDataToEndOfFile()
```

应使用：

```swift
process.run()
readDataToEndOfFile()
process.waitUntilExit()
```

或异步读取 pipe。

### 6.3 iTerm2 聚焦应继续按 TTY 匹配

因为用户期望：

- 如果已有对应 terminal，就定位到它。
- 只有 terminal 已关闭时才新开。

TTY 匹配是当前最可靠路径。

### 6.4 如果未来支持 Terminal.app 现有窗口聚焦

当前现有窗口聚焦主要针对 iTerm2。Terminal.app fallback 主要用于新开。

如果用户开始使用 macOS Terminal.app 运行 Claude，则后续需要增加 Terminal.app 根据 tty/process/window 的聚焦逻辑。

## 7. 一句话总结

本轮真正修掉的是两个“看起来像 UI 问题、实际是系统进程/管道问题”的 bug：RUN/RESUME 卡住是 `ps` pipe 读取顺序导致的潜在阻塞；会话误变黄是 active 状态只看 jsonl 更新时间、没有优先看 Claude terminal 进程是否仍存在。