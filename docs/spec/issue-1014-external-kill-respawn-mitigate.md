# Issue #1014: recoveries: manual-recovery-respawn の再発原因を特定・解消

## Overview

`manual-recovery-respawn` 症状 (バックグラウンド `run-*.sh` wrapper のプロセスグループが外部要因で停止し、親 `/auto` セッションが Tier 1/2/3 復旧機構の外側で検知・再スポーンするパターン) が `docs/reports/orchestration-recoveries.md` に5件記録され、`recoveries-auto-fire` の閾値 (3件) を超過した。既存の記録機構 (#1005 で導入、#1012 で堅牢化) は recovery の記録自体には成功しているが、kill の発生源 (`docs/reports/external-kill-investigation.md` の残存仮説 H-a/H-b/H-c) は未解明のまま残っている。

本 Spec 作成セッション自身が、作成作業中に issue #1014 の spec phase で6件目の `manual-recovery-respawn` を実地に経験した (session `12825-1784042432`、worktree lock 所有者 PID 12954 の死亡を確認、`.tmp/auto-events.jsonl` に backfilled `phase_complete` を確認)。この生きたインシデントを含めて追加調査した結果、以下の新知見を得た (根拠の詳細は Notes を参照)。

1. **全件が `/auto --batch` セッション中に発生**: 元調査 (7件、`external-kill-investigation.md`) と本 Issue の6件、合計13件すべてが `--batch` セッション中の発生であり、単発 `/auto`・`/spec`・`/code` 実行での発生は確認されていない。
2. **phase による kill シグナル種別の相関 (小サンプルの傾向)**: spec phase の kill 2件 (#1006, #1014) はいずれも EXIT trap が発火した backfilled `phase_complete` を残す (SIGTERM 系) 一方、code/review phase の kill 4件 (#1012, #1007 ×2, #1006) はいずれも残さない (SIGKILL 系。元調査の F1/F2 と整合)。
3. **`wrapper_exit_code` 観測ギャップ**: 記録済みの6件の `manual_intervention` イベントすべてで `wrapper_exit_code` が文字列 `"unknown"` であり (6/6, 100%)、`external-kill-investigation.md` の Future Observation Plan が見込んでいたデータ源 (実際の exit code 分布による H-a/b/c 絞り込み) は機能していないことが判明した。

H-a (Claude Code harness のバックグラウンドタスクライフサイクル)・H-b (ターミナル/シェル側プロセスグループ kill)・H-c (不明) はいずれも今回の追加調査でも確定に至らなかった。これを踏まえ、本 Issue の Purpose が許容する2つの解決経路 ── kill 発生源の除去、または再スポーンの自動化 ── のうち、**再スポーンの自動化 (検知の機械化)** を採用する。発生源そのものの除去については、`wrapper_exit_code` という主要な将来データ源が事実上機能していないことが判明した以上、新たに得られた検証可能な手がかりがなく、これ以上の根本原因追跡は投資対効果が低いと判断した。

## Consumed Comments

No new comments since last phase. (cutoff: 2026-07-14T18:01:57Z, most recent `phase/spec` label assignment; Issue has 1 comment total, predating cutoff; no `<!-- wholework-event: type=verify-fail` markers found)

## Changed Files
- `scripts/detect-external-kill.sh`: new file — bash 3.2+ compatible. External kill シグネチャ (exit code `137` 単独で確定的、または exit code `143` もしくは未観測 (`unknown`/空) かつ wrapper log に `Exit code: ` trailer 欠如かつ `auto-events.jsonl` に該当 `wrapper_exit` イベント欠如) を機械的に判定する。`modules/orchestration-fallbacks.md#external-kill-parent-respawn` へのポインタコメントを含める
- `tests/detect-external-kill.bats`: new file — 上記スクリプトの各分岐 (usage error / no-match / exit137 match / exit143+両マーカー欠如 match / unknown+両マーカー欠如 match / `wrapper_exit` イベント存在時の no-match) をカバー
- `docs/structure.md`: `### Scripts` の一覧 (Process management) に `scripts/detect-external-kill.sh` を追加。Directory Layout の `scripts/ ... (65 files)` コメントを `(66 files)` に更新
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー同期 (`docs/translation-workflow.md` 手順に従う)
- `skills/auto/SKILL.md`: Step 6 "External kill pre-check" の検知シグネチャ記述 (現状プレーンテキストでの条件記述) を `scripts/detect-external-kill.sh` 呼び出しに置き換える (`modules/detect-wrapper-anomaly.sh` の Tier 2 呼び出しパターンに合わせる)。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-external-kill.sh:*` を追加
- `docs/reports/external-kill-investigation.md`: 2026-07-15 付の追記セクションを追加 (6件の manual-recovery-respawn 分析、`--batch` セッション相関、phase 別シグナル種別相関、`wrapper_exit_code` 観測ギャップ、採用した緩和方針の決定を記録)
- `docs/workflow.md`: "External kill respawn" の記述にある "process group SIGKILLed rather than exiting normally" という限定表現を、spec phase では SIGTERM 系 (backfilled `phase_complete`) も観測されている旨を反映するよう修正
- `docs/ja/workflow.md`: 上記の日本語ミラー同期
- `docs/reports/orchestration-recoveries.md`: 既存5件の `manual-recovery-respawn` エントリ (2026-07-14 17:40 UTC #1012 code-patch, 2026-07-13 18:28 UTC #1007 review, 2026-07-13 18:28 UTC #1007 code-pr, 2026-07-13 17:00 UTC #1006 code-pr, 2026-07-13 16:58 UTC #1006 spec) の `### Improvement Candidate` を `未起票` から `起票済み #1014` に更新
- [Steering Docs sync candidate] `docs/tech.md` / `docs/ja/tech.md`: "Parent-session manual respawn" 節 (`## Architecture Decisions`) の記述を確認済み — 外部契約レベルの説明 (記録先3箇所、Tier 1/2/3 外という位置づけ) に留まり、本 Spec の変更後も正確なため変更不要と判断 (`/code` で再確認)

## Implementation Steps

1. `scripts/detect-external-kill.sh` (bash 3.2+ 互換) と `tests/detect-external-kill.bats` を追加する。`docs/structure.md` (および `docs/ja/structure.md` ミラー) の Scripts 一覧・ファイル数コメントを更新する (→ 受入条件A: mitigation 実装)
2. `skills/auto/SKILL.md` Step 6 "External kill pre-check" の検知記述を `scripts/detect-external-kill.sh` 呼び出しに置き換え、frontmatter `allowed-tools` に同スクリプトを追加する (after 1) (→ 受入条件A: 再スポーン検知の自動化)
3. `docs/reports/external-kill-investigation.md` に本 Spec の追加知見 (`--batch` セッション相関、phase 別シグナル相関、`wrapper_exit_code` 観測ギャップ、緩和方針決定) を追記する。`docs/workflow.md` (および `docs/ja/workflow.md` ミラー) の SIGKILL 限定表現を修正する (parallel with 1, 2) (→ 受入条件A: 根本原因調査結果の文書化)
4. `docs/reports/orchestration-recoveries.md` の既存5件の `manual-recovery-respawn` エントリの `Improvement Candidate` を `起票済み #1014` に更新する (parallel with 1, 2, 3) (→ 受入条件B)

## Verification

### Pre-merge
- <!-- verify: rubric "each cause group listed in this Issue has an identified root cause or documented mitigation plan" --> 本 Issue に列挙された cause group (外部 kill によるバックグラウンド wrapper のプロセスグループ停止) について、調査結果と採用した緩和方針が文書化されている
- <!-- verify: file_contains "docs/reports/orchestration-recoveries.md" "起票済み #1014" --> 既存の manual-recovery-respawn エントリの Improvement Candidate が更新されている
- <!-- verify: command "bats tests/detect-external-kill.bats" --> 新規 bats テストが PASS する

### Post-merge
- <!-- verify: rubric "orchestration-recoveries.md contains no '未起票' Improvement Candidate entries for manual-recovery-respawn newer than this Issue's creation date" --> <!-- verify-type: auto --> 本 Issue 作成日以降、新規の manual-recovery-respawn エントリが `未起票` のまま残っていないことを確認する (`/verify` が自動判定)

## Notes

### 生きたインシデントの扱い (worktree 再利用の判断)

本 `/spec` 実行開始時、`.claude/worktrees/spec+issue-1014` が `worktree lock` 済み (`claude session spec/issue-1014 (pid 12954 start Tue Jul 14 17:59:17 2026)`) の状態で既に存在していた。`ps -p 12954` でプロセス死亡を確認し (positive evidence)、`git status --porcelain` / `git diff main` がいずれも空 (未コミット変更なし) だったため、`modules/worktree-lifecycle.md` の reuse 判定に従い `git worktree unlock` の上 `EnterWorktree(path: ...)` で再利用した。この worktree は session `12825-1784042432` (issue #1012 完了後、#1014 の spec phase 実行中に kill された) の残骸であり、この kill 自体が本 Issue が調査対象とする symptom の6件目の実例である。

### 新知見の根拠 (measurement scope 明記)

- **バッチセッション相関**: `.tmp/auto-events.jsonl` の `manual_intervention` イベント6件 (issue 1006 ×2, 1007 ×2, 1012 ×1, および本セッション) の `session_id` を遡ると、#1006/#1007 は session `33265-1783950923` (batch 判定根拠: `"event":"next_cycle_seeded"` に `"batch_session_id":"33265-1783950923"` が付随)、#1012/#1014 は session `12825-1784042432` (batch 判定根拠: `.tmp/auto-batch-state-81514-1784042456.json` の `remaining:[1014,1015], completed:[1012]`) と、いずれも `--batch` セッション。元調査 (`external-kill-investigation.md` Background) の7件も明示的に `/auto --batch session 37830-1783901301` および `session 11543 系` と記載されており、確認できた13件全件が `--batch` セッション中の発生。
- **phase 別シグナル相関**: `.tmp/auto-events.jsonl` を `"backfilled":true` でフィルタし、`"phase":"spec"` かつ該当 issue/session に絞ると #1006 (`ts:2026-07-13T16:12:02Z`, session `33265-...`) と #1014 (`ts:2026-07-14T18:09:12Z`, session `12825-...`, 本インシデント) の2件のみヒット。同じ `manual_intervention` 記録済み6件のうち非 spec phase (#1012 code-patch, #1007 review/code-pr, #1006 code-pr) の4件は `backfilled:true` の `phase_complete` が存在しない。サンプル数 (2 vs 4) は小さく、確定的な結論ではなく追加検証が必要な傾向として記載する。
- **`wrapper_exit_code` 観測ギャップ**: `grep '"event":"manual_intervention"' .tmp/auto-events.jsonl` で得られる6件全てが `"wrapper_exit_code":"unknown"`。`scripts/run-auto-sub.sh` の `--write-manual-recovery` サブコマンドは `_mr_exit_code="${4:-}"` で呼び出し元 (親セッション LLM) が渡した値をそのまま使うのみで、スクリプト自身が OS レベルの終了コードを自動取得する経路は存在しない。`skills/auto/SKILL.md` Step 6 の検知シグネチャ記述は exit code `137`/`143` の観測を前提にしているが、実際の6件はいずれも exit code 自体が親セッションから観測不能 (`unknown`) であり、ドキュメントが想定する分岐と実態が乖離していた。この乖離が本 Issue の実装 (`scripts/detect-external-kill.sh` の判定条件に unknown/空文字列のケースを明示的に含める) の直接の動機。

### スコープ外の除外

- `docs/reports/orchestration-recoveries.md` の `## 2026-07-13 17:12 UTC: manual-recovery-skip-forward` (#1007, phase: issue) は、本 Issue 本文の Source Entries 表に含まれない別 symptom (`recovery type: skip-forward`) であるため、Improvement Candidate 更新の対象外とする。
- 本セッション自身の kill (issue #1014, spec phase, session `12825-1784042432`) は、`docs/reports/orchestration-recoveries.md` への記録 (`--write-manual-recovery` 呼び出し) が本 `/spec` フェーズ完了後に親セッションによって行われる想定であり、Spec 執筆時点では未記録 (5件のまま)。そのため Pre-merge AC2 (`起票済み #1014` への更新) は現存する5件のみを対象とする。6件目のエントリは `/code` 以降または次回 `/audit recoveries` サイクルで捕捉される想定であり、本 Spec の実装漏れではない。

### `docs/tech.md` の sync candidate 判断

`docs/tech.md` § Architecture Decisions の "Parent-session manual respawn (outside the Tier 1/2/3 machinery)" 段落を確認した。記録先3箇所 (Spec / `orchestration-recoveries.md` / `manual_intervention` イベント) という外部契約レベルの説明に留まり、検知ロジックの内部実装 (プレーンテキスト判定 vs `detect-external-kill.sh` 呼び出し) には触れていないため、本 Spec の変更後も記述は正確なまま変更不要と判断した。`/code` フェーズで変更差分確定後に再確認する。

### bash 互換性

`scripts/detect-external-kill.sh` は `scripts/detect-wrapper-anomaly.sh` と同様、macOS システム bash (3.2) 互換の構文 (`mapfile` 等の bash 4+ 専用機能を使わない) で実装する。

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (Step 3 チェック)**: `/code` 開始時、Issue #1014 のラベルは `phase/ready` ではなく既に `phase/code` だった (ラベル履歴で `phase/ready`→`phase/code` の遷移が確認できた)。これは本 Issue 自身が調査対象とする `manual-recovery-respawn` 症状により、直前の `/code` 実行が Step 4 (worktree entry + label transition) 完了後・実装完了前に外部 kill されたため (`run-code.sh` がセッション開始前に stale worktree/branch を検出・削除済み)。Spec (`docs/spec/issue-1014-external-kill-respawn-mitigate.md`) は既に完全な内容で存在することを確認できたため、「Spec なしで Issue 本文から実装」の auto-resolve 分岐は適用せず、既存 Spec をそのまま使用して実装を継続した。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 を記載順どおりに実装した。

### Design Gaps/Ambiguities
- Spec は `scripts/detect-external-kill.sh` の CLI インターフェース (フラグ名、exit code の意味、`--events` ファイル欠如時の扱い) を明記していなかったため、`scripts/test-failure-classify.sh` (exit 0 = 該当, exit 1 = 非該当という2値パターン) を参考に設計した。`--events` ファイルが存在しない場合は "corroborating evidence なし" として `external-kill` 側に倒す (該当シグネチャの検出漏れより過検出の方が安全 — 誤って respawn しても `code_phase_milestone` チェックポイントにより冪等に再開できるため)。
- `auto-events.jsonl` の `wrapper_exit` イベント照合で、issue/phase が同一行 (同一 JSON イベント) で一致するかを確認する必要があった。単純に `grep` を3回ファイル全体に対して実行すると、別々の行にある issue 一致・phase 一致が誤って「同一イベントに一致」と判定されるバグになる (false negative: 本来 external-kill と判定すべきケースを no-match と誤判定する)。pipe chain で各段階が前段階の一致行のみを絞り込む形に修正して対応した。

### Rework
- 上記の pipe chain バグは実装中に気づいて修正したもので、bats テストケース (「different phase」「different issue」のケース) を先に書いていたことで検出できた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI green / review approved (mergeable=true, reason=clean) を確認し、conflict 解消手順は不要だったため squash merge をそのまま実行した
- squash merge 後、`gh pr merge --delete-branch` によるローカルブランチ削除が、別セッションが残した孤立 worktree 登録 (`review+pr-1016` が指すディレクトリが実際には存在しない) により失敗した。remote merge/remote branch 削除自体は正常完了しているため、squash merge の成否には影響しないと判断し、ローカルブランチ削除の失敗は許容してそのまま後続ステップを継続した

### Deferred Items
- `review+pr-1016` worktree の孤立 git 管理領域 (`.git/worktrees/review+pr-1016`) と、それに紐づくローカルブランチ `worktree-code+issue-1014` の削除は本 merge スキルのスコープ外として保留 — 手動 (`git worktree unlock` 済み、あとは `git worktree remove --force` または `git branch -D` の再試行) でのクリーンアップが必要
- H-a/H-b/H-c (external kill の根源原因) は引き続き未解明のまま — code phase の Deferred Items を参照

### Notes for Next Phase
- Post-merge AC (`orchestration-recoveries.md に本 Issue 作成日以降の新規 未起票 manual-recovery-respawn エントリが無いこと`) の自動判定を `/verify` で実施する。6件目 (#1014 自身の spec phase kill) の記録タイミングについては code phase の Notes を参照
- 孤立 worktree (`review+pr-1016`) のクリーンアップ状況を次回のセッションで確認し、必要なら `git worktree remove --force .claude/worktrees/review+pr-1016` と `git branch -D worktree-code+issue-1014` を実行してほしい
