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
2. `scripts/append-consumed-comments-section.sh` の `# Commit and push` ブロック直前 (`SPEC_REL="${SPEC_FILE#$_repo_root/}"` の行の直前) に、`_git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"` と `_git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"` を算出し、両者が非空かつ一致する場合 (= main tree で実行されている = worktree Entry が省略された) に `echo "append-consumed-comments-section.sh: WARNING — not running inside an isolated worktree (was skills/verify/SKILL.md Step 3 skipped?); commit/push below lands directly on the current branch" >&2` を出力するチェックを追加する。exit code・既存の commit/push ロジックは変更しない (best-effort・non-blocking のまま)。**当初は `_repo_root` 算出直後への挿入を想定していたが、`tests/run-verify.bats` (同スクリプトを対象とする別テストファイル) が dedup guard 発動時に git が一切呼ばれないことを assert しており衝突したため、commit/push 直前に配置を変更した (詳細は Code Retrospective 参照)。** (after 1) (→ acceptance criteria B)
3. `tests/append-consumed-comments-section.bats` の共有 `setup()` 内の `git` mock に、`rev-parse --git-dir` で `"$REPO_ROOT/.git/worktrees/mock"` を、`rev-parse --git-common-dir` で `"$REPO_ROOT/.git"` を返す分岐をそれぞれ追加する (worktree 内で実行されている既定状態を模擬。両パターン文字列は重複しないため判定順は任意)。これにより既存3テストは warning なしで通り続ける。加えて、Spec ファイルを用意し (commit ブロックまで到達させるため)、この2分岐が同一値を返すよう mock を上書きしてから `$SCRIPT` を実行し、`$output` に `WARNING` と `worktree` の両方が含まれることを assert する新規テスト `"not in worktree: emits defense-in-depth warning"` を追加する。(after 2) (→ acceptance criteria B)

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

## Code Retrospective

### Deviations from Design
- Implementation Step 2 の指示 (`_repo_root` 算出直後にチェックを挿入) から、実装では commit/push ブロック (`# Commit and push` コメント) の直前に移動した。理由: `tests/run-verify.bats` (Changed Files に記載のない、同スクリプトを別途テストする既存ファイル) の `"section exists: skip and exit 0 without adding another section"` が「dedup guard 発動時は git が一切呼ばれない」ことを assert しており、`_repo_root` 直後にチェックを置くと dedup guard の早期 return より前に `git rev-parse --git-dir`/`--git-common-dir` が呼ばれてしまい、このテストが FAIL した。commit/push 直前に配置することで、dedup guard や spec-file-absent の早期 exit パスでは新規チェックが呼ばれなくなり、既存テストの前提と両立した。warning の文言が指す「この直後の commit/push」という意味論的にも、実際に commit/push する直前に置く方が正確である。

### Design Gaps/Ambiguities
- Spec の Changed Files には `tests/append-consumed-comments-section.bats` のみが挙げられていたが、実際には同一スクリプトを対象とする `tests/run-verify.bats` も存在し、フルテストスイート実行で初めて衝突が判明した。同一スクリプトに対する bats ファイルが複数存在しうるケースでは、Changed Files 記載時点の `grep -rl "<script>" tests/` 相当の探索を spec 作成時にも徹底する必要がある。

### Rework
- 上記の deviation 検出後、チェック位置の移動 (1箇所) と `tests/append-consumed-comments-section.bats` の新規テストの spec file 追加 (commit ブロックまで到達させるため) の2点を再修正し、フルスイート (`bats tests/`, 1229/1229) の再実行で解消を確認した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #1040 は mergeable=true (clean, CI success, review approved) だったため、conflict 解消手順は不要で Step 4 の squash merge にそのまま進んだ
- squash merge 後、worktree を `origin/main` に `--ff-only` で同期してから Phase Handoff を追記した (squash commit 直後の main と worktree の乖離を防ぐ既定手順どおり)

### Deferred Items
- Post-merge AC (次回 batch mode での XS patch route Issue の /verify 実行時に defense-in-depth warning が出ないことの観察) は `/verify` フェーズで evaluate される — merge フェーズでは対応不要

### Notes for Next Phase
- `/verify` は Post-merge AC (`verify-type: observation event=auto-run`) を評価する: 次回 batch mode での XS/S patch route Issue の `/verify` 実行で Step 3 Worktree Entry が省略されず、かつ `append-consumed-comments-section.sh` の defense-in-depth warning が出力されないことを確認する
- レビュー時点で MUST issue はゼロ、フルテストスイート (`bats tests/`, 1229/1229) は pass 済み

## review retrospective

### Spec vs. implementation divergence patterns
- Code Retrospective に記載済みの偏差 (defense-in-depth check の挿入位置を `_repo_root` 算出直後から commit/push 直前へ変更) 以外に、review 時点で新たな乖離は見つからなかった。当該偏差自体は `tests/run-verify.bats` の dedup guard 前提との整合を裏付けとして事前に検証・記録されており、review 側での再検証も短時間で完了できた。Changed Files に記載漏れだった `tests/run-verify.bats` との関係は Notes for Next Phase に記録済みのため、追加の対応は不要と判断した。

### Recurring issues
- 特になし。review-light (4観点) で指摘事項ゼロ。

### Acceptance criteria verification difficulty
- 特になし。両 AC とも `rubric` verify command が明確に記述されており (「常時必須 or 特定条件下で省略可」「A/B 方針が SKILL.md と script の挙動として整合」)、UNCERTAIN や再解釈の余地なく PASS 判定できた。フルテストスイート実行時に発生した2件の失敗 (`post_merge_check.bats`) は本 PR の差分と無関係なファイルであり、並列実行 (`--jobs`) 時のみ再現し単体実行では再現しなかったことから、並列実行時のフレークと判断した (この PR 固有の問題ではない)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Nothing to note — triage で Size=S 判定、`/spec` フェーズで Size=M に更新される流れは spec-derived Size 再評価の想定範囲内。

#### spec
- Changed Files に `tests/run-verify.bats` が漏れていた (Code Retrospective で判明)。同一スクリプトを対象とする複数の bats テストファイルが存在するケースで、Spec 作成時の `grep -rl "<script>" tests/` cross-search が不十分だった。これは #1035 で Steering Docs sync candidate の cross-search 不足として起票済み (#1039) の同種問題を、テストファイル側で再現した事例。

#### code
- Implementation Step 2 の指示 (`_repo_root` 直後にチェック挿入) から commit/push 直前への移動が発生。理由は `tests/run-verify.bats` の dedup guard 前提との整合。Code Retrospective に詳細記録済み。

#### review
- Nothing to note — review-light で 4観点いずれも指摘ゼロ。フルスイート flake (post_merge_check.bats 並列実行) は本 PR 差分と無関係。

#### merge
- Nothing to note — clean merge、conflict 解消不要。

#### verify
- Nothing to note — Pre-merge AC 2 件は rubric で明確に PASS 判定。UNCERTAIN 0。

### Improvement Proposals

- **`/spec` cross-search の対象を「テストファイル」にも拡張** (#1039 の scope 拡張候補): #1035 → #1037 と、Spec の Changed Files / sync candidate 洗い出しで cross-search 不足の同種パターンが 2 サイクル連続で発生した。#1039 では docs 側 (config-reference table) のみを対象としていたが、テストファイル側 (同一スクリプトを対象とする複数の bats ファイル) にも同じ問題が生じる。#1039 の Proposal Outline に「テストファイルへの grep -rl 実施」を追加するか、別途 grep-based general-purpose cross-search Issue を起こすか、`/spec` skill の Implementation Steps 記述時点でチェックリスト化するかの整理が必要。優先度は low-medium (review-spec + full-suite CI が catch する safety net が既にあるが、code phase での rework が発生する)。
