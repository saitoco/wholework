# Issue #511: code: MCP tool 呼び出しを含む実装の behavioral smoke test を /code 完了前に走らせる optional フック

## Overview

`/code` の commit/push 前に、Spec が指定する optional な behavioral smoke test を実行するフックを追加する。発端は `/auto` 非対話モードで tool-call classifier (permission-mode auto) が MCP tool 実機呼び出しをブロックし、code phase が tool schema 説明文中のフォールバック値を silent 採用 → structural AC は全 PASS だが post-merge の実機到達確認で FAIL し、behavioral 不整合が `/verify` まで露呈しなかったこと。

機構は **既存の verify-executor を再利用**する: Spec に optional な `## Smoke Test` セクションを設け、通常の `<!-- verify: mcp_call ... -->` / `<!-- verify: command ... -->` 等を記述。`/code` は commit/push 前にこのセクションを検出し verify-executor を **full mode** で実行する。新 annotation・別系統パーサは導入しない。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の Spec テンプレート (full / light) に optional な `## Smoke Test` セクションを追加し、auto-propose ガイダンス (実機 external/MCP 呼び出しを伴う Issue で propose; 既存 verify command 再利用; `/code` が full mode 実行) を追記
- `skills/code/SKILL.md`: Step 11「Commit, Push, or Create PR」冒頭に h4 サブセクション `#### Smoke Test (pre-commit behavioral check)` を追加 (Spec `## Smoke Test` 検出 → verify-executor full mode → PASS/FAIL/SKIPPED 分岐)。frontmatter `allowed-tools` に `ToolSearch` を追加 (mcp_call smoke の実機実行に必要)。renumber は行わない (bash 3.2+ 非依存; 純 Markdown 編集)
- `docs/product.md`: `## Terms` テーブルに "Smoke Test" 用語を追加
- `docs/workflow.md`: §2 (`/spec`) と §3 (`/code`) に optional smoke test の簡潔な言及を追加
- `docs/ja/product.md`: product.md Terms 追加の日本語ミラー同期 (translation-workflow)
- `docs/ja/workflow.md`: workflow.md 追加の日本語ミラー同期 (translation-workflow)

## Implementation Steps

**Step recording rules**: 整数 Step 番号、依存・AC マッピングを併記。挿入位置は近傍コンテキストで指定 (行番号は使わない)。

1. `skills/spec/SKILL.md` Step 10: full テンプレート (`## Verification` と `## UI Design` の間) と light テンプレート (`## Verification` と `## Notes` の間) に optional セクション `## Smoke Test` を追加。併せて Step 10 のSHOULD 考慮ブロックとして「Smoke Test section consideration」を追記 — 実機 external/MCP 呼び出しを伴う Issue (判定基準 (examples): Issue の verify command に `mcp_call` 等が含まれる、または `capabilities.mcp` 設定下で本文が MCP tool を参照) のとき `## Smoke Test` を propose し、そこに最小 1 件以上の full-mode verify command (`mcp_call` / `command` / `http_status`) を記述する旨。セクションは bullet (`- `) 形式・checkbox なし (Verification と同様)。(→ AC1)
2. `skills/code/SKILL.md` Step 11 冒頭 (patch/pr の commit ロジックより前) に h4 サブセクション `#### Smoke Test (pre-commit behavioral check)` を挿入。処理: Step 5 で読み込んだ Spec に `## Smoke Test` セクションが存在する場合のみ、その `<!-- verify: ... -->` を抽出し `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` を読み **full mode** で実行 (実行前に `echo "progress: Running smoke test for issue #$NUMBER..."` で watchdog リセット)。全 PASS → commit へ進む。**verify-executor.md の Read 命令は `#### Smoke Test` 見出し直後の段落に配置** (リスト/テーブル内に埋め込まない; skill-dev-checks Read Instruction Placement Rule)。本文に半角 `!` を含めない (full-width 「！」または言い換え)。(→ AC2)
3. `skills/code/SKILL.md` frontmatter `allowed-tools` に `ToolSearch` を追加 (verify-executor の mcp_call が `ToolSearch select:<tool_name>` を使うため; KNOWN_TOOLS に既存のため validator 更新不要)。(→ AC2)
4. 同サブセクションに FAIL 分岐を記述: いずれかの smoke が FAIL → 不整合を修正する 1 回の repair 試行 → smoke 再実行 → なお FAIL なら Step 9 テスト FAIL handling と同様に route 準拠 (patch route 非対話=hard-error abort / patch route 対話=AskUserQuestion で abort・continue / pr route=continue し completion message で報告)。(→ AC4)
5. 同サブセクションに blocked/SKIPPED 分岐を記述: 結果が UNCERTAIN または SKIPPED (permission/classifier ブロック、`--when` 未充足、ToolSearch 不可等) のとき、`SKIPPED` として Step 12 Code Retrospective の "Smoke Test" 行 + completion message に記録し commit を継続する (フォールバック値の silent 採用も hard-block もしない)。(→ AC3)
6. 同サブセクションに backward-compat を明記: Spec に `## Smoke Test` が無い場合は当サブセクションを no-op としスキップ (既存挙動と完全互換)。(→ AC5)
7. `docs/product.md` `## Terms` テーブルに "Smoke Test" 行を追加 (定義: `/code` が commit/push 前に実行する optional な最小 behavioral sanity check。Spec の `## Smoke Test` セクションに full-mode verify command で記述し、`/verify` より早く code phase 内で不整合を検知する。opt-in はセクションの有無)。Context: /spec, /code。日本語訳: Smoke Test。(→ AC6)
8. `docs/workflow.md` §2 (`/spec`) に「実機 external/MCP 呼び出しを伴う Issue では optional な `## Smoke Test` セクションを生成」、§3 (`/code`) に「Spec の `## Smoke Test` を commit/push 前に full mode で実行」の 1 文を追加 (parallel with 7)。
9. `docs/ja/product.md` と `docs/ja/workflow.md` を 7・8 の変更に合わせて日本語で同期 (translation-workflow; 構造・見出しは英語原典に追随)。(after 7, 8)
10. `python3 scripts/validate-skill-syntax.py skills/` と bats テストを実行し PASS を確認。(→ AC7) (after 1-6)

## Alternatives Considered

- **新 `<!-- smoke: ... -->` annotation の新設** (Issue 原案): verify-executor と別系統のパーサ・実行・テストが必要で重複。**不採用** — 既存 verify command 再利用で safe/full・permission 制御を継承 (Step 4 adapter-survey 方針)。
- **新 `### Step 11: Smoke Test` を挿入し後続 Step を renumber**: Step 11→12, 12→13, 13→14, 14→15 と 5 箇所の cross-ref (行 321/366/368-370/431/463) 更新が必要で fragile。**不採用** — Step 11 冒頭の h4 サブセクションなら commit/push 前を満たしつつ renumber 不要。
- **blocked 時に hard-block (commit 中止)**: 外部依存で `/auto` が頻繁停止。**不採用** — SKIPPED 記録して続行 (silent fallback は防止)。
- **`.wholework.yml` グローバルトグル新設**: 新 config surface 増。**不採用** — opt-in は `## Smoke Test` セクションの有無で表現。

## Verification

### Pre-merge
- <!-- verify: file_contains "skills/spec/SKILL.md" "Smoke Test" --> <!-- verify: rubric "skills/spec/SKILL.md describes generating an optional ## Smoke Test section in the Spec, proposed when the Issue involves a real external or MCP tool call, expressed using existing verify commands such as mcp_call or command" --> `/spec` の Spec 生成手順/テンプレートに optional な `## Smoke Test` セクション (既存 verify command で記述) を生成・auto-propose するガイダンスが追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "Smoke Test" --> <!-- verify: file_contains "skills/code/SKILL.md" "ToolSearch" --> <!-- verify: rubric "skills/code/SKILL.md adds a step running before the commit/push action that detects the Spec's ## Smoke Test section and runs its verify commands in full mode via verify-executor; ToolSearch is in allowed-tools so mcp_call smoke checks can invoke MCP tools" --> `/code` に commit/push 前に Spec の `## Smoke Test` を検出し verify-executor (full mode) で実行する手順が追加され、mcp_call 実行のため allowed-tools に ToolSearch が追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "SKIPPED" --> <!-- verify: rubric "skills/code/SKILL.md specifies that when the smoke-test real call cannot run (blocked by permission mode or classifier in non-interactive mode), the result is recorded as SKIPPED/UNCERTAIN in the retrospective and completion message and commit/push continues, without silently adopting a tool-schema fallback value and without hard-blocking on the environment limitation" --> 実機呼び出し不可時は SKIPPED/UNCERTAIN として retrospective + completion message に記録し commit/push を継続する旨が記述されている (silent fallback 採用も hard-block もしない)
- <!-- verify: rubric "skills/code/SKILL.md specifies smoke-test FAIL handling as one repair attempt, re-run, then route-based behavior (patch route aborts the commit and returns to the fix loop; pr route continues and leaves CI/verify to catch it), mirroring the existing Step 9 test-FAIL handling" --> smoke test が実機 FAIL した場合、1回修正試行→再実行→なお FAIL なら route 準拠 (patch=commit 中止、pr=続行) の挙動が記述されている
- <!-- verify: rubric "skills/code/SKILL.md makes the smoke-test step conditional on the presence of the Spec's ## Smoke Test section; when the section is absent the step is a no-op and behavior is unchanged (backward compatible)" --> Spec に `## Smoke Test` が無い場合は当該手順をスキップし既存挙動と完全互換であることが記述されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Smoke Test" --> `docs/product.md` の `## Terms` に "Smoke Test" 用語が追加されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> SKILL.md 構文検証 (`validate-skill-syntax.py skills/`) が通る

### Post-merge
- `## Smoke Test` セクションを持つ Spec に対し `/code N` を実行すると、commit/push 前に smoke verify command が full mode で実行されることを確認する (verify-type: opportunistic)
- 実機 external connector を使う Issue を `/auto` 非対話モードで実行し、MCP smoke 呼び出しがブロックされたケースで SKIPPED が記録され (フォールバック値の silent 採用なし)、run が中断しないことを確認する (verify-type: manual)

## Tool Dependencies

### Bash Command Patterns
- none (既存パターンで充足)

### Built-in Tools
- `ToolSearch`: verify-executor の `mcp_call` smoke が MCP tool を解決・呼び出すために `skills/code/SKILL.md` の allowed-tools へ新規追加 (#690: 新規ツールは allowed-tools 追記)。KNOWN_TOOLS に既存のため `validate-skill-syntax.py` の更新は不要

### MCP Tools
- none (具体 MCP tool は下流リポジトリの MCP 設定 + permission mode で付与。wholework 側 frontmatter には汎用 `ToolSearch` のみ追加)

## Uncertainty

- **`--permission-mode auto` 下の un-allowlisted MCP tool 呼び出しの挙動**: `claude -p --permission-mode auto` で allow ルールに無い MCP tool を呼んだとき、UNCERTAIN/denied として即返るか、確認待ちで hang するかが環境依存。
  - **Verification method**: 下流リポジトリ (実機 connector) での `/auto` 非対話実行で観測、または verify-executor mcp_call の「blocked → UNCERTAIN」記述 (modules/verify-executor.md) を前提に挙動確認。
  - **Impact scope**: Implementation Step 5 (SKIPPED 分岐)。denied→UNCERTAIN なら設計どおり SKIPPED→continue。hang の場合は `scripts/claude-watchdog.sh` の hang 検知 + 1 retry が処理する (smoke step は watchdog progress line を出力)。

## Notes

- **Step 7 自動解決 (HOW レベル、ユーザー確認不要; WHAT は /issue で確定済)**:
  - 挿入方式 = Step 11 冒頭の h4 サブセクション (renumber 回避; fragility-averse)。
  - ToolSearch を code allowed-tools に追加 (mcp_call smoke の実機実行に必須)。
  - smoke 結果の記録先 = completion message + Step 12 Code Retrospective の "Smoke Test" 行。
- **`## Smoke Test` は Spec 専用** (Issue body へはコピーしない)。smoke は「実装中に走らせる実機 sanity check」(HOW) であり acceptance criteria (WHAT) ではない。`/verify` の post-merge AC とは別軸。
- **入力分離**: code Step 11 smoke サブセクションは Spec の `## Smoke Test` のみを対象とし、Step 10 (Issue body pre-merge AC の verify) とは別入力。Spec の `## Verification` とも別セクション。
- **挿入位置**: code/SKILL.md Step 11 の patch route コミットブロック (`**For patch route (commit to BASE_BRANCH)**`) の直前。
- skill-dev-constraints 適用: #296 (新サブセクション見出しレベルを h4 と明示)、#690 (ToolSearch を AC 化)、#760 (KNOWN_TOOLS 既存のため追記不要)、#273 (product.md 用語追加に対応する実装 Step 7 を配置)。
- **skill-dev-checks (design-time) 結果**:
  - settings.json 変更不要 — 新規 skill 追加ではなく `Skill(code)` は既存。`ToolSearch` は built-in tool であり Bash パターンでも `mcp__` MCP tool でもないため `permissions.allow` 追記不要 (spec/SKILL.md が ToolSearch を settings 追記なしで使用している前例と一致)。
  - 新規 module/agent 不要 — smoke 実行ロジックは `/code` 単独使用のため code/SKILL.md 直書き (verify-patterns §6 の前提: ロジックは SKILL.md に直書きのため verify 対象も SKILL.md)。
  - SKILL.md validation constraint: 半角 `!`・本文中の生 triple backtick を避ける (既存 code fence は可)。frontmatter `description` は変更しない。
  - auto-propose 検出基準 (a)/(b) の列挙には **(examples)** マーカーを付す (網羅でなく代表例)。

## issue retrospective

`/issue 511` リファインメントの判断記録。

### 曖昧性解決 (ユーザー確認 3 点)

| 論点 | 決定 | 理由 |
|------|------|------|
| 非対話 (`/auto`) で実機 MCP 呼び出しがブロックされた場合の挙動 | **SKIPPED 記録して続行** | 本 Issue の発端は `/auto` 非対話モードで classifier が MCP 呼び出しをブロックし silent fallback を採用したこと。実機呼び出し不可時は SKIPPED/UNCERTAIN を記録し commit は止めない (silent fallback も hard-block もしない)。interactive `/code` では実際に走る。環境制約で hard-block すると `/auto` が外部依存で頻繁停止するリスクを回避。 |
| 表現機構 (新 annotation vs 既存再利用) | **既存 verify command を再利用** | `## Smoke Test` セクションに通常の `<!-- verify: mcp_call/command ... -->` を置き `/code` が full mode 実行。verify-executor の safe/full・permission 制御をそのまま継承でき、新パーサ・別系統テスト不要。skill Step 4 の adapter-survey 方針 (新機構より既存コマンド再利用を優先) に合致。原案の専用構文は不採用 (Non-Goals に明記)。 |
| 実機 FAIL 時の挙動 | **1回修正試行→route 準拠** | 既存 Step 9 のテスト FAIL handling と一貫: 1回 fix 試行、patch route は commit 中止して fix loop、pr route は CI/verify に委ねて続行。AC 原案「commit/push 中止し fix loop」を route 別に精緻化。 |

### 自動解決 (低優先 3 点)

- **`/spec` auto-propose 検出ヒューリスティック** — Issue の verify command に `mcp_call` 等が含まれる、または `capabilities.mcp` 設定下で本文が MCP tool を参照する場合に propose。既存 MCP 検出パターンと一貫。AC1 文面は細部に非依存 (HOW は `/spec` に委譲)。
- **スコープ = 汎用 full-mode verify command** — `mcp_call` 限定でなく `command` / `http_status` 等も記述可。verify-executor 再利用で自然にサポート。
- **`.wholework.yml` グローバルトグルは設けない** — opt-in は `## Smoke Test` セクションの有無で表現 (Non-Goals「opt-in」準拠)。

### 受け入れ条件の変更

- 原案「スコープ案 (a)(b)(c)」(実装詳細を含む) を WHAT レベルの Pre-merge / Post-merge AC に再構成。製品境界 (`/issue`=What / `/spec`=How) に従い、専用構文等の実装詳細は本文から除去し Notes の実装方向に降格。
- Pre-merge は `skills/spec/SKILL.md` / `skills/code/SKILL.md` への記述追加を `file_contains` + `rubric` で検証。`Smoke` / `SKIPPED` は現状 0 件のため追加検証アンカーとして有効。
- 用語整合のため `docs/product.md` の `## Terms` に "Smoke Test" 追加を AC 化。

## spec retrospective

### Minor observations
- smoke test 機構は verify-executor 再利用で完結し、新規 module/agent は不要だった (単一 skill 使用ロジックのため SKILL.md 直書き)。
- `skills/code/SKILL.md` の allowed-tools に `ToolSearch` が無く、mcp_call 系を `/code` の full-mode verify-executor 経由で実機呼び出しする経路が従来 latent に UNCERTAIN になっていた点を設計時に発見。今回 ToolSearch を追加して解消。

### Judgment rationale
- 挿入方式は renumber に伴う 5 箇所の cross-ref 更新 (fragile) を避けるため、Step 11 冒頭の h4 サブセクションを採用 (commit/push 前を満たしつつ純追加)。
- blocked→SKIPPED の設計は「`/auto` 安定性 (外部依存で停止しない)」と「silent fallback 防止 (フォールバック値を黙って採用しない)」の両立が狙い。
- FAIL→1 repair→route 準拠は既存 Step 9 テスト FAIL handling を踏襲し、`/code` 内の挙動一貫性を確保。

### Uncertainty resolution
- `permission-mode auto` 下の un-allowlisted MCP 呼び出し挙動 (UNCERTAIN/denied vs hang) は環境依存として Uncertainty に明記。verify-executor の「blocked→UNCERTAIN」記述を前提に SKIPPED→continue を設計し、hang は `claude-watchdog.sh` が処理する想定。実機確認は post-merge manual AC に委譲。

## Code Retrospective

### Deviations from Design
- N/A (implementation followed Spec implementation steps faithfully)

### Design Gaps/Ambiguities
- The Spec's Notes stated "本文に半角 `!` を含めない" — confirmed no half-width `!` introduced in skill bodies. The "!" in the hard-error abort output message ("Fix the issue manually...") was avoided by using a period instead.
- `ToolSearch` was successfully added to allowed-tools frontmatter with no KNOWN_TOOLS update required (as noted in Spec).

### Rework
- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns
- Nothing to note. Spec の全7実装ステップが PR diff に忠実に反映されており、out-of-scope な変更も implicit judgment も検出されなかった。changed files リストも Spec の「変更ファイル」と完全一致。

### Recurring Issues
- Nothing to note. MUST/SHOULD 相当の問題は review-spec・review-bug×2 の全エージェントで検出されなかった。CONSIDER 3件はいずれも Progressive Disclosure 設計判断と日本語表記の軽微な統一提案で、繰り返しパターンには該当しない。

### Acceptance Criteria Verification Difficulty
- Nothing to note. 全7条件に verify command が付与されており、`file_contains` / `section_contains` / `rubric` による自動判定が可能だった。`command` 条件は CI fallback ("Validate skill syntax" SUCCESS) で PASS 確認でき、UNCERTAIN はゼロ。verify command の品質は高く、手動判定不要だった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- mergeable=false/reason=unknown は CI 結果未集計タイミングの誤判定と判断し、非インタラクティブモードの auto-resolve ポリシーに従いマージを続行した。
- PR #545 は conflicts なしのスカッシュマージ成功 (closes #511)。BASE_BRANCH=main のため Issue は自動クローズ。
- コンフリクト解消ステップは不要 (Step 3 スキップ)。

### Deferred Items
- `permission-mode auto` 下の MCP 呼び出し実機挙動 (UNCERTAIN vs hang) の確認は post-merge manual AC に委譲 (code/review phase から継続)。
- Spec に `## Smoke Test` セクションがある実ケースの動作確認は post-merge opportunistic verify。
- docs/ja/workflow.md の "実機 external" 表記改善は必要なら後続 doc Issue で対応。

### Notes for Next Phase (verify)
- verify command は `python3 scripts/validate-skill-syntax.py skills/` 含む7条件。全 CI SUCCESS 確認済み。
- `skills/code/SKILL.md` の `#### Smoke Test` サブセクション、`ToolSearch` allowed-tools、`SKIPPED` 分岐の存在を重点確認。
- post-merge manual AC (MCP smoke 実機) は verify opportunistic モードで実施予定。

## Verify Retrospective

### Phase-by-Phase Review

#### spec (issue)
- 受入条件は WHAT レベルで明確。全7件に verify command (`file_contains` / `section_contains` / `rubric` / `command`) が付与され自動判定可能だった。ambiguity はユーザー確認3点で解消済みで、verify phase で UNCERTAIN ゼロ。Issue=WHAT / Spec=HOW の境界に従い専用構文等の実装詳細を Notes に降格した判断も適切。

#### design (spec)
- 設計は実装に忠実 (Code Retrospective: deviations N/A)。`ToolSearch` 追加・h4 サブセクション挿入 (renumber 回避) などの HOW 判断が code phase で問題なく反映された。`permission-mode auto` 下の MCP 挙動を Uncertainty に明記し実機確認を manual AC に委譲したのは妥当。

#### code
- rework なし。Spec の「半角 `!` 回避」制約を hard-error メッセージで正しく回避 (period 使用)。`ToolSearch` 追加で KNOWN_TOOLS 更新不要を確認。

#### review
- full mode (review-spec + review-bug×2) で MUST/SHOULD ゼロ、CONSIDER 3件 (Progressive Disclosure 設計判断・日本語表記統一) はマージブロックなし。Spec↔実装 divergence なし。

#### merge
- conflict なしスカッシュマージ (closes #511)。mergeable=false/reason=unknown は CI 集計タイミングの誤判定として auto-resolve しマージ続行 — 妥当。

#### verify
- pre-merge 全7件 PASS (冪等再確認、FAIL/UNCERTAIN ゼロ)。post-merge 2件 (opportunistic + manual) は本 run で実行不可のため deferred (phase/verify 維持、Issue は CLOSED のまま)。
- **(解消済み観察)** `skills/code/SKILL.md` に `ToolSearch` が欠けており mcp_call の full-mode 実機実行が latent に UNCERTAIN だった点を本 Issue で発見・解消。full-mode で verify-executor を呼ぶ他 skill を確認したところ、主要消費者の `verify` は既に ToolSearch 保有、`review` は safe mode (mcp_call は実行せず UNCERTAIN のため ToolSearch 不要)。残る `auto`/`audit` の full-mode mcp_call は稀な best-effort ケースで緊急度は低い。

### Improvement Proposals
- N/A — ワークフロー全 phase がクリーン (rework・MUST/SHOULD・conflict・FAIL いずれもゼロ)。ToolSearch の latent gap は主要 full-mode 消費者 (code/verify) で解消済み。残る auto/audit の full-mode mcp_call は稀なため独立 Issue 化は見送り。
