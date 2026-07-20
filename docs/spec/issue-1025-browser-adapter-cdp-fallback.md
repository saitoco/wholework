# Issue #1025: browser-adapter: Basic Auth 保護 preview 検証に認証済みローカルブラウザ (CDP アタッチ) fallback を追加

## Overview

`modules/browser-adapter.md` の Step 3 (Basic Authentication Setup) に、`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` 未設定時の fallback として、browser-use CLI のデフォルト動作 (実行中の認証済みローカル Chrome への CDP アタッチ) を用いた検証手順を追記する。Size=XS のため `/spec` を経由せず Issue 本文の Acceptance Criteria から直接実装した。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None. Issue 本文の AC1/AC2 の要件通り、`modules/browser-adapter.md` Step 3 への追記のみで実装完了。

### Design Gaps/Ambiguities

- なし。Issue の Notes セクションに実測結果 (browser-use CLI は CDP アタッチで認証済みセッションを再利用して通過、chrome-devtools MCP の `new_page` は独立コンテキストのため失敗) が既に記載されており、実装方針に曖昧さはなかった。

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- fallback の適用範囲を「Step 2 で検出したツールが browser-use CLI の場合のみ」に限定し、Playwright MCP 検出時は明示的に従来の unauthenticated 接続へフォールバックする分岐を追記した (Playwright MCP は常に独立コンテキストを開くため、CDP アタッチ fallback は原理的に成立しない)
- UNCERTAIN 時の詳細理由には Issue Notes の指定どおり日本語文字列「ローカルブラウザも未認証」をそのまま含める形にした (英語ドキュメント中でも AC がこの文字列の存在を要求しているため)

### Deferred Items
- None.

### Notes for Next Phase
- `/review` は本 Issue が pre-merge のみ (Post-merge AC なし) の構成のため、post-merge 側の追加検証は不要
- AC2 は `rubric` verify command による意味検証のため、`/review` safe mode でも rubric grader が実行されそのまま再評価される想定

## Issue Retrospective

### Triage 実行結果

`triaged` ラベルが未付与だったため triage を自動実行した (title normalization → Type/Priority/Size/Value 判定 → AC verify command 監査 → project field 更新 → `triaged` ラベル付与)。

- Title: 変更なし (既に `component: 名詞終わり` 規約に準拠)
- Type: Feature (`modules/browser-adapter.md` への fallback 挙動追加)
- Priority: 検出なし (title/body に明示的な優先度指定なし)
- Size: XS (対象ファイルは `modules/browser-adapter.md` 1件、ドキュメント追記のみ)
- Value: 3 (Impact=2: browser-adapter は複数スキルから参照される shared module のため +2 / Alignment=3: post-merge 検証の堅牢化という Vision に中程度合致)
- AC verify command 監査: 問題なし (grep 引数順・常時 PASS/FAIL・patch×`gh pr checks` 不整合・破壊的コマンドいずれも非該当)

### Ambiguity 自動解決ログ (非対話モード)

Size=XS のため検出上限3件。いずれも Auto-resolve tier (最小リスク・既存情報との整合性優先) で解決し、Issue body の AC1 に統合した。

- **[browser-use CLI を明記]** — 理由: Notes に既に実測結果として「browser-use CLI (CDP アタッチ) は認証済みセッションを再利用して通過」と記載されており、fallback の実装手段が既に実証済みのため、汎用表現のまま残すより具体名を明記する方が実装時の手戻りリスクが低い
  - 他の選択肢: 汎用的に「認証済みローカルブラウザ」とだけ記載し、具体ツールは `/spec` 段階の判断に委ねる (今回は不採用: Notes に既に実測済みの情報があるため、ここで確定させる方が一貫性が高い)
- **[UNCERTAIN fallback 挙動を AC1 の必須要件に統合]** — 理由: Notes では「望ましい」という推奨表現に留まっていたが、これは Purpose の「UNCERTAIN 引き継ぎの削減」と直接関係する回帰防止条件であり、AC に明記しないと実装時に欠落するリスクがある
  - 他の選択肢: Notes の記載のみに留め、AC には追加しない (今回は不採用: 回帰防止の核心部分のため明示化を優先)
- **[chrome-devtools MCP `new_page` が使用できない旨を AC1 に明記]** — 理由: Notes に記載済みの負例 (誤って `new_page` を使うと `ERR_INVALID_AUTH_CREDENTIALS` で失敗する) を手順に含めることで、実装者の誤選択を防止できる
  - 他の選択肢: 負例の記載は省略し、正しい手順のみを記載 (今回は不採用: 既に実測で判明している既知の落とし穴を明示する方が安全)

### AC 変更理由

AC1 の文言を拡張し、上記3件の自動解決内容 (ツール名の明記・UNCERTAIN fallback 挙動・負例の明記) を統合した。AC2 (資格情報非出力方針) は変更なし。verify command (`file_contains "modules/browser-adapter.md" "CDP"` / `rubric "..."`)  自体は変更していない。
