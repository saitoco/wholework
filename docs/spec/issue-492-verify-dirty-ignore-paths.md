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

## Code Retrospective

### Deviations from Design

- `git status --short` を `git status --short --untracked-files=all` に変更: Spec の実装例は `git status --short` を使用していたが、未追跡ディレクトリが `vault/` のように単一エントリとして表示されるため、`vault/.obsidian/**` 等のサブパターンがマッチしない問題が発生。`--untracked-files=all` で個別ファイル表示に変更した
- `_is_ignored` にディレクトリエントリ（トレーリングスラッシュ）のストリップ処理を追加: `--untracked-files=all` 採用後は主にファイル単位で表示されるが、念のため `file_stripped="${file%/}"` でトレーリングスラッシュを除去し、`pfx==file_stripped` の exact match も追加した
- bats テストの `git commit` 追加: Spec の擬似コードにはなかったが、`.wholework.yml` 自体がテスト内で untracked として dirty 扱いされることを防ぐため `git add && git commit` をテスト内に追加した
- bats テストのアサーション変更: Spec は `[ "$output" = "" ]`（警告は stderr のため stdout 空）と想定していたが、bats 1.13.0 では `run` が stdout/stderr を `$output` に合算するため、`[[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]` に変更した

### Design Gaps/Ambiguities

- Spec の Note「bats では run コマンドは stdout のみキャプチャする」は bats < 1.7 の挙動。bats 1.7+ (1.13.0 実環境) では stdout/stderr が合算される。Spec の注記が古かった
- 未追跡ディレクトリのエントリ表示 (`vault/`) の挙動が Spec で考慮されていなかった。`--untracked-files=all` で解決

### Rework

- テスト 3 件（7, 9, 10）が初回テスト実行で失敗: `git status` の表示形式の問題（ディレクトリ単位表示）と bats の出力合算の問題が原因。スクリプト修正とテストアサーション修正で対応した

## review retrospective

### Spec vs. 実装の乖離パターン

Spec と PR diff の間に構造的な乖離なし。`--untracked-files=all` への変更・bats テストのアサーション変更は Code Retrospective に記録済みで、review 時点で把握済みの逸脱。

### 繰り返し問題

同種の問題は検出されなかった。

### 受け入れ基準検証の難度

- 4 件の `file_contains` AC はすべて明確で検証容易。
- `github_check "Run bats tests"` AC は初回実行時未チェックだったが、CI 完了後に PASS を確認してチェックボックスを更新した。
- `_is_ignored` が "gitignore format" と宣伝しているにもかかわらず bash `case` グロブの制約で中間 `**` がサポートされない点は、将来の verify command 追加時に注意が必要（CONSIDER として inline comment を投稿済み）。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #531 を `main` ブランチへスカッシュマージ（`gh pr merge --squash --delete-branch`）
- `mergeable=true, ci_status=success, review_status=approved` — コンフリクトなし、テストスキップ（CI 通過済み）
- `closes #492` が PR body に含まれるため、`main` マージにより Issue #492 は自動クローズ

### Deferred Items
- SHOULD: `check-verify-dirty.sh` のYAMLパターン末尾空白トリム未対応（通常のYAML編集では発生しにくいためスキップ判断）
- CONSIDER: detect-config-markers.md への `VERIFY_IGNORE_PATHS` コンシューマ補足の追加
- CONSIDER: docs/guide/customization.md の "silently" 表現修正（日本語版は正確）

### Notes for Next Phase
- post-merge AC: trading リポジトリの `.wholework.yml` に `verify-ignore-paths: ["vault/**"]` を設定し、`vault/` のみ dirty な状態で `/auto N` の verify フェーズが警告のみで継続することを手動確認する
- pre-merge verify command は全 PASS 済み（CI bats tests SUCCESS 含む）
- None of the deferred SHOULD/CONSIDER items are blocking for verify

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件は明確で検証容易（4件の `file_contains` + 1件の `github_check`）。`/issue` 段階で bats テストファイル名の誤り（`check-verify-dirty.bats` → 実在の `verify-dirty-detection.bats`）を実ファイル確認で修正済みで、spec/code に正しいパスが伝播した。
- パス解決方式（スクリプト直接パース）を Auto-Resolved Ambiguity Points で事前確定したことで、code フェーズで `/verify` SKILL.md を変更せず済んだ。

#### design
- 設計は概ね妥当だが、環境固有挙動の見落としで2点のギャップが code フェーズで顕在化:
  - `git status --short` が未追跡ディレクトリを単一エントリ（`vault/`）で表示するため `vault/.obsidian/**` 等のサブパターンがマッチしない → `--untracked-files=all` で解決
  - bats 1.7+ では `run` が stdout/stderr を `$output` に合算する（Spec の注記は bats <1.7 の古い挙動）→ アサーションを stderr 文字列マッチに変更
- 設計段階で検証環境（git/bats）のバージョン挙動を確認していれば事前に防げた可能性。

#### code
- テスト3件（test 7/9/10）が初回失敗 → スクリプト（`--untracked-files=all`、トレーリングスラッシュ処理）とテストアサーション修正で対応。design ギャップ起因で本質的な手戻りではない。
- bash 3.2 互換（配列・`[[ =~ ]]`・`case` glob、`mapfile` 不使用、`set -u` 下の空配列展開ガード）を維持。

#### review
- light レビューで MUST 問題なし。`_is_ignored` が "gitignore format" を称するが bash `case` glob では中間 `**` 非対応である点を CONSIDER として inline コメント投稿。
- Spec vs 実装の乖離は Code Retrospective に記録済みで、review 時点で把握済みの逸脱。

#### merge
- スカッシュマージ（`--squash --delete-branch`）。コンフリクトなし、CI 通過済み。問題なし。

#### verify
- 全 pre-merge AC（5件）が PASS。決定的検証（`file_contains`/`github_check`）に加え、ローカル bats 実行で新規シナリオ4件（vault のみ→exit 0 / vault+scripts→exit 1 / `.obsidian`→exit 0 / unrelated spec→exit 2 回帰）の実挙動を確認。FAIL/UNCERTAIN なし。
- post-merge AC（trading 実プロジェクトでの目視確認）は外部 private repo 依存のため初回 verify では manual deferred（`phase/verify` 保留）。その後ユーザーが下流プロジェクトで `verify-ignore-paths` を設定し動作確認、`/verify 492` 再実行で当該条件を PASS としてチェック → 全条件 PASS で `phase/done` 遷移・完了。外部リポジトリ依存の manual 条件が「ユーザー確認 → /verify 再実行」フローで正しくクローズできることを確認。

### Improvement Proposals
- **`verify-ignore-paths` の glob セマンティクス明確化**: ドキュメント（`customization.md`）が "gitignore format" を称するが、実装は `dir/**` プレフィックス形式と単純 `case` glob のみ対応で、gitignore の中間 `**`（`a/**/b`）や否定（`!`）は非対応。ドキュメント表現を実サポート範囲に合わせて修正するか、対応グロブ範囲を明記すべき（review で CONSIDER 投稿済み）。
- **検証環境バージョン依存の Spec 注記の鮮度**: bats の `run` 出力挙動（<1.7 vs 1.7+）の注記が古く code で手戻りを誘発。Spec で外部ツール挙動を前提にする場合は実環境バージョンの確認を推奨。
- いずれも非ブロッキング。Phase Handoff の deferred SHOULD（YAML パターン末尾空白トリム）/ CONSIDER（detect-config-markers コンシューマ補足、customization.md "silently" 表現）も軽微。
