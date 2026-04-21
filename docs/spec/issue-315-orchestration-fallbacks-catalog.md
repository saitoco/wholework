# Issue #315: orchestration fallback catalog module

## Overview

orchestration 層で散在している retry / fallback パターン（`git merge --ff-only` 失敗→rebase、`git pull --ff-only` retry、`gh pr list --head` glob 非対応、DCO sign-off 欠落、CI flake、conflict marker 残存）を **pattern reference doc** として 1 つの共有 module に集約する。

scope は catalog 本体の新設に限定。`scripts/run-auto-sub.sh` の `run_verify_with_retry` 書き換えは #319 (tier 2 hook) に委譲、CI flake retry / DCO auto-fix の実行時統合は別 Issue に委譲。shell は markdown module を「Read and follow」できないため、既存 inline logic は維持し、該当位置に catalog エントリへの pointer コメントを添える方針を取る（Issue リファインメントで確定）。

## Changed Files

- `modules/orchestration-fallbacks.md`: 新規作成。catalog 本体。6 エントリを `## <pattern-name>` 見出しで記述、各エントリは `### Symptom` / `### Applicable Phases` / `### Fallback Steps` / `### Escalation` / `### Rationale` の必須 5 セクションを含む。末尾に #319 (tier 2 consumer) / #316 (recovery sub-agent 参照情報) / #318 (learning loop 入力源) との連携運用メモを記載
- `scripts/worktree-merge-push.sh`: pointer コメント 2 箇所追加（`git merge "$FROM_BRANCH" --ff-only` 直上、`conflict_output=$(grep -rn '^<<<<<<'` 直上）。inline logic 自体は変更しない — bash 3.2+ 互換（コメントのみ）
- `scripts/run-auto-sub.sh`: pointer コメント 1 箇所追加（`run_verify_with_retry()` 関数定義直上）。inline logic 自体は変更しない — bash 3.2+ 互換（コメントのみ）
- `modules/worktree-lifecycle.md`: 51 行目付近の `git merge --ff-only (with git pull --rebase retry on FF failure)` 説明末尾に catalog エントリへのリンクを追記
- `tests/orchestration-fallbacks.bats`: 新規作成。catalog の schema 検証（ファイル存在、6 パターン以上、各エントリの必須 5 セクション、Rationale の Issue 参照、#319 への参照）— bash 3.2+ 互換
- `docs/structure.md`: `### Modules` 一覧に `modules/orchestration-fallbacks.md` を追加。Directory Layout コメント `modules/  # ... (28 files)` を `(29 files)` に更新
- `docs/ja/structure.md`: 上記の日本語ミラー同期（Modules 一覧と Directory Layout コメント）

## Implementation Steps

1. `modules/orchestration-fallbacks.md` を新規作成。冒頭に Purpose / Input / Processing Steps（=参照方法）/ Output の標準 4 セクションを置き、続けて 6 エントリを記述する。各エントリは `## <pattern-name>` 見出しで始まり、`### Symptom`（エラー文字列 / exit code / 観測シグナル）、`### Applicable Phases`（code/review/merge/verify のいずれか）、`### Fallback Steps`（具体的な対処シーケンス）、`### Escalation`（N 回リトライでも解決しない場合の対応。#316 recovery sub-agent へのハンドオフを含む）、`### Rationale`（回避が正しい根拠となる Issue/retrospective 参照 — `#\d+` 形式を少なくとも 1 件含める）の 5 必須セクションを持つ。エントリ名（= anchor）は以下の 6 種を最低限含める: `ff-only-merge-fallback`（`git merge --ff-only` 失敗→`git pull --rebase` retry）、`verify-sync-retry`（`git pull --ff-only` + 1 回リトライ）、`gh-pr-list-head-glob`（glob 非対応、client-side filter で回避 — #311 の修正結果を catalog 化）、`ci-flake-retry`（CI check の一時的失敗に対する再実行）、`dco-signoff-missing-autofix`（`git commit --amend -s --no-edit` による修正 — detect-wrapper-anomaly.sh が検出済み、auto-fix 発火は別 Issue）、`conflict-marker-residual`（push 前の `grep -rn '^<<<<<<'` による残存検出）。ファイル末尾に「本カタログは #319 の tier 2 hook から参照、#316 の recovery sub-agent 未知パターン時の参照情報、#318 learning loop からの自動エントリ追加入力源として機能する」旨の運用メモを明記する (→ AC1, AC2, AC4)
2. `scripts/worktree-merge-push.sh` の `if ! git merge "$FROM_BRANCH" --ff-only; then` 行（現在 81 行目相当）の直上に `# See modules/orchestration-fallbacks.md#ff-only-merge-fallback` を追加。`conflict_output=$(grep -rn '^<<<<<<' . 2>/dev/null || true)` 行（現在 87 行目相当）の直上に `# See modules/orchestration-fallbacks.md#conflict-marker-residual` を追加。inline logic 自体は保持（リライトしない） (→ AC3)
3. `scripts/run-auto-sub.sh` の `run_verify_with_retry() {` 行（現在 40 行目相当）の直上に `# See modules/orchestration-fallbacks.md#verify-sync-retry` を追加。inline logic 自体は保持 (→ AC3)
4. `tests/orchestration-fallbacks.bats` を新規作成。catalog schema を bash で parse し以下を検証する bats ケースを追加: (a) ファイル存在、(b) `## <pattern-name>` 見出しが 6 個以上、(c) 各 `## <pattern-name>` エントリが直下に `### Symptom` / `### Applicable Phases` / `### Fallback Steps` / `### Escalation` / `### Rationale` の 5 見出しを含む、(d) 各エントリの Rationale セクション内に `#\d+` 参照が少なくとも 1 件、(e) カタログ本体のどこかに `#319` が含まれる。スクリプトは `BATS_TEST_FILENAME` からリポジトリルートを解決し、`awk` / `grep` で見出し解析を行う（bash 3.2+ 互換） (→ AC2, AC5)
5. `modules/worktree-lifecycle.md` の `git merge --ff-only (with git pull --rebase retry on FF failure)` 説明末尾に `(see modules/orchestration-fallbacks.md#ff-only-merge-fallback)` を追記。`docs/structure.md` の `### Modules` 箇条書きに `- modules/orchestration-fallbacks.md — orchestration-level fallback pattern reference catalog (consumed by #319 tier 2, #316 recovery sub-agent, #318 learning loop)` を追加し、Directory Layout の `modules/  # ... (28 files)` コメントを `(29 files)` に更新。`docs/ja/structure.md` にも同等の日本語訳エントリと件数更新を反映する

## Verification

### Pre-merge
- <!-- verify: file_exists "modules/orchestration-fallbacks.md" --> `modules/orchestration-fallbacks.md` が作成されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md contains at least 5 pattern entries covering: (1) git merge --ff-only fallback with git pull --rebase retry, (2) git pull --ff-only retry for verify sync, (3) gh pr list --head glob fallback (client-side filter), (4) CI flake retry, (5) DCO sign-off missing auto-fix via git commit --amend -s --no-edit, and (6) merge conflict marker residual check. Each entry must have the five required sections: Symptom, Applicable Phases, Fallback Steps, Escalation, Rationale." --> 初期 5 パターン以上が必須 5 セクション (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) 付きで記述されている
- <!-- verify: rubric "scripts/worktree-merge-push.sh and scripts/run-auto-sub.sh each contain at least one pointer comment (e.g., '# See modules/orchestration-fallbacks.md#...') placed adjacent to their existing inline fallback logic. The inline logic itself is preserved (not rewritten)." --> `scripts/worktree-merge-push.sh` と `scripts/run-auto-sub.sh` の既存 inline fallback logic 直近にカタログエントリへの pointer コメントが追加され、inline logic 自体は保持されている
- <!-- verify: file_contains "modules/orchestration-fallbacks.md" "#319" --> カタログに #319 (tier 2 consumer) への参照が記載されている
- <!-- verify: command "bats tests/orchestration-fallbacks.bats" --> catalog schema 検証の bats テストが PASS する

### Post-merge
- 新しい fallback パターンを発見した際、catalog に entry を 1 件追加する演習を実施し、必須 5 セクション schema での記述が自然に行えることを確認

## Notes

- **catalog の性質**: pattern reference doc。markdown は LLM/skill から「Read and follow」参照、shell script は既存 inline logic 維持 + pointer コメント。#165（/auto の自動復旧機能除去）の方針と整合
- **対象外**: `scripts/run-auto-sub.sh` の `run_verify_with_retry` の書き換え（#319 の tier 2 で catalog を参照する形で統合）、CI flake retry / DCO auto-fix の実行時統合（別 Issue）、catalog 内容の shell library 化
- **bats 入力データ形式**: catalog ファイルは標準 Markdown。`awk '/^## /' / '/^### /'` で見出しを抽出可能。Rationale の Issue 参照は `grep -E '#[0-9]+'` で検出。bash 3.2+ 互換のため `mapfile` / 連想配列は避け、while read ループで処理する
- **structure.md モジュール件数**: 現行 `(28 files)` から `(29 files)` に更新。`docs/ja/structure.md` も同時更新
