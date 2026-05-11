# Issue #439: docs: UI 再現案件 methodology guide (visual-reproduction.md, type: project) を新規作成

## Overview

UI 再現案件 (旧サイトのフレームワーク移行、Figma デザイン → 実装、CMS テーマ移行等) における 3 つの failure mode (A: PASS criteria が狭い / B: 仕様書 vs reference の取り違え / C: 状態の網羅不足) を体系化した **Project Document** `docs/visual-reproduction.md` を新設する。`type: project` で配置し、`docs/translation-workflow.md` 準拠で `docs/ja/visual-reproduction.md` ミラーを同期。

参照経路は **Mitigation 2 規約準拠** (#441 で確立): `modules/verify-patterns.md` への eager-load リンク追加は **行わず**、`skills/spec/visual-diff-guidance.md` (#441 で作成済の Domain file、`capability: visual-diff` gate) からの conditional 参照のみとする。これにより domain 外プロジェクトでは本 doc が一切 Read されない (eager overhead ゼロ)。

`skills/spec/visual-state-enumeration.md` (#438、Spec 完了 / code 未実装) からの参照は #438 code 実装時に追加するため本 Issue scope 外。

## Changed Files

- `docs/visual-reproduction.md`: 新規 — Project Document (`type: project`, `ssot_for: visual-reproduction-methodology`)。Failure modes A/B/C 分類 + 3 原則 + tooling 要件 + workflow + anti-patterns + exemplar references の 6 章構成
- `docs/ja/visual-reproduction.md`: 新規 — `docs/translation-workflow.md` 準拠の日本語ミラー
- `docs/structure.md`: change Directory Layout `docs/` セクションに `visual-reproduction.md` エントリ追加 (`# UI 再現案件 methodology (project)` コメント付き、`translation-workflow.md` 行の直後に挿入)
- `docs/ja/structure.md`: change Directory Layout に対応エントリ追加 (ja mirror sync)
- `skills/spec/visual-diff-guidance.md`: change 適切な箇所 (`## When to Use visual_diff` の Primary Application Scenarios サブセクションなど) に `docs/visual-reproduction.md` へのリンクを追加 (capability gate 越しの conditional 参照経路を確立)

## Implementation Steps

1. `docs/visual-reproduction.md` を新設 — frontmatter (`type: project`, `ssot_for: visual-reproduction-methodology`) + 6 章構成: (1) Failure modes A/B/C 分類 (検証範囲選択バイアス / reference 優先原則違反 / state 直積不徹底)、(2) 原則 3 点 (AI vision review = `visual_diff` + `frontend-visual-review` sub-agent が主証跡 / reference > spec doc / state 完全直積)、(3) Tooling 要件 (Playwright + sharp + pixelmatch + `visual_diff` + `frontend-visual-review`)、(4) Workflow (Issue → Spec [#438 state-enumeration scaffold] → Code → Verify [`visual_diff` 全 viewport × state])、(5) Anti-patterns (`zero_gaps_detected: true` 未明示で全 PASS 誤認 / reference より仕様書優先 / default state 単独 verify)、(6) Exemplar references (generic な架空サンプル) (→ V1)
2. `docs/structure.md` Directory Layout `docs/` セクション内 `translation-workflow.md` 行の直後に `visual-reproduction.md  # UI 再現案件 methodology guide (project)` 行を挿入 (parallel with 1) (→ V3)
3. `skills/spec/visual-diff-guidance.md` の `## When to Use visual_diff` セクション (Primary Application Scenarios サブセクション末尾、または専用の "See also" サブセクション) に `docs/visual-reproduction.md` への Markdown リンクを追加 (Mitigation 2 規約: `modules/verify-patterns.md` には追加しない、capability gate 越しの conditional 参照経路として確立) (parallel with 1, 2) (→ V3、V2 の Mitigation 2 規約準拠は file_not_contains で検証)
4. `docs/ja/structure.md` ミラーを同期 (`docs/translation-workflow.md` 準拠、Step 2 と同位置に日本語版エントリを挿入) (after 2) (→ V3 の ja mirror 部分)
5. `docs/ja/visual-reproduction.md` を新設 (`docs/translation-workflow.md` 準拠、Step 1 の 6 章構成を日本語化して全文同期) (after 1) (→ V4)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/visual-reproduction.md" --> <!-- verify: file_contains "docs/visual-reproduction.md" "type: project" --> <!-- verify: rubric "docs/visual-reproduction.md は frontmatter (type: project, ssot_for: visual-reproduction-methodology) と 6 章構成 ((1) Failure modes A/B/C 分類、(2) 原則 3 点 [AI vision primary / reference > spec / state 完全直積]、(3) Tooling 要件 [Playwright + sharp + pixelmatch + visual_diff + frontend-visual-review]、(4) Workflow [Issue → Spec → Code → Verify]、(5) Anti-patterns [zero_gaps_detected 未明示で全 PASS 誤認 / reference より仕様書優先 / default state 単独 verify]、(6) Exemplar references) を含んでいる" --> V1: `docs/visual-reproduction.md` が `type: project` Project Document として frontmatter + 6 章構成で作成されている
- <!-- verify: file_not_contains "modules/verify-patterns.md" "visual-reproduction.md" --> V2: `modules/verify-patterns.md` には `docs/visual-reproduction.md` へのリンクが追加されていない (Mitigation 2 規約準拠、eager-load 共通モジュール経由の誘導を回避)
- <!-- verify: file_contains "docs/structure.md" "visual-reproduction.md" --> <!-- verify: file_contains "docs/ja/structure.md" "visual-reproduction.md" --> <!-- verify: file_contains "skills/spec/visual-diff-guidance.md" "visual-reproduction.md" --> V3: `docs/structure.md` (en + ja) Directory Layout に `visual-reproduction.md` エントリ追加、`skills/spec/visual-diff-guidance.md` (capability gate 越し Domain file) から `docs/visual-reproduction.md` へのリンク追加
- <!-- verify: file_exists "docs/ja/visual-reproduction.md" --> <!-- verify: file_contains "docs/ja/visual-reproduction.md" "type: project" --> V4: `docs/ja/visual-reproduction.md` ミラーが作成されている (translation-workflow.md 準拠の日本語同期)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> V5: bats test CI が PASS

### Post-merge

- <!-- verify: rubric "新規 user が docs/visual-reproduction.md を読んで visual reproduction Issue を立てられる (failure modes と Workflow が理解可能)。また skills/spec/visual-diff-guidance.md (#441 capability gate 越し Domain file) から本 doc への参照リンクが capability gate 越しの conditional 参照経路として機能している" --> 実プロジェクト適用時に doc が methodology reference として機能し、Domain file 経由の conditional 参照経路が動作する <!-- verify-type: opportunistic -->

## Notes

- **三位一体の最後の 1 つ**: #441 (visual_diff 実装、完了済) ↔ #438 (state enumeration scaffold、Spec 完了 / code 未実装) ↔ 本 #439 (methodology guide)。三者すべてが `capability: visual-diff` gate もしくは Domain file 経由の conditional 参照で domain 外 eager overhead ゼロを実現
- **Mitigation 2 規約準拠** (#441 で確立、`docs/environment-adaptation.md` Extension Guide Step 6 で明文化): capability-specific guidance / methodology content は eager-load 共通モジュール (`modules/verify-patterns.md` 等) に置かず、Domain file or Project Document 経由の lazy load にする。本 Issue の `modules/verify-patterns.md` リンク追加撤回はこの規約の direct application
- **`type: project` 配置の判断根拠**: `docs/visual-reproduction.md` は単一 capability に紐づく methodology document であり、Steering Documents (`product.md` / `tech.md` / `structure.md`) より下位の Project Document カテゴリに位置する。`docs/environment-adaptation.md` (`type: project`) / `docs/workflow.md` (`type: project`) と同カテゴリ
- **`#438` の visual-state-enumeration.md からの参照**: #438 Spec body (本セッションで作成済) では「Domain file は `docs/visual-reproduction.md` を参照する」設計だが、`skills/spec/visual-state-enumeration.md` 自体は #438 code 実装で初めて作成されるため、本 Issue では参照リンク追加は対象外。#438 code 実装時に visual-state-enumeration.md 内に docs/visual-reproduction.md へのリンクを含める
- **AC 数値の整合**: 本 Spec の Verification > Pre-merge は 5 items (Issue body も 5 items に同期更新; 元の Issue body は 10 items だったが light template Simplicity Rule に従い consolidate)
- **`visual-reproduction.md` の本文内容**: failure modes / 原則 / tooling / workflow / anti-patterns / exemplar の 6 章は #441 retrospective comments と Issue body 中の Background セクションを SSoT として整合
- 同パターンの参考実装: `docs/environment-adaptation.md` (`type: project`、4-layer architecture の methodology)、`docs/translation-workflow.md` (`type: project`、ja mirror sync の methodology)

## Code Retrospective

### Deviations from Design

- N/A (実装ステップは Spec 通りに実施。Step 1-5 の並列化は Spec 記載の通り実行)

### Design Gaps/Ambiguities

- `skills/spec/visual-diff-guidance.md` へのリンク挿入位置が Spec に「Primary Application Scenarios サブセクション末尾、または専用の "See also" サブセクション」と記載されていたが、具体的な挿入位置はファイルの構造を確認した上で "Problem `visual_diff` Solves" セクションの直前に挿入した (論理的に最も自然な位置)

### Rework

- N/A

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. 実装は Spec のすべての実装ステップに準拠。`visual-diff-guidance.md` へのリンク挿入位置の微調整は Design Gaps/Ambiguities として Code Retrospective 内にすでに記録済み。

### Recurring Issues

Nothing to note. MUST/SHOULD 指摘なし。review-light 4 視点すべてクリーン。ドキュメントのみの PR は Edge Cases・Security の視点が N/A になる性質があり、今後同種の PR ではこれを前提として review に臨める。

### Acceptance Criteria Verification Difficulty

Nothing to note. 全 AC が `file_exists` / `file_contains` / `file_not_contains` / `rubric` / `github_check` の組み合わせで構成されており、safe モードで UNCERTAIN ゼロ (10/10 PASS)。ドキュメント系 Issue の AC 設計モデルケースとして参照可能。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC が `file_exists` / `file_contains` / `file_not_contains` / `rubric` / `github_check` のみで構成されており、safe モードで UNCERTAIN ゼロ (全 6 条件 PASS)。ドキュメント系 Issue の AC 設計モデルケースとして参照可能
- Scope の章立て (1)-(6) が実装の 6 章構成に直接マッピングされており、実装者の迷いを排除した

#### design
- Mitigation 2 規約準拠の参照経路設計（`modules/verify-patterns.md` へのリンク追加を撤回し、capability gate 越し Domain file 経由のみ）が Issue body と Spec で一貫していた
- #438/#441 との three-way dependency が Notes に明記されており、将来の参照として有用

#### code
- Code Retrospective 記載通り Rework なし。`visual-diff-guidance.md` へのリンク挿入位置のみ微調整（Spec が「または」で代替案を提示していた）
- Spec 記載の 5 ステップに沿って並列実装が完遂された

#### review
- MUST/SHOULD 指摘なし、review-light 4 視点クリーン
- ドキュメント専用 PR では Edge Cases・Security の視点が N/A になる性質が確認された（今後同種 PR の review 時に前提として活用可）

#### merge
- PR #451 でクリーンマージ。コンフリクトなし、CI 全チェック pass

#### verify
- 全 6 条件（V1〜V5 + post-merge rubric）PASS、再オープンなし
- AC の verifiability が高く verify が安定して完了した（high-verifiability AC 設計の効果を確認）

### Improvement Proposals
- N/A
