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
