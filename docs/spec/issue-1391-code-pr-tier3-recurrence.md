# Issue #1391: recoveries: code-pr-tier3-recovery の再発パターンを分析し恒久対策を検討

## Overview

`code-pr-tier3-recovery` symptom が #799 クローズ (2026-06-27 22:23 UTC) 後に3件 (#1224, #995, #893) 再発した。`docs/reports/orchestration-recoveries.md` の該当エントリ (L306, L1384, L1470) を精査した結果、**単一の共通 root cause ではなく、少なくとも3つの異なる原因**に分かれることが判明した。

1. **#1224 (2026-08-07 07:41 UTC)**: diagnosis に「Five silent no-op retries wasted ~90 minutes re-running /code instead of pushing the existing work」と明記されている通り、`run-code.sh` の内蔵 auto-retry-on-fail 機構 (exec ベース、`scripts/run-code.sh` L377-414) が、worktree branch `worktree-code+issue-1224` に既にコミット済み (未 push) の実装が存在する場合でも区別できず、`/code` フェーズをフルに再実行する retry を繰り返した。**根本原因は `_completion_code_pr()` (`scripts/reconcile-phase-state.sh` L334-357) が `_completion_code_patch()` (同ファイル L212-333) に既に実装されている `worktree_commits_found` 診断シグナル (L297-311) を持たないこと** — このシグナルの欠如により、pr route の retry gate は「何も完了していない」状態と「実装済みだが push 未了」の状態を区別できず、後者でも前者と同じ exec retry を選択してしまう。
2. **#995 (2026-07-12 06:18 UTC)**: diagnosis は「bats実行待ちのwatchdog kill が繰り返され、コミット・push・PR作成の直前で毎回中断された」と記録しており、commit 自体が未実施 (`git rev-list` 上は HEAD が main と同一) である点で #1224 と異なる。bats 実行時間に起因する watchdog kill (exit 143) の反復という点で、既存の「background wait」再発系統 (#994→#1102→#1212/#1213/#1234、真因は test-runner 側の固定タイムアウト) に近い形状。
3. **#893 (2026-07-04 15:25 UTC)**: diagnosis は「/code フェーズ自身の L0 comment-consumption ログ書き込みが `docs/spec/issue-893-l3-findings-disposition-tags.md` として parent main に直接コミットされ、`check-verify-dirty` がブロックした」と記録しており、worktree-path-misuse 系統 (#882/#888 — worktree 向けの編集が parent main に landing する既知パターン) に近い形状。

3件とも exit code 1 で共通するが、これは `run-code.sh` の内蔵 auto-retry が尽きた際の終端コード (`scripts/run-code.sh` L413 `EXIT_CODE=1`) であり、根本原因の共通性を意味しない。`_completion_code_pr()` 自身のコメント (L335: 「Stage 2 recovery (push+PR creation) is delegated to #316 recovery sub-agent」) が示す通り、push+PR 実行そのものを Tier 2 で自動化しない設計は元々意図的な判断であり、本 Issue はその判断自体を覆すものではない — 対象とするのは「retry すべきでない状態で retry してしまう」という gate 側の判別不足のみである。3件は #799 が対象とした watchdog kill (exit 143) 系の直接的な再発ではない。

本 Issue では、3件のうち最も直接的な証拠 (diagnosis 内の明示的な記述) と機械的な修正可能性を備える **原因1 (#1224)** を恒久対策の対象とする。原因2・3は性質が異なり Size S の本 Issue 単体では解決しない — 詳細を Notes に記録し、再発時は別 cause slug での起票を推奨する。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_pr()` (L334-357) に `worktree_commits_found` 診断シグナルを追加。`_completion_code_patch()` (L297-311) の既存パターンをミラー。bash 3.2+ 互換
- `modules/phase-state.md`: Field contract table の `actual.worktree_commits_found` 行 (L120) の `Required` 列を `code-pr` completion にも対応するよう拡張
- `scripts/run-code.sh`: auto-retry 判定ブロック (L384-407) に短絡分岐を追加 — `_RECONCILE_PHASE == "code-pr"` かつ reconcile 出力が `"worktree_commits_found":true` を含む場合、exec ベースの retry をスキップし即座に `EXIT_CODE=1` で終了 (Tier 1/2/3 へ早期委譲)。bash 3.2+ 互換
- `docs/tech.md`: 「code/spec-side auto-retry (silent no-op)」bullet (L132) に新しい短絡動作の説明を追記
- `tests/reconcile-phase-state.bats`: `_completion_code_pr()` の `worktree_commits_found` シグナルを検証する新規テストケースを追加 (既存の code-patch 版テスト L1462 相当をミラー)
- `tests/run-code.bats`: `run-code.sh` の新短絡分岐を検証する新規テストケースを追加 (既存 auto-retry テスト群 L738-849 と同じ形式)

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_code_pr()` に `worktree_commits_found` 診断シグナルを追加する。`_completion_code_patch()` の該当ブロック (L306-311: `git rev-list --count "origin/main..worktree-code+issue-${ISSUE_NUMBER}"` を fail-open (`|| worktree_commit_count=0`) で実行し `actual_json` に追記) と同一パターンを踏襲する。あわせて `modules/phase-state.md` の Field contract table (`actual.worktree_commits_found` 行) の `Required` 列に「or `code-pr` completion does not find an open PR」を追記し、code-patch/code-pr 両方に対応する記述へ更新する (→ 恒久対策)
2. `scripts/run-code.sh` の auto-retry 判定ブロック (L384 の `elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then` 直後) に、既存の retry 適格性チェック (L386-388) より前に新しい分岐を追加する: `_RECONCILE_PHASE == "code-pr"` かつ `$_reconcile_out` が `"worktree_commits_found":true` を含む場合、理由を stderr に echo したうえで exec retry を行わず `EXIT_CODE=1` を設定する。既存の CODE_RETRY_COUNT 加算・exec 再起動ロジック (L388-407) はそのまま温存し、この新分岐に該当する場合のみそちらへ到達しないよう条件分岐を追加する (after 1) (→ 恒久対策)
3. `docs/tech.md` の「code/spec-side auto-retry (silent no-op)」bullet 末尾に、code-pr phase で `worktree_commits_found:true` が検出された場合は exec retry をスキップし Tier 1/2/3 へ早期委譲する旨を追記する (#1391 参照) (after 2) (→ 恒久対策)
4. `tests/reconcile-phase-state.bats` に `_completion_code_pr()` の `worktree_commits_found:true`/`false` それぞれを検証する新規 `@test` を追加し (既存 L1462 の code-patch 版と対の形式)、`tests/run-code.bats` に新短絡分岐 (retry せず exit 1) を検証する新規 `@test` を追加する。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケースを追加したうえで両スイートが PASS すること (after 2) (→ 恒久対策、new test case requirement)
5. 3件 (#1224/#995/#893) の diagnosis 比較と root cause 判定結果を本 Spec の Overview/Notes に記録する (→ root cause 特定、AC1)

## Verification

### Pre-merge
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> `_completion_code_pr()` の `worktree_commits_found` シグナル追加を含め、既存 + 新規テストケースが PASS する
- <!-- verify: command "bats tests/run-code.bats" --> `run-code.sh` の新短絡分岐を含め、既存 + 新規テストケースが PASS する
- <!-- verify: file_contains "modules/phase-state.md" "code-pr` completion does not find an open PR" --> `actual.worktree_commits_found` 行の Required 列が code-pr completion にも言及している
- <!-- verify: file_contains "docs/tech.md" "worktree_commits_found:true" --> 「code/spec-side auto-retry (silent no-op)」bullet に code-pr 短絡動作の説明が追記されている

### Post-merge
- #1224 / #995 / #893 の3件を diagnosis 精査し、共通の root cause (exit 1 かつ worktree 残存物あり) を特定する <!-- verify-type: manual -->
- 特定した root cause に対する恒久対策 (または既知パターンとして `orchestration-fallbacks.md` への catalog 追加) が実装され、Issue #1391 作成日 (2026-08-17) 以降に `docs/reports/orchestration-recoveries.md` へ同型の `code-pr-tier3-recovery` エントリが追加されていないことを、次回 `/auto` 完了時点で `docs/reports/orchestration-recoveries.md` を grep して確認する <!-- verify-type: observation event=auto-run -->

## Notes

### 原因2・3 (#995, #893) を本 Issue の対策対象から除外した判断

Size S / SPEC_DEPTH=light の制約 (Implementation Steps ≤5) の下で、3件の診断結果は同一の `code-pr-tier3-recovery` ラベルを共有するが実体は異なる3系統であると判断した (詳細は Overview 参照)。#799 自身も同じラベル配下で「Active-implementation watchdog kill」と「Clean-slate transient hang」の2系統に分けて別々に対処した前例があり、本 Issue でも同じ方針を踏襲する。

- **#995 系統 (uncommitted diff + bats 待ち watchdog kill 反復)**: 対策には bats 実行時間そのものの短縮または watchdog タイムアウト戦略の見直しが必要と見られ、既存の「background wait」再発系統 ([[project_background_wait_recurrence]] 参照、真因は test-runner 側の固定タイムアウト) との重複調査が必要になる可能性が高い。本 Issue の Size では扱わず、再発時に独立した cause slug (例: `code-pr-uncommitted-diff-bats-kill`) で起票することを推奨する。
- **#893 系統 (comment-consumption ログの parent main 直接コミット)**: L0 comment-consumption 手続き (`modules/l0-surfaces.md`) が worktree 境界を越えて書き込まれた経路の特定が必要で、`worktree-path-misuse-parent-dirty` (#882/#888) との関係精査を要する別テーマ。本 Issue の Size では扱わず、再発時に独立した cause slug (例: `code-comment-consumption-parent-dirty`) で起票することを推奨する。

### Fail-safe critical script identification

`scripts/reconcile-phase-state.sh` は `/auto` の Tier 1 completion gate (`modules/orchestration-fallbacks.md` の Observe-Diagnose-Act パターンにおける Diagnose 相当) であり、fail-safe critical スクリプトの基準 (a) に該当する。ただし本 Issue の変更は `matches_expected` の判定ロジック自体には触れず、`_completion_code_patch()` の既存 `worktree_commits_found` フィールド (L306-311 のコメントに明記: 「Diagnostic only — does not affect `matches_expected`」) と全く同じ設計を `_completion_code_pr()` に複製するのみである。依存コマンド (`git rev-list --count`) が失敗した場合の挙動も既存パターンと同一の fail-open (`|| worktree_commit_count=0` → ブランチ不存在時は `false` 側に倒れる) を踏襲し、新たな edge case 設計は発生しない。

`scripts/run-code.sh` の新短絡分岐についても、`reconcile-phase-state.sh` の出力が空/不正な場合は `grep -q` が単純にマッチせず、既存の retry 適格性チェック側にフォールスルーする (fail-open — 短絡せず、これまで通り retry を試みる)。短絡条件を誤って満たした場合の最悪ケースは「本来 retry で解決できたはずの状態を retry せず Tier 1/2/3 に早期委譲する」ことであり、Tier 3 は3件とも100%の成功率 (Outcome: success) を記録しているため、安全側に倒れる設計である。

### New test case requirement summary (SPEC_DEPTH=light — Step 13 retrospective 省略のため本節に記録)

Implementation Step 1・2 はそれぞれ新規分岐ロジックを追加する:
- `_completion_code_pr()` への `worktree_commits_found` フィールド追加 (新規診断ロジック) → `tests/reconcile-phase-state.bats` に true/false 両ケースの新規 `@test` が必要
- `run-code.sh` の auto-retry 判定への短絡分岐追加 (新規分岐ロジック) → `tests/run-code.bats` に「code-pr + worktree_commits_found:true で retry せず exit 1」を検証する新規 `@test` が必要

いずれも Implementation Step 4 および Pre-merge Verification の `command` 検証で担保する。

## Consumed Comments

| Login | Association | Trust tier | Intent | URL |
|-------|-------------|-----------|--------|-----|
| saito | MEMBER | first-class | `/issue --non-interactive` の Issue Retrospective。AC2 を `verify-type: manual` から `verify-type: observation event=auto-run` に再分類したことを報告 (`modules/verify-classifier.md` の Evidence Collection Patterns に合致すると判断)。spec phase 時点で Issue body は既にこの再分類を反映済みであることを確認済み | https://github.com/saitoco/wholework/issues/1391#issuecomment-5326725458 |

code phase (cutoff 2026-08-18T10:30:22Z 以降): No new comments since last phase.

- saito / MEMBER / first-class / ## Change Tracking (by /code) / https://github.com/saitoco/wholework/issues/1391#issuecomment-5327243554

review phase (cutoff 2026-08-18T10:37:58Z 以降):
- saito / MEMBER / first-class / `/code` の Change Tracking コメント (Issue AC Pre-merge を Spec の 4件の verify command に更新した旨の報告)。review 開始時点で既に Issue body に反映済みであることを確認済み、review 側でのアクション不要 / https://github.com/saitoco/wholework/issues/1391#issuecomment-5327243554

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 は Spec の記述通りに実装した。

### Design Gaps/Ambiguities
- `_completion_code_pr()` は元々 `git` コマンドを一切呼び出しておらず (`gh pr list` のみ)、Spec の Implementation Step 1 は `_completion_code_patch()` の `worktree_commit_count` 算出ブロック (L306-311) のみを複製対象として挙げていたが、そのブロックは `_completion_code_patch()` 冒頭の `git fetch origin main --quiet` (別関数、L213) に暗黙で依存している。`_completion_code_pr()` にも同じ `git fetch` を追加しないと `git rev-list --count origin/main..worktree-code+issue-N` が stale なローカル `origin/main` を参照する。Spec 本文に明記はなかったが、`_completion_code_patch()` の既存パターンを厳密にミラーする意図から fetch も追加した。
- 上記の帰結として、既存の `tests/reconcile-phase-state.bats` の code-pr completion テスト2件 ("open PR exists" / "no open PR") が `git` を一切モックしていなかった (旧実装は git を呼ばないため不要だった)。今回の変更で `_completion_code_pr()` が無条件に `git fetch`/`git rev-list` を呼ぶようになったため、この2件にも `$MOCK_DIR/git` モックを追加しないと実環境の `git` に依存する非決定的なテストになってしまう。Spec の Changed Files には新規テスト追加のみが記載されていたが、既存2テストへのモック追加も安全のため同じコミットに含めた。

### Rework
- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC ゲート (`check-pre-merge-ac.sh`) は unchecked_count=0、review-incomplete-fallback チェックも `matches_expected:true` (Review Response Summary found) だったため、override なしで通常経路のままスカッシュマージを実行した。
- `gh-pr-merge-status.sh` が `mergeable=true reason=clean ci_status=success review_status=approved` を返したため、Step 3 (コンフリクト解消) はスキップし Step 4 に直行した。

### Deferred Items
- 原因2 (#995: bats 待ち watchdog kill 反復) と原因3 (#893: comment-consumption ログの parent main 直接コミット) は本 Issue の対策対象外。Spec Notes に記載の通り、再発時は独立した cause slug (`code-pr-uncommitted-diff-bats-kill` / `code-comment-consumption-parent-dirty`) での起票を推奨する。
- Post-merge AC (root cause 判定の記録確認、次回 `/auto` 完了時点での再発なし確認) は `/verify` フェーズで検証される。

### Notes for Next Phase
- Post-merge の観察系 AC (`docs/reports/orchestration-recoveries.md` への同型 `code-pr-tier3-recovery` エントリが Issue #1391 作成日 (2026-08-17) 以降追加されていないこと) は次回 `/auto` 完了時点で確認する必要があるため、`/verify` は現時点で判定不能 (`verify-type: observation event=auto-run`) として扱うこと。
- Pre-merge verify command 4件は review フェーズ時点で全て PASS 済み。merge フェーズでは追加のテスト実行は行っていない (mergeable=clean だったため Step 3 の Run Tests はスキップ)。

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の `### Fail-safe critical script identification` 節は「依存コマンド (`git rev-list --count`) が失敗した場合の挙動も既存パターンと同一の fail-open を踏襲し、新たな edge case 設計は発生しない」と明言していたが、実際には `git rev-list` とは別に新規追加された `git fetch` 呼び出しが `_handle_error` 経由で fail-closed (exit 2) になっており、この記述がカバーしていなかった。`_completion_code_patch()` の既存 `git fetch` (関数冒頭、コア判定自体が依存) と `_completion_code_pr()` の新規 `git fetch` (コア判定後、診断フィールドのためだけの依存) とでは fail-closed の妥当性が異なるにもかかわらず、「既存パターンを複製する」という Spec の表現が両者を暗黙に同一視させ、この非対称性の検討漏れにつながった可能性がある。Code Retrospective (`### Design Gaps/Ambiguities`) は `git fetch` 追加の経緯は記録していたが、追加した `git fetch` の失敗モードそのものは検討されていなかった。

### Recurring issues
- 今回の Parser/Validator Edge Case Pre-check (実測実行によるサブエージェント2件) では findings なしだったが、これは対象を「新規に追加された正規表現/grep パターン」に絞ったためであり、同じ diff 内の「新規に追加された `git` コマンド呼び出しの失敗モード」は firing condition の対象外だった。今回の MUST issue は結果的に通常の review-light (Perspective 2: Edge Cases and Robustness) が検出したが、fail-safe critical script (`scripts/reconcile-phase-state.sh`) への新規外部コマンド依存の追加は、正規表現/validator と同様に構造的な見落としリスクを持つパターンとして観察に値する。

### Acceptance criteria verification difficulty
- Pre-merge の4件はいずれも `command`/`file_contains` で機械的に検証可能であり、UNCERTAIN や verify command の不備はなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Overview の root cause 分析 (#1224/#995/#893 の diagnosis 比較、3系統への分岐判定、原因1 への絞り込み理由) は Post-merge AC5 の要求を過不足なく満たしていた。

#### design
- N/A

#### code
- Code Retrospective に記録済みの通り、`_completion_code_pr()` への `git fetch` 追加という Spec 未記載の派生作業が発生したが、`_completion_code_patch()` の既存パターンを厳密にミラーする目的に沿った妥当な判断であり手戻りではない。

#### review
- review retrospective の Recurring issues が指摘する通り、Parser/Validator Edge Case Pre-check の対象範囲が「新規追加された正規表現/grep パターン」に限定されており、「新規追加された `git` コマンド呼び出しの失敗モード」(今回の fail-open 非対称性 MUST issue の実体) は対象外だった。今回は通常の review-light Perspective 2 が代わりに検出したため実害はなかったが、fail-safe critical script への新規外部コマンド依存追加という構造的パターンとして再発しうる。

#### merge
- pre-merge AC ゲート・review-incomplete-fallback チェックとも通常経路で通過。特記事項なし。

#### verify
- FAIL/UNCERTAIN なし。Post-merge AC5 は Claude Execute で PASS、AC6 は event 未発火のため SKIPPED (次回 `/auto` 完了時に再判定)。

### Improvement Proposals
- Parser/Validator Edge Case Pre-check (`/review` の edge-case サブエージェント起動条件) の対象範囲を、「新規追加された正規表現/grep パターン」だけでなく「fail-safe critical script (`scripts/reconcile-phase-state.sh` 等) への新規外部コマンド依存の追加」も含むよう拡張検討する。今回は通常の review-light が代替検出したため実害はなかったが、observed 事例はまだ1件のみ (本 Issue #1391) — 再発時に起票判断する程度の一回性の高い観察。
