# Issue #724: spec-test-guidelines: base/head 比較 bats テストで branch-specific marker file パターンを追加

## Overview

`scripts/pre-merge-check.sh` の bats テスト実装中に、PRE_EXISTING (base=FAIL / head=FAIL) と CLEAN (base=PASS / head=PASS) シナリオで base と head が同一コンテンツになり `git commit` が空コミットエラーで失敗した。この問題は `_setup_feature_branch` に branch-specific marker file を追加することで回避できたが、Spec 段階でこのパターンを認識できれば code rework を防げた。

`skills/issue/spec-test-guidelines.md` に「git base/head 比較テストでは branch-specific marker file を追加する」パターンを追加することで、将来の git diff ベース比較ロジックの bats テスト設計時にこの問題を Spec 段階で予防できるようにする。

## Changed Files

- `skills/issue/spec-test-guidelines.md`: `## base/head 比較 bats テスト` 節を追加 — 空コミット回避用 branch-specific marker file パターンと適用シナリオ表を記述 (bash 3.2+ compatible: local 変数・echo のみ使用)

## Implementation Steps

1. `skills/issue/spec-test-guidelines.md` の末尾に `## base/head 比較 bats テスト` 節を追加する (→ AC1, AC2, AC3):
   - 節見出し: `## base/head 比較 bats テスト`
   - `空コミット` 回避の rationale と `git commit` 失敗シナリオの説明
   - `_setup_feature_branch` 関数の bash 実装例 (`marker-${branch}.md` ファイルを追加)
   - PRE_EXISTING / CLEAN シナリオで同一コンテンツになる旨の説明と `marker-` パターンが必要なシナリオ一覧表
   - 適用対象: git diff ベースの比較ロジック (`pre-merge-check.sh`、将来の diff ベーススクリプト)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "base/head 比較 bats テスト" --> `skills/issue/spec-test-guidelines.md` に base/head 比較 bats テスト節が追加されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "marker-" --> branch-specific marker file pattern が記述されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "空コミット" --> 空コミット回避の rationale が記述されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) bats 全件 green (patch route)

### Post-merge

- 次回 git diff ベース比較ロジックの Spec で `base/head 比較 bats テスト` 節が参照され、code phase で marker file 追加 rework がゼロになることを確認 <!-- verify-type: manual -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: post-merge verify-type を `observation event=spec` から `manual` に修正、post-merge 条件に `- [ ]` チェックボックスを追加 / [#issuecomment-4758917559](https://github.com/saitoco/wholework/issues/724#issuecomment-4758917559)

## Notes

- 対象ファイル `skills/issue/spec-test-guidelines.md` は現時点で存在確認済み (domain file, type: domain, skill: issue)
- 既存セクション: Behavior Test Recommendation Guidelines / github_check パターン / SKILL.md verify commands / 境界値テスト / validate-skill-syntax.py 個別指定 / PoC・計測系 AC 設計ガイドライン
- 新節は末尾に追加する (既存セクションとの依存関係なし)
- `skills/` 以下のファイルは `docs/ja/` 翻訳対象外のため translation sync 不要
- テストファイル (`tests/pre-merge-check.bats`) は変更なし — 実装済みのパターンをガイドラインとして文書化するのみ
- Issue Retrospective で指摘の post-merge verify-type は Issue body 上で既に `manual` に更新済み
