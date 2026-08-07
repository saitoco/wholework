# Issue #1227: auto/verify: CI プラットフォーム障害の判定を Tier recovery ラダーと run-review 経路から参照できるようにする

## Overview

`skills/verify/SKILL.md` Step 5 の **CI Infrastructure Failure Detection** 判定表 (steps が空 / timeout / runner error / network error) は `/verify` の AC 判定内でのみ使われており、`scripts/run-review.sh` の exit 2 (PENDING) 経路と `/auto` の Tier 1/2/3 recovery ラダーからは参照されない。結果として CI プラットフォーム側の障害と実装起因の失敗が区別されないまま recovery が選択され、2026-08-06 の GitHub Actions 障害では 3 セッション・4 事象 (#1206 / #1212 / #1214 / session `41961-1785999585`) で無駄なリトライと親セッションの手読みによる切り分けが発生した。

判定基準を `modules/ci-failure-classifier.md` に SSoT として切り出し、`/verify` / `/auto` Tier ラダー / `/auto` pr route item 8 (run-review exit 2) の 3 消費側から参照可能にする。既存の `skills/verify/SKILL.md` の inline 判定表は参照へ置換し、重複定義を残さない。

## Changed Files

- `modules/ci-failure-classifier.md`: 新規作成。CI プラットフォーム障害判定の SSoT。4-section 構造 (Purpose / Input / Processing Steps / Output)。判定シグネチャ表 (既存 4 件 + 本 Issue が挙げる 3 件)、verdict 3 値 (`ci-infra` / `implementation` / `undetermined`)、消費側ごとの応答表を持つ
- `skills/verify/SKILL.md`: Step 5 「Verification priority」Step 1 の inline 判定表を削除し、`${CLAUDE_PLUGIN_ROOT}/modules/ci-failure-classifier.md` への Read-and-follow 参照に置換 (「Fall back to local tests」の 4 手順と safe-side note は消費側固有の応答として残す)
- `modules/orchestration-fallbacks.md`: `## ci-wait-silence-timeout` の Fallback Steps 2 にある cross-reference `skills/verify/SKILL.md` Step 5 "Verification priority" Step 1 を `modules/ci-failure-classifier.md` へ repoint (判定表の移設に伴う参照先の追随。新規カタログエントリは追加しない — #1122 モラトリアム)
- `skills/auto/SKILL.md`: (a) Step 6 の External kill pre-check 直後に「CI platform failure pre-check (before Tier 1)」を追加、(b) Tier 3 の入力収集リストに CI 判定 verdict を追加、(c) pr route item 8 に CI 障害分岐を追加、(d) frontmatter `allowed-tools` の Bash パターンに `gh run list:*`, `gh run view:*`, `gh pr checks:*` を追加
- `agents/orchestration-recovery.md`: anomaly パターン表 (Step 3) に「CI platform outage」行を追加し、`Likely action` を `abort` とする (`retry` を選ばせない)
- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` の PENDING pre-check ブロック (line 721 付近) の pointer comment に `modules/ci-failure-classifier.md` への参照を 1 行追加 — bash 3.2+ compatible (コメント追加のみ、ロジック変更なし)
- `docs/workflow.md`: 「Review PENDING retry」段落に、exit 2 の原因が CI プラットフォーム障害と判定された場合はリトライを繰り返さず障害として分類する旨の 1 文を追加
- `docs/ja/workflow.md`: 上記の日本語ミラー同期 (line 118 付近)
- `docs/tech.md`: 環境変数表に `WHOLEWORK_CI_OUTAGE_RECHECK_SEC` と `WHOLEWORK_CI_OUTAGE_MAX_RECHECKS` の 2 行を追加 (`WHOLEWORK_REVIEW_PENDING_RETRY_SEC` の行に隣接させる)
- `docs/ja/tech.md`: 上記の日本語ミラー同期 (line 223 付近)
- `docs/structure.md`: Directory Layout の `modules/` カウントを `(41 files)` → `(43 files)` に更新 (実測 42 + 新規 1。41 は既存ドリフト — Notes 参照)、Key Files > Modules に `modules/ci-failure-classifier.md` の項目を追加
- `docs/ja/structure.md`: 上記の日本語ミラー同期。カウントは全角括弧の日本語書式 `（43 ファイル）` を維持 (line 21)、Key Modules 相当リスト (line 136 付近) に項目追加
- `tests/ci-failure-classifier.bats`: 新規作成。モジュール存在・4-section 構造・判定表シグネチャの存在、および `skills/verify/SKILL.md` に判定表が重複定義されていないこと (dedup ガード) を機械的に検証
- `tests/auto-recovery.bats`: 変更なし (AC4 の回帰ガードとして実行するのみ。`grep -n "ci-failure\|ci_infra" tests/auto-recovery.bats` は 0 件で、本変更の影響対象外であることを確認済み)

## Implementation Steps

1. `modules/ci-failure-classifier.md` を新規作成する (→ 受入条件 1)。4-section 構造 (Purpose / Input / Processing Steps / Output) に従う。
   - **Purpose**: CI プラットフォーム側の障害を、実装起因の失敗および harness 由来の kill と区別するための単一の判定基準を提供する。
   - **Input**: `PHASE` (失敗フェーズ名)、`PR_NUMBER` (省略可)、`HEAD_SHA` (省略可)、`WRAPPER_LOG_PATH` (省略可)。
   - **Processing Steps**: 以下の判定シグネチャ表 (exhaustive — 現時点で既知の CI プラットフォーム障害パターン) を置く。1〜4 は `skills/verify/SKILL.md` Step 5 から移設、5〜7 は本 Issue の実測 (#1206 / #1214 / session `41961-1785999585`) から追加する。

     | # | Signature | 観測方法 | Reasoning |
     |---|-----------|---------|-----------|
     | 1 | steps が空 (`steps: []`) | `gh run view <run-id> --json jobs` | ジョブが開始前に異常終了。テストコードは実行されていない |
     | 2 | Timeout (`cancelled` + 実行時間超過) | `gh pr checks --json bucket` が `cancel` | インフラ応答遅延による強制終了 |
     | 3 | Runner error (`The runner has received a shutdown signal`) | `gh run view --log-failed` | GitHub Actions runner の異常 |
     | 4 | Network error (`Unable to download`, `ECONNREFUSED`) | `gh run view --log-failed` | 依存ダウンロード失敗 |
     | 5 | head SHA に対する workflow run が生成されない | `gh run list --branch <head-ref> --limit 5` が当該 SHA の run を返さない | GitHub Actions 側が run をディスパッチしていない。push / rerun / PR close-reopen のいずれでも run が生成されない |
     | 6 | `Set up job` 段階での失敗 | `gh run view --log-failed` の最初の失敗ステップが `Set up job` | ワークフロー定義の解決またはランナー確保の段階で失敗しており、リポジトリのコードは実行されていない |
     | 7 | queued 停滞 | `gh pr checks --json bucket` が `pending` のまま、かつ `gh run list` の当該 run が `queued` から進まない | ランナーキューの滞留。時間経過だけでは解消しない場合がある |

   - **Output**: verdict を 3 値で返す (exhaustive)。`ci-infra` (シグネチャ 1 件以上に一致)、`implementation` (CI が確定状態 pass/fail に達しており、失敗が実装・テストコード由来)、`undetermined` (どちらとも判定できない — 安全側。消費側は既存の失敗扱いにフォールバックする)。
   - **Output** に消費側応答表 (exhaustive) を置く。各セルは応答の一行要約と参照先のみを書き、消費側の手順そのものは再掲しない (重複定義を作らない)。

     | Consumer | `ci-infra` のときの応答 | `implementation` / `undetermined` のときの応答 |
     |----------|------------------------|---------------------------------------------|
     | `skills/verify/SKILL.md` Step 5 Step 1 | ローカルテストへフォールバック (手順は同 Step に記載) | 既存の PASS / FAIL / UNCERTAIN 判定を継続 |
     | `skills/auto/SKILL.md` Step 6 CI platform failure pre-check | Tier 1/2/3 に入らず待機 → 再判定 → 未解消なら停止 (リトライしない) | Tier 1 へ通常どおり進む |
     | `skills/auto/SKILL.md` pr route item 8 (`run-review.sh` exit 2) | PENDING リトライループを打ち切り CI 障害として分類 | 既存の PENDING リトライ機構 (#1115) をそのまま適用 |
     | `agents/orchestration-recovery.md` (Tier 3) | `action=abort` (`retry` を選ばない) | 既存の anomaly パターン表に従う |

2. `skills/verify/SKILL.md` Step 5 「Verification priority」の `#### Step 1: CI Infrastructure Failure Detection (only when referencing CI results)` を書き換える (after 1) (→ 受入条件 1)。見出し直後の最初の段落に `Read ${CLAUDE_PLUGIN_ROOT}/modules/ci-failure-classifier.md and follow the "Processing Steps" section` の Read 指示を置き (Read 指示の配置ルール: 見出し直後の段落)、続けて「本モジュールが判定シグネチャの SSoT であり、ここに表を再掲しない」旨を明記する。既存の判定表 4 行 (`| Pattern | Reasoning |` の表) を削除する。既存の「**Fall back to local tests**」の 4 手順と末尾の `**Note**: The infrastructure failure determination errs on the safe side.` は消費側固有の応答として残し、判定の入口を「verdict が `ci-infra` のとき」に書き換える。

3. `modules/orchestration-fallbacks.md` の `## ci-wait-silence-timeout` セクション、`### Fallback Steps` の項目 2 (line 392) にある参照 `see \`skills/verify/SKILL.md\` Step 5 "Verification priority" Step 1 for the classification table` を `see \`modules/ci-failure-classifier.md\` for the classification table` に置換する (after 1, 2) (→ 受入条件 1)。シグネチャの列挙 (`steps: []`, `cancelled` + timeout, runner error, network error) はこの行から削除し、参照のみを残す (判定表の重複を残さない)。カタログエントリの新規追加は行わない。

4. `skills/auto/SKILL.md` Step 6 に `#### CI platform failure pre-check (before Tier 1)` を追加する (after 1) (→ 受入条件 2)。挿入位置は `#### External kill pre-check (before Tier 1)` セクションの末尾の水平線の直後、`#### Tier 1 (Observe): State Reconciliation` の直前。見出し直後の最初の段落に `Read ${CLAUDE_PLUGIN_ROOT}/modules/ci-failure-classifier.md and follow the "Processing Steps" section` の Read 指示を置く。分岐を全列挙して記述する。
   - **適用条件**: 失敗フェーズが CI 待機を伴う phase (`review`, `merge`) であり、かつ External kill pre-check が `no-match` を返している場合のみ。それ以外の phase では本 pre-check を実行せず Tier 1 へ進む。
   - **verdict = `ci-infra` の場合**: (a) `${WHOLEWORK_CI_OUTAGE_RECHECK_SEC:-600}` 秒待機して再判定する。(b) 再判定で verdict が `ci-infra` 以外になった場合、当該フェーズの `run-*.sh` を同一引数で 1 回だけ再実行し、通常フローに戻る。(c) 再判定を最大 `${WHOLEWORK_CI_OUTAGE_MAX_RECHECKS:-2}` 回繰り返してもなお `ci-infra` の場合、Tier 1/2/3 に入らず停止し、Step 6 末尾の停止バナーに `cause: ci-infra-outage` を明示する。(d) 停止時は `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery $NUMBER $PHASE respawn [EXIT_CODE] --cause ci-infra-outage-during-ci-wait` で記録する (pointer file 再生成の作法は External kill pre-check の Recording と同一)。
   - **verdict = `implementation` または `undetermined` の場合**: 何もせず Tier 1 へ進む (既存挙動を変更しない)。
   - **Tier 番号を増やさない**: External kill pre-check と同様、本 pre-check は Tier 1/2/3 の語彙の外側に置く。

5. `skills/auto/SKILL.md` Tier 3 の入力収集リスト (`1. Collect inputs:`) に `ci_failure_verdict`: Step 6 の CI platform failure pre-check が返した verdict (未実行の場合は空文字列) を追加し、あわせて `agents/orchestration-recovery.md` の Step 3 anomaly パターン表に 1 行追加する (after 1, 4) (→ 受入条件 2)。追加行は `| CI platform outage | 入力 \`ci_failure_verdict\` が \`ci-infra\`、または CI が確定状態に達していない | \`abort\` |` とし、表の直後の「when in doubt, prefer `abort`」の記述と整合させる。`validate-recovery-plan.sh` の `valid_actions` は `{retry, skip, recover, abort}` で `abort` を既に含むため、スクリプト側の変更は不要。

6. `skills/auto/SKILL.md` pr route item 8 (line 445) に CI 障害分岐を追加する (after 1) (→ 受入条件 3)。既存の PENDING リトライ機構 (sleep + 最大 2 回リトライ + `reconcile-phase-state.sh` フォールスルー、#1115 の成果) の記述はそのまま維持したうえで、リトライループに入る**前**の判定として次を挿入する: exit code が 2 の場合、まず `${CLAUDE_PLUGIN_ROOT}/modules/ci-failure-classifier.md` を Read して verdict を求める。verdict が `ci-infra` の場合は sleep + リトライを実行せず、Step 6 の CI platform failure pre-check と同じ待機 → 再判定 → 停止の経路に入る (リトライを繰り返さない)。verdict が `implementation` または `undetermined` の場合のみ、既存の `${WHOLEWORK_REVIEW_PENDING_RETRY_SEC:-300}` 秒 sleep + `${WHOLEWORK_REVIEW_PENDING_MAX_RETRIES:-2}` 回リトライを従来どおり適用する。

7. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、PENDING pre-check ブロック直上の既存コメント (line 721-725、`# modules/orchestration-fallbacks.md#review-pending-not-failure` で終わる) の末尾に、pointer comment 規約 (`modules/orchestration-fallbacks.md` § Pointer Comment Convention) に従って 1 行追加する (after 1, 6): `# CI-outage classification for this exit code 2: modules/ci-failure-classifier.md`。ロジックは変更しない (XL sub-issue route の bash 側は本 Issue では判定を実装せず、参照点のみを張る — Notes 参照)。

8. ドキュメント同期 (after 4, 6)。
   - `docs/workflow.md` line 125 の「Review PENDING retry」段落末尾に 1 文追加: exit code 2 の原因が CI プラットフォーム障害と判定された場合 (`modules/ci-failure-classifier.md` の verdict が `ci-infra`)、この sleep + retry は適用されず、待機 → 再判定 → 停止の経路に入る旨。
   - `docs/ja/workflow.md` line 118 の対応段落に同内容の日本語ミラーを追加する。
   - `docs/tech.md` line 242 付近の環境変数表に 2 行追加: `WHOLEWORK_CI_OUTAGE_RECHECK_SEC` (既定 `600`、CI プラットフォーム障害と判定した後の再判定までの待機秒数) と `WHOLEWORK_CI_OUTAGE_MAX_RECHECKS` (既定 `2`、再判定の最大回数)。いずれも `skills/auto/SKILL.md` Step 6 の CI platform failure pre-check が参照する旨と `modules/ci-failure-classifier.md` への参照を含める。
   - `docs/ja/tech.md` line 223 付近の同表に日本語ミラーを追加する。

9. `docs/structure.md` と `docs/ja/structure.md` を更新する (after 1)。
   - `docs/structure.md` line 28 の `├── modules/             # Shared modules referenced by skills (41 files)` を `(43 files)` に変更する (実測 42 + 新規 1)。
   - `docs/structure.md` の Key Files > Modules の箇条書きに `- \`modules/ci-failure-classifier.md\` — CI platform failure classification SSoT (signature table, 3-value verdict, per-consumer response)` を追加する。
   - `docs/ja/structure.md` line 21 の `（41 ファイル）` を `（43 ファイル）` に変更する (全角括弧の日本語書式を維持)。
   - `docs/ja/structure.md` の Key Modules 相当リスト (line 136 付近、`modules/orchestration-fallbacks.md` の項目の近傍) に日本語ミラーの項目を追加する。

10. テストを追加・実行する (after 1-9) (→ 受入条件 4)。
    - `tests/ci-failure-classifier.bats` を新規作成する。`@test` は 3 件 (exhaustive): (a) `"ci-failure-classifier: module has the 4 standard sections"` — `modules/ci-failure-classifier.md` に `## Purpose` / `## Input` / `## Processing Steps` / `## Output` の 4 見出しが存在すること。(b) `"ci-failure-classifier: signature table covers all 7 known patterns"` — 判定表に 7 件のシグネチャキーワード (`steps: []`, `cancelled`, `shutdown signal`, `ECONNREFUSED`, `workflow run`, `Set up job`, `queued`) がすべて含まれること。(c) `"ci-failure-classifier: verify SKILL.md does not duplicate the signature table"` — `skills/verify/SKILL.md` に `The runner has received a shutdown signal` が含まれず、かつ `modules/ci-failure-classifier.md` への参照が含まれること (dedup ガード)。パス解決は `$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)` 形式を用い、CWD 非依存にする。`WHOLEWORK_SCRIPT_DIR` のモックは不要 (新規スクリプトを追加しないため)。
    - `bats tests/ci-failure-classifier.bats` と `bats tests/auto-recovery.bats` の両方が PASS することを確認する。

## Verification

### Pre-merge

- <!-- verify: rubric "CI Infrastructure Failure Detection の判定基準が /verify 以外の消費側からも参照できる単一の参照点 (modules/ 配下のモジュール、または SSoT への参照リンク) を持ち、skills/verify/SKILL.md Step 5 と重複定義になっていない" --> 判定基準が単一の参照点を持つ
- <!-- verify: rubric "/auto の recovery ラダー (Tier 1/2/3) が CI プラットフォーム障害を判別した場合に、リトライではなく待機または停止を選ぶ経路が記述されている" --> Tier ラダーが CI 障害時にリトライを選ばない経路を持つ
- <!-- verify: rubric "skills/auto/SKILL.md:445 の既存 PENDING リトライ機構 (sleep + 最大 2 回リトライ + reconcile-phase-state フォールスルー、#1115 の成果) とは別に、exit 2 の原因が CI プラットフォーム障害 (workflow run が生成されない / Set up job 段階の失敗 / queued 停滞) であると判別された場合に、リトライを繰り返さず障害として分類する経路が記述されている" --> run-review.sh exit 2 の CI 障害ケースが既存 PENDING リトライ機構とは別に扱われている
- <!-- verify: command "bats tests/auto-recovery.bats" --> `tests/auto-recovery.bats` が PASS する

### Post-merge

- 次に CI プラットフォーム障害が発生した際、Tier 3 が `action=retry` を選ばず、親セッションの手読みなしに CI 障害として分類されることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Tool Dependencies

### Bash Command Patterns

- `gh run list:*`: head SHA に対する workflow run の生成有無と queued 状態の確認 (シグネチャ 5, 7)。`skills/auto/SKILL.md` の `allowed-tools` に未登録のため追加が必要
- `gh run view:*`: `--json jobs` による steps 空判定、`--log-failed` による runner / network / `Set up job` 失敗の確認 (シグネチャ 1, 3, 4, 6)。`skills/auto/SKILL.md` の `allowed-tools` に未登録のため追加が必要
- `gh pr checks:*`: bucket による cancel / pending 判定 (シグネチャ 2, 7)。`skills/auto/SKILL.md` の `allowed-tools` に未登録のため追加が必要

### Built-in Tools

- なし (`Read` / `Edit` / `Write` / `Grep` はいずれも `skills/auto/SKILL.md` および `skills/verify/SKILL.md` の `allowed-tools` に登録済み)

### MCP Tools

- なし

補足: `skills/verify/SKILL.md` の `allowed-tools` は既存の `gh api:*` / `gh pr view:*` で同等の観測が可能なため、追加は不要。`.claude/settings.json.template` の `permissions.allow` は `scripts/*` パターンのみを列挙しており生の `gh` サブコマンドを含まないため、こちらの更新も不要。`scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` は base tool 名 (Bash パターンではない) を対象とするため更新不要。

## Notes

### 設計判断 (Auto-Resolve Log — 非対話モード)

- **AC1 の「単一の参照点」の実装先: 新規モジュール `modules/ci-failure-classifier.md`** — reason: AC1 が「modules/ 配下のモジュール、または SSoT への参照リンク」を明示的に許容しており、かつ「重複定義になっていない」ことを要求している。既存コードベースでは横断的な判定基準を `modules/` の SSoT に置く規約が確立している (`modules/l0-surfaces.md`, `modules/phase-state.md`, `modules/verify-classifier.md`)。`skills/verify/SKILL.md` に表を残したまま anchor を張る案は、`/verify` 以外の消費側が SKILL.md の内部見出しに依存する構造 (現に `modules/orchestration-fallbacks.md:392` がこの形になっており脆い) を温存するため却下。
- **AC3 の適用範囲: prose (SKILL.md + モジュール) を主とし、bash (`scripts/run-auto-sub.sh`) は pointer comment のみ** — reason: 既存の `ci-wait-silence-timeout` カタログエントリ (#1221) も prose のみで `apply-fallback.sh` にハンドラを持たない前例がある。#1122 の補償層モラトリアムに従い、新規の bash 判定機構 (例: `classify-ci-failure.sh`) の追加は行わない。`modules/orchestration-fallbacks.md` § Pointer Comment Convention が「シェルスクリプトは inline ロジックを維持し pointer comment のみを持つ」と規定しており、これに従う。
- **Tier ラダーへの挿入位置: Tier 1 の前の pre-check** — reason: `skills/auto/SKILL.md:935` が「External kill pre-check は Tier 1/2/3 の語彙の外側に置き、新しい Tier 番号を導入しない」と明記している。CI 障害判定も同じ性質 (Tier 1 の reconciler では原因を判別できない外部要因) のため、同じ位置・同じ形式を踏襲する。

### 新規カタログエントリを追加しない理由

Issue 本文の Related に記載のとおり、本 Issue の主眼は既存判定表の参照可能化であり `modules/orchestration-fallbacks.md` への新規エントリ追加ではない (#1122 補償層モラトリアム)。既存の `ci-wait-silence-timeout` エントリは cross-reference の repoint のみを行う。

### `docs/structure.md` の modules カウントの既存ドリフト

`ls modules/*.md | wc -l` の実測は 42 だが `docs/structure.md` line 28 / `docs/ja/structure.md` line 21 はいずれも 41 と記載しており、本 Issue 着手前から 1 件のドリフトが存在する (計測範囲: `modules/` 直下の `.md` ファイル、2026-08-07 時点)。新規モジュール 1 件を加えた正しい値は 43 であるため、実装ではドリフトの是正も含めて 43 と書く。

### 実装/Issue 本文の整合性確認 (conflict detection)

Issue 本文の事実主張はいずれもコードベースと一致することを確認した。追加で判明した点として、`modules/orchestration-fallbacks.md#ci-wait-silence-timeout` (#1221 で追加) が既に `skills/verify/SKILL.md` Step 5 の判定表を cross-reference しており、「`/verify` 内でのみ使われる」という Issue 本文の記述は厳密には「判定表の定義が `/verify` の SKILL.md 内にあり、他の消費側は SKILL.md の内部見出しへの文字列参照に依存している」状態を指す。この参照も本 Issue の実装で新モジュールへ repoint する (実装ステップ 3)。

### bats テストの入力形式

`tests/ci-failure-classifier.bats` はスクリプトではなく Markdown ファイルを検証対象とするため、入力データ形式はプレーンな Markdown (見出し `##` / `####`、`|` 区切りのテーブル行) である。判定は `grep -q` によるリテラル文字列マッチで行い、テーブルの列順や整形には依存させない。

### verify command と Notes の整合

上記の設計判断はいずれも `## Verification > Pre-merge` の 4 件の verify command と矛盾しない。AC1 の rubric が要求する「重複定義になっていない」は実装ステップ 2 (inline 表の削除) と実装ステップ 10(c) (dedup ガードの bats テスト) の両方で担保される。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — 非対話モードでの Auto-Resolve Log (AC3 の rubric text を既存 PENDING リトライ機構を明示的に除外する形へ具体化、Post-merge observation AC に `session=next` を付与)。AC1/AC2 の rubric と AC4 は修正不要と確認済み / https://github.com/saitoco/wholework/issues/1227#issuecomment-5216881303

## issue retrospective

**Non-interactive mode**: `--non-interactive` で実行。ambiguity 検出では Issue レベルで判断が必要な新規の曖昧ポイントは見つからず (Background の事実主張はすべてコードベースと一致確認済み、AC1/AC2 の実装先ファイル選択は `/issue` (What) と `/spec` (How) の責務境界に従い `/spec` に委譲するのが適切と判断)、以下 2 件は監査コメント/機械チェックに基づく一意に解決可能な修正として自動適用した。

### Auto-Resolve Log

- **AC3 の rubric text を具体化** — reason: 直前の triage AC audit コメント (2026-08-07) が Pattern 2 (常時 PASS 懸念) を指摘。`skills/auto/SKILL.md:445` に既存の PENDING リトライ機構 (#1115 の成果) が既にあり、grader がこれを「exit 2 経路の扱いが記述されている」と解釈すると実装 0 行で PASS しうるため、コメントが提示した修復案をそのまま採用し、既存機構を明示的に除外した rubric text に変更した。
  - Other candidates: 修復せず現状維持 (Pattern 2 の懸念を残したまま) — 却下。監査コメントが具体的な修復案を提示済みで、他に妥当な選択肢がない。
- **Post-merge の observation AC に `session=next` を付与** — reason: `scripts/check-skill-change-observation-ac.sh` が exit 2 (要対応) を検出。Issue body が `skills/verify/SKILL.md` / `skills/auto/SKILL.md` を参照しており、この Issue 自体がそれらの SKILL.md を変更対象とする可能性が高いため、self-update propagation (wholework 自己ホスティングによりスキル内容は会話セッション単位でキャッシュされる) の対象になる。
  - Other candidates: なし — 機械チェックが検出した必須修正で選択の余地はない。

修正なしで問題なしと確認した項目: AC1・AC2 の rubric (audit コメントで「常時 PASS ではない」と確認済み)、AC4 (`tests/auto-recovery.bats` は既存ファイルで Pattern 6.5 を満たす)。

## spec retrospective

### Minor observations

- Issue 本文は「判定表は `/verify` 内でのみ使われる」と述べているが、実際には `modules/orchestration-fallbacks.md#ci-wait-silence-timeout` (#1221 で追加) が既に `skills/verify/SKILL.md` Step 5 の内部見出しを文字列参照している。「参照されていない」のではなく「SKILL.md の内部見出しへの脆い文字列参照に依存している」が正確な現状であり、これは本 Issue が解こうとしている問題の実例そのものだった。Issue 本文の主張は方向として正しく、修正ではなく Spec の Notes に補足として記録した。
- `docs/structure.md` の `modules/` カウントは実測 42 に対し 41 と記載されており、本 Issue 着手前から 1 件のドリフトがあった。新規モジュール追加のたびにカウント更新が必要な設計上、この種のドリフトは再発しやすい。`/audit drift` が拾う想定だが、実測値との突合を Spec 段階で行ったことで是正機会になった。
- `skills/auto/SKILL.md` の `allowed-tools` に `gh run list:*` / `gh run view:*` / `gh pr checks:*` がいずれも未登録だった。CI 状態を観測する pre-check を `/auto` に追加する以上これらは必須であり、skill-dev-constraints の「New gh command patterns in allowed-tools」(#75) に該当する。判定ロジックの設計に気を取られると見落としやすい種類の依存。

### Judgment rationale

- AC1 の「単一の参照点」を新規 `modules/` モジュールとして実装する判断は、AC 文言が 2 案 (モジュール / 参照リンク) を許容していたため曖昧ポイントだった。既存 SSoT モジュール群 (`l0-surfaces.md`, `phase-state.md`, `verify-classifier.md`) の規約と、`orchestration-fallbacks.md:392` が示す「SKILL.md 内部見出しへの参照は脆い」という実例の 2 点で一意に決まると判断し、非対話モードの auto-resolve として確定した。
- AC3 を bash (`scripts/run-auto-sub.sh`) にも実装するかは判断が割れうる点だった。#1122 の補償層モラトリアムと、`ci-wait-silence-timeout` が prose のみで `apply-fallback.sh` ハンドラを持たない前例の 2 点から、prose 主体 + pointer comment に留めた。XL sub-issue route の bash 側は判定を持たないままになるが、これは意図的な範囲限定として Notes に明記した。
- 新規環境変数 2 件 (`WHOLEWORK_CI_OUTAGE_RECHECK_SEC` / `WHOLEWORK_CI_OUTAGE_MAX_RECHECKS`) を導入し、固定値埋め込みを選ばなかった。実測された障害が約 5 時間継続しており待機間隔が運用上の調整対象になるため。代償として `docs/tech.md` + `docs/ja/tech.md` の環境変数表 2 ファイルが Changed Files に加わる。

### Uncertainty resolution

- Tier 3 sub-agent が `action=abort` を返せるかは実装確認が必要な点だった。`scripts/validate-recovery-plan.sh:41` の `valid_actions = {"retry", "skip", "recover", "abort"}` を読み、`abort` が既に有効値であることを確認したためスクリプト側の変更は不要と確定した。
- `.claude/settings.json.template` の `permissions.allow` に生の `gh` サブコマンドを追加する必要があるかは不明だったが、実ファイルを読んだところ `scripts/*` パターンのみを列挙する方針であることが判明し、更新不要と確定した。

## Code Retrospective

### Deviations from Design

- N/A — 実装ステップ 1〜10 は Spec の記述どおりの順序・内容で実施した。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

### Test Execution Note

- Behavioral Change Detection (Step 9) の条件に合致したため `bats --jobs 18 tests/` を複数回実行したところ、`tests/post_merge_check.bats` の2テスト (`fail: gh issue reopen called when FAIL input given` / `multiple issues: processed sequentially`) が間欠的に FAIL した。単体実行 (`bats tests/post_merge_check.bats`) では毎回 10/10 PASS し、当該テストファイルおよびテスト対象の `scripts/post_merge_check.sh` はいずれも本 Issue の diff に含まれていない。フル並列実行時のみ再現する resource contention 由来の既存 flake と判断し、本 Issue のスコープでは対応しなかった。AC4 の対象である `tests/auto-recovery.bats` は単体・フル実行のいずれでも 5/5 PASS で安定している。

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の Tool Dependencies (Bash Command Patterns) は「`gh run list:*`/`gh run view:*`/`gh pr checks:*` は `skills/auto/SKILL.md` の allowed-tools に未登録のため追加が必要」とだけ記述し、Built-in Tools 節では「`skills/verify/SKILL.md` の allowed-tools に登録済み」と誤って記載していた。実装フェーズはこの記述をそのまま信頼し、`skills/verify/SKILL.md` 側への追加を行わなかった。review でこのギャップ (SHOULD) が検出され修正した。**教訓**: 同一モジュールを複数消費者が参照する Issue では、Tool Dependencies の allowed-tools チェックを消費者ごとに独立して明記する (「登録済み」という記述は実ファイルの grep で都度検証し、Spec 記述をそのまま信用しない)。
- SSoT モジュール化 (AC1) の意図は「単一の参照点、重複定義なし」だったが、実装は `skills/verify/SKILL.md` の inline 表のみを置換し、`modules/verify-executor.md` § 3a に同一の4パターン判定表が独立して残っていた。bats dedup guard (`tests/ci-failure-classifier.bats`) も `skills/verify/SKILL.md` のみを対象にしており、この重複を検出できなかった。rubric grader は Issue 本文の記述範囲 (「`skills/verify/SKILL.md` Step 5 と重複定義になっていない」) に忠実に判定したため AC1 は PASS したが、Issue の意図 (単一の参照点) は完全には満たされていなかった。**教訓**: 「SSoT 化」系の Issue では、対象モジュールへの参照元を `grep -rl` 等で網羅的に洗い出し、dedup guard のテスト対象ファイルリストを Issue 起票時点ではなく実装完了時点で確定させる。

### Recurring issues

- 新しいフィールド (`ci_failure_verdict`) をプロンプト経由で渡す変更が、呼び出し側 (`skills/auto/SKILL.md` の収集リスト・spawn 節) では追加されたが、受け取り側 (`agents/orchestration-recovery.md` の `## Input` 契約セクション) には反映されなかった。同種のギャップは review-bug/review-spec の両エージェントが独立に検出しており (収束的シグナル)、「呼び出し元の変更と契約定義側の変更が同期していない」という構造的パターン。**教訓**: sub-agent への新規入力フィールド追加は、呼び出し元と `## Input` 契約の両方を同一コミットで変更するチェックリスト項目として明示する価値がある。
- 「同一イベントを2箇所で記録する」際の識別子 (cause slug: `ci-infra-outage` vs `ci-infra-outage-during-ci-wait`) が Spec 段階から不一致だった (`docs/spec/issue-1227-ci-failure-classifier.md:59` の記述をそのまま実装に転記)。CONSIDER として記録し今回は見送ったが、Spec レビュー段階でこの種の「同一概念に複数の表記」を検出する仕組みがあれば防げた。

### Acceptance criteria verification difficulty

- AC1〜AC3 はいずれも `rubric` 判定であり、静的な dedup guard (bats) が持つ「網羅性」を rubric grader 自身は持たない (grader は Issue 本文で明示された対象ファイルのみを見る傾向がある)。3体の review エージェント (review-spec, review-bug×2) が独立に `modules/verify-executor.md` の重複を検出できたのは、PR diff 全文と changed files 一覧を主体的に走査する診断フローだったため。rubric 単独では検出できなかった可能性が高い。
- 検証段階で「到達不能な条件分岐」という指摘 (review-spec と review-bug の両方から独立に提起) が誤検知と判明した (`scripts/run-auto-sub.sh` → `spawn-recovery-subagent.sh` という XL/batch route の存在を見落としていた)。この route は本 Issue の diff に変更がなく PR diff だけでは見えないため、Adversarial verification 段階で `grep`/コードベース横断確認を行わなければ誤って MUST/SHOULD として確定していた可能性がある。2段階検証 (finder → verifier) の価値を裏付ける事例。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- Step 8 の4 pre-merge AC (すべて rubric/command) は全て PASS と判定し、Issue チェックボックスは変更なし (既に `[x]` 済み)。
- Step 10 は `capabilities.workflow: true` かつ fork context (`--non-interactive`、再呼び出し保証なし) のため Workflow path をスキップし、静的 Task fan-out (review-spec + review-bug×2、`run_in_background: false`) を採用した。
- MUST issue は0件 (event=COMMENT)。SHOULD 6件のうち検証で確度の高かった6件すべてを Step 12 で修正 (allowed-tools 追加、PGID ポインタ再生成、再判定ループ明確化、Input 契約追加、verify-executor.md 重複解消、Per-Consumer Response 表への消費者追加)。CONSIDER 4件と SHOULD 1件 (docs/structure.md の verify command 追加提案) は見送り、PR コメントに理由を記録した。

### Deferred Items

- `docs/structure.md`/`docs/ja/structure.md` の modules count 用 verify command を Issue #1227 の AC に追加する提案 (SHOULD) — Issue 本文編集が必要なため本 PR のスコープ外。フォローアップ Issue の要否は次フェーズ判断。
- CONSIDER 4件 (cause slug 不一致、RECOVERY_TYPE `respawn` 誤用、fall-through 文のインデント曖昧性、signature #5/#7 の dwell threshold 欠如) は未対応。実害は限定的と判断したが、CI 障害が頻発する場合は再評価対象。
- `docs/structure.md` の `tests/` count drift (95→実測112、本 Issue 対象外) は `/audit drift` に委譲。

### Notes for Next Phase

- `/merge` 前に CI (全9ジョブ SUCCESS) と MUST issue (0件) の両方をクリアしている。
- 修正コミット5件はいずれも `Refs:` で元のレビュー指摘 (PR inline comment または Review URL) を参照済み。
- `bats --jobs 18 tests/` フル並列実行時の `tests/post_merge_check.bats` 間欠的 FAIL は本 PR の変更対象外の既知 flake (Code Retrospective 参照)。`/merge`/`/verify` が遭遇した場合はこの記録を参照してよい。
