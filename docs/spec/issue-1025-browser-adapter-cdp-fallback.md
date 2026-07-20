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
