# Issue #549: auto: Add auto-rename of session title on /auto invocation

## Overview

`UserPromptSubmit` hook を新規追加し、ユーザ入力が `/auto <N>` 等のパターンに一致した場合に、`gh issue view` で取得した Issue title からセッション名を組み立てて `hookSpecificOutput.sessionTitle` 経由で自動設定する。長時間並行する `/auto` セッションの識別性を高めることが目的。

対象は `/auto` のみ。他 skill 展開・完了時自動クリアは Non-Goals（Issue 本文参照）。

## Changed Files

- `scripts/hook-rename-on-auto.sh`: 新規。`UserPromptSubmit` hook 本体。stdin の JSON event payload から `prompt` フィールドを読み、`/auto` 系のパターンに合わせてセッション名を組み立てて JSON 出力。bash 3.2+ 互換（mapfile 等 bash4 機能を使わない）
- `.claude/settings.json.template`: 編集。`hooks` セクションに `UserPromptSubmit` エントリを追加。Edit/Write ツールは `.claude/` 配下を拒否するため、Bash の `python3` または `jq` で読み書きする
- `tests/hook-rename-on-auto.bats`: 新規。`tests/log-permission.bats` を雛形にし、Issue 本文の各分岐（番号付き / batch / resume / 非マッチ / gh 失敗 / truncate / `component:` prefix 除去）をカバー

## Implementation Steps

1. **Hook script の実装** (`scripts/hook-rename-on-auto.sh`) (→ AC1, AC2)
   - shebang `#!/bin/bash`、`set -eu` は使わない（hook 失敗時に既存セッション名を破壊しないため、エラー時は静かに空出力で抜ける）
   - `INPUT=$(cat)` で stdin JSON を読み、`PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""')` で prompt 抽出
   - 早期 return: `PROMPT` が `/auto` で始まらない、もしくは `--help` を含む場合は空出力で `exit 0`
   - 分岐判定（順序重要）:
     - `/auto --batch <N>`（`N` が単一数値かつ後続なし） → `TITLE="auto batch ($N issues)"`
     - `/auto --batch <N1> <N2> ...`（複数数値） → カンマ結合で `TITLE="auto batch #$N1,$N2,..."`
     - `/auto --resume <N>` → 番号取得 + `TITLE="auto #$N (resume): <stripped>"`
     - `/auto <N>`（フラグ前置でも可、最初の整数を採用） → `TITLE="auto #$N: <stripped>"`
   - Issue title 取得: `RAW=$(gh issue view "$N" --json title -q .title 2>/dev/null)` ; 失敗 (`$? != 0` または空) なら空出力で `exit 0`
   - `<stripped>` 整形: 先頭の `^[A-Za-z0-9_/-]+:[[:space:]]+` を sed で除去
   - Truncate: 50 文字超なら `cut -c1-49` + `…`（UTF-8 マルチバイトは `awk` で対応、後述 Notes）
   - 最終出力: `printf '{"hookSpecificOutput":{"sessionTitle":"%s"}}\n' "$(escaped)"`（`"`/`\\` は jq でエスケープ）
   - 番号なし `/auto`（`/auto --help` 等） → 空出力

2. **`.claude/settings.json.template` の編集** (→ AC3, AC4)
   - Edit/Write が `.claude/` 配下を拒否するため、Bash + `jq` で読み書き:
     ```bash
     jq '.hooks.UserPromptSubmit = [{"matcher":"","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/scripts/hook-rename-on-auto.sh","timeout":5000}]}]' \
       .claude/settings.json.template > .claude/settings.json.template.new \
       && mv .claude/settings.json.template.new .claude/settings.json.template
     ```
   - `jq` 失敗時は `|| die "jq failed"` でガード（read-then-write jq failure guard）
   - 既存 `PermissionRequest` エントリは保持（`jq` の代入は対象パスのみ）

3. **bats テストの実装** (`tests/hook-rename-on-auto.bats`) (→ AC5, AC6)
   - `tests/log-permission.bats` を雛形に複製してケース調整
   - `setup()` で `gh` を mock: `MOCK_DIR` を `PATH` 先頭に置き、`#!/bin/bash` で `case $* in ...esac` 形式の偽 `gh` を配置。`tests/apply-fallback.bats` と同パターン
   - ケース（最低 7 件）:
     - 番号付き `/auto 123` → `sessionTitle` が `auto #123: <title>` を含む JSON
     - `/auto 123 --patch` （フラグ付き） → 同上
     - `/auto --resume 123` → `auto #123 (resume): ...`
     - `/auto --batch 5` → `auto batch (5 issues)`
     - `/auto --batch 123 124 125` → `auto batch #123,124,125`
     - title 先頭 `component: ` 除去
     - 結合後 50 char 超で `…` 切り詰め
     - 非マッチ（`/code 123` 等） → 空出力
     - `gh` 失敗（mock を `exit 1`） → 空出力

4. **Spec から install.sh 影響を docs に伝達** (→ post-merge note)
   - install.sh 自体は変更不要（template を再読み込みするだけ）。README / docs/guide には特段追記しない（Non-Goals に install.sh 自動再実行は含めない）
   - 既存ユーザは template 変更後に `./install.sh` を手動再実行する必要がある旨を PR 本文に明記（コード変更ではない）

## Alternatives Considered

- **wholework plugin 配下に hook を入れる方式**: plugin 利用者全員に強制適用される副作用が大きい（opt-in 構造が壊れる）。本 Issue の Non-Goals「他 skill 拡張」とも整合しない。不採用
- **`SessionStart` hook で `--resume` 時の session 名復元**: `--resume` は Claude Code 側で session 名が永続化されているため不要（changelog: `Fixed claude --resume losing the session's custom name`）。`UserPromptSubmit` でのみ十分

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/hook-rename-on-auto.sh" --> `scripts/hook-rename-on-auto.sh` が新規作成されている
- <!-- verify: file_contains "scripts/hook-rename-on-auto.sh" "hookSpecificOutput" --> hook script が `hookSpecificOutput.sessionTitle` を含む JSON を出力する実装になっている
- <!-- verify: file_contains ".claude/settings.json.template" "UserPromptSubmit" --> `.claude/settings.json.template` に `UserPromptSubmit` hook エントリが追加されている
- <!-- verify: file_contains ".claude/settings.json.template" "hook-rename-on-auto.sh" --> `.claude/settings.json.template` の `UserPromptSubmit` hook が `hook-rename-on-auto.sh` を参照している
- <!-- verify: file_exists "tests/hook-rename-on-auto.bats" --> bats テストファイル `tests/hook-rename-on-auto.bats` が追加されている
- <!-- verify: github_check "gh pr checks" "bats" --> CI で bats テストが pass している

### Post-merge

- `/auto 123` 実行時、セッション名が `auto #123: <stripped title>` の形式（component prefix 除去 + 50 char truncate 適用）に自動変更される（Claude Code の statusline / `claude --resume` picker で確認）
- `/auto --batch 5` および `/auto --batch 123 124 125` および `/auto --resume 123` 実行時、それぞれ仕様通りのセッション名になる
- 通常のプロンプト入力時、hook が動作しても体感できる遅延・余計な出力が無い
- `gh` 失敗・Issue 不在時に既存セッション名が破壊されない

## Notes

- **`.claude/` 配下のファイル編集制約**: Edit/Write ツールは拒否される。`/code` 実行時は `jq` または `python3`/`sed` を Bash 経由で使う（`modules/worktree-lifecycle.md` Notes 参照）
- **bash 3.2 互換**: macOS の system bash が 3.2 のため、`mapfile`、連想配列、`[[ =~ ]]` 内の `BASH_REMATCH` 多用などは避けて、`grep -oE` / `awk` / `case` で代替
- **truncate と UTF-8**: Issue title は日本語含み得る。`cut -c1-49` はバイト単位で文字境界を壊す可能性がある。`awk '{ s=$0; if (length(s)>50) s=substr(s,1,49) "…"; print s }'` で文字数判定（awk の length は UTF-8 文字数を返す環境が多いが、bsd awk では bytes になる場合がある）。macOS bsd awk では gawk が無いので、安全策として bash の `${#var}` を使い、それでも不正確なケースは PR レビュー時に確認する。妥協として「概ね 50 文字、稀に 49 バイトで切れることがある」と割り切る
- **コンポーネント prefix 除去の正規表現**: `^[A-Za-z0-9_/-]+:[[:space:]]+` を sed で除去。Issue title が必ず該当形式とは限らないため、マッチしなければ無変換
- **既存ユーザへの適用**: template 変更は `./install.sh` を再実行することで反映される。PR 本文に手順を明記
- **タイムアウト 5000ms の妥当性**: `gh issue view` がネットワーク遅延込みで 1-3 秒、余裕を見て 5 秒。既存 `PermissionRequest` hook と同値で一貫性を保つ
- **hook 失敗時の安全性**: hook が空出力で終わると Claude Code 側は既存セッション名を保持する。`set -eu` を使わないのは、jq 失敗・gh 失敗で hook 全体が落ちて意図しない side effect が出るのを避けるため
- **CI への影響**: 新規 bats ファイルは `.github/workflows/test.yml` の `bats --jobs $(nproc) tests/` に自動で含まれる。CI 設定変更は不要
