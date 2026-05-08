[English](../../guide/quick-start.md) | 日本語

# 🚀 クイックスタート

サンプル Issue を使って `/issue` → `/code` → `/verify` を約 10 分で体験します。

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

Wholework は初回実行時に必要なラベルを自動作成します — 手動セットアップは不要です。

## Step 2 — サンプル Issue を作成

GitHub リポジトリで以下のタイトルと本文で Issue を作成します。そのままコピー&ペーストできます。

**タイトル:**

```
hello world スクリプトを追加する
```

**本文:**

```markdown
## Background

プロジェクトのセットアップ確認用にシンプルなシェルスクリプトが必要。

## Purpose

`scripts/hello.sh` を追加し、実行すると「Hello, Wholework!」と出力されるようにする。

## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] <!-- verify: file_exists "scripts/hello.sh" --> `scripts/hello.sh` が存在する
- [ ] <!-- verify: command "bash scripts/hello.sh | grep -qF 'Hello, Wholework!'" --> `bash scripts/hello.sh` を実行すると `Hello, Wholework!` が出力される
```

Issue 番号（例: `#42`）を控えておいてください — 次のステップで使います。

## Step 3 — `/issue` を実行

Claude Code で実行:

```
/issue 42
```

`42` は実際の Issue 番号に置き換えてください。

`/issue` は Issue を triage します: Size ラベル（このサンプルでは XS）を付与し、Type を Feature に設定し、`phase/ready` ラベルを追加します。GitHub の Issue メタデータで triage 結果を確認できます。

## Step 4 — `/code` を実行

```
/code 42
```

`/code` は Issue を読み込み、`scripts/hello.sh` を実装して main に直接コミットします（これが XS patch route です — spec フェーズや pull request はありません）。リポジトリにコミットが追加されるのを確認できます。

> **XS patch route について**: XS サイズの Issue では、Wholework は `/spec` フェーズをスキップして直接コミットします。`/verify` フェーズで使用するために、retrospective spec ファイル（`docs/spec/issue-N-*.md`）が自動生成されます。

## Step 5 — `/verify` を実行

```
/verify 42
```

`/verify` は Issue に定義された受入条件をチェックします: `scripts/hello.sh` が存在し期待通りの文字列を出力することを確認し、Issue をクローズしてチェックボックスにチェックを入れます。

## Step 6 — 結果を確認

`/verify` が完了したら以下を確認:

- GitHub で Issue が **クローズ** されているはず
- リポジトリに `scripts/hello.sh` が存在するはず
- Issue の受入条件チェックボックスがチェックされているはず

何かおかしい場合は [トラブルシューティング](troubleshooting.md) を参照してください。

## Step 7 — フル自動ワークフローを試す

もっと大きな挑戦をしたいですか？より複雑な Issue（Size M や L）を作成して `/auto` を実行してください — Wholework が spec → code → review → merge → verify のフルサイクルを自動で実行します。

## 🧭 次のステップ

基本は完了です。次に探索する方向を 3 つ紹介します:

- **`/doc init` で Steering Documents を設定** — Steering Documents（`docs/product.md`、`docs/tech.md`、`docs/structure.md`）は Wholework にプロジェクト固有のコンテキストを与えます。`/spec` や `/code` のようなスキルが自動的に読み込みます。`/doc init` を実行するとコードベースに合わせた初期セットが作成され、生成される spec と実装の質が大きく向上します
- **プロジェクト向けに Wholework をカスタマイズ** — `.wholework.yml` ファイルはレビューツール連携、spec パス、オプション機能を制御します。`.wholework/domains/` ディレクトリは各スキルフェーズにプロジェクト固有の指示を追加できます。詳細は [カスタマイズ](customization.md) を参照
- **継続運用コマンドを探索** — Issue のバックログが溜まったら、`/triage --backlog` でサイズとタイプを一括付与できます。`/audit` はドキュメントとコードの乖離を検出します。これらのコマンドはバックログが増えてもプロジェクト健全性の維持に役立ちます
