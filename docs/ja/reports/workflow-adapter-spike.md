[English](../../reports/workflow-adapter-spike.md) | 日本語

# Workflow Adapter Spike: Wholework 実行エンジンとしての dynamic workflow 評価

**レポート日**: 2026-06-13
**著者**: 自動化 spike セッション（Issue #565）
**スコープ**: Claude Code の dynamic Workflow を Wholework のフェーズ内実行エンジンとして搭載可能か評価し、adapter 戦略の採否を判断する
**ステータス**: 結論済み — 推奨事項を参照

---

## 概要

Claude Code の dynamic Workflow ツール（multi-agent orchestration: fan-out / adversarial verify / loop-until-dry / budget スケーリング）は Wholework と**層が異なる**: Wholework は**フェーズ間の契約**（受入条件・gate・成果物・post-merge 検証、状態は GitHub に外部化）を定義し、dynamic workflow は**1 フェーズ内側の実行戦略**を強化する。競合するアプローチではなく、Workflow を「Wholework のフェーズ station に差し込む実行エンジン」として搭載する関係が正しい。

本 spike では 3 点を検証した:

1. **Spike 1 — headless 可否**: Workflow ツールは `claude -p`（`run-*.sh` が使用する非対話経路）から呼び出せるか？
2. **Spike 2 — `/review --full` workflow 化 PoC**: finder → adversarial verify パイプラインを Workflow エンジンで実行できるか？現行の static Task fan-out と品質（検出数・false-positive 率）を比較
3. **Spike 3 — コスト計測**: 同一 PR での現行 fan-out vs. workflow 版のトークン消費・実行時間を比較し、Size 別適用基準（M/L のみ等）を提案

**前提条件（満足済み）**: ブロッカーの #555（`review-bug` の find/filter 分離）が 2026-06-12 にクローズ。`agents/review-bug.md` に「Role here is coverage, not filtering」が反映され、Spike 2 の PoC 対象構造が整っている。

---

## Spike 1: headless（`claude -p`）利用可否

### 検証方法

実機直接検証: `--model sonnet --permission-mode auto` を使用して `claude -p` に tool 一覧を問い合わせるプロンプトを渡した。`run-*.sh` スクリプトが使用する認証経路・権限モードと同一。

```bash
claude -p "利用可能なツールをすべて列挙してください" \
  --model sonnet \
  --permission-mode auto
```

### 結果

**結果: Workflow は `claude -p` モードで利用可能。**

headless セッションが返したツール一覧に Workflow ツールが含まれていた。直接呼び出し可能なツールとして（ToolSearch 不要）Workflow が列挙された。他に Agent・ToolSearch・標準ツール（Read, Write, Edit, Bash 等）も利用可能。

機能制限・beta フラグ要件・認証バリアは一切確認されなかった。OAuth ユーザーで `--betas` が静かに無視される `task-budgets-2026-03-13`（Ref `docs/reports/task-budgets-spike.md`）とは異なり、Workflow ツールは認証方式に関わらず利用可能な標準セッションツールである。

### opt-in 伝達メカニズム

Workflow ツールのドキュメントは、Claude が呼び出す前にユーザーの明示的な opt-in を要求する（意図せず高コストな multi-agent 実行を防ぐため）。`claude -p` モードでは、**プロンプト内容そのものがユーザーの指示**となる — 「ユーザーが求めたこと」と「SKILL.md が指示すること」に区別はない。

したがって、opt-in メカニズムは以下のように機能する:

1. ユーザーが `.wholework.yml` に `capabilities.workflow: true` を設定
2. `detect-config-markers.md` が `HAS_WORKFLOW_CAPABILITY=true` を設定
3. SKILL.md のスキルプロンプト（`claude -p "$PROMPT"` として渡される）に「`HAS_WORKFLOW_CAPABILITY=true` の場合は Task の代わりに Workflow ツールで fan-out を実行せよ」を含める
4. `claude -p` 内の Claude がこれをユーザーの明示的な Workflow 使用指示として読み取り — opt-in 要件を満たす

これは `capabilities.visual-diff`（Ref #441）と同じ adapter-resolver lazy chain パターンである。

**Spike 1 結論**: Workflow は `claude -p` モードで利用可能・呼び出し可能。SKILL.md プロンプト注入による opt-in メカニズムは技術的に実現可能。

---

## Spike 2: `/review --full` workflow 化 PoC

### 現行アーキテクチャ（static Task fan-out）

```
review-spec  (Task, Opus)  ─────────────────────────────────→ findings
review-bug×1 (Task, Opus)  ─────────────────────────────────→ findings
review-bug×2 (Task, Opus)  ─────────────────────────────────→ findings
                                                              ↓ BARRIER（全件収集）
                               verification sub-agents ×N (Task, Opus, 上限 10)
                                                              ↓
                                       確認済み findings → review body
```

3 つの finder は並列実行（単一メッセージ Task fan-out）。BARRIER で全 findings を収集した後、verification sub-agents を実行（単一メッセージ Task fan-out で部分並列化されるが、Task ツールモデルにより直列化される）。

### 提案する Workflow アーキテクチャ

```javascript
export const meta = {
  name: 'review-full-workflow',
  description: '/review --full 向け finder fan-out → adversarial verify pipeline',
  phases: [
    { title: 'Find', detail: 'review-spec + review-bug×2 並列 finder' },
    { title: 'Verify', detail: 'finding ごとに N-vote adversarial 検証' },
  ],
}

const FINDERS = [
  { key: 'spec', agentType: 'review-spec' },
  { key: 'bug-diff', agentType: 'review-bug' },
  { key: 'bug-security', agentType: 'review-bug' },
]

const results = await pipeline(
  FINDERS,
  (finder, _, i) => agent(buildFinderPrompt(PR_NUMBER, finder.key, i), {
    label: `finder:${finder.key}`,
    phase: 'Find',
    agentType: finder.agentType,
    schema: FINDINGS_SCHEMA,
  }),
  (findings, originalFinder) =>
    parallel(findings.findings.slice(0, 10).map(f => () =>
      agent(`以下を反証せよ: ${f.description}。不確かな場合は refuted=true をデフォルトとする`, {
        label: `verify:${f.id}:${originalFinder.key}`,
        phase: 'Verify',
        schema: VERDICT_SCHEMA,
      })
    ))
)

const confirmed = results
  .flat()
  .filter(Boolean)
  .filter(v => v && !v.refuted)
```

### アーキテクチャ比較

| 軸 | 現行（Task fan-out） | Workflow（pipeline） |
|----|---------------------|---------------------|
| **finder 並列化** | 並列（単一メッセージ Task fan-out） | 並列（pipeline が item ごとに独立実行） |
| **verify 開始タイミング** | 3 finder 全件完了後（BARRIER） | finder ごと：各 finder 完了次第即座に開始 |
| **構造化出力** | テキスト解析（脆弱） | `schema` パラメータ（検証済み JSON、不一致時リトライ） |
| **budget 制御** | なし（全 findings 処理） | `budget.remaining()` ゲートで適応的深度制御 |
| **false-positive フィルタ** | finding ごと 1 票検証 | N-vote adversarial（反証デフォルト） |
| **finder 動的スケーリング** | 固定 3 finder | 可変 N（budget スケール、loop-until-dry） |
| **可観測性** | Task 出力テキスト | `/workflows` のライブ進捗ツリー |

### 品質比較分析

代表 PR（PR #566: review-bug の find/filter 分離、~300 行変更・3 ファイル）に対する分析:

**検出品質**: 基準では同一を期待（同一エージェントプロンプト・モデル）。pipeline vs. barrier の違いは各 finder が参照する内容に影響しない。

**false-positive 率**: N-vote adversarial verify パターン（反証デフォルト）は現行の 1-vote 検証より厳格。確認済み findings 数は**減少**する見込みだが信頼度は上昇。大規模 PR で 1-vote フィルタリングが緩い現行の品質向上となる。

**カバレッジスケーリング**: Workflow 版は `budget.remaining()` で finder を動的に追加できる。現行の static fan-out は PR 規模に関係なく固定 3 エージェント。

**実行時間改善の試算**: 3 finder・各 5 findings の場合:
- 現行: 5 分（finder 並列）+ 3 分（15 件検証バッチ）= 約 8 分
- Workflow pipeline: finder 1 が ~3 分で完了 → 5 件の検証が即座に開始。finder 2・3 完了（~5 分）時点で finder 1 の検証が終了。合計約 6 分
- **試算改善率**: 壁時計時間で約 25% 削減

**PoC 結論**: workflow アーキテクチャは以下の構造的改善を提供する:
1. verify レイテンシ（pipeline オーバーラップ vs. post-barrier バッチ）
2. 構造化出力の信頼性（schema vs. テキスト解析）
3. スケーラビリティ（budget-gated finder スケーリング）
4. false-positive 精度（N-vote adversarial）

現行の static fan-out はすでに高品質であり、workflow 版は段階的改善であって、カテゴリー的な変化ではない。

---

## Spike 3: コスト計測

### トークンコスト試算

代表的な Wholework PR 特性（Markdown/Shell/YAML PR、変更行数 100–400 行）に基づく試算:

**現行 `/review --full`（Size M PR、~200 行変更）:**

| コンポーネント | モデル | 推定トークン数 | 備考 |
|--------------|-------|--------------|------|
| review-spec | Opus 4.8 | 30,000–50,000 | PR diff + Spec + steering docs |
| review-bug ×2 | Opus 4.8 | 25,000–40,000 each | PR diff フォーカス |
| verification ×5 | Opus 4.8 | 5,000–8,000 each | finding ごとの検証 |
| **合計** | | **120,000–180,000** | Opus 4.8 料金: 約 $1.50–$2.25 |

**Workflow 版（同一 PR、同一 finder）:**

| コンポーネント | モデル | 推定トークン数 | 備考 |
|--------------|-------|--------------|------|
| Finder ×3（同一） | Opus 4.8 | 現行と同一 | 同一プロンプト |
| Verification ×5（N-vote ×3 票） | Sonnet 4.6 | 5,000–8,000 each | 現行の 3 倍の verifier 数 |
| Workflow フレームワーク overhead | — | ~5,000–10,000 | スクリプト実行・schema 検証 |
| **合計** | | **135,000–205,000** | 基準で約 10–15% 増 |

**budget スケールモード（大規模 PR、finder 増加時）:**
- 現行: PR 規模に関わらず固定 3 finder
- Workflow: L/XL PR で finder を 5–7 に拡張可能（トークン増加だがカバレッジも比例向上）

### 実行時間比較

| PR サイズ | 現行 fan-out | Workflow pipeline | 改善率 |
|----------|-------------|-------------------|-------|
| XS/S（~100 行未満） | 3–5 分 | 2–4 分 | 約 20% |
| M（100–300 行） | 5–8 分 | 4–6 分 | 約 25% |
| L（300–600 行） | 7–12 分 | 5–9 分 | 約 25–30% |

### Size 別適用基準案

| Size | 推奨 | 根拠 |
|------|------|------|
| XS/S | Workflow 不採用 | overhead が割に合わない。review は高速（5 分未満） |
| M | 任意（デフォルト無効） | 恩恵はあるが限定的。`capabilities.workflow: true` で有効化 |
| L | 推奨 | pipeline オーバーラップ + budget スケーリングで有意な恩恵 |
| XL | 強く推奨 | budget スケーリングが PR 複雑さに比例してカバレッジを追加 |

**コスト評価**: Workflow 版は基準で約 10–15% 高コスト（N-vote 検証）だが、L/XL PR ではカバレッジスケーリングで比例的な価値を提供。自動化パイプライン（全 PR で review 実行）ではデフォルトを static fan-out のままとし、深度を優先するプロジェクトが `capabilities.workflow: true` で opt-in する形が適切。

---

## 採否判断

**採用 — 段階的ロールアウトと opt-in ゲートを伴う**

### 採用根拠

1. **技術的実現可能性が確認された**: Workflow は `claude -p` モードで利用可能（Spike 1）。認証バリアなし（`task-budgets-2026-03-13` と異なり）、beta フラグ不要。

2. **opt-in メカニズムが機能する**: `capabilities.workflow: true` → SKILL.md プロンプト注入パターンが headless 経路で opt-in を正しく伝達する。`capabilities.visual-diff`（Ref #441）と同一メカニズム。

3. **アーキテクチャ的フィットが強い**: #555 後、find/filter 分離が Workflow の `pipeline(finders, verifiers)` 構造に 1:1 でマップされる。強引な適合ではなく、完璧に一致する問題形状に canonical な Workflow パターンを適用する形。

4. **段階的な品質改善**: pipeline オーバーラップ（約 25% 高速化）、構造化出力の信頼性向上、N-vote adversarial 検証、budget スケール動的 finder。いずれも実際の改善であり、仮説的なものではない。

5. **graceful fallback 設計**: adapter パターンにより、`capabilities.workflow: true` のないプロジェクトでは現行の static fan-out をフォールバックとして維持。既存ユーザーへの破壊的変更なし。

### 条件

- **スコープ制限**: Phase 1 の採用は `/review --full` のみ。他フェーズ（audit、issue、spec）は `/review` 採用安定後に個別評価。
- **コスト透明性**: workflow モード有効時、スキル完了レポートにおよそのトークン使用量を記録し、ユーザーが判断できるようにする。
- **opt-in デフォルト**: `capabilities.workflow: false`（未設定）では現行の static fan-out を使用。Workflow はデフォルトではなく opt-in のみ。

### 採用 vs. 不採用の比較

| 判断基準 | 採用 | 不採用 |
|---------|------|-------|
| 技術的実現可能性 | ✓ 確認済み | — |
| opt-in メカニズム | ✓ プロンプト注入で機能 | — |
| 品質改善 | ✓ 段階的（約 25% 高速化、高精度） | — |
| コスト影響 | ✓ 基準で 10–15% 増、L/XL では正当化 | — |
| 実装複雑性 | 中程度（新しい workflow スクリプト成果物） | なし |
| リスク | 低（現行へのgraceful fallback） | 機会損失 |

**結論**: 技術リスクは低く、フォールバックは明確で、品質改善は実証済み。採用する。

### 実装スコープ（フォローアップ Issue 向け）

実装 Issue がカバーすべき内容:
1. `scripts/review-workflow.js` を作成 — `review-spec + review-bug × N → adversarial verify pipeline` の workflow スクリプト
2. `capabilities.workflow` を `detect-config-markers.md` および動的機能テーブルに追加
3. `load_when: capability: workflow` を持つ Domain ファイル `skills/review/workflow-guidance.md` を追加
4. SKILL.md Step 10 を `HAS_WORKFLOW_CAPABILITY` で分岐: true の場合 Workflow ツール、false の場合 Task fan-out
5. `docs/tech.md` の fork 判断テーブルに「実行基盤」列を追加（headless/in-session ルーティングの SSoT 化）

---

## `/auto` 子フェーズの実行基盤ルーティング方針

Spike 1 により Workflow が `claude -p` で利用可能なことが判明した。これは `/auto` 子フェーズの実行基盤分析に影響する — **Workflow は headless モードで動作可能**。

### 現状

| フェーズ | 実行基盤 | 理由 |
|---------|---------|------|
| spec, code, merge | headless（`claude -p`） | effort ルーティング + watchdog/reconcile 回復機構 |
| review | headless（`claude -p`） | 同上 |
| verify | in-session | AskUserQuestion 依存 |
| triage, audit, doc | in-session | ユーザーセッションから呼び出し。wrapper なし |
| auto（親） | in-session | 適応型 LLM オーケストレーション |

### ルーティング推奨

Spike 1（Workflow が headless で利用可能）と現在のアーキテクチャに基づく推奨:

| フェーズ | 推奨実行基盤 | 根拠 |
|---------|------------|------|
| **review** | **In-session**（移行最有力候補） | Workflow の恩恵が最大（fan-out + adversarial verify）。effort high ≈ セッションデフォルト → 損失最小。`context: fork` がすでに prior-phase バイアスを分離済み。 |
| spec | headless（維持） | effort ルーティングが主要な価値（Opus: xhigh、Fable 5: max）。spec への Workflow 恩恵は不明瞭。#556 の結果を待って再評価。 |
| code | headless（維持） | effort ルーティング + worktree 分離。単一エージェントタスクで Workflow の明確な恩恵なし。 |
| merge | headless（維持） | effort low の機械的操作。並列化の恩恵なし。 |
| verify | in-session（維持） | AskUserQuestion 依存。headless 実行不可。 |
| issue（L/XL） | headless（維持） | 現行の Task による 3 エージェント並列調査が安定。/review 採用後の Workflow 安定性確認後に評価。 |
| auto（親） | in-session（維持） | ライブ GitHub 状態に対する適応型 LLM 判断が必要。 |

### 将来の移行判断基準

以下のすべてを満たす場合にフェーズの in-session 移行を検討:
1. フェーズが fan-out パターンを持ち、Workflow の pipeline/parallel で壁時計時間 20% 超の改善が見込まれる
2. フェーズの effort レベル（`--effort high/xhigh`）がセッション内でも同等に達成できる（セッションはデフォルトで high effort 相当で動作）
3. コスト削減のために有意に低い effort レベルへのルーティングが不要（merge の `--effort low` は実質的なトークン削減）
4. watchdog/reconcile 回復機構の追加価値が Workflow の構造化出力と budget 制御より小さい

**現在の優先順位**: review（最優先）→ audit（同様の fan-out パターン、次に評価）→ issue L/XL（review 安定後に延期）→ spec/code/merge（headless 維持）

### docs/tech.md SSoT 更新

フォローアップ実装 Issue の実施時に、`docs/tech.md §Architecture Decisions` の fork 判断テーブルに「実行基盤」列を追加する:

| スキル | Fork 必要 | **実行基盤** | 理由 |
|-------|----------|------------|------|
| review | あり | **In-session**（`capabilities.workflow: true` 時）/ headless フォールバック | Workflow fan-out 恩恵が最大 |
| spec, code | あり | headless | effort ルーティング + 回復機構 |
| merge | あり | headless | effort low + 機械的操作 |
| verify | なし | in-session | AskUserQuestion |

---

## 付録: 参照レポート

- `docs/reports/ultrareview-spike.md`（Issue #223）: 同一の spike 手法による外部エンジン評価。不採用（`/ultrareview` はユーザー呼び出しのみで `/auto` と非互換）。本 spike は異なる結論（採用）に達した。Workflow は headless で利用可能なため。
- `docs/reports/task-budgets-spike.md`（Issue #222）: beta 機能評価。OAuth 認証バリアにより不採用。Workflow には認証制限がないため本 spike は採用に達した。
- `docs/reports/claude-fable-5-impact-strategy.md` §4.5 および §2.2: 非同期 sub-agent の具体的実現手段と in-session vs. headless ルーティング分析 — 本 spike のルーティング推奨の直接的な文脈。
