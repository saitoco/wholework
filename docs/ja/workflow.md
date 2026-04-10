[English](../workflow.md) | 日本語

# 開発ワークフロー

## 概要

Claude Code Skills を用いた開発ワークフローの概要です。フロー図は [docs/product.md](product.md) を参照してください。

**フルワークフロー**: `/issue` → `/auto`（spec 自動実行）→ code → review → merge → verify（または `/spec` → `/code` → `/review` → `/merge` → `/verify`）

**軽量ワークフロー**: `/code --patch` — Size XS/S の修正を main に直接コミットします。`/spec` が Size XS/S と判定した後にも選択可能です。詳細: [`skills/code/SKILL.md`](../../skills/code/SKILL.md)

**Size→ワークフロールーティング**: Issue の Size プロパティがワークフローの経路を決定します。判定表（Size 決定基準 2 軸 + Size→ワークフローマッピング）は [`modules/size-workflow-table.md`](../../modules/size-workflow-table.md) を参照してください。

main ブランチ保護ルール: [CLAUDE.md](../../CLAUDE.md) を参照してください。

## フェーズ詳細

Skill 内部の挙動は `skills/<name>/SKILL.md` を参照してください。本セクションでは各フェーズの役割と位置付けのみを扱います。

### 0. 基盤管理フェーズ — `/doc`、`/audit`

プロジェクトの基盤情報を `docs/` で保守します。各ドキュメントは YAML フロントマターの `type` フィールドで種別を定義します（Steering Documents は `type: steering`、運用ドキュメントは `type: project`）。`/doc sync` は `type: steering` と `type: project` のドキュメントを識別し、すべてを正規化します。`workflow.md`（`type: project`）もその対象です。各 Skill は条件付きでこれらのドキュメントを参照し、存在しない場合はスキップします（後方互換性）。`/doc sync --deep` はコードベース分析（エントリーポイント、依存グラフ、テストファイル、コメント/docstring）と既存 .md ファイルの統合スキャン（4 パターン分類、吸収対象判定）を含む拡張逆生成オプションを実行します。`/doc init --deep` と `/doc {doc} --deep` は新規作成時に同等のインライン分析を行い、質問フローを介さずにドラフトを自動生成します。`/doc translate {lang}` は英語ドキュメント（README.md、Steering Documents、Project Documents）の翻訳を指定言語（BCP 47 / ISO 639-1 言語コード。例: `ja`、`ko`、`zh-cn`）で `docs/{lang}/` および `README.{lang}.md` に生成し、自動でコミット・プッシュします。詳細: [`skills/doc/SKILL.md`](../../skills/doc/SKILL.md)

`/audit drift` は Steering Documents + Project Documents とコードベース実装の間の意味的な乖離を AI が検出し、コード側修正の Issue を自動生成します。`/doc sync`（ドキュメント側修正）と相補的に機能します。`/audit fragility` はプロジェクト文脈における構造的に脆弱な箇所（Core モジュールのテスト欠落、Architecture Decision 違反など）を検出し、リスク改善 Issue を生成します。`/audit`（引数なし）は drift + fragility の両観点を統合実行します。詳細: [`skills/audit/SKILL.md`](../../skills/audit/SKILL.md)

### 1. Issue 作成フェーズ — `/issue`

Issue の要件を明確化します。新規作成（`/issue "title"`）と既存 Issue の精査（`/issue 123`）の 2 モードがあります。曖昧性検出、受入条件の分類、verify command の割り当て、サブ Issue への分割を行います。`triaged` ラベルのない既存 Issue を精査する際には triage の実行を自動で連鎖し、単独の Issue であれば 1 回の `/issue` で triage + Issue 作成の双方が完了します。詳細: [`skills/issue/SKILL.md`](../../skills/issue/SKILL.md)

**`/issue` と `/spec` の責務境界**: [docs/product.md — 責務境界表](product.md#spec-design-boundary)

### 2. 仕様フェーズ — `/spec`

Issue の要件からコードベースを調査し、Spec（`docs/spec/issue-N-short-title.md`）を作成します。設計完了時に Size→ワークフロールーティングを行い、Size に応じた次アクション（`/code --patch` / `/code`）を提示します。`--light` は軽量設計（曖昧性解消・不確実性検出・セルフレビュー等を省略）、`--full` はフル設計。オプション省略時は Size ラベルから自動判定（M → `--light`、L/XL → `--full`）。詳細: [`skills/spec/SKILL.md`](../../skills/spec/SKILL.md)

### 3. 実装フェーズ — `/code`、`/auto`

実装の選択肢は 3 つ:
- **GitHub Copilot**: Issue で "Assign to Copilot" を選択
- **Claude Code**: `/code 123` でローカル実装（Size ベースのルーティング: XS/S→patch=main へ直接コミット、M/L→pr=ブランチ+PR）、`/auto 123 [--patch|--pr] [--review=full|--review=light]` で Size ベースのルーティング付きエンドツーエンド実行（`phase/ready` 未設定時は spec を自動実行。`phase/*` ラベル未設定時は Issue 精査から開始。patch XS/S: spec（必要時）→code→verify、pr: spec（必要時）→code→review（M→--light、L→--full）→merge→verify、XL: サブ Issue の依存グラフを読み取り並列実行、各サブ Issue で spec を自動実行）。`/auto --batch N` はバックログから XS/S の Issue を新しい順に N 件一括処理
- **手動**: ユーザーが手動で実装

`/code` は `--patch`/`--pr` フラグによる明示的な経路指定をサポート。patch 経路（XS/S）は PR を作成せず main へ直接コミット・プッシュ。

**リリースブランチワークフロー（`--base` オプション）**: 複数 Issue の変更をリリース前にリリースブランチ（例: `release/v2.0`）へ集約する場合に `--base` オプションを使用。

```
# リリースブランチを作成
git checkout -b release/v2.0 main
git push origin release/v2.0

# 各 Issue を release/v2.0 ベースで実装
/code 123 --base release/v2.0
/auto 124 --base release/v2.0

# 最終マージ: release/v2.0 → main は標準の /code → /review → /merge フローで扱う
```

`--base` が main 以外のブランチを指す場合、`closes #N` は Issue を自動クローズしない（GitHub はデフォルトブランチへのマージ時にのみ動作）。`release/v2.0` を main に最終マージするタイミングで手動で Issue をクローズするか、`gh issue close` を手動実行。

**Spec 参照**: 実装中は `docs/spec/issue-N-short-title.md` に保存された Spec を参照。Spec には対象ファイル、実装ステップ、検証方法が含まれる。Spec が存在しない場合は Issue 本文から要件を読み取る。

詳細: [`skills/code/SKILL.md`](../../skills/code/SKILL.md)、[`skills/auto/SKILL.md`](../../skills/auto/SKILL.md)

### 4. レビューフェーズ — `/review`

PR の受入条件検証、多観点のコードレビュー、Issue 対応を統合。MUST 指摘は `/merge` に進む前に自動修正。詳細: [`skills/review/SKILL.md`](../../skills/review/SKILL.md)

**レビューモード**: Size に基づいて自動判定（Project フィールド優先 → ラベルフォールバック）。`--light`/`--full` で明示指定も可能。

| Size | レビューモード | 挙動 |
|------|----------------|------|
| XS, S | skip（早期終了） | "レビュー不要" メッセージで終了（patch 経路） |
| M | light | Step 9 を軽量統合レビューとして実行（1 エージェント） |
| L, XL | full | 全ステップを実行 |

**外部レビューツール連携**: プロジェクトルートに `.wholework.yml` を作成して値を設定することで有効化（デフォルトはすべて無効）:

```yaml
# .wholework.yml
copilot-review: true        # GitHub Copilot レビューを有効化（Step 6 で待機し指摘を処理）
claude-code-review: true    # Claude Code 公式レビューを有効化（Step 6 で待機し指摘を処理）
coderabbit-review: true     # CodeRabbit AI レビューを有効化（Step 6 で待機し指摘を処理）
review-bug: false           # Step 9 の review-bug エージェントを無効化（review-spec のみ実行）
```

`.wholework.yml` が存在しない場合、すべての設定はデフォルト（無効）として扱われる。

**`--review-only` オプション**: `/review {PR 番号} --review-only` はレビュー投稿（Step 10）で停止し、修正（Step 11–13）をスキップ。修正はユーザーまたは Copilot に委譲。`phase/review` ステータスラベルは変更されない。

### 5. マージフェーズ — `/merge`

squash マージを実行し、リモートブランチを削除。コンフリクトがある場合は自動解決を試みる。詳細: [`skills/merge/SKILL.md`](../../skills/merge/SKILL.md)

### 6. 受入テストフェーズ — `/verify`

マージ後の受入条件を自動検証。すべての条件が PASS ならフロー完了、FAIL 時は `gh issue reopen` で修正サイクルに戻る。全フェーズに対してクロスフェーズのレトロスペクティブレビューを行い、コード改善は常に Issue を作成。Skill 基盤（Wholework）改善の Issue は `.wholework.yml` の `skill-proposals: true` の場合にのみ作成。詳細: [`skills/verify/SKILL.md`](../../skills/verify/SKILL.md)

## Skill 一覧

Skill 一覧は [README.md](../../README.ja.md) を参照。

## エージェント基盤

エージェント基盤（agents/、modules/ の一覧と配置）は [docs/structure.md](structure.md) を参照。

## 進捗管理（ラベルベース）

`phase/*` ラベルを用いて Issue の進捗を可視化。各 Skill はワークフローの進行に応じてラベルを自動管理。

セットアップ: `scripts/setup-labels.sh` でラベルを作成。

### ラベル遷移マップ

| ラベル | 意味 | 付与者 | 削除者 |
|--------|------|--------|--------|
| `phase/issue` | Issue 作成フェーズ | `/issue` | `/spec` |
| `phase/spec` | 仕様フェーズ | `/spec`（開始時） | `/spec`（spec push 後） |
| `phase/ready` | 設計完了、実装待ち | `/spec`（design push 後） | `/code` |
| `phase/code` | 実装フェーズ | `/code` | `/review` |
| `phase/review` | レビューフェーズ | `/review` | `/merge` |
| `phase/verify` | 受入テストフェーズ | `/merge` | `/verify` |
| `phase/done` | 完了 | `/verify`（post-merge 条件なしの場合） | — |
| （ラベルなし） | バックログ / 未開始 | — | `/verify`（FAIL 時） |

### XL 親 Issue のフェーズ管理

XL（サブ Issue 分割）親 Issue は、子 Issue の進捗に基づいてフェーズが自動集約。

| 子の状態 | 親のフェーズ | 備考 |
|----------|--------------|------|
| 1 件以上の子が `phase/code` 以降 | `phase/code` | 実装中 |
| すべての子が `phase/verify` 以降 | `phase/verify` | 検証待ち |
| すべての子が `phase/done` + 親条件なし | `phase/done` + close | 自動クローズ |
| すべての子が `phase/done` + 親条件あり | `phase/verify` | クローズ前に `/verify` で最終確認 |

集約更新は `/auto` の XL オーケストレーションの各レベル完了時に実行。

### `closes #N` による標準フロー

PR 本文に `closes #N` を付けると、マージ時に Issue が自動クローズ（GitHub 標準機能）。

```
/code: PR 本文に `closes #N` を追加
  ↓
/merge: マージ → Issue が自動クローズ
  ↓
/verify: クローズ済み Issue を検証
  - PASS → 完了（phase/verify ラベルを削除）
  - FAIL → gh issue reopen + phase/* をすべて削除 → 修正サイクルに戻る
```

### Triage 関連ラベル

| ラベル | 意味 | 付与者 |
|--------|------|--------|
| `triaged` | Triage 済み | `/triage` |
| `type/bug` | 種別: bug | `/triage` |
| `type/feature` | 種別: feature | `/triage` |
| `type/task` | 種別: task | `/triage` |

`/triage` は `phase/*` とは独立して管理（ワークフロー外のユーティリティ Skill）。`/triage --backlog`（観点指定なし）は未処理の一括 triage に加え、4 観点すべての深層分析を統合実行。観点を指定した場合（例: `--backlog value`）はその観点の分析のみを実行し、`triaged` は付与しない。各観点の適用前に承認フローが表示。詳細: [`skills/triage/SKILL.md`](../../skills/triage/SKILL.md)

### Audit 関連ラベル

| ラベル | 意味 | 付与者 |
|--------|------|--------|
| `audit/drift` | `/audit drift` が検出した乖離の修正 Issue | `/audit` |
| `audit/fragility` | `/audit fragility` が検出した構造的脆弱性の改善 Issue | `/audit` |

### Projects 連携

`.github/workflows/kanban-automation.yml` は `phase/*` ラベルによる Kanban カラムの自動移動を実装。`phase/issue`、`phase/spec` → Plan、`phase/ready` → Ready、`phase/code` → Implementation。Review/Verification/Done は Projects のビルトインオートメーションを使用。

## ドキュメント同期ルール

ドキュメント構成:
- `docs/workflow.md` — 開発ワークフロー概要（フェーズ詳細、ラベル遷移、進捗管理）
- `docs/product.md` — プロジェクトビジョン、フロー図、Terms（用語集）
- `docs/tech.md` — 技術スタック、コーディング規約、禁止表現
- `docs/structure.md` — ディレクトリ構成、エージェント基盤

**ルール**: Skill の追加・変更・削除などワークフローに影響する変更を行う場合は、`docs/workflow.md` と `README.md` も併せて更新。

理由: 実装とドキュメントを常に同期させ、ワークフロー全体像の正確性を保つため。2 つのファイルは想定読者が異なる（人間 / Claude Code）ため、双方を同期する必要がある。

**Key Files テーブル同期ルール**: `docs/structure.md` の Key Files テーブルに記載されているファイルの役割・説明が変わった場合や、ファイルの追加・削除・リネームが発生した場合には、`docs/structure.md` の Key Files テーブルも更新。

## 関連ドキュメント

- [CLAUDE.md](../../CLAUDE.md) - グローバルガイドライン
- [README.md](../../README.ja.md) - セットアップと Skill 一覧
- [docs/product.md](product.md) - プロジェクトビジョン、フロー図
- [docs/tech.md](tech.md) - 技術スタック、コーディング規約
- [docs/structure.md](structure.md) - ディレクトリ構成、エージェント基盤
