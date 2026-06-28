# Issue #819: auto: XS patch route の orphan spec stub 命名を正式形式に修正して抑制

## Overview

`/auto` の XS patch route では `/spec` フェーズがスキップされ、code フェーズが直接 Consumed Comments セクションを Spec ファイルに書き込む。LLM が書き込まなかった場合のフォールバックとして `scripts/append-consumed-comments-section.sh` が呼ばれるが、Spec ファイルが存在しないと `docs/spec/issue-N-code.md` という非標準名でスタブを作成する。このスタブは `git diff --quiet` チェックが untracked ファイルを検出しないためコミットされず、`/verify` 実行時の `check-verify-dirty.sh` dirty チェックが exit 1 でブロックする。

## Reproduction Steps

1. XS サイズの Issue に対して `/auto N` を実行 (spec フェーズをスキップ)
2. code フェーズの LLM が `## Consumed Comments` セクションを Spec に書き込まない
3. `run-code.sh` の post-processor が `_append_consumed_comments_section N code` を呼び出す
4. `append-consumed-comments-section.sh` は既存 Spec が見つからないため `docs/spec/issue-N-code.md` を作成するが、`git diff --quiet` が untracked ファイルを検出せずコミット失敗
5. 次の `/verify N` 実行時、`check-verify-dirty.sh` が untracked の `issue-N-code.md` (同一 issue 番号) を `has_other=true` と分類し exit 1

## Root Cause

`scripts/append-consumed-comments-section.sh` の `if [[ -z "$SPEC_FILE" ]]; then` ブロック (line 31–39) で：

1. **非標準ファイル名**: `SPEC_FILE="$SPEC_DIR_ABS/issue-${ISSUE_NUMBER}-${PHASE_NAME}.md"` とフェーズ名 (`code`) を suffix に使っている
2. **コミット漏れ**: `git diff --quiet "$SPEC_REL"` は新規 untracked ファイルに exit 0 を返すためコミットブロックがスキップされる

修正方針: **Option B** — Spec ファイルが存在しない場合はスタブを作成せず early exit する。Consumed Comments セクションは Spec が存在する場合のみ書き込めばよく、XS patch route (spec スキップ) での記録は省略可。

## Changed Files

- `scripts/append-consumed-comments-section.sh`: Spec ファイルが存在しない場合のスタブ作成ブロック (line 31–39) を early `exit 0` に置換 — bash 3.2+ compatible
- `tests/append-consumed-comments-section.bats`: 新規テストファイル (スキップ動作・正常追記・重複ガード)
- `docs/structure.md`: tests ディレクトリのファイル数を 90→91 に更新
- `docs/ja/structure.md`: tests ディレクトリのファイル数を `90 ファイル`→`91 ファイル` に更新

## Implementation Steps

1. `scripts/append-consumed-comments-section.sh` の `if [[ -z "$SPEC_FILE" ]]; then` ブロックを以下に置換 (→ AC1):
   ```bash
   if [[ -z "$SPEC_FILE" ]]; then
     echo "append-consumed-comments-section.sh: no spec file for issue #${ISSUE_NUMBER}, skipping" >&2
     exit 0
   fi
   ```
   Title 取得・mkdir・スタブ作成・H1 書き込みの 8 行 (line 32–39) を削除する。

2. `tests/append-consumed-comments-section.bats` を新規作成 (→ AC2, AC3):
   - setup: `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR`, PATH にモック追加。モックが必要なもの: `get-config-value.sh` (spec-path を返す), `gh` (issue timeline と comments を返す), `git` (diff/add/commit/push のスタブ)
   - `@test "no spec file: skips stub creation and exits 0"` — Spec ファイルなしで実行 → exit 0、スタブ未生成
   - `@test "spec file exists: appends Consumed Comments section"` — 既存 Spec ファイルありで実行 → `## Consumed Comments` が追記される
   - `@test "section already exists: dedup guard exits 0"` — `## Consumed Comments` が既に存在する Spec ファイルで実行 → 重複追記なし

3. `docs/structure.md` line 45: `(90 files)` → `(91 files)` に更新

4. `docs/ja/structure.md` line 38: `（90 ファイル）` → `（91 ファイル）` に更新

## Verification

### Pre-merge

- <!-- verify: rubric "patch route で生成される Spec stub が Issue title 由来の kebab-case 命名規約に従う、もしくは Consumed Comments のみのスタブ生成自体が抑制される" --> orphan spec stub の発生が解消されている
- <!-- verify: file_exists "tests/append-consumed-comments-section.bats" --> `tests/append-consumed-comments-section.bats` が実装の一部として新規作成されている
- <!-- verify: command "bats tests/run-code.bats tests/append-consumed-comments-section.bats" --> `tests/run-code.bats` および `tests/append-consumed-comments-section.bats` が成功する

### Post-merge

- 次回 `/auto --batch` または `/auto N` (XS) 実行時に `docs/spec/issue-N-code.md` 形式の orphan stub が生成されないことを観察

## Notes

- AC1 の rubric は実装方針 A/B どちらでも PASS になるよう意図的に抽象化されている。本 Spec は Option B (抑制) を採用する。
- `run-auto-sub.sh` は `run-code.sh` を runner として呼び出すため、`run-code.sh` の修正で batch route も同時に修正される。直接の変更は不要。
- Step 3–4 (structure.md 更新) は AC に対応する verify command がなく SHOULD 扱いだが、structure.md の正確性を保つために実施する。

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/819#issuecomment-4826260581

## Code Retrospective

### Deviations from Design

- None. The Spec's Option B (early exit when no spec file) was implemented as specified. The 8-line stub creation block (title fetch, mkdir, file create, H1 write) was replaced with a 2-line early exit matching the Spec exactly.

### Design Gaps/Ambiguities

- The `WHOLEWORK_SCRIPT_DIR` env var override causes `_repo_root` to be derived as `dirname(MOCK_DIR)`. Tests must structure `MOCK_DIR` as `$BATS_TEST_TMPDIR/repo/mocks` so that `_repo_root` resolves to `$BATS_TEST_TMPDIR/repo` and spec files are found at the correct path. This path convention was not documented in the Spec but was discovered during test authoring.

### Rework

- None.

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- None. The implementation exactly matches the Spec's Option B (suppress stub creation entirely). The diff was a pure 8-line → 2-line replacement with no scope drift.

### Recurring Issues

- The code phase's "All 43 bats tests pass" log referred only to the new test file (`tests/append-consumed-comments-section.bats`), not the full suite. An existing test in `tests/run-verify.bats` ("spec absent: creates skeleton file") tested the old behavior and was not updated before committing. This produced a deterministic CI FAILURE that could have been caught with `bats tests/` (full suite run) locally. Recommendation: code phase should always run `bats tests/` (all tests) before committing behavioral changes to ensure no regression in existing tests.

### Acceptance Criteria Verification Difficulty

- AC3 `command "bats tests/run-code.bats tests/append-consumed-comments-section.bats"` was narrowly scoped to only the new/modified test files, which masked the broken existing test in `tests/run-verify.bats`. Broader verify commands (e.g., `command "bats tests/"`) would have caught this at AC verification time rather than at CI check time.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #825 squash-merged into main without conflicts (mergeable=true, CI passing, review approved).
- BASE_BRANCH=main, so Issue #819 will be auto-closed via the `closes #819` reference in the PR body.
- No conflict resolution was required; proceeded directly from Step 1 to Step 4.

### Deferred Items
- Post-merge AC (observing that `docs/spec/issue-N-code.md` orphan stubs no longer appear on the next XS `/auto N` run) is pending.
- AC3 verify command scope remains narrow (`tests/run-code.bats tests/append-consumed-comments-section.bats`); widening to `bats tests/` for regression coverage is an improvement candidate for a follow-up Issue.

### Notes for Next Phase
- verify phase should confirm the three pre-merge ACs (orphan stub suppressed, `tests/append-consumed-comments-section.bats` exists, bats suite passes).
- The post-merge AC requires an actual XS `/auto N` run to observe absence of orphan stubs — cannot be verified statically.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Auto-Resolved Ambiguity Points 2 件 (AC2 分割、Related に run-auto-sub.sh 追加) は適切に処理された。

#### spec
- Option A/B/C の 3 アプローチを並列提示し Option B (early exit) を採択。rubric AC は実装方針に対し抽象化されており、Option A も PASS 可能な構成。

#### code
- Deviations なし。Spec の 8-line → 2-line 置換が正確に再現された。
- 観察ギャップ: `WHOLEWORK_SCRIPT_DIR` env var による `_repo_root` 解決のテスト用 path convention (`$BATS_TEST_TMPDIR/repo/mocks` → `_repo_root=$BATS_TEST_TMPDIR/repo`) が Spec に未記載で、テスト作成時に発見・補完された。

#### review
- 既存テスト `tests/run-verify.bats` の "spec absent: creates skeleton file" が旧挙動を前提としていたため CI で FAIL したが review phase で適切に検出・修正された。

#### merge
- PR #825 がコンフリクトなく squash merge。base=main。

#### verify
- AC3 の verify command scope (`bats tests/run-code.bats tests/append-consumed-comments-section.bats`) が局所的で、本 Issue 自体は局所変更のためカバーされるが、code フェーズの先行検証としての regression coverage は不足していた。

### Improvement Proposals

- code phase で behavioral change を含むコミット前に `bats tests/` (フルスイート) を実行するガイドラインを追加することで、本 PR の CI FAILURE のような regression を事前検知できる。`scripts/run-code.sh` または `modules/test-runner.md` への記述追加候補。
- AC 生成側 (`/issue` skill) で behavioral changes が含まれるとき verify command を局所ファイルではなく `bats tests/` 等のフルスイートにする推奨ロジックを検討。狭い scope は CI で検出されるが、verify-time に事前 catch できると review phase の reopen を削減できる。
