# Issue #823: /auto --batch Completion Report: Add Pending Manual Confirmation Section

## Overview

`/auto --batch` の "Batch Completion Report" セクションに、`phase/verify` に残置している Issue を "Pending manual confirmation" セクションとして集約するロジックを追加する。verify-type 別 (manual/observation/opportunistic) の AC 数分類と推奨次アクションガイダンスも含める。

背景: batch 完了後に複数の Issue が `phase/verify` に残置された場合、利用者は各 Issue を個別に開いて未チェック AC を確認する必要があり、未確認作業の全体像を把握できなかった (2026-06-27 の 17 Issue batch で 8 件が残置)。

## Changed Files

- `skills/auto/SKILL.md`: `### Batch Completion Report` の "report results" 出力直後に pending manual confirmation 集約ロジックを追加 — bash 3.2+ 互換
- `tests/auto-completion-report.bats`: 新規作成 — `### Batch Completion Report` セクションの集約ロジックをアサート

## Implementation Steps

1. `skills/auto/SKILL.md` の `### Batch Completion Report` セクション内、"After all Issues are processed, report results (success/skip/failure) for each Issue." の直後に以下の手順ブロックを追加する (→ AC1, AC2):

   **Pending manual confirmation (best-effort):**

   1. 全 BATCH_LIST の Issue について `gh issue view $NUMBER --json labels -q '.labels[].name'` でラベルを取得し、`phase/verify` を含む Issue を `PENDING_LIST` に収集する
   2. `PENDING_LIST` が空の場合は "No issues pending manual confirmation." を出力して終了
   3. 空でない場合、各 Issue について `gh issue view $NUMBER --json body -q '.body'` を取得し、以下を集計する:
      - `- [ ]` 行のうち `<!-- verify-type: manual` を含む行数 → `MANUAL_N`
      - `- [ ]` 行のうち `<!-- verify-type: observation` を含む行数 → `OBS_N`
      - `- [ ]` 行のうち `<!-- verify-type: opportunistic` を含む行数 → `OPP_N`
   4. 集約結果を以下の形式で出力する:
      ```
      Pending manual confirmation (N issues in phase/verify):
      - #NUMBER: MANUAL_N manual AC, OBS_N observation AC, OPP_N opportunistic AC
      ...
      verify-type breakdown: manual=TOTAL_M, observation=TOTAL_O, opportunistic=TOTAL_P
      Recommended next action:
      - For observation/opportunistic: wait for event fire (auto-checked next /verify run)
      - For manual: review and confirm or run /verify $NUMBER
      ```

2. `tests/auto-completion-report.bats` を新規作成する (→ AC3):
   - `skills/auto/SKILL.md` の `### Batch Completion Report` セクションを awk で抽出するヘルパー関数を定義する
   - 以下の `@test` アサーションを追加する (SKILL.md に追加される内容を検証):
     - `"Pending manual confirmation"` が含まれる
     - `"verify-type"` が含まれる
     - `"phase/verify"` への labels チェック (`gh issue view`) が含まれる
     - `"Recommended next action"` ガイダンスが含まれる

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Completion Report 生成手順で、各 sub-issue の labels を gh issue view で取得し、phase/verify を持つ Issue を pending manual confirmation セクションとして集約し、verify-type 別 (manual/observation/opportunistic) に分類して報告する手順が記述されている" --><!-- verify: section_contains "skills/auto/SKILL.md" "### Batch Completion Report" "Pending manual confirmation" --> phase/verify 残置 Issue の集約ロジックが Batch Completion Report セクションに追加されている
- <!-- verify: rubric "skills/auto/SKILL.md の集約セクションで、各 phase/verify 残置 Issue の未チェック AC を verify-type (manual/observation/opportunistic) 別に counting し、recommended next action ガイダンスが含まれる" --><!-- verify: section_contains "skills/auto/SKILL.md" "### Batch Completion Report" "verify-type" --> verify-type 別分類と推奨次アクションが含まれる
- <!-- verify: rubric "tests/auto-completion-report.bats で、複数の mock Issue が phase/verify ラベル + verify-type マーカーを持つ状態で集約セクションが正しく生成されることを assert する test が追加されている" --><!-- verify: command "bats tests/auto-completion-report.bats" --> tests/auto-completion-report.bats が新規作成され bats テストが通る

### Post-merge

- 次回 `/auto --batch` 完了時に "Pending manual confirmation" セクションが出力されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

**Consumed Comments:**
- saito/MEMBER/first-class (2026-06-28T16:34:26Z): Issue Retrospective — 3件の ambiguity points が auto-resolve 済み:
  1. AC3 テストファイル → `tests/auto-completion-report.bats` (新規作成) で確定
  2. AC1/AC2 に rubric 補助として `section_contains` チェックを追加
  3. Post-merge verify-type → `observation event=auto-run` に再分類

**実装スコープ**: batch route (`### Batch Completion Report`) のみ。XL route (`### Step 5: Completion Report`) は verify コマンドのスコープ外のため本 Issue では対象外。

**テスト方針**: `auto-completion-report.bats` は SKILL.md セクション内容の structural assertion に留める (auto-batch.bats と同じパターン)。SKILL.md の手順は LLM が実行するため、実際の GitHub API 呼び出しをモックした functional test は不要。

**bats awk セクション抽出**: `### Batch Completion Report` セクションは `## Notes` (次の `##` 見出し) で終端する。awk パターン: `/^### Batch Completion Report/{found=1} /^## / && !/Batch Completion Report/{found=0} found{print}`


## review retrospective

### Spec vs. Implementation Divergence Patterns

実装は Spec の手順に完全に従っており、乖離なし。`BATCH_LIST` の参照箇所が Spec と一致し、best-effort 実装も正しく反映されている。

### Recurring Issues

CONSIDER 件 1 件のみ: `batch_completion_section()` ヘルパー関数が bats ファイルで定義されたが各テストでインラインの awk が使われており未使用。これは structural assertion パターン採用時に起きがちな実装ドリフトで、ヘルパー関数の使用方針をより明示的に Spec に記述することで防ぐことができる。

### Acceptance Criteria Verification Difficulty

全 3 件の Pre-merge AC が section_contains + rubric の組み合わせで自動 PASS。verify command の設計が適切で UNCERTAIN は発生しなかった。bats test は CI フォールバックで PASS。特段の課題なし。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- mergeable=true、CI=success、review=approved → 障害なしでスカッシュマージ実行
- PR #833 を `--squash --delete-branch` でマージ (ブランチ自動削除)
- Post-merge AC は verify-type: observation のみ → /verify は observe 待ちで自動処理される

### Deferred Items
- CONSIDER 件 (batch_completion_section 未使用ヘルパー関数) は後続リファクタリング Issue で対応可能

### Notes for Next Phase
- Post-merge AC (次回 /auto --batch 完了時の観察) が唯一の残存確認事項
- verify-type: observation event=auto-run → 次回 /auto --batch 完了で自動チェックされる
- 手動確認不要; /verify #823 を次回 /auto --batch 完了後に実行すれば全 AC クローズ可能
