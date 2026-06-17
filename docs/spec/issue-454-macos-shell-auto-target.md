# Issue #454: ci: Auto Target New Scripts in macOS Shell CI Job

## Overview

`scripts/` に新しい `.sh` ファイルが追加された際、`.github/workflows/test.yml` の `macos-shell` ジョブが自動的にそのスクリプトを対象に含める仕組みを導入する。

現状の `macos-shell` ジョブは `scripts/check-translation-sync.sh` を直接実行するだけで、新規スクリプトが追加されても自動的に対象化されない (Issue #445 の Review Retrospective でこの問題が発覚)。

実装アプローチ: `scripts/*.sh` に一致する全ファイルを `bash -n` でシンタックスチェックするよう変更する。`bash -n` は実行せずに構文検証のみ行うため、引数が必要なスクリプト (`run-*.sh`、`gh-*.sh` 等) も安全に検査できる。

## Changed Files

- `.github/workflows/test.yml`: `macos-shell` ジョブの "Run shell scripts on macOS" ステップを `bash scripts/check-translation-sync.sh` から `scripts/*.sh` 全ファイルへの `bash -n` ループに変更 — bash 3.2+ 互換

## Implementation Steps

1. `.github/workflows/test.yml` の `macos-shell` ジョブの `run:` を以下のように変更する (→ 受入条件 1, 2):

   変更前:
   ```yaml
   - name: Run shell scripts on macOS
     run: bash scripts/check-translation-sync.sh
   ```

   変更後:
   ```yaml
   - name: Run shell scripts on macOS
     run: |
       for f in scripts/*.sh; do
         bash -n "$f"
       done
   ```

## Verification

### Pre-merge

- <!-- verify: file_contains ".github/workflows/test.yml" "scripts/*.sh" --> `.github/workflows/test.yml` の `macos-shell` ジョブが `scripts/*.sh` グロブパターンを使用して全スクリプトを動的に対象化している
- <!-- verify: file_contains ".github/workflows/test.yml" "bash -n" --> `macos-shell` ジョブが `bash -n` でシンタックスチェックを実行する
- <!-- verify: command "bash -n scripts/check-eager-load-capability.sh" --> `scripts/check-eager-load-capability.sh` が macOS 互換の bash 構文であることを確認
- <!-- verify: github_check "gh pr checks" "macOS shell compatibility" --> CI の `macos-shell` ジョブが GREEN であること (新機構が正常に動作していることの確認)

### Post-merge

- `scripts/` に新たな `.sh` ファイルを追加した PR で macOS 互換性チェックが自動的に走ることを確認 <!-- verify-type: opportunistic -->

## Notes

- `bash scripts/check-translation-sync.sh` (実際の実行) から `bash -n` (構文チェックのみ) への切り替えにより、`check-translation-sync.sh` はこのジョブでは実行されなくなるが、macOS 互換性は引き続き構文チェックで担保される
- `scripts/git-hooks/` 配下のスクリプトは `scripts/*.sh` グロブに含まれないため対象外
- 変更後の run ブロックは bash 3.2+ (macOS システム bash) 互換: `for` ループ、glob 展開ともに 4.0+ 機能を使用しない

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- Spec の実装ステップは 1 ステップのみで変更箇所が明確であり、曖昧な点はなかった

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `bash -n` による全 `scripts/*.sh` シンタックスチェックを採用 (実行副作用なし、新規スクリプト自動補足)
- for ループは bash 3.2+ 互換 (`for f in scripts/*.sh; do bash -n "$f"; done`)
- `scripts/git-hooks/` は `scripts/*.sh` グロブ対象外のため変更不要と確認

### Deferred Items

- CI の `macos-shell` ジョブ GREEN 確認 (AC4) は PR #692 のCI完了後に `/verify` で確認

### Notes for Next Phase

- 変更は `.github/workflows/test.yml` の 1 箇所のみ、シンプルな実装
- pre-merge AC 1-3 は PASS 済み、AC4 (github_check) のみ CI 待ち
- Post-merge AC は opportunistic verify で自動追跡される
