# Issue #177: CI bats test execution time shortening

## Overview

CI/CD ワークフロー (`test.yml`) の bats テスト実行時間が約540秒（約9分）に達している。調査の結果、30ファイル・321件のテスト（範囲: `tests/*.bats` 全ファイル、`grep -c "@test"` 合算）をシリアル実行していることが主因（約1.5秒/テスト × 321 ≈ 480秒）。`bats --jobs 4` による並列実行を導入し、テスト実行時間の60〜70%短縮を目標とする。

**調査結果（主因特定）:**

| 要因 | 推定時間 |
|-----|---------|
| bats テストのシリアル実行（321件 × ~1.5秒/件） | ~480秒 |
| apt-get update + install bats | ~30〜60秒 |
| claude-watchdog.bats sleep テスト（4件 × 2-3秒） | ~9秒 |
| gh-graphql.bats キャッシュ TTL テスト（sleep 2 × 1件） | ~2秒 |
| **合計** | **~540秒** |

`bats --jobs 4` はファイル単位の並列実行（30ファイル / 4ワーカー ≈ 8ファイル/ワーカー × ~12秒/ファイル ≈ 120〜150秒）。

## Changed Files

- `.github/workflows/test.yml`: Run bats tests ステップを `bats tests/` → `bats --jobs 4 tests/` に変更

## Implementation Steps

1. `.github/workflows/test.yml` の `Run bats tests` ステップを変更: `run: bats tests/` → `run: bats --jobs 4 tests/` (→ 受け入れ基準 B, C)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/spec/issue-N-*.md" --> 調査結果（どのテストファイル / ステップが時間消費主因か）が Spec に記録されている
- <!-- verify: grep "--jobs" ".github/workflows/test.yml" --> CI workflow に `--jobs` による並列化施策が実装されている
- <!-- verify: file_exists ".github/workflows/test.yml" --> `.github/workflows/test.yml` が実装施策を反映している
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI が成功している

### Post-merge

- 本 Issue 対応後の直近3回の CI 実行時間が対応前の平均（約540秒）より有意に短縮されていることを GitHub Actions 履歴で確認

## Notes

- **bats バージョン要件**: `--jobs` フラグは bats-core v1.3.0 以降。ubuntu-latest (24.04) の apt パッケージは bats 1.10.0 系であり対応済みと想定。実装前に `bats --version` で確認すること（v1.3.0 未満の場合は npm install -g bats で upgrade）。
- **並列安全性**: `gh-graphql.bats` の `CACHE_DIR` は `$PROJECT_ROOT/.tmp/gh-graphql-cache` の固定パスを使用するが、bats `--jobs` はファイル単位で並列化するため同一ファイル内のテストはシリアル実行される。ファイル間での競合なし。
- **期待される短縮効果**: テスト実行 ~480秒 → ~120〜150秒（65〜75%短縮）。CI 全体 ~540秒 → ~200〜230秒を目標とする。
