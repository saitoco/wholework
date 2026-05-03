# Issue #386: tests: run-*.bats を repo root の .wholework.yml から隔離

## Overview

`tests/run-*.bats` 全 7 ファイル (`run-auto-sub.bats` を含む) が `setup()` 内で CWD 隔離していないため、`scripts/get-config-value.sh` が CWD 相対で `.wholework.yml` を読む構造と相まって、repo root の `.wholework.yml` の内容が bats テストに混入する。コミット `09e83de`（`permission-mode: auto` を追加）の直後から CI の `Test / Run bats tests` が連続 FAIL した。

各ファイルの `setup()` 冒頭に「`BATS_TEST_TMPDIR/.wholework.yml` に `permission-mode: bypass` を書き込む + `cd "$BATS_TEST_TMPDIR"`」の隔離 block を追加し、ローカルの `.wholework.yml` がテスト挙動に影響しない構造に変える。`scripts/get-config-value.sh` 自体には触らない。

## Reproduction Steps

```bash
echo "permission-mode: auto" > .wholework.yml
bats tests/run-code.bats
# `not ok` 多数: FLAG_SKIP_PERMS=1 と "Permissions: skip (autonomous mode)" banner が消える
```

## Root Cause

- `scripts/get-config-value.sh:59` は `CONFIG_FILE=".wholework.yml"` を CWD 相対で参照。
- `scripts/run-*.sh` はこれを介して `permission-mode` を解決。
- bats テストは `setup()` 冒頭で CWD を切り替えていないため、テストランナーの CWD（repo root）の `.wholework.yml` を実プロダクション設定として読み込んでしまう。
- `tests/run-code.bats:319-329` で導入された auto/bypass 明示テストは個別関数内で `cd "$BATS_TEST_TMPDIR"` しているため通る。**既存テスト群の `setup()` に CWD 隔離が無い**のが構造的欠陥。

修正方針の妥当性: `setup()` 冒頭に隔離 block を追加すると、`MOCK_DIR="$BATS_TEST_TMPDIR/mocks"` などの後続定義は絶対パスベースなので影響を受けない。`run-spec.bats:97-102` で `BATS_TEST_TMPDIR/skills/spec/SKILL.md` を作成する処理も絶対パスのため安全。`permission-mode: bypass` の明示書き込みは #385（permission-mode デフォルト反転）後も挙動が変わらないため、将来安定性も担保される。

## Changed Files

- `tests/run-code.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換 (bats 互換)
- `tests/run-spec.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換
- `tests/run-review.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換
- `tests/run-verify.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換
- `tests/run-merge.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換
- `tests/run-issue.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: `setup()` 冒頭に隔離 block を追加 — bash 3.2+ 互換

## Implementation Steps

1. 各 `tests/run-*.bats` の `setup()` 関数の **直後** (関数本体の最初の行) に、以下の 3 行 block を挿入する (→ 受入条件 1〜7, 8) — 現状 7 ファイルすべての `setup()` は `MOCK_DIR="$BATS_TEST_TMPDIR/mocks"` から始まるため、その直前に挿入:
   ```bash
       # Isolate test from repo .wholework.yml
       echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
       cd "$BATS_TEST_TMPDIR"
   ```
   - インデントは既存 `setup()` 内コードと同じ 4 スペースに揃える。
   - 7 ファイルとも先頭のテキストは `MOCK_DIR=` 行のため、Edit ツールでその行を `unique` に検出して直前に挿入できる。
2. ローカルで `bats tests/run-*.bats` を 7 ファイルすべて実行して PASS することを確認する (→ 受入条件 8、Post-merge CI condition の事前確認)。`echo "permission-mode: auto" > .wholework.yml` の状態でも全件 PASS することを補助確認 (→ Post-merge opportunistic condition)。
3. 隔離 block の追加で破壊しないか、`run-code.bats:319` 以降の auto/bypass 明示テストを含め全テストが PASS することを確認する。冪等性（重複 cd / 上書き書き込み）に問題が出ないことを検証 (→ Post-merge auto condition、CI 経由で確認)。

## Verification

### Pre-merge

- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-code.bats" --> `tests/run-code.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-spec.bats" --> `tests/run-spec.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-review.bats" --> `tests/run-review.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-verify.bats" --> `tests/run-verify.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-merge.bats" --> `tests/run-merge.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-issue.bats" --> `tests/run-issue.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: grep "Isolate test from repo .wholework.yml" "tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` の `setup()` に隔離マーカーコメント `# Isolate test from repo .wholework.yml` が追加される
- <!-- verify: rubric "tests/run-*.bats 全 7 ファイルの setup() に BATS_TEST_TMPDIR/.wholework.yml への permission-mode: bypass 書き込みと cd \"$BATS_TEST_TMPDIR\" の隔離処理が追加されている" --> 7 ファイルの `setup()` に書き込みと CWD 切り替えの両方が実装されている

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 修正コミット後の main で `Test / Run bats tests` workflow が success する
- repo root の `.wholework.yml` に `permission-mode: auto` が書かれた状態で `bats tests/` を手動実行しても全件 PASS することを確認する

## Notes

- **挿入位置**: `setup()` の最初の処理（現状はすべて `MOCK_DIR="$BATS_TEST_TMPDIR/mocks"`）の **直前**に挿入する。BATS は `setup()` 開始前に `BATS_TEST_TMPDIR` を作成済みのため `mkdir -p` は不要。
- **冪等性**: `run-code.bats:319-329` などで個別テスト関数内に既存の `cd "$BATS_TEST_TMPDIR"` がある。`setup()` 内で先に cd 済みでも、テスト本体での再 cd / `.wholework.yml` 上書きは冪等で副作用なし。
- **検出マーカー**: `# Isolate test from repo .wholework.yml` コメントを設置。`permission-mode: bypass` 単独 grep は run-code.bats:319-329 の既存テスト本文で既に true となるため、setup() への新規追加を区別できない。コメント文字列はリポジトリ全体で他箇所に存在しない一意な検出マーカーとして機能する。
- **`scripts/get-config-value.sh` 構造変更は対象外**: Issue Purpose で確認済み。本 Issue ではテスト隔離のみに集中し、`WHOLEWORK_CONFIG_PATH` 等の env 経路導入は別 Issue で扱う。
- **#385 との整合**: `permission-mode: bypass` を明示書き込みするため、#385（permission-mode デフォルト反転）マージ後も bats テストの挙動は変わらない。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. All 7 files match the design exactly; isolation block position (before `MOCK_DIR=`) and content are consistent across all files.

### Recurring Issues

Nothing to note. No review issues found across any perspective.

### Acceptance Criteria Verification Difficulty

Nothing to note. All 8 verify commands resolved cleanly (7 `grep` commands + 1 `rubric`). The unique marker comment string `# Isolate test from repo .wholework.yml` served as an effective verify target with no false-positive risk.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue retrospective section is absent from the Spec (only Code/Review retrospectives). The root cause analysis and fix approach were clear and well-documented. No ambiguity was flagged in the Issue body; the two auto-resolved ambiguity points (scope of 7 files, no `scripts/get-config-value.sh` changes) were correctly pre-resolved.

#### design
- Design (Spec) accurately predicted the implementation. The `setup()` insertion position (`before MOCK_DIR=` line) and the isolation block content (`echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"` + `cd "$BATS_TEST_TMPDIR"`) were specified precisely, leaving no deviation in implementation.

#### code
- Single squash-merge commit `b542d98`. No fixup/amend patterns in the 7-file change — clean first-pass implementation. The isolation block is identical across all 7 files.

#### review
- One review was conducted on PR #392 (1 review comment). No FAIL items were found in verify; review appears to have validated correctness pre-merge.

#### merge
- Merged via PR #392 squash-merge to main without conflicts. No CI failures during merge.

#### verify
- Conditions 1–8 (Pre-merge) all PASS. Condition 9 (Post-merge CI) confirmed PASS on re-run (`test.yml` conclusion = `success`). Condition 10 (opportunistic manual check) deferred to user.
- Previous run reported condition 9 as PENDING (CI was in_progress); resolved on re-run. No actionable issue.

### Improvement Proposals
- N/A
