# Issue #807: auto: run-*.sh wrapper に SIGTERM/SIGKILL 検出 + auto-retry-once 機構を追加

## Overview

`/auto --batch` セッション内で `run-issue.sh` / `run-spec.sh` / `run-code.sh` の主要 `claude -p` 呼び出しが、watchdog の silent timeout に達する前 (実測 60-120s) に外部 kill される事象が複数回 (#778, #779) 観察された。各ケースで 1 度目 kill 後に手動 retry すると 2 度目で正常完了している。

本 Issue は `run-*.sh` wrapper に **早期 kill 検出 + auto-retry-once 機構** を追加する。主要 `claude -p` 呼び出し (および `run-auto-sub.sh` では子 runner 呼び出し) の exit code を捕捉し、**SIGTERM (143) または SIGKILL (137) かつ実行時間が早期 kill 窓 (既定 300s) 未満** の場合に 1 度だけ自動 retry する。retry も kill された場合は exit code を返し、既存の recovery 経路 (run-auto-sub Tier 1/2/3、leaf wrapper は parent /auto manual recovery) に委譲する。

実装は 4 スクリプトから source する共通ヘルパー `scripts/retry-on-kill.sh` に集約する (AC1 の「全スクリプトから呼び出される共通ヘルパー」を採用)。既存の sourceable helper (`watchdog-defaults.sh`, `phase-banner.sh`, `guard-prefix.sh`) と同じパターン。

## Changed Files

- `scripts/retry-on-kill.sh`: 新規。sourceable helper。`run_with_retry_on_kill()` 関数 + グローバルフラグ `_RETRY_ON_KILL_FIRED` を提供。bash 3.2+ 互換 (連想配列・mapfile 不使用、`date +%s` で経過時間計測)
- `scripts/run-issue.sh`: `source retry-on-kill.sh` 追加。主要 claude 呼び出しを `run_with_retry_on_kill` でラップ。env 変数 (`ANTHROPIC_MODEL` / `WATCHDOG_TIMEOUT`) を `env` 引数へ移動。pointer comment 追加。bash 3.2+ 互換
- `scripts/run-spec.sh`: 同上 (run-issue.sh と同パターン)。bash 3.2+ 互換
- `scripts/run-code.sh`: 同上。json branch / 非 json branch の両方をラップし、`OUTPUT_FORMAT_JSON=1` も `env` 引数へ移動。bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: `source retry-on-kill.sh` 追加。`run_phase_with_recovery()` 内の子 runner 呼び出し (`"$runner_script" "$issue" "$@"`) を `run_with_retry_on_kill` でラップ。retry 発火時 (`_RETRY_ON_KILL_FIRED=true`) に `docs/reports/orchestration-recoveries.md` へ記録する `_write_wrapper_retry_recovery()` を追加。pointer comment 追加。bash 3.2+ 互換
- `modules/orchestration-fallbacks.md`: `## wrapper-retry-on-kill` エントリを新規追加 (Symptom に exit code 137/143、Fallback Steps に retry-once + 早期 kill 窓、Escalation、Rationale)
- `tests/run-issue.bats`: setup() に実体 `retry-on-kill.sh` を MOCK_DIR へ copy (既存テストの source 失敗回避)。retry-success / escalation / over-threshold-no-retry のテストを追加
- `tests/run-spec.bats`: setup() に retry-on-kill.sh copy + retry-success テスト追加
- `tests/run-code.bats`: setup() に retry-on-kill.sh copy + retry-success テスト追加
- `tests/run-auto-sub.bats`: setup() に retry-on-kill.sh copy + 子 runner kill→success の retry テスト追加
- `docs/structure.md`: Scripts セクション (Process management) に `retry-on-kill.sh` 行を追加。scripts ファイル数コメントを実数へ修正 (現状 "(59 files)" は実数 61 と乖離 — 追加後の正確な数へ更新)
- `docs/ja/structure.md`: 上記の日本語ミラー同期 (retry-on-kill.sh 行追加 + 数値修正)
- `docs/tech.md`: Environment Variables テーブルに `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` 行を追加
- `docs/ja/tech.md`: 上記の日本語ミラー同期 (Environment Variables 行追加)

## Implementation Steps

1. **`scripts/retry-on-kill.sh` 作成** (→ AC1)。冒頭コメントで「sourceable helper — do not execute directly」「bash 3.2+ 互換」を明記。`RETRY_ON_KILL_MAX_SEC_DEFAULT=300` 定数を定義。`run_with_retry_on_kill()` を「## ブランチ分岐の挙動全列挙」(Notes 参照) どおりに実装。`_RETRY_ON_KILL_FIRED` をグローバルフラグとして関数先頭で `false` にリセットし、retry 発火時に `true` を設定。経過時間は `date +%s` のスナップショット差分で計測し、呼び出し側の `SECONDS` には触れない。

2. **leaf wrapper 3 本に統合** (after 1) (→ AC1)。`run-issue.sh` / `run-spec.sh` / `run-code.sh` の `source "$SCRIPT_DIR/guard-prefix.sh"` 付近に `source "$SCRIPT_DIR/retry-on-kill.sh"` を追加。`SECONDS=0` 直後の `set +e` ブロックで、現行の claude 呼び出しを `run_with_retry_on_kill <command>` でラップする。現在 shell 代入 prefix だった env 変数 (`ANTHROPIC_MODEL=...`, `WATCHDOG_TIMEOUT=...`、run-code.sh では `OUTPUT_FORMAT_JSON=1` も) を `env -u CLAUDECODE NAME=VALUE ...` の引数列へ移動 (関数経由でも env が確実に設定されるようにするため)。run-code.sh は json branch と非 json branch の双方を同様にラップし、`> "$TOKEN_USAGE_FILE"` リダイレクトは外側の `run_with_retry_on_kill ...` に付与する。直前行に pointer comment `# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill` を置く。`EXIT_CODE=$?` 以降の既存ロジック (handle-permission-mode-failure, reconcile 143/0 branch) は変更しない。

3. **`run-auto-sub.sh` の `run_phase_with_recovery()` に統合 (Layer B)** (after 1) (→ AC1)。冒頭付近で `source "$SCRIPT_DIR/retry-on-kill.sh"` を追加。`run_phase_with_recovery()` 内の `set +e` ブロックで `"$runner_script" "$issue" "$@" > "$log_file" 2>&1` を `run_with_retry_on_kill "$runner_script" "$issue" "$@" > "$log_file" 2>&1` に置換 (リダイレクトは外側に付与)。直前に pointer comment を置く。経過時間判定はヘルパー内部の `date +%s` を使用 (関数内に `PHASE_START` があるが計測はヘルパーに委譲)。

4. **`_write_wrapper_retry_recovery()` 追加 + 呼び出し** (after 3) (→ post-merge AC: orchestration-recoveries.md 記録)。`run-auto-sub.sh` に `_write_wrapper_retry_recovery(issue, phase, exit_code)` を定義。`docs/reports/orchestration-recoveries.md` が存在しなければ `return 0` でスキップ (spawn-recovery-subagent.sh `write_recovery_entry()` と同方式)。存在する場合はマーカー `<!-- Log entries appear below, newest first. -->` 直後にエントリを prepend (python heredoc、`write_recovery_entry()` のパターンを踏襲: symptom-short=`wrapper-retry-on-kill`、Source=`retry-on-kill.sh`、exit code、Outcome は exit_code==0 なら `success` / それ以外は `escalated (retry also killed)`)。既存 Tier 3 ブロック (run-auto-sub.sh 内 `git add/commit -s/push` 部) と同じ best-effort commit/push を行う。`run_phase_with_recovery()` の `exit_code=$?` 直後に `if [[ "${_RETRY_ON_KILL_FIRED:-false}" == "true" ]]; then _write_wrapper_retry_recovery "$issue" "$phase" "$exit_code"; fi` を追加 (Tier 1/2/3 判定の前)。

5. **`modules/orchestration-fallbacks.md` にエントリ追加** (parallel with 2, 3) (→ AC3, AC4)。`## wrapper-retry-on-kill` を既存スキーマ (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) で追記。Symptom に exit code `137` (SIGKILL) と `143` (SIGTERM) を明記し、早期 kill 窓 (<300s) と watchdog hang-kill (elapsed >= `WATCHDOG_TIMEOUT` >= 600s) の区別を説明。Escalation に「retry も kill → leaf は parent manual / run-auto-sub は Tier 1/2/3 へ委譲、自動 retry は 1 回のみ」。`json-mode-silent-hang` (timeout 到達後の parent 主導 retry) との相補関係を相互参照。Operational Notes の手順どおり、各スクリプトに pointer comment を置く (Step 2/3 で実施)。

6. **leaf wrapper 3 本の bats に retry テスト追加** (after 2, 5) (→ AC2)。`tests/run-issue.bats` / `run-spec.bats` / `run-code.bats` の `setup()` で、`guard-prefix.sh` と同様に実体 `scripts/retry-on-kill.sh` を `cp` で `MOCK_DIR` へ配置 (既存全テストが source 失敗で壊れないために必須)。counter ファイル方式の `claude` (または `claude-watchdog.sh`) mock で 1 回目 exit 143・2 回目 exit 0 を返し、wrapper が status 0 で終了し claude が 2 回呼ばれることを assert (retry-success)。`run-issue.bats` には追加で (a) 1・2 回目とも exit 143 → wrapper が 143 で終了 (escalation)、(b) `WHOLEWORK_RETRY_ON_KILL_MAX_SEC=0` で mock が即時 exit 143 → retry せず 143 で終了 (over-threshold no-retry) を assert。

7. **`run-auto-sub.bats` に retry テスト追加** (after 3, 5) (→ AC2)。`setup()` に retry-on-kill.sh の `cp` を追加。`get-issue-size.sh` mock を `XS` に上書きして code-patch のみの最短経路にし、`run-code.sh` mock を counter 方式で 1 回目 exit 143・2 回目 exit 0 とし、`run-auto-sub.sh` が status 0、`run-code.sh` が 2 回呼ばれることを assert。`docs/reports/orchestration-recoveries.md` は fixture 未作成のため記録はスキップされる (file 不在 → `return 0`)。

8. **ドキュメント同期** (after 1) (→ docs AC)。`docs/structure.md` の Scripts セクション (Process management) に `retry-on-kill.sh` 行を追加し、`ls scripts/*.sh scripts/*.py | wc -l` で実数を計測してファイル数コメントを正確な値に更新。`docs/ja/structure.md` を同期 (retry-on-kill.sh 行 + 数値)。`docs/tech.md` Environment Variables テーブルに `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` (既定 `300`、早期 kill 窓秒数) 行を追加し、`docs/ja/tech.md` を同期。

## Alternatives Considered

- **inline per-script (各 wrapper に重複実装)**: 4 箇所に同一ロジックが分散し保守性が低下。AC1 が共通ヘルパーを明示的に許容しており、既存の sourceable helper パターンと一致するため不採用。
- **`claude-watchdog.sh` 内に retry を実装**: `claude-watchdog.sh` の `_watchdog_killed` は自身の hang-kill のみを表し、外部 kill (claude プロセスや watchdog 自身が外部から kill されるケース) を捕捉できない。また watchdog 自身が kill されると retry する余地がない。retry は wrapper レベル (watchdog 呼び出しの exit code を捕捉する層) に置く必要がある — Issue 設計「主要 claude -p 呼び出しを subprocess で起動し exit code をキャプチャ」と一致。
- **しきい値を固定定数のみ (env override なし)**: over-threshold-no-retry branch を bats で決定的に検証できなくなる (300s の sleep は非現実的)。`WHOLEWORK_RETRY_ON_KILL_MAX_SEC` env override を設けてテスト可能にする。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-issue.sh / run-spec.sh / run-code.sh / run-auto-sub.sh のすべて (または全スクリプトから呼び出される共通ヘルパー) に SIGTERM(143)/SIGKILL(137) detection + 自動 retry-once 機構が実装されている (subprocess exit code を判定して条件付き retry を実行する関数または分岐)" --> `scripts/run-*.sh` (4 本) に kill detection + auto-retry-once mechanism が実装されている
- <!-- verify: command "bats tests/run-issue.bats tests/run-spec.bats tests/run-code.bats tests/run-auto-sub.bats" --> retry 経路に対応した bats test が追加されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md または skills/auto/SKILL.md で wrapper-level retry-on-kill mechanism の動作仕様 (trigger 条件: SIGTERM/SIGKILL + 実行時間制限、retry 回数: 1 回、escalation 経路) が明文化されている" --> wrapper-level retry mechanism の設計が SSoT に文書化されている
- <!-- verify: grep "137" "modules/orchestration-fallbacks.md" --> orchestration-fallbacks.md に exit code 137 (SIGKILL) を含む新エントリが追加されている
- <!-- verify: file_contains "docs/structure.md" "retry-on-kill.sh" --> docs/structure.md の Scripts 一覧に retry-on-kill.sh が追加されている
- <!-- verify: file_contains "docs/tech.md" "WHOLEWORK_RETRY_ON_KILL_MAX_SEC" --> docs/tech.md の Environment Variables に WHOLEWORK_RETRY_ON_KILL_MAX_SEC が文書化されている

### Post-merge

- 次回 batch session で run-*.sh kill 発生時に wrapper レベルで自動 retry が試行され、`docs/reports/orchestration-recoveries.md` に記録されることを観察 <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns
- none (新規外部コマンドなし。`bash` / `git` / `python3` / `date` / `gh` はいずれも run-auto-sub.sh / spawn-recovery-subagent.sh で既使用)

### Built-in Tools
- none new

### MCP Tools
- none

**allowed-tools impact chain**: `scripts/retry-on-kill.sh` は run-*.sh が source する sourceable helper であり、いずれの SKILL.md からも直接呼び出されない (run-*.sh は parent /auto が Bash で起動)。したがって SKILL.md frontmatter の `allowed-tools` 追加は不要。

## Uncertainty

- **wrapper 自プロセス kill は非対象**: 本機構は leaf wrapper の内部 claude 呼び出し (Layer A) と run-auto-sub の子 runner 呼び出し (Layer B) を retry する。leaf wrapper (run-issue.sh 等) の **プロセス自体** が外部/OS に kill された場合は wrapper 内 retry が不可能で、従来どおり parent /auto session の manual recovery に委譲される。Issue 設計 (「主要 claude -p 呼び出しを subprocess で起動し exit code をキャプチャ」) と整合するが、観察症状 (run-issue.sh 全体 kill) との間に境界がある点を Notes に明記。
  - **検証方法**: 設計境界として文書化 (実行時検証不要)。
  - **影響範囲**: Implementation Steps 2 (leaf は Layer A のみ)。
- **run-code.sh json branch の出力連結**: retry 時、外側の `> "$TOKEN_USAGE_FILE"` リダイレクトは 1 度だけ truncate/open され両試行が同 fd に書き込む。json mode は出力を末尾一括で出すため (claude-watchdog.sh の `OUTPUT_FORMAT_JSON` 取り扱い参照)、早期 kill された 1 回目は無出力 → 2 回目の clean JSON のみが残り、jq parse は壊れない。
  - **検証方法**: tests/run-code.bats の counter mock で retry-success を検証。必要なら防御的に各試行前 `: > "$TOKEN_USAGE_FILE"` を /code で検討。
  - **影響範囲**: Implementation Steps 2 (run-code.sh)。
- **scripts ファイル数の既存乖離**: `docs/structure.md` は "(59 files)" だが実数は 61 (既存ドリフト)。retry-on-kill.sh 追加後の正確な数を `ls scripts/*.sh scripts/*.py | wc -l` で計測し設定する。
  - **検証方法**: /code 実装時に実数計測。pre-merge AC はドリフト非依存の `file_contains "retry-on-kill.sh"` を用いる。
  - **影響範囲**: Implementation Steps 8。

## Notes

### ブランチ分岐の挙動全列挙 (`run_with_retry_on_kill`) (#642 準拠)

`run_with_retry_on_kill <command> [args...]` — command を実行し、早期 kill のとき 1 度だけ retry する。経過時間は `date +%s` のスナップショット差分。`SECONDS` には触れない。`_max_sec="${WHOLEWORK_RETRY_ON_KILL_MAX_SEC:-300}"`。

- **Branch A — 非 kill 終了 (正常終了条件)**: 1 回目 exit code が `137` でも `143` でもない (0 含む任意) → そのまま `return <exit>`。retry しない。`_RETRY_ON_KILL_FIRED=false` のまま。監視継続: なし (即 return)。
- **Branch B — 早期 kill (retry 条件)**: 1 回目 exit code ∈ {137, 143} かつ `elapsed < _max_sec` → stderr に `retry-on-kill: command killed (exit N) after Ms (< Ks); auto-retrying once` を出力し `_RETRY_ON_KILL_FIRED=true` を設定、command を 1 度だけ再実行、retry の exit code を `return`。
- **Branch C — 後期 kill / watchdog hang (retry しない条件)**: 1 回目 exit code ∈ {137, 143} かつ `elapsed >= _max_sec` → retry せず `return <exit>`。これは watchdog の hang-kill (elapsed >= `WATCHDOG_TIMEOUT` >= 600s) に該当し、早期 kill 窓 300s と重ならない。parent 主導 retry は `json-mode-silent-hang` が担当。
- **Branch D — retry も kill (escalation 条件)**: Branch B の再実行後、exit code が再び ∈ {137, 143} → stderr に `retry-on-kill: retry also killed (exit N); escalating to recovery/manual` を出力し、その exit code を `return` (caller が escalation を判断)。
- **exit code 対応**: `137` = SIGKILL (128+9)、`143` = SIGTERM (128+15)。
- **監視継続**: なし — ヘルパーは run → (条件付き) retry → return の同期処理で、ループ監視を持たない。

### しきい値 300s の根拠

早期 kill 窓 300s は、全 production phase の `WATCHDOG_TIMEOUT` 既定値 (issue 1200 / spec 1800 / code 3600 / review 2000 / merge 600 / default 2700; `scripts/watchdog-defaults.sh`) のいずれよりも小さい (最小は merge の 600s)。よって watchdog hang-kill (elapsed >= WATCHDOG_TIMEOUT) は早期 kill 窓に入らず、外部/OOM による早期 kill のみが retry 対象になる。

### env 変数の `env` 引数化

現行 wrapper は `ANTHROPIC_MODEL=... WATCHDOG_TIMEOUT=... env -u CLAUDECODE ...` のように shell 代入 prefix を用いている。`run_with_retry_on_kill` 関数経由にすると代入 prefix が子コマンドへ確実に export される保証が曖昧になるため、これらを `env -u CLAUDECODE NAME=VALUE ... command` の `env` 引数列へ移す。`env` は `-u NAME` と `NAME=VALUE` を同時に受け付ける。

### reconcile 143/0 branch との関係

leaf wrapper の既存 `if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]` reconcile 完了判定は変更しない。retry 成功時は最終 `EXIT_CODE=0` で従来どおり完了判定に入る。Branch D で最終 137 のとき (両試行 SIGKILL) は完了判定 (0/143 限定) をスキップしてそのまま 137 で escalation する — 早期に 2 度 kill されたケースは phase 未完了の蓋然性が高く、保守的な escalation が妥当。

### bats テスト前提 (test data format)

- counter ファイル方式の mock: `N=$(cat "$CTR" 2>/dev/null || echo 0); N=$((N+1)); echo "$N" > "$CTR"; [[ $N -eq 1 ]] && exit 143 || exit 0`。`run-issue/spec/code.bats` は `claude` mock を、`run-auto-sub.bats` は `run-code.sh` mock を counter 化する。
- `MOCK_DIR` には **実体** `scripts/retry-on-kill.sh` を `cp` で配置する (guard-prefix.sh と同様)。mock 置換ではなく実体を使うことで retry 挙動そのものを検証する。これを忘れると、retry-on-kill.sh を source する 4 wrapper の **既存全テスト** が `set -e` 下で source 失敗し壊れる。

### 関連 Issue

#806 (code phase milestone checkpoint) と相補的 (両実装で kill recovery が 2 段階防御)。本機構成功で #799 (Tier 3 recovery 過剰起動) の起動頻度が低下する見込み。

## Auto-Resolve Log (non-interactive mode)

Step 6 (conflict detection) および Step 7 (ambiguity resolution) で以下を自動解決した。

1. **実装方式 (HIGH)**: inline 重複 vs 共通ヘルパー → **共通ヘルパー `scripts/retry-on-kill.sh`**。AC1 が共通ヘルパーを明示許容、既存 sourceable helper パターンと一致。
2. **早期 kill しきい値 (HIGH)**: Issue 設計「実行時間 < 約 5 分」→ **300s**。`WHOLEWORK_RETRY_ON_KILL_MAX_SEC` env で override 可能 (テスト容易性・調整余地)。全 phase の WATCHDOG_TIMEOUT 既定 (>=600s) より小さく、watchdog hang と早期 kill を明確に分離。
3. **run-auto-sub.sh の「主要 claude -p 呼び出し」(HIGH)**: run-auto-sub は claude -p を直接呼ばない。等価物である `run_phase_with_recovery()` の子 runner 呼び出しを retry 対象 (Layer B = 子 wrapper プロセス全体の kill を捕捉) とし、orchestration-recoveries.md 記録もここに置く。
4. **Issue body との境界 (conflict, MEDIUM)**: 観察症状は「run-issue.sh 全体 kill」だが、本機構は inner-call / child-wrapper kill を対象とする (Issue 設計の明文と一致)。wrapper 自プロセス kill は対象外で parent manual recovery に委譲する旨を Uncertainty / Notes に明記。
5. **docs AC 追加 (MEDIUM)**: 新規 script (structure.md) と新規 env 変数 (tech.md) のドキュメント整合のため、pre-merge AC を 2 件追加 (file_contains)。Issue body も同期更新。

## Consumed Comments

No new comments since last phase.

## issue retrospective

(Transferred from Issue #807 comment — /issue phase Auto-Resolve Log)

1. **AC1 rubric スコープ曖昧性 (HIGH)**: 「のいずれかに」→「すべて (または全スクリプトから呼び出される共通ヘルパー)」に変更。理由: タイトル・Purpose は全 4 スクリプト適用を意図。実装方法 (共通ヘルパー許容) は /spec に委譲。
2. **AC2 bats テストファイル漏れ (HIGH)**: `tests/run-auto-sub.bats` を bats コマンドに追加 (run-auto-sub.sh は対象 4 本の 1 つ)。
3. **AC3 補足 verify command 追加 (MEDIUM)**: 新エントリ確認のため `grep "137"` を追加。`grep "143"` は既存 json-mode-silent-hang にマッチするため不適切、137 (現状未記載) が最善。

## spec retrospective

### Minor observations
- `docs/structure.md` の scripts ファイル数コメントは "(59 files)" だが実数 61 で既存ドリフトあり (調査中に発見)。本 PR で正確値へ更新するが、`/audit drift` の検出対象として記録に値する。
- `claude-watchdog.sh` の "retrying disabled; please re-run manually" は hang-kill の retry を parent 主導とする意図的設計。本 Issue の wrapper retry は早期 kill (<300s) のみを対象とし、両者を非重複に保つ設計判断の根拠になった。

### Judgment rationale
- inline 重複ではなく共通 sourceable helper を採用 (watchdog-defaults.sh / phase-banner.sh と同パターン、AC1 許容)。
- 早期 kill しきい値 300s: 全 production phase の WATCHDOG_TIMEOUT 既定 (>=600s) より小さく、外部早期 kill と watchdog hang-kill を重複なく分離できる。
- run-auto-sub.sh は claude -p を直接呼ばないため、「主要 claude -p 呼び出し」を `run_phase_with_recovery()` の子 runner 呼び出し (Layer B) と解釈。
- env 代入 prefix を `env` 引数列へ移動: 関数ラップ時の子コマンドへの export 保証が shell 代入 prefix では曖昧なため。

### Uncertainty resolution
- wrapper 自プロセス kill は対象外 (inner-call / child-wrapper kill のみ retry)。Issue 設計の明文と整合する境界として scoping で解決 (実装不要)。
- run-code.sh json branch の retry 出力連結は、json mode の末尾一括出力特性 (早期 kill 時は無出力) により実害なしと判断。防御的 truncation は /code の任意検討事項として残置。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- 共通 helper `scripts/retry-on-kill.sh` (`run_with_retry_on_kill()`) を 4 wrapper が source。分岐挙動は Spec Notes に 4 branch で全列挙 (#642 準拠)。
- 早期 kill 窓 300s (env `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` で override)。全 WATCHDOG_TIMEOUT 既定より小。
- 2 層構成: leaf (run-issue/spec/code) は claude 呼び出しをラップ (Layer A)、run-auto-sub は `run_phase_with_recovery()` の子 runner をラップ (Layer B) + orchestration-recoveries.md 記録。
- env 変数を `env` 引数列へ移動し関数ラップ後も propagation を保証。

### Deferred Items
- orchestration-recoveries.md 記録は run-auto-sub.sh (Layer B) のみ実装。leaf-only retry は stderr で観測可能。専用 emit_event type は追加しない (event-emission.md SSoT churn 回避) — follow-up 候補。
- wrapper 自プロセス kill は parent /auto manual recovery のまま (対象外)。
- run-code.sh json branch の防御的 `: > "$TOKEN_USAGE_FILE"` truncation は retry 連結が実観測された場合のみ /code で追加検討。

### Notes for Next Phase
- **必須**: 4 本すべての bats `setup()` で実体 `scripts/retry-on-kill.sh` を `cp` で MOCK_DIR へ配置 (guard-prefix.sh と同様)。怠ると `set -e` 下で source 失敗し既存全テストが壊れる。
- scripts 数を `ls scripts/*.sh scripts/*.py | wc -l` (現状 61) で再計測し structure.md の "(N files)" を正確値に (既存 59 ドリフト是正)。
- 既存 reconcile 143/0 branch は変更しない (137 へ拡張しない、保守的 escalation)。
- `docs/ja/structure.md` / `docs/ja/tech.md` ミラーを translation-workflow.md に従い同期。
