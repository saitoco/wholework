# Spec: size-workflow-table の ALWAYS_PR Override caller 一覧に review/next-action-guide を追加 (#1092)

No Spec existed prior to `/code` (Issue already had `phase/ready` when this run started; Size=XS). Requirements were read directly from the Issue body, including its `## Auto-Resolved Ambiguity Points` section.

## Implementation Steps

1. `skills/review/SKILL.md` `### Step 3: Review Mode Detection` に `ALWAYS_PR` のロードと override ロジックを追加する。`ALWAYS_PR=true` かつ Size `XS`/`S` の場合、`skip` (early exit) ではなく `REVIEW_DEPTH=light` を採用する (Issue の Auto-Resolved Ambiguity Points で決定済みの値)。
2. `modules/next-action-guide.md` の Input セクションに `ALWAYS_PR` (bool, optional, default `false`) を追加し、`### Step 2: Derive ROUTE from SIZE` で `ALWAYS_PR=true` かつ導出結果が `patch` の場合に `pr` へ昇格する override を追加する。
3. `modules/size-workflow-table.md` `### ALWAYS_PR Override` の「Callers that must apply this override (exhaustive)」に `skills/review/SKILL.md` (Step 3) と `modules/next-action-guide.md` (Step 2) を追加する。
4. `skills/issue/SKILL.md` の `next-action-guide.md` 呼び出しに `ALWAYS_PR=$ALWAYS_PR` を渡す (Step 2 で `ALWAYS_PR` を既に retain 済み)。`next-action-guide.md` を `ROUTE` 未指定で呼ぶ既存 caller のうち、Step 3 の判定テーブルが `ROUTE` を参照するのは `code`/`spec` 行のみで、`issue`/`triage` 行は Size 語彙を直接参照するため、この配線自体は現状の推薦文言を変えない。Issue の Auto-Resolved Ambiguity Points が明示した「既存 caller が ALWAYS_PR を渡す」設計を、対象となる唯一の caller (`/issue`) に対して完成させるための追加。

## Code Retrospective

### Deviations from Design
- Issue 本文が明示的に列挙した変更対象は `skills/review/SKILL.md` と `modules/next-action-guide.md` の 2 箇所のみだったが、Issue の `## Auto-Resolved Ambiguity Points` が「既存の全 caller (`/auto`, `/code`, `/spec`, `/issue`) は ALWAYS_PR を渡す」という設計を明言していたため、実際に渡す配線がまだ無かった `skills/issue/SKILL.md` の呼び出しにも `ALWAYS_PR=$ALWAYS_PR` を追加した。`/auto`/`/code`/`/spec` は既に `ROUTE` を明示的に渡しており `next-action-guide.md` Step 2 のこの override 自体を経由しないため対象外。
- Step 10 (Verify Command Consistency) の Patch route verify command check により、Pre-merge AC4 (`github_check "gh pr checks" "Run bats tests"`) が patch route と非互換と判定され、`github_check "gh run list" --workflow=test.yml ...` 形式に自動修正した。Issue 本文・Spec 双方の設計には含まれていなかったが、`/code` 自身の Step 10 手順が要求する機械的な補正であり、実装方針の逸脱ではない。

### Design Gaps/Ambiguities
- N/A — Issue の Auto-Resolved Ambiguity Points が両方の設計判断 (`REVIEW_DEPTH=light` 採用、`ALWAYS_PR` の受け渡し方式) を確定済みだったため、実装時に新たな曖昧さは生じなかった。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/review/SKILL.md` Step 3 の override は Issue が指定した通り `REVIEW_DEPTH=light` (skip ではなく) を採用し、`skills/auto/SKILL.md` Step 2 の同種 fallback ("other/unset → `--light`") と同じ safe fallback 値であることを明記した。
- `modules/next-action-guide.md` の override は「`ROUTE` が明示的に渡された場合は Step 2 全体をスキップする」という既存の分岐の後に置き、`patch` → `pr` の昇格のみを行う (`sub_issue` は対象外)、`skills/spec/SKILL.md` Step 18 の同種 override と同じ narrow scope に揃えた。
- `modules/size-workflow-table.md` の caller 一覧は追加のみで既存 7 エントリの並び・文言は変更していない。

### Deferred Items
- なし

### Notes for Next Phase
- Pre-merge AC1-AC3 (rubric 2件 + section_contains 2 ペア) は `/code` 内で grep 相当の検証により自己判定 PASS 済みで、Issue 本文のチェックボックスも更新済み。
- Pre-merge AC4 (`github_check "gh run list"`, 旧 `github_check "gh pr checks"` から自動修正) は patch route の branch-scoped CI AC のため本フェーズでは未チェックのまま残しており、`/verify` post-merge で評価される。
- Behavioral Change Detection により `bats --jobs 18 tests/` (フルスイート) を実行し、1786 件全て PASS を確認済み (ローカル実行結果。CI 上の実行結果は上記 AC4 で別途評価される)。

## Consumed Comments

No new comments since last phase.
