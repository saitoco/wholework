# Issue #1315: skill-dev-verify-audit: Pattern 2 に定義が構造的に充足不能な AC の検出を追加

## Consumed Comments

No new comments since last phase.

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1315#issuecomment-5235657327
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1315#issuecomment-5235677184
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1315#issuecomment-5241984272
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1315#issuecomment-5246567598
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1315#issuecomment-5255763931
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1315#issuecomment-5296392569
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1315#issuecomment-5304278099
- saito / MEMBER / first-class / <!-- wholework-event: type=batch-verify-dispatch phase=audit issue=1315 --> / https://github.com/saitoco/wholework/issues/1315#issuecomment-5306139433
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

## Code Retrospective

### Deviations from Design
- N/A — 実装は Spec の Implementation Steps 1 と完全に一致 (既存 `rubric` 型サブパターンの直後、`### Pattern 3` の直前への単一挿入)。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A — フル bats スイート (`bats --jobs 18 tests/`) で `tests/post_merge_check.bats` の 2 件が並列実行時のみ FAIL したが、`docs/tech.md` § "CI bats Parallel/Serial Split" が既知の並列限定フレーキーとして記録済みのパターンと一致。直列再実行 (`bats tests/post_merge_check.bats`) で 10/10 PASS を確認し、本実装とは無関係と判断。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 新規サブパターンの見出しは Spec が指定した通り「充足不能」を含む形 (`定義が構造的に充足不能な AC (複数量の同時成立不能)`) を採用し、AC2 の `grep "充足不能"` を満たすことを確認した。
- Detection approach / Fix options は Issue 本文の「対応方針 (案)」の文言をそのまま採用し、Spec の指示通り言い換えを行わなかった。

### Deferred Items
- Post-merge の observation AC (次に複数の量を要求する AC を `/triage`/`/issue` が処理した際の実観測、`session=next`) は未評価のまま — 次回のそのようなイベント発生時に `/verify` が判定する。

### Notes for Next Phase
- 本 Issue は patch route (Size S) のため `/review`/`/merge` を経由せず、`/verify` が直接次のフェーズとなる。
- Pre-merge AC 4 件は本フェーズで `[x]` 済み。Post-merge AC 1 件 (observation) は `/verify` 実行時点でイベント未発火なら SKIPPED 判定になる見込み。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- AC 4 件がいずれも rubric で自動検証可能な形に書かれており、triage の AC 監査も指摘 0 件だった。`/issue` は「本文は既に What レベルで十分 specified」として本文変更なしと判断しており、過剰介入がない。
- Post-merge AC を observation 型 1 件に絞った設計も適切。「次に複数量を要求する AC を処理した際に充足可能性が確認される」は、実装の効果が現れるのが将来の別 Issue 処理時であるという性質を正しく反映している。

#### spec

- Implementation Steps が「既存 `rubric` 型サブパターンの直後、`### Pattern 3` の直前への単一挿入」まで具体化されており、実装時の判断余地がほぼゼロだった。結果として逸脱・rework ともに 0。

#### code

- Spec との完全一致。逸脱なし、rework なし。
- `bats --jobs 18 tests/` で `tests/post_merge_check.bats` の 2 件が並列限定 FAIL したが、直列再実行で 10/10 PASS を確認し無関係と切り分けている。判断は妥当。

#### review

- patch route (Size S) のため `/review` は実行されていない。

#### merge

- patch route のため PR なし。main への直コミット。

#### verify

- Pre-merge 4 件は already-checked skip rule により SKIPPED、Post-merge 1 件は `auto-run` 未発火のため SKIPPED。FAIL / UNCERTAIN ゼロ。
- 実装内容を Spec の AC 要件と照合し、Fix options が要求の 2 つを上回る 3 つ提示されていること、うち 1 つが #1270 の実採用手段であることを確認した。

### Improvement Proposals

- N/A — 新規の構造的改善提案は生じなかった。観測した事象はいずれも既存 Issue が扱っている。

### 特記 1: Pattern 2 の被覆が揃った

本 Issue の着地により、`skills/triage/skill-dev-verify-audit.md` Pattern 2 が扱う「実装の如何にかかわらず結果が変わらない AC」の被覆が一通り揃った。

| サブパターン | 着地先 |
|---|---|
| 常時 PASS (文字列が既存) | 既存 |
| 常時 PASS (既存グリーンテスト) | #1294 |
| **充足不能 (定義矛盾)** | **本 Issue** |
| 常時 UNCERTAIN (executor タイムアウト超過) | #1310 (`verify-executor.md` 側の警告として) |

#1251 (AC 記述規約) がクローズ時に取りこぼした 2 件 — 充足不能の検出と件数 0 の判定ルール — は、本 Issue と #1310 でそれぞれ行き先を得た。取りこぼしの構造的原因 (L0 コメント消費カットオフの欠落窓) は **#1316** が扱う。

### 特記 2: `tests/post_merge_check.bats` の並列フレークが本セッション内で 4 回目の観測

本セッション (`40422-1786325686` および直前の関連実行) を通じて、同フレークは #1278 / #1304 / #1310 / #1315 の code フェーズで計 4 回観測された。FAIL 件数は 1 件のときと 2 件のときがあり、非決定的なレースであることが繰り返し確認されている。追跡は **#1308** が担当しており、本 Issue から追加起票はしない。ただし観測回数は #1308 の優先度判断の材料になる。
