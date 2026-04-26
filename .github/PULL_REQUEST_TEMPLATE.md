## Summary

<!-- What does this PR change and why? -->

## Type of change

- [ ] Bug fix (`fix(scope): ...`)
- [ ] New feature (`feat(scope): ...`)
- [ ] Performance improvement (`perf(scope): ...`)
- [ ] Documentation (`docs(scope): ...`)
- [ ] Chore (`chore(scope): ...`)

## Testing

```bash
# Commands I ran to test this change:
echo '{}' | bash statusline.sh
echo '{}' | bash statusline.sh | wc -l  # should be 2
```

## Screenshots / Output

<!-- Paste the plain-text output (strip ANSI with: sed 's/\x1b\[[0-9;]*m//g') -->

```
Line 1: ...
Line 2: ...
```

## Checklist

- [ ] Tested with empty input `echo '{}' | bash statusline.sh`
- [ ] Tested with realistic payload (see CONTRIBUTING.md)
- [ ] `CC_SL_LINES=1` single-line mode still works
- [ ] No new external dependencies added
- [ ] bash 3.2 compatible (no `mapfile`, `readarray`, or bash-4+ features)
