# Issue #436: issue/verify: retrospective を特筆事項あり時のみ生成して空 comment を抑制

## Overview

`/issue` (Step 10, Step 12) と `/verify` (Step 12) の retrospective ステップが、特筆事項のない場合でも無条件に comment を生成・post している。これにより Quick Start XS 経路で合計 40-80s のオーバーヘッドが発生し、Issue ノイズも増える。skip 条件を追加して、実質的な内容がある場合のみ生成・post するよう改善する。

## Changed Files

- `skills/issue/SKILL.md`: Step 10 と Step 12 の retrospective ステップに skip 条件を追加
- `skills/verify/SKILL.md`: Step 12 (Retrospective) に skip 条件を追加

## Implementation Steps

1. `skills/issue/SKILL.md` Step 10 を更新: "Always create the section (write 'Nothing to note' if no content)" を skip 条件付きに置き換える。Skip 条件: (1) ambiguity auto-resolution がゼロ、(2) AC 変更がゼロ、(3) surprising policy decision がない。Skip 時は `retrospective skipped: no notable content` をターミナルに出力し、comment は post しない。(→ AC1, AC2, AC6)

2. `skills/issue/SKILL.md` Step 12 を Step 1 と同様に更新する (Existing Issue Refinement 経路)。(→ AC1, AC3, AC6)

3. `skills/verify/SKILL.md` Step 12 に skip 条件を追加する。Skip 条件: 全 AC が PASS かつ改善提案がゼロかつ (Spec が存在しない または lifecycle review の全フェーズに観察事項がない)。Skip 時は `retrospective skipped: no notable content` をターミナルに出力し、Spec への追記とコミットもスキップする。(→ AC4, AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md の retrospective ステップに skip 条件 (例: ambiguity 自動解決ゼロ・AC 変更ゼロ・surprising decision なし) が明記されている" --> `skills/issue/SKILL.md` に retrospective の skip 条件が明記されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 10: Issue Retrospective" "skip" --> `skills/issue/SKILL.md` Step 10 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 12: Issue Retrospective" "skip" --> `skills/issue/SKILL.md` Step 12 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: rubric "skills/verify/SKILL.md の retrospective ステップに skip 条件が明記されている" --> `skills/verify/SKILL.md` に retrospective の skip 条件が明記されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 12: Retrospective (Full Workflow Review)" "skip" --> `skills/verify/SKILL.md` Step 12 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: rubric "両 skill とも skip 時はターミナル出力にスキップ理由 (例: 'retrospective skipped: no notable content') を出すことが SKILL に明記されている" --> skip 時のターミナル出力フォーマットが定義されている
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> SKILL.md 構文 lint が通る

### Post-merge

- サンプル XS Issue に対して `/issue <N>` `/verify <N>` を実行し、retrospective comment が post されないこと (もしくは notable content がある時だけ post されること) を実機で確認

## Notes

- SPEC_DEPTH=light で pre-merge verification が 7 件 (上限 5 件超) だが、Issue body の AC を verbatim でコピーするため全件含む
- `/verify` の skip 条件は Issue body の `## Auto-Resolved Ambiguity Points` で auto-resolve 済み: 「全AC PASS かつ改善提案ゼロかつ Spec 未存在（または lifecycle review に観察事項なし）」を採用
- `docs/workflow.md` の `/verify` 説明 ("Performs a cross-phase retrospective review") は変更後も意味的に正確 (skip はあくまで注記事項がない場合のみ) なので更新不要
