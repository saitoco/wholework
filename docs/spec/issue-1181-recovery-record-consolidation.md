# Issue #1181: run-auto-sub: manual recovery の記録先を recoveries.md に集約し Spec 書き込みと deferred stash を撤去

## Overview

`scripts/run-auto-sub.sh` は recovery 記録を 3 箇所 (sub-issue Spec の `## Auto Retrospective` / `docs/reports/orchestration-recoveries.md` / `manual_intervention` イベント) へ書き込んでおり、さらに open PR 検出時は Spec 書き込みを `.tmp/deferred-recovery-records-<issue>.md` へ退避して後から転記する経路 (#1150) を持つ。Spec 書き込みには機械的な消費者が存在せず、この分岐の多さが `retro/verify` Issue の系列 (#1049 / #1094 / #1150 / #1152 / #1153 / #1155) を生んでいる。

本 Issue では **Spec 書き込み経路 (manual / Tier 2 / Tier 3 の 3 関数) と deferred stash 経路を撤去**し、run-auto-sub.sh 側の recovery 記録先を `docs/reports/orchestration-recoveries.md` と `manual_intervention` イベントの 2 経路に絞る。既存 Spec ファイルに記録済みの内容には一切手を触れない (コード削除のみで、過去の記録は破壊されない)。

記録の欠落は発生しない:

- **manual recovery**: `_write_manual_recovery_to_recoveries_log()` が recoveries.md へ書き込み、`collect-recovery-candidates.sh` が消費する経路はそのまま残る
- **Tier 3**: `spawn-recovery-subagent.sh` が `write_recovery_entry()` で recoveries.md へ直接書き込む経路が既に存在する (`scripts/run-auto-sub.sh` の Tier 3 ブロックが commit/push まで行う)
- **Tier 2**: 親 `/auto` セッションの Step 4a Source 1 (`fallback-catalog`) が recoveries.md を session-level SSoT として書き込む。XL route の場合、サブ issue 単位の recovery 履歴は親 Spec の `## Auto Retrospective > Parallel Execution Issues` に集約される

`## Auto Retrospective` セクションという概念自体は撤去しない。親 `/auto` Step 4a が M/L/patch route の異常検知時および XL route で書き込み、`modules/retro-proposals.md` が `### Improvement Proposals` を読む経路は現状のまま維持される。本 Issue が撤去するのは **run-auto-sub.sh の bash 経路によるサブ issue Spec への直接書き込み**のみである。

## Changed Files

- `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_spec()` / `_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` / `_defer_recovery_record()` / `_flush_deferred_recovery_records()` / `_deferred_recovery_records_file()` と、それらの専用ヘルパー `_open_pr_for_issue()` / `_spec_has_changes()` を削除。全呼び出し箇所を削除し、`--write-manual-recovery` dispatch に `_validate_recovery_args` の明示呼び出しを追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: Spec 書き込み / deferred stash 専用テスト 12 件を削除、記録先を recoveries.md に読み替えるテスト 5 件を更新、setup の `gh pr list --search` モック分岐を削除 — bash 3.2+ 互換
- `scripts/emit-event.sh`: `recovery_record_deferred` イベントのドキュメントブロック (28-36 行付近) を削除 — bash 3.2+ 互換
- `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` セクション (アンカー名は維持) の Fallback Steps / Rationale を「recoveries.md + event の 2 経路」へ書き換え。Operational Notes 配下の `### Tier 2 bash path: Spec Auto Retrospective write` / `### Manual path: Spec Auto Retrospective write` / `### Tier 3 bash path: Spec Auto Retrospective write` の 3 小節を統合・書き換え。`#external-kill-parent-respawn` からの参照文 (548 行付近) を更新
- `skills/auto/SKILL.md`: Step 4a の「Source 1 note — XL route only」(568 行付近) から Tier 2/3 の Spec 書き込み前提を削除。「Manual recovery hand-off」(1046 行付近) の "records the recovery in three places" と deferred stash の記述を 2 経路の記述へ変更
- `skills/verify/SKILL.md`: Step 12 の「Tier 2/3/Manual automatic recovery handling」(814 行付近) から `_write_manual_recovery_to_spec()` への言及を削除し、run-auto-sub.sh 由来の recovery は recoveries.md が SSoT である旨へ更新 (過去 Spec の既存エントリは引き続き "already recorded" 扱い)
- `docs/tech.md`: Architecture Decisions の「Parent-session manual respawn」箇条書き (56 行) から Spec 書き込み・deferred stash の記述を削除
- `docs/ja/tech.md`: 上記 (47 行) の対応する日本語訳を同内容へ更新 (`docs/translation-workflow.md` の Sync Procedure に従い同一コミットで変更)
- `docs/workflow.md`: 「External kill respawn」(121 行) に記録先が recoveries.md と `manual_intervention` イベントである旨を明示
- `docs/ja/workflow.md`: 上記 (114 行) の対応する日本語訳を同内容へ更新
- `docs/reports/external-kill-investigation.md`: **変更不要** — 55 行の記述は「`--write-manual-recovery` が recoveries.md と `manual_intervention` イベントも書くようになった」という内容で、変更後も正しい (grep で確認済み)
- `docs/structure.md` / `docs/ja/structure.md`: **変更不要** — [Steering Docs sync candidate] `run-auto-sub.sh` の記述は "run auto workflow for sub-issues" のみで記録先に言及しない (grep で確認済み)
- `docs/guide/customization.md` / `docs/ja/guide/customization.md`: **変更不要** — `run-auto-sub` / `deferred-recovery-records` の記述なし (grep で確認済み)

## Implementation Steps

1. `scripts/run-auto-sub.sh` から `_deferred_recovery_records_file()` / `_defer_recovery_record()` / `_flush_deferred_recovery_records()` / `_write_manual_recovery_to_spec()` の 4 関数定義 (`_spec_has_changes()` 定義の直後〜`_search_recoveries_issue()` 定義の直前の範囲) を削除する。`docs/spec/` 配下の既存ファイルには一切手を触れない (→ 受入条件 1, 2, 3, 4, 5)
2. `--write-manual-recovery` dispatch から `_flush_deferred_recovery_records` 呼び出しと `_write_manual_recovery_to_spec` 呼び出しを削除し、代わりに引数パースループ直後 (`source "$SCRIPT_DIR/emit-event.sh"` の直前) へ `_validate_recovery_args "$_mr_issue" "$_mr_phase" "$_mr_recovery_type" "$_mr_exit_code"` を追加する (after 1) (→ 受入条件 1)
   - **必須**: 現状は `_write_manual_recovery_to_spec()` 内の `_validate_recovery_args` 呼び出しが `set -e` 経由で不正引数時の非ゼロ終了を担っている。この呼び出しを移設しないと `tests/run-auto-sub.bats` の `validate: --write-manual-recovery rejects ...` 系 6 テストが全て失敗する
3. `_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` の関数定義と、`run_phase_with_recovery()` 内の呼び出し (Tier 2 ブロック / Tier 3 ブロック)、およびスクリプト末尾の `_flush_deferred_recovery_records "$SUB_NUMBER"` を削除する。Tier 2 ブロックでは `_fallback_meta_file` 変数を削除し `apply-fallback.sh` の stdout を `/dev/null` へリダイレクトする (`mkdir -p .tmp` は Tier 3 の recovery-plan 用に残す) (after 1) (→ 受入条件 1, 2, 3, 4)
4. 不要になった `_open_pr_for_issue()` / `_spec_has_changes()` の関数定義を削除する (影響チェーン: 削除後に他の参照が残っていないことを `grep -n '_open_pr_for_issue\|_spec_has_changes' scripts/run-auto-sub.sh` で確認する) (after 1, 3) (→ 受入条件 1)
5. `scripts/emit-event.sh` の `recovery_record_deferred` イベント定義コメントブロック (`kind=` / `open_pr=` の 2 行を含む) を削除する (parallel with 1, 3, 4) (→ 受入条件 3)
6. `tests/run-auto-sub.bats` から Spec 書き込み / deferred stash 専用テスト 12 件を削除する (after 1, 3, 4) (→ 受入条件 3, 8)
   - `tier2 recovery: writes Auto Retrospective to spec file` / `tier3 recovery: writes Auto Retrospective to spec file`
   - `tier2 recovery: defers to .tmp ... (#1150)` / `tier3 recovery: defers to .tmp ... (#1150)`
   - `manual recovery: flushes previously deferred records ... (#1150)` / `main flow flushes previously deferred recovery records ... (#1150)`
   - `manual recovery: writes Auto Retrospective to spec file` / `manual recovery: defers spec write (instead of discarding) when an open PR exists for the issue`
   - `tier2 recovery: commits when spec file is untracked` / `tier3 recovery: commits when spec file is untracked` / `manual recovery: commits when spec file is untracked`
   - `manual recovery: skips spec write entirely when no spec exists (no stub created)`
   - `tier2 recovery during review phase records real Issue number, not PR number (issue #984)` は Spec 書き込みのみが前提のため削除 (Tier 3 側の同名テストは Step 7 で更新して残す)
7. `tests/run-auto-sub.bats` の以下 4 件を recoveries.md 経路へ読み替えて更新する (after 6) (→ 受入条件 8)
   - `tier3 recovery during review phase records real Issue number, not PR number (issue #984)`: Spec ファイルへのアサーション 3 行を削除し、`--record-issue 42` と `Record Tier 3 recovery event for issue #42 review phase` のアサーションを残す
   - `manual recovery: pre-pull preserves a remote-added entry alongside the local one (no record loss)`: fixture と assertion を `docs/reports/orchestration-recoveries.md` に付け替える (`git pull --ff-only` モックが remote 由来エントリを追記し、ローカル追記分と共存することを確認)
   - `push retry: non-fast-forward push succeeds after one fetch+rebase retry` / `push retry: gives up after 3 attempts and warns but continues`: commit/push のトリガを recoveries.md の dirty 判定 (`git diff --quiet ... orchestration-recoveries.md` → exit 1) に変更し、後者の期待警告文言を `WARNING: could not commit/push manual recovery log` に変更する
8. `tests/run-auto-sub.bats` の `manual recovery: reissue after PR merge completes the spec write without duplicating the recoveries log entry` を、open PR モック分岐を使わない「24 時間以内の同一 recovery 再実行で recoveries.md エントリが 1 件のまま」の dedup 回帰テストへ簡素化し、テスト名も内容に合わせて更新する。あわせて setup の gh モックから `pr list --search` 分岐とその `_open_pr_for_issue()` 参照コメントを削除する (after 6) (→ 受入条件 3, 8)
9. `modules/orchestration-fallbacks.md` を更新する: `## manual-recovery-spec-write` セクションの Fallback Steps 3/4 を「recoveries.md + `manual_intervention` イベントの 2 経路」へ書き換え、open-PR guard と deferred stash の記述を削除。Rationale に本 Issue (#1181) での方針転換を追記。Operational Notes 配下の Tier 2 / Manual / Tier 3 の 3 小節を、Spec 書き込みを含まない形へ書き換える。`#external-kill-parent-respawn` の手順 3 の参照文も整合させる。**アンカー `#manual-recovery-spec-write` は改名しない** (parallel with 1-8) (→ 受入条件 6)
10. ドキュメント 6 ファイルを実装と一致させる: `skills/auto/SKILL.md` (Step 4a Source 1 note、Manual recovery hand-off)、`skills/verify/SKILL.md` (Step 12 の recovery 記録扱い)、`docs/tech.md` および `docs/ja/tech.md` (Parent-session manual respawn の箇条書き)、`docs/workflow.md` および `docs/ja/workflow.md` (External kill respawn に記録先を明示)。en/ja は同一コミットに含める (after 9) (→ 受入条件 6, 7, 9)

## Verification

### Pre-merge

- <!-- verify: rubric "--write-manual-recovery が docs/reports/orchestration-recoveries.md のみに書き込み、sub-issue Spec への書き込みを行わなくなっている" --> 記録先が recoveries.md のみになっている
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "_recovery_to_spec" --> Spec 書き込み関数 3 種 (manual / tier2 / tier3) が run-auto-sub.sh から削除されている
- <!-- verify: rubric "deferred stash 経路 (.tmp/deferred-recovery-records-<issue>.md の生成と転記) が run-auto-sub.sh から削除され、対応する bats も削除または更新されている" --> deferred stash 経路が撤去されている
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "deferred-recovery-records" --> deferred stash ファイルへの参照が run-auto-sub.sh に残っていない
- <!-- verify: rubric "既存 Spec ファイルに記録済みの Auto Retrospective エントリが削除・改変されていない (過去の記録を破壊しない)" --> 既存 Spec の記録が保持されている
- <!-- verify: rubric "skills/auto/SKILL.md・docs/tech.md・docs/workflow.md・modules/orchestration-fallbacks.md#manual-recovery-spec-write およびそれらの docs/ja 翻訳の記述が、3 箇所書き込みの前提から新しい記録先の記述へ更新されている" --> ドキュメントの記述が実装と一致している
- <!-- verify: command "bash scripts/test-skills.sh" --> skill 構文検証が PASS する
- <!-- verify: command "bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/run-auto-sub.bats" --> run-auto-sub の bats スイートが PASS する
- <!-- verify: command "bash scripts/check-translation-sync.sh" --> docs/ja 側の翻訳が同期している

### Post-merge

- external kill 発生後の `--write-manual-recovery` 呼び出しで、recoveries.md に記録が残り Spec が変更されないことを観察する

## Tool Dependencies

### Bash Command Patterns
- なし (新規スクリプト追加なし。既存の `allowed-tools` で充足)

### Built-in Tools
- なし (`Read` / `Edit` / `Grep` はいずれも登録済み)

### MCP Tools
- なし

## Notes

**実装との矛盾 (Conflict with implementation):**

- Issue 本文 (更新前) の Pre-merge AC 5 は「<!-- verify: command "bash scripts/test-skills.sh" --> skill 構文検証と bats スイートが PASS する」と記述していたが、`scripts/test-skills.sh` の実装は `python3 scripts/validate-skill-syntax.py skills/` のみを実行し bats を一切起動しない。この矛盾を放置すると bats の回帰が pre-merge で検出されないため、AC を 2 件に分離し Issue 本文も更新した (非対話モードにつきモデル判断で自動解決)。
- 分離後の bats AC は `bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/run-auto-sub.bats` 形式を採る。実測で直列実行は 73 秒であり `command` verify の 60 秒タイムアウトを超過する (`--jobs 4` で 48 秒、論理コア数指定で 38 秒)。並列指定の書式は `modules/verify-executor.md` の `command` 行に記載された可搬形式に一致する。

**Tier 2 / Tier 3 の Spec 書き込みを撤去してよい根拠 (記録の欠落なし):**

| 経路 | 撤去後の recoveries.md 記録者 |
|---|---|
| manual | `_write_manual_recovery_to_recoveries_log()` (run-auto-sub.sh 内、維持) |
| Tier 3 | `scripts/spawn-recovery-subagent.sh` の `write_recovery_entry()` (既存) |
| Tier 2 | 親 `/auto` Step 4a Source 1 `fallback-catalog` (session-level SSoT) |

Tier 2 のみ bash 経路での recoveries.md 書き込みを持たないが、これは本 Issue 以前からの状態であり、本 Issue で新たに欠落が生じるわけではない。bash 経路での Tier 2 event 記録の是非は #1098 (Tier 2/3 recovery の発火 event 記録) が追跡しており、そちらの scope に委ねる。

**`manual_intervention` イベントを残す判断 (対応方針 3):** L3 セッション retrospective の Metrics 行 `Parent session manual interventions` が消費するため無条件に維持する。#1098 は Tier 2/3 の recovery event を追加する方向の Issue であり、本 Issue の「event は残す」判断と矛盾しない。

**`--cause` / `--diagnosis` を維持する判断 (対応方針 4):** #1179 は方針 1 (`.wholework.yml` の `recoveries-auto-fire.enabled` を既定 opt-out に戻す) を採用し、方針 3 (#1123 の group-key 細分化撤回) は明示的に不採用とした (`docs/spec/issue-1179-recoveries-auto-fire-disable.md` の Notes 49 行に「`--cause` / `--diagnosis` フラグは撤去しない」と記載)。したがって本 Issue でも撤去しない。

**アンカー `#manual-recovery-spec-write` を改名しない判断:** `docs/reports/orchestration-recoveries.md` の既存エントリ 38 件が `### Recovery Applied` 行でこのアンカーを参照している (`_write_manual_recovery_to_recoveries_log()` が生成する固定文字列)。改名すると過去ログのリンクが全て壊れるため、セクション見出しは維持し本文のみ更新する。`_write_manual_recovery_to_recoveries_log()` が新規エントリへ書き込む `### Recovery Applied` の文字列も変更しない。

**`## Auto Retrospective` 概念は撤去対象外:** 親 `/auto` Step 4a が M/L/patch route の異常検知時および XL route で Spec に書き込む経路、および `modules/retro-proposals.md` が `### Improvement Proposals` を抽出する経路は現状のまま維持する。本 Issue の撤去対象は run-auto-sub.sh の bash 経路のみ。

**既存 Spec を破壊しないための制約:** 実装はコード・テスト・ドキュメントの変更のみで、`docs/spec/` 配下の既存ファイル (本 Issue 自身の Spec を除く) には一切変更を加えない。過去の `### Manual recovery` / `### Tier 2 recovery` / `### Tier 3 recovery` エントリはそのまま残る。

**`#1094` の扱い:** Issue 本文は「本 Issue が採択される場合は close 候補」としているが、Issue の close は本 Issue の受入条件に含まれない L0 操作のため、実装ステップには含めない。`/verify` フェーズ以降の判断に委ねる。

**bats テストの入力データ形式:** 更新対象テストが読み書きする `docs/reports/orchestration-recoveries.md` のフィクスチャは、`# Orchestration Recovery Log` 見出し行と `<!-- Log entries appear below, newest first. -->` マーカー行の 2 行が最低限必要 (マーカーが無いと Python 側の `content.find(marker)` が -1 を返し書き込みがスキップされる)。既存テスト `manual recovery: appends canonical H2 entry to orchestration-recoveries.md` (2049 行付近) のフィクスチャ生成をそのまま流用できる。

**`.claude/` 配下のファイルは変更対象に含まれない**ため `git add -f` の考慮は不要。

## Consumed Comments

No new comments since last phase.
