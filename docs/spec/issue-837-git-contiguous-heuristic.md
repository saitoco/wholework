# Issue #837: verify command 生成時の git invocation contiguous sub-string heuristic を追加

## Overview

`/issue` や `/spec` が verify command を生成する際、git invocation (`git -C "$REPO_ROOT" commit` 等) を `file_contains` / `grep` でチェックするケースで、`git commit` のような full form を検索パターンに使うとマッチしない問題が頻発している。`modules/verify-patterns.md` は verify command accuracy guidelines の SSoT であるため、non-contiguous シンボルに対して contiguous sub-string を選ぶ旨のガイドラインを §23 として追加する。また、heuristic の存在を structural regression test で保証する `tests/verify-heuristics.bats` を新規作成する。

## Changed Files

- `modules/verify-patterns.md`: add §23 — non-contiguous symbol heuristic for `file_contains` / `grep` verify commands — bash compat N/A (Markdown)
- `tests/verify-heuristics.bats`: new file — structural regression test asserting §23 heuristic keyword presence — bash 3.2+ compatible (uses only POSIX `grep -q`)
- `docs/structure.md`: update tests count comment `(91 files)` → `(93 files)` (pre-existing count drift: 92 actual before this Issue, 93 after; Markdown only)

## Implementation Steps

1. Add §23 to `modules/verify-patterns.md` immediately before `## Output` section (→ AC1):
   - Section heading: `### 23. Non-Contiguous Git Invocation — Prefer Contiguous Sub-strings`
   - Core guideline: When the implementation uses `git -C "$REPO_ROOT" commit` (or similar forms inserting flags between the `git` command and its sub-command), the pattern `"git commit"` does NOT appear as a contiguous substring on any single line. Use a contiguous sub-string that is guaranteed to appear on one line: `commit -s`, `commit -m`, `-m "Add`, etc.
   - Anti-pattern: `file_contains "scripts/foo.sh" "git commit"` — fails when actual code is `git -C "$REPO_ROOT" commit -s -m "..."`
   - Recommended pattern: `file_contains "scripts/foo.sh" "commit -s"` or `file_contains "scripts/foo.sh" "commit -m"`
   - Real example: `scripts/append-loop-state-heartbeat.sh` line 142 — `git -C "$REPO_ROOT" commit -s -m "chore: ..."` — contiguous anchor = `commit -s`
   - Generalizes to any command that inserts option flags between the command name and its sub-command (e.g., `git -C` + option, `ssh -i key host` + command)

2. Create `tests/verify-heuristics.bats` with structural assertions (→ AC2):
   ```bash
   #!/usr/bin/env bats
   # Structural regression tests for verify command heuristic guidelines.
   PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
   VERIFY_PATTERNS="$PROJECT_ROOT/modules/verify-patterns.md"

   @test "verify-heuristics: non-contiguous heuristic section exists in verify-patterns.md" {
       grep -q "non-contiguous" "$VERIFY_PATTERNS"
   }

   @test "verify-heuristics: contiguous sub-string guidance is documented" {
       grep -q "contiguous" "$VERIFY_PATTERNS"
   }

   @test "verify-heuristics: git -C example is present in verify-patterns.md" {
       grep -q 'git -C' "$VERIFY_PATTERNS"
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md、modules/verify-patterns.md、modules/verify-classifier.md、modules/ambiguity-detector.md のいずれかに、git invocation 等の non-contiguous シンボルを file_contains / grep verify command でチェックする際の contiguous sub-string 選択ガイドラインが追加されている" --> verify command 生成時の git invocation heuristic が文書化されている
- <!-- verify: command "bats tests/verify-heuristics.bats" --> `tests/verify-heuristics.bats` が追加され heuristic guideline の structural regression test が通過する

### Post-merge

- 次回 `/auto` または `/issue` 実行時、git invocation を含む実装の verify command が contiguous sub-string で生成されることを観察 <!-- verify-type: observation event=auto-run -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: Auto-Resolve Log (対象ファイル候補の拡張、regression test AC 追加の rationale) / https://github.com/saitoco/wholework/issues/837#issuecomment-4827170987

## Notes

- **auto-resolved (Issue phase)**: 対象ファイルに `modules/verify-patterns.md` を追加 — 元の rubric は skills/issue/SKILL.md・verify-classifier.md・ambiguity-detector.md の 3 ファイルのみを対象としていたが、verify-patterns.md が verify command accuracy guidelines の SSoT (§1-§22 すべてがガイドライン) のため最有力ターゲット
- **auto-resolved (Issue phase)**: regression test (Proposal C) を Pre-merge AC として追加 — 元の AC に不記載だったが Issue body Proposal 欄に明示されており、既存の structural assertion パターン (tests/doc-checker.bats 等) と整合する
- **docs/structure.md count**: tests/ カウントが既に 91 (structure.md) vs 92 (実際) と 1 ずれている。本 Issue で verify-heuristics.bats を追加後は 93 になるため 93 に更新する。ただし Issue body に AC なし — /code フェーズで合わせて修正すること
- **implementation placement**: §23 は `## Output` の直前に挿入する。§22 の最終行 (`Do not force...`) の後に改行を挟んで追加
- **git -C example**: `scripts/append-loop-state-heartbeat.sh` line 142 の `git -C "$REPO_ROOT" commit -s -m "chore: loop-state heartbeat auto-commit $DATE [skip ci]"` がリファレンス例として使用可能 (非連続形式が実在することを確認済み)

## Consumed Comments (code phase)

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- None. Spec の実装ステップを設計通りに実行した。

### Design Gaps/Ambiguities
- `docs/ja/structure.md` の translation sync が Spec の Changed Files に明示されていなかったが、`docs/translation-workflow.md` のルールに従い `docs/structure.md` 更新に対応して同期した。

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- §23 を `modules/verify-patterns.md` の `## Output` 直前に挿入した。他の候補ファイル (skills/issue/SKILL.md、verify-classifier.md、ambiguity-detector.md) より SSoT として最適。
- `tests/verify-heuristics.bats` は Spec の指定通り 3 テスト (non-contiguous keyword / contiguous keyword / git -C example) で構成した。
- `docs/structure.md` の tests/ カウントを 91 → 93 に更新し、translation sync として `docs/ja/structure.md` も同期した。

### Deferred Items
- Post-merge observation AC (次回 /auto または /issue 実行時の verify command 生成観察) は verify phase に委ねる。
- `/issue` SKILL.md や他モジュールへの同 heuristic の追記は本 Issue スコープ外 (Proposal A は実施せず; verify-patterns.md SSoT で十分)。

### Notes for Next Phase
- PR #840 が CI を通過することを確認してから merge を進めること。
- post-merge AC は `verify-type: observation event=auto-run` であり、機械的な検証は不要 — verify phase では SKIPPED/post-merge manual として扱う。
- 全 pre-merge AC は code phase でチェック済み (AC1: rubric PASS、AC2: bats 3/3 PASS)。
