# Issue #980: run-auto-sub: Tier 3 recovery action=skip 後に後続 phase へ継続

## Consumed Comments

No new comments since last phase.

## Overview

`run-auto-sub.sh` の Tier 3 recovery (`spawn-recovery-subagent.sh`) が `action=skip` (phase を完了扱い) を返した場合に、後続 phase (review/merge) へ継続しないケースがある。調査の結果、この問題は **XS/S (patch route) に限定される** ことを確認した。M/L (pr route) では `run_phase_with_recovery "code-pr" ...` の直後に review/merge の呼び出しが tier/action を問わず無条件に実行される構造になっているため、Tier 3 skip 後も既に正しく継続する (bats プローブテストで実証済み)。一方 XS/S ブランチは code-patch phase を当該ルートの終端として扱う設計 (patch route は元来 PR を経由しない) のため、Tier 3 skip が実際には PR 作成済みの状態を覆い隠すケース (#979 のようなルート誤判定が絡む場合) で、review/merge へ迂回する手段が存在しない。

本 Issue では、`run_phase_with_recovery()` が Tier 3 の recovery action (`retry`/`skip`/`recover`) を呼び出し元に伝播する仕組みを追加し、XS/S ブランチで `action=skip` かつ実際に PR が存在する場合に review → merge へ継続するようにする (`auto-stop-at` 設定を尊重)。/auto SKILL.md Step 6 の定義 (「`action=skip`: treat the phase as complete and continue to the next phase」) との整合を取る。

## Reproduction Steps

1. XS/S (patch route) の Issue に対し `/auto` (内部的には `run-auto-sub.sh`) を実行する。
2. `run-code.sh --patch` が非ゼロ終了する一方、実際には PR 作成を伴う変更が生じている (例: #979 の `get-config-value.sh` パース欠陥により `always-pr` 昇格が発動せず S ルートのまま実行され、その内部で PR ベースの変更が生じた場合)。
3. Tier 1 (`reconcile-phase-state.sh code-patch --check-completion`) が `code-patch` の完了シグネチャで照合するため `matches_expected:false` を返す (実際は PR が存在し、patch シグネチャと一致しない)。
4. Tier 2 (`apply-fallback.sh`) も既知パターンに一致せず失敗する。
5. Tier 3 (`spawn-recovery-subagent.sh`) の recovery sub-agent が状況を分析し `action=skip` を返す。`spawn-recovery-subagent.sh` 自身は `write_recovery_entry` 実行後 exit 0 で終了する。
6. `run_phase_with_recovery()` は Tier 3 成功を検知しログ出力・`docs/reports/orchestration-recoveries.md` へのコミットなどを行い `return 0` するが、`XS)`/`S)` の case ブランチには `run_phase_with_recovery "code-patch" ...` 呼び出し以降に review/merge 呼び出しが一切存在しないため、case 文はそのまま終了しスクリプト全体も exit 0 で正常終了する。
7. 結果として、実際には review/merge が必要な PR が存在するにもかかわらず Issue のラベルは `phase/code` のまま更新されず、`/auto --batch` の親セッションはこの Issue を放置する (手動での review phase 起動が必要になる)。

## Root Cause

`run-auto-sub.sh` の Size ベース case 文 (`XS)`/`S)` ブランチ) は、code-patch phase を当該ルートの終端 phase として無条件に扱う設計になっている。これは code-patch が文字通り patch として完了する通常ケースでは正しい。しかし Tier 3 recovery の `action=skip` は「complete 相当として扱う」という判定に過ぎず、実際に patch として完了したことを保証しない。特に #979 のようなルート誤判定が絡むと、実際には PR が作成された状態でも `run-auto-sub.sh` 自身は S ルートの `code-patch` 呼び出しとして phase を追跡しているため、Tier 1 の completion check は誤った (patch) シグネチャで照合し `matches_expected:false` を返し、Tier 3 の skip 判定に到達する。

加えて `run_phase_with_recovery()` は Tier 3 sub-agent の成功 (exit 0) のみを見て復旧完了として扱っており、`spawn-recovery-subagent.sh` が `.tmp/recovery-plan-${issue}-${phase}.json` に書き出す `action` フィールド (`retry`/`skip`/`recover`) を一切読み取っていない。このため呼び出し元 (`XS)`/`S)` ブランチ) は「どの action で復旧したか」を知る手段がなく、`action=skip` 特有の「実体が想定と異なる可能性がある」ケースを検知して review/merge へ迂回させることができない。

対照的に M/L (pr route) ブランチでは `run_phase_with_recovery "code-pr" ...` の直後に review/merge の呼び出しが (tier/action を問わず) 無条件に続くため、この構造的な欠落は発生しない (bats プローブで実証: M ルートは Tier3 skip 後も review/merge が実行され、S ルートは実行されない)。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` の Tier 3 recovery 成功ブロックで recovery action を `.tmp/recovery-plan-${issue}-${phase}.json` の `action` フィールドから読み取りスクリプトスコープ変数 `_TIER3_RECOVERY_ACTION` に保持 (読み取り後 plan file を `rm -f` で削除)。`XS)`/`S)` case ラベルを `XS|S)` に統合し (現状 body が完全に重複しているため)、`_TIER3_RECOVERY_ACTION == "skip"` かつ該当 issue の worktree ブランチに紐づく PR が存在する場合に、`auto-stop-at` 設定 (`code`/`spec` なら継続しない) を確認したうえで review (`--light`) → merge へ継続するロジックを追加する。bash 3.2+ compatible (既存の `local`/`case`/`[[ ]]` 構文のみ、新規 bash4+ 構文なし)。[Steering Docs sync candidate: `docs/tech.md` / `docs/structure.md` / `docs/workflow.md` (+ `docs/ja/` ミラー) に `run-auto-sub.sh` の 3-tier recovery 構造への言及があるが、いずれも抽象度の高いレベルの記述 (「3-tier recovery」「(3) spawn-recovery-subagent.sh on unknown anomaly」等) に留まり phase 継続のセマンティクスには踏み込んでいないため、更新不要と判断済み]
- `tests/run-auto-sub.bats`: Tier3 skip 後に stray PR が見つかり review/merge へ継続することを検証する新規テスト、および `auto-stop-at: code` 設定時に継続しないことを確認する新規テストを追加する。

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` を変更する (→ 受入条件1)。
   - 関数冒頭 (`phase="$1"; issue="$2"; runner_script="$3"; shift 3` の直後) に `_TIER3_RECOVERY_ACTION=""` を追加し、呼び出しごとにリセットする。
   - Tier 3 recovery 成功ブロック (`if "$SCRIPT_DIR/spawn-recovery-subagent.sh" ...; then` の直後、`echo "${LOG_PREFIX} [recovery] tier3 sub-agent: recovered"` の次の行) に以下を追加する:
     ```bash
     local _plan_file=".tmp/recovery-plan-${issue}-${phase}.json"
     _TIER3_RECOVERY_ACTION=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('action','unknown'))" "$_plan_file" 2>/dev/null || echo "unknown")
     rm -f "$_plan_file"
     ```

2. (after 1) `XS)`/`S)` case ラベルを `XS|S)` に統合し、`run_phase_with_recovery "code-patch" "$SUB_NUMBER" "$SCRIPT_DIR/run-code.sh" --patch ${BASE_FLAG:-}` 呼び出し直後に以下の継続ロジックを追加する (→ 受入条件1):
   ```bash
   if [[ "${_TIER3_RECOVERY_ACTION:-}" == "skip" ]]; then
     _SKIP_PR_NUMBER=$(gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true)
     if [[ -n "$_SKIP_PR_NUMBER" ]]; then
       _STOP_AT=$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify 2>/dev/null || echo verify)
       if [[ "$_STOP_AT" == "code" || "$_STOP_AT" == "spec" ]]; then
         echo "${LOG_PREFIX} [recovery] tier3 skip revealed PR #${_SKIP_PR_NUMBER} for issue #${SUB_NUMBER}, but auto-stop-at=${_STOP_AT}: not continuing"
       else
         echo "${LOG_PREFIX} [recovery] tier3 skip revealed PR #${_SKIP_PR_NUMBER} for issue #${SUB_NUMBER}; continuing to review/merge"
         echo "${LOG_PREFIX} --- review phase (light): PR #${_SKIP_PR_NUMBER} ---"
         _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$_SKIP_PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light
         echo "${LOG_PREFIX} --- merge phase: PR #${_SKIP_PR_NUMBER} ---"
         _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "merge" "$_SKIP_PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
       fi
     fi
   fi
   ```
   PR 抽出は M/L ブランチの `PR_NUMBER` 取得と同一の exact-match jq フィルタ (`select(.headRefName == "worktree-code+issue-${SUB_NUMBER}")`, #311/#325 準拠) を再利用する。PR が見つからない場合は何もしない (patch route の正常完了として現状維持)。

3. (after 2) `tests/run-auto-sub.bats` に新規テストを 2 件追加する (→ 受入条件2)。
   - `spawn-recovery-subagent.sh` のモックを `mkdir -p .tmp && echo '{"action":"skip","rationale":"...","steps":[]}' > ".tmp/recovery-plan-${2}-${1}.json"` としたうえで exit 0 するよう拡張する (`$1`=phase, `$2`=issue の位置引数)。
   - テスト A: `Size S` + `run-code.sh` exit 1 + 上記 skip モック + デフォルトの `gh pr list` モック (issue #42 の worktree ブランチにマッチする PR #99 を返す) の組み合わせで `bash "$SCRIPT" 42` を実行し、`run-review.sh`/`run-merge.sh` が呼ばれたこと (`RUN_REVIEW_LOG`/`RUN_MERGE_LOG` が存在し、review 呼び出しに `--light` が含まれること) を確認する。テスト名に `tier3 skip reveals stray PR: continues to review/merge` を含める。
   - テスト B: テスト A と同条件に `.wholework.yml` へ `auto-stop-at: code` を追記し、`run-review.sh`/`run-merge.sh` が呼ばれない (`RUN_REVIEW_LOG`/`RUN_MERGE_LOG` が存在しない) ことを確認する。
   - 既存テスト "Size XS/S: run-code.sh --patch is called, run-review.sh and run-merge.sh are not called" (`run-code.sh` は exit 0 のまま、Tier 1-3 に到達しないケース) が無修正で PASS することを回帰確認する。

## Verification

### Pre-merge
- <!-- verify: grep -n "_TIER3_RECOVERY_ACTION" scripts/run-auto-sub.sh --> Tier 3 skip 適用後に後続 phase へ継続するロジックが存在する (skip → return/continue で次 phase に進む)
- <!-- verify: file_contains "tests/run-auto-sub.bats" "tier3 skip reveals stray PR: continues to review/merge" --> skip 適用後に後続 phase が実行されることを検証する bats テストが追加されている

### Post-merge
なし

## Notes

- SPEC_DEPTH=light (Size M → pr route 自動判定)。blocked-by なし (HAS_OPEN_BLOCKING=false)。
- **Issue 本文と実装の齟齬 (Step 6 conflict detection)**: Issue 本文は「code phase で Tier 3 skip 後に後続 phase (review/merge) を実行しない」と一般的に記述しているが、実装調査 (bats プローブテスト 6 件、全 PASS で検証) の結果、この問題は XS/S (patch route) に限定されることを確認した。M/L (pr route) では `run_phase_with_recovery "code-pr" ...` 呼び出し後、review/merge 呼び出しが case ブランチ内で無条件 (tier/action を問わず) に実行される構造のため、Tier 3 recovery (skip 含む) 後も既に正しく継続する。修正範囲を XS/S に限定した。
- **AC1 の verify command 強化**: Issue 本文の `grep -n "skip" scripts/run-auto-sub.sh` は、現行コードに resume-preamble 機能由来の `skip-to-review` (本 Issue とは無関係な既存文字列) が既に存在するため、修正前でも trivially true となり回帰検証として機能しない。より厳密な `grep -n "_TIER3_RECOVERY_ACTION" scripts/run-auto-sub.sh` (修正前に不在であることを確認済み) に強化し、Issue 本文側の verify command も合わせて更新した。
- **AC2 の verify command 新設**: Issue 本文の AC2 (「skip 適用後に後続 phase が実行されることを検証する bats テストが追加されている」) には verify command が付与されていなかった (`/verify` が機械検証できない状態だった)。新規に `file_contains` を設計し、Spec と Issue 本文の両方に追加した。
- **`auto-stop-at` respect のスコープ**: `run-auto-sub.sh` は現状どこにも `auto-stop-at`/`--stop-at` の読み取りロジックを持たない (対応しているのは `skills/auto/SKILL.md` の in-session flow のみ)。本 Issue の Purpose 文が明示する「stop-at 設定を尊重」は、今回追加する新規継続ロジック (XS/S の skip 後 review/merge 継続) にローカルなガードとして限定実装した。`run-auto-sub.sh` 全体への `auto-stop-at` retrofit は本 Issue のスコープ外と判断し、必要であれば別途の改善候補として起票する。
- Review phase の depth は `--light` を採用した (M route の always-pr 昇格ケースと同じ扱い。XS/S には元々 review 深度の先例がないため、既存の "promoted to pr route" ケースに倣った)。
- 新規変数名 `_TIER3_RECOVERY_ACTION` は `skills/auto/SKILL.md` Step 6 5b の `TIER3_RECOVERY_ACTION` (in-session 変数名) に用語を合わせつつ、`run-auto-sub.sh` 内の既存の script-scope 変数命名規則 (`_` prefix、例: `_CODE_PR_DONE`, `_RESUME_ACTION`) に整合させた。
- `.tmp/recovery-plan-${issue}-${phase}.json` の読み取り後クリーンアップ (`rm -f`) は Tier3 recovery 成功時全般 (retry/recover を含む全 phase) に適用される。従来 `run-auto-sub.sh` 側は本ファイルを一切クリーンアップしていなかった (副次的なリークの解消)。
- Related Issue #979 (`get-config-value.sh` のインラインコメント未 strip・改行なし最終行パース欠陥) は本 Issue が説明する実インシデントの根本原因だが、別 Issue として既に起票・スコープ分離されているため、本 Spec では扱わない。

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の Changed Files/Implementation Step 3 は `tests/run-auto-sub.bats` への 2 件のテスト追加を明示していたが、PR #992 の diff は `scripts/run-auto-sub.sh` のみで、テストファイルは未変更のまま提出されていた。AC2 の verify command (`file_contains`) がこの乖離を機械的に検出し FAIL と判定した (review Step 8 で確認)。review で追加実装し解消した。
- `auto-stop-at` の 3 値 (`code`/`spec` → 停止, それ以外 → review+merge 継続) という実装は、Spec Notes が明示する「stop-at 設定を尊重する」という Purpose と比べて `review` 値の扱いが漏れていた (5値enumのうち `review` が停止側にも継続側にも正しく分類されず、merge 側のデフォルトに落ちる)。Spec 自身は「ローカルガードとして限定実装」と明記し retrofit の対象外と判断していたが、その限定実装の内部でも enum 網羅性が担保されていなかった。「一部の値だけスコープ内とする」判断をする際は、スコープ内の値についてだけは全列挙を満たすことを Spec の Verification に明記すると良い。

### Recurring issues

- `auto-stop-at` の enum 網羅性ギャップは `skills/review/SKILL.md:853` に記録されている既存パターン (#783 の `spec` 値欠落) と同じクラスの不具合であり、今回で少なくとも 2 件目の発生。`auto-stop-at` を読み取る箇所が複数 (in-session `/auto` フロー、`run-auto-sub.sh` の複数 case 分岐) に分散しており、値を追加/変更するたびに全呼び出し箇所を手動で網羅する必要がある構造そのものが再発の温床になっている。共通ヘルパー化 (例: `auto-stop-at` の値を「継続可否」の bool に正規化する単一関数) を検討する価値がある。

### Acceptance criteria verification difficulty

- AC1/AC2 の verify command (`grep`/`file_contains`) はいずれも意図通り機械検証でき、AC2 は実際に本来検出すべき欠落を正しく FAIL 判定した。verify command 自体の設計に問題はなかった。
- 一方、AC ではカバーされない深い到達可能性の問題を review で発見した: `spawn-recovery-subagent.sh` の `skip)` 分岐は自前で `matches_expected` を再検証して拒否する内部ガードを持つが、bats テスト (今回追加した 2 件を含む) はすべて `spawn-recovery-subagent.sh` 自体をモックしているため、この内部ガードは一度もテストで運動 (exercise) されない。結果として、PR の対象シナリオ (route 誤判定によるstray PR) では `_completion_code_patch()` が `matches_expected:false` を返し続け、`spawn-recovery-subagent.sh` の内部ガードが `action=skip` を拒否し、本 PR の新規継続ロジックそのものに到達しない可能性が高いことが判明した (フォローアップ Issue #993 として起票)。Tier3 recovery のような多層 (dispatch script 内部ガード + 呼び出し元ロジック) な機構については、外側だけでなく実 dispatch script の内部ガードを最低 1 パスは実運動する統合テストが無いと、全テスト PASS でも機能が到達不能なまま merge されうる。

## Phase Handoff

<!-- phase: review -->

### Key Decisions

- review (light) で検出した MUST 2件 (bats テスト欠落・`auto-stop-at: review` の enum 網羅性欠落) はこの review サイクル内で直接修正し、push 済み (commit bd36b4f2, b2ded965)。
- MUST 3件目 (`_completion_code_patch` が stray PR を completion signature として検出できない可能性) は、`reconcile-phase-state.sh` が `/auto` SKILL.md Step 6 からも共有される点を踏まえ、本 PR の Changed Files 範囲を超える設計変更と判断し、この review サイクルでは修正しなかった。

### Deferred Items

- フォローアップ Issue #993 (`_completion_code_patch` の stray-PR 未検出) を起票済み。#980 の merge をブロックしない (blocked-by 関係は設定していない)。実際に必要かどうかは #993 の Spec フェーズで再検証すること。
- `auto-stop-at` の enum 網羅性ギャップが再発パターン (#783 系) であることを retrospective に記録した。共通ヘルパー化の改善候補は起票していない (この review では見送り)。

### Notes for Next Phase

- merge 前提条件: AC1/AC2 とも PASS 済み、CI 全て SUCCESS、bats 58/58 PASS。
- `docs/spec/issue-980-*.md` に紐づく worktree (`.claude/worktrees/code+issue-980`) が、PID 消滅済みのロックを保持したまま残存している (今回 review では detached HEAD で作業し削除は権限上見送った)。merge/次セッションで安全に `git worktree remove` してよい (branch `worktree-code+issue-980` の HEAD はリモートと一致済み)。
