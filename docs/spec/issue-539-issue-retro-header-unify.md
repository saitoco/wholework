# Issue #539: issue: retrospective コメント見出しを `## Issue Retrospective` に統一して XS issue の Spec 転写漏れを防止

## Issue Retrospective

### Triage 結果
- Type=Bug（producer/consumer のヘッダー不一致による retrospective の silent 転写漏れ。挙動が期待と異なる）, Priority=low, Size=XS（`skills/issue/SKILL.md` 単一ファイルの narrative 2 箇所）, Value=3（retrospective→改善提案パイプラインという共有インフラに影響）。
- 重複なし（#436 は「特筆事項あり時のみ生成」で別観点）。

### 自動解決した方針判断（Auto-Resolved）
- **fix は producer 側に統一（auto-resolve）**: 候補 (a) `/issue` 出力を canonical 見出し `## Issue Retrospective` に統一 / (b) consumer 側（`/auto` Step 4b・`/verify`）に後方互換探索キーを追加。採用は (a)。理由: 単一ファイル・最小変更で済み、`/verify` は既に `## Issue Retrospective` を canonical として文書化済み。consumer 側に探索キーを増やすと SSoT が分散する。

### 受け入れ条件
- pre-merge: rubric（Step 10/12 が canonical 見出しを明示）+ 補助 `file_contains "## Issue Retrospective"`（修正前の `skills/issue/SKILL.md` に当該リテラルは不在のため、fix 後にのみ PASS する機械的安全網）。
- post-merge: XS=patch route 整合の `github_check "gh run list"`（verify-type: auto）。

### メモ
- retro コメントの見出しを `## Issue Retrospective` としたのは、本 Issue が統一しようとしている canonical 見出しを自ら踏襲するため（ドリフトの再生産を回避）。
- 本 Spec への転写自体が、`/auto` Step 4b が canonical 見出しを検出して動作したことの実証になっている。
