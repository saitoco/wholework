# Issue #213: terminology: tech.md Forbidden Expressions に product.md Terms 旧称の参照指令を追加

## Issue Retrospective

### 自動解決した曖昧性

直前の会話コンテキストから以下を auto-resolve した。

1. **指令の形式（prose vs. 表行）**: prose を採用。Forbidden Expressions 表は具体エントリ列挙向けの構造であり、メタ指令（"Terms 'Formerly called' の全エントリを参照せよ"）は表行より文章で書く方が明確。
2. **適用範囲**: コード（コメント・識別子）・コミットメッセージ・新規ドキュメント・retrospective・Issue 本文・Spec ファイルを含む新規コンテンツ全般。既存の skill 側配線（`skills/code/SKILL.md` L172）の文言「code comments, variable names, commit messages, and new documents」を踏襲。
3. **既存残留旧称の扱い**: Scope Declaration で `not included` を明示。既存 retrospective (`docs/spec/*.md`) は disposable であり、一括置換は後続 Issue で扱う。
4. **`docs/ja/tech.md` の同期**: 英語側と同等の指令を `## 禁止表現` セクションに追加。ただし product.md § Terms の日本語表記は「旧称」であるため、日本語側の指令は「`docs/product.md` § Terms の "旧称"」を参照する表現とする。

### 設計判断

Issue #98 で用語 SSOT を product.md Terms に一元化したため、今回は **tech.md 側に禁止用語を列挙し直す (Issue #98 をひっくり返す) のではなく、product.md Terms への参照指令を 1 行追加する** 方針を採用。これにより:
- SSOT の一元性が維持される
- 新しい旧称が追加された際は product.md Terms に "Formerly called" で追記するだけで禁止対象に自動的に組み込まれる
- skill 群は既に tech.md Forbidden Expressions を参照する配線を持つため、追加の skill 改修が不要
