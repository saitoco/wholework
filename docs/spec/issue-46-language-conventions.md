# Issue #46: docs: Strengthen Language Conventions in CLAUDE.md for reliable Skill output compliance

## Issue Retrospective

### 判断根拠

- **#44 からの方針転換**: Skill の SKILL.md に直接言語指示を埋め込むアプローチは、言語選択がユーザーの好みであり Skill の汎用性を損なうため却下。CLAUDE.md 側の改善で対応する方針に変更
- **`.wholework.yml` に言語設定を追加するアプローチも検討したが不採用**: 出力物ごとに言語が混在する現状を表現するには冗長になりすぎる。まず CLAUDE.md の記述改善で効果を検証し、不十分なら次の手を考える段階的アプローチを採用

### 調査データ（#44 から引き継ぎ）

直近10件の Issue 調査結果:
- #33〜#39: 概ね日本語遵守（6/7件）
- #40〜#43: 英語/混在が増加（4/4件に何らかの違反）
- 根本原因: Skill プロンプトが長くなると CLAUDE.md の Language Conventions が LLM コンテキスト内で埋もれる

### 受入条件の変更理由

なし（初回作成）

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- `## Issue Retrospective` のみ存在（patch ルートのため Spec Retrospective は未作成）
- 受入条件の粒度は適切。`section_contains`/`grep` による検証可能な条件として明確に定義されており、ambiguity も事前に自動解決セクションで処理済み

#### design
- 設計ドキュメント（Spec）は作成されたが、実装は1コミット（`eb51526`）で完了。設計通りの直接的な変更（箇条書き→テーブル化）であり、設計逸脱なし

#### code
- パッチルート（直接 main コミット）。fixup/amend パターンなし、単一コミットでクリーンに実装完了
- `chore: restructure Language Conventions as table with PR body and Skill output rules` — コミットメッセージが変更内容を的確に表現している

#### review
- patch ルートのため PR レビューなし（XS Issue）

#### merge
- 直接 main へのコミット（patch ルート）。コンフリクトなし

#### verify
- pre-merge 3条件すべて PASS（既にチェック済みを冪等再確認）
- post-merge の opportunistic 条件 3件は自動検証対象外（`verify-type: opportunistic` で verify commandなし）。実際の Skill 実行時に確認が必要

### Improvement Proposals
- N/A
