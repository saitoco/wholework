# Issue #158: customization.md に .wholework.yml Available Keys 完全リファレンス表を追加

## Overview

`docs/guide/customization.md` の `.wholework.yml` サンプル YAML セクションの直後に `### Available Keys` 見出しを追加し、全設定キーを Key / Type / Default / Description の 4 列表で列挙する。末尾に SSoT である `modules/detect-config-markers.md` への参照リンクを付与する。日本語ミラー `docs/ja/guide/customization.md` にも同等のセクションを追加する。

## Changed Files

- `docs/guide/customization.md`: `### Available Keys` セクションを追加（サンプル YAML 直後）
- `docs/ja/guide/customization.md`: 同セクションを日本語で追加

## Implementation Steps

1. `docs/guide/customization.md` の「All keys are optional.」段落の直後（`## .wholework/domains/` 見出しの直前）に `### Available Keys` セクションを挿入する。表の列は Key / Type / Default / Description（4 列）。末尾に `modules/detect-config-markers.md` へのリンクを付与する。(→ 受入条件 1–6)
2. `docs/ja/guide/customization.md` の対応箇所（「すべてのキーはオプションです。」段落の直後）に同セクションを日本語で挿入する。(→ 受入条件 1–6 のミラー整合)

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/guide/customization.md" "Available Keys" --> customization.md に `Available Keys` 見出しが存在する
- <!-- verify: section_contains "docs/guide/customization.md" "### Available Keys" "opportunistic-verify" --> `opportunistic-verify` がリファレンス表に含まれる
- <!-- verify: section_contains "docs/guide/customization.md" "### Available Keys" "spec-path" --> `spec-path` がリファレンス表に含まれる
- <!-- verify: section_contains "docs/guide/customization.md" "### Available Keys" "capabilities.browser" --> `capabilities.browser` がリファレンス表に含まれる
- <!-- verify: section_contains "docs/guide/customization.md" "### Available Keys" "steering-hint" --> `steering-hint` がリファレンス表に含まれる
- <!-- verify: file_contains "docs/guide/customization.md" "modules/detect-config-markers.md" --> SSoT 参照リンクが存在する

### Post-merge

- customization.md を読んだ新規ユーザーが、他のドキュメントを参照せず主要設定キーを理解できる
- `detect-config-markers.md` に新キーが追加された際、customization.md との drift が `/audit drift` で検出可能

## Notes

表に含めるキーと値（Issue 本文および `modules/detect-config-markers.md` から確定）:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `copilot-review` | boolean | `false` | Wait for GitHub Copilot review before merging |
| `claude-code-review` | boolean | `false` | Wait for Claude Code Review before merging |
| `coderabbit-review` | boolean | `false` | Wait for CodeRabbit review before merging |
| `review-bug` | boolean | `true` | Run bug-detection agent in `/review` |
| `opportunistic-verify` | boolean | `false` | Run quick verify commands at skill completion |
| `skill-proposals` | boolean | `false` | Generate Wholework improvement issues during `/verify` |
| `steering-hint` | boolean | `true` | Show `/doc init` hint when steering docs are missing |
| `production-url` | string | `""` | Production URL for browser-based verify commands |
| `spec-path` | string | `docs/spec` | Where specs are stored |
| `steering-docs-path` | string | `docs` | Where steering documents live |
| `capabilities.browser` | boolean | `false` | Enable Playwright-based verify commands |
| `capabilities.mcp` | list | `[]` | MCP tool names available to skills |
| `capabilities.{name}` | boolean | `false` | Dynamic capability mapping (e.g., `capabilities.invoice-api: true`) |

`docs/ja/guide/customization.md` は日本語ミラーのため、表の Key 列は英語のまま維持し、Description のみ日本語化する。

## Code Retrospective

### Deviations from Design

- N/A（設計通りに実装）

### Design Gaps/Ambiguities

- Spec の挿入箇所定義「All keys are optional.」段落の直後）は明確で曖昧さなし
- `docs/ja/guide/customization.md` の参照リンクパスは `../../../modules/detect-config-markers.md` が正しいが、実際のファイル配置を確認すると `docs/ja/guide/` からは `../../..` が必要なため `../../../modules/detect-config-markers.md` と記載（ルートから `modules/` へのパス）

### Rework

- N/A（手戻りなし）

## review retrospective

### Spec vs. 実装の乖離パターン

特記なし。Spec と PR diff が完全に一致しており、乖離は発生しなかった。ドキュメント追加系の Issue では Spec に挿入箇所・列構成・キー一覧が明確に定義されていたため、乖離の余地が少ない。

### 繰り返し問題

特記なし。今回は純粋なドキュメント追加であり、MUST/SHOULD/CONSIDER いずれの問題も検出されなかった。

### 受入条件の検証難易度

問題なし。`file_contains` および `section_contains` による verify command が適切で、偽陽性を防ぐ工夫（`file_contains` から `section_contains` への変更）がすでに Issue 本文の「自動解決した曖昧点」として記録されており、verify command の精度が高かった。UNCERTAIN 0 件。
