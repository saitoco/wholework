## Auto Retrospective
### Improvement Proposals

- `detect-external-kill.sh` の `--log` 引数に連結ログ (複数フェーズの累積出力) を渡すと、別フェーズの `Exit code: 0` トレーラを拾って偽陰性 (`no-match`) を返す実害を本セッションで直接踏んだ。現行のガイダンスは「フェーズ単位にスコープする」ことを明記していないため、次回同じ誤りが再発しうる。
