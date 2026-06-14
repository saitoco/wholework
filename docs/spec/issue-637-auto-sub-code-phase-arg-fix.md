# Issue #637: run-auto-sub code phase argument mismatch fix

## Overview

`run-auto-sub.sh` の `run_phase_with_recovery` 呼び出しで phase 引数が `"code"` のままになっており、`reconcile-phase-state.sh` が有効なフェーズ名 (`code-patch`/`code-pr`) として認識できずに exit 2 で失敗する。その結果、Tier 1 reconcile が常に失敗扱いとなり、本来不要な Tier 2/3 recovery が発動する。

さらに `spawn-recovery-subagent.sh` の retry action では `"$SCRIPT_DIR/run-${PHASE}.sh" "$ISSUE"` のフォームを使用しているため、fix 後に PHASE が `code-patch`/`code-pr` になると存在しないスクリプトを呼び出し、かつ route フラグ (`--patch`/`--pr`) も失われる。

## Reproduction Steps

1. XL Issue の sub-issue として Size S の Issue を `/auto --batch` で実行する
2. code phase が何らかの理由で失敗する (exit ≠ 0)
3. `run_phase_with_recovery "code" ...` → `reconcile-phase-state.sh "code" ...` → unknown phase (exit 2) → Tier 1 判定不能
4. Tier 3 retry action が `run-code.sh $ISSUE` を route フラグなしで再実行 → `code-pr` に fallback → patch route Issue で PR が存在せず再失敗

## Root Cause

`run-auto-sub.sh` の case 文で `run_phase_with_recovery` の第 1 引数 (phase) がすべて `"code"` のまま。`reconcile-phase-state.sh` の dispatcher は `code-patch`/`code-pr` のみ受け入れ、`code` は `*` ケースで exit 2 となる。

`spawn-recovery-subagent.sh` は `"$SCRIPT_DIR/run-${PHASE}.sh"` で runner script を構築するため、`code-patch`/`code-pr` に対応するスクリプトが存在せず、かつ `run-code.sh` に渡すべき route フラグが消失する。

## Changed Files

- `scripts/run-auto-sub.sh`: XS/S case の `run_phase_with_recovery "code"` → `"code-patch"`、M/L case → `"code-pr"` に修正 — bash 3.2+ 互換
- `scripts/spawn-recovery-subagent.sh`: retry case に `code-patch` → `run-code.sh --patch`、`code-pr` → `run-code.sh --pr` のマッピングを追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: patch route (Size S) で `reconcile-phase-state.sh` に `code-patch` が渡されることを検証する回帰テストを追加

## Implementation Steps

1. `scripts/run-auto-sub.sh` XS case (line 177) と S case (line 181): `run_phase_with_recovery "code"` を `run_phase_with_recovery "code-patch"` に変更（→ AC1）

2. `scripts/run-auto-sub.sh` M case (line 185) と L case (line 202): `run_phase_with_recovery "code"` を `run_phase_with_recovery "code-pr"` に変更（→ AC1）

3. `scripts/spawn-recovery-subagent.sh` retry case (line 291-293): `"$SCRIPT_DIR/run-${PHASE}.sh" "$ISSUE"` を以下の case 分岐に置き換える（→ AC2）:

   ```bash
   case "$PHASE" in
     code-patch) "$SCRIPT_DIR/run-code.sh" "$ISSUE" --patch ;;
     code-pr)    "$SCRIPT_DIR/run-code.sh" "$ISSUE" --pr ;;
     *)          "$SCRIPT_DIR/run-${PHASE}.sh" "$ISSUE" ;;
   esac
   ```

4. `tests/run-auto-sub.bats` に回帰テストを追加: Size S かつ run-code.sh が exit 1 する場合に、`reconcile-phase-state.sh` が `code-patch` を第 1 引数で受け取ることを検証する（→ AC3）

   テスト方針:
   - `reconcile-phase-state.sh` を `$1` をログファイルに書き出す mock に差し替え、戻り値は `{"matches_expected":true}` として tier1 recovery に成功させる
   - `run bash "$SCRIPT" 42` 実行後、log ファイルに `code-patch` が含まれることを確認

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh で XS/S (patch route) の case と M/L (pr route) の case でそれぞれ run_phase_with_recovery に code-patch と code-pr を渡すコードが追加されている" --> <!-- verify: grep "code-patch" "scripts/run-auto-sub.sh" --> `run-auto-sub.sh` に `code-patch` が存在し、XS/S case に渡されている
- <!-- verify: grep "code-patch" "scripts/spawn-recovery-subagent.sh" --> `spawn-recovery-subagent.sh` retry action に `code-patch` 対応のマッピングが存在する
- <!-- verify: grep "code-patch" "tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` に `code-patch` を検証する回帰テストが存在する

### Post-merge

- 次回以降の `/auto --batch` 実行で size 再判定経由の patch route Issue が reconcile route mismatch で exit 1 を起こさないことを確認

## Notes

- `run-code.sh` は lines 165-168 で既に `code-patch`/`code-pr` を正しく使用しており変更不要
- `spawn-recovery-subagent.sh` retry case の `*` フォールバック (`run-${PHASE}.sh`) は `review`/`merge` 等の他フェーズで引き続き機能する
- `tests/spawn-recovery-subagent.bats` の既存 retry テストは PHASE=`code` で実行しており、fix 後は `*` フォールバックで動作するため壊れない (テストの更新は follow-up SHOULD)

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- Spec の Step 3 では `spawn-recovery-subagent.sh` の retry case の内部構造に echo を含む形式を示していたが、実装では case ブランチごとに個別の echo を追加した（より明確なログ出力のため）。動作に影響なし。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `run-auto-sub.sh` の XS/S case に `code-patch`、M/L case に `code-pr` を渡すよう 4 箇所を変更
- `spawn-recovery-subagent.sh` の retry case に `code-patch`/`code-pr` 専用分岐を追加し、それ以外は既存の `run-${PHASE}.sh` フォールバックに委ねる設計を維持
- 既存テスト 21 件は全 PASS のまま; 新規回帰テスト 1 件追加 (合計 22 件)

### Deferred Items
- `tests/spawn-recovery-subagent.bats` の既存 retry テスト (PHASE=`code`) は `*` フォールバックで引き続き動作するが、`code-patch`/`code-pr` case の直接カバレッジなし → follow-up SHOULD
- post-merge 観察 AC (auto-run event) はマニュアル確認待ち

### Notes for Next Phase
- `/verify` フェーズでは pre-merge 3 AC の grep チェックが全 PASS であることを確認すること
- post-merge AC (`observation event=auto-run`) は次回 `/auto --batch` 実行時まで検証不可

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- ambiguity 3 件を auto-resolve した判断は妥当。修正対象を `run-auto-sub.sh` + `spawn-recovery-subagent.sh` に絞り、`run-code.sh` の既存正常コードを温存した。
- AC のリファクタ（AC2分割・rubric + grep 補完追加）も verifiability 向上に寄与。タイトル drift 修正（`run-code:` → `run-auto-sub:`）が実装範囲と整合。

#### spec
- spec は code/spec retrospective を含み、AC3 で bats 回帰テスト追加を求める設計が機械検証を担保。
- `spawn-recovery-subagent.sh` の `*` フォールバックを維持しつつ `code-patch`/`code-pr` 専用 case を追加する設計は、他フェーズ（review/merge）の retry 動作を破壊せず最小リスク。

#### code
- 設計と完全一致。`run-auto-sub.sh` 177/181/185/202 の4箇所と `spawn-recovery-subagent.sh` retry case を実装。
- 回帰テスト #21「Size S + run-code.sh exit1: reconcile-phase-state.sh receives code-patch as first arg」を新規追加し、bats 22/22 PASS。

#### review
- patch route のためレビューフェーズなし。rubric + grep 双方の verify command が pre-merge AC を機械検証で carve out。

#### merge
- patch route 直 push。closes #637 で Issue 自動 CLOSE 成立。

#### verify
- pre-merge 3 AC は全 PASS（rubric/grep/bats いずれも green）。
- post-merge AC4 は observation event=auto-run で、size 再判定経由 patch route Issue が発生していない本 run では PENDING。本 fix 自体は size 再判定なしの S 直 patch route で完走したため、本 AC が捕捉したい「size 再判定後の route mismatch」シナリオは観測されていない。

### Improvement Proposals
- `tests/spawn-recovery-subagent.bats` に `code-patch`/`code-pr` の retry case を直接カバーするテスト追加が望ましい（spec で SHOULD として deferred 済み）。本 verify の retro/verify 起票は不要と判断（spec の Deferred Items で既知化されているため）。
