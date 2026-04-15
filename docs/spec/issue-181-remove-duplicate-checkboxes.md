# Issue #181: verify: 受け入れテスト結果コメントから Issue 本文と重複するチェックボックスを削除

## Overview

`/verify` が Issue に投稿する「受け入れテスト結果」コメントで、`verify-type: manual` / `opportunistic` の post-merge 条件が `- [ ]` チェックボックス形式で再掲される問題を修正する。

Issue 本文を SSoT（Single Source of Truth）とし、コメントは「実行ログ・ユーザー確認手順ガイド」の役割に限定する。具体的には `skills/verify/SKILL.md` の Step 7 にコメント本文フォーマット定義を追加し、チェックボックス再掲を明示的に禁止する。

## Changed Files

- `skills/verify/SKILL.md`: Step 7 にコメント本文フォーマット定義を追加（"Verification steps" ガイド形式 + チェックボックス重複禁止指示）

## Implementation Steps

1. `skills/verify/SKILL.md` の `### Step 7: Post Comment on Issue` 見出しの直後（"Write body to..." の前）に、コメント本文フォーマット定義ブロックを追加する (→ 受け入れ基準 1, 2, 3)

   追加する内容:
   - **コメント本文フォーマット定義**（Markdown コードフェンス付きテンプレート）:
     - `## Acceptance Test Results` ヘッダ
     - `### Auto Verification` セクション（自動検証結果表）
     - `### Items Requiring User Verification` セクション（手動確認項目ガイド形式）
       - `Verification steps:` リスト
       - `Success criteria:` 行
   - **禁止指示**（フォーマット定義の前または後）:
     - 「チェックボックス形式をコメントに含めないこと」の明示
     - 「Issue 本文のチェックボックスを duplicate しないこと（Issue 本文が SSoT; コメントのチェックボックスは永続化されない）」の明示
   - **注意**: 禁止指示の文中に `- [ ]` リテラルを含めてはならない（`section_not_contains` 検証のため、「チェックボックス」「checkbox format」等の表現を使用）

## Verification

### Pre-merge

- <!-- verify: section_not_contains "skills/verify/SKILL.md" "Step 7: Post Comment on Issue" "- [ ]" --> `skills/verify/SKILL.md` の `Step 7: Post Comment on Issue` セクションにチェックボックスリスト構文 `- [ ]` が含まれていない
- <!-- verify: file_contains "skills/verify/SKILL.md" "duplicate" --> `skills/verify/SKILL.md` にコメント本文で本文チェックボックスを重複させない旨の指示が明文化されている（英語: `duplicate` / `do not include checkbox` 等のキーワードで検証）
- <!-- verify: section_contains "skills/verify/SKILL.md" "Step 7: Post Comment on Issue" "Verification steps" --> コメント本文フォーマットに「検証手順」（Verification steps）を含む手動確認項目ガイド形式が明示的に定義されている

### Post-merge

- 本 Issue 以降に `/verify` を実行した際、投稿されるコメントに `verify-type: manual` / `opportunistic` 条件のチェックボックスが含まれていないことを実例で確認する
- 同コメントに自動検証の結果表と手動確認の手順ガイド（Verification steps / Success criteria）は引き続き含まれていることを実例で確認する

## Notes

- `file_contains "duplicate"` は現状の SKILL.md でも lines 451, 477（改善提案の重複排除処理）で既に PASS するが、コメント本文禁止の文脈で Step 7 に "duplicate" を明示することで意図を明確化する
- Step 8 (Output Summary to Terminal) は同様の "Verification steps" ガイド形式をすでに定義しており、Step 7 と同じ書式にそろえる形となる
- 追加するフォーマット定義のコードフェンス内にも `- [ ]` を含めないこと（section_not_contains はコードフェンス内も検索対象となるため）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- Spec の Notes に「コードフェンス内にも `- [ ]` を含めないこと」とある通り、実装ではテーブル記号をシンプルな PASS/FAIL/UNCERTAIN/SKIPPED テキストに置き換えることで対応した（絵文字 ✅/❌ もコードフェンス内では問題ないが、Step 8 との書式統一のため省略した）

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の構造（Background/Purpose/Acceptance Criteria）が明確で、Issue Refinement Retrospective に曖昧性解消の根拠が文書化されており品質が高い
- Pre-merge 条件に `section_not_contains` / `section_contains` / `file_contains` の組み合わせを採用し、「チェックボックスが無い」+「手順ガイドが残っている」の両面を機械検証する設計は適切
- Spec の Notes 欄で「コードフェンス内にも `- [ ]` を含めないこと」という実装上の注意点を先取りしており、実装者の混乱を防いだ

#### design
- 変更対象が `skills/verify/SKILL.md` Step 7 の1箇所に限定されており、最小変更の設計
- 実装ステップに「禁止指示の文中に `- [ ]` リテラルを含めてはならない」という制約を明記し、section_not_contains 検証との整合性を保った点は巧みな設計

#### code
- fixup/amendなし。1コミットで完了（Design commit + Implementation commit + Code Retrospective commit の3コミット）
- コードフェンス内の記法選択（絵文字 ✅/❌ を省略しテキスト表記に統一）という小さな創造的決定があったが、Spec との逸脱は最小限

#### review
- patch routeのため PRレビューは実施されず。`/review` は未実行
- Specレビューは Issue Refinement Retrospective と Design Complete コメントに記録されている

#### merge
- patch routeで main に直接コミット。コンフリクトなし、CI問題なし

#### verify
- 3つのpre-merge条件がすべて1回でPASS。verify commandの設計精度が高く再実行不要
- post-merge条件（manual）は実例確認が必要で適切にユーザー検証ガイドとして提示
- 本verifyの実行コメントが「#181の実例」として post-merge 条件の実例確認に使えるという皮肉な構造がある（コメント自体に `- [ ]` が含まれていないことを確認できる）

### Improvement Proposals
- N/A
