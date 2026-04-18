[English](../../reports/ultrareview-spike.md) | 日本語

# Ultrareview スパイクレポート: `/review --ultra` オプション評価

**作成日**: 2026-04-18
**作成者**: 自動スパイクセッション (Issue #223)
**対象範囲**: Claude Opus 4.7 の `/ultrareview` を Wholework `/review` の `--ultra` 深度モードとして評価
**状態**: 結論済み — Recommendation セクション参照

---

## 概要

Claude Opus 4.7 には、リモートクラウドサンドボックス上で深層マルチエージェントコードレビューを実行する組み込み Claude Code コマンド `/ultrareview` が導入された。本スパイクでは、この機能を Wholework `/review` の新しい `--ultra` モードとして公開し、既存の `--full`（3 並列：review-spec/Opus + review-bug×2/Opus + 2 段階検証）を置換または補強すべきかを評価する。

参照: `docs/reports/claude-opus-4-7-optimization-strategy.md` §2.3、§5.3 #9。

**調査手法**: 以下の公式ドキュメントを WebFetch で取得：
- `https://www.anthropic.com/news/claude-opus-4-7`
- `https://code.claude.com/docs/en/commands`
- `https://code.claude.com/docs/en/ultrareview`

---

## Comparison

### `/ultrareview` (組み込みコマンド) vs Wholework `/review --full`

| 軸 | `/review --full` (Wholework) | `/ultrareview` (組み込み) |
|------|------------------------------|---------------------------|
| **アーキテクチャ** | 3 つの Opus エージェントを並列起動 (review-spec + review-bug×2) + 2 段階 bug 検証サブエージェント | リモートクラウドサンドボックス上のレビュアーエージェント群; 各検出結果は独立して再現・検証 |
| **所要時間** | 3〜8 分 (ローカル、並列 Opus) | 5〜10 分 (リモートバックグラウンドタスク) |
| **コスト** | プラン利用枠を消費 (Opus 4.7 料金で一般的な PR あたり約 $1〜3) | 3 回無料 (Pro/Max 初回のみ); 以降はレビューあたり $5〜20 が追加課金 |
| **カバレッジ** | 仕様逸脱 + ドキュメント整合性 + HIGH SIGNAL bug + セキュリティ問題 | bug 重視 ("find bugs in your branch or PR") |
| **偽陽性削減** | 専用検証サブエージェントによる 2 段階検証 | エージェント群による独立再現・検証 |
| **呼び出し方法** | `run-review.sh` / `/auto` パイプラインから自動化 | ユーザー呼び出しのみ (`/ultrareview`); Claude が自動起動することはできない |
| **認証要件** | 標準 Claude Code (API key またはサブスクリプション) | Claude.ai サブスクリプション必須; API key のみ / Bedrock / Vertex AI / Foundry では利用不可 |
| **ローカルリソース使用** | ローカルの Claude Code セッションリソースを使用 | 完全リモート実行; ターミナルは占有されない |
| **設定** | `--light` / `--full`、`.wholework.yml` の `review-bug: false`、SKIP_REVIEW_BUG | なし (PR 番号のみ) |
| **自動化互換性** | 完全自動化可能 (`claude -p` 互換) | 手動のみ; ユーザー確認ダイアログ必須; バックグラウンドタスク |

### 品質

Anthropic 公式ドキュメントは `/ultrareview` の特徴を次のように説明している：
- "Higher signal: 各検出結果は独立して再現・検証される"
- "Broader coverage: 多数のレビュアーエージェントが並列で変更を探索する"

Wholework `/review --full` は既に以下を実装済み：
- 並列マルチエージェント検出 (3 つの Opus エージェント)
- 偽陽性フィルタのための 2 段階検証 (review-bug → 検証サブエージェント)

そのため、Wholework の `--full` と `/ultrareview` の間のアーキテクチャ的ギャップは、単純な単発レビュアーと比較した場合より狭い。主な不明点は、`/ultrareview` のエージェント群サイズとクラウドサンドボックス隔離が Wholework 型の PR (Markdown/Shell/YAML 変更) に対して実質的に多くの bug を検出するかどうかである。公式ドキュメントにベンチマーク数値の開示はなく、直接比較には同一 PR に両方を実行する必要がある。

### コスト

- Wholework `/review --full`: 一般的な PR あたり約 $1〜3 (Opus 4.7 エージェント 3 並列; プラン利用枠を消費)
- `/ultrareview`: 無料回数消化後はレビューあたり $5〜20 の追加課金 (10〜20 倍のコスト増)

全 PR でレビューを自動実行するパイプラインにとってコスト差は大きい。

---

## Recommendation

**非採用 (`--ultra` モードとしての導入は見送り)**

### 主要な理由: 自動化非互換

`/ultrareview` は明示的にユーザー呼び出し専用である — Anthropic 公式ドキュメントには "The command runs only when you invoke it with `/ultrareview`; Claude does not start an ultrareview on its own." と明記されている。これは Wholework の `/auto` パイプライン (spec→code→review→merge を `run-review.sh` 経由で非対話的に連結) と根本的に非互換である。現行の `/ultrareview` インタフェースでは、`--ultra` を自動化モードとして追加することは技術的に実現不可能。

### 補足理由

1. **コスト**: レビューあたり $5〜20 (追加課金) 対 `--full` の約 $1〜3。10〜20 倍のコスト増を正当化するには、定常 CI / auto 実行での品質向上が実質的かつ計測可能である必要がある。

2. **プログラマティック API 不在**: `/ultrareview` はフラグ・設定・フックを一切公開していない。Wholework からリモートレビュー群に context (Spec パス、steering documents、Issue 受入条件) を渡す手段がない — この context こそが Wholework の `--full` モードを汎用レビューではなくプロジェクト固有レビューにしている要素である。

3. **認証制約**: Wholework は API key のみの利用者 (Bedrock、Vertex AI 等) にも対応している。`/ultrareview` はこれらの構成では利用不可であるため、`--ultra` は「一部環境でのみ動作」機能となり、条件分岐とユーザー向けエラーメッセージが必要になる。

4. **アーキテクチャの重複**: Wholework `--full` は既に並列 Opus エージェントと独立検証を使用している。`/ultrareview` のアーキテクチャ上の優位性は Wholework 利用者にとって目新しいものではなく、ギャップは質的ではなく量的 (エージェント群サイズ、クラウド隔離) にとどまる。

5. **Spec / context の統合**: Wholework のレビュー品質は、PR を Spec / steering documents / Issue 受入条件と照合することに由来する。`/ultrareview` にはこのプロジェクト context を注入する仕組みがないため、Wholework の context aware なレビューのドロップイン代替としては不適格。

### 代替案 (実装コストゼロ)

利用者が `--full` を超えるマージ前の確証を求める場合、Wholework の完了レポートで `/ultrareview` を任意の手動ステップとして言及すれば良い：

> "マージ前にさらなる確認が必要な場合は、Claude Code セッションで `/ultrareview <PR 番号>` を実行してください (Pro/Max、3 回無料、以降は追加課金)。"

これで統合作業ゼロのまま機能を露出でき、`--full` の完全自動化は維持される。

### 再評価の条件

以下のいずれかが満たされれば再評価する：
- Anthropic が `/ultrareview` を非対話的にトリガするプログラマティック API または CLI フラグを公開する (`/auto` 統合が可能になる)
- ベンチマーク結果が、Markdown/Shell/YAML PR において `/ultrareview` が `--full` より顕著に多くの Wholework 関連 bug を検出することを示す
- コストが `--full` モードの 2〜3 倍以内に収まる

---

## Appendix: 調査ノート

**情報の確度**: `/ultrareview` の詳細はすべて Anthropic 公式ドキュメント (2026-04-18 取得) に基づく。公式ドキュメントでは具体的な使用モデル、エージェント群サイズ、クラウドサンドボックスの内部実装は開示されていない。コスト帯 ($5〜20) と "5〜10 分" の所要時間は公式ドキュメントに直接記載されている値。

**Tokenizer 注意**: 本スパイクは Opus 4.7 の新 tokenizer (最適化戦略 §2.1 で示された 1.0〜1.35× のトークン数増加) 下における Wholework のエンドツーエンドベンチマークに先行している。上記 `--full` のコスト見積りは新 tokenizer 下で最大 35% 増加する可能性があるが、本結論には影響しない。
