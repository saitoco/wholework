# Issue #1387: recoveries: バースト事後解析に必要な events.jsonl 計装を整備

## Overview

2026-08-16 07:09Z 前後に 3 セッション (#1273 review / #1365 code-pr / #1381 code-patch) が 16 秒以内に同時 external kill を受けたバーストが、3 つの計装ギャップを同時に露呈させた。いずれも「バースト時に `.tmp/auto-events.jsonl` へ何を記録するか」という同一の問題であるため、本 Issue で一括して扱う (2026-08-17 にスコープ統合)。

1. **未記録 kill の機械検出**: `docs/reports/orchestration-recoveries.md` への記録は親セッションの手動記録行動に依存しており、今回のバーストでも 3 件中 1 件 (#1273) が当初未記録だった。`.tmp/auto-events.jsonl` の `phase_start` 重複パターンから機械的に検出し、recoveries log と突合して報告する仕組みが必要。
2. **バースト単位の束ね**: 複数セッションの同時 kill を 1 つのバーストとして束ねる仕組みが存在しない。今回も事後に respawn 時刻を手作業で突合して判明した。
3. **spawn 時点の detach 状態記録**: `WHOLEWORK_SPAWN_DETACH=1` (Arm 3 実験) は、バースト中に detached な子と non-detached な子の生死を比較することでしか検証できない。しかし kill された各 wrapper の detach 状態が spawn 時点でログに残っていなければ、事後のバースト同定時に処置群/対照群へ割り振れない。この計装がない限り Arm 3 は実行不能 (`docs/reports/external-kill-investigation.md` § "Arm 3, repositioned" が本 Issue を前提条件として明示的に参照している)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 2026-08-17 00:29Z 付近の Issue Retrospective コメント。Size S→M へのスコープ統合根拠 (3 ギャップの統合理由)・曖昧性自動解決 1 件 (検出結果の報告先)・AC 変更点 (3→7 件への拡張) を記録。現在の Issue 本文に既に反映済みであり、追加対応なし。https://github.com/saitoco/wholework/issues/1387#issuecomment-5311198358
- login: saito / authorAssociation: MEMBER / trust tier: first-class / AC audit コメント。AC3 (旧) の rubric が「値をイベントとして記録する処理」と「flag を読んで detach する既存処理 (PR #1143, `run-auto-sub.sh:35,48`)」を区別できず、実装 0 行で PASS しうる空撃ちリスクを指摘。修復案 (rubric 文言の明示的除外 + 補助 grep 併記) を提示。本 Spec 作成時に Issue 本文の AC3 を提案通り書き換え、補助 AC (`grep "spawn_detach"`) を追加した (対応済み)。https://github.com/saitoco/wholework/issues/1387#issuecomment-5311207555

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 内の `emit_event "phase_start" "phase=${phase}"` (現状 653 行目付近) に `spawn_detach=<0|1>` フィールドを追加。bash 3.2+ 互換 (既存の `[[ -n ... ]]` 判定と同じ書き方)
- `modules/event-emission.md`: `phase_start` イベントスキーマ節に `spawn_detach` フィールドを追記 (フィールド名・値の意味・`docs/tech.md` への相互参照)
- `scripts/detect-unrecorded-kills.sh`: 新規スクリプト。`.tmp/auto-events.jsonl` の `phase_start` 重複 (respawn シグナル) を検出し、`docs/reports/orchestration-recoveries.md` と突合、近接時間窓でバースト単位にグルーピングして出力する
- `skills/verify/SKILL.md`: Step 15 (Recovery Candidates Tail Check) に新しいガード付きサブブロックを追加し `detect-unrecorded-kills.sh` を呼び出す。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-unrecorded-kills.sh:*` を追加 (allowed-tools impact chain check: 新規 `scripts/*.sh` を呼ぶ唯一の呼び出し元)
- `docs/structure.md`: Scripts > Project utilities に新規スクリプトの一行説明を追加 (`detect-external-kill.sh` の近傍)。scripts ディレクトリのファイル数コメントを `(88 files)` → `(89 files)` に更新
- `docs/ja/structure.md`: 上記 `docs/structure.md` の変更を日本語訳として同期 (`docs/translation-workflow.md` の同期対象)
- `docs/tech.md`: `WHOLEWORK_SPAWN_DETACH` 環境変数リファレンス表のエントリに「値は `spawn_detach` フィールドとして `phase_start` イベントに記録される」旨を追記
- `docs/ja/tech.md`: 上記 `docs/tech.md` の変更を日本語訳として同期
- `tests/detect-unrecorded-kills.bats`: 新規テストファイル。2026-08-16 07:09Z バースト相当のフィクスチャ (記録済み kill 2 件 + 未記録 kill 1 件 + 近接 respawn 3 件) を含む
- `tests/run-auto-sub.bats`: `phase_start` の `emit_event` 呼び出しに `spawn_detach` が正しく含まれることを検証する新規テストケースを追加 (既存の `wrapper_alive`/`token_usage` テストと同じ `emit_event` モックパターンを踏襲)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、`emit_event "phase_start" "phase=${phase}"` 呼び出し (654 行目直前、`PHASE_START=$(date +%s)` の直後) に `"spawn_detach=$([[ -n "${_WHOLEWORK_DETACHED:-}" ]] && echo 1 || echo 0)"` を追加する。`_WHOLEWORK_DETACHED` は shim が re-exec した子プロセスでのみ `1` が export される変数であり (このスクリプト冒頭の spawn detachment shim を参照)、`WHOLEWORK_SPAWN_DETACH=1` が要求されただけでなく実際に detach が成立したプロセスかどうかを反映する。この 1 箇所の変更で `code-patch`/`code-pr`/`review`/`merge` の全 `phase_start` 呼び出しをカバーする (→ 受け入れ条件 3)

2. `modules/event-emission.md` の `### phase_start` セクションに `spawn_detach` フィールドの説明 (値は `0`/`1`。emit 時点の `_WHOLEWORK_DETACHED` を反映し、`run-auto-sub.sh` の spawn detachment shim (`WHOLEWORK_SPAWN_DETACH=1` オプトイン) によって実際に detach された wrapper プロセスからの emit かどうかを表す) を追加する。`docs/tech.md` の `WHOLEWORK_SPAWN_DETACH` 環境変数テーブルのエントリ末尾に「この値は `phase_start` イベントの `spawn_detach` フィールドとして `.tmp/auto-events.jsonl` に記録される (Issue #1387)」を追記し、`docs/ja/tech.md` にも同内容を日本語で反映する (→ 受け入れ条件 4, 5)

3. `scripts/detect-unrecorded-kills.sh` を新規作成する (`collect-recovery-candidates.sh` の引数パターン踏襲: 位置引数 2 つ + オプションフラグ)。

   ```
   Usage: detect-unrecorded-kills.sh <events-jsonl-path> <recoveries-md-path> [--window SECONDS]
   ```

   処理内容:
   - `<events-jsonl-path>` (通常 `.tmp/auto-events.jsonl`) を `(issue, phase)` の組でグルーピングし、各グループ内の `phase_start` イベントを `ts` 昇順に並べる
   - 連続する `phase_start` のペア `(start_i, start_{i+1})` について、その `(issue, phase)` に対する `wrapper_exit` / `phase_complete` (backfilled 有無を問わない) / `manual_intervention` のいずれのイベントも `start_i.ts` と `start_{i+1}.ts` の間に存在しない場合を **respawn シグナル** と判定する (これが「終了イベント 4 種を伴わない同一 issue/phase の再出現」の具体化 — Issue 本文はこの 4 種を明示していないため、`wrapper_exit`・`phase_complete` (通常)・`phase_complete` (backfilled)・`manual_intervention` の 4 つを `/spec` にて確定した。根拠は `## Notes` を参照)
   - 各 respawn シグナルについて `<recoveries-md-path>` を走査し、`### Context` 内に `Issue #<issue>, phase: <phase>` を含み、見出しの日時が `start_{i+1}.ts` から `--window` 秒以内にあるエントリが存在すれば `recorded=yes`、存在しなければ `recorded=no` とする
   - 全 respawn シグナル (recorded の有無を問わない) を `start_{i+1}.ts` でソートし、隣接シグナル間のギャップが `--window` 秒以内である限り同一バーストとしてグルーピングする (貪欲法)
   - バーストごとに: バースト時刻範囲、メンバー数 (= 並行度)、各メンバーの issue/phase/kill 時刻 (`start_{i+1}.ts`)/経過時間 (`start_{i+1}.ts - start_i.ts`、`start_i` の `spawn_detach` 値、`recorded` を出力する。単独 (1 件のみ) の respawn シグナルもバースト (並行度 1) として出力し、孤立した未記録 kill を握り潰さない
   - `--window` 省略時のデフォルトは 120 秒 (観測済みバーストは 16 秒以内のクラスタだが、respawn 検知・通知の遅延を見込んだ余裕を持たせる)
   - 入力ファイルが存在しない場合は非 0 で終了しエラーメッセージを stderr に出力する (`collect-recovery-candidates.sh` と同じ規約)。異常なし (バーストも未記録 kill も検出されない) 場合は出力なしで exit 0
   - スクリプト冒頭のヘッダコメントに実行経路 (`/verify` Step 15 から呼ばれる) を明記する (→ 受け入れ条件 5 の「スクリプトのヘッダコメント」要件)

   (→ 受け入れ条件 1, 2)

4. `skills/verify/SKILL.md` Step 15 (Recovery Candidates Tail Check) に、既存の `collect-recovery-candidates.sh` 呼び出しブロック (item 3) の後、item 4 (Cleanup) の前に新しいガード付きサブブロックを追加する: `.tmp/auto-events.jsonl` が存在しない場合はスキップ (Step 15 は Step 13 Worktree Exit の後に実行されるため main repository コンテキストで動作し、このファイルに直接アクセスできる)。存在する場合、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-unrecorded-kills.sh .tmp/auto-events.jsonl docs/reports/orchestration-recoveries.md` を実行し、出力があれば `Warning: unrecorded external kill(s) / burst(s) detected:` の見出しを付けて terminal にそのまま表示する (autonomy tier によるゲーティングなし — GitHub への書き込みを一切行わない読み取り専用の診断出力のため、`recoveries-auto-fire` とは異なり advisory 表示のみ)。SKILL.md frontmatter の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/detect-unrecorded-kills.sh:*` を追加する (`collect-recovery-candidates.sh:*` と同じ形式)。`docs/structure.md` の Scripts > Project utilities に新規スクリプトの一行説明を追加し、ディレクトリツリーのファイル数コメントを `(88 files)` → `(89 files)` に更新する。`docs/ja/structure.md` に同内容を日本語で同期する (→ 受け入れ条件 5, 8)

5. `tests/detect-unrecorded-kills.bats` を新規作成し、`tests/detect-external-kill.bats` (JSONL フィクスチャ) と `tests/collect-recovery-candidates.bats` (recoveries.md フィクスチャ) の規約を踏襲する。2026-08-16 07:09Z バースト相当の入力 (Issue #1273 review / #1365 code-pr / #1381 code-patch の 3 組の重複 `phase_start`。respawn 時刻は 16 秒以内。recoveries.md 側に #1365 と #1381 の `manual-recovery-respawn` エントリのみ存在し #1273 のエントリは存在しない) を構築し、(a) #1273 のシグナルのみ `recorded=no` として報告される、(b) 3 件が並行度 3 の単一バーストとして束ねられる、の 2 点を検証する。あわせて `tests/run-auto-sub.bats` に、`_WHOLEWORK_DETACHED=1` を export した場合に `phase_start` の `emit_event` 呼び出しが `spawn_detach=1` を含み、未 export の場合は `spawn_detach=0` を含むことを検証する新規テストケースを追加する (既存の `emit_event` モックパターンを踏襲)。既存スイートが PASS することに加え、この 2 つの新規テストケースが追加されたうえでスイート全体が PASS すること (→ 受け入れ条件 6, 9)

## Verification

### Pre-merge

- <!-- verify: rubric "events.jsonl の phase_start 重複を抽出し orchestration-recoveries.md と突合して未記録 kill を報告する処理が scripts/ 配下に実装されている" --> `.tmp/auto-events.jsonl` の `phase_start` 重複パターン (終了イベント 4 種を伴わない同一 issue/phase の再出現) から未記録の external kill を検出し、`docs/reports/orchestration-recoveries.md` のエントリと突合して報告する仕組みが実装されている
- <!-- verify: rubric "近接時間窓で複数セッションの kill をバースト単位にグルーピングし、バーストごとの構成要素を出力する処理または手順が実装・文書化されている" --> 複数セッションの kill を 1 つのバーストとして束ねる手順が定義されている。近接時間窓で respawn または未記録 kill をグルーピングし、バースト単位で kill 時刻・phase・並行度・uptime・記録の有無を出力する
- <!-- verify: rubric "wrapper spawn 時に WHOLEWORK_SPAWN_DETACH の値が emit_event 経由で auto-events.jsonl のイベントとして記録されている。scripts/run-auto-sub.sh に既存の flag 読み取り・再 exec 判定 (PR #1143) はこの条件を満たさない — イベントログへの記録が新たに追加されていることを要求する" --> wrapper spawn 時点の `WHOLEWORK_SPAWN_DETACH` の値が `.tmp/auto-events.jsonl` に記録される。事後の突合時に、kill された各 wrapper の detach 状態が判別できる
- <!-- verify: grep "spawn_detach" "modules/event-emission.md" --> 記録されるフィールド名 (`spawn_detach`) が `modules/event-emission.md` に文書化されている
- <!-- verify: grep "SPAWN_DETACH" "modules/event-emission.md" --> 記録されるイベントのスキーマ (フィールド名と値の意味) が `modules/event-emission.md` に文書化されている
- <!-- verify: rubric "未記録 kill 検出の実行経路 (どの skill のどの Step から呼ばれるか) が SKILL.md またはスクリプトのヘッダコメントに明記されている" --> 検出結果の実行経路が定義されている — `collect-recovery-candidates.sh` が `/verify` Step 15 から呼ばれる既存パターンに倣う
- <!-- verify: rubric "記録済み kill と未記録 kill が混在し、かつ複数セッションの kill が近接時刻に並ぶケースを入力として、未記録分の検出とバースト束ねの両方を検証するテストが tests/ に追加されている" --> 2026-08-16 07:09Z のバースト相当の入力 (記録済み kill 2 件 + 未記録 kill 1 件 + 近接した respawn 3 件) で、未記録分のみが検出され、3 件が 1 バーストとして束ねられることがテストで保護されている
- <!-- verify: grep "(89 files)" "docs/structure.md" --> 新規スクリプト追加に伴い `docs/structure.md` の scripts ファイル数コメントが更新されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが通る

### Post-merge

- 次回 external kill が発生したセッションで、記録漏れがあった場合に検出・報告されることを観察 (verify-type: opportunistic)
- 次回バーストで、複数セッションの kill が 1 つのバーストとして束ねられ、各 wrapper の detach 状態が判別できることを確認 (verify-type: observation event=auto-run)

## Notes

### 曖昧性の自己解決 (SPEC_DEPTH=light のため Step 7 は skip、Notes に記録)

- **「終了イベント 4 種」の具体化**: Issue 本文は「終了イベント 4 種を伴わない同一 issue/phase の再出現」と書くのみで 4 種の内訳を明示していない。コードベース調査の結果、`wrapper_exit` (全 exit code で無条件 emit — `modules/event-emission.md`)、`phase_complete` (通常)、`phase_complete` (backfilled — EXIT trap による)、`manual_intervention` (`--write-manual-recovery` による記録済みシグナル) の 4 つを採用した。根拠: 前 3 つは `orchestration-fallbacks.md#external-kill-parent-respawn` の symptom 定義 (`wrapper_exit` も backfill `phase_complete` も存在しない、が external kill の必要条件) と直接対応する。`manual_intervention` は「既にこの kill は記録済みである」ことを示すイベント自体が auto-events.jsonl に残る唯一のケースであり、これを含めないと `--write-manual-recovery` 実行直後の respawn ペアを誤って「未記録」と再検出してしまう。
- **「uptime」列の解釈**: Issue 本文 AC2 の「バースト単位で kill 時刻・phase・並行度・uptime・記録の有無を出力する」における "uptime" は、`docs/reports/external-kill-investigation.md` の 2026-08-16 バースト観測がホスト uptime (`sysctl kern.boottime`) をレポート執筆時に手動測定したものであり、これは過去の kill 時点に遡って `.tmp/auto-events.jsonl` から機械的に再構成することができない (spawn 時点にホスト uptime を記録する仕組みは本 Issue のスコープに含まれない — Out of Scope 参照)。そのため本 Spec では "uptime" を「該当プロセスの経過稼働時間」(`start_i.ts` から `start_{i+1}.ts` までの経過時間。investigation report 自身の burst テーブルの "Elapsed" 列と同じ量) と解釈した。ホスト uptime 自体の記録が必要になった場合は別 Issue とする。
- **並行度の定義**: バーストのメンバー数 (recorded/unrecorded を問わず、その時間窓に属する respawn シグナルの総数) とした。investigation report の burst テーブルが 3 件を「同時」と扱った基準 (respawn が 16 秒以内) と整合する。

### 新規ロジックに対する新規テストケース (Step 13 retrospective の代替記録 — SPEC_DEPTH=light のため Step 13 は skip)

Implementation Step 1 (`run-auto-sub.sh` の `phase_start` 新規フィールド) と Step 3 (`detect-unrecorded-kills.sh` 新規作成) はいずれも新規ロジックであり、Step 5 で対応する新規テストケース (`tests/run-auto-sub.bats` の `spawn_detach` フィールド検証、`tests/detect-unrecorded-kills.bats` の新規ファイル一式) を追加する。既存スイートの PASS だけでなく、これら新規テストケースを含めたうえでのスイート PASS が要件。

### Arm 3 との関係

本 Issue は Arm 3 (`WHOLEWORK_SPAWN_DETACH=1` の対照実験) 実行そのものを含まない (Issue 本文 Out of Scope)。Implementation Step 1 は Arm 3 の前提条件 (spawn 時点の detach 状態記録) を満たすのみで、flag を有効化する判断は `docs/reports/external-kill-investigation.md` 側 (#1146) に残る。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 を Spec の記述どおりに実装した。

### Design Gaps/Ambiguities

- **`--window` が recorded 判定とバースト束ねの両方に共用される設計の実効性への懸念**: Implementation Step 3 は `docs/reports/orchestration-recoveries.md` エントリの見出し日時が respawn 時刻 (`start_{i+1}.ts`) から `--window` 秒以内にある場合のみ `recorded=yes` と判定する仕様で、これを Spec の記述どおりに実装した。しかし実際の `orchestration-recoveries.md` エントリ (例: #1365 の `manual-recovery-respawn` は 08:22 UTC 見出しで記録されているのに対し、実際の respawn 時刻は 07:09:32Z — 約 71 分の乖離) は、パーソン(親セッション)が kill を認知・診断・記録するまでの遅延を反映しており、デフォルト `--window 120` (2 分) を大きく超えるケースがある。バースト束ねに使う window (respawn 同士の近接性、観測値は 16 秒以内) と、recorded 判定に使う window (記録行動の遅延、観測値は分〜時間オーダー) は本質的に異なるスケールの量であり、同一パラメータを共用する現在の設計では、実データに対して `recorded=yes` になるべきエントリが `recorded=no` と誤判定される可能性がある。本 Issue の Spec で明示的にこの設計が指定されていたため、そのまま忠実に実装した (テストフィクスチャは recorded=yes を検証できるよう見出し時刻を respawn 時刻の近傍に置いて構成している)。実データでの誤判定が実際に問題になる場合は、recorded 判定用に独立した window パラメータ (例: `--recorded-window`、デフォルトをより長く) を導入する追随 Issue を検討する余地がある。

### Rework

N/A — 手戻りは発生しなかった。

### Smoke Test

N/A — Spec に `## Smoke Test` セクションが存在しないため実行していない。

### Pre-implementation FAIL Confirmation

Confirmed pre-implementation FAIL for 2 new test(s) (`tests/run-auto-sub.bats` の `spawn_detach` フィールド検証 2 件) against the pre-#1387 `scripts/run-auto-sub.sh` (`git checkout <pre-implementation-commit> -- scripts/run-auto-sub.sh` を用いて確認後、実装版に復元)。`tests/detect-unrecorded-kills.bats` の新規テストはプロセス出力/終了コードを検証するアサートであり、本チェックの対象外 (`skills/code/stale-test-check.md` 系のスコープ定義に従う)。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merge (`gh pr merge --squash --delete-branch`) を実行し、`closes #1387` により Issue を自動 close する経路をそのまま使用した。base branch は `main` のため fallback 分岐は不要と判断。
- Pre-merge AC ゲートは 9 件全て checked、review-incomplete-fallback も未検出だったため、override マーカーは発行せず素通しで merge した。

### Deferred Items
- review retrospective に記録された 2 件の改善提案 (bash オプションパーサのガード規約横展開チェック、`/merge` Phase Handoff コミットの forbidden-expressions ローカルチェック) は本フェーズでは起票せず据え置いた — `/verify` での集約判断を待つ。

### Notes for Next Phase
- post-merge の opportunistic 観察 AC 2 件 (未記録 kill の検出報告、複数セッション kill の単一バースト束ね) は次回の external kill / バースト発生時に確認すること。
- `detect-unrecorded-kills.sh` の `recorded=yes` 判定は `docs/reports/orchestration-recoveries.md` の phase 表記ゆれに依存し続けるため、実データでの動作を注視すること。

## review retrospective

### Spec vs. implementation divergence patterns

Code Retrospective が明示的に記録していた `--window` 共用設計の懸念 (Design Gaps/Ambiguities) は、実データ (`.tmp/auto-events.jsonl` + `docs/reports/orchestration-recoveries.md` の実エントリ) に対する実測で、想定より深刻であることが判明した — 記録済み kill の `recorded=yes` 判定率は実質 0% だった。原因は 2 つ複合していた: (1) window スケールの不一致 (Code Retrospective が既に記録済み)、(2) `orchestration-recoveries.md` の phase 表記ゆれ (`code` vs `code-pr`/`code-patch`、Code Retrospective 未記録の第 2 の原因)。加えて `skills/verify/SKILL.md` Step 15 への新規サブブロック `3b` の挿入が、既存の「出力が空ならこのステップの残りをスキップ」という記述の対象範囲を意図せず広げてしまい、新機能が到達不能になる制御フローバグを生んでいた — これは実装が Spec の記述に忠実だったにもかかわらず、Spec 自体が想定していなかった既存プロセス文書 (SKILL.md) との相互作用から生じた divergence である。いずれも `/review` の 3 段階検証 (review-spec + review-bug×2 + adversarial verify) と実データに対する実行確認 (edge case execution サブエージェント) で捕捉され、この phase 内で修正済み。

### Recurring issues

新規スクリプト `detect-unrecorded-kills.sh` のオプション引数パーサ (`while [ $# -gt 0 ]; case ... --window) ... shift 2 ;;`) が、値なしで渡された場合に無限ループするバグを含んでいた。同一リポジトリの `scripts/run-auto-sub.sh` には既に同種のハザードに対する確立済みガード規約 (`[[ $# -ge 2 ]] || { echo "Error: ... requires a value" >&2; exit 1; }`、`tests/run-auto-sub.bats` に "with no value (with diagnostic message, not a bare shift failure)" という命名規則のテストが複数存在) があったにもかかわらず、新規スクリプトはこれを踏襲していなかった。既存規約が同一リポジトリ内に存在していても、新規スクリプト作成時に横展開されない、という同種のパターンが今回も再発したと言える。**改善提案 (Issue 起票は見送り、/verify で集約判断)**: 新規 bash スクリプトが `while [ $# -gt 0 ]` 形式のオプションパーサを持つ場合、`shift 2` を伴う値取得オプションには引数個数ガードを必須とするチェックリスト項目、または `scripts/check-forbidden-expressions.sh` 相当の軽量な静的チェック (grep ベースで `shift 2` の直前に `$# -ge 2` 等のガードがあるか検出) を追加する余地がある。

### Acceptance criteria verification difficulty

Verify command (rubric/grep/github_check の混在) は全 9 件が過不足なく機械判定でき、UNCERTAIN は発生しなかった。唯一の律速要因は CI (`github_check "gh pr checks" "Run bats tests"`) 自体ではなく、**このブランチと無関係な `Forbidden Expressions check` ジョブの FAILURE** だった。根本原因は Issue #1386 の `/merge` Phase Handoff コミット (`main` への直接 push) が禁止表現を導入したこと — この書き込み経路は本リポジトリの forbidden-expressions CI ジョブでゲートされていない。**改善提案 (Issue 起票は見送り、/verify で集約判断)**: `/merge` の Phase Handoff 書き込みが `main` へ直接 push される経路 (`modules/worktree-lifecycle.md` の propagation path 表を参照) は、CI による禁止表現チェックの対象外であるため、そこで導入された違反が後続の全 PR の CI を無関係にブロックし続ける構造的ギャップがある。`/merge` の Phase Handoff コミット前に `check-forbidden-expressions.sh` をローカルで実行するステップを追加するか、`main` push 用の軽量 pre-push フックを検討する価値がある。

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec | pr | SUCCESS | |
| code | pr | SUCCESS | PR #1393 created |
| review | pr | SUCCESS (Tier 3 recovery) | 1st attempt killed by harness mid-phase (no exit code observed); Tier 3 recovery sub-agent judged retry appropriate (cause: harness-task-stop); 2nd attempt (manual retry) self-aborted (exit 1) on a false-positive concurrent-session detection caused by a stale locked `review+pr-1393` worktree left by the killed 1st attempt; after unlocking/removing that worktree, 3rd attempt succeeded — see `docs/reports/orchestration-recoveries.md` § `review-tier3-recovery` (2026-08-17 07:02 UTC) for full diagnosis |
| merge | pr | SUCCESS | manual invocation (`run-merge.sh` run directly by the parent session after Tier 3 recovery, since `run-auto-sub.sh`'s own orchestration had already been killed) |
| verify | - | (this run) | |

### Orchestration Anomalies
- `run-auto-sub.sh`'s background task was killed by the harness during the review phase (Issue #1387 itself concerns detecting exactly this class of event — see Overview). Recovered via Tier 3 (recovery-sub-agent, action=retry) plus one round of manual stale-worktree cleanup after the retry's own self-abort. Full context recorded in `docs/reports/orchestration-recoveries.md`.

### Improvement Proposals
- Stale-worktree concurrent-session detection produced a false positive: the retried `/review`'s Worktree Entry step saw a `locked` leftover worktree from its own killed predecessor plus a `ListAgents` entry describing the parent session's own batch (`auto batch #1389,1386,1387,1377`) and concluded a live peer session held the worktree, when in fact the owning process (the killed `run-auto-sub.sh`) had already been confirmed dead by the harness. `modules/worktree-lifecycle.md`'s stale-worktree check currently instructs treating an existing worktree as "a live conflict — not stale — unless there is positive evidence the owning process has actually ended," but does not give guidance on distinguishing a genuinely live peer session from a `ListAgents` entry that is actually the *current* session's own ancestor/batch description. A future Issue could add that distinction (e.g., cross-check the `ListAgents` session id/name against the current session's own `AUTO_SESSION_ID` or process ancestry before treating it as evidence of a peer).
