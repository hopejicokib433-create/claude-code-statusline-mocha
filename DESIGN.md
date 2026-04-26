# Design Notes & Compatibility Guide

## Table of Contents

1. [Architecture](#architecture)
2. [Comparison with Mature Solutions](#comparison-with-mature-solutions)
3. [Shell & Terminal Compatibility](#shell--terminal-compatibility)
4. [Platform Support & Installation](#platform-support--installation)
5. [Known Limitations](#known-limitations)
6. [Future Roadmap](#future-roadmap)

---

## Architecture

### How Claude Code Statusline Works

Claude Code's `statusLine` feature works by running a user-specified shell script once per refresh interval and displaying its stdout as one or more lines in the status bar. The full JSON payload (model, context window, rate limits, cost, vim mode, etc.) is piped to stdin of the script.

```
Claude Code
    │
    │  JSON payload (stdin)
    ▼
~/.claude/statusline.sh  ──→  stdout (one or two lines)
                                │
                                ▼
                         Status bar display
```

This architecture has a critical implication: **the script runs as an independent subprocess of Claude Code, not inside the user's interactive shell.** It does not source `.zshrc`, `.bashrc`, or any shell configuration file.

### Key Engineering Decisions

#### 1. Single `jq` Call (SOH Delimiter)

The biggest performance win was merging 8 separate `jq` invocations into one:

```bash
# Before: 8 forks
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
DIR=$(echo "$input" | jq -r '.workspace.current_dir // ""')
CTX_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | ...)
# ... 5 more

# After: 1 fork
IFS=$'\x01' read -r MODEL DIR CTX_PCT ... < <(echo "$input" | jq -r '[
  (.model.display_name // "Unknown"),
  (.workspace.current_dir // ""),
  ...
] | join("")')
```

**Why `\x01` (ASCII SOH) instead of `@tsv`?**

`@tsv` uses tab as the delimiter. In bash, any whitespace character (including tab) in `IFS` causes consecutive delimiters to be collapsed into one — meaning empty fields silently disappear. Empty fields are common here (e.g., `rate_limits.five_hour` when not yet accumulated). The SOH character (byte 0x01) is not whitespace in bash, so `IFS=$'\x01'` preserves empty fields correctly.

**Why not `@csv`?**

CSV adds quoting overhead and requires a CSV parser to read back. `join("")` produces a simpler format for `read -r`.

**Why `${var#$HOME}` instead of `${var/#$HOME/~}` for home replacement?**

A subtle bash parsing bug: in `${var/pattern/string}`, bash finds the first unescaped `/` to split pattern from string. Since `$HOME` expands to `/Users/username`, the `/` at the start of `$HOME` is consumed as the separator, making the pattern empty. Using `${var#prefix}` (prefix removal) avoids this entirely.

#### 2. Pace Delta Algorithm

Inspired by [Astro-Han/claude-lens](https://github.com/Astro-Han/claude-lens):

```
delta = used_percentage − (elapsed_seconds ÷ 18000) × 100
```

- `resets_at` is the Unix timestamp when the 5-hour window ends
- `elapsed = now − (resets_at − 18000)` gives seconds elapsed since window start
- `expected = elapsed / 18000 * 100` is the quota that should have been consumed at this pace
- If `delta > threshold`: burning faster than sustainable (⇡, red)
- If `delta < -threshold`: burning slower than sustainable (⇣, green)
- If `|delta| < threshold` (default 5pp): normal fluctuation, hidden

#### 3. Git Cache

Git commands (`branch --show-current`, `diff --numstat`) are expensive for a statusline that refreshes every 60 seconds. A 5-second file cache per directory (keyed by `cksum` of the path) ensures git commands run at most once every 5 seconds across all refreshes.

`cksum` is used instead of `md5`/`md5sum` because it is POSIX-standard and available identically on both macOS and Linux.

#### 4. Starship-Style Path Abbreviation

Full paths like `/Users/wenbin/mycode/claude-code-statusline-mocha` are abbreviated to `~/m/claude-code-statusline-mocha` by shortening each intermediate segment to its first character. This follows the same algorithm as [Starship](https://starship.rs/config/#directory):

```
/Users/wenbin/mycode/jupyter/007/project → ~/m/j/0/project
```

Paths ≤ 28 characters are shown as-is.

---

## Comparison with Mature Solutions

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

This project occupies a specific niche that no single other project covers:

1. **Codex + Gemini banners**: The only statusline project that extends to non-Claude AI CLI tools via shell wrapper functions, with real usage data from CodexBar.
2. **Pace delta in a dual-line layout**: claude-lens has pace delta but single-line only; claude-hud has dual-line but no pace delta. This project combines both.
3. **Zero build-step installation**: No npm, no Rust toolchain, no compiled binary. Three `.sh` files + `install.sh`. Works with only `jq`, `bc`, and `git` (common on any developer machine).
4. **Pure Catppuccin Mocha truecolor**: Other projects use partial or ad-hoc color schemes. Every color maps to an official Catppuccin Mocha palette swatch.

### Where Mature Projects Are Ahead

| Gap | Project | Details |
|-----|---------|---------|
| Plugin marketplace distribution | claude-hud | `/plugin install` from Claude Code's marketplace; no manual file copy |
| Theme configurability | CCometixLine | TOML theme files (Gruvbox, Nord, Powerline-Dark, etc.) |
| Compiled performance | CCometixLine | Rust binary ~1ms vs our ~37ms |
| Todo / tool activity display | claude-hud | Shows active tools and pending todos in real time |

---

## Shell & Terminal Compatibility

### Does My Shell Config Affect the Statusline?

**No.** The statusline script runs as a direct subprocess of Claude Code, not inside your interactive shell. It does not source `.zshrc`, `.bashrc`, `.zprofile`, or any other shell config file.

This means the following have **zero effect** on statusline behavior:

| Tool | Effect |
|------|--------|
| oh-my-zsh | None — the statusline uses `/bin/bash`, not zsh |
| Starship | None — Starship configures your prompt, not subprocesses |
| Powerlevel10k | None |
| conda/pyenv/nvm | None — version managers hook into interactive shells |
| Shell aliases | None — aliases only exist in interactive shell sessions |
| `.zshrc` / `.bashrc` | Not sourced by the script |

The **only** inherited context from your shell is:
- `$HOME` — used for path abbreviation (`~`)
- `$PATH` — used to find `git`, `jq`, `bc`, `cksum`
- Standard environment variables like `$TERM` (indirectly affects ANSI rendering)

Since Claude Code sets its own `$PATH` that includes common tool locations, this is almost never a problem.

### Does the Terminal Emulator Affect Colors?

**Yes, partially.** The statusline uses **24-bit truecolor** ANSI escape codes:

```
\033[38;2;203;166;247m  →  Catppuccin Mauve (#cba6f7)
```

| Terminal | Truecolor Support | Result |
|----------|:-----------------:|--------|
| iTerm2 (macOS) | ✅ | Full Catppuccin Mocha colors |
| Alacritty | ✅ | Full colors |
| Kitty | ✅ | Full colors |
| WezTerm | ✅ | Full colors |
| VS Code integrated terminal | ✅ | Full colors |
| Cursor integrated terminal | ✅ | Full colors |
| macOS Terminal.app (Sonoma+) | ✅ | Full colors |
| macOS Terminal.app (pre-Sonoma) | ❌ | Falls back to 256-color approximation |
| Warp | ✅ | Full colors |
| Windows Terminal | ✅ | Full colors |
| PuTTY / old SSH clients | ❌ | Garbled escape sequences or no color |
| tmux (with `set -g default-terminal "tmux-256color"`) | ⚠️ | Requires `set -g terminal-overrides ",xterm-256color:Tc"` |

> **Claude Code's built-in renderer** (electron-based terminal view) supports truecolor, so colors will display correctly regardless of the external terminal emulator when using the Claude Code desktop app.

**For tmux users**: add to `~/.tmux.conf`:
```
set -g default-terminal "screen-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
```

### Does the Statusline Affect Starship/oh-my-zsh Prompts?

**No.** The statusline is rendered by Claude Code inside its TUI, completely separate from the shell prompt. Your Starship/p10k prompt appears when you type commands in your terminal; Claude Code's statusline appears inside Claude Code's interface. They never interfere.

The **Gemini/Codex banners** (`gemini-banner.sh`, `codex-banner.sh`) do run in your interactive shell (triggered by the `g()` and `cx()` shell wrapper functions in `.zshrc`). These use the same ANSI color codes and are subject to the terminal's color support, but since they just `echo` a line before launching the CLI tool, they cannot conflict with Starship or oh-my-zsh.

---

## Platform Support & Installation

### macOS (Fully Supported ✅)

**Prerequisites:**
```bash
brew install jq     # JSON processor — required
# bc and git ship with macOS/Xcode Command Line Tools
```

**Install:**
```bash
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

Restart Claude Code. Done.

**For Gemini/Codex banners**, add to `~/.zshrc`:
```bash
unalias g 2>/dev/null
g()  { ~/.claude/gemini-banner.sh; gemini  "$@"; }
unalias cx 2>/dev/null
cx() { ~/.claude/codex-banner.sh;  codex   "$@"; }
```

Note: The Codex banner requires [CodexBar](https://github.com/YOUR_CODEXBAR_LINK) to be installed. Edit `codex-banner.sh` to set the correct `CODEXBAR` path if different from the default.

### Linux (Fully Supported ✅)

**Prerequisites:**
```bash
# Debian/Ubuntu
sudo apt install jq bc

# Fedora/RHEL
sudo dnf install jq bc

# git is almost certainly already installed
```

**Install:** same as macOS.

**Minor difference:** on Linux, `stat -f %m file` (BSD syntax) doesn't work; the script uses `stat -f %m ... || stat -c %Y ...` to handle both BSD (macOS) and GNU (Linux) `stat`. This is already handled in the script.

### Windows — WSL (Supported ✅)

Claude Code supports Windows via WSL (Windows Subsystem for Linux). Inside a WSL terminal, follow the Linux instructions above.

```powershell
# PowerShell: open WSL
wsl
# Then inside WSL:
sudo apt install jq bc
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha
bash install.sh
```

Claude Code for Windows typically runs through WSL, and the `~/.claude/` directory resolves to the WSL home directory. Colors will render correctly in Windows Terminal (which supports truecolor).

### Windows — Native (Not Supported ❌)

The script requires:
- `bash` (not available natively in Windows)
- POSIX tools: `jq`, `bc`, `cksum`, `git`
- ANSI truecolor escape codes (not supported in cmd.exe; partially in PowerShell)

**Native Windows is not supported.** Use WSL instead.

| Environment | Status |
|-------------|--------|
| macOS (bash 3.2+) | ✅ Full support |
| Linux (bash 4+) | ✅ Full support |
| Windows + WSL | ✅ Full support |
| Windows + Git Bash | ⚠️ May work; not tested |
| Windows native (cmd/PowerShell) | ❌ Not supported |
| macOS + Docker (Linux container) | ✅ via Linux path |
| SSH remote session | ⚠️ Depends on remote's terminal truecolor support |

---

## Known Limitations

### 1. Codex Banner Requires CodexBar
`codex-banner.sh` reads usage from CodexBar's CLI helper (`CodexBarCLI`). This is a third-party macOS menu bar app. If not installed, the banner shows without usage data. A future P3 improvement will read directly from `~/.codex/sessions/**/rollout-*.jsonl`.

### 2. Codex Usage Cache Latency
CodexBarCLI queries for Codex usage take 2+ minutes. The banner uses a stale-while-revalidate cache (1-hour TTL) to avoid blocking. The first banner shown after a cache miss may show stale data until the background refresh completes.

### 3. Truecolor Required for Best Experience
On terminals without truecolor support, colors degrade to 256-color approximations. The Catppuccin Mocha palette may look noticeably different. No 256-color fallback is currently implemented (P3 consideration).

### 4. Chinese / CJK Characters in Paths
Paths containing CJK characters (Chinese, Japanese, Korean) display correctly in the statusline, but take up 2 terminal columns per character (double-width). The 28-character threshold for path abbreviation counts bytes, not display columns, so very short CJK paths may still be abbreviated. This is a cosmetic issue only.

### 5. Git Cache May Show Stale Branch
The 5-second git cache means a branch switch is reflected in the status bar with up to 5 seconds of delay.

---

## Future Roadmap

### P2 (In Progress)
- [x] GitHub repository with full project structure
- [x] Conventional Commits history
- [ ] Screenshots/GIF in README
- [ ] `v2.0.0` GitHub Release with `.sh` file assets

### P3 (Planned)

| Item | Value | Complexity |
|------|-------|------------|
| **1M context model detection** | Show `1M` badge next to model name when `context_window_size ≥ 1,000,000` | Low |
| **Codex direct JSON parsing** | Read `~/.codex/sessions/**/rollout-*.jsonl` to eliminate CodexBarCLI dependency and 2-min delay | Medium |
| **Truecolor detection + 256-color fallback** | Detect `$COLORTERM` / `TERM_PROGRAM` and use 256-color palette when truecolor not available | Medium |
| **`CC_SL_PATH_DEPTH`** | Control how many path segments to show before abbreviating (default: all) | Low |
| **tmux integration doc** | Add tmux `terminal-overrides` setup to README | Low |
| **Plugin marketplace distribution** | Package as a Claude Code plugin for `/plugin install` one-line install | High |
| **Gemini native hook** | Test if `~/.gemini/settings.json` supports `SessionStart` hook; replace shell wrapper | Unknown |
| **256-color theme variant** | Provide a `CC_SL_THEME=256` mode with fallback palette | Medium |
