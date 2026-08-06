# Issue #1098: auto: Tier 2/3 recovery の発火・永続記録の欠落を解消し Metrics に反映する

## Overview

`run-auto-sub.sh` の `run_phase_with_recovery()` が呼び出す Tier 2 (`apply-fallback.sh`) / Tier 3 (`spawn-recovery-subagent.sh`) recovery について、次の2種類の「発火したが記録されない」ギャップを解消する。

1. `recovery` event の emit が成功パス (`result=recovered`) にのみ存在し、失敗パス (`action=abort` を含む) では一切記録されないため、`get-auto-session-report.sh` の Metrics (`Tier 1/2/3 recoveries`) が実際の発火回数を過小評価する
2. Tier 2 recovery の成功パスは `.tmp/auto-events.jsonl` への event 記録こそあるが、`docs/reports/orchestration-recoveries.md` への永続記録経路が存在しない (Tier 3 には既に存在する)
3. 上記2点の是正に伴い、`skills/verify/SKILL.md` Step 12 の Retrospective skip 判定と、Tier 2 の記録経路を前提にした周辺ドキュメント (`skills/auto/SKILL.md` Step 4a、`modules/orchestration-fallbacks.md`) を新しい記録経路に整合させる

## Reproduction Steps

1. `/auto` (または `/auto --batch`) の実行中に Tier 3 recovery が発火し、`action=abort` (pre-merge AC gate によるブロックなど、Tier 3 では解決できない正当な失敗) で終了するケースを発生させる
2. `spawn-recovery-subagent.sh` のログには `[spawn-recovery] action=abort: tier3 cannot recover this failure` が出力されるが、`.tmp/auto-events.jsonl` に `event: "recovery"` は1件も記録されない (実測: session `56516-1785934632`、Tier 3 は3回発火したが `event` 記録は成功した1回のみ)
3. 同様に、Tier 2 recovery (`json-mode-silent-hang` 等の symptom anchor) が成功発火しても、`.tmp/auto-events.jsonl` への `result=recovered` event 記録は行われる一方、`docs/reports/orchestration-recoveries.md` には記録が追記されない (実測: #1185 の code phase)

## Root Cause

- `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` は、Tier 1/2/3 それぞれの「成功」判定 (`if` の真の枝) でのみ `emit_event "recovery" ... result=recovered` を呼んでいる。Tier 3 の `if "$SCRIPT_DIR/spawn-recovery-subagent.sh" ...; then ... fi` が偽になるケース (`action=abort` 含む) は素通りして末尾の `return $exit_code` に到達するため、失敗した発火が一切記録されない。Tier 2 も `apply-fallback.sh` が非ゼロ終了した場合は同様に無記録
- `scripts/apply-fallback.sh` は Tier 2 recovery handler の実行結果を stdout に Markdown として出力するのみで、`docs/reports/orchestration-recoveries.md` へ書き込む経路を持たない。Tier 3 の `spawn-recovery-subagent.sh` は `write_recovery_entry()` で永続記録するが、Tier 2 に相当する関数が存在しない (#1181 で Spec 側の書き込みが削除された際、代替の記録経路が追加されなかった)
- `skills/verify/SKILL.md` Step 12、`skills/auto/SKILL.md` Step 4a、`modules/orchestration-fallbacks.md` の3ファイルはいずれも、上記の実装ギャップ (Tier 2 に bash 側の永続記録経路が無い) を前提にした記述になっている。特に `modules/orchestration-fallbacks.md` の `### Tier 2 bash path: recoveries.md-only recording` という見出しは、実際には bash path が存在せず `/auto` 親セッションの Step 4a Source 1 (LLM 駆動) が唯一の記録経路であることを自ら説明しており、見出しと本文が矛盾している

## Changed Files

- `scripts/apply-fallback.sh`: symptom anchor 一致後にハンドラが失敗した場合の終了コードを `exit 2` (anchor matched but failed) に区別し、anchor 不一致の `exit 1` と分離する。成功時に `docs/reports/orchestration-recoveries.md` へ記録する `write_recovery_entry()` を追加
- `scripts/run-auto-sub.sh`: Tier 2 ブロックで `_fallback_exit -eq 2` を判定して `recovery tier=2 result=failed` を emit。Tier 3 ブロックに `else` 節を追加し `recovery tier=3 result=failed` を emit。Tier 2 成功時に Tier 3 と同型の git add/commit/push ブロックを追加
- `scripts/get-auto-session-report.sh`: recovery Metrics 集計を、発火ベース (成功のみでなく) の集計であることを確認したうえで、tier 別の recovered/failed 内訳を追加
- `tests/apply-fallback.bats`: 新しい終了コード (`exit 2`) の assertion を追加
- `tests/run-auto-sub.bats`: Tier 2/3 失敗パスの `result=failed` emit assertion を追加
- `tests/get-auto-session-report.bats`: `result: failed` を含む fixture と、発火ベース集計・成功率内訳の assertion を追加
- `modules/orchestration-fallbacks.md`: `### Tier 2 bash path: recoveries.md-only recording` セクションを、実際の bash path 実装に合わせて書き換える (Tier 3 の同型セクションと揃える)
- `skills/auto/SKILL.md`: Step 4a の「Source 1 note」を更新し、Tier 2 が bash 側で記録されるようになったことで LLM 側の重複記録を避ける
- `skills/verify/SKILL.md`: Step 12 の skip 判定にある記録関数の説明(括弧書き)を更新し、新しい Tier 2 writer を含める
- `docs/structure.md`: `apply-fallback.sh` の説明に、欠落していた `json-mode-silent-hang` ハンドラを追加し、永続記録の書き込みに言及する
- `docs/ja/structure.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` 準拠)

## Implementation Steps

1. Tier 2/3 recovery の失敗パスで `recovery` event を emit する (→ acceptance criteria 1)
   - `scripts/apply-fallback.sh`: case dispatch の3ハンドラ (`dco-signoff-missing-autofix`, `code-patch-silent-no-op`, `json-mode-silent-hang`) すべてで、ハンドラ関数の終了コードを明示的にチェックする形へ統一する (現状 `code-patch-silent-no-op` のみ `if ... ; then ... ; else exit 1; fi` の形をとっており、残り2つはハンドラの終了コードを見ずに `set -e` に委ねている)。ハンドラが失敗した場合は `exit 2` (anchor matched but failed) とし、default 枝 (`*)`) の `exit 1` (no anchor matched) と区別する
   - `scripts/run-auto-sub.sh` の `run_phase_with_recovery()`: Tier 2 ブロックで `_fallback_exit` の値を判定し、`2` の場合は `emit_event "recovery" "phase=${phase}" "tier=2" "result=failed"` を実行してから Tier 3 へフォールスルーする (`0`=recovered は現状維持、`1` (anchor 不一致) は無 emit のまま Tier 3 へ)。Tier 3 ブロックの `if "$SCRIPT_DIR/spawn-recovery-subagent.sh" ...; then ... fi` に `else` 節を追加し、`.tmp/recovery-plan-${issue}-${phase}.json` が残っていればその `action` フィールドを読み取り (無ければ `unknown`)、`emit_event "recovery" "phase=${phase}" "tier=3" "result=failed" "action=${_action}"` を実行してから `return $exit_code` する。Tier 3 は Tier 1/2 が両方失敗した後にのみ到達するため、この `else` 節は `action=abort` に限らず、不正な recovery plan・`claude -p` 自体の失敗・未知の action など、呼び出しに到達した場合の失敗を一律にカバーする
   - `tests/apply-fallback.bats`: 「anchor matched but handler failed」ケース (既存の `code-patch-silent-no-op: retry itself returns silent no-op` テストなど) が `exit 2` になることを assert する行を追加。既存の `-ne 0` / `-eq 1` (no-anchor) assertion は変更しない
   - `tests/run-auto-sub.bats`: 既存の `all tiers fail: propagate original exit code` テスト (またはその近傍に追加する新規テスト) で `tier=3 result=failed` の emit を assert する。Tier 2 `_fallback_exit=2` → `result=failed` の新規テストも追加する

2. `get-auto-session-report.sh` の Metrics を発火ベース + 成功率表示に更新する (→ acceptance criteria 2, 3) (after 1)
   - `RECOVERY_COUNTS` (`.event == "recovery"` を tier 別に数える既存 jq) は `result` によるフィルタを持たないため、Step 1 で `result=failed` event が増えても base count は自動的に発火ベースの集計になることを確認する
   - `RECOVERY_COUNTS` (または隣接する新変数) を拡張し、tier 別の `recovered`/`failed` 内訳 (成功率) も出力するよう変更する。`RECOVERY_EVENTS` (個別イベント一覧セクション) は既に `result=` を表示しているため変更不要
   - `tests/get-auto-session-report.bats`: `result: "recovered"` と `result: "failed"` が混在する fixture を追加し、Metrics の「Tier 1/2/3 recoveries」が発火数を反映すること、成功率内訳が表示されることを assert する。既存テスト (Tier 2 candidate surfacing 等) が壊れないことを確認する

3. Tier 2 recovery の成功パスを `docs/reports/orchestration-recoveries.md` に永続記録する (→ acceptance criteria 4) (after 1)
   - `scripts/apply-fallback.sh`: `spawn-recovery-subagent.sh` の `write_recovery_entry()` と同型の関数を追加する (H2 見出し `## {timestamp}: {phase}-tier2-recovery`、`### Context` に `Source: fallback-catalog` を含む)。3つのハンドラそれぞれの成功枝から呼び出す
   - `scripts/run-auto-sub.sh`: Tier 2 成功ブロック (`_fallback_exit -eq 0`) に、Tier 3 成功ブロック (同ファイル内、`docs/reports/orchestration-recoveries.md` の `git diff --quiet` 判定 → `git add`/`git commit -s`/`_push_with_retry`) と同型のブロックを追加する。コミットメッセージは Tier 2 向けに変更する (例: `Record Tier 2 recovery event for issue #${EMIT_ISSUE_NUMBER} ${phase} phase`)
   - `modules/orchestration-fallbacks.md`: `### Tier 2 bash path: recoveries.md-only recording` セクションを、`### Tier 3 bash path: recoveries.md-only recording` と同じ構造 (bash path が直接 `orchestration-recoveries.md` に書き込み、`run_phase_with_recovery()` がコミット・プッシュする) に書き換える
   - `skills/auto/SKILL.md` Step 4a の「Source 1 note」: 「Tier 2 has no bash-path write of its own, so this Source 1 append is the only recording path for it」という記述を、Tier 2 も bash path で記録されるようになった旨、および Source 1 の LLM 側追記が重複記録にならないよう省略すべき旨に更新する (Tier 3 について同じ note が既に持つ除外ロジックと同型)
   - `docs/structure.md` / `docs/ja/structure.md`: `apply-fallback.sh` の説明(ハンドラ一覧)に欠落している `json-mode-silent-hang` を追加し、永続記録の書き込みに言及する

4. `skills/verify/SKILL.md` Step 12 の skip 判定を Tier 2 の記録先変更に整合させる (→ acceptance criteria 5) (after 3)
   - Step 12 の「Tier 2/3/Manual automatic recovery handling」にある `(the canonical entry format written by _write_manual_recovery_to_recoveries_log() / write_recovery_entry() / Step 4a)` という記述を、Tier 3 の `write_recovery_entry()` (in `spawn-recovery-subagent.sh`) と Tier 2 の新しい writer (in `apply-fallback.sh`、Step 3 で追加) の両方を明示する形に更新する
   - skip 判定の本文 (「Tier 2, Tier 3, and Manual recovery are recorded in `docs/reports/orchestration-recoveries.md`」) 自体は Step 3 の実装後に正しい記述となるため、内容面の変更は括弧内の関数一覧の明確化にとどめる

## Verification

### Pre-merge

- <!-- verify: rubric "Tier 2 / Tier 3 recovery の発火時点で recovery event が emit される実装になっている。recovery が失敗した場合 (action=abort を含む) でも発火が記録されることが確認できる" --> recovery event が発火時点で emit される
- <!-- verify: rubric "scripts/get-auto-session-report.sh の Metrics 集計が、recovery の発火回数を集計する形になっている (成功のみを数える形ではない)" --> Metrics が発火回数を集計する
- <!-- verify: command "bats tests/get-auto-session-report.bats" --> `tests/get-auto-session-report.bats` が PASS する
- <!-- verify: rubric "Tier 2 recovery の成功パスが docs/reports/orchestration-recoveries.md に永続記録される経路が実装されている (Tier 3 の既存経路と同型の git add/commit/push を伴う)" --> Tier 2 recovery が `orchestration-recoveries.md` に記録される
- <!-- verify: rubric "skills/verify/SKILL.md の Step 12 (Retrospective) における Auto Retrospective skip 判定が、Tier 2 recovery の記録先変更後も正しく機能する内容になっている。具体的には、記録済みの Tier 2 recovery を skip 判定に正しく含められる記述になっている" --> `skills/verify/SKILL.md` Step 12 が Tier 2 の記録先変更に整合している

### Post-merge

- Tier 3 recovery が発火し、かつ retry 側が失敗するケースを再現し、`.tmp/auto-events.jsonl` に recovery event が記録され Metrics の「Tier 1/2/3 recoveries」に反映されることを確認する <!-- verify-type: manual -->
- Tier 2 recovery が発火するケースを再現し、`docs/reports/orchestration-recoveries.md` に記録が追記されることを確認する <!-- verify-type: manual -->

## Notes

- Issue 本文 AC5 の verify command は `rubric` のみで構成されており、`section_contains "skills/verify/SKILL.md" "### Step 12" ...` のような補助チェックは含まれていない。2026-08-06 の issue retrospective コメントには「Step 12 整合 AC に `section_contains` を補助チェックとして追加」という決定が記録されているが、実際の Issue 本文には反映されていない (齟齬)。Verify command sync rule (Issue 本文を verbatim にコピーする) に従い、本 Spec は Issue 本文の現状のコマンドをそのまま採用した
- Tier 2 の失敗パス判定は `apply-fallback.sh` の終了コードを `1` (no anchor matched, 非発火) と `2` (anchor matched but handler failed, 発火して失敗) に分離することで実現する。既存の `tests/apply-fallback.bats` は `-eq 0` (成功) または `-ne 0` (失敗全般) のみを assert しており、`-eq 1` を厳密に assert しているのは「unknown symptom returns 1」テストの1件のみ (no-anchor ケース、本変更でも exit 1 のまま) — 本変更は既存テストと非互換にならない
- Tier 3 の失敗パス emit は `action=abort` に限定せず、Tier 3 呼び出し (`spawn-recovery-subagent.sh`) が到達した後のあらゆる非ゼロ終了 (不正な recovery plan、`claude -p` 自体の失敗、未知の action 等含む) を一律カバーする設計とした。Issue 本文は `action=abort` を主な実例として挙げているが、AC1 のルーブリック文言自体は「recovery が失敗した場合 (action=abort を含む)」であり、abort に限定する記述ではないため、Tier 3 到達後の全失敗パスを一律に扱う設計がより Issue の意図に忠実と判断した
- `modules/orchestration-fallbacks.md` の `### Tier 2 bash path: recoveries.md-only recording` という既存の見出しは、実装時点では bash path が存在しないにもかかわらず名付けられており、本文でその矛盾を自認する記述になっていた。本 Issue の実装によりこの見出しが実態と一致する

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 2026-08-06 の issue retrospective コメント (`/issue` フェーズでの Background 拡張・AC 拡張・タイトル更新の記録)。内容は既に Issue 本文に統合済みのため、本 Spec への追加のアクションなし / https://github.com/saitoco/wholework/issues/1098#issuecomment-5200911003
