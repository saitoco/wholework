# Issue #906: auto: code-patch-silent-no-op Tier 2 fallback が result=recovered を報告しつつコード未修正のまま完了

## Overview

`/auto --batch` のオーケストレーションで、code-patch phase において Claude が exit 0 で終了しつつ実際にはコミットを作成しない「silent no-op」が発生した場合、Tier 2 fallback (`scripts/apply-fallback.sh` の `code-patch-silent-no-op` ハンドラ) は `run-code.sh --patch` を retry する (または `auto-retry-on-fail` 有効時は組み込みリトライが既に使い果たされているとして skip する) が、その結果を検証せずに常に `result=recovered` を報告する。このため retry 自体も silent no-op で終わった場合 (Issues #895, #904 で実際に発生) でも Tier 3 エスカレーションに委譲されず、実装されないまま完了扱いになる。本 Spec は retry (または skip) 後に `reconcile-phase-state.sh code-patch <issue> --check-completion` で `matches_expected` を確認し、`false` の場合は既存の Tier 2→Tier 3 エスカレーション経路に委譲するよう修正する。

## Reproduction Steps

1. `.wholework.yml` で `autonomy: L2` または `L3` の環境 (この wholework リポジトリ自身は `autonomy: L3` + `auto-retry-on-fail.enabled: true`) で `/auto` を実行する。
2. code-patch phase で `run-code.sh --patch` (`auto-retry-on-fail` 有効時はその組み込みリトライも含む) が exit 0 で終了するが、`origin/main` に `closes #N` を含むコミットが作成されない (silent no-op)。
3. `run-auto-sub.sh` の Tier 1 reconciler check (`reconcile-phase-state.sh code-patch $N --check-completion`) が `matches_expected:false` を返す。
4. Tier 2 `apply-fallback.sh code-patch $N --log <log>` が呼ばれ、ログ中の `"silent no-op"` 文字列から `code-patch-silent-no-op` anchor が検出される。
5. `apply_code_patch_silent_no_op_retry()` が retry (または `AUTO_RETRY_ENABLED=true` の場合は組み込みリトライ済みとして skip) を行うが、完了確認を行わずに正常終了する。
6. `case "$symptom_anchor"` の `code-patch-silent-no-op)` ブランチが無条件に `result=recovered` を printf し、`apply-fallback.sh` が exit 0 で終わる。
7. `run-auto-sub.sh` は `_fallback_exit=0` を Tier 2 成功と判断し、Tier 3 にエスカレーションしないまま処理を完了する — 実際にはコード変更は行われていない。

実際に #895・#904 (batch session `5169-1783172364`, 2026-07-04〜05) で発生した: 両 Issue とも Tier 2 が `result=recovered` を報告したが、事後の `reconcile-phase-state.sh --check-completion` は `matches_expected:false`・`commits_found:false` を示していた。

## Root Cause

`scripts/apply-fallback.sh` の `apply_code_patch_silent_no_op_retry()` は retry 実行 (または `AUTO_RETRY_ENABLED=true` 時の skip) のみを行い、その後の完了確認を一切行わずに関数を終える — 現状、明示的な失敗パスが存在せず常に成功として返る。呼び出し元の `case "$symptom_anchor"` の `code-patch-silent-no-op)` ブランチはハンドラ関数がエラーを返さない限り無条件に `result=recovered` を printf する。この結果、`run-auto-sub.sh` の Tier 2 dispatcher (`_fallback_exit` 判定) は常に Tier 2 recovered と判断し、Tier 3 (`spawn-recovery-subagent.sh`) へのエスカレーションが発火しない。

なお `apply_code_patch_silent_no_op_retry()` には既に `AUTO_RETRY_ENABLED` ガード (run-code.sh 組み込みリトライが既に使い果たされている場合は Tier 2 retry 自体を skip し、二重retryを防ぐ) が実装済みだが、これは「retry を二重に行わない」ためのガードであり「retry (または skip) 後に完了を確認する」という本 Issue の要求とは独立した軸の対応であるため、今回のバグは解消されないまま残っている。

## Changed Files

- `scripts/apply-fallback.sh`: `apply_code_patch_silent_no_op_retry()` の retry/skip 後に `reconcile-phase-state.sh` completion check を追加し、`case "code-patch-silent-no-op)"` ブランチを結果に応じて分岐させる — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `code-patch-silent-no-op` エントリの Fallback Steps / Escalation 記述を実装に合わせて更新 — bash 3.2+ compat 注記は不要 (Markdown ドキュメント)
- `tests/apply-fallback.bats`: `setup()` に `reconcile-phase-state.sh` のデフォルト mock を追加 (既存テストの回帰防止)、および matches_expected:false → Tier 3 エスカレーションを検証する新規テストを追加

## Implementation Steps

1. `scripts/apply-fallback.sh` の `apply_code_patch_silent_no_op_retry()` を修正する (→ AC1):
   - 既存の retry / skip ロジック (`AUTO_RETRY_ENABLED` 分岐) はそのまま維持する
   - 関数末尾に `"$SCRIPT_DIR/reconcile-phase-state.sh" "$PHASE" "$ISSUE" --check-completion 2>/dev/null | grep -q '"matches_expected":true'` を `if` 条件として追加する (`run-auto-sub.sh` の Tier 1 reconciler チェックと同一パターン)。true なら `return 0`、false ならエラーメッセージを stderr に出力して `return 1`

2. `scripts/apply-fallback.sh` の `case "$symptom_anchor"` 内 `code-patch-silent-no-op)` ブランチを修正する (→ AC1):
   - `apply_code_patch_silent_no_op_retry` の戻り値を `if` で判定し、成功時のみ既存の `result=recovered` printf を実行する
   - 失敗時は printf をスキップして `exit 1` とする (既存の Tier 2→Tier 3 exit-code ベースエスカレーションにそのまま委譲する。新しい abort 経路は追加しない)

3. `modules/orchestration-fallbacks.md` の `code-patch-silent-no-op` エントリの Fallback Steps / Escalation を更新する (→ ドキュメント整合性):
   - Fallback Steps の 2 番目を「retry (または組み込みリトライ済みで skip) 後、`reconcile-phase-state.sh code-patch <issue> --check-completion` で `matches_expected` を確認する。`false` の場合は Tier 3 にエスカレーションする」に変更する

4. `tests/apply-fallback.bats` の `setup()` に `reconcile-phase-state.sh` のデフォルト mock (`matches_expected:true` を返す) を `$MOCK_DIR` に追加する (→ 既存テストの回帰防止、AC2 の前提):
   - 既存の `code-patch-silent-no-op` 関連テスト2件がこの mock を利用して現状どおり PASS することを確認する

5. `tests/apply-fallback.bats` に新規テストを追加する (→ AC2):
   - テスト内で `reconcile-phase-state.sh` mock を `matches_expected:false` を返すよう上書きし、`apply-fallback.sh code-patch <issue> --log <log>` の `$status` が非0であること、かつ `$output` に `result=recovered` が含まれないことを検証する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/apply-fallback.shのapply_code_patch_silent_no_op_retry()内で、run-code.sh --patch retry完了後にreconcile-phase-state.sh --check-completionの結果を確認する処理が実装されている" --> `code-patch-silent-no-op` Tier 2 fallback (`scripts/apply-fallback.sh` の `apply_code_patch_silent_no_op_retry()`) の retry 後に `reconcile-phase-state.sh code-patch <issue> --check-completion` の `matches_expected` を確認する処理が追加されている
  <!-- verify: grep "check-completion" "scripts/apply-fallback.sh" -->
- <!-- verify: rubric "tests/apply-fallback.batsに、code-patch-silent-no-op fallbackのretryがsilent no-op (no commit) で返るケースでresult=recoveredとして報告されず非0 exitでTier 3エスカレーションに委譲されることを検証するテストが含まれる" --> bats test で、retry が silent no-op で返ったケースに対して `result=recovered` を返さない (既存の Tier 2→Tier 3 エスカレーション経路に委譲される) ことが検証されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テストスイート全体) が green

### Post-merge

- 次回 `/auto --batch` 実行時、Tier 2 fallback が発火した Issue の `## Auto Retrospective` セクションで `result=recovered` を持つエントリの reconcile 結果と実 commit の一致を観察 <!-- verify-type: observation event=auto-run -->

## Notes

- 実装対象ファイルの訂正 (`scripts/run-auto-sub.sh` → `scripts/apply-fallback.sh`) は `/issue 906 --non-interactive` フェーズで既に確定済み (Issue 本文 Auto-Resolved Ambiguity Points 参照)。本 Spec 作成時のコード確認 (`scripts/apply-fallback.sh` 実読) でも同一ファイルであることを再確認した。
- `modules/orchestration-fallbacks.md` の既存 Fallback Steps は「retry が exit 1 した場合」のみ Tier 3 エスカレーションを記述しているが、実際の silent no-op は retry (`run-code.sh`) が exit 0 で返るケースであるため、この記述と実装の間には元々ギャップがあった。今回の修正でこのギャップを解消する。
- Option B (他の Tier 2 ハンドラへの同型ガード全走査) は Issue 本文で明示的にスコープ外とされている。本 Spec も `code-patch-silent-no-op` ハンドラ単体の修正のみを対象とする。
- `docs/product.md` / `docs/tech.md` / `docs/structure.md` (および `docs/ja/` 対訳) の `apply-fallback.sh` 言及箇所は grep で確認済みだが、いずれも「Tier 2 known-pattern recovery」という高レベルの役割説明に留まり、retry→completion-check→エスカレーションの内部粒度までは踏み込んでいないため、更新不要と判断した。

## Consumed Comments

- saito (MEMBER, first-class) — `/issue 906 --non-interactive` の Issue Retrospective。実装対象ファイルの訂正 (`apply-fallback.sh`) と AC1〜3 の確定内容を記録したコメント。内容は既に Issue 本文に反映済みのため、Spec 側での追加対応は不要と判断した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #907 は mergeable=true (CI green, review approved) のため conflict 解消ステップをスキップし、squash merge を直接実行した
- squash merge 後、`review+pr-907` worktree が旧ブランチ `worktree-code+issue-906` を占有していたため merge 完了を妨げていた stale worktree を削除し、ローカルブランチも削除した

### Deferred Items
- None

### Notes for Next Phase
- Post-merge verification は次回 `/auto --batch` 実行時に Tier 2 fallback 発火 Issue の `result=recovered` エントリと実 commit の一致を観察することで行う (Spec の Post-merge 節参照)
- `/code 906 --pr --non-interactive` (code フェーズ): No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps の Option A どおりに実装した。

### Design Gaps/Ambiguities
- `apply_code_patch_silent_no_op_retry()` の completion check は「関数末尾」に置く設計だったため、既存の `AUTO_RETRY_ENABLED=true` 分岐の早期 `return 0` を `if/else` に書き換えて両分岐が同じ completion check に合流するようにした。Spec の Implementation Steps には明記されていなかった小さな構造変更だが、「retry (または skip) 後に完了を確認する」という Purpose の要求を両分岐に一律適用するために必要だった。
- `/code` skill 自身の Step 11 (pr route) に `gh pr create` 実行前の `git push origin HEAD` の明記がなく、未 push のブランチで `gh pr create` が失敗する事象を実際に踏んだ。本 Issue のスコープ外 (`/code` skill 自体の改善) のため、フォローアップ Issue #908 (`retro/code`) を起票した。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `apply_code_patch_silent_no_op_retry()` の completion check は、retry を実行した分岐と `AUTO_RETRY_ENABLED=true` によりスキップした分岐の両方が合流する関数末尾に置いた (`if/else` + 共通の completion check)。理由: skip 分岐だけ検証を免除すると、built-in retry が既に使い果たされているケースでの silent no-op を見逃す可能性が残るため。
- `case "code-patch-silent-no-op)"` は `apply_code_patch_silent_no_op_retry` の戻り値で分岐させ、失敗時は `printf` をスキップして `exit 1` とした。新しい abort 経路は追加せず、既存の Tier 2→Tier 3 (`run-auto-sub.sh` の exit-code ベース) エスカレーションをそのまま再利用する Issue 本文の方針に従った。
- `tests/apply-fallback.bats` の `setup()` に `reconcile-phase-state.sh` のデフォルトモック (`matches_expected:true`) を追加し、既存の 2 件の `code-patch-silent-no-op` テストが回帰なく PASS することを確認した。

### Deferred Items
- Option B (他の Tier 2 ハンドラへの同型ガード全走査) は Issue 本文で明示的にスコープ外とされているため未着手。
- `/code` skill 自身の pr route Step 11 に `git push origin HEAD` の明記がない gap はフォローアップ Issue #908 (`retro/code`) に切り出し、本 Issue のスコープ外とした。

### Notes for Next Phase
- `bats tests/` フルスイート (1064 tests) を実行し全件 PASS を確認済み (behavioral change detection により `tests/apply-fallback.bats` 単体ではなくフルスイートを実行)。
- Issue AC3 (`github_check "gh pr checks" "Run bats tests"`) は PR 作成前のため pre-merge 時点では UNCERTAIN。PR #907 の CI green を review/merge フェーズで確認すること。
- PR #907 は `closes #906` を含む。
