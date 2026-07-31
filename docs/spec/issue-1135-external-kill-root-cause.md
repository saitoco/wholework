# Issue #1135: auto: 外部 kill の根本原因特定 (H-a 一般形/H-b/H-c) — wrapper_alive 分析と実行サーフェス切り分け実験

## Overview

`/auto --batch` セッション中に背景 `run-*.sh` wrapper がプロセスグループごと外部 kill される事象 (通算 30 回超) について、`docs/reports/external-kill-investigation.md` (#1005 / #1014、2026-07-15 更新で停止) の調査を再開する。

2 つの未追跡 lead を使って残存仮説 (H-a 一般形: harness の per-background-task lifecycle / H-b: 端末・シェル側 / H-c: その他) を確定または棄却する:

1. **wrapper_alive ヒートビートデータの分析**: #1045 (PR #1048) で導入された `wrapper_alive` イベントと、同期間の kill 発生 (`manual_intervention` イベント) を突合し、kill が subprocess 実行中に起きているか wrapper 制御フロー中に起きているかを分類する
2. **実行サーフェス切り分け実験**: 同等の batch 実行を (a) Claude Code セッション内の harness 管理下 background Bash 起動と (b) harness 外の起動 (`nohup` / `setsid` / `tmux` / `launchd` のいずれか) で比較し、kill 発生率を数値で記録する

判定結果に基づき、次アクション (Anthropic への報告準備、#598 再評価、respawn 補償層の縮小検討等) を Related Issue へのコメントまたは新規 Issue として接続する。

## Changed Files

- `docs/reports/external-kill-investigation.md`: 既存レポートの末尾に日付付き Update 節を 2 つ追記する — (1) `wrapper_alive` × kill 突合分析、(2) 実行サーフェス切り分け実験の設計・結果・H-a/H-b/H-c 判定・次アクション接続

## Implementation Steps

1. `wrapper_alive` チェックポイントイベントと `manual_intervention` (kill) イベントを突合する。対象は committed 済みの session ログ `docs/sessions/25766-1785288928-2026-07-29/events.jsonl` と `docs/sessions/46196-1785292524-2026-07-31/events.jsonl` (実行時点で新たに commit されている `docs/sessions/*/events.jsonl` があれば同様に対象に含める) — **`.tmp/auto-events.jsonl` はセッションローカルかつ gitignore 対象で過去データを保持しないため使用しない**。各 kill 発生を「kill 直前の最終チェックポイントが `pre_subprocess` で、対応する完了チェックポイントが記録されていない」= subprocess 実行中の kill、「`pre_phase_dispatch` / `post_code_pre_review` の後、次の `pre_subprocess` の前」= wrapper 制御フロー中の kill、のいずれかに分類する (→ 受入条件 1, 2)
2. 実行サーフェス切り分け実験を設計・実行する。同等規模の batch ワークロードを (a) Claude Code セッション内の harness 管理下 background Bash 起動 (`run_in_background: true`) と (b) harness 外の起動 (`nohup ... & disown` / `setsid` / `tmux new-session -d` / `launchd` のいずれか一つを選び、選定理由を記録する) の 2 方式で実行し、Issue 件数・実行時間帯を両アーム間で揃える。各アームの kill 発生率を数値 (発生件数 / 実行件数) で記録する (after 1) (→ 受入条件 3, 4)
3. 手順 1・2 の結果から、H-a 一般形・H-b・H-c それぞれについて「確定」「棄却」「未決」のいずれかの判定を根拠とともに記録する。判定に基づく次アクション (Anthropic への報告準備、#598 再評価トリガーの再確認、respawn 補償層縮小の要否検討等) を、関連する Related Issue (#1070 / #1081 / #1093 / #598 / #483 のいずれか適切なもの) へのコメント、または新規 Issue として接続する。あわせて、実験結果から導かれる運用上の回避策 (特定の起動方式を推奨する等) があれば明記し、有効な回避策が見つからない場合は「回避策なし — 既存の respawn 補償層による観測を継続する」と明記する。この記述が Post-merge 受入条件の比較基準になる (after 2) (→ 受入条件 5, Post-merge 受入条件)
4. 手順 1〜3 の内容を Update 節としてまとめ、`docs/reports/external-kill-investigation.md` の末尾に追記する (見出し例: `## 2026-08-01 Update (wrapper_alive correlation + isolation experiment)`)。追記内容に `wrapper_alive` / `切り分け実験` / `H-a` の文字列が含まれることを確認する (after 1, 2, 3) (→ 受入条件 1-6)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/external-kill-investigation.md に 2026-07-29 以降の日付を持つ Update 節が追記され、wrapper_alive イベント (7/29-31 の記録) と同期間の kill 発生 (subprocess 実行中 / 制御フロー中の別) の突合分析が含まれている" --> wrapper_alive データと kill 発生の突合分析が investigation レポートに追記されている
- <!-- verify: file_contains "docs/reports/external-kill-investigation.md" "wrapper_alive" --> レポートに `wrapper_alive` への言及が含まれている
- <!-- verify: rubric "実行サーフェス切り分け実験の設計と結果が external-kill-investigation.md に記録されている。具体的には、同等の batch 実行を (a) Claude Code セッション内の background Bash 起動と (b) harness 外の起動 (nohup / setsid / tmux / launchd のいずれか) で比較し、それぞれの kill 発生率が数値で記録されている" --> 実行サーフェス切り分け実験 (harness 内 vs harness 外) の結果が数値で記録されている
- <!-- verify: file_contains "docs/reports/external-kill-investigation.md" "切り分け実験" --> レポートに切り分け実験への言及が含まれている
- <!-- verify: rubric "H-a 一般形 / H-b / H-c のそれぞれについて、確定・棄却・未決のいずれかの判定と根拠が external-kill-investigation.md に明記され、判定に基づく次アクション (Anthropic への報告準備、#598 再評価、respawn 補償層の縮小検討など) が Related Issue へのコメントまたは新規 Issue として接続されている" --> 各仮説の判定と次アクションの接続が明記されている
- <!-- verify: file_contains "docs/reports/external-kill-investigation.md" "H-a" --> レポートに `H-a` への言及が含まれている

### Post-merge

- 切り分け実験の結論に基づく回避策を適用した状態の `/auto --batch` で、`manual-recovery-respawn` の新規エントリ発生率が適用前と比較・記録されている <!-- verify-type: manual -->

## Notes

- **Issue body vs. 実装の整合確認**: Background で言及される `docs/reports/external-kill-investigation.md` の存在、`wrapper_alive` イベントの実装箇所 (`scripts/emit-event.sh`, `scripts/run-auto-sub.sh`)、`.tmp/auto-events.jsonl` の実在はいずれもコードベース調査で裏付けを確認した。矛盾は検出されなかった。
- **データソースの選択**: Issue Background は `.tmp/auto-events.jsonl` に 7/29-31 の 31 件が記録済みと述べているが、この worktree では `.tmp/` はセッションローカルかつ gitignore 対象のため、そのままでは参照できない。同等のデータは commit 済みの `docs/sessions/25766-1785288928-2026-07-29/events.jsonl` と `docs/sessions/46196-1785292524-2026-07-31/events.jsonl` に保持されていることを確認済み (`wrapper_alive` チェックポイントと `manual_intervention` イベントの両方が存在し、7/31 分は 3 件で Background の記述と一致)。Implementation Steps はこの commit 済みログを分析対象として明記した。
- **実験規模の目安**: 実行サーフェス切り分け実験で実 backlog Issue を batch 対象に使う場合、2026-07-15 の先行 H-a 切り分け実験 (session 32651, `docs/reports/external-kill-investigation.md` 該当 Update 節) が 5 Issue 規模で実施されている。今回も同程度の小規模を目安とし、両アームの比較可能性 (件数・実行時間帯) を優先する。
- **Post-merge 受入条件の前提**: Issue の Auto-Resolve Log (Issue Retrospective コメント参照) により、実験の結果、有効な回避策が存在しない場合は「既存の respawn 補償層をそのまま用いた場合の観測継続」を比較基準とすることが既定方針として確認済み。Implementation Step 3 でこの基準を明記する。

## Consumed Comments

- **saito** (MEMBER, first-class) — `/issue` フェーズの Issue Retrospective コメント。非対話モードでの Auto-Resolve Log (H-c の判定基準をデフォルト「未決」とする根拠、Post-merge AC の回避策が調査結果依存であることの扱い) と、Background 事実確認の結果 (裏付け確認済み) を記録。本 `/spec` フェーズへの直接のアクション項目はなし、設計はそのまま踏襲。
  https://github.com/saitoco/wholework/issues/1135#issuecomment-5144982703
