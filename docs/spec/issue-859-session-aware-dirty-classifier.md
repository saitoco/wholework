# Issue #859: check-verify-dirty.sh を session-aware に拡張 (自/他 worktree / parent main 判別)

## Overview

並列セッション環境で複数の `/auto` セッションが parent repo を共有する際に、`check-verify-dirty.sh` が dirty file の出自を判別できず適切な対処判断ができない問題を解決する。

dirty file を以下 4 分類で判定し、`self-worktree` / `other-worktree` / `other-session` は blocking しない挙動を追加する:

1. **self-worktree** — `.claude/worktrees/*+issue-${NUMBER}/*` 配下 → exit 0 (自セッションの作業中ファイル、無視)
2. **other-worktree** — `.claude/worktrees/*` 配下 (他 issue) → stderr 警告のみ (block しない)
3. **other-session** — `docs/sessions/*-*/*` 配下 → stderr 警告のみ (block しない)
4. **parent-main** — 上記以外 → 既存ロジック維持 (exit 1 / exit 2)

各 dirty file の判別結果を stderr に `[check-verify-dirty] classify=... path=...` 形式で出力する。

## Consumed Comments

- saito / MEMBER / first-class — issue retrospective + Auto-Resolved Ambiguity Points (3 件); ファイル名修正・full suite 使用・BRE→ERE 修正を反映 (https://github.com/saitoco/wholework/issues/859#issuecomment-4830220577)

## Changed Files

- `scripts/check-verify-dirty.sh`: verify-ignore-paths フィルタ後に session-aware 分類ブロックを追加。4 分類の判定 + stderr 出力 + parent-main のみを既存 exit code ロジックに渡す — bash 3.2+ 互換
- `tests/verify-dirty-detection.bats`: session-aware 分類の test ケース 5 件追加 (self-worktree / other-worktree / other-session / parent-main 混合)
- `docs/structure.md`: `check-verify-dirty.sh` の Key Files 説明を session-aware 分類を反映した内容に更新
- `docs/ja/structure.md`: 上記の日本語訳を更新

## Implementation Steps

1. `scripts/check-verify-dirty.sh` を編集 — verify-ignore-paths フィルタ後、既存の `unrelated_spec_files` / `has_other` 分類ブロックの直前に session-aware 分類ブロックを追加 (→ AC1, AC2)

   追加するロジック:
   ```bash
   # Session-aware classification
   parent_main_files=()
   for f in "${dirty_files[@]}"; do
     if [[ "$f" == .claude/worktrees/*+issue-${NUMBER}/* ]]; then
       echo "[check-verify-dirty] classify=self-worktree path=$f" >&2
     elif [[ "$f" == .claude/worktrees/* ]]; then
       echo "[check-verify-dirty] classify=other-worktree path=$f" >&2
     elif [[ "$f" == docs/sessions/*-*/* ]]; then
       echo "[check-verify-dirty] classify=other-session path=$f" >&2
     else
       echo "[check-verify-dirty] classify=parent-main path=$f" >&2
       parent_main_files+=("$f")
     fi
   done
   # Replace dirty_files with parent-main only
   if [[ ${#parent_main_files[@]} -eq 0 ]]; then
     exit 0
   fi
   dirty_files=("${parent_main_files[@]}")
   ```

2. `tests/verify-dirty-detection.bats` に 5 件のテストケースを追加 (→ AC3, AC4)

   追加するテスト:
   - `"session-aware: self-worktree only dirty -> exit 0"` — `.claude/worktrees/code+issue-123/docs/spec/issue-123-foo.md` のみ dirty → exit 0
   - `"session-aware: other-worktree only dirty -> exit 0 with warning"` — `.claude/worktrees/code+issue-999/scripts/foo.sh` のみ dirty → exit 0、stderr に `classify=other-worktree`
   - `"session-aware: other-session only dirty -> exit 0 with warning"` — `docs/sessions/82534-1782700033/data-layer.md` のみ dirty → exit 0、stderr に `classify=other-session`
   - `"session-aware: parent-main only dirty -> exit 1"` — `scripts/some-script.sh` → exit 1 (既存挙動の確認)
   - `"session-aware: self-worktree mixed with parent-main -> exit 1"` — self-worktree + `scripts/foo.sh` → exit 1 (parent-main が優先)

3. `docs/structure.md` の Key Files セクションの `check-verify-dirty.sh` 説明を更新 (→ SHOULD)

   変更: `— classify dirty files as unrelated spec or other for /verify Step 1`
   → `— session-aware dirty file classifier for /verify Step 1 (self-worktree / other-worktree / other-session / parent-main 4-way classification; outputs classify=... to stderr)`

4. `docs/ja/structure.md` の対応行を更新 (→ SHOULD、translation sync)

   変更: `— dirty ファイルを unrelated spec または other に分類する /verify Step 1 ヘルパー`
   → `— /verify Step 1 用 session-aware dirty file 分類スクリプト (self-worktree / other-worktree / other-session / parent-main の 4 分類; classify=... を stderr 出力)`

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/check-verify-dirty.sh に dirty file classification ロジック (self-worktree / other-worktree / other-session / parent-main の 4 分類) が追加されており、各 dirty file の判別結果を stderr に classify=... 形式で 1 行ずつ出力する" --> `scripts/check-verify-dirty.sh` に dirty file classification ロジック (4 分類) が追加され、stderr に `classify=...` 形式で出力する
- <!-- verify: grep "classify=" "scripts/check-verify-dirty.sh" --> `scripts/check-verify-dirty.sh` に `classify=` 文字列が含まれる
- <!-- verify: grep "self-worktree" "scripts/check-verify-dirty.sh" --> `scripts/check-verify-dirty.sh` に `self-worktree` が含まれる
- <!-- verify: rubric "scripts/check-verify-dirty.sh で全ての dirty file が自 worktree (worktree-{phase}+issue-{ISSUE_NUMBER} 配下) の場合に exit 0 として扱う挙動が追加されている" --> 全 dirty が `self-worktree` 配下の場合は exit 0 として扱われる
- <!-- verify: grep "self-worktree" "scripts/check-verify-dirty.sh" --> (上記と同一 grep — AC2 の supplementary hint)
- <!-- verify: command "bats tests/" --> 既存挙動 (引数あり / verify-ignore-paths 適用 / spec ファイルのみの exit 2) は維持されている
- <!-- verify: grep "self-worktree|other-worktree|other-session|parent-main" "tests/verify-dirty-detection.bats" --> `tests/verify-dirty-detection.bats` に session-aware 分類の test ケースが追加されている

### Post-merge

- 次回並列セッション環境で他セッションの作業ファイルが parent main に残っていても、自セッションの作業中ファイルとは区別して判定されることを観察

## Notes

- `NUMBER` (第 1 引数) を self-worktree 判定の `ISSUE_NUMBER` として流用。現行の呼び出し元 (`skills/verify/SKILL.md`: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-verify-dirty.sh $NUMBER`) は変更不要。
- `.claude/worktrees/` は `.gitignore` で除外されているが、テスト用リポジトリには `.gitignore` がないため bats テストでは問題なく dirty として検出される。本番での `.claude/worktrees/` パスは `docs/sessions/` とは異なり現在は git status に現れないが、将来的な use case (verify が worktree 内から呼ばれる場合等) のために基礎機構として追加する。
- `other-worktree` と `other-session` は blocking しない (exit 0 → no-op) が、stderr への出力は残す。後続 Issue で各 run-*.sh の冒頭 check がこの出力を利用できるようにするための基礎。
- bash 3.2 互換: `=~` と `case`/glob パターン (`== glob`) は両方 bash 3.2 以上で動作。`[[ "$f" == .claude/worktrees/*+issue-${NUMBER}/* ]]` の glob マッチは bash 3.2+ 互換。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #868 squash-merged successfully; `worktree-code+issue-859` branch deleted from remote
- CONSIDER comment about `*-*` pattern intent (line 111) was not added — pattern is self-evident from context and Notes section already documents the `{pid}-{timestamp}` numeric intent
- No conflicts encountered; CI (5/5 SUCCESS) and review approval were already in place

### Deferred Items
- Post-merge observation: verify that self-worktree/other-worktree classification works correctly when called from a worktree context in a real parallel session (carried from review phase)
- bats test environment pattern (`git config core.excludesFile /dev/null`) should be documented as standard for future tests using `.claude/` paths on macOS

### Notes for Next Phase
- All verify commands are grep/rubric-based or `bats tests/` — straightforward to validate
- The `bats tests/` verify command relies on CI environment (Ubuntu); macOS may need `core.excludesFile /dev/null` — already fixed in tests
- Pre-merge verify commands can all be run directly against the merged main branch

## review retrospective

### Spec vs. 実装乖離パターン

- 乖離なし。実装はSpec定義の4分類ロジック・stderr出力フォーマット・exit codeポリシーと完全に一致している。

### 繰り返し発生するIssue

- **テスト環境依存の想定漏れ**: Specの Notes に「テスト用リポジトリには `.gitignore` がないため bats テストでは問題なく dirty として検出される」と記述されていたが、グローバル gitignore (`~/.gitignore_global`) の影響を考慮していなかった。`git config core.excludesFile /dev/null` の設定は、`.claude/` を含む任意のパスを test repo で使用するすべてのテストファイルで必要になる可能性がある。verify-dirty-detection.bats 以外のテストがこのパスを使用する場合は同様の修正が必要。

### 受入条件の検証困難度

- `bats tests/` の検証は CI では PASS (Ubuntu runner にはグローバル gitignore がない) だが、macOS 開発者環境では FAIL する潜在的な環境依存がある。bats テストで `.claude/` 配下パスを使用する際は `git config core.excludesFile /dev/null` が標準パターンとして必要であることを今後の Issue/Spec で周知するとよい。
- verify command `bats tests/` は適切で UNCERTAIN なし。他の verify commands (grep 系) もすべて確実に PASS を判定できた。

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec  | pr    | SUCCESS | run-spec.sh exit 0, Spec ファイル commit |
| code  | pr    | SUCCESS (manual recovery) | run-code.sh が 2 回 exit 1 (silent no-op); worktree に 3 commits が存在したが push/PR 作成が漏れていた。手動で push + PR #868 作成して回復 |
| review | pr   | SUCCESS | run-review.sh exit 0, lightweight review PASS |
| merge | pr    | SUCCESS | run-merge.sh exit 0, squash-merge 完了 |
| verify | -    | SUCCESS (pre-merge全PASS) | post-merge manual 1 件残り → phase/verify |

### Orchestration Anomalies
- `run-code.sh` で **silent no-op パターン** が 2 回連続発生:
  - 1 回目: claude exit 0 だが branch/commit 未作成
  - 2 回目: 自動で stale worktree cleanup → branch 削除後、claude 実行で 3 commits を作成したが、push と PR 作成が漏れて exit 1
  - Tier 3 recovery sub-agent は `action=abort` を返した (rationale が「worktree-code+issue-859 was deleted」と誤判定; 実際には 2 回目の実行で commits は作成されていた)
- 手動回復手順: `git push -u origin worktree-code+issue-859` → `gh pr create` → `reconcile-phase-state.sh --check-completion` で `matches_expected: true` 確認 → 後続 phases (review/merge/verify) を継続

### Improvement Proposals
- **`run-code.sh` の silent no-op 後 push/PR 漏れ自動回復**: `reconcile-phase-state.sh --check-completion` 失敗時に worktree の `git log origin/main..HEAD` を確認し、unpushed commits があれば自動で push + PR 作成を試みる recovery を Tier 2 fallback catalog に追加する (push-and-pr fallback パターン)
- **Tier 3 recovery sub-agent の rationale 精度向上**: 「branch was deleted」判定が誤りだったケース。現在の worktree HEAD と branch tip を実際に確認してから rationale を構築する仕組みが必要 (現状は log tail と reconcile snapshot のみ参照)
- **silent no-op 連続発生時の早期 escalation**: 同じ phase で 2 回連続 silent no-op が出た時点で Tier 3 を待たず即時に手動介入を促す banner を出す (15 分 × 2 = 30 分の wall time が失われる前に user 通知)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec ファイル名が `tests/check-verify-dirty.bats` (不存在) を参照していた問題を /issue 段階の audit で検出して修正した。/issue の AC verify command 監査が機能した好例。

#### design
- 4 分類ロジック (self/other-worktree/other-session/parent-main) の境界が明確で、後段の実装/review/verify で一切の解釈ブレが発生しなかった。

#### code
- silent no-op パターンの 2 回連続発生 → 手動回復で吸収。Improvement Proposals (Auto Retrospective) 参照。

#### review
- bats テストの macOS 環境依存問題を /review が SHOULD として検出・解決。`git config core.excludesFile /dev/null` 設定を test に追加。

#### merge
- 衝突なし、CI 5/5 PASS、squash-merge 完了。問題なし。

#### verify
- Pre-merge 4 件全 PASS。post-merge manual 観察 1 件は phase/verify で保留。`bats tests/` 1052/0 で既存挙動の維持を確認。

### Improvement Proposals
- (Auto Retrospective の Improvement Proposals を参照: silent no-op 後 push/PR 漏れ自動回復、Tier 3 rationale 精度向上、連続失敗の早期 escalation)
