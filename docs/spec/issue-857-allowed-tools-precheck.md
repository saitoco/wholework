# Issue #857: spec/code: SKILL.md と allowed-tools の差分を事前検出

## Overview

`/code` の実装中、SKILL.md body に新たな `${CLAUDE_PLUGIN_ROOT}/scripts/*` 参照が追加されると、対応する allowed-tools エントリが漏れることがある。既存の `validate-skill-syntax.py` は Step 9 最終 validate 時にしかこれを検出しないため、中間 commit 後に rework が発生する (#852 事例)。

本 Issue は、中間 commit **前** に SKILL.md body と allowed-tools の差分を検出するスクリプト `scripts/check-allowed-tools.sh` を追加し、`/code` Step 8 にプレコミットチェックとして組み込む。既存の `validate_body_scripts_in_allowed_tools` 関数 (line 695) を重複なく活用する。

## Consumed Comments

- `saito` (MEMBER, first-class, 2026-06-30T05:30:02Z): Issue Retrospective — 既存実装の事前調査結果、AC 更新内容、Auto-Resolve Log を記録。Option B (中間 commit 前チェック) 選択確認。

## Changed Files

- `scripts/check-allowed-tools.sh`: 新規スクリプト — SKILL.md body 参照と allowed-tools の差分検出 (bash 3.2+ 互換)
- `skills/code/SKILL.md`: Step 8 に `#### Allowed-tools Pre-commit Check` サブセクションを追加; allowed-tools フロントマターに `${CLAUDE_PLUGIN_ROOT}/scripts/check-allowed-tools.sh:*` を追加 (bash 3.2+ 互換)
- `tests/check-allowed-tools.bats`: 新規 bats テスト — `check-allowed-tools.sh` の呼び出しパスを検証
- `docs/structure.md`: scripts カウント "60 files" → "61 files"; tests カウント "91 files" → "92 files"; Tooling セクションに `check-allowed-tools.sh` エントリを追加
- `docs/ja/structure.md`: `docs/structure.md` 変更の日本語同期

## Implementation Steps

1. `scripts/check-allowed-tools.sh` を新規作成 (→ AC1, AC2)
   - Usage: `check-allowed-tools.sh [skill-dir]` (省略時: `skills/`)
   - `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` で validator パスを解決
   - `VALIDATOR="$SCRIPT_DIR/validate-skill-syntax.py"` が存在しない場合は exit 0
   - `output=$(python3 "$VALIDATOR" "$SKILL_DIR" 2>&1) || true` でバリデーター出力を取得
   - `mismatches=$(printf '%s\n' "$output" | grep "allowed-tools の Bash" || true)` で差分エラーを抽出
   - `$mismatches` が空でなければ `stderr` に警告を出力して exit 1; なければ exit 0
   - bash 3.2+ 互換 (mapfile 等の bash 4+ 機能を使わない)

2. `skills/code/SKILL.md` を更新 (→ AC1, Step 8)
   - **Step 8 本文**: `#### Stale Test Assertion Check` の直前に `#### Allowed-tools Pre-commit Check` サブセクションを挿入
     ```
     #### Allowed-tools Pre-commit Check

     If `scripts/validate-skill-syntax.py` exists and the current step modifies a SKILL.md file, before making the intermediate commit run:

     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-allowed-tools.sh skills/
     ```

     If the script exits non-zero, fix the allowed-tools mismatch before committing.
     ```
   - **allowed-tools フロントマター**: 既存エントリリストに `${CLAUDE_PLUGIN_ROOT}/scripts/check-allowed-tools.sh:*` を追加 (例: `${CLAUDE_PLUGIN_ROOT}/scripts/test-failure-classify.sh:*` の後)

3. `tests/check-allowed-tools.bats` を新規作成 (→ AC3, AC4)
   - `tests/_template.bats` を参考に `PROJECT_ROOT` と `SCRIPT` を定義
   - `setup()` で `MOCK_DIR="$BATS_TEST_TMPDIR/mocks"` を作成し `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定
   - テストケース 1: `validate-skill-syntax.py` が "allowed-tools の Bash(...) パターンに含まれていません" を含む出力で exit 1 → スクリプトが exit 1 かつ stderr に "Warning" を出力することを assert
   - テストケース 2: `validate-skill-syntax.py` が "0 error(s)" で exit 0 → スクリプトが exit 0 を返すことを assert
   - テストケース 3: `WHOLEWORK_SCRIPT_DIR` が空ディレクトリを指す (validator 不在) → スクリプトが exit 0 を返すことを assert

4. `docs/structure.md` と `docs/ja/structure.md` を更新 (→ SHOULD)
   - `docs/structure.md`:
     - "60 files" → "61 files" (scripts カウント)
     - "91 files" → "92 files" (tests カウント)
     - Tooling セクションに追加: `- \`scripts/check-allowed-tools.sh\` — detect SKILL.md body-to-allowed-tools mismatches before intermediate commits; called from \`skills/code/SKILL.md\` Step 8`
   - `docs/ja/structure.md`: 同内容を日本語でミラー更新

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/、.claude/hooks/、または skills/ 配下の実装により、SKILL.md body の ${CLAUDE_PLUGIN_ROOT}/scripts/* 参照と allowed-tools Bash エントリとの差分が中間 commit 前 (もしくは /spec 実行時) に検出される。既存の validate_body_scripts_in_allowed_tools 関数 (scripts/validate-skill-syntax.py line 695) を重複させずに活用していることが望ましい" --> 差分検出の仕組みが実装されている
- <!-- verify: rubric "上記検査が差分を検出した場合、stderr 出力もしくは exit code 非ゼロ等で開発者に通知される実装になっている" --> 差分検出時に通知される
- <!-- verify: rubric "tests/ 配下に、新たに追加したトリガー・統合点が allowed-tools 漏れを検出することを assert するテストが追加されている (既存の tests/validate-skill-syntax.bats lines 310-340 の関数レベルテストとは別に、新しい呼び出しパスを検証するテストが存在する)" --> 新しい呼び出しパスを検証するテストが存在する
- <!-- verify: command "bats tests/" --> 全 bats テストが通過する

### Post-merge

- 次回 SKILL.md 改修を伴う Issue (例: `/code` 実装で新規 script 呼び出しを追加) で、検査が中間 commit 前に発火し validate-skill-syntax.py での rework が発生しなかったことを観察

## Notes

- `validate-skill-syntax.py` の出力フィルタパターン: `"allowed-tools の Bash"` — この文字列は `validate_body_scripts_in_allowed_tools` 関数 (line 695) の日本語エラーメッセージ `本文中に参照されたスクリプト '...' が allowed-tools の Bash(...) パターンに含まれていません` に含まれる一意な部分
- `WHOLEWORK_SCRIPT_DIR` モック: bats テストは `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定し `$MOCK_DIR/validate-skill-syntax.py` にモックを配置する。`check-allowed-tools.sh` は `$WHOLEWORK_SCRIPT_DIR` を使って validator パスを解決するため、既存 mocking convention と一致する
- `/spec` 時点での既存チェック (`skills/spec/SKILL.md` Step 10 allowed-tools impact chain check) は**新規** `scripts/*.sh` ファイル追加のみを対象とし、既存スクリプトの新規参照は対象外。本実装はこのギャップを `/code` Step 8 で補完する
- 実装行数スコープ (測定時点: `scripts/` ディレクトリ, `ls` コマンド出力): 現在 60 ファイル + `git-hooks/` ディレクトリ = 61 エントリ → 新規 1 ファイル追加で 61 ファイル + `git-hooks/` = 62 エントリ; `docs/structure.md` の "60 files" 表記は ディレクトリを除いたファイル数 (git-hooks/ サブディレクトリ 1 個を除く)

## Code Retrospective

### Deviations from Design

- N/A (Spec の実装ステップに従い、差分なし)

### Design Gaps/Ambiguities

- `$stderr` キャプチャの bats 構文: bats 1.13.0 では `run --separate-stderr` が必要。Spec ではこの点が未記載だったが、既存テスト (`tests/check-file-overlap.bats`) を参照して `bats_require_minimum_version 1.5.0` と `--separate-stderr` を追加した
- `docs/ja/structure.md` のファイルカウントが英語版よりも +2 先行していた (62 ファイル vs 60 ファイル) が、既存の drift であり本 PR では delta (+1) を適用するに留めた

### Rework

- 初回の bats テストで `$stderr` が空になる問題が発生。`run` を `run --separate-stderr` に変更することで解決。1ステップ修正のみで完了

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST issues なし; 全 4 受け入れ条件 PASS
- `review-light` エージェントが実行環境で未登録のため、エージェント定義 (`agents/review-light.md`) を直接読み込み手動レビューとして実施
- CI 全ジョブ SUCCESS を確認済み

### Deferred Items
- Post-merge 観察 AC (observation event `auto-run`) は merge 後の次回 SKILL.md 改修 Issue で観察
- `docs/ja/structure.md` と英語版のファイルカウント差分 (+2) は pre-existing drift として未修正

### Notes for Next Phase
- MUST issues なし; `/merge 874` 実行可能
- `bats tests/` 全 1041 テスト通過 (CI 確認済み)
- `validate-skill-syntax.py` warnings: `loop-paths-fallback` (既存、本 PR 無関係)

## spec retrospective

### Minor observations

- Issue body の "tests/validate-skill-syntax.bats lines 310-340" 記述は実際には lines 310-356 (実装上の差異、影響なし)
- `/spec` 側の既存チェック (Step 10 allowed-tools impact chain check) は新規スクリプトのみ対象であり、既存スクリプトの新規参照を検出しない点は Spec Notes に記録

### Judgment rationale

- Option B (中間 commit 前スクリプト追加) を選択: Issue body の "B が最も自動化親和性が高い" との記述 + Issue Retrospective の Auto-Resolve Log より確定
- `check-allowed-tools.sh` として独立スクリプトを作成: bats テスト可能性と呼び出しパスの明確化のため。validate-skill-syntax.py の直接呼び出しではなく、ラッパースクリプト経由にすることで新しい呼び出しパスが明確になり AC3 を満たせる

### Uncertainty resolution

- `validate-skill-syntax.py` の出力フォーマット確認: "が allowed-tools の Bash" という文字列が `validate_body_scripts_in_allowed_tools` エラーメッセージに含まれることを line 718-722 で確認済み (`script_path_pattern not in allowed_tools` → `f"... が allowed-tools の Bash(...) パターンに含まれていません"`)

## review retrospective

### Spec vs. implementation divergence patterns

- Nothing to note. 実装は Spec の 4 ステップと完全に一致。Spec 記載の変更ファイルがすべて PR に含まれていた。

### Recurring issues

- Nothing to note. 今回の PR は単機能追加 (check-allowed-tools.sh) のみ; 繰り返しパターンなし。

### Acceptance criteria verification difficulty

- `rubric` 条件は `validate-skill-syntax.py` の内部実装 (line 695 `validate_body_scripts_in_allowed_tools`) を参照しており、ソースコードを読まないと検証困難。次回 rubric 記述時は実装の参照可能な部分 (ファイルパス、関数名) を明示することで AI 検証の精度が上がる。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- スカッシュマージで PR #874 を main に統合: `check-allowed-tools.sh` の単機能追加 PR であり、コンフリクトなし・CI 通過・レビュー承認済みのクリーン状態だったため直接 Step 4 へ進んだ
- ブランチ削除 (`--delete-branch`): PR マージ後にリモートブランチ `worktree-code+issue-857` を削除済み
- Phase Handoff は review フェーズの事前ハンドオフなし: Spec に `## Phase Handoff` セクションが存在しなかったため新規書き込みのみ実施

### Deferred Items
- Post-merge 観察: 次回 SKILL.md 改修を伴う Issue で `check-allowed-tools.sh` が中間 commit 前に発火するか観察 (Spec § Post-merge 記載)
- verify フェーズで `bats tests/` 全テスト通過と `scripts/check-allowed-tools.sh` の差分検出動作を確認

### Notes for Next Phase
- verify command: `bats tests/` — 全 bats テストが通過することを確認
- `scripts/check-allowed-tools.sh` が `skills/code/SKILL.md` Step 8 の Allowed-tools Pre-commit Check サブセクションに統合されていることを確認
- `tests/check-allowed-tools.bats` に 3 ケース (正常/差分検出/引数エラー) が含まれていることを確認
- `command "bats tests/"` は safe mode では CI 参照フォールバックが必要; CI が SUCCESS であることが前提。CI 未完了の場合は PENDING になる点を注意 (今回は問題なし)。
