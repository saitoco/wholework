[English](../../reports/claude-opus-4-7-optimization-strategy.md) | 日本語

# Wholework の Claude Opus 4.7 最適化戦略

**作成日**: 2026-04-17
**作成者**: 自動分析セッション
**対象範囲**: 配布コンポーネント（skills / agents / modules / scripts）と Steering Documents
**状態**: 提案 — 実行計画は §7「候補 Issue」を参照

## 1. エグゼクティブサマリ

Claude Opus 4.7 では、新しいデフォルト effort レベル（`xhigh`）、adaptive thinking 専用化（固定 `budget_tokens` は 400 を返す）、より literal な指示解釈、保守的な subagent スポーン、tool 呼び出し頻度の低下、高解像度画像対応（最大 2,576 px）が導入されました。Wholework は Claude Code を `claude -p --model <id> --effort <level>` 経由で呼び出し、`/issue`（L/XL）と `/review` で並列サブエージェントに依存しているため、ランタイム層の移行リスクは小さい一方で、挙動面で重要な影響が 2 点あります：

1. **サブエージェント fan-out**: `/issue` は `issue-scope / issue-risk / issue-precedent` を並列起動し、`/review` は `review-bug / review-spec` を並列起動します。Opus 4.7 はスポーンに対して保守的な傾向があるため、現在の挙動を保つには SKILL 本文の並列起動意図を明示化する必要があります。
2. **literal な指示追従**: 一部の SKILL.md は暗黙的一般化（例：「この種類の他のファイルにも同様に」）に依存しています。Opus 4.7 では暗黙的一般化が機能しなくなるため、曖昧な箇所は明示的な指示へ昇格する必要があります。

それ以外（API の削除、prefill、temperature / top_p / top_k）は Wholework が CLI 経由で呼び出しているため実質的に影響ありません。

最適化作業は 4 段階の優先度（P0 緊急、P1 高、P2 中、P3 低）に整理され、§7 で **12 本の候補 Issue** を提示します。

## 2. Claude Opus 4.7 の主要変更点

### 2.1 API 破壊的変更（CLI 利用者にはフラグ未使用であれば影響なし）

| 変更 | Wholework への影響 | 備考 |
|---|---|---|
| `thinking: {type: "enabled", budget_tokens: N}` が 400 を返す | なし | `--thinking budget:N` は使用していない。adaptive thinking は `--effort` で制御。 |
| `temperature` / `top_p` / `top_k` のデフォルト外値 → 400 | なし | CLI 呼び出しでは sampling パラメータを設定していない。 |
| assistant メッセージ prefill → 400 | なし | prefill 未使用。 |
| thinking display のデフォルトが `omitted` に | 部分的 | `claude -p` の進捗ストリーミング表示のみに影響。UX 考慮のみ。 |
| 新 tokenizer（同一テキストで 1.0–1.35× のトークン数） | **あり** | `max_tokens` のヘッドルームと文字ベースのヒューリスティックの再点検が必要。 |
| `output_format` 非推奨 → `output_config.format` | なし（CLI が抽象化） | |

### 2.2 挙動変更（Wholework に関係するもの）

| 挙動 | Wholework との関係 | 最適化レバー |
|---|---|---|
| 応答長がタスクの複雑さに自動調整される | 冗長な `/auto` 進捗スキャフォールドが不要になる可能性 | 「N 回ごとに要約」指示を削除し、組み込みの進捗更新に委ねる |
| より literal な指示追従 | 多くの SKILL.md ステップが暗黙的一般化に依存（例：「同様のパターンを類似ファイルにも適用」） | 暗黙的パターンを明示的列挙へ昇格、必要に応じて具体的ファイルリストを追加 |
| より直接的なトーン / 肯定フレーズの減少 | ユーザ向け skill 出力（ターミナルメッセージ）がやや素っ気なく感じられる可能性 | 内部出力は許容、ユーザ向け完了レポートのみ監査 |
| agentic trace 中の組み込み進捗更新 | `/auto` 長時間 run で中間ステータスが改善 | カスタム「3 tool call ごとにステータス出力」スキャフォールドは削除 |
| **デフォルトでスポーンする subagent 数が減少** | **`/issue` L/XL と `/review` 並列フェーズに直接影響** | 「1 つのメッセージ内で N 個の subagent を並列起動する」という明示指示を追加 |
| effort の厳格なキャリブレーション（特に `low`） | `run-merge.sh` は `low`、`run-verify.sh` は `medium` | これらのフェーズが引き続き十分に完了するか検証。必要なら `medium`/`high` へ引き上げ |
| デフォルトでの tool 呼び出し数減少 | `/spec` は Grep/Glob/Read に依存、`/review` は `git diff` ツールに依存 | 「変更範囲を十分カバーするために Grep/Read を徹底利用」という明示指示を追加 |
| サイバーセキュリティ保護の強化 | セキュリティレビュー（`review-bug` の shell injection / secrets チェック）で refusal が発生する可能性 | 監視を行い、必要なら Cyber Verification Program へ申請 |
| 高解像度画像対応（2,576 px、画像最大 4,784 tokens） | `browser-adapter` / `lighthouse-adapter` / `/verify` スクリーンショットフロー | client 側の scale-factor 変換を削除、スクリーンショット解像度のデフォルト更新、画像トークン 3 倍分の予算再評価 |

### 2.3 新機能（評価対象）

| 機能 | 状態 | Wholework での活用可能性 |
|---|---|---|
| `xhigh` effort レベル（Claude Code の coding でデフォルト） | GA | spec で `max` を置換するか、matrix 全体で再評価 |
| task budgets（`task-budgets-2026-03-13`） | Beta | `/auto` 長時間 run でフェーズ別トークン予算を設定 |
| Ultrareview command | 新 | `/review` の `--ultra` 深堀りオプションとして検討 |
| ファイルシステムメモリの改善 | 改善 | Spec-as-memory パターンに恩恵あり。即時対応は不要 |
| `output_config.task_budget` | Beta | API レベルの予算ヒントで self-pacing |
| `xhigh` + adaptive thinking + interleaved thinking（自動） | GA | デフォルト挙動 — opt-in 不要 |

### 2.4 effort レベル再キャリブレーションガイド（Anthropic 提示）

| レベル | Anthropic ガイダンス | Wholework の現状利用 |
|---|---|---|
| `max` | intelligence 要求の高いタスクで検証。オーバーシンクのリスク | `run-spec.sh`（spec フェーズ） |
| `xhigh`（新デフォルト） | ほとんどの coding / agentic 用途に最適 | 未採用 |
| `high` | intelligence 敏感な用途の最低ライン | `run-code.sh`, `run-review.sh`, `run-issue.sh` |
| `medium` | コスト重視 / intelligence 低下許容 | `run-verify.sh` |
| `low` | 短く範囲が明確 / レイテンシ重視のみ — 厳格にスコープ化 | `run-merge.sh` |

## 3. Wholework の現状表面積

### 3.1 モデル / effort matrix（`docs/tech.md` が SSoT）

| コンポーネント | フェーズ | モデル | effort | 直書き箇所 |
|---|---|---|---|---|
| `run-spec.sh` | spec | Sonnet（L では `--opus` で Opus） | `max` | `scripts/run-spec.sh` L10, L15 |
| `run-code.sh` | code | Sonnet | `high` | `scripts/run-code.sh` L136–140 |
| `run-review.sh` | review | Sonnet | `high` | `scripts/run-review.sh` |
| `run-issue.sh` | issue | Sonnet | `high` | `scripts/run-issue.sh` |
| `run-verify.sh` | verify | Sonnet | `medium` | `scripts/run-verify.sh` |
| `run-merge.sh` | merge | Sonnet | `low` | `scripts/run-merge.sh` |
| `review-bug` agent | review（subagent） | Opus | 親から継承 | `agents/review-bug.md` frontmatter |
| `review-spec` agent | review（subagent） | Opus | 親から継承 | `agents/review-spec.md` frontmatter |
| `review-light` agent | review（subagent） | Sonnet | 親から継承 | `agents/review-light.md` frontmatter |
| `issue-scope` agent | issue L/XL（subagent） | Opus | 親から継承 | `agents/issue-scope.md` frontmatter |
| `issue-risk` agent | issue L/XL（subagent） | Opus | 親から継承 | `agents/issue-risk.md` frontmatter |
| `issue-precedent` agent | issue L/XL（subagent） | Opus | 親から継承 | `agents/issue-precedent.md` frontmatter |
| `triage` skill | triage | Sonnet | — | インライン（runner なし） |

### 3.2 Opus 利用箇所の集中

Opus は以下で使用中：
- `run-spec.sh --opus`（L サイズ spec、`scripts/run-spec.sh:15` で `claude-opus-4-6` を直書き）
- YAML frontmatter で `model: opus` エイリアスを指定する 5 つの subagent

**エイリアス解決**: agent は `model: opus`（特定バージョンではない）を指定。Claude Code が `opus` を最新 Opus に解決するため、インストール後は自動で Opus 4.7 を採用します。ハードコード済み文字列 `claude-opus-4-6` は `run-spec.sh` のみで、ここだけ更新が必要。

### 3.3 並列 subagent fan-out 箇所（Opus 4.7 保守的スポーンのリスク）

| Skill | ステップ | 起動する subagent | 現在の指示スタイル |
|---|---|---|---|
| `/issue` | 11a（L/XL 限定） | `issue-scope`, `issue-risk`, `issue-precedent`（3×） | 明示的な `Task(...)` 3 連ブロック — 基本は良好だが「Launch 3 agents in parallel」の表現 |
| `/review` | 場合による | `review-bug`, `review-spec`（2×）または `review-light`（1×） | 要確認 |

### 3.4 Opus 4.7 で冗長化する可能性のあるスキャフォールド

- phase banner（`scripts/phase-banner.sh` — `print_start_banner` / `print_end_banner`）— ランタイムレベル、維持（モデル推論外）。
- 各 skill の Step N で retrospective コメントを投稿する処理 — 維持（意図的な Spec-as-memory 永続化であり進捗スキャフォールドではない）。
- 明示的な「X の後で要約」系指示 — 監査対象。

## 4. 影響分析

### 4.1 高影響領域

| 領域 | リスク | 対策 |
|---|---|---|
| `/issue` L/XL 並列調査の品質 | subagent のスポーン頻度が下がり、単一 agent 経路へ fallback が増える | Step 11a の「Launch 3 agents in parallel」を必須命令化、「in a single message with 3 Task calls」という明示表現を追加 |
| `/review` 並列レビューの品質 | review-bug / review-spec で上記と同様のリスク | 同じ対策 |
| `run-spec.sh --opus` × `max` effort | Opus 4.7 の diminishing returns 警告下でオーバーシンクの可能性 | Opus spec で `xhigh` を評価、`max` は実験用に残す |
| `run-merge.sh` × `low` effort | Opus 4.7 の low は厳格スコープ化 — マージ conflict で under-thinking のリスク | merge フェーズが edge case（conflict, CI wait）を扱えるか検証、regression があれば `medium` へ |
| ブラウザスクリーンショット検証 | 高解像度画像で 3× の画像トークン消費 | 解像度不要なら送信前にダウンサンプル、もしくは予算を再調整 |

### 4.2 低影響領域

- `run-code.sh` / `run-review.sh` / `run-issue.sh`（`high`）— 推奨最低ラインをすでに満たす。即時対応不要。
- subagent の Opus エイリアス — 4.7 へ自動更新、コード変更不要。
- prompt caching、1M context、PDF support、Files API — 変更なし。

### 4.3 影響未確定領域（ベンチマーク必要）

- 4.7 の新 tokenizer（+0–35%）下で Wholework エンドツーエンドのコスト差分。
- `/review` のバグ検出 recall 差分（Anthropic は code review recall +10% を主張）。
- 4.6 と同一 prompt 下での 4.7 の subagent スポーン回帰の有無。

## 5. 戦略的推奨事項

### 5.1 即時対応（P0 / 緊急）

1. **モデル ID 更新**: `scripts/run-spec.sh` の直書き `claude-opus-4-6` → `claude-opus-4-7`。agent 側の `model: opus` エイリアスが Claude Code で 4.7 に解決されることを確認。
2. **subagent スポーン明示化**: `/issue` Step 11a と `/review` skill の並列起動指示を監査。「in a single message with N Task calls」のような曖昧さのない表現を追加。

### 5.2 近日対応（P1 / 高）

3. **`run-spec.sh` に `xhigh` 対応を追加**: 新フラグ `--xhigh`（または Opus spec で `xhigh` をデフォルト化、`max` を置換）。
4. **`docs/tech.md` model-effort-matrix（SSoT）を更新**: `xhigh` 列の追加、Opus 4.7 へのアップグレード反映、effort レベルガイドの明記。
5. **SKILL.md の literalism 監査**: 全 SKILL.md を走査し、暗黙的一般化パターンを明示列挙へ昇格。
6. **SKILL.md の冗長な進捗更新スキャフォールド監査**: 「X tool call ごとに要約」系指示があれば削除。

### 5.3 付加価値対応（P2 / 中）

7. **高解像度スクリーンショット対応**: `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` を 2,576 px デフォルトに更新、scale-factor 変換を削除、画像トークン 3× コストの記載。
8. **task budgets（Beta）スパイク**: `task-budgets-2026-03-13` を `/auto` orchestration の境界として評価。
9. **Ultrareview 統合**: `/review` の `--ultra` 深堀りモード候補として評価。
10. **利用者向け移行ガイド**: `docs/guide/opus-4-7-migration.md` を公開、挙動変化と Wholework 利用者向けの prompt 調整を解説。

### 5.4 最適化 / 将来対応（P3 / 低）

11. **tokenizer 監査**: Wholework skills / scripts で文字長 / トークン数の前提を走査、1.0–1.35× で破綻しないか検証。
12. **エンドツーエンドベンチマーク**: 参照 Issue で 6 フェーズ全体のコストと品質を Opus 4.7 vs 4.6 で再基準化。結果を `docs/stats/` または新設 `docs/benchmarks/` に公開。

## 6. 移行チェックリスト（Wholework 固有）

- [ ] `scripts/run-spec.sh` L15: `claude-opus-4-6` → `claude-opus-4-7`
- [ ] `agents/{review-bug,review-spec,issue-scope,issue-risk,issue-precedent}.md` の `model: opus` エイリアスが、Claude Code 更新後 4.7 に解決されることを確認
- [ ] `docs/tech.md` §Architecture Decisions §Effort optimization strategy / Phase-specific model and effort matrix: Opus 4.7 と `xhigh` 対応を反映
- [ ] `/issue` SKILL.md Step 11a: 並列起動指示が明示的かつ単一メッセージで行われることを確認
- [ ] `/review` SKILL.md: review-bug / review-spec の並列起動指示が明示的かつ単一メッセージで行われることを確認
- [ ] 残りの SKILL.md を監査し暗黙的一般化パターンを洗い出す（literalism 対応）
- [ ] SKILL.md の冗長な進捗更新スキャフォールドを監査
- [ ] `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` を 2,576 px 対応に更新
- [ ] `/auto` での `task_budget` Beta 採用を評価
- [ ] 利用者向け移行ガイド（`docs/guide/opus-4-7-migration.md`）公開
- [ ] エンドツーエンドのコスト / 品質ベンチマークを再基準化

## 7. 候補 Issue（実行計画）

優先度順で 12 本の候補 Issue。すべて Wholework Standard Format（Background / Purpose / Acceptance Criteria、Pre-merge / Post-merge 分割）に準拠。

| # | タイトル | Priority | Size 見込 | 影響フェーズ |
|---|---|---|---|---|
| C1 | `run-spec.sh` の Opus モデル ID を claude-opus-4-7 へ更新 | urgent | XS | spec |
| C2 | 並列 sub-agent 起動指示の明示化（Opus 4.7 保守的スポーン対策） | high | S | issue, review |
| C3 | `run-spec.sh` に xhigh effort 選択肢を追加 | high | S | spec |
| C4 | `docs/tech.md` model-effort-matrix を Opus 4.7 / xhigh 対応で更新 | high | S | docs |
| C5 | SKILL.md の暗黙的一般化パターン監査（literalism 対応） | high | M | 全 skill |
| C6 | SKILL.md の冗長な進捗更新 scaffolding 監査と削除 | medium | S | 全 skill |
| C7 | browser-adapter / lighthouse-adapter の高解像度（2576 px）対応 | medium | M | verify |
| C8 | `/auto` に task_budgets（Beta）導入スパイク | medium | M | auto |
| C9 | `/review` に ultrareview オプション（`--ultra`）導入検討 | medium | M | review |
| C10 | Wholework 利用者向け Opus 4.7 移行ガイドの公開 | medium | S | docs/guide |
| C11 | 新 tokenizer（1.0–1.35×）対応の文字数 / token 前提監査 | low | S | scripts/modules |
| C12 | Opus 4.7 vs 4.6 でのエンドツーエンドベンチマーク | low | M | benchmarks |

### 7.1 Issue の順序付け理由

- **C1** を最優先 — モデル ID 更新が行われないと `run-spec.sh --opus` は引き続き 4.6 を呼ぶ。最速の勝ち筋、最小のブラスト半径。
- **C2** は C1 独立 — prompt レベルの変更、並行着手可能。最大の挙動リスク案件。
- **C3 + C4** は自然なペア — tech.md の SSoT 更新は `xhigh` 採用に続く。単一 PR にまとめても分割しても可。
- **C5** は中〜大規模監査、C2 と並行可能（対象ファイルが異なる）。
- **C6** は低リスクのクリーンアップ。C5 に続くか独立着手。
- **C7** は中規模、verify アダプタに触れる。モデル ID 更新と独立。
- **C8, C9, C10** は独立スパイク / 探索、順序制約なし。
- **C11, C12** は最適化、延期可。

## 8. Non-goals

- API レイヤの移行（temperature / top_p / top_k、prefill、extended thinking budget）は対象外 — Wholework は CLI のみ使用。
- Sonnet モデル更新は対象外 — 本報告書は Opus 4.7 のみ対象。Sonnet 4.6 が引き続き orchestrator のデフォルト。
- `advisor_20260301` Beta 探索は対象外 — tech.md に follow-up として既記載、Opus 4.7 固有ではない。
- `ANTHROPIC_MODEL` 環境変数の除去は対象外 — CLI `-p` モードのバグ（claude-code#22362）回避策として必要。

## 9. 参考文献

- [Claude Opus 4.7 Launch](https://www.anthropic.com/news/claude-opus-4-7)
- [Best Practices for Using Claude Opus 4.7 with Claude Code](https://claude.com/blog/best-practices-for-using-claude-opus-4-7-with-claude-code)
- [Claude Migration Guide（platform.claude.com）](https://platform.claude.com/docs/en/about-claude/models/migration-guide#migrating-to-claude-opus-4-7)
- Wholework `docs/tech.md` §Architecture Decisions（model-effort-matrix の SSoT）
- Wholework `docs/product.md` §Future Direction（ワークフロー最適化 3 軸）

---

*本報告書は §7 の Issue を提案します。各 Issue は Wholework GitHub リポジトリで作成され、`phase/issue` ラベルを付与し、Wholework GitHub Project (#35) で該当 Priority を設定することを想定しています。*
