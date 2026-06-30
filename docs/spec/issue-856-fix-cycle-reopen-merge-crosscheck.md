# Issue #856: auto: get-last-reopen クエリに merge-time cross-check を追加

## Overview

`/auto $N` の Fix-cycle Detection (Step 2a) において、OR reopened check が
`reopen_ts != null` のみで criterion 1 を満足と判定している。これにより、
PR を作らずに close → reopen されただけの Issue でも `reopen_ts` が非 null となり、
fix-cycle と誤判定 (false positive) する問題がある。

`reopen_ts > last_merge_ts` の cross-check を Step 2a に追加することで、
実際に merge が発生した後の reopen に限って criterion 1 を満たすよう修正する。

## Reproduction Steps

1. Issue を PR を作らずに close → reopen する
2. `/auto $N` を実行する
3. Step 2a: `get-last-reopen` クエリが `reopen_ts` を返す (非 null)
4. 現在: `reopen_ts != null` → criterion 1 満足 → fix-cycle 判定 → issue/spec phase スキップ (false positive)
5. 期待: merge commit が存在しないため `last_merge_ts` が空 → criterion 1 不満足 → 通常の issue/spec phase へ進む

## Root Cause

`skills/auto/SKILL.md` Step 2a の OR reopened check が `reopen_ts` の非 null チェックのみで
criterion 1 を満足と判定している。実際に merge が存在するかの確認 (`reopen_ts > last_merge_ts`)
が欠落しているため、merge なし reopen でも fix-cycle と誤判定される。

`reconcile-phase-state.sh` は `git log origin/main --after="$reopen_ts"` で merge 後の
commit を確認するパターンを既に持っており、今回は SKILL.md Step 2a でも同様のアプローチを採用する。

## Changed Files

- `skills/auto/SKILL.md`: Step 2a の OR reopened check に `last_merge_ts` cross-check を追加 — bash 3.2+ compatible
- `tests/auto.bats`: Step 2a が `last_merge_ts` cross-check の記述を含むことをアサートするテスト追加

## Implementation Steps

1. `skills/auto/SKILL.md` Step 2a 修正 (→ AC1)

   OR reopened check の既存コードブロックを以下のように変更する:

   ```bash
   reopen_ts=$("${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh" --query get-last-reopen \
     -F "num=$NUMBER" \
     --jq '.data.repository.issue.timelineItems.nodes[0].createdAt' 2>/dev/null \
     | tr -d '"' || true)
   # Cross-check: only count as "reopened after merge" if a merge commit exists before the reopen
   if [[ -n "$reopen_ts" && "$reopen_ts" != "null" ]]; then
     last_merge_ts=$(git log -1 --format=%cI --grep="closes #${NUMBER}" origin/main 2>/dev/null \
       | tr -d '"' || true)
     if [[ -z "$last_merge_ts" || ! "$reopen_ts" > "$last_merge_ts" ]]; then
       reopen_ts=""
     fi
   fi
   ```

   説明テキスト「If `reopen_ts` is non-null and non-empty, the reopened criterion is satisfied.」を
   「`reopen_ts` が非 null かつ `reopen_ts > last_merge_ts` の場合のみ criterion 1 (reopened) を満たす。
   merge commit が存在しない場合 (`last_merge_ts` が空) や reopen が merge より前の場合は criterion 1 不満足。」
   に改訂する。

2. `tests/auto.bats` テスト追加 (→ AC2)

   既存の `step2a_section()` ヘルパーを使い、Step 2a に `last_merge_ts` cross-check の記述が
   含まれることをアサートするテストを追加する:

   ```bash
   @test "Step 2a section contains last_merge_ts merge-time cross-check" {
       run step2a_section "$SKILL_FILE"
       [[ "$output" == *"last_merge_ts"* ]]
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 2a もしくは scripts/gh-graphql.sh で、Issue の最新 reopen timestamp と最後の merge commit timestamp を比較し、reopen_ts > last_merge_ts の場合のみ fix-cycle criterion 1 を満たす判定に変更されている" --> `skills/auto/SKILL.md` Step 2a または `scripts/gh-graphql.sh` の get-last-reopen クエリで、reopen_ts が最後の merge commit より後である場合のみ criterion 1 (reopened) を満たす判定に変更されている
- <!-- verify: command "bats tests/" --> bats test で「merge なし + reopen のみの Issue では fix-cycle 判定が false を返す」動作が assert されている

### Post-merge

- 次回 merge なし reopen Issue (PR を作らず close → reopen) に対して `/auto $N` を実行した際、fix-cycle と誤判定されず通常の issue/spec phase に進むことを観察

## Notes

- Approach B (SKILL.md Step 2a 側で cross-check 追加) を採用。`gh-graphql.sh` は他箇所 (`reconcile-phase-state.sh` 等) からも利用されるため変更対象から除外。
- `reconcile-phase-state.sh` の `_completion_code_patch` は既に `git log origin/main --after="$reopen_ts"` で同様の merge 確認を行っているため、今回の SKILL.md 側の変更はそのパターンに合わせた対称的な修正となる。
- Issue Retrospective (2026-06-30) により AC2 の verify command が `command "bats tests/"` に更新済み。実装先 (`tests/auto.bats` vs `tests/reconcile-phase-state.bats`) に依らず両方をカバーする。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — AC2 verify command を `command "bats tests/"` に変更し、変更理由 (verify-patterns §3, §24 準拠) を記録 — https://github.com/saitoco/wholework/issues/856#issuecomment-4839631574
