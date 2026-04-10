# Issue #92: review: COPILOT_REVIEW_* 環境変数を EXTERNAL_REVIEW_* にリネーム

## Overview

`scripts/wait-external-review.sh` の timeout/interval 環境変数 `COPILOT_REVIEW_TIMEOUT` / `COPILOT_REVIEW_INTERVAL` は、Copilot 専用命名だが現在は Claude Code Review および CodeRabbit にも共用されており実態と乖離している。`EXTERNAL_REVIEW_TIMEOUT` / `EXTERNAL_REVIEW_INTERVAL` に改名し、3 ツール共有設定であることを明示する。後方互換のため旧名をネストされたフォールバックとして残す。

## Changed Files

- `scripts/wait-external-review.sh`: L18-19 の環境変数参照を新形式 `${EXTERNAL_REVIEW_TIMEOUT:-${COPILOT_REVIEW_TIMEOUT:-300}}` / `${EXTERNAL_REVIEW_INTERVAL:-${COPILOT_REVIEW_INTERVAL:-10}}` に変更（コメントも更新）
- `tests/wait-external-review.bats`: L123-124、L143-144、L175-176 の旧変数名 `COPILOT_REVIEW_TIMEOUT=1` / `COPILOT_REVIEW_INTERVAL=1` を `EXTERNAL_REVIEW_TIMEOUT=1` / `EXTERNAL_REVIEW_INTERVAL=1` に変更

## Implementation Steps

1. `scripts/wait-external-review.sh` を編集: L18 を `TIMEOUT=${EXTERNAL_REVIEW_TIMEOUT:-${COPILOT_REVIEW_TIMEOUT:-300}}  # Default: 5 minutes` に、L19 を `INTERVAL=${EXTERNAL_REVIEW_INTERVAL:-${COPILOT_REVIEW_INTERVAL:-10}}  # Default: 10 seconds` に変更 (→ 受け入れ条件 1〜4)
2. `tests/wait-external-review.bats` を編集: `export COPILOT_REVIEW_TIMEOUT=1` を `export EXTERNAL_REVIEW_TIMEOUT=1` に、`export COPILOT_REVIEW_INTERVAL=1` を `export EXTERNAL_REVIEW_INTERVAL=1` に置換（3箇所: L123-124、L143-144、L175-176）(→ 受け入れ条件 5〜6)

## Verification

### Pre-merge

- <!-- verify: grep "EXTERNAL_REVIEW_TIMEOUT" "scripts/wait-external-review.sh" --> `scripts/wait-external-review.sh` で `EXTERNAL_REVIEW_TIMEOUT` が主変数として使用されている
- <!-- verify: grep "EXTERNAL_REVIEW_INTERVAL" "scripts/wait-external-review.sh" --> `scripts/wait-external-review.sh` で `EXTERNAL_REVIEW_INTERVAL` が主変数として使用されている
- <!-- verify: grep "COPILOT_REVIEW_TIMEOUT" "scripts/wait-external-review.sh" --> `COPILOT_REVIEW_TIMEOUT` が後方互換エイリアスとして残っている（`${EXTERNAL_REVIEW_TIMEOUT:-${COPILOT_REVIEW_TIMEOUT:-300}}` 形式）
- <!-- verify: grep "COPILOT_REVIEW_INTERVAL" "scripts/wait-external-review.sh" --> `COPILOT_REVIEW_INTERVAL` が後方互換エイリアスとして残っている（`${EXTERNAL_REVIEW_INTERVAL:-${COPILOT_REVIEW_INTERVAL:-10}}` 形式）
- <!-- verify: grep "EXTERNAL_REVIEW_TIMEOUT" "tests/wait-external-review.bats" --> `tests/wait-external-review.bats` が `EXTERNAL_REVIEW_TIMEOUT` を使用するよう更新されている
- <!-- verify: grep "EXTERNAL_REVIEW_INTERVAL" "tests/wait-external-review.bats" --> `tests/wait-external-review.bats` が `EXTERNAL_REVIEW_INTERVAL` を使用するよう更新されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テストが PASS する

### Post-merge

- `/review` skill の外部レビュー待機フローで `EXTERNAL_REVIEW_TIMEOUT` / `EXTERNAL_REVIEW_INTERVAL` 環境変数として動作することを確認
