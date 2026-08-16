# Session batch-24095-1786827554-l3session

## Auto Retrospective
### Improvement Proposals
- `skills/audit/SKILL.md` の Manual Waiting Count と `skills/auto/SKILL.md` の Pending manual confirmation 集計が、`ac-tier: preview` タグを持つ pre-merge AC を無条件除外しており、`/review` が UNCERTAIN のまま残した preview AC まで誤って除外する undercounting が生じている。`resolve-preview-ac-fallback.sh` 相当のマーカー解決ロジックの統合を提案する。
- `modules/phase-handoff.md` の Write Procedure が、ローテーション時に既存の `## Phase Handoff` ブロックを確実に置換できていないケースがあり (`/merge` フェーズの書き込みで検出)、決定論的 bash fallback の追加を提案する。
