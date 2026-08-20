# Issue #1397: run-code.sh の exec 自己再起動が bash 3.2 で空配列時に unbound variable となる潜在バグを修正

Size XS のため `/spec` は実行されていない (`phase/ready` 前提の Spec 作成をスキップし、`/code --patch` が直接実行された)。本ファイルは `/code` フェーズが Issue コメントに投稿した Implementation Complete レポートを、`/verify` の Phase Handoff / Consumed Comments 記録先として転記したものである。

## Code Retrospective

### 実装内容

- `scripts/run-code.sh:407` — `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` を `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]+"${_TRAILING_ARGS[@]}"}"` に修正 (`scripts/run-spec.sh` で #1369 にて確立済みの nounset-safe イディオムをそのまま移植)
- Commit: `b7b8cbfd` fix: Make run-code.sh exec self-restart nounset-safe for empty trailing args (closes #1397)

### Deviations from Design

- N/A — Issue 本文が示した修正内容 (#1369 の既存イディオムの移植) をそのまま実施した。手戻りは発生していない。

### Tests

- `bats --jobs 18 tests/` — PASS (1887/1887; `scripts/run-code.sh` を参照する既存テストファイルが `tests/run-code.bats` (direct counterpart) 以外に `tests/run-code-mergeability.bats` も存在したため、Behavioral Change Detection によりフルスイート実行)
- `bats tests/run-code.bats` (AC 2) — PASS
- `python3 scripts/validate-skill-syntax.py skills/` — PASS (0 error, 0 warning)
- `bash scripts/check-forbidden-expressions.sh` — PASS (violation 0)

## Consumed Comments

No new comments since last phase.
