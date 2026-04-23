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

## review retrospective

### Spec vs. implementation divergence patterns

`modules/title-normalizer.md` の `## Output` セクションは「呼び出し元が `gh issue edit` を実行する」設計を前提としているが、新設した「Title Drift Check」サブセクションはモジュール内部で直接 `gh issue edit` を実行する。この2パターンが同一モジュール内に混在し、モジュールの責任境界が不明瞭になっている（SHOULD）。将来 Output セクションを2パートに分割して責任境界を明記することで改善できる。

### Recurring issues

今回の変更規模（SKILL.md のステップ挿入とリナンバリング）としてはレビューイシューが最小限に抑えられており、繰り返しパターンは特になし。

### Acceptance criteria verification difficulty

Pre-merge 条件3件はすべて `section_contains` / `grep` ヒントが整備されており PASS 判定が容易だった。Post-merge 条件はいずれも `verify-type: opportunistic` で適切にマークされており、UNCERTAIN 対応が不要だった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は簡潔かつ正確。Issue body の「Auto-Resolved Ambiguity Points」で曖昧さが事前解消されており、Spec 作成時の不確実性が最小化されていた。
- 受入条件の verify command（`section_contains`、`grep`）が実装変更内容と正確に対応しており、自動検証が容易だった。

#### design
- 実装と設計の乖離なし。3ファイル（title-normalizer.md、issue/SKILL.md、spec/SKILL.md）への変更がすべて計画通り実施された。

#### code
- リワークなし。fixup/amend パターンも検出されなかった。実装は設計から逸脱なく完了した。

#### review
- PR #91 レビューで SHOULD:1、CONSIDER:1 のコメントが検出された（MUST:0）。
- SHOULD 指摘: `modules/title-normalizer.md` の `## Output` セクション（呼び出し元が `gh issue edit` を実行する設計前提）と Title Drift Check サブセクション（モジュール内部で直接実行）が混在し責任境界が不明瞭。今後の改善候補として Spec に記録済み。
- レビューは MUST 問題を発見せず、マージ判断は適切だった。

#### merge
- クリーンなマージ。コンフリクトなし。CI（bats tests + skill syntax validation）が全ジョブ SUCCESS。

#### verify
- Pre-merge 条件3件すべて PASS。verify commandが整備されており検証が確実かつ迅速に完了した。
- Post-merge 条件2件は `verify-type: opportunistic` で適切にマーキングされており、自動検証対象外として正しく扱われた。

### Improvement Proposals
- `modules/title-normalizer.md` の `## Output` セクションと `Title Drift Check` サブセクションの責任境界の不明瞭さを解消する: Output セクションを「呼び出し元が実行するケース」と「モジュール内部で実行するケース」の2パートに分割し、それぞれの責任範囲を明記する（review retrospective に記録済みの SHOULD 項目）。
