# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-04-26

### Changed
- **Field ordering**: Rate limits (↑5h, ↑7d) now appear immediately after model name, before the context bar — quota health is more time-critical than context fill level
- **jq extraction strategy**: Replaced `join($s)` with SOH delimiter by multi-line output (jq comma-expression + multiple bash `read` commands). This eliminates all IFS/delimiter issues and is more robust across bash versions and environments.

### Added
- **`CC_SL_DEBUG=1`**: Write raw Claude Code JSON payload to `/tmp/statusline-debug.json` for diagnosing garbled output
- **`resets_at` millisecond detection**: Auto-detects whether `resets_at` is in seconds (10 digits) or milliseconds (13 digits) and converts correctly

### Fixed
- Garbled output in live Claude Code environment: the SOH byte passed via `--arg s "$(printf '\001')"` was not reliably transmitted across all bash/subprocess environments; switching to line-per-field output eliminates the dependency entirely

## [2.1.0] - 2026-04-26

### Fixed
- **jq control byte bug**: jq silently strips literal bytes `< 0x20` from inline string literals — the SOH delimiter in `join("\x01")` was being stripped, causing all 15 fields to concatenate into the MODEL variable and produce garbled output like `Sonnet 4.6/Users/wenbin/…727.000000001777…`. Fix: pass SOH via `--arg s "$(printf '\001')"` so jq receives it as an argument value (not a literal), which is transmitted correctly.
- **Floating-point precision**: applied `floor | tostring` to all integer jq fields (duration_ms, lines_added/removed, rate limit percentages) to prevent IEEE 754 precision leakage (`727.0000000000000011777195200` → `727`)

## [2.0.0] - 2026-04-26

### Added
- **Dual-line layout**: Line 1 shows runtime metrics (rate limits, context, cost), Line 2 shows project/git context
- **Pace delta indicator**: `⇡Xp%` (red, over-pace) / `⇣Xp%` (green, under-pace) — shows whether quota burns faster or slower than sustainable rate
- **Reset countdown**: time remaining until 5h window resets (`重置 2h30m`)
- **7-day rate limit**: `↑7d:XX%` displayed after 5h limit
- **Vim mode badge**: color-coded INSERT (green) / VISUAL (pink) / NORMAL (yellow)
- **Agent badge**: `⚡agent-name` shown when running with `--agent` flag
- **Effort badge**: shows `effort:high/xhigh/max` when applicable
- **Worktree badge**: `[wt:name]` shown in worktree sessions
- **Single/dual-line toggle**: `CC_SL_LINES=1` for narrow terminals
- **`--version` flag**: `bash statusline.sh --version` outputs version string
- **Gemini CLI banner** (`gemini-banner.sh`): shows model + live usage on session start
- **Codex CLI banner** (`codex-banner.sh`): stale-while-revalidate cache (1h TTL) to handle slow CodexBarCLI queries
- **`install.sh`**: dependency checks + jq-safe settings merge + backup

### Changed
- **Performance**: merged 8 separate `jq` calls into 1 (`join()` with SOH delimiter), ~7x faster
- All fields now configurable via environment variables (see README)

### Fixed
- Empty rate limit fields now correctly hidden (was showing `↑5h:0%` when absent)
- `IFS=$'\x01'` delimiter prevents bash whitespace-collapsing of empty fields
- `${var#$HOME}` replaces broken `${var/#$HOME/~}` pattern (bash delimiter parsing bug)
- `cksum` replaces `md5` for cross-platform cache key generation (Linux compatibility)

## [1.0.0] - 2026-04-20

### Added
- Initial single-line statusline with model, context bar, 5h rate limit, project, git, duration, cost
- Catppuccin Mocha truecolor palette
- 5-second git cache (MD5-keyed per directory)
