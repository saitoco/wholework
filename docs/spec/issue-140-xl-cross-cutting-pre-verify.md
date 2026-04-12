# Issue #140: auto: XL 親 Issue の横断条件を sub-issue 完了時に先行検証

## Overview

XL Issue の `/auto` オーケストレーションで、各レベルの sub-issue が完了するたびに親 Issue の横断的 Acceptance Criteria の verify command を先行実行する。失敗した場合は警告を出力するが処理を中断しない（ベストエフォート）。既存の `/verify N` による事後検証フローは変更しない。

実装場所: `skills/auto/SKILL.md` Step 4 XL route の aggregate-update ブロック直後に新しいサブステップを追加。

## Changed Files

- `skills/auto/SKILL.md`: frontmatter `allowed-tools` に `Grep` を追加 + Step 4 XL route の aggregate-update 後に cross-cutting condition pre-verification サブステップを追加

## Implementation Steps

1. `skills/auto/SKILL.md` frontmatter の `allowed-tools` 末尾に `, Grep` を追加する（verify-executor.md が `file_contains` / `grep` チェックで Grep ツールを使用するため）（→ 受入条件 3）

2. `skills/auto/SKILL.md` Step 4 XL route の「**After `wait` completes, aggregate-update parent phase**」ブロック（item 3: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER <aggregated phase>` の直後）に以下のサブステップを追加する（→ 受入条件 1, 2）:

   ```
   **After aggregate-update, cross-cutting condition pre-verification (best-effort)**:
   When a level completes, proactively check the parent XL Issue's cross-cutting Acceptance Criteria:
   1. Fetch parent Issue body: `gh issue view $NUMBER --json body -q '.body'`
   2. Extract `<!-- verify: ... -->` commands from the Acceptance Criteria sections (pre-merge and post-merge)
   3. Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and execute each verify command in full mode
   4. For each FAIL result: output a warning and continue (best-effort cross-cutting condition detection)
      Format: "Warning: cross-cutting condition failed: [condition text]. Run `/verify $NUMBER` to confirm."
   5. Continue to the next level regardless of results (authoritative verification is done by `/verify $NUMBER`)
   ```

3. `python3 scripts/validate-skill-syntax.py skills/` を実行し、エラーゼロを確認する（→ 受入条件 3）

## Verification

### Pre-merge

- <!-- verify: grep "cross-cutting" "skills/auto/SKILL.md" --> `/auto` skill の XL orchestration セクションに親 Issue 横断条件先行検証の記述が追加されている
- <!-- verify: grep "verify command" "skills/auto/SKILL.md" --> `/auto` skill で横断条件の verify command 実行が記述されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> 変更後の `skills/auto/SKILL.md` が構文検証を PASS する

### Post-merge

- XL Issue に横断条件（verify command 付き）を設定した状態で `/auto` を実行し、sub-issue 完了時に横断条件が先行検証されることを確認

## Notes

- **既存フローとの関係**: Step 4c（XL Parent Issue Close Flow）はチェックボックス（`- [ ]`）ベースの最終ゲーティングで変更なし。本変更は「レベル完了ごとに verify command を実行して警告」を追加するもので、Step 4c とは補完関係。
- **ベストエフォート**: 失敗時は警告出力のみ（中断なし）。事後 `/verify` が権威的な検証となる（Issue body Auto-Resolved 反映）。
- **`Grep` 追加理由**: verify-executor.md の `file_contains` / `grep` タイプが Grep ツールを使用するため。現在の `/auto` allowed-tools に Grep が含まれていない。
- **挿入位置**: aggregate-update の item 3（`gh-label-transition.sh`）直後。行番号ではなくコードコンテキスト（`${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER <aggregated phase>`）で指定。
- **docs/workflow.md・README.md・CLAUDE.md 更新不要**: 変更は XL オーケストレーションの内部実装（ベストエフォート警告追加）であり、ワークフローフェーズや外部から見える動作に変化なし。

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design

- なし。Spec の実装手順通りに実施した。

### Design Gaps/Ambiguities

- なし。Spec は明確で実装上の問題は発生しなかった。

### Rework

- なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec の受入条件はすべて `<!-- verify: ... -->` 付きで設計されており、自動検証精度が高かった。
- Spec Retrospective は N/A（設計上の問題なし）。

#### design
- 実装は Spec の手順通りに完了。設計とのズレなし。
- patch route（PR なし）での直接 main コミット実装。

#### code
- リワークなし。`ee10fc9` 1コミットで実装完了。
- Code Retrospective でも「Spec の実装手順通り」と記録されており、設計と実装の一致を確認。

#### review
- PR なし（patch route）のため、コードレビューは実施されていない。
- 変更範囲が `skills/auto/SKILL.md` の 1ファイルのみと小規模だったため、patch route の判断は適切。

#### merge
- patch route で直接 main にコミット・プッシュ。コンフリクトなし。

#### verify
- Pre-merge 全3条件 PASS（grep 2件 + 構文検証 1件）。
- Post-merge 条件（opportunistic）は XL Issue での `/auto` 実行確認が必要であり、ユーザー検証ガイドとして提示した。

### Improvement Proposals
- N/A
