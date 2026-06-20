# Issue #701: auto: フェーズ遷移 tail に loop-state heartbeat を追記

## Overview

`/auto` の各フェーズ完了直後 (既存の `reconcile-phase-state.sh --check-completion` 呼び出しの直後) に、
`docs/reports/loop-state-{YYYY-MM-DD}.md` へ 1 行を追記するステップを追加する。
これにより、repo 全体のフェーズ状態スナップショットを durable な human-readable ファイルとして残す。

## Consumed Comments

- saitoco / MEMBER / first-class / Auto-Resolve Log (AC2 format definition → SKILL.md inline; AC1 file_contains → grep) / https://github.com/saitoco/wholework/issues/701#issuecomment-4757366919

## Changed Files

- `skills/auto/SKILL.md`: Add "Loop State Heartbeat" section defining the `loop-state-*.md` format (containing "Loop State" header) and heartbeat append procedure; add heartbeat step after each phase completion — bash 3.2+ compatible

## Implementation Steps

1. **Add `## Loop State Heartbeat` section to SKILL.md** (→ AC2)

   Place the section after the "Daily rollup" step in Step 5. Content:

   ```
   ## Loop State Heartbeat

   After each phase completion, append a line to `docs/reports/loop-state-{DATE}.md` (UTC date).

   ### Loop State File Format

   File: `docs/reports/loop-state-{DATE}.md`

   ---
   type: report
   description: Phase-transition heartbeat for /auto loops. Append-only.
   generated_by: skills/auto/SKILL.md (tail extension)
   ---

   # Loop State — {DATE}

   | ts (UTC) | issue | transition | repo phase/* snapshot |
   |----------|-------|------------|----------------------|
   | HH:MM:SS | #N | from→to | issue:N spec:N code:N review:N verify:N |

   ### Heartbeat Append Procedure

   After confirming `matches_expected: true` from `reconcile-phase-state.sh --check-completion`
   for the completed phase:

   1. Get timestamp: `date -u +%H:%M:%S`
   2. Get UTC date: `date -u +%Y-%m-%d`
   3. Get phase snapshot: count open issues per phase label via
      `gh issue list --label "phase/*" --json labels` — aggregate counts only
      (e.g., `issue:3 spec:1 code:0 review:2 verify:1`)
   4. If `docs/reports/loop-state-{DATE}.md` does not exist: create it with
      the frontmatter and table header using Write tool
   5. Append a row to the table (best-effort: failures must not block the main flow)
   ```

2. **Add heartbeat step after each PR route phase completion** (→ AC1, AC2)

   The PR route has 4 phase completions. After each `[N/M] phase → done` output:
   - After `[1/4] code → done` (step 3): append `from=spec, to=code`
   - After `[2/4] review → done` (step 7): append `from=code, to=review`
   - After `[3/4] merge → done` (step 10): append `from=review, to=merge`
   - After `[4/4] verify → done` (step 15-16 on success): append `from=merge, to=verify`

   Insertion position: immediately after the `[N/M] phase → done` output line,
   before the next precondition check or counter increment.

3. **Add heartbeat step after each patch route phase completion** (→ AC1, AC2)

   The patch route has 2 phase completions:
   - After code-patch completion (step 3): append `from=spec, to=code`
   - After verify completion (step 9): append `from=code, to=verify`

   Insertion position: immediately after the reconcile completion check confirms
   `matches_expected: true`.

## Verification

### Pre-merge

- <!-- verify: grep "loop-state" "skills/auto/SKILL.md" --> `/auto` SKILL.md にフェーズ遷移 tail での `loop-state-*.md` 追記ステップが記述されている
- <!-- verify: grep "Loop State" "skills/auto/SKILL.md" --> フォーマット定義 (セクションヘッダ `Loop State`) が SKILL.md に記述されている
- <!-- verify: grep "reconcile-phase-state.sh" "skills/auto/SKILL.md" --> snapshot 取得に既存 `reconcile-phase-state.sh` を利用している

### Post-merge

- `/auto N` を実走させ、`docs/reports/loop-state-{今日の UTC 日付}.md` に当該フェーズ遷移行が追記されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **reconcile-phase-state.sh シグネチャ齟齬**: Issue body では `reconcile-phase-state.sh --check-completion --phase <next>` と記述されているが、実際のシグネチャは positional `<phase> <issue_number> [options]`。heartbeat は既存の completion check 呼び出しの直後に追加するため、呼び出し変更は不要。コンテキストから `from→to` を導出する。
- **Auto-Resolved ambiguity (SKILL.md インライン定義)**: フォーマット定義は `loop-state-template.md` 等の別ファイルは作成せず、SKILL.md 内インラインに記述する (Wholework 既存パターン準拠)。
- **Best-effort**: heartbeat append の失敗はメイン実行フローをブロックしてはならない。
- **snapshot 取得**: `gh issue list --label "phase/*" --json labels` で open issues の phase別集計値のみ取得。reconcile-phase-state.sh は phase 完了確認のトリガーとして使用 (再呼び出し不要)。
- **docs/reports/**: 既存ディレクトリ。`loop-state-*.md` は新規ファイルタイプだが、ディレクトリ新設ではないため structure.md 更新不要 (単一ファイル出力につき除外ルール適用)。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None. Implementation followed all 3 steps in the Spec exactly: `## Loop State Heartbeat` section added after Daily rollup, heartbeat steps added to all PR route phase completions (steps 3, 7, 10, 16) and patch route phase completions (steps 3, 9).

### Design Gaps/Ambiguities

- The inline heartbeat references in the phase steps use "see `## Loop State Heartbeat`" which points to the new section. This is a forward reference within the same file — readable but not automatically validatable by grep-based verify commands. Acceptable given the best-effort nature of the feature.

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added `## Loop State Heartbeat` as a top-level `##` section in SKILL.md, placed between Daily rollup and L3 auto-retrospective in Step 5. This makes it a standalone reference section rather than embedding it inline within a step.
- Heartbeat references in individual phase steps use a compact inline notation (`append loop-state heartbeat; see ## Loop State Heartbeat`) to avoid repeating the full procedure at every call site.
- All 6 phase completions (4 PR route + 2 patch route) are covered with distinct `from→to` transition labels.

### Deferred Items
- Actual runtime behavior (file creation, row append, snapshot aggregation) is verified post-merge via observation event `auto-run`. The verify commands only confirm SKILL.md text presence.
- The `gh issue list` snapshot aggregation jq logic is left as a prose description in the Heartbeat Append Procedure — a future Issue could implement a helper script if needed.

### Notes for Next Phase
- All 3 pre-merge ACs pass: `grep "loop-state"`, `grep "Loop State"`, `grep "reconcile-phase-state.sh"` all PASS.
- Post-merge AC requires running `/auto N` and observing the `docs/reports/loop-state-{DATE}.md` file. This is tagged `verify-type: observation event=auto-run`.
- The pre-existing forbidden-expressions violation in `docs/spec/issue-710-blocked-by-workflow.md` (旧称: verify hint) is unrelated to this change — no action needed from `/verify`.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec の AC 設計は `grep` 主体で minimal、verify 段階で UNCERTAIN/FAIL ゼロを達成。AC1/AC2 の Auto-Resolved Ambiguity Points で `file_contains` → `grep` の変更判断、テンプレートファイル不作成方針が verify 精度に直結した。

#### code
- 3 ステップ実装、deviations なし、rework なし。code retrospective の `forward reference` 観察 (Loop State Heartbeat section への "see" 参照) は grep ベース verify の限界として記録済み。

#### merge
- patch route のため PR なし、直 main コミット。conflicts なし。

#### verify
- pre-merge 3 件すべて PASS (各 grep が複数マッチ)。post-merge AC4 (observation event=auto-run) は本 /auto 終了時に event 発火予定で SKIPPED として記録。
- 注: `/verify` 開始時に check-verify-dirty.sh が exit=1 を返した (前 batch の auto-events-rollup-2026-06-20.md が untracked のまま)。verify 前に commit して回避。auto-events-rollup.sh が生成ファイルを自動 commit しない既存挙動が verify 起動を妨げる潜在パターン。

### Improvement Proposals

- **auto-events-rollup.sh の生成物コミット自動化**: `auto-events-rollup.sh` が `docs/reports/auto-events-rollup-{DATE}.md` を生成するが commit/push しないため、次回 `/verify` 起動時に check-verify-dirty.sh が exit=1 でブロックされる。複数の skill (`auto`, `verify`) と複数 PR にまたがる潜在的再発性。auto-events-rollup.sh または呼び出し側 (auto/SKILL.md Step 5) で自動コミットするか、`docs/reports/auto-events-rollup-*.md` を verify dirty チェックの除外パターンに加えるかを検討する価値あり。Tier 2 候補 (パターン認識ベースの workflow lesson)。

