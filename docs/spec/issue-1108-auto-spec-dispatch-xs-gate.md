# Issue #1108: auto: run-auto-sub.sh の spec dispatch を Size 判定込みで /auto Step 3 と一致させる

## Overview

`scripts/run-auto-sub.sh`(`/auto` の batch List/Count mode と XL sub-issue 実行が使う spec フェーズ dispatch)は `phase/*` ラベルだけで spec 実行要否を判定しており、Size を見ていない。そのため単一 Issue 経路 (`skills/auto/SKILL.md` Step 3) が既に守っている「Size=XS は spec 不要」というルールが、batch/XL 経路では `phase/issue`(`phase/ready` 無し)状態の XS Issue に対して破られる。

これに加えて `/issue` の Completion Report が最終的な `phase/issue` / `phase/ready` ラベルを決める `get-issue-size.sh` 呼び出しがキャッシュ付き(`--no-cache` 無し)であり、triage 直後の陳腐化した空応答を読む可能性がある — 同じ Size=XS の Issue でも実行タイミング次第でラベルが割れる非決定性の実測(#1054 / #1052)と符合する。

本 Spec は Issue 本文の対応方針(案 A/B/C)のうち **案 A** を採用する: 規定(Step 3)を正とし、`run-auto-sub.sh` 側に Size 判定を追加して整合させる。理由は Notes を参照。

## Reproduction Steps

1. `/issue` で Issue を Size=XS まで triage する(非対話)。結果として `phase/issue`(`phase/ready` 無し)または `phase/ready` のいずれかで完了する(両方が実際に観測されている — Root Cause 参照)
2. `/auto --batch N1 N2 ...`(List mode)、または XL 親の sub-issue として、`scripts/run-auto-sub.sh` 経由でこの Issue を処理する
3. ラベル状態が `phase/issue`(`phase/ready` 無し)の場合: `run-auto-sub.sh` は Size=XS にもかかわらず `run-spec.sh $NUMBER` を dispatch する — `skills/auto/SKILL.md` Step 3 の単一 Issue 経路ルール(「Size is XS: Spec not needed — skip spec」)と矛盾する
   - 実例: Issue #1054 (Size=XS、`phase/issue` で完了) — `docs/spec/issue-1054-verify-absence-reference-point.md` が commit `7ebce2dd` で作成され、直後に code フェーズの commit `14765f99 ... (closes #1054)` が続いた
4. 同一 batch (`/auto --batch 1051 1066 1054 1052 1053 1050`) 内で連続処理した 2 件の Size=XS Issue で、`/issue` 完了後のラベルが割れていた: #1054 → `phase/issue`(spec dispatch: 実行される)、#1052 → `phase/ready`(spec dispatch: スキップされる)。同じ Size、同じ batch、同じ Completion Report ロジックであるにもかかわらず結果が異なった

## Root Cause

**Bug 1 — `run-auto-sub.sh` の spec dispatch が Size を見ていない:**

`scripts/run-auto-sub.sh`(L827-844)の spec フェーズ dispatch 条件はラベルのみで分岐する:

```
if <phase/code|review|merge|verify|done 存在>: skip (spec 完了以降)
elif <phase/ready 不在>: run-spec.sh を実行
```

この時点で既に取得済みの `$SIZE` を一切参照しないため、`phase/issue`(`phase/ready` 無し)状態の Issue は Size に関わらず spec が dispatch される。`skills/auto/SKILL.md` Step 3(単一 Issue 経路、本 Issue の Purpose が「一致させる」対象としている規定)は Size=XS で spec を明示的にスキップする。さらに同ファイル Step 4 の XL 経路説明文自体が「`run-auto-sub.sh` checks each sub-issue's `phase/ready` and auto-runs spec if not set」と、この Size 非考慮の挙動をあたかも意図した設計であるかのように記述しており、同一ファイル内で Step 3 と自己矛盾している。

この結果、Step 4b の前提(「The XS patch route does not go through the `/spec` phase, so no Spec file exists」)が batch/XL 経路の XS Issue に対して破られる。実際には Step 4b 自身の冪等性チェック(`## Issue Retrospective` 見出しが既存 Spec にあれば転記をスキップ)により #1054 で二重転記は避けられたが、XS には過剰なフル設計コンテンツ(Implementation Steps・Changed Files 等)を含む Spec が余分に作成された(Issue の Impact 2「不要な実行コスト」)。

**Bug 2 — `/issue` の Completion Report が陳腐化しうるキャッシュ付き Size 読み取りを行う:**

`skills/issue/SKILL.md` の `## Completion Report`(New Issue Creation・Existing Issue Refinement 両フロー共有)は次の手順で最終ラベルを決める:

```
get Size with `get-issue-size.sh $NUMBER`.
For XS issues only: transition to `phase/ready`.
```

この呼び出しは `--no-cache` を付けていない。`scripts/get-issue-size.sh` 自身のヘッダコメントは `--no-cache` を「use immediately after triage for freshness」(`scripts/get-issue-size.sh:9`)と明記しており、このリポジトリの他の「Size を書き込み直後に読む」箇所は例外なくこの作法に従っている: `modules/project-field-update.md` の Verify-after-write 手順(`/triage` 自身の Size 書き込み確認、L51/62/71/80)、`skills/auto/SKILL.md` Step 3a の Post-Spec Size Refresh(L278)、`scripts/run-auto-sub.sh` 自身の初回 Size 取得(L823)は、いずれも `--no-cache` を使う。

Completion Report は同一セッション内で Step 2 / Step 8 の triage auto-chain が GraphQL mutation で Size を設定した直後に走る。`gh-graphql.sh` の応答キャッシュ(`--cache`、TTL 300秒、issue 番号を含むクエリ単位のキー)が triage 前の(空の)応答を保持していれば、Completion Report の読み取りはその陳腐化した応答をそのまま返し、「For XS issues only」の Size 判定が一致せず `phase/ready` への遷移が黙って no-op になる — Issue は `phase/issue` に留まる。同一 batch・同じ Size=XS 条件で #1054(`phase/issue`)と #1052(`phase/ready`)が分かれた観測と符合する、コード上裏付けのある機構である。

## Changed Files

- `scripts/run-auto-sub.sh`: spec フェーズ dispatch 条件に `Size == XS` 分岐を追加し、スキップ理由をログ出力する(`skills/auto/SKILL.md` Step 3 に整合)
- `skills/auto/SKILL.md`: Step 4 の XL 経路説明文 — 「auto-runs spec if not set」を Size=XS 除外込みの記述に修正
- `skills/issue/SKILL.md`: Completion Report — `get-issue-size.sh $NUMBER` 呼び出しに `--no-cache` を追加し、理由を短いコメントで残す
- `tests/run-auto-sub.bats`: リグレッションテストを追加 — Size=XS + `phase/issue`(`phase/ready` 無し)で `run-spec.sh` が呼ばれないことを検証

## Implementation Steps

1. `scripts/run-auto-sub.sh`: spec dispatch ブロック(`LABELS=$(gh issue view ...)` から始まる `if/elif/fi`)の `if echo "$LABELS" | grep -qE "phase/(code|review|merge|verify|done)"; then ... ` 分岐と `elif ! echo "$LABELS" | grep -q "phase/ready"; then` 分岐の間に `elif [[ "$SIZE" == "XS" ]]; then echo "${LOG_PREFIX} spec phase: skipping dispatch for issue #${SUB_NUMBER} (Size XS; spec not required per skills/auto/SKILL.md Step 3)"` を追加する。ブロック先頭のコメント(`# spec phase: run only if phase/ready is absent AND ...`)に Size ゲートの説明を加筆する(→ acceptance criteria 1)
2. `skills/auto/SKILL.md`: Step 4 の「**XL route: sub-issue dependency graph with parallel execution (`run-auto-sub.sh` checks each sub-issue's `phase/ready` and auto-runs spec if not set):**」を「...checks each sub-issue's `phase/ready` and Size, auto-running spec only when `phase/ready` is absent and Size is not XS (mirrors Step 3):...」に書き換える(after 1)(→ acceptance criteria 1, 3)
3. `skills/issue/SKILL.md`: `## Completion Report` の「After opportunistic verification, get Size with `get-issue-size.sh $NUMBER`.」を「After opportunistic verification, get Size with `get-issue-size.sh --no-cache $NUMBER`(avoids a stale cached read immediately after Step 2/Step 8's triage auto-chain sets Size via GraphQL mutation — see `scripts/get-issue-size.sh`'s own `--no-cache` usage note).」に書き換える(parallel with 1, 2)(→ acceptance criteria 5)
4. `tests/run-auto-sub.bats`: 既存の `@test "phase/ready absent: run-spec.sh is called"` の直後に `@test "Size XS + phase/ready absent: run-spec.sh is NOT called (issue #1108)"` を追加する。`get-issue-size.sh` を `XS` を返すようモックし、`gh` の `--json labels` 応答を `triaged` / `phase/issue`(`phase/ready` 無し)にモックする。`$RUN_SPEC_LOG` が存在しないこと、および出力にステップ1で追加したスキップ理由文字列が含まれることを assert する(after 1)(→ acceptance criteria 4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の spec dispatch 条件と skills/auto/SKILL.md Step 3 の spec 要否判定が、XS Issue に対して同じ結論を出すようになっている" --> 単一 Issue 経路と batch/XL 経路で XS の spec 要否が一致している
- <!-- verify: rubric "skills/auto/SKILL.md Step 4b の前提記述 (XS patch route does not go through the /spec phase, so no Spec file exists) が、変更後の実挙動と一致している" --> Step 4b の前提が実挙動と一致している
- <!-- verify: rubric "Route-Phase Matrix および Phase-Level Light/Full Mapping の XS 行の spec 要否記述が、変更後の実挙動と一致している" --> ドキュメントの表が実挙動と一致している
- <!-- verify: rubric "tests/ に XS Issue に対する run-auto-sub.sh の spec dispatch 挙動を検証するケースが追加されている" --> XS の分岐がテストで保護されている
- <!-- verify: rubric "/issue が XS Issue 完了時に付与する phase label (phase/issue または phase/ready) が、run-auto-sub.sh の spec dispatch 判定と整合する形で決定的になっている (同じ Size=XS の Issue に対して実行タイミングや経路によってラベルが割れない)" --> `/issue` 側の XS 時ラベル付与の非決定性 (2026-07-30 コメント参照) が解消されている

### Post-merge

- `--batch` で XS Issue を処理し、spec 要否が規定どおりになること、および Step 4b が二重転記を起こさないことを確認する <!-- verify-type: opportunistic -->

## Notes

- **対応方針の採用理由(案 A)**:
  - Issue の Purpose 文言(「`run-auto-sub.sh` の spec dispatch と `skills/auto/SKILL.md` Step 3 の規定を一致させる」)は Step 3 を基準点として扱っている
  - 単一 Issue 経路(`/auto NUMBER` 直接実行、非 batch)は既に Step 3 のとおり XS で spec をスキップしており、これは実運用で機能している既定動作。batch/XL 経路の「XS でも spec が走る」挙動がそこから外れた異常値であり、規定側(案 B)を動かすより実装側(`run-auto-sub.sh`)を規定に合わせる方が影響範囲が小さい
  - Step 4b は XS Issue Retrospective 転記用の最小 Spec コンテナを single/batch/XL 全経路で既に提供している(Count/List mode がいずれも Step 4b を明示的に呼ぶ)。案 A でも「Spec の器としての実利」は失われない。失われるのは XS には過剰なフル設計コンテンツ(Implementation Steps・Changed Files 等)のみで、これはそもそも「Size XS は spec 不要」という既存設計根拠そのもの
  - 案 B(規定を「XS でも spec を走らせる」に変更)は Issue の Impact 2(不要な実行コスト)が問題視する方向と逆行する — コストを batch/XL だけでなく全 XS Issue に拡大してしまう
- **AC2・AC3 は検証のみで編集不要と判断した**: 案 A はルール自体(「Size XS は spec 不要」)を変更しない — 現行 3 箇所の SSoT(`skills/auto/SKILL.md` Step 3、`modules/size-workflow-table.md` の Size-to-Workflow Mapping Table、同ファイルの Phase-Level Light/Full Mapping)は既に「XS: not required」で一致しており、今回の実装修正でこの記述が実挙動と一致する側に是正される。`skills/auto/SKILL.md` Step 4b の前提文もルール変更が無いため引き続き真であることを確認済み(grep で該当箇所を確認、矛盾なし)
- `docs/workflow.md:52,113` にも同種の「XS: spec (if needed)」記述があるが、同じ理由(ルール不変)で変更不要と確認済み
- `skills/issue/SKILL.md` の Step 7(行485, AC 分類のあいまい検出件数上限)と Step 15 Pattern 4(行625, verify command 監査パターン選択)にも `get-issue-size.sh` を `--no-cache` 無しで呼ぶ同種のパターンが存在するが、いずれも phase label 決定には関与せず、本 Issue の AC5(ラベル決定性)のスコープ外と判断し今回は変更していない。同種の潜在的な陳腐化リスクとして記録のみ残す
- Issue Retrospective で自動解決された「`/issue` の XS 時ラベル付与の決定性」スコープ拡張(Purpose・対応方針・AC5 追加)は Issue 本文に既に反映済み。本 Spec ではその根本原因を `get-issue-size.sh` のキャッシュ起因(Bug 2)と特定し、修正方針を確定した

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズの Issue Retrospective。Issue 本文への「追加観察 (`/issue` の XS 時ラベル付与の非決定性)」の折り込みが既に完了していること、対応方針 (案 A/B/C) の最終決定は `/spec` に委ねる判断であることを記録。タイトルは変更しないと判断した旨も記載。 / URL: https://github.com/saitoco/wholework/issues/1108#issuecomment-5212311203

### code phase (cutoff: `2026-08-07T04:45:15Z`)

No new comments since last phase.

## Autonomous Auto-Resolve Log

- Step 3 (`phase/ready` label check): label list is `triaged`, `phase/code`, `retro/verify` — `phase/ready` is absent because the Issue already advanced past it (timeline shows `phase/ready` at 04:41:22Z → `phase/code` at 04:45:15Z, no PR/branch/worktree existed prior to this run, indicating a prior `/code` invocation transitioned the label but did not complete implementation). Spec file `docs/spec/issue-1108-auto-spec-dispatch-xs-gate.md` was confirmed present and complete. Auto-resolved: proceed with implementation using the existing Spec.

## Code Retrospective

### Deviations from Design
- N/A — implementation followed the Spec's 4 Implementation Steps as written.

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

### Smoke Test
- N/A — Spec has no `## Smoke Test` section.

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Ran `/review 1235 --light --non-interactive` (Size=M → `REVIEW_DEPTH=light`, matching the `--light` override). Base branch conflict pre-check (`git merge-tree`, 3-arg form) found 0 `changed in both` blocks — no conflict context passed to the review agent.
- Re-verified all 5 pre-merge `rubric` AC independently in Step 8 (adversarial re-check, not just trusting the code phase's self-verification) — all 5 confirmed PASS with the same reasoning as the code phase's Phase Handoff.
- Ran `review-light` (all 4 aspects: spec deviation, edge cases, security, documentation consistency) — found 1 CONSIDER-severity issue (cosmetic log-message ordering in `scripts/run-auto-sub.sh`'s new XS branch when `phase/ready` is also absent-vs-present), 0 MUST/SHOULD. Posted as an inline PR comment; not fixed (Claude's Step 12 judgment: cosmetic only, no functional impact, review agent itself offered "leave as-is" as an acceptable alternative).
- CI: all 9 checks (DCO, Run bats tests ×2, Validate skill syntax ×2, Forbidden Expressions check ×2, macOS shell compatibility ×2) SUCCESS — no FAIL-blocking entries injected into the review.

### Deferred Items
- Post-merge AC ("`--batch` で XS Issue を処理し、spec 要否が規定どおりになること、および Step 4b が二重転記を起こさないことを確認する", `verify-type: opportunistic`) remains deferred to post-merge observation — unchanged from the code phase's handoff, still `- [ ]` in the Issue body (cross-referenced, not stale).
- The CONSIDER-severity log-message-ordering issue in `scripts/run-auto-sub.sh:840` was left unfixed; if a future change touches this `elif` chain, consider reordering the `phase/ready`-absence check ahead of the `Size == XS` check so the log message always attributes the skip to its most direct cause.

### Notes for Next Phase
- No MUST issues — review posted as `COMMENT`, not `REQUEST_CHANGES`. `/merge 1235` can proceed directly.
- No policy changes were made in this review pass (Step 12 made no implementation edits), so Step 13's Issue body / AC update was skipped — the Issue's AC text and verify commands are unchanged from the Spec's Verification section.

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — implementation matched the Spec's 4 Implementation Steps exactly, confirmed both by the code phase's own retrospective (Deviations from Design: N/A) and by this review's independent Step 8/10 re-check.

### Recurring issues

Nothing to note — no issue class repeated within this PR (the single CONSIDER finding was a standalone cosmetic observation, not a pattern across multiple files/branches).

### Acceptance criteria verification difficulty

All 5 pre-merge conditions used `rubric` verify commands exclusively (no mechanical `file_contains`/`grep` supplementary checks). This worked cleanly here because the PR diff is small (5 files, ~76 net lines) and each AC maps to a clearly bounded code/doc change, but it's worth noting for future Issues in this area: AC1 ("XS Issue に対して同じ結論を出す") and AC5 ("`/issue` 側の XS 時ラベル付与の非決定性が解消されている") both describe *behavioral equivalence across two independent code paths* rather than a single-file property — a grader without git history access could plausibly miss that the "before" state (Bug 1 / Bug 2 in the Spec's Root Cause section) is what makes the "after" state meaningful. No actual grading difficulty was observed in this run, but a rubric text that briefly names the specific *prior* broken behavior (not just the desired end state) would make the grader's job more robust for this class of "make two paths agree" AC — no Issue filed for this, recording as an observation only per [[feedback_issue_filing_restraint]].
