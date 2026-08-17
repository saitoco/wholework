# Issue #1386: resolve-preview-ac-fallback: gh 失敗時の fail-open を fail-closed 化し3消費先で共通化

## Overview

`scripts/resolve-preview-ac-fallback.sh` は `/verify`・`/audit`・`/auto` の3消費先から呼ばれるが、`gh` コマンド失敗時に fail-open (空出力、exit 0) を返すため、「preview AC 未解決なしの正常系」と区別がつかない。`/verify` は `reconcile-phase-state.sh --check-completion` を組み合わせて別途 disambiguate しているが、`/audit`・`/auto` は同種の対応をしていない。

本 Issue はスクリプト自体に `gh` 失敗を区別可能な専用シグナル (`scripts/verify-executability-marker.sh` が既に採用している exit code 2 / `N0` 相当パターン) を実装し、標準出力フォーマットは変更しない。あわせて `skills/audit/SKILL.md` Manual Waiting Count、`skills/auto/SKILL.md` Batch Completion Report の2消費先を、新シグナル参照で `gh` 失敗時は undetermined として扱うよう更新する。`skills/verify/SKILL.md` Step 5 は既に fail-closed のため対象外。

## Reproduction Steps

1. `gh` コマンドが失敗する状況を用意する (認証切れ・レート制限・ネットワーク断など)
2. `scripts/resolve-preview-ac-fallback.sh <issue-number>` を実行する
3. 空出力・exit 0 が返り、「preview AC 未解決なし (正常系)」の場合の出力と区別できないことを確認する
4. この状態で `/audit` Manual Waiting Count、`/auto --batch` Pending manual confirmation を実行すると、`gh` 失敗ケースが「未解決なし」として扱われ、実際には未確認の preview-tier AC が集計から漏れる

## Root Cause

`scripts/resolve-preview-ac-fallback.sh` の `gh issue view` 呼び出し (25-27行目) が `2>/dev/null || true` で失敗を握りつぶし、「marker 不在」と「gh 失敗」を同じ空出力・exit 0 に collapse させている。3消費先のうち `/verify` Step 5 のみ `reconcile-phase-state.sh --check-completion` で別途 disambiguate しているが (`skills/verify/SKILL.md` 208-210行目)、`/audit` Manual Waiting Count と `/auto` Pending manual confirmation はこの区別を実装しておらず、スクリプト単体の fail-open 設計がそのまま両消費先の誤判定リスクに直結している。同種の `gh` 失敗検出は `scripts/verify-executability-marker.sh` の `cmd_resolve()` (149-155行目) で既に exit code 2 として実装済みであり、本 Issue はこの既存パターンを `resolve-preview-ac-fallback.sh` にも適用し、2消費先を追従させる。

## Changed Files

- `scripts/resolve-preview-ac-fallback.sh`: `gh issue view` 失敗時のハンドリングを `2>/dev/null || true` (fail-open, exit 0) から、`verify-executability-marker.sh` の `cmd_resolve()` と同じ `if ! latest_marker_body="$(...)"; then echo "Error: ..." >&2; exit 2; fi` パターンに変更。標準出力フォーマット (カンマ区切り 1-based インデックス、または空) は変更しない。冒頭コメント (8-9行目) の exit code 説明も更新する。bash 3.2+ 互換を維持。
- `tests/resolve-preview-ac-fallback.bats`: 既存の `"gh failure: fails open with empty output, exit 0"` テスト (78-88行目) を `tests/verify-executability-marker.bats` の `"resolve: gh failure exits 2, distinct from no-marker"` (149-158行目) と同じ形に書き換え、`[ "$status" -eq 2 ]` を検証するテストケースに更新する (新規分岐ロジックのカバレッジ)。
- `skills/audit/SKILL.md`: § Manual Waiting Count (363-365行目付近) を更新。`resolve-preview-ac-fallback.sh <issue>` 呼び出し後にその終了コードを確認する記述を追加し、exit code 2 の場合はこの Issue を `N0` (undetermined) バケットに fold して ac-tier:preview 行の包含判定を行わないようにする。末尾の "not disambiguated the way `N0`/exit-2 is for `verify-executability-marker.sh` below" という注記を、新しい挙動を説明する文言 (`exit code 2` という語句を含める — 対応する bats アサーションの一致対象) に置き換える。
- `tests/audit-manual-waiting-count.bats`: 新規 `@test` を追加し、Manual Waiting Count セクションに `"exit code 2"` という語句が含まれることを検証する (新規分岐ロジックのカバレッジ)。
- `skills/auto/SKILL.md`: § Batch Completion Report → Pending manual confirmation (1262-1282行目付近) を更新。`resolve-preview-ac-fallback.sh $NUMBER` 呼び出し後にその終了コードを確認する記述を追加し、exit code 2 の場合は当該 Issue を `TOTAL_MANUAL` から除外し、別途 undetermined カウント/リストとして集計・出力する (既存のフラットカウント構造は維持)。末尾の "a known best-effort limitation of this scan." という注記を、新しい挙動を説明する文言 (`exit code 2` という語句を含める) に置き換える。
- `tests/auto-completion-report.bats`: 新規 `@test` を追加し、Batch Completion Report セクションに `"exit code 2"` という語句が含まれることを検証する (新規分岐ロジックのカバレッジ)。

## Implementation Steps

1. `scripts/resolve-preview-ac-fallback.sh` の `gh issue view` 失敗時ハンドリングを fail-open (exit 0) から exit code 2 に変更し、冒頭コメントを更新する (→ 受入条件1)
2. `tests/resolve-preview-ac-fallback.bats` の gh 失敗テストケースを exit code 2 を検証する形に書き換える (after 1) (→ 受入条件2, 受入条件3)
3. `skills/audit/SKILL.md` § Manual Waiting Count を更新し (exit code 2 → N0 へ fold、注記文言更新)、`tests/audit-manual-waiting-count.bats` に新規テストケースを追加する (after 1) (→ 受入条件4, 受入条件5)
4. `skills/auto/SKILL.md` § Batch Completion Report → Pending manual confirmation を更新し (exit code 2 → undetermined カウント、注記文言更新)、`tests/auto-completion-report.bats` に新規テストケースを追加する (after 1) (→ 受入条件6, 受入条件7)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/resolve-preview-ac-fallback.sh が、gh コマンド失敗時と preview AC 未解決なしのケースを (専用の exit code 等で) 区別可能になっている。既存の scripts/verify-executability-marker.sh の gh 失敗判定 (exit code 2 / N0 相当) と整合する設計であることが望ましい。標準出力のフォーマット (カンマ区切りの1-basedインデックス、または空) は変更されていない" --> gh 失敗と未解決なしのケースが区別可能になっている (標準出力フォーマットは維持)
- <!-- verify: command "bats tests/resolve-preview-ac-fallback.bats" --> 既存の bats テストが green (回帰保護)
- <!-- verify: rubric "tests/resolve-preview-ac-fallback.bats に、gh コマンド失敗時 (専用シグナル) と marker 不在/ac=none による通常の空出力を区別する新規テストケースが追加されている" --> gh 失敗時と未解決なしを区別する新規テストケースが追加されている
- <!-- verify: rubric "skills/audit/SKILL.md の Manual Waiting Count セクションが、resolve-preview-ac-fallback.sh 自体の gh 失敗を「未解決なし」として扱う既存の best-effort 制限を解消し、専用の判別シグナルを参照して gh 失敗時は undetermined として扱う (verify-executability-marker.sh の N0 相当の既存パターンと整合する) 記述に更新されている" --> Manual Waiting Count が resolve-preview-ac-fallback.sh の gh 失敗を undetermined として扱う
- <!-- verify: section_not_contains "skills/audit/SKILL.md" "Manual Waiting Count" "not disambiguated the way" --> Manual Waiting Count セクションの古い「未対応」注記が更新されている
- <!-- verify: rubric "skills/auto/SKILL.md の Batch Completion Report → Pending manual confirmation セクションが、resolve-preview-ac-fallback.sh 自体の gh 失敗を「未解決なし」として扱う既存の best-effort 制限を解消し、専用の判別シグナルを参照して gh 失敗時は undetermined として扱う記述に更新されている (既存のフラットカウント構造は維持してよい)" --> Pending manual confirmation が resolve-preview-ac-fallback.sh の gh 失敗を undetermined として扱う
- <!-- verify: section_not_contains "skills/auto/SKILL.md" "Batch Completion Report" "a known best-effort limitation of this scan." --> Pending manual confirmation セクションの古い「未対応」注記が更新されている

### Post-merge

なし

## Notes

- **#1053 の先例との整合**: `docs/spec/issue-1053-preview-ac-failopen-guard.md` は「`resolve-preview-ac-fallback.sh` の標準出力インタフェース (1-based index のカンマ区切り、または空) を変更するとリスクがある」との理由でスクリプト自体を変更しない設計を選んだ。本 Issue は標準出力フォーマットを一切変更せず exit code のみを追加するため、#1053 の懸念とは抵触しない。
- **fail-safe critical script の edge case**: `scripts/resolve-preview-ac-fallback.sh` は `fail_open` 相当のパターン (`2>/dev/null || true`) を持つ fail-safe critical スクリプトと判断した。引数の空/非数値チェック (exit 1) は本 Issue で変更しない。依存コマンド (`gh issue view`) 失敗時の挙動を fail-open (exit 0, 区別不能) から「exit code 2 で失敗を明示するが標準出力は空のまま」という設計に変更する — 標準出力自体を fail-closed 化 (全 index を未解決とみなす出力) しないのは、スクリプト単体では `ac-tier: preview` の全 index 集合を把握できず技術的に実現不能なため (Issue Retrospective の Auto-Resolve Log で確認済み)。
- **新規テストケースの要約** (SPEC_DEPTH=light のため Spec Retrospective ではなくここに記録): (a) `tests/resolve-preview-ac-fallback.bats` — gh 失敗時に exit code 2 を返すことを検証するケースへの書き換え、(b) `tests/audit-manual-waiting-count.bats` — Manual Waiting Count セクションに `"exit code 2"` の記述が追加されたことを検証する新規ケース、(c) `tests/auto-completion-report.bats` — Batch Completion Report セクションに `"exit code 2"` の記述が追加されたことを検証する新規ケース。
- **Steering Docs sync candidate 確認済み・変更不要**: `resolve-preview-ac-fallback.sh` の grep 横断検索で見つかった以下は、いずれも exit code や fail-open 挙動を主張していないため変更不要と判断した — `docs/structure.md`/`docs/ja/structure.md` (標準出力の説明のみ)、`modules/l0-surfaces.md` (marker 解決目的の説明のみ)、`tests/verify.bats` (`skills/verify/SKILL.md` Step 5 内の文字列存在チェックのみ)。
- **Simplicity rule 超過について**: Pre-merge Verification が7件で light spec のガイドライン (5件) を超過している。Issue 本文の Acceptance Criteria は Comment Consumption で拾った Triage AC audit コメント (常時 UNCERTAIN な heading 引数バグ2件、常時 PASS な bats AC 1件の分割) を反映して7件に修正済みであり、Verify command sync rule により Spec 側もこれを逐語コピーする必要があるため、Implementation Steps 側 (4件) をグループ化することで対応した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 「`/issue` Existing Issue Refinement の Issue Retrospective — Auto-Resolve Log (専用 exit code 方式の採用理由、AC 範囲を script から audit/auto の SKILL.md 更新まで拡大した理由、Size S→M 変更の記録)」/ https://github.com/saitoco/wholework/issues/1386#issuecomment-5311390587
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 「Triage AC audit — Pre-merge AC 3件の verify command 不備を指摘 (`section_not_contains` の heading 引数に `#### `/`### ` を含めて常時 UNCERTAIN になるバグ2件、bats AC が新規カバレッジを主張せず常時 PASS になりうる問題1件)。本 Spec 作成時に Issue 本文へ反映済み」/ https://github.com/saitoco/wholework/issues/1386#issuecomment-5311413741

## Code Retrospective

### Deviations from Design
- N/A — implementation followed the Spec's Implementation Steps 1–4 exactly (`resolve-preview-ac-fallback.sh` exit-code-2 pattern mirrored from `verify-executability-marker.sh`'s `cmd_resolve()`, the two SKILL.md consumer updates, and the corresponding bats test changes).

### Design Gaps/Ambiguities
- N/A — no ambiguities encountered; the existing `cmd_resolve()` pattern and the Spec's per-file guidance were sufficient to implement all 4 steps without further interpretation.

### Rework
- N/A — no rework occurred; single implementation pass. Confirmed pre-implementation FAIL (via `git stash` on the two SKILL.md files) for both new `tests/audit-manual-waiting-count.bats` and `tests/auto-completion-report.bats` assertions before committing. Behavioral change detection (both SKILL.md files are referenced by multiple test files beyond a single direct counterpart) triggered a full `bats --jobs 18 tests/` run — 1828/1828 green, no pre-existing unrelated failures encountered this time (unlike the #1377 stale assertion noted in Issue #1371's retrospective, already fixed by then).

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Merged PR #1392 via clean squash merge — `gh-pr-merge-status.sh` reported `mergeable=true reason=clean ci_status=success review_status=approved`, so Step 2 (Worktree Entry) and Step 3 (Resolve Conflicts) were both skipped per the skill's `mergeable=true` branch.
- Pre-merge AC gate (`check-pre-merge-ac.sh 1386`) confirmed all 7 pre-merge Acceptance Criteria already checked (`unchecked_count=0`); review-incomplete-fallback check (`reconcile-phase-state.sh review 1386 --pr 1392 --check-completion`) found an organic Step 14 review completion (not fallback-origin), so no override marker was needed.

### Deferred Items
- Carried forward unchanged from the review phase: `skills/verify/SKILL.md` Step 5's disambiguation logic and full 3-consumer signal consolidation remain out of scope/future cleanup — not addressed in merge.

### Notes for Next Phase
- `/verify 1386` should find nothing outstanding beyond the standard post-merge verification pass (Post-merge Verification section is empty — "なし").
- Issue #1386 auto-closes on this merge (`closes #1386`, base branch is `main`); Step 6 (Verify Issue State fallback) should confirm `state=CLOSED` and `phase/verify` label are both applied.

## review retrospective

### Spec vs. implementation divergence patterns
No divergence found. All 7 Pre-merge AC verified PASS on first pass (1 rubric + 1 CI-backed `command` + 5 further rubric/section checks), no verify command inaccuracies or UNCERTAIN results.

### Recurring issues
Both SHOULD findings from this review share a root cause: when a shared script's failure-signaling contract changes (here, `resolve-preview-ac-fallback.sh` moving from fail-open to exit-code-2 on `gh` failure), documentation that describes or extends the *consuming* side of that contract needs a second consistency pass beyond the Issue's explicit AC list:
- `skills/audit/SKILL.md`'s Manual Waiting Count section extended an existing `N0` "undetermined" bucket (previously sourced only from `verify-executability-marker.sh` failures) with a second source (`resolve-preview-ac-fallback.sh` failures) without re-verifying that the bucket's stated invariant (`N0 ⊆ N`) still held for the new source — an easy trap when reusing an existing enumeration/bucket name for a second, structurally different signal.
- `skills/verify/SKILL.md` Step 5 (out of scope per the Issue body, since it was already fail-closed via a separate mechanism) still contained prose asserting the *pre-PR* fail-open behavior of `resolve-preview-ac-fallback.sh` as the reason that mechanism was needed. "Out of scope for behavior change" does not imply "out of scope for a documentation accuracy sweep" — a future Issue that changes a script's documented contract should grep the whole tree for prose describing that script's old behavior, not just the Issue's explicit consumer list.

### Acceptance criteria verification difficulty
None. All 7 AC (1 rubric, 1 `command` backed by a green CI job, 3 further rubric checks, 2 `section_not_contains` checks confirming stale text removal) were unambiguous and required no AI judgment calls beyond straightforward rubric evaluation.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- No ambiguities. Comment Consumption picked up a Triage AC audit finding (2 heading-argument bugs + 1 always-PASS bats AC) and reflected it into the Issue body before design started, so the Spec's Pre-merge Verification list was already sound at write time.

#### design
- No deviations. Implementation followed the 4 Implementation Steps exactly.

#### code
- No rework. Single implementation pass; pre-implementation FAIL was confirmed for both new bats assertions before committing (regression-detection discipline).

#### review
- Review found 0 MUST issues but 2 SHOULD findings sharing one root cause: when a shared script's failure-signaling contract changes, documentation describing the *consuming* side of that contract needs its own consistency sweep beyond the Issue's explicit AC list — both `skills/audit/SKILL.md`'s reused `N0` bucket invariant and `skills/verify/SKILL.md` Step 5's stale pre-PR-behavior prose were near-misses this Issue's own scope did not originally cover.

#### merge
- Clean squash merge; no conflicts, no CI failures.

#### verify
- No FAIL/UNCERTAIN. All 7 pre-merge AC were already checked at merge time (verified during `/review`), so this run's own auto-verification pass was a SKIPPED (already-checked) confirmation only.

### Improvement Proposals
- When a shared script's documented failure-signaling contract changes (e.g. fail-open → exit-code-2), grep the whole tree for prose describing the script's *old* behavior — not just the Issue's explicit named consumers — before considering the documentation sweep complete. This Issue's own review caught 2 such near-misses only through manual re-reading, not a systematic sweep. (Source: `## review retrospective` § Recurring issues, this Spec.)
