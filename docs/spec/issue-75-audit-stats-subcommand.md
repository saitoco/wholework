# Issue #75: audit: /audit stats subcommand を追加する (プロジェクト健康診断レポート)

## Overview

`/audit` に横断的な metadata 駆動の統計分析を行う `stats` サブコマンドを追加する。既存の `drift` (ドキュメント↔コード) / `fragility` (構造的脆弱性) に加え、Issue throughput・composition・first-try success rate などを集計するプロジェクト健康診断の第 3 の lens を提供する。read-only ツールで、レポートは stdout 出力に加え `docs/stats/YYYY-MM-DD.md` へ保存する (`--no-save` でスキップ可)。

## Changed Files

- `skills/audit/SKILL.md`:
  - frontmatter `description` の末尾に `/audit stats` の説明を追加
  - `Command Routing` セクションに `stats` 分岐と Usage メッセージ更新
  - 新規セクション `## stats Subcommand` を `## fragility Subcommand` と `## Integrated Execution` の間に追加 (Option Parsing / Step 1 Data Collection / Step 2 Computation / Step 3 Report Generation / Step 4 Save)
- `docs/workflow.md`: L32 の `/audit drift` / `/audit fragility` 説明段落に `/audit stats` の 1 文を追記 (プロジェクト健康診断の第 3 の lens として)

## Implementation Steps

1. `skills/audit/SKILL.md` に `## stats Subcommand` セクションを新規追加する。サブセクションは Issue #75 設計に準拠: (a) Option Parsing (`--since DATE` / `--limit N` / `--no-save`)、(b) Step 1 Data Collection (`gh issue list`/`gh issue view` で全 Issue の title/body/labels/timelineItems を取得)、(c) Step 2 Computation (3 粒度の成功/失敗定義、keyword-based Content segment 分類、Work Origin 分類、30 日 × 3 window の trend、Backlog Health 閾値 90d+)、(d) Step 3 Report Generation (Highlights / Flow / Composition / Work Origin / Outcome / Backlog Health の 6 セクション、Highlights 自動検出ロジックの 2x・trend・backlog net 差分判定)、(e) Step 4 Save (`docs/stats/YYYY-MM-DD.md` に `mkdir -p docs/stats` で保存、`--no-save` 時は stdout のみ) (→ 受入条件 pre-merge #1–#7)
2. `skills/audit/SKILL.md` の `## Command Routing` セクションに `stats` 分岐を追加: `If ARGUMENTS is 'stats' or starts with 'stats' (including options like --since DATE, --limit N, --no-save): execute the "stats Subcommand" section and exit.` を `fragility` 分岐と Integrated Execution 分岐の間に挿入する。Usage エラーメッセージを `Usage: /audit [drift|fragility|stats] [--dry-run] [--limit N] [--since DATE] [--no-save]` に更新 (→ 受入条件 pre-merge #8)
3. `skills/audit/SKILL.md` の frontmatter `description` を更新し、`/audit stats` subcommand (プロジェクト健康診断レポート) の説明を末尾に追記する。既存の drift/fragility 説明はそのまま残す (1 行内に収める)
4. `docs/workflow.md` の L32 段落末尾に `/audit stats` は Issue metadata を横断的に集計しプロジェクト健康診断レポート (throughput / composition / first-try success / Backlog Health 等) を生成する第 3 の lens である旨の 1 文を追記する (→ 受入条件 pre-merge #9)

## Verification

### Pre-merge
- <!-- verify: file_contains "skills/audit/SKILL.md" "stats Subcommand" --> `skills/audit/SKILL.md` に stats subcommand のセクションが追加されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "docs/stats/" --> `skills/audit/SKILL.md` に `docs/stats/` 保存ロジックが記載されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "First-try success" --> First-try success の定義が SKILL.md に明記されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "Work Origin" --> Work Origin セクション生成ロジックが記載されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "Backlog Health" --> Backlog Health セクション生成ロジックが記載されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "--no-save" --> `--no-save` オプションのハンドリングが記載されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "Content segment" --> Content segment 分類ロジックが記載されている
- <!-- verify: section_contains "skills/audit/SKILL.md" "Command Routing" "stats" --> Command Routing セクションに `stats` の分岐が追加されている
- <!-- verify: file_contains "docs/workflow.md" "audit stats" --> `docs/workflow.md` の `/audit` 関連記述に stats サブコマンドが追加されている

### Post-merge
- `/audit stats` を実行すると stdout に markdown report が出力される
- デフォルトで `docs/stats/YYYY-MM-DD.md` が作成される
- `/audit stats --no-save` で save がスキップされ stdout のみが出力される
- レポートに 6 セクション (Highlights, Flow, Composition, Work Origin, Outcome, Backlog Health) がすべて含まれる
- Size 別 First-try success の計算が実際のデータで意味のある数値を返す
- keyword-based content segment 分類が動作し、各 segment の件数が計上される
- Highlights セクションが乖離の大きい segment を自動ピックアップする
- companion Issue (`/verify` Step 13 への `retro/verify` ラベル付与) が merge された後、Work Origin セクションで retrospective 由来 Issue が分離表示される

## Notes

- `docs/stats/` ディレクトリは初回実行時に `mkdir -p docs/stats` で自動作成する (Issue body の保存フォーマット節準拠)。`.gitignore` 追加は行わない (履歴追跡のためコミット前提)。
- `docs/ja/workflow.md` (日本語ミラー) は `/doc translate ja` で自動生成される訳出物のため、本 Spec の changed-files には含めない (Issue 側でも pre-merge 条件に含まれていない)。
- `retro/verify` ラベルは本 Issue のスコープ外。companion Issue で導入予定で、MVP 実装では「label が存在しない場合は manual+retrospective を合算して "その他"」のフォールバックを書いておけば、companion Issue merge 後に自動で分離表示される。
- `gh issue view N --json timelineItems` は reopen 判定と phase label 遷移履歴の解析に用いる。`/audit stats` の実行時は `--limit` Issue 全件に対して順次 API コールするため、`--limit` のデフォルト 500 は rate limit への配慮として機能する。
- Content segment の keyword-based 分類は MVP。将来 LLM 分類へ拡張可能なよう、分類ロジックを独立サブセクションとして記述する (SKILL.md 内で「Content segment 分類 (MVP: keyword-based)」と見出しで明示)。
- Highlights は「解釈/推論はレポートに含めない」方針に従い、自動検出のみを記載する。SKILL.md にも「解釈しない。検出閾値に該当する項目のみ列挙する」と明記する。
