# Issue #154: docs: ユーザー向けマニュアル整備（README 改訂 + docs/guide/ 新設）

## Overview

ユーザー向けマニュアルを `docs/guide/` に新設し、README を改訂する。評価中の個人開発者が README 起点で 10-15 分以内に初回 `/auto` 実行成功へ到達できる導線を用意する。各マニュアルページは `type: project` frontmatter を付与し、`/doc sync` および `/audit drift` の自動検出スコープに含める（SSoT / ドリフト防止）。トーンは親しみやすさを優先し、主要見出し近傍への絵文字追加を許容する。

## Changed Files

- `docs/guide/index.md`: new file (TOC、対象読者、`docs/product.md` Terms への参照)
- `docs/guide/quick-start.md`: new file (`ssot_for: user-onboarding-flow`、インストール → サンプル Issue → `/auto` → Next Steps)
- `docs/guide/workflow.md`: new file (各 phase のユーザー視点使い方、Size ルーティング)
- `docs/guide/customization.md`: new file (`ssot_for: customization-entry-points`、`.wholework.yml` / `.wholework/domains/` / adapter)
- `docs/guide/troubleshooting.md`: new file (最低限の FAQ: gh 認証、plugin install、verify 失敗の読み方)
- `README.md`: delete `## Repository structure` section; add `## 🚀 Quick Start`, `## 🔄 Workflow Overview`, `## 🛠️ Customization` sections
- `docs/structure.md`: Directory Layout tree に `docs/guide/` ディレクトリエントリを追加
- `docs/product.md`: `docs/guide/` の役割を 1-2 行で Terms or 関連セクションに追記（既存 SSoT との関係を明記）

## Implementation Steps

1. **`docs/guide/` ディレクトリと 5 ファイルの骨格作成** (→ AC: 5 ファイルの `file_exists` + `type: project` frontmatter 7 項目): 各ファイルに frontmatter を設置。`quick-start.md` に `ssot_for: [user-onboarding-flow]`、`customization.md` に `ssot_for: [customization-entry-points]` を宣言。他 3 ファイルは `type: project` のみ。全ファイル冒頭に `English | [日本語](../ja/guide/...)` のプレースホルダは置かない（`/doc translate` 実行時に自動生成される）

2. **`docs/guide/quick-start.md` の本文執筆** (parallel with 1) (→ AC: `/auto` 言及、`Next Steps` セクション内の `/doc init` および customization 言及): インストール（marketplace 版）→ サンプル Issue の title/body をコピー&ペースト可能な形で提示 → `/auto N` 実行ログの主要ポイント解説 → PR 作成〜merge〜verify の流れ → 成功時の最終状態チェックリスト → `## 🧭 Next Steps` セクションで `/doc init`（Steering Documents による skill 品質安定化、1-2 行で理由説明）・`docs/guide/customization.md` への導線・`/audit` / `/triage --backlog` の紹介を列挙

3. **残り 4 ガイドページの本文執筆** (parallel with 2) (→ AC: customization.md の `.wholework.yml` と `adapter` 言及、各 manual 検証項目):
   - `index.md`: 主要見出しに絵文字 1 つ程度、対象読者セクション、5 ページへのリンク一覧、用語は `docs/product.md` の `## Terms` へのリンクで代替（独自 Glossary は作らない）
   - `workflow.md`: 各 skill の「いつ使うか」をユーザー視点で記述。Size ルーティング（XS/S→patch, M/L→PR, XL→sub-issue）と patch/PR 経路の使い分け。既存 `docs/workflow.md` への参照リンクを「開発者向け内部動作」として併記
   - `customization.md`: `.wholework.yml` の主要キー一覧（配下の詳細は `modules/detect-config-markers.md` への参照）、`.wholework/domains/` 概要、adapter の 3 階層（project-local → user-global → bundled）
   - `troubleshooting.md`: gh 認証、plugin install 失敗、verify コマンド読み方の 3 項目最低ライン

4. **README.md の改訂** (after 1) (→ AC: README 5 項目: Quick Start / Workflow Overview / Customization / quick-start.md リンク / Repository structure 削除): `## Repository structure` を削除（CONTRIBUTING 経由の `docs/structure.md` リンクは README に残さない — CONTRIBUTING.md 側で既に記載されていればそのまま、無ければ `## Contributing` 節内にリンクを含める形で維持）。`## 🚀 Quick Start` / `## 🔄 Workflow Overview` / `## 🛠️ Customization` の 3 セクションを新設し、それぞれ `docs/guide/` 配下への導線を 1-2 段落で記述。絵文字は主要見出しのみに限定し、本文段落・リスト項目には使わない

5. **`docs/structure.md` と `docs/product.md` の参照更新** (after 1) (→ AC: `/doc sync` 認識): `docs/structure.md` の Directory Layout の `docs/` ツリーに `guide/` エントリを追加（コメント: `# User-facing manual (index, quick-start, workflow, customization, troubleshooting) (project)`）。`docs/product.md` の Future Direction の直前 or Terms の直後あたりに 1 行で `docs/guide/` の役割を明記（例: "User-facing manual is maintained under `docs/guide/`."）

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/guide/index.md" --> `docs/guide/index.md` が作成されている
- <!-- verify: file_exists "docs/guide/quick-start.md" --> `docs/guide/quick-start.md` が作成されている
- <!-- verify: file_exists "docs/guide/workflow.md" --> `docs/guide/workflow.md` が作成されている
- <!-- verify: file_exists "docs/guide/customization.md" --> `docs/guide/customization.md` が作成されている
- <!-- verify: file_exists "docs/guide/troubleshooting.md" --> `docs/guide/troubleshooting.md` が作成されている
- <!-- verify: file_contains "docs/guide/index.md" "type: project" --> index.md に `type: project` frontmatter が付与されている
- <!-- verify: file_contains "docs/guide/quick-start.md" "type: project" --> quick-start.md に `type: project` frontmatter が付与されている
- <!-- verify: file_contains "docs/guide/workflow.md" "type: project" --> workflow.md に `type: project` frontmatter が付与されている
- <!-- verify: file_contains "docs/guide/customization.md" "type: project" --> customization.md に `type: project` frontmatter が付与されている
- <!-- verify: file_contains "docs/guide/troubleshooting.md" "type: project" --> troubleshooting.md に `type: project` frontmatter が付与されている
- <!-- verify: file_contains "docs/guide/quick-start.md" "user-onboarding-flow" --> quick-start.md に `ssot_for: user-onboarding-flow` が宣言されている
- <!-- verify: file_contains "docs/guide/customization.md" "customization-entry-points" --> customization.md に `ssot_for: customization-entry-points` が宣言されている
- <!-- verify: file_contains "docs/guide/quick-start.md" "/auto" --> Quick Start に `/auto` の実行例が含まれる
- <!-- verify: section_contains "docs/guide/quick-start.md" "Next Steps" "/doc init" --> Quick Start の Next Steps セクションに `/doc init` の推奨が含まれる
- <!-- verify: section_contains "docs/guide/quick-start.md" "Next Steps" "customization" --> Next Steps から customization.md への導線がある
- <!-- verify: file_contains "docs/guide/customization.md" ".wholework.yml" --> customization.md に `.wholework.yml` の説明がある
- <!-- verify: file_contains "docs/guide/customization.md" "adapter" --> customization.md に adapter の説明がある
- <!-- verify: file_contains "README.md" "Quick Start" --> README に Quick Start セクションが追加されている
- <!-- verify: file_contains "README.md" "docs/guide/quick-start.md" --> README から Quick Start Guide へのリンクが存在する
- <!-- verify: file_contains "README.md" "Workflow Overview" --> README に Workflow Overview セクションが追加されている
- <!-- verify: file_contains "README.md" "Customization" --> README に Customization セクションが追加されている
- <!-- verify: file_not_contains "README.md" "## Repository structure" --> README から Repository structure セクションが削除されている

### Post-merge

- Wholework 未経験の開発者が README → Quick Start の導線のみで、初回 `/auto` 実行を 15 分以内に成功させられる（ドッグフーディングで 1 名以上検証）
- `docs/guide/` 配下の各ページから関連ページへの相互リンクが張られ、迷子にならない
- README および `docs/guide/` 配下の絵文字使用は主要見出し近傍に留まり、本文段落・リスト項目への連発がない（レビュー時に目視確認）
- `/doc sync` 実行時に `docs/guide/` 配下が Project Documents として認識され、normalization 対象に含まれる

## Code Retrospective

### Deviations from Design

- README の `## Repository structure` 削除後、`CONTRIBUTING.md` 経由の `docs/structure.md` リンクは「CONTRIBUTING.md 側に既に記載あれば維持、なければ `## Contributing` 節にリンクを含める形で維持」という Spec の指示があったが、CONTRIBUTING.md を確認したところ構造ドキュメントへのリンクは元々なく、かつ README の `## Contributing` 節も一行のみで追加は冗長と判断。`docs/structure.md#install` リンクは既存 `## Install` 節に残っているため、`docs/structure.md` への参照は保持されていると判断し、`## Contributing` へのリンク追加は省略した。

### Design Gaps/Ambiguities

- Spec の Step 4 では「CONTRIBUTING 経由の `docs/structure.md` リンクは別途維持」と記載されているが、CONTRIBUTING.md を確認すると構造ドキュメントへのリンクは存在しなかった。Spec 作成時の前提（CONTRIBUTING に structure.md リンクがある）が実態と異なっていた。

### Rework

- 特になし。

## Notes

- **Simplicity rule 超過について**: light 用の verify 項目数上限は 5 だが、Issue body の受入条件 pre-merge は 22 項目あり全てそのままコピーした（1:1 対応で `/verify` の自動判定が確実になることを優先）。step 数は 5 に収めグループ化で対応
- **絵文字運用**: 主要セクション見出し直前のみ許容（例: `## 🚀 Quick Start`）。本文段落・リスト各項目・コードフェンス周辺での使用は避ける。半角 `!` は引き続き Forbidden（tech.md）
- **既存 `docs/workflow.md` との重複回避**: 新規 `docs/guide/workflow.md` は「ユーザーがいつ何のコマンドを打つか」のフロー、既存 `docs/workflow.md` は「skill 内部の phase 定義と label 遷移」と役割分離。相互リンクで補完
- **Terms の扱い**: `docs/product.md` の `## Terms` を SSoT として維持。`docs/guide/index.md` から参照リンクで到達可能にする
- **翻訳**: 本 Issue では英語版のみ。`/doc translate ja` を後続 Issue で実行し `docs/ja/guide/` を生成する（frontmatter `type: project` により自動で翻訳対象になる）
- **#155 との関係**: 本 Issue の `quick-start.md > Next Steps` は静的案内、#155（動的ヒント）は skill 完了時の動的表示で相補的。両者は並行せず、#155 は #154 の customization.md / quick-start.md を前提に blocked-by される
