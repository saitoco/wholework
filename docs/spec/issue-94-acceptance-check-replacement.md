# Issue #94: L2 用途の verify command を verify command に置換

## Overview

Issue #84 で verify command への用語統一を実施したが、Scope Declaration により「verify command」の広範な置換は後続に委ねられた。本 Issue では、コードベース全体で L2 用途（`<!-- verify: ... -->` 構造を指す用法）の "verify command" / "verify command" / "受入チェック" を "verify command" に置換し、用語統一を完了する。合わせて "verify command" を Forbidden Expressions に追加する。

残存状況（`grep -ri` による計測、docs/spec/ を除く全 .md/.bats ファイル）:
- 英語 "verify command": 20 ファイル・70 箇所
- 日本語 "受入チェック": 5 ファイル・8 箇所
- 除外: docs/product.md, docs/ja/product.md（"Formerly called" / "旧称" 参照として保持）

## Changed Files

### modules/ (4 files, 17 occurrences)
- `modules/verify-patterns.md`: "verify command(s)" → "verify command(s)" (8 箇所、見出し含む)
- `modules/verify-executor.md`: "verify command(s)" → "verify command(s)" (6 箇所、見出し含む)
- `modules/skill-dev-checks.md`: "verify command(s)" → "verify command(s)" (2 箇所)
- `modules/verify-classifier.md`: "verify command" → "verify command" (1 箇所)

### skills/ (8 files, 38 occurrences)
- `skills/verify/SKILL.md`: "verify command(s)" → "verify command(s)" (10 箇所、見出し・テーブル含む)
- `skills/code/SKILL.md`: "verify command(s)" → "verify command(s)" (6 箇所、見出し含む)
- `skills/review/SKILL.md`: "verify command(s)" → "verify command(s)" (6 箇所、見出し含む)
- `skills/issue/SKILL.md`: "verify command(s)" → "verify command(s)" (5 箇所、見出し含む)
- `skills/spec/SKILL.md`: "verify command(s)" → "verify command(s)" (4 箇所)
- `skills/issue/spec-test-guidelines.md`: "verify command(s)" → "verify command(s)" (4 箇所)
- `skills/audit/SKILL.md`: "verify command(s)" → "verify command(s)" (2 箇所)
- `skills/doc/translate-phase.md`: "verify command" → "verify command" (1 箇所)

### agents/ (1 file, 6 occurrences)
- `agents/risk-agent.md`: "verify command(s)" → "verify command(s)" (6 箇所、フロントマター description 含む)

### docs/ English (4 files, 6 occurrences)
- `docs/tech.md`: "verify command(s)" → "verify command(s)" (2 箇所) + Forbidden Expressions に "verify command" 行を追加
- `docs/environment-adaptation.md`: "verify command" → "verify command" (1 箇所)
- `docs/workflow.md`: "verify command" → "verify command" (1 箇所)
- `docs/structure.md`: "verify command(s)" → "verify command(s)" (2 箇所)

### docs/ja/ (5 files, 8 occurrences)
- `docs/ja/tech.md`: "受入チェック" → "verify command" (2 箇所) + Forbidden Expressions に "verify command" 行を追加
- `docs/ja/environment-adaptation.md`: "受入チェック" → "verify command" (2 箇所)
- `docs/ja/workflow.md`: "受入チェック" → "verify command" (1 箇所)
- `docs/ja/structure.md`: "受入チェック" → "verify command" (2 箇所)
- `docs/ja/product.md`: 除外（"旧称" 参照として保持）

### tests/ (1 file, 1 occurrence)
- `tests/spec-verification-hints.bats`: "verify command" → "verify command" (1 箇所、コメント)

### 除外
- `docs/product.md`: "Formerly called 'verify command / verify command'" — 歴史的参照として保持
- `docs/ja/product.md`: "旧称「verify command / verify command / 受入チェック」" — 同上

## Implementation Steps

1. **modules/ の置換** (4 files) (→ acceptance criteria A-1〜A-4)
   - 各ファイルで "verify command(s)" → "verify command(s)" を case-insensitive で置換
   - 見出しは Title Case を維持（"Verify Commands" → "Verify Commands"）
   - 単数形/複数形を保持（"verify command" → "verify command", "verify commands" → "verify commands"）

2. **skills/ の置換** (8 files) (after 1) (→ acceptance criteria A-5〜A-7)
   - 同じ置換ルール
   - 見出しの置換例: "### Step 4: Classify Acceptance Criteria and Assign Verify Commands" → "### Step 4: Classify Acceptance Criteria and Assign Verify Commands"
   - "### Step 10: Verify command Consistency" → "### Step 10: Verify Command Consistency"

3. **agents/ の置換** (1 file) (parallel with 1, 2) (→ acceptance criteria A-8)
   - フロントマター description 内も置換: "verify command effects" → "verify command effects"

4. **docs/ English の置換 + Forbidden Expressions 追加** (4 files) (parallel with 1, 2, 3) (→ acceptance criteria B-1, C-1, C-2)
   - docs/tech.md Testing Tools テーブル: "**verify commands**" → "**Verify commands**", "via `command` verify command" → "via `command` verify command"
   - docs/tech.md Forbidden Expressions に行追加: `| verify command | Term redesign (changed to "verify command") | "verify command" |`

5. **docs/ja/ の置換 + Forbidden Expressions 追加** (5 files) (parallel with 1, 2, 3, 4) (→ acceptance criteria B-2, C-3, C-4)
   - "受入チェック" → "verify command" (カタカナ化しない)
   - docs/ja/tech.md Forbidden Expressions に行追加: `| verify command | 用語再設計 (changed to "verify command") | "verify command" |`

6. **tests/ の置換** (1 file) (parallel with 1〜5) (→ acceptance criteria A-9)
   - コメント行のみ: `# Tests for verify command generation logic` → `# Tests for verify command generation logic`

7. **テスト実行** (after 1〜6) (→ acceptance criteria D-1, D-2)
   - `python3 scripts/validate-skill-syntax.py skills/` — 全 SKILL.md PASS 確認
   - `bats tests/` — 全テスト PASS 確認

## Verification

### Pre-merge

#### 主要ファイルの置換完了

- <!-- verify: file_not_contains "modules/verify-patterns.md" "verify command" --> `modules/verify-patterns.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "modules/verify-executor.md" "verify command" --> `modules/verify-executor.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "verify command" --> `skills/verify/SKILL.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "skills/code/SKILL.md" "verify command" --> `skills/code/SKILL.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "skills/review/SKILL.md" "verify command" --> `skills/review/SKILL.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "verify command" --> `skills/issue/SKILL.md` から "verify command" が除去されている
- <!-- verify: file_not_contains "agents/risk-agent.md" "verify command" --> `agents/risk-agent.md` から "verify command" が除去されている

#### 広範チェック

- <!-- verify: command "test $(grep -ri 'verify command' skills/ modules/ agents/ tests/ docs/environment-adaptation.md docs/workflow.md docs/structure.md docs/tech.md skills/doc/ skills/audit/ skills/spec/ skills/issue/spec-test-guidelines.md 2>/dev/null | grep -v 'Formerly called' | grep -v '| verify command |' | wc -l) -eq 0" --> skills/、modules/、agents/、tests/、対象 docs/ から L2 用途の "verify command" が全て除去されている
- <!-- verify: command "test $(grep -r '受入チェック' docs/ja/ 2>/dev/null | grep -v '旧称' | wc -l) -eq 0" --> `docs/ja/` から L2 用途の "受入チェック" が全て除去されている

#### Forbidden Expressions 更新

- <!-- verify: section_contains "docs/tech.md" "## Forbidden Expressions" "verify command" --> `docs/tech.md` Forbidden Expressions に "verify command" が追加されている
- <!-- verify: section_contains "docs/ja/tech.md" "## Forbidden Expressions" "verify command" --> `docs/ja/tech.md` Forbidden Expressions に "verify command" が追加されている

#### テスト整合性

- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> `validate-skill-syntax.py` で全 SKILL.md が PASS する
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge

(なし)

## Notes

- **置換ルール**: case-insensitive で "verify command(s)" → "verify command(s)"。単数/複数を保持。見出しは Title Case を維持
- **除外対象**: docs/spec/ 配下（使い捨て Spec）、docs/product.md と docs/ja/product.md の "Formerly called" / "旧称" 参照
- **#84 との関係**: #84 が "verify command" → "verify command" を実施済み。本 Issue は残りの "verify command" → "verify command" を完了する
- **#98 との関係**: #98 が本 Issue 完了後に Forbidden Expressions の用語エントリを Terms に統合する（本 Issue で追加した "verify command" エントリも含む）
- **自動解決した曖昧性**: 見出しの Title Case 維持、フロントマター内の置換、テーブル行頭の大文字維持（全て英語の慣例に従う）

## Issue Retrospective

### 曖昧性解消の判断根拠

- **全出現箇所が L2 用途**: コードベース調査の結果、"verify command" の全出現箇所（22 ファイル・70+ 箇所）が L2（`<!-- verify: ... -->` 構造）を指していた。L1（受入条件一般）を指す "verify command" は存在しない。従って L1/L2 判別の実作業は不要で、機械的全置換が可能
- **Forbidden Expressions 追加**: #84 では "verify command" のみ Forbidden Expressions に追加済み。"verify command" も同様に追加して旧用語の再混入を防止する
- **日本語 "受入チェック"**: docs/ja/ の 3 ファイルで使用。Terms SSOT に従い "verify command" に統一（カタカナ化しない方針は #84 の議論で確定済み）

### Q&A からのポリシー決定

- Size L の判定: 22 ファイルで 11+ の L 基準を満たすが、機械的置換で複雑度は低い。XL 分割は不要

### 受入条件の変更理由

- 元の Issue body には受入条件がなかったため、全面的に追加
- 主要ファイル 7 件の個別 `file_not_contains` チェック + 広範 `command` チェック（grep ベース）の 2 層構成で漏れを防止
- Forbidden Expressions 更新を受入条件に追加（元の Scope には含まれていなかった）

## Spec Retrospective

### Minor observations
- 機械的置換タスクのため Spec の付加価値は低い。Changed Files の正確な列挙と置換ルールの明文化が主な成果物
- Issue body の残存数 "33 ファイル・116 箇所" と Spec 調査時の "20 ファイル・70 箇所" に差異がある。これは Issue 作成時点では case-insensitive で "acceptance criteria" も含めてカウントしていたため。Spec では L2 用途の "verify command" のみを正確にカウントした

### Judgment rationale
- Nothing to note

### Uncertainty resolution
- Nothing to note

## Code Retrospective

### Deviations from Design

- Python スクリプトで一括置換を実装（Spec は Edit ツール逐次置換を想定していたが、22 ファイルへの効率的適用のためスクリプト化）
- 置換パターンの追加: "verify command" (capital A, lowercase c) のパターンが初回スクリプトで未対応。2 パス処理で対応（`verify-executor.md`, `spec/SKILL.md`, `issue/SKILL.md`, `risk-agent.md`, `docs/tech.md` の 5 ファイルが対象）

### Design Gaps/Ambiguities

- Forbidden Expressions テーブルエントリが広範 grep チェック (#8) に引っかかる問題: `docs/tech.md` の Forbidden Expressions 行に "verify command" が含まれるため、追加後は自身がチェックに引っかかる。`grep -v '| verify command |'` 除外パターンを追加して対処。Spec および Issue body の verify command hint を修正

### Rework

- 広範 grep コマンド hint の修正: 初回コミット後に Step 10 で FAIL が判明。verify command hint に除外パターン追加が必要だった（`| verify command |` 行の除外）。Spec と Issue body 両方を修正してリコミット

## review retrospective

### Spec vs. implementation divergence patterns

機械的置換タスク特有のパターンで、Spec の置換ルール（「単数/複数を保持」）が想定していなかった変換アーティファクトが複数発生した：

1. **冠詞の不整合**: "An verify command" → "An verify command"（"An" のまま残存）。Spec のルールは単数/複数形の保持のみで、冠詞変化（An → A）を対象外としていた
2. **複合名詞の冗長**: "verify command commands" → "verify command commands"。"verify command" 自体が "command" を含む複合名詞のため、複数形 "commands" との組み合わせで "command commands" という重複が生じた
3. **日本語テキストとのスペース**: "受入チェック" は日本語文字列として直接隣接可能だが、"verify command"（英語）に置換後は前後の日本語文字との間にスペースが必要

将来の用語置換 Issue では、Spec に「元の用語が母音始まり/子音始まりかを確認し冠詞を調整する」「置換後の用語が compound noun の場合は複数形との組み合わせを確認する」「日本語ドキュメントでの英語挿入後はスペース規則を確認する」の3点を明示的に追加すべき。

### Recurring issues

7 ファイル・9 箇所の修正が全て同一の根本原因（機械的置換の後処理不足）から発生した。これは単発ではなく構造的な見落とし。類似の用語置換タスクでは、置換後のスキャン（"An [子音始まり]"、"[term] [term]-related", 日本語境界スペース）をチェックリストに含めることで再発防止できる。

### Acceptance criteria verification difficulty

2 件の UNCERTAIN（広範 grep command チェック）が発生した。`command` hint の grep は CI でカバーされておらず、safe モードでは UNCERTAIN になる。改善案：
- `command "test ... -eq 0"` 形式ではなく、主要ファイルを個別に `file_not_contains` に分解すると safe モードで PASS/FAIL を確定できる
- または広範チェック用の CI ジョブを追加してCIフォールバックを有効化する

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件の設計は全体として適切だった。主要ファイル7件の個別 `file_not_contains` + 広範 `command` チェックの2層構成は有効
- Issue body に受入条件がなかったため Spec 側で全面追加したが、Issue の本来の要件として最初から含めておくべきだった
- Forbidden Expressions テーブルエントリが広範 grep チェックに引っかかる問題は、受入条件設計時に予見できた可能性がある。`| verify command |` 除外パターンの必要性を先読みして hint に含めておくと rework を防げた

#### design
- 設計内容自体は実装と大きく乖離しなかった（Python スクリプト化は手段の変更だが目的は同じ）
- Changed Files の正確な列挙が実装の指針となり有効だった

#### code
- 主な rework 要因は「verify command」(capital A) の2パス処理必要性と、Forbidden Expressions 追加後の grep 自己参照問題。いずれも受入条件設計またはスクリプト設計段階で対策可能だった
- 将来の用語置換タスクでは、置換後スキャン（冠詞変化、複合名詞、日本語境界スペース）をスクリプトのpost-checkとして組み込む価値がある

#### review
- 7ファイル・9箇所の後処理不足が同一根本原因から発生したことをレビューが検出し、パターン化された指摘につながった。有効なレビューだった
- `/verify` では全13条件がPASSし、レビュー指摘された問題がすべて修正済みであることを確認できた

#### merge
- PR #103 でのスカッシュマージは問題なく完了。コンフリクトなし
- bats 266テスト全通過により、マージ品質は確保されていた

#### verify
- 全13条件がPASS（再実行でも一致）。受入条件の設計が適切で自動検証が完全に機能した
- 広範 grep コマンドの除外パターン（`| verify command |`）が正しく機能し、Forbidden Expressions 追加後も誤検知なし
- `/review` での2件の UNCERTAIN（broad command が safe モードで実行不可）は `/verify` の full モードで解消された。このパターンは設計通り

### Improvement Proposals
- 用語置換 Issue の受入条件設計として、除外対象（Forbidden Expressions テーブル行、歴史的参照等）を先読みして `grep -v` パターンを hint に含める慣例を Spec に追記することを検討する
- 広範 grep を `command "test $(grep ...) -eq 0"` 形式で書く場合、`/review`（safe モード）では UNCERTAIN になることが確認されたが、これは既知の設計上の制約であり許容範囲内
