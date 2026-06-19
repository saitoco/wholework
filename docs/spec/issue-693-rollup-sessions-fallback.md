# Issue #693: run-*.sh: 単一 Issue /auto でも phase_start/phase_complete event を emit して rollup を機能させる

## Overview

`auto-events-rollup.sh` の Sessions テーブルが空のままになる問題を解消する。`#693` の初回実装 (PR #697) で `phase_start`/`phase_complete` event の emit を追加し Phase Distribution は機能するようになったが、Sessions テーブルは依然として `sub_start`/`sub_complete` event に依存しているため、単一 Issue `/auto` (= `run-auto-sub.sh` 非経由パス) では集計されない。

本 Issue では `auto-events-rollup.sh` の Sessions セクションを修正し、`sub_start`/`sub_complete` が無い場合は `phase_start`/`phase_complete` から (issue, session_id) 単位でセッションを合成する fallback を追加する。

## Reproduction Steps

1. 単一 Issue M サイズ (`/auto N`) を pr route で完走する
2. `auto-events-rollup.sh --date YYYY-MM-DD` でロールアップを生成する
3. `phase_start`/`phase_complete` event は記録されているが、Sessions テーブルが空のまま (Phase Distribution はデータあり)
4. 実例: 2026-06-19 の `/auto 684` (patch route, single-Issue) でも同様に Sessions 空

## Root Cause

`scripts/auto-events-rollup.sh:120-148` の Sessions jq クエリは `select(.event == "sub_start")` を起点としてセッションを enumerate する。`sub_start` は `run-auto-sub.sh:201` でのみ emit されるため、`run-auto-sub.sh` 非経由パス (単一 Issue `/auto` の parent session が `run-*.sh` を直接呼び出す経路) では集計対象から漏れる。

`#693` の初回実装で `run-code.sh`/`run-review.sh`/`run-merge.sh` から `phase_start`/`phase_complete` を emit するようにしたが、Sessions セクションの jq ロジック自体は変更していなかったため、Phase Distribution のみ機能して Sessions は空のままという状態になった。

## Changed Files

- `scripts/auto-events-rollup.sh`: Sessions jq クエリを修正し、`sub_start` が無い (issue, session_id) ペアについて `phase_start`/`phase_complete` から合成する fallback を追加 — bash 3.2+ 互換
- `tests/auto-events-rollup.bats`: `phase_start`/`phase_complete` のみのケースで Sessions 行が生成されることを検証する bats テストを追加

## Implementation Steps

1. `scripts/auto-events-rollup.sh:120-148` の Sessions jq クエリを修正する (→ AC1, AC2, AC3, AC4)

   - jq の起点を `[$ev[] | select(.event == "sub_start")]` から `[$ev[] | {issue, session_id: (.session_id // "")}] | unique | sort_by(.issue)` (全 (issue, session_id) ペア列挙) に変更する
   - 各ペアについて以下を解決する:
     - `$sub_start = $own | map(select(.event == "sub_start")) | first` (`$own` は同一 (issue, session_id) の event 配列)
     - `$first_phase_start = $own | map(select(.event == "phase_start")) | first`
     - `$start = $sub_start // $first_phase_start` (sub_start 優先、なければ phase_start)
     - `$sub_complete = $own | map(select(.event == "sub_complete")) | last`
     - `$last_phase_complete = $own | map(select(.event == "phase_complete")) | last`
     - `$end = $sub_complete // $last_phase_complete`
     - `$size = $sub_start.size // "-"` (sub_start が無い場合は `-`)
     - `$outcome = if $sub_complete then (if $sub_complete.exit_code == "0" then "success" else "failure" end) elif $last_phase_complete then "success" else "incomplete" end`
   - `$start == null` (=どちらの event も無い) のセッションは出力から除外する
   - Phases / Recoveries / Duration の集計ロジックは現行を踏襲

2. `tests/auto-events-rollup.bats` に新規テストケースを 2 件追加する (→ AC5)

   - `auto-events-rollup: phase_start/phase_complete only (no sub_*) produces session row`: `phase_start`/`phase_complete` のみのイベント列で `| #N` 行が生成され Outcome が `success` になることを確認 (size 列が `-`、Phases 列に phase 名が並ぶ)
   - `auto-events-rollup: phase_start without phase_complete produces incomplete outcome`: `phase_start` のみで `phase_complete` 無しの場合に Outcome が `incomplete` になることを確認

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/auto-events-rollup.sh" "phase_start" --> `scripts/auto-events-rollup.sh` の Sessions ロジックが `phase_start` を参照している
- <!-- verify: file_contains "scripts/auto-events-rollup.sh" "phase_complete" --> `scripts/auto-events-rollup.sh` の Sessions ロジックが `phase_complete` を参照している
- <!-- verify: file_contains "tests/auto-events-rollup.bats" "phase_start/phase_complete only" --> `tests/auto-events-rollup.bats` に fallback 用の新規テストが追加されている
- <!-- verify: file_contains "tests/auto-events-rollup.bats" "incomplete outcome" --> `tests/auto-events-rollup.bats` に incomplete outcome 用の新規テストが追加されている
- <!-- verify: command "bats tests/auto-events-rollup.bats" --> `bats tests/auto-events-rollup.bats` がすべて green

### Post-merge

- 次回 単一 Issue `/auto` 完走後の rollup で Sessions テーブルに `| #N` 行が出力されることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- jq の `unique` は object に対しても機能し、`{issue, session_id}` を unique key とする
- `session_id` が JSON に欠落している legacy event 対策として `.session_id // ""` で `""` に正規化してから unique に渡す
- `$sub_complete.exit_code` は `"0"` (文字列) で比較する (`run-auto-sub.sh:289` で `emit_event "sub_complete" "exit_code=0"` から `"0"` 文字列として記録される)
- Phases 列の現行ロジック (`select(.event == "phase_complete" and .issue == $iss) | .phase | join("→")`) は単一 Issue 経路でも phase_complete が emit されるため変更不要
- Recoveries 列の `recovery` event 集計は単一 Issue 経路では発生しないため `—` 表示 (現行通り)
- bash 3.2+ 互換: jq 内の変更のみで、シェル組み込みは現行のまま使用

## Code Retrospective

### Deviations from Design

- None

### Design Gaps/Ambiguities

- Spec の jq クエリ疑似コードでは `$own` を `($ev | map(select(.issue == $iss and ...)))` で絞るが、`session_id` の正規化 (`.session_id // ""`) を `unique` 前と `$own` 絞り込み時の両方に適用する必要があった。Spec では明示されていなかったが実装時に統一した

### Rework

- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Sessions jq クエリを `sub_start` 起点から `{issue, session_id}` 全列挙に変更し fallback 追加 (Spec どおり)
- `session_id` が欠落した legacy event を `.session_id // ""` で正規化してから `unique` に渡す設計を採用
- `$own` 変数で同一 `(issue, session_id)` のイベント列を絞り、`sub_start`/`phase_start` の優先順位を `//` 演算子で表現

### Deferred Items
- post-merge observation: 単一 Issue /auto 完走後の rollup Sessions テーブルに行が出力されることを確認 (Post-merge verification)
- `token_usage` event の run-*.sh への追加は別 Issue (#662)

### Notes for Next Phase
- テストは 7 件全て PASS (新規 2 件含む)
- PR #698 を review → merge フローで進める
- `bats tests/auto-events-rollup.bats` が 7 件 green であることを CI で確認
