# Issue #854: auto: loop-state / auto-events-rollup の cross-session 日次集約を完全廃止し session 別 data-layer.md に集約

## Overview

`docs/sessions/_daily/` 配下の cross-session 日次集約 view (`loop-state-{DATE}.md` / `auto-events-rollup-{DATE}.md`) を完全廃止し、SSoT 構造を単純化する。

- **データ層 SSoT**: `.tmp/auto-events.jsonl` のみ
- **view 層 SSoT**: `docs/sessions/{ID}-{DATE}/{data-layer.md,session.md,events.jsonl}` (session 内 view)
- **cross-session view**: 生成しない (必要時は session 別ファイルを直接読む)

廃止に伴い、(1) 関連スクリプト 2 本と bats test 2 本を削除、(2) heartbeat / rollup 呼び出しを run-*.sh / `skills/auto/SKILL.md` から除去、(3) `get-auto-session-report.sh` の period aggregate モードを削除して session 別単独 view に集約 (5 セクション保証)、(4) その impact chain (`/audit auto-session` period mode・`docs/sessions/_period/` 記述・workflow docs・ファイル数カウント) を整理する。

## Changed Files

**削除 (`git rm`):**
- `scripts/append-loop-state-heartbeat.sh`: delete
- `scripts/auto-events-rollup.sh`: delete
- `tests/append-loop-state-heartbeat.bats`: delete
- `tests/auto-events-rollup.bats`: delete
- `docs/sessions/_daily/loop-state-*.md` (4 件) + `docs/sessions/_daily/auto-events-rollup-*.md` (9 件) = 計 13 ファイル: delete。空になった `docs/sessions/_daily/` ディレクトリも削除

**スクリプト改修 (bash 3.2+ 互換):**
- `scripts/run-code.sh`: 成功時の `append-loop-state-heartbeat.sh` 呼び出し (`if [[ $EXIT_CODE -eq 0 ]]` ガードブロック lines 273-275 付近) を除去 — bash 3.2+ 互換
- `scripts/run-review.sh`: 同上 (line 161 付近の呼び出しとガードブロック) を除去 — bash 3.2+ 互換
- `scripts/run-merge.sh`: 同上 (line 195 付近) を除去 — bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: `_append_loop_state_heartbeat()` 関数 (lines 195-204 付近)・専用ヘルパ (`_loop_state_from_phase` / `_loop_state_to_phase` が本関数専用なら) ・全呼び出し箇所を除去 — bash 3.2+ 互換
- `scripts/check-verify-dirty.sh`: built-in ignore-path への `docs/sessions/_daily/loop-state-*.md` / `docs/sessions/_daily/auto-events-rollup-*.md` 追加 (lines 62-66 付近) を除去 (`verify-ignore-paths` config 由来の動的追加ロジックは維持) — bash 3.2+ 互換
- `scripts/get-auto-session-report.sh`: (a) period aggregate モード (`--day` / `--since-days` / `--range`) のパース (lines 70-82)・処理ブロック (lines 95-290)・usage コメント (lines 8-19 の period 行) を除去 (per-session report モードと `--since` list モードは維持)。(b) per-session report が 5 セクションを含むよう強化 (下記 Implementation Steps Step 5 参照) — bash 3.2+ 互換

**test 改修:**
- `tests/run-code.bats`: `side-effect: append-loop-state-heartbeat.sh called on code phase success` の `@test` ブロックと MOCK 生成 (lines 498-507 付近) を除去
- `tests/run-review.bats`: 同上 (lines 375-384 付近) を除去
- `tests/run-merge.bats`: 同上 (lines 554-563 付近) を除去
- `tests/verify-dirty-detection.bats`: built-in exempt 系 4 `@test` (`loop-state heartbeat only dirty` / `loop-state mixed with non-spec dirty` / `auto-events-rollup only dirty` / `auto-events-rollup mixed with non-spec dirty`, lines 139-173 付近) を除去
- `tests/audit-auto-session.bats`: period 系 `@test` (`--day generates _period report` / `--since-days generates _period since report`, lines 185-240 付近) を除去。section rename に伴い `per-issue durations` を検証する `@test` (line 20 付近) のアサーションを `Sub-Issue Completion Timeline` に更新
- `tests/get-auto-session-report.bats`: section rename / 新 section 追加に伴うアサーション更新 (旧 `Per-Issue Durations` 検証箇所があれば `Sub-Issue Completion Timeline` に更新、新 section `Phase Activity Summary` / `Token Usage Aggregate` のアサーションを追加)

**SKILL / module / doc 改修:**
- `skills/auto/SKILL.md`: (a) `allowed-tools` から `${CLAUDE_PLUGIN_ROOT}/scripts/append-loop-state-heartbeat.sh:*` / `${CLAUDE_PLUGIN_ROOT}/scripts/auto-events-rollup.sh:*` を除去。(b) 各 phase 成功時の `append-loop-state-heartbeat.sh` 呼び出し記述 (lines 360, 369, 391, 396, 400, 409 付近) を除去。(c) `auto-events-rollup.sh` 実行記述 (lines 699, 1126 付近) を除去。(d) `## Loop State Heartbeat` セクション全文 (lines 701-734 付近) を削除。(e) next-cycle-seed の `loop-state-{DATE}.md` row append step (line 1152 付近) を除去 (代替: 既存の `next_cycle_seeded` event emit + L3 session.md narrative)
- `skills/audit/SKILL.md`: `/audit auto-session` の period aggregate モード (`--day` / `--since Nd` / `--range`) 記述を除去 (frontmatter description line 3、mode 判定 lines 23/27、auto-session Subcommand の period セクション lines 864-938 付近、`_period/` 参照)。per-session モード + list モードのみ残す (`allowed-tools` の `get-auto-session-report.sh:*` は維持)
- `modules/verify-executor.md`: 廃止済み `auto-events-rollup.sh` を実在スクリプトとして参照する例示 (lines 132-136) を、実在スクリプト or 汎用プレースホルダに差し替え
- `modules/verify-patterns.md`: 廃止済み `append-loop-state-heartbeat.sh` を実在スクリプトとして参照する例示 (lines 545, 553, 825) を、実在スクリプト or 汎用プレースホルダに差し替え (過去事例参照は過去形/「(削除済み)」注記でも可)
- `docs/structure.md`: Directory Layout の `_daily/` + `_period/` サブツリー (lines 69-75 付近) を削除、Scripts 一覧の `auto-events-rollup.sh` エントリ (line 193) を削除、ファイル数カウント `scripts/ ... (62 files)` → `(60 files)` (line 32)・`tests/ ... (93 files)` → `(91 files)` (line 45) を更新
- `docs/ja/structure.md`: Directory Layout の `_daily/` + `_period/` サブツリー (lines 62-65 付近) を削除、Scripts 一覧の `auto-events-rollup.sh` エントリ (line 186) を削除 (ja/structure.md にはファイル数カウントなし)
- `docs/workflow.md`: `/audit auto-session` 説明 (line 166) から period aggregate モード (`--day` / `--since {N}d` / `--range` → `docs/sessions/_period/`) の記述を除去
- `docs/ja/workflow.md`: `/audit auto-session` 説明 (line 159) から同記述を除去 (docs/workflow.md の mirror)

**変更不要 (grep 確認済み・Exclusions 参照):** `docs/tech.md` / `docs/ja/tech.md` (`get-auto-session-report.sh` の `WHOLEWORK_ISSUE_BODY_DIR` 参照は per-session モードで存続)、`scripts/validate-skill-syntax.py` (KNOWN_TOOLS に廃止スクリプト不在)、`README.md` / `CLAUDE.md` (参照なし)。

## Implementation Steps

1. 廃止スクリプトと bats test を `git rm` で削除: `scripts/append-loop-state-heartbeat.sh` / `scripts/auto-events-rollup.sh` / `tests/append-loop-state-heartbeat.bats` / `tests/auto-events-rollup.bats` (→ acceptance criteria 1, 2, 3, 4)

2. run-*.sh から heartbeat 呼び出しを除去 (after 1): `run-code.sh` / `run-review.sh` / `run-merge.sh` の `if [[ $EXIT_CODE -eq 0 ]]` ガードブロック内の `append-loop-state-heartbeat.sh` 呼び出しを (ガードがその呼び出し専用なら) ブロックごと除去。`run-auto-sub.sh` は `_append_loop_state_heartbeat()` 関数本体・本関数専用ヘルパ・全呼び出し箇所を除去。bash 3.2+ 互換を維持 (→ acceptance criteria 8)

3. run-*.bats の heartbeat side-effect test を除去 (after 2): `tests/run-code.bats` / `tests/run-review.bats` / `tests/run-merge.bats` の `side-effect: append-loop-state-heartbeat.sh called ...` `@test` と対応 MOCK 生成を削除。削除する scenario は廃止 feature 専用のため別 test での再カバーは不要 (#526) (→ acceptance criteria 17)

4. `scripts/check-verify-dirty.sh` の built-in ignore-path 追加 (`docs/sessions/_daily/loop-state-*.md` / `docs/sessions/_daily/auto-events-rollup-*.md`, lines 62-66 付近) を除去し、`verify-ignore-paths` config 由来の動的ロジックは維持。あわせて `tests/verify-dirty-detection.bats` の built-in exempt 系 4 `@test` (lines 139-173 付近) を除去 (parallel with 1) (→ acceptance criteria 11, 17)

5. `scripts/get-auto-session-report.sh` を改修 (parallel with 1): (a) period aggregate モード (`--day` / `--since-days` / `--range`) のパース・処理ブロック・usage コメントを除去し per-session report + `--since` list モードのみ残す。(b) per-session report の出力 heredoc が以下 5 セクション (相当の表) を含むよう強化 — `## Phase Activity Summary` (新規: phase_start/phase_complete を phase 別に集計した表) / `## Sub-Issue Completion Timeline` (既存 `## Per-Issue Durations` を rename し Route 列・Recovery 列を強化) / `## Token Usage Aggregate` (新規: token_usage event を issue 別に集計; event schema に issue 粒度が無い場合は session 合計でフォールバック) / `## Verify Phase Residuals` (既存維持) / `## Recovery Events` (既存維持)。既存の `## Summary` / `## Concurrent Sessions Detected` / `## Improvement Candidates Surfaced` は保持してよい。bash 3.2+ 互換 (→ acceptance criteria 6, 7)

6. get-auto-session-report 系 bats を更新 (after 5): `tests/audit-auto-session.bats` の period 系 `@test` (lines 185-240 付近) を除去し、section rename に伴う旧 `Per-Issue Durations` アサーションを `Sub-Issue Completion Timeline` に更新。`tests/get-auto-session-report.bats` も同様に section 名アサーションを更新し、新 section (`Phase Activity Summary` / `Token Usage Aggregate`) のアサーションを追加。削除する period scenario は廃止 feature 専用のため再カバー不要 (#526) (→ acceptance criteria 17)

7. `skills/auto/SKILL.md` を改修 (parallel with 1): `allowed-tools` から 廃止 2 スクリプトのエントリを除去 / 各 phase の heartbeat 呼び出し記述を除去 / `auto-events-rollup.sh` 実行記述 (lines 699, 1126 付近) を除去 / `## Loop State Heartbeat` セクション全文 (lines 701-734 付近) を削除 / next-cycle-seed の `loop-state-{DATE}.md` row append step を除去 (代替は既存 `next_cycle_seeded` event + L3 session.md)。半角 `!` / triple backtick / YAML block scalar を新規導入しないこと (validate-skill-syntax.py 制約) (→ acceptance criteria 5)

8. `skills/audit/SKILL.md` + workflow docs から period mode を除去 (parallel with 1): `skills/audit/SKILL.md` の frontmatter description (line 3)・mode 判定 (lines 23, 27)・auto-session Subcommand の period セクション (lines 864-938 付近)・`_period/` 参照を除去し per-session / list モードのみ残す (frontmatter は単一行維持)。`docs/workflow.md` (line 166) / `docs/ja/workflow.md` (line 159) の `/audit auto-session` 説明から period aggregate モード記述を除去 (→ acceptance criteria 15)

9. `modules/verify-executor.md` (lines 132-136) と `modules/verify-patterns.md` (lines 545, 553, 825) の例示を、廃止スクリプトを実在スクリプトとして参照しない形に差し替え (実在スクリプト or 汎用プレースホルダ; 過去事例は過去形/「(削除済み)」注記可) (parallel with 1) (→ acceptance criteria 14)

10. structure docs 更新 + `_daily/` 実ファイル削除 (after 1): `docs/structure.md` の `_daily/`+`_period/` Directory Layout サブツリー (lines 69-75)・`auto-events-rollup.sh` Scripts エントリ (line 193) を削除し、ファイル数カウントを `(62 files)`→`(60 files)` (line 32) / `(93 files)`→`(91 files)` (line 45) に更新。`docs/ja/structure.md` も同様 (lines 62-65, 186; ja はカウントなし)。`docs/sessions/_daily/*.md` 13 ファイルを `git rm` し空の `docs/sessions/_daily/` ディレクトリを削除 (→ acceptance criteria 9, 10, 12, 13, 16)

## Verification

### Pre-merge

- <!-- verify: file_not_exists "scripts/append-loop-state-heartbeat.sh" --> `scripts/append-loop-state-heartbeat.sh` が削除されている
- <!-- verify: file_not_exists "scripts/auto-events-rollup.sh" --> `scripts/auto-events-rollup.sh` が削除されている
- <!-- verify: file_not_exists "tests/append-loop-state-heartbeat.bats" --> `tests/append-loop-state-heartbeat.bats` が削除されている
- <!-- verify: file_not_exists "tests/auto-events-rollup.bats" --> `tests/auto-events-rollup.bats` が削除されている
- `skills/auto/SKILL.md` から `append-loop-state-heartbeat` / `auto-events-rollup` の呼び出しおよび `## Loop State Heartbeat` セクションが除去されている <!-- verify: rubric "skills/auto/SKILL.md に append-loop-state-heartbeat.sh / auto-events-rollup.sh の呼び出し記述および ## Loop State Heartbeat セクション全文が存在しない" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "append-loop-state-heartbeat" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "auto-events-rollup.sh" --> <!-- verify: file_not_contains "skills/auto/SKILL.md" "loop-state-" -->
- <!-- verify: rubric "scripts/get-auto-session-report.sh の period aggregate モード (--day / --since-days / --range) のパラメータ解析・処理ロジックが削除されており、session 別単独実行モードのみ残っている" --> `scripts/get-auto-session-report.sh` から `--day` / `--since-days` / `--range` モードが削除されている
- <!-- verify: rubric "scripts/get-auto-session-report.sh が生成する data-layer.md に Phase Activity / Sub-Issue Completion Timeline / Token Usage Aggregate / Verify Phase Residuals / Recovery Events の 5 セクション (相当の表) が含まれており、cross-session 集約ではなく session 別単独 view として完結している" --> `scripts/get-auto-session-report.sh` が session 別 data-layer.md として Phase Activity / Sub-Issue Completion Timeline / Token Usage Aggregate / Verify Phase Residuals / Recovery Events の 5 セクションを含む report を生成する
- `scripts/run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` から `append-loop-state-heartbeat.sh` 呼び出しが除去されている <!-- verify: file_not_contains "scripts/run-code.sh" "append-loop-state-heartbeat" --> <!-- verify: file_not_contains "scripts/run-review.sh" "append-loop-state-heartbeat" --> <!-- verify: file_not_contains "scripts/run-merge.sh" "append-loop-state-heartbeat" --> <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "append-loop-state-heartbeat" -->
- <!-- verify: rubric "docs/sessions/_daily/ 配下に loop-state-*.md および auto-events-rollup-*.md ファイルが残存していない (ls docs/sessions/_daily/loop-state-*.md および ls docs/sessions/_daily/auto-events-rollup-*.md が空)" --> `docs/sessions/_daily/` 配下の `loop-state-*.md` および `auto-events-rollup-*.md` ファイルが全て削除されている
- <!-- verify: dir_not_exists "docs/sessions/_daily" --> `docs/sessions/_daily/` ディレクトリが削除されている
- `scripts/check-verify-dirty.sh` の built-in ignore-path から `loop-state-*.md` / `auto-events-rollup-*.md` 参照が除去されている <!-- verify: file_not_contains "scripts/check-verify-dirty.sh" "loop-state-" --> <!-- verify: file_not_contains "scripts/check-verify-dirty.sh" "auto-events-rollup-" -->
- `docs/structure.md` から `docs/sessions/_daily/` ディレクトリ記述および `auto-events-rollup.sh` / `loop-state-` 参照が除去されている <!-- verify: file_not_contains "docs/structure.md" "_daily/" --> <!-- verify: file_not_contains "docs/structure.md" "auto-events-rollup.sh" --> <!-- verify: file_not_contains "docs/structure.md" "loop-state-" -->
- `docs/ja/structure.md` も同様に更新されている <!-- verify: file_not_contains "docs/ja/structure.md" "_daily/" --> <!-- verify: file_not_contains "docs/ja/structure.md" "auto-events-rollup.sh" --> <!-- verify: file_not_contains "docs/ja/structure.md" "_period" -->
- `modules/verify-executor.md` および `modules/verify-patterns.md` の例示が廃止スクリプトを実在するスクリプトとして参照していない <!-- verify: rubric "modules/verify-executor.md および modules/verify-patterns.md に廃止済みの auto-events-rollup.sh / append-loop-state-heartbeat.sh を実在するスクリプトとして参照している記述が残存していない" -->
- `skills/audit/SKILL.md` / `docs/workflow.md` / `docs/ja/workflow.md` から `/audit auto-session` の period aggregate モード (`--day` / `--since Nd` / `--range`) の記述が除去され、per-session / list モードのみが残っている <!-- verify: rubric "skills/audit/SKILL.md / docs/workflow.md / docs/ja/workflow.md から /audit auto-session の period aggregate モード (--day / --since Nd / --range) の記述および _period 出力先参照が除去され、per-session モードと list モードのみが残っている" --> <!-- verify: file_not_contains "skills/audit/SKILL.md" "_period" --> <!-- verify: file_not_contains "docs/workflow.md" "_period" --> <!-- verify: file_not_contains "docs/ja/workflow.md" "_period" -->
- `docs/structure.md` から `_period/` ディレクトリ記述が除去され、scripts / tests のファイル数カウントが更新されている (scripts 62→60 / tests 93→91) <!-- verify: file_not_contains "docs/structure.md" "_period" --> <!-- verify: grep "(60 files)" "docs/structure.md" --> <!-- verify: grep "(91 files)" "docs/structure.md" -->
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats test が緑のまま

### Post-merge

- 次回 `/auto $N` 実行後、`docs/sessions/{ID}-{DATE}/data-layer.md` が rollup 相当の 5 セクションを含む形で生成されることを観察 <!-- verify-type: observation event=auto-run -->
- 次回 `/auto $N` 実行で `docs/sessions/_daily/` に新ファイルが生成されないことを観察 <!-- verify-type: observation event=auto-run -->

## Tool Dependencies

本 Issue は既存ツールの **削除** が中心で、新規 `allowed-tools` 追加は不要。

### Bash Command Patterns
- none (新規追加なし。`git rm` / `grep` 等は既存権限で実行可能)

### Built-in Tools
- none (`Read` / `Edit` / `Write` / `Bash` は既存)

### MCP Tools
- none

## Notes

### Conflict with implementation (period mode 廃止の impact chain)

- **内容**: AC #6 は `scripts/get-auto-session-report.sh` の `--day` / `--since-days` / `--range` (period aggregate) モード削除を必須とするが、Issue 本文「廃止対象」の file list には consumer 側が含まれていなかった。
- **Issue 本文の前提**: 「`scripts/get-auto-session-report.sh`: `--day` / `--since-days` / `--range` モード削除 (session 別単独実行のみ残す)」
- **実装側の実態**: `skills/audit/SKILL.md` (lines 3, 23, 27, 864-938) が `/audit auto-session --day / --since Nd / --range` を script の period mode に delegate し、`tests/audit-auto-session.bats` (lines 185-240) が `--day` / `--since-days` を直接テスト。`docs/structure.md` (72-75) / `docs/ja/structure.md` (65) / `docs/workflow.md` (166) / `docs/ja/workflow.md` (159) が `_period/` を記載。
- **自動解決 (non-interactive)**: full 廃止 (script + audit skill + period test + `_period` docs + workflow docs) を採用。Issue Notes の「cross-session view 機能の代替策は不要... 必要になれば別途 `get-auto-session-report.sh --day` を再実装する別 Issue」記述から、cross-session 集約の完全廃止が intent と判断。impact chain の AC を追加 (audit period・structure `_period`/カウント・workflow `_period`)。詳細は issue retrospective comment の Auto-Resolve Log 参照。

### 5-section data-layer.md の design 判断

- 現行 report の 6 セクション (`Summary` / `Per-Issue Durations` / `Recovery Events` / `Verify Phase Residuals` / `Concurrent Sessions Detected` / `Improvement Candidates Surfaced`) を、AC #7 要求の 5 section 名にマッピング:
  - `Phase Activity Summary` ← 新規 (phase 別 activity 集計)
  - `Sub-Issue Completion Timeline` ← `Per-Issue Durations` を rename + Route/Recovery 列強化
  - `Token Usage Aggregate` ← 新規 (issue 別 token 集計; schema に issue 粒度が無ければ session 合計でフォールバック)
  - `Verify Phase Residuals` / `Recovery Events` ← 既存維持
- 既存の追加 section (`Summary` / `Concurrent Sessions` / `Improvement Candidates`) は削除不要 (rubric は 5 section の存在のみ要求)。
- section rename は既存 bats アサーション (`tests/audit-auto-session.bats` line 20, `tests/get-auto-session-report.bats`) に影響するため同時更新が必要 (Step 6)。

### next-cycle-seed の loop-state row append 代替

- `skills/auto/SKILL.md` の batch path E (line 1152 付近) は loop-state row append + `next_cycle_seeded` event emit の二重記録。loop-state row append を除去し、SSoT である `next_cycle_seeded` event (auto-events.jsonl) + L3 session.md narrative で代替 (`file_not_contains "loop-state-"` を満たす)。

### skill-dev 制約

- `skills/auto/SKILL.md` / `skills/audit/SKILL.md` 編集時、半角 `!` / triple backtick / YAML block scalar を新規導入しないこと (validate-skill-syntax.py MUST 制約)。audit frontmatter description は単一行を維持。
- `scripts/validate-skill-syntax.py` の KNOWN_TOOLS に廃止スクリプトは未登録 (grep 確認済) のため KNOWN_TOOLS 更新は不要。

### verify command 補足

- `grep "(60 files)" "docs/structure.md"` / `grep "(91 files)" "docs/structure.md"` は ripgrep ERE。`(...)` はグループ扱いで literal "60 files" / "91 files" にマッチする (parens は file 側の隣接文字として一致)。spec 作成時点では未存在の文字列で、Step 10 で /code が導入する。
- `verify-ignore-paths` config 由来の `loop-state-*.md` / `auto-events-rollup-*.md` エントリは互換のため明示削除せず黙認 (Issue Notes 準拠)。

## Exclusions

以下は廃止シンボルを参照するが、**historical record / 非 load-bearing context** のため変更対象外:

- `docs/spec/*.md` (過去 spec ファイル群) — 過去の設計記録
- `docs/sessions/{ID}-{DATE}/*.md` (過去 session retrospective) — 過去の実行記録
- `docs/reports/loop-engineering-wholework-2026-06-18.md` / `docs/ja/reports/loop-engineering-wholework-2026-06-18.md` — 日付付き過去レポート
- `docs/reports/event-log-schema.md` (line 232) — `--narrative-draft` 廃止 (#776) の過去経緯としての参照 (period mode 非参照)
- `skills/spec/SKILL.md` (lines 323, 337) — symbol-impact-discovery の teaching example (過去の path migration を例示する instruction 本文)
- `skills/code/skill-dev-validation.md` (line 104) — `auto-events-rollup.sh` cleanup を「ある原則の発端 (PR #644 / #638)」として参照する歴史的 attribution。原則自体はスクリプト削除後も factual に成立
- `docs/tech.md` / `docs/ja/tech.md` — `get-auto-session-report.sh` の `WHOLEWORK_ISSUE_BODY_DIR` env var 参照は per-session モードで存続するため変更不要

## issue retrospective

(transferred from issue comment — `/issue` phase)

### 修正した verify コマンドエラー

- **`file_exists_not` → `file_not_exists` (4箇所)**: サポートコマンド表に `file_exists_not` は存在しない。正しいコマンドは `file_not_exists`。対象は廃止スクリプト 2 本 / 廃止 bats 2 本の削除確認 AC。
- **`command "bats tests/"` → `github_check "gh pr checks" "Run bats tests"`**: Size L は PR ルートのため `command` verify ではなく `github_check` を使用 (`modules/verify-classifier.md` 準拠)。`test.yml` の job 名 "Run bats tests" 確認済。

### 追加した AC (/issue phase)

- **`run-*.sh` heartbeat 呼び出し除去**: Proposal 明記だが AC 未記載。4 スクリプト全てで呼び出し確認済。
- **`docs/structure.md` / `docs/ja/structure.md` 更新**: Proposal 明記。各参照を `file_not_contains` で確認。
- **`dir_not_exists "docs/sessions/_daily"`**: 「空になれば削除」明記。13 ファイル存在のため削除確認 AC が必要。
- **`check-verify-dirty.sh` の `auto-events-rollup-` チェック**: line 63-66 に両パターンの ignore_paths があるが既存 AC は `loop-state-` のみ。
- **`skills/auto/SKILL.md` の補助 `file_not_contains`**: rubric だけでは allowed-tools / next-cycle-seed の loop-state append が漏れる可能性を補完。
- **`modules/verify-executor.md` / `modules/verify-patterns.md` 更新**: dangling reference 化を rubric で確認。

### Post-merge AC への verify-type 追加

- 「次回 `/auto $N` 実行後」は `auto-run` イベント駆動の observation 型 → `<!-- verify-type: observation event=auto-run -->` を 2 件に追加。

## spec retrospective

### Minor observations

- `/issue` phase は多数の AC を追加したが、**period mode 削除の consumer 側 impact chain** (`/audit auto-session` period delegation・`tests/audit-auto-session.bats` period test・`_period` docs・workflow docs・structure.md ファイル数カウント) を捕捉していなかった。AC が「スクリプトの feature 削除」を要求するとき、`/issue` 段階でも delegating skill / test / docs の impact chain を scan すべき (feature deletion impact chain は spec だけの責務ではない)。
- 「session 別 data-layer.md format 強化」の 5 section は、現行 report に既に Verify Phase Residuals / Recovery Events が存在し、Per-Issue Durations / Summary が Sub-Issue Completion Timeline / Phase Activity 相当として流用可能だった。Issue 本文の「(新規)」表記は一部不正確 (既存を rename/強化で達成可能)。

### Judgment rationale

- **period mode の full 廃止採用**: Issue Notes「必要になれば別途 `get-auto-session-report.sh --day` を再実装する別 Issue」が full 廃止 intent を示す。script-only 削除では `/audit auto-session --day` が runtime error + dangling docs を残し、`tests/audit-auto-session.bats` の period test で CI red になるため却下。
- **5-section の最小変更マッピング**: rubric は 5 section の「存在」のみ要求し他 section 削除は不要。よって既存 6 section を保持しつつ rename (Per-Issue Durations → Sub-Issue Completion Timeline) + 新規 2 section (Phase Activity Summary / Token Usage Aggregate) で達成。
- **issue body への impact-chain AC 追加**: verify-sync rule (Spec は Issue AC を verbatim mirror) と count alignment を満たすため、impact-chain の検証可能性を issue body 側に追加。Step 6 conflict は Notes + Auto-Resolve Log comment にも記録。

### Uncertainty resolution

- **Token Usage Aggregate の粒度**: `token_usage` event に issue/phase 粒度が含まれるか未確認。含まれない場合は session 合計フォールバックを spec で許容 (rubric は session 別単独 view を要求するが per-sub-issue 細分は必須でない)。`/code` で event schema を確認すること。
- **section rename の test 影響**: `Per-Issue Durations` → `Sub-Issue Completion Timeline` の rename は既存 bats アサーション (`tests/audit-auto-session.bats` line 20, `tests/get-auto-session-report.bats`) を破壊するため同時更新が必須と確定。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- period mode (`--day`/`--since-days`/`--range`) は full 廃止 (script + `skills/audit/SKILL.md` + `tests/audit-auto-session.bats` period test + `_period` docs + workflow docs)。Issue Notes の再実装は別 Issue 前提。
- 5-section data-layer.md は既存 6 section を rename/追加でマッピング (既存追加 section は保持)。
- next-cycle-seed の `loop-state-{DATE}.md` row append は廃止し、既存 `next_cycle_seeded` event + L3 session.md narrative で代替。

### Deferred Items
- 過去 phase/verify 残置 Issue の `phase/done` 一括移行 (本 Issue scope 外、merge 後の cleanup として実施)。
- session 別 view の format 詳細 (色/絵文字/列順等の UI) は別 Issue。
- `.wholework.yml` `verify-ignore-paths` の loop-state/rollup エントリは互換のため明示削除せず黙認。

### Notes for Next Phase
- **section rename の test 同時更新必須**: `tests/audit-auto-session.bats` (line 20 付近) / `tests/get-auto-session-report.bats` の旧 section 名アサーションを更新しないと CI red。
- **validate-skill-syntax.py 制約**: `skills/auto/SKILL.md` / `skills/audit/SKILL.md` 編集時に半角 `!` / triple backtick / YAML block scalar を新規導入しない。audit frontmatter description は単一行維持。
- **Token Usage Aggregate**: `token_usage` event schema に issue 粒度が無ければ session 合計でフォールバック (`/code` で schema 確認)。
- **`run-auto-sub.sh`**: 単純な呼び出し行ではなく `_append_loop_state_heartbeat()` 関数 + 専用ヘルパ + 全呼び出し箇所を除去 (`file_not_contains "append-loop-state-heartbeat"` を満たす)。
- 削除する bats `@test` の scenario は廃止 feature 専用のため別 test での再カバー不要 (#526)。

## code retrospective

### What was implemented

7 commits, 1021 bats tests green:

1. `git rm` 4 files: `scripts/append-loop-state-heartbeat.sh`, `scripts/auto-events-rollup.sh`, `tests/append-loop-state-heartbeat.bats`, `tests/auto-events-rollup.bats`
2. Removed heartbeat call sites from `scripts/run-code.sh`, `scripts/run-review.sh`, `scripts/run-merge.sh`, `scripts/run-auto-sub.sh` (functions `_loop_state_from_phase`/`_loop_state_to_phase`/`_append_loop_state_heartbeat` + 4 call sites)
3. Removed heartbeat side-effect tests from `tests/run-code.bats`, `tests/run-review.bats`, `tests/run-merge.bats`
4. Removed built-in ignore-paths from `scripts/check-verify-dirty.sh`; removed corresponding 4 `@test` blocks from `tests/verify-dirty-detection.bats`
5. Rewrote `scripts/get-auto-session-report.sh`: removed period aggregate mode (`--day`/`--since-days`/`--range`), added Phase Activity Summary / Sub-Issue Completion Timeline (rename from Per-Issue Durations) / Token Usage Aggregate sections; Token Usage uses session-total fallback (event schema lacks per-issue granularity)
6. Updated `tests/audit-auto-session.bats`: removed period `@test` blocks, updated "Per-Issue Durations" → "Sub-Issue Completion Timeline"; updated `tests/get-auto-session-report.bats`: added 5-section assertions
7. Removed heartbeat/rollup references from `skills/auto/SKILL.md` (allowed-tools, phase completions, Loop State Heartbeat section, next-cycle-seed step)
8. Removed period aggregate mode from `skills/audit/SKILL.md` (frontmatter description, routing, Argument Parsing, Step 1/Step 2); updated `docs/workflow.md` / `docs/ja/workflow.md`
9. Replaced dangling `auto-events-rollup.sh`/`append-loop-state-heartbeat.sh` refs in `modules/verify-executor.md` / `modules/verify-patterns.md`
10. Updated `docs/structure.md` / `docs/ja/structure.md`: removed `_daily/`/`_period/` directory entries, removed `auto-events-rollup.sh` entry, updated file counts (62→60 scripts, 93→91 tests); `git rm` 13 `docs/sessions/_daily/*.md` files

### Minor surprises

- `run-auto-sub.sh` had 3 helper functions for heartbeat (`_loop_state_from_phase`, `_loop_state_to_phase`, `_append_loop_state_heartbeat`) plus 4 call sites inside `run_phase_with_recovery` — more invasive than expected but cleanly removable without affecting recovery logic
- Token Usage Aggregate: `token_usage` events in `auto-events.jsonl` lack per-issue granularity; session-total fallback was spec-permitted and implemented as described

## review retrospective

### Spec vs. implementation divergence patterns

The code phase replaced dangling references to deleted scripts (`auto-events-rollup.sh` / `append-loop-state-heartbeat.sh`) in `modules/verify-executor.md` and `modules/verify-patterns.md` with substitute scripts. However, the substitutions were factually inaccurate:
- `verify-executor.md`: replaced with `scripts/run-auto-sub.sh`, but the listed CLI options (`--date|--input|--output-dir|--cleanup`) don't exist in that script
- `verify-patterns.md`: replaced "Real example" script with `scripts/emit-event.sh`, but that script doesn't call `git commit -s`

Root cause: when replacing a deleted script reference in a doc example, the code phase used plausible-looking replacements without verifying that the specific behavior cited (CLI options, git operations) actually exists in the replacement script. The `/review` phase caught both with a SHOULD-level finding and fixed them.

Improvement opportunity: when the Spec says "replace dangling references to deleted scripts with existing scripts or placeholders," the code phase should grep for the specific behavior cited in the example before choosing a replacement.

### Recurring issues

Nothing to note. All other changes were clean deletions with no functional issues.

### Acceptance criteria verification difficulty

All `file_not_exists` / `file_not_contains` / `dir_not_exists` ACs verified cleanly. The rubric ACs for period mode removal and 5-section report were verified by direct code inspection (no grep misses). The `github_check "Run bats tests"` AC completed after CI finished.

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Fixed 2 SHOULD issues (factually incorrect script references in doc examples): verify-executor.md ERE example now uses `collect-recovery-candidates.sh --threshold|--issues-json`; verify-patterns.md "Real example" now uses `append-consumed-comments-section.sh`.
- Skipped 1 CONSIDER issue (PHASE_ACTIVITY_TABLE jq field name `starts` vs. header "Event count"): functional impact is zero.

### Deferred Items
- `phase/done` bulk migration for stale phase/verify Issues (scope-out from issue #854)
- per-session view format details (UI) — separate issue
- `.wholework.yml` `verify-ignore-paths` loop-state/rollup entries (黙認 per spec)

### Notes for Next Phase
- All pre-merge ACs PASS including CI green. Ready for merge.
- No MUST issues found. Post-merge ACs are observation-type (event=auto-run) — handled by verify at next /auto run.

## Consumed Comments
No new comments since last phase.

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec  | pr    | SUCCESS | run-spec.sh exit 0 (spec creation), 2nd run also exit 0 (LLM correctly detected spec already complete, refused to re-create) |
| code  | pr    | SUCCESS | PR #870 created after batch resume |
| review (full) | pr | SUCCESS | 2 SHOULD fixed, 1 CONSIDER skipped |
| merge | pr    | SUCCESS (manual recovery) | run-merge.sh が silent no-op で 2 回失敗 (claude exit 0 / PR OPEN)。原因は #859 マージで main が進み rebase conflict 発生。手動で rebase main → modify/delete conflict 解決 (delete 採用) → force-push → gh pr merge --squash 実行 |
| verify | -    | SUCCESS (pre-merge全PASS) | post-merge observation 2 件は次回 /auto 実行待ち |

### Orchestration Anomalies
- **#854 spec を /auto --batch で開始 → 別 issue (#859) の verify を並列処理で実行 → main が進む → #854 が conflicting に**: List mode の direct sequential 実行と、verify Skill 内での parallel session の影響が衝突源となった
- **merge silent no-op パターン (#859 でも観察された同種問題が再発)**: claude exit 0 だが PR は OPEN のまま。Tier 3 sub-agent は retry を指示したが retry も同パターンで失敗。最終的にプロセスが SIGTERM kill (exit 143)
- **conflict 解決手順**: `cd .claude/worktrees/merge+pr-870 && git rebase origin/main` → modify/delete conflict (`docs/sessions/_daily/loop-state-2026-06-29.md` deleted in #854 commit, modified in main) → `git rm` で削除側採用 → `git rebase --continue` → `git push --force-with-lease` → CI 再 pass → `gh pr merge --squash` で merge 成功

### Improvement Proposals
- **silent no-op + conflict 検出と自動 fallback の組み合わせ**: `run-merge.sh` が silent no-op で失敗した時、`gh pr view --json mergeable` を確認し CONFLICTING の場合は Tier 2 fallback として「rebase main + modify/delete conflict 自動 resolution (deletes win for files deleted in PR but modified in main) + push + retry merge」を catalog 化
- **silent no-op の早期 escalation**: 同じ phase (merge/code) で 2 回連続 silent no-op + retry → Tier 3 abort のパターンが頻発。1 回目の silent no-op 検出時点で「LLM 自己診断モード」(プロセス kill 前に reconcile 結果と前回コマンドを LLM に渡して push/PR create 必要性を判断させる) を試行する catalog エントリ追加
- **batch + verify Skill 並列実行による race condition の文書化**: List mode で verify が main を更新中に次の Issue の code phase が動くと conflict が出やすい。SKILL.md または `docs/guide/customization.md` に「verify中は次 Issue 開始を待つ」または「verify は batch 完了後にまとめて」という運用パターンを明示

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 大規模廃止 Issue (17 pre-merge AC) を細かく分割せず 1 Spec で扱った。各 AC が明確で実装/検証ともスムーズ。
- spec 再実行を LLM が正しく検出してスキップ (existing spec を尊重) — `/spec` の defensive design が機能した好例。

#### design
- impact chain (period mode 削除 → audit skill / workflow docs / structure.md counts) を Auto-Resolved Ambiguity Points で先回り解決。後段 phases に rework なし。

#### code
- 11 commits で 20 ファイル変更 (scripts 2 削除 / tests 2 削除 / SKILL.md 大幅整理 / docs 更新)。サイズの大きさにも関わらず 1 PR で完結。

#### review
- 2 SHOULD (factually incorrect script refs in doc examples) を auto-fix。`docs/reports/loop-state-` 等の dead path への参照を historical context として残すべきか実在 script として参照しているのかの境界が曖昧で、review が境界判断を補完した。

#### merge
- silent no-op + conflict の組み合わせが Tier 1/2/3 all-fail → 手動回復 (rebase + delete-side + force-push + gh pr merge)。Tier 2 catalog に該当エントリなし、Tier 3 sub-agent は retry → 同パターン再失敗で abort 判断もできず SIGTERM。
- (Improvement Proposals 参照)

#### verify
- pre-merge 17 件全 PASS。observation 2 件 (auto-run 待ち) は次回 /auto 実行で自動 check。

### Improvement Proposals
- (Auto Retrospective の Improvement Proposals 参照: silent no-op + conflict fallback、early escalation、verify race 運用文書化)
