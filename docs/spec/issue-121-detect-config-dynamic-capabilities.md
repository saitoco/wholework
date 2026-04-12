# Issue #121: detect-config-markers: capabilities テーブルを動的認識に開放

## Overview

`modules/detect-config-markers.md` の Marker Definition Table が "(exhaustive)" とマークされているため、ユーザーが `.wholework.yml` に任意の `capabilities.{name}: true` を追加しても変数が生成されない。

本 Issue では以下を実装する：
- Marker Definition Table の "(exhaustive)" ラベルを除去し、固定マッピングテーブルであることを明示する
- 任意の `capabilities.{name}` boolean キーを動的に `HAS_{UPPERCASE_NAME}_CAPABILITY` にマッピングするルールを Processing Steps に追加する
- 既存の `capabilities.browser` / `capabilities.mcp` マッピングは変更しない（後方互換）
- `docs/environment-adaptation.md` の Layer 1 / Layer 2 に動的 capabilities 認識の説明を追加する

## Changed Files

- `modules/detect-config-markers.md`: "Marker Definition Table (exhaustive)" から "(exhaustive)" を除去して "(fixed mappings)" に変更し、動的マッピングルールを `### 2. Interpret YAML Keys` 内 Processing Steps に追加する
- `docs/environment-adaptation.md`: Layer 1 セクションにカスタム capabilities 宣言と `HAS_` マッピングの説明例を追加、Layer 2 セクションに動的 `HAS_{UPPERCASE_NAME}_CAPABILITY` 変数生成の仕様を追記する

## Implementation Steps

1. `modules/detect-config-markers.md` を更新する（→ 受入基準 1, 2, 3, 4）
   - `### 2. Interpret YAML Keys` 内の `**Marker Definition Table (exhaustive):**` を `**Marker Definition Table (fixed mappings):**` に変更し "(exhaustive)" を除去
   - 表の直後に動的マッピングルールを追加：「上記テーブルに含まれない `capabilities.{name}` boolean キー（`capabilities.mcp` を除く）は、`HAS_{UPPERCASE_NAME}_CAPABILITY` 変数に動的にマッピングされる。`true` のとき変数値 `true`、`false`/未設定のとき `false`」
   - 既存の `capabilities.browser` → `HAS_BROWSER_CAPABILITY` および `capabilities.mcp` → `MCP_TOOLS` エントリはそのまま維持

2. `docs/environment-adaptation.md` を更新する（→ 受入基準 5, 6）
   - Layer 1 セクションの YAML 例にカスタム capability 宣言例（`invoice-api: true`）を追加し、`HAS_INVOICE_API_CAPABILITY` にマッピングされることをコメントで示す
   - Layer 2 セクションの Detection Mechanisms テーブル（`detect-config-markers.md` 行）に、動的 `HAS_{UPPERCASE_NAME}_CAPABILITY` 変数生成の説明を追記する

## Verification

### Pre-merge

- <!-- verify: section_not_contains "modules/detect-config-markers.md" "### 2." "(exhaustive)" --> マーカー定義テーブルが "(exhaustive)" ではなくなり、テーブル外の capabilities キーも処理される旨が記載されている
- <!-- verify: section_contains "modules/detect-config-markers.md" "## Processing Steps" "HAS_{" --> 任意の `capabilities.{name}` が `HAS_{UPPERCASE_NAME}_CAPABILITY` にマッピングされる動的ルールが Processing Steps 内に記載されている
- <!-- verify: grep "capabilities.browser" "modules/detect-config-markers.md" --> 既存の `capabilities.browser` → `HAS_BROWSER_CAPABILITY` マッピングが維持されている（後方互換）
- <!-- verify: grep "capabilities.mcp" "modules/detect-config-markers.md" --> 既存の `capabilities.mcp` → `MCP_TOOLS` マッピングが維持されている（後方互換）
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 1" "HAS_" --> `docs/environment-adaptation.md` Layer 1 セクションにカスタム capabilities 宣言とマッピングの説明が追加されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 2" "HAS_" --> `docs/environment-adaptation.md` Layer 2 セクションに動的 capabilities 認識の仕様が反映されている

### Post-merge

- `/verify 121` を実行して全 Pre-merge 項目が PASS になること
- Sub-issue #122 (Domain ファイル機構) および #124 (カスタム verify command) でカスタム capability が利用できること

## Notes

Issue 本文の Auto-Resolved Ambiguity Points より：
- **新規 capabilities キーの型**: boolean のみ対応。`capabilities.mcp` の list 型は特殊パースのため、新規キーは boolean 限定。list が必要な場合は固定テーブルに明示追加
- **テーブルの位置づけ変更**: 「既知の固定マッピング」テーブルとして位置づけ変更し、動的マッピングルールを別途追記
- **adapter-resolver.md**: 変更不要（`.wholework.yml` 宣言済み capability は動的変数生成されるため、フォールバックは未宣言 capability のみ）

## Code Retrospective

### Deviations from Design
- N/A（実装は Spec の通り）

### Design Gaps/Ambiguities
- `docs/ja/environment-adaptation.md`（日本語版）の更新が Spec の Changed Files に記載されていなかった。英語版と同期して日本語版も更新した

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件が6件すべて `section_not_contains` / `section_contains` / `grep` で自動検証可能な形式で設計されており、品質が高い。変更対象ファイル（`modules/detect-config-markers.md`, `docs/environment-adaptation.md`）と条件が1対1に対応し、曖昧さがない。

#### design
- Spec の Changed Files に日本語版ドキュメント（`docs/ja/environment-adaptation.md`）が含まれていなかった点が唯一の設計上のギャップ（Code Retrospective に記録済み）。実装範囲が小さく設計の正確性は高い。

#### code
- 実装コミット1件（`f64798a`）と Code Retrospective コミット1件（`75ef424`）のみ。fixup / amend パターンなし。パッチルートで直接 main にコミットされており、レビューなしで完結。

#### review
- パッチルート（PR なし）のため、フォーマルなレビューは行われていない。変更内容がドキュメントモジュールのみで影響範囲が限定的なため、妥当な判断。

#### merge
- パッチルート（直接 `main` へのコミット）。コンフリクトなし、CI の問題なし。

#### verify
- 全6条件 PASS。パッチルートのため PR が存在せず、`github_check "gh pr checks"` 形式のコマンドは使用されていない（適切な設計）。verify コマンドはすべて静的ファイル検証で完結しており、信頼性が高い。

### Improvement Proposals
- N/A
