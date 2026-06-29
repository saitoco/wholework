# Issue #836: scripts: auto-events-rollup.sh の nothing-to-commit warning を silent skip 化

## Overview

`scripts/auto-events-rollup.sh` の auto-commit セクションは `git add` → `git commit` → `git push` を連続実行するが、出力ファイルに変更がない場合 (既コミット済みと内容が同一) でも `git commit` を試みる。その結果、`git commit` が "nothing to commit" で失敗し `|| echo "Warning: auto-commit failed (non-fatal)"` が発火する。実用上は非致命的だが、定期実行ログの S/N 比 (signal-to-noise) を悪化させる。

本 Issue では `git status --porcelain "$OUTPUT_FILE"` で変更の有無を事前判定し、変更がない場合は warning なしで silent skip するよう修正する。

## Reproduction Steps

1. `scripts/auto-events-rollup.sh` を同日 2 回実行する (2 回目の入力データは 1 回目と同一)
2. 2 回目の実行でレポートファイルの内容が変わらない状態 (既コミット済み) になる
3. `Warning: auto-commit failed (non-fatal)` がログに出力される

## Root Cause

auto-commit セクション (line 246-249):
```bash
git add "$OUTPUT_FILE" 2>/dev/null && \
  git commit -s -m "chore: ..." 2>/dev/null && \
  git push origin HEAD 2>/dev/null || \
  echo "Warning: auto-commit failed (non-fatal)" >&2
```

`git add` はファイルが未変更でも exit 0 で成功する。続く `git commit` が変更なしで exit 1 となり `||` ブランチへ落ちる。事前の変更有無チェックがないことが原因。

`git diff --quiet` では untracked ファイルを見落とすため、`git status --porcelain` が適切 (#831 `run-auto-sub.sh` で採用済みパターン)。

## Changed Files

- `scripts/auto-events-rollup.sh`: auto-commit セクションに `git status --porcelain` 事前判定を追加 — bash 3.2+ 互換
- `tests/auto-events-rollup.bats`:
  - `(h)` テスト: git mock を更新して `status --porcelain` で変更あり (M 行) を返すよう修正 (修正後の if 条件が true になるよう)
  - 新テスト `(h2)`: silent skip 動作 (`status --porcelain` が空 → commit 呼ばれない) を assert

## Implementation Steps

1. `scripts/auto-events-rollup.sh` の line 245 コメント直後 (auto-commit ブロック冒頭) を以下に置き換える (→ AC1):
   ```bash
   if git status --porcelain "$OUTPUT_FILE" 2>/dev/null | grep -q .; then
     git add "$OUTPUT_FILE" 2>/dev/null && \
       git commit -s -m "chore: auto-events-rollup auto-commit $TARGET_DATE [skip ci]" 2>/dev/null && \
       git push origin HEAD 2>/dev/null || \
       echo "Warning: auto-commit failed (non-fatal)" >&2
   fi
   ```
   変更前:
   ```bash
   git add "$OUTPUT_FILE" 2>/dev/null && \
     git commit -s -m "chore: auto-events-rollup auto-commit $TARGET_DATE [skip ci]" 2>/dev/null && \
     git push origin HEAD 2>/dev/null || \
     echo "Warning: auto-commit failed (non-fatal)" >&2
   ```

2. `tests/auto-events-rollup.bats` の `@test "auto-events-rollup: git commit is called after successful rollup"` (test `(h)`) の git mock を変更 — `status` サブコマンドで変更あり行を stdout に出力し、if 条件が true になるよう修正 (→ AC2):
   ```bash
   cat > "$MOCK_DIR/git" <<MOCK
   #!/bin/bash
   echo "git \$*" >> "$GIT_LOG"
   if [[ "\$1" == "status" ]]; then
     echo "M  some_file"
   fi
   exit 0
   MOCK
   ```

3. `tests/auto-events-rollup.bats` に以下を追加 — silent skip を assert する新テスト (→ AC2):
   ```bash
   # (h2) auto-commit: git commit is skipped when output file has no changes
   @test "auto-events-rollup: git commit is skipped when output file has no changes" {
       MOCK_DIR="$BATS_TEST_TMPDIR/mocks_rollup_skip"
       GIT_LOG="$BATS_TEST_TMPDIR/git-calls-rollup-skip.log"
       mkdir -p "$MOCK_DIR"
       cat > "$MOCK_DIR/git" <<MOCK
   #!/bin/bash
   echo "git \$*" >> "$GIT_LOG"
   exit 0
   MOCK
       chmod +x "$MOCK_DIR/git"
   
       cat > .tmp/events_skip.jsonl << 'EOF'
   {"ts":"2026-06-14T07:01:38Z","issue":824,"event":"sub_start","size":"M"}
   {"ts":"2026-06-14T07:36:09Z","issue":824,"event":"sub_complete","exit_code":"0"}
   EOF
   
       PATH="$MOCK_DIR:$PATH" run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events_skip.jsonl --output-dir docs/reports
       [ "$status" -eq 0 ]
       [ -f "$GIT_LOG" ]
       run grep "commit" "$GIT_LOG"
       [ "$status" -ne 0 ]
   }
   ```
   追加位置: 既存 test `(h)` の直後。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/auto-events-rollup.sh の auto-commit セクションで git status --porcelain による事前変更検知が行われ、変更がない場合は warning なしで silent skip する" --> <!-- verify: grep "status --porcelain" "scripts/auto-events-rollup.sh" --> `scripts/auto-events-rollup.sh` の auto-commit セクションが変更検知を事前に行い、変更がない場合は silent skip する
- <!-- verify: command "bats tests/auto-events-rollup.bats" --> bats test で silent skip 動作が assert されている

### Post-merge

- 次回 `/auto` 実行時に auto-events-rollup の "nothing to commit" warning が観察されないことを確認 (observation event=auto-run)
  - Expected output structure:
    - auto-events-rollup auto-commit が実行される場合、stderr に `"Warning: auto-commit failed"` が出力されないこと

## Notes

- **Auto-resolve (変更検知方法 A vs B)**: Issue 本文の Proposal A (`git diff --quiet`) と B (`git status --porcelain`) は、B を採用。理由: untracked ファイルも検知できる安全性、および `scripts/run-auto-sub.sh` (#831) との一貫性。
- `git status --porcelain "$OUTPUT_FILE" | grep -q .` のパイプはサブシェルを生成するが、`set -euo pipefail` 下でも `||` が後続しないため exit code は grep の結果に依存する。変更ありなら `grep -q .` が 0 exit → if true → commit 実行。変更なしなら 1 exit → if false → silent skip。意図通りに動作する。
- 既存 test `(h)` の mock 更新は必須: 修正後の実装では `status --porcelain` が空を返す mock では commit が呼ばれず、`grep -q "commit" "$GIT_LOG"` が失敗するため。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None — implementation followed Spec exactly.

### Design Gaps/Ambiguities

- None. The Spec Notes already addressed the `set -euo pipefail` interaction and confirmed the `if ... | grep -q .` pattern behaves correctly without a trailing `||` in the condition.

### Rework

- None — all tests passed on first attempt. Existing test (h) mock update was anticipated in the Spec Notes and applied correctly without iteration.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Adopted `git status --porcelain "$OUTPUT_FILE" | grep -q .` as the pre-check condition (option B from Spec), consistent with `run-auto-sub.sh` pattern from #831.
- Updated test (h) git mock to return `M  some_file` output for `status` subcommand so the new `if` condition evaluates to true and commit is still asserted.
- Added test (h2) asserting commit is NOT called when status returns empty (silent skip path).

### Deferred Items
- Post-merge observation (AC3): confirm no "nothing to commit" warning in next `/auto` run — deferred to runtime observation.

### Notes for Next Phase
- All pre-merge ACs verified: grep PASS, bats 10/10 PASS.
- No structural or interface changes — review should be straightforward.
- The `set -euo pipefail` interaction in the `if` condition is explained in Spec Notes; no behavior change risk.
