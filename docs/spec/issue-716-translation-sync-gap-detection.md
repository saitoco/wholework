# Issue #716: improvement: docs/ja/ 翻訳同期漏れの自動検出 (繰り返しパターン)

## Overview

`docs/` 配下の英語ファイルを変更した際に、対応する `docs/ja/` ミラーの同期漏れを自動検出する仕組みを実装する。
具体的には `scripts/check-translation-sync.sh` の出力に "Translation sync gap" warning を追加し、`/code` SKILL.md の同期チェックを passive な手順参照から能動的なギャップ検出に強化する。

## Changed Files

- `scripts/check-translation-sync.sh`: OUTDATED/MISSING_JA エントリに "Translation sync gap" warning 行を追加 (summary 行の後、stdout) — bash 3.2+ compatible
- `skills/code/SKILL.md`: Step 9 `docs/ja/` sync check を passive な手順参照から能動的なギャップ検出 + warning 出力 + 同期手順へ置き換え
- `tests/check-translation-sync.bats`: "Translation sync gap" 出力の bats テスト 2 件追加 (OUTDATED / MISSING_JA 各ケース)

## Implementation Steps

1. `scripts/check-translation-sync.sh` を修正し、OUTDATED/MISSING_JA を判定したループ内の `printf` 行の直後に warning 行を stdout に追加する (→ AC2)

   - OUTDATED の場合 (ループ内の `status="OUTDATED"` ブランチの `printf` の直後): `echo "Translation sync gap: $en_file was updated but $ja_file was not"`
   - MISSING_JA の場合 (ループ内の `status="MISSING_JA"` ブランチの `printf` の直後): `echo "Translation sync gap: $ja_file does not exist"`
   - 既存の `$en_file` / `$ja_file` 変数はループスコープ内にあるため、そのまま参照可能
   - bash 3.2+ 互換: `echo` を使用

2. `skills/code/SKILL.md` Step 9 の `docs/ja/` sync check を以下の形に置き換える (→ AC1)

   現在:
   ```
   **`docs/ja/` sync check:** If `docs/translation-workflow.md` exists, read it and follow the sync procedure.
   ```

   変更後:
   ```
   **`docs/ja/` sync check (gap detection + sync):** If `docs/translation-workflow.md` exists:
   1. Identify all `docs/*.md` and `docs/guide/*.md` files changed in this session (excluding `docs/ja/`, `docs/spec/`, `docs/stats/`, `docs/reports/`)
   2. For each changed file, check whether the corresponding `docs/ja/` counterpart was also updated in this session
   3. For any counterpart that was NOT updated: output "Translation sync gap: [en_file] was updated but docs/ja/[en_file_basename] was not" and then follow `docs/translation-workflow.md` sync procedure to update the missing counterpart
   4. After sync, optionally run `bash scripts/check-translation-sync.sh` to confirm IN_SYNC status (runs against committed state — only accurate after commit)
   ```

3. `tests/check-translation-sync.bats` に以下の 2 テストを追加する (→ AC3, regression guard)

   ```bash
   @test "outdated: Translation sync gap warning output for OUTDATED file" {
       # same setup as the existing "outdated" test
       echo "ja content" > docs/ja/en.md
       git add docs/ja/en.md
       GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
           git commit -q -m "add ja"
       echo "en content" > docs/en.md
       git add docs/en.md
       GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
           git commit -q -m "add en"
       run bash "$SCRIPT"
       [ "$status" -eq 0 ]
       [[ "$output" == *"Translation sync gap"* ]]
   }

   @test "missing_ja: Translation sync gap warning output for MISSING_JA file" {
       echo "en content" > docs/en.md
       git add docs/en.md
       GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
           git commit -q -m "add en"
       run bash "$SCRIPT"
       [ "$status" -eq 0 ]
       [[ "$output" == *"Translation sync gap"* ]]
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "docs/ 配下の英語ファイル変更時に翻訳同期状態を自動チェックする機構が実装されている (scripts/, modules/, skills/ のいずれかに提案 1-4 のうち少なくとも一つが実装済み)" --> 上記提案 1-4 のうちいずれかが実装され、`docs/` の英語ファイル変更時に翻訳同期状態が自動チェックされる
- <!-- verify: rubric "翻訳同期漏れ検出時に 'Translation sync gap' または同等の内容を含む明確な warning メッセージが出力される仕組みが実装されている" --> 翻訳同期漏れが検出された際に明確な warning メッセージが出力される (例: "Translation sync gap: docs/X.md was updated but docs/ja/X.md was not")
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存テスト (`bats tests/*.bats`) が green

### Post-merge

- 次回 `docs/` 配下の英語ファイル変更を含む PR で、warning が期待通り発火することを確認 <!-- verify-type: opportunistic -->

## Notes

### Conflict with implementation (Proposal 1)

Issue 本文 Proposal 1 は "scripts/check-translation-sync.sh の新規追加" と記述しているが、このスクリプトは Issue #173 で既に実装済み。

Auto-resolution (non-interactive mode): Proposal 1 は既実装として扱い、Proposal 2 (code フェーズ warning 検出) を主実装とする。合わせてスクリプト自体に "Translation sync gap" 出力形式を追加することで Proposal 1 の不足部分 (warning format) を補完する。

### Auto-Resolve Log

- **Proposal 1 の既実装コンフリクト** — reason: `scripts/check-translation-sync.sh` は Issue #173 で実装済み。Proposal 2 (code フェーズ) + スクリプト warning 出力拡張を実装することで AC1/AC2 を満たす。
- **warning 出力先 (stdout vs stderr)** — reason: stdout に追加 (summary 行の後)。理由: 既存 bats テストが `$output` (stdout) を参照するため。stderr だと新規テストで `$stderr` を使う必要があり、既存テストとの一貫性が低下する。既存の `grep "IN_SYNC"` パイプチェーン (#585 等) への影響なし (warning 行は summary の後、独立行)。

### check-translation-sync.sh の動作特性

- git commit タイムスタンプ比較のため、未コミット変更は検出されない
- そのため `/code` Step 9 の gap detection は「git diff で変更ファイルを特定し counterpart の存在を確認する」という LLM 判断ベースの手法を採用
- `bash scripts/check-translation-sync.sh` によるコミット後確認を Implementation Step 2 の手順 4 として案内 (optional)

## Consumed Comments

- T-Saito (OWNER) / first-class: Issue Retrospective (pre-cutoff) — rubric verify commands の自動付与、`verify-type: opportunistic` 修正。cutoff (2026-06-20T14:32:43Z) 以降の新規コメントなし。
