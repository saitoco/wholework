# Issue #307: review: LLM チェックをシェルスクリプトに移譲する際の grep パターン false positive チェックリストを追加

## Overview

`/review` の `review-bug` エージェントに、LLM 実行チェックをシェルスクリプト（grep/awk パターン）に移譲する際の false positive リスクを検出するチェック項目を追加する。

背景：Issue #303 の実装で conflict marker チェックを LLM からシェルスクリプトに移譲した際、`grep -rn '<<<<<<' .` がテストフィクスチャ（`.bats` の `echo '<<<<<<'`）やドキュメント内コードフェンスに false positive を起こした。LLM は暗黙的にこれらをフィルタリングできるが、シェルスクリプトはできない。この種の実装パターンを `/review` で検出できるよう `agents/review-bug.md` に検出ロジックを追加する。

## Changed Files

- `agents/review-bug.md`: `### 1. Bug/Logic Error Detection` セクションに **LLM-to-Shell Pattern Migration Risks** 検出カテゴリを追加

## Implementation Steps

1. `agents/review-bug.md` の `### 2. False Positive Filtering` 見出しの直前に、以下の新しい検出カテゴリを追加する (→ AC1)

   追加テキスト（英語）：

   ```
   **LLM-to-Shell Pattern Migration Risks:**
   When the PR replaces an LLM-executed check with a grep/awk/sed shell script pattern (e.g., migrating conflict marker detection from LLM to `grep -rn '<<<<<<' .`):
   - Check if the pattern may match false positives in test fixture files (e.g., `.bats` files containing `echo '<<<<<<'` as test data)
   - Check if the pattern may match documentation examples in code fences or backtick-enclosed content (e.g., SKILL.md or module files that demonstrate the pattern)
   - Check if an exclusion mechanism (`grep -v`, `--exclude`, path scoping, etc.) is absent for known false positive sources
   - Report at SHOULD level if false positive sources exist and no exclusions are present
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "Either skills/review/SKILL.md or agents/review-bug.md contains an explicit check or instruction to detect false positive risks when grep/awk shell script patterns replace LLM-executed checks" --> `skills/review/SKILL.md` または `agents/review-bug.md` に、LLM チェックをシェルスクリプト（grep/awk パターン）に移譲する際の false positive リスクをチェックするための記述が追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 既存 bats テストが引き続き CI で PASS する

### Post-merge

- 実際に LLM 側チェックをシェルスクリプトに移譲する実装 Issue で `/review` を実行した際、新規チェックリスト項目が review 結果に反映されることを確認

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
- Spec は簡潔で変更対象ファイルと追加テキストが明確に定義されており、実装への迷いが生じる余地がなかった。
- Auto-Resolved Ambiguity Points（Issue body 内）が3件記録されている：(1) verify command を grep パターンから rubric に変更（日本語マッチ回避）、(2) 実装対象を `agents/review-bug.md` にも拡張、(3) AC2 を github_check に切り替え（patch route 対応）。spec 作成時点でこれらを検知・解消できており、後工程での手戻りが防止された。

#### design
- 実装ステップが1ファイルへの1箇所追加に限定されており、設計の逸脱リスクが低かった。実際に実装はSpec通りに完遂された（Code Retrospective: N/A）。

#### code
- 実装は単一コミット（a22acb0）で完結。fixup/amend なし。rework なし。
- PR を経由しない patch route であったため、review による指摘は発生していない。

#### review
- patch route のため `/review` は実行されていない。review phase をスキップしても問題ない規模の変更だった（1ファイル・7行追加）。
- Post-merge の手動条件（実際の `/review` 実行で新チェック項目が反映されることを確認）は未検証のまま phase/verify に留まっている。

#### merge
- PR なしの直接 main マージ（patch route）。コンフリクト・CI 失敗なし。

#### verify
- Pre-merge 条件2件はいずれも PASS。verify command の設計（rubric + github_check）が適切で、auto-verify が完全に機能した。
- Post-merge 手動条件（verify-type: manual）は未チェック。手動確認後に `/verify 307` の再実行が必要。

### Improvement Proposals
- N/A
