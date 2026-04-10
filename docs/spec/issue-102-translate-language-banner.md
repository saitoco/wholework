# Issue #102: doc translate: 言語切り替えバナーの自動追加

## Overview

`doc translate {lang}` 実行時に、翻訳対象のすべてのドキュメント（ソース・翻訳の両方）に言語切り替えナビゲーションバナーを自動追加する。既存の翻訳ディレクトリを検出し、すべての言語をバナーに表示する。

## Changed Files

- `skills/doc/translate-phase.md`: Step 1 に翻訳検出サブステップを追加、Step 3 に翻訳ファイルへのバナー挿入を追加、新規 Step 4 でソースドキュメントへのバナー挿入を追加、Steps 4-6 を Steps 5-7 にリナンバー、Step 6 (旧 Step 5) の git add にソースファイルを追加

## Implementation Steps

1. Step 1 に既存翻訳を検出するサブステップ (item 4) を追加する。`docs/*/` ディレクトリと `README.*.md` ファイルをスキャンし、`en` + 検出された言語コード + 現在の `{lang}` を統合した **language list** を構築する。English を先頭、以降は言語コードのアルファベット順に並べる (→ acceptance criteria 3)

2. Step 3 の翻訳出力に言語ナビゲーションバナーを先頭に追加する指示を記述する。バナーフォーマット: 現在の言語はプレーンテキスト、他言語はリンク。リンク先パスは出力ファイルの位置からの相対パスとする (→ acceptance criteria 1, 5)

3. 新規 Step 4 "Add Language Navigation Banners to Source Documents" を追加する。翻訳対象リストの各ソースドキュメントに対し、frontmatter がある場合は閉じ `---` の直後、ない場合はファイル先頭にバナーを挿入する。既存バナーがある場合は置換する (→ acceptance criteria 2, 4)

4. Steps 4-6 を Steps 5-7 にリナンバーし、Step 6 (旧 Step 5) の `git add` コマンドにソースファイルを追加する (`git add` に翻訳対象リストのソースファイルを含める) (→ acceptance criteria 1, 2)

## Verification

### Pre-merge
- <!-- verify: grep "language.*banner\|language.*navigation\|language.*toggle" "skills/doc/translate-phase.md" --> translate-phase.md に言語ナビゲーションバナー追加のステップが記述されている
- <!-- verify: grep "source.*document\|source.*file\|original.*file" "skills/doc/translate-phase.md" --> ソース（英語）ドキュメントへのバナー追加処理が記述されている
- <!-- verify: grep "detect.*translat\|existing.*translat\|scan.*translat" "skills/doc/translate-phase.md" --> 既存の翻訳ディレクトリを検出する処理が記述されている
- <!-- verify: grep "frontmatter" "skills/doc/translate-phase.md" --> frontmatter を考慮したバナー挿入位置の指示がある
- <!-- verify: grep "plain.*text\|current.*language\|active.*language" "skills/doc/translate-phase.md" --> バナーフォーマット（現在の言語はプレーンテキスト、他言語はリンク）が定義されている

### Post-merge
- `doc translate ja` を実行し、ソースドキュメントと翻訳ドキュメントの両方に言語切り替えバナーが追加されることを確認

## Notes

- バナーの相対パス計算はファイル位置に依存する:
  - `README.md` → `README.{lang}.md` (同ディレクトリ)
  - `docs/product.md` → `docs/ja/product.md` → 相対パスは `ja/product.md`
  - `docs/ja/product.md` → `docs/product.md` → 相対パスは `../product.md`
  - `docs/ja/product.md` → `docs/ko/product.md` → 相対パスは `../ko/product.md`
- 言語名解決は既存の方針どおり LLM の組み込み知識に委譲（マッピングテーブル不要）
- 既存バナーの検出パターン: 先頭行（frontmatter 後）が `English |` または `[English]` で始まるかどうかで判定可能
