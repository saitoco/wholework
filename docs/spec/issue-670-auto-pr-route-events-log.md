# Issue #670: auto: pr route 単一 Issue で AUTO_EVENTS_LOG が export されず event emit がスキップされる

## Overview

`/auto` の pr route (M/L-size の単一 Issue) では、`run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` が parent session から直接 Bash invoke される。このとき `AUTO_EVENTS_LOG` が unset のため、各スクリプト内の event emit ガード (`if [[ -n "${AUTO_EVENTS_LOG:-}" ]]`) が false となり、events が一件も記録されない。

`run-auto-sub.sh` (batch/XL route) は冒頭で `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"` + `export` を設定するが、pr route の `run-code.sh` / `run-review.sh` / `run-merge.sh` には同等の処理がない。本 Issue では案 B（各 `run-*.sh` 内でデフォルト fallback を追加）を採用し、DRY に解決する。

`run-spec.sh` は event emit ガードを持たないため対象外。

## Reproduction Steps

1. Size M/L の Issue を `/auto <number>` で pr route 実行
2. 完走後 `.tmp/auto-events.jsonl` を確認
3. 当該 session_id の events が 0 件

## Root Cause

`run-auto-sub.sh` (lines 41–42) が設定する `AUTO_EVENTS_LOG` default を、pr route で使用する `run-code.sh` / `run-review.sh` / `run-merge.sh` が持たない。結果として `AUTO_EVENTS_LOG` が unset のまま `claude -p` が呼ばれ、event emit が全件スキップされる。

## Changed Files

- `scripts/run-code.sh`: `SCRIPT_DIR` 設定直後に `AUTO_EVENTS_LOG` default fallback と export を追加 — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上 — bash 3.2+ compatible
- `scripts/run-merge.sh`: 同上 — bash 3.2+ compatible

## Implementation Steps

1. `scripts/run-code.sh` の `SCRIPT_DIR` 定義行 (line 47) の直後に以下を追加する (→ AC1)
   ```bash
   AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
   export AUTO_EVENTS_LOG
   ```

2. `scripts/run-review.sh` の `SCRIPT_DIR` 定義行 (line 16) の直後に同一の 2 行を追加する (→ AC2)

3. `scripts/run-merge.sh` の `SCRIPT_DIR` 定義行 (line 14) の直後に同一の 2 行を追加する (→ AC3)

## Verification

### Pre-merge

- <!-- verify: grep "AUTO_EVENTS_LOG.*:-.tmp/auto-events.jsonl" "scripts/run-code.sh" --> `scripts/run-code.sh` に AUTO_EVENTS_LOG default fallback が追加されている
- <!-- verify: grep "AUTO_EVENTS_LOG.*:-.tmp/auto-events.jsonl" "scripts/run-review.sh" --> `scripts/run-review.sh` に同 fallback が追加されている
- <!-- verify: grep "AUTO_EVENTS_LOG.*:-.tmp/auto-events.jsonl" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に同 fallback が追加されている
- <!-- verify: command "bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats" --> 既存 bats テストが green (regression 無し)

### Post-merge

- 次回 `/auto` 単一 Issue (pr route) 完走後に `.tmp/auto-events.jsonl` で当該 session_id の events が emit されることを確認

## Notes

- `run-auto-sub.sh` の line 41–42 が手本パターン: `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"` + `export AUTO_EVENTS_LOG`
- 既存 bats テスト (run-code.bats / run-review.bats / run-merge.bats) は `AUTO_EVENTS_LOG` を unset にした状態でテストしており、追加後は常に default が設定される動作に変わる。ただし mock の `claude-watchdog.sh` / `claude` は `OUTPUT_FORMAT_JSON` / `AUTO_EVENTS_LOG` を無視するため既存テストは green のまま。
- `AUTO_SESSION_ID` は parent `/auto` session が既に export しているため、各 `run-*.sh` への追加は不要 (run-auto-sub.sh と異なり SESSION_ID 設定は parent 側の責務)。
