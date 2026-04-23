# Issue #373: terminology: verify command 旧称 (verify hint 他 3 形) の根絶とデータソース一掃

## Overview

deprecated語 (`verify hint` / `verification hint` / `verify ヒント` / `検証ヒント`) が再発し続けている根本原因は 4 層構造:

1. CI `DEPRECATED_TERMS` に短形 `"verify hint"` と日本語形 2 件が未登録
2. `docs/product.md § Terms` Formerly called 列に 1 variant しか収録されていない
3. `scripts/check-forbidden-expressions.sh` が `docs/spec/` を除外しており新規 Spec への混入を検知できない
4. CLAUDE.md に用語統一ルールがなく sub-agent が deprecated 語を再生産し続ける

データソース一掃 (docs/spec/ 37 ファイル, 102 行) + CLAUDE.md 指示 + CI 配列拡張 + docs/spec/ 除外削除の 3 軸同時対応で再発を断つ。

## Changed Files

- `CLAUDE.md`: `## 用語` セクション追加 — deprecated 4 variants を明示
- `docs/product.md`: verify command 行の Formerly called を 5 旧称 variants 列挙に更新
- `docs/ja/product.md`: 同行の `旧称:` を同内容で同期
- `scripts/check-forbidden-expressions.sh`: DEPRECATED_TERMS に `"verify hint"` / `"verify ヒント"` / `"検証ヒント"` 3 件追加; `check_term` 内の `grep -v 'docs/spec/'` 1 行削除 (bash 3.2+ 互換)
- `tests/check-forbidden-expressions.bats`: 新検出テスト 3 件追加; `@test "exclusion: term in docs/spec exits 0"` → `@test "detection: term in docs/spec exits 1"` に変更
- `docs/spec/` (37 ファイル, 102 行): deprecated 4 variants を `sed` 一括置換
  - 計測スコープ: `grep -rni "verify hint\|verification hint\|verify ヒント\|検証ヒント" docs/spec/` (全 .md ファイル, `docs/spec/` のみ)

## Implementation Steps

1. `docs/spec/` 一括置換 — `find docs/spec/ -name "*.md"` に対して `sed -i ''` で下記 6 パターンを順に置換。複数形を先に処理すること (→ AC 13):
   - `[Vv]erification hints` → `verify commands`
   - `[Vv]erification hint` → `verify command`
   - `[Vv]erify hints` → `verify commands`
   - `[Vv]erify hint` → `verify command`
   - `verify ヒント` → `verify command`
   - `検証ヒント` → `verify command`

2. `docs/product.md` の verify command 行 (line 167) を更新 (→ AC 10, 11): Formerly called 部分を以下に置換:
   - 旧: `Formerly called "verification hint / Acceptance check"`
   - 新: `Formerly called: 'verification hint', 'verify hint', 'verify ヒント', '検証ヒント', 'Acceptance check'`

3. `docs/ja/product.md` の verify command 行 (line 157) を同期 (→ AC 12): `旧称:` 部分を更新:
   - 旧: `旧称: "verification hint / Acceptance check"`
   - 新: `旧称: 'verification hint', 'verify hint', 'verify ヒント', '検証ヒント', 'Acceptance check'`

4. `CLAUDE.md` の `## Notes` の前に `## 用語` セクションを追加 (→ AC 1–5):
   ```markdown
   ## 用語

   - `verify hint` / `verification hint` / `verify ヒント` / `検証ヒント` は deprecated。常に `verify command` を使用する (SSoT: `docs/product.md § Terms`)。
   ```

5. `scripts/check-forbidden-expressions.sh` と `tests/check-forbidden-expressions.bats` を同時更新 (→ AC 6–9, 13):
   - `check-forbidden-expressions.sh`: `DEPRECATED_TERMS` の `"shared procedure document"` の後に以下 3 件を追加:
     ```bash
       "verify hint"
       "verify ヒント"
       "検証ヒント"
     ```
   - `check-forbidden-expressions.sh`: `check_term` 関数内の `| grep -v 'docs/spec/' \` 1 行を削除 (他の除外行 `Formerly called`, `旧称`, `tests/check-forbidden-expressions.bats` は据え置き)
   - `check-forbidden-expressions.bats`: `@test "exclusion: term in docs/spec exits 0"` のテスト名を `"detection: term in docs/spec exits 1"` に変更し `[ "$status" -eq 1 ]` に更新
   - `check-forbidden-expressions.bats`: 既存 `@test "detection: Issue Spec exact match exits 1"` の後に 3 件追加:
     ```bash
     @test "detection: verify hint exits 1" {
       echo "use verify hint here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }

     @test "detection: verify ヒント exits 1" {
       echo "use verify ヒント here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }

     @test "detection: 検証ヒント exits 1" {
       echo "use 検証ヒント here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }
     ```

## Verification

### Pre-merge

- <!-- verify: file_contains "CLAUDE.md" "verify command" --> `CLAUDE.md` に用語統一ルールが追加されている
- <!-- verify: grep "verify hint" "CLAUDE.md" --> `CLAUDE.md` に `verify hint` の deprecation が明示されている
- <!-- verify: grep "verification hint" "CLAUDE.md" --> `CLAUDE.md` に `verification hint` の deprecation が明示されている
- <!-- verify: grep "verify ヒント" "CLAUDE.md" --> `CLAUDE.md` に `verify ヒント` の deprecation が明示されている
- <!-- verify: grep "検証ヒント" "CLAUDE.md" --> `CLAUDE.md` に `検証ヒント` の deprecation が明示されている
- <!-- verify: grep "\"verify hint\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` の `DEPRECATED_TERMS` に短形 `"verify hint"` が追加されている
- <!-- verify: grep "\"verify ヒント\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` に `"verify ヒント"` が追加されている
- <!-- verify: grep "\"検証ヒント\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` に `"検証ヒント"` が追加されている
- <!-- verify: file_not_contains "scripts/check-forbidden-expressions.sh" "grep -v 'docs/spec/'" --> `scripts/check-forbidden-expressions.sh` から `docs/spec/` 除外が削除されている
- <!-- verify: rubric "docs/product.md § Terms の verify command 行 'Formerly called' 列に 4 variants (verification hint, verify hint, verify ヒント, 検証ヒント) + Acceptance check が explicit に列挙されている" --> product.md Terms 列に 4 旧称 variants が列挙されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "verify ヒント" --> `docs/product.md § Terms` に `verify ヒント` が記載されている (SSoT として)
- <!-- verify: section_contains "docs/ja/product.md" "## 用語" "verify ヒント" --> `docs/ja/product.md § 用語` にも同期されている
- <!-- verify: github_check "gh pr checks" "check-forbidden-expressions" --> CI `check-forbidden-expressions` job が PASS (docs/spec 除外削除後でも通過)

### Post-merge

- `/verify` を実際に実行して retro Issue が起票されるシナリオを再現し、新規 Issue title / body に 4 旧称 variants が含まれないことを opportunistic 確認 <!-- verify-type: opportunistic -->
- `#371` の title / body が `gh issue edit` で更新され、deprecated 語が除去されていることを手動確認 <!-- verify-type: manual -->

## Notes

- **bats 自己参照除外**: 新規追加テストに `verify hint` 等の fixture 文字列が含まれるが、`check_term` 関数内の `grep -v 'tests/check-forbidden-expressions.bats'` 除外 (据え置き) により CI 誤検知は発生しない
- **CLAUDE.md は SCAN_DIRS 対象外**: `check-forbidden-expressions.sh` の `SCAN_DIRS="skills/ modules/ agents/ tests/ docs/"` に root の `CLAUDE.md` は含まれないため、deprecated 語を deprecation 説明として記載しても CI に影響しない
- **docs/ja/product.md の heading 修正**: Issue body の acceptance criteria item 12 は `section_contains "docs/ja/product.md" "## Terms"` と記載されているが、日本語ファイルの実際の見出しは `## 用語`。`section_contains` は partial match のため "Terms" では `## 用語` にマッチしない (UNCERTAIN になる)。Spec では `"## 用語"` に修正し、Issue body も同期更新した
- **docs/spec/ 置換後 CI 一貫性**: Step 1 (docs/spec/ cleanup) を Step 5 (docs/spec/ 除外削除) より先に実施することで、ローカル CI 実行時も段階的に通過可能
- **大文字変体**: "Verify Hint" (title case) が docs/spec/ に 1 件存在 (`issue-35-add-triage-auto-chain.md:15`); `[Vv]erify hint` パターンで捕捉され `verify command` に置換される
