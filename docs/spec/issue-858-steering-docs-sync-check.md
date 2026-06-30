# Issue #858: spec: SKILL.md/scripts 変更時に Steering Docs 同期候補を自動列挙

## Overview

`/spec` の Step 10 (Create Spec) において、Changed Files に `SKILL.md` や `scripts/` 配下のファイルが含まれる場合に、関連する Steering Docs (`docs/*.md`, `docs/ja/*.md`) を grep で抽出し、Spec の Changed Files セクションに sync 候補として列挙するサブステップを追加する。

これにより「SKILL.md 改修を伴う Issue の `/code` 実装中に workflow.md 等の記述が古いことを事後発見する」摩擦を防ぐ。Proposal A (Processing Steps 内にステップ追加) を採用。

## Consumed Comments

- saito (MEMBER / first-class) — 2026-06-30: Issue Retrospective コメント。曖昧ポイント 3 件の自動解決 (Proposal A 採用, grep スコープは docs/*.md 全体, bats テスト不要) と AC の具体化を記録。
  URL: https://github.com/saitoco/wholework/issues/858#issuecomment-4840567245

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の `doc-checker.md` 参照行の直後に **Steering Docs sync candidate check** サブステップを追加

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10、「`Read \`${CLAUDE_PLUGIN_ROOT}/modules/doc-checker.md\` and use the "Impact Assessment" section...`」行の直後 (`**\`docs/ja/\` translation sync check:**` の手前) に下記サブステップを挿入する (→ AC1, AC2):

```
**Steering Docs sync candidate check (when Changed Files includes SKILL.md or scripts/):**

When the Spec's Changed Files section includes `SKILL.md` files (e.g., `skills/auto/SKILL.md`) or files under `scripts/`, run a grep across `docs/*.md` and `docs/ja/*.md` to find Steering Documents that reference the changed skill or script name. List found files as Steering Docs sync candidates in the Changed Files section.

Steps:
1. Extract the skill name or script filename from each changed file:
   - `skills/{name}/SKILL.md` → keyword: `{name}` (e.g., `auto`, `spec`)
   - `scripts/{script-name}.sh` → keyword: `{script-name}.sh` (e.g., `run-code.sh`)
2. For each keyword, run:
   ```bash
   grep -l "<keyword>" docs/*.md docs/ja/*.md 2>/dev/null
   ```
3. For each file found, add a **Steering Docs sync candidate** entry to the Changed Files section:
   e.g., `docs/workflow.md`: [Steering Docs sync candidate] verify that description of `<keyword>` is up to date; update if needed
4. The `/code` phase makes the final include/exclude decision by reading each candidate; listing them here prevents silent omission at implementation time

**Skip** if Changed Files does not include SKILL.md files or files under `scripts/`.
```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Processing Steps に、Changed Files が SKILL.md または scripts/ ファイルを含む場合に Steering Docs を grep して関連参照を Spec の Changed Files セクションに sync 候補として記録するステップが追加されている" --><!-- verify: grep "Steering Docs sync|sync candidate" "skills/spec/SKILL.md" --> `/spec` Processing Steps に Steering Docs sync candidate check ステップが存在する
- <!-- verify: rubric "skills/spec/SKILL.md の当該ステップ内に、SKILL.md や scripts/ のファイル名から docs/*.md docs/ja/*.md を grep して参照を抽出する具体的なコマンド例または説明が含まれており、grep ロジックが確認可能である" --><!-- verify: file_contains "skills/spec/SKILL.md" "docs/*.md" --> ステップ内に `docs/*.md` / `docs/ja/*.md` を grep するコマンド例が存在する

### Post-merge

- 次回 SKILL.md 改修を伴う Issue の `/spec` 実行時に、Steering Docs sync 候補が Changed Files セクションに自動列挙されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

### Auto-resolved ambiguity (non-interactive mode)

| 曖昧ポイント | 選択 | 根拠 |
|---|---|---|
| 実装方針: Proposal A/B/C | **Proposal A** (Processing Steps 内にステップ追加) | Issue body に「A が最も小規模で実装可能」と明記。Size=S の scope とも整合 |
| grep 抽出スコープ | **docs/*.md docs/ja/*.md 全体** | Proposal A のコマンド例から推定。広くすることで sync 漏れを防ぐ |
| AC の確認方法 | **SKILL.md ステップ内のコマンド例** (bats test 不要) | Size=S の patch route でテストファイル追加は過剰 |

### Insertion position

`skills/spec/SKILL.md` Step 10 の `doc-checker.md` 参照行の直後 (「Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-checker.md` and use the "Impact Assessment" section to decide whether to include documentation files in the changed-files list.」行末の直後)、`**\`docs/ja/\` translation sync check:**` の手前に挿入する。これは doc-checker の companion check として論理的に隣接する位置。

### Simplicity check

- Changed Files: 1 ファイル (制限 5 以内 ✓)
- Implementation Steps: 1 ステップ (制限 5 以内 ✓)
- Verification Pre-merge: 2 項目 (制限 5 以内 ✓)

### doc-checker check result

Changed File が `skills/spec/SKILL.md` (skill change) のため `skill-dev-doc-impact.md` Change Types に該当するが、今回の変更は Step 10 内部の処理サブステップ追加であり、`/spec` スキルの外部インターフェース (入力・出力・フェーズ動作) に変化なし。`docs/workflow.md` / `README.md` / `CLAUDE.md` は `/spec` を高レベルで記述するのみで、内部処理ステップの詳細は記述していない。よって各ファイルの更新は不要と判断。

## Code Retrospective

### Deviations from Design

- None. Implementation matched the spec exactly — the subtext was inserted at the specified location (after doc-checker.md reference, before `docs/ja/` translation sync check) in Step 10 of `skills/spec/SKILL.md`.

### Design Gaps/Ambiguities

- None. The spec's "Insertion position" Note section was sufficiently precise to locate the insertion point unambiguously in the actual file.

### Rework

- None. Single insertion, no rework needed.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented Proposal A (Processing Steps subtext addition) as specified: added the Steering Docs sync candidate check block directly into `skills/spec/SKILL.md` Step 10 between the doc-checker reference and the `docs/ja/` translation sync check.
- Did not add bats tests (consistent with Spec Notes: bats tests are not required for this XS/S-scope change; the verify commands check SKILL.md content directly).
- Both pre-merge ACs verified PASS via grep/file_contains; rubric judgment also PASS.

### Deferred Items
- Post-merge observation: confirm that the next `/spec` run on a SKILL.md-editing Issue actually lists Steering Docs sync candidates in Changed Files (verify-type: observation).

### Notes for Next Phase
- The `## Consumed Comments` section was not written by LLM (no comments since last phase cutoff). The bash wrapper will handle this if needed.
- No documentation sync was needed (the change is internal to `skills/spec/SKILL.md`, no external interface change).
