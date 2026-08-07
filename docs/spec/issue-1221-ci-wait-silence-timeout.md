# Issue #1221: detect-wrapper-anomaly: CI 待機中の沈黙を json-mode-silent-hang と誤診断する経路を切り分ける

## Overview

`scripts/detect-wrapper-anomaly.sh` の `json-mode-silent-hang` 判定は、wrapper ログに `watchdog: still waiting (json mode)` という文字列が含まれるかだけを見る単純 grep であり、沈黙の理由 (セッション初期化ストール vs CI 待機由来) を区別できない。検出器に `.tmp/auto-events.jsonl` の `ci_wait` イベントを判定材料として渡せるようにし、CI 待機由来の沈黙を `ci-wait-silence-timeout` という独立パターンとして切り出す。復旧手順は即リトライではなく CI 状態の確認を先行させる。呼び出し元 (`skills/auto/SKILL.md` Tier 2) の配線更新も本 Issue のスコープに含む。

## Reproduction Steps

1. `/auto` が review フェーズ (PR route) を起動し、`run-review.sh` が `wait-ci-checks.sh` で CI 待機に入る。CI ポーリングが完了/内部タイムアウトすると `.tmp/auto-events.jsonl` に `ci_wait` イベントが emit される (`scripts/wait-ci-checks.sh:96`)
2. その後の review セッション (`claude -p` json mode) 自体は稼働を続ける (PR へのレビュー投稿、修正コミット push 等) が、外部 CI インフラが同時に障害中の場合、CI 確定までの待ち時間が長引き、raw stdout の出力間隔が `watchdog-timeout-review-seconds` (設定値、例: 5400s) を超える
3. `scripts/claude-watchdog.sh` が沈黙を検知して SIGTERM を送信 (exit 143) し、wrapper ログに `watchdog: still waiting (json mode), silent for <N>s` を記録する
4. `/auto` の Tier 2 復旧 (`skills/auto/SKILL.md` #### Tier 2) が `detect-wrapper-anomaly.sh --log ... --exit-code 143 ...` を実行すると、`still waiting (json mode)` の単純一致により `json-mode-silent-hang` と判定される — 実際にはセッションが稼働中で CI 待機由来の沈黙であっても区別されない
5. 実測 (#1214, PR #1216, 2026-08-06): この誤判定により、カタログの「1 回リトライ」指示に従うと CI 障害が継続する間は同じ `ci_wait` に再突入し、再度 watchdog kill (このケースでは約 90 分 = 5400s) が発生し得る。実際には親セッションがカタログ指示に従わず、先に `gh pr checks` で CI 状態を確認し同一 SHA で re-run してから retry したため、2 回目は 1200s で正常完了した

## Root Cause

`scripts/detect-wrapper-anomaly.sh` の該当分岐 (line 74-77) は `EXIT_CODE == 143 AND grep "still waiting (json mode)"` のみで判定しており、この文字列は `claude-watchdog.sh` が出力する「still waiting」系ログ行すべてに共通して含まれるため、沈黙の理由 (セッション初期化ストール / CI 待機 / 長時間の内部処理) を一切区別できない。一方、`wait-ci-checks.sh` は CI ポーリング完了時に `.tmp/auto-events.jsonl` へ `ci_wait` イベント (issue/phase 付き) を既に emit している (`docs/reports/event-log-schema.md` §5) が、`detect-wrapper-anomaly.sh` にはこのイベントログを受け取る手段 (`--events` 引数) がなく、Tier 2 呼び出し元 (`skills/auto/SKILL.md`) もそれを渡していない。同種の課題は `detect-external-kill.sh` が `--events` 引数で既に解決済みで、本 Issue はその前例を `detect-wrapper-anomaly.sh` にも適用する。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: 新規オプション引数 `--events <path>` を追加 (必須引数には追加しない — 後方互換)。既存の exit 143 + `still waiting (json mode)` 分岐の内側で、events ログ中に当該 issue/phase の `ci_wait` イベントが存在するかを判定し、存在すれば新パターン `ci-wait-silence-timeout`、存在しなければ従来どおり `json-mode-silent-hang` を報告するよう分岐する — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `## json-mode-silent-hang` エントリの直後 (`## baseline-failure` の直前) に `## ci-wait-silence-timeout` カタログエントリを新規追加 (Symptom/Applicable Phases/Fallback Steps/Escalation/Rationale の既存スキーマに従う)
- `skills/auto/SKILL.md`: `#### Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog` セクション内の `detect-wrapper-anomaly.sh` 呼び出しに `--events .tmp/auto-events.jsonl` を追加 (同ファイル内 External kill pre-check セクションの `detect-external-kill.sh` 呼び出しが同じフラグを既に渡している前例に倣う)
- `tests/detect-wrapper-anomaly.bats`: `--events` 引数を用いた新パターンの検出/非検出 (3 ケース) を追加
- `docs/structure.md`: [Steering Docs sync candidate] `detect-wrapper-anomaly.sh` の一行説明 (223 行目) — grep 確認済み、汎用的な既存文言のままで正確なため変更不要

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` を変更する: 引数パーサに `--events` を追加 (`EVENTS_FILE` 変数、未指定時は空文字のまま — 必須引数チェックには加えない)。既存の `elif [[ "$EXIT_CODE" == "143" ]] && grep -q "still waiting (json mode)" "$LOG_FILE"; then` ブロックの内側で、`detect-external-kill.sh` (line 80-82) と同じ chained-grep イディオム (`grep -E "\"issue\":${ISSUE_NUMBER}[,}]" "$EVENTS_FILE" | grep '"event":"ci_wait"' | grep -q "\"phase\":\"${PHASE}\""`) を用いて、`-n "$EVENTS_FILE" && -f "$EVENTS_FILE"` の場合のみ当該 issue/phase の `ci_wait` イベント有無を判定する。一致した場合: `PATTERN_NAME="ci-wait-silence-timeout"`、`ANOMALY_DESC` に「`ci_wait` イベントが記録されており CI 待機中の沈黙と判明」の旨、`IMPROVEMENT_HINT` に `modules/orchestration-fallbacks.md#ci-wait-silence-timeout` への参照と「まず CI 状態を確認」の旨を設定する。不一致 (events ファイル未指定/存在しない/該当イベントなし) の場合: 既存の `PATTERN_NAME="json-mode-silent-hang"` 分岐を変更せず維持する。ファイル冒頭の Usage コメント (line 5) も `[--events <path>]` を追記して更新する。(→ 受入条件 1, 2, 5)
2. `modules/orchestration-fallbacks.md` に `## ci-wait-silence-timeout` エントリを `## json-mode-silent-hang` (line 351-377) の直後、`## baseline-failure` (line 379) の直前に挿入する。Symptom: exit 143 + `still waiting (json mode)` に加え `.tmp/auto-events.jsonl` に当該 issue/phase の `ci_wait` イベントが記録されている。Applicable Phases: `run-*.sh` 経由で CI 待機を行うフェーズ (review, merge)。Fallback Steps: (a) `gh pr checks` で現在の CI 状態を確認、(b) 失敗シグネチャが CI インフラ障害 (`steps: []` / `cancelled`+タイムアウト / runner エラー / ネットワークエラー — `skills/verify/SKILL.md` Step 5 「Verification priority」Step 1 の判定表を流用) に該当する場合、同一 SHA で CI を re-run、(c) CI が確定状態に達してからフェーズを retry。Escalation: re-run 後も CI が確定しない、またはインフラ障害シグネチャに該当しない場合は Tier 3 へ。Rationale: Issue #1221、実測ケース #1214/PR #1216 (2026-08-06、GitHub Actions 全体障害、即リトライでは無効、CI 確認優先で 1200s 完了) を参照。(→ 受入条件 4)
3. `skills/auto/SKILL.md` の `#### Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog` セクション (line 963 見出し直下、line 968) の `detect-wrapper-anomaly.sh` 呼び出しコマンドに `--events .tmp/auto-events.jsonl` を追加する。挿入位置は `--log ...` の直後、`--exit-code $EXIT_CODE` の直前 (同ファイル内 line 932 の `detect-external-kill.sh` 呼び出しと同じ引数順)。(after 1) (→ 受入条件 3)
4. `tests/detect-wrapper-anomaly.bats` に新規 `@test` を 3 件追加する: (a) 「ci wait silence: detects when ci_wait event matches issue and phase」— `--exit-code 143` の log に `still waiting (json mode)`、`--events` に当該 issue/phase の `ci_wait` イベント行を書いた fixture を渡し、output に `ci-wait-silence-timeout` を含み `json-mode-silent-hang` を含まないことを確認、(b) 「ci wait silence: falls back to json-mode-silent-hang when ci_wait event is for a different phase」— events fixture の phase を不一致にして output が `json-mode-silent-hang` を含むことを確認、(c) 「ci wait silence: falls back to json-mode-silent-hang when --events is omitted」— `--events` を渡さず既存動作 (`json-mode-silent-hang`) が維持されることを確認 (後方互換の回帰ガード)。(after 1) (→ 受入条件 6)
5. `bats tests/detect-wrapper-anomaly.bats` をローカルで実行し新規 3 件を含む全テストが PASS することを確認する。コミット・push 後、CI (`Run bats tests` job) が green になることを確認する。(after 4) (→ 受入条件 6, 7)

## Verification

### Pre-merge

- <!-- verify: grep "events" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` が events ログを入力として受け取れる
- <!-- verify: grep "ci_wait" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` が `ci_wait` イベントを判定材料にしている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog" "--events" --> Tier 2 復旧 (skills/auto/SKILL.md) の `detect-wrapper-anomaly.sh` 呼び出しが events ログ (`--events .tmp/auto-events.jsonl`) を渡すよう更新されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md に、CI 待機中の沈黙による watchdog kill を json-mode-silent-hang とは別のパターンとして扱うカタログエントリが追加されており、復旧手順が即リトライではなく CI 状態の確認を先行させる形になっている" --> CI 待機由来の沈黙が独立カタログエントリとして追加されている
- <!-- verify: rubric "json-mode-silent-hang の判定条件が、ci_wait イベントが存在する場合に当該パターンへマッチしないよう絞り込まれている" --> `json-mode-silent-hang` の判定が CI 待機ケースを除外する
- <!-- verify: command "bats tests/detect-wrapper-anomaly.bats" --> `detect-wrapper-anomaly.sh` の bats テストが PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが green

### Post-merge

- 次回 CI 待機中に watchdog kill が発生した際、`json-mode-silent-hang` ではなく CI 待機由来のパターンとして診断され、CI 状態の確認が先行することを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **Auto-Resolved Ambiguity Points (issue phase より継承)**: 新パターン名 `ci-wait-silence-timeout` は既存カタログの kebab-case 命名規則に沿って issue phase で確定済み。呼び出し元 (`skills/auto/SKILL.md` Tier 2) への `--events` 配線 AC も issue phase で追加済み — `detect-external-kill.sh` の同型呼び出し (line 932) が前例
- **スコープ外の関連ギャップ**: `scripts/apply-fallback.sh` も独自に `json-mode-silent-hang` 判定 (`still waiting (json mode)` の単純 grep、`code-pr` フェーズ限定) を持つ (`run-auto-sub.sh` の XL sub-issue bash-orchestrated Tier 2 経路)。これは `detect-wrapper-anomaly.sh` とは別実装で、本 Issue のスコープ (Issue 本文の対応方針・Auto-Resolved Ambiguity Points はいずれも `skills/auto/SKILL.md` Tier 2 + `detect-wrapper-anomaly.sh` に限定) には含まれない。`apply-fallback.sh` の対象フェーズが `code-pr` のみで、`wait-ci-checks.sh` 由来の `ci_wait` emission は現状 `run-review.sh` 経由 (review フェーズ) に限られるため、本 Issue が扱う誤診断は今のところ `apply-fallback.sh` 側では再現しない。将来 `code-pr` 側にも類似の長時間待機が入る場合は、別 Issue として再検討する
- **BRE メタキャラクタスキャン**: Pre-merge の `grep` 型 verify command 2 件 (`"events"` / `"ci_wait"`) を確認、いずれも BRE メタキャラクタ (`\|` 等) は含まれない
- **文字列存在確認**: `grep "events"` / `grep "ci_wait"` の各パターンは Implementation Step 1 の変更後にスクリプト内へ実際に出現することを確認済み (`--events`/`EVENTS_FILE` および `"event":"ci_wait"` の文字列一致)。`section_contains` の見出し文字列 (`Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog`) は `skills/auto/SKILL.md` 現行 963 行目に完全一致することを確認済み
- **CI ジョブ名確認**: `github_check "gh pr checks" "Run bats tests"` の expected_value は `.github/workflows/test.yml` 実際のジョブ名 (line 9: `name: Run bats tests`) と一致することを確認済み

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — Background の技術的主張をコードベースと照合し正確性を確認、Auto-Resolve Log (`ci-wait-silence-timeout` 命名確定、`--events` 配線 AC 追加) を記録 / https://github.com/saitoco/wholework/issues/1221#issuecomment-5214484722
- saito / MEMBER / first-class / `/issue` Step 15 (AC Verify Command Integrity Audit) — 自己監査で Step 8/9 追加直後の AC が Pattern 6-1 (heading 引数に `#### ` を含む常時 UNCERTAIN) に該当すると検出し、Issue body を修復済み (現在の AC は修復後の形) / https://github.com/saitoco/wholework/issues/1221#issuecomment-5214534020

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 を Spec 記載順のまま実装。分岐イディオムも `detect-external-kill.sh` line 80-82 と同一のものを流用した

### Design Gaps/Ambiguities
- N/A

### Rework
- 本 Issue は `/auto` の code フェーズが 1 回目の試行でフルテストスイートのバックグラウンド実行によりサイレント no-op し (`code_retry_fire iteration 1`)、2 回目の試行 (本セッション) でリトライされたもの。1 回目の失敗は本 Issue の実装内容自体とは無関係で、直前にランディングした Issue #1213 の修正 (`bats --jobs <N> tests/` をフォアグラウンドで 10 分以内に収める) が本セッションの Step 9 に反映されておりリトライは正常完了した

### Observed pre-existing test flakiness (unrelated to this Issue's scope)
- `bats --jobs 18 tests/` の並列フルスイート実行で `tests/post_merge_check.bats` の `fail: gh issue reopen called when FAIL input given` が単発 FAIL した。同テストを単独実行 (`bats tests/post_merge_check.bats`) すると 10/10 PASS するため、`scripts/test-failure-classify.sh` の分類は `infra` (並列実行下のリソース競合と推定)。`scripts/post_merge_check.sh` / `tests/post_merge_check.bats` はいずれも本 Issue の変更対象外であり、原因調査・修正はスコープ外と判断した。CI (`.github/workflows/test.yml`) も `bats --jobs $(nproc) tests/` で実行するため、同じ並列条件下では低頻度で再現しうる — 再発・パターン化した場合は別 Issue として起票を検討

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `--events` の判定分岐は `detect-external-kill.sh` の chained-grep イディオムをそのまま踏襲し、既存コードとの一貫性を優先した
- `ci-wait-silence-timeout` カタログエントリの Fallback Steps は `skills/verify/SKILL.md` Step 5 の CI インフラ障害判定表を参照する形にとどめ、判定ロジック自体は複製しなかった (SSoT 分散を避けるため)

### Deferred Items
- Post-merge AC (`verify-type: observation event=auto-run session=next`) — 次回 CI 待機由来の watchdog kill が実際に発生した際、`ci-wait-silence-timeout` として診断されることの観察が必要。次回 `/auto` セッションでの発火を待つ
- `scripts/apply-fallback.sh` 側の `code-patch` フェーズ限定の独自 `json-mode-silent-hang` 判定は、本 Issue のスコープ外として Spec Notes に明記済み (将来 `code-pr` に類似の長時間待機が入った場合は別 Issue で再検討)

### Notes for Next Phase
- `tests/post_merge_check.bats` の並列実行下フリークな FAIL (上記 Rework 参照) は再現性が低く本 Issue の変更と無関係。review/verify フェーズで再度 FAIL が観測されても、まず単独再実行で切り分けること
- AC7 (`github_check "gh pr checks" "Run bats tests"`) は PR 作成前のため未チェックのまま — CI green 確認後に `/review` または `/verify` でチェックされる想定
