# Issue #708: phase-state: code-patch/code-pr precondition に Spec exists (Size=XS は例外) を追加し future scope を解除

## Overview

`scripts/reconcile-phase-state.sh` の `--check-precondition code-patch` / `--check-precondition code-pr` は現在 `phase/ready` ラベルのみを確認し、Spec ファイルの存在を確認しない。これを修正し「Spec exists OR Size=XS」の precondition を追加することで、Spec なしの Issue に対して `/code` が誤って実行されるリスクを排除する。

あわせて `modules/phase-state.md` の Phase Table 内 "future scope" 注記を解除し、`skills/code/SKILL.md` Step 3 が `reconcile-phase-state.sh --check-precondition` を呼ぶよう更新する。

## Consumed Comments

- saito (MEMBER / first-class) — Issue Retrospective: 3 件の曖昧ポイントを自動解決済み (AC1 grep パターン変更、AC4 bats コマンド修正、AC6 追加)。既に Issue body に反映済み。
  URL: https://github.com/saitoco/wholework/issues/708#issuecomment-4759202336

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_precondition_code_common()` に Spec 存在チェック + Size=XS 例外ロジックを追加 (変数 `SPEC_EXISTS`、`_handle_mismatch "Spec missing and Size != XS"`) — bash 3.2+ compatible
- `modules/phase-state.md`: Phase Table の code-patch / code-pr 行の "future scope" 注記を "Implemented (Spec exists OR Size=XS)" に更新; JSON Schema に `actual.size` フィールドを追加
- `tests/reconcile-phase-state.bats`: Spec missing シナリオのテスト追加 (code-patch / code-pr 各 2 件); 既存テスト "same phase: precondition passes but completion not yet reached" を Spec ファイル有りに更新 (テスト意図を維持しつつ precondition を通過させる)
- `skills/code/SKILL.md`: Step 3 に `reconcile-phase-state.sh --check-precondition code-patch|code-pr $NUMBER` 呼び出しを追加; Spec missing 警告時の abort 推奨フローを明記

## Implementation Steps

1. `scripts/reconcile-phase-state.sh`: `_precondition_code_common()` を修正 — `phase/ready` チェック通過後に以下を追加: `SPEC_EXISTS=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)` (変数名は SPEC_EXISTS を使う)、`SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$ISSUE_NUMBER" 2>/dev/null || true)`; `actual_json` に `"size":"$SIZE"` フィールドを追加; SPEC_EXISTS が空かつ SIZE != "XS" の場合は `_handle_mismatch "Spec missing and Size != XS" "$actual_json"` で exit (→ AC1、AC2)
2. `modules/phase-state.md`: Phase Table の code-patch / code-pr 行 "Spec exists — future scope" を "Spec exists OR Size=XS — Implemented (Spec exists OR Size=XS)" に変更; JSON Schema フィールドテーブルに `actual.size` 行を追加 (When: "When spec precondition is checked with Size check") (→ AC3)
3. `tests/reconcile-phase-state.bats`: 新規テスト 3 件追加 — `"code-patch precondition: Spec missing and Size != XS -> mismatch"`, `"code-patch precondition: Spec missing but Size XS -> matches_expected true"`, `"code-pr precondition: Spec missing and Size != XS -> mismatch"` (各テストで `get-issue-size.sh` モックを `$MOCK_DIR` に配置); 既存テスト `"same phase: precondition passes but completion not yet reached"` を修正: `no-spec` ディレクトリに `issue-42-spec.md` を touch して precondition が通過するようにする (→ AC4、AC5)
4. `skills/code/SKILL.md` Step 3 に追加: XS でない場合に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh --check-precondition code-patch $NUMBER` (または code-pr) を実行し、`matches_expected` が false の場合は「Spec が見つかりません。\`/spec $NUMBER\` を実行してください」と出力して abort 推奨 (→ AC6)

## Verification

### Pre-merge

- <!-- verify: grep "SPEC_EXISTS" "scripts/reconcile-phase-state.sh" --> `reconcile-phase-state.sh` の code-patch / code-pr precondition に Spec 存在チェックロジックが追加されている
- <!-- verify: grep "Size != XS" "scripts/reconcile-phase-state.sh" --> Size=XS の場合に Spec チェックを skip するロジックがある
- <!-- verify: file_contains "modules/phase-state.md" "Implemented (Spec exists OR Size=XS)" --> Phase Table の future scope 注記が解除されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> phase-state 関連テストが green
- <!-- verify: file_contains "tests/reconcile-phase-state.bats" "Spec missing" --> Spec missing シナリオの bats テストが追加されている
- <!-- verify: grep "check-precondition" "skills/code/SKILL.md" --> `/code` SKILL.md が `reconcile-phase-state.sh --check-precondition` を呼ぶよう更新されている

### Post-merge

- 試験的に `phase/ready` のみ付与・Spec 無しの M Issue に対して `reconcile-phase-state.sh --check-precondition code-pr N` を実行すると `matches_expected: false` を返すことを観察
- 試験的に XS Issue (Spec 無し) に対して同コマンドを実行すると `matches_expected: true` を返すことを観察

## Notes

### Auto-Resolve: AC5 ファイル名修正 (non-interactive mode)

Issue body AC5 の verify command が `"tests/test-reconcile-phase-state.bats"` を参照していたが、このファイルは存在しない。実際の bats テストファイルは `tests/reconcile-phase-state.bats` であるため、AC5 を以下に自動修正:

- 修正前: `file_contains "tests/test-reconcile-phase-state.bats" "Spec missing"`
- 修正後: `file_contains "tests/reconcile-phase-state.bats" "Spec missing"`

### 既存テスト更新の必要性

"same phase: precondition passes but completion not yet reached" (line 809) は `MOCK_SPEC_PATH` を空ディレクトリに設定している。新 Spec チェック追加後、このテストは Spec missing として precondition FAIL になるため、`issue-42-spec.md` を作成して precondition が通過するよう修正が必要。

### `actual_json` への `"size"` フィールド追加

`_precondition_code_common()` は SIZE を `get-issue-size.sh` で取得する。Spec missing かつ Size != XS の mismatch 診断を明確にするため、`actual_json` に `"size":"$SIZE"` フィールドを含める。これは `modules/phase-state.md` JSON Schema の `actual.size` 追加と対応する。

### SPEC_DEPTH=light での Verification 件数

Issue body が 6 件の pre-merge AC を持つため Spec light 上限 (5 件) を 1 件超過するが、全 AC を漏れなく反映する。
