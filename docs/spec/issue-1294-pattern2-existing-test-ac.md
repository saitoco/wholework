# Issue #1294: skill-dev-verify-audit: Pattern 2 に既存グリーンテストを走らせるだけの command 型 AC を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1294 --non-interactive` の Issue Retrospective — 曖昧性検出 0 件 (Auto-Resolve 対象なし)、AC 本文・verify command・verify-type タグは無変更、Step 15 (AC Verify Command Integrity Audit) を本文に対して実行し Pattern 1〜6 いずれにも非該当 (rubric 2 件・grep 2 件とも実装前の main では未充足で常時 PASS ではない) と確認。本文への変更は Related セクションへの #1251 相互参照追加のみ (AC・verify command には影響なし)。 / URL: https://github.com/saitoco/wholework/issues/1294#issuecomment-5230153044

## Overview

`skills/triage/skill-dev-verify-audit.md` の Pattern 2 (常時 PASS な verify command) に、既存のグリーンなテストスイートを走らせるだけの `command` 型 AC を検出する新規サブパターンを追加する。現行の `command` 型サブパターン (`:66-78`) は「対象スクリプトが informational 専用設計で常に exit 0 を返す」ケースのみを扱っており、「AC 本文が新規テストケース・新規カバレッジの追加を主張しているが、verify command は変更前から green な既存スイートを走らせるだけ」という形は被覆されていない。同一セッション内で #1273 / #1279 / #1287 の 3 件が実測されており、うち #1287 は検出漏れとなった (`/verify 1287` の Verify Retrospective が本 Issue の起票元)。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: Pattern 2 に「既存テストファイルの実行に起因する常時 PASS (`command` 型 AC)」サブパターンを追加 (既存の「exit code 設計に起因する常時 PASS」サブパターンの直後、`section_contains`/`section_not_contains` 型サブパターンの直前に挿入)

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の Pattern 2 内、「exit code 設計に起因する常時 PASS (`command` 型 AC)」サブパターンの直後 (`section_contains`/`section_not_contains` 型サブパターンの直前) に新規サブパターンを挿入する。既存サブパターンと同じ構成 (説明文 → 例 → Detection approach → Fix options) で以下を含める:
   - 説明文: `command` 型 AC の対象が既存テストファイル/スイートであり、AC 本文が新規テストケース・新規カバレッジの追加を主張している場合、実装前の main で対象コマンドが既に exit 0 を返すなら常時 PASS になる旨。判別語として「既存テストファイル」を含める
   - 例: #1279 (bats --filter で解消)・#1287 (検出漏れ) を実例として挙げる
   - Detection approach: (a) 対象が既存テストファイル/スイートか確認、(b) 実装前 main で空撃ち、(c) 既に exit 0 かつ AC 本文が新規カバレッジ追加を主張していれば常時 PASS として検出、(d) AC 本文が回帰保護のみを主張している場合は検出対象外
   - Fix options: `bats --filter` による絞り込みを含む 2 つ以上の具体的な修正手段
   (→ acceptance criteria 1, 2, 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "skill-dev-verify-audit.md の Pattern 2 に、command 型 verify command の対象が既存テストファイルであり実装前から exit 0 になるケースを常時 PASS として検出する記述が追加されている" --> `skills/triage/skill-dev-verify-audit.md` の Pattern 2 に、既存のグリーンなテストスイートを走らせるだけの `command` 型 AC を検出するサブパターンが追加されている
- <!-- verify: grep "既存テストファイル" "skills/triage/skill-dev-verify-audit.md" --> 追加されたサブパターンに「既存テストファイル」という判別語が含まれている
- <!-- verify: rubric "AC 本文が新規カバレッジの追加を主張している場合のみ検出対象とし、既存スイート全体の回帰保護を目的とする AC は検出対象外とする旨が明記されている" --> 回帰保護のみを主張する AC を検出対象外とする除外条件が明記されている
- <!-- verify: grep -- "--filter" "skills/triage/skill-dev-verify-audit.md" --> Fix options に、`bats --filter` による絞り込みを含む具体的な修正手段が 2 つ以上示されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テストが green (patch route)

### Post-merge

- 次に `command "bats <既存ファイル>"` 形式の AC を持つ Issue を `/triage` または `/issue` が処理した際、当該 AC が常時 PASS として指摘されることを観察する<!-- verify-type: observation event=auto-run session=next -->

## Notes

- **挿入位置の判断根拠**: 新規サブパターンは既存の「exit code 設計に起因する常時 PASS (`command` 型 AC)」サブパターン (`:66-78`) と同じ `command` 型を対象とするため、その直後・`section_contains`/`section_not_contains` 型サブパターン (`:80-92`) の直前に挿入する。`command` 型という共通の対象を持つ 2 サブパターンが連続することで、読み手が同一 AC タイプの検出パターンをまとめて参照できる。
- **Issue 本文の行番号引用の正確性確認 (Step 6 コンフリクト検出)**: Issue 本文が引用する `:66-78` (現行の command 型サブパターン) を実装前の現状ファイルと突き合わせて確認済み — 完全に一致しており、コンフリクトなし。
- **Steering Docs sync candidate check**: `skill-dev-verify-audit.md` を参照する全ファイルを `grep -rln` で確認した。`docs/environment-adaptation.md` (Domain file 一覧表への言及) と `modules/size-workflow-table.md` (Pattern 4 への言及、本 Issue の変更対象外) はいずれも Pattern 2 の内部サブパターン数や具体的記述内容を参照していないため、更新不要と判断した。消費経路の `skills/triage/SKILL.md` Step 7 / `skills/issue/SKILL.md` Step 15 はいずれも「Read X and follow Processing Steps」形式の参照であり、サブパターン追加によるインターフェース変更は発生しないため、変更不要。
- **CI 検証 AC の追加**: Issue 本文の Notes は「CI 検証 AC は Size 確定後に `/spec` が追加する」と明記していた (`.md` のみの変更で Size が XS/S に落ちる可能性があり、pr route 用 `gh pr checks` と patch route 用 `gh run list` のどちらが正しいかは Size 確定後にしか決まらないため)。Size=S・`ALWAYS_PR=false` (patch route) と確定したため、`gh run list --workflow=test.yml ...` 形式の CI AC を Issue 本文・Spec の両方に追加した (`.github/workflows/` 配下に test.yml 以外のワークフロー — dco.yml、kanban-automation.yml — が存在するため `--workflow=test.yml` で対象を明示。同一セッションの #1287 で採用された形と同型)。
- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** `/issue` フェーズの Issue Retrospective (Consumed Comments 参照) が既に曖昧性検出 0 件・AC 監査クリーンと報告しており、本 Spec はその結果をそのまま踏襲する。
- **UI Design Phase 非該当**: 本 Issue はドキュメント (Domain file) の記述追加のみであり、UI 要素は一切含まない (`skills/spec/figma-design-phase.md` の適用除外条件に合致)。
- **テストファイル非該当**: `skill-dev-verify-audit.md` は LLM が読む prose 形式の Domain file であり、対応する bats テストファイルは存在しない (`tests/` 配下に該当ファイルなし)。挙動の検証は Post-merge の observation AC (次回 `/triage`/`/issue` 実行時の実観測) が担う。
