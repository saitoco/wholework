# Issue #1006: verify: 親セッション Skill() 実行時の verify FAIL イベント emit 漏れを修正

## Consumed Comments

No new comments since last phase.

## Overview

`/auto --batch` session `37830-1783901301` で Issue #998 の verify FAIL → L3 auto-retry → 再検証 PASS の完全ループが初めて実地完走したが、`skills/verify/SKILL.md` Step 11(b) が emit を指示している 3 イベント — `verify_reopen_cycle`、`verify_fail_marker_posted`、`verify_retry_fire` — が `.tmp/auto-events.jsonl` に 1 件も記録されていなかった。調査の結果、同じ FAIL 分岐内の `phase_complete` emit も同様に欠落していたことが判明している (Root Cause 参照)。emit 漏れの原因を特定し、`AUTO_SESSION_ID` 付きで確実に emit される経路を構造的に保証する。

## Reproduction Steps

1. `/auto` の親セッションが `.tmp/auto-session-current` (および `.tmp/auto-session-${PGID}`) をリポジトリルートに書き込んだ状態で、`/verify N` を in-session `Skill()` 呼び出しとして実行する (`/auto --batch` の通常経路)。
2. `/verify` Step 1 の `phase_start` emit はまだリポジトリルートで実行されるため成功する (`restore_auto_session_pointer` がルート相対で `.tmp/auto-session-current` を発見できる)。
3. `/verify` Step 3 (Worktree Entry) が `verify/issue-N` worktree に入り、以降の Bash tool call の CWD が `.claude/worktrees/verify+issue-N/` に切り替わる。
4. `/verify` Step 11 (Apply Verification Results) で auto-verification 対象に FAIL が含まれる場合、`verify_reopen_cycle` / `verify_fail_marker_posted` / `verify_retry_fire` および同分岐の `phase_complete` の emit ブロックが実行されるが、`restore_auto_session_pointer()` は常に CWD 相対で `.tmp/auto-session-current` を探すため、worktree 内には同ファイルが存在せず (`.tmp/` は `.gitignore` 対象で fresh worktree に checkout されない) 何も見つからずサイレントに no-op する。
5. 結果として `AUTO_EVENTS_LOG` が未設定のままとなり、`if [[ -n "${AUTO_EVENTS_LOG:-}" ]]` ガードで全 emit がスキップされる。`.tmp/auto-events.jsonl` には `phase_start` のみ記録され、`phase_complete` と 3 イベントのいずれも記録されない。

実際の観測 (`docs/sessions/37830-1783901301-2026-07-13/events.jsonl`、issue=998): `phase_start (phase=verify)` (`01:18:47Z`) の直後に `phase_start (phase=code-pr)` (`01:21:52Z`) が続き、`phase_complete (phase=verify)` および 3 イベントのいずれも存在しない。セッション全体 (9 Issue分) を通しても `verify_reopen_cycle` / `verify_fail_marker_posted` / `verify_retry_fire` は 0 件。

## Root Cause

`restore_auto_session_pointer()` (`scripts/emit-event.sh`) はポインタファイルを常に **CWD 相対パス** (`.tmp/auto-session-${PGID}` / `.tmp/auto-session-current`) で探索する:

```bash
_sid="$(cat ".tmp/auto-session-${_pgid}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')"
```

一方 `/verify` は Step 3 (`modules/worktree-lifecycle.md` Entry section) で自身の `verify/issue-N` worktree に `EnterWorktree` する。`.tmp/` は `.gitignore` 対象 (`.gitignore:5`) であり、`git worktree add` で作成される fresh worktree には親リポジトリの `.tmp/` 配下ファイルは一切引き継がれない (このリポジトリに `.tmp/` を共有するシンボリックリンク機構はなく、`.claude/hooks/worktree-init.sh` 自体が未設置)。

`skills/verify/SKILL.md` の emit ガードは Step 1 (`phase_start`) から Step 11 の全分岐まで一貫して `source emit-event.sh; restore_auto_session_pointer` を直前に呼ぶ設計になっており (Issue #902 Fix Cycle で導入済み、この構造自体は正しい)、問題は `restore_auto_session_pointer()` が **呼び出し元の CWD が worktree 内かどうかを考慮しない** という一点に絞られる。Step 1 の `phase_start` は Step 3 (Worktree Entry) より前に実行されるため CWD=リポジトリルートで成功するが、Step 11 の全 emit (`phase_complete` を含む) は Worktree Entry 後に実行されるため CWD=`verify/issue-N` worktree 内となり、`.tmp/auto-session-current` が見つからず一律で silent skip する。

この解釈は以下の実データ・コード比較で裏付けられる:

- 実セッションの events.jsonl で issue=998 の `phase_start (verify)` のみ成功し、`phase_complete (verify)` を含む後続の emit が全滅している (Reproduction Steps 参照) — Worktree Entry の前後で明確に成否が分かれるパターンと整合する。
- 同じ Step 11 内で `run-code.sh` を再起動する tier-gated auto-retry の `code_retry_fire` イベントは、同一実行で正しく `session_id: 37830-1783901301` 付きで記録されている (events.jsonl 実測)。`scripts/run-code.sh` は自身の `AUTO_SESSION_ID` 解決 (L83) より前に `MAIN_REPO_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"; cd "$MAIN_REPO_ROOT"` (L55-57) を実行しており、CWD を明示的にメインリポジトリルートへ戻してからポインタファイルを読んでいる。この「cd してから読む」パターンの有無が明暗を分けている決定的な傍証である。
- `scripts/detect-foreign-worktree.sh` も同じ `git worktree list --porcelain` イディオムでメインリポジトリルートを特定しており、このリポジトリで既に確立された解決パターンであることが分かる。

Issue 本文の原因候補 (「Bash 呼び出しごとのポインタファイル再生成が前提」) はおおむね正しい方向だが、「いずれかの呼び出しで再生成漏れ」という曖昧な特定に留まっていた。実際には全ての FAIL 分岐 emit (Step 11 以降の呼び出し全て) が worktree CWD により一律に無効化されるという、より具体的かつ決定的な構造的欠陥である。

## Changed Files

- `scripts/emit-event.sh`: change — `restore_auto_session_pointer()` を変更し、`git worktree list --porcelain` (既存の `scripts/detect-foreign-worktree.sh` / `scripts/run-code.sh` と同じイディオム) でメインリポジトリルートを解決し、ポインタファイル探索と `AUTO_EVENTS_LOG` の値をそのルートからの絶対パスに固定する。git repo 外 (bats テストの一時ディレクトリ等、`git worktree list` が失敗する環境) では既存の CWD 相対フォールバックを維持する — bash 3.2+ compatible
- `tests/emit-event.bats`: change — `restore_auto_session_pointer` の既存 3 テストに加え、実 git worktree (`git init` + `git worktree add`、`tests/detect-foreign-worktree.bats` と同じ fixture 規約) を使い、linked worktree の CWD から呼び出してもメイン worktree のポインタファイルを発見し `AUTO_EVENTS_LOG` がメイン worktree 配下の絶対パスになることを検証する回帰テストを追加
- `modules/event-emission.md`: change — 「Non-Wrapper Emitters」節の `restore_auto_session_pointer()` 段落 (L157) に、worktree CWD 非依存化の修正内容を追記
- `docs/structure.md`, `docs/ja/structure.md`: [Steering Docs sync candidate] 確認済み — `emit-event.sh` の説明行 (一文レベルで `restore_auto_session_pointer()` の役割を述べるのみ) は今回の修正後も正確であり、変更不要

## Implementation Steps

1. `scripts/emit-event.sh` の `restore_auto_session_pointer()` を修正する。関数冒頭 (`AUTO_EVENTS_LOG` 設定済みの early return 直後) で `git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}'` によりメインリポジトリルートを取得し、非空なら `${_root}/` を prefix としてポインタファイル探索 (`.tmp/auto-session-${_pgid}` / `.tmp/auto-session-current`) と `AUTO_EVENTS_LOG` の代入 (`${_prefix}.tmp/auto-events.jsonl`) の両方に適用する。空 (git repo 外) の場合は prefix なし (現状の CWD 相対動作を維持) とする。`AUTO_SESSION_ID` を env var 優先で上書きしない既存の優先順位、および見つからない場合に no-op する既存方針は変更しない。bash 3.2+ compatible (→ Root Cause, AC1, AC2)
2. `tests/emit-event.bats` に回帰テストを追加する (after 1)。`tests/detect-foreign-worktree.bats` と同じ fixture 規約 (`git init -q` + `user.email`/`user.name` 設定 + 初回コミット + `pwd -P` によるシンボリックリンク解決) でメイン repo を作成し、`git worktree add -q -b <branch> <path>` で linked worktree を作成する。メイン repo 側の `.tmp/auto-session-current` にテスト用 session id を書き込んでから linked worktree に `cd` し、`restore_auto_session_pointer` 呼び出し後の `AUTO_SESSION_ID` (テスト用 session id と一致) と `AUTO_EVENTS_LOG` (メイン repo 配下の絶対パスであり、linked worktree 配下ではないこと) を検証する (→ AC3)
3. `modules/event-emission.md` の `restore_auto_session_pointer()` 段落 (Non-Wrapper Emitters 節、L157) に、worktree CWD 非依存化の修正内容と Issue #1006 への参照を追記する (after 1) (→ AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "verify FAIL 分岐の verify_reopen_cycle / verify_fail_marker_posted / verify_retry_fire イベントが emit されなかった原因の特定結果が Spec に記録されている" --> emit 漏れの原因が特定され、Spec に記録されている
- <!-- verify: rubric "skills/verify/SKILL.md または scripts/emit-event.sh の修正により、親セッション Skill() 実行の verify FAIL 分岐で verify_reopen_cycle / verify_fail_marker_posted / verify_retry_fire が session_id 付きで emit されることが構造的に保証されている (ポインタ再生成の一元化、emit ガードの見直し等)" --> 修正により、verify FAIL 分岐の 3 イベントが AUTO_SESSION_ID 付きで emit される経路が保証されている
- <!-- verify: command "bats tests/emit-event.bats" --> 上記の bats テストが追加され PASS する

### Post-merge

- 次回 verify FAIL → auto-retry 発生時、3 イベントが events.jsonl に session_id 付きで記録されることを観察 <!-- verify-type: observation event=fix-cycle -->

## Notes

- **Issue AC3 の verify command 修正 (Step 6 conflict detection、非対話モード自動解決)**: Issue 本文 AC3 の verify command は `bats tests/verify.bats` を指定していたが、`tests/verify.bats` は `skills/verify/SKILL.md` Step 2 の worktree guard をセクション抽出して grep する structural テスト (4 件) のみで、emit 経路とは無関係 (`restore_auto_session_pointer`/`emit-event.sh` に一切触れない)。本 Issue の実際の修正対象は `scripts/emit-event.sh` であり、対応する振る舞いテストは `tests/emit-event.bats` に既存の `restore_auto_session_pointer` テスト群がある。SPEC_DEPTH=light のため Spec の Notes 記載のみで自動解決し (AskUserQuestion なし)、Spec の Verification と整合させるため verify command を `bats tests/emit-event.bats` に修正した。Issue body 側の AC3 も同じ内容に更新する。
- **bats テストの fixture 形式**: 追加する回帰テストは `$BATS_TEST_TMPDIR` 配下に実際の git repo を作成する (`tests/detect-foreign-worktree.bats` と同一パターン)。plain な一時ディレクトリ (git repo 外) では `git worktree list` が失敗し `_root` が空になるため、既存の 3 テスト (`restore_auto_session_pointer` の line 198, 207, 214 — いずれも plain tmpdir を使用) は無改修のまま現状の CWD 相対フォールバック経路で PASS し続ける。macOS では `/tmp` が `/private/tmp` のシンボリックリンクであるため、`git worktree list --porcelain` が返す絶対パスと比較する際は `pwd -P` で実体パスに解決してから比較する。
- **`run-auto-sub.sh` への影響なし**: `restore_auto_session_pointer` は `scripts/run-auto-sub.sh:246` からも呼ばれるが、同スクリプトは通常メインリポジトリルートで実行されるため `git worktree list` の第一エントリ (= 自分自身) がそのルートになり、実質的に現状と同じパスを指す。挙動変化なし。
- **`tests/run-auto-sub.bats` への影響なし**: 同ファイルは `restore_auto_session_pointer() { :; }` という no-op モックのみを使用しており (L43, L1732, L1780)、内部実装に依存していないため無改修。
- **未解明の傍証 (スコープ外)**: 同一セッションの events.jsonl には `phase_complete (phase=verify)` が issue #797/#857/#977/#996 で計 4 件記録されているが、いずれも対応する `phase_start (phase=verify)` を欠く (#797 のみ両方あり)。session.md の記述から、これらは observation dispatch 経由の部分的な再検証 (`/verify` のフル実行とは異なる経路) である可能性が高く、本 Issue の対象 (Step 11 FAIL 分岐の emit 漏れ) とは別の code path と判断し、本 Spec のスコープには含めない。
