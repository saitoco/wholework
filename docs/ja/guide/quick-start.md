[English](../../guide/quick-start.md) | 日本語

# 🚀 クイックスタート

10〜15 分でゼロから最初の `/auto` 自動実行までたどり着きます。

## 前提条件

- Claude Code がインストール済み（デスクトップアプリまたは CLI）
- 使用したいリポジトリがある GitHub アカウント
- `gh` CLI 認証済み（`gh auth login`）

## Step 1 — Wholework をインストール

Claude Code を開いて実行:

```
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

`/wholework:` と入力してインストールを確認 — 自動補完リストに利用可能なスキルが表示されるはずです。

## Step 2 — サンプル Issue を作成

GitHub リポジトリで以下のタイトルと本文で Issue を作成します。そのままコピー&ペーストできます。

**タイトル:**

```
Add a hello world script
```

**本文:**

```markdown
## Background

We need a simple script to verify the project setup.

## Goal

Create a shell script that prints "Hello, Wholework!" when run.

## Acceptance Criteria

- [ ] `scripts/hello.sh` exists
- [ ] Running `bash scripts/hello.sh` outputs `Hello, Wholework!`
```

Issue 番号（例: `#42`）を控えておいてください — 次のステップで使います。

## Step 3 — `/auto` を実行

Claude Code で実行:

```
/auto 42
```

`42` は実際の Issue 番号に置き換えてください。

Wholework は以下を行います:

1. Issue を triage してサイズを付与（XS または S — 直接コミットで十分な小ささ）
2. `/spec` で実装計画を作成
3. `/code` でスクリプトを実装し main にコミット
4. `/verify` で受入条件が満たされたことを確認

進行中は `/spec #42`、`/code #42`、`/verify #42` のようなフェーズバナーが表示されます。

## Step 4 — 結果を確認

`/auto` が完了したら以下を確認:

- GitHub で Issue が **クローズ** されているはず
- リポジトリに `scripts/hello.sh` が存在するはず
- Issue の受入条件チェックボックスがチェックされているはず

何かおかしい場合は [トラブルシューティング](troubleshooting.md) を参照してください。

## Step 5 — PR ベースのワークフローを試す

より大きな変更（Size M や L）の場合、Wholework は直接コミットする代わりに pull request を作成します。これを試すには、より複雑な Issue を作成してもう一度 `/auto` を実行してください — Wholework が spec → code → review → merge → verify のフルサイクルでルーティングします。

## 🧭 次のステップ

基本は完了です。次に探索する方向を 3 つ紹介します:

- **`/doc init` で Steering Documents を設定** — Steering Documents（`docs/product.md`、`docs/tech.md`、`docs/structure.md`）は Wholework にプロジェクト固有のコンテキストを与えます。`/spec` や `/code` のようなスキルが自動的に読み込みます。`/doc init` を実行するとコードベースに合わせた初期セットが作成され、生成される spec と実装の質が大きく向上します
- **プロジェクト向けに Wholework をカスタマイズ** — `.wholework.yml` ファイルはレビューツール連携、spec パス、オプション機能を制御します。`.wholework/domains/` ディレクトリは各スキルフェーズにプロジェクト固有の指示を追加できます。詳細は [カスタマイズ](customization.md) を参照
- **継続運用コマンドを探索** — Issue のバックログが溜まったら、`/triage --backlog` でサイズとタイプを一括付与できます。`/audit` はドキュメントとコードの乖離を検出します。これらのコマンドはバックログが増えてもプロジェクト健全性の維持に役立ちます
