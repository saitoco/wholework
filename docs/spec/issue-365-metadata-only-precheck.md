# Issue #365: verify: ファイル変更ゼロの実装ルートで pre-check false-positive を抑制

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| code | patch (XS) | SUCCESS (manual recovery) | run-code.sh exited 0 with reported "Direct commit and push to main 完了" but no commit was produced and working tree was clean. Parent `/auto` session manually implemented the Step 1 pre-check edit and committed directly to main. |
| verify (iter 1) | - | FAIL | Detected absent marker correctly (AC1 grep no match). Issue reopened, phase/* cleared. |
| verify (iter 2) | - | SUCCESS (pre-merge) | AC1 passed after manual recovery commit `497aea2`. Post-merge AC2 remains unchecked as `verify-type: opportunistic` awaiting a future `/verify` run against a `<!-- implementation-type: metadata-only -->` Issue. |

### Orchestration Anomalies

- **Silent no-op from code sub-agent (wrapper exit 0)**: `run-code.sh` terminated with exit code 0 and the LLM output asserted "Direct commit and push to main が完了しました" + a full implementation-content summary referencing `<!-- implementation-type: metadata-only -->` marker handling, yet `git log` / `git diff` showed no change. `reconcile-phase-state.sh code-patch --check-completion` confirmed post hoc: `{"matches_expected":false,"diagnosis":"no commit with closes #365 found on origin/main"}`. The anomaly was caught only downstream at `/verify` iter 1 (AC1 FAIL).
- Category: case (c) from `/auto` Step 4a — completed with behavior that differs from the original spec.

### Improvement Proposals

- **Always run `reconcile-phase-state.sh <phase> --check-completion` after every code phase, regardless of wrapper exit code**: Currently the patch-route completion check only fires on non-zero exit (Step 4 patch route step 3). Observe→Diagnose→Act should apply symmetrically — a false success should be caught as fast as a false failure. Proposal: in `skills/auto/SKILL.md` patch-route and pr-route, move the completion check to run unconditionally after every `run-*.sh` call; if `matches_expected: false` and wrapper exit was 0, escalate to Tier 2 anomaly detection instead of continuing to the next phase.
- **Teach `detect-wrapper-anomaly.sh` the "LLM-reported-success-but-no-commit" pattern**: add a detector entry for `exit_code=0` + (`git log --grep "#$NUMBER"` returns empty) + (LLM output contains success phrase like "完了しました" / "commit and push") so the same anomaly surfaces in Tier 2 with a known recovery (re-run `run-code.sh` once; on second failure, surface to user for manual implementation).
- **Clarify verify-type: opportunistic handling in patch-route XS**: when all pre-merge AC pass but at least one `verify-type: opportunistic` AC remains unchecked, `/auto` currently treats this as "verify success" and proceeds to Step 5. Confirm this is intended (Issue stays at `phase/verify` awaiting future opportunistic check) vs. surfacing a clearer completion state ("partial success — opportunistic pending") in the Step 5 completion banner.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body に `<!-- implementation-type: metadata-only -->` マーカーという実装ガイドとして機能する記述があり、受入条件の意図が明確だった。
- Post-merge 条件が `verify-type: opportunistic` のみでverify hintを持たないため自動検証できず、ユーザー検証ガイドに留まる。Opportunistic 条件にはverify hintを付与することを検討する価値がある。

#### design
- ソリューション選択（マーカー方式）は Issue body の「対処案の例」どおりの実装で、設計と実装の乖離なし。
- 実装差分は `skills/verify/SKILL.md` 1ファイルのみ（4行追加3行変更）と最小スコープで適切。

#### code
- iter 1 でコード変更なし（wrapper が silent no-op で exit 0）というオーケストレーション異常が発生し、iter 2 でリカバリ。Auto Retrospective に詳細記録済み。
- 実際の修正コミット（`497aea2`）は1ファイルのみ変更で、intent と実装が一致している。

#### review
- レビューPRなし（patch ルート直コミット）。コード変更が最小限のため問題なし。
- `reconcile-phase-state.sh` によるリカバリが機能した点は Auto Retrospective で記録済み。

#### merge
- 直コミット（patch route）でマージ競合なし。コミットメッセージに `closes #365` が含まれており標準的。

#### verify
- Pre-merge 条件1（verify hintあり）: PASS — `grep` verify command が正常動作し、実装の有無を正確に検出。
- Post-merge 条件2（verify-type: opportunistic、hintなし）: 自動検証対象外。Issue #364 相当のケースで実際に `/verify` を実行するまで確認できない。
- iter 1 でPAIL → 再オープン → iter 2でPASS の流れは verify-reopen ループが正常に機能したことを示す。

### Improvement Proposals
- Auto Retrospective の改善提案（`reconcile-phase-state.sh` の無条件実行、`detect-wrapper-anomaly.sh` への no-commit パターン追加）を継承。これらは本 Issue の verify 自体への観察ではなく `/auto` オーケストレーション全体への改善提案として記録済み。
- Opportunistic 条件にもverify hint（例: `<!-- verify: command "..." -->` ）を付与するガイドラインを Issue 作成時に推奨することで、自動消化率を向上できる。
