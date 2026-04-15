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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 体と Spec 設計が明確で、受入条件は全て verify コマンドで自動検証可能な形式に整備されていた。SSoT 宣言文に "SSoT" の固定文字列を含める制約が Notes に明記されており、verify command との整合が事前に考慮されていた。

#### design
- 「実質的な SSoT は既に存在するが文書上で明示されていない」という問題分析が的確で、新規ドキュメント作成不要という判断（既存 customization.md を活用）はスコープ最小化として適切。

#### code
- パッチルート（main 直コミット）での実装。commits: `24ba7e9` (design) → `b7b4698` (実装) → `4c1c5dc` (code retro) と整然としており、リワーク（fixup/amend）なし。

#### review
- パッチルートのため PR レビューなし。変更範囲が2ファイルの1行追加ずつと小さく、PR 不要判断は妥当。

#### merge
- `closes #199` により Issue が自動クローズ。コンフリクト痕跡なし。

#### verify
- Pre-merge 3条件すべて PASS。Post-merge の2条件は `verify-type: manual` で自動検証対象外。`phase/verify` ラベルを付与してユーザー確認待ちとした。verify コマンドの品質は高く、全条件が明確に自動判定できた。

### Improvement Proposals
- N/A
