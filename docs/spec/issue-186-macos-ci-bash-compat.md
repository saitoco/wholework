# Issue #186: ci: macOS 環境での bash 互換性テストを CI に追加

## Overview

`.github/workflows/test.yml` に macOS ランナーを使用したジョブを追加し、`scripts/check-translation-sync.sh` を macOS 環境で実行することで、bash 3.2 互換性の問題を CI で早期に検出できるようにする。

背景: Issue #173 の verify retrospective で `check-translation-sync.sh` が `mapfile`（bash 4+）を使用していたため macOS system bash（3.2）で動作しない問題が発見された。現在の CI は ubuntu-latest のみで実行されており、macOS 環境での bash 互換性テストが存在しない。

## Changed Files

- `.github/workflows/test.yml`: `macos-shell` ジョブを追加（`runs-on: macos-latest`、`bash scripts/check-translation-sync.sh` を実行）
- `docs/structure.md`: `test.yml` の説明に macOS shell compatibility テストの記述を追記

## Implementation Steps

1. `.github/workflows/test.yml` に `macos-shell` ジョブを追加する（→ 受入条件1, 2）
   - 既存の `check-forbidden-expressions` ジョブの後に追記
   - `runs-on: macos-latest` を指定
   - `actions/checkout@v4` で checkout するステップを追加
   - `bash scripts/check-translation-sync.sh` を実行するステップを追加（ステップ名: "Run shell scripts on macOS"）
2. `docs/structure.md` の `test.yml` 説明を更新する（after 1）（→ ドキュメント一貫性）
   - 変更前: `runs bats tests, \`validate-skill-syntax.py\`, and forbidden expressions check on push/PR`
   - 変更後: `runs bats tests, \`validate-skill-syntax.py\`, forbidden expressions check, and macOS shell compatibility test on push/PR`

## Verification

### Pre-merge

- <!-- verify: grep "macos" .github/workflows/test.yml --> `macos-latest` ランナーを使用したジョブが追加されている
- <!-- verify: grep "check-translation-sync" .github/workflows/test.yml --> `scripts/check-translation-sync.sh` が macOS ジョブ内で実行される
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の最新実行が成功している

### Post-merge

- GitHub Actions の Tests タブに macOS ジョブ (`macos-shell`) が表示される
- `/verify 186` で受入条件が確認できる

## Notes

- `docs/ja/structure.md` は `/doc translate` によって生成される翻訳ミラーのため、今回の変更対象外。英語原文 (`docs/structure.md`) を更新することで次回の翻訳実行時に反映される。
- `check-translation-sync.sh` はすでに `mapfile` から `while IFS= read -r` 形式に修正済み（Issue #173 での対応）。今回は macOS CI 追加のみが対象。
- Issue body の受入条件は2件、Spec の Pre-merge 検証は3件（github_check を追加）。github_check はGitHub Actionsワークフロー変更のSHOULD制約（#73参照）に従い意図的に追加。

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の受入条件は2件だったが、Spec で `github_check` による CI 実行確認（3件目）を追加した。Issue と Spec の条件数が一致していないが、これは意図的な追加であり有効な判断。

#### design
- 実装ステップが明確で変更対象ファイルが2件（`test.yml`、`docs/structure.md`）と最小限。設計どおりに実装された。

#### code
- 1コミット（`6462580`）で完結。fixup/amend なし、手戻りゼロ。シンプルな変更に対して理想的な実装フロー。

#### review
- パッチルートのため PR レビューなし。変更規模が小さく（CIジョブ追加のみ）、レビュースキップが妥当な判断。

#### merge
- パッチルート（main への直接コミット）。コンフリクトなし。

#### verify
- 2件の `grep` 検証コマンドがともに PASS。verify コマンドが実装内容と正確に対応しており、検証の精度が高い。

### Improvement Proposals
- N/A
