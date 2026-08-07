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
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC ゲート (`check-pre-merge-ac.sh`) で unchecked_count=0 を確認し、review-incomplete-fallback チェックも該当なしのため、通常の squash merge (`gh pr merge --squash --delete-branch`) で進行した
- CI green (mergeable=clean, ci_status=success, review_status=approved) を確認した上でマージを実行した

### Deferred Items
- Post-merge AC (`verify-type: observation event=auto-run session=next`) は未発火のため引き続き未チェック — 次回 CI 待機由来の watchdog kill が実際に発生した際の観察を待つ

### Notes for Next Phase
- `/verify` フェーズでは Post-merge AC の観察確定 (`event=auto-run`) を担当する

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — PR #1253 の diff (5 ファイル) は Spec の Implementation Steps 1-5 と厳密に一致していた (`--events` 引数名・挿入位置、`detect-external-kill.sh` の chained-grep イディオム踏襲、カタログエントリの配置、`skills/auto/SKILL.md` の引数順、bats 新規 3 ケース)。`review-light` エージェントが Spec 乖離 / エッジケース堅牢性 / セキュリティ / ドキュメント整合性の 4 側面すべてで issue 0 件と判定

### Recurring issues
- Nothing to note — 本レビューは MUST/SHOULD/CONSIDER いずれも 0 件

### Acceptance criteria verification difficulty
- Nothing significant to note。Pre-merge 7 件 (`grep` x2, `section_contains` x1, `rubric` x2, `command` x1, `github_check` x1) すべてが UNCERTAIN なしで PASS に到達した
- `rubric "json-mode-silent-hang の判定条件が、ci_wait イベントが存在する場合に当該パターンへマッチしないよう絞り込まれている"` は、実装の if/else 分岐構造 (ci_wait 検出時のみ `ci-wait-silence-timeout` へ分岐し、それ以外は既存の `json-mode-silent-hang` にフォールバックする形) を直接言い当てており、コード確認 1 回で判定確定できた。rubric 文言がコード構造を正確に予見していた良い例として記録

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` が元 AC の**配線ギャップ**を自力で検出・補完した点が本 Issue 最大の収穫。元 AC は `detect-wrapper-anomaly.sh` 自体が `--events` を受け取れることのみを検証しており、実際に発火する呼び出し元 (`skills/auto/SKILL.md` Tier 2) がそのフラグを渡すことは未検証だった。`detect-external-kill.sh` の既存配線を前例として `section_contains` AC を追加した判断は、「スクリプト単体は直ったが呼び出し元が未配線で実効ゼロ」という失敗モードを事前に潰している
- Step 15 の AC 監査が、自分が直前に追加した AC 自体の不備 (`section_contains` の heading 引数に `####` を含め Pattern 6-1「常時 UNCERTAIN」に該当) を検出して即修復した。自己生成 AC も監査対象に含める設計が機能した実例

#### spec
- SPEC_DEPTH=light で十分だった。`detect-external-kill.sh` に同型の先行実装があったため、設計は「既存イディオムの踏襲先を特定する」ことにほぼ帰着した
- Implementation Steps 1-5 と PR #1253 の 5 ファイル diff が厳密に一致し、Code Retrospective の Deviations も N/A

#### code
- 1 回目の試行がフルテストスイートのバックグラウンド実行で silent no-op (`code_retry_fire iteration 1`)、2 回目で正常完了。**#1213 の修正 (`bats --jobs <N> tests/` をフォアグラウンドで完了させる) が実際に効いた初のケース**。同一バッチの #1223 は #1213 着地前の試行だったため 3 回とも失敗しており、着地前後で挙動が分かれたことが対照的に確認できた

#### review
- `review-light` が 4 側面すべてで issue 0 件。MUST/SHOULD/CONSIDER いずれもゼロで、Spec と実装の一致度がそのまま反映された

#### merge
- Pre-merge AC 7 件すべて checked、`review_incomplete_fallback` 該当なし、CI green。オーバーライドマーカーなしの通常 squash merge で完了。recovery 発火なし

#### verify
- Pre-merge 7 件は already-checked skip rule で SKIPPED、Post-merge 1 件は `event=auto-run` 未発火で SKIPPED。FAIL / UNCERTAIN ゼロ
- Post-merge 条件は「実際に CI 待機中の watchdog kill が発生する」という外部事象待ちで、`session=next` も付いている。イベント駆動の観察条件として妥当な設計だが、発火頻度が低いため長期滞留が見込まれる

### Improvement Proposals

- **並列 bats 実行下の flakiness を検知・追跡する仕組みがない**: 本バッチセッション内だけで 2 件の並列実行由来 flaky が独立に観測された — #1221 の `tests/post_merge_check.bats` (`fail: gh issue reopen called when FAIL input given`、`bats --jobs 18` で単発 FAIL・単独実行では 10/10 PASS)、#1224 の `tests/worktree-merge-push.bats` (`--from with base-diverged and rebase conflict aborts and exits non-zero`、同一コミット `7b5132c3` に対する 2 回の CI 実行で結果が分裂)。`docs/spec/` を横断すると並列実行 flaky への言及は 5 spec (#1037 / #1056 / #829 / #1164 / #1221)、`flaky` 全体では 12 spec に及ぶ。過去の対処 (#1136 `emit` 系環境変数の隔離、#251 `PATCH_LOCK` の per-test 化) はいずれも個別テストの分離バグを CLOSED にしたもので、「並列実行下でのみ落ちるテスト」を継続的に検知・分類する常設の仕組みは存在しない。実害は CI green 判定の揺らぎに直結する — `.github/workflows/test.yml:29` は `bats --jobs $(nproc) tests/` で実行するため、`github_check` 系 AC と `/merge` の CI ゲートが低頻度で偽陰性を出す。実際に #1224 の `/merge` は `mergeable=false, reason=ci_failing` を受けて flaky と判定し auto-resolve で通す判断を要した。対策候補として (a) `scripts/test-failure-classify.sh` の `infra` 分類に「並列実行時のみ FAIL・単独実行で PASS」を判定する再実行ステップを持たせる、(b) CI で FAIL したテストのみを単独再実行して切り分ける job を追加する、(c) 並列 flaky の観測を `docs/reports/` に累積し閾値検出する (`collect-recovery-candidates.sh` と同型) のいずれか、または組み合わせ
