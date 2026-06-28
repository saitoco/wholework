# Issue #435: triage GraphQL Batch Field Update

## Overview

triage スキルが Project field (Size / Value / Priority) を更新する際、`update-field-value` named query を個別に 3 回呼び出していた (さらに `add-project-item` も重複)。`scripts/gh-graphql.sh` に Size + Value を 1 つの GraphQL mutation aliases で更新する named query `update-issue-fields-batch` を追加し、triage SKILL.md を更新して batch 呼び出しに切り替える。これにより GraphQL round-trip 回数を削減し、triage の実行時間を短縮する。

## Consumed Comments

- saito (MEMBER, first-class): `scripts/gh-graphql/` ディレクトリは現存せず、named query は `gh-graphql.sh` の case 文で管理されている。実装者は case 文追加と新ディレクトリ構成のどちらも選択可能。`tests/gh-graphql.bats` と `tests/triage-backlog-filter.bats` の両ファイルが存在することを確認済み。

## Changed Files

- `scripts/gh-graphql.sh`: `get_named_query()` の case 文に `update-issue-fields-batch` を追加 — Size + Value の 2 フィールドを GraphQL mutation aliases で 1 リクエストに集約。bash 3.2+ 互換
- `skills/triage/SKILL.md`: Single Issue Execution の Step 5/6/8 と Bulk Execution の Step 3 内の project field 更新ロジックを統合 — `add-project-item` 1 回 + `update-issue-fields-batch` 1 回 + Priority 検出時のみ `update-field-value` に変更。label fallback 経路は維持
- `tests/gh-graphql.bats`: `--query update-issue-fields-batch` の named query 解決テストを追加

## Implementation Steps

1. `scripts/gh-graphql.sh` の `get_named_query()` case 文に `update-issue-fields-batch` を追加する (→ AC1)
   - GraphQL mutation: `sz:updateProjectV2ItemFieldValue(...)` + `vl:updateProjectV2ItemFieldValue(...)` の 2 aliases を 1 mutation に集約
   - 必要変数: `projectId`, `itemId`, `sizeFid`, `sizeOid`, `valueFid`, `valueOid`
   - 使用例: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query update-issue-fields-batch -F projectId="$PROJECT_ID" -F itemId="$ITEM_ID" -F sizeFid="$SIZE_FID" -F sizeOid="$SIZE_OPT" -F valueFid="$VALUE_FID" -F valueOid="$VALUE_OPT"`

2. `skills/triage/SKILL.md` を更新して batch 呼び出しに変更する (→ AC2, AC3)
   - Single Issue Execution: Steps 5/6/8 を統合し、次の順序で実行する新 "Combined Project Field Batch Update" セクションに置き換える:
     1. `get-projects-with-fields` (--cache) で project / field / option 情報を取得 (1 回)
     2. `get-issue-id` (--cache) で Issue の node ID を取得 (1 回)
     3. `add-project-item` で Issue を project に追加し itemId を取得 (1 回)
     4. `update-issue-fields-batch` で Size + Value を 1 call で更新
     5. Priority が検出された場合のみ `update-field-value` で Priority を追加更新
     6. GraphQL 失敗時: Size / Value / Priority それぞれ label fallback (従来動作を維持)
   - Bulk Execution Step 3 の per-issue 更新も同様に batch 化
   - Named queries to use: `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-issue-fields-batch`, `update-field-value` (Priority のみ)

3. `tests/gh-graphql.bats` に `update-issue-fields-batch` named query テストを追加する (→ AC4)
   - テスト名: `@test "success: --query update-issue-fields-batch resolves named query"`
   - 検証: status=0、`gh api graphql` が呼ばれること

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-graphql/ 配下 (または同等の named query 配置場所) に Project field を複数同時更新する bulk mutation 用の named query が追加されている" --> bulk 更新用 named query が追加されている
- <!-- verify: rubric "skills/triage/SKILL.md が bulk GraphQL mutation の named query を参照するよう更新されており、named query 名と SKILL.md 内の参照が一致している" --> `skills/triage/SKILL.md` が新しい bulk named query を使うよう更新されている (named query 名は変更可、その場合 SKILL の表記と一致していること)
- <!-- verify: rubric "skills/triage/SKILL.md は GraphQL 失敗時の label fallback の挙動を従来どおり維持しており、bulk 化によって fallback 経路が壊れていない" --> GraphQL 失敗時の label fallback 経路が壊れていない
- <!-- verify: command "bats tests/gh-graphql.bats tests/triage-backlog-filter.bats" --> 既存の gh-graphql / triage 関連テストが通る

### Post-merge

- サンプル Issue に対して `/triage <N>` を実行し、API 呼び出し回数の削減が観測される

## Notes

- **実装配置の自動解決 (non-interactive auto-resolve)**: `scripts/gh-graphql/` ディレクトリは現存しない。Issue 本文は `scripts/gh-graphql/` 配下への追加を記述するが、コメントより実装者は case 文追加方式も選択可能。Spec では case 文追加方式を採用する (構造変更なし、既存 named query パターンとの一貫性)。
- **Priority を batch に含めない理由**: Priority 非検出時は "Skip without warning" が triage の正当な動作であるため、Size + Value (常に更新対象) のみを batch 対象とした。Priority は従来どおり `update-field-value` で個別更新 (非検出時スキップ)。
- **project-field-update.md は変更不要**: triage SKILL.md が直接 batch query を呼び出す実装に変更するため、共有モジュールの変更は不要。
- **Bulk Execution も対象**: Step 3 (per-issue update ループ) も同様に batch 化対象とする。Bulk 実行では N issue × (add-project-item + update-fields-batch) = 2N calls に圧縮される (従来 6N calls)。

## Code Retrospective

### Deviations from Design

- Step 5/6/8 の統合方法: Spec は "Steps 5/6/8 を統合し新セクションに置き換え" と述べているが、実際には Step 5 を Priority Detection only、Step 6 を Size Determination only に変更し、Step 8 を Combined Batch Update に改名するアプローチを採った。これにより Step 7 (AC audit) の番号変更が不要になり、変更量を最小化できた。
- Bulk Step 3 の番号変更: 旧 Step 5 (Value) を Step 4 (Priority) と統合したため、Step 5-8 が Step 5-7 に繰り上がった。Spec は明示的な番号を指定していなかったため、番号変更は意図した偏差として記録。

### Design Gaps/Ambiguities

- `update-issue-fields-batch` 応答のフィールドキー: mutation aliases (`sz:`/`vl:`) を使用するため、応答は `.data.sz.projectV2Item.id` / `.data.vl.projectV2Item.id` となる。SKILL.md に明示したが、Spec には記載がなかった。

### Rework

- 特になし。Spec に記載した実装方針どおりに進められた。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `update-issue-fields-batch` は既存 case 文への追加方式 (新ディレクトリ不要) を採用。一貫性と最小変更量を優先。
- Size + Value のみ batch 対象 (Priority は別呼び出し)。Priority は非検出時スキップが正常動作のため統合外。
- 応答検証は `.data.sz.projectV2Item.id` / `.data.vl.projectV2Item.id` の両フィールド確認とした。

### Deferred Items

- 実際の API 呼び出し削減の観測は post-merge 手動確認 (opportunistic AC)。
- batch 化後の verify-after-write はバッチ成功後も Size のみ対象 (Value/Priority の read-back ヘルパーは現状なし)。

### Notes for Next Phase

- bats 33 テスト全 PASS。CI で test.yml が通ることを確認すること。
- `/verify` フェーズでは rubric 3 件 + command 1 件を再確認。rubric は grader の adversarial 評価が主眼。
- SKILL.md の Step 5/6/8 を再編しており、レビュー時は変更前後の構造の差分を意識して確認すること。
