# Issue #47: readme: Simplify Install section and link development setup to docs/structure.md

## Issue Retrospective

### 判断の経緯

本 Issue は #42 完了後のフォローアップとして、ユーザーから「marketplace install が動作確認できたので README をシンプル化できるのでは」という提案を受けて作成した。

### Auto-Resolved Ambiguity Points（判断根拠）

| 論点 | 判断 | 根拠 |
|------|------|------|
| README に追加するリンクの配置 | Install セクション末尾に 1 行追加 | ユーザーが「1 行リンクを追加」と明示。Install セクション内で完結させるのが自然 |
| `Skills are available as wholework:<skill-name>` の扱い | 残す | marketplace install 後に skill を呼び出す際に必要な情報 |
| `docs/structure.md` の変更要否 | 当初「変更不要」と判断したが、scope 拡張により取り下げ（下記参照） |
| プレースホルダーの具体的表記 | `<path-to-wholework>` を採用 | 慣用的な angle-bracket プレースホルダー表記で置換箇所が一目で分かる |
| `git clone` に渡す clone 先引数 | 指定しない | 初見ユーザーの混乱を避けるため 2 段構成（`git clone <URL>` → `claude --plugin-dir <path-to-wholework>`） |

### Scope Update（ユーザー追加指示）

1. **`docs/structure.md` の変更が必要**: development install 手順に `git clone` を追加（現状は `claude --plugin-dir` のみでリポジトリ取得手順が欠けている）
2. **パス表記のプレースホルダー化**: `~/src/wholework` はユーザー環境依存の例のため、`<path-to-wholework>` に置き換え

変更内容:
- Background / Purpose を追記
- Pre-merge Acceptance Criteria を README.md と docs/structure.md の 2 セクションに分割し、docs/structure.md 側の検証条件を 4 件追加
- 以前の前提「docs/structure.md は変更不要」は取り下げ

Size 影響: 単一ファイル → 2 ファイル編集に拡大するが、いずれも数行の変更のため Size は **XS** のまま維持。

### Triage 結果

- **Type**: Task（ドキュメント更新）
- **Size**: XS
- **Value**: 2（DX 微改善、Impact 小・Alignment 中）
- **Priority**: 未指定
- **重複**: なし
- **停滞**: なし
- **依存**: #42（CLOSED）への言及のみ、未解決依存なし

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective が既に記録されている。スコープ拡張（docs/structure.md への変更追加）を明文化した判断プロセスが残っており、後から意図が追いやすい。受け入れ条件は具体的かつ verify command付きで品質が高かった。

#### design
- Spec ファイルに Spec Retrospective セクションなし（patch ルートのため `/spec` 未実行）。設計判断は Issue Retrospective のAuto-Resolved Ambiguity Points で代替されており、実用上問題なし。

#### code
- 実装は単一コミット `95868be` で完了（リワークなし）。patch ルート（XS）のため直接 main へコミット。コミットメッセージが変更内容を簡潔に表現しており良い。

#### review
- patch ルートのため PR レビューなし。変更規模（2 ファイル、数行の削除・追加）からして正当な判断。

#### merge
- 直接 main にコミット・プッシュ（patch ルート）。競合なし、CI パスを確認。

#### verify
- 全 9 条件が一発で PASS。受け入れ条件に verify commandが適切に付与されており、自動検証が完全に機能した。特に `section_contains` を使った構造的な検証（`### Install` セクション内の存在確認）が有効だった。

### Improvement Proposals
- N/A
