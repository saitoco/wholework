# Issue #1150: auto: open PR 存在時の recovery 記録を main 直接 commit から回避経路に変更し conflict 製造を解消

## Overview

`scripts/run-auto-sub.sh` の recovery 記録経路 (Tier 2 / Tier 3 の Spec 書き込みおよび `--write-manual-recovery`) は、対象 Issue に open PR が存在していても main の Spec ファイル (`docs/spec/issue-N-*.md`) に直接 commit / push する。PR ブランチ側も同じ Spec ファイルを変更するため、この経路は構造的に merge conflict を製造する。通算 4 件の実害 (#890 / #1005 / #1006 / #1123) が発生済み。

本 Issue は「open PR 存在時は main へ直接 commit しない」経路に切り替える。採用方針は **(b) defer + flush**: open PR 検出時は記録を `.tmp/deferred-recovery-records-<issue>.md` に退避 (defer) し、open PR が消えたタイミング (merge 完了後) に main の Spec へ転記 (flush) して commit / push する。

## Reproduction Steps

1. Size M/L (pr route) の Issue #N を `/auto` で実行し、code phase で PR が作成された状態にする
2. review phase で wrapper が異常終了し、Tier 2 (`apply-fallback.sh` 成功) または Tier 3 (`spawn-recovery-subagent.sh` 成功) の recovery が発火する
   - あるいは親セッションが手動 recovery を行い `run-auto-sub.sh --write-manual-recovery N review <type>` を呼ぶ
3. `_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` が main 上の `docs/spec/issue-N-*.md` に `## Auto Retrospective` エントリを追記し、main へ commit / push する
4. その後 PR #M (同じ Spec ファイルに `## Code Retrospective` / `## Review Retrospective` を追記済み) を merge しようとすると、同一ファイル同一近傍の変更で conflict する

実観測 (2026-08-04, Issue #1123): 親セッションが Tier 2 検出結果 (json-mode-silent-hang) を main の Spec に直接 push した 2 コミットが open PR #1149 と conflict し、rebase + Phase Handoff ローテーションを考慮した手動解消 + フルスイート再実行 (1354 tests) を要して merge が約 1 時間遅延した。

## Root Cause

recovery 記録の書き込み先が **書き込み時点の PR 状態に関係なく main 固定** であること。

現状のコード上の位置づけ (`scripts/run-auto-sub.sh`):

| 経路 | 関数 | open PR ガード | open PR 時の挙動 |
|------|------|---------------|-----------------|
| 手動 recovery | `_write_manual_recovery_to_spec()` (175 行付近) | あり (#1123 / commit `9dc07088` で追加) | **記録を破棄** (stderr 警告 + `return 0`) |
| Tier 2 | `_write_tier2_recovery_to_spec()` (563 行付近) | なし | main へ直接 commit / push |
| Tier 3 | `_write_tier3_recovery_to_spec()` (601 行付近) | なし | main へ直接 commit / push |

つまり既存ガードは 3 経路のうち 1 経路にしか無く、しかもその 1 経路も「回避経路へ切り替える」のではなく「記録を捨てる」挙動になっている。conflict は解消されるが記録が失われるため、Issue の対応方針 (a)(b) のどちらでもない第三の挙動である (Issue 本文の Auto-Resolved Ambiguity Points 1 で確認済み)。

修正方針は「書き込み先を open PR 状態に応じて切り替える」= main が安全でない間は `.tmp/` に退避し、安全になった時点で転記する。

## Changed Files

- `scripts/run-auto-sub.sh`: `_deferred_recovery_records_file()` / `_defer_recovery_record()` / `_flush_deferred_recovery_records()` を追加。`_write_manual_recovery_to_spec()` の破棄分岐を defer に置換。`_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` に open PR ガード + defer を追加。flush 呼び出しを 2 箇所に配線 — bash 3.2+ 互換 (`mapfile` / 連想配列を使わない)
- `scripts/emit-event.sh`: ファイル冒頭の event schema コメントに `recovery_record_deferred` を追加 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: `setup()` の共通 `gh` mock に `pr list --search` 分岐 (`[]` を返す) を追加。既存の open PR 破棄アサーション 2 件 (`skips commit when an open PR exists for the issue` / `open PR skips spec write but still records recoveries log and event`) を defer アサーションへ更新。Tier 2 / Tier 3 の defer ケースと flush ケースのテストを追加
- `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` の Fallback Steps 4 (open-PR ガードの説明) を defer + flush に更新。`## Operational Notes` 配下の 3 小節 (`### Tier 2 bash path: Spec Auto Retrospective write` / `### Manual path: Spec Auto Retrospective write` / `### Tier 3 bash path: Spec Auto Retrospective write`) に defer + flush の記述を追加
- `skills/auto/SKILL.md`: Step 6 の Manual recovery hand-off 段落 (1039 行付近) の「records the recovery in three places」記述を、Spec 書き込みが open PR 存在時に defer される旨を含む形へ更新
- `docs/tech.md`: 56 行の「which writes to the sub-issue Spec (only if a formal Spec already exists ...)」に defer + flush の条件を追記
- `docs/ja/tech.md`: 47 行 — `docs/tech.md` 56 行の日本語ミラー。同内容を日本語で反映 (`docs/translation-workflow.md` 同期義務)
- `docs/workflow.md` / `docs/ja/workflow.md`: **変更不要** (検証済み — 121 行 / 114 行は `--write-manual-recovery` の呼び出し方のみを記述し、書き込み先 3 箇所を列挙していないため defer 化の影響を受けない)
- `docs/structure.md` / `docs/ja/structure.md`: **変更不要** (検証済み — `scripts/run-auto-sub.sh` の記述は "run auto workflow for sub-issues" のみで内部関数に言及がなく、`.tmp/` 配下のファイルは Directory Layout ツリーに列挙されていない)

## Implementation Steps

1. `scripts/run-auto-sub.sh`: `_open_pr_for_issue()` の直後に、defer ファイルパスを返す `_deferred_recovery_records_file ISSUE` (`${REPO_ROOT}/.tmp/deferred-recovery-records-${ISSUE}.md`) と、レコード本文ファイルの内容を defer ファイルへ追記する `_defer_recovery_record ISSUE RECORD_FILE KIND` を追加する。`_defer_recovery_record` は `mkdir -p` で `.tmp` を用意し、stderr に「open PR #M が存在するため main への記録を保留した」旨と defer ファイルパスを出力し、`emit_event "recovery_record_deferred" "issue=..." "kind=..." "open_pr=..."` を best-effort で呼ぶ (`emit_event` 未定義でもスクリプトを落とさないよう `command -v emit_event >/dev/null 2>&1 &&` で保護) (→ 受け入れ条件 1)
2. `scripts/run-auto-sub.sh`: `_flush_deferred_recovery_records ISSUE` を追加する (1 の後)。処理順は (i) defer ファイルが存在しないか空なら `return 0`、(ii) `_open_pr_for_issue` が非空なら「まだ保留」と stderr に出して `return 0`、(iii) `_pull_ff_only`、(iv) `docs/spec/issue-${ISSUE}-*.md` が無ければ defer ファイルを残したまま `return 0` (記録を失わない)、(v) Spec に `## Auto Retrospective` が無ければ追記してから defer ファイルの内容を `cat` で追記、(vi) `_spec_has_changes` が真なら `git add` → `git commit -s -m "Record deferred recovery records for issue #N"` → `_push_with_retry`、成功時のみ defer ファイルを `rm -f`、失敗時は WARNING を出して defer ファイルを保持する (→ 受け入れ条件 1、2)
3. `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_spec()` を、レコード本文をいったん一時ファイル (`.tmp/recovery-record-${issue}-${phase}.md`) に組み立ててから書き込み先を決める形に整理する (1 の後)。open PR 検出時は `return 0` による破棄をやめ `_defer_recovery_record` を呼ぶ。open PR が無い場合は従来どおり `_pull_ff_only` → Spec 追記 → commit / push を行う。Spec 未作成時の既存挙動 (stub を作らずスキップ) は維持する (→ 受け入れ条件 1、2)
4. `scripts/run-auto-sub.sh`: `_write_tier2_recovery_to_spec()` と `_write_tier3_recovery_to_spec()` の Spec 探索直前に `_open_pr_for_issue` による open PR 判定を追加し、open PR がある場合は Spec を触らず `_defer_recovery_record` へ回す (1 の後)。Tier 2 は `$meta_file` の内容を、Tier 3 は現在 Spec へ書いている `### Tier 3 recovery (phase)` ブロックを一時ファイルに組み立ててから渡す。open PR が無い場合は現行の直接書き込み挙動を変更しない (→ 受け入れ条件 1、2)
5. `scripts/run-auto-sub.sh`: `_flush_deferred_recovery_records` の呼び出しを 2 箇所に配線する (2 の後)。(i) `--write-manual-recovery` ディスパッチ内、`source "$SCRIPT_DIR/emit-event.sh"` の直後かつ `_write_manual_recovery_to_spec` 呼び出しの直前、(ii) メインフローの Size 分岐 `esac` の直後、`=== run-auto-sub.sh: Completed sub-issue ===` 完了バナー出力の直前 (→ 受け入れ条件 1)
6. `scripts/emit-event.sh`: ファイル冒頭の "Documented event schemas" コメントブロックの `manual_intervention` エントリの近傍に `recovery_record_deferred` のスキーマ (`issue=<N>` / `kind=<manual|tier2|tier3>` / `open_pr=<PR番号>`) を追加する (1 と並行可)
7. `tests/run-auto-sub.bats`: `setup()` 内の共通 `gh` mock に `pr list` かつ `--search` を含む場合は `[]` を返す分岐を追加する (5 の後)。これにより open PR ガード用のクエリ (`gh pr list --search "closes #N" --state open`) だけが「open PR なし」を返し、PR 番号解決用のクエリ (`--json number,headRefName`、`--search` なし) は既存の戻り値を保つため、既存 Tier 2 / Tier 3 テストの直接書き込みアサーションがそのまま通る (→ 受け入れ条件 2、3)
8. `tests/run-auto-sub.bats`: 既存 2 件 (`skips commit when an open PR exists for the issue` / `open PR skips spec write but still records recoveries log and event`) を「Spec へは書かないが defer ファイルへ記録する」アサーションへ更新し、Tier 2 / Tier 3 の defer ケース (open PR あり → Spec 不変 + defer ファイル生成) と flush ケース (defer ファイルあり + open PR なし → Spec へ転記 + commit + defer ファイル削除) のテストを追加する (7 の後) (→ 受け入れ条件 1、2、3)
9. `modules/orchestration-fallbacks.md` / `skills/auto/SKILL.md` / `docs/tech.md` / `docs/ja/tech.md`: defer + flush 挙動を反映する (5 の後)。`modules/orchestration-fallbacks.md` は `## manual-recovery-spec-write` の Fallback Steps 4 と `## Operational Notes` 配下の Tier 2 / Manual / Tier 3 の 3 小節、`skills/auto/SKILL.md` は 1039 行付近の "three places" 記述、`docs/tech.md` 56 行とその日本語ミラー `docs/ja/tech.md` 47 行を更新する

## Verification

### Pre-merge

- <!-- verify: rubric "open PR が存在する Issue に対する recovery 記録 (Tier 2/3 の Spec 書き込みおよび --write-manual-recovery) が、main への直接 commit を回避する経路 (PR ブランチへの書き込み、または events emit + 後段転記) に変更されている" --> open PR 存在時の recovery 記録が main 直接 commit を回避する
- <!-- verify: rubric "open PR が存在しない Issue (patch route 完了後や verify 段階) では従来どおり main への記録が行われる negative case が実装またはテストで確認できる" --> open PR なしの場合は従来挙動が維持される
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が PASS する

### Post-merge

- open PR が存在する Issue で recovery が発生した際、main との conflict が発生しないことを観察する <!-- verify-type: observation event=auto-run -->
  - 期待される出力構造:
    - recovery 発生時に stderr へ defer 実行のログ (defer ファイルパスを含む) が出ること
    - merge 完了後の flush で `Record deferred recovery records for issue #N` コミットが main に 1 件積まれること
    - 当該 Issue の PR merge が conflict 解消なしで完了すること

## Tool Dependencies

### Bash Command Patterns
- なし (既存の `bats` / `git` / `gh` 権限のみで足りる)

### Built-in Tools
- なし (追加不要)

### MCP Tools
- なし

## Uncertainty

- **flush が発火しないまま残る defer ファイルの扱い**: `auto-stop-at: code` / `auto-stop-at: review` 設定時や、merge 前に `/auto` が中断した場合、実装ステップ 5 の 2 つの flush 呼び出しはどちらも「open PR あり」で no-op となり、defer ファイルが `.tmp/` に残留する。
  - **検証方法**: `.wholework.yml` の `auto-stop-at` を `review` にして bats テストまたは実行観察で defer ファイルの残留を確認する。手動 recovery 経路では、その後の `--write-manual-recovery` 呼び出し (merge phase 完了後) で flush されることを確認する。
  - **影響範囲**: Implementation Steps 2、5。記録が失われるわけではない (defer ファイルは残る) が、Spec への反映が遅延する。本 Issue のスコープでは残留を許容し、`/verify` 側からの回収は行わない (Notes の「(c) 案を採らない理由」参照)。

## Notes

### 方針選択: (b) defer + flush を採用、(a) PR ブランチ書き込みは不採用

Issue 本文の対応方針 1 が (a) PR ブランチ側の Spec に書く / (b) events emit のみ行い後段で転記 の 2 案を提示し、Auto-Resolved Ambiguity Points 2 が (a) のリスク検討を /spec に委ねていた。本 Spec は (b) を採用する。

(a) を採らない理由:
- `run-auto-sub.sh` は冒頭 (24-31 行) で `git worktree list --porcelain` により **main worktree root を解決して `cd` する** 設計になっており、これ自体が #1005 (worktree CWD から PR ブランチへ誤 push) の再発防止策である。(a) はこの不変条件を「書き込み先ブランチを状況に応じて切り替える」方向へ逆行させる
- (a) を安全に実装するには `gh pr view --json headRefName` でのブランチ名解決 + 別 worktree の作成 / checkout + push が必要で、recovery という「既に何かが壊れている状況」で実行する処理としてステップ数が多すぎる
- PR ブランチへ push すると CI が再走し、review 済み PR の diff が recovery 記録で汚染される副作用がある

(b) を採る理由:
- 書き込み先ブランチは常に main のまま。ブランチ切り替えを一切行わないため #1005 型の失敗モードを新規導入しない
- `manual_intervention` イベントが既に `.tmp/auto-events.jsonl` へ無条件で出ており、`.tmp/` を退避先とする発想は既存パターンと整合する
- 「安全になってから書く」という時間軸の分離だけで conflict クラスが消える (最小の変更)

### defer 先を `.tmp/auto-events.jsonl` ではなく専用 markdown ファイルにする理由

Issue 本文は「`.tmp/auto-events.jsonl` への emit に一本化」と記述しているが、`scripts/emit-event.sh` の `emit_event()` は値をサニタイズする際に改行を除去する (106-111 行)。Tier 2 の記録本体は `apply-fallback.sh` が出力する複数行 markdown ブロックであり、JSONL の 1 フィールドに押し込むと原形が失われる。したがって:

- **記録本体** は `.tmp/deferred-recovery-records-<issue>.md` (markdown のまま、追記のみ) に退避する
- **観測用シグナル** としては別途 `recovery_record_deferred` イベントを `.tmp/auto-events.jsonl` に emit する (件数・種別の可観測性を確保)

この 2 系統分離により、Issue 本文の意図 (main へ直接 commit しない / 後段で転記する) を満たしつつ内容欠損を防ぐ。

### Issue 本文の引用の訂正 (Issue body vs. 既存ドキュメントの矛盾)

Issue 本文 Background は「プロジェクト構造診断 (`docs/reports/ja/project-structural-review-2026-07-31.md` 推奨 6) が『recovery 記録の main 直接 commit/push を廃止し `.tmp/auto-events.jsonl` への emit に一本化 → セッション末尾または定期バッチで転記』を提案済み」と述べているが、当該ドキュメントを確認したところ:

- 「推奨 6」に相当する箇所 (68 行) は「根本原因 tracking issue → **#1135 起票済み**」であり、recovery 記録の転記方式には言及していない
- ドキュメント全文を `直接 commit` / `直接 push` / `emit に一本化` / `転記` で grep した結果、該当する提案文は存在しない。関連する記述は 47 行 (問題 B) の「recovery の main 直接 push が merge conflict を生んだ実績 3 件 (#890/#1005/#1006)」という **事実の記録のみ** で、対処方針は書かれていない

非対話モードのため自動解決した: 本 Issue の設計方針は当該ドキュメントの推奨に依拠せず、#890 / #1005 / #1006 / #1123 の 4 件の実害と現行コードの構造 (Root Cause 参照) から独立に導出する。Spec 中の設計判断は上記「方針選択」に記載のとおり。

### 補償層モラトリアムとの整合

同ドキュメント Phase 0 項目 2 は「`orchestration-fallbacks.md` への新パターン追加・新リトライ機構の導入を凍結」を求めている。本 Issue はこれに抵触しないよう:

- `modules/orchestration-fallbacks.md` に **新しい `## <pattern>` セクションを追加しない**。既存の `## manual-recovery-spec-write` と `## Operational Notes` 配下の既存小節の更新に留める
- 新しいリトライ機構を導入しない (defer + flush は失敗クラスの除去であり、失敗後の再試行機構ではない)

### (c) `/verify` からの回収を採らない理由

defer ファイルの回収点として `/verify` Step 12 (Spec の `## Auto Retrospective` を読む箇所) を使う案もあるが、`skills/verify/SKILL.md` に `.tmp/` 依存の読み取り手順を追加すると、run-auto-sub.sh (bash 層) と verify SKILL.md (prose 層) の二重実装が 1 つ増える。同ドキュメント問題 B が指摘する「3-Tier recovery は SKILL.md prose と bash に二重実装で同期は人手」という既知の負債を拡大させるため採らない。flush は run-auto-sub.sh 内で完結させる。

### 既存の open PR ガードとの関係

`_write_manual_recovery_to_spec()` の open PR ガードは #1123 (PR #1149、commit `9dc07088`) で追加済みだが、これは記録を破棄する挙動である。本 Issue はこのガードの検出ロジック (`_open_pr_for_issue`) を再利用しつつ、破棄を defer に置き換える。したがって `_open_pr_for_issue()` 自体には変更を加えない。

### `docs/reports/orchestration-recoveries.md` は現状維持

Issue 本文 対応方針 3 の判断: 現状維持とする。同ファイルは append-only (newest first) で PR ブランチ側が触らないため conflict 面が実質存在せず、`_write_manual_recovery_to_recoveries_log()` は既に `_pull_ff_only` + `_push_with_retry` で逐次化されている。また `scripts/collect-recovery-candidates.sh` の頻度検出および `recoveries-auto-fire` が即時性に依存するため、転記方式に寄せると検出が遅延する副作用がある。

### テストの mock 設計に関する注意

`tests/run-auto-sub.bats` の `setup()` が定義する共通 `gh` mock は `pr list` に対して `[{"headRefName":"worktree-code+issue-42","number":99}]` を返す (142-164 行)。この戻り値は `_open_pr_for_issue()` の `jq -r '.[0].number // empty'` でも 99 として解決されるため、Tier 2 / Tier 3 に open PR ガードを追加すると既存の直接書き込みテスト 6 件 (`tier2 recovery: writes Auto Retrospective to spec file` / `tier3 recovery: writes Auto Retrospective to spec file` / `tier2 recovery during review phase records real Issue number, not PR number (issue #984)` / 同 tier3 / `tier2 recovery: commits when spec file is untracked` / 同 tier3) が defer 側に落ちて失敗する。実装ステップ 7 の `--search` 分岐追加はこれを回避するための前提作業であり、ステップ 8 の前に必ず実施すること。

### bats テストの入力データ形式

- defer ファイル: `.tmp/deferred-recovery-records-<issue>.md`。内容は Spec の `## Auto Retrospective` 直下に貼り付け可能な markdown ブロック (`### Tier 2 recovery ...` / `### Tier 3 recovery (phase)` / `### Manual recovery (phase)` の見出しから始まる)。複数回 defer された場合は追記により複数ブロックが連結される
- flush テストでは、defer ファイルを事前に `BATS_TEST_TMPDIR/.tmp/` に配置し、`gh` mock の `pr list --search` が `[]` を返す状態で `--write-manual-recovery` またはメインフローを走らせ、Spec への追記と `git commit` 呼び出し、defer ファイルの削除を検証する

## Consumed Comments

cutoff: 2026-08-04T15:10:44Z (最新の `phase/*` ラベル付与時刻)

- `saito` / `MEMBER` / first-class / `/issue 1150 --non-interactive` の Issue Retrospective。Triage 判断 (Type=Bug / Size=L / Value=4) と、既存 open PR ガードが記録を破棄する挙動である旨・(a) 案の #1005 型リスクという 2 点の自動解決ログを記録している。本 Spec の Root Cause の表と「方針選択」で両方に対応済み / https://github.com/saitoco/wholework/issues/1150#issuecomment-5181018281
