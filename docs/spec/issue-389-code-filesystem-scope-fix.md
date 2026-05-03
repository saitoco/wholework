# Issue #389: skills/code: filesystem-scope ガイダンスへの適合性レビューと修正

## Overview

`/code` skill が直接・間接的に参照するモジュール群に、`modules/filesystem-scope.md` の Approved Patterns に沿っていない Glob/Grep 呼び出し記述が残存している。本 Issue では対象 3 ファイルの記述を `path` 引数明示形式に統一し、広範囲スキャンの攻撃面を縮小する。変更はいずれも tool 呼び出し方式の表記変更のみで、取得される情報は結果同等。

## Changed Files

- `skills/code/SKILL.md`: Step 7 — "Use Glob" → "Use Glob with `path="$STEERING_DOCS_PATH"`" に修正
- `modules/codebase-analysis.md`: Steps 1/3/4/5 の Glob/Grep 記述に `path` 引数明示を追加
- `modules/doc-checker.md`: 入力定義（lines 15-16）とProcessing Steps（line 49-50）の Glob 記述を `path` 引数明示形式に統一
- `modules/filesystem-scope.md`: Implementation Reference に修正 3 ファイルの参照を追記

## Implementation Steps

1. `skills/code/SKILL.md` Step 7（line 172）を修正: `"Use Glob to check"` → `"Use Glob with \`path=\"$STEERING_DOCS_PATH\"\` to check"` に変更（→ AC1, AC2）
2. `modules/codebase-analysis.md` の各 Step を修正: Steps 1/3/4/5 の Glob/Grep 記述に `path` 設定を追加（→ AC3）
   - Step 1: `using Glob` → `using Glob with \`path\` set to the codebase directory`
   - Step 3: `using Grep` → `using Grep with \`path\` set to each source directory`
   - Step 4: `using Glob` → `using Glob with each directory as \`path\` argument`
   - Step 5: `using Grep` → `using Grep with \`path\` set to the entry point directory`
3. `modules/doc-checker.md` の Glob 記述 2 箇所を修正: `$STEERING_DOCS_PATH/*.md` with Glob → `*.md` with Glob (path: `$STEERING_DOCS_PATH`) に変更（→ AC4）
   - Input 節 lines 15-16（Steering / Project documents 定義）
   - Processing Steps 節 line 49（候補リスト作成）
4. `modules/filesystem-scope.md` Implementation Reference に 3 エントリ追記（→ AC5）
   - `skills/code/SKILL.md` — Step 7 の steering docs 存在確認が Glob explicit path 形式に準拠
   - `modules/codebase-analysis.md` — entry point/test Glob・Grep 呼び出しが explicit path 形式に準拠
   - `modules/doc-checker.md` — `$STEERING_DOCS_PATH/*.md` Glob 呼び出しが explicit path 形式に準拠

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md Step 7 で steering docs 存在確認の記述が、Glob の path 引数明示または Read 直接呼び出しの形式に修正されている" --> <!-- verify: section_contains "skills/code/SKILL.md" "### Step 7" "path" --> `skills/code/SKILL.md` Step 7 の steering docs 存在確認が `modules/filesystem-scope.md` 準拠の形式になっている（"path" 含む）
- <!-- verify: rubric "modules/codebase-analysis.md の Glob/Grep 例で全ての検索が path 引数を明示している、または起点ディレクトリが明示されている" --> `modules/codebase-analysis.md` の Glob/Grep 例で path 引数が明示されている
- <!-- verify: rubric "modules/doc-checker.md の Glob 例で path 引数の使用形式が明確化されている" --> `modules/doc-checker.md` の Glob 例で path 引数明示形式に整理されている
- <!-- verify: file_contains "modules/filesystem-scope.md" "skills/code/SKILL.md" --> `modules/filesystem-scope.md` の Implementation Reference に修正対象ファイルが追記されている
- <!-- verify: rubric "本 Issue で行われた変更がいずれも結果同等性を保ち、tool 呼び出し方式のみの変更であることが Spec 内で確認されている" --> 変更内容が結果同等性を保つことが Spec で確認されている

### Post-merge

- `/code N` 実行時に既存と同等の動作（steering docs 検出、ドキュメント検査）が確認できる
- `/auto` 実行時の TCC プロンプト発生機会が体感的に減少している（完全解消は #378 仮説 c により upstream 待ち。本 Issue は攻撃面縮小の範囲）

## Notes

- 変更は表記レベルの修正のみ。`Glob("*.md", path="$STEERING_DOCS_PATH")` は `Glob("$STEERING_DOCS_PATH/*.md")` と同等の結果を返す（CWD がリポジトリルート時）
- `modules/codebase-analysis.md` の Grep の一部（Step 3 のソースディレクトリ指定等）は既に特定ディレクトリを記述しているが、`path` 引数の明示指示として統一する
- テスト変更不要: 挙動回帰確認は `/code` の 1 回実行で十分（Issue Notes に記載）
- `section_contains "### Step 7" "path"` は修正後のテキスト（`path="$STEERING_DOCS_PATH"`）に "path" が含まれることを確認する。修正前の `$STEERING_DOCS_PATH` にも "path" が含まれるため verify としては保守的な検証。rubric による意味的確認（AC1）と組み合わせることで実質的な確認となる

## Code Retrospective

### Deviations from Design

- N/A（Spec の実装ステップに完全準拠）

### Design Gaps/Ambiguities

- `modules/doc-checker.md` の line 49 (`$STEERING_DOCS_PATH/*.md` → `*.md` with Glob (path: `$STEERING_DOCS_PATH`)) は Processing Steps 内の記述だが、Spec では "2 箇所" と記載。実際に確認すると Input 節（lines 15-16 の 2 行）+ Processing Steps 節（line 49）の計 3 箇所が変更対象だった。Spec の "2 箇所" は Input 節と Processing Steps 節（各 1 箇所として計 2 箇所）を指しており、実際の変更行数（3 行）とは異なる。意図は同一のため機能的な問題なし

### Rework

- N/A
