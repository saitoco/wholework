# Issue #221: Update browser-adapter and lighthouse-adapter for 2576px support

## Overview

Claude Opus 4.7 は最大 2,576 px (long edge) の高解像度画像をサポートする初の Claude モデル。以前のモデルより 3× 以上の解像度で、座標は実ピクセルと 1:1 のため scale-factor 変換が不要となった。一方、フルレゾリューションの画像トークンは最大 4,784 tokens/image と 3× のコストになる。

`modules/browser-adapter.md` と `modules/lighthouse-adapter.md` に以下の内容を追記する:
- 2576px 対応の記載
- Token budget セクション (4,784 tokens/image) とダウンサンプリング指針 (browser-adapter のみ)
- scale-factor conversion の記述は現時点で両ファイルに存在しないため削除不要

## Changed Files

- `modules/browser-adapter.md`: `## Output` セクションの後に `## Token budget` セクションを追加 (2576px 対応、4,784 tokens/image、downsample 指針)
- `modules/lighthouse-adapter.md`: `## Output` セクションの後に `## Notes` セクションを追加 (2576px モデル対応の記載)

## Implementation Steps

1. `modules/browser-adapter.md` の末尾 (`## Output` の後) に `## Token budget` セクションを追加する。内容:
   - Claude Opus 4.7 が 2576 px (long edge) まで対応することを明記
   - フルレゾリューション時のトークンコストを 4,784 tokens/image と明記
   - トークン予算が制約される場合のダウンサンプリング指針を記載 ("downsample" という語を含む)
   (→ acceptance criteria 1, 2, 4, 5)

2. `modules/lighthouse-adapter.md` の末尾 (`## Output` の後) に `## Notes` セクションを追加する。内容:
   - Claude Opus 4.7 が 2576 px まで対応することを明記
   - フルレゾリューション時のトークンコスト (4,784 tokens/image) も記載
   (→ acceptance criteria 3)

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/browser-adapter.md" "2576" --> browser-adapter.md が 2576px 対応を記載
- <!-- verify: file_contains "modules/browser-adapter.md" "downsample" --> ダウンサンプリング指針が記載されている
- <!-- verify: file_contains "modules/lighthouse-adapter.md" "2576" --> lighthouse-adapter.md が 2576px 対応を記載
- <!-- verify: section_contains "modules/browser-adapter.md" "Token budget" "4,784" --> トークン予算セクションに 4,784 tokens/image の記載
- <!-- verify: file_not_contains "modules/browser-adapter.md" "scale-factor conversion" --> scale-factor conversion の旧挙動注記が除去されている

### Post-merge

- `/verify` の `browser_screenshot` を高解像度 URL で実行し、AI 視覚判定の精度改善を確認
- `lighthouse_check` のパフォーマンス測定で regression が無いことを確認

## Notes

- `file_not_contains "modules/browser-adapter.md" "scale-factor conversion"` は現時点の browser-adapter.md に該当文字列が存在しないため、変更なしで PASS する。実装時に "scale-factor conversion" を誤って追加しないよう注意すること。
- lighthouse-adapter.md は現在 AI ビジョンでスクリーンショットを判定する機能を持たないが、将来の視覚検証統合を見越した能力文書として 2576px 記載を追加する。

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- Specの Notes セクションに「scale-factor conversion を誤って追加しないよう注意」と記載されていたが、Token budget セクションの説明文として "No scale-factor conversion is needed" という表現を使用してしまった。verify check で FAIL となり、当該表現を "Coordinates are 1:1 with actual pixels on Opus 4.7 — no coordinate scaling is required." に修正して対応した。

### Rework
- `modules/browser-adapter.md` の Token budget セクションの末尾文言を1回修正（"scale-factor conversion" という語の除去）。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は5つすべて verify コマンド付きで定義されており、自動検証可能な品質。`file_not_contains` による禁止表現チェックも含まれており、Spec の注意書きと対になっている。
- Specの Notes に「scale-factor conversion を誤って追加しないよう注意」と明記されていたにもかかわらず、実装時に同語を含む表現が生成された。注意書きの効果が限定的だったことが示唆される。

#### design
- 設計は実装と一致。変更対象ファイル（browser-adapter.md, lighthouse-adapter.md）と追加セクション（Token budget, Notes）が明確に指定されており、逸脱なし。

#### code
- 実装コミット（bc91c7c）後に fix コミット（41a88f2）が1件。"scale-factor conversion" という禁止語を含む表現を1回書き直した。
- `file_not_contains` verify コマンドが実際にこの誤りを捕捉したことが確認されており、フィードバックループが機能した例といえる。

#### review
- パッチルート（direct commit to main）のため、正式な PR レビューなし。小規模変更（+16行）でパッチルートとして妥当。

#### merge
- `closes #221` を含む初回コミット後、fix コミットで直接 main に push。コンフリクトなし。

#### verify
- 全5件の pre-merge 条件が PASS。`section_contains` による特定セクション内検索が正常動作。
- Post-merge 条件2件（`verify-type: manual`）は自動検証対象外であり、手動確認として残存。これは正しい動作。

### Improvement Proposals
- N/A
