# Issue #465: run-code exit-0 reconcile silent failure detection

## Overview

`run-code.sh` was calling `reconcile-phase-state.sh --check-completion` only on watchdog timeout (exit code 143). By also calling it on normal exit (exit code 0), silent failures — where the code skill returns exit 0 without actually implementing anything (misrouted dispatch, ignored errors, etc.) — can be detected early in the `/auto` pipeline. When `matches_expected: false`, the wrapper exits 1 and feeds into the existing 3-tier recovery in `/auto` Step 6.

Implementation was completed as part of #520 (PR #525) and all pre-merge ACs are already satisfied.

## Changed Files

- `scripts/run-code.sh`: extend reconcile condition from `EXIT_CODE -eq 143` to `EXIT_CODE -eq 143 || EXIT_CODE -eq 0`; on exit-0 with `matches_expected: false`, emit stderr warning and set `EXIT_CODE=1` — bash 3.2+ compatible
- `tests/run-code.bats`: add three reconcile tests — exit 0 + `matches_expected:false` → exit 1; exit 0 + `matches_expected:true` → exit 0; exit 0 + empty reconcile output → exit 0 (no false alarm)

## Implementation Steps

1. In `scripts/run-code.sh`, change the reconcile trigger condition from `EXIT_CODE -eq 143` to `EXIT_CODE -eq 143 || EXIT_CODE -eq 0` so `reconcile-phase-state.sh --check-completion` is called on any non-error exit (→ AC1, AC2)
2. Add an `elif` branch: when `EXIT_CODE -eq 0` and reconcile output contains `"matches_expected":false`, emit a stderr warning and set `EXIT_CODE=1` — enabling the `/auto` 3-tier recovery (→ AC3, AC4)
3. Add bats tests in `tests/run-code.bats` covering the three exit-0 reconcile scenarios (→ AC5)

Note: All three steps are already implemented in #520 (PR #525). The `/code` phase should verify the existing implementation satisfies all ACs.

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-code.sh" "--check-completion" --> `run-code.sh` が `reconcile-phase-state.sh --check-completion` を呼び出す
- <!-- verify: grep "EXIT_CODE -eq 0" "scripts/run-code.sh" --> exit 0 時も reconcile の条件分岐に含まれている
- <!-- verify: grep "matches_expected" "scripts/run-code.sh" --> `matches_expected: false` 時の処理が存在する
- <!-- verify: grep "EXIT_CODE=1" "scripts/run-code.sh" --> silent failure 時に exit 1 を返す
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テストが green（`tests/run-code.bats` の exit-0 reconcile テストを含む）

### Post-merge

- `/auto` 実行で silent no-op（exit 0 だが実装なし）が自動検出され、3-tier recovery へ流れることを実運用でモニタする

## Notes

- 実装は #520（PR #525）で完了済み。`scripts/run-code.sh` L187–L198 および `tests/run-code.bats` L392–L428 が対象コード
- スコープは `run-code.sh` のみ（タイトルに明記）。他スクリプト（`run-spec.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh`）は #520 で別途対応済み
- `matches_expected: false` 時の exit code は exit 1 に確定（`/auto` 3-tier recovery フローへ接続するために必要）
- Exit 0 + empty reconcile output は false alarm を避けるため exit 0 のまま維持（AC4 の `grep "EXIT_CODE=1"` は `elif` ブランチの存在チェックであり、空出力ケースを排除するものではない）

## Code Retrospective

### Deviations from Design
- None — implementation was already complete in #520 (PR #525) before this `/code` phase ran; the code phase served as a verification-only pass confirming all five ACs pass

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- No code changes made; existing implementation in `scripts/run-code.sh` (L187–L196) and `tests/run-code.bats` (L392–L428) already satisfies all pre-merge ACs
- All 26 bats tests pass including the three reconcile scenario tests (exit 0 + matches_expected:false → exit 1; exit 0 + matches_expected:true → exit 0; exit 0 + empty output → exit 0)
- CI (test.yml) latest run concluded `success`

### Deferred Items
- Post-merge operational monitoring: verify that silent no-op (exit 0 without implementation) is auto-detected in real `/auto` runs and flows into 3-tier recovery

### Notes for Next Phase
- Implementation is already merged on `main` via #520; this patch route commit only adds the Spec Code Retrospective and Phase Handoff
- No known risks or residual issues; all ACs verified in full mode locally and via CI

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec  | patch | SUCCESS | Spec 作成 (#520 で実装済の追認 retro) |
| code  | patch | FAILED (silent no-op, manually accepted) | run-code.sh exit 1 (`silent no-op` 検出)、Tier 3 abort。AC は既に #520 マージで満たされていたため追加実装不要 |
| verify | -    | SUCCESS | Pre-merge 全 5 件 PASS、Post-merge manual SKIPPED |

### Orchestration Anomalies
- **silent no-op false-positive (predecessor merge)**: code phase Claude が #520 のマージ後の scripts/run-code.sh 状態を確認し AC が満たされていることを認識して no commit。wrapper `reconcile-phase-state.sh` が `commits_found: false` として記録し exit 1。Tier 3 sub-agent も "Human review needed" として abort。
- 根本原因: #520/#525 で先行実装済みという文脈が orchestration 層に伝達されない設計ギャップ（#490 と同パターン）。

### Improvement Proposals
- N/A (人手の状況判断で正しく no-op になったため。dependency-aware skip ルールは過剰最適化リスクがある)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 5 つの AC (file_contains + 3 grep + github_check CI) で関数レベル + 統合レベル両方カバーする実装網羅性が高い設計。

#### design
- "#520 で実装済み" を Issue 本文に明記する設計 (Note セクション) は良い実践。ただし orchestration が読み取れない問題は #490 と共通。

#### code
- 既に main にマージ済みのため code phase は本来不要だった。/auto 上の orchestration は文脈非対応で実装範囲を誤判定。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。

#### verify
- Pre-merge 全 5 件 PASS (実装の網羅性が確認できる)。Post-merge manual は実運用観察待ちで `phase/verify` 維持。

### Improvement Proposals
- See Auto Retrospective (silent no-op false-positive pattern, #490 と共通)

### 2026-08-09 re-run (observation 条件の評価)

`/auto --batch 1280 1282 1283 1281` (session `97764-1786198856`) の end-of-batch observation scan で `event=auto-run` が発火し、post-merge 条件が初めて評価対象になった。

#### verify (再実行分)

- 条件 6 は **UNCERTAIN**。条件文が 2 つの主張の連言 (「自動検出され」+「3-tier recovery へ流れる」) で、前半のみ実証された
- **前半は実運用で確証**: #1280 の code-patch フェーズで `code_retry_fire` (`trigger_reason=silent_no_op`, 2026-08-08T15:01:56Z) が発火。このイベントは `scripts/run-code.sh:299-311` の分岐からのみ emit されるため、exit 0 の `claude` に対し `--check-completion` が走り `matches_expected:false` を検出したことの直接証拠になる。本 Issue が実装した経路そのもの
- **後半は未観測**: 同 session に recovery / tier / manual_intervention 系イベントはゼロ。#1280 はリトライ 1 回目で着地した (`wrapper_exit exit_code=0` @ 15:19:22)
- フォールバック経路自体は健在 (`run-code.sh:326` の `EXIT_CODE=1`、`run-auto-sub.sh:747-791` の Tier 1/2/3)。実行されなかっただけ

#### Improvement Proposals (再実行分)

- **後段機構の追加により、先行 Issue の observation 条件が到達不能になるパターン** — 本 Issue の起票時 (2026-05) には `auto-retry-on-fail` の in-phase retry 層が存在せず、silent no-op 検出 → `EXIT_CODE=1` → 3-tier が唯一の経路だった。その後 retry 層が**前段に**挿入された結果、`autonomy: L3` + `auto-retry-on-fail.enabled: true` の構成では条件文後半が通常到達しなくなった。observation 条件は「実装当時の制御フロー」を前提に書かれるため、後から前段に層が挿入されると silent に評価不能化する。この失効は AC 側にも変更履歴にも痕跡が残らない点が問題。新機構が既存経路の前段に入る変更 (`/spec` や `/code`) の際に、`phase/verify` 滞留中の Issue の observation 条件への影響を確認する step があると検知できる。ただし本提案は変更対象が単一 skill に絞れず、`/verify` 側の実査 (#1270 系) で個別に拾う運用でも吸収できるため Tier 2 とし、起票せずここに記録する

## Consumed Comments
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/465#issuecomment-4703427504
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/465#issuecomment-5225312519
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/465#issuecomment-5227687875
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/465#issuecomment-5229257098
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=4 / https://github.com/saitoco/wholework/issues/465#issuecomment-5235399068
