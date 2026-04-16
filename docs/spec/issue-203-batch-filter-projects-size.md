# Issue #203: auto: batch mode filter ignores Projects Size field

## Overview

`/auto --batch N` のBatch Modeフィルタリングが、GitHubラベル (`size/*`) のみを参照してProjects V2フィールドのSizeを確認していない。`get-issue-size.sh` を使用してProjects V2フィールド優先（ラベルはフォールバック）でSizeを取得し、M/L/XL Issueを除外する設計に変更する。

## Reproduction Steps

1. GitHubプロジェクトのSize V2フィールドをM以上に設定したIssue（`size/*` ラベルなし）に `triaged` ラベルを付与する
2. `/auto --batch 1` を実行する
3. Projects V2フィールドにSize M以上が設定されているにも関わらず、ラベルがないためM/L/XL除外フィルタをすり抜け、当該IssueがBatch処理の対象として選ばれる

## Root Cause

`skills/auto/SKILL.md` の Batch Mode "Fetch Batch Candidates" セクションの **Filtering criteria** が、`gh issue list` が返すJSON内の `size/M`・`size/L`・`size/XL` ラベルの有無のみで除外判定している。Projects V2フィールドのSizeはラベルに反映されないため、Projects V2でM以上に設定されたIssueがフィルタをすり抜ける。`get-issue-size.sh` はPhase 1（Projects V2フィールド）→Phase 2（ラベルフォールバック）の優先順でSizeを取得する設計だが、Batch Modeフィルタリングにはこのスクリプトが使用されていない。

## Changed Files

- `skills/auto/SKILL.md`: 以下2箇所を変更
  1. "Fetch Batch Candidates" の `**Filtering criteria**` をMarkdown見出し `### Filtering criteria` に変換し、内容をラベルベースから `get-issue-size.sh` ベースのper-issue Size判定に変更
  2. "Process Each Issue" の triage ステップ（ステップ2）の後に Size 再チェックステップ（ステップ3）を追加し、旧ステップ3を4に繰り下げ

## Implementation Steps

1. `skills/auto/SKILL.md` の "Fetch Batch Candidates" セクションを以下の通り変更する (→ 受け入れ基準1、2、3):
   - `**Filtering criteria** (exclude Issues matching any of these):` の行を `### Filtering criteria` に変換
   - 現在の内容「Issues with `size/M`, `size/L`, or `size/XL` labels (large Issues are excluded from batch)」を削除し、以下に差し替える:
     ```
     For each candidate, call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`;
     exclude Issues where Size is M, L, or XL (Projects V2 field first, label fallback).
     ```
   - "Sort by `createdAt` descending..." の文を `### Filtering criteria` セクションの後（次の見出しの前）に移動し、「Targets: Issues with no Size set, XS, or S」を維持する

2. `skills/auto/SKILL.md` の "Process Each Issue" セクションで、ステップ2（`run-issue.sh` によるtriage）の後に新しいステップ3を追加し、旧ステップ3を4に繰り下げる (→ 受け入れ基準1、2):
   - 追加するステップ3: 「Re-check Size: call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; if Size is M, L, or XL: output a warning and skip to the next Issue (do not abort the entire batch)」

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "get-issue-size.sh" --> `skills/auto/SKILL.md` の Batch Mode セクションに `get-issue-size.sh` を使用した Size 判定が記述されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Mode" "M" --> Batch Mode セクションに M/L/XL 除外ロジックが明記されている
- <!-- verify: section_not_contains "skills/auto/SKILL.md" "Filtering criteria" "labels" --> Filtering criteria がラベルのみに依存する記述になっていない

### Post-merge

- Size が Projects フィールドに M と設定された triaged Issue を含む状態で `/auto --batch 1` を実行し、当該 Issue がスキップされることを確認する (verify-type: opportunistic)

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Notes

**Auto-Resolved Ambiguity Points (from Issue body):**
- **Size未設定の扱い**: 候補に含める（既存設計「Targets: Issues with no Size set, XS, or S」と整合）。triage実行後にSizeがM+になった場合はスキップして次のIssueへ進む
- **実装場所**: `skills/auto/SKILL.md` Batch Modeセクションのテキスト変更のみ。`get-issue-size.sh` は既存スクリプトをそのまま使用
- **パフォーマンス**: 候補ごとに `get-issue-size.sh` を呼ぶパターンは、既存の `gh issue view` per-issueパターンと同等。batch上限200件は実用上問題ない範囲

**`section_not_contains` と `### Filtering criteria` 見出しの関係:**
`section_not_contains "skills/auto/SKILL.md" "Filtering criteria" "labels"` が正しく機能するには、verify-executor が "Filtering criteria" をMarkdown見出し行（`#` で始まる行）として認識できる必要がある。現在の `**Filtering criteria**` はbold textであり見出しではないため、実装ステップ1で `### Filtering criteria` 見出しに変換することが必須。
