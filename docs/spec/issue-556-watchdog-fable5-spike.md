# Issue #556: Fable 5 long-turn 対応: watchdog タイムアウト/進捗 echo の spike と再調整

## Overview

`scripts/watchdog-defaults.sh` は `WATCHDOG_TIMEOUT_DEFAULT=1800`（stdout 30 分無出力 → kill）を設定している。Claude Fable 5 は単発リクエストが数分に及ぶ long-turn を生じさせるため、現行の 1800 秒デフォルトで誤 kill が増加するリスクがある。一方で Fable 5 はデフォルトでナレーションが増えるため、そのテキストが `claude -p` の stdout に届けば watchdog をリセットする可能性もある。

本 Issue は Fable 5 下での watchdog 挙動を spike で計測し、誤 kill を防ぐようデフォルト値と進捗 echo を再調整することを目的とする。調整はすべて計測結果に基づいて判断する。

## Changed Files

- `docs/reports/watchdog-recovery-strategy.md`: Fable 5 long-turn の spike 結果・所見を新セクションとして追記（`Fable 5` キーワード・最大 silent window 数値・ナレーション stdout 到達可否・調整方針の根拠）— bash 3.2+ compatible（シェルスクリプト変更なし）
- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_DEFAULT` を spike 結果に基づき引き上げ（条件付き：max silent window > 1800s またはナレーション未到達の場合）— bash 3.2+ compatible
- `tests/watchdog-defaults.bats`: `@test "sourcing sets WATCHDOG_TIMEOUT_DEFAULT=1800"` のテスト名と assertion を新しい値に更新（条件付き：直上と連動）
- `skills/spec/SKILL.md`: Step 10 Spec 作成前に `echo "progress: ..."` を追加（条件付き：spike が long-silent window を検出した場合）
- `skills/review/SKILL.md`: review 統合前（Spec compliance + bug review の結果統合前）に `echo "progress: ..."` を追加（条件付き：spike が long-silent window を検出した場合）

## Implementation Steps

1. **Spike 計測**（→ AC1, AC3）: `run-spec.sh --model claude-fable-5` または `run-code.sh --model claude-fable-5` で実タスクを 1〜2 回実行し、watchdog の heartbeat ログ（stderr: `"watchdog: still waiting, silent for Ns"`）から最大 silent window を記録；ナレーション（中間テキスト）が stdout に届き watchdog をリセットしているか確認する
2. **結果をレポートに追記**（→ AC1, AC3、after 1）: `docs/reports/watchdog-recovery-strategy.md` に `## Fable 5 long-turn findings` セクションを追加し、`Fable 5` キーワード・最大 silent window の計測値・ナレーション stdout 到達可否・`WATCHDOG_TIMEOUT_DEFAULT` 調整方針の根拠を記録（`silent window` という語を含めること）
3. **デフォルト値の調整**（→ AC2、after 1、条件付き）: max silent window > 1800s またはナレーションが stdout に届かない場合、`WATCHDOG_TIMEOUT_DEFAULT=1800` を `WATCHDOG_TIMEOUT_DEFAULT=2700` 等に引き上げ；据え置きの場合はレポートに根拠を記録のみ。値を変更する場合は `tests/watchdog-defaults.bats` の `@test "sourcing sets WATCHDOG_TIMEOUT_DEFAULT=1800"` テスト名と `[ "$output" = "1800" ]` assertion も同値に更新する
4. **progress echo 拡張**（after 1、条件付き）: spike が long-silent window（例: 600 秒超）を示す場合、`skills/spec/SKILL.md` の Step 10 Spec 作成直前と `skills/review/SKILL.md` の review 統合直前に `echo "progress: ..."` を追加
5. **テスト確認**（→ AC4、after 3）: `bats tests/watchdog-defaults.bats` を実行し全テスト green を確認

## Verification

### Pre-merge
- <!-- verify: rubric "Fable 5 spike results (max silent window duration and whether narration reaches stdout) are documented in docs/reports/watchdog-recovery-strategy.md" --> <!-- verify: grep "silent.window" "docs/reports/watchdog-recovery-strategy.md" --> spike の計測結果（Fable 5 下の最大 silent window、ナレーション stdout 到達可否）が `docs/reports/watchdog-recovery-strategy.md` に記録されている
- <!-- verify: grep "WATCHDOG_TIMEOUT_DEFAULT" "scripts/watchdog-defaults.sh" --> <!-- verify: rubric "WATCHDOG_TIMEOUT_DEFAULT in scripts/watchdog-defaults.sh was adjusted based on Fable 5 spike findings, or the value is kept unchanged with a rationale documented in docs/reports/watchdog-recovery-strategy.md" --> `watchdog-defaults.sh` のデフォルト値が計測結果に基づき調整されている（据え置きの場合はその根拠が記録されている）
- <!-- verify: file_contains "docs/reports/watchdog-recovery-strategy.md" "Fable 5" --> watchdog recovery レポートに Fable 5 long-turn の所見が追記されている
- <!-- verify: command "bats tests/watchdog-defaults.bats" --> `.wholework.yml` の `watchdog-timeout-seconds` 上書きが引き続き有効（既存テストが green）

### Post-merge
- Fable 5 を用いた `/auto` 実行で、commits 完了済みなのに watchdog kill → 手動復旧が必要となる事象が再発しないこと（観測）

## Notes

- Step 3・4 は spike 結果によって実施・スキップが分岐する条件付き変更。`WATCHDOG_TIMEOUT_DEFAULT` を変更する場合は必ず `tests/watchdog-defaults.bats` の該当テスト名と assertion を同値に更新すること（未更新だと AC4 が fail する）。
- Spike 計測の代替手法: `WATCHDOG_TIMEOUT=300 bash scripts/claude-watchdog.sh claude -p --model claude-fable-5 "..."` のように小さい WATCHDOG_TIMEOUT で短縮計測も可能。heartbeat ログが最大 silent window の証拠となる。
- `docs/reports/claude-fable-5-impact-strategy.md` の TODO チェックボックス（"Spike `claude-watchdog.sh` stdout cadence under Fable 5..."）は spike 完了後に任意でチェック可能だが、本 Spec の acceptance criteria には含めない（`docs/reports/` は verify 対象外）。
- `grep "silent.window"` は `.` が正規表現ワイルドカードとして動作し "silent window"（スペース）にマッチする。実装で `silent window` という表現を使えば AC1 の grep hint が PASS する。

## Code Retrospective

### Deviations from Design

- Step 1 の spike で `run-spec.sh --model claude-fable-5` を使わず、短縮計測代替手法（`WATCHDOG_TIMEOUT=120/180 bash scripts/claude-watchdog.sh claude -p --model claude-fable-5 "..."`）を採用した。非インタラクティブモードでの長時間試走は watchdog タイムアウトや環境制約のリスクがあるため、Spec Notes が提示する代替手法を選択した。
- Step 2 のレポート記録で、AC1 の grep パターン `silent.window` に合わせた表現（"silent window"）を各所に使用した。Spec Notes に明示されていた通り。
- `tests/watchdog-defaults.bats` の fallback テスト（non-numeric/negative value → デフォルト値を返す）も 1800 → 2700 に更新が必要だった（Spec Notes には「テスト名と assertion を更新」とあるが、stale test assertion check で fallback テストも対象と判明した）。
- `tests/claude-watchdog.bats` のコメント行に "default 1800s" の記述があり、これも 2700 に更新した。モック定数（他のテストファイルの `WATCHDOG_TIMEOUT_DEFAULT=1800`）は動作値ではないため更新対象外と判断。

### Design Gaps/Ambiguities

- Spec の「1〜2 回試走し計測」という記述は本格的なフェーズ試走（`run-spec.sh` 経由）を示唆しているが、代替手法との使い分け基準が明確でなかった。非インタラクティブモードでは代替手法が適切と auto-resolve した。
- fallback テストの更新必要性は Spec に明示されていなかったが、stale assertion check で発見できた。

### Rework

- なし（fallback テストの更新は1回で完了）。

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|--------|--------|-------|
| issue | pr | SUCCESS | triage from no phase/* labels |
| spec | pr | SUCCESS | |
| code | pr | SUCCESS (watchdog kill, reconcile override) | watchdog killed claude after 1800s silence; PR #568 already created; in-wrapper reconcile returned matches_expected:true and run-code.sh exited 0 — no manual recovery needed |
| review | pr | SUCCESS | 1 SHOULD issue resolved |
| merge | pr | SUCCESS | |
| verify | - | SUCCESS | pre-merge 4/4 PASS, post-merge 1 SKIPPED (operational observation) |

### Orchestration Anomalies
- code phase: `run-code.sh 556 --pr` hit the 1800s watchdog kill (`watchdog: no output for 1800s, killing process`) during post-PR processing under the OLD default — the exact failure mode this Issue addresses. The wrapper's unconditional completion check (reconcile Stage 2 / Layer 3) detected PR #568 OPEN and overrode to success; exit code was 0 and the parent session continued the chain without manual intervention.
- Self-referential validation: the incident is live evidence for the 1800→2700 raise merged by this very Issue. Post-merge runs (#557 onward) execute under 2700s.

### Improvement Proposals
- N/A (the observed anomaly is the problem this Issue fixed; recovery layers worked as designed)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 4 件すべてに verify command（rubric + grep のペア構成含む）が付与され、UNCERTAIN 0 件。`grep "silent.window"` の正規表現挙動まで Spec Notes に明記され、実装がそれに正確に追随した

#### design
- 条件付き実装ステップ（spike 結果による分岐）が明確で、短縮計測代替手法の提示が実際に採用された。設計と実装の乖離なし

#### code
- spike は代替手法（小 WATCHDOG_TIMEOUT での短縮計測）で実施。fallback テストの更新必要性が stale assertion check で発見され 1 回で完了（手戻りなし）
- code フェーズ自体が旧 1800s デフォルトで watchdog kill に遭遇し、reconcile Layer 3 で自動復旧 — 本 Issue の動機を実地で裏付けた（Auto Retrospective 参照）

#### review
- customization.md（EN/JA）のデフォルト値記載がスクリプト変更に追随していない点を review が検出・修正。デフォルト値変更時は customization.md を Changed Files に含める教訓が review retrospective に記録済み

#### merge
- conflicts なし、squash merge 即時完了

#### verify
- pre-merge 4/4 PASS（bats ローカル 5/5 green）。post-merge 観測条件は SKIP（変更後デフォルトでの運用観測は後続 /auto 実行が担う）

### Improvement Proposals
- N/A（review retrospective の customization.md 教訓は #556 内で対処済み。watchdog 異常は本 Issue 自体が修正）

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #568 を squash merge（`--squash --delete-branch`）で main にマージ。`closes #556` により Issue は自動クローズ。
- `mergeable=true, reason=clean` で conflicts なし。Step 3（コンフリクト解消）はスキップ。
- review フェーズの doc fix コミット（2ac1337: customization.md デフォルト値更新）は PR ブランチに含まれており、squash に含まれた。

### Deferred Items

- post-merge AC（Fable 5 `/auto` 実行での watchdog 誤 kill 再発観測）は引き続き defer — 運用観測が必要。
- `docs/reports/claude-fable-5-impact-strategy.md` 内の historical `1800` 参照は変更対象外（review フェーズ判断を継承）。

### Notes for Next Phase

- verify フェーズは post-merge AC の観察が主。コード変更は squash 済みで main に存在。
- `WATCHDOG_TIMEOUT_DEFAULT=2700` が `scripts/watchdog-defaults.sh` に反映済み。
- `bats tests/watchdog-defaults.bats` は CI で 5/5 green 確認済み（verify コマンドとして再実行可能）。
- mock 定数（他テストの `WATCHDOG_TIMEOUT_DEFAULT=1800`）は意図的 — verify フェーズでも指摘不要。

## review retrospective

### Spec vs. implementation divergence patterns

- なし。実装は Spec の acceptance criteria と step-by-step 指示に正確に対応していた。code フェーズのハンドオフが詳細で、review フェーズの再確認コストが低かった。

### Recurring issues

- `docs/guide/customization.md`（と日本語ミラー）の `.wholework.yml` デフォルト値記載が `scripts/watchdog-defaults.sh` の変更に追随していなかった。デフォルト値変更時は customization.md のテーブルと例示コメントも変更対象ファイルとして Spec の changed-files リストに追記するとよい。

### Acceptance criteria verification difficulty

- 全条件に verify command が付与されており、`bats` コマンドは CI 参照 fallback で PASS を確認できた（safe モードで command hint を直接実行不可だが CI SUCCESS で代替検証可能）。UNCERTAIN は0件。verify command の品質は高かった。
