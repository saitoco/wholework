# Issue #699: auto-events-rollup: Phases/Recoveries session scope fix

## Overview

`scripts/auto-events-rollup.sh` の Sessions テーブル生成 jq で、Phases 列と Recoveries 列の集計に `$ev[]` (events 全体) スコープを使用しているため、同一 Issue を複数セッションで実行した場合に両セッションの行で同じ値が表示されるクロス汚染が発生している。`$own` (セッション単位にフィルタ済みの配列、line 126 で定義済み) に差し替えることで修正する。

## Reproduction Steps

1. 同一 Issue #N に対して `/auto` を 2 回完走させる
2. `auto-events-rollup.sh --date YYYY-MM-DD` を実行
3. Sessions テーブルに #N の行が 2 行出力され、Phases 列が両行とも全セッション結合値を表示する

## Root Cause

`scripts/auto-events-rollup.sh:148-149` のjq コードが `$own` ではなく `$ev[]` スコープを参照している:

```jq
# 旧コード (lines 148-149)
([$ev[] | select(.event == "phase_complete" and .issue == $iss) | .phase] | join("→")) as $phases |
([$ev[] | select(.event == "recovery" and .issue == $iss)] | length) as $rec_count |
```

`$own` は line 126 で `($ev | map(select(.issue == $iss and (.session_id // "") == $sid)))` として定義済みだが、Phases/Recoveries 集計には適用されていない。同スコープ内の他の集計 (sub_start, phase_start, sub_complete, last_phase_complete) はすでに `$own` ベースのため、lines 148-149 のみが取り残されている。

## Changed Files

- `scripts/auto-events-rollup.sh`: lines 148-149 の Phases/Recoveries 集計を `$ev[]` から `$own` スコープに変更 — bash 3.2+ compatible
- `tests/auto-events-rollup.bats`: 同一 Issue 複数セッションでの Phases/Recoveries session scope 独立テスト追加

## Implementation Steps

1. `scripts/auto-events-rollup.sh` の lines 148-149 を変更する (→ AC1, AC2, AC3, AC4):
   - FROM: `([$ev[] | select(.event == "phase_complete" and .issue == $iss) | .phase] | join("→")) as $phases |`
   - TO: `($own | map(select(.event == "phase_complete")) | map(.phase) | join("→")) as $phases |`
   - FROM: `([$ev[] | select(.event == "recovery" and .issue == $iss)] | length) as $rec_count |`
   - TO: `($own | map(select(.event == "recovery")) | length) as $rec_count |`

2. `tests/auto-events-rollup.bats` に session scope クロス汚染防止テストを追加する (→ AC5, AC6):
   - 同一 issue に 2 つの session_id ("session_a", "session_b") でイベントを用意
   - session_a では phase "spec" のみ完走、session_b では phase "code" のみ完走
   - rollup 後、#issue の 2 行で各々の Phases 列が "spec" / "code" のみを表示し、"spec→code" のような結合値にならないことを検証
   - テスト名に "session scope" を含める (AC5 の file_contains パターン要件)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/auto-events-rollup.sh" "$own | map(select(.event == \"phase_complete\"))" --> `scripts/auto-events-rollup.sh` の Phases 集計が `$own` スコープに変更されている
- <!-- verify: file_contains "scripts/auto-events-rollup.sh" "$own | map(select(.event == \"recovery\"))" --> `scripts/auto-events-rollup.sh` の Recoveries 集計が `$own` スコープに変更されている
- <!-- verify: file_not_contains "scripts/auto-events-rollup.sh" ".event == \"phase_complete\" and .issue == $iss" --> 旧 `$ev[]` スコープの Phases 行が削除されている
- <!-- verify: file_not_contains "scripts/auto-events-rollup.sh" ".event == \"recovery\" and .issue == $iss" --> 旧 `$ev[]` スコープの Recoveries 行が削除されている
- <!-- verify: file_contains "tests/auto-events-rollup.bats" "session scope" --> `tests/auto-events-rollup.bats` に session スコープのクロス汚染防止テスト追加
- <!-- verify: command "bats tests/auto-events-rollup.bats" --> 既存および新規 bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テスト全件 green

### Post-merge

- 次回同一 Issue を複数セッションで `/auto` 実行した際、rollup の Sessions テーブル各行で Phases / Recoveries が当該セッション分のみを表示することを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- AC1/AC2 の `file_contains` パターン (`$own | map(select(.event == "phase_complete"))`) はすでに line 135 に存在するため、修正前でも PASS する。クロス汚染除去の核心検証は AC3/AC4 の `file_not_contains` チェック。
- `$own` は sessions jq ブロック内 line 126 でスコープ定義済みのため、差し替えのみで追加変数定義は不要。
- bats テストでは `session_id` フィールドを JSONL に含めることで異なるセッションを区別する。既存テストは `session_id` を省略しているが (`""` として扱われる)、新規テストでは明示的に `"session_a"` / `"session_b"` を使用する。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- AC1/AC2 の `file_contains` 検証で `$own` が shell 変数展開されることで false FAIL が起きるリスクがあった。Spec Notes に既に言及あり (`$ev[]` ベースでも line 135 のパターンが PASS するという注意書き)。実際に verify-executor は固定文字列マッチを行うため問題なし。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `$ev[]` スコープの Phases/Recoveries 集計 2 行を `$own` ベースに差し替えた。`$own` は line 126 で定義済みのため追加変数定義は不要。
- bats テストで `session_id: "session_a"/"session_b"` を持つイベントを用い、クロス汚染が解消されていることを session 単位で検証した。

### Deferred Items
- post-merge 確認 (observation AC): 次回同一 Issue を複数セッションで `/auto` 実行した際に実際の rollup 出力を確認する。

### Notes for Next Phase
- 変更は 2 行のみ (`scripts/auto-events-rollup.sh:148-149`) のシンプルな差し替えで、回帰リスクは低い。
- AC7 (CI github_check) はプッシュ後に確認が必要。bats テストはローカルで全件 green 確認済み。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC に `file_not_contains` を 2 件追加して旧 `$ev[]` パターン削除を verify-patterns.md §8 policy change Issues 原則どおりに網羅していた。バグ修正系の Issue では「旧パターン削除」と「新パターン追加」の対称性を確保する規約が機能した好例

#### spec
- Spec 提案で `$own` を line 126 から引用したことで、追加変数定義不要なまま 2 行差し替えに収まった
- Size を S → XS に降格 (バグ修正としては最小単位)

#### code
- design 逸脱なし、bats 新規 test 7 ("session scope") で synthetic 2-session データを使い汚染防止を直接検証
- AC1/AC2 の `$own` shell-expansion リスクは Spec Notes で予防済み、verify-executor が固定文字列マッチで処理するため実害なし

#### verify
- Pre-merge AC 7 件すべて PASS。`file_contains`/`file_not_contains` の対称的な「旧削除 + 新追加」確認が正常に機能
- AC7 (CI github_check) は HEAD commit に対する CI 完了を 2 分弱待機して PASS 判定。patch route での `gh run list` 形式が想定通り機能
- Post-merge observation AC は SKIPPED (event=auto-run 待ち) — 同等内容を bats test 7 で synthetic data 検証済みのため実装の正当性は確認済み

### Improvement Proposals
- N/A (バグ修正は計画通り完了、横展開可能な一般化改善は未確定)

## Issue Retrospective

### Acceptance Criteria の変更

今回の refinement で以下の verify command を追加しました。

**追加 1 — 旧パターン削除確認 (file_not_contains × 2)**

`verify-patterns.md §8` の policy change Issues 原則に基づき、旧 `$ev[]` スコープのパターンが削除されたことを確認する `file_not_contains` を追加しました。

- `file_not_contains "scripts/auto-events-rollup.sh" ".event == \"phase_complete\" and .issue == $iss"` — Phases 行の旧パターン削除確認
- `file_not_contains "scripts/auto-events-rollup.sh" ".event == \"recovery\" and .issue == $iss"` — Recoveries 行の旧パターン削除確認

なお、`.issue == $iss` を含む文字列は Sessions ジャンルの line 148/149 にのみ存在し、Phase Distribution セクション (line 163) には存在しないことを確認済み (false positive なし)。

**追加 2 — CI 確認 (github_check)**

Size S は patch route のため `gh pr checks` 形式は使用不可。`verify-classifier.md` の patch route 規定に従い `gh run list --workflow=test.yml` 形式の `github_check` を追加しました。

### 曖昧点

要件自体の曖昧点はなし。`verify-type: observation event=auto-run` は `verify-classifier.md` の定義済み valid 値であることを確認。
