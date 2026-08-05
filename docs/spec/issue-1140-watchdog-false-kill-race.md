# Issue #1140: claude-watchdog: スリープ中に終了したプロセスへの偽 watchdog_kill emit を解消

## Overview

`scripts/claude-watchdog.sh` の watchdog ループ `while kill -0 "$cmd_pid"; do sleep ...; done` は、プロセスの生存確認を `sleep` の **前** にしか行わない。そのため `sleep` 中に監視対象プロセスが正常終了しても、目覚めた側は `unchanged_time` を加算して kill 分岐に入り、`_auto_emit_watchdog_kill` を呼んで偽の `watchdog_kill` イベントを emit してしまう。`kill "$cmd_pid"` 自体は死亡済み PID に対して静かに失敗するため exit code は汚染されず、`tests/claude-watchdog.bats` の既存テストは exit status のみを assert しているためこの欠陥を検出できていない。本 Issue は kill 分岐に入る直前にプロセスの生存を再確認し、既に終了している場合は emit をスキップしてループを抜けるよう修正する。

## Reproduction Steps

1. リポジトリルートで、既存テスト `"OUTPUT_FORMAT_JSON=1: process that exits normally completes without false kill"` (`tests/claude-watchdog.bats` L106-117) が使う `AUTO_EVENTS_LOG` の中身を直接確認する:
   ```bash
   EVENTS_LOG=$(mktemp)
   env AUTO_EVENTS_LOG="$EVENTS_LOG" OUTPUT_FORMAT_JSON=1 WATCHDOG_TIMEOUT=10 \
     bash scripts/claude-watchdog.sh bash -c 'sleep 1; echo "{\"result\":\"done\"}"; exit 0'
   cat "$EVENTS_LOG"
   ```
2. mock プロセスは `t=1s` で正常終了しているにもかかわらず、`t=10s` (`WATCHDOG_TIMEOUT`) で watchdog ループが `unchanged_time >= WATCHDOG_TIMEOUT` と判定し、`"event":"watchdog_kill"` の行が `$EVENTS_LOG` に書き込まれる
3. 既存テストは `[ "$status" -eq 0 ]` のみを assert しているため、この偽イベントが混入していても PASS してしまう (Issue #1136 で purge した偽イベント 12 件のうち、`timeout_setting=10` の 2 件がこの経路による)

## Root Cause

`_run_with_watchdog()` の監視ループ `while kill -0 "$cmd_pid" 2>/dev/null; do sleep "$_CHECK_INTERVAL"; ... done` (`scripts/claude-watchdog.sh` L65-107) は、プロセスの生存確認をループの **各イテレーション先頭 (sleep の前)** でしか行わない。JSON モード分岐 (L67-82) と通常モード分岐 (L83-106) はいずれも `sleep` から復帰した後に `unchanged_time` を計算し `WATCHDOG_TIMEOUT` と比較する (L75, L93) が、この比較の時点でプロセスが `sleep` 中に正常終了していないかを再確認していない。

そのため、`unchanged_time` が閾値に到達したタイミングで監視対象プロセスが既に正常終了していても、kill 分岐 (L75-82 / L93-100) は無条件に `_auto_emit_watchdog_kill()` を呼んで偽の `watchdog_kill` イベントを emit し、続けて `kill "$cmd_pid" 2>/dev/null` を実行する。`kill` は死亡済み PID に対して静かに失敗する (exit code 汚染なし) ため、`wait "$cmd_pid"` (L109) が返す実際の exit code は正常なまま伝播し、exit status のみを見るテストや呼び出し元からはこの欠陥が不可視になる。

この修正方針 (kill 分岐直前で `kill -0 "$cmd_pid"` を再確認する) は、Issue #1136 の Verify Retrospective (`docs/spec/issue-1136-bats-emit-log-isolation.md` § Improvement Proposals) で既に特定・提案されていたものと同一であり、当時は対象外 (out of scope) として先送りされていた欠陥を本 Issue で解消する。

## Changed Files

- `scripts/claude-watchdog.sh`: JSON モード分岐 (L75-82) と通常モード分岐 (L93-100) の kill 判定ブロックを、それぞれ `if kill -0 "$cmd_pid" 2>/dev/null; then ... fi` でラップし、既に終了しているプロセスに対しては `_auto_emit_watchdog_kill` / `kill` / `_watchdog_killed=true` をスキップする。`break` は両分岐ともラップの外側に置き、生死に関わらず閾値到達時は必ずループを抜ける — bash 3.2+ compatible (追加するのは既存コードと同じ `if`/`kill -0` イディオムのみ)
- `tests/claude-watchdog.bats`: 既存テスト `"OUTPUT_FORMAT_JSON=1: process that exits normally completes without false kill"` (L106-117) に `AUTO_EVENTS_LOG` 内に `watchdog_kill` イベントが存在しないことを assert する行を追加。直後に通常モード相当の negative case テストを新規追加する
- `docs/reports/event-log-schema.md`: [Steering Docs sync candidate] L64 (`Emitted by claude-watchdog.sh immediately before killing a hung process.`) と L88 (`Emission point: ...`) の説明文は、生存再確認の追加後も文言上矛盾しないことを確認済み (grep 済み、変更不要と判断) — `/code` フェーズで最終確認

## Implementation Steps

1. `scripts/claude-watchdog.sh` の JSON モード分岐 (L75-82) を以下のとおり書き換える。生存確認が取れた場合のみ `echo`/`_auto_emit_watchdog_kill`/`kill`/`_watchdog_killed=true` を実行し、`break` は生死に関わらず必ず実行する (→ 受入条件 A):

   ```bash
   if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]; then
     if kill -0 "$cmd_pid" 2>/dev/null; then
       echo "" >&2
       echo "watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process (pid=${cmd_pid})" >&2
       _auto_emit_watchdog_kill "$cmd_pid" "$unchanged_time"
       kill "$cmd_pid" 2>/dev/null
       _watchdog_killed=true
     fi
     break
   fi
   ```

2. 同じラップを通常モード分岐 (L93-100) にも適用する (1 と並行可能) (→ 受入条件 A):

   ```bash
   if [[ "$unchanged_time" -ge "$WATCHDOG_TIMEOUT" ]]; then
     if kill -0 "$cmd_pid" 2>/dev/null; then
       echo "" >&2
       echo "watchdog: no output for ${WATCHDOG_TIMEOUT}s, killing process (pid=${cmd_pid})" >&2
       _auto_emit_watchdog_kill "$cmd_pid" "$unchanged_time"
       kill "$cmd_pid" 2>/dev/null
       _watchdog_killed=true
     fi
     break
   fi
   ```

3. `tests/claude-watchdog.bats` の `"OUTPUT_FORMAT_JSON=1: process that exits normally completes without false kill"` の末尾に以下 2 行を追加する (1, 2 の後) (→ 受入条件 B):

   ```bash
       [ -f "$AUTO_EVENTS_LOG" ]
       ! grep -q '"event":"watchdog_kill"' "$AUTO_EVENTS_LOG"
   ```

   `AUTO_EVENTS_LOG` は `setup()` (L15) で `$BATS_TEST_TMPDIR/auto-events.jsonl` に export 済みであり、`_auto_emit_max_silent` (`scripts/claude-watchdog.sh` L112) がループ終了後に無条件で emit するため、kill の有無に関わらずファイル自体は生成される。したがってこのアサーションは「ファイルの不在」ではなく「`watchdog_kill` 行の不在」を検証する

4. 3 のテストの直後に、通常モード相当の negative case テストを新規追加する (2 と並行可能) (→ 受入条件 B):

   ```bats
   @test "normal mode: process that exits normally during check interval does not emit false kill" {
       cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
   #!/bin/bash
   echo "output"
   sleep 4.5
   exit 0
   MOCK
       chmod +x "$MOCK_DIR/cmd.sh"

       run env WATCHDOG_TIMEOUT=3 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
       [ "$status" -eq 0 ]
       [ -f "$AUTO_EVENTS_LOG" ]
       ! grep -q '"event":"watchdog_kill"' "$AUTO_EVENTS_LOG"
   }
   ```

   タイミング根拠: `WATCHDOG_TIMEOUT=3` により `_CHECK_INTERVAL=3` (`min(WATCHDOG_TIMEOUT, 10)`)。1 回目のチェック (t=3s) の時点で mock はまだ生存中 (echo 直後に `sleep 4.5` 中) のため、出力サイズが初期値 0 から変化したと判定されて `unchanged_time` は 0 にリセットされる。2 回目のチェック (t=6s) の時点では mock は `t=4.5s` に既に終了しており新たな出力もないため、`unchanged_time` が `_CHECK_INTERVAL` 分加算されて閾値 3 に到達する — この瞬間、プロセスは 1.5 秒前から既に終了している

5. `bats tests/claude-watchdog.bats` を実行し、全テストが PASS することを確認する (3, 4 の後) (→ 受入条件 C)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/claude-watchdog.sh の watchdog ループにおいて、kill 分岐に入る直前にプロセスの生存を再確認し、既に終了している場合は watchdog_kill を emit せずループを抜ける。JSON モードと通常モードの両方の分岐が対象" --> kill 分岐直前の生存再確認が実装されている
- <!-- verify: rubric "tests/claude-watchdog.bats に、スリープ中に正常終了したプロセスに対して watchdog_kill イベントが emit されないことを検証するテストが存在する。exit status だけでなく AUTO_EVENTS_LOG の内容 (watchdog_kill の不在) を assert していること" --> 偽 kill の不在を検証する negative case テストが存在する
- <!-- verify: command "bats tests/claude-watchdog.bats" --> `tests/claude-watchdog.bats` が PASS する

### Post-merge

- 次回以降の `/auto` 実行で、正常終了したフェーズに対して `watchdog_kill` イベントが新規追加されていないことを確認する <!-- verify-type: observation event=auto-run -->

## Consumed Comments

No new comments since last phase.

## Notes

- 本 Issue の受入条件 2 は「テストが存在する」ことのみを要求しており、Issue 本文が明示的に参照する再現事例は JSON モード側 (既存テストの強化) のみである。ただし受入条件 1 (rubric) は修正が JSON モード・通常モードの両分岐に及ぶことを明記しているため、実装ステップ 4 で通常モード側の negative case テストも追加する判断とした (non-interactive mode: 自動解決)。両分岐とも同一パターンの修正であり、片方のみ回帰テストで保護すると、テストされない方の分岐が将来のリファクタリングで再び生存確認を失っても検知できないリスクがあるため
- 実装ステップ 4 の新規テストはタイミング依存 (`_CHECK_INTERVAL=3` に対して 1.5 秒のマージン) であり、既存テスト群 (`watchdog timeout` 等の `WATCHDOG_TIMEOUT=2`/`3` を使うテスト) と同程度の精度を前提とする。CI 環境で実行が不安定な場合は `sleep` の値や `WATCHDOG_TIMEOUT` を調整すること
- `docs/reports/event-log-schema.md` の `watchdog_kill` セクション (L64, L88) の説明文 ("immediately before killing a hung process" 等) は、生存再確認の追加によってむしろ正確になる (誤発火を防ぐことで、ドキュメントが元々主張していた不変条件に実装が追いつく) ため、変更不要と判断した
