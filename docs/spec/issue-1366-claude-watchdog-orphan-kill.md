# Issue #1366: claude-watchdog.bats: WATCHDOG_TIMEOUT カスタム値テストが Claude Code Bash ツールサンドボックス下で決定論的に FAIL する

## Overview

`scripts/claude-watchdog.sh` は監視対象コマンド (`"$@"`) をバックグラウンドジョブとして起動し、タイムアウト時に直接の子プロセス (`cmd_pid`) 1 つだけを `kill` する。監視対象コマンドがスクリプトファイルの実行のように内部でさらに子プロセスを fork する場合 (例: `sleep 60` を含むスクリプトファイル)、その孫プロセスは kill の対象にならず孤児化 (orphan 化) して自身の残り時間だけ生存し続ける。この孤児プロセスの残存が、プロセスツリー全体の完了を暗黙に待つ外側のハーネス (bats) の壁時計時間を押し上げ、`tests/claude-watchdog.bats` の `WATCHDOG_TIMEOUT env var: custom value takes effect` が並列実行負荷下 (`bats --jobs 18 tests/`) で FAIL する一因になっていたと判断した。監視対象コマンドをプロセスグループ単位で起動・kill するよう改修し、孤児プロセスの残存を解消する。

## Reproduction Steps

1. `bats --filter "custom value takes effect" tests/claude-watchdog.bats` を単独実行すると、テスト自身の `[ "$elapsed" -lt 30 ]` 判定は高速に完了して `ok` になる (Spec investigation 時点の実測で 2 回とも PASS。`/issue` Step 15 の AC 監査コメントの 3/3 PASS 観測と一致)。しかし `time` でラップして壁時計を測ると、`bats` プロセス全体の終了までに `sleep 60` とほぼ同じ約 60 秒を要する (実測: 60.18 秒)。
2. `WATCHDOG_TIMEOUT=2 bash scripts/claude-watchdog.sh bash cmd.sh` (`cmd.sh` は `sleep 60` のみを含むスクリプトファイル) を直接実行し、kill 発火後のプロセスツリーを `ps -eo pid,ppid,pgid,stat,command` で追跡すると、`claude-watchdog.sh` 自身は正しく即座に終了する (`exit=143`) 一方、`sleep 60` プロセスは `PPID=1` に再親化されて生存し続け、`bash cmd.sh` の元の `PGID` を保持したまま元の 60 秒間動き続ける。

## Root Cause

`_run_with_watchdog()` は `"$@" > "$tmpout" 2>&1 &` で監視対象コマンドを単なるバックグラウンドジョブとして起動しており、ジョブコントロール (`set -m`) を有効化していないため、そのジョブは `claude-watchdog.sh` 自身のプロセスグループを共有する。タイムアウト時は `kill "$cmd_pid"` で直接の子プロセス 1 つだけに SIGTERM を送っている。監視対象コマンドがスクリプトファイルの実行のように内部でさらに子プロセスを fork する場合 (`sleep 60` は `exec` されず `bash cmd.sh` の子として fork される)、その子は signal を受け取らない。

`claude-watchdog.sh` 自身の `wait "$cmd_pid"` は直接の子プロセスの終了を正しく検出して速やかに復帰する (Reproduction Steps 2 で確認)。したがって Background に記載された「`wait "$cmd_pid"` の復帰に `sleep 60` の全時間を要した」という記述は、`claude-watchdog.sh` 自身の内部ロジックの滞留ではなく、孤児化した孫プロセスの残存を外側のハーネス (bats) が壁時計に反映してしまう挙動を指していたと考えられる (精度差の詳細は Notes 参照)。

`tests/claude-watchdog.bats` にはこの孤児を生む `sleep 60` ベースのモックを使うテストが本ファイルだけで 5 件あり、`bats --jobs 18 tests/` のような並列実行下ではこれらの孤児プロセスが同時多発してスケジューリング/リソース競合を悪化させ、個別テストの `elapsed < 30s` 判定を押し上げる方向に働き得る。この孤児プロセスのリーク自体は、`claude-watchdog.sh` 本来の用途 (`claude -p` 呼び出しのラップ) においても、ハング時に `claude` 自身が残す子プロセスを掃除できないという実害のある不具合であり、本テストの再現性問題を超えて修正する価値がある。

## Changed Files

- `scripts/claude-watchdog.sh`: `_run_with_watchdog()` を修正 — ジョブコントロールを有効化し (`set -uo pipefail` → `set -umo pipefail`)、kill 対象をプロセスグループ全体に拡張 (`kill "$cmd_pid" 2>/dev/null` → `kill -- "-$cmd_pid" 2>/dev/null`、2 箇所)。既存行の in-place 変更のみで行数を変えない (bash 3.2+ 互換)
- `tests/claude-watchdog.bats`: 孫プロセスが kill 後も生存しないことを直接検証する新規 `@test` をファイル末尾に追加

## Implementation Steps

1. `scripts/claude-watchdog.sh`: `_run_with_watchdog()` にジョブコントロールを有効化 (`set -uo pipefail` → `set -umo pipefail`、L10) し、kill 対象をプロセスグループ全体に拡張 (`kill "$cmd_pid" 2>/dev/null` → `kill -- "-$cmd_pid" 2>/dev/null`、L80 と L100 の 2 箇所) — 監視対象コマンドが内部で fork する子プロセスも確実に終了させる。いずれも in-place の 1 行差し替えのみで行数を変えない (→ acceptance criteria: AC1)
2. `tests/claude-watchdog.bats`: ファイル末尾に新規 `@test` を追加 — モックコマンドが `sleep 60 &` をバックグラウンドで起動して PID をマーカーファイルに記録し `wait` するようにし、watchdog kill 発火後に `kill -0 <マーカー PID>` で当該プロセスが生存していないことを検証する (after 1) (→ acceptance criteria: AC1。新規分岐ロジックに対する新規テストケース要件を満たす、詳細は Notes)

## Verification

### Pre-merge

- <!-- verify: command "bats --filter \"custom value takes effect\" tests/claude-watchdog.bats" --> Claude Code Bash ツールサンドボックス環境下で `WATCHDOG_TIMEOUT env var: custom value takes effect` テストが PASS する

### Post-merge

- 次回このサンドボックス環境で `/code` の Step 9 Behavioral Change Detection が `tests/` full suite を実行した際に、当該テストが FAIL しないことを確認 <!-- verify-type: opportunistic -->

## Notes

- **AC の verify command 精度に関する `/issue` Step 15 コメントへの回答**: 本 AC の verify command (`bats --filter "custom value takes effect" tests/claude-watchdog.bats` を単独実行) は、Spec investigation 時点の実測で未修正のスクリプトに対しても標準的な条件では PASS することを確認した (2 回実行しいずれも `ok`)。これはテスト自身の `elapsed` 計測が `run ...` コマンドの実行時間のみを狭く測定しており、コマンド全体 (bats プロセス) の壁時計時間には孤児プロセスの残存が反映されないためである。したがって本 AC は Pattern 2 (常時 PASS な verify command) の疑いが実際に該当する。`docs/product.md` § `/issue` vs `/spec` Responsibility Boundary と Verify command sync rule により、Issue body の AC/verify command を `/spec` が独自に書き換えることはできないため、AC はそのまま copy している。修正の実際の判別力は Implementation Steps 2 の新規テストケースが担う (Spec investigation 時点で、未修正版で FAIL・修正版で PASS することを確認済み) が、これは AC の `--filter` には含まれず `bats tests/claude-watchdog.bats` 全体実行や CI の full suite 実行でのみ捕捉される点に注意
- **新規分岐ロジックへの新規テストケース要件**: Implementation Steps 1 で導入するプロセスグループ kill は既存スクリプトへの新規ロジックにあたるため、それを直接検証する新規テストケース (Implementation Steps 2) を追加した。既存スイート (`tests/claude-watchdog.bats` 12 件) が PASS することに加え、この新規テストケースを含めて PASS することを `/code` の完了条件とする
- **Background の記述の精度についての補足**: Issue Background は「`wait "$cmd_pid"` の復帰に `sleep 60` の全時間を要した」としているが、Spec investigation の直接検証では `claude-watchdog.sh` 自身の `wait "$cmd_pid"` は kill 後速やかに復帰する (`exit=143`)。壁時計に現れる遅延の実体は、孤児化した孫プロセスの残存を外側のハーネスが (プロセスツリー全体の完了待ちという形で) 反映してしまう挙動であり、`claude-watchdog.sh` 自身の `wait` が滞留しているわけではない。Root Cause 節はこの精度差を反映して記述した
- **行番号安定性の設計制約**: `modules/orchestration-fallbacks.md:400` が `scripts/claude-watchdog.sh line 71` (json mode の `still waiting` メッセージ) を明示的に参照している。Implementation Steps の変更はいずれも既存行の in-place 差し替えのみとし、行の追加・削除を行わないことでこの参照を破壊しない設計とした (`docs/`, `modules/`, `tests/`, `scripts/` 全体を `claude-watchdog` で横断 grep し、他に現行ドキュメントからの行番号参照がないことを確認済み。`docs/spec/issue-*.md` / `docs/reports/*.md` にも行番号参照が複数あるが、いずれも disposable な過去記録のため Exclusions 対象とした)
- **Fail-safe critical script 判定**: `claude-watchdog.sh` は `2>/dev/null` や `|| true` を含むが (grep で確認済み)、その役割はプロセス監視ラッパーであり、他の処理の accept/reject を決定するゲート/バリデータではないため、fail-safe critical には該当しないと判定した。既存の `2>/dev/null` はいずれも「対象プロセスが既に終了しているレースコンディション」を吸収する定型パターンであり、本修正はその種類を変えない (`kill -- "-$cmd_pid" 2>/dev/null` も同じレースコンディション吸収)
- **#1142 (spawn detachment) との非干渉確認**: `run-auto-sub.sh` 自身の spawn detachment shim (`WHOLEWORK_SPAWN_DETACH`) と `claude-watchdog.sh` は入れ子関係にない — `claude-watchdog.sh` は `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-issue.sh` / `run-merge.sh` それぞれの内部で `claude -p` 呼び出しを直接ラップしており (grep で確認済み)、`run-auto-sub.sh` 自身は `claude-watchdog.sh` を呼ばない。プロセスツリー上の別階層のため本修正の影響範囲外
- **Spec investigation 時点での動作確認 (`/code` での再実装後の確認は別途必要)**: 候補修正 (`set -umo pipefail` + 両 kill 呼び出しの `kill -- "-$cmd_pid"` 化) を `.tmp/` 上のコピーに適用し、(a) 孫プロセスが残存しないこと、(b) exit code semantics (`143`) が変化しないこと、(c) 既存 12 テストが無改修のまま全て PASS すること、(d) Implementation Steps 2 で追加する新規テストケースが未修正版で FAIL・修正版で PASS することを確認した。macOS の `/bin/bash` (3.2 系相当) で確認しており、Linux CI 環境での再確認は `/code` の通常のテスト実行に委ねる
