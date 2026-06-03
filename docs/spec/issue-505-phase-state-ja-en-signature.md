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

## Notes

- Auto-Resolved Ambiguity Points（Issue body より転記）:
  - **phase-state.md のシグネチャ記述形式**: Phase Table の該当セルに EN/JA 両シグネチャを併記する形式を採用。`reconcile-phase-state.sh` の `grep -qE` 実装と対応させるため、両文字列を明示するのが最も正確。
  - **bats テスト追加を受け入れ条件に含める**: Yes。`## レビュー回答サマリ` の completion check が PASS するテストを追加しないと回帰リスクが残る。
  - **github_check の形式**: `gh run list --workflow=test.yml` 形式に統一（PR route/patch route 両方で動作するため）。
- `grep -qE` は bash 3.2+ 互換（macOS system bash でも動作）。
- docs/ja/ 同期不要（変更対象は `modules/` と `scripts/` と `tests/`、いずれも `docs/` 以下ではない）。
