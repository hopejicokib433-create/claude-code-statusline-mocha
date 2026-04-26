---
name: Bug report
about: Something isn't displaying correctly
labels: bug
---

## Describe the bug

<!-- What did you expect to see? What did you actually see? -->

## Reproduction

```bash
# Paste the exact command that reproduces the issue, e.g.:
echo '{"model":{"display_name":"Sonnet 4.6"}, ...}' | bash statusline.sh
```

## Environment

- **macOS version**: <!-- e.g. macOS 15.4 -->
- **bash version**: <!-- run: bash --version -->
- **Claude Code version**: <!-- run: claude --version -->
- **jq version**: <!-- run: jq --version -->

## Actual output

```
<!-- paste the raw output here, ideally with: | sed 's/\x1b\[[0-9;]*m//g' to strip colors -->
```

## Expected output

<!-- describe what you expected -->
