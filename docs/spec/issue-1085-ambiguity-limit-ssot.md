# Spec: あいまいさ抽出の上限件数の SSoT を ambiguity-detector に一本化 (#1085)

No Spec existed prior to `/code` (Issue already had `phase/ready` when this run started; Size=XS). Requirements were read directly from the Issue body, including its `## 対応方針 (案)` section.

## Implementation Steps

1. `skills/spec/SKILL.md` Step 7 (Ambiguity Resolution) の固定上限記述「extract **at most 3** ambiguity points」を、`modules/ambiguity-detector.md` の Size Routing Table (Detection Limit) を参照する記述に置き換えた。Step 2 で取得済みの Size を根拠に判定する旨も明記した。

## Code Retrospective

### Deviations from Design
- N/A — Issue 本文の「対応方針 (案)」に記載された修正方針 (Size Routing Table を参照する記述への置換) をそのまま適用した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/issue/SKILL.md:506` (Existing Issue Refinement Step 6) の既存参照形式 ("XS/S/M or unset → **at most 3**; L/XL → **at most 5**") にならい、`skills/spec/SKILL.md:226` も同じ表現スタイルで Size Routing Table を参照する形に統一した。
- `skills/issue/SKILL.md:51` (New Issue Creation Step 5) の「extract **at most 3** ambiguity points」はそのまま残した — 新規 Issue 作成フローでは Size が定義上 unset であり、Size Routing Table の Unset 行 (Max 3) と矛盾しないため、今回の食い違い修正の対象外と判断した。

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC1-4 (rubric 2件 + section_contains 1件 + command 1件) は `/code` 内で検証し全て PASS、Issue 本文のチェックボックスも更新済み。
- Behavioral Change Detection により `bats --jobs 18 tests/` (フルスイート) を実行し、1786 件全て PASS を確認済み。
- Post-merge AC (`verify-type: manual` — Size L の Issue を `/spec` に通し、あいまいさ抽出が最大 5 件の上限で動作することを確認する) は未実施のまま残している。

## Consumed Comments

No new comments since last phase.
