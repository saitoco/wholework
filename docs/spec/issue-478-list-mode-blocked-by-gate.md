# Issue #478: auto: List mode Blocked-by Gate for Manual Post-merge Pending

## Overview

`/auto --batch N1 N2 ...` の List mode において、blocked-by 先 Issue が manual post-merge 条件未完了（`phase/verify` OPEN 等）のまま次 Issue の処理を開始してしまう問題を修正する。

修正方針（Option A）: 各 Issue の `run-auto-sub.sh` 実行前に、Issue body の blocked-by 関係を確認する。blocker が CLOSED または `phase/done` であれば処理続行、それ以外はスキップして `remaining` に保持し、`/auto --batch --resume` で再試行可能にする。

## Reproduction Steps

1. `/auto --batch A B C` を実行（B は `blocked-by A`、C は `blocked-by A`）
2. A の `run-auto-sub.sh` が exit 0 で完了するが、A の post-merge 条件に `verify-type: manual` が含まれており `phase/verify` OPEN のまま
3. List mode は A の exit 0 を「処理完了」とみなし、即座に B の処理を開始してしまう

## Root Cause

`run-auto-sub.sh` は verify を親セッションに委ねて exit 0 するため（issue #485）、exit 0 が A の manual post-merge 条件完了を意味しない。`### List mode` のステップに blocked-by の phase 状態チェックが存在しない。

## Changed Files

- `skills/auto/SKILL.md`: `### List mode` に blocked-by フェーズチェック（新ステップ 4）を追加；旧ステップ 4→5、5→6 に番号繰り下げ — bash 3.2+ 互換（awk/grep のみ使用）
- `tests/auto-batch.bats`: blocked-by チェックの構造テスト 3 件追加
- `docs/workflow.md`: `--batch N1 N2 ...` の説明に blocked-by ゲートの記述を追加
- `docs/ja/workflow.md`: `docs/workflow.md` と同箇所を日本語で同期更新

## Implementation Steps

1. `skills/auto/SKILL.md` の `### List mode` に新ステップ 4「Blocked-by check」を追加（→ AC 1, 2, 3）:
   - 現在のステップ 4（`run-auto-sub.sh`）の直前に挿入。旧ステップ 4 → 5、旧ステップ 5 → 6 に繰り下げ。
   - 新ステップ 4 の内容:
     - Issue body から "blocked by #N" パターン（大文字小文字無視）で blocker 番号を抽出:
       `gh issue view $NUMBER --json body -q '.body' | grep -ioE "blocked by #[0-9]+" | grep -oE "[0-9]+"` 
     - blocker が存在しない場合はスキップ（次のステップへ）
     - 各 blocker について: `gh issue view $BLOCKER --json state,labels -q '{state: .state, phases: [.labels[].name | select(startswith("phase/"))]}'`
       - CLOSED または labels に `phase/done` を含む → ゲート解除（次の blocker をチェック）
       - それ以外 → 警告を出力して当該 Issue をスキップ（`update_batch` は呼ばない — `remaining` に保持）:
         ```
         Warning: #$NUMBER blocked by #$BLOCKER which is $BLOCKER_PHASE (manual post-merge pending). Skipping #$NUMBER. After completing #$BLOCKER manually, resume with /auto --batch --resume.
         ```
         （$BLOCKER_PHASE は blocker の `phase/*` ラベルまたは OPEN 状態から取得）

2. `tests/auto-batch.bats` に 3 件の `@test` を追加（→ AC 5 の CI 通過）:
   - `@test "List mode section: blocked-by check present"` — `### List mode` セクションに "blocked" が含まれるか
   - `@test "List mode section: phase/done gate condition present"` — `### List mode` セクションに "phase/done" が含まれるか
   - `@test "List mode section: --batch --resume in blocked warning present"` — `### List mode` セクションに "--batch --resume" が含まれるか

3. `docs/workflow.md` の `--batch N1 N2 ...` 説明（3 文目以降）を更新:
   - 「Before running each Issue, the parent session checks for `blocked-by` relationships in the Issue body: if a blocker is not yet CLOSED or `phase/done`, the Issue is skipped and kept in `remaining` for retry via `/auto --batch --resume`.」を先頭に追加

4. `docs/ja/workflow.md` を対応箇所（`--batch N1 N2 ...` の説明）で同期更新（日本語）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "blocked" --> `### List mode` セクションに blocked-by チェック手順が追加される
- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "phase/done" --> blocker が CLOSED または `phase/done` の場合のみ処理続行する条件が追加される
- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "--batch --resume" --> スキップ時の警告メッセージに resume 方法が含まれる
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/auto/SKILL.md" --> `skills/auto/SKILL.md` の syntax validation が通過する
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) が成功する（patch 経路）

### Post-merge

- `/auto --batch A B C` で A が `phase/verify` OPEN の場合、B の処理がスキップされ適切な警告メッセージが出力される <!-- verify-type: manual -->
- スキップされた B が checkpoint の `remaining` に保持され、A の manual 条件完了後に `/auto --batch --resume` で再処理できる <!-- verify-type: manual -->

## Notes

- `update_batch fail` を呼ばないことで NUMBER が `remaining` に保持される。`update_batch fail` を呼ぶと `failed` に移動してしまい、resume で再試行できなくなる。
- 既存の `gh-check-blocking.sh` は CLOSED/OPEN のみを判定し `phase/done` チェックは行わないため、SKILL.md にインラインで記述する。
- `### List mode` のステップ番号変更: 旧 4 → 5（run-auto-sub.sh）、旧 5 → 6（Verify orchestration）。
- `docs/ja/workflow.md` は `docs/translation-workflow.md` の sync 規約により更新対象。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- Spec の警告メッセージ例では `$BLOCKER_PHASE` を「blocker の `phase/*` ラベルまたは OPEN 状態から取得」と示していたが、SKILL.md の実装記述では "first `phase/*` label of blocker, or `"OPEN"` if no `phase/*` label" と明確化した。Spec の記述をそのまま踏襲した。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Blocked-by チェックを step 3（Size チェック）と step 4（run-auto-sub.sh）の間に挿入し、旧ステップ 4→5、5→6 に繰り下げ。Resume 連携のため `update_batch` を呼ばずに `remaining` 保持とした。
- 警告メッセージに blocker 番号・フェーズ・resume 方法を全て含む形式を採用（Issue body の Spec 仕様に完全準拠）。
- 既存の `gh-check-blocking.sh` は `phase/done` チェックを持たないため SKILL.md にインラインで記述。

### Deferred Items
- 実際の動作検証（post-merge manual AC）は verify フェーズで手動確認が必要。
- `gh-check-blocking.sh` を `phase/done` 対応に更新する改善は後続 Issue 候補。

### Notes for Next Phase
- 全 pre-merge AC（section_contains 3件 + validate-skill-syntax 1件）はローカル検証 PASS 済み。CI (test.yml) は push 後に確認が必要。
- tests/auto-batch.bats に 3件追加（合計 6件、全 PASS 確認済み）。
- docs/workflow.md と docs/ja/workflow.md 両方更新済み。
