# Issue #1329: auto: silent no-op に対する auto-retry を run-code.sh 以外の wrapper にも揃えるか判断

## Overview

`run-code.sh` は silent no-op (`reconcile-phase-state.sh` の `matches_expected:false`) を検出すると `auto-retry-on-fail` により自己リトライするが、他の `run-*.sh` wrapper (`run-issue.sh` / `run-spec.sh` / `run-review.sh` / `run-merge.sh`) には同等の機構がない。#1130 (spec phase での実測) では built-in retry がないため親セッションの Tier 3 recovery まで落ち、#1102 (code phase、built-in retry で約 25 分の時間コストに留まった) より高コストな復旧になった。

本 Issue は「揃えるか、揃えない設計判断の根拠を明示するか」を決定し、`modules/orchestration-fallbacks.md` に記録することを求めている (検討候補 A: 全 wrapper に揃える / B: spec のみ追加 / C: 揃えない理由を明文化)。

調査の結果、phase ごとの安全性は一様ではないと判断した。spec は `code-patch` と同型 (単一 wrapper、ローカルな completion signature 判定、部分的な副作用が残らない) であり `scripts/run-spec.sh` は既に検知ロジックを持つため拡張リスクは低いが、issue / review は実測インシデントがなく、merge は squash-merge という不可逆操作を含むため単純な移植はできない。この分析を `modules/orchestration-fallbacks.md` の既存 `auto-retry-on-fail (code_retry_fire)` セクションに追記する。spec phase への実際の実装は follow-up Issue として推奨するに留め、本 Issue 自体はドキュメント上の意思決定のみを扱う (判断根拠の詳細は `## Notes` を参照)。

## Changed Files

- `modules/orchestration-fallbacks.md`: `## auto-retry-on-fail (code_retry_fire)` セクション (現在 533-558 行) を拡張。`### Applicable Phases` (539-541 行) に 1 行追加し、`### Fallback Steps` (543 行) の直前に新規 `### Phase Scope Decision` サブセクションを挿入、`### Rationale` (551-557 行) に 1 文追記。prose のみ (コード変更なし)。bash 3.2+ 互換の考慮は不要 (`.sh` ではなく `.md`)

## Implementation Steps

1. 現状の phase 別 silent no-op 検知/リトライ範囲を確認する (→ 受入条件 1)。以下を確認済み:
   - `scripts/run-spec.sh` (202-210 行付近) は既に `reconcile-phase-state.sh spec "$ISSUE_NUMBER" --check-completion` を呼び `matches_expected:false` で `EXIT_CODE=1` を設定している (`run-code.sh` 386-414 行と同型の検知) が、retry-vs-fail の分岐自体が存在しない
   - `scripts/apply-fallback.sh` の `apply_code_patch_silent_no_op_retry()` (106 行付近) は Tier 2 の実際のリトライ対象を `run-code.sh --patch` に固定しており、`detect_symptom_anchor()` 自体の検知は phase-agnostic でも、spec (および issue/review/merge) phase の silent no-op は Tier 2 では回収できない
   - `modules/phase-state.md` の Phase Table は issue/spec/code-patch/code-pr/review/merge の全 phase に対し `Implemented` の completion signature (local check または `gh pr view` 等の live check) を既に定義している

2. `modules/orchestration-fallbacks.md` の `## auto-retry-on-fail (code_retry_fire)` セクション (現在 533-558 行) を拡張する (→ 受入条件 1, 2):
   - `### Applicable Phases` (539-541 行) に 3 番目の箇条書きとして追加: 「この scope は Issue #1329 による根拠付きの確定判断であり (詳細は下記 Phase Scope Decision を参照)、未整備ではない」旨の 1 文
   - `### Fallback Steps` (543 行) の直前に新規 `### Phase Scope Decision` サブセクションを挿入する。内容 (英語、モジュールファイルの既存文体に合わせる):

     ```markdown
     ### Phase Scope Decision

     Whether this mechanism should extend beyond the code phase was evaluated in Issue #1329, prompted by a spec-phase silent no-op (#1130) that had no wrapper-level retry and fell through to Tier 3 recovery — costlier than the code-phase equivalent (#1102), which this entry's own mechanism resolved in ~25 minutes. The code-only scope is confirmed as deliberate, evidence-gated policy, not an unaddressed gap, decided per phase:

     - **spec**: structurally the same shape as `code-patch` — single wrapper, local `reconcile-phase-state.sh <phase> --check-completion` signature (`modules/phase-state.md` Phase Table), no partial external side effect to double-apply on retry. `scripts/run-spec.sh` already calls this check and sets `EXIT_CODE=1` on `matches_expected:false` (mirroring `run-code.sh`'s own detection) — only the retry-vs-fail branch itself is missing. Recommended as a follow-up Issue on the strength of the #1130 incident; not implemented by #1329 itself (Size S / documentation-only scope).
     - **issue, review**: same low-risk shape as spec (local completion signature, no partial side effect), but no observed silent-no-op incident to date. Left unextended for now, consistent with Wholework's evidence-gated recalibration pattern elsewhere (e.g. #903, #939, #1301: act after a real measured incident, not pre-emptively) — re-evaluate if one occurs.
     - **merge**: not safely portable as-is. `gh pr merge --squash --delete-branch` is an irreversible external side effect; a local-completion-only gate (the pattern `code`/`spec` use) risks a second merge attempt if that check is stale or racy. A safe design would need the same live `gh pr view --json state` check `detect-wrapper-anomaly.sh` already uses for merge-phase anomaly detection (see `#code-patch-silent-no-op`'s Exception Condition above), not the simpler local gate — a materially different, not-yet-designed mechanism. Deferred until a real merge-phase silent-no-op incident justifies the added design and implementation cost.

     Tier 2 (`apply-fallback.sh`)'s `code-patch-silent-no-op` handler is also code-phase-specific in its retry action (`apply_code_patch_silent_no_op_retry()` hardcodes `run-code.sh --patch`) even though `detect_symptom_anchor()`'s underlying symptom detection is phase-agnostic — so today, a non-code-phase silent no-op has no automatic recovery below Tier 3, matching the #1130 Background exactly.
     ```

   - `### Rationale` (551-557 行) の末尾に、本判断の出典として Issue #1329 を参照する 1 文を追記する
   - **制約**: 新規の独立した `##` トップレベルエントリを追加しないこと。`tests/orchestration-fallbacks.bats` の `"all 5 required sections appear the same number of times"` (48 行目) は `### Symptom` / `### Applicable Phases` / `### Fallback Steps` / `### Escalation` / `### Rationale` の出現数がファイル全体で完全一致することを要求しており、5 セクションを揃えない新規 `##` エントリを追加するとこのテストが壊れる。既存エントリへのサブセクション追加 (`code-patch-silent-no-op` の `### Exception Condition`、`review-pending-not-failure` の `### Structural PENDING` と同じ扱い) はこのカウントに影響しない

3. `bats tests/run-spec.bats tests/run-code.bats` を実行し、ドキュメントのみの変更が回帰を起こしていないことを確認する (→ 受入条件 3)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/orchestration-fallbacks.md に、silent no-op に対する auto-retry を phase ごとに持たせるか否かの設計判断が根拠とともに記録されている。少なくとも run-code.sh のみが auto-retry-on-fail を持つ現状について、意図的な判断か未整備かが明示されている" --> 設計判断とその根拠が `modules/orchestration-fallbacks.md` に記録されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md に、リトライが安全な phase とそうでない phase の区別が論じられており、不可逆操作を含む phase (merge 等) の扱いが明示されている" --> phase ごとのリトライ安全性が `modules/orchestration-fallbacks.md` に論じられている
- <!-- verify: command "bats tests/run-spec.bats tests/run-code.bats" --> 対象 wrapper の既存 bats スイートが回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前 2 項が担う)

### Post-merge

- 次回以降の `/auto` で code phase 以外に silent no-op が発生した際、本 Issue で決定した挙動 (自動リトライまたは明示された非対応) のとおりに動作することを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 事実確認 (Background の再検証)

Issue 本文 Background の `run-code.sh` 行番号記載 (`:302`) は現行コード (`:387`-`:411` 付近) とずれているが、対象シンボル (`AUTO_RETRY_ENABLED` / `CODE_RETRY_COUNT`) 自体の存在は一致しており、設計判断に影響する不整合ではない (Issue Retrospective コメントで既に確認済み)。

### Steering Docs sync candidate: docs/tech.md

`docs/tech.md:132` ("code-side auto-retry (silent no-op)" 箇条書き) と `docs/ja/tech.md:124` は既に `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` アンカーを参照している。本 Issue は同じエントリにサブセクションを追加するのみでアンカー自体は変更しないため、`docs/tech.md` 側の更新は不要と判断した。

### スコープ判断: Option B (spec phase 拡張) は推奨に留め、本 Issue では未実装

検討候補 A (全 wrapper に揃える) / B (spec のみ追加) / C (揃えない理由を明文化) のうち、phase 別の安全性分析の結果、**B を follow-up Issue として推奨し、本 Issue 自体はドキュメント上の意思決定のみを扱う** — A ではなく B とした理由は、issue/review に実測インシデントがなく、merge は不可逆操作のため追加設計なしに安全に拡張できないため (詳細は Implementation Steps 2 の Phase Scope Decision 本文を参照)。本 Issue を実装ではなくドキュメント判断に留めた理由:

- Issue の Purpose は「決める」ことであり「実装する」ことではない
- Size S (light depth) は、`run-code.sh` の auto-retry-on-fail 実装 (helper 関数・exec 前 recording・stash preflight・新規 bats カバレッジを含む、#1320 で実装された規模) を `run-spec.sh` に移植するには小さすぎる
- 受入条件 3 が「回帰保護のみを目的とする AC — 新規カバレッジの主張は前 2 項が担う」と明記しており、新規リトライロジックに対する新規テストカバレッジを要求していない

## Consumed Comments

- saito (MEMBER、first-class): Issue Retrospective — #1130 spec-phase 事例の Background 記載事実 (grep 行番号) を再検証し一致を確認、AC1/AC2 の rubric 根拠ファイル明示という自動解決あいまいポイントを記録。https://github.com/saitoco/wholework/issues/1329#issuecomment-5303444795

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 2 に記載された `### Phase Scope Decision` 本文をほぼ逐語的に反映した。順序・構成の変更なし

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

### Notes

- `tests/orchestration-fallbacks.bats` の Behavioral Change Detection (`modules/verify-patterns.md` §24 相当) により、`modules/orchestration-fallbacks.md` を参照する既存テストが `tests/run-code.bats` / `tests/run-auto-sub.bats` にも存在すると判定されたため、AC3 で指定された `tests/run-spec.bats tests/run-code.bats` に加えてフルスイート (`bats --jobs 18 tests/`, 1786 件) を実行し、回帰がないことを確認した (全 PASS)
- Spec Notes の「スコープ判断: Option B (spec phase 拡張) は推奨に留め、本 Issue では未実装」を受け、follow-up Issue #1369 を作成した (`retro/code` ラベル)

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 2 に記載された `### Phase Scope Decision` 本文を `modules/orchestration-fallbacks.md` の `## auto-retry-on-fail (code_retry_fire)` セクションへ逐語的に反映した (Applicable Phases への 1 文追加、新規 `### Phase Scope Decision` サブセクション挿入、`### Rationale` への 1 文追記)
- `tests/orchestration-fallbacks.bats` の「5 セクション出現数が全エントリで一致する」制約を守るため、新規 `##` トップレベルエントリではなく既存エントリへのサブセクション追加として実装した
- Behavioral Change Detection の結果、AC3 の narrow scope (`tests/run-spec.bats tests/run-code.bats`) に加えてフルスイートを実行し回帰なしを確認した

### Deferred Items
- Option B (spec phase への実際の auto-retry-on-fail 実装) は follow-up Issue #1369 として起票し、本 Issue のスコープ外とした (Spec Notes 記載通り)
- Post-merge AC (次回 silent no-op 発生時の挙動確認、`event=auto-run session=next`) は `/verify` 以降の observation 待ち

### Notes for Next Phase
- 本 Issue はドキュメントのみの変更 (prose diff 12 行) — `/verify` は 3 件の pre-merge AC (rubric x2 + bats command) と 1 件の post-merge observation AC のみを扱う
- pre-merge AC のうち rubric 2 件は `/code` 内で自己判定し PASS 済みとして checkbox を `[x]` 済みにした。`/verify` での再検証時、rubric grader が同じ diff から同一の結論に達するか確認すること

## Issue Retrospective

### 非対話モード実行

`--non-interactive` で実行。Step 12 (sub-issue splitting scope assessment) は High-Stakes Decision のためスキップ (Size S でありそもそも該当しないが、方針上明示)。

### 事実確認 (Background)

Background に記載された具体的な claim (grep 結果・行番号) を現行コードに対して再検証した:
- `grep -n "retry\|RETRY" scripts/run-spec.sh` → `:150` `:176` `:190` にヒット (retry-on-kill.sh の source と `run_with_retry_on_kill` 呼び出しのみ) — 記載どおり一致
- `grep -n "AUTO_RETRY_ENABLED\|CODE_RETRY_COUNT" scripts/run-code.sh` → `:133` `:137` `:143` `:144` に加え `:387` `:388` `:389` `:390` `:391` `:394` `:406` `:410` `:411` にもヒット (本文記載の `:302` は現行行番号とずれているが、対象シンボルの存在自体は一致)
- `run-issue.sh` / `run-review.sh` / `run-merge.sh` は `retry-on-kill.sh` の source のみで `auto-retry-on-fail` 相当の分岐は無し — 記載どおり一致

### 自動解決したあいまいポイント

**AC1/AC2 の rubric 根拠ファイル不在** (Priority: 高 — AC の合否判定そのものに影響):

`modules/verify-executor.md` § Rubric Command Semantics により、`rubric` grader の既定入力範囲は Issue body + git diff のみで、Spec ファイルは含まれない。本 Issue の Purpose は「決める」ことそのものが目的であり、決定内容が Spec のみに記録された場合、grader はその根拠を参照できず、AC1/AC2 が意図せず FAIL/UNCERTAIN になるリスクがあった。

`modules/orchestration-fallbacks.md` には同種の retry 機構の設計判断の先例が既に記録されており、本 Issue の Related セクションも同ファイルを「復旧経路のカタログ」として既に参照していたため、この既存パターンに沿って AC1/AC2 の rubric text に `modules/orchestration-fallbacks.md` を明示した。

他候補 (ファイル名を明示せず git diff 参照に委ねる) は、決定が Spec のみに残るケースを排除できないため却下した。

### Auto-Resolve Log 以外の検討事項 (変更不要と判断)

- **AC3 の bats スコープ**: AC3 は回帰保護のみを目的とする AC と明記済みで、他 wrapper の回帰は CI が別途検知するため、AC 変更は不要と判断した。
- **`verify-type: observation event=auto-run session=next` の妥当性**: `modules/verify-classifier.md` § Firing Likelihood Check に照らし、既存の確立されたパターンと一致するため変更不要と判断した。
- **`session=next` の要否**: `scripts/check-skill-change-observation-ac.sh` を実行し exit 0 (該当なし) を確認。
- **AC checkbox format**: `scripts/check-ac-checkbox-format.sh` を実行し exit 0 (問題なし) を確認。

### Consumed Comments (at /issue time)

No new comments since last phase.
