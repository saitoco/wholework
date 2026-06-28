# Issue #443: verify: worktree 内で node_modules 依存 command verify をサポート

## Overview

`/verify` 実行時、worktree 環境では `node_modules/` が親リポジトリ側にしか存在しないため、`command` verify タイプ (例: `pnpm exec astro check`) が `sh: <bin>: command not found` で失敗する。

対策として以下 2 点を実施する:

- **A. worktree-init hook 向けガイダンスを追記**: `modules/worktree-lifecycle.md` の Entry Section に、`node_modules` が親リポにある場合に worktree 内へ symlink する手順を追加する。プロジェクトの `.claude/hooks/worktree-init.sh` に組み込むためのサンプルコードを提示する。
- **D. verify-patterns.md への注記**: `modules/verify-patterns.md` §1 False Positive Patterns テーブルに、`node_modules` 依存 `command` verify が worktree 環境で失敗するパターンと推奨代替案を追記する。

## Changed Files

- `modules/worktree-lifecycle.md`: Entry Section に Step 4 (`node_modules` symlink ガイダンス) を追記 — bash 3.2+ compatible
- `modules/verify-patterns.md`: §1 False Positive Patterns テーブルに `node_modules` 依存パターン行を追記

## Implementation Steps

1. `modules/worktree-lifecycle.md` の `### Entry Section (execute at skill start)` 内の Step 3 (worktree-init.sh hook 実行) の直後に Step 4 を追記する (→ AC1, AC2)

   追記内容:

   ```
   4. **`node_modules` を親リポから symlink (Node.js プロジェクト向けオプション)**: `command` verify タイプが `pnpm exec` / `npx` 等のバイナリに依存する場合、worktree 内では `node_modules/` が存在しないためバイナリが見つからない。親リポに `node_modules/` がある場合は symlink を作成して共有する手順を `.claude/hooks/worktree-init.sh` に追加することで解決できる:
      ```bash
      PARENT_ROOT="$(git worktree list | awk 'NR==1{print $1}')"
      if [ -d "$PARENT_ROOT/node_modules" ] && [ ! -e "node_modules" ]; then
        ln -s "$PARENT_ROOT/node_modules" node_modules
      fi
      ```
      **注意**: symlink はロックファイルが一致している場合にのみ安全。worktree ブランチのロックファイルが親と異なる場合は symlink の代わりに `pnpm install --frozen-lockfile` を実行すること。
   ```

2. `modules/verify-patterns.md` の `### 1. False Positive Patterns and How to Avoid Them` テーブルに新しい行を追記する (→ AC3, AC4)

   追記内容 (テーブル行):

   ```
   | `node_modules` 依存バイナリの `command` verify が worktree 環境で失敗する | `pnpm exec astro check` や `npx tsc` など `node_modules/.bin/` のバイナリに依存する `command` verify は、worktree 内に `node_modules/` が存在しないため `command not found` で UNCERTAIN/FAIL になる (worktree は `git worktree add` で作成されるが `node_modules/` は親リポ側にのみ存在する) | `github_check` で CI 結果を参照する形に切り替えるか、`.claude/hooks/worktree-init.sh` に symlink 手順を追加する (参照: `modules/worktree-lifecycle.md` Entry Section Step 4) | ❌ `command "pnpm exec astro check"` (worktree 内で FAIL) → ✅ `github_check "gh run list --workflow=ci.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "node_modules" "modules/worktree-lifecycle.md" --> `modules/worktree-lifecycle.md` の Entry Section に `node_modules` symlink ガイダンスが追記される
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Entry Section" "node_modules" --> Entry Section 内に `node_modules` に関する記述が存在する
- <!-- verify: grep "node_modules" "modules/verify-patterns.md" --> `modules/verify-patterns.md` に `node_modules` 依存 `command` verify の worktree 環境での失敗パターンと推奨代替が追記される
- <!-- verify: section_contains "modules/verify-patterns.md" "### 1." "node_modules" --> §1 False Positive Patterns テーブルに `node_modules` 関連の行が追加される

### Post-merge

なし

## Consumed Comments

- `saito` / `MEMBER` / first-class / Issue Retrospective: A+D の実装アプローチを採用、bats テスト不要、verify-patterns.md §1 テーブルに追記、受入条件 4 件確定 / https://github.com/saitoco/wholework/issues/443#issuecomment-4825172412

## Notes

- 実装対象は `modules/` 以下のドキュメント変更のみ。worktree-init.sh は各プロジェクトが独自に実装するため Wholework 本体には含まれない
- bats テスト不要 (Issue Retrospective での Auto-Resolve による判断、ドキュメント変更のみ)
- Issue Retrospective での自動解決: B (cwd fallback) は暗黙的 cwd 切替リスク、C (install on demand) はネットワーク必須・時間コストのため除外
- verify-patterns.md の追記箇所: §1 テーブル (既存テーブル形式との整合)
- `section_contains "modules/verify-patterns.md" "### 1." "node_modules"` の heading argument `"### 1."` は verify-patterns.md 内の既存 verify 例 (line 145) と同じ形式を踏襲
