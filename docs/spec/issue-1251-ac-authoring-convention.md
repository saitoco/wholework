# Issue #1251: verify-executor/verify-classifier: AC に評価者が必要とする情報 (rubric の参照ファイル・数値 AC の母集団定義) を含める規約を追加

## Overview

`/auto 1158` の実行を通じて、AC (Acceptance Criteria) が評価者 (rubric grader / observation dispatch) の判定に必要な情報を条件文自身に含めていない、という同一クラスの欠陥が 3 形態・複数 Issue にわたって確認された。本 Issue はこれを再発防止するため、`modules/verify-executor.md` の rubric guidelines と `modules/verify-classifier.md` の observation AC 記法に、次の 3 点の記述規約を追加する:

1. **rubric の参照ファイル明示** — 一次証拠が `git diff` / Issue 本文の外にある場合、rubric text で当該ファイルを名指しする
2. **数値 AC の母集団定義** — 数値の増減を条件にする場合、母集団定義を条件文に含める。集計値ベースより対象エンティティの個別状態で書くほうを推奨する
3. **observation AC の発火見込みの明示** — どの event が発火したとき何を根拠に PASS 判定できるかを条件文に書く。書けないなら observation AC にせず、代替手段を選ぶ

`skills/issue/SKILL.md` Step 4 (AC 生成ステップ、Step 7 から全文委譲されるため両フローに自動適用される) にもこれら 3 規約への参照と、observation 型を選ぶ前の発火見込み確認ステップを追加し、AC を書く側の入口から規約に到達できるようにする。

## Changed Files

- `modules/verify-executor.md`: rubric guidelines に新規ガイドライン節「Primary evidence outside git diff / Issue body」を追加
- `modules/verify-classifier.md`: observation 型の記法に新規サブセクション「observation Type: Population Definition for Numeric Conditions」「observation Type: Firing Likelihood Check (before assignment)」を追加
- `skills/issue/SKILL.md`: Step 4 (AC 生成ステップ) に「AC authoring convention — evaluator self-sufficiency」段落と「Firing likelihood check (before assigning `observation`)」段落を追加

**Steering Docs sync candidate check** (Changed Files に SKILL.md を含むため実施): `grep -rn` で `docs/`, `tests/`, `scripts/` を横断検索した結果 (キーワード: 追加ガイドラインの見出し文言、`observation Type: Event Values and Syntax`)、`docs/spec/issue-1158-manual-ac-retype-summary.md` 等の disposable Spec ファイルのみがヒットし (doc-checker.md の scope 定義により `$SPEC_PATH/` 配下は検索除外対象)、同期が必要な `docs/guide/`・`docs/workflow.md`・`tests/*.bats` の候補は見つからなかった。`tests/verify-executor.bats`/`tests/issue.bats`/`tests/run-issue.bats` の既存 `@test` は本 Issue が変更しない別内容 (patch route CI verification テンプレート、pre-merge-preview tier 等) を対象にしており、追随不要。

## Implementation Steps

1. `modules/verify-executor.md` に新規ガイドライン節を追加 (→ 受入条件 AC1, AC2)。挿入位置: 「**Exit code verification pattern in rubric text:**」節の末尾 (`...that lack an explicit status assertion.` で終わる段落) の直後、「**Slash (`/`) notation in rubric condition text:**」の直前。既存 2 節と同じスタイル (太字見出し + 本文 + `Motivation:` + `**Guideline**:` + コード例) で以下を挿入:

   ```markdown
   **Primary evidence outside git diff / Issue body:**
   When the primary evidence for an acceptance condition is not visible in either of the grader's two default inputs (`git diff`, Issue body — see "Grader input scope" above), explicitly name the file(s) carrying that evidence in the rubric text. Files explicitly named in "text" are the only way to extend the grader's input scope beyond those two defaults; a rubric that omits the file name gives the grader no path to the actual evidence.

   Motivation: Two patterns recur where primary evidence lives outside both defaults. **Operate route**: an Issue whose only artifact is a GitHub Issue body edit — the edit is never a commit, so it never appears in `git diff`. **XL parent aggregation**: a parent Issue's acceptance condition whose evidence is a sub-issue's own record file, landed in a separate PR the grader never reads. A rubric that does not name the file leaves the grader unable to reach primary evidence in either case — a PASS verdict in that state confirms only that an aggregate summary in the Issue body looks right, not that the summary matches the primary record it summarizes (gap identified in Issue #1158's `/verify` retrospective).

   **Guideline**: Name the specific file path(s) that carry the primary evidence directly in the rubric text. Example:

   ```
   rubric "docs/reports/manual-ac-retype-summary.md's counts match the per-sub-issue record files docs/reports/manual-ac-retype-a.md and manual-ac-retype-d2.md"
   ```

   Naming the file(s) directs the grader's input scope to the actual evidence instead of leaving it to infer correctness from an aggregate summary alone.
   ```

2. `modules/verify-classifier.md` に新規サブセクションを 2 件追加 (→ 受入条件 AC3, AC4, AC6, AC7)。挿入位置: `session=next` サブステップの末尾 (`...Issue #1157, condition 7.` で終わる Background 文) の直後、「### Tag Assignment Example」の直前。この順序 (母集団定義 → 発火見込み) は Issue Purpose の記載順に合わせる:

   ```markdown
   ### observation Type: Population Definition for Numeric Conditions

   When an observation condition's evidence is a count or aggregate (e.g., "the number of X has decreased since a baseline of N"), state the population the count is measured against directly in the condition text — the scan scope (label filter, date range, open/closed state) the number was computed from. Without an explicit population, a later re-measurement under a different scope can produce a materially different number, and even invert the PASS/FAIL verdict for the same underlying change (observed in Issues #1164/#1165/#1158: a baseline of 79 measured within a 90-day window read as an increase to 123 when re-measured all-time, but as a decrease to 18 within that same 90-day window).

   **Trade-off — aggregate count vs. individual entity state**: an aggregate count is compact but re-scopable, so its PASS/FAIL verdict depends on a population definition living outside the condition unless the condition states one explicitly. An individual-entity condition (e.g., "confirm Issue #1066 and #1060 are no longer counted; Issues #1059/#709/#548/#442/#441 remain intentionally and are not counted toward the decrease") has nothing to re-scope — it is verifiable as written, with no population definition needed (Issue #1167). **Prefer the individual-entity form** when the set of relevant entities is small and enumerable.

   **When an aggregate count cannot be avoided**: state the population explicitly in the condition text itself (label filter, date range, open/closed state) — do not rely on a value recorded elsewhere (e.g., a linked report's own baseline note) to supply it implicitly.

   ### observation Type: Firing Likelihood Check (before assignment)

   Before assigning `verify-type: observation`, confirm the condition text can state two things: which `event=<name>` firing is expected to supply evidence, and what evidence — once that event fires — is sufficient to judge PASS or FAIL. Write both directly into the condition text; do not leave them implicit.

   If the condition cannot state the second part — there is no describable evidence a firing of the chosen event would produce, only a hope that a relevant firing eventually occurs — do not assign `observation`. A condition that cannot state its own resolution path either accumulates SKIPPED notifications indefinitely (the event never fires in a way relevant to the condition) or, worse, is judged against evidence the verifier cannot actually observe.

   **Alternatives, in order of preference:**
   1. **Resolve now**: if the underlying fact is already knowable at merge time, verify it directly (a pre-merge condition, or an `auto`-type post-merge condition with its own verify command) instead of deferring it to a future event.
   2. **Fall back to `auto`**: if a concrete, mechanically-checkable verify command exists for the condition once the relevant state exists, attach it and classify as `verify-type: auto` instead of `observation`.
   3. **Drop the condition**: if the condition does not correspond to a resolvable gate at all, remove it from the Issue rather than leaving an unresolvable placeholder in `phase/verify`.

   **Examples that fail the firing likelihood check** (cannot state evidence-on-fire): a condition assuming a specific downstream skill runs on a particular future `/auto` invocation (no guarantee it does), a condition awaiting "the next PR of a specific shape" (no guarantee the observation window sees one before it closes), a condition awaiting "the next Spec that touches a certain topic" (a Spec's subject matter is not itself an event `opportunistic-search.sh` can dispatch on).
   ```

3. `skills/issue/SKILL.md` Step 4 に段落を 2 件追加 (→ 受入条件 AC5, AC8)。Step 7 (Existing Issue Refinement) は Step 4 の手順を全文参照で委譲するため、この 1 箇所の追加で両フローに自動適用される:

   (a) 挿入位置: 「rubric の numeric literal/threshold value のガイダンス」段落の末尾 (`...alongside the \`rubric\` to enable deterministic verification of the value.` で終わる) の直後、「When MCP tools are available, ...」の直前:

   ```markdown
   **AC authoring convention — evaluator self-sufficiency:** An acceptance condition must carry the information its evaluator needs to judge it, not rely on context outside the condition text. Before finalizing a `rubric` command whose primary evidence lives outside `git diff`/the Issue body, read `modules/verify-executor.md` § Rubric Command Semantics ("Primary evidence outside git diff / Issue body"). Before writing a numeric or `observation`-tagged post-merge condition, read `modules/verify-classifier.md` § observation Type (Population Definition for Numeric Conditions, Firing Likelihood Check).
   ```

   (b) 挿入位置: 「Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` and assign `<!-- verify-type: auto|opportunistic|observation|manual -->` tags to each post-merge condition.」の直後、「**Skill self-update propagation check:**」の直前:

   ```markdown
   **Firing likelihood check (before assigning `observation`):**

   Before tagging a condition `verify-type: observation`, apply `modules/verify-classifier.md` § observation Type: Firing Likelihood Check — confirm the condition text states which `event=<name>` firing supplies evidence and what that evidence is. If it cannot, use one of that section's alternatives (resolve now, fall back to `auto`, or drop the condition) instead of assigning `observation`.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "primary evidence" "modules/verify-executor.md" --> `modules/verify-executor.md` の rubric guidelines に「一次証拠が git diff / Issue 本文の外にある場合、rubric text で当該ファイルを明示的に名指しする」旨のガイドラインが追加されている
- <!-- verify: rubric "追加されたガイドラインが、git diff に現れない一次証拠のパターン (operate route の Issue 本文編集、別 PR で着地した記録ファイル) を具体例として示している" --> 上記ガイドラインが、operate route / XL 親の集約 PR という「一次証拠が別 PR や GitHub Issue 本文にある」典型パターンを具体例として挙げている
- <!-- verify: grep "母集団|population" "modules/verify-classifier.md" --> `modules/verify-classifier.md` の observation AC 記法に「数値の増減を条件とする場合は母集団定義を条件文に含める」旨の規約が追加されている
- <!-- verify: rubric "observation AC の記法説明が、集計値ベースと個別エンティティベースの trade-off を示し、後者を推奨している" --> 上記規約が、集計値ベースより対象エンティティの個別状態で書くほうが評価可能性が高いこと (#1167 の実例) を推奨として示している
- <!-- verify: grep "evaluator needs" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の AC 生成ステップが上記 3 規約を参照している (AC を書く側の入口で規約に到達できる)
- <!-- verify: grep "firing likelihood" "modules/verify-classifier.md" --> `modules/verify-classifier.md` の observation 型の説明に「どの event が発火したとき何を根拠に PASS 判定できるかを条件文に書く。書けないなら observation AC にしない」旨の規約が追加されている
- <!-- verify: rubric "observation AC を作らない場合の代替手段が複数示され、それぞれをいつ選ぶかの判断基準が記述されている" --> 上記規約が、満たされ方を書けない条件の代替 (merge 時点で判断を終わらせる / auto 型の verify command へ落とす / そもそも AC にしない) を選択肢として示している
- <!-- verify: rubric "skills/issue/SKILL.md の verify-type 割り当て手順に、observation 型を選択する際の発火見込み確認ステップが含まれている" --> `skills/issue/SKILL.md` の `verify-type` 割り当てステップに、observation を選ぶ前に発火見込みを確認する段が追加されている

### Post-merge

- 次回 rubric 型 AC を含む Issue の `/review` または `/verify` 実行で、参照ファイル明示により grader が一次資料まで到達できることを確認する <!-- verify-type: observation event=pr-review-full session=next -->

## Notes

- **verify command の事前修正 (Comment Consumption 起因)**: `/issue 1251 --non-interactive` Step 15 (AC Verify Command Integrity Audit) が、Pre-merge AC1/AC5/AC6 の verify command を Pattern 2 (常時 PASS) と判定するコメントを投稿していた (対象文字列が本 Issue の実装前から無関係な文脈で既に存在するため)。Comment Consumption Procedure でこれを読み取り、`/spec` 実行時点で Issue 本文の該当 3 件を実装内容に固有の新規文字列へ修正した (`grep` verify command のみ変更、条件文自体は不変):
  - AC1: `grep "explicitly named" ...` → `grep "primary evidence" "modules/verify-executor.md"` (`"explicitly named"` は既存の rubric grader 入力スコープ定義文言と重複するため)
  - AC5: `grep "verify-executor|verify-classifier" ...` → `grep "evaluator needs" "skills/issue/SKILL.md"` (両ファイルへの既存参照が複数箇所にあり無関係にマッチするため)
  - AC6: `grep "observation" ...` → `grep "firing likelihood" "modules/verify-classifier.md"` (`"observation"` は observation 型の既存説明全体で多用されているため)
  - 3 件とも、実装前の現行内容に対象文字列が存在しないことを `grep` で確認済み (常時 PASS 回避を再確認)
  - Issue 本文は `gh-issue-edit.sh` で更新済み。本 Spec の Verification セクションは更新後の Issue 本文から逐語コピーしている (Verify command sync rule)
- **Pre-merge verification item count について**: 8 件で SPEC_DEPTH=light の上限 (5 件) を超えるが、「Verify command sync rule」により Issue 本文の Pre-merge acceptance criteria (8 件、`/issue` で既に確定・監査済み) を改変せず逐語コピーした結果であり、Issue #1063 の Spec に同型の前例がある。`/verify` は各項目をインデックスで個別にチェックするため、統合による件数圧縮は行わなかった
- **Issue body vs. 既存実装の整合性確認**: Issue Background が引用する `modules/verify-executor.md:85` の rubric grader 入力スコープ定義 ("pass Issue body, git diff, and any files explicitly named in \"text\" as input") および「先例」節が挙げる既存ガイドライン節 2 件 (`Security-sensitive validator rubric guidelines`, `Exit code verification pattern in rubric text`) は、いずれも実際のファイル内容と一致することを確認済み。conflict なし
- **テスト変更なし**: 本 Issue は既存 `modules/*.md` セクション・`skills/issue/SKILL.md` Step 4 への文言追加のみで、新規スクリプト・マーカー・関数の挙動を導入しないため、bats テストの追加・変更は不要と判断した (`tests/verify-executor.bats`/`tests/issue.bats`/`tests/run-issue.bats` を確認し、いずれも本 Issue が変更しない別内容を対象にしていることを確認済み)

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1251 --non-interactive` の Issue Retrospective — refinement で実施した grep verify command 構文修正 (4 件、`\|` → `|` 等) と Post-merge AC への `session=next` 追加を記録。AC5/AC6 の verify command が弱い (常時 PASS しうる) ことは Step 15 の audit に委譲する旨の記載あり。https://github.com/saitoco/wholework/issues/1251#issuecomment-5228748367
- saito (MEMBER, first-class): AC Verify Command Integrity Audit — Pre-merge AC1/AC5/AC6 の verify command が Pattern 2 (常時 PASS) に該当すると指摘し、`/spec` での修正を明示的に要請。本 Spec 作成時に Issue 本文を修正して対応 (Notes 参照)。https://github.com/saitoco/wholework/issues/1251#issuecomment-5228767594

### code フェーズ (2026-08-09)

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- Implementation Steps 1-3 は Spec の指示どおり個別に commit した (Step 8 の "Commit after each step completes" に従い、3 commit に分割)。この結果、`/code` Step 11 が定義する「単一の実装 commit に `(closes #N)` を含める」形にはならず、closes 参照は Step 12 の retrospective commit のメッセージに委ねた (Step 11 時点で working tree が既に clean だったため、Step 11 独自の commit を新設する代わりに次の commit で要件を満たした)。Implementation Steps 自体の内容・順序に変更はない。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1-3 (verify-executor.md / verify-classifier.md / skills/issue/SKILL.md への追記) をそのまま逐語的に実装した。Spec 本文が挿入位置・見出し・全文をあらかじめ確定していたため、実装判断の余地はほぼなかった
- Pre-merge AC 8 件はすべて実装内容と grep/rubric で PASS 確認済み。うち rubric 型 4 件 (AC2/AC4/AC7/AC8) は実装者自身の判定で PASS とし、Issue チェックボックスを更新した

### Deferred Items
- None

### Notes for Next Phase
- `/verify` は Post-merge AC (`verify-type: observation event=pr-review-full session=next`) の評価を担当する。次回 rubric 型 AC を含む Issue で `/review`/`/verify` が実際にファイル明示ガイドラインを活用できるかは、当面 SKIPPED のまま観測を継続する
- Issue #1251 は patch route (BASE_BRANCH=main) のため、closes #1251 は Step 12 の retrospective commit に含めて main へ push する。auto-close のタイミングは Deviations from Design を参照

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Pre-merge AC 8 件がいずれも「規約テキストが追加されたこと」を検証する形 (grep 4 件 + rubric 4 件) で、規約が**実際に機能するか**は post-merge の observation 1 件に集約されている。規約追加系 Issue の典型的な構造

#### spec
- Implementation Steps が挿入位置・見出し・全文をあらかじめ確定していたため、code フェーズに実装判断の余地がほぼなかった。Size は M → S へ下方修正され patch route へ再計画された (Step 3a Post-Spec Size Refresh) — 本セッションで 4 例目の Size 再評価、かつ初の**下方**修正
- 逐語的な Spec は rework ゼロを実現した一方、`/code` が独自の判断を挟む余地もないため、Spec 段階の誤りがそのまま着地するリスクと表裏

#### code
- Implementation Steps 1-3 を Spec 指示どおり 3 commit に分割した結果、`/code` Step 11 が定義する「単一の実装 commit に `(closes #N)` を含める」形にならず、closes 参照が Step 12 の retrospective commit に委ねられた。Step 11 時点で working tree が clean だったため空 commit を新設せず次 commit で要件を満たす判断で、実害なし
- rework ゼロ、逸脱は上記 commit 分割のみ

#### review
- patch route のため `/review` フェーズなし

#### merge
- patch route のため `/merge` フェーズなし。main 直コミット、コンフリクトなし

#### verify
- pre-merge 8 件は code フェーズで検証済みのため SKIPPED、observation 1 件は `event=pr-review-full` 未発火のため SKIPPED。FAIL / UNCERTAIN ゼロ
- **本 Issue が追加した規約は、本セッション内で実測 2 回機能した** (条件 9 が問う内容とは別側面のため PASS 判定には使えない):
  - #1283 AC2 — `grep -rl '^type: ' docs/ja/` が fenced code block 内サンプルを frontmatter と誤検出し恒久 FAIL になる構成を triage が捕捉、`awk` ベースへ置換
  - #1292 AC3 — rubric が記録先を「Spec または Issue コメント」としていたが、`modules/verify-executor.md` が定める grader 入力スコープ (Issue 本文・git diff・rubric text で明示的に名指ししたファイル) にはどちらも含まれず恒久 UNCERTAIN/FAIL になる構成を triage が捕捉。`docs/reports/bats-negation-assertion-audit.md` を明示参照する形へ修正。**本 Issue が追加した「一次証拠が git diff / Issue 本文の外にある場合は rubric text で当該ファイルを明示的に名指しする」規約がそのまま適用されたケース**

### Improvement Proposals

- **[Tier 1 / 起票] `pr-review-full` / `pr-review-light` は `KNOWN_EVENTS` に登録されているが発火経路が存在せず、指定した observation AC が永久 SKIPPED になる** — 本 Issue の条件 9 を評価する過程で実測確認した。`scripts/observation-trigger.sh:163` の `KNOWN_EVENTS="pr-review-full pr-review-light auto-run watchdog-kill fix-cycle"` は 5 種を認めているが、`observation-trigger.sh` を実際に呼ぶ箇所は 3 つしかなく、発火するのは 3 種のみ:

  | 呼び出し元 | 発火する event |
  |---|---|
  | `scripts/claude-watchdog.sh:140` | `watchdog-kill` |
  | `skills/verify/SKILL.md:625` | `fix-cycle` |
  | `skills/auto/SKILL.md:751` | `auto-run` |

  `pr-review-full` / `pr-review-light` を発火させる呼び出しは `scripts/` `skills/` `modules/` のいずれにも存在しない (`grep -rn "observation-trigger.sh" scripts/ skills/ modules/` で確認)。想定される発火元は `/review` フェーズだが、`skills/review/SKILL.md` に該当する呼び出しがない。

  影響範囲は本 Issue 単独ではなく、**当該 2 イベントを observation AC に指定している Issue が計 11 件**存在する (#1293 #1251 #1233 #1010 #1000 #930 #794 #713 #583 #575 #555)。いずれも `/verify` を何度再実行しても「waiting for event」の SKIPPED から動かず、`phase/verify` に滞留し続ける。`modules/verify-classifier.md` が本 Issue で追加した「どの event が発火したとき何を根拠に PASS 判定できるかを条件文に書く」規約は、**event 名に対応する発火実装の存在確認**までは求めていないため、この欠陥を検出できない。
