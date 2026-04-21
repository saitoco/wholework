# Issue #301: /auto XL route で patch lock timeout 失敗を自動再試行する

## Overview

`/auto` XL route で複数の sub-issue を並列実行する際、patch lock 待機タイムアウト（`Patch lock acquisition timeout (300s)`）で exit 1 になった sub-issue を、同一 level の他 sub-issue が完走した後に 1 回だけ自動再試行する。

背景: Issue #292 の XL 並列実行で発生した失敗パターンは定型（lock 解放待ち）で、`wait` 完了後には他 sub-issue のロックが解放済みのため安全に再試行できる。retry ループ禁止（2 回目も timeout なら通常 failure として扱う）。

## Changed Files

- `skills/auto/SKILL.md`: Step 4 XL route の並列実行部分に lock-timeout retry ロジックを追加；"On failure" 節に自動再試行の説明を追記；Step 4a Auto Retrospective の Result 判定基準に `SUCCESS (auto-retry after lock timeout)` を追加

## Implementation Steps

1. `skills/auto/SKILL.md` Step 4 XL route の item 2 "Run levels in order, in parallel" を更新:
   - 背景プロセスの起動行を出力キャプチャ付きに変更:
     ```
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER > .tmp/auto-sub-$SUB_NUMBER.txt 2>&1 &
     ```
   - `wait` 完了後（"After `wait` completes, aggregate-update parent phase" の直前）に **Lock-timeout retry** ブロックを追加:
     ```
     # Lock-timeout retry (at most once per sub-issue):
     For each failed sub-issue (exit code != 0):
       read .tmp/auto-sub-$SUB_NUMBER.txt
       if output contains "Patch lock acquisition timeout":
         retry: ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER
         if retry succeeds (exit 0): record outcome as SUCCESS_LOCK_RETRY
         if retry also fails with "Patch lock acquisition timeout": treat as regular failure
         if retry fails with other error: treat as regular failure
     ```
   - `.tmp/auto-sub-$SUB_NUMBER.txt` は各 level 完了後に削除する

2. Step 4 "On failure" 節（"Add failed sub-issue numbers to the failure set" の前）に注記を追加:
   ```
   - Lock-timeout failures (output contains "Patch lock acquisition timeout") receive exactly
     one auto-retry after all same-level sub-issues complete (see Lock-timeout retry step above).
     Only after retry failure (or non-lock-timeout failures) are issue numbers added to the
     failure set.
   ```

3. Step 4a "Auto Retrospective" の Result column 判定基準に項目を追加:
   - 現行: "exit code 0 → `SUCCESS`, non-zero exit code → `FAILED (exit code N)`, dependency skip → `SKIPPED (blocked by #X)`"
   - 追記: "exit code 0 after auto-retry for lock timeout → `SUCCESS (auto-retry after lock timeout)`"

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh (or the /auto XL-route logic) detects patch-lock-timeout exit-1 failures by matching the specific error substring and performs exactly one automatic retry after other parallel sub-issues finish, without entering a retry loop" --> lock timeout 失敗の検出と 1 回だけの自動再試行が実装されている
- <!-- verify: rubric "The /auto SKILL.md documents the auto-retry behavior, including that auto-retried successes are logged in the Auto Retrospective's Execution Summary as 'SUCCESS (auto-retry after lock timeout)'" --> /auto SKILL.md に auto-retry 挙動とログ形式が記載されている

### Post-merge

- 意図的に lock timeout を短く設定した環境、または 3 件以上の patch route sub-issue を持つ XL Issue で `/auto` を走らせ、自動再試行が機能することを確認 <!-- verify-type: manual -->

## Notes

- ISSUE_TYPE=Task のため Uncertainty・UI Design セクションは省略
- 自動再試行のタイミング: `wait` 完了後（全並列プロセス終了後）であるため、lock ホルダーが既に解放済みであり安全に再試行できる
- retry は逐次実行（並列不要）。他の sub-issue は既に完走済みのため lock 競合は発生しない
- 2 回目の lock timeout はそのまま failure set へ追加（retry ループ禁止）
- Non-interactive モードのため自動解決: 実装箇所は SKILL.md（LLM 実行）とし、`run-auto-sub.sh` 側の変更は行わない（シェルスクリプト側は lock 保持者を知る手段がないため）
