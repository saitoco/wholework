# Issue #94: L2 用途の Acceptance check を verify command に置換

## Overview

Issue #84 で verify command への用語統一を実施したが、Scope Declaration により「Acceptance check」の広範な置換は後続に委ねられた。本 Issue では、コードベース全体で L2 用途（`<!-- verify: ... -->` 構造を指す用法）の "acceptance check" / "Acceptance check" / "受入チェック" を "verify command" に置換し、用語統一を完了する。合わせて "Acceptance check" を Forbidden Expressions に追加する。

残存状況（`grep -ri` による計測、docs/spec/ を除く全 .md/.bats ファイル）:
- 英語 "acceptance check": 20 ファイル・70 箇所
- 日本語 "受入チェック": 5 ファイル・8 箇所
- 除外: docs/product.md, docs/ja/product.md（"Formerly called" / "旧称" 参照として保持）

## Changed Files

### modules/ (4 files, 17 occurrences)
- `modules/verify-patterns.md`: "acceptance check(s)" → "verify command(s)" (8 箇所、見出し含む)
- `modules/verify-executor.md`: "acceptance check(s)" → "verify command(s)" (6 箇所、見出し含む)
- `modules/skill-dev-checks.md`: "acceptance check(s)" → "verify command(s)" (2 箇所)
- `modules/verify-classifier.md`: "acceptance check" → "verify command" (1 箇所)

### skills/ (8 files, 38 occurrences)
- `skills/verify/SKILL.md`: "acceptance check(s)" → "verify command(s)" (10 箇所、見出し・テーブル含む)
- `skills/code/SKILL.md`: "acceptance check(s)" → "verify command(s)" (6 箇所、見出し含む)
- `skills/review/SKILL.md`: "acceptance check(s)" → "verify command(s)" (6 箇所、見出し含む)
- `skills/issue/SKILL.md`: "acceptance check(s)" → "verify command(s)" (5 箇所、見出し含む)
- `skills/spec/SKILL.md`: "acceptance check(s)" → "verify command(s)" (4 箇所)
- `skills/issue/spec-test-guidelines.md`: "acceptance check(s)" → "verify command(s)" (4 箇所)
- `skills/audit/SKILL.md`: "acceptance check(s)" → "verify command(s)" (2 箇所)
- `skills/doc/translate-phase.md`: "acceptance check" → "verify command" (1 箇所)

### agents/ (1 file, 6 occurrences)
- `agents/risk-agent.md`: "acceptance check(s)" → "verify command(s)" (6 箇所、フロントマター description 含む)

### docs/ English (4 files, 6 occurrences)
- `docs/tech.md`: "acceptance check(s)" → "verify command(s)" (2 箇所) + Forbidden Expressions に "Acceptance check" 行を追加
- `docs/environment-adaptation.md`: "acceptance check" → "verify command" (1 箇所)
- `docs/workflow.md`: "acceptance check" → "verify command" (1 箇所)
- `docs/structure.md`: "acceptance check(s)" → "verify command(s)" (2 箇所)

### docs/ja/ (5 files, 8 occurrences)
- `docs/ja/tech.md`: "受入チェック" → "verify command" (2 箇所) + Forbidden Expressions に "Acceptance check" 行を追加
- `docs/ja/environment-adaptation.md`: "受入チェック" → "verify command" (2 箇所)
- `docs/ja/workflow.md`: "受入チェック" → "verify command" (1 箇所)
- `docs/ja/structure.md`: "受入チェック" → "verify command" (2 箇所)
- `docs/ja/product.md`: 除外（"旧称" 参照として保持）

### tests/ (1 file, 1 occurrence)
- `tests/spec-verification-hints.bats`: "acceptance check" → "verify command" (1 箇所、コメント)

### 除外
- `docs/product.md`: "Formerly called 'verification hint / Acceptance check'" — 歴史的参照として保持
- `docs/ja/product.md`: "旧称「verification hint / Acceptance check / 受入チェック」" — 同上

## Implementation Steps

1. **modules/ の置換** (4 files) (→ acceptance criteria A-1〜A-4)
   - 各ファイルで "acceptance check(s)" → "verify command(s)" を case-insensitive で置換
   - 見出しは Title Case を維持（"Acceptance Checks" → "Verify Commands"）
   - 単数形/複数形を保持（"acceptance check" → "verify command", "acceptance checks" → "verify commands"）

2. **skills/ の置換** (8 files) (after 1) (→ acceptance criteria A-5〜A-7)
   - 同じ置換ルール
   - 見出しの置換例: "### Step 4: Classify Acceptance Criteria and Assign Acceptance Checks" → "### Step 4: Classify Acceptance Criteria and Assign Verify Commands"
   - "### Step 10: Acceptance Check Consistency" → "### Step 10: Verify Command Consistency"

3. **agents/ の置換** (1 file) (parallel with 1, 2) (→ acceptance criteria A-8)
   - フロントマター description 内も置換: "acceptance check effects" → "verify command effects"

4. **docs/ English の置換 + Forbidden Expressions 追加** (4 files) (parallel with 1, 2, 3) (→ acceptance criteria B-1, C-1, C-2)
   - docs/tech.md Testing Tools テーブル: "**Acceptance checks**" → "**Verify commands**", "via `command` acceptance check" → "via `command` verify command"
   - docs/tech.md Forbidden Expressions に行追加: `| Acceptance check | Term redesign (changed to "verify command") | "verify command" |`

5. **docs/ja/ の置換 + Forbidden Expressions 追加** (5 files) (parallel with 1, 2, 3, 4) (→ acceptance criteria B-2, C-3, C-4)
   - "受入チェック" → "verify command" (カタカナ化しない)
   - docs/ja/tech.md Forbidden Expressions に行追加: `| Acceptance check | 用語再設計 (changed to "verify command") | "verify command" |`

6. **tests/ の置換** (1 file) (parallel with 1〜5) (→ acceptance criteria A-9)
   - コメント行のみ: `# Tests for acceptance check generation logic` → `# Tests for verify command generation logic`

7. **テスト実行** (after 1〜6) (→ acceptance criteria D-1, D-2)
   - `python3 scripts/validate-skill-syntax.py skills/` — 全 SKILL.md PASS 確認
   - `bats tests/` — 全テスト PASS 確認

## Verification

### Pre-merge

#### 主要ファイルの置換完了

- <!-- verify: file_not_contains "modules/verify-patterns.md" "acceptance check" --> `modules/verify-patterns.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "modules/verify-executor.md" "acceptance check" --> `modules/verify-executor.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "acceptance check" --> `skills/verify/SKILL.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "skills/code/SKILL.md" "acceptance check" --> `skills/code/SKILL.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "skills/review/SKILL.md" "acceptance check" --> `skills/review/SKILL.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "acceptance check" --> `skills/issue/SKILL.md` から "acceptance check" が除去されている
- <!-- verify: file_not_contains "agents/risk-agent.md" "acceptance check" --> `agents/risk-agent.md` から "acceptance check" が除去されている

#### 広範チェック

- <!-- verify: command "test $(grep -ri 'acceptance check' skills/ modules/ agents/ tests/ docs/environment-adaptation.md docs/workflow.md docs/structure.md docs/tech.md skills/doc/ skills/audit/ skills/spec/ skills/issue/spec-test-guidelines.md 2>/dev/null | grep -v 'Formerly called' | wc -l) -eq 0" --> skills/、modules/、agents/、tests/、対象 docs/ から L2 用途の "acceptance check" が全て除去されている
- <!-- verify: command "test $(grep -r '受入チェック' docs/ja/ 2>/dev/null | grep -v '旧称' | wc -l) -eq 0" --> `docs/ja/` から L2 用途の "受入チェック" が全て除去されている

#### Forbidden Expressions 更新

- <!-- verify: section_contains "docs/tech.md" "## Forbidden Expressions" "Acceptance check" --> `docs/tech.md` Forbidden Expressions に "Acceptance check" が追加されている
- <!-- verify: section_contains "docs/ja/tech.md" "## Forbidden Expressions" "Acceptance check" --> `docs/ja/tech.md` Forbidden Expressions に "Acceptance check" が追加されている

#### テスト整合性

- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> `validate-skill-syntax.py` で全 SKILL.md が PASS する
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge

(なし)

## Notes

- **置換ルール**: case-insensitive で "acceptance check(s)" → "verify command(s)"。単数/複数を保持。見出しは Title Case を維持
- **除外対象**: docs/spec/ 配下（使い捨て Spec）、docs/product.md と docs/ja/product.md の "Formerly called" / "旧称" 参照
- **#84 との関係**: #84 が "verify hint" → "verify command" を実施済み。本 Issue は残りの "acceptance check" → "verify command" を完了する
- **#98 との関係**: #98 が本 Issue 完了後に Forbidden Expressions の用語エントリを Terms に統合する（本 Issue で追加した "Acceptance check" エントリも含む）
- **自動解決した曖昧性**: 見出しの Title Case 維持、フロントマター内の置換、テーブル行頭の大文字維持（全て英語の慣例に従う）
