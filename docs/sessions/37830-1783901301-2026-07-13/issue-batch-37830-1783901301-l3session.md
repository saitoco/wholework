# Batch session 37830-1783901301: L3 retrospective bridge

## Auto Retrospective
### Improvement Proposals
- バックグラウンド `claude -p` フェーズの原因不明な外部 kill (通算 7 回) の原因調査と、親セッション主導の再スポーン recovery を記録する機構の追加 (orchestration-recoveries.md / events.jsonl への記録、`--write-manual-recovery` の repo-root 自己正規化を含む)
- 親セッション内 Skill() 実行の verify における `verify_reopen_cycle` / `verify_fail_marker_posted` / `verify_retry_fire` イベント emit 漏れの調査と再発防止 (PGID ポインタファイル再生成前提の構造見直し)
- get-auto-session-report.sh の Issues processed 集計への PR 番号混入の修正 (auto-retry で親セッションから run-review.sh / run-merge.sh を直接呼ぶ経路の wrapper イベント issue フィールド正規化)
