# Issue #1104: verify-executor: 実行コストを持つ verify command への既定タイムアウト導入

## Overview

`modules/verify-executor.md` の翻訳テーブルは、`html_check` を除く実行コストを持つ verify command (`--when` の shell_condition: 10秒、`github_check`: 30秒、`command`: 60秒、`build_success`: 120秒、`http_status`/`api_check`/`http_header`/`http_redirect`: curl の `--connect-timeout 5 --max-time 10`) すべてに既定タイムアウトを規定している。`html_check` はパイプ先の `scripts/html-selector-match.py` (組み込みの Python CSS セレクタマッチャー) 実行に上限がなく、Issue #1069 / PR #1077 で計算量が O(n·d^(k-1)) になるケース (58 KB・2000行の HTML テーブルへ `thead ~ tr ~ tr` を適用して 93.6 秒) が「張り付き」として実際に表面化した (メモ化により当該ケース自体は 0.39 秒に修正済み、ただしタイムアウト未規定という構造は残存)。

本 Issue は `html_check` に既定タイムアウト (30秒) を導入し、タイムアウト到達時は FAIL ではなく UNCERTAIN として扱うようにする。あわせて翻訳テーブル全体を監査し、verify-executor.md 自身が直接 bash subprocess / curl を起動する他の command (`--when`, `command`, `build_success`, `github_check`, `http_status`/`api_check`/`http_header`/`http_redirect`) にタイムアウト未規定のものが残っていないことを確認する。アダプタ委譲系 (`browser_check`/`browser_screenshot`/`visual_diff`/`lighthouse_check`) と `mcp_call`/`rubric` (LLM 呼び出しであり bash subprocess を起動しない) はスコープ外 — `html_check` のタイムアウト値・監査スコープともに `/issue` フェーズの Auto-Resolve Log で確定済み (Consumed Comments 参照)。

## Changed Files

- `modules/verify-executor.md`: `html_check` 行 (翻訳テーブル) に `html-selector-match.py` 実行への30秒タイムアウトと、タイムアウト到達時の UNCERTAIN 扱い (理由記録付き) を追記。「### Differentiation Between `http_status` / `html_check` / `api_check` / `build_success` / `github_check` と `command`」節の直後に新規「### Timeout Coverage Audit (#1104)」節を追加し、bash subprocess / curl を直接起動する command 全種にタイムアウトが規定済みであることとスコープ外 (アダプタ委譲系・`mcp_call`・`rubric`) を明記
- `tests/verify-executor.bats`: `html_check` 行が30秒タイムアウトの記述 (`html-selector-match.py` と `30` の両方) を含むことを確認する回帰ガード用 `@test` を追加 — bash 3.2+ compatible (bats)

## Implementation Steps

1. `modules/verify-executor.md` の `html_check` 行を更新する (→ acceptance criteria AC1, AC2)。`curl ... \| python3 ${CLAUDE_PLUGIN_ROOT}/scripts/html-selector-match.py "selector"` の実行に30秒タイムアウトを付与する記述を追加し、curl 自体の `--connect-timeout`/`--max-time` はネットワーク取得のみを制限し、パイプ先 Python プロセスの CPU 時間は制限しない旨を明記する。タイムアウト到達時は **UNCERTAIN** (理由: `"html-selector-match.py execution timed out after 30s"`) として扱い FAIL にはしないことを明記する (既存の syntax エラー時の UNCERTAIN 判定とは別の分岐として、exit code 判定より先に評価する)。既存の「Judge in two stages」(exit code 判定) はタイムアウト内に完了した場合の判定として残す。行内の既存テキスト `--config "$config_file"` (2箇所) と `combinator` は変更せず保持する (`tests/verify-executor.bats` の既存回帰ガードテスト「html_check row keeps both Basic Auth --config and combinator support」が依存)
2. `modules/verify-executor.md` の「### Differentiation Between ... と `command`」節 (Safe mode handling 小節を含む) の直後、「### Shell Script Syntax Check」節の直前に新規「### Timeout Coverage Audit (#1104)」節を追加する (after 1) (→ acceptance criteria AC3, AC4)。bash subprocess / curl を直接起動する全 command (`--when`, `command`, `build_success`, `github_check`, `http_status`/`api_check`/`http_header`/`http_redirect`, `html_check`) にタイムアウトが規定済みであること、タイムアウト到達時は UNCERTAIN として扱うこと (FAIL ではない — 条件を満たさないことが確認できたわけではないため)、およびアダプタ委譲系 (`browser_check`/`browser_screenshot`/`visual_diff`/`lighthouse_check`) と `mcp_call`/`rubric` がスコープ外である理由 (前者はアダプタ側の関心事、後者はそもそも bash subprocess/curl を起動しない LLM 呼び出しのため) を記載する
3. `tests/verify-executor.bats` に新規 `@test` を追加する (parallel with 1, 2) (→ acceptance criteria AC2, AC5)。既存の `@test "verify-executor: html_check row keeps both Basic Auth --config and combinator support"` (行51-56) と同じ `row=$(grep -- '^| \`html_check ' "$VERIFY_EXECUTOR")` パターンで行を抽出し、`html-selector-match.py.*30` にマッチすることを `grep -q` で確認する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の html_check 行に実行タイムアウトの既定値 (30秒) が規定され、タイムアウト到達時は FAIL ではなく UNCERTAIN として扱い理由を記録する旨が明記されている" --> `html_check` に既定タイムアウト (30秒) とタイムアウト時の UNCERTAIN 扱いが規定されている
- <!-- verify: grep "html-selector-match\.py.*30" "modules/verify-executor.md" --> `html_check` 行にタイムアウト秒数 (30) が明記されている
- <!-- verify: rubric "modules/verify-executor.md の翻訳テーブルのうち、verify-executor 自身が直接 bash subprocess / curl を起動する command (--when, command, build_success, github_check, http_status/api_check/http_header/http_redirect, html_check) すべてにタイムアウトが規定されていることが確認されている。アダプタ委譲系 (browser_check 等) と mcp_call/rubric はスコープ外として扱われている" --> 実行コストを持つ command でタイムアウト未規定のものが残っていない (アダプタ委譲系・mcp_call・rubric は対象外)
- <!-- verify: grep "timeout" "modules/verify-executor.md" --> `verify-executor.md` がタイムアウトに言及している
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge

- 意図的に高コストなセレクタと大きな HTML の組み合わせで `html_check` を実行し、張り付かずにタイムアウトして UNCERTAIN になることを確認する <!-- verify-type: manual -->

## Notes

- **Auto-Resolve (`/issue` フェーズで確定済み)**: `html_check` のタイムアウト値 (30秒) と AC3 (翻訳テーブル監査) のスコープ限定は `/issue` フェーズの Issue Retrospective で既に確定済みの決定であり (Consumed Comments 参照)、本 Spec ではその決定をそのまま採用した
- **Auto-Resolve (本 Spec での判断)**: 新設する「Timeout Coverage Audit」節に「タイムアウト到達時は UNCERTAIN」という一般原則を、html_check 限定ではなく監査対象の全 command 共通の原則として記載することにした。Issue 本文の対応方針 (案) 項目2の文面は html_check 限定とも全 command 共通とも読めるが、Issue の Purpose ("判定不能なケースが「張り付き」ではなく UNCERTAIN として扱われるようにする") が全 command を対象にしていること、既存の Processing Steps ("Cannot be automatically determined" = UNCERTAIN の定義) と矛盾しないことから、全 command 共通の原則として明記する方を採用した。他の対象 command (`command`/`build_success`/`github_check`/`http_status` 系) 自体の行テキストは変更しない — 現状で各行にタイムアウト秒数の記述は既にあるため、Simplicity Rule (light: 実装ステップ・pre-merge 検証項目とも上限5件) の範囲に収める判断とした
- `scripts/html-selector-match.py` 自体への変更は不要と判断した: `modules/verify-executor.md` は `/verify`・`/review` を実行する Claude 自身が読んで実行する手順書であり、`command`/`build_success`/`--when` の既存タイムアウトも Claude 自身の Bash tool 呼び出しの `timeout` パラメータで実現されている (スクリプト内部やシェルの `timeout`/`gtimeout` コマンドには依存しない)。`html_check` のタイムアウトも同じ方式で実現するため、スクリプト側の変更は不要
- 影響範囲調査 (`grep -rl "html_check" .` および `grep -rl "html-selector-match" .`、リポジトリ全体) により、`docs/environment-adaptation.md`・`docs/guide/customization.md`・`modules/verify-patterns.md`・`skills/issue/SKILL.md`・`scripts/validate-skill-syntax.py` にも `html_check` への言及があるが、いずれも既存の command 分類/引数検証のための一覧言及に留まりタイムアウト仕様は含まないため、変更不要と判断した
- `tests/html-selector-match.bats` は `scripts/html-selector-match.py` 自体の CLI 動作 (stdin 経由の HTML フィクスチャに対するセレクタマッチ) を検証するテストであり、本 Issue はスクリプト自体の挙動を変更しないため、変更不要と判断した

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective。`html_check` の実行タイムアウトを 30 秒に確定した Auto-Resolve Log (`github_check` の 30 秒との整合を優先し、`command` の 60 秒より厳格・`--when` の 10 秒より緩い中間値として確定)、および翻訳テーブル全体見直し (AC3) のスコープを「verify-executor.md が直接 bash subprocess / curl を起動する command」に限定した Auto-Resolve Log (アダプタ委譲系・`mcp_call`・`rubric` は対象外) を記録。Background の事実確認 (各 command のタイムアウト規定状況) も実ファイルで確認済みと記載されている。https://github.com/saitoco/wholework/issues/1104#issuecomment-5161392034
