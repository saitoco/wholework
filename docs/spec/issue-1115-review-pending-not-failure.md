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
