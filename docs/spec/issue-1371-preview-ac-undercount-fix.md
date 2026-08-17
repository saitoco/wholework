# Issue #1371: audit/auto: preview AC が UNCERTAIN のまま残る場合の Manual Waiting Count 過小計上を解消

## Overview

`skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation 集計は、`ac-tier: preview` タグを持つ pre-merge manual AC を無条件に除外している。`/review` がその preview AC を実際には検証できず `type=preview-ac-unverified` マーカーに `UNCERTAIN` のまま残した場合でも同じ扱いになり、undercounting が生じる。`/verify` が既に持つ `scripts/resolve-preview-ac-fallback.sh` 相当のマーカー解決ロジックを、この 2 つの集計処理に統合する。

## Reproduction Steps

1. `capabilities.pr-preview: true` の Issue が pre-merge に `ac-tier: preview` タグ付きの `verify-type: manual` AC を持つ。
2. `/review` がその AC を preview URL に対して検証できず (プレビュー環境未起動など)、`<!-- wholework-event: type=preview-ac-unverified ... ac=<該当インデックス> -->` マーカーを投稿して UNCERTAIN のまま PR がマージされる。
3. Issue が `phase/verify` に到達する。
4. `/audit stats` (Manual Waiting Count) または `/auto --batch` の Batch Completion Report (Pending manual confirmation) を実行すると、この AC は `ac-tier: preview` を理由に無条件除外され、`N` / `MANUAL_N` に反映されない。
5. 実際には `/review` で検証されておらず人間または次回 `/verify` の対応が必要な AC が、集計上は「対応不要」として見えなくなる。

## Root Cause

Issue #1072 で追加された `ac-tier: preview` 除外ロジックは、「pre-merge preview AC は `/review` で確認済み」という前提を無条件に適用しており、`/review` が実際に検証できたかどうか (`type=preview-ac-unverified` マーカーの `ac=` リストに該当インデックスが残っているか) を確認していない。`/verify` の pre-merge-preview AC skip rule (`skills/verify/SKILL.md` Step 5) は `scripts/resolve-preview-ac-fallback.sh` でこの区別を既に行っているが、同種のロジックが `/audit` と `/auto` の集計処理には統合されていなかった (#1072 review retrospective で既知の未対応ギャップとして記録済み)。

## Changed Files

- `skills/audit/SKILL.md`: § Manual Waiting Count (`#### Manual Waiting Count`, 現 L363-380) の N 算出 (現 L365) と N1〜N4 バケット分類用のインデックス列挙 (step 2、現 L372) を、`ac-tier: preview` 行の無条件除外から `resolve-preview-ac-fallback.sh` のマーカー解決結果を参照する条件付き除外に更新。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加 (現在 `verify-executability-marker.sh:*` は登録済みだが本スクリプトは未登録)
- `skills/auto/SKILL.md`: § Batch Completion Report → Pending manual confirmation の `MANUAL_N` カウント条件 (現 L1267) を同様に更新。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加 (未登録)
- `tests/audit-manual-waiting-count.bats`: 新規作成 — `skills/audit/SKILL.md` の Manual Waiting Count セクションに対する構造テスト (`tests/auto-completion-report.bats` と同型)
- `tests/auto-completion-report.bats`: 既存の `batch_completion_section` ヘルパを使う新規 `@test` を追加

## Implementation Steps

1. `skills/audit/SKILL.md` § Manual Waiting Count を更新する (→ acceptance criteria 1, 2)。
   - N 算出の一文 (「Scan each Issue currently labeled `phase/verify` ... excluding lines that also carry `ac-tier: preview` ...」) を、以下の per-line ルールに書き換える: `ac-tier: preview` を伴わない unchecked `verify-type: manual` 行は常にカウント対象。`ac-tier: preview` を伴う行は、`${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh <issue>` (`/verify` Step 5 が使うものと同じスクリプト) の出力 (カンマ区切りの 1-based AC インデックス) に、その行自身の Issue 本文全体での 1-based インデックス (`gh-issue-edit.sh --checkbox` と同じ採番規約) が含まれる場合のみカウント対象とする。
   - step 2 (インデックス列挙) を同じ per-line ルールで更新し、N 算出時と一貫させる。
   - step 4 の N1〜N4 分類ロジック本体 (優先順位・`verify-executability-marker.sh` ベースの判定) は変更しない — 新たにカウント対象へ含まれた preview AC も既存ロジックでそのまま分類されることを、N1 (unevaluated) の説明に一文補足して明示する。新規バケットは追加しない。
   - `modules/l0-surfaces.md` § Machine-Readable Event Marker の `type=preview-ac-unverified` 節への参照を含める (既存 step 1 が `type=verify-executability` について行っている参照と同じ形式)。
2. `skills/audit/SKILL.md` frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加する (`verify-executability-marker.sh:*` の直後に挿入) (after 1)。
3. `skills/auto/SKILL.md` § Batch Completion Report → Pending manual confirmation の `MANUAL_N` カウント条件 (item 3 の第 1 サブ項目) を、step 1 と同じ per-line ルール (`resolve-preview-ac-fallback.sh $NUMBER` の出力を参照) に更新する (→ acceptance criteria 3, 4)。既存のフラットカウント構造 (バケット分解なし) は維持し、末尾に「best-effort aggregation のまま」である旨を一文残す。
4. `skills/auto/SKILL.md` frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加する (after 3)。
5. テストを追加し、`bats tests/*.bats` を実行して全件 PASS することを確認する (after 1, 2, 3, 4) (→ acceptance criteria 5)。
   - `tests/audit-manual-waiting-count.bats` を新規作成: `tests/auto-completion-report.bats` と同型の構造テスト。`#### Manual Waiting Count` セクションを抽出するヘルパ (`awk '/^#### Manual Waiting Count/{found=1} /^#### / && !/Manual Waiting Count/{found=0} /^### / {found=0} found{print}'`) を定義し、(a) セクションが `preview-ac-unverified` を含むこと、(b) `N1 + N2 + N3 + N4 = N` の不変条件記述が引き続き存在することを検証する `@test` を追加する。
   - `tests/auto-completion-report.bats` に、既存の `batch_completion_section` ヘルパを使い、Batch Completion Report セクションが `preview-ac-unverified` を含むことを検証する `@test` を追加する。

## Verification

### Pre-merge
- <!-- verify: rubric "skills/audit/SKILL.md の Manual Waiting Count セクションが、ac-tier: preview タグを持つ AC を無条件除外するのではなく、resolve-preview-ac-fallback.sh 相当のマーカー解決結果 (type=preview-ac-unverified マーカーの ac= リスト) を参照し、UNCERTAIN のまま残った preview AC はカウント対象に含める記述に更新されている。この更新は N の算出と N1〜N4 バケット分類用のインデックス列挙の両方に一貫して反映されており、既存の N1〜N4 分類ロジック (verify-executability-marker.sh ベース) をそのまま流用して新たに含まれた preview AC も分類する記述になっている (新規バケットの追加はしない)" --> `/audit` の Manual Waiting Count が preview-ac-unverified マーカー未解決分を N・N1〜N4 の両方で正しくカウントする
- <!-- verify: section_contains "skills/audit/SKILL.md" "Manual Waiting Count" "preview-ac-unverified" --> Manual Waiting Count セクションが preview-ac-unverified マーカーの解決に言及している
- <!-- verify: rubric "skills/auto/SKILL.md の Pending manual confirmation 集計ロジック (MANUAL_N のカウント条件) が同様に、ac-tier: preview タグを持つ AC を無条件除外するのではなく resolve-preview-ac-fallback.sh 相当のマーカー解決結果を参照し、UNCERTAIN のまま残った preview AC はカウント対象に含める記述に更新されている。既存のフラットカウント構造 (バケット分解なし) は維持されている" --> `/auto` の Pending manual confirmation 集計が preview-ac-unverified マーカー未解決分を正しくカウントする
- <!-- verify: section_contains "skills/auto/SKILL.md" "Batch Completion Report" "preview-ac-unverified" --> Pending manual confirmation セクションが preview-ac-unverified マーカーの解決に言及している
- <!-- verify: command "bats tests/*.bats" --> 既存の bats テストがすべて PASS する (加えて、新規ロジックを検証する新規テストケース `tests/audit-manual-waiting-count.bats` と `tests/auto-completion-report.bats` の新規 `@test` を追加したうえで PASS すること)

### Post-merge

Issue 本文に Post-merge セクションはなく、すべて Pre-merge auto-verified AC として完結している。追加の post-merge 確認事項なし。

## Notes

- **Comment Consumption Procedure で Issue 本文の verify command を修正済み**: `/spec` 開始時に Issue #1371 のコメント (2026-08-16T08:38:23Z, saito, MEMBER, first-class) を消費した結果、`section_contains` verify command 2 件 (AC2, AC4 相当) の heading 引数が `"#### Manual Waiting Count"` / `"### Batch Completion Report"` と先頭に `#` を含んだまま書かれており、`modules/verify-executor.md` の `section_contains` 定義 (heading 引数はファイル側見出し行を先頭 `#` 除去後に部分一致) により恒久的に UNCERTAIN になる不具合を検出した。コメントの修復案通り `"Manual Waiting Count"` / `"Batch Completion Report"` (先頭 `#` なし) に修正し、Issue 本文を更新済み (Auto-Resolve Log に記録)。本 Spec の Verification は修正後の verify command を反映している。
- **New test case requirement for new branch logic の適用**: 両 SKILL.md の変更はいずれも「`ac-tier: preview` かつ resolve-preview-ac-fallback.sh の未解決リストに含まれる」という新しい条件分岐を既存の集計ロジックに追加するものであるため、`tests/audit-manual-waiting-count.bats` (新規ファイル) と `tests/auto-completion-report.bats` の新規 `@test` を追加した。両者とも `tests/auto-completion-report.bats` の既存パターンに倣った構造テスト (SKILL.md の対象セクションが `preview-ac-unverified` を含むことの grep ベース確認) であり、SKILL.md は LLM 実行のプローズ仕様であるため bats で実行結果を直接検証できない制約下での既存の妥当なテスト手法を踏襲している。
- **`modules/l0-surfaces.md` / `docs/structure.md` は変更不要と判断**: `resolve-preview-ac-fallback.sh` の既存ドキュメント (両ファイルとも) は「`/verify` が消費する」という記述だが、スクリプト自体の仕様 (マーカー解決・fail-open 挙動) についての記述であり、`/audit`・`/auto` が同じ出力を別の目的 (カウント判定) で追加参照するようになっても文言は虚偽にならない。マーカー自体の仕様・投稿契約は本 Issue で変更しないため、Outbound pointer sync candidate check の対象外と判断した。
- **Tag/enum semantic extension consumer sweep 相当の確認**: `grep -rn "ac-tier: preview" skills/ modules/ scripts/` および `grep -rn "verify-type: manual" skills/ modules/ scripts/` で既存 consumer を確認し、`skills/audit/SKILL.md` (Manual Waiting Count) と `skills/auto/SKILL.md` (Pending manual confirmation) 以外に `ac-tier: preview` の無条件除外ロジックを持つ箇所がないことを確認した (`skills/verify/SKILL.md` は既に `resolve-preview-ac-fallback.sh` ベースで対応済み、`modules/verify-classifier.md` は分類基準のみで集計ロジックを持たない)。

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1371#issuecomment-5306555646
- saito / MEMBER / first-class / ⚠️ Triage AC audit: verify command に問題があります / https://github.com/saitoco/wholework/issues/1371#issuecomment-5306568916

Note: the bash safety net (`append-consumed-comments-section.sh`) recomputed cutoff to the `phase/spec` label assignment (set by this run's own Step 3, after the two comments above were fetched and consumed at Step 2 against the then-current `phase/issue` cutoff), so it saw zero comments after that later cutoff and wrote "No new comments since last phase." This entry replaces that placeholder with the comments actually consumed in-session; both were classified first-class (MEMBER) and acted on — see the Notes section entry on the `section_contains` heading-argument fix sourced from the second comment.

## Code Retrospective

### Deviations from Design
- N/A — implementation followed the Spec's Implementation Steps 1–5 exactly (per-line rule wording for `skills/audit/SKILL.md` N calculation and index enumeration, N1 bucket note, `allowed-tools` additions to both SKILL.md files, and the two new/extended bats test files).

### Design Gaps/Ambiguities
- The full `bats --jobs 18 tests/` run surfaced 1 unrelated pre-existing FAIL: `tests/code.bats` "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route", a stale assertion in a test file that asserts against `skills/code/SKILL.md` (untouched by this Issue — confirmed via `git diff 0158eaed HEAD -- skills/code/SKILL.md` showing no diff). Already tracked as Issue #1377; no duplicate filed. AC5 (`command "bats tests/*.bats"`) left unchecked in the Issue body for this reason, consistent with the pr-route Test FAIL handling policy (continue; CI detects it; report in completion message).
- Confirmed pre-implementation FAIL for 2 new tests in `tests/audit-manual-waiting-count.bats` (both `preview-ac-unverified`-matching asserts) and 1 new test in `tests/auto-completion-report.bats`, via `git show 0158eaed:<path>` + the same section-extraction awk against the pre-implementation content. The `audit-manual-waiting-count.bats` invariant-check test (`N1 + N2 + N3 + N4 = N`) intentionally PASSes against pre-implementation content too — it guards pre-existing text this change did not remove, not new content, so the pre-implementation-FAIL requirement does not apply to it.

### Rework
- N/A — no rework occurred; single implementation pass.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash-merged PR #1385 to `main` with no conflicts (`mergeable=true`, `reason=clean`, CI success, review approved) — no rebase or conflict resolution needed.
- Pre-merge AC gate confirmed all 5 Pre-merge acceptance conditions checked and no `review_incomplete_fallback` before proceeding — no override marker required.

### Deferred Items
- Issue #1377 (`tests/code.bats` stale assertion) remains open, confirmed unrelated to this PR's files — not addressed here, tracked separately.
- The `resolve-preview-ac-fallback.sh` fail-open recurring pattern (see review retrospective's "Recurring issues" below) remains undocumented at the script level — worth a follow-up Issue if a fourth consumer is added.

### Notes for Next Phase
- `/verify` should confirm post-merge state: Issue has no Post-merge AC section per the PR body, so `/verify` completes as a pass-through once the Issue reaches `phase/verify` and closes.

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — the `review-light` agent confirmed the prose changes in both `skills/audit/SKILL.md` and `skills/auto/SKILL.md` match the Spec's Implementation Steps 1–4 verbatim (per-line rule wording, N1 bucket note, `allowed-tools` insertion points, `modules/l0-surfaces.md` reference format), and the new/extended bats tests match Implementation Step 5's structural-test pattern exactly.

### Recurring issues

`resolve-preview-ac-fallback.sh` now has three consumers (`/verify` Step 5, and — as of this PR — `/audit` Manual Waiting Count and `/auto` Pending manual confirmation), but only `/verify` disambiguates a `gh` failure (fail-open: empty output, exit 0) from the legitimate "nothing unresolved" case, via `reconcile-phase-state.sh --check-completion`'s fail-closed handling. The two new consumers inherited the raw fail-open call without replicating that disambiguation — flagged as SHOULD findings in this review and fixed with a documentation note (not a fail-closed rewrite, to stay within this Issue's stated scope of fixing the unconditional-exclusion bug, not redesigning the fallback script's failure contract). If a fourth consumer is added later, this same gap will recur; worth considering a fail-closed default (or a distinct exit code for "gh failed" vs. "nothing unresolved") directly in `resolve-preview-ac-fallback.sh` itself so future consumers get the safe behavior for free instead of each having to remember to add it.

### Acceptance criteria verification difficulty

Nothing to note — all 5 Pre-merge conditions verified cleanly in Step 8 (4 rubric/section_contains conditions confirmed directly against the PR branch content; the 5th, `command "bats tests/*.bats"`, resolved via CI reference fallback against the `Run bats tests` job, SUCCESS on the latest commit with identity confirmed via run command containment). No UNCERTAIN results, no verify command syntax issues.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 特記事項なし。

#### design
- 特記事項なし。

#### code
- 特記事項なし。

#### review
- Recurring issues (review retrospective 記載): `resolve-preview-ac-fallback.sh` の消費先が 3 箇所 (`/verify`, `/audit`, `/auto`) に増えたが、`gh` 失敗時の fail-open (空出力 exit 0) を fail-closed に判別しているのは `/verify` のみ。今回はドキュメント注記のみで対応し、スクリプト自体の fail-closed 化はスコープ外とした。4番目の消費先が追加されれば同じギャップが再発する。

#### merge
- 特記事項なし。

#### verify
- Pre-merge AC 5件はすべて `/review` 時点で既に checked 済みのため SKIPPED (再検証なし)。Post-merge セクションなし、pass-through で完了。

### Improvement Proposals
- `resolve-preview-ac-fallback.sh` に fail-closed なデフォルト (または "gh 失敗" と "未解決なし" を区別する専用 exit code) を実装し、消費先スキルごとに個別実装させない設計へ変更することを検討 (根拠: review retrospective の Recurring issues。現時点では消費先 3 箇所・実害未確認のため Tier 2 相当と判断し、Issue 化は見送る)
