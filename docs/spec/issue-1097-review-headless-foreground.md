# Issue #1097: review: headless 実行でテストをバックグラウンド実行して通知待ちするのを防ぐ

## Overview

`/review` が headless (`claude -p`) 実行時に bats テスト等をバックグラウンド実行し、「完了通知を待つ」姿勢でターンを終えると、headless セッションには通知を受け取る後続ターンが存在しないため review が恒久的に未完了のまま終了する (session `25766-1785288928`, PR #1090 で実例確認)。同型の問題は #994 で `/code` 側は個別対応済みだが、共有モジュール `modules/test-runner.md` には一般原則が明記されておらず、`/review` 固有の `## Non-Interactive Mode Behavior` 節にも前景実行の注記がない。本 Issue はこの 2 箇所に headless 制約を明記するドキュメントのみの修正であり、`/spec`・`/verify` への同種の個別注記追加は本 Issue のスコープ外 (Issue 本文に明記済み)。

## Reproduction Steps

1. `/review` を非対話モードで実行する (`run-review.sh <PR> --full`。典型的には `/auto` からの呼び出し)。
2. Step 10 など、テストコマンド (`bats` 等) を実行しうるステップで、review セッション本体または Step 10 のレビューサブエージェントが `run_in_background: true` でテストコマンドを実行する。
3. セッションが「バックグラウンドタスクの完了通知を待つ」姿勢でターンを終える。
4. セッションは headless (`claude -p`) のため、harness がセッションを再呼び出しする後続ターンが存在せず、通知は原理的に届かない。
5. `run-review.sh` は `claude exited 0` かつ `matches_expected:false` (Step 14 の Response Summary が未投稿) を検出し、`post-fallback-review-summary.sh` の fallback が発火する。fallback は先行 review の存在確認の上で定型文を投稿するが、review 自身が書くはずだった総括・`## Review Retrospective`・review → merge の Phase Handoff 更新は失われたままになる。

## Root Cause

`modules/test-runner.md` の Step 2 (Test Execution) と `skills/review/SKILL.md` の `## Non-Interactive Mode Behavior` 節は、いずれも Bash テストコマンドを前景実行するか背景実行するかについて明記していない。この空白があるため、LLM セッション (Step 10 のレビューサブエージェントを含む) は対話モードで有効な「バックグラウンド実行 + 通知待ち」パターンを非対話実行でも選択しうる。対話セッションでは harness がタスク完了時にセッションを再呼び出しするため待ちが解消するが、headless `claude -p` セッションにはその再呼び出し機構が存在せず、ターン終了後は誰も再開しない。`/code` は #994 でこの同型事象を経験し `skills/code/SKILL.md` の Behavioral Change Detection 節 (Step 9 近傍) に個別対応済みだが、`/review` には単一の「テスト実行ステップ」が存在せず、実測インシデントも Step 10 サブエージェントの自律判断が原因と見られるため、個別ステップではなく非対話時挙動を列挙している `## Non-Interactive Mode Behavior` 節に注記する方針が Issue 本文で既に確定している。修正はドキュメント (制約の明記) のみで完結し、コード上の新規ロジックは不要。

## Changed Files

- `modules/test-runner.md`: Step 2 (Test Execution) に非対話モード (headless `claude -p`) では前景実行が必須である旨と、通知が原理的に届かない理由を明記する Note を追加
- `skills/review/SKILL.md`: `## Non-Interactive Mode Behavior` 節の「Key per-step behavior in non-interactive mode:」箇条書きに、Bash によるテスト/ビルドコマンド実行 (Step 10 のレビューサブエージェントが実行するものを含む) を前景実行し完了まで待つ旨のブレットを追加
- `tests/review.bats`: `## Non-Interactive Mode Behavior` 節を抽出する `non_interactive_mode_behavior_section()` ヘルパーと、追加した前景実行の注記を検証する `@test` を追加

## Implementation Steps

1. `modules/test-runner.md` の `### Step 2: Test Execution` — `1. Execute the test command in Bash (timeout: 120 seconds)` の行の直後、`### Step 3: Result Analysis` の直前に、以下の Note を追加する (→ acceptance criteria AC1):

   ```markdown
   **Note (non-interactive mode)**: When the calling skill is running in non-interactive mode (headless `claude -p`, e.g. `--non-interactive` in `ARGUMENTS`), always run the test command in the **foreground** — do not dispatch it with `run_in_background: true` and end the turn waiting for a completion notification. A background task's completion notification is delivered only when the harness re-invokes an interactive parent session; a headless `claude -p` process has no such subsequent turn, so the notification can never arrive in principle. Ending the turn to await it leaves the phase permanently incomplete (silent no-op), not merely delayed. Interactive-mode behavior (background execution + await notification) is unaffected by this constraint.
   ```

2. (parallel with 1) `skills/review/SKILL.md` の `## Non-Interactive Mode Behavior` 節、「Key per-step behavior in non-interactive mode:」箇条書きの末尾 (既存の「Unclear review comment intent: ...」ブレットの直後、`## Review-only Mode (--review-only)` 見出しの直前) に、以下のブレットを追加する (→ acceptance criteria AC2, AC3):

   ```markdown
   - **Foreground (前景) execution for test/build commands (including commands run by Step 10's review sub-agents)**: always run these in the foreground — do not set `run_in_background: true` and end the turn waiting for a completion notification. A headless `claude -p` process has no subsequent turn to receive a background Bash task's completion notification, so ending the turn to await one leaves the phase permanently incomplete (silent no-op) rather than merely delayed — the same root cause as Issue #994's `/code` precedent. Interactive-mode behavior (background execution + await notification) is unaffected.
   ```

3. (after 2) `tests/review.bats` に、既存の `step9_section()` ヘルパー (24行目付近) の直後に以下のヘルパーを追加する:

   ```bash
   # Extract the "## Non-Interactive Mode Behavior" section from SKILL.md.
   # The section ends at the next level-2 (## ) heading (## Review-only Mode).
   non_interactive_mode_behavior_section() {
       awk '/^## Non-Interactive Mode Behavior/{found=1} /^## Review-only Mode/{found=0} found{print}' "$SKILL_FILE"
   }
   ```

   さらにファイル末尾 (既存最終テスト「Step 8: manual preview-tier AC classified UNCERTAIN without AI judgment」の直後) に以下の `@test` を追加する:

   ```bash
   @test "Non-Interactive Mode Behavior: foreground execution required for test/build commands" {
       non_interactive_mode_behavior_section | grep -q "前景"
       non_interactive_mode_behavior_section | grep -q -F "run_in_background"
   }
   ```

4. (after 3) `bats tests/review.bats` を実行し、追加テストを含む全件が PASS することを確認する (→ acceptance criteria AC4)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/test-runner.md に、非対話モード (headless claude -p) ではテストをバックグラウンド実行して完了通知を待つ形を使わず前景実行する旨が明記されている。通知が原理的に届かない理由も示されている" --> `test-runner.md` に headless でのバックグラウンド実行禁止が明記されている
- <!-- verify: rubric "skills/review/SKILL.md の Non-Interactive Mode Behavior 節に、非対話モードでは Bash によるテスト/ビルドコマンド実行 (Step 10 のレビューサブエージェントが実行するものを含む) を前景実行し完了まで待つ旨の注記が追加されている" --> `/review` 側にも前景実行の注記がある
- <!-- verify: section_contains "skills/review/SKILL.md" "## Non-Interactive Mode Behavior" "前景" --> 該当節に前景実行を示すキーワードが含まれる (rubric の補助的な機械チェック)
- <!-- verify: command "bats tests/review.bats" --> `tests/review.bats` が PASS する

### Post-merge
- Size L の PR に対して `run-review.sh <PR> --full` を実行し、silent no-op 検出 (「claude exited 0 but review phase did not complete」) が発生せず review 自身の Response Summary が投稿されることを確認する <!-- verify-type: manual -->

## Notes

- **`前景` の日英混在について (auto-resolved)**: `skills/review/SKILL.md` は他の Skill 定義ファイルと同様に英語で記述されている (Wholework の言語規約上、Skill 本体は Source code 相当)。しかし Issue 本文の AC3 (`section_contains ... "前景"`) は日本語キーワードのリテラル一致を要求しており、`/code` の precedent (#994, `skills/code/SKILL.md` Step 9) でも "前景" という日本語グロスは使われていない。Issue 本文の verify command は SSoT であり Spec 側で書き換えないため (`modules/verify-patterns.md` §18)、Implementation Steps 2 では英語プレフィックスの直後に `(前景)` を一度だけ併記する形で両立させた。
- **Issue 本文「対応方針 (案)」項目 3 (fallback コメントへの retrospective/Phase Handoff 未書き込み注記) は対象外**: Issue 本文で「検討する」と明記されており、Acceptance Criteria には含まれていないため、本 Spec の Changed Files には `scripts/post-fallback-review-summary.sh` を含めない。
- **Steering Docs sync candidate check**: Changed Files に `skills/review/SKILL.md` を含むため、キーワード `review` で `docs/`, `tests/`, `scripts/` を横断 grep したが 738 ファイルがヒットし、本変更 (プロース追加のみ) に対して具体的な同期候補を特定できるシグナルではなかった。`modules/skill-dev-doc-impact.md`「Agent/shared module addition, change, or deletion」行 (`docs/workflow.md` 影響) も確認したが、`docs/workflow.md`・`README.md`・`CLAUDE.md` のいずれも `test-runner.md` を名指しで参照していないため、同期対象は追加なし。`docs/structure.md` の `modules/test-runner.md` 一行説明 ("quality check execution and result analysis") も、今回追加するのは実行モード制約の明記であり役割自体は変わらないため更新不要と判断した。
- **`skills/spec/external-spec.md` の適用条件**: 本 Issue はシステムコマンドの仕様・フレームワーク API・環境変数/設定ファイル形式・ファイルシステム/OS 挙動のいずれも扱わないため、適用条件に該当せず参照をスキップした。
- SPEC_DEPTH は Size S から `light` を自動判定 (Step 7 Ambiguity Resolution・Step 8 Uncertainty Identification はスキップ)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: `/issue` フェーズの Issue Retrospective。AC2 の修正先を `skills/review/SKILL.md` の `## Non-Interactive Mode Behavior` 節に特定し、機械チェック用に AC3 (`section_contains ... "前景"`) を追加し、`/spec`・`/verify` への同種の個別注記追加を本 Issue のスコープ外と確定した経緯を記録 / URL: https://github.com/saitoco/wholework/issues/1097#issuecomment-5140788831

## Code Retrospective

N/A — Implementation Steps 1〜4 をそのまま実施し、設計からの逸脱・手戻り・未解決の曖昧さはなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1〜4 を逐語通りに実施 (test-runner.md への Note 追加、review/SKILL.md へのブレット追加、review.bats へのヘルパー + テスト追加)
- `bats tests/review.bats` は前景実行で完了まで待ち、12/12 PASS を確認した

### Deferred Items
- Post-merge AC (Size L の PR で `run-review.sh <PR> --full` を実行し silent no-op が発生しないことを確認) は未実施 — `/verify` フェーズで対応
- Issue 本文「対応方針 (案)」項目 3 (fallback コメントへの retrospective/Phase Handoff 未書き込み注記) は Spec Notes で明記済みの通りスコープ外のまま

### Notes for Next Phase
- Changed Files は Spec記載の3ファイルのみで完結しており、ドキュメント同期の追加対象はない (Spec Notes 参照)
- AC1/AC2 は rubric 型のため `/review` の Step 8 で AI 判定が行われる — 本 diff は Issue 本文の要求文言をそのまま反映しているため PASS を想定

## Verify Retrospective

### Phase-by-Phase Review

#### issue / spec
- スコープを「`modules/test-runner.md` (一般原則) と `skills/review/SKILL.md` (`/review` 固有の注記) の 2 箇所」に限定し、`/spec` `/verify` への同種注記追加を明示的にスコープ外としたのは妥当。#994 で `/code` が個別対応済みという先行事例を踏まえ、共有モジュール側に一般原則を置いたことで、今後の skill 追加時にも効く形になっている。
- AC3 (`section_contains ... "前景"`) を rubric の補助的な機械チェックとして併置した設計も、`modules/verify-patterns.md` §9 の rubric + grep 併用ガイドラインに沿っている。

#### code
- ドキュメントのみの変更で single-pass 完了 (`226c2839`)。rework なし。
- 注記が「何をすべきか」(前景実行) だけでなく「なぜ通知が届かないか」(完了通知は対話セッション再起動時にのみ配送される) まで書かれている点が良い。理由が無いと、将来「待てば届くのでは」と誤解される余地が残る。
- `tests/review.bats` に `Non-Interactive Mode Behavior: foreground execution required for test/build commands` を追加し、規約を回帰ガードで保護している。

#### review / merge
- patch route (Size S) のため review / merge フェーズなし。

#### verify
- pre-merge 4 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。
- AC4 (`command "bats tests/review.bats"`) は本 Issue が定めた規約どおり**前景で実行**し、全 12 ケース PASS を確認した。
- post-merge の manual 1 件は Size L の実 PR に対する `--full` review の実走が必要で Claude では実行不能。`phase/verify` 留置。

### Improvement Proposals

- N/A — 本実行では新規の構造的問題を検出しなかった。

### 観察

- **本 Issue の症状が、直前の #1106 code フェーズで実際に発現していた**。#1106 のログには「フルテストスイート (`bats tests/`) の完了を待っています。完了次第、続きの検証・コミット作業を進めます。」と記録され、`reconcile-phase-state.sh` は `matches_expected: false` (silent no-op) を返した。本 Issue の修正が先に入っていれば回避できた可能性が高い。実行順を #1106 → #1097 から #1097 → #1106 に組み替えた判断は、この実例によって事後的に裏づけられた。
- ただし #1106 の失敗は auto-retry の中断 (並行セッションが parent main を汚していたため `check-verify-dirty` が exit 1) とも重なっており、単一原因ではない。本 Issue の修正だけで #1106 が完走したとは断定できない。
- 本 `/verify` 実行時、parent main には別セッションの無関係な Spec ファイル (`docs/spec/issue-1128-*.md`) が未コミットで存在していた (`check-verify-dirty` exit 2)。skill の規定では AskUserQuestion で stash 可否を問う分岐だが、他セッションの未コミット作業に触れない方針を優先し、stash せずに続行した。verify は自前の worktree で作業しコミット対象も `docs/spec/issue-1097-*.md` に限定されるため干渉しないと判断した。
