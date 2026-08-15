# Issue #1087: verify-patterns: §23 に実装未存在時 (実装前 AC 作成) の anchor 選定分岐を追加

## Overview

`modules/verify-patterns.md` §23 (Non-Contiguous Git Invocation — Prefer Contiguous Sub-strings) の Decision procedure (step 1-3) は、非連続シンボルに対する contiguous anchor の選定手順を定めているが、step 2/3 はいずれも「実装ファイルが既に存在すること」を暗黙の前提にしている。Wholework の Acceptance Criteria は `/issue`/`/spec` フェーズ、すなわち実装前に書かれるため、この前提は多くのケースで成立しない。

`/auto 1074` (2026-07-29) で実際にこのギャップが観測された。`/spec 1074` は非連続シンボル `curl --config` を認識したものの、実装がまだ存在しないため§23 step 2 の「連続 anchor を選び直す」を適用できず、代わりに Implementation Steps 側に「当該連続リテラルをそのまま実装に含めること」を明記する逆方向の解法を採った。この解法は正しく機能したが、§23 には記述がなく実行者ごとに再発明される状態だった (Issue #841 の Spec Retrospective で Improvement Proposal として記録)。

本 Issue は、実装未存在時 (issue/spec フェーズでの AC 作成時) の anchor 選定分岐を §23 の Decision procedure に明記し、既存 step 2/3 (実装が既に存在する場合の手順) との違いを明確化する。ドキュメント (ガイドライン) のみの変更であり、コード変更は伴わない。

## Changed Files

- `modules/verify-patterns.md`: §23 (`### 23. Non-Contiguous Git Invocation — Prefer Contiguous Sub-strings`) の "**Decision procedure:**" ブロックを改訂。既存 step 2/3 に「実装ファイルが既に存在する場合」であることを明示し、新規サブセクション "**Pre-implementation anchor selection (issue/spec phase, before `/code` runs):**" を追加して実装未存在時の分岐 (anchor を選び直す代わりに Implementation Steps 側でリテラル出現を要求する手順、および Issue #1074 の real example) を記述する
- `tests/verify-heuristics.bats`: 上記の新規分岐の存在を検証する `@test` を 2 件追加する (structural regression test)

## Implementation Steps

1. `modules/verify-patterns.md` の §23 内、"**Decision procedure:**" 見出し直後の既存番号付きリスト (現行 step 1-3、`### 24. Behavioral Changes` 見出しの直前まで) を以下のブロックに置き換える (→ acceptance criteria AC1, AC2, AC3):

   ```markdown
   **Decision procedure:**

   1. Before writing `file_contains "path" "<command> <subcommand>"` (e.g., `"git commit"`, `"git push"`, `"kubectl apply"`, `"docker compose up"`, `"ssh user@host"`), check whether the implementation may insert flags between the command name and sub-command (e.g., `git -C`, `ssh -i ~/.ssh/key user@host`, `kubectl --context prod`, `docker compose -f`)
   2. If yes (or uncertain) **and the implementation file already exists**: use `commit -s`, `commit -m`, or another contiguous sub-string anchor instead. If the implementation does not yet exist (pre-implementation — the `/issue` or `/spec` phase, before `/code` runs), see "Pre-implementation anchor selection" below instead of steps 2–3.
   3. When the implementation file already exists, verify the chosen anchor appears literally in the implementation file (cross-reference procedure from §3)

   **Pre-implementation anchor selection (issue/spec phase, before `/code` runs):**

   Steps 2 and 3 above assume the implementation file already exists — there is code to select a contiguous sub-string anchor from, and a file to cross-reference the choice against. That assumption does not hold when an acceptance condition's verify command is authored at `/issue` or `/spec` time, i.e. pre-implementation, before `/code` has produced any code: there is nothing to select an anchor from, and §3's cross-reference procedure has no file to check against.

   Rather than re-selecting the anchor from code that does not exist yet, require the implementation to conform to the anchor:

   1. Choose the contiguous anchor the verify command needs (e.g., `curl --config`)
   2. State, in the Spec's `## Implementation Steps`, an explicit requirement that the implementation include that literal contiguous substring — together with the reason (which acceptance condition's verify target string it satisfies) — so `/code` satisfies the requirement by constructing the implementation to match, instead of an anchor being selected post-hoc from existing code
   3. Keep the acceptance condition's FAIL-before-implementation / PASS-after-implementation property: do not choose an anchor already present in the codebase before implementation — that would make the condition an always-PASS defect, the same defect class `/issue`'s AC audit detects

   **Real example (Issue #1074):** the acceptance condition's verify command needed the anchor `curl --config` (`modules/verify-executor.md`'s translation table calls curl as `curl -s --connect-timeout 5 --max-time 10 [--config "$config_file"]`, where `curl` and `--config` are not contiguous). No implementation existed yet at `/spec` time, so instead of steps 2–3 above, Implementation Step 1 stated the literal-substring requirement directly: the description text must contain the contiguous string `curl --config` verbatim, because it is the AC's verify target string. `/code` satisfied this by writing `curl --config "$config_file"` in prose, and the acceptance condition correctly transitioned from FAIL (pre-implementation) to PASS (post-implementation).
   ```

   既存の step 1 の文言は変更しない。既存の step 2/3 は文言に軽微な条件句を追加するのみで、意味を変えない (後方互換)。

2. (after 1) `tests/verify-heuristics.bats` の末尾 (`@test "verify-heuristics: §23 ssh example uses real key path"` の直後) に以下 2 件の `@test` を追加する (→ acceptance criteria AC4):

   ```bash
   @test "verify-heuristics: §23 documents pre-implementation anchor selection branch" {
       grep -q "Pre-implementation anchor selection" "$VERIFY_PATTERNS"
   }

   @test "verify-heuristics: §23 pre-implementation branch preserves FAIL-before PASS-after invariant" {
       grep -q "always-PASS defect" "$VERIFY_PATTERNS"
   }
   ```

3. (after 1, 2) `bats tests/verify-heuristics.bats` をローカルで実行し、既存 7 件 + 新規 2 件の計 9 件が全て PASS することを確認する (→ acceptance criteria AC5)

## Verification

### Pre-merge

- <!-- verify: grep "pre-implementation" "modules/verify-patterns.md" --> §23 に実装未存在時の分岐が記述されている
- <!-- verify: rubric "modules/verify-patterns.md §23 の Decision procedure に、実装ファイルが未存在の場合 (issue/spec フェーズでの AC 作成時) は連続 anchor を選び直す代わりに Implementation Steps 側で当該連続リテラルの出現を要求する、という分岐が明記されている" --> 実装前 AC 作成時の解法が decision procedure に組み込まれている
- <!-- verify: rubric "modules/verify-patterns.md §23 の既存 step 2/3 (連続 anchor の選び直しと cross-reference による literal 確認) が、実装が既に存在する場合の手順であることが読み取れる形に整理されている" --> 既存手順の前提が明示されている
- <!-- verify: rubric "tests/verify-heuristics.bats に §23 の実装未存在時分岐の存在を検証するテストケースが追加されている" --> regression テストが追加されている
- <!-- verify: command "bats tests/verify-heuristics.bats" --> `tests/verify-heuristics.bats` の bats 実行が通る

### Post-merge

- 次回 `/issue` または `/spec` が実装前に非連続シンボルを対象とする verify command を生成する際、§23 の分岐に沿って Implementation Steps へのリテラル要求が行われることを確認 <!-- verify-type: opportunistic -->

## Notes

- **Steering Docs sync candidate check**: `modules/verify-patterns.md` は `modules/` 配下のファイルのため実施。ファイル名全体 (`verify-patterns.md`) での横断 grep はヒットが大量 (157.9KB 出力) かつ大半が本変更と無関係な既存参照だったため、変更対象の §23 固有キーワード (`Non-Contiguous`, `contiguous sub-string` 等) に絞って `docs/`, `tests/`, `scripts/`, `modules/` を再検索した。ライブ参照は `tests/verify-heuristics.bats` (Changed Files に含む) のみで、他のヒット (`docs/spec/issue-841-verify-patterns-§23-generalize.md`、`docs/spec/issue-837-git-contiguous-heuristic.md`、`docs/spec/issue-831-recovery-change-detection-fix.md`、`docs/sessions/62650-*/session.md`) はいずれも過去 Issue の historical record であり除外した (Exclusions 相当)。
- **Outbound pointer sync candidate check**: §23 の cross-reference 手順は同一ファイル内の §3 を指すのみで、別ファイルへのポインタはない。
- **allowed-tools impact chain check (Case 2)**: 本変更は `modules/verify-patterns.md` の内容変更だが、新規 `scripts/*.sh` 呼び出しを一切導入しない (lightweight gate 不一致) ため、reader SKILL.md 側の `allowed-tools` 追加は不要と判断した。
- **doc-checker Impact Assessment**: `docs/workflow.md` / `README.md` / `CLAUDE.md` に `verify-patterns` への直接参照はない (grep で確認済み)。モジュールの役割・一覧エントリ自体 (`docs/structure.md` の Key modules 一覧など) は変更されないため doc sync 対象はない。
- **docs/ja/ translation sync check**: `docs/translation-workflow.md` の同期対象は「top-level `docs/*.md`」のみであり、本 Issue の Changed Files (`modules/`, `tests/` 配下) はいずれも対象外。
- **BRE metacharacter detection**: Pre-merge の `grep "pre-implementation" "modules/verify-patterns.md"` に `\|` / `\(` / `\)` / `\+` / `\?` は含まれないため該当なし。
- **Patch route verify command check**: `ALWAYS_PR=false`、Size=S (patch route) だが、Pre-merge に `github_check "gh pr checks"` 形式の verify command は存在しないため該当なし。
- **String-matching verify command existence check**: AC1 の `grep "pre-implementation" "modules/verify-patterns.md"` は現時点で `NOT_FOUND` (grep 確認済み、実装前は FAIL) であり、Implementation Step 1 の新規テキストに小文字ハイフン付きの `pre-implementation` を複数箇所含めることで実装後に PASS へ遷移する設計とした。AC5 の対象ファイル `tests/verify-heuristics.bats` は現行 7 件のテストが全て PASS することを確認済み (baseline)。
- **Auto-Resolve Log**: 曖昧性解消の対話は発生していない (SPEC_DEPTH=light のため Step 7 Ambiguity Resolution 自体を skip)。Issue 本文の `## Issue Retrospective` コメント (saito, 2026-08-15T14:51:03Z) に記録済みの通り、AC 分類見直し (Post-merge AC の `verify-type` を `opportunistic` へ再分類、Pre-merge AC4 に `command "bats tests/verify-heuristics.bats"` を機械検証として補完) は `/issue` フェーズで完結し Issue 本文へ反映済みのため、Spec 作成時点での追加対応は不要と判断した。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — Step 7 (AC 分類・verify command 付与) で 2 点の機械的 defect を修正: (1) Post-merge AC の verify-type を `observation` から `opportunistic` へ再分類 (`modules/verify-classifier.md` の firing likelihood check 不合格のため)、(2) Pre-merge AC4 に `command "bats tests/verify-heuristics.bats"` を機械検証として補完 (rubric から bats 実行結果の言明を分離)。あわせて Background の `curl --config` 実例記述が `modules/verify-executor.md` の実装と一致することも確認済み。いずれも本 Spec 作成時点で Issue 本文に反映済みのため追加対応は不要と判断した。(https://github.com/saitoco/wholework/issues/1087#issuecomment-5302759410)
- No new comments since last phase (cutoff: 最新の `phase/ready` ラベル付与時刻 2026-08-15T15:08:43Z 以降のコメントなし。cross-phase marker (`verify-fail` / `preview-ac-unverified`) も該当なし)。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1-3 をそのまま実施した。

### Design Gaps/Ambiguities

- Step 9 の Behavioral Change Detection により (`modules/verify-patterns.md` を参照する他の bats ファイルが存在するため) full suite (`bats --jobs 18 tests/`) を実行したところ、`tests/claude-watchdog.bats` の `WATCHDOG_TIMEOUT env var: custom value takes effect` が FAIL した。原因を切り分けるため `scripts/claude-watchdog.sh` を直接手動実行して再現したところ、`WATCHDOG_TIMEOUT=2` で `kill "$cmd_pid"` (SIGTERM) を送出した後も実際のプロセス終了までサンドボックス環境で約 60 秒 (`sleep 60` の全体時間) かかることを確認した — この Bash ツールのサンドボックスにおけるプロセス/シグナル伝播の挙動に起因するものであり、本 Issue の変更対象ファイル (`modules/verify-patterns.md`, `tests/verify-heuristics.bats`) やそれらが参照するテスト (`tests/audit-eager-load-capability.bats` 等 5 ファイル、個別実行で 33/33 PASS 確認済み) とは無関係。`docs/tech.md` の CI parallel/serial split 分類 (FAIL→FAIL は genuine failure) には該当しない — GitHub Actions 実行環境固有の並列実行競合ではなく、このローカルサンドボックス固有のプロセスkill遅延であり、`docs/tech.md` に記載された既知の flaky テスト一覧 (`tests/post_merge_check.bats` 系統) にも含まれていない。Pre-merge AC5 の実対象コマンド `bats tests/verify-heuristics.bats` は 9/9 PASS を個別に確認済み。`scripts/claude-watchdog.sh` / `tests/claude-watchdog.bats` は本 Issue のスコープ外のため変更していない。

### Rework

N/A — rework は発生していない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- §23 の既存 step 2/3 は文言を維持しつつ「実装ファイルが既に存在する場合」の前提を条件句として追記するに留め、新規サブセクション「Pre-implementation anchor selection」を後続配置する構成にした (Spec Implementation Step 1 の指示通り、後方互換を優先)
- Issue #1074 の real example はそのまま §23 内に転記し、汎化ガイドラインと具体例の対応関係を保った

### Deferred Items
- `tests/claude-watchdog.bats` の `WATCHDOG_TIMEOUT env var: custom value takes effect` が Claude Code Bash ツールサンドボックス下で決定論的に FAIL する件は、本 Issue のスコープ外のため Issue #1366 (`retro/code`) として別途起票した

### Notes for Next Phase
- Pre-merge AC1-AC5 は全て `/code` フェーズ内で PASS 確認済み、Issue 側チェックボックスも `[x]` 済み
- `/verify` は Post-merge AC (opportunistic: 次回 `/issue`/`/spec` が非連続シンボルの verify command を実装前に生成する際の確認) を対象とする
