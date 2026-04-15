[English](README.md) | 日本語

# Wholework

自律的な GitHub ワークフローのための Issue 駆動型 Claude Code スキル。

## 🌐 なぜ Wholework なのか

1. **Issue-to-spec 設計** — Issue が *何を* と *完了条件* を定義し、spec が *どう進めるか* を分解します。検証可能な受け入れ基準を最優先とし、可能な限り自動でチェックします。
2. **サイズに応じたルーティングを備えたフルフェーズワークフロー** — `/issue → /spec → /code → /review → /merge → /verify` が要件定義からマージ後の検証まで、ライフサイクル全体をカバーします。
3. **自律実行** — `/auto` は Issue のサイズに応じてフェーズを連鎖させ、必要なときは人手を介さずにワークフロー全体を実行します。
4. **手持ちのツールで動く** — GitHub と Claude Code 上で動作します。標準的な GitHub Flow に沿っているので、どのフェーズでも介入できます。
5. **ソフトウェア開発を超えて** — Issue 駆動型のあらゆるプロジェクトに適用できます: Web サイト、ドキュメント、IaC、リサーチ、OSS 運用など。

## インストール

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

スキルは `wholework:<skill-name>` として利用できます（例: `/wholework:review`、`/wholework:code`）。

開発環境のセットアップについては [docs/ja/structure.md](docs/ja/structure.md#install) を参照してください。

## 🚀 クイックスタート

Wholework を初めて使いますか？ [クイックスタートガイド](docs/ja/guide/quick-start.md) が、インストールから最初の `/auto` 実行までを 10〜15 分で案内します。

全トピックを俯瞰したい場合は [ユーザーガイドのインデックス](docs/ja/guide/index.md) を参照してください。

## 🔄 ワークフロー概要

Wholework は 6 つの組み合わせ可能なスキルで開発ライフサイクル全体をカバーします。

`/issue` → `/spec` → `/code` → `/review` → `/merge` → `/verify`

1 つのコマンドでフルサイクルを実行: `/auto N`。各フェーズの詳細とサイズベースのルーティングについては [ワークフロー概要](docs/ja/guide/workflow.md) を参照してください。

## 🛠️ カスタマイズ

Wholework は `.wholework.yml`（フィーチャーフラグとパス）、`.wholework/domains/`（スキルごとの指示）、adapter（ツール連携）を通じてプロジェクトに適応します。詳細は [カスタマイズガイド](docs/ja/guide/customization.md) を参照してください。

## コントリビュート

すべてのコミットで DCO sign-off が必要です。詳細は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

Apache License 2.0. [LICENSE](LICENSE) を参照してください。
