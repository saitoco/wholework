# Issue #500: auto: forked session の mid-run API 障害に対する自動 reconcile + retry 強化

## Overview

`/auto` の forked session が mid-run で Anthropic API connection error 等（exit 1）する事象に対し、
既存 3-tier recovery の Tier 2 枠内で能動的に reconcile + retry を適用できるよう強化する。

具体的には以下 4 コンポーネントを拡張する：

1. `scripts/detect-wrapper-anomaly.sh` — API 接続エラーパターンの追加検出
2. `modules/orchestration-fallbacks.md` — `mid-run-api-error` catalog エントリ追加
3. `scripts/reconcile-phase-state.sh` — phase ラベル消失状態の復元ヒント出力強化
4. `skills/auto/SKILL.md` — Tier 2 recovery セクションへの API 障害パターン適用条件の明示

Parent: #483 Sub-issue 2。fork 設計は変更せず、既存 3-tier recovery 枠内の強化のみ。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `mid-run-api-error` パターン追加（`elif grep -qiE "APIConnectionError|..."` ブランチ）— bash 3.2+ 互換
- `modules/orchestration-fallbacks.md`: `## mid-run-api-error` catalog エントリ追加（"Operational Notes" セクションの直前）
- `scripts/reconcile-phase-state.sh`: `_append_hints_to_actual()` ヘルパー追加 + `_completion_spec()` の mismatch 出力で呼び出し — bash 3.2+ 互換
- `skills/auto/SKILL.md`: Tier 2 セクションに `mid-run-api-error` パターン検出時の reconcile + 1-retry 適用条件を明記
- `tests/detect-wrapper-anomaly.bats`: API エラーパターン検出テスト 3 ケース追加
- `tests/reconcile-phase-state.bats`: spec completion mismatch 時の復元ヒント出力テスト 1 ケース追加
- `modules/phase-state.md`: JSON schema table に `hint_spec_file` / `hint_recent_commit` / `hint_pr_state` 新規フィールドを追加（optional）

## Implementation Steps

1. **`detect-wrapper-anomaly.sh` に API エラーパターン追加** (→ 受入条件 1)

   既存の `elif` 連鎖（`elif [[ "$EXIT_CODE" == "0" ]]` の直前）に新規ブランチを追加する：

   ```bash
   elif grep -qiE "APIConnectionError|Request timed out|overloaded_error|529.*[Oo]verload" "$LOG_FILE"; then
     PATTERN_NAME="mid-run-api-error"
     ANOMALY_DESC="API connection error in phase \`$PHASE\` (exit code $EXIT_CODE): API connection/overload pattern detected in wrapper output. The forked session terminated mid-run before phase completion."
     IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#mid-run-api-error\`: run reconcile-phase-state.sh to check actual completion, restore the phase label if needed, then retry the phase once with the corresponding run-*.sh script."
   ```

   挿入位置: `elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q "Review Summary" "$LOG_FILE"` ブランチの直後（`elif [[ "$EXIT_CODE" == "0" ]]` ブランチの直前）

2. **`orchestration-fallbacks.md` に `mid-run-api-error` catalog エントリ追加** (→ 受入条件 2)

   `## Operational Notes` セクションの直前に以下のエントリを追加する：

   ```markdown
   ## mid-run-api-error

   ### Symptom
   - forked session (`claude -p`) exits with non-zero exit code mid-run
   - Log contains API connection/error patterns: `APIConnectionError`, `Request timed out`,
     `overloaded_error`, or `529.*Overload`
   - Issue state: OPEN, phase label may be missing or inconsistent

   ### Applicable Phases
   - Any phase running via `run-*.sh` (spec, code, review, merge, verify)

   ### Fallback Steps
   1. Run `reconcile-phase-state.sh <phase> <issue> --check-completion` and parse the JSON output
   2. If `matches_expected: true`: phase completed before the API error; override to success and continue
   3. If `matches_expected: false`:
      a. Inspect restoration hints from `actual` JSON:
         - `hint_spec_file`: spec file path if found (indicates spec phase completed)
         - `hint_recent_commit`: recent commit referencing the issue (indicates code was committed)
         - `hint_pr_state`: PR state if a PR exists for the issue
      b. Restore the phase label based on hints:
         - No hint_spec_file: spec not created; restore `phase/spec` label and retry spec
         - hint_spec_file present, no PR, no recent commit: spec done, label lost; restore `phase/ready`
         - hint_recent_commit present (commit without PR): code committed; restore `phase/code`
         - hint_pr_state is OPEN: PR exists; restore `phase/review` or `phase/merge`
      c. Retry the failed phase once via the corresponding `run-*.sh <issue_number>`

   ### Escalation
   - If retry fails again with an API error: stop with stop-and-report; persistent API failure requires manual intervention
   - If retry fails with a different error: escalate to Tier 3 (recovery sub-agent)
   - Maximum 1 retry per API error occurrence; no further looping

   ### Rationale
   - Introduced in #500: forked sessions failing mid-run due to API connection errors left issues in
     OPEN state with missing phase labels; `reconcile-phase-state.sh` Tier 1 could not fully restore
     state because labels were absent
   - `reconcile-phase-state.sh` enhancement (#500) adds restoration hints to mismatch output,
     enabling the parent session to restore the correct phase label before retrying
   - See also: #483 (parent XL issue), #314 (reconcile-phase-state), #313 (wrapper anomaly detector)
   ```

   セパレータ `---` を追加してから次のセクション。

3. **`reconcile-phase-state.sh` に `_append_hints_to_actual()` ヘルパー追加 + `_completion_spec()` で呼び出し** (→ 受入条件 3)

   `_completion_spec()` 関数の直前に以下のヘルパーを追加する：

   ```bash
   # Append restoration hints to an actual JSON object for phase label recovery.
   # Input: existing actual JSON string (must end with })
   # Output: JSON with hint_recent_commit and hint_pr_state appended
   _append_hints_to_actual() {
     local json="$1"

     local recent_commit
     recent_commit=$(git log --oneline -1 --grep="#${ISSUE_NUMBER}" 2>/dev/null | head -1 || true)
     local hint_commit_val="null"
     [[ -n "$recent_commit" ]] && hint_commit_val="\"$(_escape_json "$recent_commit")\""

     local pr_state
     pr_state=$(gh pr list --search "closes #${ISSUE_NUMBER}" --state all --json state \
       -q '.[0].state' 2>/dev/null || true)
     local hint_pr_val="null"
     [[ -n "$pr_state" ]] && hint_pr_val="\"$(_escape_json "$pr_state")\""

     printf '%s,"hint_recent_commit":%s,"hint_pr_state":%s}' \
       "${json%\}}" "$hint_commit_val" "$hint_pr_val"
   }
   ```

   `_completion_spec()` 内の両 `_handle_mismatch` 呼び出しを修正する：

   - 変更前（spec file not found の場合）:
     ```bash
     _handle_mismatch "spec file not found under ${spec_path} for issue #${ISSUE_NUMBER}" "$actual_json"
     ```
   - 変更後:
     ```bash
     _handle_mismatch "spec file not found under ${spec_path} for issue #${ISSUE_NUMBER}" \
       "$(_append_hints_to_actual "$actual_json")"
     ```

   - 変更前（ready-or-later label なしの場合）:
     ```bash
     _handle_mismatch "spec file found but no ready-or-later phase label for issue #${ISSUE_NUMBER}" "$actual_json"
     ```
   - 変更後:
     ```bash
     _handle_mismatch "spec file found but no ready-or-later phase label for issue #${ISSUE_NUMBER}" \
       "$(_append_hints_to_actual "$actual_json")"
     ```

   `actual_json` は既に `spec_file` フィールドを含んでいるため、`hint_spec_file` は不要（重複回避）。

4. **`skills/auto/SKILL.md` Tier 2 セクションに API 障害パターン適用条件を明記** (→ 受入条件 4)

   `#### Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog` セクション内、
   `If detector output is non-empty (known pattern matched):` の箇条書きに以下の条件を追加する
   （`- If the catalog's recovery fails, proceed to Tier 3` の直前）:

   変更前:
   ```
   If detector output is non-empty (known pattern matched):
   - Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` to get `SPEC_PATH`
   - Append the detector output to the Spec file...
   - Read `${CLAUDE_PLUGIN_ROOT}/modules/orchestration-fallbacks.md` and follow the catalog entry...
   - If the catalog's recovery succeeds, continue to the next phase (skip Tier 3)
   - If the catalog's recovery fails, proceed to Tier 3
   ```

   変更後（最後の箇条書きの直前に追加）:
   ```
   - **`mid-run-api-error` pattern**: run `reconcile-phase-state.sh <phase> $NUMBER --check-completion`;
     if `matches_expected: true` override to success; if `matches_expected: false` inspect
     `hint_*` fields in `actual` JSON to restore the phase label, then retry the failed phase
     once via the corresponding `run-*.sh` script
   ```

5. **bats テスト追加 + `modules/phase-state.md` JSON schema 更新** (→ 受入条件 5)

   **`tests/detect-wrapper-anomaly.bats`** — ファイル末尾に 3 テストケース追加:

   ```bats
   @test "API connection error: detects APIConnectionError pattern" {
       echo "anthropic.APIConnectionError: Connection error." > "$LOG_FILE"
       run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase spec
       [ "$status" -eq 0 ]
       [[ "$output" == *"mid-run-api-error"* ]]
       [[ "$output" == *"### Orchestration Anomalies"* ]]
       [[ "$output" == *"### Improvement Proposals"* ]]
       [[ "$output" == *"mid-run-api-error"* ]]
   }

   @test "API connection error: detects Request timed out pattern" {
       echo "Error: Request timed out after 60 seconds" > "$LOG_FILE"
       run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase code
       [ "$status" -eq 0 ]
       [[ "$output" == *"mid-run-api-error"* ]]
   }

   @test "API connection error: no detection when log has no API error pattern" {
       echo "Some unrelated error occurred." > "$LOG_FILE"
       run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase spec
       [ "$status" -eq 0 ]
       [[ "$output" != *"mid-run-api-error"* ]]
   }
   ```

   **`tests/reconcile-phase-state.bats`** — ファイル末尾に 1 テストケース追加:

   ```bats
   @test "spec completion: spec exists + no ready label -> mismatch includes hint_recent_commit and hint_pr_state" {
       SPEC_DIR="$BATS_TEST_TMPDIR/docs/spec-hints"
       mkdir -p "$SPEC_DIR"
       touch "$SPEC_DIR/issue-500-my-spec.md"
       export MOCK_SPEC_PATH="$SPEC_DIR"

       cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
   #!/bin/bash
   # Label check
   if [[ "$1" == "issue" ]]; then echo "phase/spec"; exit 0; fi
   # PR list search
   echo "OPEN"
   exit 0
   MOCK_EOF
       chmod +x "$MOCK_DIR/gh"
       export PATH="$MOCK_DIR:$PATH"

       cat > "$MOCK_DIR/git" << 'MOCK_EOF'
   #!/bin/bash
   if [[ "$1" == "log" ]]; then echo "abc1234 Add spec for issue #500"; fi
   exit 0
   MOCK_EOF
       chmod +x "$MOCK_DIR/git"

       run bash "$SCRIPT" spec 500 --check-completion --strict
       [ "$status" -eq 1 ]
       [[ "$output" == *'"matches_expected":false'* ]]
       [[ "$output" == *'"hint_recent_commit"'* ]]
       [[ "$output" == *'"hint_pr_state"'* ]]
   }
   ```

   **`modules/phase-state.md`** — JSON schema table に以下の行を追加:

   ```
   | `actual.hint_spec_file` | string\|null | When phase label mismatch detected | Path to spec file if found, otherwise `null`. Added for phase label recovery. |
   | `actual.hint_recent_commit` | string\|null | When phase label mismatch detected | Most recent git commit referencing the issue, or `null`. |
   | `actual.hint_pr_state` | string\|null | When phase label mismatch detected | PR state (`"OPEN"`, `"MERGED"`, `"CLOSED"`) if found, otherwise `null`. |
   ```

   これら 3 フィールドは optional で `_completion_spec()` の mismatch 時のみ出力される。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh が API connection error 等の mid-run 障害パターンを検出し、対応する catalog アンカーと improvement hint を出力するよう拡張されている" --> API 障害パターンが anomaly detector に追加されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md に API 障害向け catalog エントリが追加され、Fallback Steps に phase ラベル復元と当該 forked phase の1回再実行（reconcile + retry）の手順が記載されている" --> 自動 reconcile + retry の catalog エントリが整備されている
- <!-- verify: rubric "reconcile-phase-state.sh の phase 別 completion check 出力（actual JSON または diagnosis）に、phase ラベル消失状態の復元ヒント（spec ファイル存在 / 直近 commit / PR 状態）が含まれるよう拡張されている。スクリプトの引数 signature は不変" --> reconciler の復元ヒント出力が強化されている
- <!-- verify: rubric "skills/auto/SKILL.md の Tier 2 recovery セクションに、API 障害パターン検出時に reconcile + 当該 phase の1回 retry を適用する条件が反映されている" --> /auto SKILL.md の Tier 2 適用条件に API 障害パターンが反映されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト CI が SUCCESS

### Post-merge

- downstream プロジェクトで mid-run API 障害発生時に `/auto` 親セッションが Tier 2 内で自動 reconcile + retry を実行し復旧することを観察する

## Notes

- `_append_hints_to_actual()` の文字列操作 `${json%\}}` は bash 3.2+ で動作する（`%` サフィックス削除）
- `gh pr list --search "closes #N"` はフルテキスト検索のため関連 PR を広く捕捉するが、複数マッチ時は最初の結果を採用する（`.[0].state`）
- 復元ヒントは `_completion_spec()` の mismatch 時のみ出力する（spec フェーズが最も頻発する API 障害被害フェーズのため）; 他フェーズへの拡張は将来の Issue で対応
- `mid-run-api-error` パターンは `elif [[ "$EXIT_CODE" == "0" ]]` ブランチより前に挿入することで、exit 0 の silent-no-op 検出と競合しない（first-match-wins の順序維持）

## Code Retrospective

### Deviations from Design
- None. 実装ステップはすべて Spec 通りに実行した。`_append_hints_to_actual()` のシグネチャも Spec 通り。

### Design Gaps/Ambiguities
- bats テストの `reconcile-phase-state.bats` における `git` モックは、既存の test setup で `WHOLEWORK_SCRIPT_DIR` をモックディレクトリに向けているが、`git` は `WHOLEWORK_SCRIPT_DIR` 経由ではなく `PATH` 経由で解決されるため、`export PATH="$MOCK_DIR:$PATH"` が必要だった。Spec のテンプレートではこの PATH 追加が明示されており問題なかった。
- `_append_hints_to_actual()` が `spec_file` を重複追加しない設計（`actual_json` にすでに含まれているため）は Spec の Notes に明記されており、実装上も問題なし。

### Rework
- None. 一発で全テスト通過、rework は発生しなかった。

## review retrospective

### Spec vs. Implementation Divergence Patterns
- `hint_spec_file` がドキュメント（`orchestration-fallbacks.md` / `phase-state.md`）に記載されているにもかかわらず、実装の `_append_hints_to_actual()` が `hint_recent_commit` / `hint_pr_state` のみを出力していた。Spec Notes に「重複回避のため既存 `spec_file` フィールドで代替」と記載があったが、ドキュメント側は更新されていなかった。→ 同名フィールドのドキュメント-実装不整合は rubric verify command で検出困難なため、review フェーズで特に注意が必要。

### Recurring Issues
- なし（今回初出パターン）

### Acceptance Criteria Verification Difficulty
- rubric 条件はすべて PASS だったが、`hint_spec_file` の不整合はドキュメント-実装の対応チェックが必要で rubric だけでは検出困難だった。今後、フィールド名を Spec と実装の両方に明記する設計では、review での明示的なフィールド照合チェックが有効。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- `hint_spec_file` の doc-impl mismatch を修正（`orchestration-fallbacks.md` + `phase-state.md`）。既存 `spec_file` フィールドが代替として機能しているため実装変更は不要
- 全受け入れ条件が PASS、CI もすべて SUCCESS。SHOULD issues 2件を修正してマージ可能

### Deferred Items
- 他フェーズ（code, review, merge）への復元ヒント拡張（現在は spec フェーズのみ）
- reconcile + retry の自動実行ロジック自体は `/auto` スキル側（bash `run-auto-sub.sh` + `apply-fallback.sh`）への反映は将来の Issue で対応

### Notes for Next Phase
- `/merge` 前に CI が新コミットで再度 PASS していることを確認すること（docs-only 変更なので通過見込み）
- `apply-fallback.sh` は `mid-run-api-error` パターンを未対応（XL bash path は Tier 3 fallback）、将来の強化余地
