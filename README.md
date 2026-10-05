# Agent Hub for Omarchy

**Agent Hub** is a unified multi-agent session monitor, prompt & token telemetry dashboard, quota burn forecasting engine, and interactive launcher for **Claude Code** and **Google Antigravity** in the Omarchy top bar.

---

## Features

### 1. Unified Status Bar Widget & Multi-Agent State Indicator
- **Themed Vector Icon**: Clean nexus mark dynamically colorized to match your active Omarchy theme foreground color via `MultiEffect`.
- **Global State Pulse**: Color-coded pulse dot reflecting real-time cross-agent execution state:
  - 🟢 **Green (Pulsing)**: Any agent is actively executing or thinking (`Working`).
  - 🔵 **Blue**: Any session is open and waiting for user input (`Waiting`).
  - ⚪ **Transparent**: All agents are idle.
- **Configurable Dynamic Badge Modes**:
  - `active` (Default): Total concurrent background sessions running across all agents (auto-hides when 0).
  - `prompts`: Total prompts executed today across all agents.
  - `tokens`: Total tokens consumed today (e.g. `124k` or `8.9M`).
  - `quota`: Lowest quota remaining percentage across all models and accounts (colored red when below threshold).
  - `off`: Minimal bar icon without text badge.
- **Multi-Agent Tooltip**: Hovering the bar icon reveals live session counts, today's combined prompt & token stats, and active models.

### 2. Tabbed Cockpit: Overview & Dedicated Agent Deep-Dives
- **Segmented Tab Switcher**: Seamlessly toggle between:
  - **Overview**: Consolidated cross-agent activity, shared quota limits, interleaved recent session feed, combined 7-day chart, and normalized tool telemetry.
  - **Claude Code**: Dedicated deep-dive for Claude Code (models, token metrics, quota limits, recent sessions).
  - **Antigravity**: Dedicated deep-dive for Google Antigravity (Gemini & 3P models, token metrics, quota limits, recent sessions).
- **Fast Keyboard Navigation**: Press `1` for Overview, `2` for Claude Code, `3` for Antigravity, or use `Tab`.

### 3. Real Token Analytics & Prompt Cache Telemetry
- **Actual Token Extraction**:
  - Claude Code: Aggregates `input_tokens`, `output_tokens`, and prompt cache creation/read tokens directly from transcript files.
  - Antigravity: Parses `input_tokens`, `output_tokens`, and `cache_read_tokens` directly from `PLANNER_RESPONSE` transcript steps.
- **Per-Agent Breakdown**: Overview tab displays side-by-side token consumption (e.g. `Claude: 45.2k · Antigravity: 8.9M`).

### 4. Consolidated Quota Limits & Reset Forecasting
- **Multi-Account Quota Grid**:
  - Claude Code: Authoritative Session (5-hour) and Weekly (7-day) quotas via Omarchy's OAuth collector.
  - Antigravity: Gemini (Weekly & 5-Hour) and Claude/GPT 3P (Weekly & 5-Hour) limits via `agy /usage`.
- **Hourly Burn-Rate Velocity**: Real-time consumption tracking (`🔥 X%/h`).
- **Intelligent Reset Projections**: Pacing calculations (`On pace · ~64% at reset` or early alerts `Tight pace · ~9% at reset`).
- **Low Quota Desktop Alerts**: Configurable desktop notification thresholds (5% to 50%) via `omarchy-notification-send`.

### 5. Interactive Session Management & Terminal Launcher
- **Unified Recent Sessions Feed**: Interleaved chronological feed of recent sessions tagged with styled agent pills (`[CLAUDE]` or `[AGY]`).
- **Quick Terminal Resume**: Click any session card or press `4`–`9` to resume in your terminal (`claude --resume <id>` or `agy --conversation <id>`).
- **Clean Process Termination**: Hover over any running session and click the red `` button to terminate the session process cleanly (`SIGTERM`).
- **New Session Launcher**: Click the `` header button or press `n` to launch a new session in your chosen terminal emulator.
- **Terminal Emulator Override**: Configurable terminal command (e.g. `foot`, `ghostty`, `kitty`, `alacritty`, or default `xdg-terminal-exec`).

### 6. Zero-Latency Live Hook Updates
- Wires lifecycle events for both agents to push instant refreshes to the bar:
  - Claude Code: `SessionStart`, `UserPromptSubmit`, `Stop`, `Notification`, `PermissionRequest`, `SessionEnd`.
  - Google Antigravity: `PreInvocation`, `PostInvocation`, `Stop` via `hooks.json`.
- **One-Click Management**: Toggle or install/remove hooks for all agents directly from the settings panel.

---

## Installation

```sh
omarchy plugin add https://github.com/BoeyCorp/agent-hub.git --enable
omarchy restart shell
```

---

## Interactions & Shortcuts

### Mouse Controls
- **Left Click**: Open/close popup panel.
- **Middle Click**: Force immediate telemetry and quota refresh.
- **Right Click**: Toggle in-popup settings view.

### Keyboard Shortcuts (when popup is open)
| Shortcut | Action |
|---|---|
| `1` | Switch to Overview tab |
| `2` | Switch to Claude Code tab |
| `3` | Switch to Antigravity tab |
| `4`–`9` | Quick-resume corresponding session in terminal |
| `n` | Launch new terminal session for active agent tab |
| `r` | Force refresh telemetry and quota limits |
| `s` | Toggle between Stats and Settings view |
| `q` or `Esc` | Close popup panel |

### IPC Commands
The widget registers an IPC target (`boeycorp.agent-hub`), callable via `omarchy-shell`:

| Action | Command |
|---|---|
| Toggle popup | `omarchy-shell boeycorp.agent-hub toggle` |
| Open popup | `omarchy-shell boeycorp.agent-hub open` |
| Close popup | `omarchy-shell boeycorp.agent-hub close` |
| Refresh telemetry | `omarchy-shell boeycorp.agent-hub refresh` |
| Open settings | `omarchy-shell boeycorp.agent-hub settings` |

---

## Configuration

Settings can be adjusted directly in the widget's in-popup settings view (right-click or press `s`) or stored in `~/.config/omarchy/shell.json`:

| Key | Type | Default | Description |
|---|---|---|---|
| `refreshIntervalSec` | integer (10–1800) | `60` | Telemetry refresh rate in seconds (scales to 10s when active) |
| `badgeMode` | enum | `"active"` | Bar badge mode (`active`, `prompts`, `tokens`, `quota`, `off`) |
| `enableClaude` | boolean | `true` | Enable Claude Code agent integration |
| `enableAntigravity` | boolean | `true` | Enable Google Antigravity agent integration |
| `defaultTab` | enum | `"overview"` | Default tab on popup open (`overview`, `claude`, `antigravity`) |
| `enableQuotaAlerts` | boolean | `true` | Send desktop notifications when quota falls below threshold |
| `quotaAlertThreshold` | integer (5–50) | `15` | Low quota percentage alert threshold |
| `terminalCommand` | string | `""` | Terminal emulator command override (blank for `xdg-terminal-exec`) |
| `recentSessionsLimit` | integer (3–15) | `6` | Initial number of recent sessions to display |

---

## Development & Testing

Run the automated test suite verifying scanner contracts, token extraction, and live hooks:

```sh
python3 -m unittest discover -s tests -v
```

---

## License

MIT © BoeyCorp & contributors
