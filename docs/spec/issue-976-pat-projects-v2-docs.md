# Issue #976: docs: Fine-grained PAT の Projects V2 権限要件をドキュメント化

## Issue Retrospective

### 曖昧性解決の判断根拠

- **対象ファイルの特定 (`docs/guide/troubleshooting.md`)**: 元の Purpose では「`docs/guide/` 配下が候補」という未確定表現だった。`docs/guide/` 配下の既存ファイル (adapter-guide.md, autonomy.md, customization.md, scripting.md, troubleshooting.md 等) を調査した結果、troubleshooting.md が「Symptom / Fix」形式の既存節 (GitHub CLI Authentication, Plugin Install Failures 等) を持ち、本 Issue の「GitHub Actions + Projects V2 連携時の権限エラーとその回避策」という内容と最も一致するパターンと判断し、自動解決した。AC の rubric 文言自体はファイル名に依存しない書き方だったため、Purpose のみ具体化。

### Q&A における主要な方針決定

非対話モードのため AskUserQuestion は未使用。上記の対象ファイル特定を含め、すべて自動解決 (Auto-Resolve) で処理した。

### Acceptance Criteria 変更の理由

- 対象ファイルが `docs/guide/troubleshooting.md` に確定したため、rubric AC の対象パス表現を「docs/guide/ 配下」から「docs/guide/troubleshooting.md」に具体化した (rubric の判定対象自体は変更なし)。
- rubric + 補完チェックのガイドライン (verify-patterns.md §9) に従い、対象ファイル・セクションが予測可能になったことを受けて、`file_contains "docs/guide/troubleshooting.md" "Projects: Read and write"` を補完 AC として追加した。rubric が誤って PASS 判定するケース (別ファイルに記載されていても意味的に近ければ PASS になりうる) に対する機械的なセーフティネットとして機能する。

### その他

- Type: Task、Size: XS、Value: 2 (Impact=0: blocking/mentions/parent/shared いずれも該当なし、Alignment=2: downstream プロジェクト支援としてVisionに部分的合致) と判定。
- 重複候補、停滞パターン、依存関係の異常は検出されず。

## Consumed Comments
No new comments since last phase.
