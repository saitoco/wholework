# Issue #993: reconcile-phase-state: _completion_code_patch がスタライ PR (stray PR) を completion signature として検出できない

## Overview

`scripts/reconcile-phase-state.sh` の `_completion_code_patch()` は、`code-patch` phase の completion signature を「`closes #N` commit」「operate route マーカー」「ラベル/state fallback」の 3 段でのみ判定しており、`_completion_code_pr()` が用いる「issue の worktree ブランチ (`worktree-code+issue-N`) に紐づく open PR の存在」という signature を持たない。route 誤判定 (#979 系) により code-patch phase の実体が PR になっているケースでは、この 3 段のいずれにも一致せず `matches_expected:false` が確定し、`spawn-recovery-subagent.sh` の `skip` action ガードが正当な `action=skip` を拒否する。本 Issue は `_completion_code_patch()` に stray PR 検出分岐を追加し、PR #992 の continuation ロジックが対象シナリオで実際に到達可能になるようにする。

## Reproduction Steps

1. Issue が XS/S (patch route) に triage され、`/code --patch` 実行中に route 誤判定 (#979 系) が発生し、実際には `worktree-code+issue-N` ブランチへの push + PR 作成という pr-route 相当の成果物が生成される。
2. `/auto` の watchdog kill など何らかの理由で code-patch phase の wrapper が異常終了し、Tier 3 recovery (`spawn-recovery-subagent.sh`) が起動する。
3. `spawn-recovery-subagent.sh` は起動直後に `reconcile-phase-state.sh code-patch $ISSUE --check-completion` の結果を `RECONCILE_OUTPUT` としてキャプチャする (`scripts/spawn-recovery-subagent.sh` line 119)。`_completion_code_patch()` は `closes #N` コミット・operate マーカーのいずれも検出できず `matches_expected:false` を返す。
4. Tier 3 sub-agent (`agents/orchestration-recovery.md`) が open PR の存在を認識して `action=skip` を推奨しても、`spawn-recovery-subagent.sh` の `skip)` 分岐 (line 317-330) はキャプチャ済みの `RECONCILE_OUTPUT` の `matches_expected` を再検証し、`false` のため `exit 1` で拒否する。
5. 結果として PR #992 で追加された `run-auto-sub.sh` の `_TIER3_RECOVERY_ACTION == "skip"` continuation ロジックに到達しない。

## Root Cause

`_completion_code_patch()` (`scripts/reconcile-phase-state.sh` line 212-287) は、`_completion_code_pr()` (line 289-312) が用いる「open PR の存在」という signature を持たない。対照的に `_completion_code_pr()` は `gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state open` で当該 issue の worktree ブランチから open PR を検索する実装であり、`_completion_code_patch()` 側で直接再利用できる precedent パターンがすでに存在する。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_patch()` に stray PR 検出分岐を追加 (operate マーカー分岐の直後、ラベル/state fallback の直前に挿入) — bash 3.2+ compatible (no declare -A, no mapfile)
- `modules/phase-state.md`: Phase Table の `code-patch` 行 Success Signature に stray PR signature を追記、`### Operate Route Completion Signature` の直後に `### Stray PR Completion Signature` サブセクションを新設、JSON Schema field contract 表に `actual.stray_pr_signal` 行を追加
- `modules/orchestration-fallbacks.md`: `## async-external-commit` § Fallback Steps を three-stage → four-stage に更新 (stray PR 段を operate marker と label/state fallback の間に挿入)
- `tests/reconcile-phase-state.bats`: `_completion_code_patch()` の stray PR 分岐の bats テストを 3 ケース追加 — bash 3.2+ compatible
- `tests/spawn-recovery-subagent.bats`: `reconcile-phase-state.sh` を実スクリプトのまま (setup() のモックで置き換えず) 動作させて `skip)` 分岐の受理を検証する統合テストを 1 ケース追加 — bash 3.2+ compatible

**変更不要と確認したファイル (grep 実施済み — Steering Docs sync candidate として検出されたが内容確認の上除外)**:

- `docs/product.md` / `docs/tech.md` / `docs/workflow.md` / `docs/structure.md` (および対応する `docs/ja/*.md`): いずれも `reconcile-phase-state.sh` への言及は役割説明・用語集レベルの一行にとどまり、completion signature の内部段数を列挙していないため変更不要
- `agents/orchestration-recovery.md`: 判断根拠は Notes 参照 (Step 3a 相当の追加は不要と判断)
- `scripts/apply-fallback.sh` / `scripts/run-auto-sub.sh` / `skills/auto/SKILL.md`: いずれも `reconcile-phase-state.sh --check-completion` の JSON 出力 (`matches_expected`) を汎用的に解釈するのみでシグネチャロジックを複製していないため、修正は自動的に伝播する

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` に stray PR 検出分岐を追加する。挿入位置: 既存の operate signal ブロック (`actual_json="${actual_json%\}},\"operate_signal\":false}"` の直後の空行) と `# Fallback: check phase labels or issue state...` コメント行の間。挙動: `gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state open --json number -q 'length'` で件数を取得し、0 件なら `stray_pr_signal=false` のまま `actual_json` に追記してラベル/state fallback へフォールスルーする。1 件以上なら `--json createdAt -q '.[0].createdAt'` で作成日時を取得し、`operate_signal` と同一の freshness gate (`reopen_ts` が空/`null`、または PR の `createdAt` が `reopen_ts` より後) を適用する。gate を通過すれば `--json number -q '.[0].number'` で PR 番号を取得し、`actual_json` に `"stray_pr_signal":true,"pr_number":<N>` を追記して `_emit_result "true" "stray PR completion: ..." "$actual_json"` を呼び `return` する。gate 不通過の場合も `actual_json` に `"stray_pr_signal":false` を追記してフォールスルーする (→ 受け入れ基準 1)
2. `tests/reconcile-phase-state.bats` に `_completion_code_patch()` の stray PR 分岐のテストを 3 ケース追加する (after 1): (a) open PR あり・reopen なし → `matches_expected:true`, `stray_pr_signal:true`、(b) reopen あり・PR が reopen より後に作成 → `matches_expected:true` (fix-cycle 再実行防止)、(c) reopen あり・PR が reopen より前に作成 (stale) → freshness gate が拒否し `matches_expected:false`。既存の `# --- code-patch completion: operate route completion signal (Issue #998) ---` 群と同じ mock 方式 (`$MOCK_DIR` に `gh` / `git` / `gh-graphql.sh` を配置し `WHOLEWORK_SCRIPT_DIR` 経由で差し込む) を用いる。「PR も marker も何も無い」否定ケースは既存の operate route テスト群 (`gh pr list` をモックしないため空応答・`stray_pr_signal:false` にフォールスルーする) で暗黙にカバーされるため新規追加しない (→ 受け入れ基準 1, 2)
3. `modules/phase-state.md` の Phase Table `code-patch` 行と `modules/orchestration-fallbacks.md` の `## async-external-commit` § Fallback Steps を更新し、新しい stray PR signature をドキュメント化する。前者は `### Operate Route Completion Signature` の直後に `### Stray PR Completion Signature` サブセクションを新設 (検出方法・freshness gate・チェック順序を記述) し、JSON Schema field contract 表に `actual.stray_pr_signal` (boolean) の行を追加する。後者は "built-in three-stage check" の記述を four-stage に更新し、operate marker と label/state fallback の間に stray PR 段を挿入する (parallel with 1) (→ 受け入れ基準 1)
4. `tests/spawn-recovery-subagent.bats` に、`reconcile-phase-state.sh` を `setup()` の canned モック (`{"matches_expected":false}` 固定) で置き換えず実スクリプトとして動作させ (`gh` / `git` / `gh-graphql.sh` の下位依存のみモック)、stray PR 検出により `matches_expected:true` が返る状態で `spawn-recovery-subagent.sh code-patch <issue> --log <log>` を実行し、`action=skip` が受理されて exit 0 になることを検証するテストを 1 件追加する (after 1) (→ 受け入れ基準 3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/reconcile-phase-state.sh の _completion_code_patch() が、closes #N コミット未検出時でも、issue の worktree ブランチ (worktree-code+issue-N) に紐づく open PR が存在すれば matches_expected:true を返すロジックを実装している" --><!-- verify: command "grep -A 80 '^_completion_code_patch()' scripts/reconcile-phase-state.sh | grep -q 'pr list'" --> `_completion_code_patch()` が open PR を検出した場合に `matches_expected:true` を返すロジックが実装されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存の `_completion_code_patch` 呼び出し元 (run-auto-sub.sh Tier1, /auto SKILL.md Step 6) の既存テストが回帰なく PASS する
- <!-- verify: rubric "tests/reconcile-phase-state.bats (または同等の統合テストファイル) に、spawn-recovery-subagent.sh の skip) 分岐を実際にモックなしで実行し action=skip が受理されることを検証するテストケースが追加されている" --> PR #992 で追加された continuation ロジックが、モックなしの `spawn-recovery-subagent.sh` 実 dispatch 経路 (またはそれに準ずる統合テスト) で到達可能であることを確認するテストが追加されている

### Post-merge

なし

## Notes

### stray PR 検出条件の再利用方針 (Issue 本文の自動解決を継承)

`_completion_code_pr()` (line 289) と同一の `gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state open` パターンを再利用する。理由: 既存コードベースで確立された worktree ブランチ命名規約 (SSoT) であり、新規パターンを導入する理由がない。

### freshness gate の設計方針 (Issue 本文の自動解決を継承)

stray PR 検出は `operate_signal` と同一の freshness gate (`reopen_ts` が空/`null`、または signal の `createdAt` が `reopen_ts` より後) を適用する。理由: #569 (`commits_found` の freshness) と #998 (`operate_signal` の `operate_ts > reopen_ts` ガード) で同型の問題が解決済みであり、同じ設計を踏襲するのが最小リスク。挿入位置もラベル/state フォールバックより手前 (#998 と同じ位置関係) とした。

### `agents/orchestration-recovery.md` Step 3a 相当の追加は不要と判断

Issue の Purpose は「必要であれば `agents/orchestration-recovery.md` の code-patch 向け probe セクション」の追加を示唆していたが、調査の結果不要と判断した。`_completion_code_pr` 向けの Step 3a は「branch に commit はあるが PR が無い」不完全な状態を能動的に `recover` (push + PR 作成) するための probe であるのに対し、本 Issue の stray PR シナリオは「PR が既に存在し完了している」ことを検出するだけの受動的な判定であり、能動的な recovery アクションを必要としない。`agents/orchestration-recovery.md` 既存の Step 2 (`If matches_expected: true: ... recommend skip`) は `_completion_code_patch()` の修正により自動的に stray PR ケースをカバーするため、追加の probe セクションは不要と判断した。

### テストファイル配置の判断 (Issue 本文の自動解決を継承)

AC3 の Issue 本文は `tests/reconcile-phase-state.bats` を主候補としつつ「または同等の統合テストファイル」を明示的に許容していた。`spawn-recovery-subagent.sh` の `skip)` 分岐を実行するには `claude` CLI mock・slot lock ディレクトリ・`agents/orchestration-recovery.md` の存在など、`tests/spawn-recovery-subagent.bats` の `setup()` が既に提供するスキャフォールディングが必要なため、当該ファイルへの追加を採用した。

### 影響範囲の確認 (Issue 本文 Background の懸念に対する回答)

`reconcile-phase-state.sh` は `/auto` SKILL.md Step 6 (Unconditional completion check) と `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` (line 727) からも呼び出されるが、いずれも `_completion_code_patch()` が返す JSON の `matches_expected` フィールドを汎用的に解釈するのみで、シグネチャ判定ロジックを複製していない。したがって本修正は両呼び出し元に自動的に伝播し、stray PR シナリオを正しく `matches_expected:true` として扱うようになる (追加のコード変更不要)。

### #998 との関係

#998 (`_completion_code_patch()` への operate route completion signature 追加) は既にマージ済みであり、本 Spec の調査時点のコードは #998 適用後の状態 (operate signal 分岐を含む) である。#998 の Spec Notes には「#993 と物理的に近接する変更になる可能性が高いため、後からマージする側が rebase して解消すること」という事前警告が記載されていたが、#998 が先にマージされ本 Issue の worktree は post-#998 の main から分岐しているため、実際の衝突は発生しない。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (トリアージ結果 Type=Bug・Size=M、Background 記載の行番号事実誤認の修正、曖昧点 3 件の自動解決、Pre-merge AC 3 件全てへの verify command 新規付与、Related Issues への #998 追加) — https://github.com/saitoco/wholework/issues/993#issuecomment-4979750986
