# Issue #970: worktree-merge-push: push-retry ループの checkout 依存を解消

## Consumed Comments

No new comments since last phase.

## Overview

Issue #961 は `scripts/worktree-merge-push.sh` の primary merge path (行83-127) を checkout レス設計 (`git fetch . <from>:<base>` による ref-to-ref fetch、および worktree スコープの `git -C <path> rebase`) に書き換えたが、同一スクリプト内の **push-retry ループ** (行129-148、`git push origin "$BASE_BRANCH"` が non-fast-forward で失敗した際の retry) は #961 の Changed Files が明示的にスコープ外としたため未修正のまま残っている。review フェーズ (PR #968, review-light) が SHOULD として検出済み: push-retry ループの bare `git rebase` が共有ディレクトリの現在の HEAD に対して無条件に動作し、foreign checkout + push race が重なると他セッションのブランチを誤って書き換えうる。

本 Issue は、push-retry ループを primary merge path と同じ checkout レス設計 (`--from` 指定時は worktree スコープの `git -C <path> rebase` + ref-to-ref fetch 再試行) に合わせて書き換える。

## Reproduction Steps

実インシデントではなく、#961 の review フェーズで検出された潜在欠陥 (コードレビュー起点)。想定される発火条件:

1. セッション A が共有メインディレクトリで `worktree-merge-push.sh --from <worktree-branch>` を呼び出し、primary merge path (checkout レス) でローカル `$BASE_BRANCH` に自分のコミットを取り込む。
2. A の初回 `git push origin "$BASE_BRANCH"` とその retry の間に、共有メインディレクトリで別ブランチを直接 checkout して作業中のセッション B が先に `origin/$BASE_BRANCH` に push し、A の push が non-fast-forward で拒否される。
3. A の push-retry ループが bare `git rebase "origin/${BASE_BRANCH}"` を実行するが、これは **共有ディレクトリの現在の HEAD** (= たまたま B のブランチが checkout されていればそれ) に対して無条件に動作するため、B の作業中ブランチを誤って書き換えうる。

## Root Cause

push-retry ループ (行129-148, #853 由来) は #961 が導入した checkout レス設計の対象外だった。#961 の Changed Files 節は primary merge path (旧83-109行目) のみを修正対象と明示的にスコープしており、同一スクリプト内の push-retry ループには手を付けていない。ループ内の `git rebase "origin/${BASE_BRANCH}"` は `-C <path>` 指定もブランチ引数もない bare 呼び出しのため、共有ディレクトリの現在の HEAD に暗黙依存する — #961 が修正したものと同一クラスの欠陥である。

## Changed Files

- `scripts/worktree-merge-push.sh`: push-retry ループ (行129-148) を checkout レス設計に書き換え
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` の Escalation 記載 (Push retry loop 項) と Rationale を新設計に更新
- `tests/worktree-merge-push.bats`: 既存の push race テストのモックを更新し、checkout レス化を検証する新規テストを追加
- `docs/structure.md`: [Steering Docs sync candidate] 212行目の `worktree-merge-push.sh` 一行説明を確認 — grep 済み、push-retry loop の内部実装詳細 (worktree スコープ rebase) までは言及していない一行要約のため変更不要と判断。`/code` で再確認望ましい
- `docs/tech.md`: [Steering Docs sync candidate] `WHOLEWORK_PATCH_LOCK_TIMEOUT`/`_LOG_INTERVAL` の説明 (225-226行目) を確認 — grep 済み、lock/timeout 機構自体は変更しないため変更不要と判断

## Implementation Steps

1. `scripts/worktree-merge-push.sh` — push-retry ループ (現行129-148行目) を以下のロジックに書き換える (→ acceptance criteria AC1):

   ```bash
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
     echo "Push rejected (non-fast-forward); retry ${push_count}/${MAX_PUSH_RETRY}: fetching and retrying onto origin/${BASE_BRANCH}..." >&2
     git fetch origin "$BASE_BRANCH"
     if [[ -n "$FROM_BRANCH" ]]; then
       # See modules/orchestration-fallbacks.md#ff-only-merge-fallback
       worktree_path=$(git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}')
       if [[ -z "$worktree_path" ]]; then
         echo "Error: Cannot locate a worktree for ${FROM_BRANCH} to rebase without touching the shared directory's checkout. Resolve manually." >&2
         exit 1
       fi
       if ! git -C "$worktree_path" rebase "origin/${BASE_BRANCH}"; then
         git -C "$worktree_path" rebase --abort 2>/dev/null || true
         echo "Error: Rebase during push retry failed with conflicts. Resolve manually." >&2
         exit 1
       fi
       if ! git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"; then
         echo "Error: ref-fetch retry after push-rebase failed. Resolve manually." >&2
         exit 1
       fi
     else
       if ! git rebase "origin/${BASE_BRANCH}"; then
         git rebase --abort 2>/dev/null || true
         echo "Error: Rebase during push retry failed with conflicts. Resolve manually." >&2
         exit 1
       fi
     fi
     sleep 1
   done
   ```

   `$FROM_BRANCH` が設定されている場合は、primary merge path (行101-111) と同じ `git worktree list --porcelain` の awk 検索で `$FROM_BRANCH` の worktree を特定し、そこで `git -C <worktree_path> rebase` を実行後、`git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"` (**force refspec**) で共有ディレクトリの checkout に触れずローカル `$BASE_BRANCH` を更新する。force refspec が必要な理由: このリトライ時点でローカル `$BASE_BRANCH` は primary merge path が以前に設定した値のままだが、rebase 後の `$FROM_BRANCH` tip は新しく fetch した `origin/$BASE_BRANCH` を親に持つため、非 force fetch では non-fast-forward として拒否されリトライが機能しない (実 git で再現確認済み、後述の bats テスト参照)。worktree が見つからない場合は bare rebase にフォールバックせず明示エラーで exit 1。`$FROM_BRANCH` が空 (lock+push-only モード) の場合は既存の bare `git rebase` を維持する — このモードは呼び出し元の現在のブランチが `$BASE_BRANCH` そのものであることが前提のため、primary merge path 自体も `$FROM_BRANCH` が空のときはマージブロック全体をスキップしており、対称的な扱いとなる (Notes 参照)。

2. `modules/orchestration-fallbacks.md` — `## ff-only-merge-fallback` の Escalation 節にある「Push retry loop (max 3)」の記述を、Step 1 のロジックを反映して更新する: `<from-branch>` 指定時は worktree スコープの `git -C <worktree-path> rebase origin/<base>` + `git fetch . <from>:<base>` の再試行になること、worktree が見つからない場合は resolve manually で abort すること、`<from-branch>` 未指定時は bare rebase を維持すること (呼び出し元の現在のブランチが `<base>` 自体である前提のため) を明記する。Rationale に「push-retry ループの rebase を #970 でステップ5と同じ checkout レス設計に揃えた」旨の一文を追記する。(after 1) (→ acceptance criteria AC2)

3. `tests/worktree-merge-push.bats` — 既存テスト `"push race: push fails once then succeeds after fetch-rebase retry"` (行296-323) のモックに `worktree list --porcelain` ハンドラを追加し、`test-branch` に対応する fake worktree パスを返すようにする (`"--from with base-diverged triggers worktree rebase fallback"` テスト、行171-220、と同じ `WORKTREE_PATH` パターンを踏襲)。これにより同テストが新しい checkout レス retry パスを通っても green を維持する。加えて、push retry 時に bare `rebase origin/main` ではなく `git -C <worktree_path> rebase origin/main` が発行されることを検証する新規テストを追加する: 同じ push-count モック (1回目 fail→2回目 success) と `worktree list` ハンドラを使い、`grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"` と `! grep -qE "^rebase origin/main" "$GIT_LOG"` を assert する。`"max-retry exhaustion: push always fails and script exits with error"` (行364-383, `--from` なし) は既存のまま変更不要 (bare rebase パスを維持するため)。(after 1) (→ acceptance criteria AC1, AC3)

4. `bats tests/worktree-merge-push.bats` を実行し、既存テスト・新規テストがすべて green であることを確認する。(after 3) (→ acceptance criteria AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh の push-retry ループが、共有ディレクトリの現在の checkout (HEAD) に対して bare git rebase を実行するのではなく、checkout レスの ref 操作 (例: worktree スコープの git -C <path> rebase、または ref-to-ref fetch の再試行) に書き換えられている" --> push-retry ループが checkout レス設計に変更されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md#ff-only-merge-fallback またはそれに準ずるドキュメントに、push-retry ループの checkout レス化についての記述が追加されている" --> フォールバックドキュメントが push-retry ループの新設計を反映している
- <!-- verify: command "bats tests/worktree-merge-push.bats" --> 既存 bats テストスイートが green

### Post-merge

なし

## Notes

- **スコープ判断: `$FROM_BRANCH` が空 (lock+push-only モード) の push-retry は bare rebase のまま維持**: Issue 本文は「push-retry ループの checkout レス化」を求めているが、`$FROM_BRANCH` が空の場合は worktree スコープの rebase 対象となる別ブランチが存在しない。このモードは `modules/worktree-lifecycle.md` の Exit 節で `ENTERED_WORKTREE=false` (= 呼び出し元セッションが自身の対象 worktree に既に入っている、または直接 `$BASE_BRANCH` 上で作業している) 時にのみ `--from` なしで呼ばれる契約であり、primary merge path 自体も `if [[ -n "$FROM_BRANCH" ]]` でマージブロック全体をスキップして this モードでは何もしない。既存 bats テスト `"max-retry exhaustion..."` (行364-383) も `--from` なしで push-retry ループを直接検証しており、この対称性を壊さないために bare rebase を維持する判断とした。rubric AC1 の「共有ディレクトリの現在の checkout に対して bare git rebase を実行しない」は、Issue 本文の具体的な発火シナリオ (`--from` 経由の push race) を指しており、この判断と矛盾しない。
- **技術的前提の再利用**: worktree 検索 (`git worktree list --porcelain` + awk) と `git -C <path> rebase` の組み合わせは、primary merge path (現行101-111行目) で既に実装・レビュー・テスト済みのパターンをそのまま再利用するものであり、#961 Spec で実施済みのサンドボックス実証(`git fetch . <src>:<dst>` の安全特性)を超えて新たに外部仕様を確認する必要はない。
- **Steering Docs sync candidate の確認結果**: `docs/structure.md` (212行目) と `docs/tech.md` (225-226行目) は grep で該当行を確認済みで、いずれも push-retry ループの内部実装 (worktree スコープ rebase かどうか) までは踏み込まない一行要約/lock機構の説明のため、本Issueでの変更は不要と判断した。`/code` フェーズでの再確認を妨げないよう Changed Files に候補として残す。
- **設計判断の記録**: push-retry ループの `$FROM_BRANCH` 空欄時 (lock+push-only モード) の扱いについて、bare rebase を維持するかどうかが唯一の判断点だった。primary merge path 自体が同条件でマージブロックを丸ごとスキップする既存の非対称設計と整合させ、既存テスト (`"max-retry exhaustion..."`) の契約を壊さないことを優先し、bare rebase 維持を選択した (詳細は上記1項目目)。

## Code Retrospective

### Deviations from Design
- レビューフィードバック対応で1点、実装時点の Spec 記載から逸脱した: push-retry ループの retry-scoped ref-fetch (`git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"`) が実際の push race シナリオで non-fast-forward 拒否されることが判明し (レビューコメント参照)、force refspec (`git fetch . "+${FROM_BRANCH}:${BASE_BRANCH}"`) に修正した。Spec 本文・コードサンプルは本 Retrospective 追記と同じコミットで force refspec を反映済み。上記以外は Implementation Steps 1–4 を Spec の記載どおりに実装した (script rewrite → doc update → bats test → suite実行)。

### Design Gaps/Ambiguities
- N/A — Notes 節に記録済みの `$FROM_BRANCH` 空欄時の非対称設計判断以外に、実装中に新たな曖昧点は見つからなかった。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Push-retry ループの rebase を `$FROM_BRANCH` の有無で分岐: 設定時は primary merge path (step 5) と同じ `git worktree list --porcelain` + awk で worktree を特定し `git -C <path> rebase origin/<base>` を実行、未設定時 (lock+push-only モード) は bare `git rebase` を維持。primary merge path 自体が `$FROM_BRANCH` 空欄時にマージブロック全体をスキップする既存の非対称設計と整合させた。
- worktree が見つからない場合は bare rebase へのフォールバックを行わず明示エラーで exit 1 — #961 が閉じた「暗黙の checkout 依存」の再導入を避けるため。
- 既存 bats テスト (`"push race..."`) のモックに `worktree list --porcelain` ハンドラを追加して green を維持しつつ、`git -C <path> rebase` の呼び出しを直接アサートする新規テストを追加した。

### Deferred Items
- なし。Spec の Implementation Steps 1–4 をすべて実装済み。

### Notes for Next Phase
- review フェーズでは、rubric AC1 が `$FROM_BRANCH` 空欄時の bare rebase 維持を「未修正」と誤検出しないか確認してほしい (Spec Notes 節に判断根拠を記録済み)。
- `bats tests/worktree-merge-push.bats` は 16/16 green (ローカル実行済み)。CI でも再確認可能。
