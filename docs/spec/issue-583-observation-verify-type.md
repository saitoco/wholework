# Issue #583: verify-type: observation 正式分類の導入

## Overview

phase/verify 滞留の「真の WIP」と「観測待ち」を区別するため、新 verify-type `observation` を導入する。
文法: `<!-- verify-type: observation event=<event-name> -->` — 次回の指定イベント発生時に自動再評価される。

有効な `event-name` 値（規約として制限）:
- `pr-review-full` — 次回 `/review --full` 完了時
- `pr-review-light` — 次回 `/review --light` 完了時
- `auto-run` — 次回 `/auto` 完了時（成功・失敗問わず）
- `watchdog-kill` — watchdog kill 発生時
- `fix-cycle` — verify FAIL → reopen → fix サイクル発動時（**定義のみ。emitter 実装は follow-up**）

未知の `event=` 値は warning を出して `opportunistic` 相当にフォールバック（後方互換）。

既存 7 Issue（#555, #556, #557, #562, #563, #567, #569）の migration は issue body 更新作業として含む（post-merge manual 確認）。

## Changed Files

- `modules/verify-classifier.md`: `observation` verify-type 追加（文法・event 値・フォールバック規則）
- `modules/verify-executor.md`: verify-type 別処理テーブルに `observation` 追加
- `scripts/opportunistic-search.sh`: `--event <name>` フィルタ追加 — bash 3.2+ 互換
- `tests/opportunistic-search.bats`: `--event` フィルタ関連の新規テストケース追加
- `skills/review/SKILL.md`: Opportunistic Verification ステップに `pr-review-full`/`pr-review-light` イベント発火追加
- `skills/auto/SKILL.md`: Step 5 Completion Report に `auto-run` イベント発火追加
- `scripts/claude-watchdog.sh`: watchdog kill 時に `watchdog-kill` イベント発火（shell レベル、コメント投稿のみ） — bash 3.2+ 互換
- `skills/verify/SKILL.md`: Step 11 unchecked 条件チェックに `observation` 追加、Step 7 Type 表示に `observation` 追加
- `skills/audit/SKILL.md`: stats サブコマンドに 3 メトリクス追加（observation 待ち数、opportunistic 残数、滞留期間）
- `docs/workflow.md`: `opportunistic/manual` → `opportunistic/observation/manual` に更新（2 箇所）
- `docs/ja/workflow.md`: 同上（日本語ミラー）
- `docs/structure.md`: `opportunistic-search.sh` 説明文を observation 対応に更新
- `docs/ja/structure.md`: 同上（日本語ミラー）

## Implementation Steps

1. **`modules/verify-classifier.md` + `modules/verify-executor.md` 更新** (→ AC1, AC2, AC3)
   - verify-classifier.md: Classification Criteria テーブルに `observation` 行追加（`<!-- verify-type: observation event=<name> -->` タグが付いている条件、event 値一覧、unknown event フォールバック）
   - verify-executor.md: verify-type 別処理テーブルを新設し `observation` の処理方針を記載（通常 `/verify` 実行ではスキップ; 指定 event 発生時に opportunistic-search.sh --event で自動再評価）

2. **`scripts/opportunistic-search.sh` `--event <name>` フィルタ追加 + `tests/opportunistic-search.bats` 更新** (→ AC4, AC5)
   - opportunistic-search.sh に `--event <name>` オプションを追加（bash 3.2+ 互換）
   - `--event` なし: 既存動作（`verify-type: opportunistic` フィルタ）
   - `--event <name>` あり: `verify-type: observation event=<name>` の unchecked 条件を対象にフィルタ
   - skill name 引数は `--event` 使用時は不要（省略可能に変更）
   - tests/opportunistic-search.bats に追加するテスト:
     - `"event filter: --event matches observation conditions with matching event"`
     - `"event filter: --event excludes opportunistic conditions"`
     - `"event filter: --event excludes non-matching event name"`
     - `"event filter: --event with dry-run returns empty array"`
     - `"event filter: unknown event emits warning and falls back"`

3. **`skills/review/SKILL.md` + `skills/auto/SKILL.md` + `scripts/claude-watchdog.sh` イベント発火追加** (→ AC6) — watchdog 変更は bash 3.2+ 互換
   - skills/review/SKILL.md: Opportunistic Verification ステップの後（または opportunistic-verify.md 呼び出しの前）に event-based scan を追加。`REVIEW_DEPTH=full` の場合 `opportunistic-search.sh --event pr-review-full`、`REVIEW_DEPTH=light` の場合 `--event pr-review-light` を呼び出す。JSON が空でなければ opportunistic-verify.md と同様のフローで AC を再評価・チェックボックス更新・label 遷移実施。
   - skills/auto/SKILL.md: Step 5 Completion Report 後に（成功・失敗問わず）`opportunistic-search.sh --event auto-run` を呼び出す。同様に再評価フロー実施。
   - scripts/claude-watchdog.sh: `_watchdog_killed=true` 時に `opportunistic-search.sh --event watchdog-kill` を呼び出す（CLAUDE_PLUGIN_ROOT が設定されている場合のみ）。matched issues があればコメント投稿（"watchdog-kill event observed — condition FAIL"）。AI 判定なし（shell script のため）。

4. **`skills/verify/SKILL.md` Step 7・Step 11 更新** (→ AC1 間接)
   - Step 7 Post-merge Briefing: Type 表示列に `observation` を追加（`verify-type: observation event=*` を持つ条件は `observation ({event-name})` と表示）
   - Step 11 (a): 「unchecked opportunistic or manual conditions」 → 「unchecked opportunistic, observation, or manual conditions」に拡張。`<!-- verify-type: observation -->` の unchecked 条件が残る場合も `phase/verify` を維持する

5. **`skills/audit/SKILL.md` 新メトリクス追加 + docs 更新** (→ AC7, AC8)
   - skills/audit/SKILL.md stats サブコマンドの Step 2/3 に追加:
     - **phase/verify 滞留期間**（median, p95, max）: phase/verify ラベル付与からの経過日数
     - **observation 待ち Issue 数**: `verify-type: observation` の unchecked AC を持ち phase/verify な Issue
     - **opportunistic 残数**: `verify-type: opportunistic` の unchecked AC を持つ Issue 数
   - docs/workflow.md 2 箇所: `opportunistic/manual` → `opportunistic/observation/manual`
   - docs/ja/workflow.md 同上
   - docs/structure.md: `opportunistic-search.sh` 説明を `opportunistic skill search and observation event scan` に更新
   - docs/ja/structure.md: 同上（`opportunistic スキル検索と observation イベントスキャン`）

## Verification

### Pre-merge

- <!-- verify: grep "verify-type: observation" "modules/verify-classifier.md" --> `verify-type: observation` の文法と event 値が `verify-classifier.md` に文書化されている
- <!-- verify: grep "event=" "modules/verify-classifier.md" --> `event=<event-name>` パラメータの文法が `verify-classifier.md` に記述されている
- <!-- verify: grep "observation" "modules/verify-executor.md" --> `verify-executor.md` の verify-type 解釈テーブルに `observation` が追加されている
- <!-- verify: grep -- "--event" "scripts/opportunistic-search.sh" --> `opportunistic-search.sh` に `--event <name>` フィルタが実装されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> opportunistic-search の bats テストが green（observation イベントフィルタの新規ケース含む）
- <!-- verify: rubric "skills/review/SKILL.md, skills/auto/SKILL.md (and other event-emitting skills) invoke opportunistic-search with --event <name> at completion, scanning phase/verify Issues with matching observation AC for auto re-verification" --> イベント発火 skill が完了時に該当 event の observation AC を自動再評価する
- <!-- verify: grep "observation" "skills/audit/SKILL.md" --> `/audit stats` に observation 待ち Issue 数メトリクスが追加されている
- <!-- verify: grep "滞留" "skills/audit/SKILL.md" --> `/audit stats` に phase/verify 滞留期間メトリクスが追加されている

### Post-merge

- 次回 `/review --full` 実行で `event=pr-review-full` を持つ Issue が自動チェックされ、PASS した Issue が phase/done に到達することを観察 <!-- verify-type: observation event=pr-review-full -->
- `/audit stats` の新メトリクスが想定どおりの値を返す（phase/verify 滞留中央値などが妥当） <!-- verify-type: opportunistic -->
- 既存 7 Issue（#555, #556, #557, #562, #563, #567, #569）の該当 AC が `observation event=<該当>` に更新されていることを確認 <!-- verify-type: manual -->

## Notes

- `fix-cycle` は定義のみ（emitter 実装は follow-up Issue）。`verify-classifier.md` には event 名として記載し、実装ステータスを明記する
- `claude-watchdog.sh` は shell script のため AI 判定不可。observation 条件の FAIL 記録（コメント投稿）のみ実施。FAIL 時の checkbox 更新・label 遷移は `/verify` 再実行で行う
- `--event` 使用時は skill name 引数を省略可能にする。既存の skill name 必須チェックは `--event` 未指定時のみ適用
- unknown event フォールバック: `verify-type: opportunistic` 扱いで処理し、stderr に "Warning: unknown event '<name>', falling back to opportunistic treatment" を出力
- Step 4 の verify/SKILL.md 更新は AC に verify command がないが、Step 5 の docs/workflow.md 更新や Step 1 の classifier 更新が前提となる。Step 11 の `observation` 追加は後方互換（既存 Issues への影響なし）
- Step 2 の bats 自己参照チェック: `tests/opportunistic-search.bats` に `verify-type: observation event=` を含む fixture を書くが、`opportunistic-search.sh` は `SCAN_DIRS` 対象外のため check-forbidden-expressions.sh には影響しない

### Auto-Resolve Log（非対話モード自動解決）

| # | 曖昧ポイント | 採用した選択肢 | 根拠 |
|---|------------|--------------|------|
| 1 | watchdog-kill emitter の実装場所（SKILL.md vs claude-watchdog.sh） | claude-watchdog.sh に追加（shell レベル、AI 判定なし） | watchdog は SKILL.md ではなく shell script。既存の `_watchdog_killed` フラグを活用するのが最小コスト |
| 2 | `--event` 時の skill name 引数の扱い | 省略可能に変更 | event スキャンは skill name に依存しない。既存テストとの互換は条件分岐で維持 |
| 3 | skills/verify/SKILL.md の observation 処理（Step 8 で明示スキップ vs 黙示） | Step 7 type 表示に `observation` を追加し、Step 11 unchecked チェックに `observation` を含める。Step 8 で observation 条件は「event 待ち — スキップ」として扱う | verify-classifier.md の分類表と整合。手動確認も不要（event 発火時に自動再評価）なので Step 8b へのルーティングも不要 |
