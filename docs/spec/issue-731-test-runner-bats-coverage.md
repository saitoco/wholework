# Issue #731: test: add bats coverage for modules/test-runner.md

## Overview

`modules/test-runner.md` は quality check 実行の中核 module で、`skills/verify/SKILL.md` および `skills/code/SKILL.md` から source されているが、dedicated test が存在しない。

`tests/adapter-resolver.bats` の shallow documentation test パターンに倣い、module の構造と契約用語の存在を確認する bats test を新規作成する。test-runner.md は LLM 実行の手順書 (markdown module) であり実行可能スクリプトではないため、文書構造・契約用語 (PASS/FAIL) の存在確認テストを採用する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved 3 ambiguity points (AC展開方針、markdown module interpretation、post-merge checkbox format) — [issue comment](https://github.com/saitoco/wholework/issues/731#issuecomment-2994706014)

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/731#issuecomment-4804969803
- saito / MEMBER / first-class / ## Acceptance Test Results (Re-run) / https://github.com/saitoco/wholework/issues/731#issuecomment-4805225553
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5200981473
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5212260419
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5225314292
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5229258108
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5235400540
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5246553942
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5255741271
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5296375814
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5304271445
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5310544496
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5327720109
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5341227346
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/731#issuecomment-5354364338
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/731#issuecomment-5354614637
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

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- None: Spec の実装ステップ通りに実装した。`tests/adapter-resolver.bats` パターンを踏襲し 6 @test で構成。

### Design Gaps/Ambiguities
- AC3-5 の verify コマンド (`grep "## Processing Steps" "tests/test-runner.bats"` 等) は test ファイル内にそれらの文字列を含む grep 行が存在することを検証するため、test file の内容が verify コマンドの前提条件になっている。Spec Notes に明記されており問題なし。

### Rework
- None: 1 回のコミットで実装完了。テストは全件 PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `tests/adapter-resolver.bats` の shallow documentation test パターンを採用: LLM 実行 module の動作 mock は困難なため、文書構造・契約用語の存在確認で担保する方針を踏襲した
- @test 名は全て ASCII で記述 (bats multibyte @test 名パースバグ回避、#226 対応)
- 6 @test: Purpose / Input / Processing Steps / Output Format セクション存在確認 + PASS / FAIL 用語確認

### Deferred Items
- CI check (AC7: github_check "gh run list") は push 後に /verify で確認
- Post-merge AC: 次回 test-runner.md 変更時の regression 観察は手動確認

### Notes for Next Phase
- verify phase で AC7 の CI check が green になっていることを確認すること
- 全 pre-merge AC のチェックボックスは AC7 (CI) を除いて確認済み

## Verify Retrospective

### Phase-by-Phase Review

#### verify
- pre-merge AC1-6, AC8-9 PASS。AC7 (CI green) は CI job in_progress のため PENDING。CI 完了後に `/verify 731` 再実行で確認可能。
- 新規 bats テストは local で全 PASS、対象 module の structure ドキュメント (docs/structure.md, docs/ja/structure.md) も同期更新済み。

### Improvement Proposals
- N/A

### 2026-08-20 再確認 (/auto 1417 セッションから、実質初回の post-merge observation 評価)

`/auto 1417` (session `71172-1787214280`) の完了後の event-based observation scan で `event=auto-run` が dispatch された。2026-06-26 の初回判定以降、本条件は12回 (`auto-run`) トリガーされたが、oldest-first dispatch cap が常に #562/#589/#590/#724 で占有され (`#1406` が指摘する構造的問題の実例)、一度も実際の `/verify` 評価に到達していなかった。今回が実質的な初回再評価。

2026-06-26 以降 `modules/test-runner.md`/`tests/test-runner.bats` を変更した6コミットを調査したが、既存スイートが FAIL してから修正で green 化した regression 検出の証跡は見つからず (直接変更した2コミットはいずれも新規テストケース追加)。AC のフォールバック規定に従い SKIPPED を維持。

#### Improvement Proposals (再評価分)
- N/A — #1406 が既に同じ構造的問題 (oldest-first dispatch cap による特定 Issue の恒久占有) をカバーしているため、重複起票はしない。本エントリはその実例として #1406 に有用な追加傍証となる。
