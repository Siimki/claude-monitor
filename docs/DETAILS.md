# Claude Monitor

A small macOS menu-bar app for Claude subscription usage. It shows the rolling
5-hour limit, weekly limit, and live reset countdowns.

## How it works

Claude Code 2.1.80 and newer includes subscription rate limits in the JSON sent
to status-line commands after a normal Claude response:

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
```

Claude Monitor installs a lightweight status-line bridge that writes those
fields to `~/Library/Application Support/ClaudeMonitor/usage.json`. The menu-bar
app watches that directory and updates as soon as the cache changes.

The app is event-driven: it watches this cache and does not launch Claude Code,
poll the network, or run a periodic refresh timer. The reset countdown advances
locally while the popover is visible. Usage changes made through Desktop, Cowork,
web, or another device appear after the next Claude Code response publishes a
status-line event.

If a status-line command already exists, the installer saves it and the bridge
forwards the original JSON to it after updating the cache. Run the bridge with
`--uninstall` to restore the previous status-line configuration.

## Codex usage

The popover also shows OpenAI Codex CLI usage beneath the Claude ring, when Codex
data is available. Codex writes a `token_count` event with a `rate_limits` object
into `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` after each response, so no CLI
launch or PTY scraping is needed. The app checks those logs at launch and when the
popover opens. Unchanged files are skipped, and changed files are searched backward
from their tails instead of being reread in full.

The reader is generic over Codex's `primary`/`secondary` windows and labels each by
its `window_minutes` (5-hour ≈ 300, weekly ≈ 10080, monthly ≈ 43800), so if OpenAI
adds a 5-hour or weekly window it renders without code changes. Both absolute
(`resets_at`) and relative (`resets_in_seconds`) reset forms are supported. If a
Codex build logs `rate_limits: null`, the section stays hidden. Set `CODEX_HOME` to
point at a non-default config directory.

## Requirements

- macOS 14+
- Claude Code 2.1.80+ signed into a Claude.ai Pro or Max subscription
- Swift 6 toolchain (Xcode or Command Line Tools) when building from source

The `rate_limits` field appears after the first API response in a Claude Code
session.

## Build and install

```sh
./scripts/make-app.sh --install
```

This builds the app, installs it to `~/Applications`, configures the status-line
bridge in `~/.claude/settings.json`, and launches the menu-bar app. Claude Code
responses then publish usage updates to the app.

To build without installing:

```sh
./scripts/make-app.sh
ClaudeMonitor.app/Contents/Helpers/ClaudeMonitorBridge --install
open ClaudeMonitor.app
```

To remove the bridge and restore the previous status-line setting:

```sh
~/Applications/ClaudeMonitor.app/Contents/Helpers/ClaudeMonitorBridge --uninstall
```

## Verify

```sh
swift run MonitorCheck
swift build
```

The bridge can be tested without changing Claude settings or making a model
request by passing representative status-line JSON and overriding the cache path:

```sh
CLAUDE_MONITOR_CACHE_PATH=/tmp/claude-monitor-usage.json \
  swift run ClaudeMonitorBridge <<'JSON'
{"rate_limits":{"five_hour":{"used_percentage":24,"resets_at":1789038000},"seven_day":{"used_percentage":41,"resets_at":1789466400}}}
JSON
```

## Project layout

- `Sources/ClaudeMonitorCore/UsageCache.swift` decodes status-line JSON and owns
  the cache format.
- `Sources/ClaudeMonitorBridge/main.swift` installs the integration, writes the
  cache, and preserves an existing status line.
- `Sources/ClaudeMonitor/UsageStore.swift` watches status-line cache events and
  owns menu-bar state.
- `Sources/ClaudeMonitorCore/CodexUsage.swift` and `CodexUsageReader.swift` model
  Codex windows and read the freshest snapshot from `~/.codex/sessions` rollout logs.
- `Sources/ClaudeMonitor/CodexStore.swift` and `CodexSection.swift` own Codex
  menu-bar state and render the stacked Codex section in the popover.
- `Sources/MonitorCheck/main.swift` contains deterministic decoding, cache, and
  countdown checks. `swift run MonitorCheck codex-live` reads real Codex logs.
