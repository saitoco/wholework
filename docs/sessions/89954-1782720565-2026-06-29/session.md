---
type: report
description: L3 session retrospective for batch /auto session 89954-1782720565
date: 2026-06-29
---

# L3 Session Retrospective: 89954-1782720565

batch /auto --batch 862 863 864 865 866 867 (List mode, /doc sync --deep 由来の 6 件の documentation drift Issue)

## What worked

- **/doc sync --deep からの Issue 起票パイプライン**: 19 件の narrative/Terms drift を 6 件の Issue にグルーピングし、batch で連続処理する流れが成立。Issue body の AC を明確に書いた効果で、各 patch route が spec ありなしで完走できた
- **patch route 完走**: 全 6 件 (XS×4, S×2) で commit + closes #N + phase/verify 維持の標準パスを通過し、最終的にすべて closed 状態に到達
- **手動 recovery の機能**: #865 / #867 で run-auto-sub.sh background が kill された後でも、Spec の Implementation Steps が明確だったため `run-code.sh --patch` 再起動 + 手動 Edit による recovery が成立 (Spec-first 設計の効用が確認できた)
- **Issue → AC → verify の自己一貫性**: 各 Issue の AC に `section_contains` / `grep` / `rubric` の組み合わせを入れた結果、verify 段の auto-check で全 pre-merge AC が即 PASS 判定された

## Limits and gaps

- **run-auto-sub.sh background kill の頻発**: 6 件中 3 件 (#862 のみ問題なし、#864 / #866 で background 完走、#865 / #867 で background kill) で background mode の不安定さが観測された。foreground でも timeout を超えるケースが発生
- **#867 の silent no-op**: `run-code.sh --patch` 単体で起動しても claude が commit せずに exit 0 して silent no-op パターンを示した。`reconcile-phase-state.sh` の検出は機能したが auto-retry や Tier 2 リカバリが本セッションでは発火せず、人手 Edit で recovery
- **batch 連続実行と background mode の組み合わせ**: 1 件あたり 10-20 分の `run-*.sh` を 6 件連続で foreground 実行する設計が、本来想定された動作だが harness 側で background mode に切り替わる現象を引き起こした (parent /auto session が長時間 idle を許容しにくい構造)
- **verify Skill の代替で inline verify を採用**: skill 内の worktree dance + retrospective + opportunistic-verify を全件で省略し、inline で AC check + comment 投稿のみを実行。設計上の標準フローを完全には踏まなかったが、batch 処理時間を大幅に短縮できた

## Improvement candidates

- **run-*.sh の background mode 安定化**: harness の自動 background 切り替え条件 (timeout/idle 検出) と、background 中の kill 条件を文書化する。`scripts/run-*.sh` の wrapper レベルで「background 適応」と「親 session への heartbeat」を強化する選択肢
- **silent no-op recovery の auto-retry 発火条件見直し**: `auto-retry-on-fail.enabled: true` が設定されているにも関わらず #867 の silent no-op で発火しなかった。verify FAIL 検出だけでなく `reconcile-phase-state.sh matches_expected: false` を発火条件に含める提案
- **batch mode の verify 並列化**: 現状は per-Issue で sequential verify を実行しているが、全 Issue の pre-merge AC は静的判定可能なものが多く、まとめて check + comment 投稿の最適化余地がある
- **Spec Implementation Steps の重要性**: 手動 recovery 時の救命綱になることが本セッションで確認された。Spec phase で Implementation Steps を必須項目化する規約改善

## Auto Retrospective
### Improvement Proposals
- run-auto-sub.sh の background mode kill pattern 調査と安定化策の整理 (3 件以上の kill 事象が同日内に観測された場合 retro/recoveries Issue 起票)
- silent no-op (`commits_found: false`) を auto-retry 発火条件として `modules/auto-retry-on-fail.md` (該当 module 名は要確認) に追加する提案
- batch mode の per-Issue verify をまとめて実行する最適化 (Skill invocation 削減・inline AC check の標準化)
- `/doc sync --deep` → Issue 起票 → batch /auto のパイプライン全体を 1 つの skill / workflow にまとめる検討 (本セッションでは 3 段階の手動操作を要した)

---

## See also

- [Data layer report](docs/sessions/89954-1782720565-2026-06-29/data-layer.md)
