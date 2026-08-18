## Auto Retrospective
### Improvement Proposals
- Event-based observation scan (`auto-run` イベント) が78件の Issue にマッチしたが、`observation-dispatch-threshold` (default 5, oldest-pending-first) は常に同じ先頭5件 (#478, #562, #589, #590, #724) を選出する構造になっている。これら5件は Session 1 時点で既に4〜19回の再確認履歴を持ち、いずれも premise 不変で SKIPPED/UNCERTAIN が繰り返されている (#590 は19回目)。oldest-first + 固定 cap の組み合わせにより、この5件が事実上恒久的にスロットを占有し、より新しい observation-pending Issue が一度も dispatch されない可能性がある。本セッションでは変化なしと確認の上でフル dispatch を見送ったが、これは dispatch アルゴリズム自体の構造的ギャップであり、単発のスキップ判断では解消しない。
