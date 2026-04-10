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
- 受け入れ条件は明確かつ自動検証可能。7条件すべてにverifyコマンドが付与されており品質は高い
- Post-mergeに手動確認条件（`/review` skill での動作確認）が1件あるが、環境依存のため妥当

#### design
- Specのdesignはシンプルな変数置換で、実装と完全に一致。ネストされたフォールバック形式（`${EXTERNAL_REVIEW_TIMEOUT:-${COPILOT_REVIEW_TIMEOUT:-300}}`）が受け入れ条件にも明示されており設計の明瞭性が高い

#### code
- パッチルート（mainへの直接コミット）で実装。fixup/amendパターンなし。2ファイル8行のシンプルな変更

#### review
- パッチルートのため正式なPRレビューなし。変更規模が小さく後方互換性も確保されているため適切

#### merge
- 直接mainへのコミット。CI（batsテスト + skill syntax check）がすべてsuccessで問題なし

#### verify
- 条件1〜6はgrepコマンドで即時PASS。条件7（github_check "gh pr checks"）はPRなしのパッチルートだったが、mainへのCI runで"Run bats tests" successを確認しPASS
- **パッチルートとgithub_check**：`github_check "gh pr checks"` はPRベースのワークフローを想定した構文だが、パッチルートではPRが存在しない。今回はCI run一覧から代替検証できたが、verifyコマンドとしては`github_check "gh run list"`の方がパッチルートに適している可能性がある

### Improvement Proposals
- パッチルートIssueの受け入れ条件に`github_check "gh pr checks"`を使用した場合、PRが存在しないためverifyが困難になる。パッチルートではCI run結果（`github_check "gh run list" "success"`など）の方が適切なverifyコマンドである可能性があり、`/spec`または`/code`スキルでパッチルート選択時に適切なverifyコマンドを案内する仕組みを検討する
