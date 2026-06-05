# Issue #534: detect-wrapper-anomaly: patch route の silent-no-op 判定で origin/main を参照して false positive を防止

## Overview

`detect-wrapper-anomaly.sh` の `silent-no-op` 検出において、patch route（`code-patch` フェーズ）では `worktree-merge-push.sh` 経由で commit が `origin/main` へ直接 push されるが、local main が未同期のタイミングで検査されると commit を見つけられず false positive が発生する。`PHASE == "code-patch"` の場合に `git fetch origin main` 後に `origin/main` を照合する判定を追加し、false positive を排除する。

## Reproduction Steps

1. `/auto --batch` で XS/S issue を実行（patch route、`code-patch` フェーズ）
2. `run-code.sh` が `worktree-merge-push.sh` 経由で commit を `origin/main` に push 完了（exit 0）
3. `detect-wrapper-anomaly.sh` が呼び出されるタイミングで local main が未同期
4. `git log --oneline -5 | grep "#N"` が commit を見つけられず `silent-no-op` と誤検出

## Root Cause

`detect-wrapper-anomaly.sh`（`elif [[ "$EXIT_CODE" == "0" ]]` ブロック）の `silent-no-op` 判定は `git log --oneline -5` で local git log のみを検査する。patch route では commit が `origin/main` へ push される一方、local main は `git pull` が行われるまで同期されない。対照的に `reconcile-phase-state.sh code-patch --check-completion` は `git fetch origin main` 後に `origin/main` を参照するため正確に判定できる。`detect-wrapper-anomaly.sh` はこの参照を行っていないため race condition が生じる。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `silent-no-op` 判定（`elif [[ "$EXIT_CODE" == "0" ]]` ブロック）に `code-patch` フェーズ向け `origin/main` 照合を追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: `code-patch` + `origin/main` シナリオのテストケースを 2 件追加

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `silent-no-op` 検出ブロック（`elif [[ "$EXIT_CODE" == "0" ]]` 以降）を修正（→ 受入条件 1, 2, 3）:
   - 現在の入れ子条件 (`grep -qiE success phrase && ! git log ... | grep`) を段階的に展開
   - `git log --oneline -5 | grep -q "#${ISSUE_NUMBER}"` で commit が見つかった場合は no-op スキップ（既存動作を維持）
   - commit が見つからず `PHASE == "code-patch"` の場合: `git fetch origin main 2>/dev/null` を実行し `git log origin/main --oneline -5 2>/dev/null | grep -q "#${ISSUE_NUMBER}"` で照合。commit が見つかれば `PATTERN_NAME` を設定せずスキップ
   - commit が origin/main にも見つからない場合（または PHASE が code-patch 以外、fetch 失敗）: 従来通り `PATTERN_NAME="silent-no-op"` を設定

2. `tests/detect-wrapper-anomaly.bats` に 2 件のテストケースを追加（→ 受入条件 4）:
   - `@test "silent no-op: no false positive for code-patch when commit found on origin/main"`: git を mock し `git log --oneline -5` は空、`git fetch origin main` は exit 0、`git log origin/main --oneline -5` は `#$ISSUE_NUMBER` を含む出力 → output が空（anomaly なし）
   - `@test "silent no-op: code-patch triggers detection when commit absent on both local and origin/main"`: git を mock し全コマンドが空出力 → `silent-no-op` が検出される

## Verification

### Pre-merge

- <!-- verify: grep "origin|reconcile|fetch" scripts/detect-wrapper-anomaly.sh --> `detect-wrapper-anomaly.sh` の silent-no-op 判定が origin/<base> 参照または reconcile 連携を行う
- <!-- verify: rubric "detect-wrapper-anomaly.sh の silent-no-op 検出が、patch route で commit が origin/main へ push 済みだが local main 未同期のケースを false positive としないよう、origin/<base> 照合または reconcile-phase-state.sh --check-completion の結果参照で改善されている" --> patch-route race の false positive が解消されている
- <!-- verify: file_contains "scripts/detect-wrapper-anomaly.sh" "origin/main" --> origin/main 参照が実装されている（rubric §9 補足）
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI green

### Post-merge

- `/auto --batch` で XS/S issue 実行時に `silent-no-op` false positive が発生しないことを確認

## Notes

- 実装アプローチとフェーズ限定範囲は Issue 自動解決済み（Issue #534 `## 自動解決された曖昧ポイント` 参照）
- 修正スコープは `PHASE == "code-patch"` のみ。`run-auto-sub.sh` 経由 XL サブ issue では `--phase "code"` が渡されるため本修正の対象外
- `reconcile-phase-state.sh` は `--grep="closes #N"` で commit を検索するが、`detect-wrapper-anomaly.sh` は `grep "#N"` を使用。この差異は今回のスコープ外（どちらも commit 存在確認として有効）
