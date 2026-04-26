# Claude Code StatusLine — Catppuccin Mocha

A dual-line status bar for [Claude Code](https://claude.ai/code) built on the Catppuccin Mocha color scheme, with a **pace delta indicator** and optional Gemini/Codex CLI launch banners.

```
Sonnet 4.6 │ ██████░░░░ 53% │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ 38m50s │ $2.05
project    │ main +3 ~15    │ ⚡reviewer │ vim:INSERT │ effort:high │ +57/-10
```

## Features

| Feature | Description |
|---------|-------------|
| **Dual-line layout** | Line 1: runtime metrics · Line 2: project context |
| **Pace delta `⇡/⇣`** | Shows whether quota burns faster (⇡ red) or slower (⇣ green) than the sustainable rate |
| **Reset countdown** | Time until 5h window resets: `重置 2h30m` |
| **7-day rate limit** | Second rate-limit tier displayed alongside 5h |
| **Context bar** | `██████░░░░ 53%` with color thresholds (green/yellow/red) |
| **Vim mode** | INSERT (green) · VISUAL (pink) · NORMAL (yellow) |
| **Agent badge** | `⚡agent-name` when running with `--agent` |
| **Effort badge** | `effort:high/xhigh/max` |
| **Worktree badge** | `[wt:name]` in worktree sessions |
| **Single-line mode** | `CC_SL_LINES=1` for narrow terminals |
| **Gemini banner** | Live usage display on `g` alias |
| **Codex banner** | Cached usage display on `cx` alias (stale-while-revalidate) |
| **~37ms execution** | Single `jq` call replaces 8 separate invocations |

## Prerequisites

- [jq](https://jqlang.github.io/jq/) — JSON parsing
- `bc` — floating-point cost comparison
- `git` — branch/status info (optional)

```bash
brew install jq bc git
```

## Installation

### One-line install

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

Then restart Claude Code.

### Manual install

```bash
# Copy scripts
install -m 755 statusline.sh    ~/.claude/statusline.sh
install -m 755 gemini-banner.sh ~/.claude/gemini-banner.sh
install -m 755 codex-banner.sh  ~/.claude/codex-banner.sh

# Add to ~/.claude/settings.json
jq '. + {"statusLine": {"type":"command","command":"~/.claude/statusline.sh","padding":2}, "refreshInterval": 60}' \
  ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### Gemini / Codex banners (optional)

Add to `~/.zshrc`:

```bash
# Gemini CLI wrapper — shows live usage on launch
unalias g 2>/dev/null
g() { ~/.claude/gemini-banner.sh; gemini "$@"; }

# Codex CLI wrapper — shows cached usage on launch
unalias cx 2>/dev/null
cx() { ~/.claude/codex-banner.sh; codex "$@"; }
```

> **Note**: Codex banner requires [CodexBar](https://github.com/example/CodexBar) at
> `~/Downloads/CodexBar.app/Contents/Helpers/CodexBarCLI`. Edit `codex-banner.sh` to
> change the path if installed elsewhere.

## Configuration

All options are environment variables with sensible defaults — no config file needed.

| Variable | Default | Description |
|----------|---------|-------------|
| `CC_SL_LINES` | `2` | `1` = single-line (narrow terminal), `2` = dual-line |
| `CC_SL_SHOW_PACE` | `1` | `0` = hide pace delta indicator |
| `CC_SL_SHOW_RESET` | `1` | `0` = hide reset countdown |
| `CC_SL_SHOW_VIM` | `1` | `0` = hide Vim mode badge |
| `CC_SL_SHOW_AGENT` | `1` | `0` = hide Agent badge |
| `CC_SL_SHOW_EFFORT` | `1` | `0` = hide Effort badge |
| `CC_SL_RL_WARN_PCT` | `60` | Rate limit yellow threshold |
| `CC_SL_RL_DANGER_PCT` | `85` | Rate limit red threshold |
| `CC_SL_PACE_THRESHOLD` | `5` | Minimum pace delta to display (percentage points) |

Set them in `~/.zshrc` or per-session:

```bash
# Permanent: add to ~/.zshrc
export CC_SL_LINES=1             # narrow terminal
export CC_SL_RL_WARN_PCT=50      # warn earlier

# Per-session override
CC_SL_LINES=1 claude .
```

## How Pace Delta Works

The `⇡/⇣` indicator answers: *"Am I burning quota faster than the clock?"*

```
delta = used_pct − (elapsed_seconds / 18000) × 100
```

- `⇡25p%` (red) — used 25 percentage points more than the time-proportional expected amount
- `⇣25p%` (green) — 25 points below the expected pace; quota will last the full window
- Hidden when `|delta| < 5` (normal fluctuation)

Credit: algorithm inspired by [Astro-Han/claude-lens](https://github.com/Astro-Han/claude-lens).

## Comparison

| Feature | This project | [claude-hud](https://github.com/jarrodwatts/claude-hud) | [claude-lens](https://github.com/Astro-Han/claude-lens) | [CCometixLine](https://github.com/Haleclipse/CCometixLine) |
|---------|:---:|:---:|:---:|:---:|
| Dual-line layout | ✅ | ✅ | ❌ | ✅ |
| Pace delta | ✅ | ❌ | ✅ | ❌ |
| Catppuccin Mocha | ✅ | ❌ | ❌ | partial |
| Codex/Gemini banners | ✅ | ❌ | ❌ | ❌ |
| Reset countdown | ✅ | ❌ | ✅ | ❌ |
| 7-day rate limit | ✅ | ✅ | ❌ | ✅ |
| Zero dependencies | ✅ | ❌ (npm) | ✅ | ❌ (Rust/npm) |
| Single-line fallback | ✅ | ❌ | N/A | ✅ |
| macOS bash 3.2 compat | ✅ | N/A | ✅ | N/A |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local testing workflow, commit conventions, and PR checklist.

## License

[MIT](LICENSE)
