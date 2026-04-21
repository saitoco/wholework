# Issue #299: /code の Stale Test Assertion Check を existence gate で囲む

## Overview

`skills/code/SKILL.md` Step 8 の `#### Stale Test Assertion Check` サブセクションに、明示的な existence gate を追加する。

現状は末尾に暗黙的な skip 文（"Skip this check if no files under..."）があるのみで、以下の問題がある:
1. `tests/` ディレクトリがないプロジェクトでも grep 処理が走る
2. `scripts/`, `modules/`, `skills/` が wholework 固有のディレクトリであることが明示されていない

サブセクション冒頭に skip 条件を明示し、末尾の暗黙的な skip 文を gate に統合する。

## Changed Files

- `skills/code/SKILL.md`: `#### Stale Test Assertion Check` サブセクション冒頭に existence gate を追加し、末尾の暗黙的な skip 文を削除する

## Implementation Steps

1. `skills/code/SKILL.md` の `#### Stale Test Assertion Check` 見出し（line 186）直後（"After completing implementation changes..." の前）に existence gate を挿入:

   ```
   **Existence gate**: skip this check if any of the following conditions hold:
   - `tests/` directory does not exist
   - None of the target directories (`scripts/`, `modules/`, `skills/`) exist

   (`scripts/`, `modules/`, and `skills/` are wholework-specific directory names; other projects may use different naming conventions such as `src/`, `lib/`.)
   ```

2. 末尾の "Skip this check if no files under `scripts/`, `modules/`, or `skills/` were changed." 行（line 206）を削除する（gate に統合）

## Verification

### Pre-merge

- <!-- verify: rubric "In skills/code/SKILL.md Step 8 'Stale Test Assertion Check' subsection, an explicit existence gate is documented at the top of the subsection that skips the check when either the tests/ directory is absent or none of the target wholework-specific directories (scripts/, modules/, skills/) exist" --> 先頭に明示的な existence gate が追加されている
- <!-- verify: grep "Stale Test Assertion" "skills/code/SKILL.md" --> Stale Test Assertion サブセクションが存在する

### Post-merge

- wholework リポ自身で `/code` を実行し、Stale Test Assertion Check が従来通り動作することを確認
- `tests/` ディレクトリのないプロジェクトで `/code` を実行し、この節が skip されることを確認

## Notes

- ISSUE_TYPE=Task のため Uncertainty・UI Design セクションは省略
- existence gate の 2 条件（`tests/` 存在チェック + 対象ディレクトリ存在チェック）は論理 OR（どちらか 1 つでも欠ければ skip）
- 末尾の "Skip this check if no files were changed" は、git diff が空結果を返すため自然に skip される。明示 gate にすることで意図が明確になる

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
- Spec の Implementation Steps がそのまま実装できる粒度で記述されており、実装者の解釈余地がなく高品質。
- 受け入れ条件には `rubric` と `grep` の両方が添付されており、意味的確認と機械的確認が適切に組み合わされていた。

#### design
- Spec は Issue の Changes セクションをほぼ忠実に実装計画に変換しており、設計上の乖離なし。
- 末尾の暗黙的 skip 文を gate に「統合（削除）」するという方針が Notes で明示されており、実装でも正しく削除されていた。

#### code
- コミット1本で完結（リワークなし）。Spec との乖離なし。
- wholework 固有ディレクトリ名を注記として添えた点は Spec に明記されていたとおりであり、Phase 2 の Domain 抽出への配慮が適切に実現されている。

#### review
- パッチルート（PR なし）のため正式なレビューなし。Issue の設計確認コメントで実装意図は共有済み。
- シンプルな文書変更であり、正式レビューなしでも品質リスクは低い。

#### merge
- パッチルート（main 直コミット）、競合なし。

#### verify
- 自動検証2条件いずれも PASS。
- ポストマージの手動条件（`tests/` 不在プロジェクトでの動作確認）は実行環境の用意が必要なため自動化困難。

### Improvement Proposals
- N/A
