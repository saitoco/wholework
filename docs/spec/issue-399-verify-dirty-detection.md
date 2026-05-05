# Issue #399: verify: 未関連ファイルの dirty 検知時に判定/誘導を追加

## Overview

`/verify` Step 1 に未関連ファイルの dirty 検知ロジックを追加する。`docs/spec/issue-N-*.md` パターン（N が対象 Issue 番号と異なる）のみが dirty な場合は interactive で stash 提案、non-interactive では自動 stash して継続する。

## Implementation Steps

1. `skills/verify/SKILL.md` の `## Error Handling in Non-Interactive Mode` テーブルの Step 1 行を更新
   - 旧: `Same (hard-error: uncommitted changes cannot be auto-resolved)`
   - 新: unrelated spec files → auto-stash, related/other files → hard-error
2. `skills/verify/SKILL.md` の `### Step 1: Check Working Directory Safety` を更新
   - clean → continue の順序に変更
   - dirty 検出時に `git status --short` でファイルリスト取得
   - unrelated 判定: `docs/spec/issue-N-*.md`（N ≠ $NUMBER）
   - all unrelated → interactive: stash-and-continue/abort 選択提示; non-interactive: 自動 stash
   - other dirty → VERIFY_FAILED 出力して hard-error abort

## Code Retrospective

### Deviations from Design

- N/A（Spec なし、Issue 本文から直接実装）

### Design Gaps/Ambiguities

- Spec が存在しなかったため Issue 本文の Auto-Resolved Ambiguity Points セクションを設計根拠として利用した。判定スコープ（`docs/spec/issue-N-*.md` のみ）と interactive/non-interactive 分岐はその記述に忠実に実装した。

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec が実装後に作成されたため、事前の設計合意ドキュメントとしての役割を果たせていない。ただし Issue 本文の "Auto-Resolved Ambiguity Points" が Spec の代替として機能しており、判定スコープの根拠が明確に記録されている点は良い。

#### design
- 判定スコープを `docs/spec/issue-N-*.md` のみに限定した設計は適切。Issue #393 の発生パターンに対して最小スコープで対応しており、過度な一般化を避けている。

#### code
- 1コミットで完了。Code Retrospective に rework なしと記録されており、実装がシンプルだったことを裏付けている。

#### review
- patch route のため PR レビューなし。SKILL.md の変更だがコードの影響範囲が Step 1 のみかつロジックが単純なため、レビューなしでも品質上の問題はなかった。

#### merge
- 直接 main コミット（patch route）。コンフリクトなし、クリーンなマージ。

#### verify
- 3条件すべて PASS。verify コマンド（`section_contains` / `section_not_contains`）が適切に実装検証をカバーしており、自動検証が高精度で機能した。
- Post-merge opportunistic 条件（実際のシナリオ再現確認）は自動検証不可のため user-deferred のまま。この種の統合シナリオテストには bats テスト化が有効だが、今回のスコープ外。

### Improvement Proposals
- 今後同様のシナリオ検証が必要な条件には `command "bats tests/..."` 形式の verify command を付与することで自動検証に昇格できる。opportunistic 条件を bats テストでカバーすることを検討する（別 Issue として起票可）。
