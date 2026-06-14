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

## Code Retrospective

### Deviations from Design

- メインリポジトリ（`/Users/saito/src/wholework/`）に絶対パスで Edit ツールを呼び出してしまい、worktree ではなくメインリポジトリを編集した。`cp` でファイルをコピーし `git checkout --` でメインリポジトリを戻すことで対処した。worktree 内では CWD 相対パスを使うべきだったが、Spec の実装ステップには影響なし。

### Design Gaps/Ambiguities

- Phase Handoff の「`|| true` でラップするか検討」という注記に従い、`write_recovery_entry` の呼び出しを `|| true` でラップした。関数内の Python3 失敗がメインスクリプトを abort させないようにするため。
- `write_recovery_entry()` 内での Python3 呼び出し失敗は `|| return 0` でラップ済み（関数レベルのグレースフルデグラデーション）。

### Rework

- N/A（設計からの逸脱はファイルパス誤編集のみで、ロジック的なリワークなし）

## Code Retrospective (phase: code — preserved)

### Key Decisions

- `write_recovery_entry()` の呼び出しをすべて `|| true` でラップし、記録失敗がメインフロー（recovery action の成功）を abort させないよう実装した。
- Phase Handoff の「skip は exit 0 の直前に呼び出す」注記を遵守し、`write_recovery_entry "skip" || true` を `exit 0` の直前に配置した。
- メインリポジトリへの誤編集を `cp` + `git checkout --` で回復した（worktree 内での絶対パス使用は避けること）。

### Deferred Items

- XL ルートでの並行 `write_recovery_entry()` による競合書き込みは未対処（`WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` で当面許容）。
- `action=retry` 失敗時（re-run が exit non-zero になる場合）の部分記録（`outcome=partial`）は未実装。現在は成功のみ記録。

### Notes for Next Phase

- PR #622 で CI が green になることを確認。`bats tests/auto-recovery.bats` は 5/5 PASS 済み。
- 次回の Tier 3 起動を観察して post-merge AC を確認（観察型 AC）。
- `orchestration-recoveries.md` の Sources テーブルが `Available (#617 shipped)` に更新済みなので、monitoring 時は Source 列を確認する。

## review retrospective

### Spec vs. Implementation Divergence Patterns

- 乖離なし。Spec の実装ステップ全項目が PR diff で確認済み（write_recovery_entry 関数追加、Source 2 "Available" 更新、Step 5b retain 追加、bats 5ケース、docs 更新）。
- `write_recovery_entry()` のテスト設計が `WHOLEWORK_SCRIPT_DIR` 経由で script dir をモック化する巧妙な方式を採用しており、テストフィクスチャへの書き込みが正しく機能することを確認。

### Recurring Issues

- なし。review-light 4 視点すべてで問題未検出。
- Type=Feature の重点確認項目（Spec 乖離・エッジケース）も問題なし。

### Acceptance Criteria Verification Difficulty

- 3つの Pre-merge AC はすべて verify command で自動判定可能（grep/file_not_contains/command）。
- `command "bats tests/auto-recovery.bats"` は safe モードで CI 参照フォールバック経由で PASS 確認（"Run bats tests" SUCCESS）。
- Post-merge AC は observation 型で、次回 Tier 3 起動時に自動評価される設計。UNCERTAIN なし。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- 4 視点 lightweight review で MUST/SHOULD 問題なし → 修正なし・APPROVE 相当で `/merge` 進行可。
- CI 全ジョブ SUCCESS 確認済み（DCO, Run bats tests, Validate skill syntax, Forbidden Expressions check, macOS shell compatibility）。
- Pre-merge AC 3/3 PASS、Post-merge 1 件は observation 型で merge 後の観察待ち。

### Deferred Items

- Post-merge AC（次回 Tier 3 起動時の orchestration-recoveries.md エントリ自動追加）は観察待ち。

### Notes for Next Phase

- merge 後に `opportunistic-search.sh --event auto-run` が Tier 3 起動イベントを検出した際、observation AC を自動評価する。
- XL 並行書き込みリスクは `WHOLEWORK_MAX_RECOVERY_SUBAGENTS=1` で許容済み（follow-up issue 不要）。
