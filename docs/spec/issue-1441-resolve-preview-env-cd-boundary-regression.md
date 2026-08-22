# Issue #1441: review: resolve-preview-env.sh の cd 境界依存 CWD-relative path バグに regression テストを追加

## Issue Retrospective

### 曖昧性解決の判断根拠

- **Proposal item 2 (`url` モードへの同パターン適用要否)**: `scripts/resolve-preview-env.sh` を読み、`url` モードの `_tmpout` はプロセス内スクラッチとしてのみ使われ、パスを呼び出し元に返さず `rm -f` で即削除されることを確認した (CWD-relative path が呼び出し元から解決不能になる構造そのものが存在しない)。既存コードから一意に推論可能であり、AC への反映は不要と判断して `basic-auth` モードのみを対象に確定した。

### 主要な方針決定

- **AC2 の verify command 訂正**: Step 1 のコメント消費で、`triaged` ラベル付与時に投稿された監査コメント (MEMBER, first-class) を検出した。指摘内容は「Size XS (`.wholework.yml` に `always-pr: true` 未設定) は patch route で処理され PR が作成されないため、`github_check "gh pr checks" "Run bats tests"` は対応する PR が存在せず恒久的に FAIL する」というもの。`/issue` skill の Acceptance Criteria Writing Guide (Size XS/S → patch route → `gh run list` 形式) に従い、`github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` に置き換えた。

### Acceptance Criteria 変更理由

- rubric AC (regression テスト追加確認) に対する補足の機械的検証として `file_contains "tests/resolve-preview-env.bats" "#1441 regression"` を追加した。既存テストファイルには `#1417 regression` のように Issue 番号付きでタグ付けする命名規約が既に存在しており (`mock_basic_auth_special` 近傍の複数テスト名を確認)、この規約に沿った命名を機械的に強制することで rubric 単独よりも検証精度を上げる狙い。
- AC2 は上記の通り `gh pr checks` → `gh run list` 形式に修正 (patch route との不整合を解消)。
- 明示的な `### Post-merge` セクション (「なし」) を追加し、Pre-merge/Post-merge の分類が完了していることを明確化した。

### Consumed Comments

- saito / MEMBER / first-class / triage AC audit — Size XS (patch route) では `gh pr checks` verify command が恒久 FAIL する旨の指摘、修復案付き / https://github.com/saitoco/wholework/issues/1441#issuecomment-5380796463

## Consumed Comments
No new comments since last phase.
