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

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `agents/review-bug.md` に "Test Replacement Scenario Coverage" ブロックを `### 1. Bug/Logic Error Detection` 内の LLM-to-Shell Pattern Migration Risks の直後に配置 — 既存パターンとの流れを維持し一貫性を保つ
- `skills/spec/skill-dev-constraints.md` の `bats self-reference exclusion` 行の直後に新 SHOULD 制約行を配置 — bats テスト関連制約の近傍に置くことで文脈的な関連性を明示
- commit prefix を `feat:` で統一 — Issue Type は Task だが additive なガイドライン追加はfeatureとして解釈（`chore:` のほうが厳密だが変更済みのためそのまま）

### Deferred Items
- `spec_depth: full` ロック条件により `skill-dev-constraints.md` は Wholework 自身の L/XL 開発時のみロード — 汎用プロジェクトへの普及は `agents/review-bug.md` 側が担う（Spec Notes 参照）

### Notes for Next Phase
- verify phase では rubric チェック（review-bug agent への追加）と CI green を確認すること
- post-merge observation: 次に bats テスト置き換えを含む PR がレビューされた際に、削除テストのシナリオ網羅が実際に捕捉されるか観察する

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 2件（rubric / github_check）自動検証可能。`agents/review-bug.md`（汎用）と `skills/spec/skill-dev-constraints.md`（Wholework 自身向け）の二段構えの設計が妥当。

#### code
- 実装はクリーン（commit `fb487cc` が closes #526 で main マージ済み）。ただし #523 と同様、`/auto --batch` patch route の code phase で **false-positive silent-no-op アノマリ**が検出された（detector が origin/main push 前に local git log を確認したため）。

#### verify
- pre-merge AC 2/2 PASS。post-merge opportunistic 1件が未チェックのため phase/verify 維持。

### Improvement Proposals
- **silent-no-op detector の patch-route race**（#523 verify retrospective と同一論点、retro-proposals 側で重複排除）: `detect-wrapper-anomaly.sh` が patch-route の origin/main push 前に local git log を検査するため false positive となる。本バッチで #523・#526 の 2 件発生。改善詳細は #523 の提案を参照。
