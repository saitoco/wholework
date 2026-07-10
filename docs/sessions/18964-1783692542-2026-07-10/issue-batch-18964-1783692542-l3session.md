# Bridge file for retro-proposals (batch session 18964-1783692542)

## Auto Retrospective

### Improvement Proposals

- Metrics/イベント集計にも PR/Issue 番号混同が波及: 本 session report の "Issues processed: 10" は PR #978/#983/#985 を独立 Issue として誤集計し、Timeline に Size "?/?" の行が混入、Tier 3 recovery も #983 に帰属している。review/merge phase のイベント emit (`EMIT_ISSUE_NUMBER`=PR 番号) が根本原因で、#974 (自己除外) / #984 (recovery 記録) と同根の第 3 の surface。イベント emit 時または集計時に PR→Issue 解決を挟むべき。[Filed: #987]
- Tier 3 recovery (review phase, 実体は #970/PR #983) の記録が PR 番号を Issue 番号として誤使用。verify フェーズで是正済み。[Filed: #984]
- リトライ成功後の exit-0 経路で false-positive anomaly echo が 2 件 (#964, #971)。[Filed: #981]
- `--batch --resume` 時の spec phase 再ディスパッチ。[Filed: #977]
- XS patch route (batch 経由) の Issue Retrospective Spec 転記欠落。[Filed: #982]
- recovery 記録 push の non-fast-forward 失敗。[Filed: #986]
