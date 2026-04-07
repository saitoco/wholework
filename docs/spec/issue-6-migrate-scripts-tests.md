# Issue #6: scripts/tests: Migrate from private repo with English conversion and CI

## auto レトロスペクティブ

### 実行サマリー
| # | タイトル | ルート | 結果 | 備考 |
|---|---------|--------|------|------|
| #7 | GitHub API utility scripts and tests | pr (L) | SUCCESS | spec→code→review(full)→merge→verify 完了 |
| #8 | Project utilities and skill runner scripts | pr (L) | SUCCESS | spec→code→review(full)→merge→verify 完了 |
| #9 | Tooling scripts, add CI workflow | pr (L) | SUCCESS | spec→code→review(full)→merge→verify 完了。CI テスト1件失敗→修正→再マージ |

### 並列実行の問題
- 並列実行なし（#7 → #8 → #9 の順次依存グラフ）
- `run-auto-sub.sh` の PR 番号抽出バグ: `gh pr list --head "*issue-N-*"` がグロブパターン非対応のため、worktree ブランチ名（`worktree-issue-N-*`）にマッチせず全3件で失敗。親セッションから手動で review/merge/verify を続行してリカバリした
- #9 の CI テスト1件失敗: `tests/validate-skill-syntax.bats` に日本語アサーション `"2 スキル"` が残存（review で検出漏れ）。PR ブランチで修正 → CI 再実行 → PASS → merge

### 改善提案
- `run-auto-sub.sh` の PR 番号抽出を修正する必要がある: `gh pr list --head "*issue-N-*"` → `gh pr list --search "head:issue-N-"` または `gh pr list --json headRefName,number` でフィルタリングする方式に変更
- ユーザーからの要望で `docs/migration-notes.md` にインターフェース変更記録を追加。skills 移植 Issue で参照する方針

## issue レトロスペクティブ

### 判断経緯
- run-*.sh（スキルランナー 7 本）を移植対象に含めるか迷ったが、ユーザーの「全ファイル一括移植」指示と、スキルオーケストレーションの核である点から全量移植を自動解決
- 英語変換の範囲について、コメントのみ vs エラーメッセージ含む全文字列で迷ったが、CLAUDE.md Migration Guidelines の「Translate all Japanese text in source files」に準拠して全量英語化を自動解決

### 重要な方針決定
- CI ワークフロー（GitHub Actions で bats テスト自動実行）を本 Issue のスコープに含める（ユーザー確認済み）
- 3 分割方針: A(GitHub API ユーティリティ) → B(プロジェクトユーティリティ+スキルランナー) → C(ツーリング+CI) の順次実行（ユーザー承認済み）

### 受け入れ条件の変更理由
- 親 Issue の個別ファイル検証条件を各 sub-issue に再配分し、親 Issue には cross-cutting 条件（全テスト一括 PASS）のみ残した
- Risk Agent の調査結果から、install.bats の全面書き直し、gh-check-blocking.sh のフォールバックパス削除を sub-issue の設計注意点として追記
- Precedent Agent の知見から、bats テスト名の日本語パースエラー（tests/README.md 記録済み）を全 sub-issue の注意点に追加
