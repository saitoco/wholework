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

## Code Retrospective

### Deviations from Design
- bats テストの `step3a_section` helper で `declare -f` を使った `bash -c "$(declare -f ...; ...)"` 方式は動作せず（bats 環境で SKILL_FILE 変数が引き継がれない）。関数を直接 top-level で定義し `run step3a_section "$SKILL_FILE"` で呼ぶ方式に変更した

### Design Gaps/Ambiguities
- N/A

### Rework
- `tests/auto.bats` を初稿（`declare -f` 方式）→ 修正版（直接関数呼び出し方式）に 1 回書き直した

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/auto/SKILL.md` の Step 3a 末尾（「Proceed to Step 4 using...」の直前）に route demotion 専用ブロックを追加。既存ログ出力行は変更せず、その後に新ブロックを挿入した
- bats テストは SKILL.md の構造テスト（内容確認のみ、外部コマンド呼び出しなし）とし、WHOLEWORK_SCRIPT_DIR モックは不要
- `docs/structure.md` のテストファイル数が既に実態（64件）からずれていたため、新ファイル追加分を含めて 65 に更新した

### Deferred Items
- Step 4 の pr/patch ルート分岐コード自体（`run-auto-sub.sh` または `skills/auto/SKILL.md` Step 4 本文）は変更なし。route demotion 発生時に Step 4 が実際に patch シーケンスを選択するかは、Step 4 の「ROUTE 変数に基づく分岐」ロジックに依存する（既存ロジックで対応済みか要確認）
- post-merge 観察条件（M→XS 再判定 Issue が patch ルートで完走）は observation event で自動評価される

### Notes for Next Phase
- PR #620 がマージされたら、次回 `/auto` バッチで M→XS 再判定 Issue の実行時間が短縮されたかを観察する
- review フェーズでは「Step 4 本文に route demotion 分岐が反映されているか」を spec 照合として確認することを推奨（本 PR の実装は Step 3a 仕様追加のみ）
- forbidden expressions チェックは通過済み、validate-skill-syntax.py もエラーなし
