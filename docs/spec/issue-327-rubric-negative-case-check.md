# Issue #327: verify: rubric コマンドにネガティブケース検証の有無を問う形式を追加

## Overview

Issue #325 と #326 のレトロスペクティブで、`rubric` verify command のグレーダーが「テストが positive case のみを検証し negative case（誤った入力でマッチしないことの確認）を検証しない」というギャップを検出できないことが独立して指摘された。

`modules/verify-executor.md` の "Rubric Command Semantics > Adversarial stance" サブセクションに、ネガティブケース検証の観点を明示的に追記する。これにより、`rubric` グレーダーが「正しい入力でマッチすること」の確認だけでなく「誤った入力でマッチしないこと」も問うようになる。

## Changed Files

- `modules/verify-executor.md`: "Adversarial stance" サブセクション（line 95 付近）にネガティブケース検証のガイダンスを追加 — bash compat 非該当（shell script ではない）

## Implementation Steps

1. `modules/verify-executor.md` の "Adversarial stance" サブセクション末尾（"This guards against the bias of an LLM judging its own outputs favorably." の直後）に以下を追記する（→ 受け入れ基準1・2）:

   ```
   Explicitly ask whether the implementation tests negative cases (e.g., inputs that should NOT match, invalid values that should be rejected). Testing only positive cases while omitting negative case coverage is a common gap.
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/verify-executor.md" "Rubric Command Semantics" "negative" --> `modules/verify-executor.md` の "Rubric Command Semantics" セクションにネガティブケース検証に関する記述が追加されている
- <!-- verify: grep "negative.*(case|test|example)" "modules/verify-executor.md" --> rubric command の説明にネガティブケース検証の観点が含まれている

### Post-merge

- 実際の Issue の rubric verify で、ネガティブケース（誤った入力でマッチしないことの検証）が問われるようになることを確認

## Notes

- Auto-resolved: 実装場所は "Adversarial stance" サブセクション内に追記。既存のスタンス記述に続けて negative case 観点を追加するのが最も自然な統合位置のため（Issue 本文より）。
- Auto-resolved: verify コマンドは `section_contains "modules/verify-executor.md" "Rubric Command Semantics" "negative"` を使用。セクション特定により、"negative" がファイルの別箇所に偶発的に現れた場合の誤 PASS を防ぐ（Issue 本文より）。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
