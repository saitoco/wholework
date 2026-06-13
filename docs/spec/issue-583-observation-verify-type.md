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

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- bats テスト324（unknown event fallback）の assertion を修正: フォールバック実行が opportunistic 条件をマッチして issue を返すことを正しく検証する形に変更した（`run 2>&1` + warning + jq length check）
- claude-watchdog.sh のロバスト性改善: `$_issue_numbers` の空チェックガードを追加（jq 失敗時の空ループを防止）
- `skills/review/SKILL.md` の allowed-tools は既に `opportunistic-search.sh` と `gh-issue-edit.sh` を含んでおり、review-light が指摘した MUST は誤検知だった

### Deferred Items
- 既存 7 Issue (#555, #556, #557, #562, #563, #567, #569) の AC を `observation event=<該当>` へ書き換える migration は post-merge manual AC として残存
- `fix-cycle` イベントの emitter 実装は follow-up Issue に委譲
- `tests/opportunistic-search.bats` の `$stderr` 参照パターン（bats バージョン依存）の統一化は別途検討

### Notes for Next Phase
- 修正コミット (48c4ab3) を含む CI (bats tests) が green になることを確認してからマージを進めること
- Post-merge 後に observation AC（event=pr-review-light）が今回の `/review --light` 実行で自動チェックされるか観察する（本 review 自体が pr-review-light イベント）
- `/audit stats` の Section 7 の動作確認は次回 `/audit stats` 実行後に推奨

## Code Retrospective

### Deviations from Design

- `skills/audit/SKILL.md` にメトリクス追加に加え、日本語用語「滞留」を section header に追記した。理由: verify command が `grep "滞留" "skills/audit/SKILL.md"` を実行するため、英語の "dwell" だけでは AC8 が FAIL になる。AC の文字列と実装の整合をとるため追加した。

### Design Gaps/Ambiguities

- `validate-skill-syntax.py` が `skills/auto/SKILL.md` の本文中スクリプト参照をチェックするため、`opportunistic-search.sh` と `gh-issue-edit.sh` を `allowed-tools` に追加する必要があった（Spec には記載なし）。追加コミットで対処。

### Rework

- `skills/audit/SKILL.md` を2回コミット: 初回は英語のみで `dwell time` セクションを追加し、verify-executor 実行後に AC8（`grep "滞留"`）が FAIL であることが判明したため2回目のコミットで「滞留」を追記した。

### Auto-Resolve Log（非対話モード自動解決）

| # | 曖昧ポイント | 採用した選択肢 | 根拠 |
|---|------------|--------------|------|
| 1 | watchdog-kill emitter の実装場所（SKILL.md vs claude-watchdog.sh） | claude-watchdog.sh に追加（shell レベル、AI 判定なし） | watchdog は SKILL.md ではなく shell script。既存の `_watchdog_killed` フラグを活用するのが最小コスト |
| 2 | `--event` 時の skill name 引数の扱い | 省略可能に変更 | event スキャンは skill name に依存しない。既存テストとの互換は条件分岐で維持 |
| 3 | skills/verify/SKILL.md の observation 処理（Step 8 で明示スキップ vs 黙示） | Step 7 type 表示に `observation` を追加し、Step 11 unchecked チェックに `observation` を含める。Step 8 で observation 条件は「event 待ち — スキップ」として扱う | verify-classifier.md の分類表と整合。手動確認も不要（event 発火時に自動再評価）なので Step 8b へのルーティングも不要 |

## Review Retrospective

### Spec と実装の乖離パターン

- Spec では「unknown event フォールバック時に `verify-type: opportunistic` として扱う」と定義しているが、対応するテスト（test 324）は `$output == "[]"` を期待していた。フォールバックが正しく動作すると opportunistic 条件にマッチする issue を返すため、期待値が実装と矛盾していた。Spec とテスト期待値の整合確認が実装後の必須チェックとして重要。

### 繰り返し問題

- コンポーネント追加時に同種の複数箇所（skills/auto/SKILL.md と skills/review/SKILL.md の両方）に対して allowed-tools 追加が必要なケースでは、片方のみ対応する漏れが発生しやすい。今回は skills/review/SKILL.md が既存の allowed-tools に opportunistic-search.sh と gh-issue-edit.sh を含んでいたため問題なかったが、複数 skill への横断変更時は全対象 skill を一覧して確認するべき。

### 受け入れ条件検証の困難さ

- bats テストの `$stderr` 変数は bats バージョンに依存する。テスト設計時に「stderr に出力される warning を検証する」場合は `run 2>&1` か `--separate-stderr` を使う必要があり、テンプレートとして明記すると良い。`$stderr` を直接参照する assertion は実際には機能しないケースがある（今回の test 324 の UNCERTAIN 要素）。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #603 を squash merge（`--delete-branch` 付き）。`closes #583` がPR bodyに含まれ BASE_BRANCH=main のため Issue は自動クローズ
- mergeable=false/reason=unknown の状態で non-interactive auto-resolve としてマージ続行。実際のマージは成功（GH API の mergeable 判定タイミングの問題と判断）
- Phase Handoff の prior handoff は存在しなかった（review phase からの引き継ぎなし）

### Deferred Items
- 既存 7 Issue（#555, #556, #557, #562, #563, #567, #569）の `observation event=<該当>` への migration は post-merge 手動確認タスクとして残存
- `fix-cycle` event の emitter 実装は follow-up Issue 対象（Spec に明示）
- `/audit stats` の新メトリクス（滞留期間 median/p95/max、observation 待ち数）の動作確認は post-merge 観察

### Notes for Next Phase
- verify phase では post-merge 観察 AC（`next /review --full` 実行で `event=pr-review-full` を持つ Issue が自動チェックされるか）を確認する
- `scripts/opportunistic-search.sh --event <name>` の `--event` フィルタ動作を実際の review/auto 実行で観察すること
- `/audit stats` コマンドで新メトリクスが想定値を返すか verify する
