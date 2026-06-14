# Issue #626: verify-patterns: github_check の gh run list テンプレートに --commit フィルタを標準化

## Overview

patch route（Size XS/S）で使う `github_check "gh run list ..."` verify command が、並行 /auto セッションの push により「別 Issue の CI run」を参照してしまい PENDING/UNCERTAIN になる構造的問題を修正する。

`--commit=$(git rev-parse HEAD)` オプションを追加して現在の HEAD commit に紐づく CI run のみを取得するよう標準化する。`verify-executor` が `github_check` コマンドを bash サブシェルで実行する際に `$(git rev-parse HEAD)` が展開される（`modules/verify-executor.md` 参照）。

## Changed Files

- `modules/verify-classifier.md`: § Patch Route CI Verification Note のテンプレート行に `--commit=$(git rev-parse HEAD)` を追加 — bash 3.2+ compatible
- `skills/issue/spec-test-guidelines.md`: patch route 用 CI 検証テンプレートを `--commit=$(git rev-parse HEAD)` 形式に更新（2 箇所: line 47 および line 79 付近） — bash 3.2+ compatible
- `tests/verify-executor.bats`: 新規作成 — `$(git rev-parse HEAD)` 展開動作を確認するテストを追加
- `docs/structure.md`: `tests/` ファイル数コメントを `(69 files)` → `(70 files)` に更新

## Implementation Steps

1. `modules/verify-classifier.md` の Patch Route CI Verification Note セクション（line 101）のテンプレートを更新する（→ AC1）
   - 変更前: `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '[0].conclusion'" "success"`
   - 変更後: `github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '[0].conclusion'" "success"`

2. `skills/issue/spec-test-guidelines.md` の patch route テンプレートを 2 箇所更新する（after 1）（→ AC2）
   - line 47 付近（§ Example acceptance criteria entry）のコードブロック内 patch route テンプレート
   - line 79 付近（§ Using `github_check` for CI-based bats verification）のコードブロック内 patch route テンプレート
   - 変更内容: `--workflow=test.yml --limit=1 --json` → `--workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json`

3. `tests/verify-executor.bats` を新規作成する（parallel with 1, 2）（→ AC3）
   - `verify-rubric.bats` スタイルに従う（`PROJECT_ROOT` を起点とするドキュメント内容確認 + bash サブシェル動作確認）
   - テスト内容:
     - `modules/verify-classifier.md` に `--commit=` が含まれていること
     - `skills/issue/spec-test-guidelines.md` に `--commit=` が含まれていること
     - bash サブシェルで `$(git rev-parse HEAD)` が 40 文字の hex SHA に展開されること

4. `docs/structure.md` の `tests/` ファイル数コメントを `(69 files)` → `(70 files)` に更新する（after 3）

## Verification

### Pre-merge

- <!-- verify: grep -- "--commit" "modules/verify-classifier.md" --> `verify-classifier.md` に `--commit=$(git rev-parse HEAD)` 形式の説明が記載されている
- <!-- verify: grep -- "--commit" "skills/issue/spec-test-guidelines.md" --> AC Writing Guide に `--commit` を含む新テンプレートが記載されている
- <!-- verify: command "bats tests/verify-executor.bats" --> `tests/verify-executor.bats` が新規作成され green である

### Post-merge

- 次回 patch route Issue の /verify 実行で、並行 push 環境下でも CI 成功判定が正確になることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- `--limit=1` は `--commit` と併用して残す（同一 commit の CI re-run が複数ある場合に最新 run を取得するため）
- `$(git rev-parse HEAD)` は `/verify` 実行時点の HEAD を参照する。patch route では直接 main に push するため、`git rev-parse HEAD` は push した commit SHA を返し、意図した CI run を正確に絞り込む
- `spec-test-guidelines.md` の変更対象は 2 箇所（行数は実装時に grep で確認すること: `grep -n "gh run list" skills/issue/spec-test-guidelines.md`）
- `tests/verify-executor.bats` は `modules/verify-executor.md` の bash サブシェル実行という前提（`github_check` が `bash -c 'gh_command'` で実行されること）を前提とする動作テストも含む
- `docs/structure.md` の tests ファイル数更新: 現在 69 files（`ls tests/*.bats | wc -l` = 69）→ 70 files
- verify command の search pattern `--commit` は実装後に verify-classifier.md および spec-test-guidelines.md に存在する（現時点では未存在 — 実装が導入する文字列）

## Code Retrospective

### Deviations from Design

- 実装コミットのプレフィックスに `feat:` を使用した（Issue Type = Task なので正しくは `chore:`）。コミット後に気づいたため修正せず — 機能的影響なし

### Design Gaps/Ambiguities

- `docs/ja/structure.md` の sync が Implementation Steps に記載されていなかった。`docs/structure.md` 変更時は対応する `docs/ja/structure.md` も更新が必要（`docs/translation-workflow.md` の手続きに従う）

### Rework

- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `--commit=$(git rev-parse HEAD)` を `--limit=1` と併用する形でテンプレートに追加（Spec の Notes 通り）
- `tests/verify-executor.bats` は bash サブシェルでの `git rev-parse HEAD` 展開を直接テストするシンプルな実装を採用

### Deferred Items
- 既存 Issue の AC 更新（`--limit=1` のみのまま残っている Issue の verify command 修正）は別 Issue 対応
- `modules/orchestration-fallbacks.md` への並行セッション言及追記はスコープ外

### Notes for Next Phase
- 全テスト 776件 PASS、forbidden expressions チェック PASS
- Pre-merge AC 3件すべて PASS（チェックボックス更新済み）
- post-merge AC は observation event=auto-run（次回 patch route Issue の /verify 実行で観察）

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 3件 + observation 1件のシンプル構成。grep + command の自動 verify で完全自動化

#### code
- patch route で main 直 commit、ファイル変更最小（verify-classifier.md + spec-test-guidelines.md + tests/verify-executor.bats 新規）

#### verify
- pre-merge AC 3件全 PASS
- post-merge AC 1件は observation event=auto-run → 次回 patch route の /verify 観察

### Improvement Proposals
- N/A

