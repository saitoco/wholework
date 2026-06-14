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
