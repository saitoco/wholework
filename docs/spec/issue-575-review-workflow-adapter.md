# Issue #575: review: workflow adapter 実装（capabilities.workflow opt-in + static fan-out fallback）

## Overview

`/review --full` に Claude Code の Workflow ツール（マルチエージェント orchestration）を opt-in で搭載する。`.wholework.yml` に `capabilities.workflow: true` を宣言したプロジェクトでは、finder → adversarial verify pipeline を Workflow ツールで実行する。未設定（既定）の場合は現行の static Task fan-out（Step 10.1–10.3）にそのまま fallback し、既存ユーザーへの breaking change は発生しない。

実装範囲は #565 spike レポート（`docs/reports/workflow-adapter-spike.md` §Implementation Scope）の 5 項目:
1. Workflow スクリプト（finder fan-out → adversarial verify pipeline）
2. `capabilities.workflow` → `HAS_WORKFLOW_CAPABILITY` の capability 検出
3. Domain file `skills/review/workflow-guidance.md`（`load_when: capability: workflow`）
4. `skills/review/SKILL.md` Step 10 の `HAS_WORKFLOW_CAPABILITY` 分岐
5. `docs/tech.md` fork 判断テーブルへの「Execution Platform」列追加（routing SSoT）

スコープは `/review --full` のみ。Workflow は決して既定にしない（opt-in only）。

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `capabilities.workflow` → `HAS_WORKFLOW_CAPABILITY` の明示行を追加し、Output Format ブロックに対応行を追加（bash 不使用、markdown のみ）
- `skills/review/workflow-guidance.md`: 新規 Domain file（frontmatter `type: domain` / `skill: review` / `load_when: capability: workflow` + 実行ガイダンス + inline Workflow JS スクリプト + コスト透明性ノート）
- `skills/review/SKILL.md`: (a) `allowed-tools` frontmatter に `Workflow` を追加、(b) Step 7.0 の検出結果リストに `HAS_WORKFLOW_CAPABILITY` を追加、(c) Step 10 に `HAS_WORKFLOW_CAPABILITY` 分岐（full mode）を追加。本文に half-width `!` を導入しない
- `scripts/validate-skill-syntax.py`: `KNOWN_TOOLS` に `'Workflow'` を追加し、`BODY_TOOL_CHECK_SKIP` にも `'Workflow'` を追加（bash 3.2+ 互換の Python 変更／シェル非依存）
- `docs/guide/customization.md`: Available Keys テーブルに `capabilities.workflow` 行を追加し、`capabilities:` の YAML 例に `workflow: true` を追記
- `docs/ja/guide/customization.md`: 上記の日本語ミラー同期
- `docs/tech.md`: fork 判断テーブル（§Architecture Decisions）に「Execution Platform」列を追加（全 10 行）
- `docs/ja/tech.md`: fork 判断テーブルに「実行基盤」列を追加（日本語ミラー同期）

## Implementation Steps

1. `modules/detect-config-markers.md` の Marker Definition Table に明示行 `| capabilities.workflow | HAS_WORKFLOW_CAPABILITY | true | false |` を追加（既存 `capabilities.visual-diff` 行の直後・`browser`/`visual-diff` と同じ書式）。Output Format ブロックにも `HAS_WORKFLOW_CAPABILITY: true if capabilities.workflow: true is set (default: false)` を追加。Dynamic Capability Mapping でも解決されるが、precedent（browser/visual-diff）に揃えて明示行とし rubric を決定的に PASS させる（→ acceptance criteria 1）

2. `skills/review/workflow-guidance.md` を新規作成（→ acceptance criteria 3, 4, 5, 9）。Module 標準ではなく Domain file 構造とし、以下を含める:
   - frontmatter: `type: domain` / `skill: review` / `load_when:` 配下に `capability: workflow`（値を固定文字列 `capability: workflow` で記述）
   - find/filter 分離契約の明記: finder（review-spec / review-bug）は **coverage role** として全 finding を confidence（high/medium/low）+ severity（MUST/SHOULD/CONSIDER）付きで報告し、adversarial verification が下流で filter する
   - inline Workflow スクリプト（```javascript フェンス内）: `pipeline(FINDERS, finderStage, verifyStage)` 形式。finder は `agentType: 'review-spec' / 'review-bug'` + `schema: FINDINGS_SCHEMA`、verify は refute-by-default の `schema: VERDICT_SCHEMA`。`confirmed = results.flat().filter(Boolean).filter(f => !f.refuted)` で false-positive を除去
   - コスト透明性ノート: workflow 結果に `budget.spent()` 概算トークンを含め、skill 完了レポートに出力する旨を記載
   - Workflow ツールは inline `script` 渡しを前提（別ファイル `scripts/review-workflow.js` は作成しない。理由は Alternatives Considered 参照）

3. `skills/review/SKILL.md` を 3 点更新（→ acceptance criteria 6, 9）:
   - (a) `allowed-tools` frontmatter の末尾（`ExitWorktree` の後）に `, Workflow` を追加
   - (b) Step 7.0 の検出結果ブロック（`HAS_COPILOT_REVIEW: ...` のリスト）に `HAS_WORKFLOW_CAPABILITY: true if capabilities.workflow: true is set (default: false)` を追加
   - (c) Step 10 見出し直後に分岐パラグラフを追加: 「`HAS_WORKFLOW_CAPABILITY=true` かつ `REVIEW_DEPTH=full` のとき、Step 3 でロード済みの `skills/review/workflow-guidance.md` の Processing Steps に従い Workflow ツールで finder → adversarial verify pipeline を実行する。`HAS_WORKFLOW_CAPABILITY=false`／未設定（既定）のときは下記 10.1–10.3 の static Task fan-out をそのまま実行する」。10.0–10.3 本体は変更しない（fallback 経路温存）

4. `scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` set に `'Workflow'` を追加し、`BODY_TOOL_CHECK_SKIP` set にも `'Workflow'` を追加（コメントで「common English word（既存 skill 本文に "Workflow" トークンが出現するため body check 除外）」を明記）（→ acceptance criteria 10）

5. `docs/guide/customization.md` の Available Keys テーブルに `| `capabilities.workflow` | boolean | `false` | Enable Workflow-based multi-agent execution in `/review --full` (opt-in; falls back to static Task fan-out) |` を `capabilities.{name}` 行付近に追加し、`capabilities:` の YAML コードブロック例に `workflow: true # ...` を追記（→ acceptance criteria 2）

6. `docs/tech.md` の fork 判断テーブル（§Architecture Decisions）に「Execution Platform」列を挿入（`Fork needed` と `Reason` の間）。全 10 行に値を記入: review = `In-session (Workflow opt-in via capabilities.workflow: true) / headless fallback`、spec/code = `headless (run-*.sh) / in-session (direct)`、merge = `headless`、verify/triage/auto/audit/doc = `in-session`、issue = `headless (L/XL) / in-session (direct)`（→ acceptance criteria 7）

7. `docs/ja/guide/customization.md` と `docs/ja/tech.md` を上記 5・6 と同コミットで日本語同期（fork テーブルは「実行基盤」列を追加、Available Keys は `capabilities.workflow` 行追加）。同コミットにすることで git timestamp が一致し IN_SYNC となる（→ acceptance criteria 8）

## Alternatives Considered

**Workflow スクリプトの配置（採用 vs 不採用）:**

- **採用: Domain file 内に inline JS スクリプトを埋め込む**（`skills/review/workflow-guidance.md` の ```javascript フェンス）。`/review` 実行時に Workflow ツールの `script` パラメータへ inline 渡しする。
- **不採用: `scripts/review-workflow.js` 別ファイル**（spike レポート §Implementation Scope item 1 の文字どおりの案）。

採用理由:
1. Workflow ツールのガイダンスが inline 渡しを明示推奨（「Pass the script inline via `script` — do not Write it to a file first」）
2. `scripts/` は `structure.md` 上 `.{sh,py}` のみ（49 files）。`.js` を置くと命名規約違反 + Scripts リスト追記 + file count bump が発生
3. Domain file は `capability: workflow` で条件ロードされるため、スクリプトとガイダンスが同一ファイルに同梱され、opt-in 経路でのみ context に載る（progressive disclosure 原則に整合）
4. Issue 本文 §1 が「SKILL.md からのインライン script 渡しでも可」と明示的に許可

**capability 検出方式:**

- **採用: 明示テーブル行**（`browser` / `visual-diff` precedent に整合）。
- **不採用: Dynamic Capability Mapping のみに依存**。動作上は両者とも `HAS_WORKFLOW_CAPABILITY` を解決するが、明示行のほうが discoverability が高く、rubric（AC 1）が決定的に PASS する。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md resolves capabilities.workflow to HAS_WORKFLOW_CAPABILITY, either via an explicit table entry or the existing Dynamic Capability Mapping" --> `detect-config-markers.md` が `capabilities.workflow` → `HAS_WORKFLOW_CAPABILITY` を解決する（明示エントリまたは Dynamic Capability Mapping 経由）
- <!-- verify: file_contains "docs/guide/customization.md" "capabilities.workflow" --> `docs/guide/customization.md` に `capabilities.workflow` 設定が記載されている
- <!-- verify: file_exists "skills/review/workflow-guidance.md" --> Domain file `skills/review/workflow-guidance.md` が存在する
- <!-- verify: grep "load_when" "skills/review/workflow-guidance.md" --> Domain file が `load_when` 宣言を持つ
- <!-- verify: file_contains "skills/review/workflow-guidance.md" "capability: workflow" --> Domain file が `capability: workflow` 条件付きでロードされる
- <!-- verify: grep "HAS_WORKFLOW_CAPABILITY" "skills/review/SKILL.md" --> `/review` Step 10 が `HAS_WORKFLOW_CAPABILITY` で Workflow / Task fan-out を分岐する
- <!-- verify: grep "Execution Platform" "docs/tech.md" --> `docs/tech.md` fork 判断テーブルに Execution Platform 列が追加されている
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期済み（translation-sync pass）
- <!-- verify: rubric "the workflow execution path in skills/review/workflow-guidance.md preserves the find/filter separation contract: finders report all findings with confidence and severity (coverage role), and adversarial verification filters downstream; the fallback path (capabilities.workflow unset) remains the current static Task fan-out unchanged" --> Workflow 経路が find/filter 分離契約を保持し、fallback 経路が現行のまま温存されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存 bats テストが green

### Post-merge

- `capabilities.workflow: true` を設定したプロジェクトで `/review --full` が Workflow 経路で完走し、完了レポートに概算トークン使用量が出力されることを確認 <!-- verify-type: manual -->
- `capabilities.workflow` 未設定プロジェクトで `/review --full` が現行 Task fan-out で回帰なく動作することを確認 <!-- verify-type: opportunistic -->

## Tool Dependencies

### Bash Command Patterns
- none（新規 Bash パターンなし）

### Built-in Tools
- `Workflow`: `/review --full` の opt-in 経路で finder → adversarial verify pipeline を実行（`skills/review/SKILL.md` の `allowed-tools` に追加。`scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` 登録が前提）

### MCP Tools
- none

## Uncertainty

- **Workflow ツールの permission-mode auto / settings.json gating**: `--permission-mode auto`（`run-review.sh` 既定）下で Workflow ツールが settings.json への明示エントリなしに呼び出せるか。
  - **Verification method**: spike レポート Spike 1 で `claude -p --permission-mode auto` のツールリストに `Workflow` が出現することを実証済み（認証障壁・beta フラグなし）。settings.json は Bash パターンのみを列挙しており、built-in tool は `allowed-tools` frontmatter で許可される。`/code` 実装時に review SKILL.md の `allowed-tools` へ `Workflow` を追加することで充足。
  - **Impact scope**: Implementation Step 3(a), 4

## Notes

- **Workflow を allowed-tools へ追加する際の KNOWN_TOOLS 同期（必須）**: `scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` に `Workflow` が未登録（確認済み）。未追加だと review SKILL.md の allowed-tools 検証が「unknown tool name」で FAIL し AC 10（bats green）が崩れる（precedent: #760 KNOWN_TOOLS sync）。
- **BODY_TOOL_CHECK_SKIP への追加（必須）**: body tool usage check は `\bWorkflow\b`（whole-word, case-sensitive）でマッチする。既存の `skills/spec/SKILL.md`（"Workflow-impacting" / "Size-to-Workflow Determination"）と `skills/verify/SKILL.md`（"Full Workflow Review"）が本文中に "Workflow" トークンを含む（grep 確認済み）。`KNOWN_TOOLS` に追加するだけだとこれら 2 ファイルが「allowed-tools に未宣言」で誤検知 FAIL する。`Task`/`Agent`/`Skill` と同様に common English word として `BODY_TOOL_CHECK_SKIP` へも追加する。
- **Execution Platform 列のスコープ**: 本 Issue は routing 方針を SSoT 化する（tech.md / ja tech.md の列追加）のみで、`run-review.sh` の実行基盤（headless → in-session）を実際に移行はしない。review の in-session 移行は spike レポート §Routing Recommendation の将来候補であり、別 Issue で評価する。
- **detect-config-markers.md は明示行と Dynamic Capability Mapping の両方が `HAS_WORKFLOW_CAPABILITY` を解決する**: 明示行を追加しても Dynamic Capability Mapping ルール（table 未掲載キーを動的マップ）と矛盾しない（明示が優先、同一変数を生成）。
- **structure.md 変更不要**: 新規 Domain file は `skills/` 配下（modules/scripts/agents の file count 対象外）であり、Skills セクションの補助ファイル列挙は examples のみ（網羅列挙ではない）。`scripts/validate-skill-syntax.py` は既存ファイル修正のため count 変化なし。
- **`docs/workflow.md` 変更不要**: 実行基盤・in-session/headless・capabilities.workflow への参照なし（grep 確認済み）。

## Autonomous Auto-Resolve Log

非対話モードのため以下を model 判断で auto-resolve した:

- **Workflow スクリプト配置 = Domain file inline 埋め込み** — reason: Workflow ツールが inline 渡しを明示推奨、`scripts/` は `.sh`/`.py` 規約、opt-in 経路でのみ context 投入する progressive disclosure に整合、Issue 本文が inline 渡しを明示許可。
  - Other candidates: `scripts/review-workflow.js` 別ファイル（structure.md 命名規約違反 + count/list churn）
- **capability 検出 = detect-config-markers.md に明示テーブル行を追加** — reason: browser/visual-diff precedent に整合、rubric（AC 1）を決定的に PASS、discoverability 向上。
  - Other candidates: Dynamic Capability Mapping のみに依存（動作は同一だが暗黙的）
- **Execution Platform 列 = routing SSoT のドキュメント化のみ（実行基盤の実移行はしない）** — reason: Issue scope は Workflow engine の opt-in 搭載であり実行基盤移行ではない。スコープを 5 項目に限定。
  - Other candidates: review を in-session に実移行（過剰スコープ、別 Issue 案件）

## issue retrospective

### 自動解決ログ（Auto-Resolve Log）

非対話モードで実行。以下の ambiguity points を /issue フェーズで自動解決した。

#### 1. `capabilities.workflow` verify command — `rubric` + `customization.md` check に置換

**旧 AC**: detect-config-markers.md への grep

**採択**: `rubric "modules/detect-config-markers.md resolves capabilities.workflow to HAS_WORKFLOW_CAPABILITY..."` + `file_contains "docs/guide/customization.md" "capabilities.workflow"` の2点に分割

**理由**: `modules/detect-config-markers.md` は Dynamic Capability Mapping により明示エントリなしに `capabilities.workflow` → `HAS_WORKFLOW_CAPABILITY` を解決しうる。実装者が dynamic mapping を採用した場合、元の grep は両文字列とも現れず FAIL する。最小リスク: rubric（意味的検証）+ customization.md（必ず変更されるドキュメント）の組み合わせ。

#### 2. `load_when` 検証強化

**追加**: `file_contains "skills/review/workflow-guidance.md" "capability: workflow"`

**理由**: `grep "load_when"` のみでは値を確認できない。`visual-diff-guidance.md` パターンに合わせ値の固定文字列検証を独立追加。

#### 3. `bats テストが green` に verify command 追加

**採択**: `github_check "gh pr checks" "Run bats tests"`

**理由**: Pre-merge 条件に verify command が欠落。`.github/workflows/test.yml` のジョブ名を確認。Size=L → PR route のため `gh pr checks` 利用可能。

#### 4. Post-merge fallback の `verify-type` 維持

**採択**: `verify-type: opportunistic` を維持。

**理由**: verify-classifier.md の「/skill-name 実行時に確認」パターンに合致。機械的 verify command を強制しない。

#### 5. `customization.md` 記載の AC 欠落を補完

**採択**: `file_contains "docs/guide/customization.md" "capabilities.workflow"` を新規 AC として追加。

**理由**: Issue 本文 §2 に「ガイド文書 customization.md にも記載」と明記されていたが元の AC に未反映だった。

## spec retrospective

### Minor observations
- Issue 本文 §1 が Workflow スクリプト配置を「実装時に確定」と未確定にしていた。spec で Domain file inline 埋め込みに確定。配置方針を Issue 段階で決めておくと code フェーズの判断負荷が下がる。

### Judgment rationale
- `Workflow` を allowed-tools に追加する際、`validate-skill-syntax.py` の `KNOWN_TOOLS` 同期だけでなく `BODY_TOOL_CHECK_SKIP` への追加も必要と判明。既存 spec/verify SKILL.md が本文に "Workflow" トークン（"Workflow-impacting"、"Full Workflow Review" 等）を含み、body tool check（`\bWorkflow\b`）が誤検知 FAIL するため。tool 名が一般英単語と衝突する場合の二重対応は Task/Agent/Skill と同じパターン。
- capability 検出は Dynamic Capability Mapping で動作上は足りるが、precedent（browser/visual-diff の明示行）に揃えることで rubric（AC 1）を決定的に PASS させ discoverability も確保。
- Workflow スクリプトを別ファイル化せず Domain file に inline 埋め込みとした。Workflow ツール自身が inline 渡しを推奨し、opt-in 経路でのみ context へ載る progressive disclosure に整合する。

### Uncertainty resolution
- Workflow ツールの permission-mode auto 下での可用性は Spike 1（レポート §Spike 1）が実証済みで、新規検証は不要だった。settings.json は Bash パターンのみを列挙し built-in tool は allowed-tools 経由で許可される構造を確認。

## Code Retrospective

### Deviations from Design
- Spec の実装ステップを全て忠実に実行し、実質的な逸脱はなかった
- `args` ベースのプロンプト変数（`args.number`、`args.issueNumber` など）は Workflow スクリプト内で参照したが、caller が `args` を渡す形式を明示する必要があった。workflow-guidance.md の Processing Steps に「args 渡し」の説明を追加済み

### Design Gaps/Ambiguities
- inline Workflow JS スクリプト内の `SKIP_BUG` 判定は `args && args.skipReviewBug` として記述したが、Spec には `SKIP_REVIEW_BUG` 変数をどのように `args` に渡すかが記載されていなかった。caller 側（SKILL.md）の Step 10 分岐パラグラフで `SKIP_REVIEW_BUG` を `args.skipReviewBug` として渡す旨を workflow-guidance.md の Processing Steps に記述することで吸収した
- SKILL.md の half-width `!` 禁止制約は Phase Handoff に明記されており、Step 10 分岐パラグラフの文言を全角や言い換えで回避した

### Rework
- 特になし。全テスト（bats 697件、validate-skill-syntax、forbidden-expressions check、translation-sync）が 1 回目で PASS した

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

Code Retrospective には「args 渡しの説明を追加済み」とあったが、実際の `workflow-guidance.md` Processing Steps Step 4 には args オブジェクト形式が記載されておらず、指摘後に修正が必要だった。Spec の「実装ステップ 3(c)」ではその旨を明記していたが、実装時に本文への反映が抜け落ちた。Spec の Design Gaps/Ambiguities セクションにあるような実装時の知見（args 渡し形式）は、Done として先に閉じるのではなく、Spec の当該実装ステップに直接補記するパターンが望ましい。

### Recurring Issues

N-vote / majority vote という表現が Spike レポートから引き継がれ、実装が 1-vote 相当（finding ごとに 1 つの refutation agent）であるにもかかわらずドキュメントに残存していた。Spike レポートの記述（「N-vote adversarial verify」）と実装コードの間にドキュメント乖離が生じた。Spike 段階の aspirational 記述をそのまま Domain file に転記する際は、実際の実装に合わせた表現に落とし込む確認が必要。

### Acceptance Criteria Verification Difficulty

verify command のカバレッジは良好だった（rubric×2、file_contains×3、grep×3、command×1、github_check×1）。唯一 `github_check "gh pr checks" "Run bats tests"` が PR 作成直後は PENDING（CI 未完了）のため `- [ ]` だったが、今回のレビューで CI が完了し PASS に更新できた。Spec の Notes for Next Phase にその旨が明記されており、予見された状況であった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #578 を squash merge で main にマージ（conflicts なし、CI SUCCESS、受け入れ基準全PASS済み）
- `--delete-branch` でリモートブランチ `worktree-code+issue-575` を削除
- BASE_BRANCH=main のため `closes #575` が Issue を自動クローズ

### Deferred Items
- Post-merge 手動確認: `capabilities.workflow: true` 設定プロジェクトで `/review --full` が Workflow 経路完走し、完了レポートにトークン使用量が出力されることを確認（opportunistic）
- `capabilities.workflow` 未設定プロジェクトでの fallback 動作の回帰確認（opportunistic）

### Notes for Next Phase
- verify フェーズ: Spec の verify command でpost-merge rubricを実行可能（capabilities.workflow を設定したプロジェクトが必要）
- SKILL.md Step 3 見出し改善（「Domain files (bundled + project-local)」）は次の修正機会に検討（deferred from review）
