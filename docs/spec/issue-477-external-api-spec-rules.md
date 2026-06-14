# Issue #477: Add External API Integration Spec Rules

## Overview

Add an "External API Integration Checklist" section to `skills/spec/external-spec.md` that requires documenting:
- Actual API response format samples (distinct from official specs), especially for datetime/numeric attributes that may diverge
- Abnormal/error response code listing with handling policies (retry / non-failure exit / exception throw)
- Test coverage requirement for all actual format patterns in datetime/numeric conversion utilities

Background: downstream project post-merge bugs caused by underdocumented actual API behavior — actual datetime format differed from the official spec, and a throttle response code was absent from the error-handling design. Both would have been caught if Spec phase had required documenting real response behavior.

## Changed Files

- `skills/spec/external-spec.md`: add `## External API Integration Checklist` section (before `## Output Format`) — bash compat: N/A (Markdown file)

## Implementation Steps

1. Add the following new section to `skills/spec/external-spec.md` immediately before `## Output Format` (→ AC1, AC2, AC3):

   Section heading: `## External API Integration Checklist`

   Content (3 checklist items):
   1. **Actual response format samples** — Collect real response samples from the actual API (not only the official specification), especially for attributes where the actual format may diverge from the official spec (e.g., `dateTime` attributes: official `YYYY-MM-DD;HH:MM:SS` vs. actual `YYYYMMDD;HH:MM:SS`; numeric attributes: scale, separator, trailing zeros). Include at least one minimal XML or JSON actual response sample in the Spec's Implementation Steps.
   2. **Abnormal/error response code list** — Enumerate all known non-normal error codes the API may return (including throttle codes, in-progress codes, and any partner-guide-documented codes). For each code, document the handling policy: **retry** (call again with backoff) / **non-failure exit** (treat as success and stop) / **exception throw** (raise and propagate).
   3. **Test coverage for actual format patterns** — Datetime and numeric conversion utilities that parse actual API responses must have test cases covering all actual format patterns observed in real responses, not only patterns documented in the official specification.

   Also add a trigger condition before the checklist: "Apply this checklist when the Issue involves calling an external API and processing its responses."

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/external-spec.md includes guidance requiring documentation of actual API response format samples (distinct from the official spec), especially for datetime/numeric attributes that may diverge from the official specification, for external API integration Issues" --> <!-- verify: grep "actual" "skills/spec/external-spec.md" --> `skills/spec/external-spec.md` に、外部 API の実レスポンスフォーマット（XML/JSON サンプル）を明記する規約が追加されている
- <!-- verify: rubric "skills/spec/external-spec.md includes guidance requiring a list of abnormal/error response codes with their handling policies (retry, non-failure exit, exception throw) for external API integration Issues" --> <!-- verify: grep "error" "skills/spec/external-spec.md" --> `skills/spec/external-spec.md` に、非正常レスポンスコード一覧と対処方針を明記する規約が追加されている
- <!-- verify: rubric "skills/spec/external-spec.md includes guidance that datetime and numeric conversion utilities must have test cases covering all actual format patterns observed in real API responses" --> <!-- verify: grep "test" "skills/spec/external-spec.md" --> `skills/spec/external-spec.md` に、日時・数値変換ユーティリティの実フォーマット全パターンをテストケースで網羅する旨が明記されている

### Post-merge

- 次の外部 API 統合 Spec で本規約が適用されていることを確認 <!-- verify-type: manual -->

## Notes

- `skills/spec/external-spec.md` は `type: domain`, `skill: spec` で `load_when` なしの無条件ロード対象。新セクションは毎回読み込まれるが、チェックリストは「外部 API 呼び出しを含む Issue のみ適用」と明記するため、無関係な Issue への影響はない。
- 新セクションは既存の `## JSON I/O Spec Check` と相補的な位置づけ。JSON I/O は Claude Code Hooks / MCP / GitHub API 等の Wholework 内部統合向け。External API Integration Checklist は downstream プロジェクトの外部 API 統合向け。
- `skills/` 下のドメインファイルは `docs/ja/` の翻訳同期対象外（translation-workflow.md 参照）。
- `docs/structure.md` は `external-spec.md` を個別リストに含まないため更新不要（auxiliary skill files は集合として記述）。
- Auto-resolved ambiguity points (from Issue retrospective): (1) extend existing `external-spec.md` (not a new file), (2) place test coverage guidance in the same checklist as the format requirement, (3) manual guidance only (no automatic detection mechanism).

## issue retrospective

### 曖昧点の自動解決（non-interactive mode）

本 Issue は `--non-interactive` モードで実行されたため、以下の曖昧点をモデル判断で自動解決した。

#### 曖昧ポイント 1: 変更対象ファイル

- **選択**: `skills/spec/external-spec.md` を拡張する
- **理由**: 既存の `external-spec.md` は外部 API の仕様チェックを扱うドメインファイルであり、今回追加するチェック項目（実レスポンスフォーマット・異常コード一覧）と同じ文脈。Issue の「スコープ（案）」にも `external-spec.md` との連携が明示されていたため、既存ファイルへの追加を最小リスク選択として採用。
- **不採用候補**: 新ファイル作成、`skills/spec/SKILL.md` への直接追加

#### 曖昧ポイント 2: テストカバレッジ記述の配置場所

- **選択**: 実レスポンスフォーマット要件と同じ `external-spec.md` に追記
- **理由**: テスト要件は実フォーマット文書化の要件と密接に関連しており、同一チェックリストへの集約が参照一元化の観点から望ましい。

#### 曖昧ポイント 3: 「外部 API 統合」の検知条件

- **選択**: 手動ガイダンスとして追記（自動検知機構の追加は対象外）
- **理由**: 自動検知機構の新規追加は本 Issue のスコープ外。ガイダンスとして既存フローに乗る形が最小リスク。

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added `## External API Integration Checklist` section to `skills/spec/external-spec.md` immediately before `## Output Format` as specified in the Spec
- Trigger condition ("Apply this checklist when the Issue involves calling an external API") placed before the numbered checklist items to scope its applicability clearly
- All three checklist items (actual response samples, error code list, test coverage) implemented exactly as specified in Spec

### Deferred Items
- Post-merge manual AC: confirming the checklist is applied in the next downstream external API integration Spec (manual observation, out of scope for this phase)
- No follow-up Issues created (implementation was straightforward, no out-of-scope remediations identified)

### Notes for Next Phase
- Implementation is a simple Markdown addition; no bats test changes — all 823 tests passed with no modification
- Pre-merge verify commands (3 grep + 3 rubric) all PASS; checkboxes updated in Issue body
- `/verify` should focus on confirming the checklist text is properly scoped and readable in context of the existing `## JSON I/O Spec Check` section

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 3 つの AC は rubric + grep ペア構成。actual/error/test キーワード各 2 箇所出現で grep AC を確実化、rubric で意味検証も両立。

#### design
- 既存 "## JSON I/O Spec Check" の直後 "## External API Integration Checklist" 配置が論理的に整合。3 チェック項目を 1 セクションに集約で参照一元化。
- Size S → XS demotion 成功。

#### code
- 1 ファイル・文書追記のみで完了、bats 823 件 PASS、rework なし。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。worktree-merge-push.sh で main 直マージ成功。

#### verify
- Pre-merge 全 3 件 PASS。Post-merge manual は次回外部 API 統合 Spec での適用観察待ちで `phase/verify` 維持。

### Improvement Proposals
- N/A

