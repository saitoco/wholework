# Issue #429: spec: verify コマンドが Issue body と一致しているかのチェックを /spec に追加

## Overview

`/spec` Step 10 の "Verification conditions vs. Issue body acceptance criteria consistency check" ステップが現在 Spec を SSoT として Issue body を更新する方向になっている。Issue body が SSoT であるべき既存方針と矛盾するため、SSoT 方向を逆転させ Issue body を SSoT として Spec 側を更新する方向に修正する。あわせて `modules/verify-patterns.md` に Issue body SSoT 原則の新セクションを追加する。

## Consumed Comments

- saito (MEMBER / first-class) [2026-06-28T03:02:05Z] — Issue Retrospective: 既存チェック (SKILL.md line ~491-497) の SSoT 方向が逆 (`auto-update Issue body`) であることを確認。`file_not_contains "use Spec's"` で旧記述の除去を検証。

## Changed Files

- `skills/spec/SKILL.md`: "Verification conditions vs. Issue body acceptance criteria consistency check" の line 497 を変更 — 「Spec を SSoT として Issue body を更新」→「Issue body を SSoT として Spec の verify コマンドを更新」 — bash 3.2+ 互換 (シェルスクリプト操作なし; LLM が Edit ツールで実行)
- `modules/verify-patterns.md`: §17 "Issue Body Is SSoT for Verify Commands — Align Spec on Mismatch" セクションを `## Output` の直前に追加

## Implementation Steps

1. `skills/spec/SKILL.md` の "Verification conditions vs. Issue body acceptance criteria consistency check" ステップの最後の bullet を変更 (→ AC1, AC2):
   - 変更前: `- If mismatched, auto-update Issue body (use Spec's \`## Verification > Pre-merge\` as source of truth): \`mkdir -p .tmp\`, write to \`.tmp/issue-body-$NUMBER.md\`, update with \`gh-issue-edit.sh\`, delete temp file`
   - 変更後: `- If mismatched, auto-update Spec (use Issue body's \`## Acceptance Criteria > Pre-merge\` as source of truth): for each mismatched item, replace the Spec's \`<!-- verify: ... -->\` hint with the corresponding hint from the Issue body using the Edit tool`

2. `modules/verify-patterns.md` の `## Output` セクションの直前に §17 を追加 (→ AC3, AC4):
   ```
   ### 17. Issue Body Is SSoT for Verify Commands — Align Spec on Mismatch

   When verify commands in the Spec's `## Verification > Pre-merge` section diverge from the Issue body's `## Acceptance Criteria > Pre-merge` section, the Issue body is the SSoT (single source of truth). Update the Spec to match the Issue body — never the reverse.

   **Typical divergence patterns:**
   - LLM rewrites a verify command when copying from Issue body to Spec (e.g., `sync` → `check`, `build` → `build:prod`)
   - Issue body is updated after the Spec verify section was initially written

   **Resolution:**
   - Detect mismatch between Issue body `## Acceptance Criteria > Pre-merge` verify commands and Spec `## Verification > Pre-merge` verify commands
   - For each diverged item, replace the Spec's `<!-- verify: ... -->` hint with the Issue body's version verbatim
   - Do not update the Issue body from the Spec

   This SSoT principle is implemented in `/spec` SKILL.md's "Verification conditions vs. Issue body acceptance criteria consistency check" step.
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の verify コマンド整合性チェックが、Issue body を SSoT として Spec 側のコマンドを Issue body に揃える方向で記述されている" --> `skills/spec/SKILL.md` に Issue body を SSoT とした verify コマンド一致チェックステップが存在する
- <!-- verify: file_not_contains "skills/spec/SKILL.md" "use Spec's" --> 旧来の「Spec を SSoT として Issue body を更新する」記述が削除されている
- <!-- verify: rubric "modules/verify-patterns.md に、Spec の verify コマンドは Issue body を SSoT として一致させるという原則が新たなセクションとして追加されている" --> `modules/verify-patterns.md` に Issue body を SSoT とする verify コマンド整合性原則が記載されている
- <!-- verify: grep "SSoT" "modules/verify-patterns.md" --> `modules/verify-patterns.md` の新セクションに SSoT の語が含まれている

### Post-merge

なし

## Notes

- 既存の「Verify command sync rule」(SKILL.md line 471-473) は既に Issue body → Spec 方向で正しい。「consistency check」(line 491-497) のみが逆方向になっていた
- AC2 の `file_not_contains "skills/spec/SKILL.md" "use Spec's"` は、Step 1 で変更後に "use Spec's" が SKILL.md から除去されることで PASS する
- AC4 の `grep "SSoT" "modules/verify-patterns.md"` は現在 FAIL (SSoT の語が存在しない)。Step 2 で新セクション追加後に PASS する
- Issue body の更新は不要 (変更方向を逆転させるだけであり、Issue body の verify コマンドは既に正しい)

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None. Implementation followed the Spec exactly. Step 1 (SKILL.md edit) and Step 2 (verify-patterns.md §17 addition) both matched the specified text.

### Design Gaps/Ambiguities

- None identified. The Spec Notes correctly anticipated that the existing "Verify command sync rule" (SKILL.md line 471-473) was already in the correct direction, so only the "consistency check" bullet required the SSoT direction reversal.

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Changed only one bullet in the consistency check step (line 497), not the surrounding context — the surrounding detection logic was correct and only the action ("update Issue body" → "update Spec") needed reversing.
- Added §17 to `modules/verify-patterns.md` verbatim from the Spec to keep language precise.

### Deferred Items
- None. Scope was narrow (1 SKILL.md bullet + 1 module section); completed in full.

### Notes for Next Phase
- All 4 pre-merge ACs verified PASS (rubric AC1/AC3 by grader judgment, AC2/AC4 by tool checks).
- bats tests passed (exit code 0, 1005 tests).
- No forbidden expression violations found.
- Post-merge: none.
