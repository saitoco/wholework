# Issue #693: run-*.sh: 単一 Issue /auto でも phase_start/phase_complete event を emit して rollup を機能させる

## Overview

`run-code.sh` / `run-review.sh` / `run-merge.sh` で `phase_start` / `phase_complete` event を emit するように修正する。現状は `run-auto-sub.sh` 経由 (--batch / XL サブ Issue) でのみ emit されるため、単一 Issue `/auto` では `auto-events-rollup.sh` のセッション集計が常に空になる。

各スクリプトの冒頭に EMIT ガードブロック (EMIT_PHASE_NAME が未設定の場合のみ EMIT_ISSUE_NUMBER / EMIT_PHASE_NAME を設定して `phase_start` を emit) を追加し、正常終了時に `phase_complete` を明示 emit する。`run-auto-sub.sh` 経由の呼び出しでは `EMIT_PHASE_NAME` が事前に export されるため二重 emit は発生しない。

## Reproduction Steps

1. 単一 Issue M サイズ (`/auto N`) を実行する (run-auto-sub.sh を経由しないパス)
2. 実行後に `auto-events-rollup.sh` でロールアップを生成する
3. セッション表 / Phase Distribution / Recovery Tier 集計がすべて空になる (`phase_start` / `phase_complete` event が 0 件)

## Root Cause

`run-code.sh` / `run-review.sh` / `run-merge.sh` は `#672` で `_maybe_emit_phase_complete` backfill trap が追加されたが、次の欠陥により機能しない:

1. `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` が未設定のため `emit_event` の `issue` フィールドが 0 になる (backfill 関数内の `[[ -z "${EMIT_PHASE_NAME:-}" ]] && return 0` が早期 return)
2. `emit_event "phase_start"` が存在しないため backfill 条件 `_last_event == "phase_start"` が満たされない
3. `run-merge.sh` は `emit_event "test_result"` 後に EXIT するため、仮に上記が解決しても backfill 条件が不成立

`run-auto-sub.sh` の `run_phase_with_recovery` 関数では `export EMIT_ISSUE_NUMBER` / `export EMIT_PHASE_NAME` の設定と `emit_event "phase_start"` / `emit_event "phase_complete"` の明示 emit が実装されており、--batch / XL サブ Issue 経由では正常に動作する。

## Changed Files

- `scripts/run-code.sh`: AUTO_SESSION_ID 初期化、EMIT ガードブロック追加、phase_complete 明示 emit 追加 — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上 — bash 3.2+ compatible
- `scripts/run-merge.sh`: 同上 — bash 3.2+ compatible
- `tests/run-code.bats`: phase_start / phase_complete emit の新規テスト追加
- `tests/run-review.bats`: 同上
- `tests/run-merge.bats`: 同上

## Implementation Steps

1. `scripts/run-code.sh` を修正する (→ AC 1-4, rubric 部分)

   a. `export AUTO_EVENTS_LOG` の直後に AUTO_SESSION_ID 初期化を追加する:
   ```bash
   AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat .tmp/auto-session-current 2>/dev/null || echo '')}"
   export AUTO_SESSION_ID
   ```

   b. `trap '_maybe_emit_phase_complete' EXIT` の直後に EMIT ガードブロックを追加する (EMIT_PHASE_NAME が未設定の場合のみ実行):
   ```bash
   if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
     export EMIT_ISSUE_NUMBER="$ISSUE_NUMBER"
     if [[ "$ROUTE_FLAG" == "--pr" ]]; then
       export EMIT_PHASE_NAME="code-pr"
     elif [[ "$ROUTE_FLAG" == "--patch" ]]; then
       export EMIT_PHASE_NAME="code-patch"
     else
       export EMIT_PHASE_NAME="code"
     fi
     emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
   fi
   ```

   c. `echo "---"` (最終フッタの前) の直前に成功時の phase_complete emit を追加する:
   ```bash
   if [[ $EXIT_CODE -eq 0 ]]; then
     emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
   fi
   ```

2. `scripts/run-review.sh` を修正する (→ AC 5-8, rubric 部分)

   a. `export AUTO_EVENTS_LOG` の直後に AUTO_SESSION_ID 初期化を追加 (run-code.sh と同形)

   b. `trap '_maybe_emit_phase_complete' EXIT` の直後に EMIT ガードブロックを追加する:
   ```bash
   if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
     export EMIT_ISSUE_NUMBER="$PR_NUMBER"
     export EMIT_PHASE_NAME="review"
     emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
   fi
   ```
   (run-review.sh は PR 番号を引数に取るため EMIT_ISSUE_NUMBER=$PR_NUMBER とする — run-auto-sub.sh の命名規約と一致)

   c. `echo "---"` の直前に成功時の phase_complete emit を追加 (run-code.sh と同形)

3. `scripts/run-merge.sh` を修正する (→ AC 9-12, rubric 部分)

   a. `export AUTO_EVENTS_LOG` の直後に AUTO_SESSION_ID 初期化を追加 (同形)

   b. `trap '_maybe_emit_phase_complete' EXIT` の直後に EMIT ガードブロックを追加する:
   ```bash
   if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
     export EMIT_ISSUE_NUMBER="$PR_NUMBER"
     export EMIT_PHASE_NAME="merge"
     emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
   fi
   ```

   c. CI test_result emit ブロック (`if [[ $EXIT_CODE -eq 0 && -n "${AUTO_EVENTS_LOG:-}" ]]; then ... fi`) の直後に phase_complete emit を追加する:
   ```bash
   if [[ $EXIT_CODE -eq 0 ]]; then
     emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
   fi
   ```
   (`run-merge.sh` は `test_result` emit 後に exit するため、backfill 条件 `_last_event == "phase_start"` が不成立になる。そのため明示 emit が必須)

4. `tests/run-code.bats` / `tests/run-review.bats` / `tests/run-merge.bats` に新規 bats テストを追加する (after 1-3) (→ AC 15)

   各ファイルに以下の 3 テストを追加する (emit-event.sh の mock をログ記録形式に上書きして検証):
   - `emit: phase_start emitted when EMIT_PHASE_NAME is not set` — EMIT_PHASE_NAME 未設定時に `phase_start` が emit されることを確認
   - `emit: phase_start not emitted when EMIT_PHASE_NAME is pre-set (no double emit)` — `export EMIT_PHASE_NAME=...` 済みの場合に `phase_start` が emit されないことを確認
   - `emit: phase_complete emitted on success` — 正常終了時に `phase_complete` が emit されることを確認

## Verification

### Pre-merge

- <!-- verify: grep "emit_event.*phase_start" "scripts/run-code.sh" --> `scripts/run-code.sh` に `emit_event "phase_start"` 呼び出しが追加されている
- <!-- verify: grep "emit_event.*phase_complete" "scripts/run-code.sh" --> `scripts/run-code.sh` に `emit_event "phase_complete"` 呼び出しが追加されている
- <!-- verify: grep "EMIT_ISSUE_NUMBER=" "scripts/run-code.sh" --> `scripts/run-code.sh` に `EMIT_ISSUE_NUMBER` の設定が追加されている
- <!-- verify: grep "EMIT_PHASE_NAME=" "scripts/run-code.sh" --> `scripts/run-code.sh` に `EMIT_PHASE_NAME` の設定が追加されている
- <!-- verify: grep "emit_event.*phase_start" "scripts/run-review.sh" --> `scripts/run-review.sh` に `emit_event "phase_start"` 呼び出しが追加されている
- <!-- verify: grep "emit_event.*phase_complete" "scripts/run-review.sh" --> `scripts/run-review.sh` に `emit_event "phase_complete"` 呼び出しが追加されている
- <!-- verify: grep "EMIT_ISSUE_NUMBER=" "scripts/run-review.sh" --> `scripts/run-review.sh` に `EMIT_ISSUE_NUMBER` の設定が追加されている
- <!-- verify: grep "EMIT_PHASE_NAME=" "scripts/run-review.sh" --> `scripts/run-review.sh` に `EMIT_PHASE_NAME` の設定が追加されている
- <!-- verify: grep "emit_event.*phase_start" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に `emit_event "phase_start"` 呼び出しが追加されている
- <!-- verify: grep "emit_event.*phase_complete" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に `emit_event "phase_complete"` 呼び出しが追加されている
- <!-- verify: grep "EMIT_ISSUE_NUMBER=" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に `EMIT_ISSUE_NUMBER` の設定が追加されている
- <!-- verify: grep "EMIT_PHASE_NAME=" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に `EMIT_PHASE_NAME` の設定が追加されている
- <!-- verify: rubric "scripts/run-code.sh / run-review.sh / run-merge.sh の 3 つすべてが: (1) EMIT_PHASE_NAME が未設定の場合のみ EMIT_ISSUE_NUMBER / EMIT_PHASE_NAME を設定して phase_start を emit (run-auto-sub.sh 経由時の二重 emit を回避), (2) 正常終了時に phase_complete を明示 emit, (3) phase 名が run-auto-sub.sh と一致 (code-pr/code-patch/review/merge)" --> rubric 基準を満たす
- <!-- verify: section_contains "scripts/run-code.sh" "_maybe_emit_phase_complete" "EMIT_PHASE_NAME" --> backfill 関数が EMIT_PHASE_NAME ガードを保持している
- <!-- verify: command "bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats" --> 既存 bats テストが green

### Post-merge

- 次回 単一 Issue pr-route `/auto` 完走後の rollup で Sessions テーブルが空でなく phase_start/phase_complete 経由のセッションが集計されることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- `EMIT_ISSUE_NUMBER` に設定する値: `run-code.sh` は issue 番号 (`$ISSUE_NUMBER`)、`run-review.sh` / `run-merge.sh` は PR 番号 (`$PR_NUMBER`) — `run-auto-sub.sh` の `run_phase_with_recovery` 呼び出し規約と一致 (review/merge フェーズでは `$PR_NUMBER` が `issue` フィールドに使われる)
- ガード条件 `[[ -z "${EMIT_PHASE_NAME:-}" ]]` の根拠: `run-auto-sub.sh` は `export EMIT_PHASE_NAME="$phase"` 後にランナースクリプトを呼び出すため、この値が子プロセスに引き継がれる
- `run-merge.sh` の phase_complete 明示 emit 必要性: test_result emit 後に exit するため、backfill trap が `_last_event == "phase_start"` をチェックする時点で last_event は `test_result` になり backfill 条件が不成立
- Spec 簡易性ルール (light: 各 5 以内) について: 実装ステップは 4 ステップで規定内。Pre-merge 検証項目は Issue body の AC 定義に従い 15 項目となる (Issue body AC からの verbatim sync 優先)

## Code Retrospective

### Deviations from Design

- None

### Design Gaps/Ambiguities

- `AUTO_SESSION_ID` 初期化の配置: Spec では `export AUTO_EVENTS_LOG` の直後に追加と明記されていたが、実際は `source emit-event.sh` の前 (同じ直後の位置) に挿入した — 同じ行ブロックなので実質同じ配置
- `run-code.sh` の `else` ブランチ (フラグなしの場合 `EMIT_PHASE_NAME="code"`) は run-auto-sub.sh の命名規約に直接対応する phase 名がないが、直接呼び出しケースのフォールバックとして問題なし

### Rework

- None

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `phase_complete` に `_EMIT_PHASE_OWNED` センチネルガードが必要だった点が Spec に明記されていなかった。Spec は phase_start のガード (`EMIT_PHASE_NAME` 未設定チェック) を説明しているが、phase_complete が同じガードを必要とするという対称性の記述が欠如していた。実装時に非対称な状態で実装されたためレビューで発見された。

### Recurring Issues

- 二重 emit ガードのパターン (フラグ/センチネルで emit を制御) が 3 スクリプト共通で必要だったが、Spec ではスクリプトごとに独立した説明になっており横断的な一貫性要件が明示されていなかった。今後同類のパターンは Spec に "全スクリプト共通で対称的に適用する" 旨を明記すると実装漏れが防げる。

### Acceptance Criteria Verification Difficulty

- AC 15 件すべて PASS、UNCERTAIN なし。bats テストは CI 参照 (Run bats tests SUCCESS) で代替検証した。`command` verify コマンドは safe mode で UNCERTAIN になるが CI 参照フォールバックが有効に機能した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #697 を squash merge で main にマージ。CI PASS、review approved の状態で実施
- BASE_BRANCH = main のため `closes #693` が自動で Issue をクローズする
- Phase Handoff を Spec に記録し main に push

### Deferred Items
- post-merge observation: 単一 Issue /auto 完走後の rollup Sessions テーブルが空でないことを確認 (Post-merge verification)
- `token_usage` event の run-*.sh への追加は別 Issue (#662)

### Notes for Next Phase
- verify フェーズでは post-merge verification (観察確認) が主タスク
- Pre-merge verify コマンドは PR マージ済みのため全 PASS 済み
- `/auto` 単一 Issue 実行後に `auto-events-rollup.sh` で Sessions テーブルを確認すること

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 単一 emit と二重 emit ガードの対称性 (phase_start 側のガードと phase_complete 側のガード) を明示する記述が薄かった。review 段階で symmetry gap が露見し補正されたが、Spec 段階で「3 スクリプト横断で対称的に適用する」と明示しておくと初版実装で漏れを防げる

#### code
- design からの逸脱なし。実装は 4 ステップ計画通りに完了
- bash 3.2+ 互換 (export 構文、`[[ -z ... ]]` ガード) を維持

#### review
- review 段階で phase_complete のセンチネルガード `_EMIT_PHASE_OWNED` が必要だと検出され、Spec の symmetry 記述の弱さを補正。/review の semantic 検出機能が機能した好例

#### merge
- squash merge / CI PASS / closes #693 で Issue 自動クローズ済み

#### verify
- Pre-merge AC 15 件すべて grep / rubric / command で PASS。command 系は CI fallback でなく `bats` 直接実行で 74 tests green を確認
- Post-merge AC #16 (observation event=auto-run) は SKIPPED として記録。`/auto` 完走後の `observation-trigger.sh --event auto-run` 起動時に rollup Sessions テーブルが空でないことが自動評価される

### Improvement Proposals
- N/A (review retrospective に記録済みの spec symmetry gap は本 Issue 内で補正済み。横展開可能な一般化改善は未確定のため起票なし)
