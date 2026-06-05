# Issue #492: check-verify-dirty: Add Verify-Scope-Exclusion Mechanism for Obsidian vault etc.

## Overview

`/auto` の verify フェーズで `check-verify-dirty.sh` が実行される際、ワークフロー外で自動編集されるファイル（Obsidian vault、エディタ UI 状態ファイル等）が dirty 状態だと non-interactive モードで hard error となり verify が中断する。

`.wholework.yml` に `verify-ignore-paths` キー（`.gitignore` 形式の glob リスト）を追加し、マッチするファイルを dirty 判定から除外する。除外後にすべての dirty ファイルが消えた場合は警告（stderr）を出力して exit 0 で継続する。`verify-ignore-paths` 未設定時は既存動作を完全に維持する。

## Changed Files

- `modules/detect-config-markers.md`: marker 定義テーブルに `verify-ignore-paths` 行を追加（Variable: `VERIFY_IGNORE_PATHS`、block list 形式、default: `""`）
- `docs/guide/customization.md`: Available Keys テーブルに `verify-ignore-paths` 行を追加、YAML サンプルブロックにも例示
- `docs/ja/guide/customization.md`: 上記の日本語ミラーを同期更新
- `scripts/check-verify-dirty.sh`: `.wholework.yml` から `verify-ignore-paths` を直接パースし、マッチするファイルを dirty 分類前に除外するフィルタを追加 — bash 3.2+ 互換
- `tests/verify-dirty-detection.bats`: `verify-ignore-paths` 設定時の 3 シナリオをカバーする `@test` を追加

## Implementation Steps

1. **`modules/detect-config-markers.md` 更新**（→ AC1）
   - Marker 定義テーブルの `patch-lock-timeout` 行の後に以下の行を追加:
     `| verify-ignore-paths | VERIFY_IGNORE_PATHS | Newline-separated glob pattern list | "" |`
   - YAML Parsing Rules セクションに補足: `verify-ignore-paths` は block 形式リスト（`- pattern`）。`capabilities.mcp` と同じ流儀でパース。未設定または空リストの場合は `VERIFY_IGNORE_PATHS=""`

2. **`docs/guide/customization.md` 更新**（→ AC2）
   - YAML サンプルブロック（`capabilities:` ブロックの前）に以下を追加:
     ```yaml
     # Paths excluded from dirty-file detection during /verify (gitignore-style glob list)
     verify-ignore-paths:
       - vault/**
       - vault/.obsidian/**
     ```
   - Available Keys テーブルに行追加（`patch-lock-timeout` 行の後）:
     `| verify-ignore-paths | list | [] | Glob patterns (gitignore format, block list) of paths to exclude from dirty-file detection in /verify. Files matching any pattern are silently ignored and reported on stderr. Unset means no exclusions. |`

3. **`docs/ja/guide/customization.md` 同期**（Step 2 と並行可能）
   - Step 2 の変更を日本語で翻訳・反映。キー名・型・デフォルト値は英語のまま維持

4. **`scripts/check-verify-dirty.sh` 更新**（→ AC3）
   既存コードの「Clean working directory」チェック（`if [[ ${#dirty_files[@]} -eq 0 ]]; then exit 0; fi`）の直後に以下を挿入:

   a. `.wholework.yml` から `verify-ignore-paths` を直接パース（block list 形式）:
   ```bash
   ignore_patterns=()
   if [[ -f ".wholework.yml" ]]; then
     in_section=false
     while IFS= read -r line; do
       case "$line" in \#*) continue ;; esac
       if [[ "$line" =~ ^verify-ignore-paths[[:space:]]*: ]]; then
         in_section=true; continue
       fi
       if $in_section; then
         if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
           p="${BASH_REMATCH[1]//\'/}"; p="${p//\"/}"
           ignore_patterns+=("$p")
         elif [[ "$line" =~ ^[^[:space:]] ]]; then
           in_section=false
         fi
       fi
     done < ".wholework.yml"
   fi
   ```

   b. glob マッチ関数を追加:
   ```bash
   _is_ignored() {
     local file="$1" pat
     for pat in "${ignore_patterns[@]+"${ignore_patterns[@]}"}"; do
       if [[ "$pat" == *"/**" ]]; then
         local pfx="${pat%/**}"
         [[ "$file" == "$pfx/"* ]] && return 0
       else
         case "$file" in $pat) return 0 ;; esac
       fi
     done
     return 1
   }
   ```

   c. 除外フィルタを適用し、`dirty_files` を更新:
   ```bash
   ignored_files=()
   filtered=()
   for f in "${dirty_files[@]}"; do
     if _is_ignored "$f"; then ignored_files+=("$f")
     else filtered+=("$f"); fi
   done
   if [[ ${#ignored_files[@]} -gt 0 ]]; then
     for f in "${ignored_files[@]}"; do
       echo "Warning: ignoring dirty file excluded by verify-ignore-paths: $f" >&2
     done
     if [[ ${#filtered[@]} -eq 0 ]]; then exit 0; fi
     dirty_files=("${filtered[@]}")
   fi
   ```

5. **`tests/verify-dirty-detection.bats` 更新**（→ AC4）
   既存テストの末尾に以下 3 ケースを追加:
   - `@test "verify-ignore-paths: vault only dirty -> exit 0 with warning"` — `.wholework.yml` に `verify-ignore-paths:\n  - vault/**` を作成し `vault/knowledge/note.md` を dirty にする。`run bash "$REAL_SCRIPT" 123` → `[ "$status" -eq 0 ]`、`[ "$output" = "" ]`（警告は stderr のため stdout 空）
   - `@test "verify-ignore-paths: vault and scripts both dirty -> exit 1"` — 同 `.wholework.yml` で `vault/note.md` と `scripts/foo.sh` の両方を dirty にする。`[ "$status" -eq 1 ]`
   - `@test "verify-ignore-paths: .obsidian workspace dirty -> exit 0"` — `.wholework.yml` に `verify-ignore-paths:\n  - vault/.obsidian/**` を作成し `vault/.obsidian/workspace.json` を dirty にする。`[ "$status" -eq 0 ]`

## Verification

### Pre-merge
- <!-- verify: file_contains "modules/detect-config-markers.md" "verify-ignore-paths" --> `detect-config-markers.md` の marker 定義テーブルに `verify-ignore-paths` 行が追加されている
- <!-- verify: file_contains "docs/guide/customization.md" "verify-ignore-paths" --> `docs/guide/customization.md` に `verify-ignore-paths` の説明が追加されている
- <!-- verify: file_contains "scripts/check-verify-dirty.sh" "verify-ignore-paths" --> `check-verify-dirty.sh` が `verify-ignore-paths` 設定を解決し除外フィルタリングを行う
- <!-- verify: file_contains "tests/verify-dirty-detection.bats" "verify-ignore-paths" --> `tests/verify-dirty-detection.bats` が拡張され新シナリオを検証する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが全て通過する

### Post-merge
- 実プロジェクト（trading 等）の `.wholework.yml` に `verify-ignore-paths: [\"vault/**\"]` を設定し、`vault/` のみが dirty な状態で `/auto N` の verify フェーズが警告のみで継続することを目視確認する

## Notes

- **パス解決方式**: `check-verify-dirty.sh` が `.wholework.yml` を直接インラインパースする方式を採用。呼び出し元の `/verify` SKILL.md を変更する必要がない（exit 0 の扱いは変わらないため）。この判断は Issue Auto-Resolved Ambiguity Points にも記録済み。
- **bash 3.2 互換**: 配列（`ignore_patterns+=`）、`[[ =~ ]]`、`${BASH_REMATCH[1]}`、`case` glob はすべて bash 3.2+ で動作。`mapfile` 不使用。
- **glob マッチ**: `/**` サフィックスのパターンはプレフィックスチェック（`$pfx/`）で処理。それ以外は bash `case` のパターンマッチを使用。`**` の完全な再帰展開は不要（主要ユースケースは `dir/**` 形式）。
- **警告出力先**: stderr に出力（exit 2 時に stdout へ出力する spec ファイルパスと混線しないため）。bats では `run` コマンドは stdout のみキャプチャするため、新テストは `[ "$output" = "" ]` で exit 0 の stdout 空を確認する。
- **`verify-ignore-paths` 未設定時**: `ignore_patterns` 配列が空になるため `_is_ignored` は常に return 1。`ignored_files` も空で既存分類に影響なし。
- **`${ignore_patterns[@]+"${ignore_patterns[@]}"}` パターン**: bash の `set -u` 下での空配列展開エラー回避（bash 3.2 で `"${arr[@]}"` が空配列で unbound variable エラーになる場合の対策）。
- **文字列マッチ verify command 確認**: 4つの `file_contains` verify command はすべて実装により新たに追加される文字列を対象とする（現時点では存在しない）。実装時に確認が必要。
