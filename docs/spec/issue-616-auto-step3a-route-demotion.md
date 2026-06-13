# Issue #616: auto: Step 3a 再判定で実行中ルートを M/pr → patch に縮退

## Overview

`/auto` の Step 3a（Post-Spec Size Refresh）が、Size を M→XS/S に再判定してもフェーズシーケンスを変更しない問題を修正する。

現状: ROUTE と REVIEW_DEPTH を更新するが、Step 4 で実行されるフェーズシーケンス（code → review → merge → verify）はそのまま。
目的: ROUTE が pr → patch に変化した場合（route demotion）、Step 4 を patch シーケンス（code(--patch) → verify）に切り替える。

2026-06-14 バッチ実行で確認されたコスト: #581、#548 がそれぞれ M→XS 再判定されたにもかかわらず pr ルートで code+review+merge+verify を実行。各 ~30 分の無駄。

## Changed Files

- `skills/auto/SKILL.md`: Step 3a に route demotion 仕様を追加（pr→patch 縮退時のログ出力 + Step 4 パッチシーケンス使用の明示）
- `tests/auto.bats`: 新規作成（route demotion の構造テスト）

## Implementation Steps

1. `skills/auto/SKILL.md` の Step 3a 末尾を拡張する (→ AC1)
   - 既存の「If route changed from Step 2, output a log line: "Post-spec Size refresh..."」を維持
   - その後に route demotion 専用ブロックを追加:
     - 適用条件: ROUTE が `pr` から `patch` に変化した場合のみ（pr → XS/S 縮退）
     - ログ出力: `"Post-spec route demotion: pr → patch, remaining phases re-planned"`
     - Step 4 では patch ルートシーケンス（code(--patch) → verify）を使用するよう明示
   - 挿入箇所: 「Proceed to Step 4 using the updated ROUTE and REVIEW_DEPTH.」の直前

2. `tests/auto.bats` を新規作成する (after 1) (→ AC2)
   - ファイル冒頭のコメントに Issue #616 参照を記載
   - SKILL_FILE 変数で `skills/auto/SKILL.md` を参照
   - Step 3a セクション抽出 helper（awk で `### Step 3a:` から次の `### ` まで）を定義
   - テスト 1: Step 3a セクションに "route demotion" が含まれること
   - テスト 2: Step 3a セクションに "Post-spec route demotion" が含まれること

## Verification

### Pre-merge

- <!-- verify: grep -A 20 "route demotion" "skills/auto/SKILL.md" --> Step 3a に route demotion 仕様が記述されている
- <!-- verify: command "bats tests/auto.bats" --> auto skill の bats テストが green（route demotion の新規ケース含む）

### Post-merge

- 次回 `/auto` 実行で M→XS 再判定された Issue が patch ルート所要時間（< 25 分）で完走することを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- route demotion の適用条件は「pr → patch」のみ（patch → pr の昇格は Step 3a のスコープ外）
- `--patch` / `--pr` 等の明示フラグがある場合は Step 3a 自体がスキップされるため、route demotion は発生しない（既存の skip 条件が維持される）
- `tests/auto.bats` は SKILL.md の構造テスト（ファイルへのスクリプト呼び出しなし）。WHOLEWORK_SCRIPT_DIR モックは不要
- AC の post-merge 観察条件（observation event=auto-run）は既存の opportunistic-search.sh 仕組みで自動評価される
