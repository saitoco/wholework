# Issue #987: auto: review/merge フェーズのイベント集計に PR→Issue 番号解決を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 2026-07-11T13:05:11Z
  - 要旨: `/issue 987 --non-interactive` の Issue Retrospective。実装方式として emit 時解決を採用した理由 (#974 の `_EXTRA_SELF_ISSUE` 伝搬パターンの再利用、根本原因を修正できる点)、#984 との共通ヘルパ化を待たず独立実装とする理由 (スコープの広さ、AC への影響なし)、AC1 rubric を emit 時解決の挙動に絞り込んだ経緯を記録。Issue 本文の Auto-Resolved Ambiguity Points と同内容。
  - URL: https://github.com/saitoco/wholework/issues/987#issuecomment-4946094497

## Overview

`/auto` の PR route (Size M/L) で review/merge フェーズを実行する際、`.tmp/auto-events.jsonl` に emit されるイベントの `issue` フィールドが実 Issue 番号ではなく PR 番号になってしまうバグを修正する。`get-auto-session-report.sh` はこの `issue` フィールドを一意集計に使うため、PR 番号が実 Issue とは別の "Issue" として二重集計され、"Issues processed" 等のメトリクスが歪む。

方式は Issue 本文で確定済みの **emit 時解決**: `run-auto-sub.sh` の `run_phase_with_recovery()` が review/merge phase 呼び出し時点で既に受け取っている実 Issue 番号 (`_EXTRA_SELF_ISSUE`、#974 で導入済みの伝搬パターンを再利用) を使って `EMIT_ISSUE_NUMBER` を実 Issue 番号に解決し、PR 番号は新設の `pr` フィールドに別途記録してトレーサビリティを維持する。集計時解決 (`get-auto-session-report.sh` 側での PR→Issue マージ) は根本原因を修正できないため不採用 (Issue 本文 Auto-Resolved Ambiguity Points 参照)。

## Reproduction Steps

1. Size M または L の Issue を `/auto` (内部的には `run-auto-sub.sh`) で PR route 実行する
2. code-pr phase 完了後、review phase (`run_phase_with_recovery "review" "$PR_NUMBER" ...`) と merge phase (`run_phase_with_recovery "merge" "$PR_NUMBER" ...`) が PR 番号を引数に呼び出される (`scripts/run-auto-sub.sh:680,683,750,753`)
3. `.tmp/auto-events.jsonl` を確認すると、review/merge phase 中に emit された `phase_start`/`phase_complete`/`recovery`/`concurrent_commit_detected` 等のイベントの `issue` フィールドが `$PR_NUMBER` になっている (実 Issue 番号ではない)
4. `get-auto-session-report.sh --metrics-only` (または `/audit auto-session`) でセッションを集計すると、この PR 番号が独立した "Issue" としてカウントされ、"Issues processed" が実 Issue 数より多くなる。実例: batch session `18964-1783692542` で実 Issue 7 件 + PR #978/#983/#985 = "Issues processed: 10" と誤集計された

## Root Cause

`scripts/run-auto-sub.sh` の `run_phase_with_recovery(phase, issue, runner_script, ...)` は、review/merge phase 呼び出し時に第 2 引数 `issue` として `$PR_NUMBER` を受け取り、関数冒頭 (`run-auto-sub.sh:399`) で `export EMIT_ISSUE_NUMBER="$issue"` を無条件に実行する。`scripts/emit-event.sh` の `emit_event()` は常に `$EMIT_ISSUE_NUMBER` を JSON の `issue` フィールドに書き込むため、関数内の全 `emit_event` 呼び出し (`phase_start` / `wrapper_exit` / `token_usage` / `concurrent_commit_detected` / `phase_complete` / `recovery`) が PR 番号を `issue` として記録してしまう。

#974 (`fix: include Issue number in merge/review self-exclusion pattern`, commit `fe753652`) で review/merge 呼び出し元 4 箇所 (`run-auto-sub.sh:680,683,750,753`) に既に `_EXTRA_SELF_ISSUE="$SUB_NUMBER"` (実 Issue 番号) が伝搬されているが、これは `concurrent_commit_detected` の自己コミット除外正規表現 (`_self_issue_pattern`) の構築にのみ使われており (`run-auto-sub.sh:452-455`)、`EMIT_ISSUE_NUMBER` 自体の解決には使われていなかった。呼び出し元は実 Issue 番号を既に知っているため、同じ伝搬経路を `EMIT_ISSUE_NUMBER` の解決にも再利用すれば根本原因を解消できる。

なお `scripts/run-review.sh` / `scripts/run-merge.sh` 自身の `export EMIT_ISSUE_NUMBER="$PR_NUMBER"` (各スクリプトの `_EMIT_PHASE_OWNED` ブロック内) は `EMIT_PHASE_NAME` が未設定のとき (= 直接単体実行されたとき) のみ実行される分岐であり、`run-auto-sub.sh` 経由 (`EMIT_PHASE_NAME` 設定済み) では実行されない。したがって `run_phase_with_recovery()` 側の修正のみで、呼び出し元 4 箇所を変更せずに根本原因を解消できる。

## Changed Files

- `scripts/emit-event.sh`: `emit_event()` に、`EMIT_PR_NUMBER` 環境変数が設定されている場合のみ `pr` フィールドを JSON に追加する仕組みを実装。冒頭コメントの `Optional env vars` に `EMIT_PR_NUMBER` を追記 — bash 3.2+ compatible (連想配列等の新規 bashism なし)
- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 冒頭の `EMIT_ISSUE_NUMBER` 解決ロジックを、`_EXTRA_SELF_ISSUE` が設定され `issue` (PR番号) と異なる場合に実 Issue 番号へ切り替える分岐に変更。あわせて同ファイル内 `_maybe_emit_phase_complete()` (script 全体の EXIT trap、`emit_event()` を経由しない printf 直書き JSON) にも同じ `pr` フィールドを追加し、backfill 時も一貫させる — bash 3.2+ compatible (既存の `if`/`export`/`unset` パターンのみ)
- `modules/event-emission.md`: event schema SSoT に `pr` フィールド (JSON 例つき) と `EMIT_PR_NUMBER` (Optional environment variables) を追記。Wrapper Coverage Table の `run-auto-sub.sh` 行の Notes を issue/pr 解決の説明に更新
- `tests/emit-event.bats`: `EMIT_PR_NUMBER` 設定時に `pr` フィールドが出力され、未設定時は出力されない (既存イベント形状に影響しない) ことを検証するテストを追加
- `tests/run-auto-sub.bats`: review/merge phase (`_EXTRA_SELF_ISSUE` 経由) で emit されるイベントが `issue=<実Issue番号>` `pr=<PR番号>` を記録し、code phase では `pr` フィールドが付与されない (Size M のデフォルトフィクスチャ: `SUB_NUMBER=42`, `PR_NUMBER=99`) ことを検証する regression テストを追加 (#974 の `emit.log` キャプチャパターンを踏襲)

## Implementation Steps

1. `scripts/emit-event.sh` の `emit_event()` 内、`local json="{\"ts\":\"${ts}\",\"issue\":${_issue},\"event\":\"${event_type}\",\"session_id\":\"${_sid}\""` の直後に、`EMIT_PR_NUMBER` が空でない場合のみ `json="${json},\"pr\":${EMIT_PR_NUMBER}"` を追加する分岐を挿入する (`while [[ $# -gt 0 ]]; do` ループの前)。ファイル冒頭のコメントブロック `# Optional env vars:` に `EMIT_PR_NUMBER` の説明を1行追加する (→ acceptance criteria A)
2. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、`export EMIT_ISSUE_NUMBER="$issue"` の行を次の分岐に置き換える: `_EXTRA_SELF_ISSUE` が設定されておりかつ `issue` と異なる場合は `EMIT_ISSUE_NUMBER="$_EXTRA_SELF_ISSUE"` と `EMIT_PR_NUMBER="$issue"` を export し、それ以外の場合は従来通り `EMIT_ISSUE_NUMBER="$issue"` を export したうえで `EMIT_PR_NUMBER` を unset する (次回呼び出しへの値の漏れ出しを防ぐため)。`export EMIT_PHASE_NAME="$phase"` の行は変更しない (after 1) (→ acceptance criteria A)
3. `run-auto-sub.sh` の `_maybe_emit_phase_complete()` 内、`if [[ "${_last_event}" == "phase_start" ]]; then` ブロックの backfill JSON を構築する `printf` 呼び出しに、`EMIT_PR_NUMBER` が設定されている場合のみ `,\"pr\":${EMIT_PR_NUMBER}` を `"backfilled":true` の直前に挿入するローカル変数 (`_pr_field`) を追加する (`emit_event()` を経由しない直書き箇所のため 1 の変更が自動適用されないことへの個別対応) (after 1) (→ acceptance criteria A)
4. `modules/event-emission.md` に、review/merge phase イベントが `pr` フィールドを持ちうることを示す JSON 例と、`Optional environment variables` セクション (`EMIT_PR_NUMBER` 行) を追記する。`Wrapper Coverage Table` の `run-auto-sub.sh` 行の Notes に「review/merge 呼び出し時は `_EXTRA_SELF_ISSUE` により `EMIT_ISSUE_NUMBER`/`EMIT_PR_NUMBER` を実 Issue/PR 番号に解決」という旨を追記する (after 2, 3) (→ documentation completeness)
5. `tests/emit-event.bats` に `EMIT_PR_NUMBER` 設定時/未設定時の `pr` フィールド有無を検証するテストを追加する。`tests/run-auto-sub.bats` に、Size M のデフォルトフィクスチャ (`SUB_NUMBER=42`, `PR_NUMBER=99`) で `bash "$SCRIPT" 42` を実行し、review/merge phase の `emit_event` 呼び出し時点で `$EMIT_ISSUE_NUMBER`=42 かつ `$EMIT_PR_NUMBER`=99 であること、code-pr phase では `$EMIT_PR_NUMBER` が空であることを検証する regression テストを追加する (#974 の emit.log キャプチャパターンを踏襲) (after 2, 3) (→ acceptance criteria B)

## Verification

### Pre-merge
- <!-- verify: rubric "review/merge phase のイベント (phase_start/phase_complete/recovery/concurrent_commit_detected 等) が emit 時点で issue フィールドに実 Issue 番号を記録し、PR 番号は別途 pr フィールドで保持する仕組みが実装されている" --> review/merge イベントが emit 時点で実 Issue 番号を issue フィールドに記録する
- <!-- verify: rubric "tests/ 配下に、review/merge phase イベントを含むセッションの集計で PR 番号が独立 Issue として出現しないことを検証するテストが存在する" --> PR 番号の独立 Issue 混入を防ぐ regression テストが追加されている

### Post-merge
- 次回 pr route を含む `/auto --batch` の L3 session report で、Issues processed が実 Issue 数と一致することを観察 (`<!-- verify-type: observation event=auto-run -->` — `auto-run` イベント発火時に `<!-- verify: rubric "対象セッションの L3 session report (get-auto-session-report.sh の Metrics 出力) で、Issues processed の値がそのセッションで実際に処理された Issue 数と一致しており、review/merge phase の PR 番号が独立した Issue として計上されていない" -->` で再評価)

## Notes

- **Auto-Resolve Log は Issue Retrospective コメントを参照**: 実装方式 (emit 時解決 vs 集計時解決) の採用理由、#984 との独立実装の判断は、いずれも Issue 本文の `## Auto-Resolved Ambiguity Points` と `/issue 987 --non-interactive` の Issue Retrospective コメントに記録済み。本 Spec では重複記載しない。
- **post-merge observation AC への rubric 付与 (`/spec` Step 10 自動対応)**: 元の post-merge AC は `<!-- verify-type: observation event=auto-run -->` タグのみで、観測イベントと期待される出力構造の分離が prose 内に留まっていた (`modules/verify-classifier.md` の observation-tagged 条件チェック)。Option B (同一行への rubric verify command 付与) を採用し、Issue 本文を更新済み。Spec の Post-merge Verification には更新後の内容を反映した。
- **`run-review.sh` / `run-merge.sh` 自身の backfill trap は対象外とする判断**: 両スクリプトはそれぞれ独自の `_maybe_emit_phase_complete()` (printf 直書き、`emit_event()` 非経由) を持つが、`EMIT_ISSUE_NUMBER`/`EMIT_PR_NUMBER` は `run-auto-sub.sh` からの `export` を子プロセスとして継承するため、`issue` フィールド自体は本 Spec の Implementation Steps 2 の修正のみで正しくなる (`EMIT_PHASE_NAME` が既に設定されているため、両スクリプト自身の `_EMIT_PHASE_OWNED` ブロック — `export EMIT_ISSUE_NUMBER="$PR_NUMBER"` を含む — は実行されない)。両スクリプト自身の backfill JSON に `pr` フィールドを追加する対応 (SIGTERM/watchdog kill 時の稀な backfill レコードのみに影響する軽微な一貫性向上) は、AC の必須要件ではなく light spec のスコープ外として見送った。
- **`get-auto-session-report.sh` は変更不要と判断**: 同スクリプトの `unique | length` によるユニーク Issue 集計 (line 175, 272 付近) は `issue` フィールドをそのまま使う既存ロジックであり、emit 時点で `issue` フィールドが正しくなれば追加の集計側修正なしに "Issues processed" の水増しは解消される。同スクリプトが既に持つ `_pr_num=$(gh pr list --search "closes #${_num}" ...)` (line 312 付近、表の PR 列表示用) は本 Issue が明示的に不採用とした「集計時解決」とは別目的の既存機能であり、本 Spec では変更しない。
- **docs/workflow.md, docs/tech.md, docs/structure.md, docs/migration-notes.md は変更不要と判断**: いずれも `run-auto-sub.sh`/`emit-event.sh` に言及があるが (grep 済み)、ワークフロー全体像やアーキテクチャ概要レベルの記述に留まり、イベント JSON スキーマの詳細 (今回変更対象) には踏み込んでいない。`docs/migration-notes.md` の言及は private→public 移行時点の履歴記録であり対象外。SSoT である `modules/event-emission.md` のみを更新する。

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1〜5 を設計通りの順序・内容で実装した。

### Design Gaps/Ambiguities
- **`/code` Step 3 の `phase/ready` チェック前提と実際の label 履歴の不一致**: 実行開始時点で Issue #987 のラベルは `phase/ready` ではなく既に `phase/code` だった。GitHub timeline を確認したところ、本セッション開始前に別の `/code` 実行が `phase/ready→phase/code` 遷移まで完了させた後、実装コミットを残さず中断していたことが判明した (Spec は既存、コミット履歴には spec コミットのみ)。`/code` Step 3 の分岐は「`phase/ready` 不在 = Spec 未生成」を暗黙の前提としているが、今回のように「前回実行が既に `phase/code` へ進めた後に中断した」ケースでは Spec が既存のまま `phase/ready` が不在になる。既存 Spec を読み込んで続行することで正しく処理できたが、この中断→再開パターンを Step 3 のチェックロジックが明示的に区別していない点は改善余地として残る (直接のスコープ外、独立した改善提案として起票は見送り — 発生頻度が低く、既存 Spec の有無で安全にフォールバックできているため)。

### Rework
- なし。

## review retrospective

### Spec vs. implementation divergence patterns
- なし。review-spec 相当の観点 (review-light Perspective 1) で Spec Implementation Steps 1〜5 と PR diff の一致を確認した。

### Recurring issues
- **「開発環境の偶発的な env var 汚染がテストのバグを隠蔽する」パターンを検出**: 本 Issue が修正しようとしていた対象そのもの (`run_phase_with_recovery()` が `EMIT_ISSUE_NUMBER`/`EMIT_PHASE_NAME`/`_EXTRA_SELF_ISSUE` を `export` する仕組み) により、`/auto` 経由で起動された worktree セッション (今回の `/code`/`/review` 実行環境を含む) には、これらの変数がアンビエントに存在する。今回追加された regression テスト (tests/run-auto-sub.bats:998) のモックは `$EMIT_PHASE_NAME` を `set -u` 下でデフォルト値なしに参照しており、`emit_event "sub_start"` (EMIT_PHASE_NAME 設定前) 呼び出し時にクラッシュするバグを含んでいた。PR 作成者のローカル実行では偶然これらの変数が既にエクスポートされていたため「フルスイート 1130 件すべて PASS」と誤って報告され、クリーンな GitHub Actions ランナーでのみ実際に FAIL した。`/review` Step 9 (CI Status Check) が FAILURE を検出し、`env -i` によるクリーン環境再現で根本原因を特定できた。
  - **改善提案**: `EMIT_*`/`_EXTRA_SELF_ISSUE` のような env var を介した状態伝搬パターンをテストするコードは、bats テスト実行前に `env -i HOME="$HOME" PATH="$PATH" bash -c 'bats ...'` のようなクリーン環境での実行を Local 開発ガイドラインに明記する、または CI 設定自体がクリーン環境である前提に依存せず bats のテストヘルパー内で明示的に `unset EMIT_ISSUE_NUMBER EMIT_PHASE_NAME EMIT_PR_NUMBER _EXTRA_SELF_ISSUE AUTO_SESSION_ID` する setup() の防御的初期化を追加する、のいずれかを検討する価値がある (`/verify` での Improvement Proposal 集約時に起票判断)。

### Acceptance criteria verification difficulty
- なし。Pre-merge AC 2件は rubric verify command により UNCERTAIN なく PASS 判定できた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- `gh-pr-merge-status.sh` で mergeable=true (ci_status=success, review_status=approved) を確認し、コンフリクト解消・rebase ステップは不要と判断した。
- squash merge (`gh pr merge --squash --delete-branch`) を実行し、リモートブランチ `worktree-code+issue-987` を削除済み。

### Deferred Items
- `_maybe_emit_phase_complete()` backfill パスへの `pr` フィールド regression テスト追加 (SHOULD) — review retrospective 記載の通り次回関連改修時に着手余地あり。
- Post-merge observation AC は次回の pr route を含む batch 実行時に `/verify` が rubric で再評価する (変更なし)。

### Notes for Next Phase
- `/verify` は post-merge observation AC (`auto-run` イベント発火時の rubric 再評価) を確認すること。
- review retrospective に記録された「開発環境の env var 汚染がテストのバグを隠蔽するパターン」の Improvement Proposal 起票判断は `/verify` 側で行うこと。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 品質は高く、pre-merge rubric 2 件とも UNCERTAIN なく判定できた。post-merge observation AC への rubric 付与 (Option B) により event 発火時の再評価基準が機械参照可能になっている。

#### design
- 設計通り。#974 で確立済みの `_EXTRA_SELF_ISSUE` 伝搬パターンを `EMIT_ISSUE_NUMBER` 解決に再利用する判断が実装リスクを下げた。

#### code
- 前回 `/code` 実行が `phase/ready→phase/code` 遷移後に実装コミットなしで中断していた状態からの再開だった (Code Retrospective 記載)。既存 Spec の読み込みで安全にフォールバックできた。
- code-pr wrapper の exit-0 informational anomaly check が `code-completed-no-pr` を出力したが、実際には PR #988 は作成済みで false-positive だった (watchdog kill → 内部 retry 成功後の初回試行痕跡による誤検出)。これは既起票 #981 の既知パターンそのものであり、本 batch 内で #981 の修正が予定されている。recovery は発生しておらず、記録ギャップではない (verify 時の初期解釈を訂正)。

#### review
- CI FAIL (開発環境の env var 汚染がテストのバグを隠蔽するパターン) を review Step 9 が検出し、`env -i` によるクリーン環境再現で根本原因を特定・修正できた。review が機能した好例。

#### merge
- 問題なし。mergeable 確認のうえ squash merge、リモートブランチ削除済み。

#### verify
- pre-merge 2 件 PASS (rubric、commit c1ef02c4 の diff で確認)。post-merge observation AC は event=auto-run 待ちで SKIPPED。
- 本 Issue 自身の `/auto` 実行は修正前の `run-auto-sub.sh` で走ったため、当該セッションの review/merge イベントは `issue=988` (PR 番号) で記録されている (bootstrap 実行の既知アーティファクト)。修正は同一 batch セッション内の後続 Issue および次回セッションから有効。

### Improvement Proposals
- bats テストの env var 汚染への防御的初期化: `/auto` 経由の worktree セッションでは `EMIT_ISSUE_NUMBER`/`EMIT_PHASE_NAME`/`EMIT_PR_NUMBER`/`_EXTRA_SELF_ISSUE`/`AUTO_SESSION_ID` がアンビエントに export されており、これらを参照するテストのバグを隠蔽して false PASS を生む (本 Issue の review で実例発生。`tests/run-auto-sub.bats` / `tests/emit-event.bats` の setup() には防御的 unset がない — `tests/run-spec.bats` 等には既に部分的に存在)。bats の setup() でこれらを明示的に `unset` する防御的初期化を追加する。
- ~~Tier 2 recovery の記録経路ギャップ~~ → 訂正: 実際は recovery ではなく #981 既知の exit-0 false-positive anomaly 出力だった。#981 で対応済みのため起票不要。
