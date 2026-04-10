# Issue #108: effort: phase 別 model・effort マトリクスの設計・実装

## Overview

#70 で調査した effort 最適化 3 軸のうち、Axis 1（model 選択）と Axis 2（--effort パラメータ）を組み合わせ、run-*.sh・agents・skills 全体で phase ごとに性能・コストバランスを最適化する。

現状は全 run-*.sh が Sonnet + effort 指定なし（デフォルト）で統一されているが、phase ごとの品質要求・複雑度が異なるため、effort level を使い分けることで品質重視の phase とコスト重視の phase を分離する。

## Changed Files

- `docs/tech.md`: Architecture Decisions の Effort optimization strategy エントリーを更新。phase 別 model・effort マトリクステーブルを追加し、Axis 1/2 の記述を実装済み状態に更新
- `scripts/run-spec.sh`: `claude -p` 呼び出しに `--effort max` を追加、echo 出力に Effort 表示を追加
- `scripts/run-code.sh`: `claude -p` 呼び出しに `--effort high` を追加、echo 出力に Effort 表示を追加
- `scripts/run-review.sh`: `claude -p` 呼び出しに `--effort high` を追加、echo 出力に Effort 表示を追加
- `scripts/run-issue.sh`: `claude -p` 呼び出しに `--effort medium` を追加、echo 出力に Effort 表示を追加
- `scripts/run-merge.sh`: `claude -p` 呼び出しに `--effort low` を追加、echo 出力に Effort 表示を追加
- `scripts/run-verify.sh`: `claude -p` 呼び出しに `--effort medium` を追加、echo 出力に Effort 表示を追加

agents/*.md: 変更不要（現在の model 配置は phase 特性に合致。根拠は docs/tech.md マトリクスに記載）
skills/triage/SKILL.md: 変更不要（Sonnet は triage タスクに十分。根拠は docs/tech.md マトリクスに記載）

## Implementation Steps

1. docs/tech.md の Architecture Decisions を更新する（→ 受入条件 A, H, I）
   - 既存の "Effort optimization strategy (3 axes)" エントリー内の Axis 1 記述 "No further action needed" を "Reviewed and confirmed" に更新
   - Axis 2 記述の "Implementation in run-*.sh is a follow-up Issue" を実装済み状態に更新
   - 以下の phase 別 model・effort マトリクステーブルを追加:

   | Component | Phase | Model | Effort | Rationale |
   |-----------|-------|-------|--------|-----------|
   | run-spec.sh | spec | Sonnet (Opus via `--opus`) | max | Design quality is critical; spec errors propagate to all subsequent phases |
   | run-code.sh | code | Sonnet | high | Implementation requires thorough reasoning |
   | run-review.sh | review | Sonnet | high | Review orchestration; sub-agents handle deep analysis |
   | run-issue.sh | issue | Sonnet | medium | Metadata and Q&A; moderate complexity |
   | run-verify.sh | verify | Sonnet | medium | Structured acceptance testing; moderate complexity |
   | run-merge.sh | merge | Sonnet | low | Mechanical merge operation; minimal reasoning needed |
   | review-bug | review | Opus | — | Bug detection requires highest accuracy (sub-agent, effort inherited from parent) |
   | review-spec | review | Opus | — | Spec deviation requires high accuracy (sub-agent, effort inherited from parent) |
   | review-light | review | Sonnet | — | Lightweight integrated review (sub-agent, effort inherited from parent) |
   | scope-agent | issue | Sonnet | — | Scope investigation; moderate complexity (sub-agent) |
   | risk-agent | issue | Sonnet | — | Risk investigation; moderate complexity (sub-agent) |
   | precedent-agent | issue | Sonnet | — | Precedent pattern matching; moderate complexity (sub-agent) |
   | triage (skill) | triage | Sonnet | — | Metadata assignment; Sonnet sufficient (direct invocation, effort not set) |

2. quality-critical な run-*.sh に --effort を追加する（→ 受入条件 B, C, D）
   - run-spec.sh: `claude -p` 呼び出し（L61-64）に `--effort max` を追加。echo 出力に `echo "Effort: max"` を追加
   - run-code.sh: `claude -p` 呼び出し（L103-107）に `--effort high` を追加。echo 出力に `echo "Effort: high"` を追加
   - run-review.sh: `claude -p` 呼び出し（L52-56）に `--effort high` を追加。echo 出力に `echo "Effort: high"` を追加

3. cost-efficient な run-*.sh に --effort を追加する（→ 受入条件 E, F, G）
   - run-issue.sh: `claude -p` 呼び出し（L55-59）に `--effort medium` を追加。echo 出力に `echo "Effort: medium"` を追加
   - run-merge.sh: `claude -p` 呼び出し（L44-48）に `--effort low` を追加。echo 出力に `echo "Effort: low"` を追加
   - run-verify.sh: `claude -p` 呼び出し（L76-80）に `--effort medium` を追加。echo 出力に `echo "Effort: medium"` を追加

## Alternatives Considered

- **全 phase を high effort で統一**: シンプルだが、triage/merge のようなコスト重視 phase で不要な推論コストが発生する。phase ごとの最適化が本 Issue の目的であるため不採用
- **agents にも effort を設定**: Claude Code の Agent ツールに effort パラメータはなく、sub-agent は parent session の effort を継承するため、独立設定は不可。run-*.sh の effort が間接的に sub-agents にも影響する
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
- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "review-bug" --> `agents/*.md` の model frontmatter をマトリクスに基づいて見直し・更新（変更不要の場合は根拠を docs/tech.md に記載）
- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "triage" --> Skills の model frontmatter をマトリクスに基づいて見直し・更新（変更不要の場合は根拠を docs/tech.md に記載）

## Notes

- `run-auto-sub.sh` は orchestrator（他の run-*.sh を呼び出す）であり、直接 `claude -p` を呼ばないため変更不要
- `--effort` はハードコードで実装（phase ごとに固定値）。`.wholework.yml` でのカスタマイズは将来の拡張として検討
- run-spec.sh の `--opus` フラグは維持。model と effort は独立した軸であり、`--opus --effort max` の組み合わせで L-size spec の品質を最大化する
- agents の effort は parent session から継承される。例: run-review.sh が `--effort high` で実行すると、review-bug（Opus）や review-spec（Opus）もその effort で動作する
- Auto-resolved ambiguity: 各 phase の effort level は Anthropic ベンチマークと phase 特性（品質重要度・タスク複雑度）に基づいて設計。設計根拠は docs/tech.md のマトリクスに記録
- Auto-resolved ambiguity: agents の model 配置（Opus 2本、Sonnet 4本）は現在も phase 特性に合致しており変更不要。根拠を docs/tech.md のマトリクスに記載
- Auto-resolved ambiguity: docs/tech.md の既存 Axis 1/2 エントリーは実装済み状態を反映するよう更新（「follow-up Issue」→ 実装済みの事実を記述）
