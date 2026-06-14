# Issue #486: review: 削除系 PR で PR ブランチの状態を参照してファイル検証の false positive を防止

## Overview

`modules/verify-executor.md` の file 系コマンドに `PR_BRANCH` 環境変数サポートを追加する。`PR_BRANCH` が設定されている場合、`file_exists` / `file_not_exists` / `file_contains` / `file_not_contains` / `grep` コマンドはローカルファイルシステムの代わりに `git show origin/<PR_BRANCH>:<path>` を使って PR ブランチのファイル状態を参照する。これにより、削除系 PR レビュー時に `/review` が `main` ブランチのファイルを誤って参照して FAIL 判定（false positive）が発生する問題を防ぐ。

`skills/review/SKILL.md` Step 8 では `PR_BRANCH: $headRefName` を verify-executor 呼び出しのコンテキストに追加することで、この機能を実際に機能させる。

## Changed Files

- `modules/verify-executor.md`: Input セクションに `PR_BRANCH`（optional）を追加、処理テーブルの `file_exists` / `file_not_exists` / `file_contains` / `file_not_contains` / `grep` を PR_BRANCH 対応に更新
- `skills/review/SKILL.md`: Step 8 の verify-executor 呼び出しコンテキストに `PR_BRANCH: $headRefName` を追加

## Implementation Steps

1. `modules/verify-executor.md` の `## Input` セクションに `PR_BRANCH`（optional）を追加 (→ AC 1, 4)
   - 内容: "**PR branch name** (optional): PR ブランチ名。設定されている場合、file 系コマンドはローカルファイルシステムの代わりに `git show origin/<PR_BRANCH>:<path>` でファイルを読む。未設定時は従来のローカルファイルシステム参照にフォールバック"

2. `modules/verify-executor.md` の処理テーブルで `file_exists` / `file_not_exists` / `file_contains` / `file_not_contains` / `grep` の各行を PR_BRANCH 対応に更新 (→ AC 1, 2, 3, 4)

   **更新方針（全コマンド共通）:**
   - `PR_BRANCH` が設定されている場合: `git show origin/<PR_BRANCH>:<path>` でファイル内容を取得
   - `PR_BRANCH` が未設定の場合: 従来のローカルファイルシステム参照（後方互換）

   **コマンド別の `PR_BRANCH` 設定時の挙動:**
   - `file_exists`: `git show origin/<PR_BRANCH>:<path>` が exit 0 → PASS、error → FAIL
   - `file_not_exists`: `git show origin/<PR_BRANCH>:<path>` が error（ファイルが削除されている）→ PASS、exit 0 → FAIL
   - `file_contains`: `git show origin/<PR_BRANCH>:<path>` の出力に "text" が含まれる → PASS、含まれない → FAIL。`git show` error（ファイル削除）→ FAIL
   - `file_not_contains`: `git show origin/<PR_BRANCH>:<path>` の出力に "text" が含まれない → PASS、含まれる → FAIL。`git show` error（ファイル削除）→ PASS（ファイルが存在しない = テキストも存在しない）
   - `grep`: `git show origin/<PR_BRANCH>:<path>` の出力をパターンマッチ → 一致 PASS、不一致 FAIL。`git show` error → FAIL

3. `skills/review/SKILL.md` Step 8 の `Read ... modules/verify-executor.md` 呼び出し行に `PR_BRANCH: $headRefName` を追加 (→ post-merge AC)
   - 変更前: "Mode: **safe**, PR number: `$NUMBER`"
   - 変更後: "Mode: **safe**, PR number: `$NUMBER`, PR_BRANCH: `$headRefName`"

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "PR_BRANCH" --> `modules/verify-executor.md` に `PR_BRANCH` 環境変数を参照する分岐処理が追加されている
- <!-- verify: grep "git show" "modules/verify-executor.md" --> file 系コマンドが `git show` を使って PR ブランチのファイル状態を読む処理が記述されている
- <!-- verify: rubric "verify-executor.md の file_not_exists / file_not_contains コマンドで PR_BRANCH 設定時に git show origin/<branch>:<file> がエラー（ファイルが削除されている）を返した場合に PASS を返すロジックが含まれている" --> 削除済みファイルへの `file_not_exists` / `file_not_contains` が PASS を返す処理がある
- <!-- verify: rubric "verify-executor.md の file 系コマンドで PR_BRANCH が未設定の場合はローカルファイルシステムを参照する従来の動作（後方互換フォールバック）が維持されている" --> `PR_BRANCH` 未設定時はローカルファイルシステム参照にフォールバックする（後方互換）

### Post-merge

- 削除系 PR（`file_not_exists` / `file_not_contains` AC を含む PR）を実際にレビューし、FALSE POSITIVE が発生しないことを確認

## Notes

- `git show origin/<PR_BRANCH>:<path>` はリモート fetch 済みのブランチ状態を参照する（review SKILL.md Step 2 で `git fetch origin "$headRefName"` を実施済み）
- `git show` がエラーになるケース: ファイルが PR ブランチで削除されている、またはパスが存在しない。これは `file_not_exists` の成功条件として扱う
- review SKILL.md Step 2 では既に `git checkout "$headRefName"` でローカルファイルシステムを PR ブランチ状態に切り替えているが、`git show` 方式は checkout が行われていない環境でも機能する補完的な安全策となる
- Auto-Resolve Log (Issue #486 本文より転載):
  - **案 1 を採用**: verify-executor.md に PR_BRANCH 判定を追加（後方互換・必要時のみ PR ブランチ参照）
  - **対象コマンド**: file_exists / file_not_exists / file_contains / file_not_contains / grep の 5 種類（command・http_status・github_check 等はファイル読み取り非依存のため対象外）
