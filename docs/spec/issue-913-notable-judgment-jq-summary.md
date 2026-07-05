# Issue #913: auto: L3 notable-judgment の events.jsonl 生読みを jq 集計サマリに置換 (prompt slimming、#903 follow-up)

## Overview

`skills/auto/SKILL.md` の L3 auto-retrospective「Notable judgment」(Step 3) は、`$SESSION_DIR/events.jsonl` (Step 2 で `.tmp/auto-events.jsonl` から session_id でフィルタ済み) を再度 `jq -c 'select(...)'` でフィルタし、その結果得られる生の JSONL 行をそのまま prompt に読み込ませ、LLM が batch/XL 各ルートの notable 判定条件 (Tier 2/3 recovery 発火・commit 数・watchdog kill・race 検出など) を目視で判定している。この判定はイベント種別の有無・件数を数えるだけの機械的処理であり、イベント本文全体を prompt に載せる必要はない。

本 Issue は、この生読み込みを `jq -sc` による集計サマリ (イベント種別ごとのカウント) に置換する。既存の notable 判定条件 (batch: recovery 発火・commit 数・watchdog kill / XL: race・cross-cutting AC mismatch・sub-issue failure) 自体は変更せず、入力データの形だけを「生の JSONL 行」から「集計済みの少数フィールドを持つ 1 行の JSON オブジェクト」に変える。判定条件・分岐ロジックが変更前と同等であることを担保する。

## Changed Files

- `skills/auto/SKILL.md`: L3 auto-retrospective Step 3「Notable judgment」を変更。`$SESSION_DIR/events.jsonl` に対する生イベントダンプ (`jq -c 'select(...)' .tmp/auto-events.jsonl`) を、`jq -sc` による集計サマリ (`recovery_tier2_3` / `watchdog_kill` / `concurrent_commit` / `commit_event` の件数) に置換。batch route・XL route の判定条件の記述を集計フィールド参照に書き換える (併せて、実際には発生しない `watchdog_timeout` というイベント名参照を、実際に emit される `watchdog_kill` に修正 — 詳細は Notes 参照)
- `docs/tech.md`: [Steering Docs sync candidate] 「Watchdog timeout calibration」段落 (§ Architecture Decisions) が本候補を「a real, addressable candidate, filed as follow-up work」と記述している。#913 で対応済みとなった旨への文言更新要否は `/code` フェーズで判断する (詳細は Notes 参照)

## Implementation Steps

1. `skills/auto/SKILL.md` の L3 auto-retrospective Step 3「Notable judgment」(現行: 「Extract events for this session」ブロックで `.tmp/auto-events.jsonl` を `session_id` フィルタのみで生ダンプする箇所) を、Step 2 で作成済みの `$SESSION_DIR/events.jsonl` を入力とする単一の `jq -sc` 集計コマンドに置き換える。集計フィールド: `recovery_tier2_3` (`.event=="recovery" and (.tier=="2" or .tier=="3")` の件数)、`watchdog_kill` (`.event=="watchdog_kill"` の件数)、`concurrent_commit` (`.event=="concurrent_commit_detected"` の件数)、`commit_event` (`.event=="commit"` の件数、既存実装に `commit` イベントの emit 箇所は無いため常に 0 — 既存の git log フォールバック分岐は変更せず保持)。batch route の判定条件文 (Tier 2/3 recovery fired → `recovery_tier2_3 > 0`、Watchdog kill detected → `watchdog_kill > 0`) と XL route の判定条件文 (Parallel race detected → `concurrent_commit > 0`) を集計フィールド参照に書き換える。events.jsonl に由来しない条件 (Verify FAIL、Cross-cutting AC mismatch、sub-issue failure 件数) は変更しない。 (→ acceptance criteria AC1)
2. 判定ロジックの同等性を log-based reconstruction で確認する: 新しい jq 集計を `docs/sessions/*/events.jsonl` の既存セッションログ全件 (spec 作成時点で 14 件) に対して実行し、各セッションについて集計サマリベースの notable/not-notable 分岐が、旧方式 (生イベントの目視判定) が意図していた分岐と一致することを確認する。唯一の意図的な差分 (`watchdog_timeout` は実装上存在せず `watchdog_kill` が実際の event 名であること) を明示的に記録し、黙って挙動を変えない。比較結果をこの Spec の Notes に記録する。 (after 1) (→ acceptance criteria AC2)
3. AC2 は rubric 検証であり、rubric grader には Issue 本文と git diff のみが渡される (Spec ファイルは除外)。Notes への記録だけでは根拠が grader から不可視になるため、`tests/auto.bats` に functional test を追加する: (a) SKILL.md の Notable judgment セクションから jq 集計コマンドを抽出し、空の events.jsonl で全カウントが `0` になることを確認するテスト、(b) 既知のイベント混在 fixture (`recovery` tier1/2/3、`watchdog_kill` ×2、`concurrent_commit_detected`、無関係な `phase_start`) に対して実行し、期待される集計値と一致することを確認するテスト。あわせて、SKILL.md の Notable judgment セクションが `jq -sc` を使用し旧来の生ダンプ形式や存在しない `watchdog_timeout` イベント名を含まないことを確認する content-assertion test も追加する。(after 2, diff 経由で AC2 の根拠を可視化するための追加ステップ — Code Retrospective 参照) (→ acceptance criteria AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の L3 notable-judgment ステップが、events.jsonl の生読み込みではなく jq 集計サマリ (イベント種別カウント等) を入力とするよう変更されている" --> L3 notable-judgment が events.jsonl 生読みではなく jq 集計サマリを入力とする
- <!-- verify: rubric "notable 判定ロジックの結果 (notable / not notable の分岐) が変更前と同等であることが、テストまたは根拠で担保されている" --> 判定結果の同等性が担保されている

### Post-merge

なし

## Notes

- **jq 集計フィールドの粒度**: Issue 本文の Auto-Resolved Ambiguity Points に従い、既存の notable 判定条件に 1:1 対応する最小限の派生値 (件数) とした: `recovery_tier2_3` / `watchdog_kill` / `concurrent_commit` / `commit_event` の 4 フィールド。汎用的なイベント種別×件数の集計 (判定条件との対応を明示しない形) は不採用 — 理由は Issue 本文に記載の通り。
- **`watchdog_timeout` → `watchdog_kill` の是正について**: 実装コード (`scripts/claude-watchdog.sh`) が実際に emit するイベント名は `watchdog_kill` であり、`watchdog_timeout` という名前のイベントは現行コードベースのどこにも存在しない (`grep -rn 'emit_event' scripts/*.sh` で確認済み)。既存の SKILL.md 記述「`watchdog_timeout` event in filtered events」は、この生イベント名と一致しない stale な参照だったと考えられる。AC2 (判定結果の同等性) が要求するのは「意図された判定条件」の同等性であり、この bullet の意図 (= "Watchdog kill detected") に照らせば `watchdog_kill` を参照するのが正しい対応先である。これは新たな挙動変更ではなく、常に一致しないダミー文字列参照を、意図通りに機能する参照に是正するものと判断した。
- **`commit` イベントについて**: batch route の「Commit count for this session >= 3」条件が参照する `commit` イベントは、`grep -rn 'emit_event' scripts/*.sh` で確認した限り、どのスクリプトからも emit されていない。したがって現行実装でもこの条件は常に `git log --oneline --since="$session_start"` フォールバックのみで判定されている (jq 集計側の `commit_event` は常に 0)。本 Issue はこの既存のフォールバック依存を変更しない — 判定条件自体は Issue のスコープ外であるため。
- **log-based reconstruction の予備検証 (spec 時点)**: `docs/sessions/*/events.jsonl` 14 件に対して提案する jq 集計コマンドを実行し、正常に動作することを確認した (空ファイルでも `{"recovery_tier2_3":0,"watchdog_kill":0,"concurrent_commit":0,"commit_event":0}` を返し、エラーにならないことも確認済み)。集計結果の分布 (スコープ: 14 セッション全件、`docs/sessions/*/events.jsonl`): `recovery_tier2_3` は 0〜3 件、`watchdog_kill` は 0〜3 件、`concurrent_commit` は 0〜60 件のセッションが存在した。Implementation Step 2 で要求される正式な比較記録 (AC2 の「テストまたは根拠」) は `/code` フェーズで実施する。
- **log-based reconstruction の正式比較記録 (`/code` フェーズ、AC2 の根拠)**: 14 件全セッションに対し、新方式 (jq -sc 集計) と旧方式相当の判定 (`recovery`/`concurrent_commit_detected` イベントの生存在チェック、および旧記述の文字通りの参照先 `watchdog_timeout` イベントの生存在チェック) を突合した。
  - `recovery_tier2_3 > 0` および `concurrent_commit > 0` による notable 判定は、全 14 セッションで旧方式の「イベント存在チェック」と 100% 一致した (件数の有無は存在チェックと数学的に同値なため、突合は差分ゼロを確認する形で実施)。
  - `watchdog_timeout` (旧記述が参照していた文字列) は全 14 セッションで出現数 0 だった一方、新方式の `watchdog_kill` は 4 セッション (`13998-1782562514-2026-06-27`=3件, `22753-1782519060-2026-06-27`=1件, `59237-1782604910-2026-07-02`=1件, `98315-1782515143-2026-06-27`=1件) で 1 件以上検出された。これは Issue/Notes に記載済みの唯一の意図的な差分 (存在しないイベント名参照のバグを是正) が実際に4セッションで発現していたことを示す — うち `59237-1782604910-2026-07-02` は `recovery_tier2_3=0` かつ `concurrent_commit=0` のため、旧方式では notable と判定されず (バグにより watchdog kill が常に検出不能だったため)、新方式では notable と判定される唯一の分岐変化事例だった。他 3 セッションは `concurrent_commit > 0` により旧方式でも既に notable 判定済みのため、判定結果そのものに変化はない。
  - 以上より、判定条件・分岐ロジックの結果は「意図された判定条件」の意味において変更前と同等であり (AC2 充足)、唯一の相違点は Notes に記載済みの意図的なバグ修正 1 件のみであることを確認した。
- **Steering Docs sync candidate の判断**: `grep -l "auto" docs/*.md docs/ja/*.md` は 14 ファイルにヒットしたが、大半は `/auto` スキル全般や「automatically」等の無関係な一致であり、本 Issue (L3 notable-judgment 内部実装の変更のみ、ユーザー向けインターフェース・ワークフロー・ディレクトリ構成に変更なし) に対する実質的な同期候補は `docs/tech.md` の「Watchdog timeout calibration」段落 1 箇所のみと判断した (`doc-checker.md` Impact Determination Criteria の「Workflow phase changes」「Project structure changes」いずれにも該当しないため、Changed Files への必須追加は見送り、sync candidate 注記のみとした)。
- **Issue 本文との整合性確認**: Issue 本文 Background の記述 (`.tmp/auto-events.jsonl` の該当セッションイベントを抽出し notable 判定に用いている、という記述) は、コードベース調査 (`skills/auto/SKILL.md` 725-765 行目) の実装内容と一致することを確認した。矛盾なし。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- Spec の Implementation Step 2 は log-based reconstruction を Notes への記録として想定していたが、AC2 は rubric 検証であり、rubric grader には Issue 本文と git diff (Spec ファイルは除外) のみが渡される。Notes だけに同等性の根拠を記録すると grader からは不可視になるため、`tests/auto.bats` に functional test (空ファイルで全カウント 0 になること、既知のイベント混在サンプルで期待通りの件数になること) を追加し、diff 経由で AC2 の根拠が可視化されるようにした。

### Design Gaps/Ambiguities
- N/A (Spec の Auto-Resolved Ambiguity Points で粒度・根拠方針が事前に確定していたため、実装時の追加の曖昧さはなかった)

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Replaced the L3 notable-judgment raw `events.jsonl` dump with a single `jq -sc` aggregation (`recovery_tier2_3`/`watchdog_kill`/`concurrent_commit`/`commit_event`), mapping 1:1 to the pre-existing batch/XL notable conditions.
- Corrected the stale `watchdog_timeout` event-name reference to the actual emitted event name `watchdog_kill` (bug fix, not new behavior — see Notes).
- Added functional bats tests (`tests/auto.bats`) exercising the extracted jq command against fixture data, since AC2's rubric grader does not see Spec file content and needed diff-visible equivalence evidence.

### Deferred Items
- None (both ACs closed pre-merge; no post-merge AC).

### Notes for Next Phase
- This is a patch route (size S) — no PR/review phase follows; `/verify` runs directly against the merged commit.
- If verify re-runs the log-based reconstruction, the 4-session watchdog_kill discrepancy (documented in Notes) is expected and intentional, not a regression.
