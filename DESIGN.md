# Technical Design Reference

A complete technical specification for contributors, integrators, and anyone who wants to understand exactly how every pixel of this statusline is produced.

## Table of Contents

1. [Data Pipeline Architecture](#1-data-pipeline-architecture)
2. [JSON Payload Reference — All Fields](#2-json-payload-reference--all-fields)
3. [Field Extraction — Single jq Call](#3-field-extraction--single-jq-call)
4. [Rendering Pipeline](#4-rendering-pipeline)
5. [Color System — Catppuccin Mocha Truecolor](#5-color-system--catppuccin-mocha-truecolor)
6. [Algorithms](#6-algorithms)
7. [Git Information Layer](#7-git-information-layer)
8. [Output Assembly](#8-output-assembly)
9. [Shell & Terminal Compatibility](#9-shell--terminal-compatibility)
10. [Platform Support & Installation](#10-platform-support--installation)
11. [Critical Engineering Bugs & Fixes](#11-critical-engineering-bugs--fixes)
12. [Comparison with Mature Solutions](#12-comparison-with-mature-solutions)
13. [Known Limitations](#13-known-limitations)
14. [Pending Optimization Backlog](#14-pending-optimization-backlog)

---

## 1. Data Pipeline Architecture

### How Claude Code Invokes the Script

Claude Code's `statusLine` configuration in `~/.claude/settings.json` specifies a shell command to run periodically:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 2
  },
  "refreshInterval": 60
}
```

Every `refreshInterval` seconds (default: 60), Claude Code:

1. Serializes its current internal state into a JSON object
2. Forks a child process running `/bin/bash ~/.claude/statusline.sh`
3. Pipes the JSON to the child's **stdin**
4. Reads the child's **stdout** (one or two lines)
5. Renders those lines in the status bar at the bottom of the TUI

```
Claude Code (Electron/Node.js process)
    │
    │  JSON payload → stdin
    ▼
/bin/bash ~/.claude/statusline.sh
    │
    │  one or two lines → stdout
    ▼
Status bar display (inside Claude Code's terminal renderer)
```

**Critical implication:** The script runs as a direct child of Claude Code, **not inside your interactive shell**. It does not source `.zshrc`, `.bashrc`, `.zprofile`, or any login configuration file. The only environment it inherits is what Claude Code itself has in its environment — primarily `$HOME`, `$PATH`, and a few standard variables.

### What `/bin/bash` Means on macOS

macOS ships `/bin/bash` at version **3.2** (from 2007, for GPL licensing reasons). Homebrew provides a modern bash 5.x at `/opt/homebrew/bin/bash`, but the script must use `/bin/bash` because that is what Claude Code invokes. Every bash feature used in this script is therefore constrained to be bash 3.2-compatible:

- No `mapfile` / `readarray` (bash 4+)
- No associative arrays `declare -A` (bash 4+)
- No `printf -v` with `%*s` padding — uses the `printf -v VAR "%Ns"` form which works in 3.2

---

## 2. JSON Payload Reference — All Fields

The complete JSON structure Claude Code sends to stdin. Fields marked `(conditional)` are absent when not applicable — an absent field is not the same as a null field; the script must handle both.

```json
{
  "model": {
    "display_name": "Sonnet 4.6"
  },
  "workspace": {
    "current_dir": "/Users/wenbin/mycode/project"
  },
  "context_window": {
    "used_percentage": 53.0,
    "context_window_size": 200000
  },
  "rate_limits": {
    "five_hour": {
      "used_percentage": 36.0,
      "resets_at": 1745820000
    },
    "seven_day": {
      "used_percentage": 12.0
    }
  },
  "cost": {
    "total_cost_usd": 2.05,
    "total_duration_ms": 2330000.0,
    "total_lines_added": 57.0,
    "total_lines_removed": 10.0
  },
  "vim": {
    "mode": "INSERT"
  },
  "agent": {
    "name": "reviewer"
  },
  "effort": {
    "level": "high"
  },
  "worktree": {
    "is_worktree": false,
    "name": ""
  }
}
```

### Field-by-Field Reference

| JSON Path | Type | Always Present | Description |
|-----------|------|:--------------:|-------------|
| `model.display_name` | string | Yes | Human-readable model name, e.g. `"Sonnet 4.6"` |
| `workspace.current_dir` | string | Yes | Absolute path of the current working directory |
| `context_window.used_percentage` | float | Yes | Percentage of context window consumed, 0–100 |
| `context_window.context_window_size` | integer | Yes | Total tokens in context window (e.g. 200000 or 1000000) |
| `rate_limits.five_hour.used_percentage` | float | **No** | Percentage of 5-hour quota consumed; absent early in session |
| `rate_limits.five_hour.resets_at` | integer | **No** | Unix timestamp (seconds) when the 5-hour window ends |
| `rate_limits.seven_day.used_percentage` | float | **No** | Percentage of 7-day quota consumed |
| `cost.total_cost_usd` | float | Yes | Accumulated cost in USD for this session |
| `cost.total_duration_ms` | float | Yes | Total wall-clock time in milliseconds |
| `cost.total_lines_added` | float | Yes | Lines added by edits in this session |
| `cost.total_lines_removed` | float | Yes | Lines removed by edits in this session |
| `vim.mode` | string | **No** | Current Vim mode: `"INSERT"`, `"VISUAL"`, `"NORMAL"` |
| `agent.name` | string | **No** | Agent name when launched with `--agent <name>` |
| `effort.level` | string | **No** | Effort level: `"low"`, `"medium"`, `"high"`, `"xhigh"`, `"max"` |
| `worktree.is_worktree` | boolean | Yes | Whether this is a git worktree session |
| `worktree.name` | string | **No** | Name of the worktree if `is_worktree` is true |

**Note on floats:** Claude Code serializes integer-valued numbers as JSON floats due to JavaScript's number type — `2330000` becomes `2330000.0` or even `2330000.000000000000001` due to IEEE 754 precision. The script applies `floor | tostring` in jq to truncate before any display.

---

## 3. Field Extraction — Single jq Call

### Why a Single Call Matters

Each invocation of `jq` (or any external command) requires:
1. A `fork()` system call to create a child process
2. An `execve()` to load the jq binary
3. Piping data in and out via file descriptors
4. Waiting for the child to exit

On macOS, a single jq call takes ~4–5ms. The original script called jq 8 times: **~35–40ms** wasted on process management overhead. Merging into one call brings the overhead to ~5ms — a ~7× speedup.

### The SOH Delimiter Strategy

All 15 values are extracted in a single jq call by joining them with a delimiter character, then splitting in bash via `IFS`:

```bash
IFS=$'\x01' read -r MODEL DIR CTX_PCT RL5H RL5H_RESET RL7D \
  COST_USD DURATION_MS LINES_ADDED LINES_REMOVED \
  VIM_MODE AGENT_NAME EFFORT_LEVEL IS_WORKTREE WORKTREE_NAME \
  < <(echo "$input" | jq -r \
    --arg s "$(printf '\001')" \
    '[
      (.model.display_name // "Unknown"),
      (.workspace.current_dir // ""),
      ((.context_window.used_percentage // 0) | floor | tostring),
      ((.rate_limits.five_hour.used_percentage  // "") | if type == "number" then floor | tostring else . end),
      ((.rate_limits.five_hour.resets_at        // 0)  | floor | tostring),
      ((.rate_limits.seven_day.used_percentage  // "") | if type == "number" then floor | tostring else . end),
      ((.cost.total_cost_usd      // 0) | tostring),
      ((.cost.total_duration_ms   // 0) | floor | tostring),
      ((.cost.total_lines_added   // 0) | floor | tostring),
      ((.cost.total_lines_removed // 0) | floor | tostring),
      (.vim.mode    // ""),
      (.agent.name  // ""),
      (.effort.level // ""),
      (if (.worktree.is_worktree // false) then "1" else "0" end),
      (.worktree.name // "")
    ] | join($s)')
```

**Why SOH (ASCII 0x01) as the delimiter?**

The naive approach uses `@tsv` (tab-separated values):

```bash
IFS=$'\t' read -r MODEL DIR ...   # ← BROKEN for empty fields
```

`@tsv` produces tab characters between values. The problem: in bash, `IFS` characters that are also ASCII whitespace (space, tab, newline) are subject to *whitespace collapsing* — consecutive IFS whitespace characters are treated as a single separator. This means two adjacent tabs (representing an empty field between them) collapse into one separator and the empty field silently disappears.

Empty fields are common here: `rate_limits.five_hour` is absent at the start of a session, `vim.mode` is absent when not in Vim mode, etc. With `@tsv`, all fields after the first empty field shift left by one, assigning values to wrong variables.

SOH (byte `0x01`, "Start of Header") is:
- Not in the ASCII whitespace set — bash does not collapse consecutive SOH bytes
- Not present in any realistic file path, model name, or string value
- POSIX-defined, available in all bash versions

**Why pass SOH via `--arg` instead of embedding it?**

jq silently strips literal control bytes (< 0x20) from inline string literals during source parsing. Writing `join("")` or a literal SOH byte in the source file produces an empty separator — the SOH is stripped at parse time, causing all 15 values to concatenate without any separator.

```bash
# BROKEN: jq strips the literal SOH from source code
jq -r '[.a, .b] | join("")'       # produces "ab" (no separator)

# CORRECT: pass SOH as an argument value, not a source literal
jq -r --arg s "$(printf '\001')" '[.a, .b] | join($s)'   # produces "a\x01b"
```

`$(printf '\001')` evaluates the SOH byte in bash and passes it to jq as the `$s` variable value. jq receives it as data (not source code), so it is preserved correctly.

### Per-Field Processing in jq

| Variable | jq Expression | Processing | Reason |
|----------|---------------|------------|--------|
| `MODEL` | `.model.display_name // "Unknown"` | None | String, always clean |
| `DIR` | `.workspace.current_dir // ""` | None | String path, processed later in bash |
| `CTX_PCT` | `.context_window.used_percentage // 0` | `floor \| tostring` | Float → integer string |
| `RL5H` | `.rate_limits.five_hour.used_percentage // ""` | `if type == "number" then floor \| tostring else . end` | Empty string when absent; floor when present |
| `RL5H_RESET` | `.rate_limits.five_hour.resets_at // 0` | `floor \| tostring` | Unix timestamp, may be float |
| `RL7D` | `.rate_limits.seven_day.used_percentage // ""` | Same as RL5H | Same reasoning |
| `COST_USD` | `.cost.total_cost_usd // 0` | `tostring` only — **not** floored | Needs decimal for `printf '%.2f'` |
| `DURATION_MS` | `.cost.total_duration_ms // 0` | `floor \| tostring` | Integer milliseconds |
| `LINES_ADDED` | `.cost.total_lines_added // 0` | `floor \| tostring` | Integer line count |
| `LINES_REMOVED` | `.cost.total_lines_removed // 0` | `floor \| tostring` | Integer line count |
| `VIM_MODE` | `.vim.mode // ""` | None | String enum or empty |
| `AGENT_NAME` | `.agent.name // ""` | None | String or empty |
| `EFFORT_LEVEL` | `.effort.level // ""` | None | String enum or empty |
| `IS_WORKTREE` | `if (.worktree.is_worktree // false) then "1" else "0" end` | Boolean → "1"/"0" | Bash has no native booleans |
| `WORKTREE_NAME` | `.worktree.name // ""` | None | String or empty |

---

## 4. Rendering Pipeline

### How Claude Code Displays the Status Bar

Claude Code is an Electron-based application (Node.js + Chromium). Its terminal/TUI is rendered using a built-in terminal emulator component (based on xterm.js). This component:

1. **Fully supports ANSI escape codes**, including 24-bit truecolor (`\033[38;2;R;G;Bm`)
2. Renders the statusline script's stdout in a dedicated status bar area at the bottom of the UI
3. Is **independent from the system's terminal emulator** — the Claude Code desktop app renders its own terminal view inside Chromium

This means: **when using the Claude Code desktop app, colors display correctly regardless of which terminal emulator you launch Claude Code from.** The rendering happens inside the app, not in your iTerm2/Terminal.app/Kitty window.

When using Claude Code in an **IDE extension** (VS Code, JetBrains), the statusline renders inside the IDE's integrated terminal, which also supports truecolor in all modern versions.

When using Claude Code in a **raw terminal** (no desktop app), the rendering depends on the terminal emulator's truecolor support.

### ANSI Escape Code Format

The script uses **SGR (Select Graphic Rendition)** escape sequences:

```
\033[38;2;R;G;Bm   →  Set foreground color to RGB(R,G,B)  (24-bit truecolor)
\033[0m             →  Reset all attributes
```

- `\033` is the ESC character (octal 033 = decimal 27 = hex 0x1B)
- `38;2` selects "set foreground color using 24-bit RGB"
- `R;G;B` are decimal values 0–255 for red, green, blue channels
- The closing `m` terminates the escape sequence

Example for Catppuccin Mauve (`#cba6f7` = RGB 203,166,247):
```
\033[38;2;203;166;247m
```

These are written in bash using `$'...'` quoting and `echo -e`:
```bash
Mauve='\033[38;2;203;166;247m'
echo -e "${Mauve}Sonnet 4.6${RESET}"
```

---

## 5. Color System — Catppuccin Mocha Truecolor

### Palette

Every color in the script maps directly to an official [Catppuccin Mocha](https://github.com/catppuccin/catppuccin) swatch. No ad-hoc colors are used.

| Variable | Hex | RGB | Usage |
|----------|-----|-----|-------|
| `Mauve` | `#cba6f7` | 203,166,247 | Model name |
| `Blue` | `#89b4fa` | 137,180,250 | Project path |
| `Yellow` | `#f9e2af` | 249,226,175 | Git branch, warnings, Vim NORMAL |
| `Green` | `#a6e3a1` | 166,227,161 | Context bar (healthy), lines added, Vim INSERT |
| `Red` | `#f38ba8` | 243,139,168 | Context bar (critical), lines removed, over-pace |
| `Lavender` | `#b4befe` | 180,190,254 | Session duration |
| `Teal` | `#94e2d5` | 148,226,213 | Session cost |
| `Sapphire` | `#74c7ec` | 116,199,236 | Context percentage number |
| `Peach` | `#fab387` | 250,179,135 | Rate limit (normal), Agent badge |
| `Pink` | `#f5c2e7` | 245,194,231 | Vim VISUAL mode |
| `Surface2` | `#585b70` | 88,91,112 | Separators (`│`), secondary text, reset countdown |

### Color Degradation — What Happens Without Truecolor

The script makes **no attempt to detect terminal capabilities** and has **no 256-color or 8-color fallback**. This is a deliberate simplicity tradeoff documented as a P3 improvement item.

**What actually happens** when a terminal does not support 24-bit truecolor (`\033[38;2;R;G;Bm`):

| Terminal behavior | Visual result |
|-------------------|---------------|
| Terminal ignores unknown SGR codes | Text renders with no color (plain white/default) |
| Terminal approximates to nearest 256-color | Colors look different; Catppuccin pastels map to rough approximations |
| Terminal renders garbled characters | Escape sequences appear as literal text (`[38;2;203;166;247m`) — rare, only in very old terminals |

**Affected environments:**
- macOS Terminal.app before Sonoma (macOS 14): no truecolor support → 256-color approximation
- PuTTY (all versions): no truecolor → garbled or no color
- SSH sessions to remote servers with `TERM=xterm` or `TERM=vt100`: depends on the SSH client's terminal emulation
- tmux without proper configuration: strips truecolor passthrough by default

**Unaffected environments (full color guaranteed):**
- Claude Code desktop app (Electron renderer): always truecolor regardless of outer terminal
- iTerm2, Alacritty, Kitty, WezTerm, Warp: native truecolor support
- VS Code / Cursor / JetBrains integrated terminals: truecolor support built-in
- Windows Terminal: truecolor support since 2019

**Future fix (P3):** Detect `$COLORTERM=truecolor` or `$TERM_PROGRAM` and emit 256-color escape codes (`\033[38;5;Nm`) when 24-bit is not supported.

---

## 6. Algorithms

### 6.1 Context Window Progress Bar

The 10-character block progress bar uses Unicode block characters:
- Filled: `█` (U+2588, FULL BLOCK)
- Empty: `░` (U+2591, LIGHT SHADE)

```bash
CTX_PCT_INT=${CTX_PCT%%.*}          # strip any decimal fraction
FILLED=$(( (CTX_PCT_INT + 9) / 10 ))  # round up: 53% → 6 filled blocks
EMPTY=$((10 - FILLED))
printf -v FILL_STR "%${FILLED}s"   # FILL_STR = "      " (FILLED spaces)
printf -v PAD_STR  "%${EMPTY}s"    # PAD_STR  = "    " (EMPTY spaces)
CTX_BAR="${FILL_STR// /█}${PAD_STR// /░}"   # replace spaces with block chars
```

The rounding formula `(CTX_PCT_INT + 9) / 10` is ceiling division: `53 → ceil(53/10) = 6`. This ensures the bar visually represents "at least" the current percentage.

**Color thresholds** (configurable via environment variables):

| Range | Color | Variable |
|-------|-------|----------|
| `< CC_SL_RL_WARN_PCT` (default 60%) | Green | Healthy |
| `≥ CC_SL_RL_WARN_PCT` and `< CC_SL_RL_DANGER_PCT` | Yellow | Warning |
| `≥ CC_SL_RL_DANGER_PCT` (default 85%) | Red | Critical |

### 6.2 Pace Delta Algorithm

**Purpose:** Answer the question *"Am I burning quota faster or slower than the 5-hour window can sustain?"*

The 5-hour rolling quota window resets every 18,000 seconds. If you've used 60% of your quota but only 25% of the time has elapsed (1.25 hours), you're burning 2.4× faster than sustainable — the pace delta makes this visible at a glance.

**Algorithm** (inspired by [Astro-Han/claude-lens](https://github.com/Astro-Han/claude-lens)):

```
window_start = resets_at − 18000          (seconds)
elapsed      = now − window_start         (seconds since window opened)
expected_pct = elapsed / 18000 × 100      (% that should be consumed at linear pace)
delta        = used_pct − expected_pct    (signed percentage points)
```

**Display rules:**

| Condition | Display | Color | Meaning |
|-----------|---------|-------|---------|
| `delta > +THRESHOLD` | `⇡Xp%` | Red | Over-pace: burning faster than sustainable |
| `delta < -THRESHOLD` | `⇣Xp%` | Green | Under-pace: quota will last the full window |
| `|delta| ≤ THRESHOLD` | (hidden) | — | Normal fluctuation; not worth showing |

Default `THRESHOLD = 5` percentage points (configurable via `CC_SL_PACE_THRESHOLD`).

**Bash implementation:**

```bash
NOW=$(date +%s)
ELAPSED=$(( NOW - (RESET_INT - 18000) ))
EXPECTED=$(( ELAPSED * 100 / 18000 ))         # integer division; accurate enough
DELTA=$(( RL5H_INT - EXPECTED ))
ABS_DELTA=${DELTA#-}                           # strip leading minus for abs value
if [ "$ABS_DELTA" -ge "$PACE_THRESHOLD" ]; then
  if [ "$DELTA" -gt 0 ]; then
    PACE_DISPLAY=" ${Red}⇡${ABS_DELTA}p%${RESET}"
  else
    PACE_DISPLAY=" ${Green}⇣${ABS_DELTA}p%${RESET}"
  fi
fi
```

**Guard conditions:** The pace delta is only computed when:
- `SHOW_PACE=1` (not disabled by user)
- `RL5H_RESET` is non-empty and non-zero (window data is available)
- `ELAPSED > 0` (window has started)
- `ELAPSED ≤ 18000` (still within the window; not stale data)

### 6.3 Starship-Style Path Abbreviation

**Purpose:** `/Users/wenbin/mycode/claude-code-statusline-mocha` is 47 characters — too long for a status bar. The algorithm shortens intermediate path segments to their first character while preserving the leaf (last segment) in full.

**Algorithm:**

```
/Users/wenbin/mycode/jupyter/007/project
    ↓ home replacement
~/mycode/jupyter/007/project
    ↓ each intermediate segment → first character
~/m/j/0/project
```

**Threshold:** Paths ≤ 28 characters are shown as-is (no abbreviation needed).

**Home replacement (with bash bug workaround):**

The naive `${var/#$HOME/~}` is broken on bash 3.2 when `$HOME` starts with `/`. In `${var/pattern/string}`, bash finds the first unescaped `/` after the opening `${var/` to delimit pattern from string. Since `$HOME` = `/Users/wenbin`, the `/` inside `$HOME` is consumed as the delimiter, making the pattern empty and the substitution a no-op.

```bash
# BROKEN — bash parses the / inside $HOME as the pattern/string separator
path="${full/#$HOME/~}"    # returns full path unchanged

# CORRECT — use prefix removal, then prepend ~
local stripped="${full#$HOME}"
[ "$stripped" != "$full" ] && path="~${stripped}" || path="$full"
```

**awk implementation for segment abbreviation:**

```awk
awk -F/ '{
  n = NF
  for (i=1; i<=n; i++) {
    seg = $i
    if      (i==1) printf "%s",  seg        # first segment (e.g. "~" or empty)
    else if (i==n) printf "/%s", seg        # last segment: keep full
    else if (seg)  printf "/%s", substr(seg,1,1)   # intermediate: first char only
    else           printf "/"              # empty segment (double slash)
  }
  printf "\n"
}'
```

---

## 7. Git Information Layer

### Data Sources

Git information is NOT in the Claude Code JSON payload. It is obtained by running git commands directly against the workspace directory:

| git command | Data extracted | Variable |
|-------------|----------------|----------|
| `git -C "$DIR" branch --show-current` | Current branch name | `BRANCH` |
| `git -C "$DIR" diff --cached --numstat` | Number of staged files | `STAGED` |
| `git -C "$DIR" diff --numstat` | Number of modified (unstaged) files | `MODIFIED` |

`--numstat` outputs one line per file, so `wc -l` counts the number of changed files. `--cached` limits to the index (staged changes only).

### 5-Second File Cache

Git commands are expensive for a script that runs every 60 seconds but may be invoked multiple times in quick succession (e.g., the user resizes the terminal, triggering a refresh). A file-based cache avoids running git more than once per 5 seconds:

```bash
DIR_HASH=$(printf '%s' "$DIR" | cksum | cut -d' ' -f1)
CACHE_FILE="/tmp/statusline-git-cache-${DIR_HASH}"
CACHE_MAX_AGE=5   # seconds
```

**Cache key:** `cksum` of the directory path. `cksum` is used instead of `md5` (macOS) or `md5sum` (Linux) because it is POSIX-standard and available identically on both platforms with the same output format (`checksum filesize filename`; the script uses `cut -d' ' -f1` to extract the checksum only).

**Cache freshness check:**

```bash
cache_is_stale() {
  [ ! -f "$CACHE_FILE" ] || \
  [ $(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null \
                      || stat -c %Y "$CACHE_FILE" 2>/dev/null \
                      || echo 0) )) -gt $CACHE_MAX_AGE ]
}
```

`stat -f %m` is BSD (macOS) syntax; `stat -c %Y` is GNU (Linux) syntax. The double-stat with `||` handles both platforms. If both fail (e.g., cache file doesn't exist between the check and the stat), `echo 0` returns epoch, making the cache appear stale — a safe fallback.

**Cache format:** Pipe-separated single line:
```
main|3|5
```
(branch `main`, 3 staged files, 5 modified files)

---

## 8. Output Assembly

### Line 1 — Runtime Metrics

```
Sonnet 4.6 │ ██████░░░░ 53% │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ 38m50s │ $2.05
```

Assembly order:
1. `MODEL` (Mauve) — model display name
2. `SEP` — `│` separator (Surface2)
3. `CTX_BAR` (color-coded) + `CTX_PCT_INT%` (Sapphire) — context window
4. `RL5H_SECTION` — 5h rate limit + pace delta + reset countdown (conditional)
5. `RL7D_SECTION` — 7d rate limit (conditional)
6. `SEP` — separator
7. `MINS`m`SECS`s (Lavender) — session duration
8. `COST_SECTION` — cost in USD (Teal), only if > $0.00

### Line 2 — Project Context

```
~/m/claude-code-statusline-mocha │ main +3 ~15 │ ⚡reviewer │ vim:INSERT │ effort:high │ +57/-10
```

Assembly order:
1. `ABBREV_PATH` (Blue) — Starship-abbreviated current directory
2. `GIT_SECTION` — branch (Yellow) + staged count (Green) + modified count (Yellow), conditional
3. `WORKTREE_BADGE` — `[wt:name]` (Surface2), only in worktree sessions
4. `AGENT_BADGE` — `⚡name` (Peach), only when `--agent` flag used
5. `VIM_BADGE` — `vim:MODE` (color by mode), only when Vim mode active
6. `EFFORT_BADGE` — `effort:level` (Yellow), only for high/xhigh/max
7. `CODE_STAT` — `+X/-Y` added/removed lines (Green/Red), only if > 0

### Single-Line Mode (`CC_SL_LINES=1`)

For narrow terminals, the script emits one line:

```
Sonnet 4.6 │ ██████░░░░ 53% │ ↑5h:36% ⇣24p% (重置 2h0m) │ ↑7d:12% │ 38m50s │ $2.05 │ ~/m/project │ main
```

This preserves all of Line 1 and appends only the abbreviated path and git branch from Line 2, dropping vim/agent/effort/worktree/code-stat badges to save horizontal space. The path is moved to the right because the rate limit / context / cost information is more time-sensitive and should be leftmost.

### Conditional Display Logic

| Field | Shown when |
|-------|-----------|
| Rate limit 5h | `RL5H` is non-empty after jq extraction |
| Pace delta | `SHOW_PACE=1` AND `RL5H_RESET` present AND elapsed within window |
| Reset countdown | `SHOW_RESET=1` AND `RL5H_RESET` present AND time remaining > 0 |
| Rate limit 7d | `RL7D` is non-empty |
| Cost | `total_cost_usd > 0` (checked via `bc -l`) |
| Git section | `BRANCH` variable non-empty (git repo detected) |
| Staged count | `STAGED > 0` |
| Modified count | `MODIFIED > 0` |
| Worktree badge | `IS_WORKTREE=1` AND `WORKTREE_NAME` non-empty |
| Agent badge | `SHOW_AGENT=1` AND `AGENT_NAME` non-empty |
| Vim badge | `SHOW_VIM=1` AND `VIM_MODE` non-empty |
| Effort badge | `SHOW_EFFORT=1` AND `EFFORT_LEVEL` ∈ {high, xhigh, max} |
| Code stat | `LINES_ADDED > 0` OR `LINES_REMOVED > 0` |

---

## 9. Shell & Terminal Compatibility

### Does My Shell Config Affect the Statusline?

**No.** The statusline script is invoked by Claude Code as `/bin/bash ~/.claude/statusline.sh`. This process:
- Does **not** source `.zshrc`, `.bashrc`, `.zprofile`, `.bash_profile`
- Does **not** run login shell initialization
- Does **not** inherit shell functions, aliases, or `conda`/`nvm`/`pyenv` hooks

| Tool | Effect on statusline |
|------|---------------------|
| oh-my-zsh | None — the script uses bash, not zsh |
| Starship | None — Starship configures interactive prompts, not subprocesses |
| Powerlevel10k | None |
| conda / pyenv / nvm | None — version manager hooks only run in interactive shells |
| Shell aliases | None — aliases do not exist in non-interactive shells |
| `.zshrc` / `.bashrc` | Not sourced |

**What IS inherited from Claude Code's environment:**
- `$HOME` — used for path abbreviation
- `$PATH` — used to locate `git`, `jq`, `bc`, `cksum`
- `$TERM`, `$COLORTERM` — terminal type indicators (currently unused; relevant to P3 color fallback)

Claude Code sets its own `$PATH` that includes `/usr/local/bin`, `/opt/homebrew/bin`, and similar locations, so `jq` and other tools are found even if they're not in the user's shell `$PATH`.

### Does the Statusline Affect Starship/oh-my-zsh Prompts?

**No.** The statusline is rendered inside Claude Code's TUI. Your Starship/p10k prompt is rendered by your interactive shell when you type commands in your terminal. These are completely separate display contexts and cannot interfere.

The **Gemini/Codex banners** (`gemini-banner.sh`, `codex-banner.sh`) do run in your interactive shell (triggered by the `g()` and `cx()` wrapper functions in `.zshrc`). These can theoretically interact with your prompt if they output non-printable characters, but since they only `echo` a single formatted line before launching the CLI tool, they do not conflict with Starship or oh-my-zsh.

### Terminal Emulator Color Support

| Terminal | Truecolor | Result |
|----------|:---------:|--------|
| Claude Code desktop app | ✅ (Electron/xterm.js) | Full Catppuccin Mocha — always correct |
| iTerm2 (macOS) | ✅ | Full colors |
| Alacritty | ✅ | Full colors |
| Kitty | ✅ | Full colors |
| WezTerm | ✅ | Full colors |
| Warp | ✅ | Full colors |
| VS Code integrated terminal | ✅ | Full colors |
| Cursor integrated terminal | ✅ | Full colors |
| JetBrains integrated terminal | ✅ | Full colors |
| macOS Terminal.app (Sonoma 14+) | ✅ | Full colors |
| macOS Terminal.app (pre-Sonoma) | ❌ | 256-color approximation — pastels look different |
| Windows Terminal | ✅ | Full colors |
| PuTTY (all versions) | ❌ | Garbled sequences or no color |
| tmux (default config) | ⚠️ | Strips truecolor passthrough — requires explicit config |
| SSH (client-dependent) | ⚠️ | Depends on SSH client's terminal emulation |

**tmux configuration** — add to `~/.tmux.conf`:
```
set -g default-terminal "screen-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
```

---

## 10. Platform Support & Installation

### macOS (Fully Supported ✅)

**Prerequisites:**
```bash
brew install jq      # JSON processor — required
# bc ships with macOS Command Line Tools
# git ships with Xcode Command Line Tools
```

**Install:**
```bash
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

**What `install.sh` does:**
1. Checks for `jq`, `bc`, `git` — exits with error if missing
2. Backs up existing `~/.claude/statusline.sh` to `statusline.sh.bak` if present
3. Copies `statusline.sh`, `gemini-banner.sh`, `codex-banner.sh` to `~/.claude/` with mode 755
4. Merges `statusLine` and `refreshInterval` into `~/.claude/settings.json` using `jq` (does not overwrite other settings)

**For Gemini/Codex banners**, add to `~/.zshrc`:
```bash
unalias g 2>/dev/null
g()  { ~/.claude/gemini-banner.sh; gemini  "$@"; }
unalias cx 2>/dev/null
cx() { ~/.claude/codex-banner.sh;  codex   "$@"; }
```

### Linux (Fully Supported ✅)

```bash
# Debian/Ubuntu
sudo apt install jq bc

# Fedora/RHEL
sudo dnf install jq bc
```

Install steps identical to macOS. The only platform difference is in the git cache's `stat` call — the script handles both BSD (`-f %m`) and GNU (`-c %Y`) syntax automatically.

### Windows — WSL (Supported ✅)

Claude Code for Windows runs through WSL. The `~/.claude/` directory resolves to the WSL home directory. Follow the Linux instructions inside WSL.

```powershell
wsl
sudo apt install jq bc
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

### Windows — Native (Not Supported ❌)

Requires bash, POSIX tools, and ANSI truecolor — none of which are native to Windows. Use WSL.

| Environment | Status |
|-------------|--------|
| macOS (bash 3.2+) | ✅ Full support |
| Linux (bash 4+) | ✅ Full support |
| Windows + WSL | ✅ Full support |
| Windows + Git Bash | ⚠️ May work; not tested |
| Windows native (cmd/PowerShell) | ❌ Not supported |
| SSH remote session | ⚠️ Color depends on SSH client's terminal emulation |

---

## 11. Critical Engineering Bugs & Fixes

### Bug 1: jq Silently Strips Control Bytes from String Literals

**Version fixed:** v2.1.0 (2026-04-26)

**Symptom:** Garbled single-line output like:
```
Sonnet 4.6/Users/wenbin/mycode/project727.000000001777195200658.95851…
```

**Root cause:** jq strips literal bytes with value `< 0x20` (ASCII control characters) from inline string literals in source code during parsing. The SOH byte (`\x01`) used as a field delimiter in `join("\x01")` was being stripped to an empty string — so all 15 fields were joined with no separator, producing one giant concatenated string that was assigned entirely to the first variable (`MODEL`).

**How to reproduce the bug:**
```bash
# This produces "helloworld" — the \x01 is stripped
printf '["hello","world"]' | jq -r '. | join("")'

# Correct: pass SOH as a jq argument variable
printf '["hello","world"]' | jq -r --arg s "$(printf '\001')" '. | join($s)'
# → "hello\x01world"
```

**Fix:** Replace `join("\x01")` in the jq source with `join($s)` where `$s` is passed via `--arg s "$(printf '\001')"`. jq receives it as an argument value, not as source code, so the byte is preserved.

### Bug 2: IFS Whitespace Collapsing with `@tsv`

**Symptom:** Fields after any empty field are shifted left by one position. `RL5H` gets the value of `RL5H_RESET`, `RL7D` gets `COST_USD`, etc.

**Root cause:** Bash's `IFS` whitespace collapsing rule: consecutive IFS characters that are whitespace (space, tab, newline) are treated as a single separator. Tab is in the whitespace set, so `IFS=$'\t'` + consecutive tabs = one separator = empty field disappears.

**Fix:** Use SOH (`\x01`) as delimiter. SOH is not in bash's whitespace set, so `IFS=$'\x01'` preserves empty fields correctly.

### Bug 3: `${var/#$HOME/~}` Pattern/String Separator Bug

**Symptom:** Path abbreviation silently fails — `DIR` remains as the full absolute path starting with `/Users/...`; the `~` prefix is never applied.

**Root cause:** In bash's `${var/pattern/string}` substitution, the parser finds the first unescaped `/` after the opening `${var/` to split pattern from string. Since `$HOME` expands to `/Users/username`, the `/` inside the expansion is consumed as the separator — leaving the pattern empty and the string as `Users/username/~`, which matches nothing useful.

```bash
# These are equivalent in bash's parsing:
${full/#$HOME/~}     → pattern=""  string="Users/username/~"  (BROKEN)
${full/#/~}          → replace "" at start with "~Users/username" prefix
```

**Fix:** Use prefix removal operator `${var#prefix}`, which does not use `/` as a separator:
```bash
local stripped="${full#$HOME}"
[ "$stripped" != "$full" ] && path="~${stripped}" || path="$full"
```

### Bug 4: Floating-Point Precision Leaking from JSON

**Symptom:** Display shows `38m50s` correctly but intermediate values like `727.0000000000000011777195200` appear in debug output, or `↑5h:35.999999%` instead of `36%`.

**Root cause:** JavaScript (which serializes the JSON Claude Code sends) uses IEEE 754 double-precision floating point. Integer values like `2330000` (milliseconds) are stored as doubles and may be serialized with precision artifacts.

**Fix:** Apply `floor | tostring` to all integer fields in jq. `floor` rounds down to the nearest integer, eliminating any fractional component. `tostring` then converts to a string without trailing zeros.

```jq
((.cost.total_duration_ms // 0) | floor | tostring)  →  "2330000"
```

`total_cost_usd` is intentionally NOT floored — it retains decimal precision for `printf '%.2f'` formatting in bash.

---

## 12. Comparison with Mature Solutions

### Feature Matrix

| Feature | **This project** | [claude-hud](https://github.com/jarrodwatts/claude-hud) | [claude-lens](https://github.com/Astro-Han/claude-lens) | [CCometixLine](https://github.com/Haleclipse/CCometixLine) | [codex-hud](https://github.com/anhannin/codex-hud) |
|---------|:---:|:---:|:---:|:---:|:---:|
| Dual-line layout | ✅ | ✅ | ❌ | ✅ | ❌ |
| Pace delta `⇡/⇣` | ✅ | ❌ | ✅ | ❌ | ❌ |
| Reset countdown | ✅ | ❌ | ✅ | ❌ | ❌ |
| 7-day rate limit | ✅ | ✅ | ❌ | ✅ | ❌ |
| Catppuccin Mocha | ✅ | ❌ | ❌ | partial | ❌ |
| Starship path abbrev | ✅ | ❌ | ❌ | ❌ | ❌ |
| Gemini CLI banner | ✅ | ❌ | ❌ | ❌ | ❌ |
| Codex CLI banner | ✅ | ❌ | ❌ | ❌ | ✅ |
| Single-line fallback | ✅ | ❌ | N/A | ✅ | N/A |
| Vim mode badge | ✅ | ✅ | ❌ | ✅ | ❌ |
| Agent badge | ✅ | ✅ | ❌ | ❌ | ❌ |
| Effort badge | ✅ | ❌ | ❌ | ❌ | ❌ |
| Worktree badge | ✅ | ✅ | ❌ | ❌ | ❌ |
| Zero runtime deps | ✅ | ❌ (npm) | ✅ | ❌ (Rust/npm) | partial |
| Single jq call | ✅ | ❌ | ❌ | N/A (Rust) | ❌ |
| macOS bash 3.2 compat | ✅ | N/A | ✅ | N/A | ❌ |

### Unique Value Propositions

1. **Codex + Gemini banners**: The only statusline project that extends to non-Claude AI CLI tools via shell wrapper functions, with real usage data from CodexBar.
2. **Pace delta in a dual-line layout**: claude-lens has pace delta but single-line only; claude-hud has dual-line but no pace delta. This project combines both.
3. **Zero build-step installation**: No npm, no Rust toolchain, no compiled binary. Three `.sh` files + `install.sh`. Works with only `jq`, `bc`, and `git`.
4. **Pure Catppuccin Mocha truecolor**: Every color maps to an official Catppuccin Mocha swatch.
5. **bashrc-immune**: Runs completely isolated from the user's shell config — no conflicts with oh-my-zsh, Starship, conda, or any other shell tool.

### Where Mature Projects Are Ahead

| Gap | Project | Details |
|-----|---------|---------|
| Plugin marketplace distribution | claude-hud | `/plugin install` from Claude Code's marketplace; no manual file copy |
| Theme configurability | CCometixLine | TOML theme files (Gruvbox, Nord, Powerline-Dark, etc.) |
| Compiled performance | CCometixLine | Rust binary ~1ms vs our ~37ms |
| Todo / tool activity display | claude-hud | Shows active tools and pending todos in real time |

---

## 13. Known Limitations

### 1. Truecolor Required for Best Experience

No 256-color fallback is implemented. On pre-truecolor terminals, the Catppuccin Mocha palette degrades to 256-color approximations that look noticeably different. See [Section 5](#5-color-system--catppuccin-mocha-truecolor) for the full terminal compatibility matrix.

### 2. Codex Banner Requires CodexBar (macOS Only)

`codex-banner.sh` reads Codex usage via CodexBar's CLI helper (`CodexBarCLI`). This is a third-party macOS menu bar app. If not installed, the banner shows without usage data. A P3 improvement will parse `~/.codex/sessions/**/rollout-*.jsonl` directly, eliminating the dependency.

### 3. Codex Usage Cache Latency (~2 minutes)

CodexBarCLI queries for Codex usage data are slow (2+ minutes). The banner uses a stale-while-revalidate cache (1-hour TTL) with a background refresh. The first banner after a cache miss may show stale data until the refresh completes.

### 4. CJK Characters in Paths

Paths containing Chinese/Japanese/Korean characters display correctly but take 2 terminal columns per character (double-width). The 28-character abbreviation threshold counts bytes, not display columns, so short CJK paths may still be abbreviated. Cosmetic only.

### 5. Git Cache Shows Stale Branch for ~5 Seconds

After switching branches, the status bar reflects the old branch for up to 5 seconds (the cache TTL).

### 6. No `context_window_size`-Based Model Detection

The `context_window.context_window_size` field is available in the JSON payload but not currently used. A future improvement could show a `1M` badge when `context_window_size ≥ 1,000,000`.

---

## 14. Pending Optimization Backlog

### P2 — In Progress

| Item | Status | Notes |
|------|--------|-------|
| GitHub repository structure | ✅ Done | v2.1.0 released |
| Conventional Commits history | ✅ Done | 3 commits + tags |
| Screenshots/GIF in README | ❌ Not done | Need terminal recording |
| GitHub Release with `.sh` assets | ❌ Not done | v2.1.0 tag exists; Release page not created |

### P3 — Planned

| Item | Value | Complexity | Blocking? |
|------|-------|------------|-----------|
| **Truecolor detection + 256-color fallback** | High — users on pre-truecolor terminals see degraded colors | Medium — detect `$COLORTERM`, provide 256-color palette | No |
| **1M context model detection** | Low — visual indicator for large-context models | Low — read `context_window.context_window_size`, add badge | No |
| **Codex direct JSONL parsing** | Medium — eliminates CodexBarCLI dependency and 2-min delay | Medium — `~/.codex/sessions/**/rollout-*.jsonl` parsing | No |
| **`CC_SL_PATH_DEPTH` option** | Low — control abbreviation depth | Low — pass depth parameter to awk | No |
| **Plugin marketplace distribution** | High — one-line install with `/plugin install` | High — requires Claude Code plugin format | No |
| **Gemini native hook** | Low — replace shell wrapper with native hook | Unknown — `~/.gemini/settings.json` support unconfirmed | No |
| **256-color theme variant** | Medium | Medium — separate palette with `\033[38;5;Nm` codes | No |
| **README screenshots/GIF** | Medium — first-time users need visual preview | Low — requires terminal recording tool (e.g. `vhs`) | No |
