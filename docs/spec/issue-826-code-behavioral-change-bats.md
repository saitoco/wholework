# Issue #826: code: behavioral changes 時の bats フルスイート実行ガイドラインを追加

## Overview

`/code` (および `/auto` の code phase) で behavioral changes (既存ファイルを変更するケース) を含む実装をコミットする前に `bats tests/` フルスイートが実行されない運用ギャップがある。

`modules/verify-patterns.md` §24 は同じ retroで観察された補完的対策として、`/issue` フェーズの verify command 設計に「behavioral change 時はフルスイートを指定する」ガイドラインを提供している。本 Issue はその実行側 (`/code` phase 自体の Step 9) に対応するガイドラインを追加し、CI でのみ検出されていた regression を code phase で前倒し検知できるようにする。

`scripts/run-code.sh` は `skills/code/SKILL.md` のボディをそのまま `claude -p` のプロンプトとして使用するため、SKILL.md 更新が run-code.sh プロンプト更新と同義 (Issue body の Auto-Resolve Log にて確認済み)。

## Changed Files

- `skills/code/SKILL.md`: Step 9 (Run Tests) の冒頭 (`Read test-runner.md` 行の直前) に「Behavioral Change Detection」サブセクションを追加 — bash 3.2+ 互換の grep コマンドを使用

## Implementation Steps

1. `skills/code/SKILL.md` Step 9 冒頭に「Behavioral Change Detection」サブセクションを追加する (→ AC1)
   - `Read test-runner.md` の行の直前 (Step 9 の最初の文の前) に挿入
   - 手順:
     1. 変更したファイルのうち **既存ファイルが含まれるか** 確認 → 含まれない場合は test-runner auto-detection に委任 (ナロースコープ可)
     2. 既存ファイルが含まれる場合 → その修正ファイルが **直属テスト以外からも参照されているか** 確認 (`grep -rl "<modified-filename>" tests/` 等で検出)
     3. 参照が見つかれば behavioral change 検出 → test-runner auto-detection を上書きして **`bats tests/` フルスイートを実行する**
   - 定義は `modules/verify-patterns.md` §24 と統一: 「既存ファイルを変更し、かつそのファイルが変更ファイル直属のテスト以外からも参照されているケース」
   - 純粋に新規ファイルのみの追加は behavioral change 対象外

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md または modules/test-runner.md に、既存ファイルを変更する behavioral change が発生した場合は bats tests/ フルスイートを実行してから commit するガイドラインが追加されている" --> behavioral change 時のフルスイート実行ガイドラインが追加されている

### Post-merge

- 次回 code phase 実行時、behavioral changes を含む変更で `bats tests/` フルスイートが実行され、既存テストの regression が code phase で検出されることを観察 <!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - `bats tests/` が実行されたことが code phase の出力に示される
    - 既存テストの PASS/FAIL が報告される (FAIL → repair attempt が発動する)

## Notes

- **実装先の選択 (Option A)**: `modules/test-runner.md` は `skills/verify/SKILL.md` も参照するため、behavioral change 検出ロジックを追加すると verify phase にも影響が及ぶ。code phase 固有の問題なので `skills/code/SKILL.md` Step 9 に限定する
- **behavioral change 定義**: `modules/verify-patterns.md` §24 と統一 — 「既存ファイルを変更し、かつそのファイルが変更ファイル直属のテスト以外からも参照されているケース」; 純粋新規ファイル追加はナロースコープ可
- **SKILL.md = run-code.sh プロンプト**: `scripts/run-code.sh` は SKILL.md ボディをそのまま `-p` プロンプトとして使用。SKILL.md 更新が run-code.sh の動作変更と同義 (Issue body auto-resolve log にて確認)

## Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective (auto-resolve log) — "behavioral change" の定義を `modules/verify-patterns.md` §24 に統一; Proposal A/C を統合して A/B 2択に整理; rubric を 3択→2択 (`skills/code/SKILL.md` または `modules/test-runner.md`) に絞り込み。これらの決定は Issue body に反映済み。
