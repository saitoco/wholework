# Issue #292: Core の skill-dev 実行時漏出を gate で塞ぐ (Core/Domain 分離 Phase 1)

## Auto Retrospective

### Execution Summary

| # | Title | Route | Result | Notes |
|---|-------|-------|--------|-------|
| 297 | /code の validate-skill-syntax.py 実行を存在 gate で囲む (Phase 1 Sub 1A) | patch (S) | SUCCESS | 1回目成功。lock 保持側 |
| 298 | /doc sync --deep の skill scan を skill-dev 判定 gate で囲む (Phase 1 Sub 1B) | patch (S) | SUCCESS (retry) | 初回 patch lock timeout (300s) で失敗→serial 再実行で成功 |
| 299 | /code の Stale Test Assertion Check を existence gate で囲む (Phase 1 Sub 1C) | patch (S) | SUCCESS (retry) | 初回 patch lock timeout (300s) で失敗→serial 再実行で成功 |

### Parallel Execution Issues

初回並列実行で 3 件中 2 件が `.tmp/claude-auto-patch-lock` の取得に失敗した。原因は patch route の lock 保持時間（code フェーズ全体＋CI wait で 15-30 分）に対し、lock 取得待ち timeout が 300 秒と短いこと。

タイミング実績:
- #297: code phase 開始 10:48:21 → 完了 ~11:22:30（約34分、CI wait 含む）
- #298: spec 完了 10:51:14 → lock 待ち 300s で timeout (初回失敗)
- #299: spec 完了 10:49:48 → lock 待ち 300s で timeout (初回失敗)

Serial 再実行で両方成功:
- #298 retry: 2026-04-21 11:23 → 11:48 (~25 分)
- #299 retry: 2026-04-21 11:48 → 12:13 (~25 分)

総所要時間: 初回並列失敗 + serial 再実行で約 1 時間 30 分。すべて serial なら同程度、並列が成功していれば 45-50 分程度に短縮できた見込み。

### Improvement Proposals

- **patch lock timeout を code phase の現実的な所要時間に合わせて拡張する**: 現在 300 秒だが、CI wait を含む code フェーズは 15-30 分かかる。並列 N 件が走るとき、最悪 N×(code phase 所要時間) まで待つ必要があるため、lock 取得 timeout は最低でも 1800 秒 (30分)、推奨 3600 秒 (60分) に拡張すべき。併せて `watchdog: waiting for lock` メッセージを定期出力して進捗を可視化。関連: `scripts/run-auto-sub.sh` または patch lock 実装箇所。
- **XL route の `execution_order` に lock 直列化を反映する仕組みを検討**: 現状 XL の `execution_order` は blocked_by ベースでのみ並列化を判定するが、「全 sub-issue が patch route」のケースは実質的に serial 実行になる。`get-sub-issue-graph.sh` 側で Size/Route 情報を考慮して patch route の sub-issue 群は `execution_order` で serial になるように調整する案。あるいは lock timeout 拡張の方が単純で十分かも。
- **並列失敗時の自動再試行**: lock timeout で失敗した sub-issue を `/auto` 側が自動検知して一度再試行する仕組み。今回は人が検知して手動 retry したが、失敗パターンが定型（lock timeout）なので自動化可能。

## Issue Retrospective

### 判断根拠 (sub-issue 分割)

Size=XL 親 Issue として作成したが、本文に既に Sub 1A/1B/1C の分割案を明示していたため parallel investigation (issue-scope/risk/precedent) をスキップし、既存の分割案をそのまま実行した。3 件は互いに独立した単一ファイル編集であり、並列実行の実証にも適する。

### 主要な方針決定

- Sub 1A/1B/1C は Size=S (単一ファイル・10行以下の変更、patch route 適合)
- 全 sub-issue に `scripts/validate-skill-syntax.py` 存在を skill-dev project 判定の主シグナルとして採用（wholework 自身では既に存在、他プロジェクトでは不在が明確）
- 「暗黙の skip」から「明示的な existence gate」への昇格を Sub 1C の主眼に据えた（Phase 2 の Domain 抽出対象として識別しやすくするため）

### 受入条件の変更理由

親 Issue の Pre-merge AC は当初 `grep` ベースだったが、本質は「gate が追加されているか」の意味判定なので `rubric` に統一した。

### Auto-Resolve Log

なし（親 Issue 本文の明示的な分割案に従って処理。ambiguity 点は検出されなかった）。
