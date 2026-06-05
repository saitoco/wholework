# Issue #526: review/spec: テスト置き換え時に削除テストのシナリオ網羅を確認するガイドラインを追加

## Overview

テスト置き換え/リファクタ時に、削除テストが検証していたシナリオを新テストが全てカバーしているかを確認するガイドラインを追加する。
追加先は `agents/review-bug.md`（review 側チェック観点）と `skills/spec/skill-dev-constraints.md`（spec 側 SHOULD 制約）の 2 か所。

背景: #520 の `/review`（full）で削除テストの等価新テストが欠落していたことがレビューで捕捉された。
今後はレビュー検出依存ではなく、ガイドラインとして明文化することで構造的に防止する。

## Changed Files

- `agents/review-bug.md`: `### 1. Bug/Logic Error Detection` の "**LLM-to-Shell Pattern Migration Risks:**" ブロックの直後に "**Test Replacement Scenario Coverage:**" ブロックを追加 — bash 3.2+ 非依存（Markdown 変更のみ）
- `skills/spec/skill-dev-constraints.md`: SHOULD 制約テーブルに `| Test replacement scenario coverage | ... | #526 |` 行を追加（`bats self-reference exclusion` 行の直後）— bash 3.2+ 非依存（Markdown 変更のみ）

## Implementation Steps

1. `agents/review-bug.md` を編集: 行 `- Report at SHOULD level if false positive sources exist and no exclusions are present` の直後（空行を挟んで、`### 2. False Positive Filtering` の前）に以下ブロックを挿入 (→ AC1)

   ```markdown
   **Test Replacement Scenario Coverage:**
   When the PR deletes or replaces existing test cases (lines starting with `-` that contain `@test`, test function definitions, or similar markers):
   - Identify the scenarios and behaviors verified by the deleted tests (inspect test names and assertion logic in `-` lines)
   - Check whether new or remaining tests cover all those deleted-test scenarios
   - Report at SHOULD level if a deleted test's scenario is not covered by any new or remaining test
   - Note: this is distinct from "Insufficient test coverage" (filter criterion 4); it detects coverage regression when existing tests are replaced, not missing tests for new code
   ```

2. `skills/spec/skill-dev-constraints.md` を編集: `| bats self-reference exclusion | ... | #272 |` 行の直後に以下の行を挿入 (→ AC1)

   ```
   | Test replacement scenario coverage | When implementation includes deleting or replacing existing test cases (e.g., bats `@test` blocks), verify that all scenarios covered by deleted tests are present in new or remaining tests | #526 |
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "review（review-bug agent または review SKILL の spec-deviation perspective）もしくは spec の制約チェックリストに、テスト削除/置き換えを含む変更で『削除テストが検証していたシナリオを新テストが全てカバーしているか』を確認するガイダンスが追加されている" --> テスト置き換え時のシナリオ網羅チェックのガイダンスが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI が green

### Post-merge

- 次にテスト置き換えを含む PR の review で、削除テストのシナリオ網羅が確認されるか観察

## Notes

- `skills/spec/skill-dev-constraints.md` は `load_when: spec_depth: full` かつ `file_exists_any: [scripts/validate-skill-syntax.py]` のため、Wholework 自身の開発 (L/XL) の場合のみロードされる。汎用プロジェクトへの適用は `agents/review-bug.md` 側の変更（Step 1）が担う。
- フィルター criterion 4 ("Insufficient test coverage") との区別: 新ブロックの Note 行で明示。テスト置き換え時の regression 検出は criterion 4 の対象外であるため、既存フィルター条件の変更は不要。
