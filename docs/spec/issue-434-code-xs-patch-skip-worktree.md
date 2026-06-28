# Issue #434: code: XS patch route で worktree 作成をスキップして高速化

## Overview

`/code` の XS patch route で、対話的な単一起動時（`--non-interactive` フラグなし）に
`EnterWorktree` 呼び出しを省略し、直接 main へ commit するモードを追加する。

ボトルネックは worktree ライフサイクル (EnterWorktree → worktree-init.sh → worktree-merge-push.sh →
git worktree remove → branch delete) で、XS patch route の 1 実行あたり 30-60 秒の固定費を占める。
XS は実質「main への 1 ファイル程度の追加 commit」なので、worktree による隔離の利得が固定費に見合わない。

`/auto` 経由または `run-code.sh` 経由 (並列実行) では `--non-interactive` フラグが付与されるため、
これらのパスでは従来通り worktree を作成する。

## Consumed Comments

- **author**: saitoco (OWNER / first-class) — 2026-06-28T04:35:57Z
  - Issue Retrospective: AC1 の verify command を `rubric` に修正 + `grep "worktree.*skip|skip.*worktree"` を補足 AC として追加。S route は today AC スコープ外（auto-resolve log）。

## Changed Files

- `skills/code/SKILL.md`: Step 2 冒頭に XS patch + 非 non-interactive 判定の worktree skip 分岐を追加 — bash 3.2+ compatible

## Implementation Steps

1. `skills/code/SKILL.md` の Step 2 冒頭（`Read ${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` の直前）に、以下の条件分岐を追加する (→ AC1, AC2, AC3)

   **追加するテキスト（Step 2 の最初のブロックとして挿入）:**

   ```
   **Worktree skip for XS patch route (interactive direct-launch only):**

   Before following the Entry section, check all three conditions:
   - Route is **patch** (XS auto-route or `--patch` flag)
   - Size is specifically **XS** (not S — conservative scope)
   - ARGUMENTS does **not** contain `--non-interactive`

   If all conditions are met: set `ENTERED_WORKTREE=false` and skip EnterWorktree.
   This avoids the 30–60 s worktree lifecycle overhead for XS direct-launch code runs.
   For `--non-interactive` runs (via `run-code.sh`, `/auto`, batch), worktree is always created.

   If any condition is NOT met: follow the normal Entry section below.
   ```

2. 既存の bats テストが通ることを確認する: `bats tests/worktree-merge-push.bats tests/run-code.bats` (→ AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md に XS patch route での worktree 作成をスキップする条件分岐が追加されており、適用条件 (非並列実行・直接起動) が読み取れる" --> `skills/code/SKILL.md` に XS patch route での worktree skip 分岐が明記されている
- <!-- verify: grep "worktree.*skip|skip.*worktree" "skills/code/SKILL.md" --> worktree skip を示すキーワード組み合わせが SKILL.md に含まれている
- <!-- verify: rubric "skills/code/SKILL.md には patch route かつ非並列実行コンテキストでのみ worktree を skip する条件が明記されており、--auto / 並列実行コンテキストでは worktree を作成する旨が読み取れる" --> 並列実行 (`/auto` 経由など) では従来どおり worktree を使う条件分岐が読み取れる
- <!-- verify: command "bats tests/worktree-merge-push.bats tests/run-code.bats" --> 既存の worktree-merge-push / run-code テストが通る

### Post-merge

- サンプル XS Issue に対して `/code <N>` を実行し、ターミナル出力に `EnterWorktree` / `worktree remove` ステップが現れず、想定時間が 1-2 分台に収まることを実機で確認 <!-- verify-type: opportunistic -->

## Notes

- **S route の対象外**: Issue Retrospective に Auto-Resolve Log あり。S route skip は今回 AC のスコープ外であり、保守的スコープ (XS のみ) から開始する方針を採用。S route 追加は follow-up Issue で判断。
- **worktree-lifecycle.md の変更不要**: ENTERED_WORKTREE=false の場合は既存の "Exit: merge-to-main" が `worktree-merge-push.sh` を `--from` なしで実行（lock+push only）するため、Step 13 Worktree Exit の変更は不要。
- **`--non-interactive` が唯一の判断軸**: `/code 123 --auto` は Step 0 で run-code.sh に委譲して終了するため Step 2 に到達しない。run-code.sh 経由の自律実行のみが `--non-interactive` を付与するため、このフラグの有無が「対話的起動か否か」の唯一の判断軸となる。
- **CWD 変化なし**: worktree をスキップした場合、CWD は main repo のまま。Edit/Write ツールは自然に main repo 相対パスを使用するため、ファイル編集の CWD 混乱は発生しない。
