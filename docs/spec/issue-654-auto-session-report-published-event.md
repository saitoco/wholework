# Issue #654: auto-events-log: auto-session-report-published event の log schema 追加と emit 配線

## Overview

`scripts/get-auto-session-report.sh --narrative-draft` 完了時に `auto-session-report-published` event を `.tmp/auto-events.jsonl` に emit する仕組みを追加する。

背景: #632 の post-merge AC #10 が `verify-type: observation event=auto-session-report-published` を要求しているが、現状の 6 event 種に該当 event 名が含まれておらず、observation trigger 機構 (#650) が配線されても発火しない。

## Changed Files

- `scripts/get-auto-session-report.sh`: `emit-event.sh` を source 追加し、`--narrative-draft` 完了直後に `emit_event auto-session-report-published` を呼び出す — bash 3.2+ compatible
- `docs/reports/event-log-schema.md`: 新 event 種 `auto-session-report-published` のスキーマ定義を追加
- `tests/audit-auto-session-full.bats`: `--narrative-draft` 実行後に `AUTO_EVENTS_LOG` に `auto-session-report-published` event が書き込まれることを検証するテストを追加

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `SCRIPT_DIR` 定義直後に source を追加 (→ AC1):
   ```bash
   [[ -f "$SCRIPT_DIR/emit-event.sh" ]] && source "$SCRIPT_DIR/emit-event.sh" || true
   ```
   参考パターン: `scripts/claude-watchdog.sh` L13

2. `--narrative-draft` ブロック内の Python heredoc 終端 (`PYTHON_EOF`) の直後、`fi` の前に emit 呼び出しを追加 (→ AC1):
   ```bash
   declare -f emit_event > /dev/null 2>&1 && \
     AUTO_SESSION_ID="$SESSION_ID" emit_event "auto-session-report-published" "report_path=${OUTPUT_PATH}"
   ```
   - `EMIT_ISSUE_NUMBER` は未設定のため `0`（session 横断 event のため許容）
   - `AUTO_SESSION_ID="$SESSION_ID"` で標準フィールド `session_id` に値を渡す
   - `report_path` を追加 payload として渡す
   - `declare -f` ガードにより emit-event.sh が見つからない場合は skip

3. `docs/reports/event-log-schema.md` に `## New Events (introduced in #654)` セクションを追加し、`auto-session-report-published` event スキーマを記載 (→ AC2):
   - JSON example、フィールド定義表（`ts` / `issue` / `event` / `session_id` / `report_path`）、emission point を記述

4. `tests/audit-auto-session-full.bats` に event emit 確認テストを追加 (→ AC3):
   - テスト名: `@test "full mode: auto-session-report-published event is emitted after --narrative-draft"`
   - 既存 fixture を利用し、`--narrative-draft` 実行後に `AUTO_EVENTS_LOG` を grep して `auto-session-report-published` を検証

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/get-auto-session-report.sh" "auto-session-report-published" --> `scripts/get-auto-session-report.sh --narrative-draft` 完了時に `auto-session-report-published` event が emit される
- <!-- verify: file_contains "docs/reports/event-log-schema.md" "auto-session-report-published" --> `docs/reports/event-log-schema.md` に新 event 種が記載
- <!-- verify: file_contains "tests/audit-auto-session-full.bats" "auto-session-report-published" --> bats テストで event emit を検証
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) 全件 PASS

### Post-merge

なし

## Notes

### Auto-Resolve Log (non-interactive mode)

- **emit タイミング**: `--narrative-draft` フラグを指定して正常完了した場合のみ emit（Issue 記載の Auto-Resolved Ambiguity Points 通り）
- **source インクルード方法**: `claude-watchdog.sh` と同様に `SCRIPT_DIR` 基準で条件付き source。`get-auto-session-report.sh` は standalone 実行もあるため無条件 source は行わない

### emit_event payload 設計

- `session_id`: `AUTO_SESSION_ID="$SESSION_ID"` で標準フィールドを通じて渡す（追加 key=value で重複させない）
- `issue`: 0（session 横断 event）
- `report_path`: 出力先パスをペイロードに含め、observation trigger 側が参照できるようにする
