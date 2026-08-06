# Issue #1185: issue: triaged 済み Issue で AC verify command 監査が実行されない構造を是正

## Consumed Comments

- saito (MEMBER, first-class): `/issue` の triage auto-chain 実行結果 (Issue Retrospective)。Type=Bug、Priority=unset、Size=M、Value=3、Auto-Resolved Ambiguity Points 2 件 (heading 引数の `#` 個数の例示修正、Post-merge AC への `session=next` 付与) を記録。いずれも Issue 本文に既に反映済みであり、本 Spec への追加要求は無し。https://github.com/saitoco/wholework/issues/1185#issuecomment-5200104534

## Overview

`skills/issue/SKILL.md` の Existing Issue Refinement フローでは、AC verify command 監査 (`skills/triage/skill-dev-verify-audit.md` の Pattern 表) が Step 2 (triage auto-chain, `triaged` 不在時のみ実行) 経由でしか呼ばれない。このため (a) `triaged` 済み Issue (実運用でのほぼ全件) では監査が一切実行されず、(b) `triaged` 不在で Step 2 が実行される場合も AC 分類 (Step 7) より前に監査が走るため、そのセッションで新規 authoring された verify command は監査対象にならない。New Issue Creation フローはこの問題を持たない (Step 4 の AC 分類の後に Step 8 の triage auto-chain が常時実行されるため)。

本 Issue は、`triaged` ラベルの有無に関わらず AC verify command 監査が実行されるようにし、両フローで「AC 分類 → 監査」の順序を統一する。方針選択の根拠は Notes を参照。

## Reproduction Steps

1. 既に `triaged` ラベルが付与済みの Issue を用意する (通常運用では `/triage` が早期に付与するため、ほぼ全ての既存 Issue が該当)。
2. その Issue に対して `/issue N` (Existing Issue Refinement) を実行し、Step 7 (Classify Acceptance Criteria and Assign Verify Commands) で `skill-dev-verify-audit.md` の Pattern 1〜6 のいずれかに該当する verify command (例: `section_contains` の heading 引数が `#` で始まる、Pattern 6 サブパターン 1) を新規 authoring させる。
3. Step 2 (Auto-chain to triage) は `triaged` が既に存在するためスキップされ、`skill-dev-verify-audit.md` の Pattern 表監査はセッション中一度も実行されない。Step 7 で authoring された欠陥 verify command について監査コメントは投稿されない。
4. 実測 (2026-08-06): #1141 がこの経路で再現した。`triaged` 済みだったため Step 2 の auto-chain がスキップされ、直前に #1083 が追加した Pattern 6 サブパターン 1 に到達しなかった (Issue 本文 Background 参照)。

## Root Cause

`skills/issue/SKILL.md` の Existing Issue Refinement は、AC verify command 監査を独立したステップとして持たず、`/triage` の「Type/Size/Priority/Value 割り当て」auto-chain (Step 2) に間借りする形でしか呼び出していない。この間借りが 2 つの独立した欠陥を生む:

1. **ゲーティング欠陥**: `triaged` が既に存在する場合 (実運用の大半)、Step 2 自体がスキップされるため、Step 7 が何を authoring しても Pattern 表監査に到達しない。
2. **順序欠陥**: `triaged` が不在で Step 2 が実行される場合も、Step 2 は Step 7 (AC 分類) より**前**に実行されるため、監査はリファイン前の Issue 本文を見ており、このセッションで Step 7 が authoring/変更する verify command を検査できない。

両欠陥とも、監査の唯一の入口が `/issue` 自身の AC authoring ステップに紐付いておらず、`/triage` 側の無関係な auto-chain に依存していることに起因する。New Issue Creation がこの欠陥を持たないのは、`docs/tech.md` の Forbidden Expressions が Issue 作成時点での `triaged` 付与を禁止しているため、New Issue Creation 自身の Step 8 (同種の auto-chain) が常に実行され、かつ常に Step 4 (AC 分類) の後に実行されるため。

## Changed Files

- `skills/issue/SKILL.md`: Existing Issue Refinement に無条件の新設 "Step 15: AC Verify Command Integrity Audit" を追加 (Step 14 の後、`## Label Transition on Close` 直前の `---` の前)。New Issue Creation の Step 8 に順序保証を明記する注記を追加
- `skills/triage/skill-dev-verify-audit.md`: 冒頭の "Used in:" 行に `/issue` Existing Issue Refinement Step 15 の呼び出し元を追加 (同じ行にある既存の "substep 8" → "substep 7" の off-by-one も修正)。Pattern 4 の "Detection approach" に `/issue` Step 15 向けの Size/`ALWAYS_PR` 取得元を追加する 3 番目の箇条書きを追加 (同じ off-by-one をここでも修正)
- `tests/issue.bats`: Existing Issue Refinement の新設監査ステップが存在し、`triaged` に依存しない無条件実行であることを確認するテストを追加
- `docs/environment-adaptation.md` / `docs/ja/environment-adaptation.md`: [Steering Docs sync candidate] 確認済み — 変更不要 (根拠は Notes 参照)

## Implementation Steps

1. `skills/issue/SKILL.md` の Existing Issue Refinement フローで、現行 "Step 14: Opportunistic Verification" の内容の直後、`## Label Transition on Close` 直前の `---` の前に、以下の新規ステップを挿入する (→ acceptance criteria AC1, AC2):

   ```
   ### Step 15: AC Verify Command Integrity Audit

   Read `${CLAUDE_PLUGIN_ROOT}/skills/triage/skill-dev-verify-audit.md` for the verify command audit patterns and follow the "Processing Steps" section, applied to the Issue body as finalized by Step 9 (and by Step 12's redistribution, if sub-issue splitting occurred). Run this step unconditionally — regardless of whether the `triaged` label is present or absent. This closes the audit gap left by Step 2, which only runs when `triaged` is absent and, even then, only sees pre-refinement ACs (before this flow's own Step 7 authors the final ones).

   Skip this step if the Issue body contains no `<!-- verify: ... -->` patterns.

   **Pattern 4 Size/`ALWAYS_PR` sourcing in this context**: read Size with `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER` (same call as Step 6); `ALWAYS_PR` is retained from Step 4.

   Note: if Step 2's triage auto-chain already ran in this same session (`triaged` was absent at the start), its own Step 7 already audited the Issue body's pre-refinement ACs — this step's pass is independent and may post a second comment. The overlap is expected and non-blocking; the audit is non-destructive (comment-only).
   ```

2. (after 1) 同ファイルの New Issue Creation フローで、"Step 8: Triage Auto-chain (if `triaged` label is absent)" の既存文末 ("If `triaged` is present: skip this step.") の直後に、以下の注記を追加する (→ acceptance criteria AC2):

   ```
   Note: `triaged` is always absent at this point — `docs/tech.md` Forbidden Expressions prohibits assigning `triaged` at Issue creation time (Step 6 above never sets it), so this chain always executes for a freshly created Issue. This keeps the AC classification (Step 4) → audit (triage's own Step 7, run inside this chain after its Step 6 Size determination) ordering consistent with Existing Issue Refinement's unconditional Step 15 audit.
   ```

3. (parallel with 1, 2) `skills/triage/skill-dev-verify-audit.md` を編集する (→ acceptance criteria AC1, AC2):
   - 冒頭の `Used in: Step 7 (Single Issue Execution) and Bulk Execution Step 3 substep 8.` を `Used in: Step 7 (Single Issue Execution), Bulk Execution Step 3 substep 7, and \`/issue\` Existing Issue Refinement Step 15 (regardless of \`triaged\` label state).` に変更する (substep 8→7 の off-by-one 修正を含む — `skills/triage/SKILL.md` の Bulk Execution Step 3 の実際の番号付けで確認済み)
   - Pattern 4 の "Detection approach" 箇条書き (現行 2 項目: Single Issue Execution / Bulk Execution) に 3 番目の項目を追加する: `In \`/issue\` Existing Issue Refinement (Step 15): read Size via \`get-issue-size.sh $NUMBER\` (same call as \`/issue\`'s own Step 6); \`ALWAYS_PR\` is retained from \`/issue\`'s Step 4 (Reference Steering Documents).` — 併せて既存の "Bulk Execution (Step 3 substep 8)" を "substep 7" に修正する

4. (after 1) `tests/issue.bats` に以下のテストを追加する (→ acceptance criteria AC3):

   ```bash
   @test "issue skill Existing Issue Refinement runs AC verify command audit regardless of triaged" {
       grep -q 'AC Verify Command Integrity Audit' "$PROJECT_ROOT/skills/issue/SKILL.md"
       grep -q 'skill-dev-verify-audit.md' "$PROJECT_ROOT/skills/issue/SKILL.md"
       grep -q 'regardless of whether the .triaged. label is present or absent' "$PROJECT_ROOT/skills/issue/SKILL.md"
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "triaged ラベル済みの Issue に対して /issue N を実行した場合でも AC verify command 監査 (skills/triage/skill-dev-verify-audit.md の Pattern 表) が実行される旨が skills/issue/SKILL.md に記述されている。方針 3 (現状維持) を採る場合は、AC 監査が /triage の責務である旨と /issue 側では実行されない旨が明記されていること" --> `triaged` 済み Issue での監査実行 (または責務分離) が記述されている
- <!-- verify: rubric "New Issue Creation と Existing Issue Refinement の両フローについて、AC 分類 (verify command の authoring) と Pattern 表監査の実行順序が skills/issue/SKILL.md 内で一貫している (どちらも AC 分類の後に監査が走る、または方針 3 の場合は両フローとも /issue では監査しない旨が明記されている)" --> 両フローの実行順序が一貫している
- <!-- verify: command "bats tests/issue.bats" --> `tests/issue.bats` が PASS する

### Post-merge

- `triaged` ラベル済みかつ `section_contains`/`section_not_contains` の heading 引数の先頭に `#` (`#`/`##`/`###` 等) を含む AC を持つ Issue を `/issue N` に通し、Pattern 6 サブパターン 1 が指摘されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

**方針選択の根拠 (Issue 本文「対応方針の候補」より)**: 候補 1 (Existing Issue Refinement に独立監査ステップを配置) と候補 2 (両フローの順序統一) のハイブリッドを採用した。New Issue Creation は現状でも「Step 4 (AC 分類) → Step 8 (triage auto-chain、`triaged` が常時不在のため常時実行され、その内部の Step 6 Size 決定の後に Step 7 監査が走る)」の順序が既に成立しているため機能変更は不要と判断し、Step 8 にその順序保証を明記する注記のみを追加した。候補 2 が求める「一貫性」を、両フローを同一の Step 構造にする形ではなく、各フローの文脈でそれぞれ順序を保証する形で達成している。候補 3 (`/issue` 側は監査しないと明記するのみ) は不採用とした — 本 Issue は Bug 種別であり、#1141 で Existing Issue Refinement 経路において AC 監査が実際に機能しなかった実例が確認されているため、ドキュメントのみの対応では実害を解消できない。

**新設ステップの配置**: Existing Issue Refinement の Step 9 (Update Issue Body) 直後ではなく、Step 14 (Opportunistic Verification) の後 (新設 Step 15) に配置した。Step 10〜14 の間に挿入すると、内部の Step 12a/12b/12c 相互参照、および `docs/workflow.md`/`docs/ja/workflow.md` の「`/issue N` (existing issue refinement) | Step 10 calls `gh-check-blocking.sh $NUMBER`」という参照 (実際は Step 11 であり、本 Issue と無関係に既に off-by-one — 下記参照) への波及リナンバリングを招く。末尾配置によりこれらへの波及を完全に回避した。加えて、Step 12 (Scope Assessment、非対話モードでは常時スキップ) が sub-issue 分割で AC を再配分した後の、親 Issue に最終的に残る AC を監査対象にできる点でも末尾配置がより正確。

**#1156 の Spec Retrospective との関係**: `docs/spec/issue-1156-post-merge-checkbox-format.md` の Spec Retrospective は、「独立スクリプト + `/issue` Step 4 への直接組み込み」パターンが結果的に本 Issue (#1185) の影響を回避したと記録している。本 Issue でも同種のパターン (`/issue` 内への直接組み込み・`triaged` 非依存) を検討したが、`skill-dev-verify-audit.md` の Pattern 4 (patch route × `gh pr checks` 不整合) は Size に依存しており、New Issue Creation の Step 4 時点では Size が未確定 (Step 3 Ambiguity Detection で「Size なし」と明記) であるため、Step 4 への直接組み込みは New Issue Creation 側で Pattern 4 を機能させられない。この非対称性を避けるため、既存の `skill-dev-verify-audit.md` を Existing Issue Refinement 専用の独立ステップ (Size 確定後) から呼び出す形を採用した。

**許容したトレードオフ**: `triaged` が不在の状態で `/issue N` を実行した場合、Step 2 の triage auto-chain (リファイン前の AC を監査) と新設 Step 15 (最終 AC を監査) の 2 回、監査が走ることになる。監査は非破壊的 (コメント投稿のみ) なため実害はないが、重複したコメントが投稿され得る。SPEC_DEPTH=light の簡潔性を優先し、抑制ロジックは追加しなかった。

**Opportunistic fix**: `skill-dev-verify-audit.md` の「Bulk Execution Step 3 substep 8」表記 (実際は substep 7) を、同一行を編集するついでに 2 箇所とも修正した。この off-by-one は `docs/spec/issue-1061-honor-always-pr-in-route.md` の Spec Retrospective で既に指摘され、当時はスコープ外として記録されていたもの。

**Out of scope として残した既存 drift**: `docs/workflow.md`/`docs/ja/workflow.md` の「`/issue N` (existing issue refinement) | Step 10 calls `gh-check-blocking.sh $NUMBER`」は実際には Step 11 であり、本 Issue の変更前から存在する不整合。本 Issue の変更対象ファイルではないため修正しなかった (今回のリナンバリング回避方針により、本 Issue によってこの不整合が悪化することもない)。

**Issue body factual claim 検証**: Background の記述 (New Issue Creation は機能する、Existing Issue Refinement は `triaged` の有無に関わらず機能しない/順序が逆転する) はいずれも `skills/issue/SKILL.md` の現況と照合し、一致を確認した。矛盾なし。

**Steering Docs sync candidate 判定根拠**: `docs/environment-adaptation.md` / `docs/ja/environment-adaptation.md` の Domain Files 表にある `skill-dev-verify-audit.md` の行の「Skill」列は、`domain-loader` モジュールがバンドル Domain file を `${CLAUDE_PLUGIN_ROOT}/skills/{SKILL_NAME}/*.md` の Glob で発見する仕組み上のディレクトリ所有権 (`skills/triage/`) を表しており、個々の呼び出し元を網羅列挙するものではない (実際、`/triage` の SKILL.md 自身は `domain-loader.md` を読んでいないため、このバンドル機構は現状 unused — `docs/spec/issue-749-domain-frontmatter-fix.md` Notes 参照)。`/issue` からの新規参照は既存の「Read X and follow Y section」形式の手動参照であり (`/triage` の Bulk Execution Step 3 substep 7 も同形式)、動的ロード機構やこの表の分類ロジックに影響しないため、変更不要と判断した。

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (Step 3)**: `/code 1185` 実行時点のラベルは `triaged`, `phase/code`, `retro/verify` のみで `phase/ready` が不在だった。`reconcile-phase-state.sh code-pr 1185 --check-precondition` も `matches_expected: false` (診断: "does not have phase/ready label") を返した。ただし Spec (本ファイル) は既に存在し内容も完成しており、Issue タイムラインから `phase/ready` → `phase/code` の遷移が本セッション開始前 (2026-08-06T04:02:40Z) に既に発生していたことを確認した。ブランチ・PR は未作成だったため、Step 4 (ラベル遷移) のみ完了し Step 5 以降が未実施のまま中断されたセッションの再開と判断し、非対話モードの auto-resolve として Spec に基づき実装を続行した。

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜4 を Spec の記述通りに適用した。追加の Steering Docs sync 判断も Spec Notes の既存結論と一致した。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Pre-merge AC gate (`check-pre-merge-ac.sh`) は3件全てチェック済みと判定し、review-incomplete-fallback チェックも `matches_expected: true` (organic Review Response Summary) だったため、ゲート通過は無条件で成立した。
- mergeable=true (clean, CI success 9/9, review approved) を確認し、conflict resolution (Step 3) をスキップして直接 squash merge を実行した。

### Deferred Items

- Post-merge observation AC (`triaged` 済み Issue で Pattern 6 サブパターン 1 が指摘されることの観察、`session=next`) は次回セッションの `/issue N` 実行時に評価する (review phase から引き継ぎ、未着手のまま)。
- `docs/workflow.md` / `docs/ja/workflow.md` の Step 10/11 off-by-one drift はスコープ外として据え置いた (review phase から引き継ぎ)。

### Notes for Next Phase

- `/verify` は post-merge observation AC を次回セッションで評価する際、`skills/triage/skill-dev-verify-audit.md` Pattern 6 サブパターン 1 の指摘コメントが実際に投稿されるかを確認すること。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — Spec の Implementation Steps 1〜4 と PR diff は完全に一致していた。Code Retrospective が記録した追加判断 (`phase/ready` 不在時の auto-resolve) もレビュー観点からは実装内容に影響しなかった。

### Recurring issues

Nothing to note — review-light の4観点 (spec deviation / edge cases / security / documentation consistency) のうち、指摘は documentation consistency の1件 (SHOULD) のみで、他セッションと共通する繰り返しパターンは見られなかった。

### Acceptance criteria verification difficulty

Nothing to note — 3件のPre-merge AC (rubric ×2, command ×1) はいずれも決定的に PASS 判定でき、UNCERTAIN はゼロだった。rubric AC の判定根拠は `skills/issue/SKILL.md` の実際の Step 番号列挙 (`grep -n "^### Step"`) で直接検証でき、verify command 自体の記述精度に問題はなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- Issue 本文の Background が New Issue Creation / Existing Issue Refinement の実行順序の非対称性を表形式で明示していたため、`/spec` の方針選択 (候補 1 + 候補 2 のハイブリッド) が迷いなく決まった。#1083 の Spec Notes が同じ非対称性を先に記録し「Size S の #1083 単独では扱わない」とスコープ外に置いていたことが、本 Issue の起票根拠としてそのまま機能した。
- `/triage 1185` の実行時に **#1083 が追加した Pattern 6 が実運用で初発火**し、post-merge AC の 2 つの欠陥 (heading 引数の例示が `###` 限定になっていた点、`session=next` 修飾子の欠落) を検出・修正した。監査**基準**を扱う #1083 が、その**参照経路**を扱う本 Issue 自身の AC 品質を引き上げた形になっている。

#### spec

- 新設ステップを末尾 (Step 15) に配置する判断により、Step 10〜14 のリナンバリングと `docs/workflow.md` / `docs/ja/workflow.md` への波及を完全に回避した。Spec Notes 「新設ステップの配置」がこの根拠を明示していたため、code phase で配置の再検討が発生しなかった。
- Spec が `docs/workflow.md` の既存 off-by-one (「Step 10 calls `gh-check-blocking.sh`」— 実際は Step 11) を "Out of scope として残した既存 drift" と明記していたため、review phase で documentation consistency の SHOULD 指摘が出た際にスコープ判断が即座にできた。

#### code

- `phase/ready` ラベル不在での auto-resolve が発生した (Autonomous Auto-Resolve Log に記録)。Spec が完成済みで、タイムライン上 `phase/ready` → `phase/code` の遷移が本セッション開始前 (2026-08-06T04:02:40Z) に確認できたため、中断セッションの再開と判断して続行した。判断根拠が Spec に残っているため verify 側での再検証が容易だった。
- Opportunistic fix として `skill-dev-verify-audit.md` の「Bulk Execution Step 3 substep 8」→「substep 7」の off-by-one を 2 箇所修正した。この off-by-one は `docs/spec/issue-1061-honor-always-pr-in-route.md` の Spec Retrospective で既に指摘されスコープ外に置かれていたもので、同一行を編集する機会に解消された。

#### review

- review-light 4 観点のうち指摘は documentation consistency 1 件 (SHOULD) のみ。Pre-merge AC 3 件は全て決定的に判定でき UNCERTAIN ゼロだった。

#### merge

- pre-merge AC gate は無条件通過した (Pre-merge AC 3 件が全てチェック済み、review-incomplete-fallback チェックも `matches_expected: true`)。同日の `/auto --batch 1179 1181 1180` で 3 件中 2 件 (#1181 / #1180) が gate でブロックされ手動介入を要したのと対照的で、**#1083 の Pattern 6 追加後に authoring された AC が初めて gate をブロックせずに通った実測**となる。
- ただし本 Issue の AC を実際に監査したのは `/triage` の Single Issue Execution Step 7 経路であり、本 Issue が是正した `/issue` Existing Issue Refinement 経路の監査 (新設 Step 15) はまだ一度も動いていない。Step 15 の実効性は post-merge observation AC (`event=auto-run session=next`) の評価を待つ。

#### verify

- code phase で Tier 2 recovery (`json-mode-silent-hang`) が 1 回発火し、`run-code.sh --pr` の自動 retry で復旧した (watchdog が json mode で 1140 秒沈黙 → 非ゼロ終了 → Tier 2 catalog が retry → 実装完了・PR #1193 作成)。人手介入はゼロ。#1180 で「発火実績あり」として catalog に残した 2 パターンのうち 1 つが実運用で機能した実測にあたる。
- **`## Auto Retrospective` セクションが本 Spec に存在しない**: #1181 で `_write_tier2_recovery_to_spec()` が削除されたため、Tier 2 recovery が発生しても Spec には記録されず、記録先は `.tmp/auto-events.jsonl` の `recovery` イベント (`tier=2 result=recovered`) のみとなった。一方 `skills/verify/SKILL.md` Step 12 step 3 の skip 判定ルールは「Tier 2/3/Manual recovery が `## Auto Retrospective` に記録されていなければ notable content」と規定しており、#1181 の記録先変更に追随していない。結果として **Tier 2 recovery が起きる度に verify retrospective の skip が構造的に不可能になる** — #1179 / #1181 が目指した「retrospective の発散抑止」と逆方向に働く。
- post-merge observation AC は `auto-run` イベント未発火のため SKIPPED。`session=next` 修飾子により、Step 15 が main に着地した後に開始される新規セッションでの `/issue N` 実行が評価の前提となる。本セッションでは構造的に評価できない (SKILL.md Step 8c の `session=next` 規定どおり UNCERTAIN ではなく SKIPPED として扱った)。

### Improvement Proposals

- `skills/verify/SKILL.md` Step 12 step 3 の Tier 2/3/Manual recovery skip 判定を、#1181 の記録先変更に追随させる。現行ルールは Spec の `## Auto Retrospective` を参照先としているが、#1181 以降 Tier 2 recovery はそこに書かれない。参照先を `.tmp/auto-events.jsonl` の `recovery` イベント (または `docs/reports/orchestration-recoveries.md`) に切り替えるか、「自動復旧して人手介入がなかった Tier 2 は notable content に数えない」と明示するかのいずれかで整合を取る。
