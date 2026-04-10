# Issue #108: effort: phase 別 model・effort マトリクスの設計・実装

## Overview

#70 で調査した effort 最適化 3 軸のうち、Axis 1（model 選択）と Axis 2（--effort パラメータ）を組み合わせ、run-*.sh・agents・skills 全体で phase ごとに性能・コストバランスを最適化する。

現状は全 run-*.sh が Sonnet + effort 指定なし（デフォルト）で統一されているが、phase ごとの品質要求・複雑度が異なるため、effort level を使い分けることで品質重視の phase とコスト重視の phase を分離する。

## Changed Files

- `docs/tech.md`: Architecture Decisions の Effort optimization strategy エントリーを更新。phase 別 model・effort マトリクステーブルを追加し、Axis 1/2 の記述を実装済み状態に更新
- `scripts/run-spec.sh`: `claude -p` 呼び出しに `--effort max` を追加、echo 出力に Effort 表示を追加
- `scripts/run-code.sh`: `claude -p` 呼び出しに `--effort high` を追加、echo 出力に Effort 表示を追加
- `scripts/run-review.sh`: `claude -p` 呼び出しに `--effort high` を追加、echo 出力に Effort 表示を追加
- `scripts/run-issue.sh`: `claude -p` 呼び出しに `--effort high` を追加、echo 出力に Effort 表示を追加
- `scripts/run-merge.sh`: `claude -p` 呼び出しに `--effort low` を追加、echo 出力に Effort 表示を追加
- `scripts/run-verify.sh`: `claude -p` 呼び出しに `--effort medium` を追加、echo 出力に Effort 表示を追加
- `agents/scope-agent.md`: `model: sonnet` → `model: opus` に変更
- `agents/risk-agent.md`: `model: sonnet` → `model: opus` に変更
- `agents/precedent-agent.md`: `model: sonnet` → `model: opus` に変更

agents/review-bug.md, agents/review-spec.md, agents/review-light.md: 変更不要（現在の model 配置は phase 特性に合致。根拠は docs/tech.md マトリクスに記載）
skills/triage/SKILL.md: 変更不要（Sonnet は triage タスクに十分。根拠は docs/tech.md マトリクスに記載）

## Implementation Steps

1. docs/tech.md の Architecture Decisions を更新する（→ 受入条件 A, H, I）
   - frontmatter の `ssot_for` に `model-effort-matrix` を追加（model・effort 設定の SSoT を docs/tech.md に集約し、実装とのドリフトを防止）
   - 既存の "Effort optimization strategy (3 axes)" エントリー内の Axis 1 記述 "No further action needed" を "Reviewed and confirmed" に更新
   - Axis 2 記述の "Implementation in run-*.sh is a follow-up Issue" を実装済み状態に更新
   - 以下の phase 別 model・effort マトリクステーブルを追加:

   | Component | Phase | Model | Effort | Rationale |
   |-----------|-------|-------|--------|-----------|
   | run-spec.sh | spec | Sonnet (Opus via `--opus` for L) | max | Design quality is critical; spec errors propagate to all subsequent phases. `/auto` passes `--opus` for L-size only (XL is split before spec) |
   | run-code.sh | code | Sonnet | high | Implementation requires thorough reasoning |
   | run-review.sh | review | Sonnet | high | Review orchestration; sub-agents handle deep analysis |
   | run-issue.sh | issue | Sonnet | high | L/XL scope analysis and sub-issue splitting require thorough orchestration |
   | run-verify.sh | verify | Sonnet | medium | Structured acceptance testing; moderate complexity |
   | run-merge.sh | merge | Sonnet | low | Mechanical merge operation; minimal reasoning needed |
   | review-bug | review | Opus | — | Bug detection requires highest accuracy (sub-agent, effort inherited from parent) |
   | review-spec | review | Opus | — | Spec deviation requires high accuracy (sub-agent, effort inherited from parent) |
   | review-light | review | Sonnet | — | Lightweight integrated review (sub-agent, effort inherited from parent) |
   | scope-agent | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Scope identification accuracy is critical for sub-issue boundary decisions |
   | risk-agent | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Risk assessment accuracy improves acceptance criteria quality |
   | precedent-agent | issue (L/XL only) | Opus | — | Called by `/issue` Step 11a for L/XL parallel investigation. Precedent extraction improves acceptance criteria quality |
   | triage (skill) | triage | Sonnet | — | Metadata assignment; Sonnet sufficient (direct invocation, effort not set) |

   SSoT note: This matrix is the single source of truth for all model and effort settings. When changing model/effort in run-*.sh, agents, or skills, update this table first.

2. quality-critical な run-*.sh に --effort を追加する（→ 受入条件 B, C, D, E）
   - run-spec.sh: `claude -p` 呼び出し（L61-64）に `--effort max` を追加。echo 出力に `echo "Effort: max"` を追加
   - run-code.sh: `claude -p` 呼び出し（L103-107）に `--effort high` を追加。echo 出力に `echo "Effort: high"` を追加
   - run-review.sh: `claude -p` 呼び出し（L52-56）に `--effort high` を追加。echo 出力に `echo "Effort: high"` を追加
   - run-issue.sh: `claude -p` 呼び出し（L55-59）に `--effort high` を追加。echo 出力に `echo "Effort: high"` を追加

3. cost-efficient な run-*.sh に --effort を追加する（→ 受入条件 F, G）
   - run-merge.sh: `claude -p` 呼び出し（L44-48）に `--effort low` を追加。echo 出力に `echo "Effort: low"` を追加
   - run-verify.sh: `claude -p` 呼び出し（L76-80）に `--effort medium` を追加。echo 出力に `echo "Effort: medium"` を追加

4. investigation agents の model を opus に変更する（→ 受入条件 H）
   - `agents/scope-agent.md`: frontmatter `model: sonnet` → `model: opus`
   - `agents/risk-agent.md`: frontmatter `model: sonnet` → `model: opus`
   - `agents/precedent-agent.md`: frontmatter `model: sonnet` → `model: opus`

## Alternatives Considered

- **全 phase を high effort で統一**: シンプルだが、triage/merge のようなコスト重視 phase で不要な推論コストが発生する。phase ごとの最適化が本 Issue の目的であるため不採用
- **agents にも effort を設定**: Claude Code の Agent ツールに effort パラメータはなく、sub-agent は parent session の effort を継承するため、独立設定は不可。run-*.sh の effort が間接的に sub-agents にも影響する
- **run-issue.sh を medium effort のまま据え置く**: L/XL Issue の sub-issue 分割判断は orchestrator（run-issue.sh）が担うため、medium では判断品質が不足するリスクがある。high に引き上げることでバッチ実行時のコスト増は許容する
- **Haiku を低コスト phase に導入**: Haiku は `claude -p` の `--model` で指定可能だが、Skill の複雑な手順を安定的に実行するには Sonnet が最低ライン。Haiku + Opus advisor の組み合わせは Axis 3（OAuth 認証で利用不可）に依存するためスコープ外

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "run-code" --> `docs/tech.md` の Architecture Decisions に phase 別 model・effort マトリクス（各 run-*.sh、agents、skills の model + effort 設定値と根拠）を記載
- <!-- verify: grep "--effort" "scripts/run-spec.sh" --> `scripts/run-spec.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "--effort" "scripts/run-code.sh" --> `scripts/run-code.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "--effort" "scripts/run-review.sh" --> `scripts/run-review.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "--effort" "scripts/run-issue.sh" --> `scripts/run-issue.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "--effort" "scripts/run-merge.sh" --> `scripts/run-merge.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "--effort" "scripts/run-verify.sh" --> `scripts/run-verify.sh` の `claude -p` 呼び出しに `--effort` パラメータを追加
- <!-- verify: grep "model: opus" "agents/scope-agent.md" --> investigation agents（scope-agent, risk-agent, precedent-agent）の model frontmatter を `opus` に変更
- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "triage" --> Skills の model frontmatter をマトリクスに基づいて見直し・更新（変更不要の場合は根拠を docs/tech.md に記載）
- <!-- verify: grep "model-effort-matrix" "docs/tech.md" --> `docs/tech.md` の `ssot_for` frontmatter に `model-effort-matrix` を追加

## Notes

- `run-auto-sub.sh` は orchestrator（他の run-*.sh を呼び出す）であり、直接 `claude -p` を呼ばないため変更不要
- `--effort` はハードコードで実装（phase ごとに固定値）。`.wholework.yml` でのカスタマイズは将来の拡張として検討
- run-spec.sh の `--opus` フラグは維持。model と effort は独立した軸であり、`--opus --effort max` の組み合わせで L-size spec の品質を最大化する
- agents の effort は parent session から継承される。例: run-review.sh が `--effort high` で実行すると、review-bug（Opus）や review-spec（Opus）もその effort で動作する
- Auto-resolved ambiguity: 各 phase の effort level は Anthropic ベンチマークと phase 特性（品質重要度・タスク複雑度）に基づいて設計。設計根拠は docs/tech.md のマトリクスに記録
- investigation agents（scope/risk/precedent）を Opus に変更した理由: これらは /issue の L/XL 並列調査（Step 11a）でのみ使用される。スコープ分析・リスク評価の精度が sub-issue 分割判断と受入条件品質に直結するため、Opus の正確性が必要
- Auto-resolved ambiguity: docs/tech.md の既存 Axis 1/2 エントリーは実装済み状態を反映するよう更新（「follow-up Issue」→ 実装済みの事実を記述）

## Issue Retrospective

### Ambiguity Resolution

3 件の曖昧性を検出し、全て自動解決:

1. **model + effort の具体的な組み合わせ**: 実装者が Anthropic ベンチマークと phase 特性に基づいて設計。docs/tech.md のマトリクスに根拠を記録する方針。ユーザーの「phase ごとに最適化」指示に基づく
2. **run-spec.sh の --opus フラグ**: 維持。model と effort は直交する設定軸であるため、既存の --opus は L-size spec の model 選択として機能継続
3. **効果検証方法**: 本 Issue はコード変更がメイン。定量検証は運用データが必要なため follow-up で対応

### Policy Decisions from Q&A

- **スコープ**: run-*.sh + agents + skills 全体（ユーザー選択）
- **最適化方針**: phase ごとに最適化（品質重視/コスト重視を phase 特性で使い分け）
- **設定方法**: ハードコード（phase ごとに固定値、.wholework.yml カスタマイズは将来検討）

### Acceptance Criteria Changes

Nothing to note（初回作成のため変更なし）

## Spec Retrospective

### Minor observations

- `--effort` の default 値（未指定時）が Claude Code CLI のドキュメントで明示されていないため、各 level の挙動は Anthropic ベンチマークと実運用で確認が必要
- agents は parent session の effort を継承する設計だが、将来 Agent ツールに effort パラメータが追加される可能性がある。その場合はマトリクスの agent 列に effort を個別設定する拡張が必要

### Judgment rationale

- effort level の設計: spec に max を割り当てたのは、Spec エラーが code/review/merge/verify の全後続 phase に波及するため、最も品質投資のリターンが大きい phase と判断した
- merge に low を割り当てたのは、merge 操作が squash-merge + branch 削除という機械的処理であり、高度な推論が不要なため
- investigation agents を Opus に変更: 当初は Sonnet で十分と判断していたが、L/XL Issue の sub-issue 分割精度と受入条件品質への影響を再評価し、Opus に引き上げ。review-bug/review-spec と同様、正確性が最重要な sub-agent は Opus を使う方針に統一
- run-issue.sh effort を medium → high に変更: L/XL の sub-agent 結果統合と分割判断の品質を確保するため。バッチ（XS/S のみ）でのコスト増は許容範囲

### Uncertainty resolution

- `--effort` が sub-agents に継承されるかどうかは Claude Code の内部動作に依存するが、Anthropic のドキュメントから推定。実装後に run-review.sh + review-bug の動作で間接的に確認可能
