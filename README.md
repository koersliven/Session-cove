# Session Cove

A macOS menu bar app that gives you a bird's-eye view of all your Claude Code sessions across different working directories — visualized as islands in a cove.

## What is Session Cove?

When you use Claude Code across many projects, sessions scatter across directories and terminals. Session Cove scans `~/.claude/projects/` and shows every session grouped by project, with status indicators and one-click resume.

**Visual metaphor:** Each project directory is a small island. Sessions are dots on the island — green for active, yellow for recent, gray for archived. The whole view is your personal cove of coding sessions.

## Features

- **Global session discovery** — Automatically finds all Claude Code sessions across all projects
- **Status detection** — Distinguishes active, recently idle, and archived sessions
- **One-click resume** — Opens a terminal with `claude --resume <id>` in the correct directory
- **Real-time updates** — Detects new sessions and activity changes via FSEvents
- **Notch-attached panel** — Floats at the top of your screen, click to expand
- **Terminal support** — Works with iTerm2, Ghostty, and Terminal.app

## Requirements

- macOS 14.0 (Sonoma) or later
- Claude Code installed

## Build from Source

```bash
cd session-cove

# Option A: Build with Swift Package Manager
swift build -c release
./scripts/bundle.sh        # Creates .app bundle
open ".build/release/Session Cove.app"

# Option B: Open in Xcode (via SPM)
open Package.swift
# Press ⌘R to run

# Option C: Generate Xcode project (requires xcodegen)
brew install xcodegen
xcodegen generate
open SessionCove.xcodeproj
```

## How It Works

Session Cove reads from `~/.claude/projects/` where Claude Code stores conversation transcripts:

```
~/.claude/projects/
  -Users-you-Work-project-a/
    abc123.jsonl    ← one session
    def456.jsonl    ← another session
  -Users-you-Work-project-b/
    ...
```

Each `.jsonl` file's first few lines contain the session metadata (first message, timestamp, working directory). Session Cove parses just the headers — never the full transcript.

## License

MIT
