# Issue #113: auto: フェーズ開始・終了時の Issue/PR 識別情報表示を shared module で正規化

## Overview

`run-*.sh` スクリプト（7 本）と SKILL.md スキル（8 本）のフェーズ開始・終了時に、Issue/PR のタイトルと URL を表示する。ロジックは shared module (`modules/phase-banner.md`) と shell helper (`scripts/phase-banner.sh`) で正規化する。

## Changed Files
- `scripts/phase-banner.sh`: new file — shell helper (source 用。`print_start_banner` / `print_end_banner` 関数を提供)
- `modules/phase-banner.md`: new file — SKILL.md 向け shared module (フォーマット定義 + 処理手順)
- `scripts/run-issue.sh`: source helper, Starting/Finished で関数呼び出し追加
- `scripts/run-spec.sh`: same
- `scripts/run-code.sh`: same
- `scripts/run-verify.sh`: same
- `scripts/run-auto-sub.sh`: same (entity_type=issue)
- `scripts/run-review.sh`: same (entity_type=pr)
- `scripts/run-merge.sh`: same (entity_type=pr)
- `skills/issue/SKILL.md`: "Read phase-banner.md" instruction を Step 1 冒頭に追加 (Existing Issue Refinement: Step 1 fetch 直後、New Issue Creation: Step 1 冒頭)
- `skills/spec/SKILL.md`: Step 1 Fetch Issue Information 直後に追加
- `skills/code/SKILL.md`: Step 0 Route Detection の番号抽出直後に追加
- `skills/verify/SKILL.md`: Step 1 直後に追加
- `skills/triage/SKILL.md`: Step 1 直後に追加 (Single Execution のみ、Bulk Execution は対象外)
- `skills/auto/SKILL.md`: Step 1 Extract Issue Number 直後に追加
- `skills/review/SKILL.md`: Step 1 Fetch PR Information 直後に追加 (entity_type=pr)
- `skills/merge/SKILL.md`: Step 1 Check PR State 直後に追加 (entity_type=pr)
- `tests/run-code.bats`: setup() に `gh` mock 追加 (title/URL 返却)
- `tests/run-issue.bats`: same
- `tests/run-verify.bats`: same
- `tests/run-merge.bats`: same (PR variant)
- `tests/run-review.bats`: same (PR variant)
- `docs/structure.md`: Modules セクションに `phase-banner.md` 追加、Scripts セクションに `phase-banner.sh` 追加

## Implementation Steps

1. Create `scripts/phase-banner.sh` (→ acceptance criteria A2, A6, A7)

   ```bash
   #!/bin/bash
   # phase-banner.sh — sourceable helper for run-*.sh phase banner display
   # Usage: source this file, then call print_start_banner / print_end_banner

   # Fetch and cache title/URL for the given entity
   # Args: entity_type ("issue"|"pr"), entity_number
   _fetch_entity_info() {
     local entity_type="$1" entity_number="$2"
     if [[ "$entity_type" == "pr" ]]; then
       _ENTITY_TITLE=$(gh pr view "$entity_number" --json title -q '.title' 2>/dev/null || echo "")
       _ENTITY_URL=$(gh pr view "$entity_number" --json url -q '.url' 2>/dev/null || echo "")
     else
       _ENTITY_TITLE=$(gh issue view "$entity_number" --json title -q '.title' 2>/dev/null || echo "")
       _ENTITY_URL=$(gh issue view "$entity_number" --json url -q '.url' 2>/dev/null || echo "")
     fi
   }

   # Print start banner with title/URL
   # Args: entity_type ("issue"|"pr"), entity_number
   print_start_banner() {
     local entity_type="$1" entity_number="$2"
     _fetch_entity_info "$entity_type" "$entity_number"
     local label; [[ "$entity_type" == "pr" ]] && label="PR" || label="Issue"
     echo "${label}: #${entity_number} ${_ENTITY_TITLE}"
     echo "URL: ${_ENTITY_URL}"
   }

   # Print end banner with cached title/URL
   # Args: entity_type ("issue"|"pr"), entity_number
   print_end_banner() {
     local entity_type="$1" entity_number="$2"
     local label; [[ "$entity_type" == "pr" ]] && label="PR" || label="Issue"
     echo "${label}: #${entity_number} ${_ENTITY_TITLE}"
     echo "URL: ${_ENTITY_URL}"
   }
   ```

   Key design:
   - `_fetch_entity_info` は `print_start_banner` 内で呼ばれ、結果をシェル変数 `_ENTITY_TITLE` / `_ENTITY_URL` にキャッシュ
   - `print_end_banner` はキャッシュを再利用（追加 API call なし）
   - `gh` 失敗時は `2>/dev/null || echo ""` でフォールバック

2. Update 7 `run-*.sh` scripts to source helper and call banner functions (→ acceptance criteria A3)

   **Issue-based scripts (run-issue.sh, run-spec.sh, run-code.sh, run-verify.sh, run-auto-sub.sh)**:
   - `SCRIPT_DIR` 定義の直後（ただし run-issue.sh, run-spec.sh, run-review.sh, run-merge.sh では SCRIPT_DIR がバナー出力より後に定義されているため、バナー出力前に SCRIPT_DIR を前方移動するか、バナー出力後に source する）
   - 実装パターン: SCRIPT_DIR を=== 行の前に移動し、source + print_start_banner を === 行の直後に挿入
   - Starting: `echo "=== ..."` の直後に `source "$SCRIPT_DIR/phase-banner.sh"` + `print_start_banner "issue" "$ISSUE_NUMBER"`
   - Finished: `echo "=== ..."` の直後に `print_end_banner "issue" "$ISSUE_NUMBER"`

   **PR-based scripts (run-review.sh, run-merge.sh)**:
   - Same pattern with `"pr"` and `"$PR_NUMBER"`

   **run-auto-sub.sh**:
   - Same pattern with `"issue"` and `"$SUB_NUMBER"`

3. Create `modules/phase-banner.md` (→ acceptance criteria A1, A4, A5)

   ```markdown
   # phase-banner

   Standardized phase identification banner for skill start.

   ## Purpose
   Display Issue/PR title and URL at skill start for identification.

   ## Input
   - ENTITY_TYPE: "issue" or "pr"
   - ENTITY_NUMBER: Issue or PR number (extracted by calling skill)
   - SKILL_NAME: name of the skill (e.g., "issue", "spec", "review")

   ## Processing Steps
   1. Fetch title and URL:
      - Issue: `gh issue view $N --json title,url`
      - PR: `gh pr view $N --json title,url`
   2. Output banner format (at skill start, after number extraction):
      ```
      --- /SKILL_NAME #N ---
      TITLE
      URL
      ---
      ```
   3. If `gh` command fails, output banner without title/URL (skip silently)

   ## Output
   Phase identification banner displayed to terminal.
   ```

4. Update 8 SKILL.md files to reference phase-banner module (→ acceptance criteria A4, A5)

   Each SKILL.md に以下を挿入（番号抽出直後の位置）:

   **Issue-based (issue, spec, code, verify, triage, auto)**:
   ```
   Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner
   with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="{skill}".
   ```

   **PR-based (review, merge)**:
   ```
   Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner
   with ENTITY_TYPE="pr", ENTITY_NUMBER=$PR_NUMBER, SKILL_NAME="{skill}".
   ```

   **挿入位置 (per skill)**:
   - `/issue`: Existing Issue Refinement Step 1 (`gh issue view`) 直後 / New Issue Creation Step 1 冒頭
   - `/spec`: Step 1 (`gh issue view`) 直後
   - `/code`: Step 0 Route Detection の NUMBER 抽出直後
   - `/verify`: Step 1 直後
   - `/triage`: Single Execution Step 1 直後（Bulk Execution はスキップ — 個別 Issue 番号なし）
   - `/auto`: Step 1 Extract Issue Number 直後
   - `/review`: Step 1 Fetch PR Information 直後
   - `/merge`: Step 1 Check PR State 直後

5. Update 5 test files — add `gh` mock (→ acceptance criteria A8)

   各テストの `setup()` に以下の gh mock を追加:

   **Issue-based (run-code.bats, run-issue.bats, run-verify.bats)**:
   ```bash
   cat > "$MOCK_DIR/gh" <<'MOCK'
   #!/bin/bash
   if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
     echo '{"title":"test issue title","url":"https://github.com/test/repo/issues/123"}'
     exit 0
   fi
   echo ""
   exit 0
   MOCK
   chmod +x "$MOCK_DIR/gh"
   ```

   **PR-based (run-merge.bats, run-review.bats)**:
   ```bash
   cat > "$MOCK_DIR/gh" <<'MOCK'
   #!/bin/bash
   if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json"* ]]; then
     echo '{"title":"test PR title","url":"https://github.com/test/repo/pull/88"}'
     exit 0
   fi
   echo ""
   exit 0
   MOCK
   chmod +x "$MOCK_DIR/gh"
   ```

   Note: `gh` mock は `-q` (jq filter) に対応する必要がある。`run-*.sh` 内の `gh issue view N --json title -q '.title'` は jq フィルタで title のみを返す。mock の出力は JSON 全体ではなく、`-q` が `gh` 側で処理されるため、mock は jq フィルタを無視して全 JSON を返すか、`-q` を検出して適切な値を返す必要がある。

   **修正**: `gh` は `-q` でフィルタリングするため、mock は引数を解析して適切な値を返す:
   ```bash
   if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
     echo "test issue title"
   elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
     echo "https://github.com/test/repo/issues/123"
   fi
   ```

6. Update `docs/structure.md` (→ documentation consistency)
   - Modules セクション: `- modules/phase-banner.md` エントリを追加
   - Scripts セクション: `- scripts/phase-banner.sh` エントリを追加
   - Module count: 23 → 24
   - Script count: 27 → 28

## Alternatives Considered

**A. 各 run-*.sh にインラインで gh 呼び出しを追加（shell helper なし）**
- Pros: 新ファイルが modules/phase-banner.md のみ
- Cons: 同じ gh 呼び出し + echo パターンが 7 ファイルに重複。フォーマット変更時に全ファイル修正
- **不採用**: DRY 原則に反する

**B. run-*.sh 用の module も markdown で書き、run-*.sh がパースする**
- Pros: module 一元管理
- Cons: shell script が markdown をパースする不自然さ。過剰な複雑度
- **不採用**: shell helper (source パターン) が bash の自然なコード共有手段

## Verification

### Pre-merge
- <!-- verify: file_exists "modules/phase-banner.md" --> `modules/phase-banner.md` shared module が作成されている
- <!-- verify: file_exists "scripts/phase-banner.sh" --> `scripts/phase-banner.sh` shell helper が作成されている
- <!-- verify: grep "phase-banner" "scripts/run-code.sh" --> run-*.sh スクリプトが shell helper を参照している（run-code.sh で代表検証）
- <!-- verify: grep "phase-banner" "skills/issue/SKILL.md" --> SKILL.md スキルが shared module を参照している（/issue で代表検証）
- <!-- verify: grep "phase-banner" "skills/review/SKILL.md" --> PR-based スキルも shared module を参照している（/review で代表検証）
- <!-- verify: grep "gh issue view.*title\|gh pr view.*title" "scripts/phase-banner.sh" --> shell helper が Issue/PR タイトルを取得する
- <!-- verify: file_contains "scripts/phase-banner.sh" "URL:" --> shell helper が URL 表示フォーマットを含む
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テストが PASS する

### Post-merge
- `/issue N` 実行時にスキル開始出力に Issue タイトルと URL が表示される
- `/auto N` 実行時に各フェーズの Starting/Finished 出力に Issue/PR タイトルと URL が表示される

## Notes

- **SKILL.md は start banner のみ**: Completion Report が end marker の役割を果たすため、SKILL.md では終了時のバナーは不要
- **run-*.sh は start + end 両方**: 非対話的実行で出力が長いため、Finished 行にもタイトル・URL を表示
- **`/triage` Bulk Execution は対象外**: 個別 Issue 番号を持たないバッチ処理ではバナーを表示しない
- **`/doc`, `/audit` は対象外**: Issue/PR 番号を引数に取らないスキルは不要
- **SCRIPT_DIR の前方移動**: run-issue.sh, run-spec.sh, run-review.sh, run-merge.sh では SCRIPT_DIR がバナー出力位置より後に定義されているため、`=== Starting ===` 行の前に移動する必要がある
- **テストの gh mock**: `phase-banner.sh` が `gh issue/pr view N --json title -q '.title'` を呼ぶため、mock は `-q` 引数を解析して適切な値 (title 文字列 / URL 文字列) を返す必要がある
- **`/issue` の New Issue Creation フロー**: 新規作成では Issue 番号が未確定のため、Step 1 (情報収集) 時点ではバナーを表示できない。Step 6 (Create Issue) 後に表示するか、新規作成フローではスキップする。推奨: 新規作成フローではスキップ（番号確定は作成後で、その後すぐ完了するため）
- **Auto-resolved ambiguity**: shell helper 関数インターフェースは `(entity_type, entity_number)` の 2 引数。SKILL.md は start banner のみ。配置は番号抽出直後。
