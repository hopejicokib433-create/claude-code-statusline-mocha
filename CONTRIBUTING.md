# Contributing

## Quick Start

```bash
# Clone and test locally (no Claude Code needed)
git clone https://github.com/YOUR_USERNAME/claude-code-statusline-mocha
cd claude-code-statusline-mocha

# Test with empty input
echo '{}' | bash statusline.sh

# Test with realistic payload
NOW=$(date +%s)
echo "{
  \"model\":{\"display_name\":\"Sonnet 4.6\"},
  \"workspace\":{\"current_dir\":\"$(pwd)\"},
  \"context_window\":{\"used_percentage\":53},
  \"rate_limits\":{
    \"five_hour\":{\"used_percentage\":36,\"resets_at\":$((NOW+7200))},
    \"seven_day\":{\"used_percentage\":12}
  },
  \"cost\":{\"total_cost_usd\":2.05,\"total_duration_ms\":2330000}
}" | bash statusline.sh
```

## Workflow

1. Fork the repo
2. Create a branch: `git checkout -b feat/my-feature`
3. Test locally (see above)
4. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   - `feat(statusline): add X` — new feature
   - `fix(banner): handle Y` — bug fix
   - `perf(statusline): optimize Z` — performance
   - `docs(readme): update W` — docs only
5. Open a PR against `main`

## Testing

```bash
# Verify dual-line output
echo '{}' | bash statusline.sh | wc -l  # → 2

# Verify single-line toggle
CC_SL_LINES=1 bash -c 'echo "{}" | bash statusline.sh' | wc -l  # → 1

# Verify pace delta directions
NOW=$(date +%s)
# Over-pace: 1h elapsed, 80% used → should show ⇡
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":80,\"resets_at\":$((NOW+14400))}}}" \
  | bash statusline.sh | head -1 | grep -c '⇡'

# Under-pace: 4h elapsed, 20% used → should show ⇣
echo "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":20,\"resets_at\":$((NOW+3600))}}}" \
  | bash statusline.sh | head -1 | grep -c '⇣'

# Performance (should complete in <100ms)
time echo '{}' | bash statusline.sh > /dev/null
```

## Code Style

- Shell scripts use `#!/bin/bash` (bash 3.2+ compatible for macOS)
- Comments in Chinese for business logic, English for technical details
- Each section separated by `# ── section name ──` header comments
- Keep `_rl_color()` and similar helpers as inline conditionals where possible to avoid subshells

## Reporting Issues

Please include:
- Your `bash --version` output
- The Claude Code version (`claude --version`)
- The exact JSON payload (from `echo '...' | bash statusline.sh --debug` if available)
- Expected vs. actual output
