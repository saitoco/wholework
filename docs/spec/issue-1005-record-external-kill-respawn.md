# Issue #1005: auto: 外部 kill 後の親セッション再スポーン recovery を記録する機構を追加

## Overview

`/auto --batch` セッションで、バックグラウンドの `claude -p` フェーズが原因不明の外部 kill で停止する事象が通算 7 回発生している。親セッション主導の再スポーンで毎回復帰しているが、この recovery は Tier 1/2/3 機構の外で行われるため `docs/reports/orchestration-recoveries.md` にも Spec `## Auto Retrospective` にも `.tmp/auto-events.jsonl` にも記録されず、オーケストレーションの実態 (kill 率・復帰コスト) が計測不能になっている。

本 Issue では以下 3 点を実装する:

1. 外部 kill の原因調査結果を `docs/reports/external-kill-investigation.md` に文書化する (AC1)
2. 親セッション主導の再スポーン recovery を記録する機構を追加する — 既存の `run-auto-sub.sh --write-manual-recovery` サブコマンドを拡張し、Spec に加えて `docs/reports/orchestration-recoveries.md` と `manual_intervention` イベントにも記録する。あわせて `skills/auto/SKILL.md` Step 6 に外部 kill 検知 → 再スポーン → 記録の手順を組み込む (AC2)
3. `--write-manual-recovery` の CWD 依存を解消する — worktree から呼ばれても main リポジトリのルートに記録を書き込む (AC3)

## Consumed Comments

- `saito` / MEMBER / first-class / Issue Retrospective (triage 結果 + AC3 文言の Auto-Resolve 経緯: #966 の `REPO_ROOT` (show-toplevel) は worktree 内で worktree 自身のルートを返すため、AC3 は「main リポジトリのルート」への書き込みとして具体化済み。実装アプローチの選定は `/spec` に委譲) / https://github.com/saitoco/wholework/issues/1005#issuecomment-4958793312

## Investigation Findings (外部 kill)

`/code` が `docs/reports/external-kill-investigation.md` に記載すべき、本 Spec 時点で確定した事実:

**F1 — kill されたフェーズには `wrapper_exit` イベントが 1 件も残っていない。**
`docs/sessions/37830-1783901301-2026-07-13/events.jsonl` を確認したところ、#998 code-pr (00:29:23Z `phase_start` → 次イベントは 00:41:09Z の `sub_start`)、#1000 code-pr (02:46:32Z → 03:08:35Z)、#1003 code-patch (04:06:15Z → 04:08:13Z) のいずれも `wrapper_exit` を欠く。`run_phase_with_recovery()` は子プロセスの終了コードに関わらず `wrapper_exit` を emit するため、**`run-auto-sub.sh` 自身が kill された** ことを意味する (leaf の `claude -p` だけではない)。

**F2 — EXIT trap による backfilled `phase_complete` も存在しない。**
`_maybe_emit_phase_complete()` は exit 0 / 143 (SIGTERM) で発火するが、3 件とも backfill イベントがない。SIGTERM ではなく **SIGKILL (trap が走らない)** でプロセスグループごと落ちた可能性が高い。

**F3 — wrapper ログは watchdog heartbeat の途中で切断されている。**
`.tmp/wrapper-out-998-code-pr.log` は "silent for 480s"、`.tmp/wrapper-out-1000-code-pr.log` は "silent for 1260s" の行で終端し、`Exit code:` トレーラーがない。watchdog は kill していない (code フェーズの timeout は 4680s、観測された最大 silent window は 1280s)。

**F4 — macOS の jetsam (メモリ逼迫 OOM kill) の証跡はない。**
`/Library/Logs/DiagnosticReports/` (36 ファイル) と `~/Library/Logs/DiagnosticReports/` (34 ファイル) のいずれにも `JetsamEvent-*` レポートが存在しない。jetsam kill は必ず JetsamEvent レポートを残すため、メモリ逼迫由来の OOM kill 仮説は現時点の証拠では支持されない。

**F5 — kill までの経過時間は一定しない。**
#1003 code-patch は約 2 分、#998 code-pr は約 12 分、#1000 code-pr は約 22 分。固定タイムアウトによる kill ではない。

**F6 (設計上の含意) — `retry-on-kill` は構造的にこのクラスの kill を救済できない。**
`run_with_retry_on_kill()` (Layer B) は `run-auto-sub.sh` プロセス内部で動作するため、プロセスグループごと SIGKILL される本事象では発火不可能。したがって **親セッションだけが唯一の recovery 実行主体** であり、記録機構も親セッション主導でなければならない (AC2 の設計根拠)。

**残存仮説 (未検証):**
- H-a: Claude Code ハーネスのバックグラウンド Bash タスクのライフサイクル (context compaction / turn 境界 / タスク reaper) がプロセスグループを SIGKILL している
- H-b: ターミナル・シェル側からのプロセスグループ kill
- H-c: 上記以外 (不明)

**`/code` が追加実行すべき調査手順:**
```bash
log show --start "2026-07-13 09:35:00" --end "2026-07-13 09:45:00" \
  --predicate 'eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "jetsam" OR eventMessage CONTAINS[c] "SIGKILL"' \
  --style compact
```
(kill 時刻 JST 09:41 / 12:08 / 13:08 の各前後 5 分。macOS の unified log は保持期間が短いため、取得できない場合は「取得不能」を事実として記録する。AC1 の rubric は「調査手順と判明事実・残存仮説」の文書化を許容するため、否定的結果でも PASS 条件を満たす)

## Changed Files

- `scripts/run-auto-sub.sh`: (1) `SCRIPT_DIR` 定義を先頭へ移動、(2) `REPO_ROOT` を main worktree 解決に変更 + `cd`、(3) `_validate_recovery_args` に第4引数 EXIT_CODE を追加、(4) `_write_manual_recovery_to_recoveries_log()` を新規追加、(5) `_write_manual_recovery_to_spec()` に exit_code を追加、(6) `--write-manual-recovery` dispatch を拡張 (イベント emit + recoveries log 書き込み) — bash 3.2+ compatible
- `scripts/emit-event.sh`: `manual_intervention` のスキーマコメントを更新 (`intervention_type` は `--write-manual-recovery` の RECOVERY_TYPE を運ぶ、`wrapper_exit_code` は `unknown` を取りうる) — bash 3.2+ compatible
- `skills/auto/SKILL.md`: Step 6 に "External kill pre-check (before Tier 1)" サブセクションを追加。Stop-and-Report Fallback の "Manual recovery hand-off" 注釈を更新 (記録先 3 箇所 + main-root 自己正規化 + `respawn` recovery type)
- `modules/orchestration-fallbacks.md`: `## external-kill-parent-respawn` エントリを新規追加。`## manual-recovery-spec-write` の Fallback Steps を更新 (recoveries log 書き込み + イベント emit + main-root 正規化)
- `docs/reports/external-kill-investigation.md`: 新規作成 — 外部 kill 調査レポート (F1-F6 + 残存仮説 + 追加調査手順と結果)
- `tests/run-auto-sub.bats`: `setup()` の `$MOCK_DIR/emit-event.sh` モックに `restore_auto_session_pointer() { :; }` を追加。新規テスト 4 件を追加 — bash 3.2+ compatible
- `docs/reports/orchestration-recoveries.md`: 変更不要 (実行時にエントリが追記される書き込み先。`<!-- Log entries appear below, newest first. -->` マーカーが 65 行目に存在することを確認済み)
- `docs/structure.md`: [Steering Docs sync candidate] `run-auto-sub.sh` の説明は 1 行 ("run auto workflow for sub-issues") で本変更の影響を受けない。`docs/reports/` はディレクトリとして既出、個別レポートファイルは列挙されない方針のため新規レポート追加による更新も不要 (grep 確認済み)
- `docs/tech.md`: [Steering Docs sync candidate] "Two-tier orchestration" の Tier 1/2/3 記述に、Tier 機構外の親セッション再スポーン recovery とその記録経路への言及を追加するか `/code` が判断する
- `docs/workflow.md`: [Steering Docs sync candidate] `run-auto-sub.sh` への言及があるため、外部 kill 再スポーン手順の追記要否を `/code` が判断する
- `docs/ja/structure.md` / `docs/ja/tech.md` / `docs/ja/workflow.md`: [Steering Docs sync candidate] 上記 3 ファイルを更新した場合のみ、`docs/translation-workflow.md` の手順に従いミラーを同期する (`docs/reports/` は翻訳対象外と明記されているため、新規レポートのミラーは不要)

## Implementation Steps

1. **`scripts/run-auto-sub.sh` — main repo root 自己正規化** (→ AC3)。冒頭の `REPO_ROOT="$(git rev-parse --show-toplevel ...)"` (現 13 行目) を次の順序に置き換える: (a) `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` を **`cd` より前** に移動 (相対 `$0` が `cd` で壊れるのを防ぐ)、(b) `REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"` で main worktree を解決し、空なら `git rev-parse --show-toplevel`、それも空なら `pwd` にフォールバック、(c) `cd "$REPO_ROOT"` で CWD を正規化 (`.tmp/auto-events.jsonl` などの相対パスと `gh` のリポジトリ解決を main 基準に揃える)、(d) `[[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$REPO_ROOT/scripts"`。`scripts/run-code.sh` の 55-59 行目の既存パターンに揃える。現 186 行目の `SCRIPT_DIR` 再代入は削除する。bash 3.2+ 互換 (`mapfile`・連想配列を使わない)

2. **`scripts/run-auto-sub.sh` — `_validate_recovery_args` に EXIT_CODE を追加** (after 1) (→ AC3, AC4)。第4引数 `_exit_code` を受け取り、非空の場合のみ `^[0-9]+$` で検証する (既存 3 引数の検証ロジックは変更しない)

3. **`scripts/run-auto-sub.sh` — `_write_manual_recovery_to_recoveries_log()` を新規追加** (after 2) (→ AC2)。引数は `ISSUE PHASE RECOVERY_TYPE [EXIT_CODE]`。実装パターン (ファイル不在なら `return 0`、`python3` heredoc で `<!-- Log entries appear below, newest first. -->` マーカー直後に prepend、`git add` → `git commit -s` → `_push_with_retry` の best-effort チェーン) は `_write_wrapper_retry_recovery()` を踏襲するが、**定義位置は `_write_manual_recovery_to_spec()` の直後 (dispatch ブロックの手前)** — `_write_wrapper_retry_recovery()` の直後 (dispatch よりファイル上で後方) ではない。理由: bash は関数定義行が実行されて初めてその関数をシェルに登録するため、`SUB_NUMBER` パース等より前で `exit 0` する dispatch ブロックより後方に定義すると、dispatch がその関数を呼び出す時点で未定義 (`command not found`) になる (Code Retrospective 参照)。**エントリ形式は canonical な H2 形式** を使う (`_write_wrapper_retry_recovery` の H3 形式ではない — Notes 参照):

   ```
   ## <YYYY-MM-DD HH:MM UTC>: manual-recovery-<recovery_type>

   ### Context
   - Issue #<issue>, phase: <phase>
   - Source: parent-session-manual-recovery
   - Wrapper: run-auto-sub.sh, exit code: <exit_code|unknown>

   ### Diagnosis
   - Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: <recovery_type>)

   ### Recovery Applied
   - modules/orchestration-fallbacks.md#manual-recovery-spec-write

   ### Outcome
   - success

   ### Improvement Candidate
   - 未起票
   ```

   symptom-short を `manual-recovery-<recovery_type>` とすることで、`scripts/collect-recovery-candidates.sh` の H2 パーサ (`^## YYYY-MM-DD HH:MM UTC: <symptom-short>`) が頻度検出でき、`recoveries-auto-fire` の閾値判定対象になる。bash 3.2+ 互換

4. **`scripts/run-auto-sub.sh` — `_write_manual_recovery_to_spec()` に exit_code を追加** (after 2) (→ AC2)。第4引数 `exit_code` (既定 `unknown`) を受け取り、Spec エントリに `- **Wrapper exit code**: <exit_code>` 行を追加する (Tier 3 エントリと対称)。`_validate_recovery_args` 呼び出しにも第4引数を渡す。**既存の open-PR ガード (#890、現 97-102 行目) はそのまま維持する** — 早期 `return 0` する対象は Spec 書き込みのみであり、後続の recoveries log 書き込みとイベント emit は dispatch 側で継続するため (Notes 参照)

5. **`scripts/run-auto-sub.sh` — `--write-manual-recovery` dispatch ブロックを拡張** (after 1, 2, 3, 4) (→ AC2)。現 145-153 行目のブロックを次のように拡張する: (a) 引数を `ISSUE [PHASE] [RECOVERY_TYPE] [EXIT_CODE]` として受け取る (usage 文言も更新)、(b) `source "$SCRIPT_DIR/emit-event.sh"` の後に `restore_auto_session_pointer` を呼び、`export EMIT_ISSUE_NUMBER="$ISSUE"` を設定、(c) `_write_manual_recovery_to_spec` → `_write_manual_recovery_to_recoveries_log` の順に呼ぶ、(d) `emit_event "manual_intervention" "recovery_target=<phase>" "wrapper_exit_code=<exit_code|unknown>" "intervention_type=<recovery_type>"` を emit、(e) `exit 0`。emit-event.sh の source を dispatch ブロック内に置く理由: 現行の 210 行目の source は dispatch (145 行目) より後にあり到達しないため。**EXIT_CODE のデフォルト化タイミングに注意**: dispatch 変数 (例 `_mr_exit_code`) は未指定時に空文字列のまま (`"${4:-}"`) 各関数へ渡すこと。ここで `unknown` にデフォルト化してから渡すと、`_validate_recovery_args` の `^[0-9]+$` チェックに非数値文字列が渡り常に FAIL する (Code Retrospective 参照)。`emit_event` の表示専用の値としてのみ `${_mr_exit_code:-unknown}` のようにその場でデフォルト化する

6. **`scripts/emit-event.sh` — `manual_intervention` スキーマコメントを更新** (parallel with 1-5) (→ AC2)。`intervention_type` の説明を「`--write-manual-recovery` の RECOVERY_TYPE 値を運ぶ (例: `respawn`, `push-only`, `pr-create`, `review-rerun`)」に更新し、`wrapper_exit_code` が `unknown` を取りうることを明記する。emitter が `run-auto-sub.sh --write-manual-recovery` であることも 1 行で追記する

7. **`skills/auto/SKILL.md` — Step 6 に "External kill pre-check (before Tier 1)" を追加** (after 5) (→ AC2)。`### Step 6: On Failure: 3-Tier Recovery` の見出し直後、`#### Tier 1 (Observe): State Reconciliation` の直前に挿入する。内容: (a) **検知シグネチャ** — バックグラウンドの `run-*.sh` が exit 137/143 で終了する、または `.tmp/wrapper-out-$NUMBER-$PHASE.log` に `Exit code:` トレーラーがなく `.tmp/auto-events.jsonl` に当該フェーズの `wrapper_exit` イベントも存在しない場合、wrapper のプロセスグループごと外部 kill されたと判定する (`modules/orchestration-fallbacks.md#external-kill-parent-respawn` 参照)、(b) **対応** — Tier 1/2/3 診断には進まず、同じ `run-*.sh` を同じ引数で再スポーンする (`phase/*` ラベルの SSoT と `code_phase_milestone` チェックポイントが既存の進捗を復元する)、(c) **記録 (必須)** — 再スポーンしたフェーズの完了後に `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE respawn EXIT_CODE` を呼ぶ。サブコマンドは main リポジトリのルートを自己解決するため任意の CWD から安全に呼べる。**新規の Tier 番号は導入しない** (Tier 1/2/3 の語彙は `docs/tech.md` / `modules/orchestration-fallbacks.md` と共有されているため)。あわせて Stop-and-Report Fallback の "Manual recovery hand-off" 注釈 (現 1019 行目) を更新し、サブコマンドが Spec + `docs/reports/orchestration-recoveries.md` + `manual_intervention` イベントの 3 箇所に記録することと、`respawn` recovery type を明記する。SKILL.md 本文には半角の感嘆符を書かない (`validate-skill-syntax.py` 制約)

8. **`modules/orchestration-fallbacks.md` — カタログエントリを追加・更新** (after 7) (→ AC2)。(a) `## wrapper-retry-on-kill` の直後に `## external-kill-parent-respawn` を新規追加する。既存エントリと同じ 5 セクション構成 (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) で、Symptom には F1-F3 の観測シグネチャ (`wrapper_exit` イベント欠落・EXIT trap 未発火・ログの `Exit code:` トレーラー欠落) を、Rationale には F6 (`retry-on-kill` の Layer B は同一プロセスグループ内にあるため構造的に発火不可能) と本 Issue 番号を記載する。(b) `## manual-recovery-spec-write` の Fallback Steps を更新し、recoveries log 書き込みとイベント emit、main-root 自己正規化を反映する

9. **`docs/reports/external-kill-investigation.md` を新規作成** (parallel with 1-8) (→ AC1)。本 Spec の "Investigation Findings" セクションの F1-F6 と残存仮説 H-a/H-b/H-c を転記し、「`/code` が追加実行すべき調査手順」の `log show` クエリを実行してその結果 (取得できた場合は内容、取得不能なら「unified log 保持期間切れで取得不能」) を追記する。最後に「今後の観察計画」として、AC2 で追加した記録機構により次回以降の kill が `manual_intervention` イベントと `manual-recovery-respawn` エントリとして蓄積され、`wrapper_exit_code` の値 (137 vs 143) から SIGKILL/SIGTERM の判別が可能になることを記載する

10. **`tests/run-auto-sub.bats` を更新** (after 5) (→ AC4)。(a) `setup()` 内の `$MOCK_DIR/emit-event.sh` モックに `restore_auto_session_pointer() { :; }` を追加する (production 側が `set -euo pipefail` 下で無条件に呼ぶため、未定義だと exit 127 で全 `--write-manual-recovery` テストが落ちる)。(b) 新規テスト 4 件を追加する — いずれも既存の `--write-manual-recovery 42 code push-only` テスト (現 1434 行目) と同じ `git`/`gh` モック基盤を使う:
   - `main repo root resolution`: `git` モックの `worktree list --porcelain` が main root (`$BATS_TEST_TMPDIR/main`) を返し、`rev-parse --show-toplevel` が worktree root (`$BATS_TEST_TMPDIR/wt`) を返すよう設定し、Spec / recoveries log の書き込みと `git -C` の対象が **main root** になることを assert する
   - `recoveries log entry`: `docs/reports/orchestration-recoveries.md` フィクスチャ (マーカー行を含む) を用意し、実行後に `## <date> UTC: manual-recovery-push-only` 形式のエントリが prepend されていることを assert する
   - `manual_intervention event emit`: `$MOCK_DIR/emit-event.sh` を、`emit_event` が引数をログファイルに追記する版で上書きし、`manual_intervention` と `intervention_type=push-only` が emit されることを assert する
   - `open PR: spec write skipped but recoveries log and event still recorded`: `gh pr list` が open PR を返すモックで、Spec への `### Manual recovery` 追記は行われない一方、recoveries log エントリとイベントは記録されることを assert する

## Alternatives Considered

- **A: `run-auto-sub.sh` 内で kill を自己検知して自動記録する** — 却下。F1/F2/F6 のとおり wrapper 自身がプロセスグループごと SIGKILL されるため、EXIT trap も `retry-on-kill` も走らない。プロセス内での自己記録は構造的に不可能
- **B: 親セッション主導の明示記録 (既存 `--write-manual-recovery` を拡張)** — **採用**。親セッションは kill を生き延びる唯一の主体であり、既存サブコマンド・既存 allowed-tools・既存カタログエントリ (`manual-recovery-spec-write`) をそのまま拡張できる
- **C: `recovery` イベントを `tier=manual` で emit する** — 却下。`get-auto-session-report.sh` と `docs/tech.md` が定義する Tier 1/2/3 の語彙を曖昧にする。`manual_intervention` イベントは「親セッションが子 wrapper の失敗を手動復旧した」というまさに本件のセマンティクスで既に定義済みで、Metrics に専用行 (`Parent session manual interventions`) も存在する
- **D: 新規スクリプト `record-manual-recovery.sh` を追加する** — 却下。各 SKILL.md の `allowed-tools` に新エントリが必要になる。既存パターンの拡張を優先する方針 (#437 の教訓) に反する

## Verification

### Pre-merge

- <!-- verify: rubric "外部 kill (バックグラウンド claude -p プロセスの原因不明停止) について、調査結果 (発生源の特定、または調査手順と判明事実・残存仮説) が Spec または docs/ 配下に文書化されている" --> 外部 kill の原因調査結果 (発生源の特定、または調査で判明した事実と残る仮説) が文書化されている
- <!-- verify: rubric "親セッション主導の再スポーン recovery を docs/reports/orchestration-recoveries.md または events.jsonl (あるいは両方) に記録する機構が実装されている (自動記録、または親セッションが呼び出す明示的な記録手順の SKILL.md への組み込みのいずれか)" --> 親セッションが kill 後に run-auto-sub.sh / run-code.sh を再スポーンした際、その recovery が記録される機構が実装されている
- <!-- verify: rubric "scripts/run-auto-sub.sh の --write-manual-recovery 経路が、worktree 等の非 main CWD から呼ばれても、呼び出し元 worktree 自身のルートではなく main リポジトリのルートに記録を正しく書き込む" --> `--write-manual-recovery` が worktree など main 以外の CWD から呼ばれても、記録を main リポジトリのルートに書き込む
- <!-- verify: command "bats tests/run-auto-sub.bats" --> 上記の bats テストが追加され PASS する

### Post-merge

- 次回バックグラウンドフェーズの外部 kill → 親セッション再スポーン発生時、recovery が記録されることを観察 <!-- verify-type: observation event=auto-run -->
  - 期待される出力構造:
    - `docs/reports/orchestration-recoveries.md` に `## <date> UTC: manual-recovery-respawn` エントリが追記される
    - `.tmp/auto-events.jsonl` に `"event":"manual_intervention"` かつ `"intervention_type":"respawn"` のイベントが記録される
    - L3 session retrospective の Metrics 行 `Parent session manual interventions` が 0 でなくなる

## Tool Dependencies

### Bash Command Patterns
- なし (`skills/auto/SKILL.md` の `allowed-tools` には `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` が既に登録済み — grep 確認済み。新規スクリプトの追加もないため allowed-tools の変更は不要)

### Built-in Tools
- なし (既存の Read / Edit / Write / Bash で完結)

### MCP Tools
- なし

## Uncertainty

- **macOS unified log からの kill 発生源特定可否**: `log show` の保持期間 (通常数日) 内であれば取得できるが、`memorystatus` / `SIGKILL` 相当のメッセージがログに残らない実装の可能性もある
  - **検証方法**: Implementation Step 9 の `log show` クエリを `/code` で実行する
  - **影響範囲**: Implementation Step 9 のみ。AC1 の rubric は「調査手順と判明事実・残存仮説」の文書化を許容するため、取得不能でも「取得不能である」ことを事実として記録すれば PASS 条件を満たす。発生源が特定できなければ H-a/H-b/H-c は残存仮説として文書化する

- **`cd "$REPO_ROOT"` の既存 bats テストへの影響**: `tests/run-auto-sub.bats` の `git` モックは `worktree list` に対して空文字列を返すため、`rev-parse --show-toplevel` (= `$BATS_TEST_TMPDIR`) にフォールバックし、`cd` は現 CWD への no-op になる (モック実装を読んで確認済み)
  - **検証方法**: `/code` で `bats tests/run-auto-sub.bats` のフルスイートを実行する
  - **影響範囲**: Implementation Step 1

## Notes

- **recoveries log のエントリ形式は H2 (`## YYYY-MM-DD HH:MM UTC: <symptom-short>`) を使う**: `docs/reports/orchestration-recoveries.md` の Entry Format 定義と `scripts/spawn-recovery-subagent.sh` の `write_recovery_entry()` が書く実エントリ (例: 67 行目 `## 2026-07-12 06:18 UTC: code-pr-tier3-recovery`) はいずれも H2 形式で、`scripts/collect-recovery-candidates.sh` のパーサもこの形式のみを認識する。新規エントリを H2 形式で書くことで `/audit recoveries` の頻度検出と `recoveries-auto-fire` の閾値判定の対象になる

- **観測された隣接ギャップ (本 Issue のスコープ外)**: `_write_wrapper_retry_recovery()` は `### wrapper-retry-on-kill (phase)` という **H3 形式** でエントリを書いており、canonical な H2 形式と一致しない。このため wrapper-retry-on-kill の記録は `collect-recovery-candidates.sh` の頻度検出から不可視になっている。本 Issue は親セッション再スポーン経路の記録が対象のため修正はスコープ外とし、spec retrospective に改善提案候補として記録する (`/verify` Step 13 が Improvement Proposal として集約する)

- **記録される Metrics 行のマッピング**: 本機構が emit する `manual_intervention` イベントは Metrics の `Parent session manual interventions` 行に反映される (これまで production の emitter が存在せず常に 0 だった行)。`Tier 1/2/3 recoveries` 行は設計上 0 のまま — 本 recovery は Tier 機構の外側で行われるものであり、Tier のセマンティクスを汚さない。cross-Issue の paper trail と頻度検出は `docs/reports/orchestration-recoveries.md` 側が担う

- **open-PR ガード (#890) のスコープ**: `_write_manual_recovery_to_spec()` は open PR が存在する場合に Spec 書き込みをスキップする (PR ブランチが同じ Spec ファイルを触っており、main への commit が自己誘発的なマージコンフリクトを起こすため)。外部 kill の再スポーン事例では open PR が存在するケースが多い (#998 code-pr → PR #1001) ため、このガードが recoveries log とイベント記録まで巻き込んでスキップすると本 Issue の目的を達成できない。したがって dispatch 側で 3 つの記録を独立に呼び、Spec 書き込みのみがガードでスキップされる構造にする。`docs/reports/orchestration-recoveries.md` は PR ブランチが触らないファイルであり、Tier 3 経路も open PR 存在下で main に commit している既存挙動と一貫する

- **REPO_ROOT の main-root 化は 5 つの書き込み経路すべてを同時に堅牢化する**: `REPO_ROOT` はグローバルに `_write_manual_recovery_to_spec` / `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / `_write_wrapper_retry_recovery` / `run_phase_with_recovery` 内 Tier3 push (#986 で列挙された 5 箇所) と resume preamble から参照される。main worktree 解決に変更しても、通常の呼び出し (親 `/auto` セッションが repo root から起動) では現行と同じ値になり、worktree からの呼び出しでのみ挙動が変わる (= 望ましい方向のみ)

- **`skills/auto/SKILL.md` 編集時の制約**: 本文に半角の感嘆符を書かない (`scripts/validate-skill-syntax.py` が zsh history expansion 誤検知として検出する)

## issue retrospective

**Triage (auto-chain, `triaged` ラベル不在のため実行):**
- Title: 変更なし (既存の命名規則 `component: 説明` に準拠済み)
- Type: Feature (Issue Types API)
- Priority: 検出なし (本文・タイトルに優先度キーワードなし)
- Size: L — 既存 Tier 1/2/3 recovery 機構の外側で動く新規記録機構の追加 + `run-auto-sub.sh` のスクリプトロジック変更 (複数箇所) + CWD 依存解消 + bats テスト追加という規模から判定 (新規アーキテクチャパターン導入で +1 調整)
- Value: 3 — Impact=2 (shared component: `run-auto-sub.sh`/`skills/auto/SKILL.md` は auto パイプライン全体で共有される基盤スクリプト、blocking/mentions/parent なし)、Alignment=4 (`docs/product.md` Vision の「governance-and-verification harness」= 可観測性・監査可能性の強化に直接寄与)、raw=6 → Value 3
- 重複候補: なし (関連 Issue #483 #598 #465 は本文中で既に別スコープと明記済み)
- 停滞チェック: 停滞パターンなし
- 依存チェック: `Blocked by #N` 記法なし、依存関係なし

**Ambiguity 解決 (Auto-Resolved、詳細は Issue 本文の `## Auto-Resolved Ambiguity Points` セクション参照):**

AC3 (`--write-manual-recovery` の CWD 非依存動作) について、当初の文言「repo root で動作する」は #966 (CLOSED) の既存修正 (`git rev-parse --show-toplevel` ベースの `REPO_ROOT`) で字面上 PASS してしまう可能性があると判断した。#966 の `REPO_ROOT` は worktree 内で実行すると **worktree 自身のルート** を返す設計であり、これは本 Issue の Background に記載された session 37830 の事故 (code worktree の CWD で `--write-manual-recovery` を実行し、記録が PR ブランチへ誤 push された) の直接の原因パターンと一致する。そのため AC3 の文言を「main リポジトリのルートに書き込む (worktree 自身のルートではなく main を解決する)」に具体化し、rubric もこれに合わせて調整した。実装アプローチ (`git worktree list --porcelain` ベースの MAIN_ROOT パターンなど、`run-code.sh`/`run-merge.sh`/`run-review.sh` に既存パターンあり) の選定は `/spec` に委ねる。

他のクラリフィケーションポイント (AC1 の文書化先、AC2 の記録先/実装方式) は Issue 本文の AC 文言自体に「Spec または docs/ 配下」「orchestration-recoveries.md または events.jsonl (あるいは両方)」「自動記録、または明示的な記録手順のいずれか」という選択肢が既に明記されており、/issue (What) と /spec (How) の責務分界に従い実装方式の確定は /spec に委ねるべき性質のため、追加のクラリフィケーションは行わなかった。

**AC verify command 監査:** 問題パターンなし (rubric 3件、bats command 1件、いずれも安全)。

## spec retrospective

### Autonomous Auto-Resolve Log

- **記録先は `docs/reports/orchestration-recoveries.md` + `manual_intervention` イベントの両方** — reason: AC2 は「いずれか」を許容するが、前者は cross-Issue の頻度検出 (`collect-recovery-candidates.sh` / `recoveries-auto-fire`)、後者は session Metrics (`Parent session manual interventions` 行) という別々の消費者を持ち、どちらか一方では Issue が問題視した「計測不能」の片方しか解消しない。両方書くコストは追加関数 1 つと emit 1 行で済む。
  - Other candidates: recoveries.md のみ (却下 — Metrics が 0 のまま)、events.jsonl のみ (却下 — cross-Issue の paper trail と頻度検出が残らない)
- **イベント型は既存の `manual_intervention` を使い、`recovery` (tier=manual) は新設しない** — reason: `manual_intervention` は `scripts/emit-event.sh` に「parent session manually recovered a child wrapper failure」として既にスキーマ定義済みで、`get-auto-session-report.sh` にも専用の Metrics 行がある (production の emitter が存在しないため常に 0 だった)。`recovery` に tier=manual を足すと `docs/tech.md` / `modules/orchestration-fallbacks.md` と共有する Tier 1/2/3 の語彙が曖昧になる。
  - Other candidates: `recovery` イベントに `tier=manual` を追加 (却下 — Tier 語彙の汚染)、新規イベント型の追加 (却下 — 既存スキーマで足りる)
- **main root 解決は `REPO_ROOT` グローバルごと `git worktree list --porcelain` 方式に切り替える** — reason: `run-code.sh` / `run-merge.sh` / `run-review.sh` に確立済みの既存パターン。`--write-manual-recovery` だけをローカルに修正するより、`REPO_ROOT` を参照する 5 つの recovery 書き込み経路 (#986 で列挙) すべてを同時に堅牢化できる。通常呼び出し (repo root 起動) では値が変わらないため後退リスクがない。
  - Other candidates: `_write_manual_recovery_to_spec()` 内でローカルに main root を再解決 (却下 — 他 4 経路に同じ脆弱性が残る)
- **open-PR ガード (#890) は Spec 書き込みのみに適用し、recoveries log とイベントは記録を続行する** — reason: 外部 kill の再スポーン事例は open PR 存在下 (#998 code-pr → PR #1001) で起きるケースが多く、ガードが 3 記録すべてを巻き込むと本 Issue の目的を達成できない。コンフリクト回避が必要なのは PR ブランチも触る Spec ファイルだけであり、`orchestration-recoveries.md` は Tier 3 経路が既に open PR 存在下で main に commit している。
  - Other candidates: ガードを全記録に適用 (却下 — 記録漏れが残る)、ガード自体を撤廃 (却下 — #890 の自己誘発コンフリクトが再発する)
- **AC1 の文書化先は `docs/reports/external-kill-investigation.md` (新規)** — reason: AC1 は「Spec または docs/ 配下」を許容するが、Spec は disposable (`docs/tech.md` Spec-first 原則) であり、通算 7 回・複数セッションに跨る調査記録は cross-Issue な保存先が要る。`docs/reports/` には `watchdog-recovery-strategy.md` 等の同型の先例がある。
  - Other candidates: Spec 内に留める (却下 — Spec は disposable)

### Minor observations

- `_write_wrapper_retry_recovery()` は `### wrapper-retry-on-kill (phase)` という H3 形式で `orchestration-recoveries.md` にエントリを書いているが、同ファイルの Entry Format 定義・`spawn-recovery-subagent.sh` の `write_recovery_entry()` の実エントリ・`collect-recovery-candidates.sh` のパーサはいずれも H2 形式 (`## YYYY-MM-DD HH:MM UTC: <symptom-short>`) を前提としている。結果として wrapper-retry-on-kill の記録は `/audit recoveries` の頻度検出と `recoveries-auto-fire` の閾値判定から不可視になっている。本 Issue のスコープ外 (親セッション再スポーン経路が対象) だが、同種の「記録はされるが計測されない」構造的欠陥であり、Improvement Proposal 候補として起票を推奨する。
- L3 session retrospective の Metrics 行 `Parent session manual interventions` は、`manual_intervention` イベントの production emitter が 1 つも存在しなかったため、導入以来ずっと構造的に 0 だった。本 Issue が最初の emitter を追加する。

### Judgment rationale

- Issue 本文の「recovery が記録されない」という症状に対し、最初は `run-auto-sub.sh` 側での自動検知を検討したが、session 37830 の events.jsonl 調査で「kill されたフェーズには `wrapper_exit` イベントも backfilled `phase_complete` も残っていない」ことを確認し、wrapper 自身がプロセスグループごと SIGKILL されていると判断した。この事実が「親セッションが唯一の recovery 主体である」という設計制約 (Alternatives A の却下理由) を確定させ、既存 `--write-manual-recovery` の拡張という方針を一意に決めた。証拠 (F1/F2) を先に取ったことで設計選択が推測ではなく観測に基づくものになった。

### Uncertainty resolution

- **macOS jetsam (OOM kill) 仮説**: `/Library/Logs/DiagnosticReports/` と `~/Library/Logs/DiagnosticReports/` を実際に確認し、`JetsamEvent-*` レポートが 1 件も存在しないことを設計時に確認した (jetsam kill は必ずレポートを残す)。メモリ逼迫由来の OOM kill 仮説は現時点の証拠では支持されない、という否定的結果を Spec の Investigation Findings (F4) に記録した。
- **watchdog kill 仮説**: wrapper ログが "silent for 480s" / "silent for 1260s" の heartbeat 行で切断されており、code フェーズの watchdog timeout (4680s) に遠く及ばないことを確認した (F3)。watchdog kill ではない。
- **`cd "$REPO_ROOT"` の bats 後退リスク**: `tests/run-auto-sub.bats` の `git` モック実装を読み、`worktree list` に対して空文字列を返す (= `rev-parse --show-toplevel` にフォールバックする) ことを確認したため、既存テストへの影響はないと判断した。`/code` でフルスイート実行して確定させる。

## Code Retrospective

### Deviations from Design

- **`_write_manual_recovery_to_recoveries_log()` の定義位置を Implementation Step 3 の指示 (`_write_wrapper_retry_recovery()` の直後) から変更し、`_write_manual_recovery_to_spec()` の直後 (dispatch ブロックの手前) に置いた** — reason: bash は関数定義行が実行された時点で初めてその関数をシェルに登録する。`--write-manual-recovery` dispatch ブロックは `SUB_NUMBER` パース等より前で `exit 0` して早期リターンする構造のため、`_write_wrapper_retry_recovery()` の直後 (dispatch よりファイル上で後方) に定義すると、dispatch がその関数を呼び出す時点でまだ定義に到達しておらず `command not found` になる。実行順序上の制約により、呼び出し元より前に定義する必要があった。

### Design Gaps/Ambiguities

- **dispatch 側で EXIT_CODE を先にデフォルト値 `unknown` へ変換してから `_write_manual_recovery_to_spec` に渡すと、`_validate_recovery_args` の数値正規表現チェック (`^[0-9]+$`) に "unknown" という非数値文字列が渡り常に validation FAIL する不具合が発生した** — Spec Implementation Step 2/4 は「非空の場合のみ検証する」設計だったが、Step 5 のドラフト実装で dispatch 側が EXIT_CODE を空のまま関数へ渡さず先にデフォルト化してしまい、この前提を壊していた。修正: dispatch では `_mr_exit_code="${4:-}"` として未指定時は空文字列のまま関数群に渡し (`_validate_recovery_args` が空を許容してスキップする)、`emit_event` へのイベント値表示でのみ `${_mr_exit_code:-unknown}` として個別にデフォルト化する。bats テスト (`writes Auto Retrospective to spec file` 等、既存 5 件) の実行で顕在化し、修正後に全 67 件 PASS を確認した。

### Rework

- 上記 EXIT_CODE のデフォルト化タイミングの不具合修正が唯一の手戻り。実装当初の dispatch ブロックを 1 回書き直した (関数呼び出しへの引数渡し方を変更)。

## review retrospective

### Spec vs. implementation divergence patterns

Spec と実装 (skills/auto/SKILL.md, scripts/run-auto-sub.sh, docs/reports/external-kill-investigation.md) の間に構造的な乖離はなし — Implementation Step 7 の記述はそのまま SKILL.md に転記されていた。ただし、その転記元である Spec 自身 (line 25 の F2 記述: 「exit 0 / 143 で発火する」) と Implementation Step 7 (line 103: 「exit 137/143 で終了 = 外部 kill されプロセスグループごと落ちた」) の間に論理的矛盾が内在しており、これが SKILL.md にそのまま伝播していた。`/review` Step 12 で SKILL.md 側の Detection signature を「exit 143 は第2条件 (`Exit code:` トレーラー欠落 かつ `wrapper_exit` イベント欠落) との併用が必要」に修正して解消したが、根本原因は Spec 自体の矛盾にあったため、次回同種の Spec 執筆時は「調査結果セクション (Findings)」と「実装ステップ (Implementation Steps)」の記述が同じ条件分岐について矛盾しないか、`/spec` フェーズでの自己整合性チェックを強化する余地がある。

### Recurring issues

`capabilities.workflow: true` 設定下の Step 10 Workflow パス (`modules/workflow-guidance.md` のインラインスクリプト) で、finder → adversarial-verify パイプラインの verify ステージが実際には一度も実行されなかった (workflow 診断で agent_count=3 = finder 3件のみ、verify agent 0件)。原因は pipeline の第2ステージが `finding => () => agent(...)` という thunk (未実行の関数) の配列を返しているだけで、それを実行する `parallel()`/awaited呼び出しが script 内に存在しないこと — 返り値がシリアライズ不能な関数を含むため `null` に落ちて `finderResults.flat().filter(Boolean)` で消え、`confirmed: []` / `totalFound: 0` という「0件検出」に見える結果になった。実際には review-bug×2 が SHOULD 1件・CONSIDER 1件を検出しており、これを本レビューでは手動で直接検証 (diff・Spec・該当ファイルの読み込み) して救済した。`modules/workflow-guidance.md` のインラインスクリプト自体のバグであり本 PR のスコープ外だが、`capabilities.workflow: true` を設定している他プロジェクトの `/review --full` すべてに影響するため、Improvement Proposal 候補として `/verify` 側での起票を推奨 (finder 検出後の verify 未実行を静かに握りつぶす = false negative のリスク)。

また、Issue #1005 本文の「Verification (pre-merge)」に記載の `tests/auto-sub-observability.bats (52件)` という件数表記は、実際にファイルを確認すると6件のみ (`grep -c "^@test"` = 6) であり、Issue 本文の記述精度に軽微な誤りがあった。AC のチェックボックスや verify command には影響しないため FAIL 扱いにはしていないが、Issue 起票時のテスト件数記載を実測値と照合する運用上の注意点として記録する。

### Acceptance criteria verification difficulty

4件の pre-merge AC (rubric 3件 + bats command 1件) はいずれも判定に迷いなく PASS 確定できた — rubric の文言が「何を確認すればよいか」を具体的に特定できる粒度で書かれており、UNCERTAIN の発生はゼロだった。Post-merge の observation AC は設計どおり判定保留。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- Step 10 の Workflow パス (finder → adversarial-verify) は `capabilities.workflow: true` により実行したが、verify ステージが実際には起動しない script 側のバグを発見したため、finder が検出した2件 (SHOULD 1件・CONSIDER 1件) を直接コード/Spec/diff を読んで手動検証し、レビュー結果に採用した。
- SHOULD (skills/auto/SKILL.md:921 の Detection signature 内部矛盾) は Issue のコア目的 (kill/recovery 計測の正確性) に直結するため修正。CONSIDER (run-auto-sub.sh:189 のヒアドキュメント変数展開) は現状 exploit 不可・既存の同種パターンと一貫しているため見送り。
- 修正は SKILL.md の条件分岐の厳密化のみで、AC の文言や verify command と矛盾しないため Step 13 (Acceptance Criteria Consistency Check) はスキップ判定。

### Deferred Items

- `_write_wrapper_retry_recovery()` の H3 → H2 形式修正は本 Issue のスコープ外 (spec retrospective の Minor observations に記録済み。`/verify` Step 13 が Improvement Proposal として起票する)。
- 外部 kill の発生源そのもの (H-a/H-b/H-c) は特定できず、`docs/reports/external-kill-investigation.md` に残存仮説として文書化した。
- `modules/workflow-guidance.md` インラインスクリプトの verify ステージ未実行バグは本 PR スコープ外 — 上記 Recurring issues に記録、`/verify` での Improvement Proposal 起票を推奨。
- CONSIDER (run-auto-sub.sh:189 ヒアドキュメント変数展開) は未修正のまま残存 (exploit 不可と判断し見送り)。

### Notes for Next Phase

- Post-merge AC (observation) は次回の実際の外部 kill 発生時まで検証できない — `/verify` は現時点では PASS/FAIL 判定不能な観測待ち状態として扱うこと。
- `/merge 1008` 実行可 (MUST issue なし、CI 全件 SUCCESS)。
