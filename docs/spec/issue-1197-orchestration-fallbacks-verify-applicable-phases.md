# Issue #1197: orchestration-fallbacks: ff-only-merge-fallback の Applicable Phases に verify を追加

## Overview

`modules/orchestration-fallbacks.md` の `#ff-only-merge-fallback` エントリの `### Applicable Phases` に verify が抜けていた。`skills/verify/SKILL.md` Step 2 が `git checkout "$BASE_BRANCH"` を実行するため、Worktree Exit (Step 13) 時点で `current_branch == BASE_BRANCH` が確定的に成立し、verify は必ず true 側の経路 (fallback Step 2) に入る。実測でも `docs/reports/orchestration-recoveries.md` の `manual-recovery-worktree-rebase` 4件中3件が verify フェーズで発生している。

Size XS のため事前調査を伴わず直接修正した。Spec 前提条件チェックは対象外 (XS は Spec 不要)。

## Changed Files

- `modules/orchestration-fallbacks.md`: `ff-only-merge-fallback` の Applicable Phases に verify を追加 (確定的に true 側を通る根拠と `git checkout` への言及を含む)。他エントリの Applicable Phases と実装呼び出し元の突き合わせで見つかった追加の漏れ2件を修正 (下記 Implementation Steps 参照)

## Implementation Steps

1. `#ff-only-merge-fallback` の Applicable Phases に verify を追加し、Step 2 の `git checkout "$BASE_BRANCH"` により true 側経路が確定的に成立する旨を注記する。(→ 受入条件 AC1, AC2, AC3)
2. 他エントリの Applicable Phases と実際の呼び出し元 (`modules/worktree-lifecycle.md` の Direct Callers 表、各 SKILL.md、`scripts/detect-wrapper-anomaly.sh`) を突き合わせ、見つかった漏れを修正する。(→ 受入条件 AC4)

## Cross-Entry Audit (AC4)

`modules/orchestration-fallbacks.md` の全17エントリの `### Applicable Phases` を、対応する SKILL.md の実装内容および `scripts/detect-wrapper-anomaly.sh` の検出パターンと突き合わせた。

### 修正した漏れ (2件)

- **`dco-signoff-missing-autofix`**: 現行は `code` / `merge` のみを列挙していたが、`skills/spec/SKILL.md` / `skills/review/SKILL.md` / `skills/verify/SKILL.md` も同一の `git commit -s` + `ERROR: missing sign-off` ガードを持つ (grep で確認済み)。`scripts/detect-wrapper-anomaly.sh` の `ERROR: missing sign-off` マッチはフェーズ非依存のため、spec/review/verify でも同一パターンで検出されうる。spec, review, verify を追加した。
- **`code-patch-silent-no-op`**: 現行は `code (patch route)` のみを列挙していたが、エントリ本文の `### Exception Condition` セクション自体が merge フェーズ (`_merge_pr_confirmed_merged`) と review フェーズ (`_review_confirmed_posted`) 専用の live check を明記しており、これは `detect-wrapper-anomaly.sh` の `silent-no-op` 判定 (`EXIT_CODE == 0` 分岐、フェーズ非依存) が merge/review でも誤発火しうることに対する回避策として存在する。merge, review を追加した。

### 追加漏れなしと判断したエントリ

`dirty-working-tree` (verify 限定、妥当) / `reconciler-header-mismatch` (review 限定、妥当) / `review-completion-false-negative` (review 限定、妥当) / `code-completed-no-pr` (code PR route 限定、妥当) / `mid-run-api-error` (`run-*.sh` 全般を明記済み) / `code-base-conflict` (code PR route 限定、妥当) / `async-external-commit` (code patch route の `_completion_code_patch` 固有ロジック、妥当) / `json-mode-silent-hang` (`run-*.sh` 全般を明記済み) / `baseline-failure` (`run-merge.sh` 固有ゲート、妥当) / `wrapper-retry-on-kill` (呼び出し元スクリプトを明記済み) / `external-kill-parent-respawn` (`run-*.sh` 全般を明記済み) / `review-pending-not-failure` (review 限定、妥当) / `manual-recovery-spec-write` (code/review/merge を明記済み) は、実装呼び出し元との突き合わせで追加の漏れは見つからなかった。

### 対象外とした観察事項 (out of scope)

`ff-only-merge-fallback` と `conflict-marker-residual` の Applicable Phases が列挙する `merge` について、`/merge` (`skills/merge/SKILL.md`) の現行実装は `scripts/worktree-merge-push.sh` を経由せず、Step 4 で直接 `git merge origin/main --ff-only` + `git push origin HEAD:main` を行っている (`scripts/run-merge.sh` も同スクリプトを呼び出していない)。`merge` エントリの記載が現行実装とずれている可能性があるが、この裏取りには `worktree-merge-push.sh` の呼び出し履歴の追加調査を要し、本 Issue (XS, verify 追加が主目的) のスコープを超えるため、本 Issue では変更しない。将来 `ff-only-merge-fallback` / `conflict-marker-residual` を変更する際に併せて確認することを推奨する。

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "Applicable Phases" "verify" --> `ff-only-merge-fallback` の Applicable Phases に verify が含まれている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の ff-only-merge-fallback の Applicable Phases に、verify が Step 2 の base branch checkout により true 側経路を確定的に通ることの注記がある" --> verify が確定的に true 側を通る理由が注記されている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "Applicable Phases" "checkout" --> `ff-only-merge-fallback` の Applicable Phases セクションに checkout への言及がある
- <!-- verify: rubric "ff-only-merge-fallback 以外の orchestration-fallbacks.md の各エントリについても Applicable Phases と実際の呼び出し元の突き合わせが行われ、追加の漏れがあれば修正されているか、漏れがない旨が Spec に記録されている" --> 他エントリの突き合わせが行われている (本 Spec の `## Cross-Entry Audit (AC4)` 参照)

### Post-merge

- 次回 verify フェーズで `ff-only-merge-fallback` を踏んだ際、`Applicable Phases` を参照した実行者が verify を対象として認識できることを確認する <!-- verify-type: opportunistic -->

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — Spec がなかったため、本 Spec は `/code` 内で新規作成した (Issue 本文の Proposal をそのまま Implementation Steps に落とし込んだため設計からの逸脱はない)

### Design Gaps/Ambiguities
- AC4 の「漏れがあれば修正されているか、漏れがない旨が Spec に記録されている」という文言は「Spec」への記録を要求しているが、Size XS の `/code` は Spec 前提条件チェック自体をスキップする (Spec 不要) ため、当初は Spec が存在しない状態だった。AC4 を機械的に満たすため、実装の一部として本 Spec ファイルを新規作成し `## Cross-Entry Audit (AC4)` セクションに記録する判断をした

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 他エントリの突き合わせ (AC4) で `dco-signoff-missing-autofix` (spec/review/verify 未列挙) と `code-patch-silent-no-op` (merge/review 未列挙) の2件の追加漏れを発見し、本 Issue の主目的 (ff-only-merge-fallback への verify 追加) と同一パターンのため合わせて修正した
- `ff-only-merge-fallback` / `conflict-marker-residual` の Applicable Phases が列挙する `merge` については、現行の `/merge` 実装 (`scripts/worktree-merge-push.sh` を経由しない直接 `git push`) との整合性に疑義があるが、追加調査を要するため本 Issue のスコープ外とした (Spec の "対象外とした観察事項" 参照)

### Deferred Items
- `ff-only-merge-fallback` / `conflict-marker-residual` の `merge` 記載の妥当性再調査 (Spec の "対象外とした観察事項" に記録済み。着手する場合は新規 Issue 起票を推奨)

### Notes for Next Phase
- verify フェーズでは Post-merge AC (`verify-type: opportunistic`) のみが残っている — 次回 `ff-only-merge-fallback` 発生時に `Applicable Phases` から verify が認識できるかを確認する運用チェック

## Issue Retrospective

### Acceptance Criteria の変更理由

- AC1 (`section_contains "modules/orchestration-fallbacks.md" "### Applicable Phases" "verify"`) の heading 引数から先頭の `###` を除去した。`section_contains` はファイル側の見出し行から `#`/空白を除去したうえで部分一致するため、引数側に `###` を残すと本文中のどの `### Applicable Phases` 見出しにも一致せず恒久的に UNCERTAIN になる (triage AC 監査で検出、`modules/verify-executor.md` § `section_contains` 仕様および `skills/triage/skill-dev-verify-audit.md` Pattern 6.1 準拠)。`modules/orchestration-fallbacks.md` には同名の `### Applicable Phases` 見出しが約 18 箇所あるが、`section_contains` は文書順で最初に一致した見出しを対象とするため、修正後も `ff-only-merge-fallback` エントリ (文書内で最初に出現) を正しく対象化できる。
- AC2 (rubric: verify が確定的に true 側を通る理由の注記) に、機械的補助チェックとして `<!-- verify: section_contains "modules/orchestration-fallbacks.md" "Applicable Phases" "checkout" -->` を追加した。実装が加える注記文には Background で述べている `git checkout` の技術的根拠が含まれる見込みが高く、rubric 単独より判定精度が上がるため (`modules/verify-patterns.md` §9 の rubric + 補助チェック指針に準拠)。

### 曖昧ポイント

Background/Purpose/Proposal (Outline) が十分に具体的で、曖昧ポイントの抽出・自動解決は発生しなかった。

### Type/Size/Value 判定根拠

- Type: Task (ドキュメント記載漏れの修正、コード挙動変更なし)
- Size: XS (`modules/orchestration-fallbacks.md` 1 ファイルの変更、ドキュメントのみ)
- Value: 3 (Impact=2: `modules/orchestration-fallbacks.md` は複数 Skill から参照される共有モジュール、Alignment=3: verify/orchestration の正確性はプロジェクトの中核である governance-and-verification harness の Vision に直接関わる)
