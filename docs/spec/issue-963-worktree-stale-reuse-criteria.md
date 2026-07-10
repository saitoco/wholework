# Issue #963: worktree-lifecycle: stale worktree 再開時の再利用/破棄判断基準を追加

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (AC の verify command 修正経緯の報告: 常時 PASS してしまう `grep "stale" "modules/worktree-lifecycle.md"` から、Entry section の範囲に限定した `section_contains "modules/worktree-lifecycle.md" "### Entry Section" "stale"` への変更。あわせて曖昧さ検出の結果 (Size S 相当として追加確認事項なし) も報告。修正後の AC は既に Issue 本文に反映済みで、Spec 設計への追加アクションアイテムなし) — https://github.com/saitoco/wholework/issues/963#issuecomment-4931506038

## Overview

Issue #956 の `/code` フェーズでセッションが crash した際、`.claude/worktrees/code+issue-956` に未コミット実装が残った状態から再開する場面があった。`modules/worktree-lifecycle.md` の Entry Section (execute at skill start) は `scripts/detect-foreign-worktree.sh` による `own`/`foreign`/`none` の3値判定のみを持つ。この判定はカレントブランチのみを見るため、CWD がメインリポジトリ直下で判定結果が `none` であっても、対象 worktree ディレクトリ (`.claude/worktrees/$WORKTREE_NAME`) が前回セッションの crash 等で未クリーンアップのまま残存しているケース (stale worktree) を検出できない。このため `EnterWorktree(name: WORKTREE_NAME)` を呼ぶ前に、残存内容を再利用すべきか破棄すべきかを判断する基準が Entry Section に存在しなかった。

`modules/worktree-lifecycle.md` は `/spec`, `/code`, `/review`, `/merge`, `/verify` 全スキルが参照する共有モジュールであるため、Entry Section に stale worktree 検出時の判断基準 (プロセス終了確認 → 未コミット内容の有無 → Spec の Implementation Steps との内容一致確認 → 再利用/破棄の実行) を追加し、Issue #956 で実施した即興対応を再現可能な手順として明文化する。

## Changed Files

- `modules/worktree-lifecycle.md`: `### Entry Section (execute at skill start)` に stale worktree 検出時の再利用/破棄判断基準を新規ステップとして追加。既存 step 1 (`detect-foreign-worktree.sh` 判定) と step 2 (`EnterWorktree(name:...)` 呼び出し) の間に挿入し、以降の step 番号 (旧2/3/4 → 3/4/5) を繰り下げる。あわせて旧 step 1 内の「in step 2」という前方参照を「in step 3」に更新する

## Implementation Steps

1. `modules/worktree-lifecycle.md` の `### Entry Section` に、以下の内容で新規 step 2 を挿入する (既存 step 1 の直後、既存 step 2 `Only when ENTERED_WORKTREE=true: Call EnterWorktree(name: WORKTREE_NAME)` の直前)。挿入に伴い既存 step 2/3/4 を step 3/4/5 に繰り下げ、既存 step 1 内の "in step 2" という前方参照文言を "in step 3" に修正する (→ AC1, AC2)

   挿入する新規 step 2 の内容:

   ```markdown
   2. **Stale worktree check** (when step 1 recorded `ENTERED_WORKTREE=true`; run before calling `EnterWorktree(name: WORKTREE_NAME)` in step 3): `detect-foreign-worktree.sh` only inspects the *current* branch, so it cannot see a worktree directory left behind by a previous session that crashed or exited without calling `ExitWorktree` — from the main repo root, such a worktree is invisible to step 1 and would otherwise conflict with a fresh `EnterWorktree(name: ...)` call. Check whether `.claude/worktrees/$WORKTREE_NAME` already exists on disk:
      - **Does not exist**: no stale worktree — proceed to step 3 as normal.
      - **Exists** (candidate stale worktree): treat it as a live conflict — not stale — unless there is positive evidence the owning process has actually ended (e.g., no concurrent session or `/auto` run is known to hold it); when in doubt, stop and surface the conflict instead of acting automatically. Once confirmed stale, decide **reuse vs. discard**:
        - Inspect residual content: `git -C ".claude/worktrees/$WORKTREE_NAME" status --porcelain` (and `git diff` for detail).
        - **No uncommitted changes**, or changes **consistent with this phase's intended work** (e.g., for `/code`, matching the Spec's Implementation Steps at `docs/spec/issue-N-*.md`) → **reuse**: call `EnterWorktree(path: ".claude/worktrees/$WORKTREE_NAME")` instead of step 3's `name` form.
        - Changes that **contradict or only partially match** the intended work, or nothing to compare against → **discard**: remove the stale worktree and branch (`git worktree remove --force ".claude/worktrees/$WORKTREE_NAME"`; `git branch -D "worktree-${WORKTREE_NAME//\//+}"`), then proceed to step 3 to create a fresh worktree.
   ```

   旧 step 1 の最終行 "(pass the same value used for `EnterWorktree`'s `name` parameter in step 2):" は "in step 3" に修正する。

## Verification

### Pre-merge
- <!-- verify: rubric "modules/worktree-lifecycle.md の Entry section に、起動プロセスが終了済み (stale) だが未コミット内容が残る worktree を検出した際の再利用/破棄判断基準 (Spec Implementation Steps との内容一致確認など) が追加されている" --> Entry section に stale worktree 再開時の判断基準が明記されている
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "### Entry Section" "stale" --> `stale` (worktree 関連) への言及が Entry section 内に含まれている

### Post-merge
なし

## Notes

- **既存の別レイヤーの stale worktree 破棄機構との関係**: `scripts/run-code.sh` (headless `/code` 起動のラッパー) には `claude -p` 起動前に同名 worktree ディレクトリ/ブランチを無条件で `git worktree remove --force` する既存 cleanup ロジックがある (`run-code.sh` の "Cleanup stale worktrees/branches from previous failed runs" ブロック)。また `/auto --resume` の PR route milestone 機構 (`skills/auto/SKILL.md` "Resume preamble") でも `pre-commit` milestone は「再実行、未コミット変更は破棄」という無条件破棄方針を取る。これらはいずれも LLM セッションが存在しない、または再開判断を bash レベルで完結させる必要があるヘッドレス自動再実行の文脈で動く安全側の仕組みであり、今回 Entry Section に追加する再利用/破棄判断基準 (LLM セッションが Spec の内容と照合して判断する、対話的/手動再開を含む文脈向け) とは適用レイヤーが異なる。両者は独立して機能するため統一の必要はないと判断し、本 Issue のスコープ外とした。
- **プロセス終了確認の具体的な検出手段は規定しない**: Issue の Background では「ロックファイルの PID を `ps -p` で確認」という即興対応が記録されているが、worktree Entry 時点で汎用的に参照できるロック/PID ファイルの仕組みは現状のコードベースに存在しない (`worktree-merge-push.sh` の PID スタンプ付きロックは merge 時点専用で Entry Section とは無関係)。そのため新規ステップでは「終了の積極的な証拠がない限り live とみなし、自動処理せず衝突として表面化させる」という判断原則のみを明記し、特定の技術的検出手段 (lock ファイル形式など) は規定しない。
- **Changed Files をドキュメントのみに限定した判断 (Auto-Resolve, non-interactive mode)**: 本 Issue は `modules/worktree-lifecycle.md` という手順書 (LLM が読んで実行する Markdown) への追記のみで完結し、対応する `.sh` スクリプトや bats テストは存在しない (`tests/` 配下に `worktree-lifecycle` を対象とするテストなし、確認済み)。再利用/破棄の判断ロジック自体が「Spec の内容と実際の diff を照合する」という LLM 解釈を前提とするため、既存 Entry Section の他ステップ (例: step 4 の node_modules symlink 手順) と同様、専用スクリプト化はせずプレーンな手順記述として追加する。

## Code Retrospective

### Deviations from Design
- なし。実装内容 (`modules/worktree-lifecycle.md` の Entry Section への新規 step 2 挿入、旧 step 2/3/4 の繰り下げ、旧 step 1 の前方参照修正) は Spec の Implementation Steps と完全一致。

### Design Gaps/Ambiguities
- 本セッション自体が Issue #963 が扱う stale worktree シナリオに該当した。前回セッションが `EnterWorktree(name: "code/issue-963")` で作成した worktree 内で実装・コミット (`07e9b1df`) まで完了させたが、Step 12 (retrospective) 以降で crash し、`.claude/worktrees/code+issue-963` が未クリーンアップのまま残存していた。今回のセッションで同名 worktree に再エントリした際、`git status --porcelain` で未コミット差分がないこと、および残存コミットの内容が Spec の Implementation Steps と完全一致することを確認した上で、今回追加した Entry Section step 2 の再利用判定基準に沿って再実装せず再利用した。Issue が定義した基準を Issue 自身の実装再開に適用する形になった。

### Rework
- なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- stale worktree (前回セッションの実装済みコミット `07e9b1df` が残る `.claude/worktrees/code+issue-963`) を検出し、Spec Implementation Steps との内容一致を確認した上で再利用した。再実装は行っていない。
- pre-merge verify command 2件 (`rubric`, `section_contains "### Entry Section" "stale"`) をこのセッションで実行し PASS を確認、Issue の Acceptance Criteria チェックボックスを更新済み。

### Deferred Items
- なし。

### Notes for Next Phase
- `/review` フェーズでは、コミット `07e9b1df` (chore: add stale worktree reuse/discard criteria...) の内容を確認すること。差分は `modules/worktree-lifecycle.md` の Entry Section のみ (11 insertions, 4 deletions)。
- patch route のため `/merge` は不要 (Step 13 でこのセッションが直接 main へ push する)。
