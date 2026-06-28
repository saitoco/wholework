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

## review retrospective

### Spec vs. Implementation Divergence Patterns
- AC1 の rubric verify command は対象ファイルを 4 件列挙しているが、実装は `modules/verify-patterns.md` 1 件のみに追加された。rubric の "のいずれかに" 条件は満たされており、PASS。将来の Issue で同様の複数候補 rubric を書く場合、実装ターゲットを 1 件に絞る判断は code phase で行うため rubric は候補列挙で問題ない。

### Recurring Issues
- §23 の Decision Procedure (step 1) が `git commit` に限定されており、§23 本文の「汎化」と矛盾していた。ガイドライン文書では、本文での「汎化します」という宣言と手順書の具体例が一致しているか review phase で意識的にチェックすることを推奨。
- ssh の例示に placeholder 文字列 (`host command`) を使っており、ガイドラインの実用性が低下していた。例示には常に実在するリテラル文字列を使うべきというルールを verify-patterns.md 自体が自己適用できていなかった。

### Acceptance Criteria Verification Difficulty
- pre-merge AC2 の `command "bats tests/verify-heuristics.bats"` は safe mode で CI reference fallback を使用した。CI `Run bats tests` SUCCESS で PASS を確認 — verify command と CI ジョブ名の対応が明確であり、fallback が正常に機能した。
- AC1 の rubric は adversarial grader なしに AI judgment で PASS 判定した。対象ファイルが diff に明示的に含まれており、verify command 検証が容易だった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #840 を squash merge (--delete-branch) で取り込んだ。コンフリクトなし、CI 全 SUCCESS 確認済み。
- `mergeable=false, reason=unknown` (GitHub API の一時的な状態) を non-interactive auto-resolve で通過 — merge コマンド自体は正常完了。

### Deferred Items
- Post-merge observation AC (`verify-type: observation event=auto-run`) は verify phase が担当。
- 次回 `/auto` または `/issue` 実行時に git invocation を含む verify command が contiguous sub-string で生成されるか観察すること。

### Notes for Next Phase
- Pre-merge AC (AC1 rubric, AC2 bats test) は review phase で PASS 確認済み。
- verify phase では post-merge AC のみ残存 — `verify-type: observation` のため SKIPPED/post-merge manual 扱いが適切。
- `modules/verify-patterns.md §23` および `tests/verify-heuristics.bats` が main に取り込まれた状態で verify を実施すること。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- non-interactive で 2 件の ambiguity (対象ファイル候補拡張、regression test 必須化) を自動解決。

#### spec
- Deviations なし。Spec の章節 §23 構造が明確。

#### code
- Rework なし。Spec の implementation steps を設計通り実行。

#### review
- Recurring Issues 2 件: (1) §23 Decision Procedure (step 1) が git commit に限定で本文の汎化と矛盾、(2) ssh 例示に placeholder 文字列を使用しているがガイドラインで「実在リテラルを使う」と推奨しているため自己矛盾。

#### merge
- mergeable=false reason=unknown を non-interactive auto-resolve で通過 (#831 と同根、#839 起票済み)。

#### verify
- 2 件 pre-merge AC PASS (rubric + bats)。calibration ミスなく一発 PASS。

### Improvement Proposals

- `modules/verify-patterns.md §23` の Decision Procedure を汎化し、git invocation 以外の non-contiguous シンボル (ssh, kubectl, docker compose 等) 例を含む形に修正。同時に「§23 が自己適用 (例示は実在リテラル) できているか」のチェックを `tests/verify-heuristics.bats` に追加する Issue を後続で起票推奨。
