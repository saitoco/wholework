# Issue #88: issue/spec: スコープ変更時の Issue title 自動更新

## Overview

`/issue`（既存 Issue 精査）で body が大幅に更新された後、または `/spec` で Spec を作成した後に、Issue body と title の意味的乖離（drift）を LLM が検出し、乖離があれば `title-normalizer.md` の規則に従って title を自動更新する機能を追加する。#55 で `/issue` 実行後にスコープが拡大したが title がそのままだった事例が動機。

## Changed Files

- `modules/title-normalizer.md`: 「Title Drift Check」サブセクションを Processing Steps に追加
- `skills/issue/SKILL.md`: Existing Issue Refinement フロー Step 8（body 更新）の後に title drift check ステップを追加
- `skills/spec/SKILL.md`: Step 10（Spec 作成）の後、Step 11（Commit Spec）の前に title drift check ステップを追加

## Implementation Steps

1. `modules/title-normalizer.md` の Processing Steps セクションに「### Title Drift Check」サブセクションを追加する（→ 受入条件 A）
   - Input: Issue title（現在の title）、Issue body（更新後の body）
   - Processing: LLM が title と body の意味的乖離を判定する。body のスコープ・目的・対象が title と大きく異なる場合を drift と判定する
   - drift 検出時: 既存の naming convention（`component: concise description`）に従って title を再生成し、`gh issue edit "$NUMBER" --title "$new_title"` で更新。更新前後の title をスキル出力に表示する
   - drift なし: 何もしない（出力もなし）

2. `skills/issue/SKILL.md` の Existing Issue Refinement セクションに title drift check ステップを追加する（→ 受入条件 B）
   - Step 8（Update Issue Body）の後、Step 9（Set Blocked-by Dependencies）の前に新ステップを挿入
   - 内容: `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` の「Title Drift Check」セクションを Read して follow する
   - 既存の Step 9〜12 を Step 10〜13 にリナンバリング

3. `skills/spec/SKILL.md` に title drift check ステップを追加する（→ 受入条件 C）
   - Step 10（Create Spec）の後、Step 11（Commit Spec）の前に新ステップを挿入
   - 内容: `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` の「Title Drift Check」セクションを Read して follow する。drift 検出ソースは Issue body のみ（Spec の技術情報は含めない — `/issue` (What) vs `/spec` (How) の境界に従う）
   - 既存の Step 11〜18 を Step 12〜19 にリナンバリング

4. ステップリナンバリングに伴い、両 SKILL.md 内のステップ相互参照（"Step N"、"after N" 等）を更新する（→ 受入条件 B, C）

## Verification

### Pre-merge
- <!-- verify: section_contains "modules/title-normalizer.md" "## Processing Steps" "Drift Check" --> `modules/title-normalizer.md` に「Title Drift Check」手順が追加されている
- <!-- verify: grep "title.*drift\|drift.*check\|Title Drift" "skills/issue/SKILL.md" --> `/issue` SKILL.md の Existing Issue Refinement フローに title drift check ステップが追加されている
- <!-- verify: grep "title.*drift\|drift.*check\|Title Drift" "skills/spec/SKILL.md" --> `/spec` SKILL.md に title drift check ステップが追加されている

### Post-merge
- `/issue N` の精査実行で body のスコープが大きく変わった場合、title が自動更新されスキル出力に更新前後が表示される <!-- verify-type: opportunistic -->
- `/spec N` の Spec 作成後にスコープ変更が検出された場合、title が自動更新されスキル出力に更新前後が表示される <!-- verify-type: opportunistic -->

## Notes

- Auto-Resolved Ambiguity Points（Issue body に記載済み）:
  - Drift 検出ロジックは `title-normalizer.md` に「Title Drift Check」サブセクションとして追加（shared module pattern に従う）
  - `/spec` での drift 検出ソースは Issue body のみ（`docs/product.md` の `/issue` (What) vs `/spec` (How) 境界に沿う）
  - drift 検出後の再生成は既存の naming convention をそのまま適用
- `docs/structure.md` のモジュール一覧の description は "issue title normalization" のままで更新不要（drift check は normalization の拡張であり範囲内）

## Spec Retrospective

### Minor observations
- Nothing to note

### Judgment rationale
- Nothing to note

### Uncertainty resolution
- Nothing to note

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
