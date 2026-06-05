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

## Retrospective Guard

Before committing the code retrospective to the Spec:

1. Run forbidden expressions check to detect any deprecated terms introduced by the retrospective content:
   ```bash
   bash scripts/check-forbidden-expressions.sh
   ```
2. If violations are detected: fix the retrospective text before committing
   - Use descriptive language instead of quoting deprecated terms directly (e.g., write `旧称: <term>` or describe without quoting the term)
3. If no violations: proceed with commit
