# Issue #368: auto: reconcile-phase-state.sh の check-completion を exit 0 時も無条件実行

## Overview

`/auto` skill の code phase（patch/PR 両経路）において、`run-code.sh` の wrapper exit code が 0 の場合に `reconcile-phase-state.sh --check-completion` が呼ばれない問題を修正する。false success（exit 0 + コミットなし/PR未作成）を早期検出できるよう、completion check を exit code に関わらず無条件実行し、`matches_expected: false` の場合は exit 0 であっても Step 6 へエスカレーションする。

対象: `skills/auto/SKILL.md` の patch route および PR route の code phase ステップのみ（`run-auto-sub.sh` は別スコープ）。

## Changed Files

- `skills/auto/SKILL.md`: patch route の code phase step 3 を無条件完了チェックに変更；PR route の code phase steps 2-3 を無条件完了チェックに変更（"done" 出力をチェック後に移動）

## Implementation Steps

1. `skills/auto/SKILL.md` の "**patch route XS/S (2 phases):**" セクションで、code phase の step 3 を変更する（→ 受入条件 AC1, AC2, AC3）：
   - 挿入位置: "Each phase follows the Observe → Diagnose → Act pattern (same as pr route; see above)." の後の numbered list 内
   - 変更前: `3. If code fails: completion check \`${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-patch $NUMBER --check-completion\` — if \`matches_expected: true\`, override to success; otherwise go to Step 6`
   - 変更後: `3. Unconditional completion check: \`${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-patch $NUMBER --check-completion\` — runs unconditionally regardless of exit code; if \`matches_expected: false\` (including exit 0), go to Step 6; if code exited non-zero but \`matches_expected: true\`, override to success`

2. `skills/auto/SKILL.md` の "**pr route (4 phases):**" セクションで、code phase の steps 2-3 を変更する（after 1）（→ 受入条件 AC1, AC2, AC3）：
   - step 2 変更前: `2. Output \`[1/4] code\`, then run \`${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --pr [--base {branch}]\` via Bash (timeout: 600000); on success output \`[1/4] code → done (PR #N)\``
   - step 2 変更後: `2. Output \`[1/4] code\`, then run \`${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --pr [--base {branch}]\` via Bash (timeout: 600000)`
   - step 3 変更前: `3. If code fails: completion check \`${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-pr $NUMBER --check-completion\` — if \`matches_expected: true\`, override to success and continue; otherwise go to Step 6`
   - step 3 変更後: `3. Unconditional completion check: \`${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-pr $NUMBER --check-completion\` — runs unconditionally regardless of exit code; if \`matches_expected: false\` (including exit 0), go to Step 6; if \`matches_expected: true\`, output \`[1/4] code → done (PR #N)\` and continue`

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/auto/SKILL.md" "If code fails: completion check" --> `skills/auto/SKILL.md` の patch-route および PR-route の code phase ステップにおいて「wrapper exit code が非 0 の場合のみ」という条件記述が削除されている
- <!-- verify: grep "unconditional" "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の code phase ステップで `reconcile-phase-state.sh --check-completion` が無条件実行されることが明示されている
- <!-- verify: rubric "skills/auto/SKILL.md code phase steps explicitly state that reconcile-phase-state.sh --check-completion runs unconditionally (regardless of exit code) and that matches_expected: false triggers Step 6 escalation even when code exited 0" --> exit 0 + `matches_expected: false` の場合も Tier 2 検出（Step 6）へエスカレーションされることが明示されている

### Post-merge

- Issue #365 相当の silent no-op シナリオ（exit 0 + コミットなし）を再現し、異常が検出されることを確認 <!-- verify-type: opportunistic -->

## Notes

- `run-auto-sub.sh` は今回のスコープ外（XL 経路での exit 0 + Tier 2 未エスカレーション問題は別スコープとして除外）
- Issue body の Background では「exit code 143 のタイムアウト時のみ呼ばれる」とあるが、実際の実装は「If code fails」（任意の非 0 exit）。ただし「exit 0 の場合に呼ばれない」という核心は一致しており、実装方針への影響はない
- PR route の step 2 から "on success output `[1/4] code → done (PR #N)`" を削除し、step 3 の completion check 後（`matches_expected: true` 確認後）に移動する。これにより false success 時に `[1/4] code → done` と誤表示されることも防ぐ
- Auto-resolved ambiguity は Issue body の "Auto-Resolved Ambiguity Points" セクションに記録済み（AC1/AC2 verify command の変更理由、`run-auto-sub.sh` スコープ除外理由を含む）
- `validate-skill-syntax.py` 制約: 新規テキストに半角 `!` なし、小数ステップ番号なし ✓

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## spec retrospective

### Minor observations

- PR route の step 2 に "on success output `[1/4] code → done (PR #N)`" が含まれており、step 3 を無条件チェックに変更する際に step 2 からこの出力も移動する必要があった（単純な step 3 の書き換えだけでは不完全）。今後同様の「成功時出力が Act ステップに含まれているパターン」では、Diagnose ステップへの移動も Set として設計すること
- Issue body の Auto-Resolved Ambiguity Points に verify command の変更理由が既に詳細に記録されていたため、/spec の Step 7 (Ambiguity Resolution) は実質スキップできた

### Judgment rationale

- `run-auto-sub.sh` をスコープ外とした判断: Issue body に明示的な除外理由（XL 経路の別問題）が記録済みのため、Spec でも引き継いだ
- Issue body background の「exit code 143 のみ」という記述と実装の「If code fails（任意の非 0）」の差異は、実装方針への影響がないと判断してコンフリクトとしてメモのみ

### Uncertainty resolution

- Nothing to note

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の "Auto-Resolved Ambiguity Points" に verify command 変更理由が詳細に記録されていたため、Spec の Ambiguity Resolution ステップを実質スキップできた。Issue 側での事前整備が効いた例
- PR route step 2 に「成功時出力」が埋め込まれており、step 3 の無条件チェック化に際して出力移動も必要だった点が spec retrospective に記録済み。設計時に「Diagnose と Act の出力タイミング分離」を考慮するパターンとして有用

#### design
- Spec の実装ステップが変更前後の diff 形式で明示されており、実装ブレが生じなかった。受入条件の verify command も Issue 側で auto-resolve 済みだったため整合性が保たれていた

#### code
- 実装コミット 1 件（`4159f1e`）のみ、6行変更（3挿入/3削除）。fixup/amend なし。Spec の設計通りに一発で実装が完了している

#### review
- patch route のため PR レビューなし。verify コマンドの `file_not_contains` + `grep "unconditional"` + `rubric` の 3 層構成が事前レビュー（pre-merge verify）として機能し、実装の正確性を機械的に担保した

#### merge
- patch route (直接 main コミット)。merge conflict なし、CI 不要のシンプルな経路

#### verify
- pre-merge 条件 3 件すべて初回で PASS
- post-merge opportunistic 条件（Issue #365 シナリオ再現）は手動確認が必要。自動化が困難なシナリオ再現系の条件は `verify-type: opportunistic` が適切な分類
- verify コマンドの設計品質が高い: `file_not_contains`（削除の確認）→ `grep "unconditional"`（追加の確認）→ `rubric`（意味論的整合性）の 3 段階で漏れなく検証できた

### Improvement Proposals
- N/A
