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
