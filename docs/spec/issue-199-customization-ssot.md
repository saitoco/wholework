# Issue #199: docs: .wholework.yml の全キー仕様を SSoT スキーマ文書として集約

## Overview

`docs/guide/customization.md` の Available Keys テーブルは `.wholework.yml` の全キーを網羅しているが、文書上で「SSoT である」と明示されていない。本 Issue の目的は：

1. `docs/guide/customization.md` Available Keys セクションに SSoT 宣言文を追加する
2. `modules/detect-config-markers.md` に `customization.md` への参照リンクを追加し、双方向リンク化する

`customization.md` → `detect-config-markers.md` の参照（L67）は既に存在する。逆方向（`detect-config-markers.md` → `customization.md`）が不在なのが主なギャップ。

## Changed Files

- `docs/guide/customization.md`: Available Keys セクション冒頭に SSoT 宣言文を追加
- `modules/detect-config-markers.md`: Purpose セクションに `docs/guide/customization.md` への参照リンクを追加

## Implementation Steps

1. `docs/guide/customization.md` の `### Available Keys` 見出し直下にSSoT宣言文を追加: `This table is the **single source of truth (SSoT)** for all \`.wholework.yml\` configuration keys. Update this table when adding or changing keys.` (→ 受入条件 A)
2. `modules/detect-config-markers.md` の Purpose セクションに `docs/guide/customization.md` への参照リンクを追加: `For user-facing documentation and the SSoT key reference, see [docs/guide/customization.md](../docs/guide/customization.md).` (→ 受入条件 B)

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/guide/customization.md" "Available Keys" "SSoT" --> `docs/guide/customization.md` の Available Keys セクションに SSoT であることが明記されている
- <!-- verify: file_contains "modules/detect-config-markers.md" "customization.md" --> `modules/detect-config-markers.md` から customization.md への参照リンクが追加されている（双方向リンク化）
- <!-- verify: grep -E "opportunistic-verify|skill-proposals|review-bug" docs/guide/customization.md --> 主要キーが customization.md に列挙されている（既存テーブルの整合性確認）

### Post-merge

- 他ドキュメント（docs/product.md, docs/tech.md, docs/workflow.md）に customization.md と同等の full schema table が存在しないことを手動確認
- 新規キー追加時の更新箇所が `docs/guide/customization.md` と `modules/detect-config-markers.md` の 2 箇所に集約されていることを確認

## Notes

- `docs/ja/guide/customization.md` は修正対象外（`/doc translate` で自動生成）
- 追加する SSoT 宣言文には "SSoT" の文字列を含めること（verify command `section_contains` が固定文字列マッチのため）
- detect-config-markers.md への追加は Purpose セクションの末尾が適切

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
