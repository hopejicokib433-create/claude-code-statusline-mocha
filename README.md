# Claude Code StatusLine — Catppuccin Mocha

A dual-line status bar for [Claude Code](https://claude.ai/code) that shows real-time session metrics, quota pace, and project context — all in the [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) color palette.

```
Sonnet 4.6 │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ ██████░░░░ 53% │ 38m50s │ $2.05
~/m/claude-code-statusline-mocha │ main +3 ~15 │ ⚡reviewer │ vim:INSERT │ effort:high │ +57/-10
```

> **How it works:** Claude Code pipes a JSON payload to `~/.claude/statusline.sh` on every refresh. The script parses all 15 fields in a single `jq` call, builds two lines with Catppuccin Mocha 24-bit colors, and writes them to stdout. Claude Code renders them in its built-in terminal view. Your `.zshrc`, Starship, oh-my-zsh, and other shell config have zero effect on this script.

---

## Field Reference — Annotated Diagram

### Line 1 — Runtime Metrics

```
 Sonnet 4.6 │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ ██████░░░░ 53% │ 38m50s │ $2.05
     ①           ②       ③        ④          ⑤           ⑥        ⑦      ⑧       ⑨
```

| # | Example | What it means | Always shown? |
|---|---------|---------------|:---:|
| ① | `Sonnet 4.6` | **Model name** — which Claude model is active | Yes |
| ② | `↑5h:36%` | **5-hour quota used** — percentage of your 5h rolling token budget consumed | Only when data available |
| ③ | `⇣24p%` / `⇡24p%` | **Pace delta** — ⇣ green means you're 24 points *under* sustainable pace (quota will last); ⇡ red means 24 points *over* (may run out early) | Only when |delta| ≥ 5pp |
| ④ | `(重置 2h0m)` | **Reset countdown** — time until the 5h window resets and quota refreshes | Only when quota data available |
| ⑤ | `↑7d:12%` | **7-day quota used** — percentage of your weekly token budget | Only when data available |
| ⑥ | `██████░░░░` | **Context window bar** — 10 blocks showing how full the current conversation is; color changes green→yellow→red as it fills | Yes |
| ⑦ | `53%` | **Context percentage** — exact number for the bar above | Yes |
| ⑧ | `38m50s` | **Session duration** — wall-clock time since Claude Code started | Yes |
| ⑨ | `$2.05` | **Accumulated cost** — total API cost for this session | Only when > $0.00 |

**Context bar color thresholds** (configurable):

```
░░░░░░░░░░  0–69%  → green   (healthy)
░░░░░░░░░░ 70–89%  → yellow  (warning)
░░░░░░░░░░ 90–100% → red     (critical)
```

**Pace delta — how to read it:**

```
delta = used% − (elapsed_seconds / 18000) × 100

  ⇣24p%  You've used 24 percentage points LESS than the clock-proportional rate.
         Quota will comfortably last the full 5-hour window at this pace.

  ⇡24p%  You've used 24 percentage points MORE than sustainable.
         Quota may run out before the 5-hour window ends.

  (hidden)  |delta| < 5 — normal fluctuation, not worth showing.
```

---

### Line 2 — Project Context

```
 ~/m/project │ main +3 ~15 │ [wt:feat] │ ⚡reviewer │ vim:INSERT │ effort:high │ +57/-10
      ⑩         ⑪   ⑫  ⑬      ⑭             ⑮            ⑯           ⑰          ⑱
```

| # | Example | What it means | Always shown? |
|---|---------|---------------|:---:|
| ⑩ | `~/m/project` | **Current directory** — Starship-style abbreviation: intermediate segments → first letter, leaf preserved | Yes |
| ⑪ | `main` | **Git branch** — current branch name (truncated at 16 chars) | Only in git repos |
| ⑫ | `+3` (green) | **Staged files** — files added to the index (`git add`) | Only when > 0 |
| ⑬ | `~15` (yellow) | **Modified files** — files changed but not yet staged | Only when > 0 |
| ⑭ | `[wt:feat]` | **Worktree name** — shown only when running inside a git worktree | Only in worktrees |
| ⑮ | `⚡reviewer` | **Agent name** — shown only when Claude Code launched with `--agent <name>` | Only in agent mode |
| ⑯ | `vim:INSERT` | **Vim mode** — INSERT (green), VISUAL (pink), NORMAL (yellow) | Only when Vim mode active |
| ⑰ | `effort:high` | **Effort level** — shown only for `high`, `xhigh`, or `max` | Only for high effort |
| ⑱ | `+57/-10` | **Code delta** — lines added (green) / removed (red) in this session | Only when > 0 |

**Path abbreviation example:**

```
/Users/wenbin/mycode/jupyter/007/project
          ↓
~/m/j/0/project
          ↑
          Each intermediate segment → its first character.
          The last segment is always kept in full.
          Paths ≤ 28 characters are shown as-is.
```

---

## Features

| Feature | Description |
|---------|-------------|
| **Dual-line layout** | Line 1: quota & context · Line 2: project context |
| **Pace delta `⇡/⇣`** | Shows if quota is burning faster (⇡ red) or slower (⇣ green) than the sustainable rate |
| **Reset countdown** | Time until 5h window resets: `(重置 2h30m)` |
| **7-day rate limit** | Second rate-limit tier displayed alongside 5h |
| **Context bar** | `██████░░░░ 53%` with green/yellow/red thresholds |
| **Vim mode** | INSERT (green) · VISUAL (pink) · NORMAL (yellow) |
| **Agent badge** | `⚡agent-name` when running with `--agent` |
| **Effort badge** | `effort:high/xhigh/max` |
| **Worktree badge** | `[wt:name]` in git worktree sessions |
| **Single-line mode** | `CC_SL_LINES=1` for narrow terminals |
| **Gemini banner** | Live quota display on `g` alias |
| **Codex banner** | Cached quota display on `cx` alias |
| **~5ms execution** | Single `jq` call; multi-line output avoids all IFS/delimiter issues |

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
install -m 755 statusline.sh    ~/.claude/statusline.sh
install -m 755 gemini-banner.sh ~/.claude/gemini-banner.sh
install -m 755 codex-banner.sh  ~/.claude/codex-banner.sh

jq '. + {
  "statusLine": {"type":"command","command":"~/.claude/statusline.sh","padding":2},
  "refreshInterval": 60
}' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

### Gemini / Codex banners (optional)

Add to `~/.zshrc`:

```bash
unalias g 2>/dev/null
g() { ~/.claude/gemini-banner.sh; gemini "$@"; }

unalias cx 2>/dev/null
cx() { ~/.claude/codex-banner.sh; codex "$@"; }
```

> **Codex banner note:** Requires [CodexBar](https://github.com/example/CodexBar) at  
> `~/Downloads/CodexBar.app/Contents/Helpers/CodexBarCLI`. Edit the `CODEXBAR` variable in  
> `codex-banner.sh` if installed elsewhere.

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CC_SL_LINES` | `2` | `1` = single-line (narrow terminal), `2` = dual-line |
| `CC_SL_SHOW_PACE` | `1` | `0` = hide pace delta |
| `CC_SL_SHOW_RESET` | `1` | `0` = hide reset countdown |
| `CC_SL_SHOW_VIM` | `1` | `0` = hide Vim mode badge |
| `CC_SL_SHOW_AGENT` | `1` | `0` = hide Agent badge |
| `CC_SL_SHOW_EFFORT` | `1` | `0` = hide Effort badge |
| `CC_SL_RL_WARN_PCT` | `60` | Yellow threshold for context bar and rate limits |
| `CC_SL_RL_DANGER_PCT` | `85` | Red threshold |
| `CC_SL_PACE_THRESHOLD` | `5` | Minimum |delta| in percentage points to show pace indicator |
| `CC_SL_DEBUG` | `0` | `1` = write raw Claude Code JSON payload to `/tmp/statusline-debug.json` |

```bash
# Permanent — add to ~/.zshrc
export CC_SL_LINES=1
export CC_SL_RL_WARN_PCT=50

# Per-session
CC_SL_LINES=1 claude .

# Diagnose garbled output — capture real payload
CC_SL_DEBUG=1 claude .
# then inspect: cat /tmp/statusline-debug.json | jq .
```

---

## Color Scheme

All colors are [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) — 24-bit truecolor (`\033[38;2;R;G;Bm`).

| Color | Hex | Used for |
|-------|-----|----------|
| Mauve | `#cba6f7` | Model name |
| Blue | `#89b4fa` | Project path |
| Yellow | `#f9e2af` | Git branch, warnings, NORMAL vim mode |
| Green | `#a6e3a1` | Healthy bars, lines added, INSERT vim mode, under-pace |
| Red | `#f38ba8` | Critical bars, lines removed, over-pace |
| Lavender | `#b4befe` | Session duration |
| Teal | `#94e2d5` | Session cost |
| Sapphire | `#74c7ec` | Context percentage |
| Peach | `#fab387` | Rate limit (normal), Agent badge |
| Pink | `#f5c2e7` | VISUAL vim mode |
| Surface2 | `#585b70` | Separators `│`, secondary text |

**Truecolor requirement:** Colors display correctly in the Claude Code desktop app (Electron/xterm.js renderer), all modern terminal emulators (iTerm2, Kitty, WezTerm, Alacritty, VS Code, Windows Terminal). On terminals without 24-bit truecolor (old Terminal.app, PuTTY), colors approximate to the nearest 256-color value. See [DESIGN.md § Color Degradation](DESIGN.md#color-degradation--what-happens-without-truecolor) for details.

---

## Compatibility

**Shell config (oh-my-zsh, Starship, etc.):** Zero effect. The script runs as a subprocess of Claude Code, not inside your shell. It does not source `.zshrc`, `.bashrc`, or any shell config.

**Terminal emulators:** The status bar renders inside Claude Code's built-in Electron/xterm.js view. When using the Claude Code desktop app, colors are always correct regardless of the outer terminal emulator.

| Environment | Status |
|-------------|--------|
| macOS (bash 3.2+) | ✅ Fully supported |
| Linux (bash 4+) | ✅ Fully supported |
| Windows + WSL | ✅ Follow Linux steps inside WSL |
| Windows native | ❌ Requires bash + POSIX tools |

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
# Basic smoke test
echo '{}' | bash statusline.sh | wc -l          # → 2
CC_SL_LINES=1 bash -c 'echo "{}" | bash statusline.sh' | wc -l  # → 1

# Full payload with ANSI stripped
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
  \"vim\": {\"mode\": \"INSERT\"}, \"agent\": {\"name\": \"reviewer\"}, \"effort\": {\"level\": \"high\"}
}" | bash statusline.sh | sed 's/\x1b\[[0-9;]*m//g'

# Capture real Claude Code payload for debugging
CC_SL_DEBUG=1 claude .
cat /tmp/statusline-debug.json | jq .

# Version
bash statusline.sh --version    # → "statusline v2.2.0"
```

---

## Technical Details

See [DESIGN.md](DESIGN.md) for the complete implementation reference:
- Full JSON payload field specification (all 15 fields, types, presence)
- jq multi-line output strategy and why SOH delimiter was abandoned
- Pace delta algorithm with worked examples
- Starship path abbreviation with bash `${var/#$HOME/~}` bug explanation
- Git cache cross-platform implementation (`cksum` vs `md5`/`md5sum`)
- ANSI truecolor rendering and color degradation behavior
- All critical engineering bugs and their root-cause fixes
- Pending optimization backlog (P2/P3)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
