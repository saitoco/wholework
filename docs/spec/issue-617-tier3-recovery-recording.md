# Issue #617: auto: Tier 3 recovery sub-agent 起動を orchestration-recoveries.md に記録

## Overview

`/auto` の 3-Tier リカバリ階層で Tier 3 recovery sub-agent が起動し成功した際、現在は wrapper log にしか記録されず `docs/reports/orchestration-recoveries.md` の監査トレイルループが閉じていない。2026-06-14 のバッチ実行で初めて Tier 3 が起動した（#554 code フェーズ、`action=recover`、成功）が、その記録は `.tmp/wrapper-*.log` にしか残らなかった。

本 Issue では以下を実装する:
- `skills/auto/SKILL.md` Step 4a Source 2 を "Available" に更新し、単一 Issue 親セッション Tier 3 起動後の記録ロジックを追加
- `scripts/spawn-recovery-subagent.sh` に `write_recovery_entry()` 関数を追加し、成功時に `docs/reports/orchestration-recoveries.md` へエントリを prepend
- `docs/reports/orchestration-recoveries.md` の Sources テーブルも対応更新
- 新規 `tests/auto-recovery.bats` でリカバリ記録の挙動をテスト

## Changed Files

- `skills/auto/SKILL.md`: Step 4a の Source 2 行の Dependency を `#316 ship 後に有効 (skip this source until #316 ships)` → `Available` に変更; Step 4a に Source 2 処理ロジック追加; Step 6 Tier 3 成功後に `TIER3_RECOVERY_*` 状態を retain する手順を追加
- `scripts/spawn-recovery-subagent.sh`: `write_recovery_entry()` 関数追加; `case` 文の retry/skip/recover 成功後に呼び出し — bash 3.2+ compatible
- `docs/reports/orchestration-recoveries.md`: Sources テーブルの `recovery-sub-agent` 行を "Dependent on #316 shipping" → "Available (#617 shipped)" に変更
- `tests/auto-recovery.bats`: 新規ファイル — `spawn-recovery-subagent.sh` のリカバリ記録動作をテスト
- `docs/structure.md`: tests/ ディレクトリのファイル数カウント 65 → 66; `spawn-recovery-subagent.sh` の説明をリカバリ記録に言及するよう更新
- `docs/ja/structure.md`: 上記の日本語 mirror 同期（テスト数 `65 ファイル` → `66 ファイル`; spawn-recovery-subagent.sh 説明更新）

## Implementation Steps

1. **`skills/auto/SKILL.md` Step 4a Source 2 テーブル更新** (→ AC1, AC2): Source 2 行の Dependency セルを `Available` に変更。併せて Step 4a に Source 2 の処理条件を追記: 「`TIER3_RECOVERY_PHASE` が設定されている場合（単一 Issue 親セッションが Step 6 Tier 3 を Task 経由で実行し成功した場合）、retained 状態から `docs/reports/orchestration-recoveries.md` にエントリを prepend する。バッチ/XL ルートでは `spawn-recovery-subagent.sh` が直接書き込むため、Source 2 は単一 Issue 親セッション分のみを対象とする」

2. **`skills/auto/SKILL.md` Step 6 Tier 3 retain 追加**: "Act on recovery plan" (step 5) の成功後（`abort` 以外）に `TIER3_RECOVERY_PHASE / _ACTION / _RATIONALE / _STEPS_COUNT / _EXIT_CODE / _LOG_TAIL` を LLM コンテキスト変数として retain する手順を追記 (after 1)

3. **`scripts/spawn-recovery-subagent.sh` への `write_recovery_entry()` 追加**: 既存の `# --- Action dispatch ---` セクションの前に関数を定義する。関数は: (a) `docs/reports/orchestration-recoveries.md` が存在する場合のみ動作、(b) `$PLAN_FILE` から rationale/steps を Python3 で読み取る、(c) `date -u '+%Y-%m-%d %H:%M UTC'` で UTC タイムスタンプを生成、(d) エントリを `<!-- Log entries appear below, newest first. -->` マーカー直後に prepend する。`case` 文で retry/skip/recover 成功後に `write_recovery_entry "$ACTION" "success"` を呼び出す; abort は呼ばない。bash 3.2+ 互換（`local`, heredoc, python3） (after 1)

4. **`docs/reports/orchestration-recoveries.md` Sources テーブル更新**: `recovery-sub-agent` 行の Dependency を "Available (#617 shipped)" に変更 (parallel with 3)

5. **`tests/auto-recovery.bats` 新規作成 + `docs/structure.md` / `docs/ja/structure.md` 更新** (after 3): 以下の 5 テストケースを含む bats ファイルを作成。setup では `spawn-recovery-subagent.bats` と同等のモック + `$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md` フィクスチャを用意。`docs/structure.md` と `docs/ja/structure.md` のテスト数を 66 に更新し、spawn-recovery-subagent.sh の説明にリカバリ記録に関する記述を追加 (→ AC3)

## Verification

### Pre-merge

- <!-- verify: grep "recovery-sub-agent.*Available" "skills/auto/SKILL.md" --> Step 4a の表で Source 2 が Available と記載されている（Source 2 行に "Available" が含まれる）
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "#316 ship 後に有効" --> 旧文言「#316 ship 後に有効」が削除されている
- <!-- verify: command "bats tests/auto-recovery.bats" --> リカバリ記録の bats テストが green（recovery-sub-agent ソースの新規ケース含む）

### Post-merge

- 次回 Tier 3 起動時、`orchestration-recoveries.md` に `Source: recovery-sub-agent` のエントリが自動追加されることを観察

## Notes

### Tier 3 起動経路と記録箇所の対応

Tier 3 リカバリには 2 つの呼び出し経路がある:

| 経路 | 呼び出し元 | 記録箇所 |
|------|-----------|---------|
| 単一 Issue `/auto N` (M/L/patch) | 親 LLM セッション Step 6 (Task tool) | SKILL.md Step 4a Source 2 |
| バッチ/XL sub-issue | `run-auto-sub.sh` → `spawn-recovery-subagent.sh` | スクリプト内 `write_recovery_entry()` |

生産時の Tier 3 起動（#554）は後者（`run-auto-sub.sh` 経由）だったため、`spawn-recovery-subagent.sh` への `write_recovery_entry()` 追加が主要な修正となる。

### `write_recovery_entry()` エントリフォーマット

```markdown
## YYYY-MM-DD HH:MM UTC: <phase>-tier3-recovery

### Context
- Issue #N, phase: <phase>
- Source: recovery-sub-agent
- Wrapper: run-<phase>.sh, exit code: <N>
- Log tail: "<last relevant log line>"

### Diagnosis
- <rationale from sub-agent plan>

### Recovery Applied
- action=<retry|skip|recover>
- steps: <N step(s)|none>

### Outcome
- success

### Improvement Candidate
- 未起票
```

### bats テスト入力データフォーマット

`tests/auto-recovery.bats` のモック claude が返す plan JSON:
```json
{"action":"skip","rationale":"phase already completed","steps":[]}
```

`docs/reports/orchestration-recoveries.md` フィクスチャ（最小構成）:
```markdown
---
type: report
---

# Orchestration Recovery Log

<!-- Log entries appear below, newest first. -->
```

### XL ルートにおける並行書き込みリスク

XL ルートで複数 sub-issue が同時に Tier 3 を起動した場合、`docs/reports/orchestration-recoveries.md` への同時書き込みが発生する可能性がある。Python の `open(..., 'w')` はアトミックではないため、エントリが重複または欠落するリスクがある。ただし XL ルートでの Tier 3 同時起動は `WHOLEWORK_MAX_RECOVERY_SUBAGENTS`（デフォルト 1）により事実上シリアル化されているため、実用上のリスクは低い。本実装では対処しない（follow-up issue で必要に応じて対応）。

### `#316` について

Issue の背景に出てくる `#316` は、当初 Source 2 のブロッカーとして言及されていたが、`spawn-recovery-subagent.sh`（`#589` で実装）が #316 相当の機能を既に提供しているため、この Issue で Source 2 を有効化できる。

## issue retrospective

### 曖昧ポイント解決（Auto-Resolve Log）

非インタラクティブモードで以下の3点を自動解決した:

| 曖昧ポイント | 採用 | 根拠 |
|------------|------|------|
| 記録トリガー条件（成功のみ vs 成功・失敗問わず） | **成功時のみ** | 既存 SKILL.md Source 2 行の定義「successful recovery plan during Tier 3 recovery」に整合。失敗時記録は監査ノイズになりうる |
| エントリ日時フォーマット（JST vs UTC） | **UTC** | 既存 SKILL.md の Entry format（`## YYYY-MM-DD HH:MM UTC`）が UTC を採用。一貫性を維持 |
| tests/auto-recovery.bats（新規作成 vs 既存ファイル追記） | **新規作成** | AC が `tests/auto-recovery.bats` を明示的に指定。既存の `spawn-recovery-subagent.bats` は subagent 起動動作をテストする別概念 |

### Verify Command 修正（AC audit 結果対応）

Triage AC audit で2件の問題を検出し、Issue body 更新時に修正した:

1. **Pattern 2 (常時PASS)**: `grep "recovery-sub-agent" "skills/auto/SKILL.md"` は文字列が既存（line 374, 384）なので常時PASS → `grep "recovery-sub-agent.*Available"` に修正
2. **引数不足**: `section_not_contains "skills/auto/SKILL.md" "#316 ship 後に有効"` は引数が2つ（3つ必要） → `file_not_contains "skills/auto/SKILL.md" "#316 ship 後に有効"` に修正

### Policy Decision

- Post-merge 条件は `verify-type: observation event=auto-run` で維持。次回 `/auto` 実行時に Tier 3 が起動するかは不確定だが、event 型 observation が最も適切
- Size M 確定（bats テスト新規追加 → CI minimum override により M に到達）

## spec retrospective

### Minor observations

- `spawn-recovery-subagent.sh` への `write_recovery_entry()` 追加は、生産 Tier 3 発生事例（#554）がバッチ経由（`run-auto-sub.sh` → shell script）だったため、shell script 側が主要実装。SKILL.md Step 4a Source 2 は単一 Issue 親セッション分のみカバーする非対称構造が明確になった
- XL ルートでの並行書き込みリスクを Notes に記録したが、`WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` により事実上シリアル化されているため許容範囲と判断

### Judgment rationale

- `spawn-recovery-subagent.sh` での直接書き込み vs SKILL.md Step 4a 経由の2経路を分離した。重複を防ぐため、バッチ/XL はスクリプト直書き込み、単一 Issue 親セッションは Step 4a が担当する設計とした
- `write_recovery_entry()` 関数は bash 3.2+ 互換を維持するため Python3 を使用。日本語文字列（未起票）はスクリプトに直書きするのではなく Python 内で扱う形とした

### Uncertainty resolution

- `#316` への依存は `spawn-recovery-subagent.sh`（#589 実装済み）が代替していることが調査で確認でき、ブロッカーなしで Source 2 を有効化できると確認

## Phase Handoff
<!-- phase: spec -->

### Key Decisions

- `write_recovery_entry()` は `spawn-recovery-subagent.sh` 内に定義し、成功アクション（retry/skip/recover）の直後に呼び出す。`docs/reports/orchestration-recoveries.md` が存在しない場合はスキップ（graceful degradation）
- SKILL.md Step 4a Source 2 は「単一 Issue 親セッションが Step 6 Tier 3 を Task tool 経由で実行した場合のみ」と限定し、バッチ/XL との重複を防ぐ
- `tests/auto-recovery.bats` は新規作成（`spawn-recovery-subagent.bats` への追記ではなく）。テスト対象（記録動作）とテスト名（auto-recovery）の意味的対応が明確

### Deferred Items

- XL ルートでの並行 `write_recovery_entry()` による競合書き込みへの対処（`WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` で当面許容）
- `action=retry` 失敗時（re-run が exit non-zero になる場合）の部分記録（`outcome=partial`）は未実装。現在は成功のみ記録

### Notes for Next Phase

- `write_recovery_entry()` は `set -euo pipefail` 環境下で動作するため、Python3 呼び出し失敗時にスクリプト全体が abort するリスクがある。必要なら `|| true` でラップするか検討
- `docs/structure.md` と `docs/ja/structure.md` のテスト数更新（65 → 66）を忘れずに行う
- `spawn-recovery-subagent.sh` の case 文では `skip` が `exit 0` で抜けるため、`write_recovery_entry` は `exit 0` の直前に呼び出す必要がある（後に記述すると実行されない）
