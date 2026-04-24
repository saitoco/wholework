# Issue #351: verify: retro Issue 作成時に domain-classifier で対象ファイルを Domain file path にリライト

## Overview

`/verify` Step 13 の「Skill infrastructure improvement」分類後に `modules/domain-classifier.md` (#350) を呼び出し、分類された提案が具体的な Domain (例: skill-dev) に属する場合、作成される Issue 本文の Pre-merge AC verify command path 引数と AC テキスト中の明示的なファイルパス参照を Domain file path に書き換える。`domain: ambiguous` の場合は `## Domain Classification` セクションを Issue 本文末尾に追加してから Issue 化する。`domain: none` またはエラー時は Core 対象のまま Issue 化する既存動作を維持する。

前提: `.wholework/domains/verify/skill-infra-classify.md` は #295 Sub 4B で既に新設済み。本 Issue ではこのファイルは変更せず、Step 13 本体に domain-classifier 呼び出しと分岐ロジックを追加する。

## Changed Files

- `skills/verify/SKILL.md`: Step 13 の `HAS_SKILL_PROPOSALS=true` ブロック内に、「Skill infrastructure improvement」分類後の domain-classifier 呼び出し・分岐・path 書き換え処理を追加

## Implementation Steps

1. `skills/verify/SKILL.md` Step 13 の `HAS_SKILL_PROPOSALS=true` ブロック内: 「Skill infrastructure improvement」に分類された各提案について、domain-classifier への入力となる Domain files リストを構築する。`skills/*/*.md`、`modules/*.md`、`.wholework/domains/*/*.md` を Glob し、frontmatter に `applies_to_proposals` が宣言されているファイルのみを読み込む（`/verify` 自身の domain-loader スコープに限定しない）。「Code improvement」に分類された提案はこのステップをスキップし既存の Issue 化フローへ進む。(→ AC1, AC3, AC8)

2. 各 Skill-infra 提案について、`${CLAUDE_PLUGIN_ROOT}/modules/domain-classifier.md` を読み Processing Steps に従い分類を実行する。入力: 提案テキスト + Step 1 で構築した Domain files リスト。呼び出し失敗時 (Domain files リストが空、classifier エラー等) は Core 対象のまま Issue 化するフォールバックへ進む。(→ AC1, AC2, AC7)

3. Classifier 出力の `domain` フィールドで分岐してから Issue 化する:
   - 具体 domain 値 (例: `skill-dev`) かつ `rewrite_target` あり → Issue 本文の Pre-merge AC に埋め込まれた verify command の path 引数 (例: `<!-- verify: file_exists "skills/verify/SKILL.md" -->`) と AC テキスト中の明示的ファイルパス参照を `rewrite_target.to` に書き換える。Background / Purpose などコンテキスト記述中のパス言及は書き換えない。書き換え後 `gh issue create` で Issue 化する。
   - `domain: ambiguous` → Core 対象のまま。Issue 本文末尾に `## Domain Classification` セクション (`classifier_result: ambiguous` / `reason: <fallback_reason>` / `action_required: ...`) を追加してから `gh issue create` で Issue 化する。
   - `domain: none` またはエラー → Core 対象のまま Issue 化する (既存動作)。
   (→ AC4, AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: rubric ".wholework/domains/verify/skill-infra-classify.md (or skills/verify/SKILL.md Step 13) invokes modules/domain-classifier.md and branches on the returned domain value (specific domain / ambiguous / none)" --> domain-classifier 呼び出しと結果分岐が記述されている
- <!-- verify: grep "domain-classifier" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` に `domain-classifier` への参照が追加されている（Step 13 本体 または Domain file 経由の参照記述）
- <!-- verify: rubric "The classifier is invoked only for proposals classified as Skill infrastructure improvement, not for Code improvement proposals" --> classifier 適用対象が Skill-infra 提案のみに限定されていることが明記されている
- <!-- verify: rubric "When domain-classifier returns a specific domain with rewrite_target, the Issue body's Pre-merge verify command path arguments and AC text file path references are rewritten to the Domain file path before gh issue create. Background/Purpose context path mentions are preserved unchanged." --> 具体 Domain が返った場合の path 書き換えロジック（対象範囲の明確化込み）が記述されている
- <!-- verify: rubric "When domain-classifier returns ambiguous, the Issue is created with Core target preserved and a '## Domain Classification' section is appended to the Issue body with classifier_result=ambiguous, reason, and action_required fields" --> ambiguous 時のフォールバック動作（note フォーマット込み）が記述されている
- <!-- verify: grep "ambiguous" "skills/verify/SKILL.md" --> `ambiguous` 時の動作が Step 13 側に記述されている
- <!-- verify: rubric "When domain-classifier invocation fails (e.g., no Domain files with applies_to_proposals found, classifier error), the implementation falls back to Core target Issue creation (consistent with the 'no Domain file → Core' existing behavior)" --> classifier エラー時のフォールバック動作が記述されている
- <!-- verify: rubric "The implementation is domain-agnostic: adding a new Domain file (bundled or project-local) with applies_to_proposals frontmatter requires NO changes to skills/verify/SKILL.md or .wholework/domains/verify/skill-infra-classify.md (Open/Closed Principle)" --> 新 Domain 追加時に本 skill 側の修正が不要であることが明記されている

### Post-merge

- skill-dev プロジェクトで retro 改善提案から `/verify` を完了させ、生成された Issue の対象パス（verify command target）が `skills/*/skill-dev-*.md` などの Domain file に書き換わっていることを手動確認
- テスト用に新 Domain file（例: web-dev stub）を `.wholework/domains/` に配置して retro を回し、Step 13 側の修正なしで該当提案が新 Domain に分類されることを手動確認
- Code improvement 分類の提案が classifier を経由せず従来通り Issue 化されることを手動確認

## Notes

- 実装ロケーション: Issue の Auto-Resolved Ambiguity Points に従い、`skills/verify/SKILL.md` Step 13 本体に domain-classifier 呼び出しを追加する（skill-infra-classify.md は変更しない）
- Classifier 入力の Domain file スコープは `/verify` 自身の domain-loader (SKILL_NAME=verify) がロードするものより広い。全 skill にまたがる Domain files を参照するため、Glob を使って独立に収集する
- `skill-infra-classify.md` は #295 Sub 4B で既に新設済み（worktree で確認済み）。frontmatter に `applies_to_proposals` は不要（このファイルは Skill-infra vs Code 分類基準を提供するものであり、自身が classifier の入力となる Domain file ではない）
- 書き換えスコープ: Pre-merge AC の verify command path 引数 + AC テキスト中の明示的ファイルパス参照のみ。Background / Purpose などコンテキスト記述のパス言及は保持（文脈情報として有用）
- HAS_OPEN_BLOCKING=true: #295 がオープンだが worktree で skill-infra-classify.md の存在を確認済みのため、#295 Sub 4B は実質完了と判断し実装可能
