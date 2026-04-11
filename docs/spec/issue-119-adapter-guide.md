# Issue #119: docs: アダプター作成ガイドを追加

## Overview

Wholework ユーザーがプロジェクト固有の capability（MCP サーバ、CLI ツール、外部サービスなど）のアダプターを作成・設定するための汎用ガイドを `docs/adapter-guide.md` に作成する。

対象読者は wholework リポジトリをクローンしていない **アダプター制作者**。公開 URL 経由で Claude Code へ渡してアダプター作成を依頼できる自己完結型の形式とする。`type: project` frontmatter を付与し `/doc sync` / `/audit drift` の対象とする。

ガイドに含める内容（acceptance criteria に基づく）：
- `.wholework.yml` の `capabilities` セクション設定手順
- アダプターファイル配置パス（`.wholework/adapters/`）と 3 層解決（project-local → user-global → bundled）の説明
- `mcp_call` verify command の acceptance criteria 設計パターン例
- アダプター契約テンプレート（Detection / Execution / Result セクション）の自己完結的埋め込み
- Claude Code への依頼プロンプトテンプレートセクション（コピペ可能なワンショット形式）
- Further Reading に `environment-adaptation.md` と `browser-adapter.md` への参照

## Changed Files

- `docs/adapter-guide.md`: new file — アダプター作成汎用ガイド（自己完結型、Project Document）
- `docs/structure.md`: add — docsセクションに `adapter-guide.md` への参照を追加

## Implementation Steps

1. `docs/adapter-guide.md` を新規作成する。以下の構成とする（→ acceptance criteria 1〜8）：
   - frontmatter: `type: project`、`ssot_for: [adapter-authoring-guide]`
   - **Overview** — ガイドの目的と自己完結性の説明
   - **Prerequisites** — `.wholework.yml` の `capabilities` セクション設定手順（`browser`、`mcp` の宣言方法を含む）
   - **Adapter Resolution** — `.wholework/adapters/` 配置パスと 3 層解決順序の説明
   - **Adapter Contract Template** — Detection / Execution / Result の 3 セクション構成を、`Processing Steps` ヘッダーを含めてガイド内に完全埋め込み（`environment-adaptation.md` の File Structure Template をベースに整形）
   - **Workflow Integration Example** — `/issue` acceptance criteria での `mcp_call` verify command 設計例
   - **Claude Code Prompt Template** — コピペ可能なワンショット形式のプロンプト（GitHub 公開 URL を含む）
   - **Further Reading** — `environment-adaptation.md`、`browser-adapter.md` への参照（必須依存ではなく参考情報として明記）

2. `docs/structure.md` の docsセクション（`docs/` ディレクトリツリー）に `adapter-guide.md` の行を追加する（→ acceptance criteria 9）：
   - 追加位置: `figma-best-practices.md` の次行付近（既存のプロジェクト文書リストに沿う）
   - 追加内容: `│   ├── adapter-guide.md    # Adapter authoring guide for project-specific capabilities (project)`

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/adapter-guide.md" --> `docs/adapter-guide.md` が作成されている
- <!-- verify: grep "type: project" "docs/adapter-guide.md" --> `type: project` frontmatter が付与されている
- <!-- verify: grep "\.wholework\.yml" "docs/adapter-guide.md" --> `.wholework.yml` の `capabilities` セクション設定手順が含まれている
- <!-- verify: grep "\.wholework/adapters/" "docs/adapter-guide.md" --> アダプターファイルの配置パス（`.wholework/adapters/`）と3層解決の説明が含まれている
- <!-- verify: grep "mcp_call" "docs/adapter-guide.md" --> `mcp_call` verify command を設計するパターンが例示されている
- <!-- verify: grep "Processing Steps" "docs/adapter-guide.md" --> アダプター契約テンプレート（Detection / Execution / Result セクション）がガイド内に完全に埋め込まれている
- <!-- verify: grep "Prompt" "docs/adapter-guide.md" --> Claude Code への依頼プロンプトテンプレートセクションが含まれている
- <!-- verify: grep "Further Reading" "docs/adapter-guide.md" --> `environment-adaptation.md` および `browser-adapter.md` への参照が Further Reading セクションに配置されている
- <!-- verify: file_contains "docs/structure.md" "adapter-guide.md" --> `docs/structure.md` の docs セクションに `adapter-guide.md` への参照が追加されている

### Post-merge

- `docs/adapter-guide.md` が GitHub 公開 URL で WebFetch 可能であり、ガイド単体で Claude Code がアダプター作成を実施できる
- `/audit drift` 実行時に `docs/adapter-guide.md` が Project Document としてドリフト検出対象になっている

## Notes

- 契約テンプレートの "Processing Steps" ヘッダーは `grep "Processing Steps" "docs/adapter-guide.md"` の verify 条件を満たすため、テンプレートセクション内に必ず含める
- プロンプトテンプレートは「Prompt」という文字列を含む見出しまたはセクション名とする（`grep "Prompt" "docs/adapter-guide.md"` を満たすため）
- `docs/structure.md` ツリーへの追加行は、ファイルが実際に存在したときに `file_contains` が PASS になることを確認済み
- `ISSUE_TYPE=Task` のため Uncertainty セクションは省略
