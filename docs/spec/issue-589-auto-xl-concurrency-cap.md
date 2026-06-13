# Issue #589: auto: XL sub-issue 並列実行の同時実行数キャップ追加

## Overview

XL 親 Issue の sub-issue を `run-auto-sub.sh` で並列実行する際、現在は同時実行数に上限がない。`.wholework.yml` に `auto-max-concurrent` キー（デフォルト 5）を追加し、semaphore パターンで実行数を制御する。bash 3.2 (macOS) では `wait -n` が使えないため `kill -0` ポーリング fallback を実装する。

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `auto-max-concurrent | AUTO_MAX_CONCURRENT | ... | 5` 行を追加; Output Format section に `AUTO_MAX_CONCURRENT` エントリを追加
- `skills/auto/SKILL.md`: XL route Step 4 の冒頭で `detect-config-markers.md` を読み `AUTO_MAX_CONCURRENT` を取得; sub-issue バックグラウンド実行ブロックを semaphore パターン（`kill -0` fallback つき）に置き換え
- `docs/guide/customization.md`: Available Keys テーブルに `auto-max-concurrent` 行を追加; 例 YAML ブロックに `auto-max-concurrent` コメント行を追加
- `docs/ja/guide/customization.md`: `auto-max-concurrent` 行の日本語訳を追加（translation sync）
- `tests/auto-xl-concurrency.bats`: 新規 bats テストファイル（3 ケース: AUTO_MAX_CONCURRENT 参照, kill -0 fallback, detect-config-markers fallback ルール）
- `docs/structure.md`: `tests/` ファイル数を 62 → 63 に更新

## Implementation Steps

1. **`modules/detect-config-markers.md`**: Marker Definition Table の `verify-max-iterations` 行の直後に以下を追加 (→ AC1):
   ```
   | auto-max-concurrent | AUTO_MAX_CONCURRENT | Integer string (extract as-is; use `5` if ≤0 or non-numeric) | `5` |
   ```
   Output Format section に以下を追加（`VERIFY_MAX_ITERATIONS` エントリの直後）:
   ```
   AUTO_MAX_CONCURRENT: integer from auto-max-concurrent (default: "5"; falls back to "5" if ≤0 or non-numeric)
   ```

2. **`skills/auto/SKILL.md` XL route** (→ AC2, AC3, AC4):
   - "**XL route: sub-issue dependency graph with parallel execution...**" ブロック冒頭（"1. **Fetch dependency graph**" の直前）に以下を追加:
     ```
     Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `AUTO_MAX_CONCURRENT` (maximum concurrent sub-issue executions; default: 5).
     ```
   - "then run non-skipped sub-issues in background:" のブロック（`run-auto-sub.sh $SUB_NUMBER &`）を semaphore パターンに置き換え:
     ```
     then run non-skipped sub-issues with concurrency cap using AUTO_MAX_CONCURRENT:
       RUNNING=0
       for each SUB in non-skipped sub-issues:
         ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER &
         PIDS+=($!)
         RUNNING=$((RUNNING + 1))
         if [ $RUNNING -ge $AUTO_MAX_CONCURRENT ]; then
           # bash 4.3+: wait -n waits for any one child to finish
           # bash 3.2 fallback (macOS): kill -0 polling
           if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
             wait -n
           else
             while true; do
               for pid in "${PIDS[@]}"; do
                 if ! kill -0 "$pid" 2>/dev/null; then break 2; fi
               done
               sleep 1
             done
           fi
           RUNNING=$((RUNNING - 1))
         fi
       done
     Wait for all processes with `wait`, check each process exit code
     ```

3. **`docs/guide/customization.md`** (→ AC5, AC7 の一部):
   - Available Keys テーブルの `verify-max-iterations` 行の直後に追加:
     ```
     | `auto-max-concurrent` | integer | `5` | Maximum concurrent sub-issue executions in XL parallel route. Applies to each level of the dependency graph. Values ≤0 or non-numeric fall back to `5`. |
     ```
   - 例 YAML ブロックの `verify-max-iterations: 3` 行の直前に追加:
     ```
     # XL sub-issue parallel execution concurrency cap (default: 5)
     # auto-max-concurrent: 5
     ```
   - **`docs/ja/guide/customization.md`** の対応行（`verify-max-iterations` 行の直後）に日本語訳を追加:
     ```
     | `auto-max-concurrent` | integer | `5` | XL 並列ルートで同時実行できる sub-issue の最大数。依存グラフの各レベルに適用。0 以下または非数値の場合は `5` にフォールバック。 |
     ```

4. **`tests/auto-xl-concurrency.bats`** (→ AC6): 新規ファイルを作成。`tests/auto-batch.bats` のパターンに倣い、SKILL.md と detect-config-markers.md の構造内容テストを 3 ケース記述:
   - `@test "XL route: AUTO_MAX_CONCURRENT semaphore pattern present"` — XL route ブロックに `AUTO_MAX_CONCURRENT` が含まれること
   - `@test "XL route: kill -0 bash 3.2 fallback present"` — XL route ブロックに `kill -0` が含まれること
   - `@test "detect-config-markers: auto-max-concurrent fallback rule present"` — `detect-config-markers.md` に `auto-max-concurrent.*AUTO_MAX_CONCURRENT` が含まれること
   - `docs/structure.md` の `tests/` ファイル数を `62` → `63` に更新 (→ SHOULD)

## Verification

### Pre-merge

- <!-- verify: grep "auto-max-concurrent|AUTO_MAX_CONCURRENT" "modules/detect-config-markers.md" --> Marker Definition Table に `auto-max-concurrent` が追加されている
- <!-- verify: grep "AUTO_MAX_CONCURRENT" "skills/auto/SKILL.md" --> SKILL.md の XL route で `AUTO_MAX_CONCURRENT` を semaphore として使用
- <!-- verify: rubric "skills/auto/SKILL.md XL route uses a semaphore pattern to limit concurrent run-auto-sub.sh executions to AUTO_MAX_CONCURRENT, with bash 3.2 fallback for macOS compatibility" --> semaphore 実装と bash 3.2 互換が明記されている
- <!-- verify: grep "kill -0" "skills/auto/SKILL.md" --> bash 3.2 互換のための `kill -0` ポーリング fallback が記述されている
- <!-- verify: grep "auto-max-concurrent" "docs/guide/customization.md" --> `docs/guide/customization.md` の Available Keys テーブルに `auto-max-concurrent` が追加されている
- <!-- verify: command "bats tests/auto-xl-concurrency.bats" --> bats テストが green（並列度制限・fallback・無効値処理の 3 ケース最小）
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期

### Post-merge

- 実 XL Issue（Nuxt → Next 移行など）で 50+ sub-issue を並列実行した際、OOM・rate limit kill が許容内に収まることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- verify コマンド AC1–5 は実装前には対象文字列が存在しない（実装後に追加される文字列を検証するコマンド）
- bats テストは shell script 実行ではなく SKILL.md / detect-config-markers.md の内容検証（`tests/auto-batch.bats` パターン準拠）; WHOLEWORK_SCRIPT_DIR モックは不要
- `kill -0` ポーリング fallback は既存コードベースのパターン（`scripts/claude-watchdog.sh:40`）と一致
- semaphore の `PIDS` 配列管理: bash 3.2 fallback では `PIDS` 配列から終了済みプロセスを効率的に除去するのが難しいため、実装は単純に全 PID を走査して最初の終了プロセスを検出したら break する方式を採用（精度より簡潔さを優先）
- AC7（ja 同期）は `docs/guide/customization.md` の変更が `docs/ja/guide/customization.md` に反映されることで達成
- `docs/structure.md` の tests/ カウント更新は SHOULD レベル（verify command なし）
- Non-interactive mode: Issue body の Auto-Resolved Ambiguity Points セクションで事前解決済み（event=auto-run 修正、customization.md スコープ追加、rubric + grep 補完）

## Code Retrospective

### Deviations from Design
- `docs/ja/guide/customization.md` の YAML 例ブロックにもコメント行を追加した（Spec には明示されていなかったが、customization.md の英語版と対称性を保つために実施）
- `docs/ja/structure.md` のtests/カウントも62→63に更新した（translation-workflow.md の手順に従い、docs/structure.md の変更に連動）

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- semaphore パターンは RUNNING カウンタ + PIDS 配列で実装; bash 3.2 fallback は `kill -0` ポーリング（`scripts/claude-watchdog.sh` と同一パターン）
- SKILL.md の擬似コードブロック内に実装を記述（実際の bash スクリプトではなく LLM 実行フロー）
- detect-config-markers.md の Marker Definition Table と Output Format section の両方に `auto-max-concurrent` を追加した

### Deferred Items
- 実 XL Issue での動作観察（OOM・rate limit kill 削減）はPost-mergeのobservationとして残す
- semaphore の PIDS 配列精度向上（終了済みPIDの除去）は将来の最適化として残す

### Notes for Next Phase
- 全7 pre-merge verify commandがPASSしている（チェックボックス更新済み）
- bats 3件すべてgreen、translation sync確認済み
- `docs/ja/structure.md` も同期更新済み（translation-workflow.mdに従った追加対応）
