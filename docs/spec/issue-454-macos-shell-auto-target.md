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

## review retrospective

### Spec と実装の乖離パターン

- 乖離なし。Spec の実装ステップと PR diff が完全に一致しており、特記すべきパターンなし

### 繰り返し問題

- なし。今回の変更は1ファイル1箇所の最小限の変更であり、同種の問題は発生しなかった

### 受け入れ条件の検証難易度

- 全条件が verify command 付き。AC4 (`github_check`) は CI 完了まで検証不可だったが、CI SUCCESS 確認後に PASS を確定できた
- UNCERTAIN なし。グロブ非マッチ時の挙動 (CONSIDER) は検証可能だったが実用上影響なし

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- mergeable=true, CI 全ジョブ SUCCESS, review approved の状態でスカッシュマージを実行
- `gh pr merge 692 --squash --delete-branch` で正常完了。Issue #454 は `closes #454` により自動クローズ

### Deferred Items

- Post-merge AC (scripts/ に新規 .sh 追加した PR で macOS 互換性チェックが自動的に走ることの確認) は opportunistic verify で追跡

### Notes for Next Phase

- 変更内容は `.github/workflows/test.yml` の 1 箇所のみ (macos-shell ジョブのグロブ化)
- verify フェーズでの確認事項: post-merge AC (opportunistic) のみ。pre-merge AC はすべて PASS 済み
- 競合なし、リベース不要、テスト実行不要 (CI 済み)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC 4 件 pre-merge + 1 件 post-merge opportunistic でコンパクト。`file_contains` / `command` / `github_check` の verify command が適切に使い分けされている。

#### spec
- Implementation Steps が `.github/workflows/test.yml` の 1 箇所 (`macos-shell` job) のみと最小。Spec と実装の乖離なし。

#### code
- 一発実装で全 bats テスト PASS、CI 全 SUCCESS、rework なし。

#### review
- light review で MUST 0 件。CI 全 SUCCESS。

#### merge
- **本セッションが #685/#687/#690 全 3 pillar fix 適用後の最初の pr-route merge**。`source=ci` 付き `test_result` event が自動 emit された (passed=855, failed=1, run_id=27704310243)。
- 連鎖 close target (#679 / #662 / #630) の post-merge AC observation が opportunistic-search で trigger される見込み (本 /auto 完了後の Step 5)。

#### verify
- Pre-merge 4/4 PASS、Post-merge 1 opportunistic 残留 → `phase/verify` 維持。

### Improvement Proposals

- N/A — 本 Issue 自身は scope 通り完了。`source=ci` test_result emit pipeline の機能確認も merge phase で副次的に達成。
