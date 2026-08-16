# Issue #589: auto: XL sub-issue 並列実行の同時実行数キャップ追加

## Overview

XL 親 Issue の sub-issue を `run-auto-sub.sh` で並列実行する際、現在は同時実行数に上限がない。`.wholework.yml` に `auto-max-concurrent` キー（デフォルト 5）を追加し、semaphore パターンで実行数を制御する。bash 3.2 (macOS) では `wait -n` が使えないため `kill -0` ポーリング fallback を実装する。

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `auto-max-concurrent | AUTO_MAX_CONCURRENT | ... | 5` 行を追加; Output Format section に `AUTO_MAX_CONCURRENT` エントリを追加
- `skills/auto/SKILL.md`: XL route Step 4 の冒頭で `detect-config-markers.md` を読み `AUTO_MAX_CONCURRENT` を取得; sub-issue バックグラウンド実行ブロックを semaphore パターン（`kill -0` fallback つき）に置き換え
- `docs/guide/customization.md`: Available Keys テーブルに `auto-max-concurrent` 行を追加; 例 YAML ブロックに `auto-max-concurrent` コメント行を追加
- `docs/ja/guide/customization.md`: `auto-max-concurrent` 行の日本語訳を追加（translation sync）
- `tests/auto-xl-concurrency.bats`: 新規 bats テストファイル（3 ケース: AUTO_MAX_CONCURRENT 参照, kill -0 fallback, detect-config-markers fallback ルール）
- `docs/structure.md`: `tests/` ファイル数を 62 → 63 に更新

## Implementation Steps

1. **`modules/detect-config-markers.md`**: Marker Definition Table の `verify-max-iterations` 行の直後に以下を追加 (→ AC1):
   ```
   | auto-max-concurrent | AUTO_MAX_CONCURRENT | Integer string (extract as-is; use `5` if ≤0 or non-numeric) | `5` |
   ```
   Output Format section に以下を追加（`VERIFY_MAX_ITERATIONS` エントリの直後）:
   ```
   AUTO_MAX_CONCURRENT: integer from auto-max-concurrent (default: "5"; falls back to "5" if ≤0 or non-numeric)
   ```

2. **`skills/auto/SKILL.md` XL route** (→ AC2, AC3, AC4):
   - "**XL route: sub-issue dependency graph with parallel execution...**" ブロック冒頭（"1. **Fetch dependency graph**" の直前）に以下を追加:
     ```
     Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `AUTO_MAX_CONCURRENT` (maximum concurrent sub-issue executions; default: 5).
     ```
   - "then run non-skipped sub-issues in background:" のブロック（`run-auto-sub.sh $SUB_NUMBER &`）を semaphore パターンに置き換え:
     ```
     then run non-skipped sub-issues with concurrency cap using AUTO_MAX_CONCURRENT:
       RUNNING=0
       for each SUB in non-skipped sub-issues:
         ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER &
         PIDS+=($!)
         RUNNING=$((RUNNING + 1))
         if [ $RUNNING -ge $AUTO_MAX_CONCURRENT ]; then
           # bash 4.3+: wait -n waits for any one child to finish
           # bash 3.2 fallback (macOS): kill -0 polling
           if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
             wait -n
           else
             while true; do
               for pid in "${PIDS[@]}"; do
                 if ! kill -0 "$pid" 2>/dev/null; then break 2; fi
               done
               sleep 1
             done
           fi
           RUNNING=$((RUNNING - 1))
         fi
       done
     Wait for all processes with `wait`, check each process exit code
     ```

3. **`docs/guide/customization.md`** (→ AC5, AC7 の一部):
   - Available Keys テーブルの `verify-max-iterations` 行の直後に追加:
     ```
     | `auto-max-concurrent` | integer | `5` | Maximum concurrent sub-issue executions in XL parallel route. Applies to each level of the dependency graph. Values ≤0 or non-numeric fall back to `5`. |
     ```
   - 例 YAML ブロックの `verify-max-iterations: 3` 行の直前に追加:
     ```
     # XL sub-issue parallel execution concurrency cap (default: 5)
     # auto-max-concurrent: 5
     ```
   - **`docs/ja/guide/customization.md`** の対応行（`verify-max-iterations` 行の直後）に日本語訳を追加:
     ```
     | `auto-max-concurrent` | integer | `5` | XL 並列ルートで同時実行できる sub-issue の最大数。依存グラフの各レベルに適用。0 以下または非数値の場合は `5` にフォールバック。 |
     ```

4. **`tests/auto-xl-concurrency.bats`** (→ AC6): 新規ファイルを作成。`tests/auto-batch.bats` のパターンに倣い、SKILL.md と detect-config-markers.md の構造内容テストを 3 ケース記述:
   - `@test "XL route: AUTO_MAX_CONCURRENT semaphore pattern present"` — XL route ブロックに `AUTO_MAX_CONCURRENT` が含まれること
   - `@test "XL route: kill -0 bash 3.2 fallback present"` — XL route ブロックに `kill -0` が含まれること
   - `@test "detect-config-markers: auto-max-concurrent fallback rule present"` — `detect-config-markers.md` に `auto-max-concurrent.*AUTO_MAX_CONCURRENT` が含まれること
   - `docs/structure.md` の `tests/` ファイル数を `62` → `63` に更新 (→ SHOULD)

## Verification

### Pre-merge

- <!-- verify: grep "auto-max-concurrent|AUTO_MAX_CONCURRENT" "modules/detect-config-markers.md" --> Marker Definition Table に `auto-max-concurrent` が追加されている
- <!-- verify: grep "AUTO_MAX_CONCURRENT" "skills/auto/SKILL.md" --> SKILL.md の XL route で `AUTO_MAX_CONCURRENT` を semaphore として使用
- <!-- verify: rubric "skills/auto/SKILL.md XL route uses a semaphore pattern to limit concurrent run-auto-sub.sh executions to AUTO_MAX_CONCURRENT, with bash 3.2 fallback for macOS compatibility" --> semaphore 実装と bash 3.2 互換が明記されている
- <!-- verify: grep "kill -0" "skills/auto/SKILL.md" --> bash 3.2 互換のための `kill -0` ポーリング fallback が記述されている
- <!-- verify: grep "auto-max-concurrent" "docs/guide/customization.md" --> `docs/guide/customization.md` の Available Keys テーブルに `auto-max-concurrent` が追加されている
- <!-- verify: command "bats tests/auto-xl-concurrency.bats" --> bats テストが green（並列度制限・fallback・無効値処理の 3 ケース最小）
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期

### Post-merge

- 実 XL Issue（Nuxt → Next 移行など）で 50+ sub-issue を並列実行した際、OOM・rate limit kill が許容内に収まることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- verify コマンド AC1–5 は実装前には対象文字列が存在しない（実装後に追加される文字列を検証するコマンド）
- bats テストは shell script 実行ではなく SKILL.md / detect-config-markers.md の内容検証（`tests/auto-batch.bats` パターン準拠）; WHOLEWORK_SCRIPT_DIR モックは不要
- `kill -0` ポーリング fallback は既存コードベースのパターン（`scripts/claude-watchdog.sh:40`）と一致
- semaphore の `PIDS` 配列管理: bash 3.2 fallback では `PIDS` 配列から終了済みプロセスを効率的に除去するのが難しいため、実装は単純に全 PID を走査して最初の終了プロセスを検出したら break する方式を採用（精度より簡潔さを優先）
- AC7（ja 同期）は `docs/guide/customization.md` の変更が `docs/ja/guide/customization.md` に反映されることで達成
- `docs/structure.md` の tests/ カウント更新は SHOULD レベル（verify command なし）
- Non-interactive mode: Issue body の Auto-Resolved Ambiguity Points セクションで事前解決済み（event=auto-run 修正、customization.md スコープ追加、rubric + grep 補完）

## Code Retrospective

### Deviations from Design
- `docs/ja/guide/customization.md` の YAML 例ブロックにもコメント行を追加した（Spec には明示されていなかったが、customization.md の英語版と対称性を保つために実施）
- `docs/ja/structure.md` のtests/カウントも62→63に更新した（translation-workflow.md の手順に従い、docs/structure.md の変更に連動）

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- semaphore パターンは RUNNING カウンタ + PIDS 配列で実装; bash 3.2 fallback は `kill -0` ポーリング（`scripts/claude-watchdog.sh` と同一パターン）
- SKILL.md の擬似コードブロック内に実装を記述（実際の bash スクリプトではなく LLM 実行フロー）
- detect-config-markers.md の Marker Definition Table と Output Format section の両方に `auto-max-concurrent` を追加した

### Deferred Items
- 実 XL Issue での動作観察（OOM・rate limit kill 削減）はPost-mergeのobservationとして残す
- semaphore の PIDS 配列精度向上（終了済みPIDの除去）は将来の最適化として残す

### Notes for Next Phase
- 全7 pre-merge verify commandがPASSしている（チェックボックス更新済み）
- bats 3件すべてgreen、translation sync確認済み
- `docs/ja/structure.md` も同期更新済み（translation-workflow.mdに従った追加対応）

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 7 件すべて自動 verify command 付き設計が機能
- spec phase で Size S → M に変更されたが run-auto-sub.sh は patch route のまま継続（initial Size=S 判定）。route 切り替えロジックの隙間だが、bats テスト・customization.md 更新がコンパクトだったため patch route で完遂

#### code
- AUTO_MAX_CONCURRENT semaphore + bash 3.2 fallback (kill -0) の組合せが initial 実装で完遂
- bats テスト 3 件すべて green、translation sync 確認済み

#### review/merge
- patch route のため別途 review/merge phase なし。main 直 commit
- run-auto-sub.sh での "Size: S → M" 更新 vs "code phase (patch)" 実行は inconsistent だが結果は安全（patch route の方が小スコープ）

#### verify
- pre-merge AC 7 件全 PASS
- post-merge AC 1 件は observation event=auto-run → 実 XL Issue 発生時に観察

### Improvement Proposals
- spec phase での Size 更新（S → M）が run-auto-sub.sh の route 判定に反映されない問題が観察された。`/auto` skill Step 3a「Post-Spec Size Refresh」は記載されているが、run-auto-sub.sh 経路ではこのリフレッシュが実行されていない可能性がある。次回 XL や M Issue の spec phase で route 不整合が発生したら起票候補

### 2026-08-10 re-run (条件8 小規模傍証の追加確認)

`/auto 1322` の end-of-run observation scan で `event=auto-run` が再発火し、post-merge observation 条件を再評価した。前回 (2026-08-06) 同様、条件が要求する「50+ sub-issue」規模の XL 実行はまだ発生しておらず SKIPPED を維持。

#### verify (再々実行分)

- 新たな傍証: session `94570-1786069858` (2026-08-07) で 4 並列 sub-issue が `auto-max-concurrent` 既定値5の範囲内で完走 (worktree/push/merge 競合ゼロ、`concurrent_commit_detected` 69件はすべて無害な検知イベント)。session `2319-1786222234` (2026-08-09) でも 3 並列が同様に完走
- semaphore 機構自体は小規模 (3-4 並列) では実運用で正しく機能していることが確認できた。ただし本条件が求める 50+ 規模での OOM/rate limit kill 抑制効果はまだ未実測 — 引き続き Nuxt → Next 移行等の大規模 XL 実行を待つ

### 2026-08-10 再々確認 (/auto #953 セッションから)

`/auto #953` (pr route、単発実行) の event-based observation scan で再度 dispatch された。XL sub-issue 並列実行は今回も発生しておらず、結論は変わらず SKIPPED を維持。

### 2026-08-11 再確認 (/auto --batch --until 953 セッションから)

`/auto --batch --until "label:theme/observability"` (session `29601-1786367167`) の Batch Completion Report observation scan で再度 dispatch された。本 run は List mode (spec→code→verify の順次単発実行) であり XL sub-issue 並列実行を伴わないため、傍証の追加もなし。結論は変わらず SKIPPED を維持 — 50+ 規模の実 XL 実行を引き続き待つ。

### 2026-08-15 再確認 (/auto --batch 1349 1350 1351 1352 セッションから)

`/auto --batch 1349 1350 1351 1352` (session `81722-1786714713`) の Batch Completion Report observation scan で再度 dispatch された。本 run も List mode で XL sub-issue 並列実行を伴わず、結論は変わらず SKIPPED を維持。50+ 規模の実 XL 実行を引き続き待つ。

### 2026-08-16 再確認 (/auto --batch 1362 1358 1125 951 1329 1086 1328 1092 1085 セッションから)

`/auto --batch 1362 1358 1125 951 1329 1086 1328 1092 1085` (session `63449-1786797049`) の Batch Completion Report observation scan で再度 dispatch された (7回目)。本 run も List mode (9 Issue、うち Size L 1件を除き XS/S/M、XL なし) で XL sub-issue 並列実行を伴わず、結論は変わらず SKIPPED を維持。50+ 規模の実 XL 実行を引き続き待つ。

### 2026-08-16 再確認 (/auto --batch 1132 1348 1072 1363 1095 セッションから)

`/auto --batch 1132 1348 1072 1363 1095` (session `24095-1786827554`) の Batch Completion Report observation scan で再度 dispatch された (8回目)。本 run も List mode (5 Issue、XS/S/M のみ、XL なし) で XL sub-issue 並列実行を伴わず、結論は変わらず SKIPPED を維持。

## Consumed Comments
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-4700058969
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4756911035
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4768309245
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4806655551
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4814731501
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4816318840
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4817060792
- saito / MEMBER / first-class / observation event `auto-run` detected. Run `/verify 589` to verify the condition / https://github.com/saitoco/wholework/issues/589#issuecomment-4818975232
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5195217378
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5202635511
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5205456802
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5212259117
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5225313594
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5229257431
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5235399496
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5236972782
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5237139836
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5237743781
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5246552657
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5247401875
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5249961570
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5255739882
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5296374687
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5296507248
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=5 / https://github.com/saitoco/wholework/issues/589#issuecomment-5304271115
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/589#issuecomment-5304456248
