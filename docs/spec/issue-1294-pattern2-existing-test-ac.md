# Issue #1294: skill-dev-verify-audit: Pattern 2 に既存グリーンテストを走らせるだけの command 型 AC を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1294 --non-interactive` の Issue Retrospective — 曖昧性検出 0 件 (Auto-Resolve 対象なし)、AC 本文・verify command・verify-type タグは無変更、Step 15 (AC Verify Command Integrity Audit) を本文に対して実行し Pattern 1〜6 いずれにも非該当 (rubric 2 件・grep 2 件とも実装前の main では未充足で常時 PASS ではない) と確認。本文への変更は Related セクションへの #1251 相互参照追加のみ (AC・verify command には影響なし)。 / URL: https://github.com/saitoco/wholework/issues/1294#issuecomment-5230153044

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1294#issuecomment-5230359433
- saito / MEMBER / first-class / ## Post-merge observation の証拠を観測しました (#1293 の `/issue` フェーズ) / https://github.com/saitoco/wholework/issues/1294#issuecomment-5230704983
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1294#issuecomment-5230976953
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

## Code Retrospective

### Deviations from Design

N/A — Spec の Implementation Steps 通り、Pattern 2 の「exit code 設計に起因する常時 PASS」サブパターン直後・`section_contains`/`section_not_contains` 型サブパターン直前に新規サブパターンを挿入した。

### Design Gaps/Ambiguities

N/A

### Rework

- 実装コミット自体に手戻りはない。テストフェーズで `bats --jobs 18 tests/` の 1 回目実行時に `tests/post_merge_check.bats` の `fail: gh issue reopen called when FAIL input given` が 1 件 FAIL したが、`bats tests/post_merge_check.bats` の単独実行および 2 回目のフルスイート並列実行ではいずれも PASS した。本 Issue の変更対象 (`skills/triage/skill-dev-verify-audit.md`) とは無関係なファイルであり、`--jobs` 並列実行時の一時的な競合 (flake) と判断し、実装への手戻りは発生していない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 新規サブパターンは既存の「exit code 設計に起因する常時 PASS (`command` 型 AC)」サブパターンの直後・`section_contains`/`section_not_contains` 型サブパターンの直前に挿入した (Spec Notes の判断根拠を踏襲)。
- 判別語「既存テストファイル」と Fix options 内の `bats --filter` は Issue 本文の AC 文言・grep 対象と完全一致させ、grep 型 AC (2, 4) を確実に PASS させる形にした。
- Pre-merge AC 5 件のうち CI AC (`gh run list --workflow=test.yml ...`) は patch route の branch-scoped CI AC 除外規則により未チェックのまま残した (`/verify` が post-merge で評価)。

### Deferred Items
- CI (test.yml) green の確認 — `/verify` が post-merge で評価する (Issue 本文 Pre-merge AC 5 件目、現状 `- [ ]`)。
- Post-merge observation AC (次回 `/triage`/`/issue` が `command "bats <既存ファイル>"` 形式の AC を処理した際の実観測) — 次回セッションでの自然発生を待つ。

### Notes for Next Phase
- テスト実行時に `tests/post_merge_check.bats` で 1 件の一過性 FAIL を観測したが、単独実行・2 回目のフルスイート実行ではいずれも PASS しており、本 Issue の変更とは無関係な並列実行時の flake と判断済み。`/review`/`/verify` で再現した場合はこの記録を参照。
- 実装は `skills/triage/skill-dev-verify-audit.md` のプローズ追加のみで、対応する bats テストファイルは存在しない (Spec Notes 「テストファイル非該当」参照)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- Step 15 の AC 監査は所見なし (Pattern 1〜6 いずれにも非該当)。本 Issue の AC は起票時にベースラインを実測してから書いたため (`grep "既存テストファイル"` = 0 件、`grep -- "--filter"` = 0 件)、判別可能な形になっていた
- 既存コメントで重複候補として挙がっていた **#1251** への相互参照を Related に追加。#1251 は「rubric の参照ファイル・数値 AC の母集団定義を AC に含める規約」を扱う Issue で、本 Issue (`command` 型の常時 PASS 検出) とは対象が異なる。重複ではなく隣接として処理された判断は妥当

#### spec

- AC が要求した検出条件・除外条件・Fix options・根拠の記録をすべて満たす形でサブパターンを設計。プローズ追加のみで対応する bats テストが存在しないことを Notes に明記し、テスト追加 AC を立てない判断を残した
- patch route 用に `github_check "gh run list ..."` 形式の CI AC を追加 (起票時は route 未確定のため意図的に含めなかったもの)

#### code

- `skills/triage/skill-dev-verify-audit.md` のプローズ追加のみ。rework ゼロ
- Step 9 のテスト実行で `tests/post_merge_check.bats` に一過性 FAIL を観測したが、単独実行と 2 回目のフルスイートで PASS を確認し並列実行フレークと判断。#1301 の code フェーズでも同一ファイルの並列フレークが観測されており (#1308 で追跡中)、本セッションで 2 件目

#### review

- patch route のため `/review` フェーズは実行されていない

#### merge

- patch route の直コミット。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 4 件は既チェックのため skip、CI の 1 件は実測して PASS。post-merge の observation 1 件は `auto-run` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- CI run の同一性を確認した: `--limit=1` が返した run (headSha `92130e95`) は並行セッション (#1304) の commit だが main は線形で本 Issue の実装 `7ffc4c07` を含み、本 Issue 自身の commit (`02476619`) の run も独立に green だった
- 追加されたサブパターンの実体を確認した (`:80-96`)。検出手順 (a)-(c) に加え、除外条件 (d) が「既存スイート全体を走らせる回帰保護 AC 自体は正当であり禁止しない」と明記されている。Fix options 3 件、根拠として #1279 (検出成功) と **#1287 (検出漏れ)** の両方を引用。検出漏れ側の実例が文書内に残ることで、本 Issue の根拠が「実行者の注意深さのばらつき」ではなく「パターン文書の被覆漏れ」であることが後から追える
- **本 Issue の主張を裏づける追加事例が同一セッションで発生した**: 起票直後に処理した #1301 の AC (これも `/verify` の L3 retrospective が起草) にも `/issue` Step 15 が常時 PASS を 1 件検出している。always-PASS を 7 件指摘した直後の起票に同じ欠陥クラスが混入しており、根因が個々の実行者の注意深さでないことの実例として #1301 の Verify Retrospective にも記録済み

### Improvement Proposals

- N/A — 本 Issue が対処した被覆漏れ以外に、本実行から新たに派生する構造的な改善点は検出されなかった。`tests/post_merge_check.bats` の並列実行フレークは #1308 が既に追跡している
