# Issue #824: auto: loop-state heartbeat / auto-events-rollup の auto-commit 化で dirty file friction を解消

## Overview

`/auto --batch` session で `loop-state-*.md` / `auto-events-rollup-*.md` が dirty 状態になることで、各 Issue の `/verify` 開始前に `git stash → pull → stash pop → add → commit → push` の手動シーケンスが必要になる friction を構造的に解消する。

- `append-loop-state-heartbeat.sh` の末尾に best-effort auto-commit + push ロジックを追加し、heartbeat 記録直後にコミットする
- `auto-events-rollup.sh` の末尾にも同様の best-effort auto-commit + push ロジックを追加する
- `check-verify-dirty.sh` の built-in ignore_patterns に `auto-events-rollup-*.md` を追加 (auto-commit 失敗時のフォールバック、`loop-state-*.md` パターンとの一貫性)
- 各スクリプトの bats テストに auto-commit 動作 (mock git) テストを追加し、`verify-dirty-detection.bats` に `auto-events-rollup-*.md` の exempt テストを追加する

#798 の解決 (loop-state dirty → verify ブロックの解消) を補強し、git pull 前の stash friction も含めて構造的に排除する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved ambiguity points (AC2 アプローチ = auto-commit + verify-side exemption デュアル対策; AC4 verify command 修正; AC3 スコープ拡張) — 2026-06-28T17:34:34Z

## Changed Files

- `scripts/append-loop-state-heartbeat.sh`: 末尾 (final `exit 0` 前) に best-effort auto-commit シーケンス (`git add "$FILE"` → `git commit -s` → `git push origin HEAD`) を追加。失敗時は warning を stderr に出力して `exit 0` を維持 — bash 3.2+ compatible
- `scripts/auto-events-rollup.sh`: 末尾 (`echo "Rollup complete: ..."` 直後) に best-effort auto-commit シーケンス (`git add "$OUTPUT_FILE"` → `git commit -s` → `git push origin HEAD`) を追加。`set -euo pipefail` 環境のため `||` で warning 出力に fallback — bash 3.2+ compatible
- `scripts/check-verify-dirty.sh`: built-in exempt 追加 — `ignore_patterns+=("docs/sessions/_daily/auto-events-rollup-*.md")` を既存の `loop-state-*.md` 行の直後に挿入 — bash 3.2+ compatible
- `tests/append-loop-state-heartbeat.bats`: auto-commit mock test 追加 (PATH-based git mock で `git commit` 呼び出しを assert)
- `tests/auto-events-rollup.bats`: auto-commit mock test 追加 (PATH-based git mock で `git commit` 呼び出しを assert)
- `tests/verify-dirty-detection.bats`: `auto-events-rollup-*.md` dirty → exit 0 (built-in exempt) テストを追加

## Implementation Steps

1. `scripts/check-verify-dirty.sh`: 既存の `ignore_patterns+=("docs/sessions/_daily/loop-state-*.md")` 行 (L62) の直後に `ignore_patterns+=("docs/sessions/_daily/auto-events-rollup-*.md")` を挿入 (→ AC2 verify-dirty exempt)
2. `scripts/append-loop-state-heartbeat.sh`: 末尾の `exit 0` の直前に auto-commit シーケンスを追加。`git -C "$REPO_ROOT"` 形式でリポジトリルートを明示的に指定。失敗しても `exit 0` を維持する best-effort 設計:
   ```bash
   git -C "$REPO_ROOT" add "$FILE" 2>/dev/null && \
   git -C "$REPO_ROOT" commit -s -m "chore: loop-state heartbeat auto-commit $DATE [skip ci]" 2>/dev/null && \
   git -C "$REPO_ROOT" push origin HEAD 2>/dev/null || \
   echo "append-loop-state-heartbeat.sh: WARNING — auto-commit failed (non-fatal)" >&2
   ```
   (→ AC1)
3. `scripts/auto-events-rollup.sh`: 末尾の `echo "Rollup complete: ${OUTPUT_FILE}"` 行の後に auto-commit シーケンスを追加。`set -euo pipefail` 環境のため `||` fallback で warning 出力してスクリプトを継続:
   ```bash
   git add "$OUTPUT_FILE" 2>/dev/null && \
   git commit -s -m "chore: auto-events-rollup auto-commit $TARGET_DATE [skip ci]" 2>/dev/null && \
   git push origin HEAD 2>/dev/null || \
   echo "Warning: auto-commit failed (non-fatal)" >&2
   ```
   (→ AC2)
4. `tests/append-loop-state-heartbeat.bats`: PATH ベースの git mock (ログファイルへコマンドを記録) を使って auto-commit が呼び出されることを assert するテストを追加。既存の `_make_wrapper` + `MOCK_DIR` パターンを踏襲 (→ AC3)
5. `tests/auto-events-rollup.bats` と `tests/verify-dirty-detection.bats` にそれぞれ:
   - `auto-events-rollup.bats`: git mock で `git commit` 呼び出し assert (→ AC3)
   - `verify-dirty-detection.bats`: `auto-events-rollup-2026-06-28.md` dirty → `exit 0` + warning メッセージ assert。既存の `loop-state heartbeat only dirty` テスト (L137) と同パターン (→ AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/append-loop-state-heartbeat.sh の末尾に、git add + git commit -s + git push origin HEAD の best-effort シーケンスが追加されており、失敗時は warning のみで return 0 する設計になっている" --> <!-- verify: file_contains "scripts/append-loop-state-heartbeat.sh" "commit -s" --> `scripts/append-loop-state-heartbeat.sh` 末尾に heartbeat 追加後の auto-commit + push (best-effort) ロジックが追加されている
- <!-- verify: file_contains "scripts/auto-events-rollup.sh" "git commit" --> <!-- verify: file_contains "scripts/check-verify-dirty.sh" "auto-events-rollup" --> `scripts/auto-events-rollup.sh` にも auto-commit + push (best-effort) ロジックが追加されており、かつ `scripts/check-verify-dirty.sh` が `auto-events-rollup-*.md` を ignore_patterns で除外している
- <!-- verify: grep "git commit" "tests/append-loop-state-heartbeat.bats" --> <!-- verify: grep "git commit" "tests/auto-events-rollup.bats" --> <!-- verify: command "bats tests/append-loop-state-heartbeat.bats" --> <!-- verify: command "bats tests/auto-events-rollup.bats" --> `tests/append-loop-state-heartbeat.bats` および `tests/auto-events-rollup.bats` で auto-commit 動作 (mock git environment) がそれぞれ assert されている
- <!-- verify: grep "auto-events-rollup" "tests/verify-dirty-detection.bats" --> <!-- verify: command "bats tests/verify-dirty-detection.bats" --> `tests/verify-dirty-detection.bats` に `auto-events-rollup-*.md` が dirty でも verify dirty 検出から exempt されることを assert するテストが追加されている

### Post-merge

- 次回 `/auto --batch` 実行で `loop-state-*.md` / `auto-events-rollup-*.md` 由来の dirty file friction が発生しないことを観察

## Code Retrospective

### Deviations from Design

- AC1 verify command `file_contains "scripts/append-loop-state-heartbeat.sh" "git commit"` was miscalibrated: the Spec-mandated `git -C "$REPO_ROOT" commit` form does not contain "git commit" as a contiguous substring. Corrected to `file_contains "scripts/append-loop-state-heartbeat.sh" "commit -s"` in both the Issue body and this Spec (Step 10 case 2: miscalibrated hint).
- No deviations from the implementation steps themselves — all 5 steps in the Spec were implemented as specified.

### Design Gaps/Ambiguities

- The early-exit paths in `auto-events-rollup.sh` (no input data / no events for date) also write to `$OUTPUT_FILE` but were not given auto-commit per the Spec ("末尾の echo Rollup complete 行の後" only). This is acceptable because those early paths are edge cases unlikely to generate friction.
- The `git -C "$REPO_ROOT"` form in `append-loop-state-heartbeat.sh` is necessary because the script can be invoked from any CWD (not necessarily the repo root). This distinction from `auto-events-rollup.sh` (which runs from the project CWD) was correctly captured in the Spec Notes.

### Rework

- One additional commit (`Fix miscalibrated verify command in spec for issue #824`) was needed to fix the Spec verify command before PR creation, because the initial implementation commit did not update the Spec verify command to match the corrected form.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #835 squash-merged to main (base branch = main, Issue auto-close via `closes #824` will trigger).
- No conflict resolution was needed — PR was mergeable=true/clean at time of merge.
- Phase Handoff written to Spec and pushed to main for verify to consume.

### Deferred Items

- Post-merge observation: verify that `loop-state-*.md` / `auto-events-rollup-*.md` dirty file friction is eliminated in the next `/auto --batch` run (manual observation required — not automatable).
- Optional fix for false warning when `git commit` runs on an unchanged `$OUTPUT_FILE` (CONSIDER — non-fatal, cosmetic).

### Notes for Next Phase

- The `[skip ci]` suffix on heartbeat/rollup auto-commits prevents CI from being triggered — confirm this behavior is working post-merge.
- Dual defense pattern (auto-commit primary + verify-side exempt fallback) is the intended design; verify should not remove either layer.
- Post-merge AC: observe next `/auto --batch` run for absence of dirty file friction from `loop-state-*.md` and `auto-events-rollup-*.md`.

## Notes

- `append-loop-state-heartbeat.sh` は `set -uo pipefail` (no `-e`) を使用しているため、git コマンド失敗時も `||` fallback を使えば `exit 0` を保てる。`auto-events-rollup.sh` は `set -euo pipefail` (with `-e`) を使用しているため、`||` での fallback が必須
- `append-loop-state-heartbeat.sh` の auto-commit は `git -C "$REPO_ROOT"` でリポジトリルートを明示。`auto-events-rollup.sh` はカレントディレクトリのリポジトリに対して git を実行する (呼び出し元がユーザープロジェクトの CWD を持つ前提)
- Commit メッセージに `[skip ci]` を付与して heartbeat 起因の CI トリガーを防止する
- `tests/append-loop-state-heartbeat.bats` は `_make_wrapper` + PATH-based mock パターンを採用。auto-commit テストも同じ `MOCK_DIR/git` mock を追加することで既存テストとの一貫性を維持
- `tests/auto-events-rollup.bats` は現在 git mock なし。git mock を `setup()` に追加するか、テスト内でローカルに追加する (既存テストへの影響を最小限に抑えるため、テスト内ローカル追加を推奨)
- auto-commit 失敗は非致命的 (warning + exit 0) — 次回の heartbeat / rollup 実行時に再試行される
- Issue Retrospective から消費: AC2 はデュアル対策 (auto-commit + verify-side exemption) を採用。AC4 は `bats tests/verify-dirty-detection.bats` テストで検証する形式に変更済み (元の `|| true` command は検証不能なため)

## review retrospective

### Spec vs. 実装乖離パターン

特記すべき乖離なし。Phase Handoff に記録された通り、AC1 verify command の `file_contains "git commit"` → `"commit -s"` 修正が code phase で既に対応済みで、Spec と Issue body 両方に反映されていた。`git -C "$REPO_ROOT"` 形式と `git commit` の関係はコードレビュー時に引き続き注意が必要な落とし穴パターン。

### 再発 Issue

特記なし。MUST/SHOULD Issue はゼロ。`auto-events-rollup.sh` で「nothing to commit」時に false warning が発生する可能性 (CONSIDER) は記録したが、実用上の影響は軽微。

### 受入条件の検証難易度

全 10 件の verify command を safe mode で処理済み。`command` ベース 4 件 (bats テスト実行) は CI "Run bats tests" SUCCESS を代替検証として利用し PASS と判定した。rubric check は AI 判断でシームレスに実行できた。verify command の calibration は既に code phase で修正済みであり、今回の review では全 UNCERTAIN ゼロで完了した。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 3 件の ambiguity (AC2 アプローチ、AC4 verify command、AC3 bats scope) を自動解決。特に AC4 の `|| true` で常に PASS になる検証不能 command を `grep + bats command` に置換した判断は適切。

#### spec
- 3 アプローチ (A: gitignore / B: auto-commit / C: verify-side exemption) を併記し、デュアル対策 (B + C) を採択。`auto-events-rollup.sh` の `set -e` の違いに気付き fallback を `||` で書く設計判断が code phase の安定性に寄与。

#### code
- AC1 verify command の miscalibration (`file_contains "git commit"` → `"commit -s"`) が初回コミット後に発覚し、後続 commit で修正。`git -C "$REPO_ROOT"` 形式は `file_contains "git commit"` にマッチしない落とし穴。

#### review
- MUST/SHOULD ゼロ。CONSIDER 1 件 (`auto-events-rollup.sh` で nothing to commit 時の false warning) を deferred 扱いに記録。

#### merge
- PR #835 conflict なし、CI 緑、approved 状態で squash merge。`[skip ci]` 付与で heartbeat 起因の CI トリガーを防止。

#### verify
- 4 件 pre-merge AC が全 PASS。bats 11/11 + 9/9 + 14/14。verify-dirty-detection.bats の test 13/14 で auto-events-rollup の exempt 動作も確認。

### Improvement Proposals

- `auto-events-rollup.sh` で commit 対象に変更がない場合 (`nothing to commit`) に warning が出る現状を `git diff --quiet` 等で事前判定して silent skip させる小修正を後続 Issue で対応。cosmetic だが log の S/N 比を改善する。
- `git -C "$REPO_ROOT" commit` 等の git invocation 形式が `file_contains "git commit"` verify command にマッチしない問題が code phase で 1 commit 分の修正コストを発生させた。`verify-classifier.md` または `/issue` skill の verify command 生成ロジックに「git invocation は contiguous でないことが多いため `commit -s` 等の sub-string を選ぶ」ガイドラインを追加する Issue を起票推奨。本セッションでも同種 calibration が #823, #824 で連続発生しているため再発性あり。

