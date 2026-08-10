# Issue #1315: skill-dev-verify-audit: Pattern 2 に定義が構造的に充足不能な AC の検出を追加

## Consumed Comments

No new comments since last phase.

## Overview

`skills/triage/skill-dev-verify-audit.md` の Pattern 2 (常時 PASS な verify command) に、AC が複数の量 (分母・分子など) を同時に要求しながら、それらが同一実行単位で同時に取得できないため定義自体が構造的に充足不能になるケースを検出する新規サブパターンを追加する。現行 Pattern 2 は「実装前から真になる」常時 PASS 系のサブパターン (基本形 + `command`/`section_contains`/`github_check`/`rubric` 型の 5 派生) を検出するが、「実装をどう進めても充足できない」定義矛盾は被覆していない。#1270 の Pre-merge AC 1 (observation dispatch の SKIPPED 率、分母 85・分子上限 5) が実例で、`/verify 1270` は UNCERTAIN と判定した。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: Pattern 2 に「定義が構造的に充足不能な AC」サブパターンを追加 (既存の `rubric` 型サブパターンの直後、`### Pattern 3` の直前に挿入)

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の Pattern 2 内、`rubric` 型に起因する常時 PASS サブパターン (現行 `:125-137`) の直後、`### Pattern 3` (現行 `:139`) の直前に新規サブパターンを挿入する。既存サブパターンと同じ構成 (見出し → 説明 → 例 → Detection approach → Fix options) で以下を含める:
   - 見出し: 「充足不能」という判別語を含む見出し (例: 「定義が構造的に充足不能な AC (複数量の同時成立不能)」)
   - 例: #1270 の Pre-merge AC 1 (分母 85・`observation-dispatch-threshold` 既定 5 による分子上限、`/verify 1270` の UNCERTAIN 判定) を実例として挙げる
   - Detection approach: (a) AC が複数の量を同時に要求しているか確認、(b) 一方の取得が設定値やスクリプトの構造的上限で制約されるか確認、(c) 判定が難しい場合は検出せず素通しする (偽陽性回避、Issue 本文の文言をそのまま採用)
   - Fix options: 単位を揃える方法 (#1270 の実例を含む) を含む、Issue 本文の 3 案をそのまま採用
   (→ acceptance criteria 1, 2, 3, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "skill-dev-verify-audit.md の Pattern 2 に、AC が複数の量を同時に要求しながらそれらが同一実行単位で成立しないケースを検出する記述が追加されている" --> Pattern 2 に、定義が構造的に充足不能な AC (複数の量を要求するが同一実行単位で同時に取得できない) を検出するサブパターンが追加されている
- <!-- verify: grep "充足不能" "skills/triage/skill-dev-verify-audit.md" --> 追加されたサブパターンに「充足不能」という判別語が含まれている
- <!-- verify: rubric "充足不能サブパターンの Detection approach に、判定が難しい場合は検出しない方針が明記されている" --> Detection approach に、判定困難時は検出せず素通しする旨 (偽陽性回避) が明記されている
- <!-- verify: rubric "充足不能サブパターンの Fix options に、単位を揃える方法を含む修正手段が 2 つ以上記載されている" --> Fix options に、#1270 が実際に採った「単位を揃える」方法を含む具体的な修正手段が 2 つ以上示されている

### Post-merge

- 次に複数の量を同時に要求する AC を持つ Issue を `/triage` または `/issue` が処理した際、充足可能性が確認されることを観察する<!-- verify-type: observation event=auto-run session=next -->

## Notes

- **挿入位置の判断根拠**: 新規サブパターンは特定の verify command type (`command`/`section_contains`/`github_check`/`rubric`) に紐づかない横断的な AC 定義レベルの問題である。#1294 は「同じ `command` 型」という基準で既存 `command` 型サブパターンの直後に挿入したが、本サブパターンは既存のどの type 別サブパターンとも type を共有しないため、type 別サブパターン群の末尾 (`rubric` 型の直後、`### Pattern 3` の直前) に追加する。
- **Issue 本文の記述確認 (Step 6 コンフリクト検出)**: Issue 本文が引用する #1270 の実測値 (分母 85・分子上限 5・`observation-dispatch-threshold` 既定 5) を実装前の現状ファイル (`skills/triage/skill-dev-verify-audit.md` の現行 Pattern 2 内容、`.wholework.yml` に `observation-dispatch-threshold` 未設定=既定 5) と突き合わせて確認済み — 矛盾なし。
- **CI 検証 AC は追加しない**: #1294 (同じファイルへの同種のサブパターン追加、Size S・patch route) は `github_check "gh run list --workflow=test.yml ..."` 形式の CI AC を Pre-merge に追加しているが、その Issue 本文の Notes には「CI 検証 AC は Size 確定後に `/spec` が追加する」という明示的な事前合意が記載されていた。本 Issue の本文にはその種の事前合意がなく、`/spec` の責務境界 (`docs/product.md` § `/issue` (What) vs `/spec` (How) — 「要件の追加・変更」は `/spec` の Prohibited 項目) を踏まえ、Issue 本文にない新規 AC を独自に追加することは見送った。CI (`test.yml`) 自体は push トリガーで自動実行されるため、AC として明示されていなくても実行・確認はされる。
- **Steering Docs sync candidate check**: `skill-dev-verify-audit.md` を参照する全ファイルを `grep -rln "Pattern 2"` (skills/, modules/, docs/) および `grep -rl "skill-dev-verify-audit"` (tests/) で確認した。`modules/next-action-guide.md` と `skills/doc/SKILL.md` がヒットしたが、いずれの "Pattern 2" も本ファイルと無関係な独自のパターン番号付け (next-action-guide.md 自身のガイダンス分類、doc/SKILL.md 自身のドキュメント分類) であり誤検出。`tests/issue.bats` の参照は `/issue` SKILL.md が本ファイルを読む旨の参照チェーン確認のみで、Pattern 2 の内容自体は対象外。消費経路の `skills/triage/SKILL.md` (Step 7 他) ・`skills/issue/SKILL.md` (Step 15) はいずれも「Read X and follow」形式の参照であり、サブパターン追加によるインターフェース変更は発生しないため、変更不要。
- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文の「対応方針 (案)」が Detection approach / Fix options の具体文言まで既に確定しているため、曖昧性は生じていない。
- **UI Design Phase 非該当**: 本 Issue はドキュメント (Domain file) の記述追加のみであり、UI 要素は一切含まない。
- **テストファイル非該当**: `skill-dev-verify-audit.md` は LLM が読む prose 形式の Domain file であり、対応する bats テストファイルは存在しない (`tests/issue.bats` は参照チェーンのみを検証)。挙動の検証は Post-merge の observation AC (次回 `/triage`/`/issue` 実行時の実観測) が担う。
