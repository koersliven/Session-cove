# CLAUDE.md — Session Cove

> 项目级 AI 指令。本地开发用，不入开源仓库（`.gitignore` 已排除 `.claude/`）。

## 项目概述

Session Cove — macOS 像素画风格 notch app。管理 Claude Code 会话：在 notch 区域展示项目岛屿，hover 展开会话列表，点击恢复终端中的 claude 进程。

- **平台:** macOS 14+ (SwiftUI + AppKit NSPanel)
- **构建:** `swift build` / `swift run SessionCove`
- **仓库:** github.com/koersliven/Session-cove / gitlab:lipu.wzw/Session-cove

## 日常命令

```bash
cd /Users/lipu/Work/Session-cove

# 开发
swift run SessionCove          # debug 启动
swift build                    # 仅编译
swift test                     # 测试

# Release
bash scripts/bundle.sh         # 编译 universal .app → .build/release/
UNIVERSAL=0 bash scripts/bundle.sh  # 单架构快速迭代
bash scripts/make-release.sh   # 一步打包 zip → dist/
VERSION=0.2.0 bash scripts/make-release.sh

# 进程
pgrep -lf "SessionCove$"       # 查 PID
kill <pid>                     # 停

# Git
git push github main && git push origin main   # 双仓库推送
```

## 架构速查

```
CoveRootView
├─ PetWindowController         NSPanel 48×48 可拖拽
├─ CoveModeWindowController    NSPanel fullWidth×750 notch 面板
│   ├─ NotchHoverDetector      光标检测 + 状态机
│   └─ CoveNotchView           closed / peeking / opened 三态
├─ CovePanel                   主面板 520×480
└─ PermissionInterruptionView  权限审批
```

### 核心文件

| 文件 | 职责 |
|------|------|
| `SessionCove/Core/CoveViewModel.swift` | 核心状态机：uiMode、islands、session CRUD |
| `SessionCove/Services/SessionResumer.swift` | 终端 AppleScript：iTerm → Terminal.app 两级聚焦 |
| `SessionCove/Services/SessionScanner.swift` | 扫描 `~/.session-cove/requests/*.jsonl` |
| `SessionCove/Services/SessionParser.swift` | JSONL → SessionRecord（含 jsonlPath） |
| `SessionCove/Services/SessionWatcher.swift` | FSEvents 监听文件变更 |
| `SessionCove/Services/ProcessDetector.swift` | ps 扫描活跃 claude 进程 |
| `SessionCove/UI/Components/PixelArtSprites.swift` | `PixelSpriteCache` NSImage 缓存 |
| `SessionCove/UI/Views/HarborMapOverviewView.swift` | 中央 harbor 地图（compact 模式用于 notch peeking） |
| `SessionCove/Core/Notch/NotchWindowController.swift` | Constant-panel notch 窗口 |
| `scripts/bundle.sh` | universal .app bundle |
| `scripts/make-release.sh` | 一键 release zip |

### 设计约定

1. **像素美学一致性** — PixelPalette 色板、monospaced 字体、PixelBox 边框
2. **乐观更新 + FSEvents 兜底** — UI 先响应用户操作，后端 idempotent 刷新
3. **不做模态确认框** — 删除走废纸篓（可逆）
4. **两级终端 fallback** — iTerm → Terminal.app → launchNewSession
5. **Constant panel** — Notch 窗口 frame 不变，形变在 SwiftUI 内完成

## 改动后必做 — Memory & Changelog 更新

**每次代码改动提交后，必须执行以下步骤：**

1. **更新 `.claude/memory.md`** — 如果本次改动涉及：
   - 新增/删除文件或模块
   - 架构变化（窗口、数据流、状态机）
   - 设计决策或约定变更
   - 性能优化方法
   - 新的外部依赖
   → 更新 memory.md 中对应的章节，保持与代码库一致

2. **更新 `.claude/CHANGELOG.md`** — 每次 commit 后追加条目：
   ```markdown
   ## YYYY-MM-DD — `<commit>` 标题
   - 改动摘要
   - 设计决策
   - **影响文件:** xxx
   ```

3. **更新本文件 (CLAUDE.md)** — 如果项目概述/命令/架构/约定发生变化

**更新原则：**
- 不要重复代码 diff 已能表达的内容
- 重点记录 WHY（为什么这样做）、WHERE（关键文件位置）、FLOW（调用链路）
- 目标：让下一次会话的 AI 用 1 轮读取就能理解项目全景

## 相关本地文件

| 文件 | 内容 |
|------|------|
| `.claude/memory.md` | 项目完整记忆：架构、文件索引、设计约定、性能关键点 |
| `.claude/CHANGELOG.md` | 按时间倒序的改动记录 |
| `memory-plan/` | 历史计划和备案文档 |
