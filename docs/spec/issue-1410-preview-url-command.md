# Issue #1410: run-review: project-side スクリプトで PREVIEW_URL を自動解決する preview-url-command 設定キーを追加

## Overview

`.wholework.yml` に `preview-url-command` キーを追加し、`scripts/run-review.sh` の preview 待ちゲートが、`PREVIEW_URL` 未設定時にそのコマンドを実行して `PREVIEW_URL` を解決・export できるようにする。

これにより、GitHub deployment を作らない hosting provider (AWS Amplify Hosting 等) を使うプロジェクトでも、`/auto` 経由・スケジュール実行・`run-review.sh` 直接実行のいずれでも設定 1 行で preview 層 AC が動作するようになる。`#781` の設計判断 (provider 別 adapter は upstream に持たない) は維持し、「プロジェクト側スクリプトを呼び出す汎用フック」だけを追加する。

`PREVIEW_URL` が既に export 済みの場合は `#1128` の fast path をそのまま使い、`preview-url-command` の解決は行わない。コマンドが失敗・空出力・非 URL 出力の場合は既存の GitHub Deployments API ポーリング経路にフォールバックする (後方互換)。

## Consumed Comments

No new comments since last phase.

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `preview-url-command` → `PREVIEW_URL_COMMAND` の行を追加。YAML Parsing Rules に `preview-url-command` は `production-url` と同じ文字列扱い (引用符除去) である旨と、`get-config-value.sh` がインラインコメントを除去する仕様上、コマンド文字列に半角スペース + `#` を含められない制約を追記。Output Format の変数一覧に `PREVIEW_URL_COMMAND` を追加
- `scripts/run-review.sh`: `_gh_api_bounded()` の隣に `_resolve_preview_url_command()` を追加し、`capabilities.pr-preview` ゲート内の `_preview_timeout_sec` 代入直後・`if [[ -n "${PREVIEW_URL:-}" ]]` の直前で呼び出す — bash 3.2+ 互換 (`${var//pattern/replacement}` と `case` のみ使用。`mapfile` / 連想配列は使わない)
- `tests/run-review.bats`: `preview-url-command` の分岐を検証する新規 `@test` を 6 件追加 (詳細は Implementation Steps 4)
- `docs/guide/customization.md`: Available Keys 表 (`.wholework.yml` キーの SSoT) に `preview-url-command` 行を追加。"Resolving `PREVIEW_URL`" 節に説明・サンプル設定・呼び出し規約・カバー範囲 (wrapper 経路のみ) を追記
- `docs/ja/guide/customization.md`: [translation sync] 上記 2 箇所の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う。コードフェンス数の一致を確認する)
- `docs/guide/adapter-guide.md`: `.wholework/adapters/` 配下の project-local スクリプトを `preview-url-command` から呼び出すパターンへの参照を追記 (adapter 自体の同梱は引き続き対象外)
- `docs/ja/guide/adapter-guide.md`: [translation sync] 上記の日本語ミラーを同期
- `docs/tech.md`: Capability Flags 表の `HAS_PR_PREVIEW_CAPABILITY` 行に、`PREVIEW_URL` 未設定時に `preview-url-command` を先に解決してから fast path に入る旨を追記 (`skills/spec/skill-dev-constraints.md` の #250 制約: 新規 `.wholework.yml` キー追加時は `docs/tech.md` を Changed Files に含める)
- `docs/ja/tech.md`: [translation sync] 上記の日本語ミラーを同期
- `modules/orchestration-fallbacks.md`: [Steering Docs sync candidate] `review-pending-not-failure` 節の "Structural PENDING" の **Fix** 行 (「export `PREVIEW_URL` on the project side, then re-run `run-review.sh`」) に `preview-url-command` を宣言する選択肢を追記。同節 Rationale 末尾に本 Issue の拡張を 1 行追加
- `scripts/detect-wrapper-anomaly.sh`: [Steering Docs sync candidate] `preview-deployment-absent` パターンの `IMPROVEMENT_HINT` (「Export `PREVIEW_URL` on the project side and re-run `run-review.sh`」) に `preview-url-command` を宣言する選択肢を追記 — bash 3.2+ 互換。`tests/detect-wrapper-anomaly.bats` は `PREVIEW_URL` の部分文字列一致のみを assert しているため、既存テストは変更不要 (`PREVIEW_URL` の語は残す)

**変更不要 (grep で確認済み):**

- `docs/structure.md`: `scripts/run-review.sh` / `scripts/get-config-value.sh` / `scripts/detect-wrapper-anomaly.sh` は既に列挙済みで、いずれの記述も本変更後も正確 (新規スクリプト・新規ディレクトリの追加が無い)
- `docs/environment-adaptation.md`: Layer 1 の `.wholework.yml` サンプルは部分例 (`always-pr` / `autonomy` / `capabilities.pr-preview` 等の既存キーも未記載) であり、キーの網羅表ではない
- `scripts/get-config-value.sh`: `preview-url-command` はフラットな文字列キーで、同スクリプト header の Supported Input Shapes 表の行 1 (Flat key) にそのまま該当する。パーサ変更は不要
- `skills/review/SKILL.md`: Step 8.0 は変更しない (理由は Notes「`/review` skill 直接実行を対象外にした理由」参照)
- `.claude/settings.json` / SKILL.md の `allowed-tools`: `get-config-value.sh` を呼ぶのは bash wrapper (`run-review.sh`) のみで、SKILL.md 本文から新規スクリプトを呼ぶ変更が無いため追加不要

## Implementation Steps

1. `modules/detect-config-markers.md` を編集する (→ acceptance criteria AC1, AC2)。Marker Definition Table の `production-url` 行の直後に、`| preview-url-command | PREVIEW_URL_COMMAND | Command string (extract value as-is) | "" |` の行を追加する。YAML Parsing Rules に「`preview-url-command` is treated as a shell command string with quotes removed (same handling as `production-url`). Because `scripts/get-config-value.sh` strips everything from an inline ` #` onward, the command string must not contain a space followed by `#`」を追記する。Output Format のコードブロックに `PREVIEW_URL_COMMAND: shell command string extracted from preview-url-command (default: "")` を追加する

2. `scripts/run-review.sh` に `_resolve_preview_url_command()` を追加する (parallel with 1) (→ acceptance criteria AC3, AC4, AC5)。関数定義は既存の `_gh_api_bounded()` 定義の直後に置き、呼び出しは `_preview_timeout_sec="${WHOLEWORK_PREVIEW_TIMEOUT_SEC:-600}"` の代入直後・`if [[ -n "${PREVIEW_URL:-}" ]]; then` の直前に `[[ -z "${PREVIEW_URL:-}" ]] && _resolve_preview_url_command || true` の形で置く。処理内容:
   - `"$SCRIPT_DIR/get-config-value.sh" preview-url-command ""` でコマンド文字列を取得する
   - `{pr}` プレースホルダを `$PR_NUMBER` に置換する (`${_cmd//\{pr\}/$PR_NUMBER}`)。`$PR_NUMBER` は同スクリプト冒頭で `^[0-9]+$` 検証済みのため、置換値に injection 経路は無い
   - `timeout --kill-after=10 30` / `gtimeout 30` / 素の実行、の順にフォールバックして `bash -c "$_cmd"` を実行する (既存 `_gh_api_bounded()` と同じ 3 段フォールバック)
   - 標準出力の 1 行目を取り、CR と前後空白を除去する
   - 成功時は `PREVIEW_URL` に代入して `export` し (`claude -p` 子プロセスに継承させるため必須)、`Resolved PREVIEW_URL via preview-url-command for PR #<N>` を stderr に出力する
   - 変数はすべて `local` 宣言し、`local x=$(cmd)` 形式は使わない (`local` が終了ステータスを隠すため宣言と代入を分ける)

3. Step 2 の関数の分岐挙動を、以下の表のとおり全列挙で実装する (after 2) (→ acceptance criteria AC4, AC5)。本ゲートは review セッションの起動可否を決める fail-safe critical な gate であるため、各エッジケースの期待挙動を明示する:

   | 条件 | 挙動 |
   |------|------|
   | `PREVIEW_URL` が既に非空で export 済み | 解決処理を実行しない。既存の `#1128` fast path をそのまま実行 (挙動不変) |
   | `preview-url-command` が未設定 / 空文字 | 解決処理を実行しない。既存の Deployments API ポーリング経路へ (挙動不変) |
   | コマンドが非 0 で終了 (timeout kill 含む) | stderr に warning を出し解決失敗。Deployments API 経路へフォールバック |
   | コマンドが 0 で終了、出力が空 / 空白のみ | stderr に warning を出し解決失敗。Deployments API 経路へフォールバック |
   | コマンドが 0 で終了、出力が 2048 文字超 | stderr に warning を出し解決失敗。Deployments API 経路へフォールバック (暴走コマンドの巨大出力を `curl` に渡さないため) |
   | コマンドが 0 で終了、出力が `http://` / `https://` で始まらない | stderr に warning を出し解決失敗。Deployments API 経路へフォールバック (`file://` 等を `curl` / `{{base_url}}` に渡さないため) |
   | コマンドが 0 で終了、出力が妥当な http(s) URL | `PREVIEW_URL` に設定+export し、既存の `#1128` fast path (HTTP 到達性ポーリング、上限 `WHOLEWORK_PREVIEW_TIMEOUT_SEC`) へ進む |
   | 解決成功したが `curl` が無い | 既存の fail-open 分岐 (probe をスキップし `PREVIEW_URL` をそのまま採用) — 挙動不変 |
   | 解決成功したが timeout 内に到達不能 | 既存の PENDING (exit code 2、`PR preview URL not reachable`) — 挙動不変 |

   フォールバック方向の根拠: いずれの失敗系も「本 Issue 以前の既存挙動に戻す」だけであり、新たな fail-open も fail-closed も導入しない。これは AC5 が要求する後方互換そのものである

4. `tests/run-review.bats` に新規 `@test` を 6 件追加する (after 2, 3) (→ acceptance criteria AC7)。既存スイートが PASS することだけでなく、新規ロジックを検証する以下の新規テストケースを追加したうえでスイートが PASS すること:
   - `success: preview-url-command resolves PREVIEW_URL when the env var is unset`
   - `success: exported PREVIEW_URL takes precedence over preview-url-command`
   - `success: preview-url-command {pr} placeholder is substituted with the PR number`
   - `fallback: preview-url-command failure falls back to the Deployments API branch`
   - `fallback: preview-url-command empty output falls back to the Deployments API branch`
   - `fallback: preview-url-command non-URL output falls back to the Deployments API branch`

   既存 `setup()` の `get-config-value.sh` モックは `permission-mode` 以外のキーに `$DEFAULT` (空文字) を返すため、既存テストは無改修で従来経路を通る。新規テストは各 `@test` 内でこのモックを上書きして `preview-url-command` を返させる。`setup()` の `unset` 行に `PREVIEW_URL` が既に含まれている点は変更不要。優先順位テストとコマンド未実行の確認は、コマンド側でマーカーファイルを書き出しその不在を assert する形で行う

5. `docs/guide/customization.md` を編集する (parallel with 1, 2) (→ acceptance criteria AC6)。(a) Available Keys 表 (`.wholework.yml` キーの SSoT) の `production-url` 行の直後に `preview-url-command` 行を追加する。説明には型 (string)、既定値 (`""`)、`{pr}` プレースホルダ規約、`run-review.sh` の preview ゲートのみが参照すること、` #` を含められない制約を含める。(b) "Resolving `PREVIEW_URL`" 節の末尾に、`preview-url-command` の説明・yaml サンプル設定 (`preview-url-command: ".wholework/adapters/resolve-preview-url.sh {pr}"`)・優先順位 (export 済み `PREVIEW_URL` > `preview-url-command` > Deployments API)・失敗時フォールバック・カバー範囲 (`run-review.sh` 経由 = `/auto`・スケジュール実行・wrapper 直接実行。`/review` skill を直接呼ぶ場合は従来どおり手動 export が必要) を追記する

6. `docs/guide/adapter-guide.md` を編集する (after 5) (→ acceptance criteria AC6 の周辺整合)。"Prerequisites > Declare capabilities in `.wholework.yml`" 節または "Further Reading" 節に、`.wholework/adapters/` に置いた project-local スクリプトを `.wholework.yml` の `preview-url-command` から呼び出して `PREVIEW_URL` を解決するパターンと、`docs/guide/customization.md` の該当節への相互参照を 1 段落追記する。provider 別 adapter を bundled adapter として同梱する話ではない旨を明記する

7. `docs/tech.md` の Capability Flags 表 `HAS_PR_PREVIEW_CAPABILITY` 行を編集する (after 2)。「When `PREVIEW_URL` is unset, `run-review.sh` falls back to polling the GitHub Deployments API」という既存記述の直前に、`PREVIEW_URL` 未設定かつ `.wholework.yml` に `preview-url-command` が宣言されている場合はまずそのコマンドを実行して `PREVIEW_URL` を解決し、解決できたときのみ fast path に入る旨を挿入する

8. `modules/orchestration-fallbacks.md` と `scripts/detect-wrapper-anomaly.sh` の復旧ガイダンスを同期する (after 2)。前者は `review-pending-not-failure` 節「Structural PENDING」の **Fix** 行に「または `.wholework.yml` に `preview-url-command` を宣言して恒久化する」旨を追記し、同節 Rationale 末尾に「Extended in Issue #1410: ...」の 1 行を追加する。後者は `preview-deployment-absent` パターンの `IMPROVEMENT_HINT` 文字列に同じ選択肢を追記する。`tests/detect-wrapper-anomaly.bats` は `PREVIEW_URL` の部分文字列一致のみを assert しているため、`PREVIEW_URL` の語を残す限りテスト変更は不要

9. `docs/ja/guide/customization.md` / `docs/ja/tech.md` / `docs/ja/guide/adapter-guide.md` を同期する (after 5, 6, 7)。`docs/translation-workflow.md` の Sync Procedure に従い、構造・見出し・書式を英語版に合わせたうえで日本語で記述する。コードフェンス (3 連バッククォート) の個数が英語版と一致することを確認する

## Alternatives Considered

- **PR 番号の渡し方: 環境変数 (`WHOLEWORK_PR_NUMBER`) を export する案 (不採用)** — 設定を書く側から見て「PR 番号がどこから来るか」が暗黙になり、`{pr}` 置換より自己記述性が低い。またコマンド文字列の任意の位置 (`--pr={pr}` 等) に埋め込めない。Issue 本文のサンプルも `{pr}` 形を示している
- **PR 番号の渡し方: コマンド末尾に位置引数として自動追加する案 (不採用)** — プロジェクト側スクリプトの引数順を upstream が固定してしまい、`--flag` 付きコマンドで破綻する
- **`preview-url-command` の代わりに `preview-url` capability adapter (`modules/preview-url-adapter.md`) を新設する案 (不採用)** — `modules/adapter-resolver.md` は skill が "Read and follow" する LLM 駆動モジュールであり、bash wrapper である `run-review.sh` からは呼び出せない。Issue の主目的は `/auto` 経由 (= wrapper 経路) の解決であるため、adapter chain には乗せず設定キー + wrapper 実装とする
- **解決コマンドを `WHOLEWORK_PREVIEW_TIMEOUT_SEC` の上限内でリトライし続ける案 (不採用)** — AC5 が「コマンド失敗・空出力時は既存の Deployments API ポーリングにフォールバック」を明示的に要求している。外側のリトライは `run-review.sh` の PENDING (exit code 2) を受けた `WHOLEWORK_REVIEW_PENDING_RETRY_SEC` / `WHOLEWORK_REVIEW_PENDING_MAX_RETRIES` の既存機構が担う
- **コマンド実行のタイムアウトを新規 `.wholework.yml` キーで可変にする案 (不採用)** — 実測ニーズが無い段階で設定面を増やす。同ファイル内の `_gh_api_bounded()` が採る固定 30 秒と揃える

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md のマーカー定義表に preview-url-command キーと対応変数が追加されている" --> `.wholework.yml` で `preview-url-command` を宣言できるよう `detect-config-markers.md` が拡張されている
- <!-- verify: grep "preview-url-command" "modules/detect-config-markers.md" --> `detect-config-markers.md` に `preview-url-command` エントリが追加されている
- <!-- verify: grep "preview-url-command" "scripts/run-review.sh" --> `scripts/run-review.sh` が `preview-url-command` を参照する fast path を持つ
- <!-- verify: rubric "scripts/run-review.sh の fast path が、PREVIEW_URL 未設定かつ preview-url-command が宣言されている場合に該当コマンドを実行し PREVIEW_URL を解決する" --> fast path は `PREVIEW_URL` 未設定時に `preview-url-command` を実行して解決する
- <!-- verify: rubric "scripts/run-review.sh の fast path は preview-url-command の実行が失敗または空出力の場合、既存の GitHub Deployments API ポーリング経路にフォールバックし後方互換を維持している" --> コマンド失敗・空出力時は既存の Deployments API ポーリングにフォールバックする (後方互換)
- <!-- verify: file_contains "docs/guide/customization.md" "preview-url-command" --> `docs/guide/customization.md` に `preview-url-command` の説明とサンプル設定が追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 関連する bats テストが全て pass する (PR route)。Implementation Steps 4 の新規 `@test` 6 件を追加したうえでスイートが PASS すること

### Post-merge

- preview-url-command を宣言した実プロジェクトで `/auto` を実行し、`PREVIEW_URL` が自動解決され review フェーズの preview 層 AC が `--when` ガードを通過して実行されることを観察 <!-- verify-type: opportunistic event=review-run -->

## Tool Dependencies

### Bash Command Patterns

- なし (`bats:*` は `skills/code/SKILL.md` の `allowed-tools` に登録済み。新規スクリプトの追加が無いため `allowed-tools` の追記は不要)

### Built-in Tools

- なし (Read / Edit / Write / Grep / Glob はいずれも登録済み)

### MCP Tools

- なし

## Uncertainty

- **[`get-config-value.sh` がコマンド文字列を正しく返すか]**: 引用符付き / 引用符なし / インラインコメントを含む値での挙動が設計前提。
  - **検証方法**: `WHOLEWORK_CONFIG_PATH` を一時 YAML に向けて `scripts/get-config-value.sh preview-url-command ""` を実行
  - **結果**: spec フェーズで検証済み。引用符付き `".wholework/adapters/resolve-preview-url.sh {pr}"` と引用符なし `--pr {pr}` 付きの両形式が正しく返る。キー未設定時は default を返す。ただし値に半角スペース + `#` を含むと以降が切り捨てられることを確認 (Implementation Steps 1 と 5 で制約として明文化する)
  - **影響範囲**: Implementation Steps 1, 2, 5

- **[`${var//\{pr\}/$N}` の bash 3.2 互換性]**: macOS システム bash (3.2) で動作するかが設計前提。
  - **検証方法**: `/bin/bash -c` で直接実行
  - **結果**: spec フェーズで `BASH_VERSION=3.2.57` にて検証済み。正しく置換される。CI の `macOS shell compatibility` ジョブ (`bash -n scripts/*.sh`) も構文レベルで守る
  - **影響範囲**: Implementation Steps 2

## Notes

### fail-safe critical 判定

`scripts/run-review.sh` の preview 待ちゲートは、review セッションの起動可否を決める gate (`skills/spec/SKILL.md` Step 6 の fail-safe critical 判定基準 (a)) に該当する。既存コードにも `command -v curl` 不在時の fail-open 分岐がある。したがって Implementation Steps 3 で、空入力・巨大入力・特殊文字を含む入力・依存コマンド失敗時の期待挙動 (フォールバック方向とその根拠) を全列挙している。

### `/review` skill 直接実行を対象外にした理由

Issue の Purpose は「`/auto` 経由・スケジュール実行・人間による直接実行のいずれでも」機能させることを掲げているが、`skills/review/SKILL.md` Step 8.0 (skill を直接呼ぶ経路) への `preview-url-command` 対応は本 Issue では実装しない。理由:

- skill 本文から任意のプロジェクト宣言コマンドを実行するには `allowed-tools` にそのコマンドを列挙する必要があるが、値がプロジェクト任意である以上フロントマターに書けない。`--permission-mode auto` 下で許可プロンプトを誘発し、non-interactive 実行では停止する
- 実際、`get-config-value.sh` はどの `skills/*/SKILL.md` の `allowed-tools` にも登録されていない (grep で確認済み)。設定値の読み取りは skill 側では LLM 駆動の `modules/detect-config-markers.md` が担い、`get-config-value.sh` は bash wrapper 専用という既存の役割分担がある
- Issue の "Proposal (Outline)" が挙げる変更対象も `detect-config-markers.md` / `run-review.sh` / ドキュメントの 3 点であり、`skills/review/SKILL.md` は含まれていない

代替として、Implementation Steps 5 で `docs/guide/customization.md` に「本キーは `run-review.sh` 経由 (`/auto`・スケジュール実行・wrapper 直接実行) をカバーし、`/review` skill を直接呼ぶ場合は従来どおり手動 export が必要」と明記する。skill 直接実行までカバーするには権限モデル側の設計が別途必要であり、follow-up Issue の候補として記録する。

### `#781` の設計判断との関係

本 Issue は「プロジェクト側スクリプトを呼び出す汎用フック」だけを upstream に追加するもので、provider 別 (Amplify / Vercel / Netlify / Cloudflare Pages) の解決ロジックや bundled adapter は依然として対象外 (Issue の Out of Scope どおり)。`docs/guide/adapter-guide.md` への追記も、project-local スクリプトを指す設定パターンの案内に留める。

### `{{base_url}}` 解決系統との関係

`docs/spec/issue-781-three-tier-ac-preview.md` の Notes が指摘するとおり、`{{base_url}}` の解決系統は現在 3 つ (`/review` Deployments API、`/verify` `PRODUCTION_URL`、`PREVIEW_URL` env-var fast path) ある。本 Issue は 4 つ目の系統を追加するものではなく、3 番目の系統の**入力の作り方**を 1 つ増やすだけである (最終的に `PREVIEW_URL` に集約される)。adapter chain への統合は引き続き将来の follow-up。

### 監査・調査型 Issue 判定

**該当しない**。本 Issue は既存項目の分類・監査ではなく、新規機能 (設定キーとその消費経路) の追加であり、判定列を持つ表やレポートの生成も含まない。

### Auto-Resolve Log

Step 7 の曖昧点解消結果は Issue の retrospective コメントとして投稿する (`modules/ambiguity-detector.md` の配置ルール: `issue` / `spec` フェーズは issue retrospective コメント)。

## spec retrospective

### Minor observations

- Issue 本文の Proposal は変更対象を 3 点 (`detect-config-markers.md` / `run-review.sh` / ドキュメント) に絞っていたが、`PREVIEW_URL` をキーワードにした横断 grep で復旧ガイダンス 2 箇所 (`modules/orchestration-fallbacks.md` の Structural PENDING Fix 行、`scripts/detect-wrapper-anomaly.sh` の `IMPROVEMENT_HINT`) が「`PREVIEW_URL` を手動 export せよ」と案内し続けることが判明した。Issue 本文の変更対象リストをそのまま Changed Files にすると、新機能の追加後も運用者に旧手順を案内し続ける状態が残る
- `docs/guide/customization.md` の Available Keys 表は自らを「`.wholework.yml` キーの SSoT」と宣言しているため、AC が「説明とサンプル設定」しか要求していなくても表への行追加は必須。AC 文面だけを追って節への追記で済ませると SSoT が欠損する

### Judgment rationale

- **PR 番号の渡し方に `{pr}` 置換を選んだ理由**: 環境変数案・位置引数自動追加案と比べ、設定 1 行を読むだけで PR 番号の受け渡しが自己完結して見える。かつ「プレースホルダを書かない = 引数なし実行」が自然に成立するため、Issue が挙げていた 3 案のうち 2 案 (プレースホルダ / 引数なし) を単一機構でカバーできる
- **adapter chain に乗せなかった理由**: `modules/adapter-resolver.md` は skill が Read して従う LLM 駆動モジュールで、bash wrapper (`run-review.sh`) からは構造的に呼べない。「特化機能追加は adapter-resolver lazy chain が default」という既存方針の例外として、消費者が bash wrapper であることを根拠に設定キー + wrapper 実装を選んだ
- **`skills/review/SKILL.md` Step 8.0 を対象外にした理由**: Issue の Purpose は「人間による直接実行」も掲げており当初は含める方向で検討したが、`allowed-tools` に任意のプロジェクト宣言コマンドを列挙できないという権限モデル上の障害を発見して除外した。`get-config-value.sh` がどの SKILL.md の `allowed-tools` にも登録されていない (設定読み取りは skill 側では LLM 駆動の `detect-config-markers.md` が担う) という既存の役割分担が、この判断の裏付けになっている

### Uncertainty resolution

- `get-config-value.sh` がコマンド文字列 (引用符あり/なし、フラグ付き) を欠損なく返すかは設計の前提だったため、`WHOLEWORK_CONFIG_PATH` を一時 YAML に向けて spec フェーズ中に実測した。両形式とも正しく返る一方、値に半角スペース + `#` を含むと切り捨てられることも同時に判明し、制約としてドキュメント側に明文化する Implementation Step に反映した。設定キーを追加する Issue では、パーサの「通る形」だけでなく「通らない形」も実測しておくと、後段で仕様として書き残せる
- `${var//\{pr\}/$N}` の bash 3.2 互換性は `/bin/bash -c` (`BASH_VERSION=3.2.57`) で直接実行して確認した。CI には `macOS shell compatibility` ジョブがあるが `bash -n` の構文チェックのみで、パラメータ展開の意味論までは守らないため、実行による確認が必要だった

### New test cases required for new branch logic

- `scripts/run-review.sh` に新規分岐 (`preview-url-command` 解決経路) を追加するため、`tests/run-review.bats` に新規 `@test` 6 件 (解決成功 / export 済み `PREVIEW_URL` 優先 / `{pr}` 置換 / コマンド失敗フォールバック / 空出力フォールバック / 非 URL 出力フォールバック) の追加を Implementation Steps 4 と Pre-merge 検証項目 7 に明記した

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1–9 were followed as planned: call site placement, `{pr}` substitution form, 3-段 timeout フォールバック、失敗系の全列挙、いずれも Spec のとおり実装した。

### Design Gaps/Ambiguities

- **bats の裸の `[[ "$output" == ... ]]` アサーションが bash 3.2 で `set -e` に反応しない**: Spec の "New test cases required for new branch logic" は新規 `@test` 6 件の追加を指示していたが、その実装時に「New Verification-Test Pre-implementation FAIL Check」(Step 9) を実施したところ、5/6 件が想定に反して実装前状態でも "ok" (PASS) と報告された。原因を isolate すると、macOS システム bash (`3.2.57`) では `[[ ... ]]` を単独文として書いた場合、条件が偽でも `set -e` (errexit) が伝播せずテストが誤って PASS 扱いになるという bash 3.2 固有の既知の制限だった (`[ ]` 単一角括弧や `[[ ]] || false` では正しく伝播する)。この repo の `tests/*.bats` 全体で同じ形の assertion が 79 ファイル・約 1000 箇所見つかったため、可視化を目的とした follow-up Issue #1412 を起票した。本 Issue 自身の新規 6 テストは `|| false` を付与して修正済み (詳細は Rework 参照)
- Spec の Notes に記載された「優先順位テスト (`success: exported PREVIEW_URL takes precedence over preview-url-command`) は、コマンド側でマーカーファイルを書き出しその不在を assert する形で行う」という設計は、実装前状態でも自明に真になる (機能が存在しないので当然コマンドは実行されずマーカーも作られない) という性質を持つ。これは Spec が既に想定していた設計上のトレードオフであり、pre-implementation FAIL check で唯一 PASS した項目だが、post-implementation でも同じ不変条件を検証する回帰ガードとして妥当と判断し、そのまま採用した

### Rework

- 上記の bats `[[ ]]` 発見を受け、新規 6 テストのうち出力内容を検証する 5 件 (`success: preview-url-command resolves ...` / `success: exported PREVIEW_URL takes precedence ...` の一部 / `fallback:` 系 3 件) の `[[ "$output" == ... ]]` 行に `|| false` を追加し、実装前状態で確実に FAIL することを再確認してから実装を復元した (`{pr}` 置換テストと `success: exported PREVIEW_URL takes precedence` の一部は元々 `grep -q` / `[ ! -f ... ]` を使っており修正不要だった)
- `_resolve_preview_url_command()` の出力トリム処理を実装中に一度簡略化した — 当初 `${_resolved%%[[:space:]]}` という不要な中間行を書いたが、bash 3.2 での動作確認 (`/bin/bash -c` での直接実行) の過程で冗長・不要と判明し削除した。最終形は `#`-トリムの標準的な 2 行パラメータ展開イディオムのみ

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の設計どおり実装した (call site 位置、`{pr}` 置換、3 段 timeout フォールバック、失敗系の全列挙に逸脱なし)
- `_resolve_preview_url_command()` は `_gh_api_bounded()` の直後に配置し、`[[ -z "${PREVIEW_URL:-}" ]] && _resolve_preview_url_command || true` の形で `_preview_timeout_sec` 代入直後・`PREVIEW_URL` 分岐直前から呼び出した
- Pre-merge の 6 grep/rubric 系 AC はチェック済みにした。`github_check "gh pr checks" "Run bats tests"` は CI verification AC exclusion (pr route) によりチェックせず `/review` に委ねる

### Deferred Items

- `skills/review/SKILL.md` Step 8.0 (`/review` skill 直接呼び出し経路) の `preview-url-command` 対応 — `allowed-tools` に任意コマンドを列挙できない権限モデル上の制約により対象外。follow-up 候補
- provider 別 (Amplify / Vercel / Netlify / Cloudflare Pages) の preview URL 解決 adapter の同梱 — Issue の Out of Scope どおり `#781` の設計判断を維持
- `{{base_url}}` 解決 3 系統の adapter chain への統合 — `#781` 由来の既存 follow-up として据え置き
- 解決コマンドのタイムアウト値の設定可能化 — 実測ニーズが出るまで固定 30 秒
- bats の裸の `[[ "$output" ]]` アサーションが bash 3.2 で `set -e` に反応しない問題 (Code Retrospective 参照) — 可視化・周知を目的として `#1412` を起票、既存 ~1000 箇所の一括修正は対象外

### Notes for Next Phase

- `/review` は PR #1411 の CI (`Run bats tests` ジョブ) を確認すること — code フェーズでは `github_check "gh pr checks"` AC を意図的に未チェックのまま残した (CI verification AC exclusion)
- 新規 `tests/run-review.bats` の 6 テストのうち、内容検証を伴う 5 件は `|| false` を付与済み — bats + bash 3.2 環境では裸の `[[ "$output" ]]` は FAIL を検出しないため、今後同ファイルにテストを追加する際もこのパターンを踏襲すること (`#1412` にも記録)
- `docs/ja/` 同期済み (customization / tech / adapter-guide の 3 ファイル)。`check-translation-sync.sh` で IN_SYNC を確認済み (無関係な既存 drift が `docs/guide/xl-decomposition.md` に 1 件あるが本 Issue の対象外)
