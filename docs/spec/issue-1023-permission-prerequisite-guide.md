# Issue #1023: issue: 外部サービス操作を含む運用系 Issue に実行アカウント・権限の前提を明記するガイドを追加

## Issue Retrospective

### Triage (非対話モード内で自動連鎖実行)
- `triaged` ラベル未付与だったため `/issue` 内から triage を自動連鎖 (title normalization 起点)
- Type: Feature (先例 #1024「metadata-only マーカー付与を追加」と同種の skill ガイド追加のため同じ分類を採用)
- Size: XS (先例 #1024 と同様、`skills/issue/SKILL.md` 単一ファイルへのガイド追記と想定)
- Value: 2 (Impact=0: 他 Issue からの参照・ブロッキングなし、Alignment=3: product.md Vision との関連は中程度と評価)

### Ambiguity 自動解決ログ (非対話モード三段階ポリシーの Tier 1)

- **「外部サービス操作を含む AC」の範囲定義** — 既存の SKILL.md Step 4 (metadata-only マーカー判定) で定義済みの「外部システムを対象とする verify command 集合」(`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect` / `lighthouse_check` / `browser_check` / `browser_screenshot` / `mcp_call` / `github_check` および外部対象の `command`/`rubric`) を踏襲する方針を採用。理由: 既存パターンとの一意な整合が取れ、AC 本文の記述 (「外部サービス操作を含む AC」) 自体は選択に依らず変化しないため。
- **ガイドの配置先** — `skills/issue/SKILL.md` 本体を採用 (別モジュールへの切り出しは不採用)。理由: AC の verify command が既に `grep "権限" skills/issue/SKILL.md` として配置先を明示しており、モジュール切り出しを選ぶと verify command と実装が不整合になるため。先例 #1024 も同様に SKILL.md 本体へ直接追記している。

### Acceptance Criteria の変更
- チェックボックスの条件文・verify command 自体は変更なし
- `## Acceptance Criteria` を `### Pre-merge (auto-verified)` / `### Post-merge` の節構成に整形 (両 AC とも `skills/issue/SKILL.md` の内容検証であり pre-merge 分類、Post-merge 該当なし)
- 上記 Ambiguity 自動解決ログを Issue 本文の `## Auto-Resolved Ambiguity Points` として追記

### AC Verify Command 監査 (triage Step 7 相当)
- `grep "権限" skills/issue/SKILL.md`: 引数順は正しい (pattern → path)。main 上で "権限" は未出現のため常時 PASS ではない
- 破壊的コマンド・patch route 不整合 (`gh pr checks`) なし。指摘事項なし、監査コメントは投稿せず
