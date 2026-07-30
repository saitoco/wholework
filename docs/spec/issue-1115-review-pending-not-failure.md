# Issue #1115: auto: run-review.sh の PENDING (exit 2) を失敗と区別して 3-Tier recovery に流さない

## Consumed Comments

No new comments since last phase.

## Overview

`run-review.sh` は #1050 で PENDING (exit code 2) という第三の終了状態を獲得した。CI/preview の状態が確定しない場合に review セッションを起動せず `PENDING: ...; skipping review session` を出力して exit 2 で終了する。これは「失敗」ではなく「まだ判定できないので待つべき」という意図された正常系である。しかし呼び出し側 (`scripts/run-auto-sub.sh` の `run_phase_with_recovery()`、および `skills/auto/SKILL.md` pr route の review フェーズ分岐) はこの exit code 2 を他の非 0 終了と区別しておらず、意図どおりに動作した結果 (PENDING) が 3-Tier recovery (Tier 1 reconciler → Tier 2 fallback catalog → Tier 3 recovery sub-agent) を誤って起動させてしまう。

本 Spec は、両方の呼び出し側に「exit code 2 のときは待機後に bounded retry し、それでも解消しなければ通常の失敗経路 (3-Tier recovery) にフォールスルーする」という pre-check を追加し、exit code の意味を文書化する。

## Reproduction Steps

1. `capabilities.pr-preview: true` が設定されたプロジェクト (または CI check-suite がまだ作成されていない PR) で `/auto` の pr route を実行する。
2. `run-review.sh` が CI/preview の状態確定を待つが `WHOLEWORK_CI_TIMEOUT_SEC` / `WHOLEWORK_PREVIEW_TIMEOUT_SEC` 内に確定しない。
3. `run-review.sh` が `PENDING: ...; skipping review session` を出力し、exit code 2 で終了する (review セッションは一度も起動しない)。
4. 呼び出し側 (`run-auto-sub.sh` の `run_phase_with_recovery()`、または `skills/auto/SKILL.md` item 8) が exit code 2 を他の非 0 終了と同様に扱い、Tier 1 reconciler (`reconcile-phase-state.sh review --check-completion`) を実行する。Review Response Summary が存在しないため `matches_expected: false` が返る。
5. Tier 2 (`detect-wrapper-anomaly.sh`) にも該当パターンが登録されていないため、Tier 3 (`spawn-recovery-subagent.sh`) まで進み、高コストな sub-agent 診断が「review が異常終了した」という誤った前提で起動する。

## Root Cause

`scripts/run-review.sh` L151-159 (#1050 で追加) は CI/preview 待機が確定しない場合に exit code 2 を返す。これは意図された「待機すべき」状態を表す第三の終了コードだが、`scripts/run-auto-sub.sh` の `run_phase_with_recovery()` (L751 の `exit_code -eq 0` チェックのみが成功パス) と `skills/auto/SKILL.md` pr route item 8 (`if matches_expected: true, override to success; otherwise go to Step 6` という 2 値分岐のみ) は、どちらも「0 か 0 以外か」の 2 値でしか判断しておらず、exit code 2 (PENDING) を区別する分岐が存在しない。`detect-wrapper-anomaly.sh` にも PENDING 用パターンは未登録。結果として、PENDING は他の任意の失敗と同一の経路 (Tier 1 → Tier 2 → Tier 3) を通ってしまう。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` に review フェーズ限定の PENDING pre-check を追加 (bash 3.2+ compatible)
- `skills/auto/SKILL.md`: pr route item 8 を PENDING 分岐込みのテキストに変更
- `modules/orchestration-fallbacks.md`: 新規カタログエントリ `review-pending-not-failure` を追加
- `scripts/run-review.sh`: ヘッダコメントに exit code 契約 (0/2/その他) を追記 (bash 3.2+ compatible)
- `docs/tech.md`: Environment Variables 表に `WHOLEWORK_REVIEW_PENDING_RETRY_SEC` / `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` の 2 行を追加 [Steering Docs sync candidate]
- `docs/ja/tech.md`: 上記 2 行の日本語訳を追加 (`docs/translation-workflow.md` 準拠)
- `docs/workflow.md`: Orchestration セクションに "Review PENDING retry" の短い説明を追加 (`external-kill-parent-respawn` の "External kill respawn" 記述に準ずる) [Steering Docs sync candidate]
- `docs/ja/workflow.md`: 上記の日本語訳を追加 (`docs/translation-workflow.md` 準拠)
- `tests/run-auto-sub.bats`: review フェーズの PENDING retry を検証するテストを追加

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、`exit_code -eq 0` ブロックの `fi` (現行L760) の直後・`# Tier 1: reconciler` コメント (現行L762) の直前に、`phase == "review" && exit_code == 2` の場合のみ動作する PENDING pre-check ブロックを追加する。ブロックの内容: `${WHOLEWORK_REVIEW_PENDING_RETRY_SEC:-300}` 秒 sleep してから `run_with_retry_on_kill "$runner_script" "$issue" "$@" > "$log_file" 2>&1` を再実行するループを、`${WHOLEWORK_REVIEW_PENDING_MAX_RETRIES:-2}` 回を上限に回す。retry 後に `exit_code -eq 0` になれば `emit_event "phase_complete" "phase=${phase}"` して `return 0`。上限に達してもなお exit code 2 の場合は何もせず後続の Tier 1 reconciler 処理へ自然にフォールスルーさせる (以降の既存コードは変更しない)。(→ 受入条件 AC1, AC2)
2. `skills/auto/SKILL.md` pr route item 8 (現行: "If review fails: completion check ... otherwise go to Step 6") を次の内容に変更する: review が exit code 2 (PENDING) で終了した場合は `${WHOLEWORK_REVIEW_PENDING_RETRY_SEC:-300}` 秒 sleep して item 7 の `run-review.sh $PR_NUMBER $REVIEW_DEPTH` 呼び出しを再実行し、`${WHOLEWORK_REVIEW_PENDING_MAX_RETRIES:-2}` 回まで繰り返す。retry が成功 (exit 0) すれば item 7 と同様に継続。それ以外の exit code、または retry 上限到達後もなお exit code 2 の場合は、既存の completion check (`reconcile-phase-state.sh review --check-completion`) → Step 6 という経路に進む。`modules/orchestration-fallbacks.md#review-pending-not-failure` への参照を付記する。(→ 受入条件 AC1, AC2)
3. `modules/orchestration-fallbacks.md` に新規カタログエントリ `## review-pending-not-failure` を追加する。`external-kill-parent-respawn` と同じ Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale の構成を用いる。Symptom: 「`run-review.sh` が CI/preview 未確定で exit code 2 を返す」。Applicable Phases: 「review」。Fallback Steps: 手順1・2の sleep+retry。Escalation: 「retry 上限到達後は通常の Tier 1/2/3 に進む」。Rationale: #1115 / #1050 / #1066 を参照する。(→ 受入条件 AC1)
4. `scripts/run-review.sh` の冒頭コメント (現行L1-3付近) に exit code 契約を追記する: `0 = review completed (or overridden to success via Tier 1 reconcile)` / `2 = PENDING (CI/preview state not yet confirmed; caller should retry after a delay, not treat as failure)` / `other non-zero = review phase failed`。あわせて `docs/tech.md` の Environment Variables 表 (`WHOLEWORK_PREVIEW_TIMEOUT_SEC` 行の直後) に `WHOLEWORK_REVIEW_PENDING_RETRY_SEC` (default `300`) と `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` (default `2`) の行を追加し、`docs/workflow.md` の Orchestration セクション ("External kill respawn" 直後) に "Review PENDING retry" の短い説明を追加する。`docs/ja/tech.md` と `docs/ja/workflow.md` に日本語訳を同期する (`docs/translation-workflow.md` 準拠)。(→ 受入条件 AC3)
5. `tests/run-auto-sub.bats` に、review フェーズ限定の PENDING retry を検証するテストを追加する: (a) 1回目 exit 2、2回目 exit 0 → retry 後に成功する、(b) `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` 回すべて exit 2 → 既存の Tier 1 reconciler パスにフォールスルーする (既存の "phase exit nonzero + tier1 reconcile matches_expected=true" 系テストと同じ `$MOCK_DIR` モックパターンを使用)。テスト実行を高速化するため `WHOLEWORK_REVIEW_PENDING_RETRY_SEC=0` を各テストの setup で設定する。(→ 受入条件 AC1, AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "run-review.sh が exit code 2 (PENDING) で終了した場合に、呼び出し側 (skills/auto/SKILL.md または scripts/run-auto-sub.sh) が失敗と区別して扱い、3-Tier recovery に流さない経路が記載/実装されている" --> PENDING が失敗と区別されている
- <!-- verify: rubric "PENDING 時の再実行について、間隔と上限回数が規定されている (無限に即時再実行しない)" --> 再実行の間隔と上限が規定されている
- <!-- verify: rubric "run-review.sh の exit code の意味 (0 = 完了 / 2 = PENDING / その他 = 失敗) が、スクリプトのヘッダコメントまたは modules/phase-state.md に明記されている" --> 終了コードの意味が文書化されている

### Post-merge

- CI check-suite が作成されない PR、または preview が確定しない PR に対して `/auto` を実行し、review フェーズが 3-Tier recovery に入らず待機後の再実行として扱われることを確認する <!-- verify-type: opportunistic -->

## Notes

- 採用方針は Issue 本文の「案 A」(呼び出し側への直接的なハンドリング追加)。案 B (`reconcile-phase-state.sh` への第三の返り値追加) は影響範囲が広く、案 C (`detect-wrapper-anomaly.sh` へのパターン登録) は Tier 2 に吸収する形だが、案 A が本 Issue の症状を最短かつ最小の変更範囲で解消するため採用した。#1050 の Verify Retrospective (Improvement Proposals) も同じ 3 案を提示しており、判断はそれと整合する。
- リトライ間隔・上限のデフォルト値 (`WHOLEWORK_REVIEW_PENDING_RETRY_SEC=300`, `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES=2`) は、既存の `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` (300) や `scripts/retry-on-kill.sh` の bounded-retry パターンの規模感に合わせた。#1050 の review retrospective が「新規ポーリングループ追加時は既存実装のタイムアウト境界パターンを踏襲すべき」と指摘しており、これに従う形で `retry-on-kill.sh` の設計 (env var override 可能なデフォルト付き bounded loop) を踏襲した。
- PENDING pre-check は `skills/auto/SKILL.md` の pr route item 8 (Step 4 内、review フェーズ専用の分岐) に配置し、Step 6 (3-Tier Recovery、全フェーズ共通) には配置しない。Step 6 は code/review/merge/verify 共通の汎用セクションであり、review 固有の分岐を持ち込むと既存の phase-generic な構成を崩すため。同様に `run_phase_with_recovery()` は code/review/merge の 3 フェーズで共有される汎用関数だが、exit code 2 (PENDING) は `run-review.sh` にのみ存在する契約であるため、pre-check は `phase == "review"` に明示的に限定する。他の `run-*.sh` (`run-code.sh`, `run-merge.sh`, `run-spec.sh`, `run-issue.sh`) が exit code 2 を使用していないことは grep で確認済み。
- retry 成功時に Tier 1/2/3 と同様の `emit_event "recovery" ... "tier=N"` を追加することも検討したが、`get-auto-session-report.sh` の集計が `tier == "1"/"2"/"3"` に固定されており、新しい tier 値を追加するには集計スクリプト側の変更も必要になる。3 件の受入条件のいずれにも要求されていないため、本 Issue のスコープ外として意図的に見送った (observability 拡張は別 Issue の対象)。
- `scripts/detect-wrapper-anomaly.sh` への新規パターン登録は行わない。exit code 2 は既に一意で曖昧さのないシグナルであり (external-kill pre-check のように exit code 137/143/unknown を log/event と突き合わせて判別する必要がある曖昧なケースとは異なる)、専用の検出スクリプトを追加する理由がない。
- bats テスト入力形式: `tests/run-auto-sub.bats` の新規テストは、既存の `$MOCK_DIR/run-review.sh` モックパターン (`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"`) を踏襲する。retry の 1 回目と 2 回目で異なる exit code を返す必要があるため、モックスクリプト内でカウンタファイル (例: `$MOCK_DIR/review-call-count`) をインクリメントし、呼び出し回数に応じて exit code を切り替える形にする。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜5 をすべて Spec 記載どおりの箇所・構成で実装した。`run_phase_with_recovery()` への挿入位置 (現行L760 `fi` 直後・L762 `# Tier 1: reconciler` 直前) は実装時点でも一致していた

### Design Gaps/Ambiguities
- N/A — 実装中に Spec の記述で解釈に迷う箇所はなかった

### Rework
- N/A — 初回実装で bats テスト (新規2件・既存77件) と `bats tests/` フルスイート (1293件) が一発 PASS した。手戻りは発生していない

### Minor Implementation Note
- bats テストのカウンタファイルパスは Spec の例示 (`$MOCK_DIR/review-call-count`) ではなく `$BATS_TEST_TMPDIR/review-call-count` を使用した。Spec の記述が「例:」であり拘束的でないため、テスト間の独立性がより明確な `BATS_TEST_TMPDIR` を選んだ (`MOCK_DIR` は teardown で `rm -rf` される一時ディレクトリであり、カウンタ専用の状態を置く意味的な適切さの観点で `BATS_TEST_TMPDIR` を優先)

## review retrospective

### Spec vs. implementation divergence patterns

- なし。Spec の Implementation Steps 1〜5 と実装 (`scripts/run-auto-sub.sh`, `skills/auto/SKILL.md`, `scripts/run-review.sh`, `modules/orchestration-fallbacks.md`, `docs/tech.md` 系) は構造・挿入位置とも一致していた。

### Recurring issues

- review-light が検出した 3 件の指摘 (SHOULD 1 / CONSIDER 2) はすべて同一の根本原因に起因していた: 新設した PENDING retry 成功パス (`scripts/run-auto-sub.sh` L780-784) が、既存の初回成功パス (L751-759) が持つ副作用 (anomaly 検出・`_RETRY_ON_KILL_FIRED` 記録・ログ保持) の一部を引き継いでいなかった。「既存の成功パスと並行する新しい成功パスを追加する際、既存パスの副作用を意図的に洗い出して引き継ぐか判断する」というチェック観点は、今回のように単一 PR 内でも複数件検出されるパターンであり、review-bug/review-spec の汎用チェックリストに追加する価値がありそうだが、本 review フェーズでは Issue 起票は行わず本記録に留める (Issue 起票は `/verify` で集約)。

### Acceptance criteria verification difficulty

- なし。3件の rubric AC はいずれも文言が明確で、PR diff を読むだけで PASS/FAIL を機械的に判定できた。UNCERTAIN は発生していない。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #1116 は squash merge (`gh pr merge --squash --delete-branch`) で main にマージ。mergeable=true (CI success / review approved) だったため conflict 解消手順・worktree は不要だった
- pre-merge AC gate: 3件の rubric AC すべて `[x]` 済みを再確認 (`check-pre-merge-ac.sh` で `unchecked_count: 0`) してからマージを実行した

### Deferred Items
- Post-merge AC (CI check-suite 未作成 / preview 未確定の PR での `/auto` 実行確認, verify-type: opportunistic) は未検証のまま — `/verify` または実運用での偶発的発生を待つ
- CONSIDER 2件 (`_RETRY_ON_KILL_FIRED` の PENDING retry 非対応、`$log_file` の PENDING retry 間上書き) は本 Issue スコープ外として見送り継続。将来 observability 要求が高まった場合に別 Issue で対応を検討

### Notes for Next Phase
- `/verify` は Post-merge AC (opportunistic) が UNCERTAIN/PENDING のまま残る想定で処理すること
- base branch は `main` のため `closes #1115` で Issue は自動クローズされる見込み

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background の主張 (「exit code 2 を他の非 0 と区別する分岐が存在しない」) を `run-review.sh` / `run-auto-sub.sh` / `skills/auto/SKILL.md` の実コードと照合して確認しており、事実確認のステップが機能した。
- 案 A/B/C の選択を `/issue` (What) ではなく `/spec` (How) の責務として意図的に未確定のまま残す判断も、`docs/product.md` の責務境界に沿っている。
- **一方でラベル遷移が実行されなかった** (下記 Improvement Proposals)。

#### spec / code
- 実装は「exit 2 なら待機して再実行、それ以外の非 0 または再試行上限到達後にのみ completion check → 3-Tier recovery」という順序を採っており、意図的な PENDING が recovery に流れない。再試行の間隔・上限を環境変数 (`WHOLEWORK_REVIEW_PENDING_RETRY_SEC` 既定 300s / `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` 既定 2) で外出しした点も、CI の所要時間がプロジェクトごとに異なることへの対応として妥当。
- exit code contract を `run-review.sh` のヘッダに書き、`orchestration-fallbacks.md#review-pending-not-failure` から参照する二段構えにしたことで、スクリプト単体を読む人と catalog を辿る人の両方に届く形になっている。

#### review
- `--light` で実施。修正コミット 2 件が追加され silent no-op なし (comments 0→1、reviews 0→1、`matches_expected: true`)。

#### merge
- CI 7 SUCCESS / 2 実行中の状態から `run-merge.sh` が完了まで待機して squash merge。conflict なし。

#### verify
- pre-merge 3 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。

### Improvement Proposals

- **`/issue` フェーズが実作業完了・exit 0 のままラベル遷移せず終了することがあり、issue / spec フェーズには機械的な completion check が存在しない**: 本 Issue の `/issue` 実行 (`run-issue.sh 1115`) は exit 0 で終了し、出力上も Step 1〜14 の実作業 (Background の主張とコードの照合、曖昧性検出、AC 分類、blocked-by チェック、opportunistic verification) を完了したと報告していた。しかし直後にラベルを確認すると `triaged retro/verify` のままで、**`phase/issue` が付与されていなかった**。
  - **対比**: 同一 batch 内の #1054 / #1053 の `/issue` 実行では「ラベル遷移: `phase/issue` 付与」が出力に明示されていた。本実行の出力にはラベル遷移に関する記述自体が存在しない。
  - **なぜ検出しにくいか**: `scripts/reconcile-phase-state.sh` がサポートする phase は `code-pr` / `code-patch` / `review` / `merge` / `verify` であり、**issue と spec のフェーズには completion check が無い**。`/auto` Step 3 も「ラベルを読んで分岐する」だけで、`run-issue.sh` の実行後にラベルが期待どおり遷移したかを検証するステップを持たない。今回はラベルを直接確認していたため気づけたが、`run-auto-sub.sh` 経由なら「`phase/ready` も `phase/issue` も無い」状態のまま spec dispatch 条件 (`phase/ready` が無い) を満たして spec が走り、症状が別の形に化けていた可能性がある。
  - **本 Issue との関係**: 皮肉なことに、本 Issue 自身が「wrapper が silent no-op で完了扱いされるのを防ぐ」ための Issue である。#1050 が `/review` について塞いだのと同型の穴が、`/issue` フェーズには残っている。
  - **対応方針 (案)**: (a) `reconcile-phase-state.sh` に `issue` / `spec` フェーズの completion check を追加する (期待ラベル: issue → `phase/issue` または `phase/ready`、spec → `phase/ready`)。`/auto` Step 3 の各 `run-*.sh` 呼び出し後に completion check を挟む。(b) `run-issue.sh` / `run-spec.sh` の wrapper 側で、終了前にラベル遷移が行われたかを確認し、未遷移なら非 0 で終了する。(c) `/issue` SKILL.md のラベル遷移ステップを、他ステップの成否によらず必ず実行される位置に移す。
  - (a) は既存の Observe → Diagnose → Act パターンに揃うため一貫性が高く、(b) は wrapper 単体で完結するため `/auto` を経由しない手動実行でも効く。両者は排他ではない。

### 観察

- 本 Issue の merge により preview / CI 待機の防御が 4 層揃った (#1066 上流 / #1050 中間 / #1115 接続 / #1053 下流)。
- フェーズ分割方式での完走はこれで 7/7 (kill ゼロ)。連結実行 (`run-auto-sub.sh`) を用いた #1066 のみ kill 3 回という対比が維持されている。
