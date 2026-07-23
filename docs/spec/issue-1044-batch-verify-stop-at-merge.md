# Issue #1044: auto: batch mode の Verify orchestration に auto-stop-at: merge を反映

## Consumed Comments

No new comments since last phase.

## Overview

`/auto --batch` の List mode (`--batch N1 N2 ...`) は、`skills/auto/SKILL.md` の Batch Mode セクション内で Issue ごとに `run-auto-sub.sh` を呼び出した後、Step 7 (Verify orchestration) で `phase/verify` ラベルの有無を確認し、`Skill(skill="wholework:verify", args="$NUMBER")` を parent session から dispatch する。この dispatch 判定は現状 `--non-interactive` の有無のみで分岐しており、`.wholework.yml` の `auto-stop-at` 設定を一切参照しない。そのため `auto-stop-at: merge` を設定していても、merge phase 完了後に verify phase まで自動実行されてしまう。

前例の Issue #1042 は `run-auto-sub.sh` 内部の `M)`/`L)` ケース (code→review→merge の直列実行) に stop-at gate を追加したが、この gate は `run-auto-sub.sh` の return 前 (merge phase 呼び出し前) にのみ配置されている。List mode Step 7 の Verify orchestration は `run-auto-sub.sh` の return **後**に parent session (SKILL.md 側) が独自に行う処理であり、#1042 の修正範囲には含まれていなかった。

**Scope (triage 時の auto-resolve により確定済み)**: 当初 Issue 本文では Count mode にも同種の gate が必要と想定されていたが、triage 時の調査で `skills/auto/SKILL.md` の Verify orchestration ステップ (parent session からの `Skill(skill="wholework:verify", ...)` dispatch) は List mode Step 7 にのみ存在し、Count mode の `Process Each Issue` 手順には該当ステップ自体が存在しないことを確認済み。`run-auto-sub.sh` は Size に関わらず verify を一切呼び出さない (`# verify is deferred to the parent /auto session`) ため、Count mode は「`auto-stop-at` 未反映」ではなく「dispatch ステップ自体の欠落」という別種のギャップであり、本 Issue のスコープ (List mode Step 7 への gate 追加) には含めない。

## Reproduction Steps

1. `.wholework.yml` に `auto-stop-at: merge` を設定したリポジトリで `/auto --batch N1 N2 ...` (List mode) を実行する。
2. 対象 Issue (Size M/L、または `always-pr: true` 昇格の XS/S) に対して `run-auto-sub.sh $NUMBER` が呼ばれ、code→review→merge まで正常に完了する (`run-auto-sub.sh` 自身は #1042 の gate により `auto-stop-at: merge` の場合でも merge phase までは実行するのが正しい挙動であり、ここは正常動作)。
3. `run-auto-sub.sh` が成功で return した後、`skills/auto/SKILL.md` List mode Step 7 (Verify orchestration) が実行され、Issue のラベルを再取得すると `phase/verify` が付与されている。
4. Step 7 は `AUTO_STOP_AT` を一切参照せず `--non-interactive` の有無のみで分岐するため、非対話モードでなければ `Skill(skill="wholework:verify", args="$NUMBER")` がそのまま dispatch されてしまう。
5. 結果: `auto-stop-at: merge` を設定していたにもかかわらず、merge 後に verify phase まで自動実行される。

## Root Cause

`skills/auto/SKILL.md` の Batch Mode は Step 1 で `--batch` を検出すると Steps 2–6 を丸ごとスキップして Batch Mode セクションへ分岐する。単独 `/auto N` の pr route (Step 4) が phase 完了ごとに参照する `EFFECTIVE_STOP_AT` は Step 2 でのみ算出されるため、Batch Mode の LLM 主導フロー内には元々この変数(および元になる `AUTO_STOP_AT`)が存在しない。List mode Step 7 の Verify orchestration ブロックはこの欠落の影響を直接受けており、`.wholework.yml` の `auto-stop-at` 値を読まないまま `--non-interactive` の有無だけで verify dispatch を判定しているため、`auto-stop-at: merge` が無視される。

## Changed Files

- `skills/auto/SKILL.md`: Batch Mode セクション「List mode (--batch N1 N2 ...)」に `AUTO_STOP_AT` の読み込みを追加し、Step 7 (Verify orchestration) に `AUTO_STOP_AT == "merge"` の場合の skip 分岐を追加する。
- `tests/auto-batch.bats`: List mode セクションに新しい skip 分岐の文言が含まれることを確認する構造テストを2件追加する (既存テストと同じ awk+grep による構造検証スタイル)。

## Implementation Steps

1. `skills/auto/SKILL.md` の「List mode (--batch N1 N2 ...)」内、「**Batch checkpoint initialization (List mode only):**」ブロック (`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_batch ...` を含む段落) の直後・「Process each Issue in `BATCH_LIST` in order:」の直前に、以下の一段落を追加する (Step 2 の `detect-config-markers.md` 読み込みパターンと同型) (→ 受入条件1):
   ```
   **Load stop-at setting (List mode only):**

   Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `AUTO_STOP_AT` for use in step 7's verify orchestration gate below.
   ```
2. (after 1) 「Process each Issue in `BATCH_LIST` in order:」以下の手順7 (**Verify orchestration**) を以下の構造に変更する (→ 受入条件1):
   - 現状:
     ```
     7. **Verify orchestration** (after run-auto-sub.sh success):
        - Re-fetch current labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
        - If `phase/verify` is present in labels:
          - If `--non-interactive` is NOT in ARGUMENTS: invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session
            - On success: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
            - On failure or output contains `MAX_ITERATIONS_REACHED`: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue
          - If `--non-interactive` IS in ARGUMENTS: output "Skipping verify for #$NUMBER (non-interactive mode); phase/verify remains"; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
        - If `phase/verify` is NOT in labels: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
     ```
   - 変更後 (`AUTO_STOP_AT == "merge"` の分岐を `--non-interactive` チェックより先に追加。既存の2分岐の構造・文言・`update_batch` 呼び出しは変更しない):
     ```
     7. **Verify orchestration** (after run-auto-sub.sh success):
        - Re-fetch current labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
        - If `phase/verify` is present in labels:
          - If `AUTO_STOP_AT == "merge"`: output "Skipping verify for #$NUMBER (auto-stop-at=merge); phase/verify remains"; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
          - Else if `--non-interactive` is NOT in ARGUMENTS: invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session
            - On success: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
            - On failure or output contains `MAX_ITERATIONS_REACHED`: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue
          - Else (`--non-interactive` IS in ARGUMENTS): output "Skipping verify for #$NUMBER (non-interactive mode); phase/verify remains"; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
        - If `phase/verify` is NOT in labels: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
     ```
   - `### Resume mode (--batch --resume)` は「List mode と同じ手順に従う」と規定されているため、本ステップの変更は Resume mode 経由の実行にも自動的に適用される (Resume mode 側の個別編集は不要)。
3. (after 2) `tests/auto-batch.bats` に以下の2テストを追加する。既存テスト (L19-56) と同じ `awk '/^### List mode/{found=1} ... found{print}' | grep -q '...'` 構造検証スタイルに揃える (→ 受入条件2):
   - `"List mode section: AUTO_STOP_AT retained for verify gate"` — List mode セクション内に `AUTO_STOP_AT` の文字列が含まれることを確認
   - `"List mode section: auto-stop-at merge skip behavior present"` — List mode セクション内に `auto-stop-at=merge` の文字列が含まれることを確認

## Verification

### Pre-merge
- <!-- verify: rubric "skills/auto/SKILL.md の Batch Mode セクション List mode Step 7 で verify dispatch 直前に AUTO_STOP_AT の check を行い、merge の場合 verify を skip して phase/verify を維持するロジックが実装されている" --> `skills/auto/SKILL.md` Batch Mode List mode Step 7 に `AUTO_STOP_AT == "merge"` の場合の verify skip gate が追加されている
- <!-- verify: rubric "auto-stop-at: merge 設定下で List mode batch 実行時に verify orchestration が skip されることを検証するテストが追加されている" --> `auto-stop-at: merge` 設定下で `/auto --batch N1 N2 ...` (List mode) を実行した際、run-merge.sh は実行され verify dispatch (parent Skill invoke) は実行されないことを確認する bats テストまたは同等の検証コードが追加されている

### Post-merge
- tofas repo (または他の `auto-stop-at: merge` 設定 repo) で `/auto --batch N1 N2 ...` を実行し、merge phase 完了後に verify phase が実行されず `phase/verify` label が維持されることを確認

## Notes

- SPEC_DEPTH=light (Size M → pr route 自動判定、非対話モード)。blocked-by なし (HAS_OPEN_BLOCKING=false)。
- **Steering Docs sync candidate 確認済み** (`grep -rn "auto-stop-at\|AUTO_STOP_AT" docs/ tests/ scripts/` 実行): `docs/workflow.md:107` と `docs/guide/customization.md:107,155,161-171` (および `docs/ja/` 対訳ミラー) は `auto-stop-at` を「`/auto` パイプラインを指定 phase で停止する」という汎用的な記述に留めており、batch mode の内部実装の詳細 (List mode Step 7 dispatch 判定の詳細) には触れていない。本修正後もこの記述は正確なまま (むしろ記述と実装の乖離が解消される) であり、テキスト変更は不要と判断した。`docs/spec/issue-*.md` は disposable な過去 Spec のため対象外 (`docs/tech.md` 「Spec-first (disposable)」方針)。`tests/auto.bats:65-66` の緩い "SKILL.md contains auto-stop-at keyword" 検証は本修正後も無条件に PASS し続けるため変更不要。`scripts/run-auto-sub.sh` は #1042 で既に修正済みのため対象外。
- **ヘルパー関数化の見送り (auto-resolve)**: Issue 本文 Notes は `should-stop-at-phase.sh` のような共通ヘルパー化の検討を推奨していたが、本 Issue では見送り、既存パターンに倣った最小差分の実装とした。理由: (1) `run-auto-sub.sh` 内の3箇所 (Tier3 skip 分岐、`M)`、`L)`) は bash 側のロジックであり、本 Issue の対象である List mode Step 7 は LLM 主導の SKILL.md prose であるため、両者を1つの bash ヘルパーで統合するには `skills/auto/SKILL.md` Step 4 の5箇所の `EFFECTIVE_STOP_AT` チェックも含めた横断的なリファクタリングが必要になり、Size M の Bug 修正としてのスコープを大きく超える。(2) 前例の Issue #1042 の Spec/retrospective は「4 箇所目の出現時に共通ヘルパー化を再検討する価値がある」として既存パターン踏襲を選択しており、既存コードとの差分最小化を優先する方針が確立されている。(3) 本 Issue の追加により分散箇所は合計6箇所となり #1042 が想定した閾値を既に超過しているため、ヘルパー化の再検討自体は妥当だが、その再検討と実施は本 Issue のスコープ外とし、別 Issue での実施を推奨する (下記参照)。
- **フォローアップ候補 (本 Issue のスコープ外、2件)**:
  1. Count mode (`--batch N`) に List mode Step 7 相当の verify orchestration ステップ自体が存在しない件 (Issue 本文 Notes 記載の既知ギャップ)。
  2. `auto-stop-at` 判定ロジックの共通ヘルパー化 (`should-stop-at-phase.sh` 等) — 本 Issue の実装により分散箇所が合計6箇所 (`run-auto-sub.sh` 内3箇所 + `skills/auto/SKILL.md` 単独 `/auto N` 経路 + List mode Step 7 + Count mode の潜在箇所) に達し、#1042 が設定した「4箇所目で再検討」の閾値を超過している。

## Auto Retrospective

### Manual recovery (spec)
- **Date**: 2026-07-23 12:44 UTC
- **Issue**: #1044, phase: spec
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success
