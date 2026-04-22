# Issue #355: verify: patch route で先行 pr route PR の CI を wait 対象として参照

## Overview

XL 並列実行で、patch route (XS/S) sub-issue の `/verify` phase が先行する pr route sub-issue の merged PR を CI wait 対象として参照するバグを修正する。
`scripts/run-verify.sh` の PR 検索ロジックが無効な GitHub 検索クオリファイア (`linked:issue:N`) を使用しており、patch route でも最新の merged PR を返してしまう。
fix: (1) pr route では branch 名による正確な PR 検索へ変更、(2) patch route では main branch の最新 workflow run を待機する。

## Reproduction Steps

1. XL issue に対して `/auto N` を実行
2. Level 2 (M/L) sub-issue が pr route で処理され PR がマージされる
3. Level 3 (XS/S) sub-issue が patch route で処理される
4. Level 3 sub-issue の `/verify` phase が Level 2 の merged PR を CI wait 対象として参照し、誤った PR の CI を待機する

## Root Cause

`scripts/run-verify.sh:57`:
```bash
VERIFY_PR_NUMBER=$(gh pr list --search "is:merged linked:issue:$ISSUE_NUMBER" --json number -q '.[0].number' 2>/dev/null || echo "")
```

`linked:issue:N`（N に具体的な数値付き）は GitHub の PR 検索 API で有効なクオリファイアとして機能しない。結果として `is:merged` だけが有効になり、最後にマージされた PR が返される。XL 並列実行で先行する pr route sub-issue のマージ直後に patch route sub-issue の verify が実行されると、誤って先行 PR を wait 対象として選択する。

他スクリプト（`run-auto-sub.sh:159`、`reconcile-phase-state.sh:194`）はブランチ名による正確な PR 特定（`--head "worktree-code+issue-${ISSUE_NUMBER}"`）を使用しており、`run-verify.sh` の実装と一貫性もない。

## Changed Files

- `scripts/run-verify.sh`: PR 検索を `--search "is:merged linked:issue:$ISSUE_NUMBER"` から `--head "worktree-code+issue-${ISSUE_NUMBER}" --state merged` へ変更; patch route の場合は main branch 最新 workflow run を待機するロジックを追加 — bash 3.2+ compatible
- `tests/run-verify.bats`: gh mock の `--search` マッチ条件を `--head` マッチ条件へ変更; `gh run list` / `gh run watch` の mock 分岐を追加; patch route が先行 PR を参照しないことを確認する regression test を追加

## Implementation Steps

1. `scripts/run-verify.sh` を修正する (→ 受け入れ基準 A, B)

   行 56-62 の CI wait ブロックを以下に置き換える:
   ```bash
   # Detect associated PR for CI wait (patch route has no PR)
   VERIFY_PR_NUMBER=$(gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state merged --json number -q '.[0].number' 2>/dev/null || echo "")
   if [[ -n "$VERIFY_PR_NUMBER" ]]; then
     # pr route: wait for the associated PR's CI checks
     "$SCRIPT_DIR/wait-ci-checks.sh" "$VERIFY_PR_NUMBER"
   else
     # patch route: wait for the latest branch workflow run
     _WAIT_BRANCH="${BASE_BRANCH:-main}"
     _RUN_ID=$(gh run list --branch "$_WAIT_BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")
     if [[ -n "$_RUN_ID" ]]; then
       TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"
       echo "Waiting for ${_WAIT_BRANCH} branch CI run #${_RUN_ID} (patch route, timeout: ${TIMEOUT_SEC}s)..." >&2
       if command -v timeout >/dev/null 2>&1; then
         timeout "$TIMEOUT_SEC" gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
       elif command -v gtimeout >/dev/null 2>&1; then
         gtimeout "$TIMEOUT_SEC" gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
       else
         gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
       fi
       echo "CI run #${_RUN_ID} complete" >&2
     else
       echo "No CI runs found for ${_WAIT_BRANCH} branch (patch route), skipping CI wait" >&2
     fi
   fi
   ```

2. `tests/run-verify.bats` の mock を更新し regression test を追加する (after 1) (→ 受け入れ基準 C)

   - `setup()` の gh mock (line 36): `$*` == *"--search"* の条件を `$*` == *"--head"* へ変更
   - `setup()` の gh mock に `gh run list` と `gh run watch` の分岐を追加（デフォルトは run ID なし = CI wait スキップ）
   - "success: calls wait-ci-checks.sh when associated PR is found" テスト (line 135) の gh override mock も `--head` マッチへ変更
   - regression test を追加: "patch route: does not wait on prior merged PR when no branch PR exists" — `--head` で空を返すが別の merged PR が存在する状況をシミュレートし、wait-ci-checks.sh が呼ばれず main branch CI wait が行われることを確認

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md (or scripts/run-verify.sh) clearly branches on route detection: patch route waits on the latest main-branch workflow run (no PR number involved); pr route waits on the associated PR's CI checks." --> patch route / pr route で CI wait 対象が明示的に分岐されている
- <!-- verify: rubric "The PR lookup logic for verify does not fall back to a prior unrelated PR when the current issue has no associated PR (patch route). When no PR is found for the issue, the logic selects main-branch workflow runs instead of an arbitrary merged PR." --> patch route で prior PR への fallback 参照が存在しない
- <!-- verify: command "bats tests/run-verify.bats" --> 関連 bats/unit テストが追加または更新されている

### Post-merge

- patch route の Issue（XS/S）で `/auto N` を実行し、`/verify` log に `PR #N` 参照が無く、main branch の workflow を wait 対象としていることを手動確認
- pr route の Issue（M/L）で `/auto N` を実行し、従来通り当該 PR の CI wait が正しく動作することを手動確認
- XL 並列（pr route + patch route 混在）で Level 3 patch route sub-issue が先行 PR を参照しないことを手動確認

## Notes

- PR 検索の fix は `run-auto-sub.sh:159` や `reconcile-phase-state.sh:194` の既存パターンと一致させる（ブランチ名による確定的な PR 特定）
- patch route の main branch CI wait: `gh run watch <databaseId>` を使用; `databaseId` は `gh run list --json databaseId --jq '.[0].databaseId'` で取得; `--interval 60` で 60 秒ポーリング
- `WHOLEWORK_CI_TIMEOUT_SEC` を patch route の main branch CI wait にも適用（`wait-ci-checks.sh` 内と同じ変数で統一）
- `skills/verify/SKILL.md` の PR lookup (line 79, `closes #$ISSUE_NUMBER`) はテキスト検索で正しく動作しており、修正対象外
- `gh run watch` が存在しない環境（非常に古い gh CLI）での自動解決: `2>/dev/null || true` でエラーを吸収し、後続の LLM 実行で判断させる（既存の `wait-ci-checks.sh` の `|| true` と同じ戦略）

## Code Retrospective

### Deviations from Design

- なし。Spec の実装ステップを忠実に実施した。

### Design Gaps/Ambiguities

- regression test の `WHOLEWORK_SCRIPT_DIR` オーバーライドアプローチが問題: `WHOLEWORK_SCRIPT_DIR` を設定すると `claude-watchdog.sh` など他のスクリプトも mock dir から探されてしまい、テストが失敗した。Spec では言及されていなかった制約。回避策として `WHOLEWORK_SCRIPT_DIR` オーバーライドを削除し、PATH 上の mock `gh` だけで検証する方法に変更した。

### Rework

- regression test を 1 回修正: `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を使ってサイドチャネル検証（`wait-ci-checks.sh` 呼び出しログ）を試みたが、他のスクリプト（`claude-watchdog.sh` 等）が mock dir に存在せずスクリプトがエラー終了した。オーバーライドを削除し、出力メッセージの有無で検証する方式に変更した。
