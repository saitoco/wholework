# Issue #76: verify: /verify Step 13 で作成する Issue に retro/verify ラベルを付与する

## Issue Retrospective

`/issue 76` 実行時の精査結果。

### Auto-resolved ambiguities

3 個の ambiguity を auto-resolve:

1. **Label 色の hex 不整合**: 元案「水色系 `#0e8a16`」は内部矛盾していた。`#0e8a16` は GitHub 標準 green で、`triaged` ラベルが既に同 hex を使用中(`gh label list` で確認済み)。元の意図「水色系」を尊重して `#c5def5`(GitHub 標準 light blue)に修正。これによって既存ラベルとの色衝突も回避。
2. **失敗時の挙動**: `audit/drift` / `audit/fragility` の既存実装を確認したところ、明示的な error halting なしの best-effort パターン。同パターンを継承する旨を本文に明記。
3. **Label description**: 既存 audit パターンには description text の指定がなかったが、`gh label create` の慣例として有用なので `Auto-created from /verify retrospective improvement proposal` を推奨値として明記。

### Acceptance criteria の調整

Post-merge の 4 条件すべてに `<!-- verify-type: opportunistic -->` タグを追加。これらは:

- `/verify` Step 13 の次回実行で自然に検証される(Issue にラベル付与、ラベル自動作成)
- `/audit drift|fragility` の次回実行で既存挙動が検証される(audit ラベルが引き続き正しく付与される)
- `/audit stats`(#75)実装後に Work Origin セクションで分離表示が確認される

すべて手動アクション不要で、通常のワークフロー進行中に opportunistic に検証されるため `manual` ではなく `opportunistic` が適切。

### 設計判断

- **Pre-merge 3 つ目**(両フローへの付与確認)には verify command を付けず、reviewer の目視確認に委ねた。`grep -c` での回数チェックは `verify-patterns.md` で antipattern とされており、`section_contains` でも Step 13 全体が大きすぎて意味をなさないため。Code improvement / Skill infrastructure improvement の分岐後に統合された Issue 生成 flow があり、そこで一度ラベル付与すれば両カテゴリをカバーできる構造的な単純さもある。
- **既存 Issue への retrofit はしない**方針を維持: 履歴データの一貫性を壊すリスクがあり、`/audit stats` 側で「label 導入以前は その他 扱い」と明示する設計の方が clean。

### 関連

- #75 が companion Issue で、ラベル導入後に Work Origin の分離表示が有効になる
- #75 → #76 ではなく **#76 → #75 の順** で実装するのを推奨(label が先にあれば #75 のテスト時に origin 分離が即確認できる)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec フェーズは実行されず。Issue Retrospective のみが存在する。Issue 精査が十分に詳細で、実装計画が Issue 本文に含まれていたため、別途 Spec 作成は不要と判断された。
- `/issue 76` で3つの ambiguity が auto-resolve されており、Issue 品質は高い。特に色 hex の不整合(`#0e8a16` が green で water-blue の意図と矛盾)の指摘は実装の正確性に直結する重要な修正。

#### design
- N/A (Spec フェーズなし)

#### code
- 単一コミット(`ac49f65`)、16行追加のみのシンプルな実装。rework なし。
- `skills/verify/SKILL.md` の Step 13 末尾に `retro/verify` ラベル付与セクションを追加する設計は既存の `audit/drift` パターンを踏襲しており、一貫性がある。
- patch ルート（main への直接コミット）が適切に選択された。

#### review
- patch ルートのため PR レビューなし。Issue のサイズが XS であり、パターン踏襲の実装のため省略は妥当。

#### merge
- main への直接コミット。コンフリクトなし、問題なし。

#### verify
- Pre-merge 3条件すべて PASS を確認。
- Post-merge 4条件は `<!-- verify-type: opportunistic -->` で、次回の `/verify` Step 13 実行時や `/audit drift|fragility` 実行時に自然に検証される設計。
- Pre-merge 3条件目（両フローでの `retro/verify` 付与）は verify command なし → AI 判定で検証。SKILL.md line 425 「This applies to both Code improvement and Skill infrastructure improvement categories.」で確認できた。

### Improvement Proposals
- N/A
