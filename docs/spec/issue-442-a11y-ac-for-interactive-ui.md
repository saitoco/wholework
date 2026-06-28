# Issue #442: spec: インタラクティブ UI コンポーネントの a11y AC をデフォルトで含めるガイドライン整備

## Overview

インタラクティブな UI コンポーネント (toggle / menu / accordion / dialog 等) を含む Issue で Spec を作成する際、`aria-*` 属性の動的更新を **デフォルトで Acceptance Criteria に含める** ガイドラインを整備する。

実観測の背景: ハンバーガーメニューのトグルボタン実装で `aria-expanded` の動的切替が AC から抜け落ち、verify retrospective で発見された。スクリーンリーダー向けの状態通知 (a11y) が未実装のまま merge される事態を防ぐため、設計時点でのチェック機構を導入する。

採用案: A (`skills/spec/figma-design-phase.md` への追記) + C (`modules/verify-patterns.md` への早見表追加)。

## Consumed Comments

- 2026-06-28T06:06:58Z: Issue Retrospective (Auto-Resolve Log) — 採用案 A+C の決定、bats テスト不採用の決定、Figma MCP 非依存配置の決定を確認済み

## Changed Files

- `skills/spec/figma-design-phase.md`: Figma MCP チェック前に `## Interactive UI — a11y Checklist` セクションを追加 — bash 非対象 (md ファイル)
- `modules/verify-patterns.md`: `## Output` 直前に `### 21. Interactive UI Components — a11y Acceptance Criteria Reference` セクションを追加 — bash 非対象 (md ファイル)

## Implementation Steps

1. `skills/spec/figma-design-phase.md` の `## MCP Availability Check` セクションの直前に `## Interactive UI — a11y Checklist` セクションを追加 (→ 受け入れ基準 1, 2, 3, 4)

   セクション内容:
   - **Auto-detection Criteria**: インタラクティブ UI 要素 (toggle / menu / accordion / dialog 等) を含む Issue を対象とする判定基準
   - **Required aria-* Attributes by Component**: UI コンポーネント種別ごとの必須 aria-* 属性テーブル
     - toggle button: `aria-expanded` (true/false 動的更新), `aria-controls`, `aria-label`
     - menu / hamburger: `aria-expanded`, `aria-controls`, `aria-label`, `aria-haspopup`
     - accordion: `aria-expanded`, `aria-controls`, `role="region"`
     - dialog / modal: `aria-modal`, `aria-labelledby`, `aria-describedby`
   - **AC Template**: Spec の Acceptance Criteria に含めるテンプレート例

   配置位置の理由: `## MCP Availability Check` 以降は Figma MCP 不可時に "skip this phase entirely" となる。a11y チェックをその手前に置くことで、Figma 非使用の UI 実装でも必ず参照される構成にする。

2. `modules/verify-patterns.md` の `## Output` セクション直前に `### 21. Interactive UI Components — a11y Acceptance Criteria Reference` セクションを追加 (→ 受け入れ基準 5)

   セクション内容:
   - UI 要素別 a11y AC 早見表テーブル (コンポーネント / 必須 aria-* 属性 / verify command 例)
   - 例: `file_contains "path/to/component" "aria-expanded"` で動的更新の実装を確認するパターン

## Verification

### Pre-merge

- <!-- verify: grep "aria" "skills/spec/figma-design-phase.md" --> `skills/spec/figma-design-phase.md` にインタラクティブ要素の `aria-*` 属性チェック手順が追記されている
- <!-- verify: grep "toggle|dialog|accordion|menu" "skills/spec/figma-design-phase.md" --> toggle / dialog / accordion / menu の各 UI 要素について `aria-*` 属性の要件が列挙されている
- <!-- verify: grep "aria-expanded|aria-controls|aria-label" "skills/spec/figma-design-phase.md" --> `aria-expanded` / `aria-controls` / `aria-label` の具体的な AC テンプレート例が含まれている
- <!-- verify: rubric "skills/spec/figma-design-phase.md の a11y チェックセクションが MCP Availability Check でスキップされない位置 (MCP チェック前か、または Figma 非使用時にも適用される構成) に配置されている" --> Figma MCP 不可時でも a11y チェック手順が参照できる構成になっている
- <!-- verify: grep "aria|a11y|accessibility" "modules/verify-patterns.md" --> `modules/verify-patterns.md` に UI 要素別の a11y AC 早見表が追加されている

### Post-merge

- `/spec` を実行したとき、インタラクティブな UI コンポーネント (toggle ボタン等) を含む Issue の Spec に `aria-*` 属性の動的更新 AC が含まれることを確認する <!-- verify-type: manual -->

## Notes

- `figma-design-phase.md` は `type: domain` / `skill: spec` のドメインファイルであり、`/spec` 実行時のみ参照される。UI 実装に関する Issue であれば Figma 非使用でも本セクションが有効になる (MCP チェック前に配置するため)。
- Auto-Resolve Log からの引き継ぎ: bats テストは LLM 出力 (Spec AC 内容) の機械的検証に不向きのため不採用。`grep` / `rubric` verify command に代替している。
- Conflict detection: 実装なし。Issue body と既存コードに矛盾なし。
