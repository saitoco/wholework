# Issue #1037: verify: XS patch route での worktree Entry の必要性を明示化 (常時強制 or 省略許可のルール整理)

## Consumed Comments
No new comments since last phase.

## Overview

`/verify` skill の Step 3 (Worktree Entry) は Size や route (XS patch route か否か) に関わらず無条件で worktree を作成する手順として実装されているが、その「無条件性」自体が SKILL.md の文面上には明示されていない。この曖昧さが原因で、XS patch route Issue (#1031) の batch verify 実行時に worktree Entry が省略される drift が発生した (docs/sessions/91609-1784609460-2026-07-21/session.md § Findings に記録)。

Issue 本文の Proposal (A/B 案) のうち **A. 常に worktree 強制** を採用する (判断根拠は Notes 参照)。対応として (1) `skills/verify/SKILL.md` Step 3 に XS/S patch route を含め無条件に必須である旨と理由を明示し、(2) その前提に依存する `append-consumed-comments-section.sh` に、前提が破られた場合 (worktree 外で実行された場合) を検知する defense-in-depth の warning を追加する。

## Changed Files

- `skills/verify/SKILL.md`: Step 3 (Worktree Entry) に XS/S patch route を含め無条件で必須である旨と、その理由 (`append-consumed-comments-section.sh` の並行実行安全性) を明記
- `scripts/append-consumed-comments-section.sh`: `_repo_root` 算出直後に `git rev-parse --git-dir` と `--git-common-dir` を比較して worktree 外 (main tree) での実行を検知し、stderr に warning を出力する defense-in-depth チェックを追加 (exit code・既存の commit/push 挙動は変更しない)
- `tests/append-consumed-comments-section.bats`: 共有 `setup()` の `git` mock を「worktree 内で実行されている」既定状態 (`--git-dir` と `--git-common-dir` が異なる値を返す) に更新して既存3テストが従来どおり warning なしで通ることを維持したうえで、「worktree 外で実行された場合に warning が出力される」新規テストを追加

**Steering Docs sync candidate** (`grep -l "verify" docs/*.md docs/ja/*.md` 実施済み。ヒットしたファイルはすべて内容確認したが、いずれも `/verify` Step 3 の worktree Entry の XS patch route 挙動という粒度の記述は持たず、更新不要と判断):
- `docs/workflow.md` / `docs/ja/workflow.md`、`docs/product.md` / `docs/ja/product.md`、`docs/tech.md` / `docs/ja/tech.md`、`docs/structure.md` / `docs/ja/structure.md` ほか: いずれも worktree lifecycle の一般的な説明 (`modules/worktree-lifecycle.md` への言及等) のみで、Step 3 の XS patch route 固有挙動には触れていないため対象外

## Implementation Steps

1. `skills/verify/SKILL.md` の `### Step 3: Worktree Entry` セクション内、`**Worktree naming convention:** \`verify/issue-$NUMBER\`` の行と `Record the \`ENTERED_WORKTREE\` variable...` の行の間に、次の趣旨の段落を追加する: 「この手順は Issue の Size や route (XS/S patch route を含む) に関わらず常に必須であり、省略条件は存在しない。省略すると Step 4 の `append-consumed-comments-section.sh` が worktree 外のブランチへ直接 commit/push することになり、`worktree-merge-push.sh` のロック機構を経由しないため、`/auto --batch` 等での並行 `/verify` 実行時に競合するリスクがある (Issue #1037)。」 (→ acceptance criteria A)
2. `scripts/append-consumed-comments-section.sh` の `_repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` の行の直後に、`_git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"` と `_git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"` を算出し、両者が非空かつ一致する場合 (= main tree で実行されている = worktree Entry が省略された) に `echo "append-consumed-comments-section.sh: WARNING — not running inside an isolated worktree (was skills/verify/SKILL.md Step 3 skipped?); commit/push below lands directly on the current branch" >&2` を出力するチェックを追加する。exit code・既存の commit/push ロジックは変更しない (best-effort・non-blocking のまま)。(after 1) (→ acceptance criteria B)
3. `tests/append-consumed-comments-section.bats` の共有 `setup()` 内の `git` mock に、`rev-parse --git-dir` で `"$REPO_ROOT/.git/worktrees/mock"` を、`rev-parse --git-common-dir` で `"$REPO_ROOT/.git"` を返す分岐をそれぞれ追加する (worktree 内で実行されている既定状態を模擬。両パターン文字列は重複しないため判定順は任意)。これにより既存3テストは warning なしで通り続ける。加えて、この2分岐が同一値を返すよう mock を上書きしてから `$SCRIPT` を実行し、`$output` に `WARNING` と `worktree` の両方が含まれることを assert する新規テスト `"not in worktree: emits defense-in-depth warning"` を追加する。(after 2) (→ acceptance criteria B)

## Verification

### Pre-merge

- `skills/verify/SKILL.md` Step 3 に XS patch route での worktree Entry の可否 (常時強制 or 省略許可) が明示されている <!-- verify: rubric "skills/verify/SKILL.md の Step 3 (Worktree Entry) セクションに XS patch route での挙動が明示的にドキュメントされている (常に必須 or 特定条件下で省略可)" -->
- 選択した方針に対応する挙動が実装されている (append-consumed-comments-section.sh の worktree 前提整合含む) <!-- verify: rubric "Proposal で選択した A/B の方針が SKILL.md の手順と append-consumed-comments-section.sh の挙動として整合的に実装されている" -->

### Post-merge

- 次回の batch mode で XS patch route Issue の verify が SKILL.md 手順通りに実行されることを観察 <!-- verify-type: observation event=auto-run -->
  - 期待される出力構造:
    - XS/S patch route Issue の `/verify` 実行でも Step 3 の Worktree Entry (EnterWorktree 呼び出し) が省略されずに実行される
    - `append-consumed-comments-section.sh` 実行時に今回追加する defense-in-depth warning ("not running inside an isolated worktree") が出力されない (= worktree 内で正常に実行されている)

## Notes

- **A/B 判断根拠 (Proposal, 非対話モードによる自動解決)**: **A. 常に worktree 強制** を採用した。B 案 (省略許可) は Issue 本文が明記するとおり「並列 batch 実行時の安全性は別途保証する必要あり」という未解決の追加検討事項を残す一方、A 案は追加コスト (XS/S patch route の verify 実行時間が worktree 作成/削除で 5-10 秒延長される) のみで並行実行時の競合リスクを構造的に排除できる。また現行実装は既に Step 3 が無条件で Entry section に従っており (省略分岐は存在しない)、A 案は「暗黙の現状挙動を明文化する」だけで済み、B 案のような新しい分岐ロジックや追加のロック機構の設計を要しない。`modules/ambiguity-detector.md` の Non-Interactive Mode Handling (Auto-resolve tier: least-risk を優先する / 既存パターンと整合するものを優先する / 両案が安全なら単純な方を優先する) の基準に照らして A 案を選択した。
- **`append-consumed-comments-section.sh` の commit/push 先について**: `_repo_root` は `git rev-parse --show-toplevel` (CWD 依存) で決まるため、Step 3 が実行される正常系では常に isolated worktree のパスに解決され、commit/push は worktree ブランチに対して行われる (main への直接 push にはならない)。このブランチは後続の Step 13 Worktree Exit (`worktree-merge-push.sh`) がロック付きでマージするため、並行 `/verify` 実行同士が競合することはない。今回追加する defense-in-depth warning は、A 案採用後も何らかの理由で Step 3 がスキップされた場合に、サイレントな main 直接コミットではなく検知可能にするための追加の安全策であり、通常経路の挙動を変更するものではない。
- **ドキュメント同期**: Changed Files の Steering Docs sync candidate は内容確認済みで、いずれも本変更 (SKILL.md の文言明確化 + スクリプトの防御チェック追加) による更新は不要と判断した。
