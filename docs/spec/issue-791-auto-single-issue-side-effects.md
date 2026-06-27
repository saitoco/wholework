# Issue #791: auto: bash side effects coverage for parent /auto single Issue path

## Overview

`/auto N` の parent session 単一 Issue path (M/L pr route) では `run-code.sh`、`run-review.sh`、`run-merge.sh` を直接呼ぶため、bash 駆動 side effect (`_emit_comments_consumed`、`append-loop-state-heartbeat.sh`) が発火しない。batch/XL mode は `run-auto-sub.sh` の `run_phase_with_recovery()` 経由で確実に発火する。

## Reproduction Steps

1. Size M/L の Issue で `/auto N` を single Issue parent session として実行する
2. `.tmp/auto-events.jsonl` を確認: `comments_consumed` event が記録されない
3. `docs/sessions/_daily/loop-state-{date}.md` を確認: code/review/merge の heartbeat 行が追記されない
4. batch mode (`run-auto-sub.sh` 経由) と挙動が異なる

## Root Cause

| Path | Side effects 発火元 |
|------|-------------------|
| batch/XL | `run-auto-sub.sh` `run_phase_with_recovery()` — bash で確実発火 |
| parent single Issue pr route | `skills/auto/SKILL.md` Step 4 prose ステップ — LLM が実行、スキップ多発 |

`_emit_comments_consumed()` は `run-auto-sub.sh` にローカル定義され、`run-code.sh`/`run-review.sh`/`run-merge.sh` は側面効果呼び出しを一切持たない。

## Changed Files

- `scripts/emit-event.sh`: `_emit_comments_consumed()` を追加 (run-auto-sub.sh から抽出、bash 3.2+ compatible)
- `scripts/run-auto-sub.sh`: ローカル定義の `_emit_comments_consumed()` を削除 (emit-event.sh から取得)
- `scripts/run-code.sh`: `_emit_comments_consumed` 呼び出し (claude 実行前) + heartbeat 呼び出し (成功時) を追加 — bash 3.2+ compatible
- `scripts/run-review.sh`: heartbeat 呼び出し (成功時) を追加 — bash 3.2+ compatible
- `scripts/run-merge.sh`: heartbeat 呼び出し (成功時) を追加 — bash 3.2+ compatible
- `tests/run-auto-sub.bats`: `emit-event.sh` mock に `_emit_comments_consumed() { :; }` を追加
- `tests/auto-sub-observability.bats`: 同上
- `tests/run-code.bats`: `_emit_comments_consumed` および heartbeat 発火を検証する新規テスト追加
- `tests/run-review.bats`: heartbeat 発火を検証する新規テスト追加
- `tests/run-merge.bats`: heartbeat 発火を検証する新規テスト追加

## Implementation Steps

1. **emit-event.sh に `_emit_comments_consumed()` を追加** (→ AC1, AC2)

   `scripts/run-auto-sub.sh` の `_emit_comments_consumed()` 実装をそのまま移植。`emit_event()` の直後（ファイル末尾）に追記。関数は `AUTO_EVENTS_LOG` と `AUTO_SESSION_ID` が未設定の場合に即 return するガードを持つ。

2. **run-auto-sub.sh の重複定義を削除** (→ AC1)

   `scripts/run-auto-sub.sh` の `_emit_comments_consumed()` 関数定義ブロックを削除。`source "$SCRIPT_DIR/emit-event.sh"` の後に定義されるため、emit-event.sh の実装が自動的に使われる。

3. **run-code.sh に side effects を追加** (→ AC1)

   `source "$SCRIPT_DIR/emit-event.sh"` の後 (関数定義済みの位置) に:
   - claude 実行直前 (`echo "=== run-code.sh: Starting /code..."` の後): `_emit_comments_consumed "$ISSUE_NUMBER" "code" || true`
   - 成功パス (`emit_event "phase_complete"` の直前): `"$SCRIPT_DIR/append-loop-state-heartbeat.sh" --issue "$ISSUE_NUMBER" --from spec --to code >/dev/null 2>&1 || true`

4. **run-review.sh と run-merge.sh に heartbeat を追加** (→ AC1)

   - `run-review.sh`: 成功パス (`emit_event "phase_complete"` の直前) に `"$SCRIPT_DIR/append-loop-state-heartbeat.sh" --issue "$PR_NUMBER" --from code --to review >/dev/null 2>&1 || true`
   - `run-merge.sh`: 成功パス (`emit_event "phase_complete"` の直前) に `"$SCRIPT_DIR/append-loop-state-heartbeat.sh" --issue "$PR_NUMBER" --from review --to merge >/dev/null 2>&1 || true`

5. **テスト更新と新規テスト追加** (→ AC3, AC4)

   - `tests/run-auto-sub.bats` および `tests/auto-sub-observability.bats` の `emit-event.sh` mock に `_emit_comments_consumed() { :; }` を追加 (関数が未定義だと source 後に呼び出しが失敗する)
   - `tests/run-code.bats` に新規テスト: `_emit_comments_consumed` が claude 呼び出し前に発火すること、heartbeat が成功時に発火することを `append-loop-state-heartbeat.sh` mock のログで検証
   - `tests/run-review.bats` に新規テスト: heartbeat が成功時に発火すること
   - `tests/run-merge.bats` に新規テスト: heartbeat が成功時に発火すること

## Verification

### Pre-merge

- <!-- verify: rubric "提案 A/B/C のいずれかを採用した実装が scripts/run-auto-sub.sh または各 scripts/run-*.sh または skills/auto/SKILL.md に反映されており、parent /auto 単一 Issue path でも bash 駆動 side effect が確実に発火する仕様になっている" --> 単一 Issue path での bash emit カバーが実装されている
- <!-- verify: rubric "実装内容 (採用した候補 A/B/C と理由) が docs/spec/issue-791-auto-single-issue-side-effects.md に記録され、tradeoff 比較が残されている" --> 設計判断が Spec に記録されている
- <!-- verify: command "bats tests/run-auto-sub.bats tests/auto.bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats" --> 関連 bats テストが green
- <!-- verify: rubric "tests/run-code.bats または tests/run-review.bats または tests/run-merge.bats に parent 単一 Issue path での side effect 発火 (comments_consumed または loop-state heartbeat) を検証する新規テストが 1 件以上追加されている" --> 修正をカバーする新規 bats テストが追加されている

### Post-merge

- 次回 単一 Issue `/auto N` (M/L pr route) 実行時に、`auto-events.jsonl` に `comments_consumed` event が記録され、かつ `docs/sessions/_daily/loop-state-{date}.md` に当該 Issue の heartbeat 行が追記されることを観察

## Alternatives Considered

| 候補 | 概要 | 採用理由 |
|------|------|---------|
| **A (採用)** | 各 `run-*.sh` に bash side effects を直接埋め込み。`_emit_comments_consumed` を `emit-event.sh` に移動して DRY 緩和 | 最小変更・影響範囲小・bash 保証・#701/#705 の既存パターン再利用 |
| B | parent /auto を `run-auto-sub.sh` 経由に統一 | verify phase が `Skill()` 呼び出しのため `run-auto-sub.sh` に入らない。pr route verify orchestration の再設計が必要で影響範囲大 |
| C | SKILL.md prose ステップを bash 呼び出しに書き換え | #701 iteration 2 で同様の試みを行ったが、parent session でも 5 回連続スキップを観測。LLM 遵守度への依存は根本解決にならない |

**DRY 対策:** `_emit_comments_consumed` を `emit-event.sh` に移動することで全 `run-*.sh` が source 後に使用可能になり、新規 side effect 追加時の更新コストを最小化する。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — AC プレースホルダー修正・新規 bats テスト AC 追加の自動解決
- saito (MEMBER, first-class): AC11 verification (#705) + 設計入力
  - 候補 B の verify orchestration 制約 (parent-driven Skill() は run-auto-sub.sh 非対応) を明示するよう要請
  - 候補 A の DRY 緩和 helper sourceable 設計を提案
  - 既存 `_emit_comments_consumed()` / `append-loop-state-heartbeat.sh` 再利用前提

## Notes

- **候補 A の DRY 違反**: `_emit_comments_consumed` は run-code.sh のみで呼ばれる。emit-event.sh への移動により run-review.sh/run-merge.sh は使わないが source コストは無視できる。新規 side effect 追加時は emit-event.sh 1 箇所の追加で済む
- **heartbeat issue 番号**: `run-review.sh`/`run-merge.sh` は PR 番号しか持たないため `--issue $PR_NUMBER` で heartbeat を記録する。これは batch mode (run-auto-sub.sh) の既存挙動と一致する
- **`docs/structure.md` の emit-event.sh 説明**: `_emit_comments_consumed()` 追加後は "providing `emit_event()` for structured JSONL event emission" の説明が不完全になるが、doc-checker の impact criteria では script 機能説明変更は SHOULD レベル (軽微) のため本 PR では更新を見送る
- **verify command AC3 更新**: Issue body AC3 の `bats tests/run-auto-sub.bats tests/auto.bats` を新規テストファイル含む形 `bats tests/run-auto-sub.bats tests/auto.bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats` に更新する
