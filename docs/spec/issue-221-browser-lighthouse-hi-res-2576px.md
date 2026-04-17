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
