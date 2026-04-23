# Issue #294: Core gate 明示化と /audit drift の Domain 整合チェック追加 (Core/Domain 分離 Phase 3)

## Auto Retrospective

### Execution Summary

| # | Title | Route | Result | Notes |
|---|-------|-------|--------|-------|
| 359 | /verify Step 13 の skill-infra 分類ブロックを HAS_SKILL_PROPOSALS で早期 gate する (Core/Domain 分離 Phase 3 Sub 3A) | patch (S) | SUCCESS | spec → code (patch) → verify partial PASS (post-merge manual 1 件残); CLOSED + phase/verify |
| 360 | /audit drift に Domain frontmatter と docs/environment-adaptation.md Layer 3 表の整合チェックを追加 (Core/Domain 分離 Phase 3 Sub 3B) | patch (S) | SUCCESS | spec → code (patch) → verify partial PASS (post-merge manual 1 件残); CLOSED + phase/verify |

execution_order: `[[359, 360]]` (1 level, 2 並列)

### Parallel Execution Issues

- None. 両サブは worktree 分離で並列実行され、conflict や race condition は発生しなかった。main branch への push は両者とも直接 commit (patch ルート) で、直列化衝突なし。
- PR 抽出不要 (patch route)、merge 待ちなし。

### Orchestration Anomalies

- None. /auto XL route の Step 3 で parent が `phase/issue` のままだと spec が走る gap があったため、事前に parent #294 を `phase/ready` へ手動 transition してから /auto を起動した。これは既知 gap (skills/issue/SKILL.md の XL parent ready-transition ステップ欠落) であり、本 Phase 3 実行の異常ではない。

### Improvement Proposals

- **XL parent の phase/ready auto-transition**: `/issue` skill の sub-issue 分割完了時に、parent を `phase/ready` へ自動 transition するステップを追加する。現状は分割後も parent が `phase/issue` のまま残り、`/auto {parent}` が XL 親に対して無駄な spec を走らせようとする gap がある。Issue #363 (XL 昇格ステップ追加) の延長線で、Step 9 procedure 8 と Step 11c procedure 8 の「Parent phase management」の一部として扱うのが自然。

## Issue Retrospective

(parent #294 の Issue コメントに Retrospective は存在しない — XL 親は /issue の retrospective 対象でないため)

### Cross-cutting AC Status

- [ ] すべての sub-issue (#359, #360) が phase/done に到達している — **未達** (両サブとも phase/verify で post-merge manual 条件残)

Sub-issue の post-merge 手動確認を完了後、`/verify 359` および `/verify 360` を再実行すれば phase/done 遷移 → parent #294 close flow が起動する。
