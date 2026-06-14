# Issue #638: auto-events-rollup script

## Overview

`.tmp/auto-events.jsonl`（`/auto` セッションが emit する構造化 JSONL event log）は ephemeral で `.gitignore` 配下にある。セッション終了時に破棄されるため、cross-session メトリクス集計が不可能だった。

本 Issue では JSONL を日付単位で集約し、`docs/reports/auto-events-rollup-YYYY-MM-DD.md` として永続化する `scripts/auto-events-rollup.sh` を実装する。raw stream は引き続き ephemeral のまま、curated summary のみをコミット対象とする。

出力フォーマット: frontmatter (type/description/generated_by/generated_at) + 4 セクション — Sessions / Phase Distribution / Recovery Tier Invocations / Anomalies。

## Changed Files

- `scripts/auto-events-rollup.sh`: 新規。`--date`/`--input`/`--output-dir`/`--cleanup` 対応 rollup script — bash 3.2+ compatible
- `tests/auto-events-rollup.bats`: 新規。4 ケース (empty input / single session / multi-session / cleanup rotation)
- `docs/structure.md`: scripts 説明行追加 (Project utilities 節)、ファイル数 54→55 に更新、tests ファイル数を 74 に更新
- `docs/ja/structure.md`: 同上を日本語で反映

## Implementation Steps

1. `scripts/auto-events-rollup.sh` 新規作成: オプション解析 (`--date` 今日 UTC / `--input` `.tmp/auto-events.jsonl` / `--output-dir` `docs/reports/` / `--cleanup` off) を実装; `--output-dir` を `mkdir -p` で作成; 入力 JSONL が空またはファイル不在の場合は空セクションで出力し exit 0 (→ AC1, AC2, AC3)
2. jq ベースの rollup ロジック実装: 対象日 (`--date`) でフィルタ → `sub_start`/`sub_complete` から Sessions 表 (Issue / Size / Start UTC / End UTC / Duration / Phases / Recoveries / Outcome) 生成、`phase_start`/`phase_complete` ペアから Phase Distribution 表 (Phase / Count / Median Duration / p95) 生成、`recovery` event から Recovery Tier 表 (Tier / Count / Issues) 生成、`anomaly` event から Anomalies リスト生成 → frontmatter 4 フィールド付き markdown を `--output-dir/auto-events-rollup-YYYY-MM-DD.md` へ書き出し; `--cleanup` 指定時は対象日エントリを `--input` JSONL から削除 (→ AC6, AC3)
3. `tests/auto-events-rollup.bats` 新規作成: (a) empty input → ファイル生成・4 セクション存在確認、(b) single session rollup → Sessions 行数検証、(c) multi-session aggregation → 複数 issue 集計確認、(d) cleanup rotation → 該当日エントリ削除・他日エントリ保持確認 (→ AC4, AC5)
4. `docs/structure.md` 更新: Scripts > Project utilities 節に `scripts/auto-events-rollup.sh` 説明行追加; `scripts/` カウント 54→55; `tests/` カウント 71→74（現在実態 73 + 本 Issue 追加 1）(→ AC7)
5. `docs/ja/structure.md` 更新: 同内容を日本語で反映 (スクリプト説明、ファイルカウント)

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/auto-events-rollup.sh" --> `scripts/auto-events-rollup.sh` が新規作成されている
- <!-- verify: command "bash -n scripts/auto-events-rollup.sh" --> 構文エラーなし
- <!-- verify: grep -- "--date|--input|--output-dir|--cleanup" "scripts/auto-events-rollup.sh" --> 4 オプション (`--date` / `--input` / `--output-dir` / `--cleanup`) すべて実装されている
- <!-- verify: grep "auto-events-rollup" "tests/auto-events-rollup.bats" --> bats テストファイル `tests/auto-events-rollup.bats` が新規作成されている
- <!-- verify: command "bats tests/auto-events-rollup.bats" --> bats テストが green（最小 4 ケース: empty input / single session rollup / multi-session aggregation / cleanup rotation）
- <!-- verify: rubric "scripts/auto-events-rollup.sh produces a markdown report under docs/reports/auto-events-rollup-YYYY-MM-DD.md with frontmatter (type/description/generated_by/generated_at), Sessions table, Phase Distribution table, Recovery Tier Invocations table, and Anomalies section, parsing the JSONL input with jq" --> 出力フォーマット 4 セクション（Sessions / Phase Distribution / Recovery Tier / Anomalies）と frontmatter 4 フィールドが仕様通り
- <!-- verify: grep "auto-events-rollup" "docs/structure.md" --> `docs/structure.md` に新スクリプトが追記されている

### Post-merge

- 次回の本格 `/auto --batch` 実行後に `scripts/auto-events-rollup.sh --date $(date -u +%Y-%m-%d)` を手動実行し、当日 session が curated に再構成されることを確認
- 自動実行（cron / git hook / `/auto` 終了時 hook 等）の議論 follow-up Issue が起票されている

## Notes

- `docs/structure.md` の tests カウントは既に実態 (73 ファイル) と乖離あり (記載: 71)。本 Issue で 74 に更新する
- jq は Key Dependencies (docs/tech.md) に記載済みのため前提依存として扱う
- bash 3.2+ 互換必須: `mapfile` / `declare -A` 不可。jq で JSON 処理、awk/sed で文字列操作
- `date -u +%Y-%m-%d` は macOS (BSD date) / Linux 共通で動作する
- Size 計算のためのフィールド (`size`) は現在の event schema に存在しない。Sessions 表の Size 列はイベントに含まれる場合のみ表示し、ない場合は `-` とする
- `phase_complete` event が存在しない phase の Duration は `-` とする (watchdog kill 等の異常終了)

## Code Retrospective

### Deviations from Design

- bats テスト数が 4 ではなく 5 ケース: empty input の frontmatter テストを独立させた（AC5 の「最小 4 ケース」は満たしつつ frontmatter 検証を独立させる方が可読性が高い）
- `write_sessions_section` / `write_phase_dist_section` などのヘルパー関数で section データと header を一緒に出力するパターンを採用。Spec は「sections separate write」を明示していなかったが実装上まとめる方が DRY

### Design Gaps/Ambiguities

- verify command #3 の `\|` は ripgrep 文脈では literal backslash-pipe であり alternation ではない（GNU grep BRE の `\|` 挙動と混同されていた）。実装前に検証し `|`（bare pipe）に修正してから進めた
- `anomaly` event は現在 `run-auto-sub.sh` に emit_event 呼び出しがなく（出力のみ）、Anomalies セクションは常に `- (none)` になる。将来 emit_event("anomaly", ...) が追加されれば自動的に機能する設計で対応済み

### Rework

- N/A（設計通り初回で完成）

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `\|` → `|` への verify command 修正を apply: Issue body と Spec の両方に反映し、齟齬なし
- bash 3.2+ 互換を jq 一本で実現: `declare -A` や `mapfile` を一切使わず、jq の `group_by` / `map` / `sort_by` で集計ロジックをすべて処理
- ヘルパー関数（`write_header`, `write_sessions_section` 等）を `{ ... } > FILE` ブロック内で呼ぶパターンを採用: 可読性と DRY を確保

### Deferred Items
- `anomaly` event emit は本 Issue スコープ外。`run-auto-sub.sh` への emit_event 追加は #630 関連で別途検討
- 自動実行（cron / hook）は Issue body で明示的に別 Issue 扱いとなっている
- Duration が midnight をまたぐ場合の `+86400` 補正を実装したが、実際のテストケースは未作成（エッジケース）

### Notes for Next Phase
- verify command #3 を `\|` → `|` に修正済み（Issue body と Spec 両方）: /review 時に元の形と比較しないよう注意
- bats テストは 5 ケース（frontmatter テストを独立させたため）。AC の「最小 4 ケース」を超過しているが設計意図通り
- `anomaly` セクションは現実装では常に `- (none)` となる（emit_event 未実装のため）: /review で設計上の制限として認識すること
