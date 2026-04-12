# Issue #124: verify-executor: カスタム verify command タイプのハンドラ登録機構を追加

## Overview

verify-executor に、プロジェクトローカルの `.wholework/verify-commands/{name}.md` を発見・ディスパッチするカスタム verify command ハンドラ機構を追加する。ユーザーは Markdown ハンドラをファイル配置するだけでカスタム検証コマンドを追加でき、`<!-- verify: {name} "arg" -->` の形式で Issue 受入条件に組み込める。

Issue で確定した設計方針:
- 発見パスは adapter パターン再利用ではなく独立パス `.wholework/verify-commands/{name}.md`（Sub-issue #123 の方針整合、#122 Domain ファイルと同系統の UX）
- 発見機構は verify-executor 起動時の Glob scan（capability 宣言不要）
- ディスパッチは `<!-- verify: {name} ... -->` のコマンド名とハンドラファイル名（拡張子なし）の一致で決定
- ハンドラ形式は Markdown（adapter contract / domain-loader と同形式）
- safe-mode 可否はハンドラ側が所定セクションで自己宣言。未宣言時は UNCERTAIN
- ビルトインコマンド（`file_exists` 等）は常に優先。重複はスキップ（警告）
- user-global パス（`~/.wholework/verify-commands/`）は対象外（将来拡張）

## Changed Files

- `modules/verify-executor.md`: Processing Steps にカスタム verify command 発見・ディスパッチ手順を追加（Glob scan、ビルトイン優先、コマンド名一致、未解決 UNCERTAIN、safe-mode 自己宣言の扱い）
- `docs/environment-adaptation.md`: Layer 4 に `### Custom verify command handlers` セクションを追加（宣言パス、ハンドラ契約テンプレート、結果フォーマット PASS/FAIL/UNCERTAIN、safe-mode 自己宣言仕様）
- `skills/issue/SKILL.md`: verify command セクションの "Supported commands" 直後に、プロジェクトローカル `.wholework/verify-commands/{name}.md` カスタムコマンドへの言及ブロックを追加
- `docs/structure.md`: Directory Layout の `.wholework/` エントリに `verify-commands/` サブディレクトリを追加

## Implementation Steps

1. `modules/verify-executor.md` の Processing Steps にカスタム verify command 発見・ディスパッチ手順を追加する（→ 受入条件 1）
   - 位置: `3. Execute verification according to the translation table below:` の直前に新規 step として挿入（または既存 step 3 の前段フローに組み込む）
   - 内容: (a) コマンド名がビルトインに一致する場合は翻訳テーブルを使用、(b) ビルトイン不一致の場合 `.wholework/verify-commands/{name}.md` を Glob scan で探索し、ファイルが存在すればそれをハンドラとして Read、(c) ファイルが存在しなければ UNCERTAIN、(d) ハンドラが safe-mode 可否を所定セクション（例: 冒頭の `**Safe mode:** compatible` 宣言）で宣言していれば safe モードで実行、未宣言なら safe モードで UNCERTAIN、(e) ハンドラの処理手順に従って実行し PASS/FAIL/UNCERTAIN を返す、(f) ビルトイン名と重複するファイルは警告を出してビルトイン優先

2. `docs/environment-adaptation.md` の Layer 4 にカスタム verify command 機構セクションを追加する（→ 受入条件 2, 3, 4）
   - 追加位置: `### Adapter Pattern` の前後どちらか自然な場所（推奨: `### Adapter Contract Template` の直前または直後に `### Custom verify command handlers` として追加）
   - 内容: 宣言パス `.wholework/verify-commands/{name}.md`、ディスパッチ規約（コマンド名 = ファイル名）、ハンドラ契約（Purpose / Input / Processing Steps / Output の 4 節構造）、結果フォーマット（PASS / FAIL / UNCERTAIN）、safe-mode 自己宣言仕様（宣言記法例と未宣言時の UNCERTAIN 扱い）、ビルトインとの衝突解決（ビルトイン優先）、adapter パターンとの差異（1 実装前提）
   - Inter-layer Relationships ダイアグラム（ファイル末尾）にもフロー行を追加: `verify-executor (Layer 4) ─→ .wholework/verify-commands/*.md` 形で追記

3. `skills/issue/SKILL.md` の verify command セクションにカスタム verify command への言及を追加する（→ 受入条件 5）
   - 位置: Step 4 内の "Supported commands (exhaustive)" 表の直後、`--when` modifier ブロックの前に新規ブロックとして挿入
   - 内容: 冒頭に `**Custom verify command handlers (project-local):**` 見出しを置き、「`.wholework/verify-commands/{name}.md` にハンドラ Markdown を配置するとカスタムコマンドを追加できる」「Issue 受入条件に `<!-- verify: {name} "arg" --> ...` として記述できる」「詳細仕様は `docs/environment-adaptation.md` Layer 4 を参照」の 3 点を簡潔に記述

4. `docs/structure.md` の Directory Layout にカスタム verify commands ディレクトリを追加する（→ Changed Files 整合）
   - 変更箇所: `├── .wholework/` ブロック内
   - 変更内容: `│   ├── adapters/        # Verification adapter overrides` 行の下、`│   └── domains/` 行の前に `│   ├── verify-commands/ # Project-local custom verify command handlers` 行を追加（`└──` の末端記号は適宜調整）

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/verify-executor.md" "## Processing Steps" "verify-commands" --> `modules/verify-executor.md` の Processing Steps にカスタム verify command タイプの発見・ディスパッチ仕様（`.wholework/verify-commands/{name}.md` の Glob scan、コマンド名マッピング、ビルトイン優先、未解決は UNCERTAIN）が追加されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 4" "verify-commands" --> `docs/environment-adaptation.md` Layer 4 にカスタム verify command 機構の仕様（宣言パス `.wholework/verify-commands/{name}.md`、ハンドラ契約、結果フォーマット）が追加されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 4" "PASS" --> カスタムコマンドの結果フォーマット（PASS/FAIL/UNCERTAIN）が `docs/environment-adaptation.md` Layer 4 に記載されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "## Layer 4" "safe" --> カスタムハンドラが safe-mode 可否を自己宣言する仕様（未宣言時は UNCERTAIN）が `docs/environment-adaptation.md` に文書化されている
- <!-- verify: file_contains "skills/issue/SKILL.md" ".wholework/verify-commands/" --> `skills/issue/SKILL.md` の verify command セクションにプロジェクトローカルのカスタム verify command タイプへの言及が追加されている

### Post-merge

- `.wholework/verify-commands/{name}.md` にテストハンドラを配置し、対応する `<!-- verify: {name} ... -->` 条件を `/verify` で実行したときカスタムハンドラが検出・ディスパッチされることを確認 <!-- verify-type: opportunistic -->

## Notes

- **ハンドラ契約テンプレートの位置**: 本 Issue では Layer 4 にテンプレートを直接記載する。adapter contract template（`### Adapter Contract Template`）と類似の 4 節構造（Purpose / Input / Processing Steps / Output）を採用し、参照実装は後続 Issue で追加可能な余地を残す（本 Issue スコープでは参照実装ファイル作成は行わない）。
- **safe-mode 自己宣言の記法**: Markdown の「所定セクション」とは、ハンドラファイル冒頭付近の明示的な宣言行（例: `**Safe mode:** compatible` / `**Safe mode:** uncertain`）を想定。記法の詳細は Layer 4 に明記する。
- **`docs/ja/environment-adaptation.md`** および **`docs/ja/structure.md`** は翻訳出力ファイル（`/doc translate ja` 生成）のため実装対象外。
- **ビルトイン衝突時の警告出力先**: verify-executor の出力結果テーブルの Details 列に警告文言を含める（新規ログ機構の導入は不要）。
- **Glob scan のタイミング**: verify-executor が呼び出されるたびに Glob scan を行う（キャッシュ不要、ファイル数は実用上小規模を想定）。#122 domain-loader と同方式。
