# Issue #538: review/code: CI 完了前の pass 誤報告と retrospective 非推奨用語混入を防止

## Overview

`/auto 500`（PR #537）の review フェーズが「全CI PASS」と報告したが Forbidden Expressions check が FAIL していた。原因は 2 点:

1. **CI timing gap**: `skills/review/SKILL.md` Step 9 が `gh pr view --json statusCheckRollup` を 1 回だけ参照し、PENDING/IN_PROGRESS 状態のチェックが残っていても「CI running, proceed」として処理を継続する。その後全チェックが完了した際に FAILURE があっても review 側では再確認しないため「全CI PASS」と誤報告した。
2. **retrospective 非推奨用語混入**: `/review` と `/code` の retrospective writer が `docs/spec/` 配下の Spec ファイルへ非推奨用語を直接引用して書き込んだ。`scripts/check-forbidden-expressions.sh` の SCAN_DIRS に `docs/` が含まれるため CI が FAIL した。

## Reproduction Steps

1. `docs/spec/` 配下に非推奨用語を含む Spec ファイルを用意した状態で PR を作成する
2. PR の CI 高速チェック（Forbidden Expressions check）が FAIL している状態で `/review` を実行する
3. Step 9 で `gh pr view --json statusCheckRollup` を実行した時点で FAIL チェックが pending 表示になっているか、review が先に「全 CI PASS」と結論付ける
4. 実際には FAILURE が存在するが `/review` は「全CI PASS」として完了報告する

（または: retrospective 書き込みステップで deprecated term を spec に直接引用 → CI FAIL）

## Root Cause

**CI timing gap**: `skills/review/SKILL.md` Step 9 は wait なしで 1 回の status snapshot を参照し、pending/in_progress チェックが残っていても「CI running, proceed」として後続処理を続行する。全チェックが terminal state に達するまで待機する手順が存在しないため、FAILURE チェックの見落としが起きる。

**retrospective guard 不在**: `/review` の Retrospective ステップおよび `/code` の Step 12（Code Retrospective）に、spec へのコミット前に非推奨用語混入を検出する手順が存在しない。`docs/spec/` は `check-forbidden-expressions.sh` の SCAN_DIRS 対象であるため、retrospective 内の deprecated term が CI FAIL を引き起こす。

## Changed Files

- `skills/review/SKILL.md`: allowed-tools に `wait-ci-checks.sh` 追加; Step 9 に wait 手順追加; Retrospective に forbidden-expressions guard 参照追加
- `skills/review/skill-dev-recheck.md`: Retrospective Guard セクション追加
- `skills/code/SKILL.md`: Step 12 に forbidden-expressions guard 参照追加
- `skills/code/forbidden-expressions-check.md`: Retrospective Guard セクション追加

## Implementation Steps

1. `skills/review/SKILL.md` を変更する（→ AC1、AC3）:
   - **allowed-tools**: `${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh:*` の直前に `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*,` を挿入する
   - **Step 9 (CI Status Check)**: `gh pr view "$NUMBER" --json statusCheckRollup` の bash ブロックの直前に以下を挿入する:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh "$NUMBER"
     ```
     また、箇条書きを以下のように変更する:
     - 既存の `- **PENDING/IN_PROGRESS jobs**: note CI is running and proceed` を `- **PENDING/IN_PROGRESS jobs** (after wait timeout): note CI wait timed out; list pending checks and proceed with caution` に変更する
   - **Retrospective セクション**: 番号付きリストの既存 Step 2（Write review retrospective to Spec）の後、Step 3（Phase Handoff write）の前に新しい Step 3 として以下を挿入し、旧 Step 3 以降を 4→5→6 に繰り上げる:
     ```
     3. If `scripts/check-forbidden-expressions.sh` exists, Read `${CLAUDE_PLUGIN_ROOT}/skills/review/skill-dev-recheck.md` and follow the "Retrospective Guard" section.
     ```

2. `skills/review/skill-dev-recheck.md` に Retrospective Guard セクションを追加する（→ AC2）:
   既存の `## Step 12.3: Re-run validate-skill-syntax` の後に以下のセクションを追記する:
   ```markdown
   ## Retrospective Guard

   Before committing the review retrospective to the Spec:

   1. Run forbidden expressions check to detect any deprecated terms introduced by the retrospective content:
      ```bash
      bash scripts/check-forbidden-expressions.sh
      ```
   2. If violations are detected: fix the retrospective text before committing
      - Use descriptive language instead of quoting deprecated terms directly (e.g., write `旧称: <term>` or describe without quoting the term)
   3. If no violations: proceed with commit
   ```

3. `skills/code/SKILL.md` Step 12（Code Retrospective）を変更する（→ AC2）:
   番号付きリストの既存 Step 2（Append `## Code Retrospective` section）の後、Step 3（Sync Spec implementation steps）の前に新しい Step 3 として以下を挿入し、旧 Step 3 以降を 4→5→6→7 に繰り上げる:
   ```
   3. If `scripts/check-forbidden-expressions.sh` exists, Read `${CLAUDE_PLUGIN_ROOT}/skills/code/forbidden-expressions-check.md` and follow the "Retrospective Guard" section.
   ```

4. `skills/code/forbidden-expressions-check.md` に Retrospective Guard セクションを追加する（→ AC2）:
   既存の `## Processing Steps` セクションの後（ファイル末尾）に以下のセクションを追記する:
   ```markdown
   ## Retrospective Guard

   Before committing the code retrospective to the Spec:

   1. Run forbidden expressions check to detect any deprecated terms introduced by the retrospective content:
      ```bash
      bash scripts/check-forbidden-expressions.sh
      ```
   2. If violations are detected: fix the retrospective text before committing
      - Use descriptive language instead of quoting deprecated terms directly (e.g., write `旧称: <term>` or describe without quoting the term)
   3. If no violations: proceed with commit
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md に、CI 状態を結論づける前に全チェックの完了（pending/queued が残らず全て terminal state に達すること）を確認し、いずれかが FAILURE なら CI-pass と報告しない手順が記載されている" --> /review の CI 結論前の全チェック完了確認手順が追加されている
- <!-- verify: rubric "/code と /review の両方の retrospective 書き込み手順（Code Retrospective / Review Retrospective を spec へコミットするステップ）に、コミット前に非推奨用語混入（docs/spec は check-forbidden-expressions.sh の SCAN_DIRS 対象）を検出・回避する guard が記載されている" --> /code・/review 両方の retrospective 非推奨用語混入 guard が追加されている
- <!-- verify: file_contains "skills/review/SKILL.md" "check-forbidden-expressions" --> /review 手順に forbidden-expressions チェックへの言及が追加されている

### Post-merge

- 次に CI を伴う PR の `/review` 実行時に、Forbidden Expressions 等の高速チェック FAIL を CI-pass 結論前に検出することを観察する <!-- verify-type: opportunistic -->
- 次に retrospective を spec へ書き込む `/code` または `/review` 実行時に、非推奨用語混入による Forbidden Expressions CI 失敗が発生しないことを観察する <!-- verify-type: opportunistic -->

## Notes

- **Domain 確定**: CI 全チェック完了確認は `/review` の Core 挙動のため `skills/review/SKILL.md` Step 9 を直接修正する。forbidden-expressions retrospective guard は wholework 固有の skill-dev 関心事のため Domain file（`skill-dev-recheck.md` / `forbidden-expressions-check.md`）へ切り出し、Core SKILL.md から条件付き参照する。
- **CI wait のタイムアウト**: `wait-ci-checks.sh` は `WHOLEWORK_CI_TIMEOUT_SEC`（デフォルト 1200s）でタイムアウトする。タイムアウト後も PENDING が残る場合は「proceed with caution」として警告し処理を継続する（ハードストップはしない）。
- **`check-forbidden-expressions.sh` のスコープ**: ガードは spec ファイルだけでなく SCAN_DIRS 全体（skills/, modules/, agents/, tests/, docs/）を対象とする。これは既存の `forbidden-expressions-check.md` と同じ invocation 方法（`bash scripts/check-forbidden-expressions.sh` 無引数）で実現できる。

## Code Retrospective

### Deviations from Design

- Spec の実装ステップ 3（`skills/code/SKILL.md` Step 12）では「旧 Step 3 以降を 4→5→6→7 に繰り上げる」と記載されていたが、元のステップ数は 5（旧3→4, 旧4→5, 旧5→6）であり「7」には達しない。記述の数え間違いと判断し、実際には 6 ステップ構成（新 step 3 挿入後）に実装した。

### Design Gaps/Ambiguities

- Spec の「旧 Step 3 以降を 4→5→6→7 に繰り上げる」という記述は元ステップ数と合わない（元が 5 ステップのため最大 6 まで）。実装では矛盾なく新 step 3 挿入・旧3→4・旧4→5・旧5→6 に繰り上げを実施した。

### Rework

- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `/review` の CI wait を `wait-ci-checks.sh "$NUMBER"` として Step 9 の `gh pr view` の直前に挿入した（非-SKILL.md の Domain file でなく SKILL.md 直接修正）
- `/code` と `/review` の retrospective guard は Domain file（`forbidden-expressions-check.md` / `skill-dev-recheck.md`）の "Retrospective Guard" セクションとして切り出し、各 SKILL.md から `check-forbidden-expressions.sh` 存在チェック付きで条件参照する方式を採用した
- PENDING 記述を "after wait timeout" に変更し、タイムアウト後も継続できることを明示した

### Deferred Items
- `/review` の Retrospective Guard は `skill-dev-recheck.md` を読んで実行するため、wholework 以外の非 skill-dev プロジェクトでは実行されない（設計通り）
- Post-merge の opportunistic 検証は観察のみ

### Notes for Next Phase
- PR #540 が CI を通過するか確認が必要（allowed-tools に `wait-ci-checks.sh:*` を追加しているため、`validate-skill-syntax.py` の allowed-tools パターン検証が通るか注意）
- Retrospective Guard セクションの内容が「旧称:」prefix や descriptive language の使用例として分かりやすいかレビューで確認すること
