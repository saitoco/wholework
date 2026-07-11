# Issue #986: run-auto-sub: recovery 記録 push の non-fast-forward 失敗にリトライを追加

## Consumed Comments

- saito / MEMBER / first-class / `/issue --non-interactive` によるリファインメント実施報告 (push 箇所 5 箇所への訂正、リトライ方式の具体化、Auto-Resolve Log) — 内容は Issue 本文に反映済みで、Spec 設計に追加で影響する新規情報はなし / https://github.com/saitoco/wholework/issues/986#issuecomment-4946943362

## Overview

`run-auto-sub.sh` の recovery 記録書き込み経路 5 箇所 (`_write_manual_recovery_to_spec` / `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / `_write_wrapper_retry_recovery` / `run_phase_with_recovery` 内 Tier3 recoveries log push) は、いずれも `git add && git commit -s && git push origin HEAD` を 1 回試行するだけで、non-fast-forward で拒否されると WARNING を出して記録を諦める。`modules/orchestration-fallbacks.md#ff-only-merge-fallback` の "lock+push-only mode" (`<from-branch>` 未指定、呼び出し元が既に base ブランチ上で直接 commit → push する構造) に対して確立済みの push retry loop パターン (`git fetch origin <branch>` → `git rebase origin/<branch>` → 再 push、最大 3 回) を共通ヘルパー関数として 1 箇所に実装し、5 箇所全てから呼び出す。

## Reproduction Steps

1. `/auto --batch` などの並列セッション実行中に、`run-auto-sub.sh` が 5 箇所のいずれか (例: `_write_manual_recovery_to_spec`) で recovery 記録を `$REPO_ROOT` 上に commit する。
2. commit 直後、別セッション (別の sub-issue の merge phase handoff commit など) が先に `origin/main` へ push する。
3. `git push origin HEAD` が non-fast-forward で拒否されるが、リトライ処理が存在しないため WARNING を出すのみで記録は失われる (Issue #971 で実際に発生し、親セッションが手動で `git reset --hard origin/main` → `--write-manual-recovery` 再実行して復旧した)。

## Root Cause

5 箇所全てが「commit → `git push origin HEAD` を 1 回のみ試行 → 失敗時は WARNING を出して続行」という同一パターンを個別実装しており、push 失敗に対するリトライ処理を持たない。一方 `scripts/worktree-merge-push.sh` の push retry loop (`modules/orchestration-fallbacks.md#ff-only-merge-fallback` Escalation 節) は、`<from-branch>` 未指定時 (lock+push-only mode — 呼び出し元の現在のブランチが既に base ブランチ) と全く同じ状況に対して、fetch+rebase を挟んだ最大 3 回のリトライを既に確立・実証済み (#853, #970) だが、`run-auto-sub.sh` の 5 箇所はこのパターンを未適用のまま個別実装されたままになっている。

## Changed Files

- `scripts/run-auto-sub.sh`: `_push_with_retry()` ヘルパーを新規追加 (bash 3.2+ 互換)。`_write_manual_recovery_to_spec` / `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / `_write_wrapper_retry_recovery` / `run_phase_with_recovery` 内インライン処理の計 5 箇所で `git -C "$_repo_root" push origin HEAD` を `_push_with_retry "$_repo_root"` に置き換え
- `tests/run-auto-sub.bats`: push retry 成功シナリオ・3 回リトライ上限到達 (WARNING 継続) シナリオを検証する新規テスト 2 件を追加
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` エントリの Applicable Phases / Rationale に `run-auto-sub.sh` の recovery 記録 push (lock+push-only mode) を追記
- `docs/structure.md`: [Steering Docs sync candidate] grep 済み (L207, L218, L223) — `run-auto-sub.sh` の一行要約のみで push リトライ機構には言及しないため変更不要と判断。`/code` での再確認望ましい
- `docs/tech.md`: [Steering Docs sync candidate] grep 済み (L55) — 3-tier recovery 機構の概念説明のみで recovery 記録 push のリトライ機構には触れないため変更不要と判断
- `docs/workflow.md`: [Steering Docs sync candidate] grep 済み (L111, L113) — `--batch`/`--resume` の挙動説明のみで recovery 記録 push の内部実装には触れないため変更不要と判断
- `docs/migration-notes.md`: [Steering Docs sync candidate] grep 済み (L48-52, L554-558) — verify phase 削除・用語修正という無関係な過去移行の記録のため変更不要と判断

## Implementation Steps

1. `scripts/run-auto-sub.sh` — `_spec_has_changes()` の直後・`_validate_recovery_args()` の手前に `_push_with_retry()` ヘルパーを新規追加する (この位置が必須の理由: `_write_manual_recovery_to_spec` は L116-124 の `--write-manual-recovery` 早期 CLI dispatch ブロックから直接呼ばれうるため、`SCRIPT_DIR` 設定や `emit-event.sh` source より前に定義されている必要がある)。直上に `# See modules/orchestration-fallbacks.md#ff-only-merge-fallback` のポインタコメントを付与する。アルゴリズムは `worktree-merge-push.sh` の `<from-branch>` 未指定時 (lock+push-only mode) の既存 push retry ロジックと同一のカウント方式 (`MAX_PUSH_RETRY=3` — 初回 push 試行 + 最大 2 回の fetch+rebase リトライ、計 3 回の push 試行) に揃える:
   ```
   _push_with_retry(repo_root):
     attempt = 0
     loop:
       if `git -C repo_root push origin HEAD` succeeds → return 0
       attempt += 1
       if attempt >= 3 → return 1        # 上限到達。呼び出し元の既存 else 節が WARNING を出して続行する
       branch = `git -C repo_root rev-parse --abbrev-ref HEAD`  (失敗時 → return 1)
       `git -C repo_root fetch origin "$branch"`  (失敗時 → return 1)
       if `git -C repo_root rebase "origin/$branch"` fails:
         `git -C repo_root rebase --abort` (自身の exit code は無視)
         return 1
       # push retry へループ
   ```
   関数内のどの失敗パスでも `exit` は使わず必ず `return` する (5 箇所の呼び出し元が持つ既存の best-effort `if ... ; then ... else WARNING ... fi` 構造にそのまま委ねるため — 「記録より phase 継続を優先する」という Issue Purpose の既存方針を維持する)。(→ acceptance criteria AC1)
2. `scripts/run-auto-sub.sh` — 5 箇所の `if git -C "$_repo_root" add ... && git -C "$_repo_root" commit -s -m "..." && git -C "$_repo_root" push origin HEAD; then ... else ... fi` チェーンについて、末尾の `&& git -C "$_repo_root" push origin HEAD` のみを `&& _push_with_retry "$_repo_root"` に置き換える。`add`/`commit` 部分と成功時 echo / WARNING echo の文言は変更しない。対象: `_write_manual_recovery_to_spec` / `_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / `_write_wrapper_retry_recovery` (いずれも `local _repo_root="$REPO_ROOT"` を使用) / `run_phase_with_recovery` 内インライン処理 (`local _repo_root="$REPO_ROOT"` の直後にある `if ! git -C "$_repo_root" diff --quiet ...` ブロック)。(after 1) (→ acceptance criteria AC1)
3. `modules/orchestration-fallbacks.md` — `## ff-only-merge-fallback` エントリの Applicable Phases に「auto (`run-auto-sub.sh` の recovery 記録 push 5 箇所 — lock+push-only mode variant、`--from` branch を介さない)」を追記し、Rationale に「#986 でこの push retry パターンを共通ヘルパー `_push_with_retry()` として `run-auto-sub.sh` の recovery 記録書き込み 5 箇所に適用した」旨の一文を追記する。(after 1) (→ acceptance criteria AC1)
4. `tests/run-auto-sub.bats` — 既存テスト `"run-auto-sub: manual recovery: writes Auto Retrospective to spec file"` と同じ `--write-manual-recovery 42 code push-only` CLI 経路・同じ `git`/`gh` モック基盤を使い、新規テストを 2 件追加する:
   - (a) `git` モックで `push origin HEAD` を 1 回目失敗・2 回目成功とし (`worktree-merge-push.bats` の "push race" テストと同じ COUNT_FILE パターン)、`rev-parse --abbrev-ref HEAD` は `main` を返すよう追加する。`status -eq 0`、`push origin HEAD` が計 2 回ログされること、その間に `fetch origin main` と `rebase origin/main` が 1 回ずつログされることを assert する。
   - (b) `git` モックで `push origin HEAD` を常に失敗させる。`status -eq 0` (best-effort — 続行する)、出力に既存の `"WARNING: could not commit/push manual recovery to spec; continuing"` 文言が含まれること、`push origin HEAD` が計 3 回ログされ 4 回目は発生しないことを assert する。
   (after 2) (→ acceptance criteria AC2)
5. `bats tests/run-auto-sub.bats` を実行し、既存テストと新規 2 件がすべて green であることを確認する。(after 4) (→ acceptance criteria AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "run-auto-sub.sh の recovery 記録書き込み経路 5 箇所 (_write_manual_recovery_to_spec / _write_tier2_recovery_to_spec / _write_tier3_recovery_to_spec / _write_wrapper_retry_recovery / run_phase_with_recovery 内 Tier3 recoveries log push) が、git push の non-fast-forward 失敗時に git fetch origin <current-branch> と git rebase origin/<current-branch> を挟んで最大3回リトライする共通ヘルパー処理を使用している" --> recovery 記録の push が non-FF 失敗時に最大3回リトライされる (5 箇所全てが共通処理を使用)
- <!-- verify: rubric "tests/ 配下に、recovery 記録 push の non-fast-forward 失敗 → fetch+rebase → 再 push 成功のシナリオと、3回リトライしても失敗した場合に WARNING を出して続行するシナリオを検証するテストが存在する" --> リトライ成功/上限到達 (3回) の両ケースを検証するテストが追加されている

### Post-merge

- 次回 batch 実行中に recovery 記録の push が remote 先行と競合した際、リトライで記録が保全されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **既存の `#ff-only-merge-fallback` カタログエントリを拡張する方針とし、新規エントリは追加しない**: 本 Issue が要求するリトライパターンは、`<from-branch>` 未指定の "lock+push-only mode" に対して `modules/orchestration-fallbacks.md#ff-only-merge-fallback` に既に確立済みの push retry loop (`scripts/worktree-merge-push.sh`、#853/#970 由来) と完全に同型であり、新規パターンではない。新規エントリを追加すると同一パターンが 2 箇所に分散し、#970 の Verify Retrospective が指摘した「一部だけ改修して関連箇所への展開が漏れる」再発パターンと同種のリスクを生むため、既存エントリの拡張を選んだ。
- **`_push_with_retry()` の定義位置は `--write-manual-recovery` CLI dispatch より前が必須**: `_write_manual_recovery_to_spec` は L116-124 の早期 CLI dispatch ブロック (`SCRIPT_DIR` 設定や `emit-event.sh` source より前) から直接呼ばれうるため、新ヘルパーは `_spec_has_changes()` の直後・`_validate_recovery_args()` の手前に定義する。
- **リトライ回数は `worktree-merge-push.sh` の `MAX_PUSH_RETRY=3` と同一のカウント方式**: 「最大 3 回」は "3 回リトライ (=4 回試行)" ではなく "計 3 回の push 試行 (初回 + 2 回の fetch+rebase リトライ)" を指す。Issue 本文の Auto-Resolve Log が明記する「既存値への統一」という意図に基づき、既存実装 (`worktree-merge-push.sh` L129-141) のカウント方式にそのまま揃えた。
- **ベストエフォート契約は変更しない**: `_push_with_retry()` は失敗時に `exit` せず必ず `return 1` する。5 箇所の呼び出し元は既存の `if ... && ... ; then 成功echo; else WARNING echo; fi` 構造をそのまま維持し、WARNING メッセージの文言も変更しない (「記録より phase 継続を優先する」という Issue Purpose の既存方針を壊さないため)。
- **`_write_wrapper_retry_recovery` のコミットメッセージ形式差異は本 Issue のスコープ外**: 同関数のコミットメッセージは他 4 箇所と異なり `Co-Authored-By:` トレーラーを含まないが、push リトライとは無関係な既存の差異であり本 Issue では触れない。
- **Steering Docs sync candidate 確認結果**: `docs/structure.md` (L207, L218, L223) / `docs/tech.md` (L55) / `docs/workflow.md` (L111, L113) / `docs/migration-notes.md` (L48-52, L554-558) はいずれも grep 済みで、`run-auto-sub.sh` の一行要約または高レベルな動作説明に留まり、recovery 記録 push のリトライ機構という粒度までは踏み込んでいないため、本 Issue での変更は不要と判断した。`/code` での再確認を妨げないよう Changed Files に候補として残す。
- **関連 Issue #984 はスコープ外**: Related Issues に挙げられている #984 (recovery 記録の PR番号/Issue番号混同) は同じ 5 つの recovery-write 経路に関わる別欠陥だが、push リトライとは独立した問題であり本 Issue では対応しない。
