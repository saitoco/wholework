# Issue #1003: review: pre-merge AC の機械チェック FAIL 時に review 通過をブロック

## Overview

`/review` の pre-merge AC 検証 (Step 8) で safe-mode 互換の機械チェック (`file_contains` / `grep` / `section_contains` 等) が FAIL しても、現状は Review body の結果テーブルに記録されるだけで、review 通過 (`COMMENT` イベントでの投稿) をブロックしない。Issue #998 (PR #1001) では、この機械チェック FAIL が review をすり抜け、`/verify` 初回実行まで検出が持ち越された。

`skills/review/SKILL.md` に、(1) Step 8 の機械チェック FAIL、(2) Step 9 の CI FAILURE を、Step 10 で構築される MUST issue → `REQUEST_CHANGES` ゲート (`gh-pr-review.sh` の `HAS_MUST` 判定) に合流させる挙動を明記し、`tests/review.bats` に対応する structural テストを追加する。

## Changed Files

- `skills/review/SKILL.md`: Step 8 に「FAIL Blocking Behavior」サブセクションを追加、Step 9 の FAILURE 記述に「Blocking by default」を追加、Step 10 (10.0/10.2) に Step 8/9 の MUST 相当エントリ注入手順を追加
- `tests/review.bats`: Step 8/Step 9 の新規記述を検証する structural テストを追加 (既存の awk セクション抽出パターンを踏襲)

## Implementation Steps

1. `skills/review/SKILL.md` Step 8 (Static Acceptance Criteria Verification) を編集 (→ AC1)。「**`file_contains` exact match check:**」パラグラフの直後、「### Checkbox Updates」の直前に、以下の内容の新規サブセクションを挿入する:

   ```markdown
   ### FAIL Blocking Behavior

   Any condition classified **FAIL** in this step is MUST-equivalent, not a passive
   table row: Step 10 (10.0/10.2) MUST add a `"severity": "MUST"`, `"path": null`
   entry for it (see Step 10's injection instructions). This reuses the existing
   MUST issue → `REQUEST_CHANGES` gate in `gh-pr-review.sh` (`HAS_MUST` scan over
   `.tmp/review-comments-$NUMBER.json`) rather than introducing a separate blocking
   mechanism — a genuinely FAILing condition (any command type; Step 8 only returns
   FAIL when the result is deterministic, never for ambiguous cases, which instead
   return UNCERTAIN) forces the review to post as `REQUEST_CHANGES` and must be
   fixed in Step 12 before `/merge`. UNCERTAIN, SKIPPED, PENDING, and POST-MERGE
   classifications do not block review.
   ```

2. `skills/review/SKILL.md` Step 9 (CI Status Check) を編集 (after 1) (→ AC2)。既存の「**FAILURE jobs**」箇条書きの末尾 (「... 'Step 8: Additional Suggestions on CI Failure' section.」の直後) に以下を追記する:

   ```markdown
   **Blocking by default**: CI FAILURE joins the same MUST-equivalent gate as
   Step 8's FAIL Blocking Behavior — Step 10 (10.0/10.2) MUST add one
   `"severity": "MUST"`, `"path": null` entry summarizing the failed job(s) so
   review cannot complete as `COMMENT` while CI is FAILURE. No built-in exception
   exists for known-flaky or unrelated-job failures; every FAILURE job blocks
   until a follow-up Issue defines an allowlist.
   ```

3. `skills/review/SKILL.md` Step 10 の2箇所を編集 (after 1, 2) (→ AC1, AC2 の注入メカニズム)。
   - **10.0 (light mode) 手順5**「**Pass results to Step 10**」内、"Issues where `path` is `null` → merge into..." の箇条書きの直後、"`mkdir -p .tmp`" の直前に新規箇条書きを挿入:
     `- **Inject Step 8/Step 9 blocking entries**: for each Step 8 condition classified FAIL, and the Step 9 CI FAILURE summary (if any), add one \`severity: "MUST"\`, \`path: null\` entry per the FAIL Blocking Behavior / Blocking by default rules`
   - **10.2 (full mode) 手順4**「**Integrate 2 groups' results and generate line comments JSON and Review body**」内、同じ文脈 (`path` が `null` の場合の General Comments マージ箇条書きの直後、"`mkdir -p .tmp`" の直前) に同一の箇条書きを挿入

4. `tests/review.bats` に structural テストを追加 (after 1, 2, 3) (→ AC3)。既存の `opportunistic_verification_section()` と同じ awk パターンで `## Step 8: Static Acceptance Criteria Verification` セクション (次の `## Step 9` 見出し手前まで) と `## Step 9: CI Status Check` セクション (次の `## Step 10` 見出し手前まで) を抽出するヘルパー関数を追加し、以下を検証する `@test` を追加する:
   - Step 8 セクションに `FAIL Blocking Behavior` 見出しと `REQUEST_CHANGES` への言及が存在する
   - Step 9 セクションに `Blocking by default` への言及が存在する

## Verification

### Pre-merge
- <!-- verify: rubric "skills/review/SKILL.md の AC 検証ステップに、safe-mode 互換の機械チェック (file_contains / grep / section_contains 等) が FAIL した場合の挙動 (review 通過のブロック、または MUST issue 化して修正を強制) が明記されている" --> 機械チェック FAIL 時のブロッキング挙動が `/review` に定義されている
- <!-- verify: rubric "skills/review/SKILL.md に、CI (gh pr checks) が FAILURE の状態で review を完了させる場合の条件または禁止が明記されている" --> CI FAIL 時の review 通過可否が明確化されている
- <!-- verify: rubric "tests/ 配下に、review の AC 検証ステップの FAIL 時ブロッキング挙動 (SKILL.md の該当記述) を検証する structural テストが存在する" --> ブロッキング挙動の structural テストが追加されている

### Post-merge
- 次回 pre-merge AC の機械チェックが FAIL する PR の `/review` 実行時、review がブロックまたは MUST issue 化することを観察 <!-- verify-type: opportunistic -->

## Notes

- **Issue 本文と実装の齟齬 (SPEC_DEPTH=light — 記録のみ、自動解決)**: Issue 本文の Auto-Resolved Ambiguity Points は「Step 11 の REQUEST_CHANGES 判定は Step 10 (コードレビュー) の MUST issue 有無のみを見ており、Step 7 の AC 機械チェック FAIL は組み込まれていない」と記述しているが、現行の `skills/review/SKILL.md` では AC 機械チェックは **Step 8** (Static Acceptance Criteria Verification) であり、「Step 7」は External Review Integration (Copilot/Claude Code Review/CodeRabbit 連携) である。判定ロジック自体 (Step 10 の MUST issue 有無のみを見ている、という指摘) は現行コードと一致しているため、Issue の意図に影響はないと判断し、本 Spec は実際のステップ番号 (Step 8/Step 9/Step 10/Step 11) を用いて実装対象を記述した。
- **スコープの一般化 (設計判断)**: Issue の AC1 は例として `file_contains` / `grep` / `section_contains` を挙げているが、本 Spec では Step 8 が返す **FAIL 判定全般** (コマンド種別を問わない) を MUST 相当として扱う設計を採用した。理由: Step 8 は安全に判定できない場合は常に UNCERTAIN を返す設計になっており (`modules/verify-executor.md` 参照)、FAIL は定義上すでに「確定的」である。command 種別で線引きするより単純で、`file_exists` / `dir_exists` / `json_field` / `symlink` / allowlist 経由の `github_check` FAIL なども同じ扱いになり、Issue の意図 (機械チェック FAIL の見逃し防止) をより広くカバーする。
- **Steering Docs sync candidate チェック結果**: `grep -l "review" docs/*.md docs/ja/*.md` は 18 ファイルにヒットする (`/review` がワークフローの中核フェーズ名であるため) が、`REQUEST_CHANGES` / `MUST issue` / review のブロッキング挙動を具体的に記述しているファイルは無い (`docs/workflow.md` の唯一のヒットは `blocked-by` 関連の無関係な文脈)。本 Issue の変更は Step 8-11 内部の手続き詳細であり、`README.md` / `docs/workflow.md` / `CLAUDE.md` のスキル一覧・フェーズ概要記述 (`modules/skill-dev-doc-impact.md` 該当) を陳腐化させないため、Changed Files への追加は不要と判断した。
- 本 Issue は Size=S (patch route) のため、この Issue 自身の実装は `/review` を経由しない (XS/S は review early-exit)。本 Spec が変更する `/review` の新しい挙動は、次回以降の PR route (M/L) Issue の review 実行時に適用される。

## Consumed Comments
- saito (MEMBER, first-class): Issue phase retrospective — triage 結果 (Type=Task/Size=S/Value=3) の確認と、3件の Auto-Resolved Ambiguity Points (AC1/AC2/AC3 の採用理由) を記録。AC本文・verify command 自体への変更なし。https://github.com/saitoco/wholework/issues/1003#issuecomment-4954255801
- code phase (2026-07-13): No new comments since last phase (cutoff: most recent `phase/*` label assignment, 2026-07-13T04:07:26Z).

## Autonomous Auto-Resolve Log

- **`phase/ready` label absent at code phase start**: at the start of this `/code 1003 --patch --non-interactive` run, the Issue already carried `phase/code` (not `phase/ready`). A Spec already existed at `docs/spec/issue-1003-review-ac-fail-blocking.md` and matched the Issue's acceptance criteria, so auto-resolved by proceeding with execution using the existing Spec rather than aborting. No content gap was found — the label state reflects an already-advanced phase transition, not a missing Spec.

## Code Retrospective

### Deviations from Design
- N/A — the 4 Implementation Steps were followed as written (Step 8 FAIL Blocking Behavior subsection, Step 9 Blocking by default paragraph, Step 10 10.0/10.2 injection bullets, `tests/review.bats` structural tests).

### Design Gaps/Ambiguities
- The Behavioral Change Detection guard in `/code` Step 9 found `tests/run-review.bats` also matches the `skills/review` grep (it builds a fixture `SKILL.md` under a temp dir for its own unrelated tests, not a dependency on this PR's Step 8/9 content changes). This triggered a full-suite `bats tests/` run instead of the narrower `tests/review.bats` scope; the full suite (1173 tests) passed, so no functional gap, only extra runtime.

### Rework
- N/A — no rework was required; all edits and the added tests passed on the first attempt.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Reused the existing MUST issue → `REQUEST_CHANGES` gate (`gh-pr-review.sh` `HAS_MUST` scan) for both Step 8 FAIL and Step 9 CI FAILURE, per the Spec's design choice — no new blocking mechanism was introduced.
- Added the 2 new structural tests to the existing `tests/review.bats` file rather than a new file, following the file's established awk-section-extraction pattern.

### Deferred Items
- No allowlist for known-flaky/unrelated CI job failures — every FAILURE job blocks by default (per Spec Notes); a follow-up Issue would need to define an allowlist if that proves too strict in practice.
- Post-merge AC (opportunistic) observes the new behavior on the next PR route Issue's `/review` run — not verifiable within this patch-route Issue itself, since Size=S skips `/review`.

### Notes for Next Phase
- This is a patch route (direct commit to main, no `/review`/`/merge` phase) — `/verify` is the next phase and should focus on the post-merge opportunistic AC (observe blocking behavior on a future PR route review).
- Full `bats tests/` suite (1173 tests) was run and passed due to Behavioral Change Detection matching `tests/run-review.bats` (unrelated fixture reference, not a real dependency) — no action needed, just informational for `/verify`.
