# Issue #208: fix: autonomous mode で run-*.sh が interactive prompt を出力して停止する

## Overview

`/auto --batch` 実行中に `run-issue.sh` が autonomous mode（`claude -p --dangerously-skip-permissions`）で起動されているにもかかわらず、曖昧点を検出すると `AskUserQuestion` で interactive prompt を出力して処理が停止する。同様の問題は `spec` / `review` / `merge` skill にも存在し、一方で既存の `code` / `verify` skill は `--non-interactive` フラグパターンを持つものの「exit with error」ポリシーを採用しており、auto-resolve 方針とは反対になっている。

本 Issue では全対象 skill で「**auto-resolve + retrospective 記録**」ポリシーに統一し、必要な箇所に `--non-interactive` フラグ検知と分岐を追加する。

## Reproduction Steps

1. 曖昧点を含む Issue を作成（例: Size 未設定 + 複数解釈可能な受入条件）
2. `run-issue.sh $NUMBER` を実行
3. skill が `AskUserQuestion` を呼び出して interactive prompt を出力
4. `claude -p` プロセスが stdin 応答を得られず、出力のみ出して exit 0 で終了
5. Issue ラベルは `phase/issue` で止まり、`phase/ready` に遷移しない

再現事例：#196（既存テスト存在でスコープ判断要求）、#194（Purpose のスコープ境界要求）。

## Root Cause

1. **`run-issue.sh` が `--non-interactive` を ARGUMENTS に付与していない** — 既存 `run-code.sh` / `run-verify.sh` / `run-spec.sh` は付与するが、`run-issue.sh` / `run-review.sh` / `run-merge.sh` は付与しない
2. **skill 側の `--non-interactive` 分岐が未実装** — `issue` / `review` / `spec` の SKILL.md は `--non-interactive` を検出しない（`spec` は flag を受け取っても処理しない空振り状態）
3. **既存 `code` / `verify` / `merge` は「exit with error」ポリシー** — autonomous の完了率を下げるため、本 Issue の「auto-resolve」方針とポリシーが衝突
4. **`modules/ambiguity-detector.md` に non-interactive mode のガイダンスがない** — 各 skill で個別に実装する必要があり、一貫性が保てない

fix 方針：①全 `run-*.sh` で `--non-interactive` 付与、②全 skill で `--non-interactive` 検知 + auto-resolve ポリシー統一、③`ambiguity-detector.md` に共通ガイダンスを追加。

## Changed Files

- `modules/ambiguity-detector.md`: `## Non-Interactive Mode Handling` セクションを追加し、auto-resolve ポリシー・Auto-Resolve Log フォーマット・High-Stakes Decisions 定義を集約
- `skills/issue/SKILL.md`: `## Non-Interactive Mode Behavior` セクション追加、Step 5/7/11 の `AskUserQuestion` 箇所に non-interactive mode 分岐注記を追加、Step 9 (sub-issue splitting) を High-Stakes として skip 扱いに
- `skills/spec/SKILL.md`: `## Non-Interactive Mode Behavior` セクション追加、Step 6 conflict detection / Step 7 clarify / Step 8 uncertainty の `AskUserQuestion` 箇所に分岐注記を追加
- `skills/code/SKILL.md`: 既存 "Error Handling in Non-Interactive Mode" セクションのポリシーを「exit with non-zero」→「auto-resolve + log」に変更。Size 未設定 / XL などの hard error は exit のまま維持（モジュール側の High-Stakes 一覧に該当理由を明記）
- `skills/review/SKILL.md`: `## Non-Interactive Mode Behavior` セクション追加（既存 `--auto` 委譲セクションとは別）、AskUserQuestion 箇所を洗い出して分岐注記を追加
- `skills/merge/SKILL.md`: 既存 "Error Handling in Non-Interactive Mode" セクション内の `--auto` 参照を `--non-interactive` に修正し、ポリシーを「exit with non-zero」→「auto-resolve + log」に変更（delegation 側の `## Autonomous Mode (--auto)` セクションはユーザー向けフラグとして残す）
- `skills/verify/SKILL.md`: 既存 "Error Handling in Non-Interactive Mode" 表の「Non-interactive mode」列のポリシーを exit 系から「auto-resolve」系に変更
- `skills/audit/SKILL.md`: 3箇所の `AskUserQuestion` に non-interactive mode 分岐注記を追加（該当セクションの設計判断を auto-resolve）
- `skills/doc/SKILL.md`: 複数箇所の `AskUserQuestion` のうち、bulk approval / optional section 追加系は skip 扱い、単一選択系は auto-resolve 扱いで分岐注記
- `skills/triage/SKILL.md`: `--backlog` Step 4 の approval flow を non-interactive mode では skip （bulk 操作で誤適用リスク大）に変更する旨を追記
- `scripts/run-issue.sh`: ARGUMENTS 組み立て時に ` --non-interactive` を末尾に付与（bash 3.2+ 互換）
- `scripts/run-review.sh`: ARGUMENTS 組み立て時に ` --non-interactive` を末尾に付与（bash 3.2+ 互換）
- `scripts/run-merge.sh`: ARGUMENTS 組み立て時に ` --non-interactive` を末尾に付与（bash 3.2+ 互換）
- `tests/run-issue.bats`: `--non-interactive` が ARGUMENTS に含まれることを検証するテストを追加
- `tests/run-review.bats`: 同上
- `tests/run-merge.bats`: 同上

## Implementation Steps

1. **共通ガイダンスの追加** (→ acceptance criteria: ambiguity-detector.md non-interactive): `modules/ambiguity-detector.md` の末尾に `## Non-Interactive Mode Handling` セクションを追加し、以下を記述：
   - 検知メカニズム（ARGUMENTS 中の `--non-interactive`）
   - 3段階の分岐（auto-resolve / skip / hard-error abort）
   - Auto-Resolve Log フォーマット（`## Autonomous Auto-Resolve Log` サブセクション、`- **[選択肢]** — reason: ... / Other candidates: ...`）
   - High-Stakes Decisions 列挙（sub-issue splitting / optional additions / bulk approvals）
   - モデル判断の推奨ヒューリスティック（least-risk、codebase パターン優先、skipで安全な場合は skip）

2. **wrapper script の ARGUMENTS 付与** (parallel with 1) (→ run-issue.sh non-interactive / run-review.sh non-interactive / run-merge.sh non-interactive):
   - `scripts/run-issue.sh` L53-55 相当の `PROMPT="${SKILL_BODY}\n\nARGUMENTS: ${ISSUE_NUMBER}"` を `ARGUMENTS: ${ISSUE_NUMBER} --non-interactive` に変更
   - `scripts/run-review.sh` L49-55 相当の ARGUMENTS 組み立てに ` --non-interactive` を追加
   - `scripts/run-merge.sh` L44-47 相当の ARGUMENTS 組み立てに ` --non-interactive` を追加
   - いずれも bash 3.2+ 互換の単純な文字列連結で実装

3. **issue skill の non-interactive 対応** (after 1) (→ skills/issue/SKILL.md non-interactive): SKILL.md の先頭付近（`---` frontmatter の直後）に `## Non-Interactive Mode Behavior` セクションを追加し、`modules/ambiguity-detector.md` を参照するよう指示。Step 5 (Ambiguity Detection), Step 7 (Clarification Questions), Step 9 (Scope Assessment / sub-issue splitting), Step 11 (Scope Assessment) の各 `AskUserQuestion` 箇所に「(non-interactive mode: auto-resolve に従う)」または「(non-interactive mode: skip)」の注記を追加

4. **spec skill の non-interactive 対応** (parallel with 3) (→ skills/spec/SKILL.md non-interactive): SKILL.md 先頭付近に `## Non-Interactive Mode Behavior` セクションを追加。Step 6 (Codebase Investigation の conflict detection), Step 7 (Ambiguity Resolution), Step 8 (Uncertainty) の `AskUserQuestion` 箇所に non-interactive mode 分岐注記を追加

5. **code skill のポリシー変更** (parallel with 3, 4) (→ skills/code/SKILL.md auto-resolve): `## Error Handling in Non-Interactive Mode` セクションの policy を「auto-resolve + log」に書き換え。既存の hard-error（Size 未設定、XL size）は `modules/ambiguity-detector.md` の High-Stakes 定義へのリンクを添えた上で exit のまま残す。文中に "auto-resolve" 表記を明示

6. **review skill の non-interactive 対応** (parallel with 3, 4, 5) (→ skills/review/SKILL.md non-interactive): SKILL.md 先頭付近に `## Non-Interactive Mode Behavior` セクションを追加。review phase 中に `AskUserQuestion` が登場する箇所（review コメント対応、外部 review 待機タイムアウト時など）に分岐注記を追加。既存 `## Autonomous Mode (--auto)` とは別セクション

7. **merge skill のリネームとポリシー変更** (parallel with 3-6) (→ skills/merge/SKILL.md non-interactive): `## Error Handling in Non-Interactive Mode` セクション内の `In --auto mode` 表記を `In --non-interactive mode` に修正。既存ポリシー「exit with non-zero」を「auto-resolve + log」に変更。本文各所の `(非-interactive mode: ...)` ガイダンスも内容更新（exit → auto-resolve）。`## Autonomous Mode (--auto)` 委譲セクションはユーザー向けフラグとして残す

8. **verify skill のポリシー変更** (parallel with 3-7) (→ skills/verify/SKILL.md auto-resolve): `## Error Handling in Non-Interactive Mode` 表の `Non-interactive mode` 列の行動を「exit 系」→「auto-resolve + log」系に変更。`auto-resolve` 表記を本文に明示

9. **secondary skill (audit / doc / triage) の対応** (parallel with 3-8): 各 SKILL.md の `AskUserQuestion` 箇所に `(non-interactive mode: auto-resolve または skip)` の注記を追加。特に `doc` の bulk approval・optional section 追加系は skip、`triage --backlog` Step 4 の approval flow も skip

10. **bats テストの追加** (after 2): `tests/run-issue.bats`, `tests/run-review.bats`, `tests/run-merge.bats` に「ARGUMENTS に `--non-interactive` が含まれる」ことを検証するテストケースを追加。`tests/run-code.bats` / `tests/run-spec.bats` の既存パターンを踏襲

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/issue/SKILL.md" "non-interactive" --> `skills/issue/SKILL.md` に `--non-interactive` フラグ対応と auto-resolve ポリシーが記載されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "non-interactive" --> `skills/spec/SKILL.md` に auto-resolve ポリシーが記載されている（`--non-interactive` 記述を含む）
- <!-- verify: file_contains "skills/code/SKILL.md" "auto-resolve" --> `skills/code/SKILL.md` の既存 non-interactive ポリシーが exit→auto-resolve に変更されている
- <!-- verify: file_contains "skills/review/SKILL.md" "non-interactive" --> `skills/review/SKILL.md` に `--non-interactive` フラグ対応と auto-resolve ポリシーが記載されている
- <!-- verify: file_contains "skills/merge/SKILL.md" "non-interactive" --> `skills/merge/SKILL.md` に `--non-interactive` フラグ対応と auto-resolve ポリシーが記載されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "auto-resolve" --> `skills/verify/SKILL.md` の既存 non-interactive ポリシーが exit→auto-resolve に変更されている
- <!-- verify: file_contains "modules/ambiguity-detector.md" "non-interactive" --> `modules/ambiguity-detector.md` に non-interactive mode 分岐が追加されている
- <!-- verify: file_contains "scripts/run-issue.sh" "non-interactive" --> `run-issue.sh` が `--non-interactive` を ARGUMENTS に付与する
- <!-- verify: file_contains "scripts/run-review.sh" "non-interactive" --> `run-review.sh` が `--non-interactive` を ARGUMENTS に付与する
- <!-- verify: file_contains "scripts/run-merge.sh" "non-interactive" --> `run-merge.sh` が `--non-interactive` を ARGUMENTS に付与する

### Post-merge

- 再現ケース（既存実装済み issue の triage、スコープ曖昧点ありの issue）で `run-issue.sh` を autonomous mode で実行し、interactive prompt で停止せず `phase/ready` まで自動遷移する
- autonomous 判断の選択肢と理由が Issue retrospective コメントに `## Autonomous Auto-Resolve Log` として記録されている
- `/auto --batch N` で曖昧点のある issue を処理しても batch が途中停止せず、全件が完了または明示的 SKIP になる
- sub-issue 分割のような高負荷判定が autonomous mode ではスキップされ、警告メッセージと共に本体処理が継続する

## Tool Dependencies

既存の allowed-tools の範囲で実装可能。追加の Bash command patterns・MCP tools は不要。

## Uncertainty

- **merge skill の `--auto` 名称衝突**: delegation flag (`--auto`) と旧 non-interactive mode naming (`--auto` を説明に流用) が混在している。
  - **検証方法**: `skills/merge/SKILL.md` の各 `--auto` 参照を1つずつレビューし、delegation 用途（ユーザーフラグ）か non-interactive mode 用途（内部）かを分類
  - **影響範囲**: Implementation Step 7（merge skill 修正）
- **secondary skills の具体的な分岐点**: `audit` / `doc` / `triage` の `AskUserQuestion` 各箇所について、auto-resolve / skip のどちらが適切かはコンテキスト依存
  - **検証方法**: 各 `AskUserQuestion` 箇所の文脈（設計判断の重要度）を評価し、Step 9 実装時に判定
  - **影響範囲**: Implementation Step 9

## Notes

- **Size L 維持の根拠**: 13ファイル変更（Axis 1では XL 閾値 11+）だが、`modules/ambiguity-detector.md` への集約により skill 側の記述は短く、既存 `--non-interactive` パターンの横展開（lateral extension）であることから、Size Complexity Adjustment の「Simple lateral extension of existing patterns」で 1 段階ダウングレード → L
- **ポリシー衝突の経緯**: 既存 `code` / `verify` skill は「exit with non-zero」で caller に失敗を伝達する設計だった。本 Issue で「auto-resolve + log」に統一する理由は、batch 処理の完了率を最大化するユーザー選択（#208 Issue Q&A）に基づく。hard error（Size 未設定等）は引き続き exit で扱う
- **Auto-Resolve Log の配置**: Issue retrospective コメント または Spec の retrospective セクションのいずれかに `## Autonomous Auto-Resolve Log` サブセクションとして追加する。両者の使い分けは skill に依存（code/verify phase は Spec、issue/spec phase は Issue コメントが自然）
- **High-Stakes Decisions の判定ルール**: 「skip してもワークフロー全体が進行可能」「誤判定で巻き戻しコストが高い」の2条件を満たす場合に High-Stakes 扱い。具体例を `ambiguity-detector.md` に exhaustive として列挙
- **bash 3.2+ 互換**: `run-*.sh` の ARGUMENTS 修正は文字列連結のみで、`mapfile` などの bash 4+ 機能を使わない
- **Auto-Resolved Ambiguity Points の移動**: Issue #208 body の `## Auto-Resolved Ambiguity Points` セクションは /issue phase で既に解決済みとして記録されており、本 Spec 内では参照のみで重複記載しない
- **docs/workflow.md の更新は不要**: 本変更はフェーズ/ルーティングを変えず、既存フェーズ内部の autonomous 挙動のみを変更するため、docs/workflow.md は対象外

## issue retrospective

### 曖昧点解決の判断根拠

本 Issue は `/auto --batch 5` 実行中に観測された `run-issue.sh` の interactive prompt 停止バグを起点に起票した。初稿作成時点で既に scope と approach をユーザー選択で確定済みだったが、/issue refinement 中の調査で **既存 `code` / `verify` skill には既に `--non-interactive` フラグパターンが存在し、本 Issue の提案 approach と真逆のポリシー（exit with error）を採用している** ことが判明した。

### 主要な方針決定（Q&A）

| 論点 | 選択 | 理由 |
|------|------|------|
| 既存 code/verify との矛盾解消 | 全 skill を auto-resolve に統一 | 完了率優先。batch モードで途中停止させない方針と整合 |
| 対象 skill スコープ | 全 skill に拡張 | 1 Issue で一貫パターン適用。将来の skill 追加時にも統一ルールが使える |
| Step 9 Scope Assessment 等の高負荷判定 | autonomous ではスキップ | sub-issue 分割のような誤判定リスクが大きい操作は skip + 警告、本体処理は継続 |
| sub-issue 分割判断 | 分割なし・単一 L Issue のまま | 同一パターンの横展開で、分割すると整合性が保ちにくい |

### Auto-Resolved 曖昧点

- **検知メカニズム**（env var vs フラグ）: 既存 code/verify skill の `--non-interactive` フラグパターンを踏襲。環境変数は不採用
- **retrospective 記録フォーマット**: 既存 retrospective セクションに `## Autonomous Auto-Resolve Log` サブセクションを追加する形式で統一

### 受入条件変更の理由

初稿の Pre-merge 条件は `file_contains "autonomous"` ベースだったが、調査で既存 skill が `--non-interactive` という具体的なフラグ名を使用していることが判明し、検証条件も `file_contains "non-interactive"` / `file_contains "auto-resolve"` に変更した。これにより既存コードベースとの一貫性を担保できる。

また、wrapper script (`run-issue.sh` / `run-review.sh` / `run-merge.sh`) の変更条件を追加した。これらは現状 `--non-interactive` を付与しておらず、skill 側だけ対応しても実効性がないため。

## spec retrospective

### Minor observations

- skill によって `--non-interactive` の naming 慣習が微妙に異なっていた（merge では `--auto` で代用、code/verify では `--non-interactive` 明示）。この整理は副産物として入る
- tests/run-code.bats と tests/run-spec.bats に既存の `--non-interactive` 検証パターンがあり、新規テスト作成時の参考になる

### Judgment rationale

- Size L 維持: 13ファイルは XL 閾値だが、横展開パターンのため Complexity Adjustment で downgrade 適用
- ambiguity-detector.md への集約: 各 skill の記述を短く保つため、詳細は module に集約し、skill 側では「read `modules/ambiguity-detector.md`」で参照
- merge skill の `--auto` vs `--non-interactive` の整理: delegation は `--auto`（ユーザー向け）、内部フラグは `--non-interactive` に分離

### Uncertainty resolution

- **`--auto` 名称衝突**（merge skill）: Spec では Implementation Step 7 で1つずつ分類する方針とした（Uncertainty セクションに明記）
- **secondary skill の各判定**: Step 9 実装時に文脈評価する方針（Uncertainty セクションに明記）
