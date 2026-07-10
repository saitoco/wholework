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

## review retrospective

### Spec vs. 実装の乖離パターン

- push-retry ループの retry-scoped ref-fetch は、review コメント (2026-07-10) で non-fast-forward 拒否の MUST バグが指摘され、`git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` → force refspec `"+${FROM_BRANCH}:${BASE_BRANCH}"` へ修正された (commit 211eb33d)。このコミットはスクリプトと bats テストのみを更新し、Spec のコードサンプルおよび `modules/orchestration-fallbacks.md` の Escalation 記述は非 force のまま取り残されていた。review フェーズ (review-light) の Documentation Consistency / Spec Deviation 観点が両方の乖離を独立に検出し、本フェーズ内で修正済み。**パターン**: レビュー起因の修正コミットがコード+テストのみを更新し、Spec / カタログ系ドキュメント (orchestration-fallbacks.md 等) の追随更新を忘れるケースが再発している。次回以降、レビュー中に fix commit を作る際は「Spec のコードサンプル」「関連する orchestration-fallbacks.md 等のカタログドキュメント」も差分対象に含めるチェックを明示的に行うことを推奨。
- Code Retrospective の "Deviations from Design: N/A" は、上記の force refspec 差分を記録し損ねていた (review-light が検出、本フェーズで修正)。"Spec どおりに実装した" という記述は、レビュー起因の修正が入った時点で再確認が必要。

### 繰り返しイシューの有無

- 本 Issue (#970) 自体、PR #968 の review-light が検出した SHOULD 指摘から起票されたものであり、「#961 が primary merge path のみをスコープした結果、同型の欠陥が push-retry ループに残存した」という構造的パターンの再発である。今回もレビュー中に検出された force refspec バグは、#961→#970 と同様に「一部だけ checkout レス化して、関連箇所への展開が漏れる」パターンの一種と言える。今後、checkout 依存排除のような横断的な設計変更を行う Issue では、Changed Files 節に「同一スクリプト内の類似コードパス (retry ループ、エラーハンドリング分岐等) を網羅的に洗い出したか」を明示的にチェックする観点を追加すると良い。

### 受入条件検証の難易度

- rubric AC1/AC2 は問題なく判定できた。特に AC1 は `$FROM_BRANCH` 空欄時の bare rebase 維持という非対称設計を「未修正」と誤検出するリスクがあったが、Spec Notes 節に判断根拠が記録されていたため正しく PASS 判定できた — rubric 対象に複雑な条件分岐がある場合、Spec Notes への判断根拠の明記が UNCERTAIN/誤 FAIL を防ぐ効果を持つことを確認できた好例。
- PR 本文の bats 実行結果表記 ("16/16 PASS") が、本 PR で追加した新規テスト2件を含む実際の総数 (17→19) と一致しておらず、軽微な記述の陳腐化が見られた。AC自体の判定には影響しなかったが、PR 説明文の数値は生成後にテストを追加した場合ずれやすいので注意。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #983 は mergeable=clean / CI success / review approved で、conflict 解消は不要だった。squash merge を `gh pr merge 983 --squash --delete-branch` で直接実行した。
- Issue 番号は PR body の `closes #970` から抽出。base branch は `main` のため、squash merge により Issue #970 は自動クローズされる。

### Deferred Items
- なし。

### Notes for Next Phase
- `/verify 970` に進んで良い。Pre-merge verification 3件 (rubric 2件、bats command 1件) はレビューフェーズ内で確認済み。Post-merge verification は「なし」。

## Auto Retrospective

### Tier 3 recovery (review)
- **Date**: 2026-07-10 18:09 UTC
- **Issue**: #970 (PR #983) — 発生時は誤って `#983` (PR 番号) として記録された。verify フェーズで本 Spec へ是正転記し、誤設置ファイル `docs/spec/issue-983-recovery.md` は削除済み
- **Source**: spawn-recovery-subagent.sh
- **Wrapper exit code**: 1 (run-review.sh)
- **Diagnosis**: review phase の silent no-op — CI 完了済みだが Review Response Summary が PR #983 に未投稿のまま終了 (reconcile: matches_expected:false)
- **Recovery**: action=retry (run-review.sh 983 再実行) → success。false-positive anomaly の後続発生なし
- **Recovery details**: docs/reports/orchestration-recoveries.md の `2026-07-10 18:09 UTC: review-tier3-recovery` エントリ参照 (同エントリの "Issue #983" も同じ誤記)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- #961 の Verify Retrospective 改善提案 + PR #968 review の SHOULD 指摘から起票された Issue で、AC は 3 件とも機械検証可能。retro → 起票 → 実装パイプラインの好例。

#### design
- `$FROM_BRANCH` 空欄時の bare rebase 維持という非対称設計の判断根拠を Spec Notes に明記したことで、rubric AC1 の誤 FAIL を防止 (review retrospective に記録済みの好パターン)。

#### code
- review で検出された force refspec の MUST バグ (非 force fetch が non-FF 拒否されリトライ不能) を review phase 内で修正 (commit 211eb33d)。レビュー起因 fix commit が Spec/カタログドキュメントの追随更新を忘れるパターンは review retrospective に記録済み。

#### review
- review-light が MUST バグ + ドキュメント乖離を検出し、フェーズ内で解決。実効性の高いレビューだった。
- **Tier 3 recovery (review phase)**: review セッションが Review Response Summary 未投稿の silent no-op で終了し、Tier 3 sub-agent が action=retry を選択、再実行で成功。リカバリ自体は設計通りに機能した。

#### merge
- squash merge、コンフリクトなし。クリーン。

#### verify
- 全 3 AC が初回 verify で PASS (rubric 2 件 + bats 19 tests 0 failures)。
- **Recovery 記録の PR/Issue 番号混同**: Tier 3 recovery の記録処理 (`spawn-recovery-subagent.sh` の recoveries log 書き込みと `run-auto-sub.sh` の `_write_tier3_recovery_to_spec`) が、review phase では PR 番号 (983) を issue 番号として扱い、存在しない `docs/spec/issue-983-recovery.md` を新規作成、orchestration-recoveries.md にも "Issue #983" と誤記録した。post-code phase (review/merge) では wrapper 引数が PR 番号になるためで、open issue #974 (concurrent_commit_detected の自己除外が merge/review で機能しない) と同一の根本原因クラス。verify フェーズで本 Spec へ是正転記し誤設置ファイルを削除した。

### Improvement Proposals
- run-auto-sub.sh / spawn-recovery-subagent.sh の recovery 記録経路: review/merge phase では引数が PR 番号のため、Tier 3 recovery 記録が PR 番号を issue 番号として Spec ファイル作成 (`issue-<PR>-recovery.md`) と orchestration-recoveries.md 記録に使ってしまう。PR body の `closes #N` から issue 番号を解決する共通処理を挟むべき。#974 と同一根本原因クラスのため、共通の issue-number 解決ヘルパでまとめて修正するのが望ましい (Skill infrastructure improvement)。
