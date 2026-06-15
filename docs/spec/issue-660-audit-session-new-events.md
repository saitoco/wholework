# Issue #660: audit/auto-session — Summary table 追加メトリクス (parent manual interventions / verify reopen cycles) を event 配線で実装

## Overview

`/audit auto-session` レポートの Summary table に、手動レポート `docs/reports/auto-batch-list-mode-2026-06-14.md` が持つ 2 メトリクスを追加する:

1. **Parent session manual interventions** — 親セッションが child wrapper の失敗を手動回復した回数
2. **verify FAIL → reopen fix cycles** — `/verify` FAIL → Issue reopen → 再 verify の fix cycle 回数

対応方針:
- `scripts/emit-event.sh` に両 event 種のスキーマをコメントドキュメントとして追加
- `skills/verify/SKILL.md` Step 11 reopen 処理に `verify_reopen_cycle` emit 呼び出しを追加 (emit は `/auto` 実行コンテキスト限定)
- `scripts/get-auto-session-report.sh` Summary table に両メトリクスの集計行を追加
- `tests/audit-auto-session.bats` に新 event 種を含むテストケースを追加

## Changed Files

- `scripts/emit-event.sh`: add `manual_intervention` and `verify_reopen_cycle` event schema comments — bash 3.2+ compatible
- `skills/verify/SKILL.md`: add `verify_reopen_cycle` emit instruction in Step 11 case (b) reopen block; update `allowed-tools` to include `date:*`, `printf:*` for inline emit command — bash 3.2+ compatible
- `scripts/get-auto-session-report.sh`: add `MANUAL_INTERVENTIONS` and `VERIFY_REOPEN_CYCLES` jq count queries; add 2 rows to Summary table — bash 3.2+ compatible
- `tests/audit-auto-session.bats`: add `@test "success: manual_intervention and verify_reopen_cycle events appear in Summary table"` — bash 3.2+ compatible

## Implementation Steps

1. `scripts/emit-event.sh` に `manual_intervention` と `verify_reopen_cycle` のスキーマコメントを追加 (→ AC1, AC2)
   - 既存 comment block の直後 (`emit_event()` 関数定義の前) に以下を挿入:
   ```
   # Documented event schemas:
   #
   # manual_intervention: parent session manually recovered a child wrapper failure
   #   recovery_target=<phase>       e.g. code-patch, verify
   #   wrapper_exit_code=<code>      original wrapper exit code
   #   intervention_type=<type>      silent_no_op_manual_fix | tier3_abort_manual_fix | direct_commit
   #
   # verify_reopen_cycle: /verify FAIL → issue reopen fix cycle entered
   #   iteration=<n>                 verify iteration counter (from get-verify-iteration.sh)
   #   reopen_reason=<reason>        pre_merge_ac_fail | post_merge_observation_fail | manual_judgment
   ```

2. `skills/verify/SKILL.md` Step 11 case (b) の `gh issue reopen "$NUMBER"` 直後に `verify_reopen_cycle` emit 命令を追加 (→ AC3)
   - `/auto` 実行コンテキスト (`AUTO_EVENTS_LOG` が set されている場合) のみ emit するガード付き
   - inline JSON write アプローチ (emit-event.sh のソース不要):
   ```bash
   # Emit verify_reopen_cycle event (only when running inside /auto session)
   if [[ -n "${AUTO_EVENTS_LOG:-}" && -n "${AUTO_SESSION_ID:-}" ]]; then
     _ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     printf '%s\n' "{\"ts\":\"${_ts}\",\"issue\":${NUMBER},\"event\":\"verify_reopen_cycle\",\"session_id\":\"${AUTO_SESSION_ID}\",\"iteration\":\"${NEXT_ITERATION}\",\"reopen_reason\":\"pre_merge_ac_fail\"}" >> "${AUTO_EVENTS_LOG}" 2>/dev/null || true
   fi
   ```
   - `allowed-tools` の `Bash(...)` リストに `date:*`, `printf:*` を追加

3. `scripts/get-auto-session-report.sh` に `MANUAL_INTERVENTIONS` count query を追加し Summary table に行を挿入 (→ AC4)
   - `# Render the markdown report` コメントの直前に追加 (→ `CONCURRENT_COMMITS` 変数定義の後):
   ```bash
   MANUAL_INTERVENTIONS=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "manual_intervention")] | length' 2>/dev/null || echo 0)
   ```
   - `cat > "$OUTPUT_PATH" << REPORT_EOF` ブロック内の Summary table 末尾 (`| Concurrent commits detected | ${CONCURRENT_COMMITS} |` の後) に追加:
   ```
   | Parent session manual interventions | ${MANUAL_INTERVENTIONS} |
   ```

4. `scripts/get-auto-session-report.sh` に `VERIFY_REOPEN_CYCLES` count query を追加し Summary table に行を挿入 (→ AC5, AC6)  
   - Step 3 の `MANUAL_INTERVENTIONS` 定義の直後に追加:
   ```bash
   VERIFY_REOPEN_CYCLES=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "verify_reopen_cycle")] | length' 2>/dev/null || echo 0)
   ```
   - Summary table の `| Parent session manual interventions | ... |` 行の直後に追加:
   ```
   | verify FAIL → reopen fix cycles | ${VERIFY_REOPEN_CYCLES} |
   ```

5. `tests/audit-auto-session.bats` に新 event 種を含むテストを追加 (→ AC7)
   - 既存テスト末尾に新規 `@test` を追加:
   ```bash
   @test "success: manual_intervention and verify_reopen_cycle events appear in Summary table" {
       cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
   {"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"abc-333","size":"M"}
   {"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"abc-333","phase":"code-pr"}
   {"ts":"2026-06-14T10:20:00Z","issue":100,"event":"phase_complete","session_id":"abc-333","phase":"code-pr"}
   {"ts":"2026-06-14T10:21:00Z","issue":100,"event":"manual_intervention","session_id":"abc-333","recovery_target":"code-pr","wrapper_exit_code":"1","intervention_type":"tier3_abort_manual_fix"}
   {"ts":"2026-06-14T10:30:00Z","issue":100,"event":"verify_reopen_cycle","session_id":"abc-333","iteration":"1","reopen_reason":"pre_merge_ac_fail"}
   {"ts":"2026-06-14T10:35:00Z","issue":100,"event":"sub_complete","session_id":"abc-333","exit_code":"0"}
   FIXTURE_EOF

       run bash "$SCRIPT" "abc-333" --output "$OUTPUT_PATH" --no-github
       [ "$status" -eq 0 ]
       [ -f "$OUTPUT_PATH" ]
       grep -q "Parent session manual interventions" "$OUTPUT_PATH"
       grep -q "verify FAIL.*reopen fix cycles" "$OUTPUT_PATH"
       grep -q "manual interventions | 1" "$OUTPUT_PATH"
       grep -q "reopen fix cycles | 1" "$OUTPUT_PATH"
   }
   ```

## Verification

### Pre-merge

- <!-- verify: grep "manual_intervention" "scripts/emit-event.sh" --> `manual_intervention` event schema が emit-event.sh に追加されている
- <!-- verify: grep "verify_reopen_cycle" "scripts/emit-event.sh" --> `verify_reopen_cycle` event schema が emit-event.sh に追加されている
- <!-- verify: grep "verify_reopen_cycle" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` Step 11 reopen 処理に `verify_reopen_cycle` emit 呼び出しが追加されている
- <!-- verify: grep "manual_intervention" "scripts/get-auto-session-report.sh" --> `get-auto-session-report.sh` が `manual_intervention` count を Summary table に反映する
- <!-- verify: grep "verify_reopen_cycle" "scripts/get-auto-session-report.sh" --> `get-auto-session-report.sh` が `verify_reopen_cycle` count を Summary table に反映する
- <!-- verify: rubric "Generated Summary table includes 'Parent session manual interventions' and 'verify FAIL → reopen fix cycles' rows after this Issue's implementation" --> Summary table の構造が manual report と一致する
- <!-- verify: command "bats tests/audit-auto-session.bats" --> bats テストが green（新規 event 種を含むテストケース追加）

### Post-merge

- 次回 `/auto` 完走後の `/audit auto-session` レポートで両メトリクスが 0 または実際の event 数を反映することを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- **Verification count note**: Pre-merge verification items (7) exceeds SPEC_DEPTH=light limit (5). All 7 are verbatim copies from Issue body acceptance criteria, so they are preserved as-is. Follows Issue #335 precedent.
- **`manual_intervention` emit wiring は本 Issue スコープ外**: AC が要求するのは (1) emit-event.sh へのスキーマ comment 追加と (2) get-auto-session-report.sh での count 集計のみ。実際の emit 呼び出し配線 (wrapper が flag ファイルを検出して emit するロジック) は別 Issue で実装する。flag file 設計方針: `.tmp/manual-recovery-<issue>-<phase>.flag` を `/auto` skill が手動介入時に作成し、`run-auto-sub.sh` が次回実行時またはポスト処理で検出して emit する。
- **verify_reopen_cycle emit は `/auto` コンテキスト限定**: `AUTO_EVENTS_LOG` と `AUTO_SESSION_ID` の両方が set されている場合のみ emit する。standalone `/verify` 実行時は emit をスキップ (`|| true` で無音失敗)。
- **inline JSON write vs. source emit-event.sh**: verify SKILL.md では emit-event.sh を source する代わりに printf による直接 JSON 書き込みを採用。locking なし (best-effort) だが verify は issue ごとに serial 実行されるため競合リスクは低い。
- **Auto-Resolved (Issue body より転記)**: event schema の追加形式 → コメントドキュメント採用; `verify_reopen_cycle` emit wiring AC → pre-merge AC として追加; `manual_intervention` 検出機構 → Spec フェーズで設計 (上記 Notes 参照)

## Auto Retrospective

### Orchestration Anomalies
- **[review-completion-false-negative]** Review phase completion false-negative in phase `review` (exit code 1): `matches_expected:false` and `phase:review` detected in reconciler output, but no existing fallback header (## Review Response Summary / ## レビュー回答サマリ) was found in wrapper log. Root cause: the review skill posted the summary as a **PR Review (state=COMMENTED)**, so it did not appear in the issue comments read by `gh pr view --json comments`. The `<!-- review-summary -->` marker was also absent. Reference: #547.

### Improvement Proposals
- Standardize the review skill (`skills/review/SKILL.md`) summary posting channel from "PR Review submission" to "PR issue comment with `<!-- review-summary -->` marker"; or extend `reconcile-phase-state.sh _completion_review` to also scan PR Review bodies (`gh api repos/{owner}/{repo}/pulls/{N}/reviews`). The former is lower-cost and aligns with the existing marker SSoT.
- Add an explicit `<!-- review-summary -->` marker-mandatory note to the review skill prompt to suppress LLM omission.
