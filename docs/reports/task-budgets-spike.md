English | [日本語](../ja/reports/task-budgets-spike.md)

# Task Budgets (Beta) Spike: Evaluation for Wholework `/auto`

**Report date**: 2026-04-18
**Issue**: #222
**Scope**: Evaluate whether `task-budgets-2026-03-13` beta can be adopted in `/auto` and `run-*.sh`

---

## Setup

### 認証方式の前提

Wholework の `run-*.sh` は `claude -p --dangerously-skip-permissions` を使い、**OAuth / サブスクリプション認証**を既定とする。

`docs/tech.md` §Axis 3 (Advisor strategy) に既存の記録があるとおり、Anthropic API beta ヘッダーは **API key ユーザー専用**であり、OAuth / サブスクリプション認証では利用できない。`task-budgets-2026-03-13` についても同様の制約が当てはまる可能性があることが、今回のスパイク検証の出発点となっている。

### `task-budgets-2026-03-13` ヘッダーの有効化方法

Claude Code CLI では `--betas` フラグで beta ヘッダーを指定する:

```bash
claude -p "$PROMPT" --betas task-budgets-2026-03-13 --model sonnet --effort high
```

API 直接呼び出しの場合は `output_config.task_budget` フィールドで予算を指定する。ただし Wholework は CLI 経由でのみ Claude を呼び出すため、API 直接呼び出しのパスは存在しない。

### 検証環境

- Claude Code version: 2.1.114
- 認証方式: OAuth / サブスクリプション認証（`ANTHROPIC_API_KEY` 未設定）
- OS: macOS (Darwin 25.2.0)
- 対象スクリプト: `scripts/run-*.sh` 全般

---

## Findings

### 1. 認証制約の実機確認

以下のコマンドを OAuth 認証環境で実行した:

```bash
claude -p "echo test" --betas task-budgets-2026-03-13 --model sonnet
```

**実行結果**:

```
Warning: Custom betas are only available for API key users. Ignoring provided betas.
```

**観察**:

- Claude Code CLI は `--betas` オプションを受け付けるが、OAuth / サブスクリプション認証では**警告を出してフラグを無視する**
- エラーで終了するのではなく、beta なしで通常通り実行が継続される
- すなわち、`run-*.sh` に `--betas task-budgets-2026-03-13` を追加しても、OAuth ユーザーには**何の効果もない**（静かに無視される）

### 2. 予算設定時のモデル挙動・self-pacing

beta ヘッダーが OAuth 環境で無視されるため、**Wholework の既定認証下では self-pacing の挙動を観察できない**。

公式ドキュメント・`docs/reports/claude-opus-4-7-optimization-strategy.md` §2.3 の記載によると、task budgets はアgentic loop 全体のトークン予算（thinking + tool calls + tool results + final output）をモデルへヒントとして伝え、残予算に応じてタスク完了戦略を自律調整させる機能である。API key 認証環境での期待挙動は以下のとおり:

- 残予算が多い段階: 通常の探索的実行
- 残予算が少なくなると: モデルが戦略を切り替え、不要なツール呼び出しを省略し、確実な完了を優先
- 予算超過時: モデルがタスクを中断するのではなく、完了に向けた戦略変更を行う（エラーにはならない）

### 3. 予算超過時の挙動

公式仕様（Anthropic ドキュメント）によると、task budget はハードリミットではなく**ソフトヒント**である。モデルは予算を超えて実行を継続できるが、予算内に収めるよう self-pacing が働く。Wholework のユースケースにおける失敗モードは以下が想定される:

| ケース | 挙動 |
|--------|------|
| 予算値が小さすぎる | モデルが過度に省略し、実装品質が低下するリスク |
| 予算値が大きすぎる | self-pacing の効果がなく、コスト削減に寄与しない |
| フェーズ間での予算調整ミス | 後半フェーズ（review/verify）で予算不足が顕在化するリスク |

いずれも **API key 認証環境でのみ発生するシナリオ**であり、OAuth 認証下では検証不可。

---

## Recommendation

**結論: 非採用（現時点）**

### 技術的実現可能性

**利用不可**。OAuth / サブスクリプション認証（Wholework の既定）では `--betas task-budgets-2026-03-13` が静かに無視されることを実機で確認した。Wholework 利用者の大多数が OAuth 認証を使用しており、API key 認証への切り替えを全ユーザーに要求することは認証モデルの破壊的変更となる。

### 実効性

**不明**。Wholework の既定認証環境では機能を有効化できないため、`/auto` の長時間ワークフロー（spec→code→review→merge→verify）での self-pacing 効果を測定できなかった。Axis 1 (モデル選択) および Axis 2 (Adaptive Thinking / effort レベル) と組み合わせたときのコスト削減効果も評価不可。

### 失敗モード

- **静かな失敗**: beta フラグが無視されてもエラーにならないため、`run-*.sh` に誤ってフラグを追加した場合に気づきにくい
- **フェーズ別チューニングの困難さ**: phase 別（spec / code / review / verify）に適切な予算値を決定するには、現在のトークン使用量の実測データが必要（未取得）
- **ソフトヒントによる品質劣化リスク**: 予算が小さすぎると品質低下が発生するが、適切な値の決定には大量の実験が必要

### 導入コスト

- **コード変更コスト**: 低（`run-*.sh` 各スクリプトへの `--betas` フラグ追加のみ）
- **チューニングコスト**: 高（フェーズ別予算値の決定には反復実験が必要）
- **運用コスト**: 高（全ユーザーに API key 認証への切り替えを要求する場合）
- **総合コスト**: 現状の OAuth 認証モデルを維持しながら導入することは不可能

### 今後の条件

以下の条件が揃った場合に再評価を推奨する:

1. `task-budgets-2026-03-13` が GA（一般公開）になり、OAuth 認証でも利用可能になった場合
2. Wholework が API key 認証をオプションとしてサポートする方針になった場合（例: `.wholework.yml` の `auth: api-key` オプション）
3. Wholework 利用者の大多数が API key 認証に移行した場合

### 対比: 既存の Axis 2 (Adaptive Thinking / effort) との関係

task budgets と `--effort` フラグは補完的な機能である。`--effort` はモデルの思考深度を制御するのに対し、task budgets は思考量の上限をトークンで指定する。現時点では `--effort` のみで Axis 2 の最適化が実現されており、task budgets が GA になるまでこのアプローチで十分と判断する。

---

## 参考資料

- Claude Code CLI `--help`: `--betas` オプションに "API key users only" の記載を確認（version 2.1.114）
- `docs/reports/claude-opus-4-7-optimization-strategy.md` §2.3 — task budgets の位置付け（C8）
- `docs/tech.md` §Architecture Decisions §Axis 3 — Advisor strategy の先行事例（同様の認証制約）
- `docs/tech.md` §Architecture Decisions §Axis 2 — 現行の `--effort` による最適化実装
