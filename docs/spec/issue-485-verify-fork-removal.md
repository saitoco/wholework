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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec retrospective が `## spec retrospective` セクションに詳細記録されており品質は高い。AC count が 10 件ちょうど（上限）で設計変更への余地が狭い点を注記していたが、実装ではすべての条件が充足された。
- Specの「Changed Files」が13ファイルと広範で、size L の実装として適切に範囲を管理していた。

#### design
- Spec retrospective の "Judgment rationale" に主要な設計判断（XL sub-issue verify の parent 委譲、run-verify.sh 完全削除、VERIFY_FAILED marker 削除）が明文化されており、実装との乖離なし。
- `detect-wrapper-anomaly.sh` の dead code 化（`VERIFY_FAILED` 検出パターンが run-verify.sh 削除で経路消滅）が Spec では cleanup AC として設けられなかった。Review retrospective でも指摘されている。これはSpecの変更ファイル一覧に影響連鎖を明記する習慣で防げた可能性がある。

#### code
- 実装コミット649f307はsquash merge（5コミット）で、各作業ステップが明確に分離されており読みやすい。
- reviewコメント（1件）を取り込んだ痕跡は見当たらない（review timeのコメントが実装前に行われたことを示唆）。fixup/amend パターンは確認されず、設計から実装への一本道。
- Spec の「Implementation Uncertainty: Skill tool の skill→skill 呼び出し可否」は実機で検証され、Skill tool 経由で正常動作することが確認された。

#### review
- PR #498 に review が1件あり、accept済み。review retrospective では2件の SHOULD 指摘（detect-wrapper-anomaly.sh の dead code 化、Step 4d の --base フラグ伝播が Spec に未記載）が記録されている。
- 2件のSHOULD指摘はいずれも「削除した機能の後処理が Spec に書かれなかった」パターン。影響連鎖の追跡を Spec の Changed Files セクションに組み込むことで防げる。
- 10件の pre-merge AC が全て PASS であり、review が見落とした FAIL はなし。

#### merge
- PR #498 は正常にsquash merge済み（2026-05-26）。コンフリクト解消の痕跡なし。

#### verify
- Pre-merge 全10条件 PASS。Post-merge 3条件（verify-type: manual）は実際のシステム動作確認が必要なため未確認（phase/verify 維持）。
- `docs/ja/reports/` 配下のレポートに run-verify.sh 参照が残っていたが、履歴系文書として適切に除外判定できた。rubric の「履歴/サンプル系を除く」という記述が docs/spec/ および docs/ja/reports/ の扱いに十分な指針を提供していた。
- **再 verify 実行（2026-05-26）**: Post-merge 3条件（verify-type: manual）が全てチェック済みであることを確認。全条件 PASS → phase/done 遷移完了。Issue #485 は正式にクローズ。

### Improvement Proposals
- **Spec の Changed Files に影響連鎖を明記する習慣を導入**: 機能削除時、削除対象を参照する関連ファイルを「影響連鎖」として Changed Files に列挙し、cleanup AC を設けることを標準化する（detect-wrapper-anomaly.sh パターンの再発防止）。
- **フラグ伝播の明示化**: `run-*.sh` から Skill 呼び出しへの移行時、「伝播すべきフラグ」（例: `--base`）を Spec の変更ファイル一覧に明記する慣行を整備する（Step 4d の `--base` フラグ未伝播パターンの再発防止）。

### bats test mock 追加チェック

- `run-auto-sub.bats` の `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` 経由で `run-verify.sh` mock が配置されていたが、削除に伴い該当 mock も削除する必要がある（Implementation Step 10 で対応）

### docs/ja/ sync

- `docs/translation-workflow.md` のルール上、`docs/tech.md` と `docs/structure.md` 更新時は `docs/ja/tech.md` / `docs/ja/structure.md` も同期する必要がある（Implementation Step 1 と Step 9 で含む）

### Migration notes (per project memory)

- `~/.claude/projects/.../memory/project_migration_notes.md` のメモリに記載の通り、`scripts/` 配下のインターフェース変更は `docs/migration-notes.md` に追記する。本 Issue では `run-verify.sh` 完全削除と `/auto` 呼び出しパターン変更が該当（Implementation Step 10 で対応）

### Section rename impact check

- `skills/verify/SKILL.md` 内の section 番号は変更しない（Step 1, Step 2, ... の番号体系維持）。`section_contains` verify command を持つ参照側 (もし存在すれば) への影響なし

## spec retrospective

### Minor observations
- Skill tool の skill→skill 呼び出し可否は未検証。Notes に Uncertainty として記録済み。`/code` 実装時に実機で確認し、動かなければ "Read and follow" 慣行へフォールバック
- AC count が full template 上限 10 件ちょうど。これ以上の AC 追加要求があれば実装ステップの整理（共通化）が必要
- 影響範囲は最終的に 13 ファイル（skills 2 + scripts 3 + modules 1 + docs 5 + tests 2）。Size L 維持で妥当だが、複数 skill にまたがるため `/code` で worktree 内の並行編集はせず順次編集すべき

### Judgment rationale
- **XL sub-issue verify を parent /auto session に委譲**: bash subprocess 内で AskUserQuestion が user に届かない構造的制約のため。並列実行の利点は code/review/merge に保持され、verify は manual AC 確認のため本質的に serial で問題なし
- **run-verify.sh 完全削除**: 「verify は parent context」原則の徹底のため deprecation shim を残さない。CI/cron 用途は当面 `/auto` 経由でカバー
- **VERIFY_FAILED marker 削除**: wrapper exit code への配線が不要になるため。skill 内エラー出力で十分

### Uncertainty resolution
- **A1 (XL sub-issue verify 実行場所)**: parent /auto session で serial 実行に決定。run-auto-sub.sh から verify を取り除く（Implementation Step 7, 8）
- **A2 (run-verify.sh 扱い)**: 完全削除に決定（Implementation Step 8）
- **A3 (VERIFY_FAILED marker)**: 削除に決定（Implementation Step 4）
- **A4 (verify-iteration counter)**: 維持に決定（Implementation Step 5 で言及）
- **A5 (/verify 内 worktree)**: 維持に決定（変更不要）
- **未解決 (Skill tool skill→skill)**: Notes に記録し /code 時に検証。動かなければ "Read and follow" 慣行へ

## review retrospective

### Spec vs. 実装乖離パターン

記録なし。実装はすべての Spec ステップに沿っており、10 件の pre-merge AC が全 PASS。

### 繰り返し指摘パターン

2 件の SHOULD 指摘があり、いずれも「削除した機能の後処理」カテゴリ:
1. `detect-wrapper-anomaly.sh` の `VERIFY_FAILED` 検出パターンが dead code 化 — `run-verify.sh` 削除で経路消滅したが、スクリプトとドキュメントが旧状態のまま残った。`run-verify.sh` 削除時に同スクリプト内の `dirty-working-tree` パターンも合わせて cleanup する AC を設けておくべきだった。
2. Step 4d の `--base` フラグ伝播が Spec に記載されていなかった — 旧 `run-verify.sh` 呼び出しでは `[--base ${BASE_BRANCH}]` 伝播を明記していたが、Skill 呼び出しへの置き換え時に引き継がれなかった。Spec の変更ファイル一覧に「伝播すべきフラグ」を明記する慣行があると防げた。

### 受け入れ条件検証の難易度

UNCERTAIN なし。全条件が file-based か bats CI で機械的に検証可能。`section_contains` verify command で 5 行以上離れた内容を参照した場合に grep -A5 が不十分で一時 FAIL 判定になったが、ファイル直読みで補完。Spec の verify command はそのままで問題なし。

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| code | pr | SUCCESS (watchdog kill, reconciled) | 1800s silent → SIGTERM、`reconcile-phase-state.sh code-pr --check-completion` で PR #498 検出により override success |
| review | pr | SUCCESS (header drift, manual override) | exit 0、CI 全 PASS、AC 全 PASS、MUST 0 / SHOULD 2 (→ #503, #504)。ただし PR comment header が `## レビュー回答サマリ` (JA) で SSoT `## Review Response Summary` (EN) と不一致 → reconciler mismatch、実体は成功のため manual override |
| merge | pr | SUCCESS | PR #498 MERGED |
| verify | — | SUCCESS (Skill tool path) | 旧 /auto SKILL が削除済 run-verify.sh を呼ぼうとしたが、新設計通り Skill tool 経由で /verify 起動。10/10 auto PASS、3 manual pending |

### Orchestration Anomalies

- **[code-watchdog-late-completion]** code phase で実装完了後に watchdog 1800s 沈黙で SIGTERM (PID 81299)。`reconcile-phase-state.sh code-pr --check-completion` が PR #498 OPEN を検出し override success。#469 でも同パターン発生 (recurring)
- **[review-header-language-drift]** review skill が PR comment を `## レビュー回答サマリ` (日本語) で投稿。`modules/phase-state.md` SSoT は `## Review Response Summary` (英語) を期待。`reconcile-phase-state.sh review --check-completion` が mismatch を返したが、CI/AC/MUST 全て問題なしのため実体は成功
- **[stale-skill-mid-chain]** /auto セッションは PR #498 マージ前に開始したため旧 `skills/auto/SKILL.md` をロード (run-verify.sh 呼び出し版)。マージ後 verify phase 時に script が削除済となり呼び出し不可。新設計通り Skill tool で `/verify` を起動して回避

### Improvement Proposals

- **watchdog kill 後の code-pr 自動 reconcile**: 現状 reconcile は /auto Step 4 で手動実行。run-code.sh 側で exit 0 を返した後の /auto handling は `reconcile-phase-state result:` ログから anomaly detector が拾うが、log 出力タイミングと watchdog SIGTERM の race がある可能性。同パターンの再発を踏まえ、run-code.sh 内で SIGTERM 検出時に自動 reconcile + exit code 上書きする (run-verify.sh が exit 143 で行うのと同様の処理) を検討
- **review skill output 言語の SSoT 化**: `modules/phase-state.md` の expected signature と `skills/review/SKILL.md` の出力 header が言語不一致。同期するか、reconcile-phase-state.sh が JA/EN 両方を許容するかのどちらか。recommend: phase-state.md を JA/EN regex match 化 (skill 出力言語の独立性維持)
- **同 PR 内 skill 変更時の旧版実行リスク**: /auto は parent context で実行され SKILL.md を session 開始時にロード。同 PR が parent skill 自体を変更すると、マージ後の chain 内で stale skill が動く。Skill tool は新版を invoke するため部分的に救済可能だが、orchestration logic 自体が古い場合の corner case が残る。recommend: SKILL.md 変更を含む PR は /auto による self-modification 制限 (warning または stop-at-spec) を spec 段階でガイドライン化 — ただし follow-up #503 (Changed Files に影響連鎖 cleanup 明記) と部分的に重なるため、issue として独立起票するか #503 にスコープ追加するか判断要
