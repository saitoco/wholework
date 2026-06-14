# Issue #508: Post-Merge Manual Verification Bundled CLI

## Overview

実機 API 操作を伴う Issue の `phase/verify` 停留を解消するため、複数 Issue の手動 AC をバンドル実行する CLI を `scripts/post_merge_check.sh` として新規作成する。

- 複数 Issue 番号を引数として受け取る
- 各 Issue の Spec (`docs/spec/issue-N-*.md`) から `<!-- verify-type: manual -->` 付き AC を抽出 (Spec 不在時は Issue body にフォールバック)
- 各 AC を表示し `[P]ass/[F]ail/[S]kip` 対話入力を受け付け
- 全 AC PASS の Issue: `phase/verify` → `phase/done` ラベル遷移 + 完了コメント投稿
- FAIL AC がある Issue: `gh issue reopen` + FAIL 詳細コメント追記

Issue body の `## Auto-Resolved Ambiguity Points` セクションに記録済みの解決済み曖昧点:
- **実装アプローチ**: `scripts/post_merge_check.sh` として独立した Bash スクリプト (既存の `scripts/run-*.sh` パターンと整合)
- **Spec vs Issue body 優先順位**: Spec が存在する場合は Spec を優先、存在しない場合は Issue body にフォールバック

## Changed Files

- `scripts/post_merge_check.sh`: new file — bash 3.2+ compatible (→ AC1, AC2, AC3, AC4)
- `tests/post_merge_check.bats`: new test file
- `docs/structure.md`: update scripts count (52→53), tests count (70→71), add script description in Key Files section
- `docs/ja/structure.md`: update scripts count (51→53), tests count (70→71), add script description in Key Files section (translation sync)

## Implementation Steps

1. Create `scripts/post_merge_check.sh` (→ AC1, AC2, AC3, AC4):
   - Header: `#!/bin/bash`, `set -euo pipefail`, `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` pattern
   - Accept one or more issue numbers as positional args; print usage and exit 1 if none given
   - For each issue number:
     - Locate Spec file: `spec_file=$(find docs/spec -name "issue-${N}-*.md" 2>/dev/null | head -1)`
     - If Spec found: extract lines containing `verify-type: manual` from Spec
     - If Spec not found: fetch Issue body via `gh issue view "$N" --json body -q .body` and extract same
     - Extraction: `grep "verify-type: manual" <source>` → strip HTML comments and checkbox markup for display
     - If no manual AC found for this issue: skip with notice
   - For each extracted AC: display issue number + AC text, prompt `[P]ass/[F]ail/[S]kip (default: S):`
   - Read single-char input; treat P/p as PASS, F/f as FAIL, anything else as SKIP
   - After all ACs for an issue are processed:
     - All non-SKIP results are PASS: echo "Transitioning issue #N to phase/done"; call `"$SCRIPT_DIR/gh-label-transition.sh" "$N" done`; post completion comment via `"$SCRIPT_DIR/gh-issue-comment.sh"`
     - Any FAIL: call `gh issue reopen "$N"`; post FAIL detail comment via `"$SCRIPT_DIR/gh-issue-comment.sh"` listing failed ACs
     - All SKIP: skip label change with notice
   - **Note**: include "phase/done" as a string in an echo or comment in the PASS path to satisfy `file_contains "scripts/post_merge_check.sh" "phase/done"` verify command

2. Create `tests/post_merge_check.bats` (test coverage):
   - Test: no arguments → exit 1 + usage message
   - Test: `--dry-run` or invalid arg → appropriate error
   - Mock `gh` and `WHOLEWORK_SCRIPT_DIR` mocks for `gh-label-transition.sh` and `gh-issue-comment.sh`
   - Test: Spec file with `verify-type: manual` AC present → AC extracted and displayed
   - Test: No Spec file → falls back to `gh issue view` body
   - Test: all PASS input → `gh-label-transition.sh N done` invoked
   - Test: FAIL input → `gh issue reopen N` invoked

3. Update `docs/structure.md` and `docs/ja/structure.md` (after Step 1):
   - `docs/structure.md`: change `(52 files)` → `(53 files)` in scripts line; change `(70 files)` → `(71 files)` in tests line; add `scripts/post_merge_check.sh` entry to "Project utilities" category in Key Files/Scripts section
   - `docs/ja/structure.md`: change `（51 ファイル）` → `（53 ファイル）` in scripts line; change `（70 ファイル）` → `（71 ファイル）` in tests line; add corresponding Japanese entry for `post_merge_check.sh`

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/post_merge_check.sh" --> `scripts/post_merge_check.sh` が作成されている
- <!-- verify: rubric "CLI が複数 Issue 番号を受け取り、各 Issue の Spec または Issue body から verify-type: manual AC を抽出し、[P]ass/[F]ail/[S]kip の対話入力を受け付けて順次処理する" --> <!-- verify: grep "verify-type" "scripts/post_merge_check.sh" --> 抽出・対話入力ロジックが実装されている
- <!-- verify: rubric "全 AC PASS 時に phase/verify ラベルを phase/done に付け替え、完了コメントを追記する実装になっている" --> <!-- verify: file_contains "scripts/post_merge_check.sh" "phase/done" --> PASS 時のラベル遷移自動化が実装されている
- <!-- verify: rubric "FAIL AC がある Issue を reopen し、FAIL 詳細をコメントに追記する実装になっている" --> <!-- verify: grep "reopen" "scripts/post_merge_check.sh" --> FAIL 時の reopen とコメント追記が実装されている

### Post-merge

- downstream の実機 API 統合系 Issue 群（最低 2 件以上）に対し `scripts/post_merge_check.sh` を適用し、phase/verify → phase/done 遷移が複数 Issue で同セッション内に完了することを確認 <!-- verify-type: manual -->

## Notes

- `post_merge_check.sh` は Spec ファイルから `verify-type: manual` を含む行を抽出する。bats テスト内にも同文字列がフィクスチャとして含まれるが、スクリプトは Issue 番号を受け取って特定 Spec ファイルまたは Issue body を参照するため、テストファイルを誤ってスキャンすることはない (自己参照除外不要)
- `file_contains "scripts/post_merge_check.sh" "phase/done"` の verify command を満たすため、Implementation Step 1 で PASS パスの echo 文またはコメントに `phase/done` を明示的に含める
- `docs/ja/structure.md` の scripts カウントが 51 ファイル (英語版 52 files より 1 少ない) のため、今回の変更で 53 に揃える (英語版の変更 +1 に加え、既存ドリフト +1 を同時解消)
- 対話入力はパイプ/リダイレクト不可の通常端末を前提とする。`-p` フラグ付き `read` で `[P/F/S]` を一文字入力として受け取る設計

## Code Retrospective

### Deviations from Design

- `read -n 1` (1 文字入力) の代わりに `read -r INPUT` (1 行読み取り) + `${INPUT:0:1}` を採用。Spec では「一文字入力」と書かれていたが、bats テストで `printf "p\n" | run bash "$SCRIPT"` のパイプ構文だと bats が subshell で `run` を実行するため `$status` が見えなかった。ファイルリダイレクト (`run ... < file`) に変更したことで解決し、`read -r` にすることで Enter を押す必要はあるが CI 環境でも安全になった。

### Design Gaps/Ambiguities

- `exec 3< "$TMP_ACS"` + `read -r -u 3 ac_line` で AC ファイルを fd 3 から読み、stdin を対話入力専用にする設計は Spec に明記されていなかったが、bats テストで stdin 経由で入力を差し込む必要から採用。

### Rework

- bats テストの stdin 渡し方を `printf "..." | run bash "$SCRIPT"` (subshell 問題) → `printf > file && run bash "$SCRIPT" < file` に修正（1 コミット追加）。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `read -r INPUT` + `${INPUT:0:1}` を採用し、Enter が必要だが bats テストとの互換性を確保した
- `exec 3< "$TMP_ACS"` + `read -u 3` で AC ファイルを fd 3 から読み、stdin を対話入力専用に分離
- `WHOLEWORK_SCRIPT_DIR` 環境変数でテスト時の sibling script を mock できる設計にした

### Deferred Items
- `phase/verify` → `phase/done` 遷移は `gh-label-transition.sh` に委任。遷移前に Issue が既に closed かどうかの確認は行っていない（実運用では closed Issue に `done` ラベルをつけるケースも考慮が必要かもしれないが、今回はスコープ外）
- コメント本文のフォーマットはシンプルな Markdown — テンプレート化は今後の拡張余地

### Notes for Next Phase
- `/review` フェーズ: `read -r` ループの stdin/fd 3 分離は正しく動作しているが、コードが複雑に見えるかもしれない。仕様上の理由（bats テスト互換性）をレビュアーに説明するとよい
- 全テスト（10 件）PASS 済み
- `phase/done` 文字列は echo とコメントに明示的に含めており、verify command の `file_contains` をクリアしている
