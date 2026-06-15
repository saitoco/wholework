# Issue #666: audit/auto-session: phase 別 silent window 閾値違反を Summary 行 + Issue 別 Notes に追加

## Overview

`/audit auto-session` レポートの Summary 表に「Phase silent windows > threshold」行を追加し、phase 別 watchdog デフォルト − 600 秒を閾値とした silent window 違反件数・breakdown を表示する。加えて Per-Issue Notes において、閾値超過した silent window を `Silent <N>s phase=<phase> (within 600s of watchdog limit)` 形式で区別して表記する。これにより、watchdog デフォルトを引き締めるためのエビデンスを収集できるようにする。

`merge` フェーズは `WATCHDOG_TIMEOUT_MERGE_DEFAULT=600` で threshold=0 となるため、Summary breakdown から除外する。

## Changed Files

- `scripts/get-auto-session-report.sh`: watchdog-defaults.sh を source し、phase 別 threshold を計算; PHASE_SILENT_BREAKDOWN 変数と Summary row を追加; per-issue Notes に phase-aware at-risk 判定を追加 — bash 3.2+ 互換
- `tests/audit-auto-session.bats`: silent window threshold 違反フィクスチャを含む新テストを追加

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `source "$SCRIPT_DIR/emit-event.sh"` の直後 (行 25 付近) に `source "$SCRIPT_DIR/watchdog-defaults.sh"` を追加し、`SILENT_MARGIN=600` 定数と phase 別閾値変数 (`SILENT_THRESHOLD_SPEC=$(( WATCHDOG_TIMEOUT_SPEC_DEFAULT - SILENT_MARGIN ))` など) を定義する。merge フェーズは `threshold<=0` となるため除外フラグとして扱う (→ AC3)

2. Step 1 の後 (per-issue ループの前)、 `MAX_SILENT` 計算付近に `PHASE_SILENT_BREAKDOWN` 計算ブロックを追加する。`EVENTS_JSON` から `max_silent_window` イベント (phase=merge を除く) を抽出し、phase 別 threshold と `max_sec` を比較。違反件数を phase 別 (`spec/code/review/issue`) にカウントし `<count> (phase=code:<n>, spec:<n>, review:<n>)` 形式の文字列を組み立てる。違反なしなら `"0"` を設定する (→ AC1, AC6)

3. レポートテンプレート (行 380 付近の `| Max silent window (any phase) |` 行) の直後に `| Phase silent windows > threshold | ${PHASE_SILENT_BREAKDOWN} |` 行を追加する (→ AC1, AC5, AC6)

4. per-issue ループ内の Notes 判定 (行 268–269 付近) を phase-aware に変更する。`_issue_events` から `max_silent_window` イベントを phase 別に抽出し、phase 別 threshold を超えるイベントが存在する場合は `max_sec` が最大のものを選び `Silent <N>s phase=<phase> (within 600s of watchdog limit)` を `_notes_parts` に追加する。phase threshold 違反がない場合は既存の `_max_silent > 600` フォールバック動作を維持する (→ AC2)

5. `tests/audit-auto-session.bats` に `@test "success: phase silent window threshold violation appears in Summary and Notes"` を追加する。フィクスチャに `max_silent_window` イベント (`phase=spec`, `max_sec=1500`、threshold=1200 を超える) を含め、`grep -q "Phase silent windows"` と `grep -q "within 600s of watchdog limit"` で Summary 行とNotes アノテーションを検証する (→ AC4)

## Verification

### Pre-merge

- <!-- verify: grep "Phase silent windows" "scripts/get-auto-session-report.sh" --> サマリ行が追加されている
- <!-- verify: grep "within 600s of watchdog limit" "scripts/get-auto-session-report.sh" --> Issue 別 Notes に閾値超過アノテーションが実装されている
- <!-- verify: grep "watchdog.limit\|WATCHDOG_THRESHOLD\|_MARGIN\|at_risk" "scripts/get-auto-session-report.sh" --> 閾値判定ロジック（margin 定数またはしきい値変数）が実装されている
- <!-- verify: command "bats tests/audit-auto-session.bats" --> bats テストが green (silent window threshold fixture を追加)
- <!-- verify: rubric "scripts/get-auto-session-report.sh の Summary 表に 'Phase silent windows > threshold' 行が追加されており、phase 別 breakdown (merge フェーズ除外) が示されている。また Per-Issue Notes 列に silent window が phase 別 watchdog デフォルト − 600 秒 閾値を超えた Issue へのアノテーションが実装されている" --> rubric 基準を満たす
- <!-- verify: file_contains "scripts/get-auto-session-report.sh" "Phase silent windows" --> Summary 行のラベル文字列が含まれる

### Post-merge

- 次回 `/auto` 完走後の `/audit auto-session` レポートで本メトリックが期待通り集計されることを確認

## Notes

- `max_silent_window` イベントには既に `phase` フィールドが含まれている (`scripts/claude-watchdog.sh` の `_auto_emit_max_silent` 関数で `phase=${EMIT_PHASE_NAME:-unknown}` として emit される)
- `scripts/get-auto-session-report.sh` は現状 `watchdog-defaults.sh` を source していないため、Step 1 で追加が必要
- merge フェーズ (WATCHDOG_TIMEOUT_MERGE_DEFAULT=600) の threshold = 600 - 600 = 0 → Summary breakdown から除外
- Implementation Steps 数は 5 (SPEC_DEPTH=light 上限)、Pre-merge verification 数は 6 (Issue body AC をそのまま全コピー — sync rule 優先)
- Issue body の Auto-Resolved Ambiguity Points に沿って設計した (merge 除外、watchdog-defaults.sh 参照、AC 分割)

## Code Retrospective

### Deviations from Design

- None: 実装は Spec の 5 ステップに沿って忠実に実施した。

### Design Gaps/Ambiguities

- AC#3 の `grep "watchdog.limit\|WATCHDOG_THRESHOLD\|_MARGIN\|at_risk"` は BRE 形式 (`\|` を OR として使用) だが、verify-executor は ripgrep (ERE デフォルト) を使用する。実際のコードには `_MARGIN` と `at_risk` の両方が含まれているため verify は PASS するが、正確には ERE OR パターン (`|`) を使うべきだった。Issue の Auto-Resolved Ambiguity Points に記載されている AC 分割で対処済み。
- per-issue の `_at_risk_silent` jq クエリは `--argjson` で 4 つの閾値変数を渡す構造になっており、ループ内で毎回実行される。Issue 数が多い場合は jq 起動コストが累積するが、現状の規模では問題ない。

### Rework

- None: 実装は一発で全テスト PASS。修正なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `watchdog-defaults.sh` を `get-auto-session-report.sh` の先頭 (emit-event.sh source 直後) で source し、`SILENT_MARGIN=600` と phase 別閾値変数を定義した。merge フェーズは threshold=0 なので除外。
- `PHASE_SILENT_BREAKDOWN` の jq クエリは `--argjson` で 4 変数 (t_spec/t_code/t_review/t_issue) を渡し、違反 phase をカウントして `<total> (code:<n>, spec:<n>)` 形式で出力する設計にした。
- per-issue Notes は `_at_risk_silent` が空なら既存の `_max_silent > 600` フォールバックを維持する 2 段階フォールバック構造にした。

### Deferred Items
- merge フェーズの threshold floor (min 60s など) の設定は Issue body で却下され設計から除外。将来 merge watchdog の引き締めが必要になったら別 Issue で対応。
- `_at_risk_silent` jq クエリのループ内起動コスト最適化は Issue 数が増えた段階で検討 (Icebox 候補)。

### Notes for Next Phase
- AC#3 の BRE `\|` パターンは `/verify` で ripgrep ERE として実行される点に注意。`_MARGIN` と `at_risk` のどちらかが実装に残っていれば PASS するはず。
- bats テスト #5 (`phase silent window threshold violation appears in Summary and Notes`) がフィクスチャの spec phase (max_sec=1500, threshold=1200) で PASS していることを確認済み。
- Post-merge AC は `verify-type: observation event=auto-run` — 次回 `/auto` 完走後に `/audit auto-session` で確認。
