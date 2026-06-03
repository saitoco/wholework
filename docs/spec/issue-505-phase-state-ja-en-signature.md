# Issue #505: phase-state: review phase の expected signature を JA/EN 両言語で許容する

## Overview

`modules/phase-state.md` の review phase 完了シグネチャは `## Review Response Summary`（英語）のみを期待しているが、`skills/review/SKILL.md` が投稿するコメントヘッダーは実行コンテキストによって `## レビュー回答サマリ`（日本語）になる場合がある。この不一致により `reconcile-phase-state.sh review --check-completion` が `matches_expected:false` を返し、正常完了したにもかかわらず reconcile mismatch として扱われる。

`modules/phase-state.md` の review 完了シグネチャ記述と `scripts/reconcile-phase-state.sh` の grep パターンを JA/EN 両言語受け入れに変更し、false mismatch を排除する。

## Reproduction Steps

1. `skills/review/SKILL.md` が日本語コンテキストで実行される（`CLAUDE.md` で日本語出力指定済みの環境）
2. review 完了後、PR コメントヘッダーが `## レビュー回答サマリ` になる
3. `reconcile-phase-state.sh review <issue> --pr <pr> --check-completion` を実行すると `matches_expected:false` が返る

## Root Cause

`_completion_review` 関数（`scripts/reconcile-phase-state.sh` line 227）が `grep -q "## Review Response Summary"` のみでマッチングしており、日本語ヘッダー `## レビュー回答サマリ` を見逃す。`modules/phase-state.md` の Phase Table でも英語シグネチャのみ記載されている。

## Changed Files

- `modules/phase-state.md`: Phase Table の review 行 Success Signature 列を `## Review Response Summary` または `## レビュー回答サマリ` を受け入れる記述に更新
- `scripts/reconcile-phase-state.sh`: `_completion_review` の `grep -q "## Review Response Summary"` を `grep -qE "## Review Response Summary|## レビュー回答サマリ"` に変更 — bash 3.2+ compatible
- `tests/reconcile-phase-state.bats`: `## レビュー回答サマリ` ヘッダーで completion check が PASS するテストを追加

## Implementation Steps

1. `modules/phase-state.md` の Phase Table review 行を更新: Success Signature 列の値を `PR has a comment containing \`## Review Response Summary\` or \`## レビュー回答サマリ\`` に変更 (→ 受け入れ条件 A, B, C)
2. `scripts/reconcile-phase-state.sh` の `_completion_review` 関数 (line 227 付近) を変更: `grep -q "## Review Response Summary"` を `grep -qE "## Review Response Summary|## レビュー回答サマリ"` に変更 (after 1) (→ 受け入れ条件 D)
3. `tests/reconcile-phase-state.bats` に新規テスト追加（`@test "review completion: no Review Summary comment -> mismatch"` の直後）: `## レビュー回答サマリ` を PR コメントとして返す gh モック環境で `--check-completion --strict` が exit 0 かつ `matches_expected:true` を返すことを検証 (after 2) (→ 受け入れ条件 E)

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/phase-state.md" "### Phase Table" "Review Response Summary" --> `modules/phase-state.md` の Phase Table に英語シグネチャが記載されている
- <!-- verify: section_contains "modules/phase-state.md" "### Phase Table" "レビュー回答サマリ" --> `modules/phase-state.md` の Phase Table に日本語シグネチャが記載されている
- <!-- verify: rubric "modules/phase-state.md の review completion signature が JA/EN 両ヘッダー（Review Response Summary / レビュー回答サマリ）をいずれも受け入れる形式に更新されている" --> JA/EN 両言語対応が modules/phase-state.md に実装されている
- <!-- verify: grep "レビュー回答サマリ" "scripts/reconcile-phase-state.sh" --> `scripts/reconcile-phase-state.sh` の `_completion_review` に日本語シグネチャのマッチングが追加されている
- <!-- verify: file_contains "tests/reconcile-phase-state.bats" "レビュー回答サマリ" --> `tests/reconcile-phase-state.bats` に日本語シグネチャの completion テストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テスト CI が success

### Post-merge

- `reconcile-phase-state.sh review <issue> --pr <pr> --check-completion` が `## レビュー回答サマリ` ヘッダーを含む PR で `matches_expected:true` を返すことを手動確認（該当環境がある場合）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Notes

- Auto-Resolved Ambiguity Points（Issue body より転記）:
  - **phase-state.md のシグネチャ記述形式**: Phase Table の該当セルに EN/JA 両シグネチャを併記する形式を採用。`reconcile-phase-state.sh` の `grep -qE` 実装と対応させるため、両文字列を明示するのが最も正確。
  - **bats テスト追加を受け入れ条件に含める**: Yes。`## レビュー回答サマリ` の completion check が PASS するテストを追加しないと回帰リスクが残る。
  - **github_check の形式**: `gh run list --workflow=test.yml` 形式に統一（PR route/patch route 両方で動作するため）。
- `grep -qE` は bash 3.2+ 互換（macOS system bash でも動作）。
- docs/ja/ 同期不要（変更対象は `modules/` と `scripts/` と `tests/`、いずれも `docs/` 以下ではない）。

## review retrospective

### Spec vs. Implementation Divergence

実装ステップ 3 では bats テストを `@test "review completion: no Review Summary comment -> mismatch"` の「直後」に追加と指定していたが、実際は EN pass テストの直後（"no Review Summary" テストの直前）に挿入された。テスト順序は EN pass → JA pass → fail の論理グループになっており機能上の問題はない。次回以降の Spec では挿入位置をテスト名で「直前」/「直後」双方向から明示するか、グループ番号で指定するとよい。

### Recurring Issues

特になし。

### Acceptance Criteria Verification Difficulty

全 6 条件を PASS で判定できた。`github_check` 条件のみ実際の CI 実行結果参照が必要だったが、`gh run list` で確認可能。`section_contains` 条件が 2 件あり verify コマンドの精度を要したが、いずれも明確にマッチした。UNCERTAIN は 0 件。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件 6 件はいずれも verify command 付きで自動検証可能。曖昧さなし。`github_check` を `gh run list --workflow=test.yml` 形式に統一した判断は妥当（PR/patch 両 route 対応）。

#### design
- 設計は実装と整合。review retrospective が指摘したテスト挿入位置の微小な乖離（実装ステップ 3 の「直後」指定 vs 実挿入位置）は論理グループ（EN pass → JA pass → fail）として正しく、機能影響なし。

#### code
- 手戻りなし（Code Retrospective: N/A）。`grep -qE` による bash 3.2+ 互換実装でクリーン。fixup/amend なし。

#### review
- review-light が 4 視点を実行し MUST 指摘ゼロ。AC 6/6 PASS、CI 全 SUCCESS を pre-merge で確認済み。verify 段階で FAIL/UNCERTAIN ゼロだったことから review の見落としなし。

#### merge
- squash merge 正常完了、コンフリクトなし。merge precondition チェックで `reviewDecision` が空（必須レビュアー未設定リポジトリ）の warning が出たが warn-only で非ブロック（stage-1 gradual rollout の既知挙動）。問題なし。

#### verify
- 全 6 条件 PASS。`github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'"` がマージ直後の初回実行で空文字列を返した。原因はマージ push がトリガーした main 上の CI run が in_progress（`conclusion` が null）だったため。再実行で `success` を取得し PASS 確定。

### Improvement Proposals
- **`github_check` の `gh run list` 形式における in_progress 検出**: `--json conclusion --jq '.[0].conclusion'` 形式は CI 実行中に `conclusion=null`（空文字列）を返すが、verify-executor の PENDING 検出はリテラル `in_progress` 文字列を探すため、この形式では PENDING に分類されない。merge 直後に verify を走らせる auto フローでは、CI 完走前の単発実行で空文字列 → "success" 不一致となり、誤って FAIL/UNCERTAIN 判定されるリスクがある。`gh run list` 形式の github_check では `status` フィールド（`in_progress`/`completed`）も参照して PENDING を返す、もしくは verify-executor が `gh run list` 由来の空 conclusion を PENDING として扱うよう改善する余地がある。今回は再試行で success に到達したため実害なし。（→ Issue #523 起票済み）

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | pr | SUCCESS | phase/* ラベル無し → run-issue.sh で triage、Size M 確定、phase/issue 付与 |
| spec | pr | SUCCESS | run-spec.sh、phase/ready 到達 |
| code | pr | SUCCESS | PR #519 作成 |
| review | pr | SUCCESS | --light、MUST 指摘 0、CI 全 green |
| merge | pr | SUCCESS | squash merge、phase/verify 遷移 |
| verify | - | SUCCESS (manual worktree-merge recovery) | 全 6 AC PASS。worktree exit の FF merge が concurrent push で失敗 → cherry-pick で手動 recovery |

### Orchestration Anomalies
- **verify worktree exit の FF merge 失敗 → 手動 recovery**: verify Step 13（merge-to-main）で `worktree-merge-push.sh --from worktree-verify+issue-505 --base main` が exit 128（`fatal: Not possible to fast-forward, aborting.`）。原因は verify 作業中に別の /auto 実行が #517 の verify retrospective（`f305822`）を origin/main へ push し、local/remote main が worktree ブランチ（`0a33f9e` ベース）より 1 コミット先行したこと。`worktree-merge-push.sh` の FF fallback は `git pull --rebase origin main`（local base を remote に追従）のみで、worktree ブランチを更新後の base へ rebase しないため復旧不能だった。変更ファイルは別 Spec（#505 vs #517）で非衝突のため、parent session が `git cherry-pick b0aa50a` → `git push origin main`（f305822..d84705f）で手動 recovery（Signed-off-by 保持を確認）。worktree/branch は cleanup 済み。Issue #505 自体の verify 結果（全 AC PASS、phase/done、CLOSED）には影響なし。

### Improvement Proposals
- **`worktree-merge-push.sh` の FF fallback を worktree-branch-behind-base ケースに拡張**（既存 Issue #522 と同一論点。本 verify での再発が #522 を補強）: 現行の FF fallback（`modules/orchestration-fallbacks.md#ff-only-merge-fallback`）は local base が remote より遅れているケース（`git pull --rebase origin <base>`）のみを扱い、concurrent push により local base が worktree ブランチより先行したケース（worktree ブランチが base の祖先でない）を扱えない。FF 失敗時に worktree ブランチを更新後の base へ rebase（非衝突なら cherry-pick）してから ff-merge を再試行するフォールバックを追加すべき。patch-lock は push クリティカルセクションを保護するが base 分岐自体は防げないため、複数 /auto 並行実行時に再発しうる。retro-proposals の重複チェックで #522 と一致するため新規起票はスキップ。

