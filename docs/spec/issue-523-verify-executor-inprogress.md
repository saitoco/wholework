# Issue #523: verify-executor: gh run list 形式の github_check で in_progress を PENDING 検出

## Overview

`modules/verify-executor.md` の `github_check` 処理に、`gh run list --json conclusion` 形式で CI run が in_progress の間（conclusion=null → 空文字列）に PENDING を返す検出ロジックを追加する。これにより、merge 直後の `/verify` 実行で CI 完走前に誤って FAIL/UNCERTAIN 判定される問題を解消する。

## Reproduction Steps

1. `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` の verify command を持つ Issue に対して merge 直後（CI 実行中）に `/verify` を実行する
2. CI run が in_progress のため `conclusion` は null → `gh run list --jq '.[0].conclusion'` の出力は空文字列
3. 現在の処理: 出力に `in_progress` リテラルが含まれないため PENDING と判定されず、expected_value `success` との不一致で FAIL/UNCERTAIN となる（Issue #505 の verify retrospective で観測）

## Root Cause

`github_check` の PENDING 検出ロジックが "出力に `in_progress` が含まれるか" のリテラル検出のみ。

`gh pr checks` 形式では in_progress 中に `in_progress` リテラルが出力に現れるが、`gh run list --json conclusion` 形式では CI run が in_progress の間 `conclusion` フィールドが null → `--jq '.[0].conclusion'` の出力が空文字列となる。リテラル検出では空文字列をカバーできず、誤って FAIL/UNCERTAIN 判定となる。

## Changed Files

- `modules/verify-executor.md`: `github_check` 変換表エントリ内の PENDING 検出ロジックに「`--json conclusion` 形式の空文字列出力 → PENDING」条件を追加（safe モード・full モード両方）

## Implementation Steps

1. `modules/verify-executor.md` の `github_check` 変換表エントリを編集し、safe モードの PENDING 検出 "If output contains `in_progress` → **PENDING** ..." の直後に以下を追記する（→ AC1, AC2）:
   - 「Also, if `gh_command` contains `--json conclusion` AND output is empty string → **PENDING** (detail: "CI run conclusion is null (in_progress); re-verify after CI completes")」
   
   また full モードの記述「Same `in_progress` detection and display name fallback apply in full mode」を更新し、同様の空文字列 PENDING 検出が full モードにも適用されることを明示する。

## Verification

### Pre-merge

- <!-- verify: grep "in_progress" "modules/verify-executor.md" --> `modules/verify-executor.md` の `github_check` 説明に in_progress / PENDING 検出に関する記述がある
- <!-- verify: rubric "modules/verify-executor.md の github_check 処理が、gh run list --json conclusion 形式で CI run が in_progress の間（conclusion が空）に PENDING を返すよう記述されている（status フィールド参照、または空 conclusion を PENDING として扱う旨の明示）" --> gh run list 形式の in_progress→PENDING 検出が明文化されている

### Post-merge

- CI が in_progress の間に `/verify` を実行した際に `github_check "gh run list ... --json conclusion ..."` が FAIL/UNCERTAIN ではなく PENDING を返すことを confirm する（Issue #505 のような実事例で動作確認）

## Notes

なし
