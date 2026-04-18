[English](../../reports/sonnet-effort-recalibration.md) | 日本語

# Sonnet Effort 再評価レポート

**作成日**: 2026-04-18
**Issue**: #229
**対象範囲**: `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-verify.sh` / `run-issue.sh`
**状態**: 確定 — すべての設定が妥当にキャリブレーションされていることを確認

## Background

Sonnet で動作する 5 つの `run-*.sh` スクリプトには固定の `--effort` フラグ (`high` / `medium` / `low`) が設定されているが、これらは各 phase の workload に対して妥当かを体系的に評価せずに段階的に設定されてきた。

`xhigh` effort レベル (Opus 4.7 の推奨デフォルト) は Sonnet では利用不可のため、本レポートでは 5 つの Sonnet スクリプトについて `low` / `medium` / `high` のみを評価対象とする。`run-spec.sh` (Opus / `xhigh` 路線) は本スコープ外 — Issue #217 を参照。

本再評価は `docs/reports/claude-opus-4-7-optimization-strategy.md` の Opus 4.7 recalibration 作業とは独立して行う。

## 現行構成

| Script | Model | Effort | 主なタスク |
|--------|-------|--------|-----------|
| `run-code.sh` | Sonnet | high | Spec 駆動の実装 + PR / patch 作成 |
| `run-review.sh` | Sonnet | high | Review オーケストレーション (サブエージェント: Opus) |
| `run-merge.sh` | Sonnet | low | PR マージ判定 + コンフリクト解消 |
| `run-verify.sh` | Sonnet | medium | 受入条件検証 + AI 回顧 |
| `run-issue.sh` | Sonnet | high | Issue triage + refinement (L/XL のサブエージェント: Opus) |

## Workload 分析

### run-code.sh — `high`

code phase は 14 の明確なステップを実行する: worktree 進入、spec 読み込み、uncertainty 解消、steering document レビュー、実装、テスト実行、verify command 整合性チェック、commit / push または PR 作成、retrospective 記述、worktree 退出。

各ステップは複数ファイル読み込み、編集判断、条件分岐を伴う。`high` effort により、モデルは曖昧な実装選択を推論し、spec のギャップを検知し、正しいファイル配置を選択できる — これらはすべてライフサイクルを通して誤ると累積するタイプの判断である。

**time / cost / quality トレードオフ**: `medium` では初期ステップでの浅い推論が後続ステップでの手戻りを招き、トークン単価は下がっても総 wall-clock 時間が増える傾向がある。累積手戻りを最小化するため `high` が妥当。

### run-review.sh — `high`

review オーケストレータは CI チェックを待ち、`review-spec` (Opus) と `review-bug` (Opus) を並列サブエージェントとして起動する。`docs/tech.md` に従い、effort はサブエージェントへ親呼び出しから継承される。オーケストレータを `high` から `medium` へ下げると、サブエージェントの effort も下がり、バグ検出と spec 準拠精度に直接影響する。

**主な制約**: サブエージェントの effort 継承により、オーケストレータの effort レベルは review phase のすべてのサブエージェントに対する共通上限となる。`review-bug` (Opus) / `review-spec` (Opus) の現行品質水準を保つため、`high` を維持する必要がある。

**time / cost / quality トレードオフ**: review は PR ごとに 1 回実行される。1 回の `high` effort review セッションの絶対コストは、見逃されたバグが `phase/verify` まで到達するコストに比べれば小さい。

### run-merge.sh — `low`

merge phase は決定論的な手順を実行する: PR メタデータ取得、review 判定読み込み、承認 / 却下判断、`gh pr merge` 実行。各判断は構造的に制約されており、skill は明示的な review 出力を読んで固定ルールセットを適用する。

コンフリクト解消は唯一の非機械的サブタスクである。ただし本ワークフローではコンフリクトは稀で (worktree がブランチを隔離し、ほとんどの PR は `main` に対してファイル重複が少ない)、発生した場合も解消パスは git conflict marker によって構造的に導かれる。

Sonnet の `low` effort は、モデルが文字通り要求されたことを実行し、代替案を探らないことを意味する — これは決定論的なマージ判断が行うべきまさにその挙動である。`medium` はプライマリパスの正確性を改善せずにコストを増やし、`high` は機械的操作を考えすぎるリスクがある。

**time / cost / quality トレードオフ**: `low` は merge の決定論的性質に適合している。コンフリクト解消の失敗率が観測可能になった場合は、`medium` への昇格が次の適切なステップ (§Notes で "Requires Observation" として追跡)。

### run-verify.sh — `medium`

verify phase は Issue 受入条件に由来する固定ルールセットに対し、構造化された verify command (`file_exists` / `section_contains` / `github_check`) を実行し、その後 AI 回顧を記述する。

verify command の実行は機械的でパターン駆動であり、command 発行だけなら `low` effort でも十分である。しかし AI 回顧 (learnings / drift 分析 / follow-up issue 作成) は中程度の推論深度から恩恵を受ける。`medium` は両サブタスクをバランスよくカバーする。

`high` は retrospective 品質が主要な価値ドライバである本 phase に対して意味のあるコスト増加となるが、`medium` で既に品質は十分である。`low` は retrospective の深度が不十分になるリスクがある。

**time / cost / quality トレードオフ**: `medium` は、構造化された機械的作業と中程度の分析出力を組み合わせる phase に対する妥当な中間点である。

### run-issue.sh — `high`

issue phase は triage (Type / Size / Priority / Value 割り当て) と Issue body refinement を実行する。L/XL Issues では 3 つの Opus 並列サブエージェント (`issue-scope` / `issue-risk` / `issue-precedent`) を起動し、これらの effort はオーケストレータから継承される。

Issue 品質は基盤的である: scope 定義、受入条件、size 推定の誤りは spec → code → review → verify と伝播する。triage を誤った Issue は後続全 phase のコストを倍加させる。

XS / S / M Issue ではオーケストレータ自身がサブエージェントなしで triage を行うため、正確な size / scope 評価に `high` effort が必要。L / XL では `run-review.sh` と同じ継承制約により、サブエージェント精度を保つために `high` を維持する必要がある。

**time / cost / quality トレードオフ**: Issue triage は code / review サイクルと比較すると頻度が低い。1 回の `high` effort triage セッションのコストは、誤分類された Issue の下流コストに比べれば無視できる。

## Recommendations

5 スクリプトすべてが適切にキャリブレーションされていることを確認。effort 変更の推奨はない。

| Script | 現行 | 推奨 | 根拠 |
|--------|------|------|------|
| `run-code.sh` | `high` | **現状維持** | 14 ステップの実装には持続的な推論深度が必要。 |
| `run-review.sh` | `high` | **現状維持** | サブエージェントの effort 継承: 下げると Opus サブエージェントの精度が低下する。 |
| `run-merge.sh` | `low` | **現状維持** | 決定論的な merge ロジック; `low` が overthinking を防ぐ。コンフリクトエスカレーションは Notes を参照。 |
| `run-verify.sh` | `medium` | **現状維持** | 構造化された command 実行と中程度の retrospective 深度のバランスが取れている。 |
| `run-issue.sh` | `high` | **現状維持** | Issue 品質は基盤的; サブエージェントの effort 継承が適用される。 |

## Notes

### Requires Observation

- **`run-merge.sh` のコンフリクト解消**: 運用中にコンフリクト解消の失敗率 (解消失敗または誤解消) が観測可能になった場合は、`medium` への昇格が推奨される corrective action となる。現時点の証拠は先行的な昇格を正当化しない。
- **`run-verify.sh` の retrospective 深度**: 複数の verify サイクルで retrospective 出力の品質が学習目的に対して不十分であることが判明した場合は、`high` への昇格が候補となる修正案。現時点の出力品質は十分。

### Out of Scope

- `run-spec.sh`: Opus / `xhigh` 路線 — Issue #217 で対応。
- Sonnet の `xhigh`: 利用不可; すべての recommendations から除外。
- 定量ベンチマーク (token 数 / wall-clock 時間): Issue #226 (Opus 4.7 vs 4.6 ベンチマーク) で追跡。本レポートは workload ベースの定性分析のみを使用。
- Advisor 戦略 (`advisor_20260301`): `run-*.sh` にまだ実装されていない; `docs/tech.md` §Effort optimization strategy Axis 3 で follow-up として追跡。

### docs/tech.md Matrix との関係

`docs/tech.md` の Phase-specific model and effort matrix は、すべての model / effort 設定の SSoT である。本レポートの結果としての matrix 更新は不要 (すべての設定が変更なしと確認された)。今後いずれかの `run-*.sh` effort レベルを変更する際は、同じ PR で matrix を更新する必要がある。
