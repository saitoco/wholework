---
type: domain
skill: code
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
---

# Stale Test Assertion Check (/code supplement)

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.

## Processing Steps

**Internal guard**: skip this entire check if any of the following conditions hold:
- `tests/` directory does not exist
- None of the target directories (`scripts/`, `modules/`, `skills/`) exist

(`scripts/`, `modules/`, and `skills/` are wholework-specific directory names; other projects may use different naming conventions such as `src/`, `lib/`.)

After completing implementation changes to files under `scripts/`, `modules/`, or `skills/`, check whether any removed literal strings remain as stale assertions in `tests/`.

**Removed literals** are string constants that appear as `-` lines in `git diff` (excluding comment-only lines and whitespace-only changes).

Steps:
1. Extract removed literals from the diff:
   ```bash
   git diff HEAD -- scripts/ modules/ skills/ | grep '^-' | grep -v '^---' | grep -v '^\s*#'
   ```
2. For each non-trivial string constant found (e.g., model IDs, command names, flag values), search `tests/` for residual occurrences:
   ```bash
   grep -rn "REMOVED_LITERAL" tests/ | grep -v '^\s*#'
   ```
3. If any matches are found in `tests/`, output a warning and update the stale assertions before committing:
   ```
   Warning: stale test assertion found — "REMOVED_LITERAL" remains in tests/. Update the assertion to match the new value.
   ```
