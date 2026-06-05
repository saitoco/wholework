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

## Code Retrospective

### Deviations from Design
- None: 実装ステップはSpecの通りに実施。単一条件式の展開 → `_found_on_origin` フラグ導入による段階的分岐の構造も設計通り

### Design Gaps/Ambiguities
- `set -uo pipefail` 環境での `!` 付きパイプラインの動作: `-e`(errexit) が設定されていないため、parenの中で非ゼロ終了が起きてもスクリプトが落ちないことを確認。既存コード（line 91）も同パターンを使用済みで問題なし
- `_found_on_origin` 変数のスコープ: `set -u` 環境での未定義変数エラーを避けるため、`if [[ "$PHASE" == "code-patch" ]]` ブロックの前に初期化済み

### Rework
- None: 設計から実装まで一発で完了。テスト2件も即時 pass

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `git fetch origin main` + `origin/main` チェック方式を採用（reconcile 委譲より自己完結でシンプル）
- スコープは `PHASE == "code-patch"` のみに限定（他フェーズは origin push を行わないため影響なし）
- `_found_on_origin` フラグ変数で判定を整理（`set -uo pipefail` 環境でも安全）
- 既存テストへの影響なし（`--phase code` での既存テストは `_found_on_origin` が false のまま通る）

### Deferred Items
- `git fetch origin main` は main ブランチをハードコードしているが、BASE_BRANCH が main 以外の場合への対応はスコープ外
- 全テスト 25/25 green で CI 通過を確認済みだが、実際の `/auto --batch` 環境での end-to-end 確認は post-merge

### Notes for Next Phase
- 変更は `scripts/detect-wrapper-anomaly.sh` と `tests/detect-wrapper-anomaly.bats` の 2 ファイルのみ
- verify コマンド全4件 PASS 済み（チェックボックス更新完了）
- `origin/main` 文字列が `file_contains` verify に含まれるため、verify フェーズは機械的に確認可能

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件は全 4 件が verify command 付き（grep / rubric / file_contains / github_check）で、機械検証可能性が高い。`/issue` リファインメントで `file_contains "origin/main"` 補足条件が追加され、rubric 単独より検証粒度が向上した

#### design
- Spec の Implementation Steps が実装と 1:1 で一致。`_found_on_origin` フラグによる段階的分岐の構造まで設計通りに実装され、設計と実装の乖離はゼロ
- 実装アプローチ（直接 git fetch vs reconcile 委譲）とフェーズ限定範囲は `/issue` 段階で自動解決済み。spec phase が判断を再検討せず踏襲したため手戻りなし

#### code
- Code Retrospective に「設計から実装まで一発で完了、テスト 2 件も即時 pass」と記録。fixup/amend パターンなし、rework ゼロ
- `set -uo pipefail` 環境での `!` 付きパイプライン挙動と未定義変数スコープを事前確認しており、bash 互換性への配慮が適切

#### review
- patch route（Size S）のため review フェーズはスキップ。N/A

#### merge
- patch route のため main 直コミット（`1d0e953`）。merge フェーズ・コンフリクトなし

#### verify
- 全 4 条件 PASS、FAIL ゼロ。verify command と実装の不整合なし
- Issue は patch route の `closes #534` で merge 時に自動クローズ済み（ISSUE_STATE=CLOSED）。verify は phase/done 遷移のみ実施

### Improvement Proposals
- N/A（`git fetch origin main` の base ブランチハードコードは Phase Handoff で明示的にスコープ外として deferred 済み。patch route + 非 main base は稀なエッジケースであり、現時点で起票は見送り）
