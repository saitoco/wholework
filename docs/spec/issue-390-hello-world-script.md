# Issue #390: scripts: Add hello world script

## Issue Retrospective

### 曖昧ポイントの自動解決（非対話モード）

今回の精査では以下の点を自動解決しました。

#### Auto-Resolve Log

- **セクション名 `Goal` → `Purpose` に変更** — 理由: `/issue` 標準フォーマットは `## Purpose` を使用するため。代替案: そのまま残す（選択せず）
- **Issue body を英語から日本語へ変換** — 理由: `CLAUDE.md` の "Issue bodies: Japanese" ポリシーに準拠。代替案: 英語のまま（選択せず）
- **Pre-merge / Post-merge セクション分割を追加** — 理由: 両受入条件ともに機械検証可能（ファイル存在確認 + コマンド出力確認）なので Pre-merge に分類。代替案: 分割なし（選択せず）

### Verify Command 設計の判断

| 受入条件 | 採用した verify command | 判断理由 |
|---------|----------------------|---------|
| `scripts/hello.sh` が存在する | `file_exists "scripts/hello.sh"` | ファイル存在確認には専用コマンド推奨 |
| `Hello, Wholework!` を出力する | `command "bash scripts/hello.sh \| grep -qF 'Hello, Wholework!'"` | 出力内容の確認には `command` hint を使用。`grep -qF` で固定文字列として照合 |

### 受入条件変更なし

受入条件の実質的な内容は変更なし。フォーマット（セクション分割・verify command 付与・言語統一）のみ更新。
