# Issue #799: recoveries: code-pr-tier3-recovery の再発原因を特定・解消

## Overview

`docs/reports/orchestration-recoveries.md` に記録された `code-pr-tier3-recovery` の 5 件を 2 つの原因グループに分類し、それぞれの根本原因に対する緩和策を実装する。

- **Cause Group 1 — Active-implementation watchdog kill** (3 件: #729, #770, #769): JSON mode で `/code` が実装中に watchdog (1800s) に kill される。サイレント期間リセットが機能しないため。
- **Cause Group 2 — Clean-slate transient hang** (2 件: #675, #775): `/code` 起動直後に API ストールで no-output のまま watchdog kill される。`json-mode-silent-hang` パターンが Tier 2 に到達せず Tier 3 サブエージェントを不必要に起動していた。

## Changed Files

- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_CODE_DEFAULT` を 1800 → 3600 に変更 — bash 3.2+ compatible
- `scripts/apply-fallback.sh`: `json-mode-silent-hang` Tier 2 ハンドラを追加 (`code-pr` フェーズ限定、`still waiting (json mode)` 検出 → `run-code.sh --pr` リトライ) — bash 3.2+ compatible
- `docs/reports/orchestration-recoveries.md`: 5 件の `code-pr-tier3-recovery` エントリの Improvement Candidate を `未起票` → `起票済み #799` に更新
- `tests/watchdog-defaults.bats`: code フェーズデフォルト 3600 テストを追加
- `tests/apply-fallback.bats`: `json-mode-silent-hang` パターンのテストを追加

## Implementation Steps

1. `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_CODE_DEFAULT=1800` を `WATCHDOG_TIMEOUT_CODE_DEFAULT=3600` に変更 (→ 受入条件 A)

2. `scripts/apply-fallback.sh` に `json-mode-silent-hang` Tier 2 ハンドラを追加 (→ 受入条件 A)
   - `detect_symptom_anchor()` に以下を追加 (`code-patch-silent-no-op` 検出ブロックの後):
     ```bash
     # See modules/orchestration-fallbacks.md#json-mode-silent-hang
     if [[ "$PHASE" == "code-pr" ]] && grep -q "still waiting (json mode)" "$log" 2>/dev/null; then
       echo "json-mode-silent-hang"
       return 0
     fi
     ```
   - `apply_json_mode_silent_hang_retry()` 関数を追加:
     ```bash
     apply_json_mode_silent_hang_retry() {
       echo "[apply-fallback] json-mode-silent-hang: retrying run-code.sh --pr for issue $ISSUE" >&2
       "$SCRIPT_DIR/run-code.sh" "$ISSUE" --pr >> "$LOG_FILE" 2>&1
       echo "[apply-fallback] json-mode-silent-hang: done" >&2
     }
     ```
   - `case` 文に `json-mode-silent-hang)` ブランチを追加:
     ```bash
     json-mode-silent-hang)
       apply_json_mode_silent_hang_retry
       printf '%s\n' \
         "### Orchestration Anomalies" \
         "- **[json-mode-silent-hang]** Tier 2 fallback applied: phase=\`$PHASE\`, action=run-code.sh-pr-retry, result=recovered." \
         "" \
         "### Improvement Proposals" \
         "- N/A (resolved by Tier 2 fallback catalog)"
       ;;
     ```

3. `docs/reports/orchestration-recoveries.md` 内の `code-pr-tier3-recovery` エントリ 5 件 (2026-06-27 18:15 / 16:54 / 15:39、2026-06-20 20:45、2026-06-15 18:20) の Improvement Candidate フィールドを `未起票` → `起票済み #799` に変更 (→ 受入条件 B)

4. テストを追加 (→ 受入条件 A 品質担保)
   - `tests/watchdog-defaults.bats`: code フェーズデフォルトが 3600 であることを検証するテストを追加
     ```
     @test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_CODE_DEFAULT when phase is code" {
       # get-config-value.sh が空を返す場合、phase-specific default 3600 が使われる
       ...
       [ "$output" = "3600" ]
     }
     ```
   - `tests/apply-fallback.bats`: `json-mode-silent-hang` パターンが `code-pr` フェーズで検出されリトライされることを検証するテストを追加 (existing `code-patch-silent-no-op` テストと同様のパターンで)

## Verification

### Pre-merge

- <!-- verify: rubric "each cause group listed in this Issue has an identified root cause and either a concrete mitigation implemented in this PR or a follow-up Issue filed" --> 各 cause group に根本原因の特定と緩和策の実装
- <!-- verify: file_contains "docs/reports/orchestration-recoveries.md" "起票済み #799" --> recoveries.md の code-pr-tier3-recovery エントリに 起票済み #799 が記載される

### Post-merge

- `docs/reports/orchestration-recoveries.md` に、この Issue の fix が merge された後に追記された `code-pr-tier3-recovery` エントリで Improvement Candidate が `未起票` のものは存在しない

## Notes

- `WATCHDOG_TIMEOUT_CODE_DEFAULT=1800` は global default (`WATCHDOG_TIMEOUT_DEFAULT=2700`) より低く、code フェーズが最も短い timeout 設定になっていた。JSON mode では出力が終了まで来ないため silence counter がリセットされず、長時間実装タスクで kill 頻度が上昇していた。3600s 設定により active-implementation kill のリスクを緩和する。
- `json-mode-silent-hang` は既に `modules/orchestration-fallbacks.md` にカタログ済みだが、`apply-fallback.sh` に対応する Tier 2 ハンドラがなく Tier 3 にエスカレートしていた。本 Issue では `code-pr` フェーズ限定で Tier 2 ハンドラを追加する。他フェーズへの拡張は別 Issue で検討。
- `detect-wrapper-anomaly.sh` の `json-mode-silent-hang` 検出は exit code 143 AND `still waiting (json mode)` の AND 条件。`apply-fallback.sh` 側は exit code を受け取らないため、`still waiting (json mode)` ログパターンのみで検出する (フェーズ限定でリスクを絞る)。

## Consumed Comments

- saito / MEMBER / first-class / Issue retrospective: auto-resolved ambiguity points (source entries count update, AC2 rubric timing fix, Pre/Post-merge section split) / https://github.com/saitoco/wholework/issues/799#issuecomment-4822091817

## review retrospective

### Spec vs. implementation divergence patterns

`modules/orchestration-fallbacks.md` の `### Applicable Phases` セクションが "Any phase" と記載しているが、`apply-fallback.sh` の実装は `code-pr` フェーズのみに対応している。Spec の Notes には「他フェーズは別 Issue で検討」と明記されているが、`orchestration-fallbacks.md` 自体には制限が記載されていない。Tier 2 ハンドラの実装範囲が広がる際に、モジュールドキュメントと実装の同期が必要。

### Recurring issues

Nothing to note.

### Acceptance criteria verification difficulty

AC1 (rubric) は各 cause group の緩和策実装を確認する形式で、PR diff から直接 PASS/FAIL を判断できた。AC2 (file_contains) は `git show HEAD:docs/reports/orchestration-recoveries.md` で確認が必要だった (worktree の working directory が PR ブランチではなく main branch を参照していたため)。今後、`file_contains` verify command を PR ブランチのコンテキストで実行する場合は `git show HEAD:file` パターンが信頼性が高い。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #808 をスカッシュマージ (closes #799)、BASE_BRANCH=main のため Issue は自動クローズ
- ローカルブランチ削除エラー (別 worktree が `worktree-code+issue-799` を使用中) は無視 — リモートブランチ・PR は正常マージ済み
- 競合なし (mergeable=CLEAN、CI 全 SUCCESS) のため conflict resolution フローはスキップ

### Deferred Items
- `modules/orchestration-fallbacks.md` の `Applicable Phases` セクション更新 (review フェーズ引継ぎ、SHOULD レベル未実施)
- `worktree-code+issue-799` ローカルブランチの手動削除 (別 worktree 使用中のため自動削除不可)

### Notes for Next Phase
- verify フェーズで main ブランチのスカッシュコミットを対象に verify command を実行すること
- `docs/reports/orchestration-recoveries.md`、`scripts/apply-fallback.sh`、`scripts/watchdog-defaults.sh`、`tests/apply-fallback.bats`、`tests/watchdog-defaults.bats` が変更対象ファイル
