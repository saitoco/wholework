# Issue #687: scripts: run-merge.sh の CI log bats summary parse 失敗を解消 (TAP 形式対応)

## Overview

`scripts/run-merge.sh` の CI test_result emit ロジックが、`gh run view --log` 出力の bats TAP 形式
(`1..N` plan line + `ok N / not ok N` per-test lines) を parse できていない。
`bats --jobs N` による並列実行では summary 行 (`N tests, M failures`) が出力されず、
毎回 "no bats summary found" warning が出て `source=ci` 付き `test_result` event が emit されない。
TAP 形式対応 parser に置換して正常に emit されるようにする。

## Reproduction Steps

1. PR route で `/auto merge` を実行
2. `run-merge.sh` 内で `gh run view --log` の出力を `grep -E "[0-9]+ tests?, [0-9]+ failures?"` でフィルタ
3. bats が `--jobs $(nproc)` で並列実行されているため summary 行が存在せずマッチしない
4. stderr に `"Warning: run-merge.sh: gh run view ... --log: no bats summary found"` が出力される
5. `source=ci` 付き `test_result` event が `.tmp/auto-events.jsonl` に emit されない

## Root Cause

`scripts/run-merge.sh:156` の parser が **sequential bats 実行の summary 行** (`N tests, M failures`) を前提にしている。
GitHub Actions CI では `bats --jobs $(nproc)` で並列実行するため TAP 形式に切り替わり、
summary 行は出力されない。TAP 形式の特徴:
- plan line: `1..N` (N = 総テスト数)
- per-test line: `ok N <desc>` または `not ok N <desc>`
- summary 行なし

修正方針: `_bats_summary` パターン検索を廃止し、TAP plan line と `not ok` カウントから
passed/failed を計算する parser に置換する (Issue 本文 候補 A)。

## Changed Files

- `scripts/run-merge.sh`: lines 156-163 — TAP 非対応 parser を TAP 対応 parser に置換 — bash 3.2+ 互換
- `tests/run-merge.bats`: `@test "test_result: ..."` の gh mock を TAP 形式に更新; TAP parse の regression test を追加 — bash 3.2+ 互換

## Implementation Steps

1. **`scripts/run-merge.sh` TAP parser 置換** (→ AC1, AC2, AC3)

   lines 156-163 を以下に置換:
   ```bash
   _log=$(gh run view "$_run_id" --log 2>/dev/null || true)
   _total=$(echo "$_log" | grep -oE "1\.\.[0-9]+" | grep -oE "[0-9]+$" | head -1 || echo 0)
   _failed=$(echo "$_log" | grep -c "not ok ") || _failed=0
   if [[ "${_total:-0}" -gt 0 ]]; then
     _passed=$((_total - _failed))
     emit_event "test_result" "phase=merge" "framework=bats" "source=ci" "passed=${_passed}" "failed=${_failed}" "run_id=${_run_id}"
   else
     echo "Warning: run-merge.sh: gh run view ${_run_id} --log: TAP plan line (1..N) not found" >&2
   fi
   ```

   ポイント:
   - `grep -oE "1\.\.[0-9]+"` は TAP plan `1..854` にマッチ (タイムスタンプ付き行でも `^` 不要)
   - `grep -c "not ok "` は count を出力して count=0 時に exit 1 → `|| _failed=0` で安全にハンドル
   - `set -euo pipefail` 環境で `|| _failed=0` は compound command のため `set -e` abort しない

2. **`tests/run-merge.bats` テスト更新** (→ AC4, AC5)

   a. 既存 `@test "test_result: emit_event called with source=ci after merge"` の gh mock を更新:
   `gh run view --log` レスポンスを TAP 形式に変更:
   ```bash
   if [[ "$1" == "run" && "$2" == "view" && "$*" == *"--log"* ]]; then
     echo "1..5"
     echo "ok 1 first test"
     echo "ok 2 second test"
     echo "ok 3 third test"
     echo "ok 4 fourth test"
     echo "ok 5 fifth test"
     exit 0
   fi
   ```
   既存 assertion (`grep -q "source=ci" "$EMIT_LOG"`) はそのまま維持。

   b. 新規テスト追加 — TAP 形式 regression test (ファイル末尾に追加):
   ```bash
   @test "test_result: TAP format with not ok lines counts failures correctly" {
     # ...  (emit_event mock + gh mock with not ok lines + verify failed count)
   }
   ```
   gh mock は `1..3` plan + `ok 1` + `not ok 2 failing` + `ok 3` を返し、
   emit log に `failed=1` と `passed=2` が含まれることを確認。

## Verification

### Pre-merge

- <!-- verify: grep "1\\.\\.|not ok|--formatter" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に TAP 形式 (`1..N` / `not ok`) parser または `--formatter junit` fallback のいずれかが実装されている
- <!-- verify: rubric "scripts/run-merge.sh が CI log の bats TAP 形式出力 (1..N plan line + ok/not ok per test) を parse して passed/failed count を抽出し、source=ci 付き test_result event を emit する。'N tests, M failures' summary 行が存在しなくても正常動作する" --> rubric 基準を満たす
- <!-- verify: grep "source=ci" "scripts/run-merge.sh" --> `emit_event` 呼び出しに `source=ci` が含まれている (rubric 補足)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存 bats テストが CI で green
- <!-- verify: grep "TAP|1\\.\\.|not ok" "tests/run-merge.bats" --> CI log の TAP 形式 parse の regression test が追加されている

### Post-merge

- 次回 pr route `/auto` 完走時に `.tmp/auto-events.jsonl` で `source=ci` 付き `test_result` event が emit されることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- **Issue 本文提案 regex の修正**: Issue 候補 A の `grep -oE "^1\.[0-9]+"` はバグ:
  (1) `^` anchor は `gh run view --log` のタイムスタンプ付き行に非マッチ。
  (2) `1\.[0-9]+` は TAP plan `1..854` にマッチしない (`1.` の次が数字でなく `.`)。
  正しくは `1\.\.[0-9]+` (ドット2つ) かつ `^` なし。Spec では修正済み。
  (auto-resolved: non-interactive mode, model judgment)
- **`grep -c` + `|| _failed=0` パターン**: `grep -c` は count=0 でも `0` を stdout に出力し exit 1。
  `|| echo 0` パターンだと stdout が `"0\n0"` になり算術エラーになるため `|| _failed=0` を使用。
  (auto-resolved: non-interactive mode, model judgment)
- **doc-checker**: `scripts/` および `tests/` のみの変更のため docs/structure.md 等への文書更新不要。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #688 を squash merge で main にマージ（no conflicts、CI green、review approved）
- BASE_BRANCH=main のため `closes #687` による Issue 自動クローズが機能する
- non-interactive モードで実行、ambiguity なし

### Deferred Items
- Post-merge AC（次回 `/auto` 完走時の `source=ci` event 確認）は observation 型で verify がスキップする
- ブランチ削除済み（`--delete-branch` オプション使用）

### Notes for Next Phase
- Issue #687 は merge 完了後に自動クローズ済み（`closes #687` + BASE_BRANCH=main）
- verify で確認すべき Pre-merge AC は全て PASS 済み（review phase で確認完了）
- Post-merge AC（`source=ci` event の emit 確認）は observation 型のため verify では skip される

## Code Retrospective

### Deviations from Design
- None. Spec の実装ステップを忠実に実行した。Issue 本文提案の regex バグ (Spec Notes 参照) は Spec 段階で既に修正されており、コード実装時に改めて気づくことはなかった。

### Design Gaps/Ambiguities
- None. Spec Notes が `grep -c` + `|| _failed=0` パターンの理由を事前に説明しており、実装中に迷いは生じなかった。

### Rework
- None.

## review retrospective

### Spec vs. Implementation Divergence Patterns

Spec と実装の間に乖離なし。Spec Notes が `grep -c "not ok "` + `|| _failed=0` パターンの理由（`grep -c` は count=0 で exit 1 → `|| echo 0` だと stdout が二重になり算術エラー）を事前に記述しており、実装との齟齬が生じにくい構成だった。TAP 正規表現 (`grep -oE "1\.\.[0-9]+"`) も Issue 候補 A のバグを Spec 段階で修正済みで、コードレビューで再発見する必要がなかった。

### Recurring Issues

Nothing to note. 変更は `scripts/run-merge.sh` + `tests/run-merge.bats` の 2 ファイルに限定されており、単一パターンの parser 置換。繰り返し発生した問題はない。

### Acceptance Criteria Verification Difficulty

AC4 (`github_check "gh pr checks" "Run bats tests"`) のみ事前に `[ ]` であり、CI green 待ちとして deferred されていた。レビュー時に CI SUCCESS を確認して PASS に更新。他の 4 つの AC（`grep`/`rubric` 系）は verify コマンドが明確で UNCERTAIN なし。全体として verify コマンドの精度は高く、manual 判断不要だった。
