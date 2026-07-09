# Issue #961: scripts: worktree-merge-push.sh が共有メインディレクトリの checkout 状態に依存し、他セッションのブランチを誤って操作しうる

## Consumed Comments

- saito (MEMBER, 2026-07-09T14:31:43Z): Issue Retrospective — `/issue 961` の非対話実行が triage 直後に silent hang したため親セッションが引き継いだ旨、および Auto-Resolve Log (AC2 の verify command を `file_not_contains "git checkout"` (常時 PASS) から `file_not_contains "git pull --rebase"` へ差し替え、根拠込み) を記録。現在の Issue body にはこの差し替え後の AC2 が既に反映されている。 (https://github.com/saitoco/wholework/issues/961#issuecomment-4926136254)

なお、cutoff (直近の `phase/issue` ラベル付与: 2026-07-09T14:28:03Z) より前の Triage AC audit コメント (2026-07-09T13:45:09Z) は前フェーズ (`/issue`) 側で消費済みのため対象外だが、AC2 差し替えの発端として参考にした。

## Overview

`worktree-merge-push.sh` の FF-only マージが失敗した際のフォールバック (`git pull --rebase origin <base>`) が、共有メインディレクトリの「現在チェックアウトされているブランチ」に暗黙に依存している。これを、working directory の checkout に一切依存しない ref 操作 (`git fetch . <worktree-branch>:<base>`) に置き換える。Spec 設計時に実施したサンドボックス実証により、この ref 操作は (a) `<base>` がどこかの worktree で checkout 中なら拒否され、(b) fast-forward でない場合も拒否される — という 2 つの安全特性を持ち、`--ff-only` と同等の安全性を checkout レスで実現できることを確認した。

## Reproduction Steps

1. 同一リポジトリを共有する 2 セッション: セッション A は自分の worktree ブランチ (例: `worktree-verify+issue-266`) で作業し `worktree-merge-push.sh --from worktree-verify+issue-266` を呼び出す。セッション B は共有メインディレクトリで (worktree を使わず) 別ブランチ (例: `feat/12-kwes-form-frontend`) を直接 checkout して作業中。
2. セッション A の呼び出しで `git merge worktree-verify+issue-266 --ff-only` が実行されるが、これは共有ディレクトリの**現在の HEAD** (= セッション B の `feat/12-kwes-form-frontend`) に対して行われるため、無関係な履歴同士のマージとなり失敗する。
3. フォールバックの `git pull --rebase origin main` が、現在チェックアウトされているブランチ (= セッション B のブランチ) に対して無条件に実行され、セッション B が編集中のファイルとコンフリクトする (tofas 実インシデントでは `src/messages/ar.json` でコンフリクト発生)。
4. オペレーターが `git rebase --abort` で中断し、セッション B のブランチを origin と一致することを確認したうえで、`main` を明示的に checkout → 手動で fast-forward マージする、という本来スクリプトが自動で完了すべき処理を手動でリカバーする羽目になる。

## Root Cause

マージ本体とその FF 失敗時フォールバックの両方が、`git checkout` 状態に依存する操作 (`git merge --ff-only` は現在の HEAD に対して、`git pull --rebase origin <base>` も現在の HEAD に対してリベースする) になっている。`worktree-merge-push.sh` は常に**共有**メインディレクトリから実行される (`ExitWorktree(action: "keep")` で呼び出し元 worktree からメインディレクトリへ戻ってからスクリプトを呼ぶため) ため、そのディレクトリがたまたま何のブランチを checkout しているかが、それが実際に `$BASE_BRANCH` かどうかに関わらず、暗黙にマージ/リベース対象として扱われてしまう。

## Changed Files

- `scripts/worktree-merge-push.sh`: FF マージ失敗時のフォールバック連鎖 (現行 83-109 行目) を checkout レスの ref-fetch プライマリパスに置き換え
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` エントリを新しい checkout 非依存の手順に更新
- `tests/worktree-merge-push.bats`: FF フォールバック依存テストの git モックを新プライマリパスに合わせて更新し、「他セッションの checkout により ref-fetch が拒否されるケース」のテストを追加
- `docs/structure.md`: [Steering Docs sync candidate] `worktree-merge-push.sh` の一行説明 (212 行目) を checkout レス設計に合わせて更新
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー (204 行目)
- `docs/tech.md`: [Steering Docs sync candidate] `WHOLEWORK_PATCH_LOCK_TIMEOUT`/`_LOG_INTERVAL` の説明を確認 (lock/timeout 機構自体は変更しないため恐らく変更不要)
- `docs/ja/tech.md`: [Steering Docs sync candidate] 上記の日本語ミラーを確認 (恐らく変更不要)

## Implementation Steps

1. `scripts/worktree-merge-push.sh` — マージブロック (`if [[ -n "$FROM_BRANCH" ]]; then` の内側、現行 83-109 行目。111-117 行目のコンフリクトマーカーチェックはこの `if` の内側のまま維持) を以下のロジックに置き換える (→ acceptance criteria AC1, AC2):
   - **プライマリパス**: まず `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` を試みる。これは同一リポジトリ内の ref-to-ref fetch であり、git 自身が (a) `$BASE_BRANCH` がどこかの worktree で checkout 中なら `refusing to fetch into branch ... checked out at ...` (exit 128) で拒否し、(b) fast-forward でなければ `[rejected] ... (non-fast-forward)` (exit 1) で拒否する。成功 = working directory の checkout に一切触れずに `$BASE_BRANCH` を fast-forward できたことを意味する。
   - **フォールバック tier 1**: fetch が失敗し、かつ共有ディレクトリで `git rev-parse --abbrev-ref HEAD` が `$BASE_BRANCH` と一致する場合 (= ref-fetch が拒否する唯一のケース、共有ディレクトリ自身が `$BASE_BRANCH` を checkout している) は、その場での `git merge "$FROM_BRANCH" --ff-only` が安全かつ同等の結果になる。
   - **フォールバック tier 2** (真の分岐、かつ `$BASE_BRANCH` が共有ディレクトリで checkout されていない場合): 既存の is-ancestor チェック (`git merge-base --is-ancestor "origin/${BASE_BRANCH}" "$FROM_BRANCH"`) と、`git worktree list --porcelain` で見つけた worktree パスに対する `git -C <worktree_path> rebase "origin/${BASE_BRANCH}"` は維持する。ただし非 `-C` の最終フォールバック (`git rebase "$BASE_BRANCH" "$FROM_BRANCH"`、worktree パスが見つからない場合の現行ロジック) は削除する — これは共有ディレクトリで `$FROM_BRANCH` を暗黙に checkout してしまい、本 Issue が修正する対象と同じ欠陥クラスになるため。worktree パスが見つからない場合は "resolve manually" の明示エラーで exit 1 とする。worktree 内 rebase 成功後は、3 回目の無条件 `git merge --ff-only` ではなく `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` を再試行する (これも共有ディレクトリの checkout に触れない)。再試行も失敗した場合は明示エラーで exit 1 (既存の「自動リトライは 1 回のみ」方針を維持)。
   - `git pull --rebase origin "$BASE_BRANCH"` の行は完全に削除する。
2. `modules/orchestration-fallbacks.md` — `## ff-only-merge-fallback` エントリを更新する (→ AC3): 現行 Fallback Steps の 1-3 (`git pull --rebase` によるログ・実行・再マージ) を、Step 1 で説明した checkout レス ref-fetch プライマリパスの記述に置き換える。is-ancestor チェックと worktree スコープの rebase (現行 4a-4e) は維持しつつ、非 `-C` フォールバック (現行 4d) の削除を反映して番号を調整する。Rationale に「ref-fetch 自身の checked-out-branch 拒否が safety の根拠である」旨と本 Issue (#961) を追記する。
3. `tests/worktree-merge-push.bats` — 以下の既存テストの git モック呼び出し順序を、新プライマリパス (`--from` パスの最初の呼び出しが素の `merge` ではなく `fetch . <from>:<base>` になる) に合わせて更新する: `"--from triggers git merge --ff-only"`、`"--from with FF failure triggers git pull --rebase and retry"`、`"--from with base-diverged triggers worktree rebase fallback"`、`"--from with base-diverged and rebase conflict aborts and exits non-zero"`、`"is-ancestor true: rebase is skipped when branch already contains origin base"`。加えて、ref-fetch が「共有ディレクトリの HEAD が `$BASE_BRANCH` と一致する」以外の理由で拒否された場合 (= 他セッションの foreign checkout を模擬) に、非 `-C` の素の `git rebase`/`git merge` が共有ディレクトリに対して一切発行されないことを検証する新規テストを追加する (→ AC1, AC2)。
4. `docs/structure.md` (212 行目) と `docs/ja/structure.md` (204 行目) — `worktree-merge-push.sh` の一行説明を「ff-only merge with is-ancestor rebase-skip」から checkout レス ref-fetch 設計に言及する記述へ更新する。`docs/tech.md`/`docs/ja/tech.md` の環境変数説明は lock/timeout の仕組み自体は変更しないため、内容が現状のままで正確であることを確認する (変更不要の見込み)。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh が、共有ディレクトリで git checkout を実行せずに worktree ブランチを base ブランチにマージする (例: git fetch . <worktree-branch>:<base> による ref 更新のみ、または同等の checkout レス操作) ロジックに書き換えられている" --> スクリプトが checkout レスのマージ処理に変更されている
- <!-- verify: file_not_contains "scripts/worktree-merge-push.sh" "git pull --rebase" --> スクリプト内に、共有ディレクトリの現在の checkout 状態に暗黙に依存する `git pull --rebase` (fallback 経路) が残っていない
- <!-- verify: rubric "modules/orchestration-fallbacks.md#ff-only-merge-fallback が、ff-only マージ失敗時のフォールバックとして「現在チェックアウトされているブランチ」に依存しない安全な手順に更新されている" --> フォールバック手順も checkout 非依存に更新されている

### Post-merge

- 複数セッションが同一リポジトリで同時に worktree 作業と直接作業 (checkout) を行う環境で、`/verify`・`/spec`・`/code --patch` の merge-to-main が他セッションのブランチに影響しないことを実地確認する <!-- verify-type: manual -->

## Notes

- **技術的前提の実証 (Spec 設計時にサンドボックスで確認済み)**: `git fetch . <src>:<dst>` は (a) `<dst>` がどの worktree であれ checkout 中なら `refusing to fetch into branch ... checked out at ...` (exit 128) で拒否し、working directory には一切触れない。(b) fast-forward でない場合は `! [rejected] ... (non-fast-forward)` (exit 1) で拒否し、ref も変更されない。この 2 特性により `--ff-only` と同等の安全性を checkout レスで実現できることを確認した (2 パターンとも実際に git を動かして確認済み)。
- **Auto-Resolve Log は本フェーズでは追加なし**: Issue 側の Auto-Resolve Log (Issue Retrospective コメントに記録済み) で AC2 の verify command が既に `file_not_contains "git pull --rebase"` に差し替えられており、Spec フェーズで新たに解決すべき曖昧点はなかった。
- **非 `-C` フォールバックの削除は挙動変更を伴わない見込み**: 現行スクリプトで `git rebase "$BASE_BRANCH" "$FROM_BRANCH"` (worktree パスが見つからない場合の最終手段) に到達するのは `$FROM_BRANCH` の worktree が既に存在しない場合のみだが、Wholework の呼び出しパターンでは常に `ExitWorktree(action: "keep")` を経てから本スクリプトを呼ぶため、この分岐は実運用ではそもそも到達しない。削除は観測可能な挙動を変えるものではなく、潜在的な欠陥経路を閉じるものである。
- `docs/spec/issue-961-recovery.md` は `/issue` フェーズでの silent-hang に対する手動リカバリ記録であり、本 Issue の技術設計とは無関係のため本 Spec には引き継いでいない (プロセス上の記録として別ファイルのまま残す)。

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1〜4 を計画通りに実装した。Step 1 (`scripts/worktree-merge-push.sh` の primary path 書き換え) は本セッション開始前に既に別セッションでコミット済み (34a59d1c) だったため、本セッションでは Spec の設計 (primary path / フォールバック tier 1・2 の分岐条件) と実装内容が一致していることを確認したのみで、追加変更は行っていない。

### Design Gaps/Ambiguities
- なし。Spec の Notes に技術的前提の実証結果が記録済みで、実装時に新たに確認すべき曖昧点はなかった。

### Rework
- worktree に `EnterWorktree` を経由せずセッションを再開したため、`modules/orchestration-fallbacks.md` と `tests/worktree-merge-push.bats` への最初の Edit 呼び出しが誤って共有メインリポジトリ (`/Users/saito/src/wholework/...`) の絶対パスに対して行われ、worktree 側 (`.claude/worktrees/code+issue-961/`) には反映されなかった。`bats tests/worktree-merge-push.bats` をworktree側で実行した際に旧テスト名のまま (`--from triggers git merge --ff-only` 等) 出力されたことで発覚。差分を worktree 側にコピーし、`git checkout --` でメインリポジトリ側を元の状態に復元して解消した。再開セッションでは、Edit/Write の対象パスが実際に worktree 内を指しているか (`pwd` 確認) を先に行うべきだった。

## review retrospective

### Spec vs. implementation divergence patterns
- なし。Primary FF-merge path・rebase fallback は Spec の Implementation Steps (tier1/tier2 フォールバック分岐) と実装が完全に一致しており、構造的な乖離は見られなかった。

### Recurring issues
- **worktree-local path の取り違えが code フェーズと review フェーズで連続して発生**: 本 review フェーズでも、`Read` ツールで最初に `scripts/worktree-merge-push.sh` を絶対パス指定した際、誤って共有メインリポジトリ側 (`/Users/saito/src/wholework/scripts/...`、worktree セグメント欠落) を読み込み、旧ロジック (`git pull --rebase` あり) を見てしまうという事象があった。`git show HEAD:...` で worktree 側の実コミット内容を確認して復旧した。code フェーズの Rework 記録 (同じ取り違えを Edit で経験) と合わせて、worktree セッションで絶対パスを扱う際は `pwd` 確認または worktree セグメントを含む絶対パスの使用を徹底する運用上の弱点が2フェーズ連続で顕在化した。
- **push-retry ループの checkout 依存が本 Issue のスコープ境界をまたいで見落とされていた**: Issue #961 の Changed Files 節は primary merge path (行83-109) のみを修正対象と明示的にスコープしていたが、同一スクリプト内の push-retry ループ (行129-148、#853 由来、本 PR 未変更) には本 Issue の Root Cause と同一クラスの checkout 依存 (`git rebase` が HEAD に対して無条件に動作) が残存していた。スコープ境界の外側にある「同じ根本原因を共有するコード片」を横断的に検知する仕組みがなく、review-light エージェントへの追加コンテキスト注入 (プロンプトで明示的に当該箇所を指示) によって初めて発見できた。

### Acceptance criteria verification difficulty
- なし。Pre-merge AC 3件はいずれも rubric / file_not_contains ベースで機械的に PASS 判定でき、UNCERTAIN は発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #968 は mergeable=true / CI success / review approved の状態で Step 1 の判定条件に合致したため、conflict resolution (Step 3) を経ずに直接 Step 4 (Squash Merge) を実行した。
- `gh pr merge --squash --delete-branch` により squash merge し、リモートブランチを削除した。PR body に `closes #961` が含まれ base は `main` のため、Issue #961 は自動クローズされる想定。

### Deferred Items
- push-retry ループ (`scripts/worktree-merge-push.sh` 行129-148) の checkout 依存は review フェーズで見送られたスコープ外事項のまま。follow-up Issue 化は `/verify` フェーズでの Improvement Proposal 集約に委ねる (review フェーズからの引き継ぎを維持)。
- Post-merge AC (複数セッション環境での実地確認) は manual verify-type のため、`/verify` フェーズでの人手確認待ち。

### Notes for Next Phase
- `/verify` は Post-merge AC (複数セッションでの merge-to-main が他セッションのブランチに影響しないことの実地確認) を人手確認として扱うこと。
- CI は全ジョブ SUCCESS 済み、squash merge・remote branch 削除ともに正常完了。
- push-retry ループの checkout 依存 (review フェーズ Deferred Items 参照) について、follow-up Issue 起票の要否を判断すること。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue 961` の非対話実行が triage 直後 (Triage AC audit コメント投稿後) に silent hang → kill され、親セッション (`/auto --batch`) が引き継いで AC2 の verify command 差し替え (常時 PASS だった `file_not_contains "git checkout"` を実在文字列 `git pull --rebase` に差し替え) を含む refinement を完了させた。詳細は `docs/spec/issue-961-recovery.md` (manual recovery 記録) 参照。

#### spec
- `/spec 961` も同様に silent hang → kill されたが、Tier 1 reconciliation (`reconcile-phase-state.sh issue --check-completion`) は `matches_expected: true` を返した後、実際には spec phase 自体は最終的に正常完了 (Design complete メッセージがログに記録済み) しており、真の kill は spec 完了後・code phase 遷移の間際だったと判明した。Spec 内容そのものに欠陥はなかった。

#### code
- code phase は Tier 2 fallback catalog による自動リカバリが1回発生 (`[recovery] tier2 fallback catalog: recovered`) し、Spec の Auto Retrospective に記録済み。Code Retrospective の Rework 節が記録する「worktree-local path 取り違え」(絶対パス指定時に worktree セグメントを欠落させ共有メインリポジトリを誤編集) は、review フェーズでも再発した (下記)。

#### review
- review phase は harness kill (SIGKILL 相当、ログが phase 開始直後で途切れ、PR にコメント0件) で1回中断した。Tier 2 (anomaly detector) は unknown pattern、Tier 3 (`orchestration-recovery` sub-agent) は "transient failure, nothing to preserve" と診断し `action=retry` を返却。`run-review.sh 968 --light` の再実行で正常完了した (Review Response Summary 確認済み)。
- 再実行直前、共有 main 作業ディレクトリに **wholework に存在しない Issue #267 / PR #289 を参照する `docs/reports/orchestration-recoveries.md` への未コミット変更**を発見した。これは Issue #966 (`_repo_root` 誤算出によるリカバリ記録の誤リポジトリ書き込み、既に CLOSED = 修正済みのはず) と同型のパターンが再発したものと推測される。ユーザー承認を得て `git stash` で退避し (削除はしていない)、review 再実行をブロックしないようにした。詳細は Improvement Proposals 参照。
- review-light は Code Retrospective と同型の「worktree-local path 取り違え」(絶対パス指定時に worktree セグメントを欠落) を独立に経験し、`git show HEAD:...` で復旧した (Review Retrospective の Recurring issues 節に記録済み)。同一パターンが code/review 2 フェーズで連続再発している。
- review-light は push-retry ループ (行129-148) の checkout 依存という SHOULD 指摘を検出したが、Issue #961 の Changed Files が明示的にスコープ外としているため Skip 判定・follow-up 化を Deferred Items へ引き継いだ (Improvement Proposals 参照)。

#### merge
- squash merge は mergeable=true / CI success / review 済みで一発完了。conflict なし。

#### verify
- Pre-merge 3件 (rubric×2, file_not_contains×1) はいずれも UNCERTAIN なく一発 PASS。Post-merge の manual AC (複数セッション実地確認) は Claude 非実行のため未チェックのまま `phase/verify` を維持。verify command 自体の不整合は検出されなかった。

### Improvement Proposals

- **push-retry ループの checkout 依存 (`scripts/worktree-merge-push.sh` 行129-148) の解消**: 本 Issue #961 が解消したのは primary merge path のみで、push 失敗時の retry ループは同一スクリプト内に残る `git rebase "origin/${BASE_BRANCH}"` (bare、`-C` 指定なし) が引き続き共有ディレクトリの現在の checkout に暗黙依存している。#961 と同一の Root Cause パターンが同一ファイル内の別関数に残存しており、再発性が高い (パターン/構造的 — Tier 1 相当)。
- **worktree-local path 取り違えが code/review 2 フェーズで連続再発**: 絶対パスで `Read`/`Edit` する際に worktree セグメント (`.claude/worktrees/{name}/`) を欠落させ、共有メインリポジトリ側を誤って参照・編集する事象が、本 Issue の code フェーズと review フェーズの両方で独立に発生した。`modules/worktree-lifecycle.md` は Edit/Write 呼び出しについて `hook-worktree-path-guard.sh` で構造的に強制しているが、**Read** ツールでの誤参照 (今回2件とも実際に発生したのは Read/Edit 対象の取り違えで、Edit 自体はガードされたか手動で気づいて復旧した) は同ガードの対象外であり、繰り返し発生している (パターン/lesson — Tier 2 相当の可能性もあるが、複数 skill にまたがる共有モジュールの挙動のため Tier 1 寄りと判断)。
- **`docs/reports/orchestration-recoveries.md` への誤リポジトリ書き込みが Issue #966 修正後も再発**: review フェーズ再開直前、wholework に存在しない Issue #267/PR #289 を参照するリカバリー記録が共有 main 作業ディレクトリに未コミットで存在していた。Issue #966 (`run-auto-sub.sh` の `_repo_root` を `git rev-parse --show-toplevel` ベースに修正、CLOSED 済み) と同型の症状だが、#966 の Acceptance Criteria は `run-auto-sub.sh` の `_repo_root` のみを対象としており、Tier 3 リカバリ経路 (`spawn-recovery-subagent.sh` 等) 独自の repo-root 解決ロジックが同種の欠陥を持ったまま残っている可能性が高い。安全側で `git stash` により退避済み (削除はしていない、ユーザー承認済み)。実際に誤書き込みを行ったスクリプト・セッションを特定できていないため、Tier 1 の構造的リスク (再発・複数スクリプトにまたがる可能性) として起票を推奨する。
