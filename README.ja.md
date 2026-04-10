[English](README.md) | 日本語

# Wholework

自律的な GitHub ワークフローのための、Spec ファーストな Claude Code Skill 群。

## なぜ Wholework か

1. **Issue から Spec への設計** — Issue は *何を* と *いつ完了とみなすか* を定義し、Spec は *どうやって* そこに到達するかを分解します。検証可能な受入条件を最優先とし、可能な限り自動チェックします。
2. **Size に応じたルーティングを備えた全フェーズワークフロー** — `/issue → /spec → /code → /review → /merge → /verify` が、要件定義からマージ後の検証までライフサイクル全体をカバーします。
3. **自律実行** — `/auto` は Issue の Size に応じてフェーズを連鎖させ、必要に応じてワークフロー全体を人手を介さず実行します。
4. **手元の環境で動く** — GitHub と Claude Code の上で動作します。標準的な GitHub Flow に従っており、任意のフェーズで介入できます。
5. **ソフトウェア開発にとどまらない** — Issue 駆動のあらゆるプロジェクトに適用できます: Web サイト、ドキュメント、IaC、リサーチ、OSS 運営など。

## インストール

```sh
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

Skill は `wholework:<skill-name>` として利用可能です（例: `/wholework:review`、`/wholework:code`）。

開発環境のセットアップについては [docs/ja/structure.md](docs/ja/structure.md#install) を参照してください。

## リポジトリ構成

ディレクトリレイアウトとインストール規約の全体像は [`docs/ja/structure.md`](docs/ja/structure.md) を参照してください。

## ライセンス

Apache License 2.0。[LICENSE](LICENSE) を参照してください。
