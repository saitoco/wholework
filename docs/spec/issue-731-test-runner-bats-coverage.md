# Issue #731: test: add bats coverage for modules/test-runner.md

## Overview

`modules/test-runner.md` は quality check 実行の中核 module で、`skills/verify/SKILL.md` および `skills/code/SKILL.md` から source されているが、dedicated test が存在しない。

`tests/adapter-resolver.bats` の shallow documentation test パターンに倣い、module の構造と契約用語の存在を確認する bats test を新規作成する。test-runner.md は LLM 実行の手順書 (markdown module) であり実行可能スクリプトではないため、文書構造・契約用語 (PASS/FAIL) の存在確認テストを採用する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved 3 ambiguity points (AC展開方針、markdown module interpretation、post-merge checkbox format) — [issue comment](https://github.com/saitoco/wholework/issues/731#issuecomment-2994706014)

## Changed Files

- `tests/test-runner.bats`: new file — shallow documentation tests for `modules/test-runner.md` (bash 3.2+ compatible)
- `docs/structure.md`: update tests/ file count "84 files" → "85 files"
- `docs/ja/structure.md`: update "84 ファイル" → "85 ファイル" (translation sync per docs/translation-workflow.md)

## Implementation Steps

1. Create `tests/test-runner.bats` — follow the `tests/adapter-resolver.bats` pattern with PROJECT_ROOT + module path setup. Add @test cases covering: `## Purpose`, `## Input`, `## Processing Steps`, `## Output Format` section existence; PASS condition documented; FAIL condition documented. Each @test uses `grep -q "PATTERN" "$TEST_RUNNER"` form. (→ AC1-6)

2. Update file count in `docs/structure.md` and `docs/ja/structure.md`: "84 files" → "85 files" / "84 ファイル" → "85 ファイル" (→ SHOULD-level doc sync)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/test-runner.bats" --> `tests/test-runner.bats` が新規作成されている
- <!-- verify: file_contains "tests/test-runner.bats" "@test" --> bats `@test` ケースが含まれている (test ファイルとして有効)
- <!-- verify: grep "## Processing Steps" "tests/test-runner.bats" --> basic invocation テスト (module 実行フロー構造の検証) を含む
- <!-- verify: grep "PASS" "tests/test-runner.bats" --> fixture pass テスト (PASS 条件ドキュメントの検証) を含む
- <!-- verify: grep "FAIL" "tests/test-runner.bats" --> failure path テスト (FAIL 条件ドキュメントの検証) を含む
- <!-- verify: command "bats tests/test-runner.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green
- <!-- verify: file_contains "docs/structure.md" "(85 files)" --> tests/ file count updated in structure.md
- <!-- verify: grep "85 ファイル" "docs/ja/structure.md" --> tests/ file count updated in Japanese structure.md

### Post-merge

- 次回 test-runner.md を変更する Issue で `bats tests/test-runner.bats` が regression を検出することを観察 <!-- verify-type: manual -->

## Notes

- **Shallow documentation test パターン**: `tests/adapter-resolver.bats` と同じ方針 — LLM 実行 module は動作 mock が困難なため、文書構造・契約用語の存在確認で担保する
- **Pre-merge verification count**: 9 items (Issue 起票済み 7 + docs sync 2); light 上限 5 を超えるが、Issue 側 AC は変更不可のため Notes に記録して続行
- **実装上の注意**: `tests/test-runner.bats` に `## Processing Steps`、`PASS`、`FAIL` の文字列を含む grep 行が必要 (AC3-5 の verify コマンドがこれらを検索するため)
- **Auto-Resolve Log** (Issue コメントより転記):
  1. AC "minimum 3 tests" → 3 カテゴリ別 grep チェックに展開 (count aggregation 回避)
  2. "basic invocation / fixture pass / failure path" → markdown module 向け文書構造テストとして解釈
  3. Post-merge checkbox → `- [ ]` 形式に修正済み
