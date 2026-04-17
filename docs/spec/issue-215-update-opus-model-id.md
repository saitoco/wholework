# Issue #215: run-spec.sh の Opus モデル ID を claude-opus-4-7 へ更新

## Issue Retrospective (refinement 2026-04-17)

### Judgment Rationale

利用者から「これを機に `model: opus` エイリアスを使った方がよい？」という明示的な scope 拡張提案があり、3 案（A. 最小スコープ維持 / B. Opus のみ alias / C. 全 run-*.sh を alias）を提示して判断を仰いだ。

**選択: A. 最小スコープ維持**

### 採用理由

1. **速度**: Priority=urgent の本 Issue を最短でマージするため、スコープを 1 行置換に固定
2. **ベンチマーク柔軟性**: 関連 Issue #226（Opus 4.7 vs 4.6 ベンチ）でバージョンピン固定が必要。alias 化はこの用途と競合する
3. **レビュー粒度**: pure な version bump は review-bug / review-spec が容易に検証可能。refactor と混在させない
4. **独立性**: agents 側は既に alias、run-*.sh は pinned という非対称性は Wholework 全体の命名規則の課題として独立検討する価値がある

### 派生アクション

- 新規 Issue #227 を作成（Priority=medium, Size=S, type/task）。対象は 6 run-*.sh 全体 × Opus/Sonnet、ANTHROPIC_MODEL の alias 対応検証を含む
- 本 Issue の body に Related Issues として #227 を追記
- docs/reports/claude-opus-4-7-optimization-strategy.md §6 migration checklist の精神に整合（alias 化は §6 では言及なしだが #227 で別途カバー）

### AC 変更

- AC 自体は変更なし（既に `file_contains "claude-opus-4-7"` + `file_not_contains "claude-opus-4-6"` でピン更新を正しく捉えている）
- Body の Purpose セクションに「スコープ最小化の明示」と #227 参照を追加のみ
