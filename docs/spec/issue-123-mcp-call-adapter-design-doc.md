# Issue #123: environment-adaptation: mcp_call の adapter 非経由の設計判断を文書化

## Overview

親 Issue #120（プロジェクトローカル拡張ポイント開放）の Sub-issue C。

`verify-executor` では `browser`/`lighthouse` が adapter-resolver 経由で実行されるが、`mcp_call` は ToolSearch を直接呼び出す非対称な設計になっている。adapter パターンの適用要件（複数実装の選択肢が存在する場合に価値がある）を定義し、mcp_call が adapter を経由しない理由を `docs/environment-adaptation.md` に文書化する。

設計方針：**ToolSearch 直接呼び出しを維持**。
- Adapter パターンは「複数の実装選択肢を抽象化する」場合に価値がある（browser-use CLI vs Playwright MCP のような分岐が必要な場合）
- MCP ツールは ToolSearch が唯一の検出・呼び出しメカニズムであり、adapter レイヤーを挟む機能的利点がない
- 将来的な拡張（pre/post 処理カスタマイズ）は adapter ではなく hook 機構として別途追加する方針

## Changed Files

- `docs/environment-adaptation.md`: `### Adapter Pattern` セクションに mcp_call の設計判断（適用要件定義、adapter 非経由の理由、将来方針）を追加
- `modules/verify-executor.md`: `mcp_call` テーブル行に `environment-adaptation.md` の設計判断への参照を追加

## Implementation Steps

1. `docs/environment-adaptation.md` の `### Adapter Pattern` セクションに、adapter パターンの適用要件と mcp_call の設計判断を追記する（→ 受入条件 1, 2）
   - 追記位置: `### Adapter Pattern` セクション内、現在の「An adapter encapsulates a capability」段落の直後（「3-layer resolution order」の説明の後）
   - 内容: adapter 適用要件（複数実装の選択肢が必要）、mcp_call が ToolSearch 直接を維持する理由（ToolSearch が唯一のメカニズム）、将来的拡張方針（hook 機構）
2. `modules/verify-executor.md` の `mcp_call` テーブル行の説明に `environment-adaptation.md` の設計判断への参照を追加する（→ 受入条件 3）
   - 追記位置: `mcp_call` 行の説明テキスト末尾
   - 内容: `docs/environment-adaptation.md` の Adapter Pattern セクションへの参照

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/environment-adaptation.md" "### Adapter Pattern" "mcp" --> `docs/environment-adaptation.md` Adapter Pattern セクションに mcp_call の設計判断（ToolSearch 直接を維持する理由）が記載されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Adapter Pattern" "ToolSearch" --> Adapter Pattern セクションに adapter パターンが MCP に適用されない理由（ToolSearch が唯一の検出・呼び出しメカニズム）が明記されている
- <!-- verify: grep "environment-adaptation" "modules/verify-executor.md" --> `modules/verify-executor.md` の mcp_call エントリに `environment-adaptation.md` の設計判断への参照が追加されている

### Post-merge

- `docs/environment-adaptation.md` の `### Adapter Pattern` セクションが mcp_call と ToolSearch の両キーワードを含む
- `modules/verify-executor.md` の mcp_call 行から environment-adaptation.md へのリンクが辿れる

## Notes

- 実装変更なし（verify-executor の mcp_call 実行ロジックは変更しない）
- `docs/ja/environment-adaptation.md` は翻訳出力ファイルのため実装対象外（`/doc translate` で別途更新）
- doc-checker 対象：今回の変更は docs/ 内のドキュメント追記のみで、スキル・スクリプト・ワークフロー変更ではないため README.md / workflow.md 更新不要

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance conditions were specific and verifiable from the start: all 3 conditions had `<!-- verify: ... -->` commands attached, which enabled full auto-verification.
- The design decision (ToolSearch直接を維持) was clarified in the Issue body itself, so no additional ambiguity resolution was needed during spec phase.

#### design
- Spec matched implementation exactly: 2 files changed (`docs/environment-adaptation.md`, `modules/verify-executor.md`) as planned.
- No design deviations or gaps detected.

#### code
- Single clean commit (`6885ef4`): 13 lines added, 1 line modified. No fixup/amend patterns.
- Patch route (no PR): issue was small enough for direct commit to main.

#### review
- Patch route — no PR review. Given the minimal scope (documentation-only change), skipping PR review was appropriate.

#### merge
- No merge issues. Patch route commit applied cleanly to main.

#### verify
- All 3 `section_contains` and `grep` conditions passed on first run.
- Verify commands were well-matched to the acceptance criteria, enabling clean auto-verification.

### Improvement Proposals
- N/A
