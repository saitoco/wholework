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
