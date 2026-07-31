# Issue #1128: run-review: preview 待ちゲートを skills/review Step 8.0 と同じ PREVIEW_URL 契約に揃える

## Consumed Comments

- `saito` / `MEMBER` / first-class / `/issue` フェーズの Issue Retrospective (Ambiguity Resolution Rationale + Auto-Resolve Log + Acceptance Criteria Changes + Triage Summary)。Post-merge を「なし」とした根拠、Size=L の判定根拠、派生論点 2 件をスコープ外に固定した経緯を本 Spec の設計前提として取り込んだ / https://github.com/saitoco/wholework/issues/1128#issuecomment-5140750062

cutoff: `2026-07-31T08:05:31Z` (最新の `phase/*` label 付与時刻)

## Overview

`skills/review/SKILL.md` Step 8.0 は `PREVIEW_URL` 環境変数が export 済みなら GitHub Deployments API lookup を skip する fast path を持つ。一方 `#1050` で `scripts/run-review.sh` に追加された review セッション起動前の preview 待ちゲートには fast path が無く、`capabilities.pr-preview: true` なら `PREVIEW_URL` の有無に関わらず Deployments API を無条件にポーリングする。

結果として同一リポジトリ内で skill 本体と wrapper が別々の契約に従っており、deployment を作成しない hosting provider (AWS Amplify Hosting 等) を使うプロジェクトでは、契約どおり `PREVIEW_URL` を用意していても wrapper のゲートで止まり review セッションが起動しない。

本 Issue は `scripts/run-review.sh` のゲートに fast path を追加して契約を揃え、あわせてドキュメント (`docs/tech.md` / `docs/ja/tech.md`)、フォールバックカタログ (`modules/orchestration-fallbacks.md`)、異常検出 (`scripts/detect-wrapper-anomaly.sh`) を同期する。

## Reproduction Steps

downstream (tofas #334 / PR #362) で観測された再現手順:

1. `.wholework.yml` に `capabilities.pr-preview: true` を設定し、preview は AWS Amplify Hosting (GitHub deployment を作成しない provider) で配信する
2. プロジェクト側 adapter (`.wholework/adapters/resolve-amplify-preview-url.sh`) で `PREVIEW_URL` を解決できる状態にする
3. `/auto` から review フェーズに入る (`scripts/run-review.sh <PR>` が起動する)
4. CI checks は `total=2 passed=2 failed=0 pending=0` で確定するが、preview ゲートで停止する:

```
Waiting for PR preview deployment on PR #362...
PENDING: PR preview deployment not confirmed for PR #362 (branch=worktree-code+issue-334 state=none); skipping review session
Exit code: 2
```

5. `gh api "repos/saitoco/tofas/deployments?per_page=5" --jq 'length'` は repo 全体で `0` を返す (Amplify は GitHub deployment を作らない)
6. `gh pr checks 362` には `AWS Amplify Console Web Preview   pass   0   https://pr-362.dx2esn188lzi1.amplifyapp.com` が並び、`curl -s -o /dev/null -w "%{http_code}" https://pr-362.dx2esn188lzi1.amplifyapp.com/en/faq` は `401` (Basic 認証プロンプト = preview は稼働中) を返す

タイミングではなく構造的な原因のため、`modules/orchestration-fallbacks.md#review-pending-not-failure` の 300s x 2 リトライも原理的に無効。

## Root Cause

`scripts/run-review.sh` L133-155 の preview 待ちゲートが、`skills/review/SKILL.md` L215-217 の fast path (`PREVIEW_URL` 優先) を持たないまま実装された。

- `skills/review/SKILL.md` (L215-217): `PREVIEW_URL` が export 済みならその値を使い Deployments API lookup を skip する
- `docs/guide/customization.md` (L189-195): 「`PREVIEW_URL` の export は CI またはプロジェクト側スクリプトの責務。Wholework は自動解決しない」
- `scripts/run-review.sh` (L133-155): 上記いずれも参照せず、`capabilities.pr-preview: true` だけを条件に Deployments API を無条件ポーリングする

`_preview_state` が `success` にならなければ `_pending_reason` が設定され、L157-166 で exit 2 (PENDING) となる。deployment がそもそも 1 件も作られない provider では `_preview_state` は永久に空文字 (`state=none`) のままなので、この分岐は構造的に抜けられない。

修正方針の妥当性: `#781` の設計判断 (プラットフォーム別 adapter は upstream に持たず、`PREVIEW_URL` 解決はプロジェクト側の責務) を維持したまま、wrapper が既存の `PREVIEW_URL` 契約を参照するだけで解消する。upstream に Amplify 固有の知識は入らない。

## Changed Files

- `scripts/run-review.sh`: preview 待ちゲート冒頭に `PREVIEW_URL` fast path 分岐を追加 (Deployments API ポーリングを skip し HTTP 到達性で稼働判定)。既存の Deployments API 分岐は `else` 側に退避し挙動不変 — bash 3.2+ compatible
- `scripts/detect-wrapper-anomaly.sh`: 構造的 PENDING (`PENDING: PR preview deployment not confirmed` かつ `state=none`) を検出する `preview-deployment-absent` パターンを elif チェーンに追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `## review-pending-not-failure` セクションに「リトライで解消しない構造的 PENDING」の見分け方 (`gh api "repos/:owner/:repo/deployments?per_page=1"` が repo 全体で 0 件) と `PREVIEW_URL` export による対処を追記
- `docs/tech.md`: `HAS_PR_PREVIEW_CAPABILITY` 行 (L251) の `run-review.sh` 記述に fast path を追記。あわせて `WHOLEWORK_PREVIEW_TIMEOUT_SEC` 行 (L238) を「Deployments API ポーリングと fast path の HTTP 到達性ポーリングの双方の上限」に更新
- `docs/ja/tech.md`: 上記 2 行 (L232 / L219) の対応箇所を日本語で同期 (`docs/translation-workflow.md` Sync Procedure)
- `docs/guide/customization.md`: [Steering Docs sync candidate] `**Resolving PREVIEW_URL:**` 節 (L189-195) と `**Behavior summary:**` 節 (L199-201) が現状「`/review` 呼び出し前に export」としか書いておらず、`run-review.sh` のゲートも同じ変数を読むようになる点が反映されない。prose 箇条書きと config-reference 表 (L131) の両方を確認して更新要否を `/code` で判断する
- `docs/ja/guide/customization.md`: [Steering Docs sync candidate] 上記の日本語ミラー (L120 / L176-188)。`scripts/check-translation-sync.sh` は `docs/guide/*.md` を同期対象に含むため、英語側を変更した場合は必須
- `docs/workflow.md`: [Steering Docs sync candidate] L123 の「Review PENDING retry」記述。リトライ挙動自体は不変のため更新不要の見込みだが、構造的 PENDING に触れるか `/code` で判断する
- `docs/ja/workflow.md`: [Steering Docs sync candidate] L116 の対応箇所。英語側を変更した場合のみ同期する
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `scripts/run-review.sh` (L230 / L222) と `scripts/detect-wrapper-anomaly.sh` (L216 / L208) の 1 行説明。いずれも役割レベルの汎用記述であり更新不要の見込み — `/code` が実際に読んで最終判断する
- `tests/run-review.bats`: fast path のテストを追加 (200 稼働 / 401 稼働 / 到達不可 PENDING / `PREVIEW_URL` 未設定時のフォールバック)。`setup()` の `unset` 行に `PREVIEW_URL` を追加し、親プロセス環境からの汚染を遮断する
- `tests/detect-wrapper-anomaly.bats`: `preview-deployment-absent` パターンのテストを追加 (検出 / `state=pending` では非検出 / 片方の文字列のみでは非検出)

**計測スコープ**: `grep -rn "PREVIEW_URL" --include="*.sh" --include="*.md" --include="*.bats" . | grep -vE "^\./docs/(spec|sessions|reports|ja/reports)/"` で 51 hits。うち `scripts/run-review.sh` は 0 hits、`scripts/detect-wrapper-anomaly.sh` も 0 hits (いずれも本 Issue で新規導入)。`grep -n "fast path" docs/tech.md docs/ja/tech.md` は 0 hits (AC6 の対象文字列は新規導入)。

## Implementation Steps

1. **`scripts/run-review.sh` — fast path 分岐の追加** (→ AC1, AC2, AC5)

   `_gh_api_bounded()` 定義の直後にある `if [[ -z "$_pending_reason" ]] && [[ -f .wholework.yml ]] && grep -A 20 '^capabilities:' ...` ブロックの内側を、`_preview_timeout_sec` 代入の直後で 2 分岐に再構成する。冒頭の `echo "Waiting for PR preview deployment on PR #${PR_NUMBER}..." >&2` は Deployments API 側の分岐内へ移す (fast path では別メッセージを出す)。

   - `[[ -n "${PREVIEW_URL:-}" ]]` が真: fast path (Step 2 で実装する稼働判定を行う)。`gh pr view --json headRefName` も `_gh_api_bounded` も一切呼ばない
   - 偽: 既存の Deployments API ポーリング分岐をそのまま `else` 側に置く (後方互換。`_preview_branch` 取得・`while` ループ・`_preview_state != success` 時の `_pending_reason` 設定は現行のまま)

   `capabilities.pr-preview` が未宣言/false のプロジェクトではブロック全体が従来どおり skip される (外側の `if` 条件は変更しない)。

2. **`scripts/run-review.sh` — fast path の稼働判定 (HTTP 到達性)** (after 1) (→ AC3, AC4)

   fast path 分岐の中身を、以下のブランチ挙動を全て満たすよう実装する。`set -euo pipefail` が有効な点に注意する。

   - **プローブ前提**: `command -v curl >/dev/null 2>&1` が偽の場合はプローブを行わず稼働とみなして review セッションを起動する (fail-open)。`Warning: curl not found; accepting PREVIEW_URL without a reachability probe` を stderr に出す。理由は Notes の「curl 未検出時の fail-open」を参照
   - **プローブコマンド**: `curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$PREVIEW_URL"`。既存の `command -v timeout` 判定と同じ idiom で、curl 自身の `--connect-timeout` / `--max-time` により自己制限させる (`timeout`/`gtimeout` によるラップは不要)
   - **正常終了条件**: HTTP status が `2xx` / `401` / `403` のいずれか → `_pending_reason` を空のまま維持し review セッション起動へ進む。stderr に `PR preview reachable via PREVIEW_URL for PR #${PR_NUMBER} (HTTP <code>)` を出力する。判定は bash 3.2 互換の `case "$_preview_http_code" in 2??|401|403) ... ;; esac` 形式で書く (401/403 は Basic 認証で保護された preview が「サーバは応答している」ことの証拠 — `#1074` / `#1025` / `#1051` が既に前提としている)
   - **error path (curl 実行失敗)**: 名前解決失敗などで curl は stdout に `000` を出力し非 0 で終了する (実測: exit 6)。`_preview_http_code=$(curl ... 2>/dev/null || true)` の形で終了コードを吸収し、結果が空文字なら `000` を代入する。`000` は稼働条件に該当しないためポーリングを継続する
   - **ポーリング**: `_preview_timeout_sec` (既存の `WHOLEWORK_PREVIEW_TIMEOUT_SEC:-600`) を上限に、既存の Deployments API 分岐と同じ `sleep 30` 間隔で繰り返す
   - **timeout 条件**: 上限秒数を超えても稼働条件を満たさない → `_pending_reason="PR preview URL not reachable for PR #${PR_NUMBER} (PREVIEW_URL set, last HTTP status=${_preview_http_code:-none})"` を設定する。以降は既存の L157-166 の PENDING 出力経路がそのまま exit 2 を返す
   - **kill 条件**: なし (この分岐は subprocess を自前で kill しない)
   - **監視継続**: 稼働条件成立またはタイムアウトでループを抜ける。それ以外は継続する
   - **ログ出力の制約**: `PREVIEW_URL` の値そのものは stdout/stderr のいずれにも出力しない (Notes の「認証情報の取り扱い」を参照)。出力するのは HTTP status code のみ

3. **`scripts/detect-wrapper-anomaly.sh` — 構造的 PENDING パターンの追加** (parallel with 1, 2) (→ AC9)

   `mid-run-api-error` の `elif` の直後、`elif [[ "$EXIT_CODE" == "0" ]]; then` ブロックの直前に、新しい `elif` を挿入する。

   - **検出条件**: `grep -q "PENDING: PR preview deployment not confirmed" "$LOG_FILE"` かつ `grep -q "state=none" "$LOG_FILE"` の AND。`EXIT_CODE` は条件に含めない (理由は Notes の「Tier 2 呼び出し口の非対称性」を参照)
   - `PATTERN_NAME="preview-deployment-absent"`
   - `ANOMALY_DESC`: PR ブランチに deployment が 1 件も存在しない (`state=none`) ため、この provider は GitHub deployment を作らず、リトライでは解消しない構造的 PENDING である旨。`#1128` を参照として含める
   - `IMPROVEMENT_HINT`: `gh api "repos/:owner/:repo/deployments?per_page=1" --jq 'length'` が repo 全体で 0 件なら確定である旨と、プロジェクト側で `PREVIEW_URL` を export して `run-review.sh` を再実行すれば fast path が Deployments API ポーリングを迂回する旨。`modules/orchestration-fallbacks.md#review-pending-not-failure` を参照として含める。文字列中に `PREVIEW_URL` を含めることが AC9 の検証対象
   - **記法の注意**: `ANOMALY_DESC` / `IMPROVEMENT_HINT` は二重引用符文字列であり、バッククォートは既存行と同じく `\`` でエスケープする (エスケープ漏れはコマンド置換として解釈される)

4. **`modules/orchestration-fallbacks.md` — `review-pending-not-failure` への追記** (parallel with 1, 2, 3) (→ AC8)

   `## review-pending-not-failure` セクション (L561-580) の `### Fallback Steps` と `### Escalation` の間に、h3 見出し `### Structural PENDING (retry does not help)` を新設して以下を書く。

   - 見分け方: PENDING メッセージが `state=none` を含む場合、`gh api "repos/:owner/:repo/deployments?per_page=1" --jq 'length'` を実行する。repo 全体で 0 件なら「この provider は GitHub deployment を作らない」ことが確定し、`Fallback Steps` のリトライは何回繰り返しても解消しない
   - 対処: プロジェクト側で `PREVIEW_URL` を export してから `run-review.sh` を再実行する。`run-review.sh` の fast path が Deployments API ポーリングを迂回し、`PREVIEW_URL` への HTTP 到達性 (2xx / 401 / 403) で稼働を判定する
   - 検出: `scripts/detect-wrapper-anomaly.sh` の `preview-deployment-absent` パターン (Step 3) が同じ条件を機械的に検出する
   - `### Rationale` の末尾に本 Issue (`#1128`) を追記する

5. **`docs/tech.md` の同期** (after 1, 2) (→ AC6)

   - `HAS_PR_PREVIEW_CAPABILITY` 行 (L251) の末尾の `Also gates scripts/run-review.sh's pre-session preview deployment wait:` 以降の文を、fast path 込みの記述に更新する。`PREVIEW_URL` が export 済みの場合は Deployments API ポーリングを skip し、`PREVIEW_URL` への HTTP 到達性 (2xx に加え Basic 認証下の 401/403 も稼働とみなす) で判定すること、未設定時は従来どおり Deployments API をポーリングすることを書く。文字列 `fast path` を含めることが AC6 の検証対象
   - `WHOLEWORK_PREVIEW_TIMEOUT_SEC` 行 (L238) の説明を、Deployments API ポーリングと fast path の HTTP 到達性ポーリングの双方に共通の上限である旨に更新する

6. **`docs/ja/tech.md` の同期** (after 5) (→ AC7)

   `docs/translation-workflow.md` の Sync Procedure に従い、Step 5 で変更した 2 行 (L232 の `HAS_PR_PREVIEW_CAPABILITY`、L219 の `WHOLEWORK_PREVIEW_TIMEOUT_SEC`) を日本語で同期する。構造・見出し・表形式は英語版と一致させる。

7. **`docs/guide/customization.md` / `docs/ja/guide/customization.md` の同期判断** (after 1, 2)

   `**Resolving PREVIEW_URL:**` 節と `**Behavior summary:**` 節、および config-reference 表 (英語 L131 / 日本語 L120) の 3 箇所すべてを読み、`run-review.sh` のゲートも同じ `PREVIEW_URL` を読むようになる点を反映すべきか判断して更新する。英語側を変更した場合、`scripts/check-translation-sync.sh` が `docs/guide/*.md` を同期対象に含むため日本語ミラーも必ず更新する。同時に `docs/workflow.md` / `docs/ja/workflow.md` / `docs/structure.md` / `docs/ja/structure.md` の該当行 (Changed Files 参照) も読んで更新要否を確定する。

8. **`tests/run-review.bats` のテスト追加** (after 1, 2) (→ AC10)

   - `setup()` の `unset EMIT_PHASE_NAME EMIT_ISSUE_NUMBER AUTO_SESSION_ID` 行に `PREVIEW_URL` を追加する (親プロセス環境の汚染で既存 preview テストが壊れるのを防ぐ)
   - `curl` mock を `$MOCK_DIR` に追加する (`$PATH` は `$MOCK_DIR` を先頭に持つ)。テストごとに返す HTTP status を切り替えられるようにする
   - `@test` を 4 件追加する: (a) `PREVIEW_URL` 設定 + curl 200 → claude が起動し、`gh api` の Deployments 呼び出しが発生しないこと、(b) `PREVIEW_URL` 設定 + curl 401 → 同様に稼働とみなして起動すること、(c) `PREVIEW_URL` 設定 + curl 000 (到達不可) + `WHOLEWORK_PREVIEW_TIMEOUT_SEC=1` → exit 2 かつ `PENDING:` を含み claude が起動しないこと、(d) `PREVIEW_URL` 未設定 → 既存の Deployments API 分岐に落ちること (`Waiting for PR preview deployment` メッセージで判別)
   - `.wholework.yml` fixture は既存の pr-preview テストと同じ `capabilities:\n  pr-preview: true` 形式を使う

9. **`tests/detect-wrapper-anomaly.bats` のテスト追加** (after 3) (→ AC10)

   `@test` を 3 件追加する: (a) `PENDING: PR preview deployment not confirmed ... state=none` を含むログで `preview-deployment-absent` と `PREVIEW_URL` が出力に現れること、(b) 同じ PENDING 行でも `state=pending` (deployment は存在するが未完了) では検出しないこと、(c) `state=none` のみ、または PENDING 文字列のみでは検出しないこと。既存テストと同じく `--exit-code 2` と `--exit-code 0` の双方で (a) が成立することも確認する。

## Verification

### Pre-merge

- <!-- verify: grep "PREVIEW_URL" "scripts/run-review.sh" --> `scripts/run-review.sh` の preview 待ちゲートが `PREVIEW_URL` 環境変数を参照する fast path を持つ
- <!-- verify: rubric "scripts/run-review.sh の preview 待ちゲートが、PREVIEW_URL が設定されている場合に GitHub Deployments API ポーリングをスキップする fast path を実装している" --> fast path は `PREVIEW_URL` が非空の場合に Deployments API ポーリングをスキップする
- <!-- verify: grep "40[13]" "scripts/run-review.sh" --> fast path の稼働判定基準に 401/403 (Basic 認証保護下の preview) が含まれる
- <!-- verify: rubric "scripts/run-review.sh の fast path が PREVIEW_URL への HTTP 到達性判定で 2xx に加えて 401/403 も preview 稼働とみなす" --> fast path の稼働判定は 2xx に加え 401/403 も稼働とみなす
- <!-- verify: rubric "scripts/run-review.sh の fast path は PREVIEW_URL 未設定時に既存の GitHub Deployments API ポーリング分岐へフォールバックし後方互換を維持している" --> `PREVIEW_URL` 未設定時は現行の Deployments API ポーリングにフォールバックする (後方互換)
- <!-- verify: file_contains "docs/tech.md" "fast path" --> `docs/tech.md` の `HAS_PR_PREVIEW_CAPABILITY` 説明が fast path を反映して更新されている
- <!-- verify: rubric "docs/ja/tech.md の HAS_PR_PREVIEW_CAPABILITY 説明が、run-review.sh の PREVIEW_URL fast path による Deployments API ポーリングのスキップに言及するよう更新されている" --> `docs/ja/tech.md` の対応行が同様に同期されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## review-pending-not-failure" "PREVIEW_URL" --> `review-pending-not-failure` セクションに、deployment を作らない provider の見分け方と `PREVIEW_URL` export による回避策が追記されている
- <!-- verify: grep "PREVIEW_URL" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` に、この構造的 PENDING を Tier 2 の既知パターンとして検出する分岐が追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> `tests/run-review.bats` / `tests/detect-wrapper-anomaly.bats` を含む bats テストが全て pass する (PR route)

### Post-merge

なし

## Tool Dependencies

### Bash Command Patterns

- なし。新規スクリプトを追加しないため、`skills/*/SKILL.md` の `allowed-tools` に追加すべき `${CLAUDE_PLUGIN_ROOT}/scripts/` パターンは無い。`curl` は `scripts/run-review.sh` の内部で実行され、Skill 側からは既存の `${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh:*` 経由で起動されるため新たな許可は不要

### Built-in Tools

- なし (`Read` / `Edit` / `Grep` は `/code` の既存 `allowed-tools` に含まれる)

### MCP Tools

- なし

## Uncertainty

- **curl 未検出時の fail-open 分岐に bats カバレッジが無い**: Step 2 の `command -v curl` 偽ブランチは、bats から `curl` を PATH ごと除去して再現しようとすると `gh` / `date` / `sleep` などの mock 解決も同時に壊れるため、現実的なテスト手段が無い。
  - **検証方法**: コードリーディングによる確認のみ。実装時に `bash -n scripts/run-review.sh` で構文を確認し、分岐の到達性はレビューで担保する
  - **影響範囲**: Implementation Steps 2 のみ。fail-open のため、この分岐に不具合があっても発現は「curl が無い環境で PENDING にならず review が起動する」であり、修正前の挙動 (常に PENDING) より悪化しない

## Notes

### Tier 2 呼び出し口の非対称性 (Step 3 の設計根拠)

`detect-wrapper-anomaly.sh` の呼び出し口は 2 つあり、渡される `--exit-code` が異なる。

| 呼び出し口 | 渡される exit code | 位置づけ |
|-----------|------------------|---------|
| `scripts/run-auto-sub.sh` L756 (`_complete_phase_after_success`) | `0` 固定 | wrapper が成功した場合の silent no-op 検出専用 |
| `skills/auto/SKILL.md` L955 (Tier 2) | 実際の `$EXIT_CODE` | Issue 本文が言う「Tier 2 の既知パターン」 |

このため新パターンの検出条件を `EXIT_CODE == 2` で絞ると、`skills/auto/SKILL.md` 経由でしか発火しなくなる。ログ文字列 2 本 (`PENDING: PR preview deployment not confirmed` と `state=none`) の AND という十分に特異な条件にすることで、どちらの呼び出し口からでも一貫して発火する。

あわせて、`run-auto-sub.sh` の bash 側 Tier 2 は `apply-fallback.sh` であり `detect-wrapper-anomaly.sh` ではない点も記録しておく。`apply-fallback.sh` のハンドラは「自動復旧を実行して exit 0 を返す」契約だが、本件の復旧手段は「プロジェクト側で `PREVIEW_URL` を export する」であり upstream から自動実行できない (`#781` の設計判断)。したがって `apply-fallback.sh` への追加は本 Issue のスコープ外とし、検出のみを `detect-wrapper-anomaly.sh` に持たせる。

### 認証情報の取り扱い (credential/security policy alignment)

`PREVIEW_URL` は `https://user:pass@host/` 形式で Basic 認証情報を埋め込める。fast path のログに URL 値をそのまま出すとこれが平文で残るため、Step 2 では HTTP status code のみを出力する。`modules/verify-executor.md` の「Basic Authentication Support」節が `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` をログにマスクする方針と整合する。

また、fast path 側では `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` を読まない (curl の `--config` によるクレデンシャル注入を行わない)。401/403 を稼働とみなす判定により認証を通す必要が無く、wrapper に新たなクレデンシャル取り扱い面を作らずに済むため。`PREVIEW_BASIC_*` は引き続き verify-executor の責務に留める。

### curl 未検出時の fail-open

`command -v curl` が偽のとき、Deployments API 分岐へフォールバックする案もあるが、それは本 Issue が修正しようとしている失敗経路そのものに戻る。`PREVIEW_URL` がプロジェクト側の責務であるという契約 (`docs/guide/customization.md`) を尊重し、プローブ不能時は稼働とみなして review を起動する (fail-open)。この fail-open は `capabilities.pr-preview: true` かつ `PREVIEW_URL` 設定済みという二重の前提下でのみ到達する。

### ツール検出パターンの一貫性

`command -v curl` は `scripts/run-review.sh` 内の既存 `_gh_api_bounded()` が使う `command -v timeout` / `command -v gtimeout` と同じ idiom。新しい検出方式は導入しない。

### bash 3.2 互換

開発環境は macOS system bash 3.2.57 (実測)。Step 2 の HTTP status 判定は `case ... in 2??|401|403)` 形式で書き、`mapfile` などの bash 4 以降の機能は使わない。

### verify command の適用範囲

Issue 本文の Pre-merge 条件はすべて `modules/verify-executor.md` の built-in 変換表 (`grep` / `rubric` / `file_contains` / `section_contains` / `github_check`) に含まれるため、`docs/environment-adaptation.md` Extension Guide の adapter 調査は不要。BRE メタ文字 (`\|` `\(` `\)` `\+` `\?`) を含む `grep` パターンも無い (`40[13]` は ERE の文字クラスとして意図どおり動作する)。`ALWAYS_PR=false` かつ Size=L (pr route) のため `github_check "gh pr checks"` 形式が正しく、`gh run list` 形式への自動修正は行わない。`Run bats tests` は `.github/workflows/test.yml` L9 の実際の job name と一致することを確認済み。

### 新規外部依存

`curl` は `scripts/run-review.sh` にとって新規の外部コマンド依存だが、macOS / 主要 Linux CI イメージにプリインストールされており、`modules/verify-executor.md` の `http_status` / `html_check` / `api_check` が既に前提としている。インストール手順の追加は不要とし、代わりに Step 2 の `command -v curl` ガードで未検出時の挙動を明示する。

### 派生論点の扱い

Issue 本文の「派生論点」2 件 (`/auto` 経由で `PREVIEW_URL` を export するフックの整備、`--when` ガード未尊重疑いの切り分け) は `## Out of Scope` に明記済みでスコープ外。本 Spec でも実装ステップを起こさない。ただし、本 Issue の修正後も `/auto` 経由では `PREVIEW_URL` が設定されないままなので、`capabilities.pr-preview: true` かつ deployment を作らない provider のプロジェクトでは引き続き Deployments API 分岐に落ちて PENDING になる。この場合に Step 3 の `preview-deployment-absent` パターンが「`PREVIEW_URL` を export せよ」と案内する構造になっており、本 Issue のスコープ内で運用上の出口は確保されている。

### Autonomous Auto-Resolve Log

- **fast path も既存分岐と同じくタイムアウトまでポーリングする (1 回プローブで打ち切らない)** — reason: ゲート本来の目的 (`#1050`: 未稼働 preview に対して review を起動しない) は「待つ」ことなので、単発プローブでは preview 起動待ちの取りこぼしが出る。既存 Deployments API 分岐と同じ `_preview_timeout_sec` / `sleep 30` を再利用するのが最小の一貫した設計
  - Other candidates: 1 回だけプローブして即判定 — 稼働直前のタイミングで PENDING に落ちる確率が上がるため不採用
- **curl 未検出時は fail-open (稼働とみなして起動)** — reason: Deployments API へのフォールバックは本 Issue が修正する失敗経路そのものに戻る。`PREVIEW_URL` がプロジェクト側責務という既存契約を尊重する
  - Other candidates: Deployments API 分岐へフォールバック / 無条件 PENDING — いずれも本 Issue の症状を再現するため不採用
- **`detect-wrapper-anomaly.sh` の新パターンは EXIT_CODE を条件に含めずログ文字列のみで判定する** — reason: 呼び出し口 2 つで渡される exit code が非対称 (上記「Tier 2 呼び出し口の非対称性」)。ログ文字列 2 本の AND で十分に特異
  - Other candidates: `EXIT_CODE == 2` を AND 条件に加える — `run-auto-sub.sh` 経由では永久に発火しなくなるため不採用
- **`docs/guide/customization.md` (+ ja ミラー) を Steering Docs sync candidate として Changed Files に含める** — reason: `#1035` の retro で「同じ挙動を説明する prose 箇条書き / 変数テーブル / config-reference 表の sync 漏れ」が 2 サイクル連続で発生した記録がある。`PREVIEW_URL` の契約 SSoT はこのファイルなので、候補として明示し `/code` に include/exclude を委ねる
  - Other candidates: `docs/tech.md` / `docs/ja/tech.md` のみに絞る (AC が要求するのはこの 2 ファイルのみ) — 契約 SSoT が古いまま残るため不採用
- **fast path のログに `PREVIEW_URL` の値を出力しない** — reason: `https://user:pass@host/` 形式でクレデンシャルが埋まりうる。`modules/verify-executor.md` のマスク方針と整合させる
  - Other candidates: デバッグ性を優先して URL を出力する — ログが CI アーティファクトや Issue コメントに残る経路があるため不採用

## issue retrospective

### Ambiguity Resolution Rationale

Issue 本文には `## Acceptance Criteria` セクションが存在しなかったため (`## Proposal (Outline)` に自然文で提案が書かれているのみ)、Proposal の内容を Pre-merge 条件として分解し、verify command を割り当てた。Post-merge は「なし」とした — 変更対象 (`scripts/run-review.sh` の分岐追加、`docs/tech.md` / `docs/ja/tech.md` の記述同期、`modules/orchestration-fallbacks.md` への追記、`scripts/detect-wrapper-anomaly.sh` へのパターン追加) はすべてリポジトリ内で機械的に検証可能であり、マージ後の環境観測を要する条件が存在しないため。

`PREVIEW_URL` 未設定時のフォールバック挙動と、fast path の稼働判定基準 (2xx に加え 401/403 を稼働とみなす) は文言のニュアンスが評価対象になるため `rubric` を用い、対象ファイル・キーワードが事前に予測できる箇所には `grep` / `file_contains` / `section_contains` を補助チェックとして併記した (`modules/verify-patterns.md` §9 のガイドラインに従う)。

### Key Policy Decisions (Non-Interactive Auto-Resolve Log)

- **Post-merge を「なし」とする** — reason: 本 Issue の変更範囲は全てマージ前に本リポジトリ内で検証できるため
  - Other candidates: `/auto` 経由の実運用確認を Post-merge (verify-type: manual) として追加する案 — 検証対象が downstream リポジトリでの観測になり本リポジトリの `/verify` では確認できないため不採用
- **Size = L** (Axis1: 対象5ファイルで M 相当 [3–5] の上限、Axis2: `run-review.sh` と `detect-wrapper-anomaly.sh` の2本にまたがるスクリプトロジック変更で +1 段) — reason: `modules/size-workflow-table.md` の「Script logic changes (adding branches, ...)」がスクリプト2本に該当するため
  - Other candidates: M のまま据え置き — スクリプトロジック変更の重みを軽視することになるため不採用
- **派生論点 (`/auto` 経由で `PREVIEW_URL` を export するフックの整備) を本 Issue のスコープ外とする** — reason: Issue 本文中で著者自身が「別 Issue にすべきかもしれない」と留保しており、AC の文言はどちらの選択でも影響を受けない低優先度のあいまいさのため自動解決。`## Out of Scope` に明記して追跡可能にした
  - Other candidates: 本 Issue の AC に含める — 本件の主目的 (wrapper/skill 契約不整合の解消) と混ざり検証範囲が拡散するため不採用
- **`--when="test -n \"$PREVIEW_URL\""` ガード未尊重疑いの切り分け調査を本 Issue のスコープ外とする** — reason: 特定の過去 review 実行に対する事後調査であり、完了条件を AC として固定できるほど検証対象が定まっていないため
  - Other candidates: Post-merge (manual) AC として追加 — 調査対象が「未確認」の域を出ておらず完了条件を定義できないため不採用

### Acceptance Criteria Changes

- `## Acceptance Criteria` セクション (Pre-merge 9件 / Post-merge なし) を新設。既存の `## Proposal (Outline)` の3項目 (fast path 追加・稼働判定基準・フォールバック) と、あわせて記載の3項目 (`docs/tech.md` / `docs/ja/tech.md` 同期・`orchestration-fallbacks.md` 追記・`detect-wrapper-anomaly.sh` パターン追加) をそれぞれ Pre-merge 条件化し、bats テスト pass (PR route, `gh pr checks` 形式) を1件追加した
- `## Out of Scope` に2項目 (`/auto` の `PREVIEW_URL` export フック整備、fail-open 疑いの切り分け調査) を追記し、`## 派生論点` で著者が留保した論点を明示的にスコープ外として固定した

### Triage Summary

Type=Bug, Priority=検出なし, Size=L, Value=3 (Impact=2 [shared: `modules/` 変更 +2]、Alignment=3 [Vision: harness の契約整合性に直結])。重複候補・停滞パターン・未解決の blocked-by 依存はいずれも検出されなかった。

## spec retrospective

### Minor observations

- 「Tier 2」という語が 2 つの異なる実装を指している。`skills/auto/SKILL.md` の Tier 2 は `detect-wrapper-anomaly.sh` を実 exit code 付きで呼ぶが、`scripts/run-auto-sub.sh` の Tier 2 は `apply-fallback.sh` であり、`detect-wrapper-anomaly.sh` は exit 0 の成功経路 (`_complete_phase_after_success`) から `--exit-code 0` 固定で呼ばれるだけ。Issue 本文の「Tier 2 で既知パターンとして拾えるようにする」という表現はこの二重性を前提にしておらず、実装条件を exit code で絞ると片方でしか発火しない設計になっていた
- Issue の Auto-Resolve Log が Size=L の根拠を「対象5ファイル」としていたが、Steering Docs sync candidate まで含めると 12 ファイルになった。triage 時点の Size は粗い見積もりであり、実質的な確定は Spec 側の再評価 (`/spec` Step 18) が担っている

### Judgment rationale

- fast path を「1 回プローブ」ではなく「タイムアウトまでポーリング」にした。ゲートの目的 (`#1050`) が「未稼働 preview に対して review を起動しない」ことである以上、待機は本質的な機能であり、既存 Deployments API 分岐と同じ `_preview_timeout_sec` / `sleep 30` を再利用するのが最小の一貫した設計になる
- curl 未検出時を fail-open (稼働とみなして起動) にした。Deployments API 分岐へのフォールバックは本 Issue が修正しようとしている失敗経路そのものに戻ってしまうため、`PREVIEW_URL` がプロジェクト側責務という既存契約 (`docs/guide/customization.md`) を優先した
- `detect-wrapper-anomaly.sh` の新パターンから `EXIT_CODE` 条件を外し、ログ文字列 2 本 (`PENDING: PR preview deployment not confirmed` と `state=none`) の AND だけで判定することにした。上記「Tier 2 の二重性」への直接の対処であり、`state=none` が「deployment が 1 件も無い」= 構造的、`state=pending` が「deployment はあるが未完了」= 一時的、という判別軸をそのまま検出条件に写している

### Uncertainty resolution

- `PREVIEW_URL` が `claude -p` の review セッションへ伝播するかは未確認だったが、`scripts/run-review.sh` が `env -u CLAUDECODE` で `CLAUDECODE` のみを除去し他の環境変数はそのまま継承させていることをコードで確認して解決した (伝播する)。wrapper 側のゲートと `skills/review/SKILL.md` Step 8.0 の fast path が同じ値を見る前提が成立する
- curl の `%{http_code}` が接続失敗時に何を返すかは未確認だったが、`curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 3 <存在しないホスト>` を実行して stdout に `000` / exit code 6 を実測した。`set -euo pipefail` 下では `|| true` で終了コードを吸収しないと wrapper 全体が abort するという実装制約に落とし込んで Implementation Steps に明記した
- 未解決のまま残したのは curl 未検出分岐の bats カバレッジのみ。`## Uncertainty` に検証方法と影響範囲を記載した

## Code Retrospective

### Deviations from Design

- なし。Implementation Steps 1–9 を設計どおりに実装した。

### Design Gaps/Ambiguities

- なし。Step 7 の Steering Docs sync candidate 判断 (`docs/guide/customization.md` / `docs/ja/guide/customization.md` は「wrapper も同じ `PREVIEW_URL` を読む」旨を追記して更新、`docs/workflow.md` / `docs/ja/workflow.md` の Review PENDING retry 記述と `docs/structure.md` / `docs/ja/structure.md` の 1 行説明はいずれも既存の記述と矛盾せず汎用的に成立するため更新不要と判断) は Spec が想定した「`/code` に委ねる」判断そのものであり、実装時に新たな曖昧さは生じなかった。

### Rework

- なし。

## review retrospective

### Spec vs. implementation divergence patterns

- Spec/Implementation 自体 (`run-review.sh` のロジック) には divergence なし。ただし `/code` フェーズで追加した Steering Docs 同期文 (`docs/guide/customization.md` / `docs/ja/guide/customization.md`) に「Deployments API を indefinitely (無期限に) ポーリングする」という表現があり、同じ PR で更新した `docs/tech.md` の「`WHOLEWORK_PREVIEW_TIMEOUT_SEC` で打ち切られる」という記述と矛盾していた。実装は最初から bounded (timeout → `PENDING` exit) だったが、prose 側の記述だけが unbounded であるかのように書かれており、実装とドキュメントの間の drift として Workflow review (adversarial verify) で検出・修正した
- `docs/tech.md` の `HAS_PR_PREVIEW_CAPABILITY` 説明が「`skills/review/SKILL.md` Step 8.0 の契約と一致する」と書いていたが、実際に一致するのは「`PREVIEW_URL` 設定時に Deployments API lookup を skip する」部分のみで、2xx/401/403 による HTTP reachability probe は `run-review.sh` 側の新規挙動だった。「一致する」の範囲を精査せずに広く書いてしまう pattern も divergence の一種として記録

### Recurring issues

- 同一テーマの指摘が en/ja ミラー双方に重複して出現した (「indefinitely」表現 ×2、「一致する」の過大表現 ×2)。Steering Docs sync で日本語ミラーを追記する際、英語側の不正確な表現をそのまま翻訳してしまうと、修正時も両言語で同じ修正を重複して行う必要が生じる。英語側のドキュメント文言を書く時点で「bounded by X」を明示する習慣があれば、ミラー側の修正コストも同時に防げた
- `scripts/detect-wrapper-anomaly.sh` の `IMPROVEMENT_HINT` に二重エスケープバグ (`\\\"` → 出力にバックスラッシュが残る) があったが、bats テストは `preview-deployment-absent` / `PREVIEW_URL` という部分文字列の有無しか assert しておらず、エスケープの破損を検知できなかった。生成される診断メッセージ内に埋め込みコマンド文字列がある場合、bats アサーションを「部分文字列の有無」だけでなく「実際にシェルとして valid か」まで踏み込ませるか、rubric verify command 側でエスケープの妥当性を明示的に問う設計が今後の再発防止に有効

### Acceptance criteria verification difficulty

- 10 件の pre-merge AC (grep 3件、file_contains 1件、section_contains 1件、github_check 1件、rubric 4件) はいずれも一発で PASS し、UNCERTAIN は 0 件だった。grep/section_contains/file_contains は対象文字列がそのまま実装に存在し曖昧さがなく、rubric 4件もアドバーサリアルグレーダーへの丸投げで迷いなく判定できた。verify command の設計自体に改善の余地はなし

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- Workflow モード (finder×3 → adversarial verify) で `/review` を実行し、17 件の指摘のうち 6 件 (統合後 4 件のコメント) が生存。いずれも MUST ではなく SHOULD/CONSIDER のドキュメント精度・診断メッセージのエスケープ修正であり、全て `/review` 内で修正・push 済み
- 修正はすべて低リスクな文言/エスケープ修正であり `run-review.sh` / `detect-wrapper-anomaly.sh` のロジック自体には変更を加えていない。Step 13 のポリシー変更判定でも "no policy change" と判断し、Issue の Acceptance Criteria 更新は不要と結論した
- 修正後に `python3 scripts/validate-skill-syntax.py skills/` (0 error)、`bats tests/run-review.bats` (38/38)、`bats tests/detect-wrapper-anomaly.bats` (45/45) を再実行し回帰がないことを確認した

### Deferred Items

- `/auto` 経由で `PREVIEW_URL` を export するフックの整備 — Issue の `## Out of Scope` で別 Issue に分離済み。`/merge` 後も未着手のまま
- `--when="test -n \"$PREVIEW_URL\""` ガード未尊重疑いの切り分け調査 — 同じく `## Out of Scope`、未着手
- `scripts/apply-fallback.sh` への `preview-deployment-absent` ハンドラ追加 — 自動復旧手段が存在しないため本 Issue では検出のみ

### Notes for Next Phase

- `/merge` は通常のマージ手順でよい。MUST issue はなく、CI (9/9 SUCCESS) と全 10 pre-merge AC (すべて PASS) は確認済み
- Post-merge 検証条件は Issue 本文に「なし」と明記されているため、`/verify` は AC チェックのみで完了する見込み
