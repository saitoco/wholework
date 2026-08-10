# Issue #1334: auto: --until モードの Round 境界に triage を挟み Theme label 未達 (chicken-and-egg) を解消

## Overview

`/auto --batch --until <query>` の Round ループに、新規 issue を triage する挿入ステップを追加する。Until mode のクエリ再解決 (`resolve-batch-query.sh`) は `theme/*` label の glob match のみで、triage の副作用を一切持たないため、ラウンド処理中 (verify phase) に起票された retrospective issue はまだ `theme/*` label を持たず、次ラウンドの `label:theme/xxx` クエリにヒットしない (chicken-and-egg 問題)。Round ループの既存 Step 2 (ROUND インクリメント) と Step 3 (`resolve-batch-query.sh` 呼び出し) の間に bulk `/triage` (Proposal Option A — 詳細は Notes 参照) を挿入し、この問題を `--until` モード単体で解消する。ループ開始前から存在する未 triage issue にも Round 1 から効かせるため、セッション中に起票された分だけに限定しない。

## Changed Files

- `skills/auto/SKILL.md`: `### Until mode (--batch --until <query>)` セクションの Round ループに新規 triage 挿入ステップを追加し、後続ステップを再番号付け (bash compat: n/a — Markdown skill file)
- `tests/auto-batch.bats`: Until mode セクション向けの構造テストを 2 件追加。既存ファイルと同じ awk 抽出パターンを再利用 (bash compat: bats 1.13.0 で動作確認済み)
- `docs/workflow.md`: `--batch --until <query>` の説明段落に新規 triage 挿入ステップの記述を追加 (Steering Docs sync candidate — 本 Issue で直接対応)
- `docs/ja/workflow.md`: 上記の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に準拠)

## Implementation Steps

1. `skills/auto/SKILL.md` の `### Until mode (--batch --until <query>)` セクションで、既存の番号付きステップ 1〜7 を以下の全文に置き換える (→ 受入条件 AC1, AC2)。

   挿入位置: 既存の step 2 (`Increment \`ROUND\` by 1. ...`) の直後、既存の step 3 (`resolve-batch-query.sh` 呼び出し) の直前に新しい step 3 を挿入し、既存の step 3〜7 をそれぞれ 4〜8 に繰り下げる。既存ステップ本文中の "go to step 7" は "go to step 8" に、step 1 内の "step 5's delegation" は "step 6's delegation" に、それぞれステップ番号の繰り下げに合わせて更新する。("List mode step 7" — List mode 自身の内部ステップ番号への参照 — および新 step 6 内の "steps 1–7 unchanged" — List mode 自身の内部ステップ範囲への参照 — はいずれも Until mode 側のステップ番号ではないため変更しない。)

   置き換え後の全文 (1〜8、そのままコピーして良い):

   ````markdown
   1. Generate `BATCH_ID="${PPID}-$(date +%s)"`. Initialize `ROUND=0`, `PROCESSED=""`, `COMPLETED=""`, `FAILED=""`, `ALL_TARGETS=""`. Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section; retain `AUTO_STOP_AT` for step 6's delegation to List mode step 7's verify orchestration gate below — List mode's own "Load stop-at setting (List mode only)" block sits outside its numbered steps 1–7, so step 6's "steps 1–7 unchanged" reuse does not cover it on its own.
   2. Increment `ROUND` by 1. If `ROUND > MAX_ROUNDS`: output "Until mode: max-rounds ($MAX_ROUNDS) reached; stopping." and go to step 8.
   3. Run `Skill(skill="wholework:triage")` (bulk `/triage`, no Issue number) to triage any Issues in the project that are still missing metadata (Type/Size/Priority/theme). Run this unconditionally every round, including round 1 — this is what lets the loop pick up Issues that were already untriaged before it started, not only ones created mid-session. Bulk `/triage`'s own Bulk Execution flow assigns `theme/*` labels as part of its normal metadata pass (same judgment as single-Issue Step 6a), so any Issue newly labeled here becomes visible to step 4's query resolution on this same round.

      **Adopted approach**: bulk `/triage` (Proposal option A) is adopted over scoped `/triage $N` (option B). Option B would only reach Issues created by this session's own `retro-proposals` step — it has no visibility into Issues that were already untriaged before the loop started, which this step must also cover from round 1 onward. Reaching those pre-existing Issues under option B would require re-deriving the same project-wide untriaged scan bulk `/triage` already performs, without the plumbing cost option B was chosen to avoid (surfacing created-Issue numbers out of List mode's `wholework:verify` retro-proposals dispatch, a step reused verbatim by Count/List/Resume modes). Option A's acknowledged trade-off — it also triages backlog Issues unrelated to this `--until` session — is accepted: the 2026-08-10 measurement that motivated this Issue found the call near-zero-cost whenever there is nothing left to triage, the common case once a project's backlog is caught up.
   4. Run:
      ```
      ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh --query "$UNTIL_QUERY" --exclude "$PROCESSED"
      ```
      - Exit 1 (parse error — the query itself is malformed): abort Until mode entirely (no `delete_batch` call needed if `write_batch` was never reached — see step 6).
      - Exit 2 (`gh` failure): if `ROUND == 1`, abort Until mode; if `ROUND >= 2`, output a warning and treat as converged (go to step 8).
   5. If the output is empty: output "Until mode: query returned 0 issues at round $ROUND; converged." and go to step 8.
   6. Record the output as `ROUND_LIST`. Run:
      ```
      ${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_batch "$BATCH_ID" "$ROUND_LIST" "$COMPLETED" "$FAILED"
      ```
      (this call also serves as List mode's own checkpoint initialization — do not call `write_batch` a second time). Add each number in `ROUND_LIST` to `ALL_TARGETS` if not already present (set union — an Issue skipped by the blocked-by gate can legitimately reappear in a later round's `ROUND_LIST`; see below), then process each Issue in `ROUND_LIST` by applying `### List mode (--batch N1 N2 ...)` steps 1–7 unchanged (using the `AUTO_STOP_AT` retained in step 1 above). Whenever `update_batch ... complete` or `... fail` is called for an Issue number, add that number to `COMPLETED`/`FAILED` and to `PROCESSED`. An Issue skipped by the blocked-by gate (step 4 of List mode) is **not** added to `PROCESSED` — its blocker may clear within this same session, so it should be re-evaluated on the next round.
   7. If `CHECKIN_PER_ROUND` is `true`:
      - If ARGUMENTS does **not** contain `--non-interactive`: use AskUserQuestion to confirm proceeding to the next round; any answer other than "continue" goes to step 8.
      - Else (ARGUMENTS contains `--non-interactive`): output "Warning: --checkin-per-round ignored in non-interactive mode." and proceed without asking.

      In every case that did not go to step 8 above (including the default `CHECKIN_PER_ROUND=false` case, which asks nothing and always proceeds), go back to step 2.
   8. Run:
      ```
      ${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_batch "$BATCH_ID"
      ```
      Treat `BATCH_LIST` as `ALL_TARGETS` (the union of every round's targets) and proceed to `### Batch Completion Report` and everything after it (Batch Completion Report → observation scan → run-fact AC reconciliation → next-cycle handoff → L3 auto-retrospective) exactly as List mode does.
   ````

2. `tests/auto-batch.bats` に以下 2 件の `@test` を、既存の `@test "Until mode section: List mode reused for per-round Issue processing"` の直後・`@test "Until mode section is inserted between List mode and Resume mode"` の直前に追加する (after 1) (→ 受入条件 AC1, AC3):

   ```bash
   @test "Until mode section: triage insertion between step 2 and step 3" {
       run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -n 'wholework:triage\|resolve-batch-query.sh --query'"
       [ "$status" -eq 0 ]
       triage_line=$(echo "$output" | grep 'wholework:triage' | head -1 | cut -d: -f1)
       query_line=$(echo "$output" | grep 'resolve-batch-query.sh --query' | head -1 | cut -d: -f1)
       [ "$triage_line" -lt "$query_line" ]
   }

   @test "Until mode section: triage insertion adopted-approach rationale present" {
       run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'Adopted approach'"
       [ "$status" -eq 0 ]
   }
   ```

3. `docs/workflow.md` の `--batch --until <query>` の説明段落 (`**\`--batch --until <query>\`**: Condition-driven batch mode...` で始まる段落) 内、"Each round resolves the query via `scripts/resolve-batch-query.sh`" の直前に以下の一文を挿入する (parallel with 1, 2) (→ 受入条件 AC1, AC2):

   > Each round first runs bulk `/triage` (no Issue number) to triage any still-untriaged Issues project-wide — including ones that were already untriaged before the loop started, not only ones created mid-session — so that Issues newly assigned a `theme/*` label become visible to that round's query;

   `docs/ja/workflow.md` の対応段落 (`**\`--batch --until <query>\`**: 条件駆動のバッチモードです...`) にも、"各ラウンドで `scripts/resolve-batch-query.sh` によりクエリを解決し" の直前に、`docs/translation-workflow.md` の Sync Procedure に従い日本語で同内容を追加する:

   > 各ラウンドはまず bulk `/triage` (Issue 番号なし) を実行し、プロジェクト全体でまだ triage されていない Issue (セッション中に起票された分だけでなく、ループ開始前から未 triage だった分も含む) を triage します。これにより新たに `theme/*` label が付与された Issue がそのラウンドのクエリで拾えるようになります。そのうえで

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Until mode (--batch --until <query>) セクションで、Step 2 (ROUND インクリメント) と Step 3 (resolve-batch-query.sh 呼び出し) の間に、新規 issue を triage する挿入ステップが追加されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Until mode (--batch --until <query>)" "wholework:triage" --> Until mode の Round ループ (Step 2 と Step 3 の間) に triage 挿入ステップが実装されている
- <!-- verify: rubric "skills/auto/SKILL.md の Until mode セクション (または隣接する説明文) に、triage 挿入方式として bulk /triage と scoped /triage $N のどちらを採用したかが明記され、採用理由が記載されている" --> <!-- verify: grep "Adopted approach" "skills/auto/SKILL.md" --> 挿入方式 (A: bulk / B: scoped) のどちらを採用するかが明記され、採用理由が記録されている
- <!-- verify: rubric "skills/auto/SKILL.md の Until mode セクションの triage 挿入ステップの説明に、triage 実行後に theme label が付与され次ラウンドの label:theme/xxx クエリ再解決で正しく処理対象に入ることが明記されている" --> <!-- verify: grep "Until mode section: triage insertion between step 2 and step 3" "tests/auto-batch.bats" --> <!-- verify: command "bats tests/auto-batch.bats" --> ラウンド中 (ループ開始前から存在する未 triage issue を含む) に triage された issue が、triage 後に theme label を獲得し次ラウンドのクエリ解決で正しく処理対象に入ることを確認する構造テスト (`@test "Until mode section: triage insertion between step 2 and step 3"`) が `tests/auto-batch.bats` に追加され、全テストが pass する

### Post-merge

なし

## Notes

- **verify command の空撃ち検証記録**: Triage AC audit (2026-08-10T13:54:23Z Issue コメント) の提案をそのまま適用する前に、`/spec` で対象ファイルに対する空撃ち検証を全 3 件実施した。
  - AC1: audit 提案どおり heading 引数から `###` を除去しても、キーワードを裸の `"triage"` のままにすると `Until mode` セクション既存の地の文 ("per-Issue processing within a round reuses `### List mode (--batch N1 N2 ...)` verbatim (triage → size gate → blocked-by gate → ...)") に既に一致し、実装前から常時 PASS することを確認した。キーワードを本 Issue で新規導入する一意な文字列 `wholework:triage` に変更し、実装前は 0 件一致であることを確認済み。
  - AC2: audit 提案の `採用理由` (日本語) は `skills/auto/SKILL.md` 自体が英語主体のファイルであるため (既存の設計判断コメントは "no new subcommand and no seed file are introduced" のようにすべて英語)、意味を保ったまま英語キーワード `Adopted approach` に置き換えた。実装前にファイル全体で 0 件一致であることを確認済み。
  - AC3: audit 提案の `command "bats --filter 'Until mode section: triage insertion' tests/auto-batch.bats"` を実機 (Bats 1.13.0) で空撃ちしたところ、該当テスト 0 件でも `1..0` を出力して exit 0 (成功) を返すことを確認した。これは AC3 が本来検出しようとしていた「新規テストを追加しなくても常時 PASS する」問題を形を変えて再導入するため不採用とし、`grep "{新規テスト名}" tests/auto-batch.bats` (新規テスト文字列の存在確認。実装前は不一致) と `command "bats tests/auto-batch.bats"` (全テスト — 新規 2 件を含む計 22 件 — が pass することの確認) の 2 段構えに変更した。
- **Issue #953 との関係**: 本 Issue は #953 (`--until` モード本体) の post-merge 実運用検証から派生した追加改善。`scripts/resolve-batch-query.sh` 自体への変更はなく (純粋な label glob match のままでよい)、`skills/auto/SKILL.md` の Until mode セクションと関連ドキュメントのみが変更対象。
- **Option B (scoped `/triage $N`) を採用しない理由の補足**: Issue 本文の Proposal は Option B の課題を「`Skill(wholework:verify)` 呼び出し結果から起票 issue 番号を回収する経路の新設が必要」とのみ記述しているが、`/spec` の調査で追加の構造的制約を発見した — Option B は「セッション自身が起票した issue」のみを対象にするため、原理的に「ループ開始前から存在する未 triage issue」を Round 1 からカバーするという Issue の明示的要件を満たせない。この制約が Option A 採用の決定打であり、実装コストの多寡は副次的な理由にとどまる。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Issue Retrospective (`/issue` Existing Issue Refinement, 2026-08-10T13:48:28Z): AC を Pre-merge 3 件 (rubric + 機械的補助チェック) に再構成したこと、および Proposal の A/B 実装方式選択は `/issue` (What) と `/spec` (How) の責務境界に照らして `/spec` の判断事項として Issue 側で確定させなかったことを記録。本 Spec の Option A (bulk `/triage`) 採用判断はこの委譲を受けたもの。https://github.com/saitoco/wholework/issues/1334#issuecomment-5241168319
- login: saito / authorAssociation: MEMBER / trust tier: first-class — Triage AC audit (2026-08-10T13:54:23Z): Issue 本文の Pre-merge AC 3 件すべてに verify command の不具合を検出 (AC1: `section_contains` heading 引数の `###` 残存、AC2: `grep "bulk|scoped"` の無関係な既存一致、AC3: 既存テスト全 PASS 済みによる保証不足) し、次フェーズでの反映を依頼。本 Spec 作成時に Issue 本文を更新して反映した (詳細な空撃ち検証record は Notes 参照)。https://github.com/saitoco/wholework/issues/1334#issuecomment-5241233384

### code phase (cutoff: phase/ready 付与時刻 2026-08-10T14:19:09Z)

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 1〜3 に記載された全文置き換え・テスト追加・ドキュメント追記をそのまま実装した。ステップの並び替えや省略・統合は発生していない。

### Design Gaps/Ambiguities
- N/A — Spec の Notes に verify command の空撃ち検証記録が既に詳細に残されており、実装フェーズで新たに発見した設計上の曖昧さはなかった。

### Rework
- N/A — 実装は 1 パスで完了し、テスト失敗による手戻りは発生しなかった (`bats --jobs 18 tests/` 全 1690 件 PASS)。

## review retrospective

### Spec vs. implementation divergence patterns
- 乖離なし。review-light エージェントが Spec の Implementation Steps 1〜3 と PR diff (Until mode Step 3 の全文追加・`tests/auto-batch.bats` の新規テスト2件・`docs/workflow.md`/`docs/ja/workflow.md` の追記) を突き合わせ、いずれも Spec 記載どおりであることを確認した。再番号付けされたステップ間の内部参照 (新 step 6/8 など) にも古い番号への取り残しはなかった。

### Recurring issues
- 唯一の指摘 (SHOULD: `Skill(skill="wholework:triage")` 呼び出しの失敗処理未定義) は本 PR 単発の指摘であり、他 PR との明確な反復パターンはこの時点では確認していない。ただし新しい Skill/script 呼び出しを SKILL.md の自然言語手順に組み込む際、周辺ステップ (List mode step 2/3/5/7 等) と同型の失敗処理節を書き忘れやすい点は一般的な注意点として次回以降のレビューでも意識する価値がある。

### Acceptance criteria verification difficulty
- 困難なし。Pre-merge AC 3 件はいずれも `section_contains`/`grep`/`command` の機械的チェックで PASS 判定でき、UNCERTAIN はゼロだった。Issue 起票直後の Triage AC audit が事前に verify command の不具合 3 件を検出・修正していたため、review フェーズでの空撃ち確認は不要だった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- `REVIEW_DEPTH=light` (`--light` 明示指定、Size M とも整合) のため review-light エージェント1体による4観点統合レビューを採用し、review-spec/review-bug の2エージェント fan-out は行わなかった
- SHOULD 指摘 (`wholework:triage` dispatch の失敗処理欠如、`skills/auto/SKILL.md:1211`) は周辺ステップとの一貫性を重視しその場で修正した。CONSIDER 指摘 (`docs/workflow.md`/`docs/ja/workflow.md` の base branch との `git merge-tree` コンフリクト検出) はコード修正を要さない情報提供のためスキップした

### Deferred Items
- N/A — MUST issue なし。Pre-merge AC 3 件はすべて review フェーズでも PASS 再確認済み

### Notes for Next Phase
- `/merge` 時に `docs/workflow.md` / `docs/ja/workflow.md` で base branch (PR #1336 / Issue #1049) との `git merge-tree` コンフリクトが発生する見込み。本 PR の diff は隣接する別段落 (`--batch --until <query>`) のみを変更しており、いずれの側の内容も diff 内では失われていないことを review フェーズで確認済みなので、両側の追記を保持する形でリベース/コンフリクト解消すればよい
