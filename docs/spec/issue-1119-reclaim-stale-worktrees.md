# Issue #1119: worktree: 異常終了したフェーズが残す stale worktree とブランチを回収

## Overview

異常終了経路 (外部 kill 後の respawn、silent no-op 終了、wrapper クラッシュなど) では、各フェーズ (`/spec` `/code` `/review` `/merge` `/verify`) が自身の Worktree Exit ステップに到達できず、`.claude/worktrees/` 配下の worktree と対応するローカルブランチが回収されないまま残り続ける。これを解消するため、完了済み Issue/PR に対応する stale worktree・孤児ブランチ (worktree ディレクトリは既に無くブランチのみ残存するもの) を安全に回収する、単体で実行可能な棚卸しスクリプト `scripts/reclaim-stale-worktrees.sh` を新設する。

回収対象の判定は「対応する Issue が CLOSED、または対応する PR が MERGED/CLOSED」を主判定とし、以下 3 つの安全策を必須で組み込む: (1) 並行セッション除外 (`locked` かつ現行 HEAD が main の現行 HEAD と一致する worktree は除外)、(2) 未コミット変更の保護 (`git status --porcelain` が非空なら削除せず警告)、(3) squash merge されたブランチの安全な削除判定 (`git branch -d` が拒否された場合、対応する MERGED PR の `headRefOid` とブランチ tip の一致を確認してから `-D` を使う)。

## Reproduction Steps

決定的な単一コマンドでの再現はできない (外部プロセス kill、または silent no-op 終了経路が必要 — 詳細は Issue 本文の Background 参照) が、蓄積した結果は本リポジトリで直接確認できる。

`git worktree list --porcelain` を実行すると、本 Issue の作業時点で **main を除き 45 件の worktree エントリ** が存在し、うち 1 件が `prunable` (ディレクトリ実体が既に無い bats テストの残骸)、1 件が本 Spec 執筆用の現行セッション自身 (`spec+issue-1119`、`locked`) であり、残り **43 件が stale 候補** だった (Issue 本文記載の実測値「43 件」と一致)。このうち以下をサンプル確認したところ、全て完了済みだった:

- `code+issue-1006` → Issue #1006: `state=CLOSED`, `labels=[triaged, phase/verify, retro/verify]`
- `code+issue-385` → Issue #385: `state=CLOSED`, `labels=[triaged, phase/verify]`
- `patch+issue-33` → Issue #33: `state=CLOSED`, `labels=[triaged, phase/done]`
- `merge+pr-1149` → PR #1149: `state=MERGED`
- `review+pr-1001` → PR #1001: `state=MERGED` (このエントリは `detached HEAD` — ブランチ自体は既に削除済みで worktree ディレクトリのみ残存)

回収する仕組みが存在しないため、これらは今後もセッションを重ねるたびに積み上がり続ける。

## Root Cause

`modules/worktree-lifecycle.md` の Entry セクション step 2 (stale worktree check) は、これから入ろうとしている **自分自身の** `WORKTREE_NAME` と同名の worktree が残っていないかしか見ない。フェーズが正常に Exit できず、かつ後続のどのフェーズもそのフェーズ名・Issue 番号で再入場しない場合 (最も典型的には、外部 kill 後の respawn が Worktree Exit に到達する前に silent no-op で終了するケース)、その worktree と対応ブランチを見直す経路がコードベースのどこにも存在しない。`git worktree prune` は「ディレクトリ実体が既に無い」`prunable` エントリしか対象にしないため、ディレクトリが実在する stale worktree には無力である。この「誰も見直さない」状態が、実測 43 件の stale worktree と、`git worktree remove` がブランチを削除しないことに起因する孤児ブランチ (実測 9 件、うち 2 件は squash merge 済みで `git branch -d` が拒否) の蓄積として顕在化している。

## Changed Files

- `scripts/reclaim-stale-worktrees.sh`: 新規ファイル — stale worktree・孤児ブランチの棚卸し兼回収コマンド (bash 3.2+ 互換)
- `tests/reclaim-stale-worktrees.bats`: 新規ファイル — 上記スクリプトの bats テスト
- `docs/structure.md`: Key Files > Scripts > Process management に新規スクリプトのエントリを追加。Directory Layout のファイル数コメントを `(75 files)` → `(76 files)` に変更
- `modules/worktree-lifecycle.md`: Notes に、Entry セクションの同名 stale checkではカバーされない「完了済み Issue/PR に対応する worktree/ブランチの棚卸し」について、新規スクリプトへの参照を追記

## Implementation Steps

1. `scripts/reclaim-stale-worktrees.sh` を新規作成する (→ 受入条件 AC1, AC2, AC3, AC4)

   - **引数/モード**: 引数無しならデフォルトでレポートのみ (dry-run、削除は一切行わない)。`--apply` を渡した場合のみ実際に削除を実行する。誤操作による成果喪失を防ぐため、既定値は非破壊側に倒す。
   - **Step A. prunable エントリの機械的回収**: 最初に `git worktree prune -v` を実行する。これは `git worktree list --porcelain` が `prunable` と明示するエントリ (ディレクトリ実体が既に無いもの) のみを対象にする、git 標準の安全な操作。
   - **Step B. worktree 一覧の取得と分類**: `git worktree list --porcelain` を再実行し、1 レコードずつ (空行区切り) `worktree <path>` / `HEAD <sha>` / `branch refs/heads/<name>` または `detached` / `locked` (存在する場合) / `prunable` (存在する場合) を読み取る。bash 3.2 互換のため連想配列は使わず、`while IFS= read -r line; do ...; done` で 1 レコードずつ逐次処理する。最初の `worktree` エントリ (main の作業木) は判定対象から除外する。
   - **Step C. Issue/PR 番号の抽出 (kind 判定)**: 各エントリについて、`branch` 行があればそのブランチ名を、`detached` の場合は worktree ディレクトリの basename を対象文字列とし、`^worktree-.+\+(issue|pr)-([0-9]+)$` (detached の場合は先頭の `worktree-` 無しの `^.+\+(issue|pr)-([0-9]+)$`) に一致するかを確認する。

     **実装上の注意 (実データで確認済み)**: 分類は必ず `branch` 行 (実際にチェックアウトされているブランチ) を優先して行うこと。worktree ディレクトリ名とブランチ名は一致しない場合がある — 実例: `.claude/worktrees/merge+pr-1190` はディレクトリ名から PR #1190 に見えるが、実際にチェックアウトされているブランチは `worktree-code+issue-1186` (`modules/worktree-lifecycle.md` Entry step 2 の reuse 経路で付け替わったと推測される)。ディレクトリ名だけで判定すると誤ったブランチを回収対象にしかねないため、`detached` の場合のみディレクトリ名にフォールバックする。
     - 一致しない場合は `unrecognized` として分類し、削除対象から除外してレポートのみ行う (例: `issue-56-configurable-paths` のような、現行の `{phase}+{issue|pr}-{番号}` 命名規則以前の古い worktree)。
   - **Step D. 完了判定**: `kind=issue` なら `gh issue view <N> --json state -q .state` を実行し、`CLOSED` なら完了とみなす。`kind=pr` なら `gh pr view <N> --json state,headRefOid` を実行し、`MERGED` または `CLOSED` なら完了とみなす (`MERGED` の場合は `headRefOid` を後続の branch 安全削除判定のために保持する)。`gh` コマンドが失敗した場合 (認証エラー、Issue/PR 削除済みなど) は状態不明として扱い、完了とはみなさず `warned (gh lookup failed)` として削除対象から除外する。
   - **Step E. 並行セッション除外 (→ AC2)**: エントリが `locked` かつ、そのエントリの `HEAD` が現行の main の HEAD (`git -C "$MAIN_ROOT" rev-parse HEAD`; `MAIN_ROOT` は他スクリプトと同じ `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'` で解決) と一致する場合、完了判定の結果によらず無条件に除外し `excluded (concurrent-session-guard)` としてレポートする。
   - **Step F. 未コミット変更の保護 (→ AC4)**: Step D で完了と判定され、かつ Step E で除外されなかったエントリについて、`git -C "<path>" status --porcelain` を実行する。出力が非空なら削除せず `warned (uncommitted changes: N files)` としてレポートし、次のエントリへ進む (このエントリはワーキングディレクトリごと手元に残す — 退避处理は行わず、警告に留める)。
   - **Step G. 回収の実行 (`--apply` 時のみ; → AC1, AC3)**: Step D/E/F を通過したエントリについて:
     - エントリが `locked` の場合は先に `git worktree unlock "<path>"` を実行する (失敗は無視 — 既に unlock 済みなら成功扱いでよい)。
     - `git worktree remove --force "<path>"` で worktree を削除する (Step F で未コミット変更が無いことを確認済みのため `--force` は「locked 起因の拒否」のみを解除する目的であり、作業内容を握りつぶすものではない)。
     - ブランチ削除を試みる: まず `git branch -d "<branch>"`。失敗した場合 (squash merge 済みで「not fully merged」と拒否されるケース) は、`kind=pr` かつ Step D で `MERGED` と判定されていた場合に限り、`git rev-parse refs/heads/<branch>` (ブランチ tip) と Step D で取得済みの `headRefOid` を比較する。一致すれば `git branch -D "<branch>"` で安全に削除する。不一致、または `kind=issue` (対応する MERGED PR が無い) の場合は削除せず `warned (branch tip diverges from merged PR head, or no merged PR found — left in place)` としてレポートする。
     - dry-run (デフォルト) の場合は上記の削除操作を一切実行せず、`would reclaim: <path> (<branch>, kind, 判定根拠)` の形でレポートのみ行う。
   - **Step H. 孤児ブランチの回収 (worktree ディレクトリが既に無いブランチ; → AC3)**: `git branch --list 'worktree-*'` で全ブランチを列挙し、Step B で列挙済みの (現存する worktree が使用中の) ブランチを除外した残りを対象に、Step C〜D と同じ kind 判定・完了判定・headRefOid 安全削除判定を適用する (worktree ディレクトリが無いため Step E の HEAD 比較と Step F の未コミット変更チェックは適用対象外 — 作業ディレクトリ自体が存在しないため)。
   - **Step I. サマリ出力**: 実行の最後に、`pruned` / `reclaimed (worktree+branch)` / `reclaimed (orphan branch only)` / `excluded (concurrent-session-guard)` / `warned (uncommitted changes)` / `warned (branch tip diverges)` / `skipped (unrecognized)` の各カテゴリ件数と対象一覧を出力する。dry-run 時は末尾に `[dry-run] No changes made. Re-run with --apply to perform reclaim.` を出力する。

2. `tests/reclaim-stale-worktrees.bats` を新規作成する (after 1) (→ AC1, AC2, AC3, AC4 の検証)

   `tests/detect-foreign-worktree.bats` と同様に実際の git worktree を一時ディレクトリに作成して検証する (git 自体はモックしない)。`gh` は `tests/check-pre-merge-ac.bats` と同じ「`PATH` に `MOCK_DIR` を通し、`$MOCK_DIR/gh` に呼び出し引数に応じた JSON を返す mock スクリプトを置く」方式でモックする。最低限カバーするケース:
   - `prunable` エントリが `git worktree prune` 相当で回収されること
   - 完了済み Issue (`gh issue view` が `CLOSED` を返す) かつクリーンな worktree が `--apply` で削除されること
   - `locked` かつ HEAD が main の現行 HEAD と一致する worktree が除外され、`--apply` でも削除されないこと (AC2)
   - 未コミット変更がある worktree が削除されず warning になること (AC4)
   - squash merge 済み (`git branch -d` が失敗する状況を実際に squash 相当のコミットで再現) ブランチが、`gh pr view` の `MERGED`/`headRefOid` 一致により `-D` で安全に削除されること (AC3)
   - worktree ディレクトリが既に無い孤児ブランチが同じ判定ロジックで回収されること (AC3)
   - 現行の命名規則に一致しない worktree/ブランチが `unrecognized` として素通りされること
   - デフォルト (引数無し) では一切削除が行われない (dry-run) こと

3. `docs/structure.md` を更新する (after 1) (parallel with 2, 4)

   Key Files > Scripts > **Process management** のリストに `scripts/reclaim-stale-worktrees.sh` のエントリを追加する (`detect-foreign-worktree.sh` や `worktree-merge-push.sh` と同じ並び)。Directory Layout の `scripts/` ファイル数コメントを `(75 files)` から `(76 files)` に変更する。

4. `modules/worktree-lifecycle.md` を更新する (after 1) (parallel with 2, 3)

   Notes セクションに、Entry セクション step 2 の stale worktree check は「自フェーズと同名の worktree」しか見ない設計であることを踏まえ、完了済み Issue/PR に対応する worktree・孤児ブランチ全般の棚卸しには `scripts/reclaim-stale-worktrees.sh` を使う旨を追記する。

## Verification

### Pre-merge

- <!-- verify: rubric "異常終了経路 (silent no-op 終了・外部 kill 後の respawn を含む) でフェーズが作成した worktree が回収される仕組みが実装されている。実装箇所は wrapper の EXIT trap / Worktree Entry の孤児回収 / 棚卸しコマンドのいずれでもよいが、回収の発火条件がコードから読み取れること" --> 異常終了経路でも worktree が回収される
- <!-- verify: rubric "worktree 回収処理が、並行セッションが使用中の可能性がある worktree (locked かつ現行 HEAD と同じコミットにあるもの等) を回収対象から除外する判定を持っている" --> 使用中の worktree を巻き込まない除外判定がある
- <!-- verify: rubric "worktree 回収機構が、worktree ディレクトリが既に無くブランチのみ残っている孤児ブランチも回収対象に含んでいる。squash merge されたブランチで git branch -d が拒否される場合に、対応する MERGED PR の headRefOid とブランチ tip の一致を確認してから安全に削除する判定を持っている" --> 孤児ブランチも回収対象に含み、squash merge 済みブランチの安全な削除判定がある
- <!-- verify: rubric "worktree 回収処理が、削除前に対象 worktree の未コミット変更の有無 (git status --porcelain 相当) を検査し、変更がある場合は削除せず警告するか退避する経路を持っている" --> 未コミット変更のある worktree を検査し、削除せず警告/退避する

### Post-merge

- 数セッション運用したのち `git worktree list` / `git branch` に完了済み Issue/PR の worktree・ブランチが蓄積していないことを確認 <!-- verify-type: opportunistic -->

## Notes

- **実装方式の選択**: Issue 本文は「wrapper の EXIT trap で cleanup」「フェーズ開始時の孤児回収の対象拡大」「定期的な棚卸しコマンド」の 3 方向を提示していた (いずれか、または組み合わせ)。今回は単体の棚卸しコマンドを採用した。理由: 前者 2 つは `run-*.sh` 5 本と `modules/worktree-lifecycle.md` の Entry ロジック本体に手を入れる必要があり、Size M の light spec で扱うには変更範囲・リスクともに大きい。単体コマンドは影響範囲が新規ファイル 1 本 (+ テスト) に閉じており、AC1 の rubric 文言自体が「棚卸しコマンド」を明示的に許容する実装先として挙げている。将来的に `/audit` のサブコマンド化やスケジュール実行に発展させる余地はあるが、今回のスコープには含めない。
- **既定を dry-run にした理由**: Issue 本文に「削除すると成果を失いかねなかった実例」が記録されているため、明示的な `--apply`無しでは一切削除しない設計とした。これは AC4 (未コミット変更の保護) とは独立した、ツール全体としての安全側デフォルトの選択。
- **並行セッション除外の限界**: 「`locked` かつ現行 HEAD が main の現行 HEAD と一致」という判定は、Issue 本文が実測で確認した具体的な 1 パターンであり、並行セッション検出の完全な保証ではない (Issue 本文の AC 文言自体も「等」として例示に留めている)。より広く「所有プロセスが本当に終了したという積極的な証拠が無い限りは自動処理しない」という `modules/worktree-lifecycle.md` Entry step 2 の一般原則との整合は、まず主判定である「対応 Issue が CLOSED / 対応 PR が MERGED・CLOSED」で確保している — 稼働中の並行セッションが既に CLOSED/MERGED 済みの Issue/PR に対して worktree を保持し続けるケースは通常発生しない。
- **bash 3.2 互換**: `scripts/reclaim-stale-worktrees.sh` は連想配列 (`declare -A`) や `mapfile`/`readarray` (いずれも bash 4+) を使わず、`while IFS= read -r line` によるレコード単位の逐次処理で実装すること (macOS システム bash 3.2 で動作させるため)。

## Consumed Comments
No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — implemented Steps A–I and the orphan-branch step (H) exactly as specified. `classify_name()` uses a single generic regex (`^.+\+(issue|pr)-([0-9]+)$`) for both the branch-name and detached-directory-basename forms instead of the Spec's two separate regexes (`^worktree-.+\+(issue|pr)-([0-9]+)$` for branches, unprefixed for detached dirs) — the single pattern matches both forms since a `worktree-`-prefixed branch name still satisfies the more permissive pattern, so behavior is identical; not recorded as a deviation requiring an Implementation Steps update.

### Design Gaps/Ambiguities
- Step D's "gh コマンドが失敗した場合... 状態不明として扱い... `warned (gh lookup failed)` として削除対象から除外する" wording implies a specific summary category, but Step I's exhaustive category list omits it. Added `warned (gh lookup failed)` as an additional summary category (alongside the 7 Step I lists it) rather than folding it into `skipped (unrecognized)`, since the two failure modes (unparseable name vs. unreachable gh state) have different remediation paths and conflating them would obscure which one occurred.

### Rework
- Initial implementation of `check_completion()`'s issue-kind branch used the shorthand `[ "$state" = "CLOSED" ] && COMPLETION_STATE="done"` as the last statement inside its `if [ "$kind" = "issue" ]; then ... fi` block. Under `set -euo pipefail`, when the branch name's condition is false, this pattern's exit status (1, from the failed `[ ]` test) becomes the function's own return status — and since the top-level `if [ "$kind" = "issue" ]` construct itself resolves to 0 regardless (bash's documented "if with no branch taken → exit 0" rule), the *function's* last-executed-command is actually the failed `[ ]` test, not the `if`. The caller (`check_completion "$kind" "$num"`, called as a bare top-level statement, not guarded by `if`/`||`) then propagates that non-zero status and `set -e` aborts the whole script silently (no error message, no trap) — reproduced live against this repository's real worktree/branch data (script exited at exactly the point where the first `OPEN` Issue was evaluated, right after `[ "$state" = "CLOSED" ]` returned false). Root cause isolated via a series of minimal `bash -c` repros (see below) rather than guesswork. Fixed by rewriting as an explicit `if [ "$state" = "CLOSED" ]; then COMPLETION_STATE="done"; fi` (an if-statement with no else and a false condition returns exit status 0, unlike the `&&` short-circuit form). Generalizable pitfall for future bash 3.2-compatible scripts under `set -e`: **a bare `[ cond ] && assignment` as the last statement of a function is unsafe** — if `cond` is false, the function's return status becomes 1 and kills the caller's script unless the call site explicitly guards it (`if`, `||`, etc.). Prefer an explicit `if`/`fi` (or append a trailing no-op like `|| true` immediately after, though the explicit `if` is clearer) whenever such a construct could be the last thing a function executes. Audited the rest of the script for the same shape (all other `&&` usages are inside `if`-conditions or `||`-guarded, which are safe) before considering the fix complete.
- Real-data smoke test (dry-run against this repository's own ~43 stale worktree entries) surfaced two additional validations beyond the bats suite: (1) the Spec's `merge+pr-1190` example (directory name suggests PR #1190, but the checked-out branch is actually `worktree-code+issue-1186`) was classified correctly by branch-name-priority logic; (2) the current session's own worktree (`code+issue-1119`, locked, Issue still OPEN) was correctly excluded before ever reaching the locked/HEAD-match guard, since the `not-done` completion check short-circuits first — confirming the primary completion-based filter (not just the concurrent-session guard) protects an in-progress session.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented all of Steps A–I (including the orphan-branch Step H) exactly as specified in the Spec's single-script design; no split into multiple scripts or wrapper-EXIT-trap alternative was introduced.
- Used a single generic classify_name regex (`^.+\+(issue|pr)-([0-9]+)$`) instead of the Spec's two separate branch/detached-dir regexes — behaviorally identical, simpler implementation, not a functional deviation.
- Added an extra `warned (gh lookup failed)` summary category beyond Step I's 7 listed categories, since Step D's own text requires this outcome to be tracked and reported, and folding it into `skipped (unrecognized)` would conflate two different failure modes.

### Deferred Items
- Post-merge opportunistic AC (running the script for real across several sessions to confirm no re-accumulation) is left as documented — not something `/code` can satisfy pre-merge.
- No `--apply` run was executed against this repository's real worktree/branch data during implementation (only dry-run smoke testing) — the actual cleanup of the ~71 stale entries observed in the dry-run (32 worktrees + 39 orphan branches) is left for a human or a follow-up `--apply` run, since deleting real branches/worktrees is outside this Issue's implementation scope and was not requested.
- Two pre-existing, unrelated translation-sync gaps were surfaced by `scripts/check-translation-sync.sh` (`docs/guide/autonomy.md` MISSING_JA, `docs/guide/index.md` OUTDATED) — not touched, since neither file was changed by this Issue.

### Notes for Next Phase
- The `set -e` + bare `[ cond ] && assignment`-as-last-statement pitfall (see Rework above) is worth a broader sweep across other bash 3.2-compatible scripts in this repo if a reviewer wants to proactively rule out latent instances elsewhere — out of scope for this Issue's review, noted here only as a possible follow-up angle.
- All 4 pre-merge rubric ACs were self-assessed PASS directly against the implementation in Step 10; `/review` should independently confirm the rubric judgments rather than treating this as authoritative.
- The dry-run smoke test output (32 worktree+branch pairs, 39 orphan branches, 6 uncommitted-changes warnings, 9 unrecognized/skipped) is a useful reference for `/review` to spot-check specific classification edge cases against real repository state without needing to re-run anything destructively.
