---
type: domain
skill: code
load_when:
  file_exists_any: [scripts/check-forbidden-expressions.sh]
---

# Forbidden Expressions Check (/code supplement)

This file is loaded only in repositories where `scripts/check-forbidden-expressions.sh` exists.

## Processing Steps

Run forbidden expressions check locally:

```bash
bash scripts/check-forbidden-expressions.sh
```

This is equivalent to the CI `forbidden-expressions` job and detects prohibited expressions before reaching CI. If the check fails, fix the issues before continuing (same as test failures).
