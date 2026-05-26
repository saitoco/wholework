# Issue #485: verify: fork 実行を廃止し parent context で実行（manual AC 確認チャネル + closeout 自動化）

## Overview

`/verify` の forked-session 実行（`context: fork` + `run-verify.sh` ラッパ）を廃止し、parent context で実行する設計に移行する。これにより `AskUserQuestion` が自然に使用可能となり、`<!-- verify-type: manual -->` の post-merge AC を都度確認 → checkbox flip → `phase/verify → phase/done` 遷移 → close を一つのフローで完結できる。

`/auto` chain では `run-verify.sh` 呼び出しを Skill tool 経由の `/verify` 直接実行に置き換える。XL route の sub-issue verify は parent /auto session に委譲し、`run-auto-sub.sh` から verify phase を取り除く（manual AC 確認に user dialog が必要なため、bash subprocess 内では実行不能）。

設計原則として `docs/tech.md` の fork decision table を `verify | No` に更新し、rationale を併記する。

## Changed Files

- `docs/tech.md`: change `| verify | Yes | Verifies post-merge state independently; must not be influenced by prior phase decisions |` → `| verify | No | ...` with new rationale; remove `run-verify.sh` row from "Phase-specific model and effort matrix"; update `verify (skill)` row to drop `run-verify.sh sets medium effort` parenthetical
- `docs/ja/tech.md`: 同等修正を日本語ミラーへ反映
- `docs/structure.md`: remove `- \`scripts/run-verify.sh\` — run verify skill` entry from script listing
- `docs/ja/structure.md`: 同等修正を日本語ミラーへ反映
- `docs/guide/scripting.md`: line 90 — replace `run-verify.sh` example reference with another script (e.g., `run-merge.sh`) or remove example
- `docs/migration-notes.md`: append new migration entry `## Issue #485: run-verify.sh removal` documenting the interface change
- `skills/verify/SKILL.md`: remove `context: fork` frontmatter; remove "Autonomous Mode (--auto)" section; remove "Mode Detection" + `--non-interactive` flag handling; remove "Error Handling in Non-Interactive Mode" table; unify Step 1 dirty file handling (interactive only); replace VERIFY_FAILED line markers with simple error output (no longer wired to wrapper exit code); remove `run-verify.sh` from allowed-tools; add `AskUserQuestion` integration for manual AC verification step
- `skills/auto/SKILL.md`: remove `run-verify.sh` from allowed-tools, add `Skill` tool; in M/L pr route Step 4 verify phase, replace `Bash: run-verify.sh $NUMBER` with `Skill(skill="wholework:verify", args="$NUMBER")`; in patch route, same replacement; in XL route Step 4 sub-issue loop, remove individual sub-issue verify; add new "Step 4d: XL Sub-issue Verify" after Step 4c that iterates sub-issues + parent and invokes `Skill(skill="wholework:verify", args="$SUB_NUMBER")` serially in parent session
- `scripts/run-verify.sh`: delete
- `scripts/run-auto-sub.sh`: delete `run_verify_with_retry()` function (lines 40–62); delete `run_verify_with_retry "$SUB_NUMBER" "${BASE_BRANCH:-}"` invocations (4 occurrences at lines 154, 161, 181, 201); add a note in the Size handling block that verify is deferred to parent /auto session — bash 3.2+ compatible (no syntax change)
- `scripts/detect-wrapper-anomaly.sh`: line 80 `IMPROVEMENT_HINT` — change `retry via \`run-verify.sh $ISSUE_NUMBER\`` → `retry via \`/verify $ISSUE_NUMBER\``; remove or update `dirty-working-tree` references that mention run-verify.sh
- `modules/orchestration-fallbacks.md`: delete or deprecate `verify-sync-retry` section (no longer applicable when run-verify.sh is removed); update `dirty-working-tree` section's `run-verify.sh <issue-num>` references to `/verify <issue-num>` (manual operator invocation)
- `tests/run-verify.bats`: delete (script removed)
- `tests/run-auto-sub.bats`: remove `cat > "$MOCK_DIR/run-verify.sh"` mock block (lines 70–75); remove or rewrite test cases asserting `run-verify.sh` is called (lines 193, 202, 259) — replace assertions with "verify is NOT called by run-auto-sub.sh (deferred to parent /auto)"

## Implementation Steps

**Step recording rules:** integer step numbers, dependencies noted as "(after N)" / "(parallel with N, M)", acceptance criteria mapped via "(→ AC X)". Insertion positions specified by nearby code context.

1. Update `docs/tech.md` fork decision table: change verify row to `| verify | No | mostly mechanical (verify command execution + checkbox update); manual AC confirmation requires AskUserQuestion which cannot run in fork context; FAIL → /code (fork) re-runs so bias propagation risk is low |`. Same update propagated to `docs/ja/tech.md`. Also remove `run-verify.sh` entry from the "Phase-specific model and effort matrix" and update `verify (skill)` row (→ AC1, AC2)

2. Update `skills/verify/SKILL.md` frontmatter: remove `context: fork` line (delete line 4) and remove `${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh:*` from `allowed-tools`. Update `description` field if needed (current description still accurate) (→ AC3)

3. Remove "Autonomous Mode (--auto)" section (lines 15–25) and "Mode Detection" comment block + `--non-interactive` flag detection (lines 27–40) from `skills/verify/SKILL.md`. Remove "Error Handling in Non-Interactive Mode" table (lines 42–53). Replace these with a single "## Mode" section noting "always interactive (runs in caller's context)" (→ AC3)

4. (after 3) Unify Step 1 dirty file handling in `skills/verify/SKILL.md`: remove `--non-interactive` mode auto-stash branch; keep only the AskUserQuestion-based interactive branch. Remove `VERIFY_FAILED` standalone-line markers (no longer wired to wrapper exit code); replace with plain error output to terminal. Apply same simplification to Step 2 OPEN_PR check (→ AC3)

5. (after 3) Add explicit manual AC verification flow to `skills/verify/SKILL.md` Step 5: after auto AC verification, for each `<!-- verify-type: manual -->` condition still unchecked, invoke `AskUserQuestion` to prompt user "Condition X: PASS / FAIL / SKIP?"; record responses; in Step 6 apply PASS responses to checkbox updates; in Step 9 use combined auto + manual results to drive close/reopen logic. Manual FAIL responses count toward FAIL judgment same as auto FAILs (→ AC4)

6. (after 2, 3, 4, 5) Update `skills/auto/SKILL.md` allowed-tools: remove `${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh:*` from Bash list; add `Skill` to top-level tool list. In M/L pr route Step 4 (line 206), replace `run \`${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh $NUMBER ...\` via Bash (timeout: 600000)` with `invoke \`Skill(skill="wholework:verify", args="$NUMBER")\``. Same replacement for patch route Step 4 (line 169). Retain `auto-checkpoint.sh write_single` + verify iteration counter logic unchanged (→ AC5)

7. (after 6) Update `skills/auto/SKILL.md` XL route Step 4: remove implicit verify-via-run-auto-sub.sh assumption. Add new "Step 4d: XL Sub-issue Verify" subsection that runs after all sub-issue levels complete and before Step 4c (XL parent close flow): iterate `[sub_issue_1, sub_issue_2, ..., parent_issue]` and invoke `Skill(skill="wholework:verify", args="$N")` for each, serially in parent session (→ AC5)

8. (after 1, 7) Delete `scripts/run-verify.sh`. Delete `scripts/run-auto-sub.sh` `run_verify_with_retry()` function (lines 40–62, depends on bash compat — no new syntax) and the 4 invocations at lines 154/161/181/201. Add a brief comment in run-auto-sub.sh after the size handling block: `# verify is deferred to parent /auto session (issue #485)` (→ AC6, AC7)

9. (parallel with 8) Update support files:
   - `scripts/detect-wrapper-anomaly.sh` line 80: `run-verify.sh $ISSUE_NUMBER` → `/verify $ISSUE_NUMBER` in IMPROVEMENT_HINT text
   - `modules/orchestration-fallbacks.md`: delete `## verify-sync-retry` section (lines 62–86); update `## dirty-working-tree` section (lines 213–217) to reference `/verify <issue-num>` instead of `run-verify.sh <issue-num>`
   - `docs/structure.md`: remove `- \`scripts/run-verify.sh\` — run verify skill` line; same for `docs/ja/structure.md`
   - `docs/guide/scripting.md` line 90: replace `run-verify.sh` example reference with `run-merge.sh` (also uses `// empty` pattern)
   (→ AC8)

10. (after 1–9) Update tests + migration notes:
   - Delete `tests/run-verify.bats`
   - `tests/run-auto-sub.bats`: remove `MOCK_DIR/run-verify.sh` mock setup (lines 70–75); rewrite test cases at lines 193/202/259 to assert verify is NOT called by `run-auto-sub.sh` (deferred to parent /auto session)
   - `docs/migration-notes.md`: append `## Issue #485: run-verify.sh removal` section documenting (a) script deletion (b) `--auto` / `--non-interactive` flag removal from `/verify` (c) `/auto` invocation pattern change (Bash → Skill tool) (d) `run-auto-sub.sh` verify phase removal (→ AC9, AC10)

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/tech.md" "fork context vs main context" "| verify | No |" --> `docs/tech.md` の fork decision table で verify が `No` に更新されている
- <!-- verify: rubric "docs/tech.md の verify エントリに、fork 廃止の rationale（機械的処理 / AskUserQuestion 必要性 / FAIL 時 bias 伝播低 等）が注記されている" --> verify 非 fork の根拠が明文化されている
- <!-- verify: rubric "skills/verify/SKILL.md から --auto / --non-interactive モード分岐が撤廃され、AskUserQuestion による manual AC 確認フローが追加されている" --> verify skill が parent context 前提の interactive フローに統一されている
- <!-- verify: rubric "skills/verify/SKILL.md に、manual AC PASS 時の checkbox flip + 全 AC PASS 時の phase/done 遷移 + issue close ロジックが記述されている" --> closeout 自動化が実装されている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "run-verify.sh" --> `skills/auto/SKILL.md` の verify phase 呼び出しが `run-verify.sh` から Skill tool 経由に置き換わっている
- <!-- verify: file_not_exists "scripts/run-verify.sh" --> `scripts/run-verify.sh` が削除されている
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "run-verify.sh" --> `scripts/run-auto-sub.sh` の `run-verify.sh` 参照が除去されている
- <!-- verify: file_not_contains "modules/orchestration-fallbacks.md" "run-verify.sh" --> `modules/orchestration-fallbacks.md` の `run-verify.sh` 参照が更新されている
- <!-- verify: github_check "gh pr checks --json name,state --jq '[.[] | select(.name | test(\"bats\"; \"i\")) | .state] | unique | join(\",\")'" "SUCCESS" --> bats テスト CI ジョブが PR で SUCCESS
- <!-- verify: rubric "run-verify.sh への参照が tests/、docs/、modules/ から一掃されている（docs/migration-notes.md と tests/fixtures/orchestration-recoveries-sample.md などの履歴/サンプル系を除く）" --> 周辺コードベースから run-verify.sh 参照が一掃されている

### Post-merge

- phase/verify 状態の代表的な Issue で `/verify N` を実行し、manual AC の confirm → checkbox flip → phase/done 移行が一括で行えることを確認
- `/auto N` を実行し、verify phase で manual AC が parent context の AskUserQuestion で都度確認されることを確認
- downstream プロジェクトでの manual closeout ceremony が削減されることを観察

## Notes

### Auto-Resolved Ambiguity Points (詳細)

- **A1: XL sub-issue verify の実行場所** → parent /auto session で serial 実行（`run-auto-sub.sh` から verify を取り除く）
  - 理由: bash subprocess 内では user dialog (AskUserQuestion) が user に届かない。XL 並列実行の利点は code/review/merge phase で保持され、verify は manual AC 確認のため本質的に serial。並列化喪失のコストは低い
- **A2: `run-verify.sh` の扱い** → 完全削除（CI/cron 等の非対話用途も /auto 経由 or 手動 /verify N で代替）
- **A3: VERIFY_FAILED marker** → 削除（wrapper exit code への配線が不要になるため）
- **A4: verify-iteration counter** → 維持（`get-verify-iteration.sh` + コメントマーカー方式は parent context でも有効）
- **A5: /verify 内の worktree (verify/issue-$NUMBER)** → 維持（main branch との衝突回避に有効、parent context 化と独立）

### Implementation Uncertainty (Notes)

- **Skill tool の skill→skill 呼び出し可否**: `/auto` から `Skill(skill="wholework:verify", args="N")` 形式で別 skill を invoke 可能か未検証。代替案として `Read skills/verify/SKILL.md and follow the Processing Steps section` パターン（既存の "Read and follow" 慣行）も使える。`/code` の実装時に確認し、Skill tool が skill→skill で動作しない場合は "Read and follow" 方式に切替
- **manual AC 数が多い場合の UX**: post-merge に manual AC が 4+ 件ある Issue で AskUserQuestion を 4 回繰り返すと冗長。一括提示（multiSelect で「全 PASS」/「個別判定」を 1st step で問う）を実装するか、initial Issue 起票時に manual AC 数を抑える運用ルールを併用するかは `/code` 時に判断
- **detect-wrapper-anomaly.sh の dirty-working-tree パターン**: 現在 verify wrapper exit code を起点に検出している。`run-verify.sh` 削除後は同パターンが他の wrapper (run-code.sh 等) からの異常検出のみに使われる。`dirty-working-tree` anomaly 自体は維持し、IMPROVEMENT_HINT の手動オペレータ向けメッセージのみ更新

### bats test mock 追加チェック

- `run-auto-sub.bats` の `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` 経由で `run-verify.sh` mock が配置されていたが、削除に伴い該当 mock も削除する必要がある（Implementation Step 10 で対応）

### docs/ja/ sync

- `docs/translation-workflow.md` のルール上、`docs/tech.md` と `docs/structure.md` 更新時は `docs/ja/tech.md` / `docs/ja/structure.md` も同期する必要がある（Implementation Step 1 と Step 9 で含む）

### Migration notes (per project memory)

- `~/.claude/projects/.../memory/project_migration_notes.md` のメモリに記載の通り、`scripts/` 配下のインターフェース変更は `docs/migration-notes.md` に追記する。本 Issue では `run-verify.sh` 完全削除と `/auto` 呼び出しパターン変更が該当（Implementation Step 10 で対応）

### Section rename impact check

- `skills/verify/SKILL.md` 内の section 番号は変更しない（Step 1, Step 2, ... の番号体系維持）。`section_contains` verify command を持つ参照側 (もし存在すれば) への影響なし
