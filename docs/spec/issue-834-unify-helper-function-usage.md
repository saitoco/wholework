# Issue #834: tests: auto-completion-report.bats の helper 関数使用方針を統一

## Overview

`tests/auto-completion-report.bats` では `batch_completion_section()` helper 関数が定義されているが、4 件の `@test` すべてでインライン awk が使われており helper は未使用になっている。

本 Issue では **Option A (helper 関数を使うように統一)** を採用する: 4 件の `@test` 内のインライン awk を `batch_completion_section | grep -q "..."` 形式に置き換え、awk パターンの重複を解消する。

## Consumed Comments

- saito (MEMBER / first-class) — Issue Retrospective: Proposal C (文書化) はスコープ外と自動解決。rubric verify command の設計確認済み。`verify-type: observation event=auto-run` 有効。
  URL: https://github.com/saitoco/wholework/issues/834#issuecomment-4828125418

## Changed Files

- `tests/auto-completion-report.bats`: 4 件の `@test` 内インライン awk を `batch_completion_section` helper 呼び出しに変更

## Implementation Steps

1. `tests/auto-completion-report.bats` の各 `@test` ブロックを以下の形式に書き換える (→ AC: helper 統一):
   - 変更前: `run bash -c "awk '/^### Batch Completion Report/...' '$SKILL_FILE' | grep -q 'TEXT'"` + `[ "$status" -eq 0 ]`
   - 変更後: `batch_completion_section | grep -q "TEXT"`

   具体的な各 @test の変更:
   - `"Batch Completion Report: Pending manual confirmation block present"`: `batch_completion_section | grep -q "Pending manual confirmation"`
   - `"Batch Completion Report: verify-type classification present"`: `batch_completion_section | grep -q "verify-type"`
   - `"Batch Completion Report: phase/verify label check present"`: `batch_completion_section | grep -q "phase/verify"`
   - `"Batch Completion Report: Recommended next action guidance present"`: `batch_completion_section | grep -q "Recommended next action"`

## Verification

### Pre-merge

- <!-- verify: rubric "tests/auto-completion-report.bats の 4 件の @test がすべて helper 関数 (batch_completion_section 等) を使うか、すべてインライン awk を使うかのいずれかに統一されており、混在していない" --> helper 関数の使用方針が統一されている
- <!-- verify: command "bats tests/auto-completion-report.bats" --> bats test が緑のまま

### Post-merge

- 次回 SKILL.md structural assertion テスト追加時、本 Issue で確立した方針が適用されることを観察

## Notes

**Non-interactive 自動解決 (Option A vs B):**
- Option A (helper 使用に統一) を選択
- 根拠: `batch_completion_section()` は awk パターンの再利用を目的として設計されており、helper への一本化により、セクション抽出パターンの変更時の修正箇所を 1 か所に集約できる。本ファイルが structural assertion テストのリファレンス実装となることを Issue が意図しているため、helper 使用パターンを確立する方が妥当と判断。
- `auto-batch.bats` と `auto-xl-concurrency.bats` も同じ "helper 定義・inline awk 使用" パターンを持つが、本 Issue のスコープ外のため変更しない。

**既存テスト確認:** 変更前に `bats tests/auto-completion-report.bats` を実行し、4 件全て PASS することを確認済み。

## Code Retrospective

### Deviations from Design
- None: Spec の Implementation Steps の通りに実装できた。4 件の `@test` を `run bash -c "awk ... | grep -q ..."` + `[ "$status" -eq 0 ]` から `batch_completion_section | grep -q "..."` に正確に変換した。

### Design Gaps/Ambiguities
- None: Spec の変更後形式 (`batch_completion_section | grep -q "TEXT"`) は bats の動作モデルと一致しており、サブシェルで `batch_completion_section` が未定義になる問題もなかった (bats は同ファイル内の関数をテスト本体から直接呼び出し可能)。

### Rework
- None: 実装一発で全 4 件 PASS。`run bash -c` パターンを除去して直接パイプ呼び出しに変更したが、bats のスコープ規則を事前に把握していたため手戻りなし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Option A (helper 関数使用に統一) を採用。`batch_completion_section | grep -q` の直接呼び出しパターンを確立した。
- `run bash -c` ラッパーを削除してシンプル化した結果、テストの可読性が向上した。

### Deferred Items
- `auto-batch.bats` と `auto-xl-concurrency.bats` も同じ "helper 定義・inline awk 使用" パターンを持つが、本 Issue スコープ外のため変更しなかった (将来の follow-up 候補)。
- Proposal C (文書化) はスコープ外のまま。

### Notes for Next Phase
- verify command は全て PASS 済み (`rubric` + `bats` コマンド)。`/verify` での再確認は不要だが、形式的に実施しても問題ない。
- Post-merge AC は `verify-type: observation event=auto-run` のため `/verify` ではスキップされる (SKIPPED として記録)。
