# Issue #517: verify-executor: github_check の gh pr checks を post-merge /verify で merged PR 番号に解決するフォールバックを追加

## Overview

`/verify` の post-merge フェーズ（Step 8a）で `github_check "gh pr checks"` ヒントを検証する際、`gh pr checks` コマンドに PR 番号が注入されないため、verify worktree ブランチ（`verify/issue-N`）上で実行すると PR を見つけられず FAIL/UNCERTAIN になる問題を修正する。`modules/verify-executor.md` の `github_check` ハンドラで、コマンドが `gh pr checks`（明示的 PR 番号なし）かつ呼び出しコンテキストの `PR_NUMBER` が非空の場合に PR 番号を注入してから実行するフォールバックを追加する。

## Reproduction Steps

1. pr route の Issue を merge する
2. `/verify N` を実行（post-merge モード）
3. Issue の受入条件に `<!-- verify: github_check "gh run list --workflow=test.yml" "Run bats tests" -->` が含まれる
4. verify SKILL.md Step 2 で `PR_NUMBER` が解決済み（非空）であるにもかかわらず、verify-executor.md が `gh pr checks` をそのまま実行
5. verify worktree ブランチ `verify/issue-N` に PR が紐づいていないため `gh pr checks` が失敗 → FAIL/UNCERTAIN の誤判定

## Root Cause

`modules/verify-executor.md` の `github_check` ハンドラが `gh_command` をそのままの文字列で Bash 実行する設計で、呼び出し元（verify SKILL.md Step 2）が解決済みの `PR_NUMBER` を `gh pr checks` コマンドに注入していない。

- verify SKILL.md Step 5 の patch route 検出は「PR_NUMBER が空かつ `gh pr checks` を含む」場合のみ処理し、PR_NUMBER が非空（pr route）のケースは素通りする
- verify-executor.md は Input として `PR_NUMBER` を受け取る設計だが、`github_check` ハンドラ内でこの値を使用していない

## Changed Files

- `modules/verify-executor.md`: `github_check` ハンドラの translation table 行に PR number injection（pre-run）ロジックを追加 — bash 3.2+ 互換の Bash 記法で記述

## Implementation Steps

1. `modules/verify-executor.md` の translation table `github_check` 行で、「If allowlist matches → run `gh_command` in Bash」の直前（safe モード）および「`full` → no restrictions; run `gh_command` in Bash」の直前（full モード）に、以下の **PR number injection（pre-run）** 処理を追加する（→ AC 1）:

   - `gh_command` が `gh pr checks` で始まり、かつ `gh pr checks` 直後のトークンが整数ではない（明示的 PR 番号を持たない）場合
   - かつ呼び出しコンテキストの `PR_NUMBER` が非空の場合
   - → `gh_command` を `gh pr checks $PR_NUMBER`（残りの引数を末尾に保持）に書き換える
   - Details 列に `"PR #N injected into gh pr checks command"` を記録する
   - safe モード・full モード両方に適用する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の github_check ハンドラが、PR 番号引数を持たない `gh pr checks` コマンドに対して、post-merge コンテキストで解決済みの merged PR 番号（PR_NUMBER もしくは gh pr list --search 'closes #N' --state merged による解決結果）を注入してから実行するフォールバックを実装しており、verify worktree ブランチに PR が無くても誤 FAIL/UNCERTAIN にならない" --> post-merge での PR 番号解決・注入フォールバックが実装されている
- <!-- verify: file_contains "modules/verify-executor.md" "PR number injection" --> `verify-executor.md` の `github_check` ハンドラに PR number injection ロジックの記述が含まれる
- <!-- verify: github_check "gh run list --workflow=test.yml" "Run bats tests" --> CI の bats テストが green
- <!-- verify: github_check "gh run list --workflow=test.yml" "Validate skill syntax" --> CI の skill 構文検証が green

### Post-merge

- pr route の Issue で merge 後に `/verify N` を実行し、`github_check "gh pr checks" "<job name>"` ヒントが merged PR を参照して PASS することを確認 <!-- verify-type: opportunistic -->

## Notes

- **Auto-resolved ambiguities**（Issue body に記載済み）:
  - 実装箇所 = `modules/verify-executor.md` の `github_check` ハンドラ（`verify SKILL.md Step 5` 前処理ではない）。根拠: verify-executor.md が既に `PR_NUMBER` を Input として受け取る設計；Issue #515 spec の verify retrospective が "verify-executor の github_check ハンドラ" と明示特定；SKILL.md Step 5/8a は共に verify-executor.md に委譲するため verify-executor.md 修正で両ステップをカバー
  - 適用モード = safe/full 両モード（PR_NUMBER が利用可能な場合）。根拠: `gh pr checks` は safe モードの allowlist に含まれており、safe モードでも同様の誤判定が発生し得る

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- Step 10 verify command sync: Spec の verify コマンド（2件）が `gh pr checks` のままだった（Reproduction Steps 記述と verify コメントの 2 箇所）。Python replace(..., 1) が最初の出現のみ置換したため 1 件が残存。2 回目の replace で対応。
