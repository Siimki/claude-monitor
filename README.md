# Claude Monitor

A small Mac app that lives in the menu bar (top right of your screen).
It shows how much of your Claude usage limit you have used, and when it resets.

## What you see

- **5-hour limit**: how much you used in the last 5 hours
- **Weekly limit**: how much you used this week
- **Reset timer**: how long until each limit resets
- **Codex usage** (optional): same idea, for OpenAI Codex, if you use it

## How it works

1. You use Claude Code as normal.
2. After each answer, Claude Code sends usage numbers to a small helper program.
3. The helper saves these numbers to a file on your Mac.
4. The menu bar app watches that file and updates right away.

```
Claude Code  →  helper  →  usage file  →  menu bar app
```

For Codex, the app reads the log files Codex already writes on your Mac.

## Good to know

- The app does **not** use the internet. It only reads files on your Mac.
- Numbers update only after you use Claude Code. If you use Claude on the web
  or another device, you will see the change after your next Claude Code answer.
- If you already have your own status line in Claude Code, it still works.
  The helper passes the data on to it.

## What you need

- macOS 14 or newer
- Claude Code 2.1.80 or newer
- A Claude Pro or Max subscription

## Install

```sh
./scripts/make-app.sh --install
```

This builds the app, puts it in `~/Applications`, sets up the helper and starts the app.

## Uninstall the helper

```sh
~/Applications/ClaudeMonitor.app/Contents/Helpers/ClaudeMonitorBridge --uninstall
```

This puts your old Claude Code status line back.

## More details

See [docs/DETAILS.md](docs/DETAILS.md) for the technical explanation.
