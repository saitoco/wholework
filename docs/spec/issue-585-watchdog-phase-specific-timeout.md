# Issue #585: Watchdog Phase-Specific Timeout

## Overview

Tune `run-*.sh` watchdog timeouts per-phase to speed up true-stall detection without increasing false-kill risk.

Based on observed silent-window measurements from the 2026-06-13 `/auto` session performance report:

| Phase  | Observed max silent | Proposed timeout | Margin |
|--------|---------------------|-----------------|--------|
| spec   | 540s                | 1800s           | 3.3×   |
| code   | 540s                | 1800s           | 3.3×   |
| review | 660s                | 2000s           | 3.0×   |
| merge  | <60s                | 600s            | 10×    |
| issue  | <60s                | 600s            | 10×    |

`WATCHDOG_TIMEOUT_DEFAULT=2700` (global fallback) is retained unchanged. New phase-specific default constants are added. `load_watchdog_timeout()` gains an optional `phase` argument for backward compatibility.

Priority order (highest to lowest):
1. Phase-specific `.wholework.yml` key (e.g., `watchdog-timeout-spec-seconds`)
2. Global `.wholework.yml` key (`watchdog-timeout-seconds`)
3. Phase-specific default constant (e.g., `WATCHDOG_TIMEOUT_SPEC_DEFAULT`)
4. `WATCHDOG_TIMEOUT_DEFAULT`

## Changed Files

- `scripts/watchdog-defaults.sh`: add 5 phase-specific default constants; extend `load_watchdog_timeout()` with optional `phase` argument and 4-level priority resolution — bash 3.2+ compatible
- `scripts/run-spec.sh`: change `load_watchdog_timeout "$SCRIPT_DIR"` → `load_watchdog_timeout "$SCRIPT_DIR" "spec"`
- `scripts/run-code.sh`: change `load_watchdog_timeout "$SCRIPT_DIR"` → `load_watchdog_timeout "$SCRIPT_DIR" "code"`
- `scripts/run-review.sh`: change `load_watchdog_timeout "$SCRIPT_DIR"` → `load_watchdog_timeout "$SCRIPT_DIR" "review"`
- `scripts/run-merge.sh`: change `load_watchdog_timeout "$SCRIPT_DIR"` → `load_watchdog_timeout "$SCRIPT_DIR" "merge"`
- `scripts/run-issue.sh`: change `load_watchdog_timeout "$SCRIPT_DIR"` → `load_watchdog_timeout "$SCRIPT_DIR" "issue"`
- `modules/detect-config-markers.md`: add 5 new rows to Marker Definition Table (`watchdog-timeout-{phase}-seconds` → `WATCHDOG_TIMEOUT_{PHASE}_SECONDS`)
- `docs/guide/customization.md`: add 5 new rows to Available Keys table; add phase-specific keys to YAML example comment
- `docs/ja/guide/customization.md`: sync translation for the same changes
- `tests/watchdog-defaults.bats`: add phase-specific timeout resolution tests (phase default, yml phase key, yml global key priority, backward compatibility)

## Implementation Steps

1. Update `scripts/watchdog-defaults.sh` (→ AC1–AC4)
   - Add phase-specific default constants immediately after `WATCHDOG_TIMEOUT_DEFAULT=2700`:
     ```
     WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800
     WATCHDOG_TIMEOUT_CODE_DEFAULT=1800
     WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2000
     WATCHDOG_TIMEOUT_MERGE_DEFAULT=600
     WATCHDOG_TIMEOUT_ISSUE_DEFAULT=600
     ```
   - Extend `load_watchdog_timeout()` to accept an optional second argument `phase`:
     ```bash
     load_watchdog_timeout() {
       local script_dir="$1"
       local phase="${2:-}"
       local val phase_default
       phase_default="$WATCHDOG_TIMEOUT_DEFAULT"
       if [ -n "$phase" ]; then
         local phase_upper
         phase_upper=$(echo "$phase" | tr '[:lower:]' '[:upper:]')
         local var_name="WATCHDOG_TIMEOUT_${phase_upper}_DEFAULT"
         eval "phase_default=\"\${${var_name}:-$WATCHDOG_TIMEOUT_DEFAULT}\""
         # Try phase-specific yml key first
         val=$("$script_dir/get-config-value.sh" "watchdog-timeout-${phase}-seconds" "" 2>/dev/null || echo "")
         if [ -z "$val" ]; then
           # Fall back to global yml key (using phase_default as final fallback)
           val=$("$script_dir/get-config-value.sh" watchdog-timeout-seconds "$phase_default" 2>/dev/null || echo "$phase_default")
         fi
       else
         # Backward-compatible path: no phase argument
         val=$("$script_dir/get-config-value.sh" watchdog-timeout-seconds "$WATCHDOG_TIMEOUT_DEFAULT" 2>/dev/null || echo "$WATCHDOG_TIMEOUT_DEFAULT")
       fi
       if ! echo "$val" | grep -qE '^[0-9]+$' || [ "$val" -le 0 ]; then
         echo "Warning: invalid watchdog timeout '${val}', using default ${phase_default}" >&2
         val="$phase_default"
       fi
       WATCHDOG_TIMEOUT="$val"
     }
     ```
   - Note: `eval` used for indirect variable lookup to remain bash 3.2+ compatible (`${!var}` syntax is also 3.2-compatible; either form is acceptable)

2. Update 5 `run-*.sh` scripts — add `"<phase>"` as second argument to `load_watchdog_timeout` (parallel with Step 1) (→ AC5–AC9)
   - `scripts/run-spec.sh`: `load_watchdog_timeout "$SCRIPT_DIR" "spec"`
   - `scripts/run-code.sh`: `load_watchdog_timeout "$SCRIPT_DIR" "code"`
   - `scripts/run-review.sh`: `load_watchdog_timeout "$SCRIPT_DIR" "review"`
   - `scripts/run-merge.sh`: `load_watchdog_timeout "$SCRIPT_DIR" "merge"`
   - `scripts/run-issue.sh`: `load_watchdog_timeout "$SCRIPT_DIR" "issue"`

3. Update `tests/watchdog-defaults.bats` — add phase-specific timeout tests (after Step 1) (→ AC15)
   - `@test "load_watchdog_timeout uses phase-specific default when phase is spec"` — mock `get-config-value.sh` returns `""` (no yml key), expect `WATCHDOG_TIMEOUT=1800`
   - `@test "load_watchdog_timeout uses WATCHDOG_TIMEOUT_MERGE_DEFAULT when phase is merge"` — expect `WATCHDOG_TIMEOUT=600`
   - `@test "load_watchdog_timeout uses phase yml key when set"` — mock phase-key response `900`, expect `WATCHDOG_TIMEOUT=900`
   - `@test "load_watchdog_timeout falls back to global yml key when phase key is unset"` — mock phase-key returns `""`, global key returns `3600`, expect `WATCHDOG_TIMEOUT=3600`
   - `@test "load_watchdog_timeout without phase argument uses WATCHDOG_TIMEOUT_DEFAULT"` — mock returns `""`, no phase arg, expect `WATCHDOG_TIMEOUT=2700`
   - Note: Inspect current `@test` names with `grep "@test" tests/watchdog-defaults.bats` before writing new tests to avoid naming conflicts

4. Update `modules/detect-config-markers.md` — add 5 rows to Marker Definition Table (parallel with Steps 2–3) (→ AC10–AC11)
   - Insert after the `watchdog-timeout-seconds` row:

     | `watchdog-timeout-spec-seconds` | `WATCHDOG_TIMEOUT_SPEC_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` (unset; falls through to global key or phase default) |
     | `watchdog-timeout-code-seconds` | `WATCHDOG_TIMEOUT_CODE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` |
     | `watchdog-timeout-review-seconds` | `WATCHDOG_TIMEOUT_REVIEW_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` |
     | `watchdog-timeout-merge-seconds` | `WATCHDOG_TIMEOUT_MERGE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` |
     | `watchdog-timeout-issue-seconds` | `WATCHDOG_TIMEOUT_ISSUE_SECONDS` | Integer string (extract as-is; use phase-specific default if ≤0 or non-numeric) | `""` |

   - Also add corresponding entries under the "Output Format" / variable list section

5. Update `docs/guide/customization.md` and `docs/ja/guide/customization.md` (after Step 4) (→ AC12–AC13, AC16)
   - Add 5 new rows to the Available Keys table (after `watchdog-timeout-seconds` row):

     | `watchdog-timeout-spec-seconds` | integer | `""` (falls back to `1800`) | Per-phase watchdog timeout override for `/spec`. Priority: this key > `watchdog-timeout-seconds` > `1800`. |
     | `watchdog-timeout-code-seconds` | integer | `""` (falls back to `1800`) | Per-phase watchdog timeout override for `/code`. |
     | `watchdog-timeout-review-seconds` | integer | `""` (falls back to `2000`) | Per-phase watchdog timeout override for `/review`. |
     | `watchdog-timeout-merge-seconds` | integer | `""` (falls back to `600`) | Per-phase watchdog timeout override for `/merge`. |
     | `watchdog-timeout-issue-seconds` | integer | `""` (falls back to `600`) | Per-phase watchdog timeout override for `/issue`. |

   - Add the 5 new keys as commented examples in the YAML block (after the `watchdog-timeout-seconds: 3600` example line):
     ```yaml
     # Per-phase overrides (optional; take precedence over watchdog-timeout-seconds)
     # watchdog-timeout-spec-seconds: 1800
     # watchdog-timeout-code-seconds: 1800
     # watchdog-timeout-review-seconds: 2000
     # watchdog-timeout-merge-seconds: 600
     # watchdog-timeout-issue-seconds: 600
     ```
   - Update `docs/ja/guide/customization.md` with the same changes in Japanese

## Verification

### Pre-merge

- <!-- verify: grep "WATCHDOG_TIMEOUT_SPEC_DEFAULT|WATCHDOG_TIMEOUT_CODE_DEFAULT" "scripts/watchdog-defaults.sh" --> `watchdog-defaults.sh` に spec/code フェーズ別デフォルトが定義されている
- <!-- verify: grep "WATCHDOG_TIMEOUT_REVIEW_DEFAULT" "scripts/watchdog-defaults.sh" --> `watchdog-defaults.sh` に review フェーズ別デフォルト（2000s）が定義されている
- <!-- verify: grep "WATCHDOG_TIMEOUT_MERGE_DEFAULT" "scripts/watchdog-defaults.sh" --> `watchdog-defaults.sh` に merge フェーズ別デフォルト（600s）が定義されている
- <!-- verify: grep "load_watchdog_timeout.*phase|local phase" "scripts/watchdog-defaults.sh" --> `load_watchdog_timeout` が phase 引数を受け付ける
- <!-- verify: grep "load_watchdog_timeout.*spec" "scripts/run-spec.sh" --> `run-spec.sh` が phase="spec" で呼び出している
- <!-- verify: grep "load_watchdog_timeout.*code" "scripts/run-code.sh" --> `run-code.sh` が phase="code" で呼び出している
- <!-- verify: grep "load_watchdog_timeout.*review" "scripts/run-review.sh" --> `run-review.sh` が phase="review" で呼び出している
- <!-- verify: grep "load_watchdog_timeout.*merge" "scripts/run-merge.sh" --> `run-merge.sh` が phase="merge" で呼び出している
- <!-- verify: grep "load_watchdog_timeout.*issue" "scripts/run-issue.sh" --> `run-issue.sh` が phase="issue" で呼び出している
- <!-- verify: grep "watchdog-timeout-spec-seconds|watchdog-timeout-code-seconds" "modules/detect-config-markers.md" --> フェーズ別キー（spec/code）が Marker Definition Table に追加されている
- <!-- verify: grep "watchdog-timeout-merge-seconds" "modules/detect-config-markers.md" --> フェーズ別キー（merge/issue、600s）が Marker Definition Table に追加されている
- <!-- verify: grep "watchdog-timeout-spec-seconds" "docs/guide/customization.md" --> `docs/guide/customization.md` の Available Keys テーブルに新キーが追記されている
- <!-- verify: grep "watchdog-timeout-spec-seconds" "docs/ja/guide/customization.md" --> `docs/ja/guide/customization.md` の翻訳が同期されている
- <!-- verify: command "bash -n scripts/run-spec.sh && bash -n scripts/run-code.sh && bash -n scripts/run-review.sh && bash -n scripts/run-merge.sh && bash -n scripts/run-issue.sh" --> 5 本の run-*.sh が構文エラーなし
- <!-- verify: command "bats tests/watchdog-defaults.bats" --> bats テストが green（フェーズ別 timeout 解決テストの新規追加含む）
- <!-- verify: command "scripts/check-translation-sync.sh | grep 'customization.md' | grep -q IN_SYNC" --> docs/guide/customization.md と docs/ja/guide/customization.md の翻訳同期が保たれている

### Post-merge

- 次回 `/auto` 実行で `merge` フェーズが 60s 〜 10 分以内に完走し、誤 kill が発生しないことを観察
- 真のストール（commit ゼロ）が発生した場合、該当フェーズの timeout で kill されることを観察

## Notes

- `run-auto-sub.sh` は `load_watchdog_timeout` を使用していない（grep 確認済み）。スコープ外。
- `eval` による間接変数参照は `${!var_name}` に代替可能（どちらも bash 3.2+ 対応）。どちらも許容。
- `get-config-value.sh` は空文字列 default (`""`) をサポート。phase 別キー不在時の空文字判定に利用。
- Issue body の Auto-Resolved Ambiguity Points で `docs/guide/customization.md` 更新と `--fail-if-outdated` の追加は既に自動解決済み。
