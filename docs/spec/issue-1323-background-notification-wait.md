# Issue #1323: detect-wrapper-anomaly: background task 完了通知待ちによる silent no-op を Tier 2 signature に追加

## Overview

`scripts/detect-wrapper-anomaly.sh` に「background task 完了通知待ちによる silent no-op」の signature がなく、5 回再発しても Tier 2 (`/auto` Step 6 の Known-pattern 検出) が一度も検出できていない。原因は 2 つ:

- (a) 成功主張フレーズのリスト (`完了しました|commit and push|...`) に「待機宣言」フレーズ (`完了通知` / `を待ちます` 等) が含まれていない
- (b) silent-no-op 分岐全体が `EXIT_CODE == "0"` のガード配下にあるが、`run-*.sh` wrapper は検出した silent no-op を非ゼロ exit (実測: 1) に変換して返すため、`/auto` Step 6 が `detect-wrapper-anomaly.sh` を呼ぶ時点では常に非ゼロ exit であり、このガードに到達しない

本 Issue は検出 (安全網) のみを扱う。新しい `elif` 分岐を `EXIT_CODE` に依存しない位置に追加し、`/auto` が Tier 3 診断を経ずに正しい復旧手順 (phase の 1 回リトライ) へ直行できるようにする。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `background-notification-wait` パターン分岐を新規追加する (新規の最上位 `elif`。`EXIT_CODE == "0"` ゲートの外に置く) — bash 3.2+ 互換 (新規 bashism なし。ファイル内で既に使われている `grep -qiE` / `_phase_retry_hint` パターンを再利用)
- `modules/orchestration-fallbacks.md`: `## background-notification-wait` カタログエントリを新規追加する (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale)
- `tests/detect-wrapper-anomaly.bats`: 回帰テストを追加する — (1) positive: #1130 実測ログ形状の再現 (待機宣言フレーズ + `"matches_expected":false` + exit code 1)、(2) negative: `matches_expected:false` 単独、(3) negative: 待機宣言フレーズ単独

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` に `background-notification-wait` パターン分岐を追加する (→ Pre-merge AC 1, 4)
   - 挿入位置: `review-completion-false-negative` ブロックの閉じ `fi` の直後、`elif grep -qiE "APIConnectionError|Request timed out|overloaded_error|529.*[Oo]verload" "$LOG_FILE"; then` (`mid-run-api-error` パターン) の直前
   - 条件: `grep -q '"matches_expected":false' "$LOG_FILE" && grep -qiE "完了通知|を待ちます|待っています|waiting for .*(notification|completion)" "$LOG_FILE"`
   - `PATTERN_NAME="background-notification-wait"`
   - `IMPROVEMENT_HINT` は既存の `_phase_retry_hint "$PHASE" "$ISSUE_NUMBER"` ヘルパーを再利用しつつ、`run-auto-sub.sh --write-manual-recovery ISSUE PHASE respawn [EXIT_CODE] --cause background-notification-wait` での記録手順を明記する (Issue 対応方針 (案) 1. の指示どおり)
2. `modules/orchestration-fallbacks.md` に `## background-notification-wait` カタログエントリを追加する (→ Pre-merge AC 2)
   - 挿入位置: `## manual-recovery-spec-write` エントリの直後 (`## Operational Notes` の直前)、既存の `---` 区切り規約に従う
   - Fallback Steps に `run-auto-sub.sh --write-manual-recovery ... --cause background-notification-wait` の呼び出しを含める (`#manual-recovery-spec-write` の呼び出し規約を参照)
3. `tests/detect-wrapper-anomaly.bats` に回帰テストを追加する (→ Pre-merge AC 3)
   - positive test: `--exit-code 1` で実測ログ形状 (待機宣言フレーズ行 + `"matches_expected":false` を含む JSON 断片行) を再現し、出力に `background-notification-wait` / `### Orchestration Anomalies` / `### Improvement Proposals` が含まれることを確認する
   - negative test ×2: `matches_expected:false` のみ / 待機宣言フレーズのみでは検出されないことを確認する (既存の `code completed no PR: no detection when only ...` テストと同じ形式)

## Verification

### Pre-merge

- <!-- verify: grep "background-notification-wait" "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` が `background-notification-wait` パターンを報告する
- <!-- verify: grep "background-notification-wait" "modules/orchestration-fallbacks.md" --> `modules/orchestration-fallbacks.md` に同名のカタログエントリがある
- <!-- verify: grep "background-notification-wait" "tests/detect-wrapper-anomaly.bats" --> 実測ログ形状に対する回帰テストが追加されている
- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh の background-notification-wait 判定が EXIT_CODE == 0 のガード配下に置かれておらず、wrapper が silent no-op を exit 1 に変換したケースでも到達可能な位置にある" --> wrapper が exit 1 に変換した場合でも検出される (上記 (b) の解消)

### Post-merge

- 次に background task 完了通知待ちが発生した `/auto` 実行で、Tier 2 が `background-notification-wait` を報告し Tier 3 へ回らないことを確認する

## Notes

- **Issue 本文の行番号ドリフト (Step 6 conflict detection)**: Issue 本文 Background は `scripts/detect-wrapper-anomaly.sh:129` (成功主張フレーズ grep) と `:108` (`EXIT_CODE == 0` ゲート) を引用しているが、コミット `c3fbbb2e` 以降の現在のコードでは同じ構造がそれぞれ `:165` (`elif grep -qiE "完了しました|commit and push|successfully committed|pushed to|changes have been committed" "$LOG_FILE"; then`) と `:144` (`elif [[ "$EXIT_CODE" == "0" ]]; then`) に位置している。引用対象のロジック自体 ((a) 成功主張リストに待機宣言が含まれない / (b) silent-no-op 分岐全体が `EXIT_CODE == 0` でゲートされている) は現在も同一のため Issue の要求は有効。実装時は現物の行番号 (:165 / :144 付近) を基準にすること。この既存実装との差分は Issue Retrospective コメントで既に指摘済み。
- **`apply-fallback.sh` はスコープ外**: `run-auto-sub.sh` の bash-only ladder (`run_phase_with_recovery()`) が使う Tier 2 (`scripts/apply-fallback.sh`, handlers: `dco-signoff-missing-autofix` / `code-patch-silent-no-op` / `json-mode-silent-hang`) は `detect-wrapper-anomaly.sh` を一切呼ばない別実装であり、本 Issue の対象外。本 Issue が変更する `detect-wrapper-anomaly.sh` は `skills/auto/SKILL.md` Step 6 「Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog」(実際の `$EXIT_CODE` を渡して呼び出す LLM 駆動パス、Step 6 内 `${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh --log ... --exit-code $EXIT_CODE ...`) から消費される。
- **allowed-tools impact chain check**: `modules/orchestration-fallbacks.md` の reader は `skills/auto/SKILL.md` と `skills/verify/SKILL.md` の 2 件 (`grep -rl "modules/orchestration-fallbacks\.md" skills/*/SKILL.md` で確認)。新カタログエントリが参照する `run-auto-sub.sh` はいずれの allowed-tools にも `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` として既に含まれているため (新規スクリプトではなく、同モジュール内の既存エントリで既に使われている呼び出しパターンの再利用)、追加変更は不要。
- **bats テストの入力データ形式**: 新規 positive test の `$LOG_FILE` fixture は `printf` で実測ログ形状 (session `16210-1786327272`、#1130 spec phase) を再現する: (1) 待機宣言フレーズを含む行 (例: `バックグラウンドの bats スイート完了通知、またはフォールバックの wakeup (約20分後) を待ちます。`)、(2) `"matches_expected":false` を含む JSON 断片行、(3) `--exit-code 1` を渡す (実測値と一致)。negative test 2 件はそれぞれ (1)(2) の条件を単独で持たせ、他方を欠落させることで false positive がないことを確認する。
- **新分岐の優先順位**: 新 `elif` を `code-completed-no-pr` / `reconciler-header-mismatch` / `review-silent-no-op` 系 (いずれも `matches_expected:false` ゲート) より後に置くことで、より特化した既存診断 (review phase の実 API 確認など) を優先させつつ、それらがカバーしない phase (spec 等) や条件不一致のケースを本パターンで拾う。

## Consumed Comments

No new comments since last phase. (直近の `phase/spec` ラベル付与後に投稿された Issue コメント 2 件は `/issue` フェーズ自身が Step 13 で残した Issue Retrospective であり、上記「行番号ドリフト」の指摘はその内容を踏まえて本 Spec の Notes に反映済み。)

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1323#issuecomment-5249462422
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1323#issuecomment-5249505809
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1323#issuecomment-5296393325
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1323#issuecomment-5304278450
- saito / MEMBER / first-class / <!-- wholework-event: type=batch-verify-dispatch phase=audit issue=1323 --> / https://github.com/saitoco/wholework/issues/1323#issuecomment-5306107966
## Code Retrospective

### Deviations from Design

- N/A (Implementation Steps 1-3 をそのまま実施。挿入位置・条件式・パターン名は Spec 記載どおり)

### Design Gaps/Ambiguities

- N/A

### Rework

- Implementation Step ごとに個別コミットしていたが (3 コミット)、いずれのコミット subject にも `#1323` が含まれておらず、`skills/code/SKILL.md` Step 11 が要求する「BASE_BRANCH が main の場合、実装コミット自体に `closes #N` を含める (Issue #996 の `concurrent_commit_detected` false-positive 再発防止)」を満たしていなかった。3 コミットは未 push のローカル worktree ブランチ上のみに存在したため、`git reset --soft` で 1 コミットにまとめ直し、`(closes #1323)` を含む commit subject で再コミットした。今後 patch route で複数ステップに分けてコミットする場合、少なくとも最終コミット (または全コミットのいずれか) の subject に `#N` を含めることを意識する。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 新 `elif` 分岐は `review-completion-false-negative` ブロックの `fi` 直後・`mid-run-api-error` の直前に配置し、Spec 指定どおり `EXIT_CODE == "0"` ガードの外に置いた (AC4 rubric の要求を満たす)
- 条件式は `matches_expected:false` と待機宣言フレーズ (`完了通知|を待ちます|待っています|waiting for .*(notification|completion)`) の AND とし、phase 非依存にした
- IMPROVEMENT_HINT は既存の `_phase_retry_hint()` ヘルパーを再利用しつつ、`run-auto-sub.sh --write-manual-recovery ... --cause background-notification-wait` の記録手順を明記した

### Deferred Items
- Post-merge AC (次に background task 完了通知待ちが発生した `/auto` 実行での実地確認、`verify-type: observation event=auto-run session=next`) は `/verify` フェーズで評価される

### Notes for Next Phase
- Behavioral Change Detection により `modules/orchestration-fallbacks.md` が `tests/run-code.bats` / `tests/run-auto-sub.bats` / `tests/orchestration-fallbacks.bats` から参照されているため、フルスイートを `bats --jobs 18 tests/` で実行済み (1748 件 全 PASS)
- 4 件の Pre-merge AC は grep 3 件 + rubric 1 件で全て PASS 済み。Issue 側チェックボックスも `[x]` 済み
