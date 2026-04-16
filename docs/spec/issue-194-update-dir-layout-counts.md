# Issue #194: docs: Update scripts/tests file count in structure.md Directory Layout

## Overview

`/audit` drift detection identified that `docs/structure.md` Directory Layout records
`scripts/ (30 files)` and `tests/ (27 files)`, but the actual counts are 32 and 32 respectively.
Update the file count annotations in both the English and Japanese mirror files to match reality.

## Changed Files

- `docs/structure.md`: change `scripts/ (30 files)` → `scripts/ (32 files)` and `tests/ (27 files)` → `tests/ (32 files)`
- `docs/ja/structure.md`: change `（30 ファイル）` → `（32 ファイル）` and `（27 ファイル）` → `（32 ファイル）` for scripts/ and tests/ entries

## Implementation Steps

1. Edit `docs/structure.md`: update scripts/ count from 30 to 32 and tests/ count from 27 to 32 (→ acceptance criteria 1, 2)
2. Edit `docs/ja/structure.md`: update scripts/ count from 30 to 32 and tests/ count from 27 to 32 (after 1)

## Verification

### Pre-merge

- <!-- verify: bash -c 'actual=$(ls scripts/*.sh | wc -l | tr -d " "); grep -qE "scripts/[^(]*\(${actual} files\)" docs/structure.md' --> `docs/structure.md` の scripts/ ファイル数が実際の値と一致
- <!-- verify: bash -c 'actual=$(ls tests/*.bats tests/**/*.bats 2>/dev/null | wc -l | tr -d " "); grep -qE "tests/[^(]*\(${actual} files\)" docs/structure.md' --> `docs/structure.md` の tests/ ファイル数が実際の値と一致

### Post-merge

- 他のカウント表記箇所がないか確認

## Notes

- Acceptance criteria counts `ls scripts/*.sh` only (.sh files), excluding `scripts/validate-skill-syntax.py`. Structure.md will record 32 (shell scripts only). The .py file is not counted by the acceptance criteria command.
- `docs/ja/structure.md` is a Japanese mirror and has the same outdated counts. It is not covered by the acceptance criteria verify commands but should be updated in the same change for consistency.
- Current actual counts (verified at spec time): `scripts/*.sh` = 32, `tests/*.bats` = 32 (up from 30/27 at issue creation due to additional files added since then).

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- Verify commands in both Issue and Spec were miscalibrated: the pattern `grep -q "scripts/ (${actual} files)"` assumed the text `scripts/ (X files)` appears as a contiguous substring in structure.md, but the actual format is `scripts/             # Utility scripts used by skills and agents (X files)` (count appears after a long comment). Both verify commands were corrected to use extended regex (`grep -qE "scripts/[^(]*\(${actual} files\)"`) that skips the comment text between the directory name and the count.

### Rework
- N/A
