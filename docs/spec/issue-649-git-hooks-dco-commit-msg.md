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
