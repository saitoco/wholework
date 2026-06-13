# Issue #592: detect-wrapper-anomaly: silent-no-op false-positive を抑制 (reconcile-success gate + phase 名拡張 + 検出窓拡大)

## Overview

`scripts/detect-wrapper-anomaly.sh` の silent-no-op 検出ロジックに 3 つのギャップがあり、`/auto --batch` 実行中に false-positive が連続発生（#576, #580）した。

1. **reconcile 結果を無視**: ログ内に `"matches_expected":true` と `"commits_found":true` が存在しても anomaly detector はこれらを参照せず独自判定していた。
2. **phase 名のミスマッチ**: `run-auto-sub.sh` が渡す phase 名は `"code"` だが、origin チェック分岐は `"code-patch"` のみで発動していた。
3. **検出窓のサイズが小さい**: `git log --oneline -5` のみで、worktree merge 等の派生コミットが続くとターゲット commit がウィンドウ外に漏れる可能性があった。

## Reproduction Steps

1. `/auto --batch` で patch-route Issue を処理する
2. `run-auto-sub.sh` が `--phase code` で `detect-wrapper-anomaly.sh` を呼び出す
3. ログには `"matches_expected":true` と `"commits_found":true`（reconcile 成功確認済み）が存在する
4. exit code は 0、ログにも成功フレーズが含まれる
5. anomaly detector は reconcile 結果を無視し、local git log -5 にコミットが見つからないと silent-no-op を発火する

## Root Cause

`scripts/detect-wrapper-anomaly.sh` line 89-107 の silent-no-op 検出ブロックが、`run-code.sh` の reconcile 結果（`reconcile-phase-state result: {...,"matches_expected":true,...,"commits_found":true}`）を参照せずに独立して判定しているため。reconcile-first authority が確立されていない。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: 3 修正 — reconcile-success gate 追加、phase 名拡張、検出窓拡大 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: 2 変更 — 既存 mock の `-5` → `-20` 更新、false-positive 再現テスト追加

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `elif [[ "$EXIT_CODE" == "0" ]]; then` ブロック冒頭（既存の success phrase 検索 `if grep -qiE "完了しました|..."` の直前）に reconcile-success gate を追加する: ログに `"matches_expected":true` と `"commits_found":true` の両方が存在する場合は silent-no-op 検出をスキップする（reconcile-first authority）。(→ AC1, AC2)

2. `scripts/detect-wrapper-anomaly.sh` の同ブロック内で 2 点修正する: (a) line 93 の phase 名条件 `[[ "$PHASE" == "code-patch" ]]` を `[[ "$PHASE" == "code-patch" || "$PHASE" == "code" ]]` に拡張する（`run-auto-sub.sh` が渡す `"code"` phase でも origin チェックが発動）; (b) local check `git log --oneline -5` および origin check `git log origin/main --oneline -5` の両方を `git log --oneline -20` / `git log origin/main --oneline -20` に拡張する。(→ AC3, AC4)

3. `tests/detect-wrapper-anomaly.bats` を 2 点更新する: (a) line 215 の既存 mock パターン `"log origin/main --oneline -5"` を `"log origin/main --oneline -20"` に更新する（Step 2 の検出窓拡大に追随、これを行わないと当該テストが失敗する）; (b) reconcile-confirmed-success の false-positive 再現テストを追加する — ログに `"matches_expected":true` + `"commits_found":true` + 成功フレーズを含む場合に exit_code=0・git mock 空返し でも output が空（suppressed）になることを確認する。(→ AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: grep "matches_expected.:true" "scripts/detect-wrapper-anomaly.sh" --> reconcile-success gate（`matches_expected:true` チェック）が `scripts/detect-wrapper-anomaly.sh` に追加されている
- <!-- verify: grep "commits_found.:true" "scripts/detect-wrapper-anomaly.sh" --> reconcile-success gate（`commits_found:true` チェック）が `scripts/detect-wrapper-anomaly.sh` に追加されている
- <!-- verify: grep "PHASE.*code-patch.*code\|PHASE.*code.*code-patch" "scripts/detect-wrapper-anomaly.sh" --> phase 名拡張（`"code-patch"` または `"code"`）が反映されている
- <!-- verify: grep "git log --oneline -2[0-9]" "scripts/detect-wrapper-anomaly.sh" --> 検出窓が拡大されている（-20 以上）
- <!-- verify: grep "matches_expected.*true" "tests/detect-wrapper-anomaly.bats" --> false-positive 再現テスト（reconcile が `matches_expected:true` を確認済みの場合に silent-no-op を抑制）が `tests/detect-wrapper-anomaly.bats` に追加されている
- <!-- verify: command "bats tests/detect-wrapper-anomaly.bats" --> 既存テストが green（false-positive 再現テストの追加を含む）

### Post-merge

- 次回の `/auto --batch` 実行で reconcile が成功確認済みの code phase に対して silent-no-op false-positive が発火しないことを観察 <!-- verify-type: opportunistic -->

## Notes

- Step 3(a) の既存 mock 更新（`-5` → `-20`）は Issue AC には明記されていないが、Step 2 の窓拡大に伴い `bats tests/detect-wrapper-anomaly.bats` を green に保つために必須。
- Step 2(a) の phase 名拡張（`"code"` を追加）は PR route の code phase でも発動する。PR route では commit が origin/main ではなく feature branch に push されるため、origin/main 検索では `_found_on_origin=false` になる可能性がある。ただし reconcile-success gate（Step 1）が優先されるため、reconcile 出力が存在する通常ケースでは false-positive は発生しない。reconcile 出力が存在しない例外ケースでの影響は許容範囲内と判断（Issue #592 の原因は reconcile gate の欠如であり phase 名拡張は secondary fix）。
- 検出窓の拡大は local check（`git log --oneline`）と origin check（`git log origin/main --oneline`）の両方に適用する。Issue body は line 91（local check）のみ言及しているが、origin check も同様の問題があるため両方更新する。

## Code Retrospective

### Deviations from Design
- None (implementation exactly matched the Spec steps)

### Design Gaps/Ambiguities
- The Spec correctly noted that the `elif` structure for the reconcile-success gate must be nested inside `elif [[ "$EXIT_CODE" == "0" ]]; then`, not as a top-level `if`. The implementation followed this correctly but required careful reading of the existing code structure.

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used `elif` (not a nested `if`) for the reconcile-success gate to integrate cleanly with the existing `elif [[ "$EXIT_CODE" == "0" ]]; then` block without restructuring the entire pattern-matching chain.
- Applied `-20` window to both local and origin/main checks for consistency, even though the Issue body only mentioned the local check.
- Added the false-positive reproduction test with a log that includes BOTH `matches_expected:true` AND a success phrase ("commit and push") to make the suppression actually testable (a test with only reconcile data and no success phrase would pass trivially without the gate).

### Deferred Items
- PR route corner case: when reconcile output is absent and phase is `"code"`, origin/main check will now run but may yield `_found_on_origin=false` for feature branches. Accepted as low-impact since reconcile gate takes priority in normal runs.
- Opportunistic verification (post-merge observation) deferred to the next `/auto --batch` run per the Post-merge AC.

### Notes for Next Phase
- All 6 pre-merge ACs verified PASS; bats tests 26/26 green.
- No documentation changes needed (`detect-wrapper-anomaly.sh` is not mentioned in README or workflow docs).
- The fix is purely internal to the anomaly detection script — no interface changes, no new flags.
