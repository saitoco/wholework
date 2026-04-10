# Issue #62: feat: 各フェーズ完了時の次アクション案内を統一

## Overview

全 8 skill（issue, spec, code, review, merge, verify, triage, auto）の完了メッセージを「状況に応じた推奨アクション + 代替選択肢」の統一パターンに揃える。共有モジュール `modules/next-action-guide.md` を新設し、各 skill が「Read して Processing Steps に従う」パターンで参照することで DRY を担保する。

現状は `/spec` のみが ROUTE ベースの 2 択（`/auto` 推奨 + `/code` 手動）を実装済みで、他の skill は次の個別 skill を 1 行で案内するだけ、または `/verify` PASS / `/triage` のように次アクション案内自体が欠如している。本 Issue でこの分散したパターンを `/spec` のリファレンス実装をもとに一般化し、新モジュールに集約する。

## Changed Files

- `modules/next-action-guide.md`: new file（4 セクション構造 Purpose/Input/Processing Steps/Output。Size→Route 判定は `modules/size-workflow-table.md` を参照、skill ごとの推奨/代替テーブルと出力フォーマットを定義）
- `skills/issue/SKILL.md`: `## Completion Report` セクションを書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一（既存の Size=XS のみ `/auto` 案内するロジックを廃止）
- `skills/spec/SKILL.md`: `### Step 18: Completion Message` を書き換え。既存の ROUTE ベース 2 択ロジックを廃止し、`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/code/SKILL.md`: `## Completion Report` セクション（patch / pr 両ルート）を書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/review/SKILL.md`: `## Completion Report` セクションおよび Step 3 の早期終了メッセージを書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/merge/SKILL.md`: `## Completion Report` セクションを書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/verify/SKILL.md`: `Completion report` セクション（Step 13 末尾）を書き換え。PASS 時は完了報告のみ・FAIL 時は修正サイクル案内、`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/triage/SKILL.md`: `### Step 10: Completion Report`（単一実行）と `### Completion Report`（一括実行）を書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `skills/auto/SKILL.md`: `### Step 5: Completion Report` および `### Batch Completion Report` を書き換え。`modules/next-action-guide.md` を Read して Processing Steps に従う形式に統一
- `docs/structure.md`: 23 行目の `modules/             # Shared modules referenced by skills (22 files)` のファイル数を 23 に更新、`### Modules` セクションのキーモジュール一覧に `modules/next-action-guide.md` を追加

## Implementation Steps

**Step 記録ルール:**
- Step 番号は整数のみ
- 8 skill 更新ステップ（Step 2〜9）は新モジュール作成（Step 1）に依存し、相互には独立（並列実行可能）
- 受入基準マッピングを各ステップに付記

1. `modules/next-action-guide.md` を新規作成（→ 受入基準 1, 2, 3, 4, 5, 6）
   - frontmatter なし、共有モジュール標準の 4 セクション構造（`## Purpose` / `## Input` / `## Processing Steps` / `## Output`）
   - `## Purpose`: 各 skill 完了時の次アクション案内を統一フォーマットで生成する目的を記述（"next action" の文言を含める）。呼び出し元 skill 一覧（issue / spec / code / review / merge / verify / triage / auto）も明示
   - `## Input`: 呼び出し元 skill が渡す変数を定義
     - `SKILL_NAME` (string, required): 完了した skill 名（`issue` / `spec` / `code` / `review` / `merge` / `verify` / `triage` / `auto`）
     - `RESULT` (string, optional, default `success`): `success` / `fail` / `blocked` のいずれか
     - `ISSUE_NUMBER` (int, optional): Issue 番号
     - `PR_NUMBER` (int, optional): PR 番号
     - `SIZE` (string, optional): `XS` / `S` / `M` / `L` / `XL` / 空文字
     - `ROUTE` (string, optional): `patch` / `pr` / `sub_issue` のいずれか（省略時は SIZE から `modules/size-workflow-table.md` のマッピングで導出）
     - `BLOCKED_BY_OPEN` (bool, optional, default false): 未解決の blocked-by 関係があるか
   - `## Processing Steps`: LLM が文脈理解に基づき判定する Q&A 風ガイダンス
     - Step 1. RESULT 判定: `success` / `fail` / `blocked` で分岐（ブロック時はブロッカー解消後の案内のみ）
     - Step 2. SIZE→ROUTE 導出: `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` を参照（SIZE 未指定時は ROUTE のみで判定）
     - Step 3. SKILL_NAME ごとの推奨アクションと代替アクションを以下の判定テーブルで決定（ルール羅列ではなく LLM 文脈理解に委ねる旨を明記）

       | SKILL_NAME | RESULT | 状況 | 推奨 | 代替 |
       |------------|--------|------|------|------|
       | `triage` | success | (任意) | `/issue {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `issue` | success | XS/S かつ受入基準明確 | `/auto {ISSUE_NUMBER}` | `/spec {ISSUE_NUMBER}` |
       | `issue` | success | M/L | `/spec {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `issue` | success | XL（sub-issue 分割推奨） | `/issue {ISSUE_NUMBER}` (split) | — |
       | `spec` | success | patch (XS/S) | `/auto {ISSUE_NUMBER}` | `/code {ISSUE_NUMBER}` |
       | `spec` | success | pr (M, light) | `/auto {ISSUE_NUMBER}` | `/code {ISSUE_NUMBER}` |
       | `spec` | success | pr (L, full) | `/auto {ISSUE_NUMBER}` | `/code {ISSUE_NUMBER}` |
       | `spec` | success | sub_issue (XL) | `/issue {ISSUE_NUMBER}` (split) | — |
       | `code` | success | patch | `/verify {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `code` | success | pr | `/review {PR_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `review` | success | (任意) | `/merge {PR_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `merge` | success | (任意) | `/verify {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `verify` | success (PASS) | (任意) | （案内なし） | — |
       | `verify` | fail | (任意) | `/code {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}` |
       | `auto` | success | (任意) | （案内なし） | — |
       | `auto` | fail | (任意) | `/code {ISSUE_NUMBER}` | 手動調査 |

     - Step 4. blocked-by Issue がある場合の特別処理（推奨提示せずブロッカー解消を案内）
   - `## Output`: ターミナル出力の統一フォーマット（日本語、CLAUDE.md 準拠）
     - 推奨ありパターン:
       ```
       次のアクション:
       - **`{推奨コマンド}`** （推奨） — {理由 1 行}
       - `{代替コマンド}` — {代替の用途 1 行}
       ```
     - 案内なしパターン: 何も出力しない（PASS 完了報告のみ）
     - blocked パターン: ブロッカー Issue の解消後の案内のみを表示

2. `skills/issue/SKILL.md` の `## Completion Report` セクション（388〜398 行目）を書き換え（→ 受入基準 7）
   - 既存の Size=XS のみ `/auto` 案内 / 他は `/spec` のみ案内するロジックを廃止
   - `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=issue, ISSUE_NUMBER=$NUMBER, SIZE={fetched size}, RESULT={success|blocked}` の形式で参照指示を記述
   - XL の sub-issue 分割パスでは sub-issue 一覧表示の既存ロジックを保持し、その後ろで `next-action-guide.md` を参照
   - opportunistic 検証受入基準: `/issue N` 実行時に推奨/代替フォーマットで案内が表示される

3. `skills/spec/SKILL.md` の `### Step 18: Completion Message` セクション（607〜660 行目）を書き換え（→ 受入基準 8）
   - 既存の ROUTE ベース 2 択ロジック（patch/pr light/pr full/sub_issue/blocked の 5 パターン）を全廃
   - `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=spec, ISSUE_NUMBER=$NUMBER, ROUTE=$ROUTE, SIZE={fetched}, RESULT=success, BLOCKED_BY_OPEN=$HAS_OPEN_BLOCKING` の形式で参照指示を記述
   - 「Spec created, committed, pushed, and Issue comment posted.」の固定 prefix を残し、その後に `next-action-guide.md` の出力を挿入する旨を明示

4. `skills/code/SKILL.md` の `## Completion Report` セクション（368〜372 行目）を書き換え（→ 受入基準 9）
   - 既存の patch / pr 別固定文言を廃止
   - `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=code, ISSUE_NUMBER=$NUMBER, PR_NUMBER={if pr route}, ROUTE={patch|pr}, RESULT=success` の形式で参照指示を記述
   - patch ルート完了の固定 prefix（commit/push 完了報告）と pr ルート完了の固定 prefix（PR 作成完了報告）は保持

5. `skills/review/SKILL.md` の `## Completion Report` セクション（710〜730 行目）と Step 3 の早期終了メッセージ（108〜111 行目）を書き換え（→ 受入基準 10）
   - メイン Completion Report: `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=review, PR_NUMBER=$NUMBER, ISSUE_NUMBER=$ISSUE_NUMBER, RESULT=success` の形式で参照指示を記述
   - Step 3 早期終了（patch ルートでレビュー不要）も同パターンで `SKILL_NAME=review, RESULT=success` を指定し、`/merge` 推奨 + `/auto` 代替を出力させる
   - 既存の `"need to run a review explicitly"` / `"main branch protection"` 言及はそのまま保持（#51 で grep 対象になっている、Risk Notes 参照）
   - review-only モード完了メッセージは独自のため変更対象外

6. `skills/merge/SKILL.md` の `## Completion Report` セクション（201〜211 行目）を書き換え（→ 受入基準 11）
   - 既存の固定文言「Merge complete. Run `/verify {Issue number}` next.」を廃止
   - Issue 番号抽出ロジックは保持（PR body / title 検索）
   - `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=merge, ISSUE_NUMBER=$ISSUE_NUMBER, RESULT=success` の形式で参照指示を記述

7. `skills/verify/SKILL.md` の `Completion report` セクション（Step 13 末尾、423〜426 行目）を書き換え（→ 受入基準 12）
   - PASS 時の固定文言（"Acceptance test complete. Issue #$NUMBER is closed."）と FAIL 時（"Acceptance test found unchecked conditions. Issue #$NUMBER has been reopened."）の prefix は保持
   - `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=verify, ISSUE_NUMBER=$NUMBER, RESULT={success|fail}` の形式で参照指示を末尾に追加
   - PASS 時は `RESULT=success` で「案内なし」、FAIL 時は `RESULT=fail` で `/code` 推奨 + `/auto` 代替が出力される

8. `skills/triage/SKILL.md` の `### Step 10: Completion Report`（単一実行、224〜239 行目）と `### Completion Report`（一括実行、372〜384 行目）を書き換え（→ 受入基準 13）
   - 単一実行: 既存の Triage Result サマリ表は保持し、その後ろに `Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=triage, ISSUE_NUMBER=$NUMBER, SIZE={triaged size}, RESULT=success` の参照指示を追加
   - 一括実行: 既存の Bulk Triage Results 表は保持し、その後ろに同パターンの参照指示を追加（一括実行では複数 Issue が対象なので案内対象を 1 件選ぶ or 表示省略する旨を `next-action-guide.md` の Processing Steps で吸収）。**判断:** 一括実行では案内対象 Issue を特定できないため、参照指示で `RESULT=success` のみ渡して module 側で「一括完了の場合は案内省略 or 代表 Issue を提示」を判定させる

9. `skills/auto/SKILL.md` の `### Step 5: Completion Report`（247〜249 行目）と `### Batch Completion Report`（285〜287 行目）を書き換え（→ 受入基準 14）
   - Step 5（単一 Issue 完了）: 既存の "report completion" を維持しつつ、`Read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section. SKILL_NAME=auto, ISSUE_NUMBER=$NUMBER, RESULT={success|fail}` の参照指示を追加。Step 6（On Failure）も同様に `RESULT=fail` で参照
   - Batch Completion Report: 一括処理結果表の後ろに同パターンの参照指示を追加（`SKILL_NAME=auto, RESULT=success`、ISSUE_NUMBER は省略 / バッチ完了向けに module で「案内省略」を選ぶ）

10. `docs/structure.md` を更新し validate-skill-syntax を実行（→ 受入基準 15, 16）
    - 23 行目: `├── modules/             # Shared modules referenced by skills (22 files)` → `(23 files)` に変更
    - `### Modules` セクション（60〜83 行目）のキーモジュール一覧に `- modules/next-action-guide.md — unified next action guidance for all skills` を追加（既存の英語短説明スタイルに合わせる）
    - 全変更完了後 `python3 scripts/validate-skill-syntax.py skills/` を実行し 0 errors を確認

## Alternatives Considered

- **個別 skill にロジック展開（モジュール化しない）**: 各 SKILL.md の Completion Report に同じ判定テーブルを直書きする案。却下理由は (1) DRY 違反、(2) 判定ルール変更時に 8 ファイル更新が必要、(3) 既存の `/spec` リファレンス実装の二重保守になるため。Issue 本文の Design Decisions で「shared module 化」が明示されているため本案を採用。
- **判定ロジックをスクリプト化（`scripts/next-action-guide.sh`）**: bash で判定して文字列出力する案。却下理由は (1) LLM の文脈理解（受入基準明確性、ブロッカー有無、Size 推定など）を活かせない、(2) Issue 本文「Auto-Resolved Ambiguity Points」で「ルールテーブルではなく LLM の文脈理解に委ねる」と明示されている、(3) 既存モジュールパターンと一貫しない。

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/next-action-guide.md" --> `modules/next-action-guide.md` が新規作成されている
- <!-- verify: section_contains "modules/next-action-guide.md" "## Purpose" "next action" --> モジュールに `## Purpose` セクションがあり次アクション案内の目的が記述されている
- <!-- verify: grep "## Input" "modules/next-action-guide.md" --> モジュールに `## Input` セクション（呼び出し元からの入力仕様）がある
- <!-- verify: grep "## Processing Steps" "modules/next-action-guide.md" --> モジュールに `## Processing Steps` セクション（状況別の判断ロジック）がある
- <!-- verify: grep "## Output" "modules/next-action-guide.md" --> モジュールに `## Output` セクション（出力フォーマット定義）がある
- <!-- verify: grep "size-workflow-table" "modules/next-action-guide.md" --> Size→Route 判定に `modules/size-workflow-table.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/issue/SKILL.md" --> `/issue` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/spec/SKILL.md" --> `/spec` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/code/SKILL.md" --> `/code` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/review/SKILL.md" --> `/review` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/merge/SKILL.md" --> `/merge` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/verify/SKILL.md" --> `/verify` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/triage/SKILL.md" --> `/triage` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide" "skills/auto/SKILL.md" --> `/auto` SKILL.md が `modules/next-action-guide.md` を参照している
- <!-- verify: grep "next-action-guide.md" "docs/structure.md" --> `docs/structure.md` のモジュール一覧に新規モジュールが追加されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> `validate-skill-syntax.py` が 0 errors で通る

### Post-merge

- `/issue N` 実行時に「`/auto` 推奨（条件付き）+ `/spec` 代替」のフォーマットで案内が表示される（opportunistic）
- `/code N` 実行時に「次の個別 skill + `/auto` 代替」のフォーマットで案内が表示される（opportunistic）
- `/review N`、`/merge N` も同様の統一パターンで案内される（opportunistic）
- `/verify N` FAIL 時に修正サイクル（`/code` / `/auto`）が案内される。PASS 時は完了報告のみで次アクション案内はしない（opportunistic）
- `/triage N` 実行時に `/issue` 推奨 + `/auto` 代替の案内が表示される（opportunistic）

## Tool Dependencies

新規ツール権限の追加は不要。`Read` / `Edit` / `Write` / `Bash(python3:*)` は全 skill ですでに allowed-tools に含まれており、本変更で参照する tool はすべて既存と同じ。

### Bash Command Patterns
- なし（新規追加なし）

### Built-in Tools
- なし（新規追加なし）

### MCP Tools
- なし

## Uncertainty

特になし。Issue 本文で曖昧点はすべて auto-resolve 済み（推奨ロジック方式 = LLM 文脈理解、`/triage` 次アクション = `/issue` 推奨 + `/auto` 代替）。

## Notes

- **出力言語の選定**: `next-action-guide.md` の Output フォーマットは日本語で統一する。理由は (1) Issue 本文の期待出力例が日本語、(2) `~/.claude/CLAUDE.md` および wholework `CLAUDE.md` で「Skill output (terminal): Japanese」と明示、(3) ユーザー向けターミナル出力は日本語優先のグローバル方針。なお SKILL.md / module 本体（LLM 向け処理指示）は英語で記述する（リポジトリ規約「Source code: English / Documentation: English」に従う）。
- **`/spec` のリファレンス実装**: 既存の `### Step 18: Completion Message`（607〜660 行目）が新モジュールの設計起点となる。新モジュールは `/spec` の ROUTE × blocked × Size 分岐パターンを 8 skill 共通フォーマットに一般化したもの。本 Issue 完了後は `/spec` 自身もモジュール参照に切り替える（既存の固定文言は廃止）。
- **`/auto` および `/verify` の PASS 時案内省略**: Issue 本文の Design Decisions「`/verify` の次アクション: PASS 時は完了報告のみ。FAIL 時のみ修正サイクル」に従い、ワークフロー終端で次アクション案内を出さない設計。`/auto` も同じく PASS 時は案内なし（修正サイクル開始は FAIL 時のみ）。受入基準「PASS 時は完了報告のみ」と矛盾しないように `next-action-guide.md` の判定テーブルで明示する。
- **`/triage` 一括実行・`/auto --batch` 完了時**: 案内対象 Issue を 1 件に特定できないため、`next-action-guide.md` の Processing Steps で「一括完了 (`ISSUE_NUMBER` 未指定 + 複数件結果) の場合は案内省略」を判定させる。`SKILL_NAME=triage` / `SKILL_NAME=auto` で `ISSUE_NUMBER` を渡さない呼び出しが該当。
- **`docs/ja/structure.md` の同期**: 翻訳ドキュメント `docs/ja/structure.md`（16 行目「22 ファイル」、52〜75 行目モジュール一覧）も同様の更新が必要だが、`/doc translate ja` で再生成される auto-generated ファイルのため本 Issue では更新対象外。後続の `/doc translate ja` 実行時に自動同期される。
- **Risk Note (Issue body より)**: `docs/spec/issue-51-review-early-exit-pr-hint.md` に `/review` 早期終了メッセージ文言を grep する受入ヒントが 3 件存在（`"need to run a review explicitly"`, `"/review $PR_NUMBER --light"`, `"main branch protection"`）。#51 は CLOSED 済みだが、本 Issue で `/review` の早期終了メッセージを書き換える際は該当文言を保持する。新モジュール参照を追加しても既存 grep 対象文字列は削除しない。
- **Risk Note (Spec Changed Files 漏れ)**: #58 / #72 で繰り返し発生した失敗パターン（横断的変更の Spec 変更対象ファイル列挙漏れ）を予防するため、Spec 作成段階で `grep -rn 'Completion Report\|Completion report\|Next:' skills/` で全該当箇所を網羅確認済み。8 skill すべての Completion Report 位置を Implementation Steps に明記。
- **Risk Note (verify ヒント偽陽性)**: 8 skill すべてで `grep "next-action-guide"` を使うが、`next-action-guide` は新規文字列で既存と衝突しないことを `grep -r "next-action-guide" .` で確認済み（0 件）。偽陽性リスクなし。
- **Auto-Resolved Ambiguity Points (Issue body より転記)**:

  | 項目 | 解決内容 | 根拠 |
  |------|---------|------|
  | 推奨ロジックの方式 | ルールテーブルではなく LLM の文脈理解に委ねる | Issue 本文の例文から「状況に応じて推奨」が求められている。ルール化すると文脈理解の柔軟性が失われる |
  | `/triage` の次アクション | `/issue {N}` 推奨 + `/auto {N}` 代替 | 既存の /issue triage-auto-chain パターン（triage → issue → ready）から一意推論 |

- **モジュール標準構造**: 新規モジュール `next-action-guide.md` は `worktree-lifecycle.md` などの 4 セクション（Purpose / Input / Processing Steps / Output）を踏襲する。`docs/tech.md` の Coding Conventions「新規コンポーネントの入力インターフェース」に準拠。
- **Read 指示の書式**: 抽出されたモジュール参照は `read ${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md and follow the "Processing Steps" section` 形式で記述する（#716 のパターン、tech.md 準拠）。

## Code Retrospective

### Deviations from Design

- なし。Spec の Implementation Steps に記載された順序・内容通りに実装完了。Step 1（モジュール作成）→ Step 2〜9（8 skill 更新、並列実施）→ Step 10（docs/structure.md 更新）の順序を維持。

### Design Gaps/Ambiguities

- `skills/review/SKILL.md` の早期終了（XS/S patch route）メッセージ箇所は Spec で「108〜111 行目」と記載されていたが、実際は 104〜111 行目が該当ブロック。行番号のズレは軽微で内容は一致しており問題なし。
- Spec で「既存の `"need to run a review explicitly"` / `"main branch protection"` 言及はそのまま保持」と指示されていた通り、既存文言を削除せずに `next-action-guide.md` 参照指示を後ろに追加する形で実装した。

### Rework

- なし。各 SKILL.md の Completion Report セクションを 1 回で確定できた。バリデーションも 0 errors で一発通過。

## spec retrospective

- **Spec 作成の所感**: 8 skill の Completion Report セクションを Grep で一括特定し、各セクションの出力パターンを比較することで、統一モジュールに必要な入力インターフェース（SKILL_NAME / RESULT / ISSUE_NUMBER / PR_NUMBER / SIZE / ROUTE / BLOCKED_BY_OPEN）を抽出できた。`/spec` Step 18 の ROUTE ベース 2 択ロジックが既存の参照実装として機能しており、そこから一般化する形で設計できた。
- **曖昧性の解決**: Issue body に既存の "Auto-Resolved Ambiguity Points" セクションがあったため、推奨ロジック方式（LLM 文脈理解）と `/triage` の次アクション（`/issue` 推奨）は追加質問なしで確定できた。`--non-interactive` モードと整合。
- **スコープ確定のポイント**: `docs/ja/structure.md` は `/doc translate` で自動生成されるため対象外、`docs/structure.md` の Modules セクションとカウント (22 → 23) のみが更新対象であることを特定した。これにより対象ファイルを 10 件に確定。
- **想定リスク**: `/verify` および `/auto --batch` での PASS 時の次アクション案内抑制ルールをモジュール側で扱う必要があり、判定テーブルで `RESULT=success AND SKILL_NAME IN (verify, auto-batch)` のケースを明示する必要がある。実装時に見落とすと「何もしない」動作が崩れる。
- **検証計画**: 16 件の pre-merge acceptance check と 5 件の post-merge acceptance check で、モジュール作成・8 skill 更新・structure.md 同期を網羅。`grep` と `section_contains` で機械的に検証可能にした。
