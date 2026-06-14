# Issue #649: git-hooks: DCO commit-msg hook を core.hooksPath で repo 全体に配備

## Overview

`scripts/git-hooks/commit-msg` を新規作成し DCO `Signed-off-by:` を commit ごとに強制する。`install.sh` で `git config core.hooksPath scripts/git-hooks` を実行し、全 worktree にフックを自動継承させる（worktree は `.git/config` を共有するため）。`CONTRIBUTING.md` に `core.hooksPath` のセットアップ手順を記載する。bats テストも追加する。

背景: PR #643 (#631) で 2 件の commit に DCO 署名漏れが発生。原因は (1) `EnterWorktree` 作成の worktree に commit-msg hook が不在、(2) `claude -p` の code フェーズで `git commit -s` を省略したコミットがあった。`core.hooksPath` パターンは原因 (1) を根本解決する: `.git/config` に記録されるため全 worktree に自動継承される。

## Changed Files

- `scripts/git-hooks/commit-msg`: 新規作成 — DCO 強制フック; `$1` の commit message を読み `^Signed-off-by:` 確認、未記載なら exit 1 — bash 3.2+ 互換、chmod +x
- `install.sh`: `echo "Done..."` の後に `git config core.hooksPath scripts/git-hooks` ステップを追加 — bash 3.2+ 互換
- `CONTRIBUTING.md`: DCO セクションに `core.hooksPath` セットアップ手順を追記
- `tests/git-hooks-commit-msg.bats`: 新規作成 — `scripts/git-hooks/commit-msg` の bats テスト
- `docs/structure.md`: Directory Layout に `scripts/git-hooks/` サブディレクトリを追記
- `docs/ja/structure.md`: `docs/structure.md` 変更に合わせて日本語翻訳を同期

## Implementation Steps

1. `scripts/git-hooks/commit-msg` を新規作成: shebang `#!/bin/bash`、`$1` から commit message を読み `grep -q "^Signed-off-by:" "$1"` で確認; 未記載なら `echo "Error: Commit is missing Signed-off-by. Use: git commit -s"` して exit 1; 記載あれば exit 0 — bash 3.2+ 互換、`chmod +x scripts/git-hooks/commit-msg` (→ AC1、Post-merge AC)
2. `install.sh` 更新: `echo "Done. Restart Claude Code..."` の後、`git config core.hooksPath scripts/git-hooks` を追加し `echo "Configured core.hooksPath = scripts/git-hooks"` でユーザーに通知 — bash 3.2+ 互換 (→ AC2 補完)
3. `CONTRIBUTING.md` DCO セクション更新: "### How to sign off" の後または直前に "### Automatic hook enforcement" サブセクションを追加; `./install.sh` が `core.hooksPath = scripts/git-hooks` を自動設定すること、手動設定は `git config core.hooksPath scripts/git-hooks` を記載 (→ AC2)
4. `tests/git-hooks-commit-msg.bats` を新規作成: `@test "commit-msg: signed commit passes"` (exit 0)、`@test "commit-msg: unsigned commit fails"` (exit 1)、`@test "commit-msg: error output mentions Signed-off-by"` (output に "Signed-off-by" を含む) の 3 ケース (→ AC3、AC4)
5. `docs/structure.md` Directory Layout 更新: `scripts/` エントリ配下に `│   └── git-hooks/       # Git hook scripts (commit-msg DCO enforcement)` を追記; `docs/ja/structure.md` を同内容で日本語同期 (→ SHOULD: 構造変更のドキュメント同期)

## Verification

### Pre-merge
- <!-- verify: file_exists "scripts/git-hooks/commit-msg" --> `scripts/git-hooks/commit-msg` を新規作成し、DCO Signed-off-by を強制する
- <!-- verify: file_contains "CONTRIBUTING.md" "core.hooksPath" --> `git config core.hooksPath scripts/git-hooks` をリポジトリで設定する手順を `CONTRIBUTING.md` に記載
- <!-- verify: file_exists "tests/git-hooks-commit-msg.bats" --> bats テストファイル `tests/git-hooks-commit-msg.bats` が作成されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI bats テストが全て PASS

### Post-merge
- 既存 EnterWorktree フローで自動継承されることを確認（`git config --get core.hooksPath` が新 worktree でも有効）

## Notes

- `core.hooksPath` は `.git/config` に記録されるため、`EnterWorktree` で作成された全 worktree に自動継承される
- `install.sh` に組み込むことで clone 後の `./install.sh` 一度の実行だけで hook が有効になる
- Auto-resolved: ドキュメント記載先 → `CONTRIBUTING.md`（既存 DCO セクションが存在し自然な格納場所; `docs/setup.md` は不在で新規作成が必要）
- Auto-resolved: AC2 verify command → `file_contains "CONTRIBUTING.md" "core.hooksPath"`（wholework 仕様準拠、単一ファイル・単一パターン）
- Auto-resolved: AC4 bats テスト実行検証 → `github_check "gh pr checks" "Run bats tests"`（Size M PR route; `.github/workflows/test.yml` の CI ジョブ名 "Run bats tests" を確認済み）

## Code Retrospective

### Deviations from Design
- `install.sh` の追記箇所を Spec では `echo "Done..."` の直後と記載していたが、実際には既存の plugin update ブロックの後（最終行 `echo "Done. Restart Claude Code..."` の直後）に追記した。意味的に同一だが、install.sh の末尾構造を確認した上で適切な位置に配置した
- `docs/structure.md` の file count (55 files) は既に実態 (56) と乖離していたため、カウント修正は今回のスコープ外として据え置き、`git-hooks/` サブディレクトリエントリの追加のみを行った

### Design Gaps/Ambiguities
- `scripts/git-hooks/commit-msg` の `set -e` と `grep -q` の組み合わせ: `grep -q` が見つからない場合（exit 1）に `set -e` が先に反応するため、明示的な `if ! grep -q ... then exit 1; fi` パターンで実装した。Spec の記述よりも堅牢な実装
- `install.sh` は `git config` を `git -C "$SCRIPT_DIR"` 形式で呼び出す必要があった（`install.sh` 実行ディレクトリが repo root でない場合の安全策）

### Rework
- N/A

## review retrospective

### Spec vs. 実装の乖離パターン
- Spec で指定した `install.sh` への追記位置（"Done..." の直後）は実装上も同位置だったが、`git config` ブロックを "Done" メッセージの後に置くと UX 上の問題（"Done" 表示後に設定が完了する）が生じることを review で発見。Spec 段階でスクリプト末尾の出力順序を明示しておくと code フェーズで順序ミスを防げた。

### 繰り返し指摘パターン
- 新規スクリプト追加時のテストケース完全性: bats 第3テストが exit code と output を両方アサートすべきところ output のみだった。テストケースを追加する際には「正常系: exit 0」「異常系: exit 1」「エラーメッセージ: output 内容」の3軸を全て assert するチェックリストを Spec に含めると改善できる。

### AC 検証難易度（UNCERTAIN 件数）
- 今回は全 Pre-merge AC が `file_exists` / `file_contains` / `github_check` で自動判定可能で UNCERTAIN なし。`github_check` の CI ジョブ名 "Run bats tests" が事前確定済みだったことが効いた。ジョブ名を Spec 段階で明記する方針は今後も継続すること。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST 指摘なし。SHOULD（install.sh メッセージ順序）と CONSIDER（bats exit code アサーション）の 2 件を review フェーズ内で修正・コミット済み
- `git config core.hooksPath` ブロックを "Done. Restart Claude Code..." より前に移動（UX 改善）
- bats 第3テストに `[ "$status" -eq 1 ]` を追加してリグレッション耐性を強化

### Deferred Items
- `docs/structure.md` の file count (55 files vs 実態 56) の乖離修正は引き続きスコープ外
- Post-merge AC（`git config --get core.hooksPath` が新 worktree でも有効か）は merge 後の手動確認が必要

### Notes for Next Phase
- 全 Pre-merge AC PASS 確認済み（file_exists × 2、file_contains × 1、github_check × 1）
- CI 全ジョブ SUCCESS（DCO、Run bats tests、Validate skill syntax、Forbidden Expressions check、macOS shell compatibility）
- MUST 指摘なし → `/merge 657` で merge 可能
