# Issue #1076: worktree-merge-push: base が current branch の経路にも rebase fallback を追加

## Overview

`scripts/worktree-merge-push.sh` の `--from` マージ処理 (`git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` が失敗した後の分岐) は、`current_branch == BASE_BRANCH` (true 側、L90-95) かどうかで経路を分けている。false 側 (`current_branch != BASE_BRANCH`、L96-117) は ancestry 判定 → worktree 内 rebase → 再試行という fallback を完備しているが、true 側は `git merge "$FROM_BRANCH" --ff-only` が失敗したら fallback を一切試さず即座に `exit 1` する。`/verify` は Step 2 で main リポジトリに対し常に `git checkout "$BASE_BRANCH"` を実行するため、Worktree Exit (`worktree-merge-push.sh --from`) は必ず true 側を通る。並行セッションが base を進めている状況ではこの非対称性により確定的に手動介入が必要になる (実測: 2026-07-29, Issue #1051 の `/verify`)。true 側にも false 側と同型の fallback を追加する。

false 側は rebase 対象に `origin/${BASE_BRANCH}` を使う (`git fetch . <from>:<base>` という ref-to-ref 更新に対する ff 判定のため、対象は ref そのもの)。true 側は `git merge --ff-only` がローカル checkout の HEAD (= ローカル `${BASE_BRANCH}`) に対する ff 判定であるため、rebase 対象もローカル `${BASE_BRANCH}` を使う — false 側と同じ `origin/${BASE_BRANCH}` を使うと、本スクリプト自身の in-place merge → push の間にローカル `${BASE_BRANCH}` が origin より先行する窓を塞ぎきれない。詳細は Notes を参照。

## Reproduction Steps

1. `/verify` (または `/spec`／`/code` patch route) が Worktree Exit に到達し、main リポジトリで `worktree-merge-push.sh --from <worktree-branch>` を呼び出す。
2. `/verify` Step 2 は main リポジトリで常に `git checkout "$BASE_BRANCH"` を実行済みのため、`current_branch == BASE_BRANCH` が成立し true 側 (L90-95) に入る。
3. 並行セッションが同じフェーズ実行中に `origin/$BASE_BRANCH` へ commit を push し、ローカル `$BASE_BRANCH` もそれに追従して前進する (worktree ブランチの fork 元より先へ)。
4. `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` が失敗 (理由 (a): `$BASE_BRANCH` がここで checkout 済み)。
5. true 側に入り `git merge "$FROM_BRANCH" --ff-only` を試すが、base が分岐しているため失敗 (理由 (b): fast-forward 不可)。
6. fallback が存在しないため `Error: FF merge failed even though ${BASE_BRANCH} is checked out locally. Resolve manually.` を出力して `exit 1`。

実測 (2026-07-29, Issue #1051 の `/verify`): 並行セッションが main を 2 コミット進めた (`b678c0c9`, `a4d8f28d`) 結果、上記で停止。`git -C .claude/worktrees/verify+issue-1051 rebase main` を手動実行してから再実行することで解決した。

## Root Cause

`scripts/worktree-merge-push.sh` L88 の `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` は (a) `BASE_BRANCH` がいずれかの worktree で checkout 済み (exit 128)、(b) fast-forward にならない (exit 1) という異なる 2 つの理由で失敗しうるが、L89-117 の分岐は `current_branch == BASE_BRANCH` かどうかだけで経路を選び、失敗理由を区別していない。true 側 (L90-95) は理由 (a) だけを想定した `git merge --ff-only` を 1 回試すのみで、それが (a)(b) 同時発生により失敗しても ancestry 判定も rebase も試さず `exit 1` する。false 側 (L96-117) は `git merge-base --is-ancestor` 判定 → `git worktree list --porcelain` によるパス検出 → `git -C <worktree_path> rebase origin/${BASE_BRANCH}` → 再試行、という fallback を既に持つ (Issue #522 で追加、#961/#970 で checkout レス設計に統一済み)。true 側にも同型の fallback を追加すれば解決する。false 側と同じ `origin/${BASE_BRANCH}` をそのまま流用すると、true 側特有の ff 判定基準 (ローカル checkout の HEAD) との不一致で窓が残るため、rebase 対象のみ変える (Notes 参照)。

## Changed Files

- `scripts/worktree-merge-push.sh`: true 側 (`current_branch == BASE_BRANCH`、L90-95) の `git merge --ff-only` 失敗時に、ancestry 判定 → worktree 内 rebase (対象: ローカル `$BASE_BRANCH`) → `git merge --ff-only` 再試行、という fallback を追加。false 側と重複するロジックは対象 ref を引数に取る共有関数に切り出す — bash 3.2+ compatible (既存 false 側と同じ `git worktree list --porcelain` / `git -C <path> rebase` パターンを流用、新規 bashism なし)
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` エントリの Step 2 (true 側の説明) を更新し、新しい fallback と、true/false 側で rebase 対象 ref が異なる理由を記述
- `tests/worktree-merge-push.bats`: `BASE_BRANCH` が checkout された状態かつ base が diverged した条件で fallback が発動し成功することを検証する新規テストケースを追加 — bash 3.2+ compatible (既存テストの mock パターンを流用)

## Implementation Steps

1. `scripts/worktree-merge-push.sh` — true 側 (L90-95) の `if ! git merge "$FROM_BRANCH" --ff-only; then ... exit 1; fi` を以下のロジックに置き換える (→ acceptance criteria AC1, AC2):
   - `echo "FF merge failed while ${BASE_BRANCH} is checked out; base may have diverged. Checking ancestry..." >&2`
   - `git merge-base --is-ancestor "$BASE_BRANCH" "$FROM_BRANCH"` で判定 (**ローカルの `$BASE_BRANCH`。`origin/${BASE_BRANCH}` ではない** — Notes 参照)。ancestor なら rebase をスキップ
   - ancestor でなければ `git worktree list --porcelain` で `$FROM_BRANCH` の worktree パスを検出し、`git -C "$worktree_path" rebase "$BASE_BRANCH"` を実行 (ローカル ref)。失敗時は `git -C "$worktree_path" rebase --abort 2>/dev/null || true` の後 `echo "Error: Rebase of ${FROM_BRANCH} onto ${BASE_BRANCH} failed with conflicts. Resolve manually." >&2; exit 1`。worktree が見つからない場合は false 側と同じ文言 (「共有ディレクトリの checkout に触れずに rebase する worktree が見つからない」旨) で `exit 1`
   - rebase 成功 (またはスキップ) 後、`git merge "$FROM_BRANCH" --ff-only` を再試行する (**`git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` ではなく in-place `merge`** — `$BASE_BRANCH` は checkout されたままのため false 側の ref-to-ref 再試行は使えない)。これも失敗した場合のみ既存の `Error: FF merge failed even though ${BASE_BRANCH} is checked out locally. Resolve manually.` で `exit 1`
   - false 側 (L98-111) の ancestry 判定・worktree パス検出・rebase+abort ロジックと重複するため、対象 ref (ancestry 判定と rebase の両方に使う) を引数に取る共有関数に切り出し、true 側は `"$BASE_BRANCH"`、false 側は `"origin/${BASE_BRANCH}"` を渡す形にリファクタする
2. `modules/orchestration-fallbacks.md` (after 1) — `#ff-only-merge-fallback` エントリの Step 2 (現行: 「Run `git merge <from-branch> --ff-only` in place ... Failure here aborts with exit 1」) を更新し、失敗時に true 側でも ancestry 判定 (対象: ローカル `<base-branch>`) → worktree rebase (対象: ローカル `<base-branch>`) → `git merge --ff-only` 再試行という fallback が効くことを記述する。Rationale に、true 側がローカル `<base-branch>` へ rebase する理由 (ff 判定対象はローカル checkout の HEAD であり、`origin/<base-branch>` への rebase では本スクリプト自身の in-place merge → push 間のようにローカル base が origin より先行しているケースを救えない) を追記する (→ acceptance criteria AC4)
3. `tests/worktree-merge-push.bats` (parallel with 1, 2) — 新規テストケースを追加する: 既存の `"--from with ref-fetch rejected while base is checked out locally merges in place"` (L135-163) と `"--from with base-diverged triggers worktree rebase fallback"` (L171-220) の mock パターンを組み合わせ、`rev-parse --abbrev-ref HEAD` は `main` を返す (true 側)、`git merge test-branch --ff-only` は 1 回目 exit 1・2 回目 exit 0 (カウントファイルパターン)、`git worktree list --porcelain` はモック worktree パスを返す、`merge-base --is-ancestor` は exit 1 (rebase 実行) とする mock を用意する。アサーション: `status -eq 0`、GIT_LOG に `-C <worktree_path> rebase main` が含まれる (`-C <worktree_path> rebase origin/main` は含まれない — ローカル ref を使っていることの確認)、`merge test-branch --ff-only` が 2 回呼ばれている、`push origin main` が実行されている (→ acceptance criteria AC3)
4. (after 1, 2, 3) `bats tests/worktree-merge-push.bats` を実行し、既存テスト・新規テストがすべて green であることを確認する (→ acceptance criteria AC1, AC2, AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh において、BASE_BRANCH が current branch である経路の FF merge 失敗時に、ancestry 判定と worktree での rebase を経た再試行が行われるようになっている (失敗時に即 exit せず fallback を試みる)" --> base が current branch の経路にも rebase fallback がある
- <!-- verify: rubric "rebase がコンフリクトした場合は rebase --abort したうえでエラー終了し、共有ディレクトリの作業ツリーを壊さないことが担保されている" --> rebase 失敗時の後始末が安全側に倒れている
- <!-- verify: rubric "tests/worktree-merge-push.bats に、BASE_BRANCH が checkout された状態かつ base が進んでいる (diverged) 条件で fallback が発動し成功することを検証するケースが追加されている" --> 該当条件がテストで保護されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の ff-only-merge-fallback の記述が、両経路で fallback が効くようになった変更後の挙動と一致している" --> ドキュメントが実装と整合している

### Post-merge

- 並行セッションが base に commit している状況で `/verify` を実行し、Worktree Exit が手動介入なしに完了することを確認する <!-- verify-type: opportunistic -->

## Consumed Comments

- saito (MEMBER, first-class, 2026-08-06T05:45:45Z): `/issue` フェーズの Issue Retrospective。Background の技術的主張がコードベースと一致していることの確認、rebase 対象 ref を `origin/${BASE_BRANCH}` とした Auto-Resolve 判断の理由、AC 分類・rubric-only 維持の判断、Size=M のため sub-issue splitting 対象外という Step 12 のスコープ判定を記録。内容は Issue 本文の Auto-Resolved Ambiguity Points に既に反映済み。 (https://github.com/saitoco/wholework/issues/1076#issuecomment-5200858512)
- saito (MEMBER, first-class, 2026-08-06T05:49:22Z): 「spec への申し送り」— Issue 本文の Auto-Resolved Ambiguity Points が rebase 対象を両経路とも `origin/${BASE_BRANCH}` に統一した点について、true 側は ff 判定基準がローカル checkout の HEAD であるため `origin/${BASE_BRANCH}` では窓を塞ぎきれない (特に本スクリプト自身の in-place merge → push の間、ローカル base が origin より 1 コミット先行する窓) ことを指摘し、true 側限定でローカル `${BASE_BRANCH}` へ rebase する案 (A) を推奨。本 Spec はこの推奨を採用し、Issue 本文の Auto-Resolved Ambiguity Points を true 側について修正する (Notes 参照)。 (https://github.com/saitoco/wholework/issues/1076#issuecomment-5200883050)
- saito (MEMBER, first-class, 2026-08-06T06:18:51Z, code フェーズで消費): 2026-08-06 に #1180/#1179 の `/verify` で本 Issue が扱う経路の FF 失敗が 2 件実測され、`docs/reports/orchestration-recoveries.md` に `manual-recovery-worktree-rebase` として記録済みであることを報告。根本原因・再発条件・手動復旧手順は本 Spec の Root Cause / Implementation Steps と一致しており、新たな要件変更はなし。実装への影響なし (追加の実測証跡として記録のみ)。 (https://github.com/saitoco/wholework/issues/1076#issuecomment-5201097457)

## Autonomous Auto-Resolve Log

- **Step 3 (`phase/ready` label check)**: Issue #1076 のラベルは `phase/ready` ではなく既に `phase/code` (2026-08-06T06:10:35Z に遷移済み)。`reconcile-phase-state.sh code-pr 1076 --check-precondition` も `matches_expected: false` (`phase/ready` 不在) を報告した。しかし `docs/spec/issue-1076-worktree-merge-rebase-fallback.md` は既に `/spec` フェーズで完成済み (Implementation Steps・Verification・Notes まで記載) であり、ラベル不整合は前回セッションが Step 4 のラベル遷移まで実行して中断した状態と推定される。非対話モードの auto-resolve ポリシーに従い、既存 Spec を正として実装を継続する (Spec なしでの Issue 本文直読みにはフォールバックしない — 完成済み Spec が存在するため)。

### Auto-Resolved Ambiguity Points の修正 (true 側の rebase 対象 ref)

Issue 本文の `## Auto-Resolved Ambiguity Points` は、新たに追加する rebase fallback の対象 ref を「`origin/${BASE_BRANCH}` (ローカルの `${BASE_BRANCH}` ではない)」として両経路 (true/false) 共通で解決していた。false 側については既存実装 (`git -C "$worktree_path" rebase "origin/${BASE_BRANCH}"`) との一貫性からこの判断は妥当であり変更しない。

しかし true 側については、Consumed Comments に記録した spec への申し送りコメントで以下の技術的な指摘があり、本 Spec ではこれを採用して **true 側限定でローカル `${BASE_BRANCH}` へ rebase する** よう修正する:

- false 側は rebase 後 `git fetch . <from>:<base>` という ref-to-ref 更新でローカル `${BASE_BRANCH}` を直接書き換えるため、rebase 対象を `origin/${BASE_BRANCH}` にしておけば ff 判定 (= 更新後のローカル ref が rebase 済みブランチの祖先かどうか) は常に成立する。
- true 側は rebase 後 `git merge --ff-only` を使う。この ff 判定基準は **ローカル checkout の HEAD** (= ローカル `${BASE_BRANCH}` の現在値) であり、`origin/${BASE_BRANCH}` ではない。ローカル `${BASE_BRANCH}` が `origin/${BASE_BRANCH}` より先行している場合 (例: 本スクリプト自身が true 側で in-place merge を実行してから push するまでの間、ローカル `${BASE_BRANCH}` は 1 コミット先行する)、その窓で別セッションが true 側に入ると `origin/${BASE_BRANCH}` への rebase では ff 条件を満たせず、fallback 追加後も再試行が失敗し続ける。
- ローカル `${BASE_BRANCH}` が `origin/${BASE_BRANCH}` より遅れているケース (通常の並行 push によるもの) は、true 側で rebase → merge が成功した後の push 段階で non-fast-forward となり、既存の push retry loop (L129-171、`origin/${BASE_BRANCH}` への rebase を伴う) が拾うため、ローカル ref を rebase 対象にしても取りこぼしはない。

この決定は AC 文言自体には影響しない (rubric は「ancestry 判定と rebase を経た再試行が行われている」という振る舞いレベルの検証であり、対象 ref を明記していない)。Issue 本文の Auto-Resolved Ambiguity Points の更新は本 Spec 作成フローの範囲外 (light depth では Step 7 のアンビギュイティ解決フローを実行しないため Issue 本文編集は行わない) とし、本 Notes と Issue コメントでの追跡に留める。

### Steering Docs sync candidate 確認 (更新不要と判断)

`grep -rn "worktree-merge-push" docs/ tests/ scripts/` (加えて `grep -rln "worktree-merge-push\|ff-only-merge-fallback" modules/ agents/ skills/`) で全参照箇所を確認した。

- `docs/structure.md` (Scripts > Process management の一行説明) / `docs/tech.md` (`WHOLEWORK_PATCH_LOCK_TIMEOUT`/`_LOG_INTERVAL` の説明) およびそれぞれの `docs/ja/` ミラー: いずれも lock 機構や primary path (checkout レス ref-fetch) の概要レベルの記述で、true 側 fallback の有無には言及していないため、本変更後も内容は正確 — 更新不要
- `scripts/run-auto-sub.sh:80` のポインタコメント: push-retry ループの lock+push-only mode variant (`_push_with_retry()`) を指しており、本 Issue が変更する true 側 ff-merge fallback とは別のコードパス — 更新不要
- `docs/spec/issue-*.md` (過去 Spec、100+ 件) / `docs/sessions/*/session.md` / `docs/reports/*.md`: いずれも disposable な履歴記録 (`docs/tech.md` § Spec-first (disposable) の設計判断、および `docs/reports/`・`docs/sessions/` は doc-checker.md のデフォルト除外対象と同じ扱い) であり、sync 対象外
- `docs/workflow.md` / `README.md`: `orchestration-fallbacks.md` の他アンカー (`#external-kill-parent-respawn` 等) への参照はあるが `#ff-only-merge-fallback` への参照はなく、影響なし

### 外部仕様確認のスキップ理由

Implementation Steps で使う `git merge-base --is-ancestor` / `git -C <path> rebase <ref>` / `git merge --ff-only` はいずれも `scripts/worktree-merge-push.sh` の false 側で既に使用され、既存 bats テストで動作が検証済みのプリミティブである。true 側への適用は同じプリミティブを異なる ref・異なる条件分岐で再利用するのみで新規の外部仕様調査は不要と判断した (`skills/spec/external-spec.md` の適用対象だが、既存実装による実証で代替)。

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1-4 をそのまま実装した。共有関数名は Spec で明記されていなかったため `rebase_from_branch_onto(target_ref)` と命名した (Implementation Steps の意図した引数名「対象 ref」をそのまま反映)。

### Design Gaps/Ambiguities
- なし。

### Rework
- なし。既存の false 側ロジックをそのまま `rebase_from_branch_onto()` に切り出し、true/false 両呼び出し元は引数 (ローカル `$BASE_BRANCH` / `origin/${BASE_BRANCH}`) のみを差し替える形で 1 回で実装が収束した。既存 19 bats ケースと新規 2 ケースを合わせて 21 件が green (`bats tests/worktree-merge-push.bats`)。behavioral change detection (`modules/orchestration-fallbacks.md` を `tests/run-auto-sub.bats`/`tests/orchestration-fallbacks.bats` も参照) により `bats tests/` full suite (1432+ 件) も green を確認した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- 非対話モード (`--non-interactive`) で実行。pre-merge AC gate は 4件すべてチェック済み・review-incomplete-fallback も該当なしのため、追加の override マーカーなしでそのまま merge に進んだ
- `gh pr merge --squash --delete-branch` で squash merge を実行 (mergeable=true, ci_status=success, review_status=approved を確認済み)

### Deferred Items
- Post-merge AC (opportunistic): 並行セッションが base に commit している状況で `/verify` を実行し、Worktree Exit が手動介入なしに完了することの実地確認は `/verify` に委ねる
- push retry loop の true-side checked-out gap (`git fetch . "+<from>:<base>"` が exit 128 で拒否される) 自体の修正は未着手 (review retrospective の Improvement Candidate 参照、起票は `/verify` 側の判断に委ねる)

### Notes for Next Phase
- `/verify` は Post-merge AC (opportunistic) の実地確認を行うこと (Deferred Items 参照)
- review retrospective の Improvement Candidate (`gh-pr-review.sh` の self-review 時の 422 対応) は未起票のまま — `/verify` 側で起票判断が必要

## review retrospective

### Spec vs. implementation divergence patterns

Issue 本文の Auto-Resolved Ambiguity Points (true 側 rebase 対象 ref = `origin/${BASE_BRANCH}`) と Phase Handoff / 実装 (ローカル `$BASE_BRANCH`) は一見矛盾するが、Spec の Consumed Comments に人間 (saito) による明示的な override 承認とその技術的根拠が記録されており、`modules/orchestration-fallbacks.md` の Rationale にも反映済みだった。意図的かつ文書化された設計判断であり、spec deviation としては扱わなかった。Issue 本文の Auto-Resolved Ambiguity Points 自体は当初案のまま残っており実装と食い違って見える — Spec 側で override が明記されていたからこそ `/review` が正しく判別できた。Issue 本文側も override 後の結論に更新しておくと、Spec を読まずに Issue だけを見た読者の誤解を防げる (今回は実害なし、次回以降 override 発生時の一般的な留意点として記録)。

### Recurring issues

Base Branch Conflict Pre-check (`git merge-tree`) が、この Issue 自身の Spec ファイル (`docs/spec/issue-1076-worktree-merge-rebase-fallback.md`) に対して実際のコンフリクトを検出した — 別セッションが `main` に「consumed comments fallback」コミット (`623c2371`) を同一箇所へ追加していたため。本 Issue の主題 (並行セッションによる base 分岐への対処) が、レビュー中の Spec ファイル自身にメタ的に再現した形。Pre-check が正しく機能し、`/review` の Step 12 で手動 merge + コンフリクト解消 (該当箇所は重複コメントログだったため安全に解消) を行った。Base Branch Conflict Pre-check の実効性を裏付ける実例として記録。

### Acceptance criteria verification difficulty

4件すべて rubric type で、safe mode (`always_allow`) のまま淀みなく PASS 判定できた。UNCERTAIN や verify command の不備はなし。

### Improvement Candidate

- `gh-pr-review.sh` が MUST issue 検出時に `event=REQUEST_CHANGES` で投稿を試みるが、レビュー実行アカウントと PR 作成者が同一 (本リポジトリのような single-account 運用) の場合、GitHub API が `422 Unprocessable Entity: "Review Can not request changes on your own pull request"` を返し失敗する。今回は line comments JSON に `severity` フィールドを付け忘れていたため偶然 `COMMENT` イベントとなり実害はなかったが、`severity` を正しく付与していれば同じ 422 に直面していた可能性が高い。self-review 制約下での `gh-pr-review.sh` の event 選択ロジック (MUST 検出時に `REQUEST_CHANGES` を試みて 403/422 なら `COMMENT` にフォールバックする、等) は改善余地がある。未起票 (`/verify` 側での起票判断に委ねる)。
