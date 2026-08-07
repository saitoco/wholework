# Issue #1212: verify-classifier: patch route の CI 検証 AC の run 参照形を是正し推奨形を SSoT に一本化

## Overview

patch route の CI 検証 AC の正準形 (`modules/verify-classifier.md:161`) は `--commit=$(git rev-parse HEAD)` を含む。この形には独立した 2 つの欠陥がある — 欠陥 A (HEAD 依存: `/verify` 実行時点の main 先端を参照するため無関係なコミットの CI を検証しうる) と欠陥 B (実装コミットに run が存在しない: GitHub Actions は push の先頭コミットにのみ run を作るため、patch route の [実装コミット, retrospective コミット] という push 構成では実装コミット自身の run が常に空になる)。加えて `--commit` の有無が `modules/verify-classifier.md`・`skills/issue/SKILL.md`・`skills/verify/SKILL.md`・`modules/verify-patterns.md` の 4 箇所で不統一。本 Issue はこれを解消し、`modules/verify-classifier.md` を SSoT として推奨形を一本化する。

Step 6 のコードベース調査で、4 箇所の `gh run list --limit=1` 系フォームがいずれも `--branch` を指定しておらず、`.github/workflows/test.yml` のブランチ無制限トリガー設定と組み合わさって worktree ブランチ・PR ブランチの無関係な run を拾いうる欠陥 (欠陥 C、Issue 本文未記載) を新たに発見した。`--commit` を外すだけの方針 (a) は欠陥 C を伴わない限り欠陥 A より高頻度の false PASS/FAIL を招くため、`--branch=main` の追加を方針 (a) の必須の一部として実施する (詳細は Root Cause と Notes を参照)。

## Reproduction Steps

1. patch route で Issue を実装すると、Step 11 で [実装コミット, retrospective コミット] が同一 push で送られる (実測例: #1210 の `6a08557c` → `599fb8a4`)。
2. `gh run list --workflow=test.yml --commit=<実装コミット SHA> --limit=3` を実行すると `[]` が返る — push の head (retrospective コミット) だけが run を持つため。本 Spec 作成時に #1210 の実コミット `6a08557ca4a422e6248f98580167e8cdb917a1d7` で再実測し確認済み (空配列)。
3. `--commit` を外して `gh run list --workflow=test.yml --limit=8` を実行すると、`main` だけでなく `worktree-verify+issue-476` や `worktree-code+issue-1082` など無関係な worktree ブランチの run が直近順に混在する。本 Spec 作成時 (2026-08-07) に本リポジトリで実測し確認済み。
4. `/verify` 実行時、worktree HEAD は base ブランチの現在の先端に解決される。並行セッションが常態のこのリポジトリでは、その先端が同一 push の retrospective コミットと一致するとは限らない — 一致すれば偶然 PASS、別セッションのコミットに解決されれば無関係な CI 結果を参照する。

## Root Cause

### 欠陥 A: HEAD 依存 (#1133 で記録済み)

`--commit=$(git rev-parse HEAD)` はコマンド文字列として保存され、`/verify` 実行時に評価される。このため「実装コミット」ではなく「その時点の base ブランチ先端」を指す。既知の観測は #1133・#1102・#1210 の 3 件 (Issue 本文 Related 参照)。

### 欠陥 B: 実装コミットに run が存在しない (#1102, #1210 で実測)

GitHub Actions は push の先頭コミットにのみ workflow run を作る。patch route は実装コミットと retrospective コミットを同一 push で送るため、run の `head_sha` は常に retrospective コミットであり、実装コミット自身の run は存在しない。`--commit=<実装コミット SHA>` は常に空配列を返し、`/verify` は PASS/FAIL を判定できない。retrospective コミットは Spec ファイルのみを変更するため、push の `head_sha` の run が指すツリーは実装のツリーと等価 — 「対象ブランチの直近 run」を参照する (`--commit` を外す) ことは妥当な代替になりうる。

### 欠陥 C (今回のコードベース調査で新規発見): `--branch` フィルタの欠落

`modules/verify-classifier.md`・`skills/issue/SKILL.md`・`skills/verify/SKILL.md`・`modules/verify-patterns.md`・`skills/issue/spec-test-guidelines.md` の `gh run list --limit=1` 系フォームはいずれも `--branch` を指定していない。`.github/workflows/test.yml` は `on: push:` / `on: pull_request:` にブランチ制限がなく、worktree ブランチ・PR ブランチも含めたリポジトリ全体で直近の run を拾う。2026-08-07 時点の実測:

```
$ gh run list --workflow=test.yml --limit=8 --json conclusion,headBranch,event
(headBranch: worktree-verify+issue-476, worktree-code+issue-1082, worktree-code+issue-1075 ... が push/pull_request イベントとして直近順に並ぶ — main の run は含まれない)
```

`--commit` を外すだけの方針 (a) 単独採用は、この欠陥 C を伴わないと「無関係なブランチの直近 run」を参照してしまい、欠陥 A よりも高頻度で false PASS/FAIL を引き起こす。`--branch=main` の追加は方針 (a) を安全に成立させるために必須。

### 補足実測: main の CI は並行セッションの影響で頻繁に cancelled/failure になる

2026-08-07 時点で `gh run list --workflow=test.yml --branch=main --limit=15` を実測したところ、直近の run に `cancelled` (新しい push による supersede) や `failure` が複数含まれていた。`--branch=main --limit=1` を採用しても「直近 run が本 Issue の実装を反映している」保証はなく、この残存リスクは方針 (a) 単独では解消しない (Notes 参照)。

## Changed Files

- `modules/verify-classifier.md`: Patch Route CI Verification Note の canonical form から `--commit=$(git rev-parse HEAD)` を削除し `--branch=main` を追加。`head_sha` を用いた run/コミット対応関係の説明と、defect A の残存リスク・UNCERTAIN フォールバック指針を追記 (SSoT)
- `skills/issue/SKILL.md`: line 786 の patch route 例に `--branch=main` を追加、SSoT に整合
- `skills/verify/SKILL.md`: line 224 の "Example replacement" 内 patch route 例に `--branch=main` を追加
- `modules/verify-patterns.md`: `gh run list --limit=1` 系の 4 箇所 (line 39 Gotchas 表, line 177 DCO 例, line 198 Preferred pattern 1, line 223 job-level sub-form) に `--branch=main` を追加
- `skills/issue/spec-test-guidelines.md`: line 47, 79 の patch route 例から `--commit=$(git rev-parse HEAD)` を削除し `--branch=main` に統一 (bats テストが 2 箇所の存在を assert しているため両方修正必須)
- `skills/code/SKILL.md`: Step 10 (Verify Command Consistency) に、patch route の commit-scoped `github_check "gh run list"` CI AC は実装コミットが存在する前 (Step 11 の commit/push 前) に評価しても意味を持たないため、この Step の verify-executor パス対象から除外する旨のノートを追加 (Issue コメント #2 への対応)
- `tests/verify-executor.bats`: `--commit`/`git rev-parse HEAD` の存在を assert していたテスト 4 件を `--branch` の存在を assert する形に書き換え、孤立する bash subshell テスト 1 件を削除。ファイル冒頭のコメントも新しい根拠に合わせて更新 — bash 3.2+ 互換 (シェルスクリプトではなく bats テストファイルのため既存の bats 記法をそのまま踏襲)

## Implementation Steps

1. `modules/verify-classifier.md` の Patch Route CI Verification Note を修正: canonical form から `--commit=$(git rev-parse HEAD)` を削除し `--branch=main` を追加、`head_sha` を用いた run/コミット対応関係の説明、および defect A の残存リスクと UNCERTAIN フォールバック指針を追記する (→ acceptance criteria AC1, AC2)
2. `skills/issue/SKILL.md`、`skills/verify/SKILL.md`、`modules/verify-patterns.md`、`skills/issue/spec-test-guidelines.md` の `gh run list` 系 patch route 例を Step 1 の SSoT 形式 (`--branch=main`、`--commit` なし) に統一する (after 1) (→ acceptance criteria AC3)
3. `tests/verify-executor.bats` を Step 1-2 の変更に合わせて更新する: `--commit`/`git rev-parse HEAD` の assert を `--branch` の assert に置き換え、孤立した bash subshell テストを削除する (after 2) (→ CI (test.yml) を green に保つ。acceptance criteria AC4 の前提)
4. `skills/code/SKILL.md` Step 10 に、patch route の commit-scoped CI AC を Step 10 の verify-executor パス対象外とする旨のノートを追加する (parallel with 1, 2, 3) (→ Purpose 全体、Issue コメント #2 の指摘への対応。個別の AC には対応しない — Notes 参照)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-classifier.md の Patch Route CI Verification Note に、GitHub Actions が push 先頭コミットにのみ run を作るため実装コミットに run が存在しないケースがあることと、それを踏まえた推奨形が明記されている" --> 実装コミットに run が存在しないケースの挙動と推奨形が `modules/verify-classifier.md` に明記されている
- <!-- verify: file_contains "modules/verify-classifier.md" "head_sha" --> `modules/verify-classifier.md` に run と コミットの対応関係の説明が追加されている
- <!-- verify: rubric "modules/verify-classifier.md, skills/issue/SKILL.md, skills/verify/SKILL.md, modules/verify-patterns.md の 4 箇所で patch route の gh run list 形式が一致しているか、または verify-classifier.md を SSoT として他が参照に統一されている" --> 4 箇所の形式不一致が解消されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (test.yml) の bats tests job が pass する (本 Issue は Size M — pr route のため、main 参照の `gh run list` ではなく PR 自身の CI を見る `gh pr checks` を使う。2026-08-06 Triage AC audit コメント参照)

### Post-merge

- 次回 patch route Issue の `/verify` 実行で CI 検証 AC が実装コミットを含む run を参照して判定されることを観察する

## Notes

**Consumed Comments からの反映:** 2 件の first-class (MEMBER) コメントを消費した。(1) Triage AC audit — 本 Issue 自身の AC4 が Size M (pr route) にもかかわらず `gh run list --branch=main` (欠陥 A を体現する形) を使っていた点を指摘。`github_check "gh pr checks" "Run bats tests"` に修正し Issue body に反映済み (`/spec` 実行前に `gh-issue-edit.sh` で更新)。(2) 欠陥 B の 3 例目実測 (#1210) と、`skills/code/SKILL.md` Step 10 が同じ commit-scoped AC を実装コミット作成前に評価してしまう未文書化の問題を指摘。Implementation Step 4 で対応。Related に #1210, #1134 を追加し Issue body に反映済み。詳細は `## Consumed Comments` を参照。

**Auto-resolved: 対応方針は (a) を採用し、(c) は運用ガイダンスとして部分採用。** Issue 本文の対応方針候補 (a)/(b)/(c) のうち (a) `--branch=main --limit=1` を採用した。理由:
- (b) (push 単位で実装コミットの `head_sha` を逆引きし対応範囲を判定) は正確だが、実装コミットを独立に特定するロジック (`git log --grep` 等) と push 境界判定の実装が必要で、Size M / SPEC_DEPTH=light の範囲を超える設計・実装コストになる。
- (c) 単独 (常に UNCERTAIN) は、4 箇所すべてが「直近 run で判定する」運用を前提にしている既存パターンから離れすぎており、一貫性を失う。
- (a) は 4 箇所中 3 箇所 (`skills/issue/SKILL.md`、`skills/verify/SKILL.md`、`modules/verify-patterns.md`) が既にこの形に近く (`--commit` を使っていたのは `modules/verify-classifier.md` のみ)、最小変更で欠陥 B を解消できる。
- (c) の考え方 (run が実装との対応を確証できない場合は UNCERTAIN) は、`modules/verify-classifier.md` の「残存リスク」節に運用ガイダンスとして反映した (`cancelled` 等の不自然な結果を UNCERTAIN 相当として再実行を促す) — 機械的な自動判定ロジックとしては実装していない。

**Scope 拡張の判断根拠:** Issue 本文が明示した 4 箇所には含まれないが、以下 2 ファイルも変更範囲に含めた。
- `tests/verify-executor.bats`: 既存テスト 4 件が `modules/verify-classifier.md`/`skills/issue/spec-test-guidelines.md` 両方の `--commit`/`git rev-parse HEAD` の存在を assert しており、`--commit` 削除で確実に FAIL する。CI を green に保つための必須修正。
- `skills/issue/spec-test-guidelines.md`: `/issue` が bats テスト AC を書く際に参照する教育用サンプル。SSoT (`verify-classifier.md`) と異なる形 (`--commit` あり) を教え続けると新たな不整合を生むため、`tests/verify-executor.bats` の既存テストとあわせて修正した。

**Deferred (未着手、フォローアップ推奨):** コードベース調査で、同じ `gh run list ... --limit=1` パターン (`--branch` 欠落) が以下にも見つかった — `modules/verify-executor.md` (job-level sub-form の例)、`skills/spec/SKILL.md` (本スキル自身の Step 10 における patch route auto-fix ロジック)、`skills/triage/skill-dev-verify-audit.md` (Pattern 4 の Fix 例 — 本 Issue のコメント 1 の Triage AC audit を生成した audit ロジックそのもの)。Issue 本文が明示した 4 箇所 + 直接関連する 2 ファイル (`tests/verify-executor.bats`, `skills/issue/spec-test-guidelines.md`) に範囲を絞り、これらは未修正のまま残す。特に `skill-dev-verify-audit.md` Pattern 4 は将来の triage audit が `--branch` なしの旧形を「修復案」として提示し続けるため、フォローアップ Issue での追随修正を推奨する。

**残存リスク (defect A の完全解消ではない):** 方針 (a) + `--branch` 追加後も、`/verify` 実行時点で「対象ブランチの直近 run」が本 Issue の実装 push によるものである保証はない。並行セッションが同じブランチに追加コミットを push すれば、その run が「直近」になる。この残存リスクは `modules/verify-classifier.md` の「残存リスク」節に明記した。完全な解消 (push 境界を認識した方針 (b)) は本 Issue のスコープ外。

**Issue #1212 自身の AC4 修正について:** 本 Spec 作成の一環として、Issue body の AC4 verify command を `github_check "gh run list --workflow=test.yml --branch=main --limit=1 ..." "success"` から `github_check "gh pr checks" "Run bats tests"` に修正した (Consumed Comments の (1) 参照)。本 Issue 自身が Size M / pr route であるため、patch route 向けの `gh run list` 形式ではなく `gh pr checks` 形式が正しい。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: Triage AC audit — Issue 本文の AC4 verify command が pr route (Size M) にもかかわらず `gh run list --branch=main` 形式を使っており、本 Issue が是正対象とする欠陥 A をそのまま体現していると指摘。`gh pr checks "Run bats tests"` への修正を提案 / URL: https://github.com/saitoco/wholework/issues/1212#issuecomment-5205304798
- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: 欠陥 B の 3 例目実測 (#1210) の記録、および `skills/code/SKILL.md` Step 10 が実装コミット作成前に同じ commit-scoped AC を評価してしまう未文書化の問題を指摘。対応方針確定時にこの評価タイミングの扱いも SSoT に含めるかの判断を要請 / URL: https://github.com/saitoco/wholework/issues/1212#issuecomment-5206424811

## Code Retrospective

### Deviations from Design
- None. Implementation Steps 1-4 were applied as specified.

### Design Gaps/Ambiguities
- None beyond what the Spec's Notes section already resolved (route selection, scope boundary).

### Rework
- The initial "why `--commit` is not used" explanation in `modules/verify-classifier.md` quoted the deprecated `--commit=$(git rev-parse HEAD)` form as one contiguous string. This tripped the new negative-assertion bats test (`! grep -q -- '--commit=$(git rev-parse HEAD)'`) against the SSoT file's own explanatory prose, not a live command. Reworded to separate the `git rev-parse HEAD` mention from the literal `--commit=` prefix so the explanation no longer contains the deprecated form as a contiguous substring.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Merged under a recorded pre-merge-ac-gate override (`decision=override`, `fallback=true`) — `/review`'s Step 12.2 (commit/push) ended in a silent no-op after MUST/SHOULD findings were applied but left uncommitted; a parent session verified the diff, ran the full suite (1495 pass), and committed/pushed as `e878a321` before merge proceeded.
- Squash-merged PR #1222 into `main` as `9a8b3c55`; all 4 pre-merge ACs were checked at gate time.

### Deferred Items
- The 3 locations the Spec's Notes section marked "Deferred" (`modules/verify-executor.md` job-level sub-form, `skills/spec/SKILL.md` Step 10, `skills/triage/skill-dev-verify-audit.md` Pattern 4) still lack `--branch=main`; no follow-up Issue was filed by this run.
- Root cause of the review-phase silent no-op (background test-run notification never arriving) is tracked separately in Issue #1213, not in this Issue's scope.

### Notes for Next Phase
- `/verify` should confirm the post-merge observation AC: the next patch-route Issue's `/verify` run should reference a CI run that includes the implementation commit (`head_sha`-based), not an unrelated prior run.
- No other outstanding risks identified during merge.
