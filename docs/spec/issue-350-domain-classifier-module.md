# Issue #350: domain-classifier: New General-Purpose Module for Classifying Improvement Proposals by Domain

## Overview

`modules/domain-classifier.md` を新設する。入力として改善提案テキストと `domain-loader.md` でロード済みの Domain file 一覧（frontmatter parse 済み）を受け取り、どの Domain に属するか (`domain: skill-dev` / `none` / `ambiguous`) と Core → Domain の書き換え先パスを判定して返す汎用 LLM-in-context モジュール。

判定ロジック:
- 各 Domain file の `applies_to_proposals.file_patterns` (glob 評価) と `content_keywords` (OR マッチ) を評価
- 優先順位: 両方マッチ → 宣言順フォールバック (Option 3→1)
- ワイルドカード解決: LLM 意味的マッチ (Option 1)、一意選択不能時のみ `ambiguous`
- どの Domain にもマッチしない場合: `domain: none`

## Changed Files

- `modules/domain-classifier.md`: 新規作成
- `tests/domain-classifier.bats`: 新規作成 (shallow contract test、domain-loader.bats パターン準拠)
- `docs/structure.md`: modules 数を `(29 files)` → `(31 files)` に更新（既存ドリフト修正 + 新規ファイル）、tests 数を `(53 files)` → `(54 files)` に更新、Key Files Modules リストに `domain-classifier.md` エントリ追加 — bash 3.2+ 互換
- `docs/environment-adaptation.md`: 将来形参照を現在形に更新 (`future domain-classifier.md` → `domain-classifier.md`; lines 96, 129)
- `docs/ja/structure.md`: 上記 `docs/structure.md` 変更の翻訳同期
- `docs/ja/environment-adaptation.md`: 上記 `docs/environment-adaptation.md` 変更の翻訳同期

## Implementation Steps

1. `modules/domain-classifier.md` を新規作成（→ AC1-8）。4 section 構造 (Purpose / Input / Processing Steps / Output) で記述:
   - **Purpose**: 改善提案テキストをロード済み Domain file 一覧と照合して domain 分類を返す汎用モジュール。`domain-loader.md` のあとに呼ぶ composable 設計（file I/O 行わず）
   - **Input**: (a) 改善提案テキスト; (b) `domain-loader.md` で既にロード済みの Domain file 内容リスト（frontmatter 含む）。`applies_to_proposals` を持つ Domain file のみ分類対象
   - **Processing Steps**:
     - `applies_to_proposals` 未宣言の Domain file はスキップ
     - 各 Domain file で `file_patterns` (提案が言及する Core ファイルの glob マッチ) と `content_keywords` (提案テキスト内キーワード OR マッチ) を評価
     - 優先順位判定: 両方マッチ → 宣言順 → 片方のみ → 宣言順 → マッチなし → `none`
     - `rewrite_target.to` がワイルドカードを含む場合: 提案内容と候補ファイル名の LLM 意味的マッチで一意選択。一意選択不能な場合のみ `domain: ambiguous`、`fallback_reason` に理由を記載
     - 複数 Domain マッチは優先順位ルールで必ず解決され `ambiguous` にはならない
   - **Output**: `domain` (matched `domain:` キー値 / `none` / `ambiguous`)、`matched_keys` (マッチした評価キーの配列)、`rewrite_target` (`from`/`to` オブジェクト)、`fallback_reason` (非 null は `ambiguous` 時のみ)

2. `tests/domain-classifier.bats` を新規作成（→ AC9、Step 1 の後）。`domain-loader.bats` と同じ shallow contract test パターン:
   - `grep -q "applies_to_proposals"` — input key が documented されている
   - `grep -q "file_patterns"` — input sub-key が documented されている
   - `grep -q "content_keywords"` — input sub-key が documented されている
   - `grep -q "rewrite_target"` — output key が documented されている
   - `grep -q "ambiguous"` — ambiguous 値が documented されている
   - `grep -q "none"` — none 値が documented されている
   - `grep -qiE "priority|both"` — 優先順位ルールが documented されている
   - `grep -qiE "wildcard|\\*"` — ワイルドカード解決ルールが documented されている
   - `grep -q "^## Input"` — Input section が存在する
   - `grep -q "^## Output"` — Output section が存在する

3. `docs/structure.md` を更新（Step 1, 2 の後）:
   - Directory Layout の `modules/` 行: `(29 files)` → `(31 files)`（既存ドリフト: 実際は 30 ファイルで structure.md が 29 と記録していたため +2）
   - Directory Layout の `tests/` 行: `(53 files)` → `(54 files)`
   - Key Files Modules リストに追加: `- \`modules/domain-classifier.md\` — improvement proposal Domain classification (composable, LLM-in-context)`

4. `docs/environment-adaptation.md` を更新（Step 1 の後）:
   - Line 96: `(future \`domain-classifier.md\`, #350)` → `(\`domain-classifier.md\`)` に変更
   - Line 129: `future classifier logic (#350)` → `classifier logic (\`domain-classifier.md\`)` に変更; `handled by \`domain-classifier.md\` (#350)` → `handled by \`domain-classifier.md\`` に変更

5. `docs/ja/structure.md` と `docs/ja/environment-adaptation.md` を翻訳同期（Step 3, 4 の後。parallel with each other）:
   - `docs/ja/structure.md`: Step 3 の変更内容（modules/tests カウント更新、domain-classifier エントリ追加）を日本語で反映
   - `docs/ja/environment-adaptation.md`: Step 4 の変更内容（将来形 → 現在形）を日本語で反映（lines 89, 122 付近）

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/domain-classifier.md" --> `modules/domain-classifier.md` が新設されている
- <!-- verify: rubric "modules/domain-classifier.md defines a clear interface with input (proposal text, list of Domain files with applies_to_proposals frontmatter already loaded via domain-loader.md) and output (domain name sourced from the matched Domain file's frontmatter domain: key, rewrite_target with from/to, ambiguity flag)" --> Classifier の interface (入出力) が明確に定義されており、domain 名は frontmatter `domain:` キー由来であることが明示されている
- <!-- verify: section_contains "modules/domain-classifier.md" "## Input" "applies_to_proposals" --> Input セクションに `applies_to_proposals` が記述されている
- <!-- verify: section_contains "modules/domain-classifier.md" "## Output" "rewrite_target" --> Output セクションに `rewrite_target` が記述されている
- <!-- verify: rubric "modules/domain-classifier.md documents the priority rule for multi-domain matches (both file_patterns and content_keywords match first, then declaration order as tie-break) and the wildcard resolution rule for rewrite_target.to (LLM semantic match with ambiguous fallback only for wildcard resolution, not for multi-domain match)" --> 優先順位ルールとワイルドカード解決ルールが記述されている
- <!-- verify: grep "ambiguous" "modules/domain-classifier.md" --> `ambiguous` フラグの発火条件が記述されている
- <!-- verify: rubric "modules/domain-classifier.md defines the 'none' fallback behavior for proposals that do not match any Domain (Core target preserved)" --> Core フォールバック動作が定義されている
- <!-- verify: grep "none" "modules/domain-classifier.md" --> `none` ドメイン値の扱いが記述されている
- <!-- verify: file_exists "tests/domain-classifier.bats" --> `tests/domain-classifier.bats` shallow contract test が追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> すべての bats tests が PASS する
- <!-- verify: grep "(31 files)" "docs/structure.md" --> `docs/structure.md` modules カウントが更新されている

### Post-merge

- skill-dev プロジェクトで `skills/code/SKILL.md` 改善提案を classifier に通すと `domain: skill-dev` + 書き換え先 Domain file path が返ることを手動確認 <!-- verify-type: manual -->
- どの Domain にも該当しない一般的な提案（例: docs/product.md の追記）を classifier に通すと `domain: none` が返ることを手動確認 <!-- verify-type: manual -->

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- Spec の Notes に「`rewrite_target` は `applies_to_proposals` の下位フィールド」と記載があったが、モジュールの Processing Steps と Output では `rewrite_target` を独立したフィールド名として使用する設計。実装では Spec Notes の指摘どおり `applies_to_proposals.rewrite_target` として参照することを明記し、Output の field 名は `rewrite_target` のままとした（Issue body の Interface 定義と一致）。

### Rework

- N/A

## Notes

- **スキーマ差異（Issue body vs. 実装）**: Issue body では `domain` / `applies_to_proposals` / `rewrite_target` を 3 つの独立した frontmatter キーとして記述しているが、#349 の実際の実装では `rewrite_target` は `applies_to_proposals` の下位フィールド（`applies_to_proposals.rewrite_target`）として追加された（`skills/spec/skill-dev-constraints.md` 等で確認済み）。モジュール実装は実際のスキーマ（ネスト）を反映する。出力フィールド名 `rewrite_target` はそのまま保持。
- **structure.md 既存ドリフト**: `docs/structure.md` の modules 数が `(29 files)` と記載されているが、実際のファイル数は 30（`phase-state.md` と `skill-dev-doc-impact.md` が追加された際に count が更新されなかった）。本 Issue では `domain-classifier.md` 追加で 31 ファイルになるため、count を `(29 files)` → `(31 files)` に更新する（ドリフト修正も兼ねる）。
- **Auto-Resolved Ambiguity Points（Issue body 記載済み）**:
  - 実行モード: LLM-in-context（スクリプト wrapper なし）
  - 入力契約: 呼び出し側が先に `domain-loader.md` を実行してロード; classifier は file I/O しない
  - テスト戦略: `domain-loader.bats` と同じ shallow contract test
  - 優先順位ルール: 両方マッチ優先 → 宣言順フォールバック (Option 3→1)
  - ワイルドカード解決: LLM 意味的マッチ (Option 1)、一意選択不能時のみ `ambiguous`
  - Core フォールバック: `domain: none`
  - `ambiguous` 発火条件: ワイルドカード解決時のみ（複数 Domain マッチは優先順位ルールで解決）
