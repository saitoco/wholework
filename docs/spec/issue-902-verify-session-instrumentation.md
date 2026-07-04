# Issue #902: verify: /verify セッション計装追加 (phase_start/phase_complete + AskUserQuestion回数) — #877 再測定の代理指標限界を解消

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — 曖昧ポイント 3 件の自動解決ログ、AC1 への `file_contains` 補助追加、Post-merge AC の verify-type を opportunistic に修正、#898/#899 重複申し送り (現状維持) / https://github.com/saitoco/wholework/issues/902#issuecomment-4883879006

## Overview

`/verify` skill の実行に `phase_start`/`phase_complete` (phase=verify) イベント発火と、interactive mode での `AskUserQuestion` 呼び出し回数を記録する `verify_user_confirm` イベント発火を追加する。目的は、#877 (`docs/reports/verify-sonnet-5-remeasurement.md`) で NO-GO 判定の根拠となった「`/verify` 実行時の実際の摩擦を直接計測する手段がない」という計装ギャップを解消し、将来の再測定 (Sonnet バージョン比較や設計変更の効果測定) が GitHub アーティファクトの代理指標ではなく実測値に基づいて行えるようにすることである。

`skills/verify/SKILL.md` には既に `AUTO_EVENTS_LOG` 条件付きの `emit_event` 呼び出し (`verify_fail_marker_posted`、`verify_retry_fire`、`recoveries_threshold_fire`) が存在するが、`phase_start`/`phase_complete` は未実装であることをコードベース調査で確認した (該当パターンが存在しない)。この事実は Issue #900 (クローズ済み) の調査結果とも一致する — 同 Issue は `/verify` が `phase==verify` イベントを一切 emit しないことを実データで確認し、`audit/auto-session` の Verify Phase Residuals 検出をライブラベル参照方式に切り替えた。

## Changed Files

- `skills/verify/SKILL.md`: Step 1 に `phase_start` 発火、Step 11 の全終端分岐に `phase_complete` 発火、Step 8b に `verify_user_confirm` 発火を追加
- `scripts/emit-event.sh`: コメントブロックに `verify_user_confirm` イベントスキーマのドキュメントを追加 (bash 3.2+ 互換、ロジック変更なし)
- `modules/event-emission.md`: `skills/verify/SKILL.md` がラッパーを介さずインラインで `phase_start`/`phase_complete` (phase=verify) を発火する旨の注記を追加 [Steering Docs sync candidate]
- `tests/emit-event.bats`: `phase=verify` の `phase_start`/`phase_complete` と `verify_user_confirm` イベント形状を検証する bats テストを追加

## Implementation Steps

1. `skills/verify/SKILL.md` Step 1 (phase banner 表示の直後) に `phase_start` 発火を追加する。既存の `verify_fail_marker_posted` と同じ `AUTO_EVENTS_LOG` ゲート条件を踏襲する:
   ```bash
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
     source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
     EMIT_ISSUE_NUMBER=$NUMBER emit_event "phase_start" "phase=verify"
   fi
   ```
   (parallel with 2, 3) (→ acceptance criteria A)

2. `skills/verify/SKILL.md` Step 11 の全終端分岐 (5 箇所) に `phase_complete` 発火を追加する。内訳: (a) 全 PASS/SKIPPED 分岐の先頭 1 箇所、(b) FAIL 分岐の NEXT_ITERATION < VERIFY_MAX_ITERATIONS 側 1 箇所 (既存の `verify_fail_marker_posted` 発火箇所の近傍)、(b) FAIL 分岐の NEXT_ITERATION >= VERIFY_MAX_ITERATIONS 側 1 箇所 (MAX_ITERATIONS_REACHED、既存の `verify_fail_marker_posted` 発火箇所の近傍)、(c) PENDING 分岐 1 箇所、(d) UNCERTAIN 分岐 1 箇所。PASS 完了時だけでなく FAIL/PENDING/UNCERTAIN を含む全終端分岐で発火させる (Issue 本文の Autonomous Auto-Resolve Log 参照 — 「AC 判定に到達したこと」が完了シグナルであり、AC の FAIL 自体は skill 実行の失敗ではないため):
   ```bash
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
     source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
     EMIT_ISSUE_NUMBER=$NUMBER emit_event "phase_complete" "phase=verify"
   fi
   ```
   (parallel with 1, 3) (→ acceptance criteria A)

3. `skills/verify/SKILL.md` Step 8b の「2a. If executable: present per-condition AskUserQuestion」ブロックに、ユーザー回答受信直後の `verify_user_confirm` 発火を追加する。フィールドは条件のインデックス (`ac_index`) と選択された回答 (`response`: `Claude Execute` / `Manual Verification (Show Guide)` / `SKIP`) とする。Step 1 の dirty file 確認時の別の `AskUserQuestion` 呼び出し (Exit 2 分岐) はスコープ外とする (Issue 本文が「manual AC 確認」に限定して計測対象としているため):
   ```bash
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
     source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
     EMIT_ISSUE_NUMBER=$NUMBER emit_event "verify_user_confirm" \
       "ac_index=${N}" \
       "response=${RESPONSE}"
   fi
   ```
   (parallel with 1, 2) (→ acceptance criteria B)

4. `scripts/emit-event.sh` の「Documented event schemas」コメントブロックに `verify_user_confirm` のスキーマ説明 (`ac_index`、`response`) を既存エントリ (`verify_retry_fire` 等) と同じ書式で追加する。`modules/event-emission.md` の Wrapper Coverage Table 直後に「Non-Wrapper Emitters」小節を追加し、`skills/verify/SKILL.md` がラッパーを介さず `phase_start`/`phase_complete` (phase=verify) をインライン発火する旨と、`_EMIT_PHASE_OWNED` パターンを使わない理由 (対応する `run-verify.sh` が存在しないため) を記載する (after 1, 2, 3) (→ acceptance criteria A)

5. `tests/emit-event.bats` に以下 2 種のテストケースを追加する:
   - `phase=verify` を指定した `phase_start`/`phase_complete` イベントが正しい JSON 形状 (`event`/`phase`/`issue` フィールド) で書き込まれることを検証するテスト (既存の「emit_event writes a valid JSONL line to AUTO_EVENTS_LOG」テストと同様の構造)
   - `verify_user_confirm` イベントが `ac_index`/`response` フィールドを含む正しい JSON 形状で書き込まれることを検証するテスト
   (after 4) (→ acceptance criteria C)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/verify/SKILL.md または関連 script に、verify フェーズの phase_start/phase_complete イベント発火ロジックが追加されている" --> <!-- verify: file_contains "skills/verify/SKILL.md" "phase_start" --> <!-- verify: file_contains "skills/verify/SKILL.md" "phase_complete" --> `/verify` 実行開始時・終了時に `scripts/emit-event.sh` 経由で `phase_start`/`phase_complete` (phase=verify) イベントが `.tmp/auto-events.jsonl` に記録される
- <!-- verify: rubric "skills/verify/SKILL.md に AskUserQuestion 呼び出し回数を記録するイベント発火ロジックが追加されている" --> interactive mode で `AskUserQuestion` が呼び出されるたびに専用イベント (例: `verify_user_confirm`) が記録される
- <!-- verify: rubric "bats テストで新規イベント発火が検証されている" --> 追加した2種のイベント発火について bats テストが追加されている

### Post-merge
- 次回 `/verify` 実行時に `.tmp/auto-events.jsonl` へ `phase_start`/`phase_complete` (phase=verify) と `verify_user_confirm` (該当時) が実際に記録されることを確認 <!-- verify-type: opportunistic -->

## Notes

- **`/issue` フェーズの自動解決 (再掲・参照)**: 実装場所 (SKILL.md インライン)、`phase_complete` の全終端分岐発火、`AUTO_EVENTS_LOG` 単独ゲートの 3 点は `/issue` フェーズで既に自動解決済み (Issue 本文の `## Autonomous Auto-Resolve Log` 参照)。本 Spec はその決定を踏襲する。
- **Issue #900 との整合性確認**: `scripts/get-auto-session-report.sh` の Verify Phase Residuals 検出は Issue #900 でライブラベル参照方式 (`gh issue list --label phase/verify`) に切り替え済みであり、本 Issue が追加する `phase_start`/`phase_complete` (phase=verify) イベントには依存しない。したがって本実装は既存の集計ロジックに影響しない、純粋な追加のみの変更である。
- **フォローアップ候補 (本 Spec のスコープ外)**: `scripts/get-auto-session-report.sh` 内の Metrics 出力キャベア (「The verify phase does not emit phase_start/phase_complete events...」という一文) は、本 Issue 実装後は事実と異なる記述になる。同ファイルの `PHASE_ACTIVITY_TABLE`/`_phase_breakdown` 集計ロジック自体は `.phase` 値ベースの汎用実装のため、コード変更なしで `verify` フェーズも自動的に集計対象に含まれる。ただし当該キャベア文言の削除・更新は本 Issue の Acceptance Criteria に含まれないスコープ外の変更のため、別 Issue での対応を推奨する。
- **重複 Issue のクローズ状況**: #898・#899 は `/issue` フェーズで本 Issue (#902) を正 (canonical) として重複クローズ済み。#898 は実装未了で「#902 を正として実装を進める」と明記されている。本 Spec の設計に影響する重複実装は存在しない。

## review retrospective

### Spec vs. implementation divergence patterns

実装は Implementation Steps 1〜5 の内容と厳密に一致していた (発火箇所・イベント名・フィールド名・Step 11 の5終端分岐カバレッジすべて)。ただし Step 3 のコードスニペットに含まれていた `${N}`/`${RESPONSE}` という bash 変数代入前提の記法は、本 Spec 自身がそのまま実装へ転記した結果であり、コード化フェーズで新たに生じた乖離ではない。`skills/verify/SKILL.md` の既存慣例 (`{N}` のようなプレースホルダーは `$` なしで書く。実際の bash 変数を指す場合のみ `${NEXT_ITERATION}` のように `$` を使う) との不整合が Spec 作成時点から埋め込まれていたことになる。次回同種の Spec 作成時は、SKILL.md 内の既存コードスニペット記法 (代入済み変数か prose プレースホルダーか) を踏襲するよう明記するとよい。

### Recurring issues

なし。今回の2件の SHOULD 指摘 (記法不整合、`docs/structure.md` の記述漏れ) はいずれも単発の軽微な指摘であり、過去レビューで繰り返し出ているパターンとは異なる。

### Acceptance criteria verification difficulty

3件すべて rubric ベースで、うち1件は `file_contains` による補助検証も付与されていたため、判定に迷う UNCERTAIN は発生しなかった。Post-merge の1件は `verify-type: opportunistic` であり `/merge` 後の次回 `/verify` 実行で観測されるため、本レビューでの判定対象外として扱った。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merge を実行 (mergeable=true、conflict なし)。マージコミット `fdee8d3d`
- レビュー指摘対応の追加コミット `78fafc29` を含めてマージ完了

### Deferred Items
- `scripts/get-auto-session-report.sh` の Metrics 出力キャベア文言 (「The verify phase does not emit phase_start/phase_complete events...」) は本実装後は事実と異なる記述になるが、Spec の Notes 記載通りスコープ外として別 Issue 送りとする
- Post-merge AC (opportunistic): 次回 `/verify` 実行で `phase_start`/`phase_complete`/`verify_user_confirm` の実記録を観測する必要あり

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC を rubric + file_contains の多層構成にした設計は verify で機械的に検証でき良好。Size S は妥当
- spec がクローズ済み #900 の「/verify は実データ上 phase==verify イベントを emit していない」証拠を発見し Background 主張を裏付けた

#### design
- `/verify` は #485 で run-verify.sh が削除され wrapper を持たないため、skill 本体からインラインで emit する設計は正しい。`phase_complete` を Step 11 の全終端分岐で発火する判断も妥当

#### code
- **silent no-op アノマリ (手動リカバリ)**: code-pr フェーズが worktree branch `worktree-code+issue-902` に実装コミット `ae0d6165` を作成したが push / PR 作成に至らず終了。run-code.sh の auto-retry が 3/3 まで回ったが各回とも no-op (コミット済みを検知せず push+PR に進めなかった) だった。parent session が手動で push + PR #909 作成してリカバリ
- これは #906/#907 で対応中の `code-patch-silent-no-op` の **pr-route 変種**。run-auto-sub.sh が持つ `code_phase_milestone` (post-commit → push-and-pr) resume は、/auto pr route が直接呼ぶ standalone `run-code.sh --pr` 経路には効かないため取りこぼした
- 実装自体は fixup/amend なしで妥当

#### review
- review-light が SHOULD 2件 (`${N}`/`${RESPONSE}` 記法統一、docs/structure.md 更新) を検出・即修正。CI 全 SUCCESS。有効に機能した

#### merge
- conflict なし squash merge。ただし本実装により `get-auto-session-report.sh` の verify-phase caveat 文言が事実と drift する点を merge handoff が検出し deferred 化した

#### verify
- pre-merge 3件すべて file_contains/rubric/bats で PASS。post-merge (opportunistic) は本 verify 実行が計装反映前スキルで走ったため未計測 → phase/verify で opportunistic pending

### Improvement Proposals
- **code フェーズの AC 駆動 follow-up Issue 作成に重複チェックが無い**: #877 の code フェーズが AC4 (「follow-up Issue 作成」) を満たすため `gh issue create` で #902 を直接起票したが、既に同趣旨の #898/#899 が存在していた。code フェーズの follow-up 起票は retro-proposals の dedup パイプラインを通らず open Issue との照合が無いため、三重重複 (#898/#899/#902) を招いた。code フェーズの follow-up Issue 作成前に軽量な open-issue 重複チェック (retro-proposals の dedup ロジック共用) を挟むことを提案する (複数箇所で follow-up 起票が発生する構造的問題)
- **`get-auto-session-report.sh` の verify-phase caveat 文言 drift**: 本 Issue の計装追加により「The verify phase does not emit phase_start/phase_complete events...」という caveat が事実と異なる記述になった。`scripts/get-auto-session-report.sh` (および関連ドキュメント) の当該文言を、verify phase も phase_start/phase_complete を emit する前提に更新する必要がある (merge phase handoff で deferred 化済み)

### Notes for Next Phase
- `/verify` 実行時、Post-merge AC の opportunistic 観測 (`.tmp/auto-events.jsonl` への実イベント記録確認) を忘れずに行うこと
