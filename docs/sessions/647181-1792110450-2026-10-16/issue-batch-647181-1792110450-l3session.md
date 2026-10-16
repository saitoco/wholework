## Auto Retrospective

### Improvement Proposals

- batch route の L3 notable 判定の「セッションのコミットが 3 件以上」という条件が、observation dispatch の `/verify` が積む Consumed Comments フォールバックのコミット (今回は #1227, #1241, #1255, #1271, #1278 の 5 件) や Spec のフェーズ記録のコミットまで数える。そのため、recovery、FAIL、kill がいずれも 0 件の batch でも毎回 notable と判定される。前回のセッション `19747-1792075390` でも同じ現象が起きて Tier 2 (メモの提案) に分類しており、今回で 2 セッション連続の再発になる。`skills/auto/SKILL.md` Step 5 の L3 notable 判定で、数えるコミットを batch 対象 Issue の実装コミット (`closes #N` またはマージコミット) に絞るべき
