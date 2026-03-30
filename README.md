# ProcessGuard

Lightweight macOS menubar app that monitors CPU-heavy processes and energy drainers. Built to catch runaway processes before they drain your battery overnight.

## Features

- **Top 10 CPU processes** — color-coded (red >50%, yellow >20%, green)
- **Top 5 energy drainers** — shows power impact from `top`
- **Kill with confirmation** — SIGTERM with SIGKILL fallback, confirmation dialog with process details
- **Investigate with Claude** — opens Terminal with Claude Code pre-prompted to diagnose why a process is using so much CPU
- **Alert icon** — menubar icon changes when any process exceeds 50% CPU
- **30-minute polling** — near-zero CPU between scans
- **Manual refresh** — Cmd+R or click "Refresh Now"

## Install

```bash
git clone https://github.com/bamboozledkitty/process-guard.git
cd process-guard
bash install.sh
```

This compiles the binary, copies it to `~/.local/bin`, and creates a LaunchAgent so it starts on login.

Or build manually:

```bash
swiftc -O -o ProcessGuard Sources/ProcessGuard/main.swift -framework AppKit
cp -r ProcessGuard /Applications/ProcessGuard.app/Contents/MacOS/
```

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- [Claude Code](https://claude.ai/claude-code) (for the "Investigate with Claude" feature)

## Why this exists

macOS background processes (plugin daemons, Shortcuts automations, orphaned server processes) can silently peg the CPU and drain a MacBook's battery to zero overnight. Activity Monitor itself uses 2-5% CPU polling constantly. ProcessGuard polls once every 30 minutes and uses 0% CPU in between.

## Technical notes

- Uses `posix_spawn` instead of Foundation's `Process` class to avoid blocking the main thread's run loop (Foundation.Process/NSTask causes the app to become unresponsive in menubar apps)
- Energy impact data comes from `top -l 2 -stats pid,power,command` (requires two samples for accurate readings)
- 89KB binary, ~40MB RSS (AppKit baseline), 0.0% CPU when idle
