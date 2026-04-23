# Issue #373: terminology: verify command 旧称 (verify command 他 3 形) の根絶とデータソース一掃

## Overview

deprecated語 (`verify command` / `verify command` / `verify command` / `verify command`) が再発し続けている根本原因は 4 層構造:

1. CI `DEPRECATED_TERMS` に短形 `"verify command"` と日本語形 2 件が未登録
2. `docs/product.md § Terms` Formerly called 列に 1 variant しか収録されていない
3. `scripts/check-forbidden-expressions.sh` が `docs/spec/` を除外しており新規 Spec への混入を検知できない
4. CLAUDE.md に用語統一ルールがなく sub-agent が deprecated 語を再生産し続ける

データソース一掃 (docs/spec/ 37 ファイル, 102 行) + CLAUDE.md 指示 + CI 配列拡張 + docs/spec/ 除外削除の 3 軸同時対応で再発を断つ。

## Changed Files

- `CLAUDE.md`: `## 用語` セクション追加 — deprecated 4 variants を明示
- `docs/product.md`: verify command 行の Formerly called を 5 旧称 variants 列挙に更新
- `docs/ja/product.md`: 同行の `旧称:` を同内容で同期
- `scripts/check-forbidden-expressions.sh`: DEPRECATED_TERMS に `"verify command"` / `"verify command"` / `"verify command"` 3 件追加; `check_term` 内の `grep -v 'docs/spec/'` 1 行削除 (bash 3.2+ 互換)
- `tests/check-forbidden-expressions.bats`: 新検出テスト 3 件追加; `@test "exclusion: term in docs/spec exits 0"` → `@test "detection: term in docs/spec exits 1"` に変更
- `docs/spec/` (37 ファイル, 102 行): deprecated 4 variants を `sed` 一括置換
  - 計測スコープ: `grep -rni "verify command\|verify command\|verify command\|verify command" docs/spec/` (全 .md ファイル, `docs/spec/` のみ)

## Implementation Steps

1. `docs/spec/` 一括置換 — `find docs/spec/ -name "*.md"` に対して `sed -i ''` で下記 6 パターンを順に置換。複数形を先に処理すること (→ AC 13):
   - `[Vv]erification hints` → `verify commands`
   - `[Vv]erification hint` → `verify command`
   - `[Vv]erify hints` → `verify commands`
   - `[Vv]erify hint` → `verify command`
   - `verify command` → `verify command`
   - `verify command` → `verify command`

2. `docs/product.md` の verify command 行 (line 167) を更新 (→ AC 10, 11): Formerly called 部分を以下に置換:
   - 旧: `Formerly called "verify command / verify command"`
   - 新: `Formerly called: 'verify command', 'verify command', 'verify command', 'verify command', 'verify command'`

3. `docs/ja/product.md` の verify command 行 (line 157) を同期 (→ AC 12): `旧称:` 部分を更新:
   - 旧: `旧称: "verify command / verify command"`
   - 新: `旧称: 'verify command', 'verify command', 'verify command', 'verify command', 'verify command'`

4. `CLAUDE.md` の `## Notes` の前に `## 用語` セクションを追加 (→ AC 1–5):
   ```markdown
   ## 用語

   - `verify command` / `verify command` / `verify command` / `verify command` は deprecated。常に `verify command` を使用する (SSoT: `docs/product.md § Terms`)。
   ```

5. `scripts/check-forbidden-expressions.sh` と `tests/check-forbidden-expressions.bats` を同時更新 (→ AC 6–9, 13):
   - `check-forbidden-expressions.sh`: `DEPRECATED_TERMS` の `"Shared module"` の後に以下 3 件を追加:
     ```bash
       "verify command"
       "verify command"
       "verify command"
     ```
   - `check-forbidden-expressions.sh`: `check_term` 関数内の `| grep -v 'docs/spec/' \` 1 行を削除 (他の除外行 `Formerly called`, `旧称`, `tests/check-forbidden-expressions.bats` は据え置き)
   - `check-forbidden-expressions.bats`: `@test "exclusion: term in docs/spec exits 0"` のテスト名を `"detection: term in docs/spec exits 1"` に変更し `[ "$status" -eq 1 ]` に更新
   - `check-forbidden-expressions.bats`: 既存 `@test "detection: Spec exact match exits 1"` の後に 3 件追加:
     ```bash
     @test "detection: verify command exits 1" {
       echo "use verify command here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }

     @test "detection: verify command exits 1" {
       echo "use verify command here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }

     @test "detection: verify command exits 1" {
       echo "use verify command here" > skills/bad.md
       run bash "$SCRIPT"
       [ "$status" -eq 1 ]
     }
     ```

## Verification

### Pre-merge

- <!-- verify: file_contains "CLAUDE.md" "verify command" --> `CLAUDE.md` に用語統一ルールが追加されている
- <!-- verify: grep "verify command" "CLAUDE.md" --> `CLAUDE.md` に `verify command` の deprecation が明示されている
- <!-- verify: grep "verify command" "CLAUDE.md" --> `CLAUDE.md` に `verify command` の deprecation が明示されている
- <!-- verify: grep "verify command" "CLAUDE.md" --> `CLAUDE.md` に `verify command` の deprecation が明示されている
- <!-- verify: grep "verify command" "CLAUDE.md" --> `CLAUDE.md` に `verify command` の deprecation が明示されている
- <!-- verify: grep "\"verify command\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` の `DEPRECATED_TERMS` に短形 `"verify command"` が追加されている
- <!-- verify: grep "\"verify command\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` に `"verify command"` が追加されている
- <!-- verify: grep "\"verify command\"" "scripts/check-forbidden-expressions.sh" --> `scripts/check-forbidden-expressions.sh` に `"verify command"` が追加されている
- <!-- verify: file_not_contains "scripts/check-forbidden-expressions.sh" "grep -v 'docs/spec/'" --> `scripts/check-forbidden-expressions.sh` から `docs/spec/` 除外が削除されている
- <!-- verify: rubric "docs/product.md § Terms の verify command 行 'Formerly called' 列に 4 variants (verify command, verify command, verify command, verify command) + verify command が explicit に列挙されている" --> product.md Terms 列に 4 旧称 variants が列挙されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "verify command" --> `docs/product.md § Terms` に `verify command` が記載されている (SSoT として)
- <!-- verify: section_contains "docs/ja/product.md" "## 用語" "verify command" --> `docs/ja/product.md § 用語` にも同期されている
- <!-- verify: github_check "gh pr checks" "check-forbidden-expressions" --> CI `check-forbidden-expressions` job が PASS (docs/spec 除外削除後でも通過)

### Post-merge

- `/verify` を実際に実行して retro Issue が起票されるシナリオを再現し、新規 Issue title / body に 4 旧称 variants が含まれないことを opportunistic 確認 <!-- verify-type: opportunistic -->
- `#371` の title / body が `gh issue edit` で更新され、deprecated 語が除去されていることを手動確認 <!-- verify-type: manual -->

## Notes

- **bats 自己参照除外**: 新規追加テストに `verify command` 等の fixture 文字列が含まれるが、`check_term` 関数内の `grep -v 'tests/check-forbidden-expressions.bats'` 除外 (据え置き) により CI 誤検知は発生しない
- **CLAUDE.md は SCAN_DIRS 対象外**: `check-forbidden-expressions.sh` の `SCAN_DIRS="skills/ modules/ agents/ tests/ docs/"` に root の `CLAUDE.md` は含まれないため、deprecated 語を deprecation 説明として記載しても CI に影響しない
- **docs/ja/product.md の heading 修正**: Issue body の acceptance criteria item 12 は `section_contains "docs/ja/product.md" "## Terms"` と記載されているが、日本語ファイルの実際の見出しは `## 用語`。`section_contains` は partial match のため "Terms" では `## 用語` にマッチしない (UNCERTAIN になる)。Spec では `"## 用語"` に修正し、Issue body も同期更新した
- **docs/spec/ 置換後 CI 一貫性**: Step 1 (docs/spec/ cleanup) を Step 5 (docs/spec/ 除外削除) より先に実施することで、ローカル CI 実行時も段階的に通過可能
- **大文字変体**: title case 変体 (e.g., `issue-35-add-triage-auto-chain.md:15`) も sed で `verify command` に置換済み。

## Code Retrospective

### Deviations from Design

- **Spec Step 1 スコープ拡張**: Spec の実装ステップは verify-related 4 変体の `docs/spec/` 置換のみを記述していたが、`grep -v 'docs/spec/'` 除外削除 (Step 5) によりその他の deprecated 語（5 種類）が CI に引っかかることが判明。Spec に記載のない範囲まで `docs/spec/` 全 deprecated 語を一括置換してスコープを拡張した。Issue body の「全置換対象」原則に準拠した判断。
- **bats テスト名の ASCII 化**: Spec が `@test "detection: verify katakana hint exits 1"` 等の日本語テスト名を記述していたが、コードの注記「bats test @test names must be in English (ASCII)」に従い ASCII 名 (`verify katakana hint`, `kensho hint`) に変更した。

### Design Gaps/Ambiguities

- **docs/spec/ 除外削除と他 deprecated 語の相互作用**: Spec は verify-related 4 変体の置換後に `grep -v 'docs/spec/'` を削除すれば CI が通過すると想定していたが、他の deprecated 語が docs/spec/ に残存していることが考慮されていなかった。実装時に発見し auto-resolve で対処。
- **macOS sed の `\b` 非対応**: `sed -i '' 's/\b<deprecated_term>\b/.../g'` が macOS (BSD sed) では機能しないため Python の `re.sub` に切り替えた。

### Rework

- docs/spec/ の deprecated 語置換を 2 段階で実施 (verify-related → 残余全語)。Spec が段階的置換を想定していなかったため追加イテレーションが発生した。

## review retrospective

### Spec vs. 実装乖離パターン

Spec の Code Retrospective セクション自身が、置換対象の deprecated 語をそのまま引用していたため CI が FAIL した。Spec を retrospective の記録先として使う際に「Spec ファイル自身が docs/spec/ CI スキャン対象になる」という再帰的問題が発生。根本原因: `docs/spec/` 除外削除後の CI スキャン範囲拡大が、Spec ファイルを書く sub-agent 自身のコンテキストに反映されていなかった。再発防止: Spec の retrospective 記述ガイドとして「deprecated 語を引用する場合は具体的な語を直接書かず説明的記述（例: deprecated 語 N 種類）を使うか、`旧称:` 接頭辞を付けて CI 例外フィルタを活用する」を周知することが有効。

### 繰り返し Issue

なし。本レビューでの MUST issue は 1 件のみ（CI failure）で、単一の根本原因。

### 受け入れ基準検証難易度

12/13 条件が PASS。残り 1 件（CI）は実際の CI failure として明確。UNCERTAIN は 0 件で verify command の質は良好。rubric 検証条件も正確で問題なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue retrospective セクションが Spec に存在しないため issue フェーズの振り返りは不明
- 受入条件は全13件のうち12件が事前チェック済み（[x]）で品質は高い
- 条件10（rubric）と条件13（CI）が未チェックで残っていたが、いずれも実装後に検証が必要なもの（CI は実行が必要、rubric は product.md 確認が必要）であり、適切な設計

#### design
- Spec 自身が実装対象の deprecated 語をそのまま引用したため、docs/spec/ 除外削除後に CI が FAIL する再帰的問題が発生（Code Retrospective に記録）
- macOS sed の `\b` 非対応という実装環境依存の問題が Spec に記載なく、コード実装時に発見

#### code
- 実装コミットは1件（merge commit）にまとまっており、fixup/amend パターンは確認されない
- Spec のスコープ外（verify-related 以外の deprecated 語）の置換が必要となり、実装時にスコープを拡張
- 2段階置換が必要だったことは設計ギャップだったが、auto-resolve で適切に対処

#### review
- CI failure（Spec ファイルの deprecated 語引用）が唯一の MUST issue として適切に検出された
- UNCERTAIN 0件、PASS 12/13 という高品質な verify command 設計により review の負担が軽減
- Spec retrospective セクション自身が CI スキャン対象になる再帰的問題は review が指摘済み

#### merge
- merge commit `8534977` は squash merge で1件にまとまっており、コンフリクトなし
- マージ後の `git pull` タイミングで変更が反映（/verify 開始時点では未取得だったが、Step 2 の git pull で解決）

#### verify
- 13条件すべてが PASS（うち2件は今回 /verify で確認）
- CI job 名の表示名（"Forbidden Expressions check"）と job ID（"check-forbidden-expressions"）の不一致により、verify command の expected string が出力に含まれないが、ワークフロー YAML でのマッピング確認により PASS と判断
- Post-merge の opportunistic/manual 条件（#371 修正確認）はユーザー確認が必要

### Improvement Proposals
- verify command `github_check "gh pr checks" "check-forbidden-expressions"` は CI job の display name "Forbidden Expressions check" と literal 不一致になる。`github_check` は job ID でも一致できるよう、またはワークフロー YAML と display name 両方を探索する改善を検討
- Spec retrospective セクションで deprecated 語を「引用」する際に CI スキャンに引っかかる再帰的問題の対策として、Spec 記述ガイドに「deprecated 語を直接引用せず説明的記述か `旧称:` 接頭辞を使う」旨を追記することを検討
