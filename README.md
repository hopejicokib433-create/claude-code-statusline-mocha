# Claude Code StatusLine — Catppuccin Mocha

A dual-line status bar for [Claude Code](https://claude.ai/code) that shows real-time session metrics, quota pace, and project context — all in the [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) color palette.

```
Sonnet 4.6 │ ██████░░░░ 53% │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ 38m50s │ $2.05
~/m/claude-code-statusline-mocha │ main +3 ~15 │ ⚡reviewer │ vim:INSERT │ effort:high │ +57/-10
```

**Line 1** — runtime metrics: model, context window, 5h/7d rate limits with pace indicator, session duration and cost  
**Line 2** — project context: abbreviated path, git branch, agent/vim/effort badges, code line delta

> **How it works:** Claude Code pipes a JSON payload to `~/.claude/statusline.sh` on every refresh. The script parses all fields in a single `jq` call (~5ms), builds two lines with ANSI 24-bit color, and writes them to stdout. Claude Code renders them in its built-in terminal view. Your `.zshrc`, Starship, oh-my-zsh, and other shell config have zero effect on this script.

---

## Features

### Line 1 — Runtime Metrics

| Field | Example | Description |
|-------|---------|-------------|
| **Model name** | `Sonnet 4.6` | From `model.display_name` in the JSON payload |
| **Context bar** | `██████░░░░ 53%` | 10-block progress bar; green < 60%, yellow ≥ 60%, red ≥ 85% |
| **5h rate limit** | `↑5h:36%` | Percentage of 5-hour quota consumed; color-coded same as context bar |
| **Pace delta** | `⇣24p%` (green) / `⇡24p%` (red) | How much faster or slower you're burning quota vs. the sustainable linear rate |
| **Reset countdown** | `(重置 2h0m)` | Time until the 5-hour window resets |
| **7d rate limit** | `↑7d:12%` | 7-day quota consumed |
| **Duration** | `38m50s` | Total session wall-clock time |
| **Cost** | `$2.05` | Accumulated API cost; hidden when $0.00 |

### Line 2 — Project Context

| Field | Example | Description |
|-------|---------|-------------|
| **Abbreviated path** | `~/m/claude-code-statusline-mocha` | Starship-style: intermediate segments → first character; leaf preserved |
| **Git branch** | `main` | Current branch, truncated to 16 characters if long |
| **Staged files** | `+3` (green) | Number of files staged for commit |
| **Modified files** | `~15` (yellow) | Number of unstaged modified files |
| **Worktree badge** | `[wt:feature-x]` | Shown only in git worktree sessions |
| **Agent badge** | `⚡reviewer` | Shown only when Claude Code launched with `--agent <name>` |
| **Vim mode** | `vim:INSERT` | Color-coded: INSERT=green, VISUAL=pink, NORMAL=yellow |
| **Effort badge** | `effort:high` | Shown only for `high`, `xhigh`, or `max` effort levels |
| **Code delta** | `+57/-10` | Lines added (green) / removed (red) in this session |

### Pace Delta — What It Means

The `⇡/⇣` indicator answers: *"Am I burning quota faster or slower than the clock?"*

The 5-hour window is 18,000 seconds. If you've used 60% of quota but only 20% of the time has elapsed (1 hour), you're burning 3× faster than sustainable.

```
delta = used_pct − (elapsed_seconds / 18000) × 100
```

| Display | Color | Meaning |
|---------|-------|---------|
| `⇡24p%` | Red | 24 percentage points over the sustainable pace — quota may run out early |
| `⇣24p%` | Green | 24 percentage points under pace — quota will last the full window |
| (hidden) | — | Delta within ±5pp — normal fluctuation |

Credit: algorithm from [Astro-Han/claude-lens](https://github.com/Astro-Han/claude-lens).

---

## Prerequisites

| Tool | Required | Install |
|------|:--------:|---------|
| `jq` | **Yes** | `brew install jq` / `apt install jq` |
| `bc` | Yes | Ships with macOS CLT; `apt install bc` on Linux |
| `git` | For git fields | Ships with macOS Xcode CLT |

---

## Installation

### One-line install

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

Then **restart Claude Code**.

`install.sh` will:
- Check for `jq`, `bc`, `git`
- Back up your existing `~/.claude/statusline.sh` to `statusline.sh.bak`
- Copy the three scripts to `~/.claude/` with executable permissions
- Merge `statusLine` and `refreshInterval: 60` into `~/.claude/settings.json` without overwriting your other settings

### Manual install

```bash
# Copy scripts
install -m 755 statusline.sh    ~/.claude/statusline.sh
install -m 755 gemini-banner.sh ~/.claude/gemini-banner.sh
install -m 755 codex-banner.sh  ~/.claude/codex-banner.sh

# Merge settings (preserves existing settings)
jq '. + {
  "statusLine": {"type":"command","command":"~/.claude/statusline.sh","padding":2},
  "refreshInterval": 60
}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### Gemini / Codex banners (optional)

These are shell wrapper functions, not part of the Claude Code statusline. They print a usage summary line when you launch Gemini CLI or Codex CLI.

Add to `~/.zshrc`:

```bash
# Gemini CLI wrapper — prints live quota on launch (~2.5s API call)
unalias g 2>/dev/null
g() { ~/.claude/gemini-banner.sh; gemini "$@"; }

# Codex CLI wrapper — prints cached quota on launch (1h stale-while-revalidate cache)
unalias cx 2>/dev/null
cx() { ~/.claude/codex-banner.sh; codex "$@"; }
```

> **Codex banner note:** Requires [CodexBar](https://github.com/example/CodexBar) at  
> `~/Downloads/CodexBar.app/Contents/Helpers/CodexBarCLI`. Edit the `CODEXBAR` variable in  
> `codex-banner.sh` if installed elsewhere. The banner still works without CodexBar — it just won't show usage data.

---

## Configuration

All options are environment variables with defaults. No config file is needed.

| Variable | Default | Description |
|----------|---------|-------------|
| `CC_SL_LINES` | `2` | `1` = single-line mode (narrow terminals), `2` = dual-line |
| `CC_SL_SHOW_PACE` | `1` | `0` = hide pace delta indicator |
| `CC_SL_SHOW_RESET` | `1` | `0` = hide reset countdown |
| `CC_SL_SHOW_VIM` | `1` | `0` = hide Vim mode badge |
| `CC_SL_SHOW_AGENT` | `1` | `0` = hide Agent badge |
| `CC_SL_SHOW_EFFORT` | `1` | `0` = hide Effort badge |
| `CC_SL_RL_WARN_PCT` | `60` | Rate limit / context bar yellow threshold (%) |
| `CC_SL_RL_DANGER_PCT` | `85` | Rate limit / context bar red threshold (%) |
| `CC_SL_PACE_THRESHOLD` | `5` | Minimum |delta| in percentage points to show pace indicator |

**Setting permanently** — add to `~/.zshrc` (Claude Code inherits these from its environment):
```bash
export CC_SL_LINES=1            # narrow terminal
export CC_SL_RL_WARN_PCT=50     # warn earlier
export CC_SL_SHOW_VIM=0         # hide vim badge
```

**Per-session override:**
```bash
CC_SL_LINES=1 claude .
```

---

## Color Scheme

All colors are from the [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) palette using 24-bit ANSI truecolor (`\033[38;2;R;G;Bm`).

| Color | Hex | Used for |
|-------|-----|----------|
| Mauve | `#cba6f7` | Model name |
| Blue | `#89b4fa` | Project path |
| Yellow | `#f9e2af` | Git branch, warnings, NORMAL vim mode |
| Green | `#a6e3a1` | Healthy context/rate limit, lines added, INSERT vim mode |
| Red | `#f38ba8` | Critical context/rate limit, lines removed, over-pace |
| Lavender | `#b4befe` | Session duration |
| Teal | `#94e2d5` | Session cost |
| Sapphire | `#74c7ec` | Context percentage |
| Peach | `#fab387` | Rate limit (normal range), Agent badge |
| Pink | `#f5c2e7` | VISUAL vim mode |
| Surface2 | `#585b70` | Separators (`│`), secondary text |

**Truecolor requirement:** These colors display correctly in the Claude Code desktop app (Electron renderer), and in all modern terminal emulators (iTerm2, Kitty, WezTerm, Alacritty, VS Code, Windows Terminal). On terminals without 24-bit truecolor support (old Terminal.app, PuTTY), colors will be approximated to the nearest 256-color value and may look different. See [DESIGN.md § Color Degradation](DESIGN.md#color-degradation--what-happens-without-truecolor) for the full compatibility matrix.

---

## Compatibility

### Shell config (oh-my-zsh, Starship, etc.)

**Zero effect.** The statusline script runs as a direct subprocess of Claude Code — it does not source `.zshrc`, `.bashrc`, or any shell configuration file. Your Starship prompt, oh-my-zsh themes, conda environments, and shell aliases have no effect on the statusline.

### Terminal emulators

The status bar is rendered **inside Claude Code's built-in terminal view** (Electron/xterm.js). When using the Claude Code desktop app, colors are always correct regardless of the terminal emulator you launch Claude Code from. When running Claude Code in a raw terminal window, colors depend on that terminal's truecolor support.

### Operating systems

| Environment | Status |
|-------------|--------|
| macOS (bash 3.2+) | ✅ Fully supported |
| Linux (bash 4+) | ✅ Fully supported |
| Windows + WSL | ✅ Fully supported (follow Linux steps inside WSL) |
| Windows native | ❌ Not supported (requires bash + POSIX tools) |

---

## Comparison

| Feature | This project | [claude-hud](https://github.com/jarrodwatts/claude-hud) | [claude-lens](https://github.com/Astro-Han/claude-lens) | [CCometixLine](https://github.com/Haleclipse/CCometixLine) |
|---------|:---:|:---:|:---:|:---:|
| Dual-line layout | ✅ | ✅ | ❌ | ✅ |
| Pace delta `⇡/⇣` | ✅ | ❌ | ✅ | ❌ |
| Reset countdown | ✅ | ❌ | ✅ | ❌ |
| 7-day rate limit | ✅ | ✅ | ❌ | ✅ |
| Catppuccin Mocha | ✅ | ❌ | ❌ | partial |
| Starship path abbrev | ✅ | ❌ | ❌ | ❌ |
| Gemini/Codex banners | ✅ | ❌ | ❌ | ❌ |
| Single-line fallback | ✅ | ❌ | N/A | ✅ |
| Zero build deps | ✅ | ❌ (npm) | ✅ | ❌ (Rust) |
| macOS bash 3.2 compat | ✅ | N/A | ✅ | N/A |

---

## Testing

```bash
# Basic: two-line output
echo '{}' | bash statusline.sh | wc -l     # → 2

# Single-line mode
CC_SL_LINES=1 bash -c 'echo "{}" | bash statusline.sh' | wc -l   # → 1

# Full realistic payload (strip ANSI for readable output)
NOW=$(date +%s)
echo "{
  \"model\": {\"display_name\": \"Sonnet 4.6\"},
  \"workspace\": {\"current_dir\": \"/Users/you/mycode/project\"},
  \"context_window\": {\"used_percentage\": 53},
  \"rate_limits\": {
    \"five_hour\": {\"used_percentage\": 36, \"resets_at\": $(($NOW + 7200))},
    \"seven_day\": {\"used_percentage\": 12}
  },
  \"cost\": {\"total_cost_usd\": 2.05, \"total_duration_ms\": 2330000,
             \"total_lines_added\": 57, \"total_lines_removed\": 10},
  \"vim\": {\"mode\": \"INSERT\"},
  \"agent\": {\"name\": \"reviewer\"},
  \"effort\": {\"level\": \"high\"}
}" | bash statusline.sh | sed 's/\x1b\[[0-9;]*m//g'

# Over-pace scenario: used=80%, only 15 minutes remaining → large positive delta
NOW=$(date +%s)
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":80,\"resets_at\":$(($NOW+900))}}}" \
  | bash statusline.sh | sed 's/\x1b\[[0-9;]*m//g'   # → should show ⇡ red

# Version
bash statusline.sh --version    # → "statusline v2.1.0"
```

---

## Technical Details

See [DESIGN.md](DESIGN.md) for:
- Complete JSON payload field reference
- Detailed explanation of every field extraction and processing step
- jq SOH delimiter strategy and the control byte bug fix
- Pace delta algorithm with worked examples
- Starship path abbreviation algorithm
- Git cache implementation
- ANSI truecolor rendering and color degradation behavior
- All critical engineering bugs encountered and their fixes
- Pending optimization backlog with priorities

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the local testing workflow, commit convention, and PR checklist.

## License

[MIT](LICENSE)
