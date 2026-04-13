# Issue #148: code: verify command 固定文字列の literal 包含ガイドを Step 10 に追加

## Overview

`/code` Step 10 の `section_contains`/`file_contains` FAIL 処理ガイドを更新し、「Spec 由来の固定文字列が実装ファイルに存在しないことによる FAIL」の場合に、hint 書き換えではなく実装ファイルへの literal な文字列追加を第一選択とするよう明示する。

併せて `modules/verify-patterns.md` Section 3 に、`section_contains`/`file_contains` は固定文字列マッチングのため、指定文字列が実装ファイルに literally 含まれている必要があるという核心的な要件を明記する。

背景: Issue #64 の `/code` で `section_contains "skills/verify/SKILL.md" "Step 9" "Issue OPEN"` という verify command を定義したが、実装に "Issue OPEN" が含まれておらず修正コミットが 1 件発生した。現行ガイドでは hint 書き換えが第一選択として例示されており、実装側への追加に誘導されていなかった。

## Changed Files

- `skills/code/SKILL.md`: Step 10 item 2 (FAIL 処理) に「FAIL 原因の判別」ガイドを追加 — "literal string missing" vs "miscalibrated hint" を区別し、前者は実装ファイルへの追加を第一選択とする
- `modules/verify-patterns.md`: Section 3 の冒頭に `section_contains`/`file_contains` の固定文字列 literal 包含要件の注記を追加

## Implementation Steps

1. `skills/code/SKILL.md` の Step 10 item 2 を更新する (→ 受け入れ条件1):
   - 現行: 「FAIL したら hint を書き換える」
   - 変更: FAIL 原因判別の 2 分岐を追加
     - "Spec-derived literal string absent": 実装ファイルへの literal 文字列追加を第一選択
     - "Miscalibrated hint": hint 書き換えを選択
   - 両分岐の example を追加（Issue OPEN 例 と既存の Skill(triage) 例）

2. `modules/verify-patterns.md` Section 3 の冒頭（`### 3. Pre-Check Target File Format (Cross-Referencing)` の直後、`**Cross-Reference Procedure:**` の前）に literal string requirement の注記を追加する (→ 受け入れ条件2):
   - `section_contains`/`file_contains` は fixed-string マッチングであるため、verify command の keyword は実装ファイルに literally 存在する必要があることを明記
   - FAIL の解釈: literal string が不在の場合は hint 書き換えでなく実装への追加が正しい対処であることを補足

## Verification

### Pre-merge
- <!-- verify: section_contains "skills/code/SKILL.md" "### Step 10" "literal" --> `skills/code/SKILL.md` Step 10 に literal string 不在時の実装追加を促すガイドが追加されている
- <!-- verify: section_contains "modules/verify-patterns.md" "### 3." "literal" --> `modules/verify-patterns.md` Section 3 に `section_contains`/`file_contains` の literal 包含要件の注記が追加されている

### Post-merge
- `/code 148` で実装が完了し、Step 10 の FAIL ハンドリングが更新されていることを確認
- `/verify 148` でどちらの verify command も PASS することを確認

## Notes

- 変更は各ファイル 1 箇所ずつのテキスト追加のみ。テスト更新不要（ガイドライン変更であり、スクリプトロジック変更なし）
- ドキュメント更新不要（既存 skill/module の内容変更であり、新規追加/削除なし）
- `section_contains "modules/verify-patterns.md" "### 3." "literal"` の動作: `### 3. Pre-Check Target File Format (Cross-Referencing)` セクションが対象。`### 4.` の前までの範囲に "literal" が含まれていれば PASS

## Code Retrospective

### Deviations from Design
- N/A（Spec の実装ステップに完全に従った）

### Design Gaps/Ambiguities
- `## Code Retrospective` の追記先として Spec は「`## Spec Retrospective` の後」と指示しているが、Spec Retrospective が存在しないケースの処理が明示されていなかった。ファイル末尾に追記することで対処した。

### Rework
- N/A（修正なし、一発で実装完了）

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文に「Auto-Resolved Ambiguity Points」セクションが設けられ、AC2 の対象ファイルが `/issue` 時点で自己決定・記録されていた。Issue 品質は高く、verify command も即座に設計できた。
- 受け入れ条件の verify command (`section_contains "skills/code/SKILL.md" "### Step 10" "literal"`) は実装に "literal" という単語が含まれることを前提としており、実装との整合性が事前に検証可能な設計だった。

#### design
- Spec はシンプルで実装ステップと変更対象ファイルが明確。デザインのずれは発生しなかった。
- `## Code Retrospective` の追記位置（Spec Retrospective が存在しない場合の扱い）が Spec に明示されていなかった点が Code Retrospective で記録済み。次回 Spec 作成時に考慮できる。

#### code
- 実装は一発で完了（rework なし）。Spec の実装ステップに忠実に従った。
- コミット `eae283e` 1 件で 2 ファイルに変更（`skills/code/SKILL.md` +19/-7、`modules/verify-patterns.md` +4）。

#### review
- パッチルート（PR なし）で実装されたため、レビューステップはスキップ。Issue サイズが XS/S 相当で妥当な判断。

#### merge
- 直接 main へコミット（パッチルート）。コンフリクトなし、CI 実行なし（ドキュメント変更のみ）。

#### verify
- 両条件とも PASS。verify command の "literal" というキーワードが実装ファイルに literally 含まれており、Issue #148 自身が解決した問題（literal 包含要件）を自己証明する形になっていた。

### Improvement Proposals
- N/A
