# Issue #853: scripts: worktree-merge-push.sh の rebase fallback 強化 (lock 後 fetch + max-retry + is-ancestor silent-skip)

## Consumed Comments

- saito (MEMBER): Issue Retrospective — AC5 の verify command として `rubric` を追加してシナリオカバレッジを確認するよう補強した旨の解決記録。`retry loop` 内での `ff-only merge` ステップの扱いは `/spec` 段階で設計する旨。

## Overview

`scripts/worktree-merge-push.sh` の並列 session 環境での race condition と silent no-op を修正する。以下 3 点を追加する:

- **A. lock 取得直後の fetch** — `acquire_lock` 直後に `git fetch origin "$BASE_BRANCH"` を best-effort 実行。以後の ff-only merge / rebase で参照する `origin/${BASE_BRANCH}` ref が stale なまま使われることを防ぐ。
- **C. is-ancestor silent-skip** — worktree branch を `origin/${BASE_BRANCH}` の上に rebase する前に `git merge-base --is-ancestor` で判定し、既に ancestor なら rebase をスキップして ff-only merge に進む。rebase が silent no-op になって後続の ff-only が失敗するパスを排除する。
- **B. push retry loop** — `git push` が non-fast-forward で失敗した場合、`git fetch + git rebase origin/${BASE_BRANCH} + git push` を max 3 回 retry する。3 回失敗で abort + 明示エラー + exit 1。

conflict 発生時は `rebase --abort` + 明示エラーで停止する現行方針を維持 (auto-resolve しない)。

## Changed Files

- `scripts/worktree-merge-push.sh`: A / C / B の 3 点追加 — bash 3.2+ 互換
- `tests/worktree-merge-push.bats`: push race / is-ancestor skip / max-retry exhaustion の 3 シナリオのテストケースを追加
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` エントリを新動作 (fetch-after-lock / is-ancestor check / push retry loop) に合わせて更新

## Implementation Steps

1. `scripts/worktree-merge-push.sh` — `acquire_lock` 呼び出し (`acquire_lock`) の直後、`if [[ -n "$FROM_BRANCH" ]]; then` の直前に以下を追加 (→ AC1):
   ```bash
   git fetch origin "$BASE_BRANCH" 2>&1 || echo "Warning: git fetch origin ${BASE_BRANCH} failed; continuing with local refs" >&2
   ```

2. `scripts/worktree-merge-push.sh` — 2 回目の ff-only merge 失敗後 (`echo "FF merge still failed; base may have diverged. Rebasing ..." >&2` の直後)、`worktree_path=$(...)` の前に is-ancestor チェックを挿入し、rebase ブロック全体を条件分岐に変える (→ AC3):
   ```
   if git merge-base --is-ancestor "origin/${BASE_BRANCH}" "$FROM_BRANCH" 2>/dev/null; then
     echo "Branch ${FROM_BRANCH} is already on origin/${BASE_BRANCH} (is-ancestor=true); skipping rebase" >&2
   else
     # 既存の worktree_path 判定 + rebase ロジック (変更なし)
   fi
   git merge "$FROM_BRANCH" --ff-only   # どちらのパスも実行
   ```

3. `scripts/worktree-merge-push.sh` — 末尾の `git push origin "$BASE_BRANCH"` を push retry loop に置き換える (→ AC2, AC4):
   ```
   MAX_PUSH_RETRY=3
   push_count=0
   while true; do
     if git push origin "$BASE_BRANCH"; then
       break
     fi
     push_count=$((push_count + 1))
     if [[ $push_count -ge $MAX_PUSH_RETRY ]]; then
       echo "Error: git push origin ${BASE_BRANCH} failed after ${MAX_PUSH_RETRY} retries. Manual push required." >&2
       exit 1
     fi
     echo "Push rejected (non-fast-forward); retry ${push_count}/${MAX_PUSH_RETRY}: fetching and rebasing onto origin/${BASE_BRANCH}..." >&2
     git fetch origin "$BASE_BRANCH"
     if ! git rebase "origin/${BASE_BRANCH}"; then
       git rebase --abort 2>/dev/null || true
       echo "Error: Rebase during push retry failed with conflicts. Resolve manually." >&2
       exit 1
     fi
     sleep 1
   done
   ```

4. `tests/worktree-merge-push.bats` — 以下 3 テストケースを追加 (→ AC5):
   - `@test "push race: push fails once then succeeds after fetch-rebase retry"` — git mock: push 1 回目 exit 1 / 2 回目 exit 0、merge/fetch/rebase は exit 0。出力に retry ログを含み exit 0 であること、GIT_LOG に "fetch origin main" と "push origin main" が記録されることを assert。
   - `@test "is-ancestor true: rebase is skipped when branch already contains origin base"` — git mock: `merge --ff-only` 1 回目と 2 回目を exit 1 / 3 回目を exit 0、`pull --rebase` exit 0、`merge-base --is-ancestor` exit 0。GIT_LOG に worktree rebase (`-C`) および `rebase origin/main` が記録されていないことを assert (rebase skip を確認)。
   - `@test "max-retry exhaustion: push always fails and script exits with error"` — git mock: push 常に exit 1、fetch/rebase exit 0。exit code 非ゼロかつ出力に "Error" + retry 回数表示を含むことを assert。

5. `modules/orchestration-fallbacks.md` — `## ff-only-merge-fallback` エントリを更新 (→ AC1, AC2, AC3):
   - Fallback Steps の冒頭に Step 0 として "acquire_lock 直後に `git fetch origin <base>` を best-effort 実行; 失敗は warning のみで続行" を追記
   - Fallback Steps の Step 4 の前に "4a. `git merge-base --is-ancestor origin/<base> <from>` で ancestor 判定: true なら rebase をスキップして Step 4e の ff-only merge に進む" を追記
   - Escalation に "push retry loop (max 3): non-fast-forward push 失敗時に `git fetch + git rebase origin/<base> + git push` を retry。3 回失敗で abort + exit 1。retry 中の rebase conflict は abort + exit 1 (方針 D 維持)" を追記
   - Rationale に本 Issue (#853) を追記

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh で acquire_lock 関数呼び出し直後に git fetch origin \"$BASE_BRANCH\" が明示的に実行されている (best-effort で失敗は warning だが処理続行)" --> <!-- verify: file_contains "scripts/worktree-merge-push.sh" "git fetch origin" --> AC1: lock 取得直後に fetch が実行されている
- <!-- verify: rubric "scripts/worktree-merge-push.sh の git push 失敗時に fetch + rebase + push を最大 3 回 retry し、max retries 到達で abort + 非ゼロ exit する loop が追加されている" --> <!-- verify: file_contains "scripts/worktree-merge-push.sh" "MAX_PUSH_RETRY=3" --> AC2: push retry loop (max 3) が追加されている
- <!-- verify: rubric "scripts/worktree-merge-push.sh で worktree branch を origin/${BASE_BRANCH} に rebase する前に git merge-base --is-ancestor 等で既に ancestor 関係にあるかを判定し、ancestor の場合は rebase をスキップして直接 ff-only merge に進む" --> <!-- verify: file_contains "scripts/worktree-merge-push.sh" "merge-base --is-ancestor" --> AC3: is-ancestor チェックによる rebase skip ロジックが追加されている
- <!-- verify: rubric "scripts/worktree-merge-push.sh で rebase conflict 発生時の挙動は abort + 明示エラーで停止する現行方針が維持されており、--strategy-option=theirs/ours 等の auto-resolve オプションは追加されていない" --> <!-- verify: file_not_contains "scripts/worktree-merge-push.sh" "--strategy-option" --> AC4: conflict 時は abort + 明示エラーのみ、auto-resolve 追加なし
- <!-- verify: rubric "tests/worktree-merge-push.bats に push race (非 fast-forward push 失敗後の retry)、silent no-op (is-ancestor check によるリベース skip)、max-retry exhaustion (retry 上限到達で abort) の各シナリオをカバーする bats テストケースが追加されている" --> <!-- verify: command "bats tests/worktree-merge-push.bats" --> AC5: 3 シナリオの bats テストが追加されており全て通る

### Post-merge

- 次回並列 session 環境で worktree-merge-push.sh の race / silent fail が発生せず、3 回 retry 内で復旧することを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- `git fetch origin "$BASE_BRANCH"` は lock 取得直後に実行するが best-effort 扱い。ネットワーク障害時は警告を stderr に出力して続行し、スクリプト全体は abort しない (現行ロジックを壊さない)
- push retry loop 内の `git rebase "origin/${BASE_BRANCH}"` は、ローカルの BASE_BRANCH (main) 上にある FROM_BRANCH 由来のコミット群を最新 origin/${BASE_BRANCH} の上に rebase し直す。conflict 時は `rebase --abort` + exit 1 (方針 D 維持)
- `sleep 1` は retry 間の fetch 安定化用。lock 保持中なので concurrent worker を待つ目的ではない
- is-ancestor check の失敗 (コマンドエラー) は exit code 非 0 → 条件式が false → 既存の worktree rebase ロジックに fallthrough する (safe fallback)
- `MAX_PUSH_RETRY=3` はハードコード (将来的に `.wholework.yml` から expose 可能だが初期実装ではハードコード)
- bats テスト内での `sleep 1` は実際に実行されるが 1 秒 × 最大 2 回 = 2 秒と短いため許容範囲

## spec retrospective

### Minor observations

- Nothing to note

### Judgment rationale

- is-ancestor check の配置: 2 回目の ff-only 失敗後かつ worktree_path 判定の前が最適。これにより silent no-op rebase を確実に検知できる
- push retry loop: `git rebase "origin/${BASE_BRANCH}"` を retry 内で使うことで、local main に取り込まれた FROM_BRANCH コミット群を最新 origin/main の上に replay できる。conflict 時は abort + exit 1 で方針 D を維持

### Uncertainty resolution

- Nothing to note
