# Issue #1443: auto: background-notification-wait パターンの再発 (#1271) を調査し #1332 のカバー範囲を検証

## Overview

PR #1332 は `scripts/guard-prefix.sh` に background-notification-wait 禁止ガードを追加し、`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` の全 5 wrapper が `PROMPT` 先頭にこの文字列を前置するようにした (#1213 iteration 2)。しかし 2026-08-22、review フェーズ (Issue #1271) で同じ失敗モードが再発し、Tier 3 recovery (`agents/orchestration-recovery`) が自動復旧した (`docs/reports/orchestration-recoveries.md` 2026-08-22 10:10 UTC エントリ、cause: `background-notification-wait`、Outcome: success)。

本 Issue は、#1271 の実行パスが PR #1332 のガードを実際に通過していたのかを検証し、原因に応じた対策 (追加修正 / 検出・復旧改善 / 既存 Tier 3 で十分と明文化) のいずれかを実施する。

## Reproduction Steps

決定的に再現可能な不具合ではない — 非対話 `claude -p` セッション内での LLM 指示遵守のばらつきであり、決定的なコード欠陥ではない。#1271 で観測された事象の時系列 (`docs/reports/orchestration-recoveries.md` 2026-08-22 10:10 UTC エントリより):

1. `/auto` が Issue #1271 に紐づく PR に対して `run-review.sh` を起動した。
2. CI checks が terminal state に到達 (14/15 SUCCESS、1 件は無関係な FAILURE) — wrapper 側の `claude` 起動前の CI wait (`run-review.sh:107`) と、`claude -p` セッション内の Step 9 の両方で確認済み。
3. review セッションは Step 9 以降のどこかでターンを黙って終了し、Step 11 の "Acceptance Criteria Verification Results" コメント投稿に到達しなかった。
4. `run-review.sh` が exit 1、`reconcile-phase-state.sh` は `matches_expected:false` を報告、`post-fallback-review-summary.sh` はフォールバック元にできる既存 AC コメントを発見できなかった。
5. Tier 3 recovery (`agents/orchestration-recovery` sub-agent) が `cause: background-notification-wait` と診断し retry。retry は成功 (`Outcome: success`)。

## Root Cause

- PR #1332 由来の wrapper 層ガードは #1271 の実行パスに実際に到達していた: `scripts/run-review.sh` が無条件に `scripts/guard-prefix.sh` を source し、`claude -p` 起動の都度 `GUARD_PREFIX` を `PROMPT` 先頭に前置していることを確認した (`run-review.sh:251-257`)。これをスキップする条件分岐は存在しない。したがって #1130 (spec フェーズにガード文言が一切存在しなかったケース) と同種のカバレッジ欠落ではない。
- `modules/execution-context.md` § "Wrapper-Level Constraint Injection" は #1271 以前から、これが「prompt-level guidance であり mechanical enforcement ではない」こと、および同じ in-prompt ルールが #1168 で 2/2 違反された前例を明記している — つまり設計は元々 100% 防止を謳っておらず、検出/復旧 (Tier 1-3) が残存率に対する想定済みの backstop だった。
- Tier 3 sub-agent の診断が粗い ("ended its turn silently after the CI wait") 理由: 与えられる証拠が `log_tail` (wrapper 自身の stdout/stderr の末尾 200 行、`agents/orchestration-recovery.md:22`) と `reconcile-phase-state.sh` のスナップショットのみで、`claude -p` セッション内部のツール呼び出し・思考過程は含まれない。そのため利用可能な証拠からは、ターンが黙って終了した正確な SKILL.md ステップを特定できない。
- 構造分析による最有力候補 (直接証拠による確認はできていない): Step 10 (「Multi-perspective Code Review — parallel execution」)。オーケストレータが 1〜3 件の `Task(...)` sub-agent 呼び出しを dispatch し、その結果を消費してから続行する必要がある箇所である。`skills/review/SKILL.md` の既存の foreground execution 記述 (`## Non-Interactive Mode Behavior` 内、39 行目) は review sub-agent 自身が内部で実行する test/build コマンド ("commands run by Step 10's review sub-agents") のみを対象としており、オーケストレータ自身の Step 10 での Task/Agent dispatch を同一ターン内で同期的に扱うべきことは別途明記されていない。これは `modules/execution-context.md` が SKILL.md 側ガードに割り当てている役割 (wrapper 層の backstop を補う「具体的な実行時点のガイダンス」) の狭い欠落であり、#1271 の実際のトリガーであったかどうかに関わらず存在する。
- 定量的背景: PR #1332 マージ (2026-08-10T06:55:56Z) から #1271 (2026-08-22) までの 12 日間で、本リポジトリで作成された PR は約 51 件 (`gh pr list --state all --search "created:2026-08-10..2026-08-22" --limit 300`、全ファイル種別、全 state 対象。`/review` 実行回数の下限近似値 — fix cycle で再 review が入った PR も 1 件として数えるため)。この window で確認された `background-notification-wait` 発生は #1271 の 1 件のみで、Tier 3 により自動復旧 (`Outcome: success`、人手介入ゼロ)。

## Changed Files

- `modules/execution-context.md`: § "Wrapper-Level Constraint Injection" に日付入りの「recurrence check」段落を追記する。内容: ガード到達確認、上記の定量的根拠、「Verdict: maintain」(既存の 3 段階検出/復旧で十分) という結論、再評価トリガー。
- `skills/review/SKILL.md`: `## Step 10: Multi-perspective Code Review (parallel execution)` 見出し直下に、foreground dispatch reminder を短く追加する。既存の sub-agent 内部コマンド向けの記述 (`## Non-Interactive Mode Behavior`) とは対象が異なることを明記し、オーケストレータ自身の `Task(...)` dispatch を対象とする。
- [Steering Docs sync candidate] キーワード "execution-context.md" はスキップ: `docs/`, `tests/`, `scripts/`, `modules/` 配下で 23 件ヒット (discriminating power なし)
- [Steering Docs sync candidate] キーワード "review" (bare skill name) はスキップ: `/spec` Step 10 ガイダンスの常時スキップ対象クラス

## Implementation Steps

1. ガード到達の事実確認と再発率の定量的根拠を収集する: `scripts/run-review.sh` が `guard-prefix.sh` を無条件 source していること (バイパス分岐が存在しないこと) を再確認し、2026-08-10〜2026-08-22 の window で `gh pr list` による近似計測を実行する (→ acceptance criteria AC1)
2. `modules/execution-context.md` § Wrapper-Level Constraint Injection に「Verdict: maintain」結論の段落を追記する (1 の後) (→ acceptance criteria AC2)
3. `skills/review/SKILL.md` の Step 10 に foreground dispatch reminder を追加する (1 の後、2 と並行可) (→ acceptance criteria AC2)
4. 根本原因の特定内容と Verdict: maintain の結論を、コミットメッセージおよび Issue 本文 (retrospective) の両方に記録し、AC1/AC2 の「Issue 本文またはコミットメッセージで」という要件を landed change 自体で満たす (2, 3 の後) (→ acceptance criteria AC1, AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "PR #1332 で導入された wrapper 層のガード実装 (skills/*/SKILL.md および run-*.sh 相当) を確認し、#1271 (2026-08-22, review フェーズ) の実行パスがそのガードを実際に通過していたのか、あるいはガードが到達しない経路 (別のコード分岐、ガード注入漏れ箇所など) だったのかが、Issue本文またはコミットメッセージで具体的に特定されている" --> #1271 再発の根本原因が特定されている
- <!-- verify: rubric "特定された原因に対して、(a) ガードの適用漏れ箇所への追加修正、(b) 検出/復旧ロジックの改善、(c) 既存の Tier 3 自動復旧で十分と判断しその根拠を明文化する、のいずれかの形で具体的な結論が実施されている" --> 対策または明文化された結論が実施されている

### Post-merge

- 対策実施後 (または「対策不要」の結論後) も `background-notification-wait` が review フェーズで再発しないか、`docs/reports/orchestration-recoveries.md` への新規記録の有無を継続的に観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- Auto-Resolve Log: N/A — SPEC_DEPTH=light のため Step 7 (Ambiguity Resolution) はスキップ。エスカレーションされた曖昧ポイントはなし。
- 監査/実査型 Issue 判定 (`/spec` Step 6 記載の判定基準に基づく): **該当しない** と判断。本 Issue は単一インシデントの根本原因調査であり、複数の既存項目を定義済みカテゴリへ分類する実査 (#1274/#1276 のような per-AC-line 監査) ではない。そのため「引用参照の存在確認」要件は形式上は適用対象外だが、上記で引用した全ファイル/行番号 (`run-review.sh:107`、`run-review.sh:251-257`、`execution-context.md:97-141`、`skills/review/SKILL.md:39`、`orchestration-recoveries.md` 2026-08-22 10:10 UTC エントリ) はいずれも Spec 調査時に grep/Read で直接確認済みであり、記憶からの転記ではない。
- 未解決の不確実性 (light depth のため意図的に深追いしていない): Claude Code の `Task`/`Agent` sub-agent dispatch ツールが、非対話 `claude -p --non-interactive` セッション内で同期的 (呼び出し元ターンが全結果の返却をブロックして待つ) か、それとも通知ベースの完了を伴うバックグラウンド既定かは、本調査では一次情報から確認できていない。Root Cause の Step 10 仮説は構造分析に基づく尤もらしい候補であり、直接証拠による確認ではない — `agents/orchestration-recovery.md` の Tier 3 sub-agent が受け取るのは wrapper の stdout/stderr `log_tail` のみで、review セッション内部のツール呼び出しトレースは含まれないため、現状これを裏付け/反証できる証拠源がない。今後の再発診断で正確なステップが特定できた場合はこの Note を更新すること。
- Steering Docs 同期: `docs/tech.md` は意図的に変更対象から外した。`modules/execution-context.md` § Wrapper-Level Constraint Injection が本件と同じ話題を扱う、より狭くスコープされた既存の SSoT であるため (`docs/tech.md` の Architecture Decisions は多数の無関係な話題を横断する広いリストである一方)、結論はそちらに一本化し、同一内容を 2 箇所に重複記載することを避けた。

## Code Retrospective

### Deviations from Design
- Implementation Step 4 said to record the root cause / Verdict conclusion in "the commit message and the Issue body (retrospective)". Interpreted this concretely as adding a `## Resolution` section to the Issue body (between `## Purpose` and `## Acceptance Conditions`) summarizing the root cause, quantitative background, and Verdict — since `modules/verify-executor.md`'s rubric grader input scope is Issue body + git diff + explicitly-named files (Spec is excluded), and the rubric AC text explicitly asks for "Issue本文またはコミットメッセージで" identification. Confirmed both Pre-merge rubric AC now have concrete, checkable evidence in the Issue body itself, not only in the diff.

### Design Gaps/Ambiguities
- N/A beyond what the Spec's Notes section already records (the Task/Agent sub-agent dispatch synchronicity question remains unresolved from first-party evidence; not re-investigated at this phase since it was explicitly scoped out at light depth).

### Rework
- N/A

## Consumed Comments
No new comments since last phase.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Verdict: maintain — the existing three-tier detection/recovery (wrapper-level `guard-prefix.sh` injection + Tier 1-3 recovery) is treated as sufficient given a 1-in-51-PR recurrence rate, fully auto-recovered with no manual intervention. Recorded as a dated recurrence-check paragraph in `modules/execution-context.md` rather than opening a new SSoT section, since that module already owns this topic.
- Added a narrow foreground-dispatch reminder to `skills/review/SKILL.md` Step 10 for the orchestrator's own `Task(...)` calls, distinct from the existing reminder that only covered commands run internally by review sub-agents.
- Recorded the root cause and Verdict in a new `## Resolution` section in the Issue body (not just the commit message / diff), because the rubric grader's input scope (Issue body + git diff + explicitly-named files) needed concrete Issue-body evidence for both Pre-merge AC to be checkable independent of diff visibility.

### Deferred Items
- The Spec's Notes-recorded uncertainty (whether Claude Code's `Task`/`Agent` dispatch is synchronous or notification-based under `claude -p --non-interactive`) remains unresolved from first-party evidence — intentionally not re-investigated here (light depth, same reasoning as the Spec phase).
- No follow-up Issue filed: the added Step 10 reminder is treated as closing the identified gap, and Post-merge AC (observation) covers ongoing monitoring.

### Notes for Next Phase
- Post-merge AC is an `observation` type (event=auto-run session=next) — no action needed from `/review`/`/merge`; `/verify` will pick it up in a later auto-run session.
- Both Pre-merge rubric AC are self-graded PASS in this phase based on: (a) the diff to `modules/execution-context.md` / `skills/review/SKILL.md`, and (b) the Issue body `## Resolution` section added in this phase. If `/review` re-grades adversarially and disagrees, check whether it read the worktree-current Issue body (post-edit) rather than a stale cached version.
