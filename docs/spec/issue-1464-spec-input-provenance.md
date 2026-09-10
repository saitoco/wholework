# Issue #1464: spec: 実データ検証を行った場合は入力 fixture の出所を Spec に記録する

## Issue Retrospective

**非対話モード (`--non-interactive`) で実行。**

### 実施内容

- `## Acceptance Criteria` セクションが存在しなかったため新規作成した。既存の「想定される方向性 (要検討)」3 案のうち、1 点目 (Notes への入力出所記録) と 2 点目 (再取得不能な入力の fixture 保存選択肢) を採用対象とし、`skills/spec/SKILL.md` Step 8 (Identify Uncertainty) への追記として AC を構成した
- 3 点目 (`/verify` 側の注記、Issue 本文で「任意」と明記) は本 Issue のスコープから除外した。Size XS の範囲に留め、必要になれば別 Issue で対応する方針
- 全 AC を Pre-merge (rubric + section_contains の組み合わせ) に分類。ドキュメント (Skill 手順) の内容追加であり、外部環境依存や実行結果検証を要しないため Post-merge 条件は「なし」

### 曖昧ポイントの自動解決

3 件の曖昧ポイントを自動解決した (詳細は Issue 本文 `## Auto-Resolved Ambiguity Points` を参照)。

1. 採用する方向性の範囲 — 3 点中 2 点を採用、1 点 (任意項目) を除外
2. ルールの追加位置 — `skills/spec/SKILL.md` Step 8 (Identify Uncertainty)。背景の事象が「実機検証によって前提の不確実性を解消した」ケースであり、同ステップの既存対象範囲と一致するため
3. トリガー条件の厳密な文言 — Issue 本文の表現をそのまま踏襲し、確定は `/spec` の実装判断 (How) に委ねた。AC は `rubric` による意味的判定を用いており、字句一致を要求しないため問題ない

### Consumed Comments

No new comments since last phase.
