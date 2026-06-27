# Issue #781: AC 分類を三層化して PR preview URL 検証を pre-merge に統合

## Consumed Comments

No new comments since last phase.

## Overview

現状の AC 分類は **pre-merge (ローカル静的検証) / post-merge (本番検証)** の二分。Web サイト制作のように PR で preview URL が出るプロジェクトでは、URL/UX 系 AC (`http_status` / `html_check` / `api_check` 等) が一律 post-merge に振られ、preview で実質確認済みでも merge 後に `/verify` で再実行する二重確認が起きる。

本 Issue は AC 分類を **三層化** する軽量実装を行う。

| 層 | 実行タイミング | 対象 AC |
|---|---|---|
| pre-merge-local | `/review` safe mode | ファイル存在・テキスト一致・コード品質・テスト |
| pre-merge-preview | `/review` (PREVIEW_URL 解決時) | URL/UX 系 verify command |
| post-merge-production | `/verify` full mode | 本番反映・production 固有動作 |

軽量版方針: プラットフォーム別 adapter は持たず、`PREVIEW_URL` 環境変数の解決はプロジェクト側スクリプト/CI の責務とする (skill はラップしない)。プロジェクトは `.wholework.yml` の `capabilities.pr-preview: true` で「PR preview を持つ」とだけ宣言する。

## Changed Files

- `modules/detect-config-markers.md`: マーカー定義表に `capabilities.pr-preview` 行を追加し `HAS_PR_PREVIEW_CAPABILITY` 出力を定義 (Dynamic Capability Mapping で既に派生する変数を明示行に格上げ) (→ AC1, AC2)
- `skills/issue/SKILL.md`: Step 2 の retain 対象に `HAS_PR_PREVIEW_CAPABILITY` を追記。Step 4 に pre-merge-preview 層の分類ガイダンス (URL/UX 系 verify command の集合定義、`HAS_PR_PREVIEW_CAPABILITY` 有効時に `### Pre-merge (auto-verified)` 内へ `<!-- ac-tier: preview -->` タグ付き + `--when="test -n \"$PREVIEW_URL\""` 自動付与で配置、無効時は従来通り post-merge) を追加 — half-width `!` 禁止に注意 (→ AC3, AC4)
- `skills/review/SKILL.md`: Step 8.0 に「`PREVIEW_URL` 環境変数が export されていれば Deployments API ルックアップをスキップして直接 preview base URL に使う」パスを追加 (→ AC5)
- `skills/verify/SKILL.md`: Step 5 に「`<!-- ac-tier: preview -->` タグ付き AC は post-merge で skip (二重検証防止)、SKIPPED として記録」ルールを追加 — half-width `!` 禁止に注意 (→ AC6)
- `docs/guide/customization.md`: `## .wholework.yml` サンプルと Available Keys 表に `capabilities.pr-preview` 行を追加。三層分類 (pre-merge-local / pre-merge-preview / post-merge-production) の説明と `.wholework.yml` サンプル設定セクションを追加 (→ AC7)
- `tests/issue.bats`: 新規作成。pre-merge-preview 分類ガイダンスが SKILL.md / detect-config-markers.md に存在することを検証する content-assertion テスト (script/content 層) を追加。bats 3.2+ 互換 (→ AC8)
- `docs/tech.md`: Environment Variables > Capability Flags 表に `HAS_PR_PREVIEW_CAPABILITY` 行を追加 (新 `.wholework.yml` キー追加に伴う SSoT 同期、constraint #250)
- `docs/structure.md`: Directory Layout の `tests/` ファイル数コメントを更新 (現状 87 表記 → 実数に同期。`tests/issue.bats` 追加後は 89)
- `docs/ja/structure.md`: 上記 structure.md 変更の ja ミラー同期 (top-level docs、必須)
- `docs/ja/tech.md`: 上記 tech.md 変更の ja ミラー同期 (top-level docs、必須)
- `docs/ja/guide/customization.md`: customization.md 変更の ja ミラー同期 (consistency。translation-workflow.md の必須スコープは top-level docs のみ。本ファイルは subdirectory のため consistency 目的の推奨同期)

## Implementation Steps

1. `modules/detect-config-markers.md` のマーカー定義表に行 `| capabilities.pr-preview | HAS_PR_PREVIEW_CAPABILITY | true | false |` を追加し、Output Format の変数リストに `HAS_PR_PREVIEW_CAPABILITY: true if capabilities.pr-preview: true is set (default: false)` を追記。「Dynamic Capability Mapping」既定との重複ではなく、`pr-preview` は専用分類ロジックを持つため明示行へ格上げする旨を 1 行注記。`grep "preview"` がヒットすることを確認 (→ AC1, AC2)

2. `skills/issue/SKILL.md` を編集 (after 1) (→ AC3, AC4):
   - Step 2 の retain 文 (`Retain SPEC_PATH and STEERING_DOCS_PATH`) に `HAS_PR_PREVIEW_CAPABILITY` を追加 (Step 4 で参照するため。MCP_TOOLS と同様に Step 2 で取得した値を再利用)
   - Step 4 の classification 節 (「After ambiguity detection, classify each acceptance criterion as "pre-merge" or "post-merge"」直後) に **pre-merge-preview 層** の小節を追加。記載内容:
     - URL/UX 系 verify command 集合 (exhaustive): `http_status`, `html_check`, `api_check`, `http_header`, `http_redirect`, `browser_check`, `browser_screenshot`, `lighthouse_check`
     - `HAS_PR_PREVIEW_CAPABILITY=true` のとき、上記集合に該当する AC を `### Pre-merge (auto-verified)` セクションに配置し、AC 行末に `<!-- ac-tier: preview -->` タグを付与、verify command に `--when="test -n \"$PREVIEW_URL\""` を自動付与する
     - `HAS_PR_PREVIEW_CAPABILITY` が false/unset のとき: 従来通り post-merge に振る (既存挙動)
     - `pre-merge-preview` というキーワードを本文に含める (AC4 の grep 対象)
   - 既存 `--when` modifier 表の `Preview URL required` 行は流用 (変更不要だが、pre-merge-preview 節からその行を参照する旨を記述)
   - 編集時 half-width `!` を本文に書かない (validate-skill-syntax.py MUST)

3. `skills/review/SKILL.md` Step 8.0 を編集 (parallel with 2) (→ AC5): 「Preview URL Resolution」の冒頭に新パスを追加 — 「`PREVIEW_URL` 環境変数が既に export されている (CI またはプロジェクトスクリプトが設定) 場合、それを preview base URL として直接使用し、GitHub Deployments API ルックアップ (手順 1-4) をスキップする。`{{base_url}}` は `$PREVIEW_URL` に解決し、`--when="test -n \"$PREVIEW_URL\""` ガード付き `ac-tier: preview` AC はこのパスで実行される」。env var 未設定時は既存 Deployments API パスにフォールバック

4. `skills/verify/SKILL.md` Step 5 を編集 (parallel with 2, 3) (→ AC6): Scope 節 (「This step processes pre-merge conditions only」付近) に skip ルールを追加 — 「`### Pre-merge` セクション内で `<!-- ac-tier: preview -->` タグを持つ AC は post-merge での二重検証防止のため verify 対象から除外し、SKIPPED として結果テーブルに記録する (詳細: "preview-tier AC; verified at /review against preview URL")。本番でも同 URL を確認したい場合は、当該 AC を `### Post-merge` セクションに `ac-tier: preview` タグ無しで複製する運用 (`{{base_url}}` は `/verify` で `PRODUCTION_URL` に解決される)」。編集時 half-width `!` 禁止

5. `docs/guide/customization.md` を編集 (parallel with 2-4) (→ AC7):
   - `## .wholework.yml` の `capabilities:` サンプルブロックに `pr-preview: true   # Declare that PRs produce a preview URL (enables pre-merge-preview AC tier)` を追加
   - Available Keys 表に行 `| capabilities.pr-preview | boolean | false | Declare PR preview availability; URL/UX ACs are classified as pre-merge-preview and run at /review when PREVIEW_URL is set |` を追加
   - 新規サブセクション (h3 `### AC verification tiers`) を追加し、三層分類 (pre-merge-local / pre-merge-preview / post-merge-production) の説明、`PREVIEW_URL` 環境変数のプロジェクト側解決責務、`.wholework.yml` サンプル設定を記述

6. `tests/issue.bats` を新規作成 (after 1, 2): 以下の content-assertion `@test` を含める (script/content 層テスト。分類ロジック自体は LLM 実行のため LLM 層は post-merge observation AC でカバー — Notes 参照):
   - `@test "issue skill Step 4 documents pre-merge-preview tier"`: `grep -q 'pre-merge-preview' skills/issue/SKILL.md`
   - `@test "issue skill Step 4 tags preview-tier ACs with ac-tier preview"`: `grep -q 'ac-tier: preview' skills/issue/SKILL.md`
   - `@test "issue skill Step 4 auto-appends PREVIEW_URL when-guard"`: `grep -q 'test -n .*PREVIEW_URL' skills/issue/SKILL.md`
   - `@test "detect-config-markers documents pr-preview capability"`: `grep -q 'pr-preview' modules/detect-config-markers.md && grep -q 'HAS_PR_PREVIEW_CAPABILITY' modules/detect-config-markers.md`
   - リポジトリルートからの相対パスで参照 (bats 実行 CWD はリポジトリルート前提)。bats 3.2+ 互換構文のみ使用

7. `docs/tech.md` の Environment Variables > Capability Flags 表に行 `| HAS_PR_PREVIEW_CAPABILITY | capabilities.pr-preview: true | true when the project's PRs produce a preview URL. Gates pre-merge-preview AC classification in /issue Step 4. |` を追加 (parallel with 5)

8. `docs/structure.md` Directory Layout の `tests/` 行コメント `Bats test files for scripts (87 files)` を実数に更新 (`tests/issue.bats` 追加後の実数。現状 88 + 新規 1 = 89) (after 6)

9. `docs/ja/structure.md` / `docs/ja/tech.md` (top-level docs、必須) と `docs/ja/guide/customization.md` (consistency) を、対応する英語版変更に合わせて日本語で同期 (after 5, 7, 8)

## Alternatives Considered

- **`.wholework.yml` キー shape — 案A `preview-url-env: PREVIEW_URL` (不採用)**: 環境変数名を設定値で持たせる案。`--when` modifier 表が既に `$PREVIEW_URL` をハードコードしており、env 変数名を可変にすると `--when` 自動付与と verify-executor の評価が複雑化する。軽量版方針 (プロジェクトが `PREVIEW_URL` を解決) とも整合するため、env 変数名は `PREVIEW_URL` に標準化し、宣言は capability flag に一本化する 案B を採用。
- **Issue body AC セクション表現 — 案1 新セクション `### Pre-merge (preview)` (不採用)**: 3 つ目のサブセクションを追加する案。`/review` Step 5 と `/verify` Step 4/5 のセクション解析・チェックボックス index・count 整合ロジックすべてに新セクション認識を追加する必要があり破壊的。既存の per-AC メタタグ慣習 (`<!-- verify-type: ... -->`) と整合する 案2 (`<!-- ac-tier: preview -->` タグ) を採用し、セクション構造は不変のまま `/verify` 側で per-AC skip するだけにする。
- **preview AC を adapter で自動解決 (本 Issue スコープ外)**: Vercel / Netlify / CF Pages 用の preview URL 自動解決 adapter は `modules/adapter-resolver.md` lazy chain に乗せる前提で、採用実績が出てから follow-up Issue で判断 (Issue body 「将来検討事項」)。

## Verification

### Pre-merge
- <!-- verify: rubric "modules/detect-config-markers.md のマーカー定義表に preview URL 関連の YAML キー (preview-url-env または capabilities.pr-preview など) と対応変数が追加されている" --> `.wholework.yml` で preview URL 設定を宣言できるよう `detect-config-markers.md` が拡張されている
- <!-- verify: grep "preview" "modules/detect-config-markers.md" --> `detect-config-markers.md` に preview 関連エントリが追加されている
- <!-- verify: rubric "skills/issue/SKILL.md Step 4 の分類ガイダンスに pre-merge-preview 層 (URL/UX 系 AC を preview URL 上で検証する層) が追加されており、preview 宣言が有効な場合に URL ベース verify command を pre-merge-preview に振り分ける旨が記述されている" --> Issue skill Step 4 の分類ロジックに pre-merge-preview 層が導入されている
- <!-- verify: grep "pre-merge-preview|pre_merge_preview" "skills/issue/SKILL.md" --> SKILL.md に "pre-merge-preview" キーワードが追加されている
- <!-- verify: rubric "skills/review/SKILL.md または modules/verify-executor.md に、PREVIEW_URL 環境変数が export されている場合に URL 系 verify command を preview URL 上で実行する仕様が記述されている" --> `/review` 側で PREVIEW_URL を読んで URL 系 AC を実行する仕様が記述されている
- <!-- verify: rubric "skills/verify/SKILL.md に、pre-merge-preview に分類された AC は post-merge では skip される (二重検証防止) 仕様が記述されている" --> `/verify` post-merge で pre-merge-preview AC を skip する仕様が記述されている
- <!-- verify: rubric "docs/guide/customization.md または同等のユーザ向けドキュメントに、三層分類 (pre-merge-local / pre-merge-preview / post-merge-production) の説明と .wholework.yml サンプル設定が追加されている" --> ユーザ向け docs に三層分類の説明と `.wholework.yml` サンプルが追加されている
- <!-- verify: command "bats tests/issue.bats" --> issue skill の bats テストが green (pre-merge-preview 分類のケース追加)

### Post-merge
- preview URL を持つ実プロジェクトで `/issue` → `/review` を実行し、URL 系 AC が preview URL 上で検証されることを観察 <!-- verify-type: opportunistic event=review-run -->
- 同プロジェクトで merge 後の `/verify` 実行時に pre-merge-preview AC が SKIPPED として扱われ、本番反映系 AC のみ実行されることを観察 <!-- verify-type: opportunistic event=verify-run -->

## Tool Dependencies

### Bash Command Patterns
- none (新規スクリプト/コマンドパターンの追加なし。`bats` は既存の `command` verify で実行)

### Built-in Tools
- `Read` / `Edit` / `Write`: 既存ファイル編集と `tests/issue.bats` 新規作成 (既に allowed-tools に含まれる)

### MCP Tools
- none

## Uncertainty

- **[`tests/issue.bats` の非存在]**: Issue body AC8 は `tests/issue.bats` を参照するが、現状リポジトリに存在しない (本 Spec で新規作成する。Notes「Conflict with implementation」参照)。
  - **検証方法**: `/code` 実装時にファイル作成。`bats tests/issue.bats` が green になることを確認
  - **影響範囲**: Implementation Step 6
- **[分類ロジックの LLM 層]**: pre-merge-preview の振り分けは `/issue` Step 4 の LLM 実行ガイダンスであり、bats では決定論的な「ガイダンス文言の存在」(script/content 層) しか検証できない。実際の分類精度 (LLM 層) は post-merge observation AC (review-run / verify-run) で人手評価する (skill-dev-constraints.md「LLM-assisted Skill Phase Test Strategy」準拠)。
  - **検証方法**: post-merge opportunistic AC でプロジェクト実観察
  - **影響範囲**: Implementation Steps 2, 6 / Post-merge AC
- **[`--when` env-var ガードと既存 Deployments API パスの相互作用]**: `--when="test -n \"$PREVIEW_URL\""` は env 変数を見るため、Deployments API 経由でのみ preview を解決するプロジェクトでは guard が SKIP する。軽量版では env 変数エクスポートがプロジェクト側責務 (Notes 参照)。
  - **検証方法**: Step 3 の env-var 直接利用パス記述で整合を担保
  - **影響範囲**: Implementation Steps 2, 3

## Notes

### Conflict with implementation (Issue body vs. existing code)

- **AC8 が参照する `tests/issue.bats` は存在しない**: Issue body は「issue skill の bats テストが green (pre-merge-preview 分類のケース追加)」と既存テストを前提にした表現だが、`tests/issue.bats` は未作成 (`tests/run-issue.bats` は runner script 用、`tests/verify-executor.bats` は別対象)。分類ロジックは LLM 実行 markdown のため、本 Spec は `tests/issue.bats` を **新規作成** し、ガイダンス文言の存在を検証する content-assertion テストとして実装する (非対話モードのため model 判断で auto-resolve)。

### Auto-Resolve Log (non-interactive mode)

- **案B: `capabilities.pr-preview: true` を単一宣言シグナルとし、env 変数名は `PREVIEW_URL` に標準化** — reason: Capability は「機能が利用可能か」を表す codebase 既定パターン (product.md Terms)。pre-merge-preview 分類は正にその capability チェック。既存 `--when` modifier 表が `$PREVIEW_URL` をハードコード済で env 変数名を可変化する必要がない。`capabilities.pr-preview` は既存 Dynamic Capability Mapping で `HAS_PR_PREVIEW_CAPABILITY` に派生するため新機構は最小。
  - Other candidates: 案A `preview-url-env: PREVIEW_URL` (env 変数名を設定値化 — `--when` 自動付与が複雑化)
- **案2: `<!-- ac-tier: preview -->` per-AC メタタグを既存 `### Pre-merge (auto-verified)` 内で使う** — reason: セクション解析 (`/review` Step 5、`/verify` Step 4/5) とチェックボックス index・count 整合への破壊的変更を回避。per-AC メタタグは既存 `<!-- verify-type: ... -->` 慣習と整合。`/verify` の skip は per-AC ルールで表現できる。
  - Other candidates: 案1 新セクション `### Pre-merge (preview)` (両 skill のセクション認識・count 整合の追加が必要)
- **Q3 (preview AC の post-merge 再実行) の既定: skip。本番再検証は opt-in 複製** — reason: Issue body point 5「pre-merge-preview タグ付き AC は post-merge では skip。本番でも同 AC を確認したい場合は明示的に post-merge にも複製する運用」に準拠。既定 skip が二重検証防止の主目的に直結。複製した post-merge AC は `{{base_url}}` → `PRODUCTION_URL` で既存 `production-url` キーと合成される。
  - Other candidates: 既定で production へ自動再実行 (二重確認が再発し Issue 目的に反する)
- **URL/UX 系 verify command 集合を明示列挙 (`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect` / `browser_check` / `browser_screenshot` / `lighthouse_check`)** — reason: URL 引数を取り preview URL に対して実行可能なコマンド型に限定。`mcp_call` はツールベースで URL 解決対象外のため除外。

### Design alignment notes

- **eager-load capability ガード回避**: PREVIEW_URL 実行仕様は `skills/review/SKILL.md` (skill-local) に置き、eager-load 共有モジュール (`modules/verify-executor.md` / `modules/verify-patterns.md`) には capability 固有ガイダンスを混入させない (`scripts/check-eager-load-capability.sh` のスキャン対象は両モジュール。`pr-preview` は bundled adapter 非存在のため対象外だが方針として skill-local に置く)。AC5 は「review SKILL.md **または** verify-executor.md」のいずれかで可。
- **half-width `!` 禁止**: `skills/issue/SKILL.md` / `skills/verify/SKILL.md` 編集時、本文 (コードフェンス・inline code・HTML コメント外) に half-width `!` を書かない (validate-skill-syntax.py MUST)。
- **BRE メタ文字**: AC4 の `grep "pre-merge-preview|pre_merge_preview"` の `|` は ripgrep ERE の OR 交替として正しく機能する (`\|` 不使用、警告不要)。
- **verify-classifier.md は変更しない**: 同モジュールは post-merge の `verify-type` (auto/opportunistic/observation/manual) 分類専用。pre-merge-preview は層 (tier) の概念で verify-type とは直交するため `/issue` Step 4 のガイダンスに閉じる。
- **constraint #250**: 新 `.wholework.yml` キー追加に伴い `docs/tech.md` を Changed Files に含める (Capability Flags 表へ 1 行)。
- **translation sync スコープ**: `docs/structure.md` / `docs/tech.md` は top-level docs で必須同期 (`docs/ja/structure.md` / `docs/ja/tech.md`)。`docs/guide/customization.md` は subdirectory で translation-workflow.md の必須スコープ外だが、ja ミラー (`docs/ja/guide/customization.md`) が存在するため consistency 目的で同期する。

### Skill-dev checks (SPEC_DEPTH=full)

- **Shared module 不要 (ac-tier タグの SSoT)**: `ac-tier: preview` は 3 skills (issue/review/verify) で参照されるが、各 skill の挙動は異なる (issue=付与 / review=実行 / verify=skip)。共有されるのは「タグ文字列とその意味」という規約のみでありロジックではないため、専用 module は作らない。タグの定義・付与は `/issue` Step 4 を SSoT とし、`/review` Step 8.0 と `/verify` Step 5 は「`/issue` Step 4 が付与する `ac-tier: preview` タグ」を参照する旨を明記する。`verify-classifier.md` は post-merge verify-type 専用のため変更しない。
- **Exhaustive marker**: `/issue` Step 4 に追加する URL/UX 系 verify command 集合には `(exhaustive)` マーカーを付ける (skill-dev-checks「Exhaustive/Example Markers」)。
- **Triple backtick / half-width `!` 禁止**: `skills/*/SKILL.md` 本文 (コードフェンス・inline code・HTML コメント外) に half-width `!` と triple backtick を新規追加しない (validate-skill-syntax.py)。ガイダンス追記は inline code とプレーン文で表現する。
- **Tool Dependencies**: 実装で使うツール (Read/Edit/Write/`command`+bats) は全て既存 allowed-tools に含まれ、新規 KNOWN_TOOLS 追加は不要。
- **`docs/workflow.md` は変更不要**: grep 確認の結果、workflow.md は pre-merge/post-merge を phase 説明・label 遷移レベルでしか言及しておらず、AC tier 分類の詳細は記述していない。三層化は phase 遷移/routing を変えないため同期不要。

## spec retrospective

### Minor observations
- Issue body AC8 が未作成のテストファイル (`tests/issue.bats`) を「既存テスト前提」で参照していた。`/issue` 段でテスト系 AC を書く前に対象ファイルの存在確認を 1 度入れると、spec 段での conflict 検出を前倒しできる。
- 既存 `{{base_url}}` プレースホルダ機構が 2 系統 (`/review` Step 8.0 = GitHub Deployments API、`/verify` = `PRODUCTION_URL`) あり、本 Issue で 3 系統目 (`PREVIEW_URL` env-var 軽量パス) が加わる。将来の preview URL adapter 化 (follow-up) で統合する余地を残した (adapter chain lazy pattern に乗せる前提)。

### Judgment rationale
- `.wholework.yml` キーは案B (capability flag `capabilities.pr-preview`) + env 変数名 `PREVIEW_URL` 標準化を採用。env 変数名を設定値化する案A は `--when` 自動付与と verify-executor の評価を複雑化するため不採用。
- AC tier 表現は新セクションでなく per-AC `<!-- ac-tier: preview -->` タグ (案2)。既存 `verify-type` per-AC タグ慣習と整合し、`/review`/`/verify` のセクション解析・チェックボックス index・count 整合への破壊的変更を回避できる、という判断が決め手。

### Uncertainty resolution
- 分類ロジックは `/issue` Step 4 の LLM 実行ガイダンスのため、bats では決定論的な「ガイダンス文言の存在」(content 層) しか検証できない。実分類精度 (LLM 層) は post-merge observation AC でカバーする二層テスト戦略を採用 (skill-dev-constraints.md「LLM-assisted Skill Phase Test Strategy」準拠) → 解消。
- `--when="test -n \"$PREVIEW_URL\""` env-var ガードと既存 Deployments API パスの相互作用は、`/review` Step 8.0 に env-var 直接利用パスを明記することで整合 (env 変数未設定時のみ Deployments API へフォールバック) → 解消。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- No deviations. All implementation steps followed the Spec exactly.

### Design Gaps/Ambiguities
- Spec Step 2 said to add `HAS_PR_PREVIEW_CAPABILITY` to "Step 2 の retain 文" without specifying which Step 2 (New Issue Creation vs. Existing Issue Refinement). Applied to both, which is correct since both sections read detect-config-markers and both reference Step 4/6 classification logic.
- `docs/structure.md` had "87 files" in the tests/ comment but actual count was 88 (pre-existing drift noted in Spec). Updated to 89 (88 existing + 1 new `tests/issue.bats`).

### Rework
- None.

## review retrospective

### Spec vs. implementation divergence patterns
- No structural divergences between Spec and PR diff. All 9 implementation steps were completed exactly as designed.
- The Phase Handoff (code phase) accurately predicted that all 8 AC checks would PASS without fixup — confirmed during review.

### Recurring issues
- `tests/issue.bats` was created without the `PROJECT_ROOT` anchoring pattern used by all other 87 bats tests in the repository. This is a recurring gap: new test files don't inherit the project's established portability convention automatically. The issue was SHOULD-severity and fixed in this review. Consider adding a note to the test-writing guidance or a bats fixture template that includes the `setup()` pattern.
- The JA mirror (`docs/ja/guide/customization.md`) omitted a bash code block present in the EN version. Translation drift in code examples is a recurring risk when adding code fences to documentation. Mitigation: the `docs/translation-workflow.md` sync procedure should explicitly check code blocks, not just text content.

### Acceptance criteria verification difficulty
- All 8 pre-merge ACs verified PASS without ambiguity. The mix of `rubric`, `grep`, and `command` verify commands provided good coverage at different verification depths.
- The `command "bats tests/issue.bats"` AC was resolved via CI reference fallback (ok 441–444 in the CI log). The overall CI FAILURE in `Run bats tests` is caused by a pre-existing `append-loop-state-heartbeat.bats` issue unrelated to this PR. The AC verification correctly distinguished the specific test file result from the overall job status.

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- All 8 pre-merge ACs PASS. Two SHOULD fixes applied (PROJECT_ROOT anchoring in bats, JA bash code block). Three CONSIDER issues skipped.
- The Workflow path (capabilities.workflow: true) attempted but fell back to static fan-out because custom agentTypes (review-spec, review-bug) are not available as registered agent types in the worktree environment. Findings were collected via direct Agent tool calls instead.
- No policy changes or acceptance criteria updates needed.

### Deferred Items
- CONSIDER: skills/review/SKILL.md Step 8.0 fast-path description scope ambiguity — the sentence "ac-tier: preview ACs ... are executed via this path" could mislead about ACs without {{base_url}}. Low risk, deferred to a future doc cleanup pass.
- CONSIDER: skills/verify/SKILL.md "### Pre-merge" vs "### Pre-merge (auto-verified)" section name mismatch in skip rule prose. Low functional risk.
- Vercel/Netlify/CF Pages preview URL auto-resolver adapter — already deferred from code phase.

### Notes for Next Phase
- Two SHOULD fixes committed (PROJECT_ROOT in bats, JA code block). CI re-run expected to show same status (pre-existing append-loop-state-heartbeat.bats failures remain).
- merge phase: no MUST issues to block merge. CI FAILURE is pre-existing on main too — merge can proceed if that's the project's accepted state.
- Post-merge opportunistic ACs require a real project with `capabilities.pr-preview: true` and CI that exports `PREVIEW_URL`.
