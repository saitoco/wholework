# Issue #624: merge: PR merge 後の phase/review → phase/verify ラベル遷移漏れを検出・補正

## Overview

`/auto --batch` 実行時、PR merge 成功後に `/merge` スキルが `gh-label-transition.sh verify` を呼ぶ前に early-stop した場合、issue ラベルが `phase/review` に滞留する。`run-merge.sh` の completion check は merge 成功（PR MERGED 状態）を確認するが、ラベル遷移の完了は確認しない。

`run-merge.sh` の reconcile check 後にラベル状態を確認し、merge 完了済みかつ `phase/review` 滞留中の場合は自動補正する（Option A 実装）。

## Reproduction Steps

1. `/auto --batch` で複数 Issues を並行処理
2. ある Issue で PR が MERGED になった後、`claude -p` セッションが label transition 呼び出し前に early-stop
3. `run-merge.sh` は exit 0（reconcile が `matches_expected:true` を返すため）
4. Issue の phase ラベルが `phase/review` のまま滞留

## Root Cause

`skills/merge/SKILL.md:231` で `gh-label-transition.sh "$ISSUE_NUMBER" verify` を呼ぶが、`run-merge.sh` はこのラベル遷移呼び出しが完了したかを確認しない。reconcile は PR の MERGED 状態のみ検証するため、ラベル遷移漏れを検出できない。

## Changed Files

- `scripts/run-merge.sh`: merge 完了後の issue ラベル状態チェックと `phase/verify` 自動遷移ロジック追加 — bash 3.2+ compatible
- `tests/run-merge.bats`: `gh-label-transition.sh` no-op mock を setup() に追加、label stuck 自動遷移テストケース追加

## Implementation Steps

1. `scripts/run-merge.sh` の reconcile if/elif ブロック末尾（`if [[ -n "$_MERGE_ISSUE" ]]; then` の内側、`else` の直前）に追加 (→ AC1, AC2):
   ```bash
   if [[ $EXIT_CODE -eq 0 ]]; then
     _issue_labels=$(gh issue view "$_MERGE_ISSUE" --json labels -q '[.labels[].name]' 2>/dev/null || echo "")
     if echo "$_issue_labels" | grep -q '"phase/review"' && ! echo "$_issue_labels" | grep -q '"phase/verify"'; then
       echo "Warning: merge completed but phase label still at phase/review. Auto-transitioning to phase/verify." >&2
       "$SCRIPT_DIR/gh-label-transition.sh" "$_MERGE_ISSUE" verify || true
     fi
   fi
   ```

2. `tests/run-merge.bats` の setup() に `gh-label-transition.sh` no-op mock 追加（既存テストの再実行安全性確保）(after Step 1) (→ AC3):
   ```bash
   cat > "$MOCK_DIR/gh-label-transition.sh" <<'MOCK'
   #!/bin/bash
   exit 0
   MOCK
   chmod +x "$MOCK_DIR/gh-label-transition.sh"
   ```

3. `tests/run-merge.bats` に label stuck 自動遷移テストケース追加 (after Step 2) (→ AC3):
   - `LABEL_TRANSITION_LOG` で `gh-label-transition.sh` 呼び出しを記録
   - `gh issue view` が `["phase/review","triaged"]` を返す gh モック
   - テスト: `[ "$status" -eq 0 ]`、warning 出力確認、`CALLED: 99 verify` ログ確認

## Verification

### Pre-merge

- <!-- verify: grep "phase/review" "scripts/run-merge.sh" --> `run-merge.sh` に merge 後の issue ラベル状態チェックロジック（`phase/review` 滞留検出）が実装されている
- <!-- verify: grep "gh-label-transition" "scripts/run-merge.sh" --> `run-merge.sh` に `phase/verify` への自動遷移呼び出しが実装されている
- <!-- verify: command "bats tests/run-merge.bats" --> run-merge の bats テストが green（label stuck パターンの新規ケース含む）

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI（test.yml）の全ジョブが成功
- 次回 `/auto` 実行で merge→verify ラベル遷移漏れが発生した場合、wrapper が自動補正し stderr に warning を出すことを観察

## Notes

- `|| true` により label 遷移失敗が main の exit code に影響しない設計（silent recover の観測可能性は stderr warning で維持）
- 既存 reconcile テスト（exit 0 + matches_expected:true/empty）への影響なし: デフォルト gh モックが `gh issue view` に空文字列を返すため `phase/review` 検出が false になる
- Issue 本文の Auto-Resolved Ambiguity Points（`section_contains` → `grep` x2 変更、patch 経路 CI 検証 AC 追加）は既に Issue 本文に反映済み

## Code Retrospective

### Deviations from Design

- Spec Step 2 の `gh-label-transition.sh` mock は no-op（exit 0 のみ）として指定されていたが、`LABEL_TRANSITION_LOG` へのログ記録を追加した。Spec Step 3 の test assertion で `grep -q "CALLED: 99 verify"` を使うため、mock がログを記録しなければテストが成立しないため。

### Design Gaps/Ambiguities

- commit prefix: Issue type が Bug のため `fix:` が正しいが、type 取得（Step 11）より前の Step 8 で `feat:` を使ってコミットしてしまった。次回は type 取得後にコミット prefix を決定する手順を Step 8 より前に行うこと。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Option A（run-merge.sh の reconcile check 後にラベル状態チェックを追加）をそのまま実装。既存 reconcile ロジックの if/elif 末尾に EXIT_CODE=0 条件ガード付きで挿入した。
- `|| true` でラベル遷移失敗を exit code に波及させない設計を採用（Spec Notes に明記済み）。
- テスト mock では `LABEL_TRANSITION_LOG` を導入し、`gh-label-transition.sh` の呼び出しを記録可能にした（Spec Step 2 の「exit 0 のみ」から拡張）。

### Deferred Items
- コミット prefix が `fix:` でなく `feat:` になった（Step 8 で type 取得前にコミット）。次回コードレビュー時に指摘されうる。
- Post-merge CI 検証（`github_check "gh run list ..."`）は merge 後に自動実行される。

### Notes for Next Phase
- `/verify` フェーズでは post-merge AC（CI test.yml 全ジョブ成功）と observation AC（次回 /auto 実行での自動補正観察）を確認すること。
- bats テスト 17/17 PASS、forbidden expressions チェック、skill syntax validation すべて通過済み。
- PR なし（patch route）のため、CI は push 後の test.yml workflow で確認。
