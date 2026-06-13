[English](../../reports/wholework-positioning-memo-2026-06-13.md) | 日本語

# Wholework Positioning Memo — 2026-06-13

**作成日**: 2026-06-13
**作成者**: ユーザー対話セッション（Fable 5 ローンチ/停止 → /auto セッションパフォーマンス分析 → Nuxt→Next 着手準備の流れ）
**ステータス**: 戦略メモ — 確定仕様ではなく、判断と凍結項目の文脈保存
**関連レポート**:
- `docs/reports/claude-fable-5-impact-strategy.md`（Fable 5 影響分析）
- `docs/reports/auto-session-performance-2026-06-13.md`（14 Issue 連続実行の実証データ）
- `docs/reports/workflow-adapter-spike.md`（dynamic workflow 採否判断）

## 1. 目的とスコープ

本メモは 2026-06-13 のユーザー対話から得られた **Wholework の戦略的 positioning と凍結項目の文脈** を保存する。Issue や Spec に分散して入りきらない判断ロジック・スペクトル把握・境界宣言を集約する場所。

含めるもの:
- Wholework が最も価値を出すアンカーユースケースの定義
- 問題形状のスペクトル整理（Stripe-class fleet / Wholework mid-scale / interactive single-task）
- 5 つの典型 migration パターンと分類
- Managed Agents + Outcomes との補完関係
- 明示的 out-of-scope 宣言
- 派生 Issue 索引（#583–#591）
- Icebox 候補と再評価トリガー
- メモ自身の改訂規律

含めないもの:
- 個別実装の詳細（各 Issue に委ねる）
- ベンチマーク数値（`auto-session-performance-2026-06-13.md` へ）
- Fable 5 移行戦略（`claude-fable-5-impact-strategy.md` へ）

## 2. Anchor Use Case — mid-scale modernization

Wholework が**最も明確に価値を出す**作業帯域:

| 軸 | 範囲 |
|---|---|
| 予算 | 最大 $10,000 / 案件 |
| 期間 | 数日〜2 週間（10 日が標準） |
| 規模 | 50〜100 PR / 案件 |
| 並列度 | 5〜10 concurrent（ローカル + サブスク認証の実機天井） |
| 案件タイプ | framework migration、major version upgrade、test coverage backfill、library upgrade、CMS migration（hybrid） |

具体例（ユーザーの実務領域、大規模コーポレート/EC サイト）:

1. **Nuxt.js → Next.js 全面置換**（Pattern B fan-out + foundation 段階）
2. **Astro バージョン +1**（Pattern A 逐次、単発 L サイズ）
3. **Rails メジャー +2 + Ruby +1**（Pattern A 直列、phase 分割）
4. **API テストカバレッジ追加**（Pattern B 純粋 fan-out）
5. **Contentful → Sanity CMS 移行**（Pattern C hybrid: コード + data fleet）

アンカー数値: $10K × 10 日 × 5 案件/年 × 1 開発者 = **$50K 規模 / 年 / 1 開発者**。エージェンシーが年 4-6 案件回せば $200-300K の予算規模。商用としても明確にハマるサイズ。

## 3. 問題形状のスペクトル

3 つの異なる問題形状があり、それぞれに適したツールが異なる:

| 形状 | 規模 | ツール |
|---|---|---|
| **Stripe-class fleet** | 50M LOC を 1 日 / 100+ 並列 / 同型変換 / 無制限予算 | API 直叩き fleet infrastructure（自社構築 or Anthropic Managed Agents Outcomes） |
| **Wholework mid-scale** | 50-100 PR を 10 日 / 5-10 並列 / 異質性高 / governance 必須 / $10K | **Wholework** |
| **Interactive single-task** | 1-5 ファイル / 数時間 / 対話的 IDE 支援 | Claude Code 対話セッション、Cursor 等 |

ハンマーが鋸ではないのと同じで、これは Wholework の欠陥ではなく専門化。

Stripe-class への過剰投資（fleet 化）は moat を壊す: subscription auth の所有感が消える、Anthropic ホスト依存になる、Managed Agents の劣化版になる。

### Wholework の moat（governance + verification harness）

`/auto` 14 Issue 連続実行（2026-06-13 セッション）で実証された:

- **自己診断 / 自己修復ループ** — `/auto` で発生した問題 → retrospective → 改善 Issue → 同セッション内で実装 → クローズ が **10 時間以内**で完結
- **GitHub-native artifacts** — チームが既に生活している Issue/PR/Label/review thread が成果物
- **subscription / OAuth 認証** — `claude -p` がユーザーのサブスクで動く（fleet infrastructure 不要）
- **段階的採用** — `/review` だけ、`/verify` だけの adoption が可能
- **人間 gate ファーストクラス** — PR review、AC 確認、retrospective が人間の判断を組み込む

Anthropic の Fable 5 運用ガイダンス（「memory surface を与えよ / 検証 harness を回せ / 境界を明示せよ」）が Wholework の設計思想と一行ずつ一致する事実は偶然ではない。

## 4. 5 Migration Pattern の分類

| Pattern | 特徴 | 対応例 | 必要なツール |
|---|---|---|---|
| **A. 逐次アップグレード** | 順序依存・コード変更のみ・breaking change 連鎖 | Astro +1、Rails メジャー +N、Ruby +N | 既存 Wholework（Issue 直列 + CI 通過確認） |
| **B. fan-out 移行** | 同型変換が page/endpoint 単位で並列化可能・コード変更のみ | Nuxt→Next、API テスト追加 | XL 並列実行 + #589 concurrency cap + #590 progress + #591 bulk creation |
| **C. hybrid 移行** | コード変更 + 外部 data fleet job + 観測長期化 | CMS migration（Contentful→Sanity、レコード移行） | Wholework がコード部分を担当、data fleet 部分は外部 script で実行し AC として「script 完走 + 検証 pass」を受け止める |

Pattern C は Wholework が単独で完結しない例。**Wholework は migration project の指揮者** として、コードは自分でやり、fleet 部分は外部 script に委譲し、長期観測を observation AC で追跡する。

## 5. Managed Agents + Outcomes との補完関係

Anthropic の **Managed Agents + Outcomes**（rubric 採点ループ）は Wholework に概念収束している部分があるが、棲み分けは明確:

| 観点 | Wholework | Managed Agents + Outcomes |
|---|---|---|
| 単位 | Issue / PR（複数） | Outcome / Session（単一） |
| 期間 | 数日〜2 週間 | 数時間〜1 日 |
| 監査証跡 | GitHub Issue/PR/Label/retro（永続・公開） | Session log（Anthropic ホスト） |
| 認証 | Subscription / OAuth | API key |
| 反復 | 各 Issue で人間 gate + retrospective が累積 | 自律 rubric grading + revise loop |
| 適性 | 異質・段階的・governance 必須 | 同型・fleet 的・単一ゴール |

両者は競合ではなく **異なる時間スケールと異なる作業形状** に最適化されている。Pattern C（hybrid CMS 移行）では実際に共存しうる: Wholework が Sanity スキーマ設計とフロント書き換えを担当、Managed Agents Outcome が data 移行を一括実行する協調パターン。

## 6. 明示的 Out-of-Scope（Non-Goals 拡張候補）

以下は Wholework の **拡張対象としない** 戦略的判断:

1. **Fleet-class 100+ 並列実行** — Managed Agents Outcomes の領域。subscription auth の moat を壊す
2. **Interactive single-task UI 補助** — Claude Code 対話セッション or Cursor 等の領域
3. **CI/CD pipeline 完全代替** — Wholework は CI を「verify の入力」として使うが、自前で workflow runner を持たない
4. **monorepo cross-package orchestration の組み込み** — package manager に委譲（pnpm workspace 等）
5. **モバイルアプリ store 提出フロー** — Wholework は GitHub 中心、Fastlane 等外部ツールに委譲

これらは `docs/product.md § Non-Goals` への追記候補だが、本メモで先行宣言する。

## 7. 派生 Issue 索引（2026-06-13 セッションで起票）

### Fable 5 影響分析シリーズ（#555–#563, #565, #575, #576, #579–#582）

詳細は `docs/reports/claude-fable-5-impact-strategy.md` および各 Issue 参照。本セッションで全件 CLOSED 済み。

### `/auto` セッションパフォーマンス分析シリーズ（#583–#588）

| # | 内容 | Status |
|---|---|---|
| #583 | `verify-type: observation` 分類導入 | OPEN, retro/verify |
| #584 | triage AC verify command audit 体系化 | OPEN, retro/verify |
| #585 | watchdog phase 別 timeout | OPEN, retro/verify |
| #586 | `/code` Tier 0 リカバリ（test 失敗の自動修復） | OPEN, retro/verify |
| #587 | Opus 4.8 親セッション perf spike | OPEN, retro/verify |
| #588 | audit-stats retention metrics（blocked by #583） | OPEN, retro/verify |

### Nuxt→Next 着手前 prerequisite（#589–#591）

| # | 内容 | 効くタイミング |
|---|---|---|
| #589 | XL sub-issue 並列度キャップ（`auto-max-concurrent`） | 毎実行（並列度の安全網） |
| #590 | `/audit progress <XL>` 進捗スナップショット | 10 日間の運用全期間 |
| #591 | XL sub-issue 一括起票（YAML → bulk create） | 初日（4-8h typing 削減） |

## 8. Icebox 候補（凍結中、再評価トリガー付き）

以下の改善候補は今回意図的に Issue 化を見送った。GitHub Project の **Icebox status** に該当 Issue を起票し、再評価トリガーで管理する:

| 候補 | 凍結理由 | 再評価トリガー |
|---|---|---|
| **Migration template 集**（`framework-migration.md` 等） | 1 件目の Nuxt→Next 走らせて経験から作る方が良い。先回りすると現場とズレる | Nuxt→Next 完了後 |
| **完全 auto-decomposition**（LLM が codebase 解析→YAML 自動生成） | 大規模実装。#591 の YAML manual minimum で十分か実走で測る | #591 着地 + 1 案件運用後 |
| **コスト計測機構** | $10K/10 日は post-hoc 確認で足りる。実装コスト > 価値 | budget が tight な案件が出たとき |
| **Adaptive throttling**（concurrency 動的調整） | #589 fixed cap で実走データを取ってから | #589 + 1 XL 実走後 |
| **External-job primitive**（data fleet 連携 adapter） | Pattern C（CMS 移行）で必要、Pattern A/B では不要 | Contentful→Sanity 案件着手時 |
| **`/auto` 子フェーズ in-session 化**（spawn-and-block → 非同期） | #587 計測結果次第。Fable 5 復帰後に再評価 | #587 結論後 + Fable 5 復帰後 |
| **`docs/product.md` anchor case 正式追記** | 実走 1 件のデータがあった方が説得力ある | Nuxt→Next 完了後 |

Icebox 起票時の規約:
- Project Status を `Icebox` に明示設定（`Backlog` 自動遷移を避ける）
- `retro/verify` ラベル付与
- 本文に「凍結理由」「再評価トリガー」「派生元（本メモへのリンク）」を最低 3 セクション
- 四半期 1 回見直し（`/audit stats` で Icebox 滞留 90 日超を可視化 — #588 retention metric の応用）

## 9. ベンチマーク指標の再定義

Stripe-class の「LOC/日」指標は Wholework と異なる作業形状なので、自分の指標を持つべき:

| 指標 | 説明 | 2026-06-13 セッション実測 |
|---|---|---|
| **監査可能 PR / 日** | 完了し monitored / verified された PR | 約 1.3 PR/h（14 Issue / 11h） |
| **自己改善ループ閉時間** | 問題発生 → 改善 Issue → 消化までの時間 | 10 時間以内（#557 → #569） |
| **triage 修復率** | triage 段で verify command 欠陥を捕まえた割合 | 3/14 = 21% |
| **autonomous 完走率** | wrapper 完走 / 親セッション手動介入なし | 13/14 = 93% |
| **観測 AC 滞留期間** | phase/verify 滞留中央値（#588 で可視化予定） | TBD |

これらは「Wholework は何を最適化するシステムか」を示す **moat 指標**。

## 10. 改訂規律

本メモは **マイルストーン後に改訂** する:

- Nuxt→Next 完了後: anchor case の数値検証 + Icebox 再評価 + Pattern B の実証データ追記
- 各四半期: Icebox 滞留 90 日超の見直し
- Fable 5 復帰後: `docs/reports/claude-fable-5-impact-strategy.md` Suspension Notice 削除と連動して本メモも更新
- Anthropic 新製品リリース時: Managed Agents 等との境界宣言を再検証

改訂時はファイル名に日付を残す（`wholework-positioning-memo-2026-XX-XX.md`）。差分が読める形を維持し、過去判断のロジックを失わない。

## 11. 派生する次のアクション

本メモ commit 後、以下を順に実施:

1. **Icebox Issue 7 件起票**（§8 の候補、本メモを参照リンク付き）
2. **Auto memory 3 件追加**（anchor case / problem shape / Icebox index）
3. **`/audit stats` で Icebox 滞留可視化の計画**を #588 retention metric に組み込む（#588 本文への追記コメント）

ユーザー対話セッションの戦略的論理が、これで 3 つの永続化チャネル（report / Issues / memory）に冗長配置される。

---

*本メモは戦略メモ report であり、`docs/product.md` 等の Steering Document が SSoT である項目には介入しない。確定戦略は Steering Document へ昇格し、本メモは「昇格前の判断ロジック保存場所」として機能する。*
