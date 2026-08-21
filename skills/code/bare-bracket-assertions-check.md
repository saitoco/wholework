---
type: domain
skill: code
load_when:
  file_exists_any: [scripts/check-bare-bracket-assertions.sh]
---

# Bare Bracket Assertions Check (/code supplement)

This file is loaded only in repositories where `scripts/check-bare-bracket-assertions.sh` exists.

## Processing Steps

Run bare bracket assertion detection locally:

```bash
bash scripts/check-bare-bracket-assertions.sh
```

This is equivalent to the CI `bare-bracket-assertions` job and visualizes bats `@test` bodies that assert `$output`/`$status` via a bare `[[ ... ]]` statement without `|| false` — a form that silently fails to propagate through `set -e` on bash 3.2 (macOS system bash). The script is informational only (always exits 0); it does not block commit or CI. See `skills/code/skill-dev-validation.md` § "Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`" for the pitfall and safe alternatives, and prefer those alternatives (`[ ]`, `grep -q`, `[[ ... ]] || false`) when writing new `@test` assertions.
