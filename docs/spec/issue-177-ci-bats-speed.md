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

1. `.github/workflows/test.yml` の `Install bats` ステップに `parallel` を追加: `sudo apt-get install -y bats` → `sudo apt-get install -y bats parallel`
2. `.github/workflows/test.yml` の `Run bats tests` ステップを変更: `run: bats tests/` → `run: bats --jobs 4 tests/`

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/spec/issue-177-ci-bats-speed.md" --> 調査結果（どのテストファイル / ステップが時間消費主因か）が Spec に記録されている
- <!-- verify: grep "--jobs" ".github/workflows/test.yml" --> CI workflow に `--jobs` による並列化施策が実装されている
- <!-- verify: file_exists ".github/workflows/test.yml" --> `.github/workflows/test.yml` が実装施策を反映している
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI が成功している

### Post-merge

- 本 Issue 対応後の直近3回の CI 実行時間が対応前の平均（約540秒）より有意に短縮されていることを GitHub Actions 履歴で確認

## Notes

- **bats バージョン要件**: `--jobs` フラグは bats-core v1.3.0 以降。ubuntu-latest (24.04) の apt パッケージは bats 1.10.0 系であり対応済みと想定。実装前に `bats --version` で確認すること（v1.3.0 未満の場合は npm install -g bats で upgrade）。
- **並列安全性**: `gh-graphql.bats` の `CACHE_DIR` は `$PROJECT_ROOT/.tmp/gh-graphql-cache` の固定パスを使用するが、bats `--jobs` はファイル単位で並列化するため同一ファイル内のテストはシリアル実行される。ファイル間での競合なし。
- **期待される短縮効果**: テスト実行 ~480秒 → ~120〜150秒（65〜75%短縮）。CI 全体 ~540秒 → ~200〜230秒を目標とする。

## Code Retrospective

### Deviations from Design

- `bats --jobs 4` は GNU Parallel (`parallel` コマンド) を必要とするため、`Install bats` ステップに `sudo apt-get install -y parallel` を追加。当初の設計ではコマンド1行の変更のみを想定していたが、依存関係のインストールが追加ステップとして必要だった。

### Design Gaps/Ambiguities

- Notes セクションに「bats バージョン確認」は記載されていたが、GNU Parallel の依存関係については言及がなかった。ローカルテスト時に `parallel: command not found` エラーで判明。

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 調査が詳細で根拠のある設計（321件 × ~1.5秒 の定量分析）になっている。GNU Parallel 依存が spec に記載されていなかった点はコード実装時に発覚し Code Retrospective に記録済み。
- verify コマンドが spec には詳細に記載されていたが（`grep "--jobs"` など）、Issue 本文の受け入れ条件 #2 には verify ヒントが付与されておらず、AI 判断頼みになっていた。Issue 作成・精緻化フェーズで spec の verify コマンドを Issue 条件に反映する運用が改善余地あり。

#### design
- 設計は実装と整合。変更ファイルも1ファイルのみで明確。GNU Parallel 依存の欠落を除けば設計品質は高い。

#### code
- `git log` に同一メッセージのコミットが2件（`d1e6d06`, `0d019ae`）存在する。patch route での再コミット（amend 忘れ or 重複 push）の可能性。実装自体は正しいが、コミット履歴に重複が残った。
- `806394a chore: fix miscalibrated verify hint in spec for issue #177` — spec 内の verify ヒントが実装後に修正されている。spec 作成時点での verify ヒントの精度検証が不十分だった。

#### review
- Patch route（PR なし）のため正式なコードレビューは行われなかった。変更規模（2行変更）からは妥当な選択だが、verify ヒントのミスキャリブレーションは PR レビューがあれば早期発見できた可能性がある。

#### merge
- Patch route: 直接 main へコミット。`closes #177` がコミットメッセージに含まれている（`0d019ae`）。Issue は自動クローズされず `/verify` が必要だった（`HAS_AUTO_CLOSE=false` 相当の設定）。

#### verify
- Pre-merge 3条件すべて PASS。Post-merge 条件1件（verify-type: manual）は CI 実行時間の実測確認のため手動検証が必要。
- Issue 本文の条件 #2 に verify ヒントがなく AI 判断で PASS としたが、spec には `grep "--jobs" ".github/workflows/test.yml"` の verify コマンドが存在しており活用可能だった。Issue 条件と spec verify コマンドの乖離が生じていた。

### Improvement Proposals
- Issue 受け入れ条件の verify ヒントを `/spec` フェーズで spec の verify コマンドから Issue 本文へ反映するステップを追加する（spec にある verify コマンドが Issue に反映されず AI 判断頼みになるケースを防ぐ）
- Spec 実装ステップに外部コマンド依存（今回は GNU Parallel）を記載する規約を追加する（`Notes` ではなく `Implementation Steps` に依存パッケージを明記）
