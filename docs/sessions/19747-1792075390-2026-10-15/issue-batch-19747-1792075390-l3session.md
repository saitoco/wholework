## Auto Retrospective

### Improvement Proposals

- batch route の L3 notable 判定にある「セッションのコミットが 3 件以上」という条件が、observation dispatch の `/verify` が積む Consumed Comments フォールバックのコミット (今回は #1200, #1213, #1221, #1224, #1226 の 5 件) も数えている。そのため、recovery、FAIL、kill がいずれも 0 件のきれいな 2 件 batch でも notable と判定された。機械的なフォールバックのコミットを数えないようにするか、batch 対象 Issue の実装コミットだけを数えるように条件を絞るべき
