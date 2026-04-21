# Issue #333: tests: orchestration-fallbacks.bats の Rationale 参照チェックを entry-scoped 範囲解析に改善

## Overview

`tests/orchestration-fallbacks.bats` test 9 の awk スクリプトは、`### Rationale` が各エントリの **最終セクション** であることを前提として動作している。具体的には、`in_rationale` フラグを `## ` 境界検査に使用しているため、`### Rationale` の後に別の `### ` セクションが追加されると `in_rationale` が 0 にリセットされ、`## ` 境界での欠落検知が機能しなくなる。

`found_rationale` 変数を導入し、`### ` セクション境界をまたいでも Rationale 検出状態を保持することで、将来的に Rationale が最終セクションでなくなった場合も正しく動作するよう改善する。

## Changed Files

- `tests/orchestration-fallbacks.bats`: test 9 の awk スクリプトを `found_rationale` 変数による entry-scoped 範囲解析に変更 — bash 3.2+ 互換（awk 変数追加のみ）

## Implementation Steps

1. `tests/orchestration-fallbacks.bats` の test 9 awk スクリプトを次のように修正する（→ acceptance criteria A, B）:
   - `## ` 境界の処理ブロック（`in_rationale = 0` の直前）に `found_rationale = 0` を追加
   - `### Rationale` 検出ルール（`in_rationale = 1` の行）に `found_rationale = 1` を追加
   - `## ` 境界チェック（`if (in_entry && in_rationale && !has_ref)`）の条件を `in_rationale` から `found_rationale` に変更
   - `END` ブロックのチェック（`if (in_entry && in_rationale && !has_ref)`）の条件を `in_rationale` から `found_rationale` に変更

## Verification

### Pre-merge

- <!-- verify: command "bats tests/orchestration-fallbacks.bats" --> 修正後も `bats tests/orchestration-fallbacks.bats` が全テスト PASS する
- <!-- verify: rubric "In tests/orchestration-fallbacks.bats test 9, the awk script tracks whether a Rationale section was found within each entry using a variable (e.g., found_rationale) that persists across ### section boundaries. At each ## entry boundary and in the END block, the script checks found_rationale && !has_ref (not in_rationale && !has_ref), so entries with a Rationale section containing no Issue reference are correctly detected even when Rationale is not the last subsection of the entry." --> Rationale セクション検出ロジックが entry-scoped な範囲で正しく機能する（Rationale 後に別セクションがあっても `has_ref` が正しく評価される）

### Post-merge

- `bats tests/orchestration-fallbacks.bats` がすべて PASS することを CI で確認

## Notes

- `found_rationale` は `## ` 境界でリセットされるが `### ` 境界ではリセットされないため、Rationale が中間セクションになった場合でも正しく機能する
- 既存の `in_rationale` フラグは `has_ref` の蓄積範囲（Rationale 内のみ）を限定する役割を引き続き担う（削除不可）

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue受け入れ条件は verifiable な形式で記述されており、`command` + `rubric` の組み合わせで曖昧さを排除。特にrubricの条件文が「`found_rationale` 変数が `###` 境界を越えて持続する」という実装の意図を正確に表現しており、grep では判定できない振る舞いをカバーしている点が良好。

#### design
- Specの実装ステップが具体的で、コミット内容との乖離なし。`found_rationale` 導入と4箇所の変更点が全て正確に記述されていた。

#### code
- fixup/amendパターンなし。設計通りのシングルコミット実装（`2de10bb`）。reworkゼロ。Spec記述と diff が一致。

#### review
- patchルートのため正式PRレビューなし。rubric検証がセマンティックレビューの代替として機能し、entry-scoped な振る舞いを正しく評価。

#### merge
- patchルート（main直コミット）。コンフリクトなし。

#### verify
- 両条件ともPASS。条件1（batsテスト）はコマンド実行で直接確認、条件2（rubric）はdiff解析で意味的に確認。FAIL・UNCERTAINなし。
- PR番号が存在しないpatchルートのため、`github_check "gh pr checks"` 形式は使用されていないが、`command` + `rubric` の組み合わせで検証を完結できた。

### Improvement Proposals
- N/A
