# Issue #1089: spec: Steering Docs sync candidate check のゲート条件に modules/ 変更を含める

## Overview

`skills/spec/SKILL.md` Step 10 の Steering Docs sync candidate check ( #1039 で導入) は、ゲート条件が `SKILL.md` と `scripts/` の変更にのみ限定されており、`modules/*.md` のみの変更では発火しない ( #1074 で実測)。加えて、発火した場合の cross-search (grep -rn) 自体の検索対象ディレクトリも `docs/ tests/ scripts/` の3つに限定されており、`modules/` 自体が対象外のため、`modules/` 間の sync 漏れを検出できない ( #1109 で実測)。この2つは独立した原因であり、本 Issue はゲート条件の拡張 (Proposal A) と cross-search 検索対象ディレクトリへの `modules/` 追加 (Proposal C、必須) を両方実施する。

## Reproduction Steps

1. `modules/verify-executor.md` のような SKILL.md 以外の `modules/` ファイルのみを変更する Issue を `/spec` で処理する。
2. Step 10 の Steering Docs sync candidate check のゲート条件 (`Changed Files includes SKILL.md or scripts/`) が発火しない。
3. 結果、変更内容と同じ仕様事項を記述する他ファイル (例: `docs/guide/customization.md`) への sync 漏れが検出されないまま `/spec` が完了する ( #1074 で実測)。
4. ゲートが発火するケース ( `SKILL.md` や `scripts/` を含む変更) でも、cross-search の検索対象ディレクトリが `docs/ tests/ scripts/` のみのため、`modules/` 間の sync 漏れ (別の `modules/*.md` ファイルが同じ仕様事項を古い記述のまま保持) は検出されない ( #1109 で実測: `modules/verify-executor.md` の変更時に `modules/observation-trigger.md` / `modules/verify-classifier.md` の古い記述が見逃された)。

## Root Cause

`skills/spec/SKILL.md` の Steering Docs sync candidate check は、(a) ゲート条件が `SKILL.md`・`scripts/` の変更にのみ限定され `modules/` が対象外、(b) 発火後の cross-search 手順自体の検索対象ディレクトリも `docs/ tests/ scripts/` の3つに限定され `modules/` 自体が含まれない、という2つの独立した制約を持つ。(a) は #1074 (ゲート不発火)、(b) は #1109 (検索対象漏れ) としてそれぞれ別の side effect で顕在化した。

## Changed Files

- `skills/spec/SKILL.md`: Steering Docs sync candidate check のゲート条件 (ヘッダ・本文段落・Skip 条件) を `modules/` を含む形に拡張。keyword 抽出手順 (step 1) に `modules/{name}.md` → keyword `{name}.md` を追加。cross-search (step 2) の検索対象ディレクトリに `modules/` を追加。step 3 のカテゴリ別チェックに `modules/` 項目を追加。Tag/enum semantic extension consumer sweep 内「Differs from adjacent checks」の Steering Docs sync candidate check 説明文を新しい検索範囲に合わせて更新
- `tests/spec.bats`: ゲート条件文言と cross-search 検索対象ディレクトリの拡張を検証する content-assertion test を2件追加

## Implementation Steps

1. `skills/spec/SKILL.md`: Steering Docs sync candidate check のゲート条件ヘッダ・本文段落・Skip 条件を「`SKILL.md`, `modules/`, or `scripts/`」に拡張する (→ acceptance criteria 1, 2, 3)
2. `skills/spec/SKILL.md`: keyword 抽出手順 (step 1) に `modules/{name}.md` → keyword `{name}.md` の行を追加し、cross-search (step 2) のコマンドと説明文に `modules/` を追加し、step 3 のカテゴリ別チェックに `modules/` 項目を追加する (→ acceptance criteria 4)
3. `skills/spec/SKILL.md`: Tag/enum semantic extension consumer sweep セクション内「Differs from adjacent checks」の Steering Docs sync candidate check 説明文を、新しい検索範囲 (`docs/`/`tests/`/`scripts/`/`modules/`) と整合する内容に更新する (→ 一貫性維持のための付随変更、独立した acceptance criteria なし)
4. `tests/spec.bats`: ゲート条件文言 (`SKILL.md, \`modules/\`, or \`scripts/\``) と cross-search 検索対象ディレクトリ (`docs/ tests/ scripts/ modules/`) を検証する content-assertion test を追加し、`bats tests/spec.bats` が通ることを確認する (→ acceptance criteria 5)
5. Issue #1089 本文の Pre-merge acceptance criteria 2番目 (`verify: grep "modules/" "skills/spec/SKILL.md"`) を修正する。実装前から `skills/spec/SKILL.md` に `modules/` という文字列が43箇所既に含まれるため、実装内容に関わらず常時 PASS するパターンだった (`/issue` の triage AC audit コメントで指摘済み)。ステップ1で実装したゲート条件文言に対する `file_contains` チェックに置き換える (→ acceptance criteria 2。本 Spec 作成と同一セッションで Issue body に反映済み)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Steering Docs sync candidate check のゲート条件が、modules/ 配下のファイル変更でも発火するよう拡張されている (modules/ をゲートに追加、またはゲート自体を撤廃して常時実施に変更)" --> ゲート条件が `modules/` 変更をカバーしている
- <!-- verify: file_contains "skills/spec/SKILL.md" "SKILL.md, `modules/`, or `scripts/`" --> Steering Docs sync candidate check のゲート条件文言に `modules/` が拡張されている
- <!-- verify: rubric "skills/spec/SKILL.md の Skip 条件 (Skip if Changed Files does not include ...) が、拡張後のゲート条件と矛盾しない形に更新されている" --> Skip 条件がゲート条件と整合している
- <!-- verify: rubric "skills/spec/SKILL.md の Steering Docs sync candidate check ステップ2 (grep -rn による cross-search) の検索対象ディレクトリリストに modules/ が追加されており、docs/tests/scripts に加えて modules/ 配下のファイルも sync candidate として検出できるようになっている" --> cross-search の検索対象に `modules/` が含まれている
- <!-- verify: rubric "拡張後のゲートで modules/*.md のみを変更する Issue が対象に含まれること、および cross-search が modules/ 配下のファイルも検索対象とすることを検証するテストケースが tests/spec.bats に追加されており、bats 実行が通る" --> テストが追加されている

### Post-merge

- 次回 `modules/*.md` のみを変更する Issue の `/spec` 実行時、Steering Docs sync candidate check が発火し、`modules/` 配下のファイルを含む候補が Changed Files に登録されることを観察 <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **Proposal A vs B の選択**: 本 Spec では Issue 本文が `/spec` に委ねていた「ゲート条件拡張 (Proposal A)」と「ゲート撤廃・常時実施 (Proposal B)」の選択について、**Proposal A** (ゲート条件に `modules/` を追加) を採用した。理由: Issue 本文の実測根拠 ( #1074 , #1109 ) はいずれも「`modules/` がゲート・検索対象の両方で対象外である」ことに起因しており、Proposal B (全 Changed Files で常時実施) が追加でカバーする範囲は実測に基づかない先回りの拡張になる。Issue 自身の Out of Scope が「`skills/` を検索対象に追加する案」を実測なしとして見送った判断 (「実測に基づかない先回りの拡張はしない」) と同じ理由で、ゲート撤廃というより広いスコープの変更も見送った。Proposal C (cross-search 検索対象への `modules/` 追加) は Issue 本文で「A/B の選択とは独立した必須の変更」と明記されており、Proposal A/B いずれを選んでも実施する必要があるため、そのまま実施した。
- **Steering Docs sync candidate check の self-check**: 本 Issue の Changed Files には `skills/spec/SKILL.md` ( SKILL.md ファイル) が含まれるため、拡張前・拡張後いずれのゲート条件でもこのチェック自体が発火する。`grep -n "Steering Docs sync candidate check\|sync candidate" docs/structure.md docs/tech.md docs/workflow.md docs/guide/*.md` を実行したが0件で、この内部手続き自体は Steering Docs 側に記述がないため追加の同期は不要と判断した ( `docs/spec/` 配下の過去 Spec ファイルでの言及は履歴記録のため対象外)。
- **Pre-merge acceptance criteria 2番目の verify command 修正**: `/issue` の triage AC audit コメント (2026-08-10T15:59:26Z) で、既存の `grep "modules/" "skills/spec/SKILL.md"` が実装前から常時 PASS するパターンであると指摘された。ゲート条件 (acceptance criteria 1番目) の実装後文言に対する `file_contains` チェックに置き換え、Issue body に反映済み (本 Spec 作成と同一セッション、Implementation Step 5)。
- **`grep` ではなく `file_contains` を採用**: `modules/verify-executor.md` の "Prefer `file_contains` for fixed strings" ガイドラインに従い、固定文字列マッチには `file_contains` を使用した。検索文字列がバッククォートを含むため、`grep` 型 (ERE 解釈) より `file_contains` (固定文字列マッチ) の方が shell エスケープ・正規表現解釈の懸念を避けられる。
- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ**。Proposal A/B の選択は上記の通り本 Notes で判断根拠を記録した。
- **UI Design Phase 非該当**: 本 Issue は `/spec` skill 自身の内部手続き記述の変更のみであり、UI 要素は一切含まない。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective — #1109 実例の Background 統合、Proposal C の追加、Out of Scope 改訂の経緯説明 / https://github.com/saitoco/wholework/issues/1089#issuecomment-5242671687
- saito / MEMBER / first-class / Triage AC audit — Pre-merge acceptance criteria 2番目の verify command (`grep "modules/" ...`) が常時 PASS パターンである指摘と修復案。本 Spec で修復適用済み ( Implementation Step 5 ) / https://github.com/saitoco/wholework/issues/1089#issuecomment-5242715411
