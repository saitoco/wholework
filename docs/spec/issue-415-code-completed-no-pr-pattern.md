# Issue #415: detect-wrapper-anomaly: code-completed-no-pr パターンを Tier 2 カタログに追加

## Overview

watchdog 1800s timeout で kill された code-pr フェーズが、worktree 内の commit を完了したまま PR 未作成で終了するシナリオ（#385 の retrospective で発見）を Tier 2 catalog で半自動 recovery 可能にする。`scripts/detect-wrapper-anomaly.sh` に `code-completed-no-pr` パターンを追加し、`modules/orchestration-fallbacks.md` に rebase → push → PR 作成の recovery 手順を catalog 化する。signature は `'"matches_expected":false'` + `'"phase":"code-pr"'` の組み合わせを採用。

## Changed Files

- `scripts/run-code.sh`: 159–169 行の `if [[ $EXIT_CODE -eq 143 ]]` ブロックに `echo "reconcile-phase-state result: $_reconcile_out"` を追加（detect-wrapper-anomaly.sh からの検出を成立させる前提変更） — bash 3.2+ compatible
- `scripts/detect-wrapper-anomaly.sh`: `dco-missing` ブロック直後・`watchdog-kill` ブロック直前に `code-completed-no-pr` パターン（`'"matches_expected":false'` AND `'"phase":"code-pr"'`）を追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: `code-completed-no-pr` パターン検出テスト（正例 1 件 + negative 2 件）を追加
- `modules/orchestration-fallbacks.md`: `## reconciler-header-mismatch` 直後・`## Operational Notes` 直前に `## code-completed-no-pr` カタログエントリ（Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale）を追加

## Implementation Steps

1. `scripts/run-code.sh`: 159–169 行の `if [[ $EXIT_CODE -eq 143 ]]` ブロック内、`_reconcile_out=$(...)` 行の直後（`if echo "$_reconcile_out" | grep -q ...` の前）に `echo "reconcile-phase-state result: $_reconcile_out"` を追加する。これにより reconcile 結果がラッパーログに記録され、Tier 2 検出が成立する。 (→ 検出シグネチャ前提条件)
2. `scripts/detect-wrapper-anomaly.sh`: `elif grep -q "ERROR: missing sign-off" "$LOG_FILE"; then` ブロック（`dco-missing`）の直後・`elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then` ブロック（`watchdog-kill`）の直前に、`code-completed-no-pr` の elif ブロックを追加する。検出条件: `grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"code-pr"' "$LOG_FILE"`。`PATTERN_NAME="code-completed-no-pr"` を設定し、`ANOMALY_DESC` には watchdog kill 後 PR 未作成シナリオの説明と Issue #415 の出典、`IMPROVEMENT_HINT` には `modules/orchestration-fallbacks.md#code-completed-no-pr` への参照を含める。 (→ AC1, AC6 のうち bats 側、AC3 [rubric の検出側根拠])
3. `tests/detect-wrapper-anomaly.bats`: 既存 `reconciler-header-mismatch` テスト群の直後に `code-completed-no-pr` の bats テストを 3 件追加する。(a) 正例: ログに `'"matches_expected":false'` と `'"phase":"code-pr"'` の両方を含み、`exit-code 143 --phase code` で実行 → output が `code-completed-no-pr` と `### Orchestration Anomalies` を含むことを assert; (b) negative: `'"matches_expected":false'` のみで `'"phase":"code-pr"'` を含まない場合は空出力; (c) negative: `'"phase":"code-pr"'` のみで `'"matches_expected":false'` を含まない場合は空出力。 (→ AC6)
4. `modules/orchestration-fallbacks.md`: `## reconciler-header-mismatch` セクション末尾の `---` 直後・`## Operational Notes` 直前に `## code-completed-no-pr` カタログエントリを追加する。`### Symptom`（`run-code.sh` が exit code 143 を返し、ラッパーログに `reconcile-phase-state result:` の `'"matches_expected":false'` + `'"phase":"code-pr"'` を含む）、`### Applicable Phases`（code (PR route)）、`### Fallback Steps`（1. worktree branch に checkout し最新 main へ rebase、2. `git push origin <branch>` で push、3. `gh pr create` で PR を作成、4. `/review <PR>` で review 継続）、`### Escalation`（recovery sub-agent #316 への委譲、conflict 発生時の中断条件）、`### Rationale`（出典 #385 retrospective、`run-code.sh` の echo 追加によって検出可能化、`_completion_code_pr()` の `matches_expected:false` 唯一の mismatch ケースが PR 不在であること）を含める。 (→ AC2, AC3, AC4, AC5)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "code-completed-no-pr" --> `scripts/detect-wrapper-anomaly.sh` に `code-completed-no-pr` パターンが追加されている
- <!-- verify: file_contains "modules/orchestration-fallbacks.md" "code-completed-no-pr" --> `modules/orchestration-fallbacks.md` に `code-completed-no-pr` カタログ項目が追加されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の code-completed-no-pr エントリに、worktree 内の commit を main へ rebase → branch を push → PR を作成 → review 継続、というリカバリ手順が記述されている" --> カタログ項目に rebase + push + create PR の recovery 手順が含まれている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## code-completed-no-pr" "rebase" --> `## code-completed-no-pr` セクションに `rebase` 手順が含まれている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "## code-completed-no-pr" "push" --> `## code-completed-no-pr` セクションに `push` 手順が含まれている
- <!-- verify: file_contains "tests/detect-wrapper-anomaly.bats" "code-completed-no-pr" --> `tests/detect-wrapper-anomaly.bats` に `code-completed-no-pr` パターン検出のテストが追加されている

### Post-merge

- Issue #385 と同様の watchdog 1800s timeout + 実装完了 + PR 未作成シナリオで `detect-wrapper-anomaly.sh` が non-empty 出力（`code-completed-no-pr`）を返し、Tier 2 catalog 経路に乗ることを確認する <!-- verify-type: manual -->

## Notes

### 検出 signature の選定（Issue body Auto-Resolved 1 から委任）

`'"matches_expected":false'` AND `'"phase":"code-pr"'` の組み合わせを採用。

`reconcile-phase-state.sh` の `_completion_code_pr()` は唯一 PR 不在ケース（`gh pr list --head "worktree-code+issue-N"` 結果が 0 件）でのみ `matches_expected:false` を返し、JSON に `"phase":"code-pr"` が含まれる。`run-code.sh` が EXIT_CODE=143 のみで reconcile を呼ぶ前提と組み合わせることで、PR 不在シナリオを confidently 識別できる。

不採用案: `"no open PR found"` などの diagnosis 文字列を grep する形は `reconcile-phase-state.sh` の implementation detail（メッセージ文言）に依存するため、シグネチャ安定性が低い。`'"phase":"code-pr"'` は schema-level の安定識別子で長期安定性が高い。

### `watchdog-kill` パターンとの優先順位

`code-completed-no-pr` を `watchdog-kill`（`grep -q "watchdog: kill and state not reached"`）より前に挿入する。本パターンが対象とするシナリオでは watchdog kill 後に `run-code.sh` 内で reconcile も実行されるため、log には両方のシグネチャが含まれる。first-match-wins 仕様に沿って、より specific な `code-completed-no-pr` を先に判定する。Issue body Auto-Resolved 2 で合意済み。

### `run-code.sh` への echo 追加が前提となる理由

現状 `_reconcile_out=$(...)` は variable 代入のみで stdout に出力されない（166 行目で grep -q への pipe のみ）。Tier 2 (`detect-wrapper-anomaly.sh`) は LOG_FILE のみを参照する設計のため、reconcile 結果が log に echo されない限り検出が成立しない。#394（`reconciler-header-mismatch`）で `run-review.sh` に同様の echo を追加した前例（`modules/orchestration-fallbacks.md#reconciler-header-mismatch` Rationale 参照）に倣い、`run-code.sh` でも echo を追加する。

Acceptance Criteria には追加せず Implementation Steps と本 Notes でのみ明記する（#394 spec の前例に揃える）。`run-code.sh` 変更は `code-completed-no-pr` 検出の必要条件であり、bats テストが PASS することで間接的に検証される。

### 既存パターンとの衝突回避

- `silent-no-op` は EXIT_CODE=0 + 完了 signature + commit 不在を検出する。本パターンは EXIT_CODE=143 で trigger されるシナリオを想定するが、検出条件自体は EXIT_CODE に依存しない（log の reconcile signature のみ）。よって衝突しない。
- `reconciler-header-mismatch` は `'"matches_expected":false'` + `'Review Summary'` を grep する。本パターンは `'"phase":"code-pr"'` を要求するため、review phase の log では一致しない。衝突しない。

### light SPEC_DEPTH の件数制限

Pre-merge verification 6 件は light の 5 件制限を超えるが、`/issue` refinement で `rubric` の補助として `section_contains` を 2 件追加した結果であり、合意済み。`rubric` (意味的検証) と `section_contains` × 2 (構造的補助) は独立した役割を持つためグルーピングは適用しない。

### bats test mock 不要

`code-completed-no-pr` 検出は LOG_FILE grep のみ。`silent-no-op` のような外部状態確認（git log 実行）を伴わないため、bats テストでの git/gh mock は不要。`reconciler-header-mismatch` のテスト構造（`printf '"matches_expected":false\n...\n' > "$LOG_FILE"`）に倣う。

### `--phase` 制約なし（Issue body Auto-Resolved 3）

新パターンの実装で `--phase` を制約条件に含めない。呼び出し側（`run-auto-sub.sh`）が phase=code 時にのみ呼ぶ前提。これは `dirty-working-tree`（verify phase 専用シグネチャだが phase 制約なし）の前例に揃える。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance Criteria 6 件すべてに verify command が付与されており、自動検証可能な条件設計だった。`rubric` （意味的検証）+ `section_contains` × 2（構造補助）の組み合わせはカバレッジとして適切。Spec Notes に 6 件制限超過の明示的合意記録あり（透明性高い）。

#### design
- Spec の実装ステップ 1〜4 が diff と完全整合。Changed Files と実装方針の記述粒度が高く、コード phase での判断余地がほぼ不要だった。

#### code
- Rework なし、design deviation なし。`_reconcile_out` echo の追加が検出の前提条件であることが Spec Notes で明記されており、bats テストで間接検証する設計も機能した。

#### review
- review-light 全4観点で問題検出ゼロ。CI 全ジョブ SUCCESS。レビューコメントなし。PR #422 のレビューは効率的だった。

#### merge
- クリーンな FF merge（a043d3a）。コンフリクトなし。

#### verify
- Pre-merge 6 件すべて PASS。verify command に不整合・曖昧さなし。Post-merge manual 条件（watchdog 再現シナリオ）は未チェックのまま残存（phase/verify 移行済み）。

### Improvement Proposals
- N/A

## Code Retrospective

### Deviations from Design

- なし。実装ステップ 1〜4 をすべて Spec どおりに実行した。

### Design Gaps/Ambiguities

- `scripts/run-code.sh` の `_reconcile_out` echo は `exit 143` 判定ブロック内にのみ存在するため、正常終了・他エラー終了では log に出力されない。これは Spec の意図通り（Tier 2 は EXIT_CODE=143 のみを対象とする前提）であり、設計ギャップではない。

### Rework

- なし。

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- なし。Spec の実装ステップ 1〜4 はすべて diff と完全に整合していた。Code Retrospective でも「Deviations from Design: なし」が記録されており、Spec 品質は高い。

### Recurring Issues

- なし。review-light 全4観点で確認済みの問題はゼロ件。パターン重複も見られない。

### Acceptance Criteria Verification Difficulty

- `rubric` 条件（AC3）はルーブリック判定を要するが、Fallback Steps の記述が明確であり AI 判定で PASS を確定できた。UNCERTAIN は発生しなかった。
- `section_contains` （AC4、AC5）は diff から直接確認可能で、verify command の品質は高い。
- 全 6 件の pre-merge 条件がすべて PASS。verify command の精度に問題なし。
