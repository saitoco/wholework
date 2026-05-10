# Issue #441: verify: visual_diff command と visual-diff-adapter (bundled) を追加

## Overview

UI 再現案件における「検証範囲の選択バイアス」を体系的に防ぐため、`visual_diff` verify command を新設する。`browser_check` / `lighthouse_check` と完全に同形の **既存 adapter-resolver パターン** を流用 — Core (`modules/verify-executor.md`) に 1 行追加し、bundled adapter (`modules/visual-diff-adapter.md`) を新設、`capabilities.visual-diff: true` で gate する。

画像比較手法は 3-panel composite (Before / After / Diff highlight) を default として bundled adapter に実装。pixel diff highlight が「機械的にどこが違うか」を保証し、Before/After で意味解釈を可能にする。

副次的成果物: `agents/frontend-visual-review.md` sub-agent (3-panel images から差分を構造化リストで列挙)、`modules/verify-patterns.md` §12 (適用ガイドライン)、`tests/visual-diff-adapter.bats` (shallow contract test、`tests/adapter-resolver.bats` パターン)。

## Changed Files

- `modules/verify-executor.md`: translation table に `visual_diff` 行を追加 (`browser_check` と同形式、adapter-resolver delegate、capability=`visual-diff`)
- `modules/visual-diff-adapter.md`: 新規 — bundled adapter (Adapter Contract 準拠 6-Step 構造、3-panel composite default、`pixelmatch` 依存明記)
- `modules/adapter-resolver.md`: capability example に `visual-diff` を追記 (Extension Guide step 2 準拠、変更箇所小)
- `modules/detect-config-markers.md`: Marker Definition Table に `capabilities.visual-diff` 行を追加 (Extension Guide step 4 準拠)
- `modules/verify-patterns.md`: §12 「visual_diff の適用シナリオ」を追加 (UI 再現案件 / computed style との使い分け / `rubric` との差異 / `browser_screenshot` との差異)
- `agents/frontend-visual-review.md`: 新規 — sub-agent 定義 (frontmatter: `name`, `description`, `tools: Read`, `model: opus`)、adversarial system prompt、Input/Output JSON schema (`comparison_images`, `image_format`, `viewports`, `states`, `gaps` array with `zero_gaps_detected`, `gap_type` 等)
- `tests/visual-diff-adapter.bats`: 新規 — `tests/adapter-resolver.bats` パターンの shallow contract test (Purpose/Input/Processing Steps/Output セクション存在 + capability/pixelmatch/sharp/3-panel/frontend-visual-review 等のキーワード grep) — bash 3.2+ compatible
- `docs/structure.md`: change Directory Layout 内 file count comment (`modules/` 33 → 34, `agents/` 7 → 8, `tests/` 56 → 57)、Key Modules リストに `modules/visual-diff-adapter.md` 追加
- `docs/environment-adaptation.md`: change Command-by-Environment Table に `visual_diff` 行追加、Adapter Pattern Application Requirements の例に `visual-diff` を追記
- `docs/ja/structure.md`: docs/structure.md の変更に追随する日本語ミラー同期 (translation-workflow.md 準拠)
- `docs/ja/environment-adaptation.md`: docs/environment-adaptation.md の変更に追随する日本語ミラー同期

## Implementation Steps

**前提**: Step 1-7 は parallel-safe (異なるファイル、依存なし)。Step 8-10 は parallel-safe (docs/ 系)。

1. `modules/verify-executor.md` translation table に `visual_diff "ref_url" "impl_url" --viewports="..." --states="..."` 行を追加。`browser_check` 行の直後に挿入。Mode-dependent 記述: `safe → return UNCERTAIN. full → Read ${CLAUDE_PLUGIN_ROOT}/modules/adapter-resolver.md, resolve adapter by capability name visual-diff, and delegate. Pass command type visual_diff and arguments ref_url, impl_url, viewports, states. Best-effort due to subjective elements`。Permission: `always_ask` (→ V1)
2. `modules/visual-diff-adapter.md` を新設。Adapter Contract に従う 6-Step 構造 (parallel with 1):
   - Step 1: Capability Declaration Check (`HAS_VISUAL_DIFF_CAPABILITY` 未宣言時 UNCERTAIN)
   - Step 2: URL Security Check (`modules/browser-verify-security.md` を ref_url / impl_url 両方に適用)
   - Step 3: Tool Detection (Playwright MCP / browser-use CLI を browser-adapter 同優先順位 + `sharp` / `pixelmatch` を `node -e "require.resolve('...')"` で検出)
   - Step 4: Basic Auth Setup (`browser-adapter.md` と同パターン、`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS`)
   - Step 5: 3-panel composite Execution (default): (a) 各 (viewport × state) で reference / impl screenshot を Playwright で撮影、`.tmp/visual-diff-{run-id}/{viewport}-{state}-{ref|impl}.png` に保存 / (b) `pixelmatch` で diff highlight 画像生成 / (c) `sharp` で 3-panel (Before / After / Diff) を 1 枚に composite / (d) `frontend-visual-review` sub-agent を Task で spawn し comparison_images + image_format=`"3-panel"` + panel_layout + viewports + states を渡す / (e) sub-agent の構造化出力 (`zero_gaps_detected`, `gaps[]`) から PASS (zero_gaps_detected=true) / FAIL (gaps non-empty) / UNCERTAIN マッピング / (f) 一時画像を `rm -f` でクリーンアップ
   - Step 6: Return Result (PASS / FAIL / UNCERTAIN + Details)
   依存追加: `pixelmatch` を本 markdown 内で明示参照 (Step 3 と Step 5 で参照、→ V2 の keyword check) (→ V2)
3. `modules/adapter-resolver.md` の Step 1 capability example 説明文 (`browser` の例の隣) に `visual-diff` を追記 (after 2、Extension Guide step 2 準拠) (→ V3)
4. `modules/detect-config-markers.md` Marker Definition Table に `capabilities.visual-diff` 行を追加 (parallel with 1-3、Extension Guide step 4 準拠)。値マッピング: `true → HAS_VISUAL_DIFF_CAPABILITY=true` / `false/unset → false`。Output Format セクションにも `HAS_VISUAL_DIFF_CAPABILITY` を追記 (→ V4)
5. `agents/frontend-visual-review.md` を新設 (parallel with 1-4)。frontmatter: `name: frontend-visual-review`, `description: Compare 3-panel comparison images and enumerate visual gaps as structured JSON`, `tools: Read`, `model: opus`。本文に Purpose / Input (JSON schema: `comparison_images`, `image_format`, `panel_layout`, `viewports`, `states`, `context`) / Processing Steps (adversarial stance for exhaustive gap enumeration、diff highlight panel で「どこ」を確定し Before/After で意味解釈) / Output (JSON schema: `summary.zero_gaps_detected`, `summary.total_gap_count`, `gaps[]` with `viewport`, `state`, `element_description`, `gap_type` ∈ {`position`, `size`, `color`, `weight`, `spacing`, `other`}, `reference`, `implementation`, `severity` ∈ {`must`, `should`, `nit`}) を記載 (→ V5)
6. `modules/verify-patterns.md` 末尾 (現 §11 の後) に §12「visual_diff の適用シナリオ」を追加 (parallel with 1-5)。内容: 適用シナリオ (UI 再現案件、Figma → 実装、theme migration) / computed style 系 verify との使い分け (computed は補助、`visual_diff` が主) / `rubric` との差異 (rubric=semantic text、visual_diff=visual layout) / `browser_screenshot` との差異 (1 URL の subjective check vs 2 URL の網羅的差分) (→ V6)
7. `tests/visual-diff-adapter.bats` を新設 (parallel with 1-6、bash 3.2+ compatible)。`tests/adapter-resolver.bats` パターンの shallow contract test:
   - `@test "visual-diff-adapter: ## Purpose section exists"` (grep `^## Purpose`)
   - `@test "visual-diff-adapter: ## Input section exists"` (grep `^## Input`)
   - `@test "visual-diff-adapter: ## Processing Steps section exists"`
   - `@test "visual-diff-adapter: ## Output section exists"`
   - `@test "visual-diff-adapter: capability gate documented"` (grep `HAS_VISUAL_DIFF_CAPABILITY`)
   - `@test "visual-diff-adapter: pixelmatch dependency documented"` (grep `pixelmatch`)
   - `@test "visual-diff-adapter: sharp dependency documented"` (grep `sharp`)
   - `@test "visual-diff-adapter: 3-panel composite documented"` (grep `3-panel`)
   - `@test "visual-diff-adapter: frontend-visual-review sub-agent dispatch documented"` (grep `frontend-visual-review`)
   - `@test "visual-diff-adapter: Playwright tool detection documented"` (grep `Playwright`)
   `PROJECT_ROOT` は `tests/adapter-resolver.bats` と同様 `$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)` で解決 (→ V7)
8. `docs/structure.md` を更新 (parallel with 1-7): Directory Layout 内コメントを修正 (`modules/             # Shared modules referenced by skills (33 files)` → `(34 files)`、`agents/              # Agent definitions (7 files)` → `(8 files)`、`tests/               # Bats test files for scripts (56 files)` → `(57 files)`)、Key Modules リスト (line 121 付近) に `- modules/visual-diff-adapter.md — visual diff (3-panel composite) verification adapter` を追加 (→ V8)
9. `docs/environment-adaptation.md` を更新 (parallel with 1-8): Command-by-Environment Table (line 172 付近) に `| visual_diff | UNCERTAIN | Capability declaration check (HAS_VISUAL_DIFF_CAPABILITY), then delegate via adapter-resolver; default 3-panel composite (pixelmatch + sharp) |` 行を追加、Adapter Pattern Application Requirements の例 (line 195 付近) に `visual-diff` (Playwright/browser-use + sharp + pixelmatch の組み合わせ) を追記 (→ V9)
10. `docs/translation-workflow.md` の手順に従い、`docs/ja/structure.md` と `docs/ja/environment-adaptation.md` を Step 8/9 の変更内容に追随する日本語ミラーとして更新 (after 8, 9)。Directory Layout コメントの count 数値、Key Modules リストの新規エントリ、Command-by-Environment Table、Adapter Pattern Application Requirements の追記内容を日本語化して反映 (→ V10)

## Alternatives Considered

- **A 案 (Core 直接追加)**: `modules/verify-executor.md` の built-in table に Playwright/sharp/pixelmatch invocation を直接書き、bundled adapter を作らない。**却下** — Core/Domain 分離違反、メンテナンスコスト過大
- **B 案 (bundled custom verify handler resolution の 3-tier 化機構)**: `${CLAUDE_PLUGIN_ROOT}/verify-commands/` を verify-executor が探索する新メカニズムを新設。**却下** — 既存 `adapter-resolver.md` の 3-layer resolution と機能重複 (重要な見落としを再々考察で発見、#440 close 済)
- **E 案 (#437 close、#439 reference 集約)**: Issue 自体を close し、`docs/visual-reproduction.md` に reference implementation のみ掲載。**却下** — Wholework として配信する価値があると判断 (採用 = F 案)
- **画像比較手法: Side-by-side のみ**: 選択バイアスの再発リスク、却下
- **画像比較手法: Diff highlight のみ**: 「意図的改善 vs regression」の判別不可、却下
- **画像比較手法: 2 画像渡し (side-by-side + diff highlight 別々)**: 3-panel と機能同等だが token cost 2 倍、却下
- **bats test: functional mock test**: adapter は markdown spec のため、機能的検証は bash トレースでしか出来ず、メンテナンスコスト増。却下 (採用 = shallow contract test、`tests/adapter-resolver.bats` パターン)

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "visual_diff" --> <!-- verify: rubric "modules/verify-executor.md translation table に visual_diff 行が追加され、safe mode は UNCERTAIN、full mode は adapter-resolver で capability=visual-diff に delegate する処理が browser_check 行と同形式で記述されている" --> V1: `modules/verify-executor.md` table に `visual_diff` 行が追加 (`browser_check` と同形式)
- <!-- verify: file_exists "modules/visual-diff-adapter.md" --> <!-- verify: file_contains "modules/visual-diff-adapter.md" "HAS_VISUAL_DIFF_CAPABILITY" --> <!-- verify: file_contains "modules/visual-diff-adapter.md" "pixelmatch" --> <!-- verify: rubric "modules/visual-diff-adapter.md は browser-adapter.md / lighthouse-adapter.md と同じ Adapter Contract に従い、Step 1 で HAS_VISUAL_DIFF_CAPABILITY の capability gate (未宣言時 UNCERTAIN)、Step 5 で default 3-panel composite (Playwright で reference / impl screenshot 撮影 → pixelmatch で diff highlight 生成 → sharp で 3-panel composite → frontend-visual-review sub-agent dispatch → 構造化出力からの PASS/FAIL/UNCERTAIN マッピング) を実装している" --> V2: `modules/visual-diff-adapter.md` (Adapter Contract + capability gate + 3-panel composite + `pixelmatch` 依存) が実装されている
- <!-- verify: file_contains "modules/adapter-resolver.md" "visual-diff" --> V3: `modules/adapter-resolver.md` の capability example に `visual-diff` が追記されている
- <!-- verify: section_contains "modules/detect-config-markers.md" "Marker Definition Table" "capabilities.visual-diff" --> V4: `modules/detect-config-markers.md` Marker Definition Table に `capabilities.visual-diff` 行が追加されている
- <!-- verify: file_exists "agents/frontend-visual-review.md" --> <!-- verify: file_contains "agents/frontend-visual-review.md" "comparison_images" --> <!-- verify: file_contains "agents/frontend-visual-review.md" "image_format" --> <!-- verify: file_contains "agents/frontend-visual-review.md" "zero_gaps_detected" --> <!-- verify: file_contains "agents/frontend-visual-review.md" "gap_type" --> V5: `agents/frontend-visual-review.md` (sub-agent 定義 + Input/Output JSON schema) が実装されている
- <!-- verify: file_contains "modules/verify-patterns.md" "visual_diff" --> <!-- verify: rubric "modules/verify-patterns.md 末尾に §12 が追加され、visual_diff の適用シナリオ (UI 再現案件、Figma→実装、theme migration)、computed style 系 verify との使い分け、rubric との差異、browser_screenshot との差異を説明している" --> V6: `modules/verify-patterns.md` §12 が追加されている
- <!-- verify: file_exists "tests/visual-diff-adapter.bats" --> <!-- verify: rubric "tests/visual-diff-adapter.bats は tests/adapter-resolver.bats パターンの shallow contract test として実装されている: ## Purpose / ## Input / ## Processing Steps / ## Output セクション存在 grep + HAS_VISUAL_DIFF_CAPABILITY / pixelmatch / sharp / 3-panel / frontend-visual-review / Playwright 等のキーワード grep を含む" --> V7: `tests/visual-diff-adapter.bats` が shallow contract test として実装されている
- <!-- verify: file_contains "docs/structure.md" "visual-diff-adapter.md" --> <!-- verify: rubric "docs/structure.md の Directory Layout 内 file count コメントが (modules: 33→34, agents: 7→8, tests: 56→57) に更新され、Key Modules リストに modules/visual-diff-adapter.md エントリが追加されている" --> V8: `docs/structure.md` が更新されている (count + Key Modules)
- <!-- verify: section_contains "docs/environment-adaptation.md" "Command-by-Environment Table" "visual_diff" --> <!-- verify: rubric "docs/environment-adaptation.md Command-by-Environment Table に visual_diff 行が追加され、Adapter Pattern Application Requirements の例に visual-diff (Playwright/browser-use + sharp + pixelmatch の組み合わせ) が追記されている" --> V9: `docs/environment-adaptation.md` が更新されている (Table + Application Requirements 例)
- <!-- verify: file_contains "docs/ja/structure.md" "visual-diff-adapter.md" --> <!-- verify: file_contains "docs/ja/environment-adaptation.md" "visual_diff" --> <!-- verify: github_check "gh pr checks" "Run bats tests" --> V10: `docs/ja/` ミラー (structure.md + environment-adaptation.md) が同期され、bats test CI が PASS

### Post-merge

- サンプル UI 再現プロジェクトで `<!-- verify: visual_diff ... -->` を実装し、検出結果が期待通り (差分あり → FAIL、なし → PASS) <!-- verify-type: manual -->
- <!-- verify: rubric "実プロジェクト適用時に frontend-visual-review sub-agent が 3-panel comparison images から差分を JSON schema (gaps array with viewport/state/element_description/gap_type/severity) 通りの構造化リストで返している" --> `frontend-visual-review` sub-agent が 3-panel comparison images から差分を構造化リストで返す <!-- verify-type: opportunistic -->

## Tool Dependencies

実装で必要な追加ツール:

### Bash Command Patterns

- 追加なし — Bash 経由の操作はすべて既存 `Bash` permission で済む (Node.js script を `bash -c` で起動するパターンは `command` verify command の用途と同じ)

### Built-in Tools

- 追加なし — `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep` (既存)

### MCP Tools

- 実装時 (`/code 441`) には `mcp__plugin_playwright_playwright__*` を `tools` allowlist に含める可能性。ただし adapter file は markdown spec のため、MCP tool 自体は実装に影響しない (実行は `/verify` 時)

## Uncertainty

- **adapter から sub-agent を spawn するパターンの先例**: visual-diff-adapter は markdown 内で `Task(subagent_type=frontend-visual-review, ...)` の起動を記述する初のケース (既存 `browser-adapter` / `lighthouse-adapter` は CLI/MCP のみ)。markdown 上の表現方法 (擬似コード or 自然文での指示)。
  - **検証方法**: `/code` 実装時に `agents/issue-scope.md` 等の既存 agent ファイルが呼ばれる `skills/issue/SKILL.md` の記述方法を参照し、同パターンで visual-diff-adapter Step 5 (d) に記述
  - **影響範囲**: Implementation Steps 2 (Step 5 (d) の記述方法のみ)、AC は変わらず
- **`.tmp/visual-diff-{run-id}/` の一時ファイル命名**: 既存 `browser-adapter.md` の `mktemp .tmp/verify-screenshot-XXXXXX.png` パターンを踏襲予定だが、複数 (viewport × state × {ref|impl|diff|3panel}) のファイルを生成するため命名規約が複雑
  - **検証方法**: `/code` 実装時に `browser-adapter.md` Step 4 (browser-use CLI の screenshot サブセクション) のパターンを参照し、サブディレクトリ + 連番方式で命名
  - **影響範囲**: Implementation Steps 2 (Step 5 (a)-(c) の記述方法のみ)、AC は変わらず

## Notes

- F 案 (adapter 流用) を採用したため新メカニズム不要。既存 `adapter-resolver.md` の 3-layer resolution と `detect-config-markers.md` の dynamic capability mapping をそのまま流用
- `browser_check` / `lighthouse_check` と完全に同形のため、ユーザの認知負荷も最小
- `.wholework/adapters/visual-diff-adapter.md` で project override 自動サポート (既存 3-layer 機構) — 3-panel 以外の比較手法 (side-by-side / ROI 切り出し / odiff 等) は project 側で実装可能
- 画像比較手法は **3-panel default** を採用 (Percy / Chromatic / Playwright snapshot の業界標準)。pixel diff highlight + Before/After の組み合わせが Purpose (検証範囲選択バイアス防止) と LLM 視覚特性 (意味理解は強いが pixel 検出は不得手) の両方を満たす
- 依存追加: `pixelmatch` (npm) — `sharp` のみで簡易差分を出すことも可能だが、アンチエイリアス感度の低さにより実用度低
- AC 数値の整合: Spec の Verification > Pre-merge は 10 items (Issue body AC も 10 items に同期更新する; 元の Issue body は 11 items だったが count alignment check により Spec を SSoT として更新)
- Auto-resolved (codebase pattern):
  - Playwright invocation 優先順位 → `browser-adapter` と同 (browser-use CLI priority 1, Playwright MCP priority 2)
  - failure fallback → 既存 adapter と同 (UNCERTAIN with detail)
  - structure.md count update 必須 (機械的)
  - detect-config-markers.md marker table 明示行 (Extension Guide step 4 厳守)
  - docs/ja/ mirror sync (translation-workflow.md 必須)
- Bash 3.2+ compatibility: `tests/visual-diff-adapter.bats` は `mapfile` 等 bash 4+ 機能を使わず、macOS system bash でも動作するパターンに限定 (既存 `tests/adapter-resolver.bats` 同様)
