# Issue #445: audit eager-load 共通モジュールへの capability guidance 混入検出

## Overview

`/audit drift` の Step 2「Project Documents categories」テーブルに、eager-load される共通モジュール（`modules/verify-patterns.md`・`modules/verify-executor.md`）への capability 固有のガイダンス content 混入を検出する行を追加する。検出ロジックは shell script として実装し、SKILL.md から呼び出す構成をとる。bats テストでフィクスチャを使った単体テストを実装する。

背景: Issue #441 で visual-diff capability を Domain file 化（`load_when: capability: visual-diff` gate）した際、共通モジュールへの混入が ~1500 tokens の overhead を招くことが判明した。`docs/environment-adaptation.md` Extension Guide Step 6 で規約を明文化済みだが、`/audit drift` での自動検出がなければ同じ間違いが繰り返されるリスクがある。

## Changed Files

- `skills/audit/SKILL.md`: Step 2「Project Documents categories (examples)」テーブルに eager-load 混入検出行を追加
- `scripts/check-eager-load-capability.sh`: 新規ファイル — bash 3.2+ 互換の検出スクリプト
- `tests/audit-eager-load-capability.bats`: 新規ファイル — bats テスト
- `docs/structure.md`: スクリプト数カウント更新（47 → 48）、Key Files > Scripts にエントリ追加

## Implementation Steps

1. `scripts/check-eager-load-capability.sh` を新規作成（bash 3.2+ 互換）
   - `--root <path>` オプションを受け付ける（デフォルト: カレントディレクトリ）
   - `<root>/modules/*-adapter.md` を Glob して capability 名（ファイル名から `-adapter.md` を除いたもの）を列挙
   - 各 capability 名について、`modules/verify-patterns.md` と `modules/verify-executor.md` の本文を grep し、セクション見出し（`^##* .*{capability}`）に capability 名が含まれる箇所を検出（case-insensitive）
   - 該当箇所がある場合、`<root>/skills/*/{capability}-guidance.md` が存在するか確認
   - Domain file が存在しない場合のみ `ISSUE: capability '{name}' guidance found in {file} (no Domain file at skills/*/{name}-guidance.md)` を出力
   - (→ 受け入れ条件 3)

2. `skills/audit/SKILL.md` の Step 2「Project Documents categories (examples)」テーブルに新行を追加（after 1）
   - `docs/environment-adaptation.md` Layer 3 行の直後に挿入:
     ```
     | eager-load 共通モジュールへの capability guidance 混入 | `${CLAUDE_PLUGIN_ROOT}/scripts/check-eager-load-capability.sh` を実行し出力を drift レポートに含める。スクリプトが行う処理: (1) `modules/{name}-adapter.md` を Glob して capability 名を列挙; (2) `modules/verify-patterns.md` と `modules/verify-executor.md` の本文のセクション見出し（table row 除く）に capability 名が現れる箇所を検出; (3) 対応する Domain file `skills/*/{name}-guidance.md` の存在を確認; (4) Domain file が存在しない場合に Issue 候補として記録 |
     ```
   - (→ 受け入れ条件 1・2)

3. `tests/audit-eager-load-capability.bats` を新規作成（after 1）
   - `setup()`: `mktemp -d` で BATS_TMPDIR を作成し、`modules/` と `skills/` ディレクトリを用意
   - `teardown()`: BATS_TMPDIR を削除
   - テスト1「detection: verify-patterns.md に visual-diff セクション見出しがあれば検出する」
     - `modules/visual-diff-adapter.md`（空ファイル）と `modules/verify-patterns.md`（`## visual-diff Guidance` セクションを含む汚染版）を配置
     - `bash "$SCRIPT" --root "$BATS_TMPDIR"` の出力に `visual-diff` が含まれることを確認
   - テスト2「no-issue: Domain file が存在する場合は出力なし」
     - 上記と同じ汚染版を配置しつつ、`skills/spec/visual-diff-guidance.md` も配置
     - 出力が空であることを確認
   - テスト3「clean: 汚染がなければ出力なし」
     - クリーンな verify-patterns.md を配置
     - 出力が空であることを確認
   - (→ 受け入れ条件 3)

4. `docs/structure.md` を更新（parallel with 1, 2）
   - Directory Layout の `scripts/` 行のカウントを `(47 files)` → `(48 files)` に変更
   - Key Files > Scripts > Tooling セクションに追加:
     `scripts/check-eager-load-capability.sh` — eager-load 共通モジュール（verify-patterns.md, verify-executor.md）への capability guidance 混入検出スクリプト；/audit drift Step 2 から呼び出される

5. `tests/audit-eager-load-capability.bats` に自己参照除外が不要なことを確認（after 3）
   - 検出スクリプトは `--root` 引数で指定したディレクトリの `modules/verify-patterns.md` のみを検索対象にするため、bats テストファイル自体はスキャン対象外。除外処理は不要。

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/audit/SKILL.md" "### Step 2: Drift Detection" "eager-load" --> `skills/audit/SKILL.md` の `### Step 2: Drift Detection` セクションに `eager-load` という文字列が含まれる
- <!-- verify: section_contains "skills/audit/SKILL.md" "### Step 2: Drift Detection" "verify-patterns.md" --> `skills/audit/SKILL.md` の `### Step 2: Drift Detection` セクションに `verify-patterns.md` という文字列が含まれる
- <!-- verify: rubric "tests/ ディレクトリに、verify-patterns.md に visual-diff guidance を直書きした fixture を用いて eager-load 混入を検出できることを確認するテスト (bats または scripts) が実装されている" --> `tests/audit-eager-load-capability.bats` に visual-diff contamination fixture を使った検出テストが存在する

### Post-merge

- `/audit drift` を手動実行し、現状 repo で false positive がないことを確認
- 意図的な regression（eager-load 混入）fixture で検出が動作することを実環境で確認

## Notes

- 検出スクリプトは `--root` オプションで repo ルートを外部から注入できる設計とし、bats テストでのフィクスチャ注入を可能にする
- bash 3.2+ 互換: `mapfile` や `associative array` は使用禁止。`while read -r` ループと通常の配列を使用する
- `modules/verify-executor.md` の「adapter-resolver に delegate していない built-in command 行の詳細除外」は今回スコープ外。セクション見出しレベルの grep で十分な機械的検出が可能と判断（Auto-Resolve: Issue 本文の明示スコープに絞ることで実装の確実性を優先）
- `docs/structure.md` のスクリプト数は実測 46 .sh + 1 .py = 47 ファイル（2026-05-11 時点）。本 Issue で 48 になる
