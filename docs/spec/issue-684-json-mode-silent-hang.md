# Issue #684: anomaly-detector: json mode silent hang を catalog 追加

## Overview

`detect-wrapper-anomaly.sh` Tier 2 検出器に `json-mode-silent-hang` パターンを追加し、`modules/orchestration-fallbacks.md` に対応カタログエントリを追加する。

背景: 下流プロジェクトで `run-code.sh` が `claude -p` json モード起動後に出力を返さず、watchdog の 1800s タイムアウトで SIGTERM (exit 143) された。Tier 3 orchestration-recovery が「一時的な API 遅延 / セッション初期化ストール」と診断して retry で成功した。Tier 2 (detect-wrapper-anomaly.sh) では unknown pattern で Tier 3 への escalation が発生したが、このパターンはカタログ駆動 retry で対処可能なため Tier 3 escalation コストを削減できる。

## Root Cause

`detect-wrapper-anomaly.sh` に exit 143 かつ `watchdog: still waiting (json mode)` ログメッセージという json mode silent hang パターンが未登録だった。Tier 2 のパターン未検出により Tier 3 (LLM 診断) への不要なエスカレーションが発生していた。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `json-mode-silent-hang` elif ブランチを追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `## json-mode-silent-hang` カタログエントリを追加
- `tests/detect-wrapper-anomaly.bats`: 新パターン向けテストケースを追加 — bash 3.2+ compatible

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `watchdog-kill` elif ブランチの直前に `json-mode-silent-hang` elif ブランチを追加する。条件: `[[ "$EXIT_CODE" == "143" ]] && grep -q "still waiting (json mode)" "$LOG_FILE"`。first-match-wins 優先順で `watchdog-kill` より先に配置する (より具体的なパターン)。PATTERN_NAME=`json-mode-silent-hang`、ANOMALY_DESC にはフェーズと exit code を含め、IMPROVEMENT_HINT には retry once と `modules/orchestration-fallbacks.md#json-mode-silent-hang` 参照を含める。(→ AC1、AC2)

2. `modules/orchestration-fallbacks.md` の `## Operational Notes` セクションの直前に `## json-mode-silent-hang` エントリを追加する。構成: Symptom (exit 143 + `still waiting (json mode)` in log)、Applicable Phases (run-*.sh 経由の全フェーズ)、Fallback Steps (1 回 retry)、Escalation (retry 失敗で Tier 3 へ)、Rationale (transient API delay or session init stall、Tier 3 診断結果)。(→ AC3、AC4)

3. `tests/detect-wrapper-anomaly.bats` に以下のテストケースを追加する:
   - `json mode silent hang: detects exit 143 with still waiting (json mode) in log` — LOG_FILE に `watchdog: still waiting (json mode), silent for 1800s (pid=99)` を書き込み、exit-code 143 で実行 → output に `json-mode-silent-hang` が含まれることを確認
   - `json mode silent hang: no detection when exit code is not 143` — 同じ log 内容で exit-code 1 → output に `json-mode-silent-hang` が含まれないことを確認
   - `json mode silent hang: no detection when log does not contain json mode message` — exit-code 143 かつ log に `json mode` を含まない内容 → output に `json-mode-silent-hang` が含まれないことを確認
   (→ AC5 — CI bats テスト pass)

## Verification

### Pre-merge

- <!-- verify: grep "json-mode-silent-hang" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` に `json-mode-silent-hang` パターン名が追加されている
- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "still waiting (json mode)" --> `detect-wrapper-anomaly.sh` に json mode 検出トリガー文字列 `still waiting (json mode)` が含まれている
- <!-- verify: grep "json-mode-silent-hang" "modules/orchestration-fallbacks.md" --> `orchestration-fallbacks.md` に対応カタログエントリが追加されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## json-mode-silent-hang" "transient" --> カタログエントリに "transient API delay" の rationale が含まれている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) bats テストがすべて pass する (patch route)

### Post-merge

- サンプル log で `detect-wrapper-anomaly.sh --log <path>/sample-silent-hang.log --exit-code 143 --issue 1 --phase code` を実行すると `json-mode-silent-hang` パターンへの参照を含む markdown が出力される <!-- verify-type: manual -->

## Notes

- `json-mode-silent-hang` elif ブランチは `watchdog-kill` の直前に配置する。json mode silent hang は exit 143 AND "still waiting (json mode)" ログメッセージの AND 条件で、`watchdog-kill` (ログメッセージのみ) より具体的。first-match-wins ルールにより正しく優先される
- `watchdog: still waiting (json mode)` メッセージは `scripts/claude-watchdog.sh` の行 71 で stderr に出力される。run-*.sh のラッパーログはこれを捕捉している
- bats テストの LOG_FILE fixture に `still waiting (json mode)` 文字列を含むが、`check-forbidden-expressions.sh` の CI スキャン対象外のため自己参照問題は発生しない
