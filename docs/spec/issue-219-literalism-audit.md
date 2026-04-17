# Issue #219: SKILL.md の暗黙的一般化パターンを監査して明示化 (literalism 対応)

## Overview

Claude Opus 4.7 はプロンプトをより literal に解釈するため、既存の SKILL.md / modules の
「類似ファイルにも同じ処理を」「同様のパターンを適用」等の暗黙的一般化表現が意図通り動作しない
リスクがある。全 10 skills SKILL.md と 27 modules を監査し、発見したパターンを
`docs/reports/literalism-audit.md` としてレポート化する。
単純な言い換えは同 PR 内で inline rewrite し、複雑な変更はフォローアップ Issue を起票する。

監査対象ファイル数:
- `skills/*/SKILL.md`: 10 ファイル (`skills/audit`, `auto`, `code`, `doc`, `issue`, `merge`, `review`, `spec`, `triage`, `verify`)
- `modules/*.md`: 27 ファイル (measurement scope: `modules/` 直下 `.md` ファイル全件)

## Changed Files

- `docs/reports/literalism-audit.md`: 新規作成 — 監査結果レポート (Summary / Findings / Remediation)
- `skills/*/SKILL.md` (複数): inline rewrite の対象ファイル — 実装時の監査結果に基づき確定
- `modules/*.md` (複数): inline rewrite の対象ファイル — 実装時の監査結果に基づき確定

## Implementation Steps

1. 全 10 `skills/*/SKILL.md` を Read し、検出基準 1–4 (類似性省略 / 列挙省略 / 暗黙 for-each / 推論依存条件) に該当する箇所を列挙する (→ 受け入れ基準 A, B)
2. 全 27 `modules/*.md` を Read し、同じ検出基準で該当箇所を列挙する (→ 受け入れ基準 A, C)
3. 収集した findings から inline rewrite / follow-up issue の判定を行い、`docs/reports/literalism-audit.md` を作成する (Summary・Findings・Remediation の 3 セクション必須) (→ 受け入れ基準 A–F)
4. inline rewrite 対象ファイルに直接 Edit を適用する (同一ファイル内の単純な言い換え・暗黙列挙→明示列挙変換・曖昧形容詞の除去) (→ 受け入れ基準 G)
5. follow-up issue 対象のパターンを `gh issue create` で起票し、レポートの `## Remediation > Follow-up Issues` に番号を記載する (→ 受け入れ基準 G)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/literalism-audit.md" --> 監査結果レポートが作成されている
- <!-- verify: section_contains "docs/reports/literalism-audit.md" "## Findings" "skills/" --> `## Findings` に skills/ 配下の結果が含まれる
- <!-- verify: section_contains "docs/reports/literalism-audit.md" "## Findings" "modules/" --> `## Findings` に modules/ 配下の結果が含まれる
- <!-- verify: section_contains "docs/reports/literalism-audit.md" "## Remediation" "Inline Rewrites" --> `## Remediation` に inline rewrite の方針が記載されている
- <!-- verify: section_contains "docs/reports/literalism-audit.md" "## Remediation" "Follow-up" --> `## Remediation` に follow-up Issue 欄が存在する (N/A 記載でも可)
- <!-- verify: file_contains "docs/reports/literalism-audit.md" "## Summary" --> レポート冒頭に Summary セクションがある

### Post-merge

- 監査で特定された全パターンが inline rewrite として本 PR に含まれる、またはフォローアップ Issue として起票されている
- 任意の Issue で `/auto N` を実行し literalism 変化による回帰 (skill 実行失敗、一般化挙動欠落等) が発生しないことを確認

## Notes

- Changed Files の `skills/*/SKILL.md` と `modules/*.md` の具体的なファイルリストは実装時に確定する。Spec 段階では監査前のため列挙不可能。
- `docs/reports/` ディレクトリは既存 (`claude-opus-4-7-optimization-strategy.md` が存在)。新規ディレクトリ作成ではないため `docs/structure.md` の更新は不要。
- pre-merge verification 6 件は SPEC_DEPTH=light の上限 (5 件) を 1 件超過しているが、Issue body 受け入れ基準に対応する全件を含めるため容認。

## Code Retrospective

### 実装の判断記録 (2026-04-17)

**Step 8 → Step 9 off-by-one 誤り**
`skills/issue/SKILL.md` line 355 の `New Issue Creation Step 8, procedures 2–8` は誤りだった。Step 8 は "Triage Auto-chain" であり、手順 2–8 を持つのは Step 9 (Scope Assessment)。Spec 調査中に発見し、参照先修正と手順インライン展開を同時に実施した。

**Steps 12/13 の step 番号誤参照**
Existing Issue Refinement の Step 12 (Issue Retrospective) は `Same as New Issue Creation Step 9.` と記述されていたが、Step 9 は Scope Assessment。正しくは Step 10。同様に Step 13 (Opportunistic Verification) は Step 10 → 正しくは Step 11。両方を修正しインライン展開した。

**Step 4 の内容インライン化方針**
New Issue Creation Step 4 は ~97 行の長大なステップ。完全複製は保守性を損なうため、要点を 1 段落に要約した上で「New Issue Creation → Step 4: Classify Acceptance Criteria and Assign Verify Commands」という明示的なセクション+ステップ名参照を添える形にした。これにより LLM がセクション境界をまたいだナビゲーションを確実に行える。

**フォローアップ Issue 3 件 (audit/doc/review)**
`skills/audit/SKILL.md` の 4 箇所は drift/fragility/integrated 間の cross-subcommand 参照で、それぞれ参照先の全手順を展開する必要がある大規模変更のため follow-up とした。`skills/doc/SKILL.md` も cross-section 参照で同様。`skills/review/SKILL.md` の "all three reviewer types" は reviewer type 列挙の設計見直しが必要なため follow-up とした。

## review retrospective

### Spec vs. 実装の乖離パターン

監査レポート (`docs/reports/literalism-audit.md`) の `## Findings` セクションに、Remediation に記載したはずの `skills/triage/SKILL.md` と `skills/doc/SKILL.md` のエントリが抜け落ちていた。Remediation 表と Findings 節の整合性を確認するステップが実装時に欠けていたことが原因。レビューで SHOULD として検出し修正した。今後の監査レポートでは "Remediation の各行に対応する Findings エントリが存在するか" をチェックする手順を Spec に追加することを推奨する。

### 繰り返し課題

特記なし。今回は単一ファイル (docs/reports) の Findings 欠落であり、繰り返しパターンではない。

### 受入条件検証の困難さ

全 6 件の `verify` コマンドが PASS。`section_contains` の regex は最初の Python スクリプトで誤動作したが (`(?=^##)` パターン不整合)、修正後に正常判定。`section_contains` の検証スクリプトは `(?=\n## |\Z)` パターンが安定することを確認した。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Changed Files に `skills/*/SKILL.md` と `modules/*.md` の具体的リストを "実装時に確定" とした点は適切。監査前にファイルを列挙するのは不可能であり、Spec として正しい表現。
- pre-merge 受入条件 6 件は SPEC_DEPTH=light 上限 (5 件) を 1 件超過しているが、Spec に明示的に容認理由が記載されており問題なし。

#### design
- 設計フェーズとしての Spec 内容は実装結果と概ね一致。監査結果 (16 findings / 9 inline rewrite / 3 follow-up) は Spec の実装ステップに沿って生成されており、設計と実装の乖離なし。

#### code
- off-by-one 誤りと step 番号誤参照 (Steps 12/13) が実装時に発見・修正された。これらは Spec 段階では検出不能な動的発見であり、コード実装フェーズの貢献として適切。
- git log にリワーク (fixup/amend) パターンなし。単一コミット `5a4f6eb` でマージ。実装品質は高い。
- 長大 Step 4 のインライン化戦略 (要点要約 + セクション名参照) は保守性とリテラリズム対応のバランスが良く妥当な判断。

#### review
- Findings/Remediation の不整合 (triage/doc エントリ欠落) をレビューで SHOULD として検出できた。review 有効性は高い。
- section_contains regex 問題を受入条件検証で発見 (`(?=^##)` パターン) し修正できた。verify フェーズ前にレビューで発見できなかったが、verify で対処済み。

#### merge
- 単一クリーンコミットでマージ。競合なし。フォローアップ Issue #233, #234, #235 も適切に起票済み (commit `5a4f6eb` 確認)。

#### verify
- 全 6 件の pre-merge 条件が PASS。verify コマンドの設計 (file_exists / section_contains / file_contains) は適切で誤検知なし。
- Post-merge 2 条件 (manual) が未確認のまま残存。`verify-type: manual` として明示されており、自動化できない性質の条件。issue は `phase/verify` で管理継続。

### Improvement Proposals
- 監査レポート系タスクでは Spec の "Implementation Steps" に「Remediation 表の各行に対応する Findings エントリが存在するか確認する」ステップを追加することを推奨する。レビューで検出できたが、実装フェーズで予防できれば再作業を防げる。
