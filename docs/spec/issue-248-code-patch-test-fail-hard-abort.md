# Issue #248: code: patch route でテスト FAIL 時を hard-error abort に昇格

## Overview

`/code --patch` 経路（Size=XS/S）の non-interactive モードで、テストが FAIL した場合のハンドリングを soft gate から hard-error abort へ昇格させる。現状の `## Error Handling in Non-Interactive Mode` はハードエラー例外を「Size 未設定」「Size=XL」の 2 件のみ定義しており、テスト FAIL は Notes の soft 指示文のみで管理されている。patch route は `/merge` を経由しないため CI required gate がなく、テスト FAIL のまま main に push される余地がある。本 Issue は patch route でテストが 1 回の修正試行後も FAIL し続ける場合を hard-error abort 例外リストに追加し、Step 9 に明示的な FAIL ハンドリングを追加する。

## Changed Files

- `skills/code/SKILL.md`: `## Error Handling in Non-Interactive Mode` の hard-error abort 例外リストに patch route テスト FAIL ケース（1 回の修正試行後も FAIL なら abort）を追記
- `skills/code/SKILL.md`: `### Step 9: Run Tests` に patch route / pr route 区別付きの FAIL ハンドリング節を追加

## Implementation Steps

1. `## Error Handling in Non-Interactive Mode` の `- **hard-error abort** (exceptions...):` リスト末尾（`Size is \`XL\`` 行の直後）に 3 番目の例外を追加（→ 受入条件 1）:
   ```
     - patch route: test FAIL persists after 1 repair attempt (cannot push failing tests to main; fix tests manually then re-run `/code $NUMBER --patch`, then abort)
   ```

2. `### Step 9: Run Tests` の本文（`test-runner.md` 呼び出し指示の直後）に FAIL ハンドリング節を追加（→ 受入条件 2、3）:
   ```
   **Test FAIL handling (when test-runner.md reports FAIL):**

   1. Attempt to fix the failing tests (1 repair attempt)
   2. Re-run tests
   3. If tests still FAIL after the repair attempt:
      - **patch route (non-interactive mode)**: hard-error abort — output "Tests still FAIL after one repair attempt. Fix tests manually, then re-run \`/code $NUMBER --patch\`." and exit with non-zero
      - **patch route (interactive mode)**: use AskUserQuestion to let the user decide (abort / continue)
      - **pr route**: continue — CI will detect the failure; report remaining failures in the completion message
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/code/SKILL.md" "Error Handling in Non-Interactive Mode" "patch route" --> `## Error Handling in Non-Interactive Mode` の hard-error abort 例外一覧に patch route テスト失敗ケースが追記されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 9" "FAIL" --> Step 9 (Run Tests) に patch route 時の FAIL ハンドリング（1 回の修正試行後もなお FAIL なら abort）が明示されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 9" "patch route" --> Step 9 の記述で patch route と pr route の扱いの違いが明示されている

### Post-merge

- 意図的にテスト失敗を残した状態で `/code N --patch --non-interactive` を dry-run 相当で実行すると Step 11 (Commit) に進まずに abort することを確認
