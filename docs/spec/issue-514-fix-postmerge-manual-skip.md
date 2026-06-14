# Issue #514: code: post-merge manual 検証対象 Step の実装スキップを防止

## Overview

`/auto` の code phase が Spec の Implementation Steps のうち post-merge manual 検証に対応するステップを「実装対象外」と誤解してスキップし、PR 作成後に実装漏れが発覚する事象を防止する。

2 点の修正を行う（defense in depth）：
1. `skills/code/SKILL.md` Step 8 に、全 Implementation Steps（post-merge manual 含む）の実装義務を明示するガードテキストを追加する
2. `skills/spec/SKILL.md` の Step recording rules に、post-merge manual AC に対応するステップも当該 PR で実装必須である旨のガイダンスを追加する

## Reproduction Steps

1. post-merge manual 検証を含む AC を持つ Issue を `/auto` で実行
2. code phase が post-merge manual 対象の Implementation Steps をスキップして PR を作成
3. verify phase で実装漏れが判明

## Root Cause

`skills/code/SKILL.md` Step 8 が `Implement the code following the "Implementation Steps" in the Spec.` とのみ記述しており、post-merge manual verify-type を持つ AC に対応するステップも実装が必須であることを明示していない。code phase が「post-merge manual ＝ 実装対象外」と誤解する余地がある。

## Changed Files

- `skills/code/SKILL.md`: Step 8 冒頭に post-merge manual ステップの実装義務を明示するガードテキストを追加 — bash 3.2+ 非依存（テキスト追加のみ）
- `skills/spec/SKILL.md`: `## Implementation Steps` の Step recording rules に post-merge manual 実装義務ガイダンスを追加 — bash 3.2+ 非依存（テキスト追加のみ）

## Implementation Steps

1. `skills/code/SKILL.md` の `### Step 8: Implement` セクションにて、`Implement the code following the "Implementation Steps" in the Spec.` 行の直後（`- Use TaskCreate/TaskUpdate` の前）に、post-merge manual を含む全 Implementation Steps が実装必須であることを明示するガードテキストを追加する（→ AC1）
2. `skills/spec/SKILL.md` のテンプレート内 `**Step recording rules:**` ブロックにて、`- **Acceptance criteria mapping**: ...` の行の直後に、post-merge manual AC に対応するステップも当該 PR での実装が必須であることを明示するガイダンス bullet を追加する（after 1）（→ AC2）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の ### Step 8: Implement セクションに、post-merge manual verify-type を持つ Implementation Steps であっても実装を省略できないことを明示する文言が追加されており、post-merge manual は検証方法を指し実装要否とは無関係であることが説明されている" --> `skills/code/SKILL.md` Step 8 に、post-merge manual 含む全 Implementation Steps の実装義務を明示するガードテキストが追加される <!-- verify: file_contains "skills/code/SKILL.md" "post-merge manual" -->
- <!-- verify: rubric "skills/spec/SKILL.md の Implementation Steps 記録ルール（Step recording rules）セクションに、AC の verify-type が post-merge manual であっても対応する実装ステップは当該 PR で必須であることを明示するガイダンスが追加されている" --> `skills/spec/SKILL.md` の Implementation Steps 記録ルールに、post-merge manual ステップの実装義務を示すガイダンスが追加される <!-- verify: file_contains "skills/spec/SKILL.md" "post-merge manual" -->

### Post-merge

- `/auto` で post-merge manual AC を含む Issue を実行した際、対応する Implementation Steps がすべて実装されていることが確認できる <!-- verify-type: observation event=auto-run -->

## Notes

- review 側の強化（spec-deviation 検出）は本 Issue のスコープ外
- ガードテキストは SKILL.md body 内に追加するため、半角 `!` は使用しない（CLAUDE.md の Forbidden Expression）
- `skills/spec/SKILL.md` の `**Step recording rules:**` ブロックは SPEC_DEPTH=full テンプレート（2 箇所）と SPEC_DEPTH=light テンプレートの計 3 箇所あるが、実際の Spec 生成で使われるのはテンプレートの `## Implementation Steps` 節の直下のブロック（full テンプレートは line 498 付近、light テンプレートは別途）。両テンプレートに共通のルールとして追加する方が漏れがない。調査結果: SKILL.md の `**Step recording rules:**` は full テンプレート本文に 1 箇所（line 498 付近）、light テンプレートには記録ルールの記述がないため、full テンプレートの Step recording rules のみに追加する。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- Spec Notes の調査結果（`**Step recording rules:**` が full テンプレートの 1 箇所のみ）が正確であり、light テンプレートには記録ルールがなかったため追加不要と判断できた。追加の調査コストなしに Spec を信頼して実装できた。

### Rework
- None

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- REVIEW_DEPTH=light（Issue Size=M および --light フラグ）で review-light 軽量統合レビューを実施
- 外部レビューツール（Copilot/Claude Code Review/CodeRabbit）は無効設定のため全て省略
- 全4観点（Spec 逸脱・エッジケース・セキュリティ・ドキュメント整合性）で問題なし、MUST 課題ゼロ

### Deferred Items
- Post-merge AC（`observation event=auto-run`）: `/auto` で post-merge manual AC を含む Issue を実行した際の観察による確認。verify phase での対応事項
- review 側強化（spec-deviation 検出で post-merge manual 項目の実装漏れを MUST 検出）は本 Issue スコープ外。別 Issue 対応

### Notes for Next Phase
- 課題なし、CI 全 SUCCESS のため `/merge 633` で即座にマージ可
- Post-merge AC（observation: event=auto-run）は merge 後の `/auto` 実行で確認
- 変更はテキスト追加のみであり、マージ後のリグレッションリスクは低い

## review retrospective

### Spec vs. 実装の乖離パターン

特記なし。Spec の Implementation Steps 2 件と PR diff が 1:1 で対応しており、乖離は検出されなかった。テキスト追加のみの変更であり、乖離が生じにくい性質の PR だった。

### 繰り返し課題

特記なし。Spec のスコープ（2 ファイルへのテキスト追加）に対して PR が過不足なく対応しており、同種の課題は見当たらない。

### 受け入れ条件検証の困難さ

特記なし。全 pre-merge AC が `rubric` + `file_contains` の組み合わせで検証可能であり、UNCERTAIN 件数はゼロだった。Post-merge AC は `observation: event=auto-run` 型であり、verify phase での確認が必要だが、これは設計上の意図である。
