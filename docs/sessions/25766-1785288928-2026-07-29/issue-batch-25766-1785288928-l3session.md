# L3 session bridge: batch-25766-1785288928

## Auto Retrospective

### Improvement Proposals

- **`/review` が bats をバックグラウンド実行して通知待ちのままターンを終える silent no-op を起こす**。#1061 の 3 回目 review で「bats のバックグラウンド実行完了を待ちます (通知が届き次第、続行します)。」を最後に出力してセッションが終了し、`run-review.sh` が「claude exited 0 but review phase did not complete (silent no-op)」を検出した。headless (`claude -p`) 実行では完了通知が届かないため、この待機は必ず無期限になる。fallback で復旧はしたが、Response Summary が自動生成の定型文に置き換わり review の締めくくり情報が失われる。
- **Tier 3 recovery が 2 回発火したのに Metrics の「Tier 1/2/3 recoveries」が 0/0/0 のまま**。#1060 と #1061 の review フェーズで `[spawn-recovery] action=retry: re-invoking run-review.sh` がログに出ているが、`events.jsonl` に `recovery` event が 1 件も記録されていない (event 種別一覧に `recovery` が存在しない)。両方とも retry 自体が外部 kill されたため、成功時のみ emit する実装になっている可能性がある。いずれにせよ「発火した recovery の回数」が観測できず、`recoveries-auto-fire` の threshold 判定にも影響する。
- **`observation-trigger.sh` が副作用 (advisory コメント投稿) を持つのに冪等でない**。親セッションが出力形式を確認するため同スクリプトを 3 回実行し、11 件の Issue に同一の advisory コメントが 3 通ずつ投稿された。呼び出し側の運用ミスではあるが、同一 event・同一 Issue に対する直近のコメントが既に存在する場合は再投稿しない dedup ガードがあれば、この種のノイズは構造的に防げる。
