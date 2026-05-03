# Issue #369: detect-wrapper-anomaly: LLM-reported-success-but-no-commit パターンを検出ルールに追加

## Overview

Issue #365 で発生した「LLM が実装完了を報告しながら実際にはコミットが発生しない silent no-op 異常」を早期検出できるよう、`scripts/detect-wrapper-anomaly.sh` に新しい検出パターン `silent-no-op` を追加する。検出条件は `exit_code=0` + ログに成功フレーズ + git log に対象 Issue のコミットなし。スコープは**検出ルールの追加のみ**（リカバリは別 Issue）。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `silent-no-op` 検出パターンを追加 — bash 3.2+ compatible
- `scripts/run-auto-sub.sh`: `run_phase_with_recovery` で exit_code=0 でも `detect-wrapper-anomaly.sh` を呼び出す — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: `silent-no-op` パターンのテストケースを追加

## Implementation Steps

1. **`scripts/detect-wrapper-anomaly.sh` に `silent-no-op` パターンを追加** (→ AC1, AC2)

   既存の if/elif チェーンの末尾 `fi` の直前（`watchdog-kill` ブロックの後）に以下の `elif` ブロックを挿入する:

   ```bash
   elif [[ "$EXIT_CODE" == "0" ]]; then
     if grep -qiE "完了しました|commit and push" "$LOG_FILE" && \
        ! git log --oneline -5 2>/dev/null | grep -q "#${ISSUE_NUMBER}"; then
       PATTERN_NAME="silent-no-op"
       ANOMALY_DESC="LLM reported success in phase \`$PHASE\` (exit code 0) but no commit for #$ISSUE_NUMBER found in recent git log. Possible silent no-op: output indicated completion but no code was committed. Reference: #365."
       IMPROVEMENT_HINT="Re-run \`run-code.sh $ISSUE_NUMBER\` to retry the code phase. If a second run also fails to produce a commit, escalate to manual implementation. See Issue #365 for a known case of this pattern."
     fi
   fi
   ```

   変更前（末尾）:
   ```bash
   elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then
     PATTERN_NAME="watchdog-kill"
     ...
   fi
   ```

   変更後（末尾）:
   ```bash
   elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then
     PATTERN_NAME="watchdog-kill"
     ...
   elif [[ "$EXIT_CODE" == "0" ]]; then
     if grep -qiE "完了しました|commit and push" "$LOG_FILE" && \
        ! git log --oneline -5 2>/dev/null | grep -q "#${ISSUE_NUMBER}"; then
       PATTERN_NAME="silent-no-op"
       ANOMALY_DESC="..."
       IMPROVEMENT_HINT="..."
     fi
   fi
   ```

2. **`scripts/run-auto-sub.sh` の `run_phase_with_recovery` を更新** (after 1) (→ AC3)

   `run_phase_with_recovery` 関数内の `[[ $exit_code -eq 0 ]] && return 0` を以下に置き換える:

   ```bash
   if [[ $exit_code -eq 0 ]]; then
     local anomaly_out
     anomaly_out=$("$SCRIPT_DIR/detect-wrapper-anomaly.sh" --log "$log_file" --exit-code 0 --issue "$issue" --phase "$phase" 2>/dev/null || true)
     if [[ -n "$anomaly_out" ]]; then
       echo "[anomaly] silent no-op detected in ${phase}:"
       echo "$anomaly_out"
     fi
     return 0
   fi
   ```

3. **`tests/detect-wrapper-anomaly.bats` にテストケースを追加** (after 1) (→ AC4)

   ファイル末尾に以下の 2 テストを追加する。

   **テスト a: silent no-op 検出成功ケース**
   - `@test "silent no-op: detects exit_code=0 with success phrase and no recent commit"`
   - `$BATS_TEST_TMPDIR/bin/git` に空出力の mock git スクリプトを作成し、`PATH="$BATS_TEST_TMPDIR/bin:$PATH"` で PATH に追加
   - `echo "実装が完了しました。commit and push も完了しています。" > "$LOG_FILE"` でログ作成
   - `run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 365 --phase code` で実行
   - アサーション: `[ "$status" -eq 0 ]`、`[[ "$output" == *"silent-no-op"* ]]`、`[[ "$output" == *"### Orchestration Anomalies"* ]]`

   **テスト b: 成功フレーズなし → 非検出ケース**
   - `@test "silent no-op: no detection when exit_code=0 but no success phrase"`
   - `echo "Execution finished normally." > "$LOG_FILE"` でログ作成（成功フレーズなし）
   - `run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 365 --phase code` で実行
   - アサーション: `[ "$status" -eq 0 ]`、`[ -z "$output" ]`

   mock git スクリプト内容（bash 3.2+ compatible）:
   ```bash
   #!/bin/bash
   # mock git: returns empty output for all subcommands
   exit 0
   ```

## Verification

### Pre-merge

- <!-- verify: grep "silent.no.op\|silent_no_op" "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` に `silent-no-op` パターン名のルールが追加されている
- <!-- verify: grep "git log" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` が内部で git log チェックを行い、exit_code=0 + コミットなしを検出する
- <!-- verify: rubric "skills/auto/SKILL.md, scripts/run-code.sh, or scripts/run-auto-sub.sh is updated to invoke detect-wrapper-anomaly.sh even when exit_code=0, enabling silent no-op detection" --> exit_code=0 のケースでも `detect-wrapper-anomaly.sh` が呼び出される（呼び出し側の更新）
- <!-- verify: grep "silent.no.op\|silent_no_op\|no.commit" "tests/detect-wrapper-anomaly.bats" --> `tests/detect-wrapper-anomaly.bats` に silent no-op パターンのテストケースが追加されている

### Post-merge

- silent no-op シナリオ（exit 0 + コミットなし + 成功フレーズ出力）を再現し、anomaly として検出されることを確認 <!-- verify-type: manual -->

## Tool Dependencies

none

## Uncertainty

none

## Notes

- `detect-wrapper-anomaly.sh` の既存パターンは全て非ゼロ exit を暗黙的に前提としている（trigger 文字列がゼロ exit シナリオには出現しない）。`silent-no-op` は唯一 `EXIT_CODE==0` を明示的に確認するパターン。
- bats テストでの git mock: `$BATS_TEST_TMPDIR/bin/git` に空出力スクリプトを配置し、`env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT"` 形式で実行することで、`git log --oneline -5 | grep -q "#365"` が "no match"（exit 1）を返し silent-no-op 条件を満たす。
- 成功フレーズパターン `"完了しました|commit and push"` は Issue #365 の実際の出力に基づく（"Direct commit and push to main が完了しました"）。
- `run-auto-sub.sh` の更新は bash path をカバーする。LLM path（`skills/auto/SKILL.md` 直接実行）での exit_code=0 検出は今回スコープ外（SKILL.md の patch-route completion check 無条件化は Issue #365 Improvement Proposals 参照）。
- bats テスト入力データ: `echo "..." > "$LOG_FILE"` で 1 行テキストを書き込む。スクリプトは `grep -qiE` でパターンマッチするため、ログ内容は 1 行で十分。

## issue retrospective

### 曖昧ポイントの自動解決

非対話モードで以下の 3 つの曖昧ポイントを自動解決した。

#### 1. リカバリスコープ（auto-resolved）

- **決定**: スコープは検出ルール追加のみ。Purpose の「run-code.sh 再実行 → エスカレーション」は `apply-fallback.sh` への follow-up として別 Issue で扱う
- **根拠**: AC が Detection のみを記述しており、リカバリ実装は AC に明示されていない。最少リスクオプションとして Detection スコープに確定
- **他の候補**: `apply-fallback.sh` に silent-no-op ハンドラーを追加してリカバリまで含める → スコープ過大と判断し不採用

#### 2. exit_code=0 の検出アーキテクチャ（auto-resolved）

- **決定**: `detect-wrapper-anomaly.sh` を exit_code=0 ケースに対応させ、スクリプト内で git log を直接確認する設計を採用。呼び出し側（auto SKILL.md 等）も exit_code=0 時に呼び出すよう更新が必要
- **根拠**: 現在 `detect-wrapper-anomaly.sh` は non-zero exit のみを対象とするが、silent no-op は exit 0 のため呼び出し変更が必要。スクリプト内完結が既存設計と一貫している
- **他の候補**: `reconcile-phase-state.sh` 側で検出 → 既存の phase state 管理の責務と混在するため不採用

#### 3. verify command 精度（auto-resolved）

- **決定**: AC1 の grep パターンを `silent.no.op\|silent_no_op` に改善（元の `exit_code.*0` は uppercase `EXIT_CODE` に不一致の恐れ）。呼び出し変更 AC を rubric で追加。bats テスト AC を追加
- **根拠**: 元パターン `LLM.*success\|exit_code.*0` は実装の変数名規則（UPPER_SNAKE_CASE）に一致しにくい。`silent.no.op` はパターン名として実装で使われる可能性が高い

### 主要変更点

- **Post-merge AC の classify 修正**: `verify-type: opportunistic` → `verify-type: manual` に修正（手動再現が必要なシナリオのため、opportunistic の「skill 実行時に副次検証」パターンに非該当）
- **新 AC 追加**: exit_code=0 呼び出し変更（rubric）と bats テスト追加の AC を新規追加

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## spec retrospective

### Minor observations
- Nothing to note.

### Judgment rationale
- `run-auto-sub.sh` の更新を選択した理由: `detect-wrapper-anomaly.sh` の呼び出しが LLM path（SKILL.md）と bash path（run-auto-sub.sh）の 2 箇所に分散しているが、AC3 の rubric は "or" でいずれかで良い。bash path のみのカバーは意図的スコープ限定であり、LLM path の patch-route completion check 無条件化は Issue #365 の別 Improvement Proposal に委ねる。
- `elif [[ "$EXIT_CODE" == "0" ]]; then` をチェーン末尾に置く理由: 既存の 4 パターンは trigger 文字列が exit_code=0 シナリオに出現しないため順序依存なし。末尾が自然な配置。

### Uncertainty resolution
- Nothing to note (design was straightforward; no significant uncertainties at spec time).

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文の `## Auto-Resolved Ambiguity Points` が Spec `## issue retrospective` に引き継がれており、曖昧ポイントの解決根拠が明示されている。特に「LLM path（SKILL.md）は今回スコープ外」という意図的スコープ限定が Spec Notes にも明示されており、verify 時に誤判定を防ぐ情報が揃っていた。
- AC3 rubric の "OR" 条件は `run-auto-sub.sh` 更新のみで満たせるよう設計されており、verify で PASS 判定を得やすい構造だった。

#### design
- 実装ステップ 1〜3 はすべて Spec の設計通りに実装されており、逸脱なし。
- `detect-wrapper-anomaly.sh` のパターン追加場所（`watchdog-kill` ブロックの後）は適切。既存パターンと順序依存がないことが Notes で説明されている。

#### code
- 単一のクリーンな実装コミット（`3839c8b`）。fixup/amend パターンなし。
- `run-auto-sub.sh` 変更は最小限（`[[ $exit_code -eq 0 ]] && return 0` を if ブロックに展開し anomaly 検出を追加）。
- `skills/auto/SKILL.md` は意図的に非更新（スコープ限定の判断）。

#### review
- パッチルートのため review フェーズなし。

#### merge
- main への直接 push（パッチルート）。コンフリクトなし。

#### verify
- 4 条件すべて PASS。成功フレーズパターン（`完了しました|commit and push`）は Issue #365 実例に基づくが、他の成功フレーズが検出漏れとなる可能性あり（下記 Improvement Proposals 参照）。

### Improvement Proposals
- `skills/auto/SKILL.md` の非 XL ルートにも exit_code=0 時の `detect-wrapper-anomaly.sh` 呼び出しを追加する（Spec Notes および Issue #365 Improvement Proposals で言及済みの未対応スコープ）。Issue #365 の実際の発生パスは LLM-executed path であり、bash path のみのカバーでは同種異常が再発した場合に検出できない。
- 成功フレーズパターン `"完了しました|commit and push"` は Issue #365 実例に基づく狭い定義。英語成功フレーズ（`"successfully committed"`, `"done"` 等）を追加するか、フレーズベースではなく commit 有無のみで判定する方式への変更を検討する。
