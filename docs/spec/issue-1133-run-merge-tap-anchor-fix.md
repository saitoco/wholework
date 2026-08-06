# Issue #1133: run-merge: TAP 失敗カウントを行頭アンカーにし説明文中の not ok 誤検出を解消

## Overview

`scripts/run-merge.sh` の CI `test_result` event emit ロジック (214行目) は、TAP 出力の失敗件数を `grep -c "not ok "` (行頭アンカーなし) で数えている。このため、真の失敗行 (`not ok N description`) だけでなく、合格しているテストの説明文中に `not ok` という部分文字列が偶然含まれる場合まで失敗として誤カウントする。行頭 (GitHub Actions のログ接頭辞を考慮した位置) にアンカーされた判定に修正し、この誤カウントを検知する回帰テストを追加する。

## Reproduction Steps

1. pr route の Issue が merge phase を通過し、CI が全 job SUCCESS (真の failure 0 件) の状態で `run-merge.sh` の CI `test_result` emit ロジック (205-222行目) が実行される
2. `gh run view <run_id> --log` が返す生ログの各行は `<job名>\t<step名>\t<ISO8601タイムスタンプ>Z <TAP本体>` という GitHub Actions 特有の接頭辞を持つ。回帰テスト自身の名前 `test_result: TAP format with not ok lines counts failures correctly` が TAP 出力の説明文として含まれると、ログ行は `...Z ok 963 test_result: TAP format with not ok lines counts failures correctly` の形になる
3. 現行の `grep -c "not ok "` は行頭アンカーがないため、この合格行 (説明文中に `not ok` を含む) にもマッチし `failed=1` を誤って emit する

実測 (Issue #1128 / PR #1131 / run 30618554029、本 Spec 作成時点で `gh run view 30618554029 --log` により再取得・再現確認済み):

```
$ gh run view 30618554029 --log | grep -c "not ok "                                      # 現行実装 (行頭アンカーなし)
1
$ gh run view 30618554029 --log | grep -cE "[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z not ok "  # タイムスタンプ接頭辞直後にアンカー
0
```

## Root Cause

`grep -c "not ok "` は行頭アンカーなしの部分文字列マッチであるため、TAP の真の失敗行だけでなく、合格行の説明文中に偶然 `not ok` という文字列が含まれる場合 (本件では回帰テスト自身の名前) にもマッチする。

さらに、単純な `^` (真の行頭) アンカーを追加するだけでは解決しない。`gh run view --log` が返す実運用ログの各行は必ず `<job>\t<step>\t<timestamp>Z <TAP本体>` という GitHub Actions 特有の接頭辞を持ち (実測確認済み — 対象 run の全 1319 件の TAP 行が例外なくこの形式)、TAP 本体は真の行頭に位置しない。したがって `^` のみのアンカーでは実運用ログの真の失敗行を一切カウントできなくなり (常に `failed=0` に固定される)、より深刻な逆方向のバグを生む。修正は「タイムスタンプ接頭辞の直後」または「(接頭辞なしログ向けに) 真の行頭」のいずれかに `not ok ` がアンカーされている場合のみを数える必要がある。

## Changed Files

- `scripts/run-merge.sh`: 214行目の `_failed` 計算パターンを、行頭アンカーなし `grep -c "not ok "` から、真の行頭または GitHub Actions タイムスタンプ接頭辞直後にアンカーされた `grep -cE "(^|[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z )not ok "` に変更 (bash 3.2+ 互換 — 変更は `grep` 引数のみで、スクリプト側の bash 構文には影響しない)
- `tests/run-merge.bats`: 既存テスト `test_result: TAP format with not ok lines counts failures correctly` (464行目付近) の直後に、合格行の説明文に `not ok` 部分文字列を含むケースが `failed=0` と数えられることを検証する negative case テストを追加

## Implementation Steps

1. `scripts/run-merge.sh:214` を次のように変更する (→ 受入条件 1, 2):
   ```bash
   # Before
   _failed=$(echo "$_log" | grep -c "not ok ") || _failed=0
   # After
   _failed=$(echo "$_log" | grep -cE "(^|[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z )not ok ") || _failed=0
   ```
   `grep -c` + `|| _failed=0` という既存パターン (count=0 でも `grep -c` が exit 1 を返すためのフォールバック、Issue #687 由来) はそのまま維持し、マッチパターンのみを変更する。
2. `tests/run-merge.bats` に以下の negative case テストを追加する (→ 受入条件 3)。既存テスト `test_result: TAP format with not ok lines counts failures correctly` の mock 構造 (`emit-event.sh` mock + `gh run list`/`gh run view --log`/`gh pr view` mock) を踏襲し、`gh run view --log` の mock 出力を `1..1` + `ok 5 some test about not ok lines` (接頭辞なし、説明文に `not ok` を含む合格行 1 件のみ) に差し替える。アサーションは `failed=0` かつ `passed=1`。
3. `bats tests/run-merge.bats` をローカル実行し、追加した negative case (Step 2) と既存の positive case `test_result: TAP format with not ok lines counts failures correctly` (無変更) の両方が pass することを確認する (→ 受入条件 4, 5 の実装側裏付け)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-merge.sh の TAP 失敗カウントが、GitHub Actions のログ接頭辞を考慮したうえで行頭にアンカーされた not ok 行のみを数えるようになっており、テスト説明文中の not ok 部分文字列を失敗として数えない" --> TAP 失敗カウントが行頭アンカー判定になっている
- <!-- verify: file_not_contains "scripts/run-merge.sh" "grep -c \"not ok \"" --> アンカーなしの `grep -c "not ok "` が残っていない
- <!-- verify: rubric "tests/run-merge.bats に、テスト説明文中へ not ok という部分文字列を含む合格行 (例: ok 5 some test about not ok lines) を与えたときに failed=0 と数えられることを検証する negative case テストが追加されている" --> 説明文に `not ok` を含む合格行を失敗として数えない negative case テストが追加されている
- <!-- verify: rubric "tests/run-merge.bats の既存テスト test_result: TAP format with not ok lines counts failures correctly が、真の not ok 行のみを失敗として数える positive case として引き続き pass している" --> 真の失敗行を数える既存の positive case が維持されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストが全て pass する (patch route)

### Post-merge

- `/auto` を pr route の Issue に対して実行し、CI が全 job SUCCESS のときに `.tmp/auto-events.jsonl` の `test_result` event が `failed=0` を記録することを確認する <!-- verify-type: observation event=auto-run -->

## Notes

- **Patch route verify command の自動修正**: Issue triage で Size S と判定され、`.wholework.yml` に `always-pr` が未設定 (デフォルト `false`) のため patch route (直接 main コミット、PR なし) となる。Issue 本文の Pre-merge 受入条件 5 は `<!-- verify: github_check "gh pr checks" "Run bats tests" -->` だったが、patch route では PR が存在せず `gh pr checks` は常に FAIL するため、`modules/verify-classifier.md` § "Patch Route CI Verification Note" の正準パターンに従い `<!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->` に自動修正した (`.github/workflows/` に `dco.yml`/`kanban-automation.yml`/`test.yml` の 3 ファイルが存在するため `--workflow=test.yml` を明示、`--commit=$(git rev-parse HEAD)` は同モジュールの正準形かつ他の既存 Spec 多数 (#795, #724, #721 など) で採用実績のあるパターンを採用し、直近コミット以外の run を誤って参照する競合を避ける)。同内容を Issue 本文にも同期する。
  (auto-resolved: non-interactive mode, model judgment — Issue 本文には 2026-07-31 付けで同種の指摘コメントが既に存在したが、cutoff より前のため `## Consumed Comments` の対象外。本チェックはそのコメントとは独立に Step 10 の機械的チェックとして実行し、結論が一致することを確認した)
- **実 CI ログでの実証**: 対象 run (30618554029) は本 Spec 作成時点でまだ取得可能であり、`gh run view 30618554029 --log` を実際に実行して不具合を実測再現した (詳細は Reproduction Steps 参照)。修正後パターンが実ログに対して正しく `0` 件、既存 bats mock の接頭辞なしログに対して正しく `1` 件を返すことをローカルでも確認済み。
- **`grep -c` + `|| _failed=0` パターンは変更なし**: 前身 Issue #687 の Spec Notes が記録する通り、`grep -c` は count=0 でも exit 1 を返すため `|| echo 0` ではなく `|| _failed=0` を使う必要がある (`|| echo 0` だと stdout が二重になり算術エラーになる)。本 Issue はマッチパターンのみを変更し、このエラーハンドリング部分は踏襲する。
- **Out of Scope の妥当性確認**: Issue 本文の Out of Scope が挙げる `_total` (TAP plan line `1..N`) のパースについて、実 CI ログで `_total=1319` が正しく取得できることを実測確認済み (Changed Files に含めない判断は妥当)。

## Code Retrospective

### Deviations from Design
- N/A — implementation followed Implementation Steps 1–3 exactly as written.

### Design Gaps/Ambiguities
- N/A — the Spec's Reproduction Steps and Root Cause analysis were precise enough that no gap surfaced during implementation. The pattern `(^|[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z )not ok ` was re-verified against both the real CI log line (0 matches, as expected) and a synthetic true-failure line (1 match), confirming the Root Cause section's dual-anchor rationale.

### Rework
- N/A — single-pass implementation; both the local `bats tests/run-merge.bats` run and the full-suite `bats tests/` run (triggered by the behavioral-change detection in Step 9, since `tests/verify-dirty-detection.bats` also references `scripts/run-merge.sh`) passed on the first attempt (1460/1460).

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Changed only the `grep` match pattern in `scripts/run-merge.sh:214`, keeping the `grep -c ... || _failed=0` error-handling idiom untouched, per Spec Notes' explicit instruction not to regress the Issue #687 `|| _failed=0` fix.
- Added the negative-case bats test immediately after the existing positive-case test (`tests/run-merge.bats`) reusing the same mock structure, so the two cases stay adjacent for future readers.

### Deferred Items
- Pre-merge AC #5 (`github_check` CI check) is UNCERTAIN at code-phase completion — the implementation commit has not been pushed to `origin/main` yet (patch route pushes at Worktree Exit). Re-verify after push.
- Post-merge AC (observation: `/auto` pr route run confirming `failed=0` in `.tmp/auto-events.jsonl`) is out of scope for this phase by design (verify-type: observation).

### Notes for Next Phase
- No PR is created for this patch route — after Worktree Exit pushes to `main`, confirm CI (`test.yml`) is green on the resulting commit to resolve the UNCERTAIN AC #5.
- Issue body Pre-merge AC #5 was already pre-corrected to the `gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ...` form before this phase started (see Spec Notes) — no further AC/verify-command sync was needed in this phase.

## Consumed Comments

No new comments since last phase.
