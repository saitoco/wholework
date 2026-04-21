# Issue #308: auto: watchdog timeout interrupts push/PR on code phase

## Overview

`/auto` の code phase で Sonnet の long-thinking が 30 分間続き、watchdog (1800s 無音検出) が SIGTERM kill した。
`watchdog-reconcile.sh` の `code-pr` 判定は「open PR が存在するか」のみを確認するため、「実装 commit 完了・push/PR 未作成」の中間状態では exit 143 のまま終了し、`/auto` 全体が手動回復を要した。

2 つの独立した問題が重なっている:
1. watchdog が stdout ベースの無音検出のため、thinking 中は常にリスクがある
2. reconcile が「最終状態（PR 存在）」しか確認しないため、中間状態からの自動回復ができない

## Reproduction Steps

1. `/auto N` で Size M/L Issue を実行（`--pr` route）
2. code phase で Claude が PR body 草案等を長時間 thinking（stdout 出力なし）
3. 30 分後 watchdog が SIGTERM kill（exit 143）
4. `watchdog-reconcile.sh code-pr N` が open PR を確認 → 存在しない → exit 143
5. `/auto` が exit 143 を受け取り手動回復が必要な状態で停止

## Root Cause

**問題 1 (Prevention)**: `skills/code/SKILL.md` の Step 11 (PR 作成) と Step 12 (push) の直前に stdout 出力がない。
Claude が PR body 草案を thinking 中、または push 前に長時間無音になると watchdog の 1800s を超える。

**問題 2 (Recovery)**: `_reconcile_code_pr` が open PR の存在のみを確認する。
commit 完了・push/PR 未作成の中間状態（ worktree に commits あり、remote branch なし）では reconcile できない。

修正方針: **Approach D（SKILL.md 進捗出力）+ Approach C（reconcile 強化）**

## Changed Files

- `docs/reports/watchdog-recovery-strategy.md`: new file — Approach A〜D の比較分析と採用方針
- `skills/code/SKILL.md`: Step 11 (pr route `gh pr create` 直前) と Step 12 (pr route `git push origin HEAD` 直前) に progress echo 指示を追加
- `scripts/watchdog-reconcile.sh`: `_reconcile_code_pr` に Stage 2 を追加（worktree branch + commit 検出 → push + PR 作成） — bash 3.2+ compatible
- `tests/watchdog-reconcile.bats`: Stage 2 のテストケースを追加（branch あり commit あり → exit 0、branch あり commit なし → exit 143、push 失敗 → exit 143）

## Implementation Steps

1. `docs/reports/watchdog-recovery-strategy.md` を作成する (→ AC 1, 2, 3)
   - Approach A/B/C/D の比較表（メリット・デメリット）を記載
   - 採用方針「Approach D + C の組み合わせ」を選定理由とともに明記
   - 報告書ヘッダー（report date: 2026-04-21, Issue: #308, Scope: watchdog recovery strategy）を含める

2. `skills/code/SKILL.md` を更新する（Approach D）(after 1) (→ AC 4)
   - Step 11 pr route の `gh pr create` 直前に「`echo "progress: Creating PR for issue #$NUMBER..."` を実行してから PR 作成に進む」旨の指示を追加
   - Step 12 pr route の `git push origin HEAD` 直前に「`echo "progress: Pushing branch to origin for issue #$NUMBER..."` を実行してから push に進む」旨の指示を追加
   - 既存のステップ番号・構成は変更しない

3. `scripts/watchdog-reconcile.sh` の `_reconcile_code_pr` を強化する（Approach C）(after 1) (→ AC 4)
   - Stage 1（open PR 存在確認）はそのまま維持
   - Stage 2 を追加: worktree dir `$SCRIPT_DIR/../.claude/worktrees/code+issue-${ISSUE_NUMBER}` が存在し、かつそのブランチに `closes #${ISSUE_NUMBER}` を含む commit がある場合、`git -C <worktree_dir> push origin HEAD` → `gh pr create --head "worktree-code+issue-${ISSUE_NUMBER}" --base main` を試みる
   - push/PR 作成成功時は `return 0`（reconciled）、失敗時は Stage 1 同様 `return 1`（exit 143 継続）
   - bash 3.2+ 互換（`declare -A`, `mapfile` 不使用）

4. `tests/watchdog-reconcile.bats` にテストを追加する (after 3) (→ AC 4)
   - `code-pr: worktree with implementation commits exists → push and create PR → exit 0`
   - `code-pr: worktree exists but no closes-#N commit → exit 143`
   - `code-pr: push fails → exit 143`
   - bats mock パターン: `MOCK_DIR/git` と `MOCK_DIR/gh` を組み合わせてモック（既存パターン踏襲）

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/watchdog-recovery-strategy.md" --> `docs/reports/watchdog-recovery-strategy.md` が作成されている
- <!-- verify: grep "Approach [A-D]" "docs/reports/watchdog-recovery-strategy.md" --> 4 アプローチ (A-D) の trade-off 比較が同ファイルに記録されている
- <!-- verify: rubric "docs/reports/watchdog-recovery-strategy.md に採用方針（Approach A〜D のいずれか、または複数の組み合わせ）が選定理由とともに明記されている" --> 採用方針が選定理由とともに記載されている
- <!-- verify: rubric "scripts/claude-watchdog.sh、scripts/watchdog-reconcile.sh、scripts/watchdog-defaults.sh、または skills/code/SKILL.md のいずれかに変更が加えられており、その変更内容が docs/reports/watchdog-recovery-strategy.md に記載された採用方針と整合している" --> 採用方針に基づく実装が完了している

### Post-merge

- code phase を Sonnet high effort で実行し、長時間 thinking 中に watchdog kill されないことを確認
- watchdog kill された場合でも、`/auto` resume が手動介入なしで進むことを確認

## Notes

- Approach B（CPU 監視）は macOS/Linux 互換性と閾値設計の難しさから今回は採用しない
- Approach A（timeout 引き上げ）は対症療法のため単独採用しない。ただし既存の `watchdog-timeout-seconds` 設定で各プロジェクトが調整可能であることを報告書に記載する
- Stage 2 reconcile は「commits あり push なし」ケースのみ対象。未コミット変更が worktree に残っている場合は push されないため、部分実装が PR になるリスクは低い
- PR 作成の title は暫定文言（"(watchdog recovery)" など）で可。実用上、`/review` や `/merge` でユーザーが確認できる

## Code Retrospective

### Deviations from Design
- Spec の Stage 2 で `code+issue-${ISSUE_NUMBER}` のみをチェックする設計だったが、SKILL.md のpr route 命名規則（`issue-N-desc`）とrun-code.sh の命名（`code+issue-N`）が不一致であることを発見。両パターンをカバーする `_find_code_worktree` ヘルパー関数を追加し、プライマリ（`code+issue-N`）とフォールバック（`issue-N-*` グロブ）の2段階探索に変更した。

### Design Gaps/Ambiguities
- run-code.sh の stale cleanup が `code+issue-N` を参照しているが、SKILL.md の命名規則は `issue-N-desc`。どちらが正とも言えない不整合が残っている（本 Issue のスコープ外のため follow-up 対象）。

### Rework
- なし

## spec retrospective

### Minor observations
- Issue body の Approach A〜D は比較的整理されており、Spec での追加調査は最小限で済んだ
- Stage 2 reconcile の bash 互換実装は `git -C` コマンドを使用する。bash 3.2 対応の `git -C` は git 1.8.5 以降（macOS 標準 git は 2.x なので問題なし）

### Judgment rationale
- Approach D + C の組み合わせを選択: D は予防的措置（thinking 中の沈黙を防ぐ）、C は回復的措置（kill 後の自動再開）。互いに補完関係にある
- Approach A（timeout 延長）は単体では採用しないが、既存設定での調整可能性を報告書に記録することで、各プロジェクトでの workaround として機能する

### Uncertainty resolution
- `git -C <worktree>` push が worktree のブランチを正しく push できるか: worktree は独立した git コンテキストを持つため `HEAD` は `worktree-code+issue-N` ブランチを指す。`git push origin HEAD` で正しく push される

## review retrospective

### Spec vs. 実装の乖離パターン

Code Retrospective に `_find_code_worktree` のフォールバック追加が記録されていたが、その変更に伴う Stage 1 の非対称性（Stage 2 は両パターンをカバーするが Stage 1 は `issue-N-*` のみ）が Spec・報告書のいずれにも反映されていなかった。Code Retrospective に設計からの逸脱を記録しても、その逸脱が他コンポーネントへの影響波及を分析した形跡がない。設計変更を記録する際は「この変更が他の箇所と整合しているか」を同時にチェックする習慣が望ましい。

### 繰り返し問題

なし（今回のコードは新規追加中心であり、繰り返しパターンは観察されなかった）。

### 受け入れ条件の検証困難度

rubric ベースの条件が2件あり、いずれも AI 判断で PASS 判定した。verify command が具体的なファイル名・パターンを指定しているため UNCERTAIN なし。ただし `rubric "採用方針に基づく実装が完了している"` は対象ファイルが実装後に確定するという性質上、verify command に具体的なファイルパスを入れられない。今後も同様のケースでは `rubric` が最適解であり、現状の設計は適切と判断する。
