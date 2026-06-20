# Issue #700: verify: tail に auto-retry-on-fail を追加し FAIL を予算内で自動折り返す

## Overview

`/verify` FAIL 経路に opt-in の自動リトライループを追加する。`.wholework.yml` で `auto-retry-on-fail.enabled: true` を設定し、AUTONOMY_TIER が L2/L3 の場合、AC FAIL 検出後に自動で `/code` を再発火し `/verify` を再実行する。`max_iterations` 到達または `budget_tokens` 枯渇で停止し、停止時のみユーザに戻る。

AUTONOMY_TIER が L1 の場合、または `auto-retry-on-fail.enabled` が未設定の場合は現状動作 (reopen + ユーザ復帰) に加えて advisory print (path A) のみ出力する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (auto-resolve log): A1 Post-merge verify-type を manual に変更, A2 loop-paths-used AC 追加, A3 Retry Count AC 追加 / https://github.com/saitoco/wholework/issues/700#issuecomment-4757371687

## Changed Files

- `skills/verify/SKILL.md`: frontmatter に `loop-paths-used: [A]` を追加 (Step 1)
- `skills/verify/SKILL.md`: Step 4 の retain 変数リストに `AUTONOMY_TIER`, `AUTO_RETRY_ENABLED`, `AUTO_RETRY_MAX_ITERATIONS`, `AUTO_RETRY_BUDGET_TOKENS` を追加 (Step 4)
- `skills/verify/SKILL.md`: Step 11(b) FAIL 経路 (NEXT_ITERATION < VERIFY_MAX_ITERATIONS) に tier-gated auto-retry ブロックを追加 (Step 4)
- `skills/verify/SKILL.md`: Step 12 `## Verify Retrospective` テンプレートに `Retry Count: N/max` 追記ロジックを追加 (Step 5)
- `modules/detect-config-markers.md`: Marker Definition Table に `auto-retry-on-fail.*` 3 キーを追加; Output Format に 3 変数を追加 (Step 2)
- `scripts/emit-event.sh`: `verify_retry_fire` イベントスキーマをコメントに追加 (Step 3)
- `docs/guide/customization.md`: SHOULD — `auto-retry-on-fail` キーをリファレンステーブルとサンプル YAML に追加
- `docs/tech.md`: SHOULD — Architecture Decisions の `#700 / #702 / #703` 参照を更新; `docs/ja/tech.md` の日本語ミラーも同期

## Implementation Steps

1. **`skills/verify/SKILL.md` frontmatter 追加**: `model: sonnet` の直後の行に `loop-paths-used: [A]` を追加する (→ AC4)。bash 3.2+ 互換 (ファイル編集のみ)。

2. **`modules/detect-config-markers.md` 更新**: Marker Definition Table に以下の 3 行を追加する (→ AC3)。既存 `autonomy` 行の直後が挿入位置として適切。Output Format セクションにも 3 変数を追加する。
   ```
   | `auto-retry-on-fail.enabled`      | `AUTO_RETRY_ENABLED`          | `true`                        | `false`                     |
   | `auto-retry-on-fail.max_iterations` | `AUTO_RETRY_MAX_ITERATIONS` | Integer string (extract as-is; use `3` if ≤0 or non-numeric) | `3` |
   | `auto-retry-on-fail.budget_tokens`  | `AUTO_RETRY_BUDGET_TOKENS`  | Integer string (extract as-is; use `500000` if ≤0 or non-numeric) | `500000` |
   ```
   YAML Parsing Rules: nested キー `auto-retry-on-fail.enabled` は `auto-retry-on-fail:` セクション下の `enabled: true/false` として解釈する。`max_iterations` と `budget_tokens` は整数として扱う。

3. **`scripts/emit-event.sh` イベントスキーマ追加**: `comments_consumed` スキーマコメントブロックの直後に以下を追加する (→ AC2)。コードロジックの変更なし、コメント追加のみ。bash 3.2+ 互換。
   ```
   # verify_retry_fire: tail extension が /code を再発火した
   #   iteration=<n>                 verify retry iteration counter (1-based within auto-retry)
   #   trigger_reason=<reason>       ac_fail | verify_timeout | verify_uncertain
   #   budget_remaining_tokens=<n>   estimated remaining token budget (approximated)
   ```

4. **`skills/verify/SKILL.md` Step 4 + Step 11(b) 更新** (Step 1 の後):
   - Step 4 の "Retain" 変数リストに `AUTONOMY_TIER`, `AUTO_RETRY_ENABLED`, `AUTO_RETRY_MAX_ITERATIONS`, `AUTO_RETRY_BUDGET_TOKENS` を追記する。
   - Step 11(b) の FAIL 経路 (NEXT_ITERATION < VERIFY_MAX_ITERATIONS) の既存動作 (reopen + label 削除 + guidance 出力) の直後に以下のブロックを挿入する (→ AC1):

   ```
   **Tier-gated auto-retry check:**

   If AUTONOMY_TIER is `L2` or `L3` AND `AUTO_RETRY_ENABLED=true` AND `NEXT_ITERATION` < `AUTO_RETRY_MAX_ITERATIONS`:
     a. Emit `verify_retry_fire` event (only when AUTO_EVENTS_LOG is set):
        ```bash
        source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
        EMIT_ISSUE_NUMBER=$NUMBER emit_event "verify_retry_fire" \
          "iteration=${NEXT_ITERATION}" \
          "trigger_reason=ac_fail" \
          "budget_remaining_tokens=unknown"
        ```
     b. Append `Retry Count: ${NEXT_ITERATION}/${AUTO_RETRY_MAX_ITERATIONS}` to the Spec's
        `## Verify Retrospective` section (handled in Step 12).
     c. Re-invoke code phase:
        ```bash
        bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh" $NUMBER --patch [--base $BASE_BRANCH]
        ```
     d. After run-code.sh completes, restart verification from Step 5 (the LLM re-executes
        Steps 5–11 in the same session context).

   If AUTONOMY_TIER is `L1` OR `AUTO_RETRY_ENABLED` is not `true`:
     Print advisory (path A):
     "次の手として `/goal` または `/code --patch $NUMBER` で再発火可能です。"
   ```

5. **`skills/verify/SKILL.md` Step 12 Retry Count 追記** (Step 4 の後):
   `## Verify Retrospective` テンプレートの `### Improvement Proposals` セクションの前に以下を追加する (→ AC5):

   ```
   **Retry Count** (include only when auto-retry ran: N ≥ 1; omit when N=0):
   Retry Count: N/AUTO_RETRY_MAX_ITERATIONS
   ```

   Spec へのappend 時、`NEXT_ITERATION` ≥ 1 の場合のみこの行を `## Verify Retrospective` セクションに追記する。N=0 (1 回目で PASS) のときは省略する。

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/verify/SKILL.md" "auto-retry-on-fail" --> `/verify` SKILL.md に `auto-retry-on-fail` 分岐ロジックが追記されている
- <!-- verify: file_contains "scripts/emit-event.sh" "verify_retry_fire" --> `verify_retry_fire` イベント型が `emit-event.sh` の documented event schemas に追加されている
- <!-- verify: grep "auto-retry-on-fail" "modules/detect-config-markers.md" --> `.wholework.yml` フラグが `detect-config-markers.md` の marker テーブルに登録されている
- <!-- verify: grep "loop-paths-used" "skills/verify/SKILL.md" --> `/verify` SKILL.md frontmatter に `loop-paths-used: [A]` が宣言されている
- <!-- verify: grep "Retry Count" "skills/verify/SKILL.md" --> `/verify` SKILL.md に Spec retrospective への `Retry Count: N/max` カウンタ追記ロジックが記述されている

### Post-merge

- `auto-retry-on-fail.enabled: true` を `.wholework.yml` に設定した状態で `/verify N` を意図的に FAIL させ、`/code` 再発火 → `/verify` 再実行 → 最終的に PASS または budget 枯渇で停止することを観察する <!-- verify-type: manual -->

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- **Spec Note `allowed-tools 変更不要` は不正確だった**: Spec Notes に「`run-code.sh` は既存の Bash allowed-tools パターン `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` でカバーされている」と記述されていたが、`skills/verify/SKILL.md` の `allowed-tools` には `*.sh` ワイルドカードパターンは存在せず個別スクリプトが列挙されている。`validate-skill-syntax.py` のチェックにより検出し、`${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*` を `allowed-tools` に追加した。
- **`loop-paths-used` が `KNOWN_FIELDS` に未登録だった**: 新 frontmatter フィールドを追加したが、`scripts/validate-skill-syntax.py` の `KNOWN_FIELDS` セットに未登録のため "unknown field" 警告が出た。`loop-paths-used` を `KNOWN_FIELDS` に追加して解消した。
- **AC1 の literal match 不備**: 実装では `AUTO_RETRY_ENABLED` (変数名) として参照していたが、`file_contains "skills/verify/SKILL.md" "auto-retry-on-fail"` の verify command はキー名 `auto-retry-on-fail` が本文中に存在することを要求していた。Step 11 の tier-gated ブロックに `auto-retry-on-fail.enabled` への明示的参照を追加して解消した。

### Design Gaps/Ambiguities

- **`docs/workflow.md` の Verify Fail フロー記述が旧来の「手動選択のみ」だった**: 今回の変更で opt-in 自動リトライの存在が文書化されていない状態になるため、`docs/workflow.md` および `docs/ja/workflow.md` も更新した。Spec の Changed Files リストに含まれていなかった。

### Rework

- `skills/verify/SKILL.md` を 3 回に分けてコミット: 初回実装 → `allowed-tools` 追加 + `loop-paths-used` バリデータ修正 → AC1 literal string 追加。いずれも validate-skill-syntax.py の検出結果に基づく修正。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `auto-retry-on-fail` は `.wholework.yml` の `auto-retry-on-fail:` セクション下のネストキーとして実装。`detect-config-markers.md` にパースルールを追記した。
- `run-code.sh` を `skills/verify/SKILL.md` の `allowed-tools` に追加した (Spec Note の誤りを修正)。
- `loop-paths-used: [A]` frontmatter とそのバリデータサポートを同時に実装した。

### Deferred Items
- `budget_tokens` の実際のトークン消費量ベース判定は将来拡張 (Spec Notes に記録済み)。
- `--pr` ルートでの auto-retry サポートは将来拡張 (現在 `--patch` 固定)。

### Notes for Next Phase
- `docs/workflow.md` の Verify Fail フロー記述を更新済み (review で確認推奨)。
- `validate-skill-syntax.py` KNOWN_FIELDS への `loop-paths-used` 追加は意図的な変更。
- All 5 pre-merge ACs pass (verified locally).

## Notes

- **Tier-gating 設計**: L1 では `auto-retry-on-fail.enabled` を読まない。advisory print のみ (path A)。L2/L3 では enabled=true かつ NEXT_ITERATION < AUTO_RETRY_MAX_ITERATIONS の場合にリトライループを起動する。`budget_tokens` は将来的に実際のトークン消費量で判定する予定だが、初期実装では `NEXT_ITERATION` ベースのイテレーション制限のみを使用し `budget_remaining_tokens=unknown` を emit する。
- **`run-code.sh` の route 決定**: 初期実装では `--patch` フラグを固定で使用する。Size L 以上での PR ルートは将来の拡張として Notes に記録する。
- **`Skill()` ツール不使用**: `/verify` の allowed-tools に `Skill` は含まれていないため、re-verify は SKILL.md の LLM 実行者が Step 5 に戻る形で実現する (同一セッション内の継続実行)。
- **auto-resolve ログ引継ぎ**: Issue Retrospective (コメント) の内容は以下の通り引き継いだ:
  - A1: Post-merge verify-type を `manual` に変更 (verify-retry は verify-classifier.md に未登録)
  - A2: `loop-paths-used: [A]` を Pre-merge AC に追加
  - A3: `Retry Count: N/max` を Pre-merge AC に追加
- **`docs/guide/customization.md` SHOULD**: `auto-retry-on-fail` キーを configuration key リファレンステーブルとサンプル YAML に追加する (verify-max-iterations と同様の形式)。この変更は MUST AC には含まれていないが、ユーザ向けドキュメントの一貫性のために推奨する。
- **`docs/tech.md` SHOULD**: Architecture Decisions の「Enforcement of skill-level gating... is delegated to #700 / #702 / #703」の記述を #700 実装後に更新する。`docs/ja/tech.md` の日本語ミラーも同期が必要 (translation-workflow.md 準拠)。
- **`verify` allowed-tools 変更不要**: `run-code.sh` は既存の Bash allowed-tools パターン `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` でカバーされている。`validate-skill-syntax.py` KNOWN_TOOLS の更新も不要 (新ツール追加なし)。
