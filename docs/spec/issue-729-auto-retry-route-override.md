# Issue #729: verify: add route_override option to auto-retry-on-fail for Size-aware retry routing

## Overview

`/verify` Step 11(b) の auto-retry path で `run-code.sh $NUMBER --patch` がハードコードされており、Size=M/L の Issue でも PR review を skip した main 直コミットが発生する構造的リスクがある (#702 で実際に発生)。

`auto-retry-on-fail.route_override` config key (`auto` / `patch` / `pr`, default: `auto`) を追加し、`auto` 時は Issue Size に応じて `--patch` / `--pr` を自動選択する。XL Size は手動介入が必要なためスキップする。

## Changed Files

- `modules/detect-config-markers.md`: `auto-retry-on-fail.route_override` → `AUTO_RETRY_ROUTE_OVERRIDE` マーカー行を Marker Definition Table・Parsing Rules・Output Format に追加 — bash 3.2+ compatible
- `skills/verify/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*` 追加; Step 1 retain 変数リストに `AUTO_RETRY_ROUTE_OVERRIDE` 追加; Step 11(b) のハードコード `--patch` 呼び出しを `AUTO_RETRY_ROUTE_OVERRIDE` + `ISSUE_SIZE` 条件分岐に置換 — bash 3.2+ compatible
- `docs/guide/customization.md`: Available Keys テーブルに `auto-retry-on-fail.route_override` 行追加、サンプル config コメントに `route_override: auto` 追加
- `docs/workflow.md`: Verify Fail Flow の auto-retry 説明 (line 232) を route_override 対応の記述に更新
- `docs/ja/workflow.md`: `docs/workflow.md` 変更の日本語 mirror 更新 (translation sync)

## Implementation Steps

1. `modules/detect-config-markers.md` に `auto-retry-on-fail.route_override` → `AUTO_RETRY_ROUTE_OVERRIDE` マーカーを追加 (→ AC1):
   - Marker Definition Table の `auto-retry-on-fail.*` 行末尾に追加: `| auto-retry-on-fail.route_override | AUTO_RETRY_ROUTE_OVERRIDE | String (extract as-is; valid: "auto"/"patch"/"pr"; invalid → "auto") | "auto" |`
   - Parsing Rules の `auto-retry-on-fail.*` 記述に追記: `route_override` is a string key; valid values `auto`, `patch`, `pr`; invalid or unset falls back to `"auto"`
   - Output Format セクションに追記: `AUTO_RETRY_ROUTE_OVERRIDE: string from auto-retry-on-fail.route_override (default: "auto"; falls back to "auto" if invalid or unset)`

2. `skills/verify/SKILL.md` frontmatter + Step 1 を更新 (→ AC2a 前提):
   - frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*` を追加 (Step 11(b) での Size 取得に必要)
   - Step 1 retained config variables リスト末尾に `AUTO_RETRY_ROUTE_OVERRIDE` を追加

3. `skills/verify/SKILL.md` Step 11(b) auto-retry ブロック `c.` を条件分岐に書き換え (→ AC2a, AC2b, AC3, AC5, AC6):
   - 変更前: `c. Re-invoke code phase: bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh" $NUMBER --patch`
   - 変更後: ISSUE_SIZE を `get-issue-size.sh` で取得し、`AUTO_RETRY_ROUTE_OVERRIDE` と組み合わせて `RETRY_ARGS` を決定してから `run-code.sh $NUMBER $RETRY_ARGS` を呼ぶ:
     ```bash
     ISSUE_SIZE=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh" "$NUMBER" 2>/dev/null)
     case "$AUTO_RETRY_ROUTE_OVERRIDE" in
       pr)     RETRY_ARGS="--pr" ;;
       patch)  RETRY_ARGS="--patch" ;;
       auto|*)
         case "$ISSUE_SIZE" in
           XS|S) RETRY_ARGS="--patch" ;;
           M|L)  RETRY_ARGS="--pr" ;;
           XL)   RETRY_ARGS="" ;;
           *)    RETRY_ARGS="--patch" ;;
         esac ;;
     esac
     if [[ -n "$RETRY_ARGS" ]]; then
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh" $NUMBER $RETRY_ARGS
     else
       echo "auto-retry スキップ: XL Size は手動介入が必要です。"
     fi
     ```
   - XL skip 時は `d.` (restart from Step 5) もスキップ

4. `docs/guide/customization.md` に `auto-retry-on-fail.route_override` を追加 (→ AC4) (after 1):
   - サンプル config の `#   budget_tokens: 500000` 行直後に `#   route_override: auto` を追加
   - Available Keys テーブルの `auto-retry-on-fail.budget_tokens` 行直後に追加: `| auto-retry-on-fail.route_override | string | "auto" | Route for auto-retry. auto: Size-based (XS/S → --patch; M/L → --pr; XL → skip/manual); patch: always --patch; pr: always --pr. |`

5. `docs/workflow.md` Verify Fail Flow (line 232) の auto-retry 説明を更新し、`docs/ja/workflow.md` も translation sync で更新:
   - 現在: "automatically re-fires \`/code --patch N\`"
   - 変更後: "automatically re-fires \`/code\` (route: `auto-retry-on-fail.route_override` + Issue Size — XS/S → `--patch`, M/L → `--pr`, XL → skip; default `auto`)"

## Verification

### Pre-merge

- <!-- verify: grep "route_override" "modules/detect-config-markers.md" --> `auto-retry-on-fail.route_override` marker が detect-config-markers に追加されている
- <!-- verify: grep "AUTO_RETRY_ROUTE_OVERRIDE" "skills/verify/SKILL.md" --> `/verify` SKILL.md Step 11(b) が `AUTO_RETRY_ROUTE_OVERRIDE` 変数を参照する
- <!-- verify: grep "ISSUE_SIZE" "skills/verify/SKILL.md" --> `/verify` SKILL.md Step 11(b) が `ISSUE_SIZE` で route を分岐する
- <!-- verify: section_not_contains "skills/verify/SKILL.md" "### Step 11" "$NUMBER --patch" --> Step 11(b) のハードコード `--patch` 呼び出しが条件分岐に置換されている
- <!-- verify: grep "route_override" "docs/guide/customization.md" --> `docs/guide/customization.md` に `route_override` キーが記載されている
- <!-- verify: rubric "auto-retry が Size=M/L の Issue で --pr ルートを選択する経路が SKILL.md に明示されている" --> Size 別 route 自動選択が文書化されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 11" "--pr" --> Step 11 に `--pr` ルートが含まれる

### Post-merge

なし

## Notes

- XL Size の auto-retry スキップは Step 11(b) の `d.` (restart from Step 5) もスキップする。RETRY_ARGS が空の場合は run-code.sh を呼ばず、以降の restart も行わない。
- `AUTO_RETRY_ROUTE_OVERRIDE` の invalid 値 (e.g., `"local"`) は `auto` に fall back する。この fall back は detect-config-markers.md の Parsing Rules に明記する。
- `get-issue-size.sh` の結果が空 (未設定 Issue、API エラー等) の場合は `*` ケースに fall back して `--patch` を使用する。
- `docs/guide/customization.md` は `docs/guide/` サブディレクトリのため translation-workflow.md の top-level `docs/*.md` 対象外。日本語 mirror の更新は必須ではないが、`docs/workflow.md` (top-level) の変更は `docs/ja/workflow.md` の sync を要する。

## Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective — AP1～AP4 自動解決 (BRE バグ修正、rubric + section_contains 補強、Pre/Post-merge 分割、ハードコード削除 AC 追加)。Issue body の AC はすでに更新済み。
