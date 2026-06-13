# Issue #588: audit-stats: Add --retention Flag with Phase/Verify and Icebox Dwell Metrics

## Overview

`/audit stats` に `--retention` フラグを追加し、phase/verify 滞留メトリクス（中央値・p95・30 日超件数・verify-type 別待ち件数）と Icebox 滞留メトリクス（中央値・p95・再評価トリガー候補）を可視化する。滞留期間に応じた escalation（verify: 30/60/90 日、Icebox: 90/180 日）で retire 提案コメントを自動投稿し、60 日超の phase/verify Issue に `stale-verify` ラベルを付与する。

## Changed Files

- `skills/audit/SKILL.md` — stats subcommand に `--retention` オプション・計算ロジック・`### --retention Option` レポートセクション・retire 提案コメント投稿・allowed-tools 追記
- `scripts/setup-labels.sh` — ALWAYS_LABELS に `stale-verify` ラベルを追加
- `scripts/compute-escalation-level.sh` — 新規: phase/verify および Icebox の escalation レベル計算ヘルパースクリプト — bash 3.2+ 互換
- `tests/audit-retention.bats` — 新規: compute-escalation-level.sh の bats テスト
- `docs/workflow.md` — `/audit stats --retention` の説明を追記
- `docs/ja/workflow.md` — 翻訳同期（workflow.md 変更に伴う）

## Implementation Steps

1. `scripts/setup-labels.sh` の `ALWAYS_LABELS` に `stale-verify` ラベルを追加（`audit/fragility` エントリの直後に挿入）（→ AC stale-verify in setup-labels）
   - エントリ形式: `"stale-verify|EDEDED|Stale verification — phase/verify not observed in 60+ days"`
   - スクリプト先頭コメント `# Always-group (12 labels)` を `(13 labels)` に更新

2. `scripts/compute-escalation-level.sh` を新規作成 — bash 3.2+ 互換（→ AC bats test）
   - 引数: `<type> <days>`（type は `verify` または `icebox`; days は非負整数）
   - verify: 0–29d → 0, 30–59d → 1, 60–89d → 2, 90+d → 3
   - icebox: 0–89d → 0, 90–179d → 1, 180+d → 2
   - 標準出力にエスカレーションレベル（0–3）を出力; 不正入力は exit 1
   - `set -euo pipefail`; `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` パターンに従う

3. `tests/audit-retention.bats` を新規作成（after 2） — compute-escalation-level.sh をテスト（→ AC bats test）
   - verify 29d → level 0, 30d → level 1, 60d → level 2, 90d → level 3
   - icebox 89d → level 0, 90d → level 1, 180d → level 2
   - invalid type → exit 1
   - 境界値テスト（0d, 179d, 180d）

4. `skills/audit/SKILL.md` を更新（after 2）（→ ACs 1–6）
   - frontmatter `description` に `--retention` の説明を追記
   - `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/compute-escalation-level.sh:*` を追加
   - Command Routing に `--retention` オプション対応を追記（stats コマンドの options として）
   - Usage メッセージに `[--retention]` を追記
   - stats Option Parsing に `--retention` を追加（説明: retention analysis with retire-proposal comment posting）
   - stats Step 2 Computation に以下を追加:
     - `#### Manual Waiting Count` — phase/verify の unchecked `verify-type: manual` AC を持つ Issue 数
     - `#### 30-Day Threshold Violations` — phase/verify 遷移から 30 日以上経過した Issue リスト（verify の滞留 30 日超件数）
     - `#### Icebox Dwell Time` — Project Status=Icebox の Issue の created→現在の日数の median / p95 を `gh-graphql.sh get-projects-with-fields` の延長で取得
     - `#### Icebox Trigger Candidates` — Icebox Issue の body から「再評価トリガー」を grep し heuristic 判定（参照 Issue CLOSED / 言及イベント発生）
   - stats Step 3 Report Generation に `### --retention Option` セクションを追加（`--retention` 未指定時はこのセクションをスキップ）:
     - phase/verify 滞留 6 メトリクス表（中央値・p95・observation 待ち・opportunistic 待ち・manual 待ち・30 日超件数）、各閾値警告（中央値>14d / p95>30d / observation>10 / opportunistic>10 / manual>5 / 30日超>0 で WARNING 表示）
     - Icebox 滞留 4 メトリクス表（中央値・p95・件数・再評価トリガー発火候補）、各閾値警告
     - Retire 提案コメント自動投稿: `compute-escalation-level.sh verify <dwell_days>` でレベルを判定し、レベル 1（30–59d）= 観測ガイドリマインド、レベル 2（60–89d）= `stale-verify` ラベル付与 + retire 候補マーク、レベル 3（90+d）= 手動確認または観測条件削除の判断促し；Icebox は `compute-escalation-level.sh icebox <dwell_days>` で同様に処理（90d / 180d）
     - 重複防止: `gh issue view --json comments` で既コメント確認、同レベルコメント既存 Issue はスキップ
   - stats Step 4 Save: `--no-save` 未指定時は `docs/stats/YYYY-MM-DD.md` に `--retention` 出力も含める

5. `docs/workflow.md` を更新し `docs/ja/workflow.md` を同期（→ AC ja sync）
   - workflow.md 153 行目付近の `/audit stats` 説明末尾に「`/audit stats --retention` adds phase/verify and Icebox dwell metrics with escalation-based retire-proposal comments.」を追記
   - `docs/ja/workflow.md` の対応箇所を日本語で同期

## Verification

### Pre-merge

- <!-- verify: grep -- "--retention" "skills/audit/SKILL.md" --> `--retention` フラグが SKILL.md に文書化されている
- <!-- verify: grep "p95\\|30-day\\|30 day" "skills/audit/SKILL.md" --> phase/verify 滞留期間（p95・30 日超）が記載されている
- <!-- verify: grep "manual" "skills/audit/SKILL.md" --> manual 待ち件数が記載されている（新規メトリクス）
- <!-- verify: rubric "skills/audit/SKILL.md --retention subcommand specifies: phase/verify dwell-time calculation via gh timelineItems label transitions, threshold-based warnings (median/p95/30+day), escalation levels (30/60/90 days), retire-proposal comment posting with duplicate prevention, and Icebox dwell metrics (median/p95/trigger candidate detection)" --> 仕様が rubric 基準を満たす
- <!-- verify: section_contains "skills/audit/SKILL.md" "--retention" "stale-verify" --> `--retention` セクションに stale-verify ラベルへの言及がある
- <!-- verify: grep "Icebox\\|icebox" "skills/audit/SKILL.md" --> Icebox 滞留メトリクスが SKILL.md に記載されている
- <!-- verify: grep "stale-verify" "scripts/setup-labels.sh" --> 新規ラベル `stale-verify` が setup-labels.sh に追加されている
- <!-- verify: command "bats tests/audit-retention.bats" --> bats テストが green
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期

### Post-merge

- 次回 `/audit stats --retention` 実行で phase/verify 滞留メトリクスが出力されることを確認 <!-- verify-type: opportunistic -->

## Notes

- verify 件数が 9 件（light テンプレート上限 5 件超）: Issue body の verify command sync ルールを優先し、Issue body の 9 AC をすべて verbatim で採用
- `manual` は既存 SKILL.md（Work Origin 分類）にも出現するが、AC 3 は新規メトリクスとしての manual 待ち件数の追加を指す; rubric check が意味的な充足を保証
- `p95` は既存 stats subcommand（Section 7）に既出; `30-day` は新規 --retention セクションで追加することで AC 2 をカバー
- Icebox の Project Status 取得は `gh-graphql.sh get-projects-with-fields` を使用（既存 stats の Size/Priority 取得と同パターン）
- `compute-escalation-level.sh` は SKILL.md `--retention` セクションから直接呼び出す設計のため、bats テストが実装コードを直接検証する
- setup-labels.sh のコメント内 label 件数（13 labels）は現行 12 から 1 増加

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI green 確認済み（all checks passed）、PR #618 を squash merge し `worktree-code+issue-588` ブランチを削除した
- Post-merge AC は `verify-type: opportunistic`（次回 `/audit stats --retention` 実行時に確認）のみ残存
- code/review 2 件の Phase Handoff が共存していたため、merge フェーズで統合した（rotation の修正）

### Deferred Items
- Post-merge AC（`verify-type: opportunistic`）: `/audit stats --retention` 実行時に phase/verify・Icebox 滞留メトリクスが実際に出力されることを確認する
- Icebox の Project Status 取得（`gh-graphql.sh get-projects-with-fields` フロー）は実行時に LLM が解釈するため、実際の動作確認は opportunistic verify に委ねる

### Notes for Next Phase
- Pre-merge AC 9 件はすべて code/review フェーズで PASS 確認済み（/verify フェーズでの再検証不要）
- `stale-verify` ラベルが `scripts/setup-labels.sh` に追加済み（`/setup-labels` 実行で自動作成される）
- `bats tests/audit-retention.bats` 15 件は CI で green 確認済み

## Code Retrospective

### Deviations from Design

- `docs/structure.md` / `docs/ja/structure.md` の更新は Spec の Changed Files に含まれていなかったが、新規スクリプト追加に伴いファイルカウント（50→51）とKey Filesエントリ追加が必要となったため実施。テスト数（60→62）の乖離（既存2件が未反映）も合わせて修正した。

### Design Gaps/Ambiguities

- `docs/structure.md` のテストファイルカウントが既に「60 files」と実際（61 files）でずれており、本 PR 前から discrepancy があった。Spec には触れられていなかったが、追加1件で 62 files となるため両方修正した。
- translate-sync スクリプトは git のコミットタイムスタンプではなくファイルの内容差分を基準に同期状態を判定するため、未コミットの変更でも `IN_SYNC` と報告される（ja/ ファイルを同時に更新すれば問題なし）。

### Rework

- Issue ボディのチェックボックス更新で `sed` を使用したが、エスケープシーケンスの問題で一部の行が未置換になった。Python で再実行して全9件を確実にチェック済みとした。

## review retrospective

### Spec と実装の乖離パターン

- Spec では `setup-labels.sh` のコメント件数（12→13）の変更に言及していたが、`tests/setup-labels.bats` の更新については言及がなかった。結果として bats テストの更新漏れが発生し、CI が 5 件失敗した。Spec の Changed Files には「テストファイルの更新が必要な場合はそのファイルも列挙する」ルールを追加すると、このような漏れを事前に検知できる。

### 繰り返し発生した問題

- 特になし（今回の MUST 指摘は 1 件のみ）。

### AC 検証の難易度

- すべての verify コマンドが機械的に PASS/FAIL を判定でき、UNCERTAIN は 0 件だった。`bats tests/audit-retention.bats` の CI fallback では「Run bats tests」全体が FAILURE だったため、最初は UNCERTAIN と判断しそうになったが、CI ログを確認して `audit-retention.bats` 固有テストがすべて PASS していることを確認できた。CI 全体の失敗と個別ファイルの成否を区別するためのログ調査手順が有効だった。
