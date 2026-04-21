# Issue #297: /code の validate-skill-syntax.py 実行を存在 gate で囲む (Phase 1 Sub 1A)

## Overview

`skills/code/SKILL.md` Step 9 末尾の "Additional validation" サブステップが、`scripts/validate-skill-syntax.py` の存在チェックなしに無条件で実行される。非 skill-dev プロジェクトではこのスクリプトも `skills/` ディレクトリも存在しないため、`/code` 実行時に毎回エラーとなる。

このサブステップを `scripts/validate-skill-syntax.py` の存在チェック内に移動し、ファイルが存在しない場合はサブステップ全体を skip するよう修正する。既存の wholework リポ（skill-dev プロジェクト）では従来通り validate が実行される。

## Changed Files

- `skills/code/SKILL.md`: Step 9 の "Additional validation" サブステップ（237-245行）を `scripts/validate-skill-syntax.py` 存在チェックで囲む — bash 3.2+ 非該当（シェルスクリプト変更なし）

## Implementation Steps

1. `skills/code/SKILL.md` の `**Additional validation (run after tests):**` ブロックを編集する。"After tests complete, run skill syntax validation locally:" という書き出しを、`scripts/validate-skill-syntax.py` が存在する場合のみ実行する条件分岐に書き換える。存在しない場合はサブステップ全体を skip することを明示する。（→ 受け入れ基準 1, 2）

   変更イメージ（現在 → 変更後）:
   - 現在: `After tests complete, run skill syntax validation locally:`
   - 変更後: `If \`scripts/validate-skill-syntax.py\` exists, run skill syntax validation locally: ... If the file does not exist, skip this sub-step.`

## Verification

### Pre-merge

- <!-- verify: grep "validate-skill-syntax.py" "skills/code/SKILL.md" --> validate 呼び出しが SKILL.md に残っている
- <!-- verify: rubric "In skills/code/SKILL.md, the 'Additional validation' subsection that invokes python3 scripts/validate-skill-syntax.py is wrapped in an explicit existence condition for scripts/validate-skill-syntax.py, and the SKILL.md text makes clear that the step is skipped when the file is absent" --> 存在 gate 条件が明示的に記述されている

### Post-merge

- wholework リポ自身で `/code` を実行し、validate が従来通り実行されることを確認 <!-- verify-type: manual -->
- `scripts/validate-skill-syntax.py` が存在しないプロジェクトで `/code` を実行し、このサブステップが skip されることを確認 <!-- verify-type: manual -->

## Notes

なし

## Code Retrospective

### Deviations from Design

- 変更イメージの「If the file does not exist, skip this sub-step.」という末尾表現の代わりに、先頭に「If `scripts/validate-skill-syntax.py` does not exist, skip this subsection entirely.」を配置した。条件の否定（存在しない場合のskip）を先に明示する方が読み手にとって明確なため。

### Design Gaps/Ambiguities

- なし

### Rework

- なし

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は `grep` と `rubric` による自動検証が可能な明確な形式で記述されており、品質は高い。ポストマージ条件も `<!-- verify-type: manual -->` で適切に分類されている。

#### design
- 変更対象ファイルと実装イメージが具体的で、実際の実装と概ね一致。Code Retrospective に記載の通り、「否定条件を先頭に配置する」という小さな改善が加えられたが、仕様の意図は完全に満たされている。

#### code
- リワークなし。コミット `2b0b298` で1コミットにクリーンに実装された。設計からの逸脱は「先頭に否定条件を置く」という読みやすさ向上のための意図的な変更であり、問題なし。

#### review
- パッチルート（main 直コミット）のため PR レビューなし。変更が1行追加と1行変更の小規模修正であり、パッチルートの判断は適切。

#### merge
- パッチルートでの直接コミット。コンフリクトなし、CI 失敗なし。クリーンなマージ。

#### verify
- 全自動検証対象条件（2件）が PASS。`grep` と `rubric` コマンドが期待通りに動作した。ポストマージ manual 条件（2件）はユーザー確認が必要だが、受け入れ基準の性質上適切な分類。

### Improvement Proposals
- N/A
