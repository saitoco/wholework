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
<!-- phase: merge -->

### Key Decisions
- PR #657 をスカッシュマージ（`gh pr merge 657 --squash --delete-branch`）で main に統合
- mergeable=true、CI 全 SUCCESS、review approved の状態で conflicts なし → Step 3 スキップ、直接 Step 4 へ
- BASE_BRANCH=main のため `closes #649` によりマージと同時に Issue は自動クローズされる

### Deferred Items
- `docs/structure.md` の file count (55 files vs 実態 56) の乖離修正は引き続きスコープ外
- Post-merge AC（`git config --get core.hooksPath` が新 worktree でも有効か）は `/verify` で確認すること

### Notes for Next Phase
- Pre-merge AC は全て PASS 済み（review フェーズ確認済み）
- verify で確認すべきポイント: `git config --get core.hooksPath` が新 worktree 環境で `scripts/git-hooks` を返すこと
- Spec の Post-merge AC セクションに verify command が記載されていないため、verify フェーズで手動確認が必要

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC 4 件すべて自動検証可能 (`file_exists` × 2、`file_contains` × 1、`github_check` × 1)。CI job 名 "Run bats tests" を spec 段階で明確化していたため UNCERTAIN ゼロ。
- Post-merge manual AC は `git config --get core.hooksPath` という executable な手順を持つが、`verify-type: manual` のため batch mode では user 確認待ち。

#### design
- `core.hooksPath` + `scripts/git-hooks/` パターン採用。worktree 自動継承の git 構造的保証あり。
- 既存 hook と競合なし。`install.sh` への 1 行追加で fresh clone 対応完了。

#### code
- 1 PR (#657) で完了。fixup/amend なし。
- 変更ファイル 7 件 / 97 insertions（commit-msg hook 新規、bats テスト新規、install.sh / CONTRIBUTING.md / docs/structure.md 加筆）。

#### review
- light review で MUST/SHOULD なし。
- DCO 自体の正しさは bats テスト 3 ケースで担保。

#### merge
- squash merge `--delete-branch` で main 直接マージ。CI 全 SUCCESS、conflict なし。
- `closes #649` で Issue 自動クローズ。

#### verify
- Pre-merge AC 4 件全て PASS。Post-merge manual AC のみ手動確認待ちで `phase/verify` を維持。

### Improvement Proposals
- (CONSIDER) Post-merge manual AC の文言を「user が `install.sh` 適用後に `git config --get core.hooksPath` が `scripts/git-hooks` を返す」のように executable command 形式に整理し、`<!-- verify: command "..." -->` で auto-verify 化を検討。本 Issue スコープ外。

