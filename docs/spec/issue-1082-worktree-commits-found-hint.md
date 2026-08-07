# Issue #1082: reconcile-phase-state: code-patch の completion check に worktree コミット有無の hint を追加

## Overview

`scripts/reconcile-phase-state.sh` の `_completion_code_patch()` は `code-patch` phase の完了判定を origin/main 上の `closes #N` コミット有無のみで行っており、「未着手」(state A) と「worktree にコミット済みだが push 未完」(state B) が同一の観測値 `{"commits_found":false,"operate_signal":false,"stray_pr_signal":false}` に潰れる。本 Issue は `actual` JSON に読み取り専用の `worktree_commits_found` フィールドを追加し、Tier 1/2 診断と `code-patch-silent-no-op` 判定がこの 2 状態を機械的に区別できるようにする。`matches_expected` の判定自体は変更しない。

## Reproduction Steps

1. `/code --patch` (patch route) の実行中に worktree 上で実装コミット (`closes #N` を含む) が作成される
2. push 完了前に外部要因 (watchdog kill 等) でセッションが中断する
3. `reconcile-phase-state.sh code-patch <issue> --check-completion` を実行すると `{"commits_found":false,"operate_signal":false,"stray_pr_signal":false}` が返る — worktree に完成済みコミットが存在するにもかかわらず、実装が一切行われていない state A と同一の観測値になる
4. 実際に Issue #1074 (session `67898-1785296439`) で観測: 1 回目の「真の未着手」判定 (`code-patch-silent-no-op` → auto-retry) は正しかったが、external kill 後の 2 回目の「push 未完」状態も同じ観測値になったため、respawn 判断が誤る手前だった (parent session がコード実装を直読して回避)

## Root Cause

`_completion_code_patch()` (`scripts/reconcile-phase-state.sh`) は `commits_found` / `operate_signal` / `stray_pr_signal` の3シグナルをすべて `origin/main` または GitHub 上の状態 (commit, Issue comment marker, open PR) からのみ判定しており、ローカルの worktree branch (`worktree-code+issue-N`) 自体の状態を一切観測しない。worktree branch は同一リポジトリ内の linked worktree が作成するローカル branch であり、push 前はこの3シグナルいずれにも現れない。これが「未着手」と「コミット済み・push 未完」を区別できない根本原因である。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_patch()` に worktree branch (`worktree-code+issue-N`) の `origin/main` に対する先行コミット数を読み取り専用の `git rev-list --count` で判定するロジックを追加し、`actual_json` に `worktree_commits_found` (boolean) を追記する — bash 3.2+ compatible (no declare -A, no mapfile)
- `tests/reconcile-phase-state.bats`: state A (branch 不在) と state B (branch に先行コミットあり) を区別する bats テストを2ケース追加 — bash 3.2+ compatible
- `modules/phase-state.md`: JSON Schema (v1) の Field contract 表に `actual.worktree_commits_found` 行を追加 (SSoT: `reconcile-json-schema`)

**変更不要と確認したファイル (grep 実施済み):**

- `docs/product.md` / `docs/tech.md` / `docs/workflow.md` / `docs/structure.md` (および対応する `docs/ja/*.md`): `reconcile-phase-state.sh` への言及は役割説明レベルの一行にとどまり、completion signature の内部フィールドを列挙していないため変更不要 (`#993` の Notes と同一の判断根拠)
- `modules/orchestration-fallbacks.md`: `## async-external-commit` の four-stage 列挙は `matches_expected:true` を返す判定段の説明であり、本 Issue の追加フィールドは既存 stage 4 (label/state fallback) の直前に診断用フィールドを追記するのみで判定段自体を増やさない。Issue 本文の Out of Scope でも「fallback catalog へのエントリ追加」が明示的に除外されている
- `agents/orchestration-recovery.md`: `commits_found`/`operate_signal`/`stray_pr_signal` いずれの直接参照も grep で見つからず (`#998`/`#993` の類似フィールド追加時も同ファイルへの参照追加は不要と判断されている)、今回も同様

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` に worktree commits 判定を追加する (→ Pre-merge AC1, AC2)。挿入位置: `actual_json="${actual_json%\}},\"stray_pr_signal\":false}"` の直後、`# Fallback: check phase labels or issue state...` コメント行の直前。ロジック: `worktree_branch="worktree-code+issue-${ISSUE_NUMBER}"` として `git rev-list --count "origin/main..${worktree_branch}" 2>/dev/null` を実行し、`stray_pr_count` と同じ防御パターン (失敗時 `|| worktree_commit_count=0` に加え `[[ "$worktree_commit_count" =~ ^[0-9]+$ ]] || worktree_commit_count=0` で非数値出力もガード) を適用する。件数が 0 より大きければ `worktree_commits_found=true`、そうでなければ `false` とし、`actual_json="${actual_json%\}},\"worktree_commits_found\":${worktree_commits_found}}"` で追記する。branch が存在しない場合は `git rev-list` 自体が非 0 exit で失敗するため、追加の `git rev-parse` 存在確認は不要 (単一コマンドで branch 不在・0コミット到達の両方を `false` に正しく畳み込める)
2. `tests/reconcile-phase-state.bats` に2ケース追加する (after 1、既存の stray PR completion テスト群の末尾 — `code-patch precondition: Spec missing and Size != XS` テストの直前 — に挿入) (→ Pre-merge AC4): (a) 「worktree branch に先行コミットあり (push 未完)」— `git` mock に `rev-list` 分岐を追加し件数 `1` を返す。期待値: `matches_expected:false`, `commits_found:false`, `worktree_commits_found:true`。(b) 「worktree branch が存在しない (真の未着手)」— `git` mock の `rev-list` 分岐が非 0 exit (`fatal: unknown revision` 相当) を返す。期待値: `matches_expected:false`, `commits_found:false`, `worktree_commits_found:false`。いずれも既存の stray PR テスト群と同じ mock 方式 (`gh-graphql.sh` / `gh` / `git` を `$MOCK_DIR` に配置し `WHOLEWORK_SCRIPT_DIR` 経由で差し込む) を用いる
3. `bats tests/reconcile-phase-state.bats` を実行し全ケース PASS を確認する (after 2) (→ Pre-merge AC5)
4. `modules/phase-state.md` の JSON Schema (v1) Field contract 表に `actual.worktree_commits_found` (boolean) の行を追加する。`actual.stray_pr_signal` 行の直後に挿入し、Required 列に "When `code-patch` completion does not find a `closes #N` commit, operate marker, or stray PR"、Notes 列に判定方法 (`git rev-list --count`, read-only, branch 不在時は false) と「diagnostic only, `matches_expected` を変更しない」旨を記載する (parallel with 1) (→ Pre-merge AC2, AC3)

## Verification

### Pre-merge

- <!-- verify: grep "worktree_commits_found" "scripts/reconcile-phase-state.sh" --> `_completion_code_patch()` が worktree の先行コミット有無を示すフィールドを返している
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の _completion_code_patch() が、worktree branch (worktree-code+issue-N) の base に対する先行コミット有無を読み取り専用の git 操作で判定し、その結果を actual JSON に含めている。branch または worktree が存在しない場合は false 相当を返す" --> worktree branch 不在時も含めて判定が定義されている
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の変更により code-patch の matches_expected の真偽値が変化していない (push 未完は従来どおり false のまま)" --> matches_expected の判定は据え置かれている
- <!-- verify: rubric "tests/reconcile-phase-state.bats に、worktree にコミットがあり push 未完のケースと、コミットが一切ないケースを区別して検証するテストケースが追加されており、bats 実行が通る" --> 2状態を区別するテストが追加されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> tests/reconcile-phase-state.bats の bats 実行がすべて通る

### Post-merge

- 次回 patch route の code phase が push 未完で中断したケースで、completion check の出力から「未着手」と区別できることを観察 <!-- verify-type: opportunistic -->

## Notes

### フィールド配置・命名 (Issue 本文の自動解決を継承)

`worktree_commits_found` は `actual` JSON ルート直下に配置し (`hint_` prefix なし)、既存の兄弟フィールド (`commits_found`/`operate_signal`/`stray_pr_signal`) との命名パターンに揃える。Issue 本文の `## Auto-Resolved Ambiguity Points` で既に確定済みの判断であり、`/spec` ではこれを追認するのみ。

### 実装方式: 単一コマンドで branch 不在・0コミットを畳み込む

`git rev-parse --verify` による事前の存在確認は行わず、`git rev-list --count origin/main..<branch>` 単体に一本化した。branch が存在しない場合、このコマンドは非 0 exit (実測: exit 128, `fatal: unknown revision or path not in the working tree`, git 2.55.0 で実機確認済み) で失敗するため、既存の `stray_pr_count` と同じ「失敗時 0 フォールバック + 数値正規表現ガード」パターンで安全に `false` へ畳み込める。

### `git rev-list --count` の base は `origin/main` 固定 (パラメータ化しない)

`reconcile-phase-state.sh` は `--base` フラグを持たず、`code-patch` completion 判定全体が `origin/main` 決め打ちの実装になっている (`git fetch origin main` および `git log origin/main` を関数冒頭で使用)。本 Issue のフィールドもこの既存方針に合わせ `origin/main` 固定とし、release branch 対応などの base パラメータ化は別スコープとする。

### diagnosis 文字列への反映は見送り (Issue 本文の自動解決を継承)

Issue 本文の Proposal は「`diagnosis` 文字列に push 未完である旨を反映すると respawn 誤判定を防ぎやすい」と推奨していたが、AC 化されておらず、`docs/product.md` § `/issue` vs `/spec` Responsibility Boundary に照らし実装詳細として `/spec` も見送りを継承する。`worktree_commits_found` フィールド自体が診断情報として `actual` に含まれるため、Purpose (observability) は充足される。

### 発見事項: `code-patch-silent-no-op` fallback の Rationale が本 Issue により部分的に古くなる (対応は Out of Scope)

`modules/orchestration-fallbacks.md` の `## code-patch-silent-no-op` § Rationale (「`commits_found:false` の場合 working tree は known-clean で retry は常に安全、no partial commit can exist」) は、本 Issue が示す state B (worktree にコミット済み・push 未完) の存在と矛盾する記述になる。ただし Issue 本文の Out of Scope が「fallback catalog へのエントリ追加」を明示的に除外しており (「本 Issue は observability に限定し、復旧手順側は関連 Issue で扱う」)、`worktree_commits_found` を実際に fallback/retry 判断へ組み込む変更は本 Issue のスコープ外。フォローアップで `orchestration-fallbacks.md` の Rationale 更新および Fallback Steps への活用を検討する価値があるが、実装や起票はここでは行わない。

### Background 事実確認 (Issue 本文との整合性)

Issue 本文 Background の技術的主張 (`_completion_code_patch()` の実装内容、`run-code.sh` の無条件 stale worktree cleanup) をコードベースと再照合し、記載通りであることを確認した (`/issue` retrospective で一度確認済みの内容を `/spec` でも再確認)。矛盾は検出されなかった。

### 参考にした類似 Spec

`docs/spec/issue-998-operate-completion-signature.md` (`operate_signal` 追加) と `docs/spec/issue-993-reconcile-code-patch-stray-pr.md` (`stray_pr_signal` 追加) は同一関数への類似フィールド追加であり、挿入位置・mock 方式・数値ガードパターンの判断根拠として参照した。特に `#993` の Code Retrospective が報告した「汎用 `gh`/`git` mock が非数値文字列を返し bash 算術評価が `unbound variable` で落ちる」既知の罠は、本 Issue の実装 (Implementation Step 1) で最初から回避する設計とした。

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1082 --non-interactive` の Issue Retrospective (Background 事実確認で技術的主張がコードベースと一致することを確認、曖昧点2件の自動解決 (フィールド命名・配置、diagnosis 文字列反映の要否) を記録、AC4 の rubric に `command "bats tests/reconcile-phase-state.bats"` の補完 verify command を追加) — https://github.com/saitoco/wholework/issues/1082#issuecomment-5206875528

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1-4 を Spec の記述通りに実施した。

### Design Gaps/Ambiguities

N/A — Spec の Notes セクションで主要な論点 (フィールド配置・命名、単一コマンドでの branch 不在/0コミット畳み込み、base 固定、diagnosis 反映見送り) が事前に解決済みで、実装時に新たな設計ギャップは発生しなかった。

### Rework

N/A

## Autonomous Auto-Resolve Log

- **Step 3 の `phase/ready` ラベル不在チェックで続行を選択** — reason: Issue #1082 のラベルは `phase/ready` ではなく `phase/code` だったが (直前の `/spec` 実行がラベルを `phase/code` へ遷移済みで、`/code` 自体が前回中断した痕跡ではないと確認: `git log --all` に `closes #1082` コミットなし、`gh pr list` に該当 PR なし、`.claude/worktrees/` に `code+issue-1082` の残存なし)、`docs/spec/issue-1082-worktree-commits-found-hint.md` が既に存在し内容も完備していたため、Spec を読み込んで実装を続行する判断は最も低リスクだった。
  - Other candidates: 非対話モードでも処理を中断しユーザー判断を待つ (Spec が既に存在するため過度に保守的と判断し不採用)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate は 5/5 checked (unchecked_count=0)、review-incomplete-fallback も検出されなかったため、追加確認なしで Step 1 の mergeability チェックへ進んだ。
- `gh pr merge 1218 --squash --delete-branch` で squash merge を実行、リモートブランチは削除済み。コンフリクトは発生しなかった。

### Deferred Items
- `diagnosis` 文字列への push 未完反映は Issue 本文で明示的に見送り済み — 引き続き未対応。
- `modules/orchestration-fallbacks.md` の `code-patch-silent-no-op` Rationale が本 Issue により部分的に古くなる点は Out of Scope のまま未対応。
- Post-merge AC (opportunistic 観察: 次回 patch route の中断時に「未着手」と区別できることの実地確認) は未検証のまま。

### Notes for Next Phase
- `/verify 1082` は Post-merge AC (opportunistic) の観察のみが対象。他の Pre-merge AC はすべて merge 前に確認済み。
- Issue #1082 は `closes #1082` により squash merge で自動クローズされる見込み (base branch は main)。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — 実装は Spec Implementation Steps 1-4 と完全に一致していた (review-light Perspective 1 で確認済み)。

### Recurring issues

1件: 兄弟フィールド (`operate_signal` / `stray_pr_signal`) が使っているコメント規約 `# See modules/phase-state.md#{anchor}` をそのまま踏襲したが、Spec Notes が「独立した Completion Signature 見出しセクションは追加しない」と明示的にスコープを絞ったため、新規フィールドではこの規約の前提 (参照先見出しの存在) が崩れ、実際には存在しない見出しへのダングリング参照になっていた (SHOULD として検出・修正済み)。既存パターンをそのまま踏襲する際、「踏襲元パターンが前提とする周辺要素 (見出しの存在など) がスコープ判断で欠落していないか」を implementation phase で確認するチェックが弱かった。`modules/phase-state.md` へのフィールド追加が今後も発生しうる領域では、コメント規約 (`# See ...` 参照) の要否を見出し追加の要否判断と一体で Spec に明記しておくと、同種の SHOULD 指摘を pre-merge 前に防げる可能性がある。

### Acceptance criteria verification difficulty

Nothing to note — 5 件の Pre-merge AC (grep 1件・rubric 3件・command 1件) はいずれも曖昧さなく自動判定できた。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- triage が AC4 (bats テスト追加の rubric) に `command "bats tests/reconcile-phase-state.bats"` を機械的安全網として追加した判断が効いた。rubric 単独では「テストが追加されている」ことしか見ないが、command 併記により「追加されたテストが実際に通る」ことまで確定的に検証される。`modules/verify-patterns.md` §9 の推奨 (rubric に決定的コマンドを併記) が実際に機能した例。

#### spec

- 同一関数への類似フィールド追加という先例 (#993 の `stray_pr_signal`、#998 の `operate_signal`) に挿入位置・mock 方式・数値ガードのパターンを揃えた判断が、実装 rework ゼロにつながった。既存パターンの踏襲が明示的に設計方針として書かれていると、code フェーズの裁量が減って安定する。
- `matches_expected` の判定を変えず診断フィールドの追加に限定するスコープ設定により、既存の完了判定ロジックへの回帰リスクを構造的に排除している。AC3 がそれを明示的に守らせた。

#### code

- 実装 rework なし。Pre-merge AC 5 件すべて PASS、bats 1492 件 PASS。

#### review

- `--light` で SHOULD 1 件 (壊れたアンカー参照) を検出・修正。MUST なし。
- 副次的に Issue #1220 が起票された (`keyword=workflow` ゲートがファイル名の部分一致で誤発火する構造的欠陥、Tier 1 判定)。event-based observation scan から #476 の `/verify` を自動 dispatch した過程での発見であり、observation scan が本来の観測対象とは別の欠陥を掘り当てた形。
- **Opportunistic Verification で誤判定が 1 件発生した**。#129 の条件「残留 worktree が蓄積せず、再試行時に競合しない」を PASS と判定し `phase/done` へ遷移させたが、実測では worktree が 47 件残留しており条件は満たされていなかった。親セッションが検出して uncheck・`phase/verify` へ差し戻し、訂正コメントを投稿済み。

#### merge

- CI インフラ障害 (後述) からの復旧後に実行。squash merge、conflicts なし。

#### verify

- Post-merge の opportunistic 条件を PASS 判定できた。本来は「次回 patch route の code phase が push 未完で中断したケース」の観察を待つ条件だが、リポジトリに残留していた `worktree-code+issue-485` (base に対し 8 コミット先行、push 未完) がまさにそのケースであり、merge 済みの completion check を実行して `commits_found: false` / `worktree_commits_found: true` の分離を実データで確認した。**過去の中断結果が残っていたことが、新機能の即時検証を可能にした**。
- #1119 の verify では同種の opportunistic 条件を SKIPPED にした (「数セッション運用したのち」という時間条件が明示的だったため)。条件文が時間経過そのものを要求するか、観測可能な状態を要求するかで扱いが分かれる。

### Improvement Proposals

- **GitHub Actions のインフラ障害で本 Issue の review が 2 回スキップされた**。`macOS shell compatibility` job が 1h17m / 1h31m でタイムアウト fail、`gh run cancel` は HTTP 502、rerun / PR close-reopen / 空コミット push のいずれも新規 run を生成しない状態が約 5 時間続いた。`run-review.sh` は CI が confirmed state に達しないと exit 2 で review セッションをスキップする設計のため、この間フェーズを進められなかった。`modules/orchestration-fallbacks.md` に「CI プラットフォーム側の障害で confirmed state に到達しない」ケースの扱い (待機の判断基準、ローカル検証済みの場合の扱い) を記録する価値がある。`skills/verify/SKILL.md` の CI Infrastructure Failure Detection は verify 内の AC 判定用であり、review フェーズの進行判断には適用されない。
- **Opportunistic Verification の判定範囲が条件によっては広すぎる**。#129 の「残留 worktree が蓄積せず」はリポジトリ全体の状態を問う条件だが、`/review` セッションは自分の worktree を 1 つ作って 1 つ消しただけで PASS と判定した。`modules/opportunistic-verify.md` の判定基準 (「skill 実行の記憶を retrospect して判断」) は、条件がセッション単位で観測可能な範囲に収まっている前提に立っている。セッション単独では観測できない条件 (リポジトリ全体の集計、複数セッションにまたがる状態) を SKIP に倒す判定基準の追加を検討する。
