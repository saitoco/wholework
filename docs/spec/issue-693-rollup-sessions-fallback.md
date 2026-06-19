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

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Phases / Recoveries 集計列が `$own` (session スコープ) ではなく `$ev[]` (issue 全体) で実装されていた。Spec が "現行を踏襲" と明示したため実装は Spec どおりだが、session_id 別行が生成される新構造では同一 issue が複数セッションで実行された際にクロス汚染が発生する。Spec 記述が "現行を踏襲" という短縮形で将来の含意を隠蔽した典型。次回類似改修では "session スコープ vs. issue スコープ" を明示的に書くこと。

### Recurring Issues

- Nothing to note

### Acceptance Criteria Verification Difficulty

- `command "bats tests/auto-events-rollup.bats"` は safe mode では UNCERTAIN 扱いだが、CI reference fallback (Run bats tests SUCCESS) で PASS に解決できた。verify command 品質に問題なし。
- `rubric` 基準は AI 判断で PASS。3 スクリプトの symmetry (phase_start emit ガード + phase_complete on success) を rubric が適切に捉えていた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #698 を squash merge で main にマージ。CI PASS、review approved の状態で実施
- BASE_BRANCH = main のため `closes #693` が自動で Issue をクローズする
- Phase Handoff を Spec に記録し main に push

### Deferred Items
- post-merge observation: 単一 Issue /auto 完走後の rollup Sessions テーブルに行が出力されることを確認 (Post-merge verification)
- Phases/Recoveries 列を `$own` スコープに変更する改善 (SHOULD 級、別 Issue で検討)

### Notes for Next Phase
- verify フェーズでは post-merge verification (観察確認) が主タスク
- Pre-merge verify コマンドは PR マージ済みのため全 PASS 済み (CI 7 tests green)
- `/auto` 単一 Issue 実行後に `auto-events-rollup.sh` で Sessions テーブルを確認すること
