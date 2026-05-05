# Issue #406: auto: show CI fail and recovery info in completion summary

## Overview

`/auto` の Completion Report (Step 5) に、phase 内で発生した CI FAIL と auto-recovery の概要を
表示する。現状、CI FAIL → 自動回復が発生しても result table の Notes カラムに情報が現れず、
ユーザーはサマリだけで「途中で何が起きたか」を把握できない。

実装方針は Option A（Notes カラム enrichment）: 軽量・既存構造維持を優先する。

## Changed Files

- `skills/auto/SKILL.md`: Step 5: Completion Report — result table 構築ロジックに CI FAIL/recovery スキャン手順と Notes カラム追記ロジックを追加（→ AC1, AC2）

## Implementation Steps

1. `skills/auto/SKILL.md` の Step 5 "result table" 構築説明に、以下のサブステップを追加する（→ AC1, AC2）:

   **result table 構築前に CI FAIL/recovery スキャンを実施:**
   - 各 phase の run-*.sh 出力（Step 4 の Bash 呼び出しで LLM コンテキストに保持された出力）を以下のパターンでスキャンする:
     - CI check failure: `gh pr checks` 形式の出力に `fail` / `FAILED` が含まれる
     - review 自動修正: `MUST issue` 解決フレーズ（例: `1 MUST issue resolved`）または `Fix:` で始まる追加コミット
   - 検出した場合、該当 phase の Notes カラムに concise な 1 行サマリを追加する（例: `1 CI fail → fixed in abc1234`、`1 MUST issue auto-resolved`）
   - 未検出の場合、Notes は空（または `—`）

   **挿入箇所**: Step 5 の "Followed by a result table (one row per phase with status)." の直前に追記する

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 5: Completion Report" "CI" --> Step 5 に CI FAIL/recovery 情報の表示ロジック説明が追加されている
- <!-- verify: rubric "skills/auto/SKILL.md Step 5 が phase 内で発生した CI FAIL と auto-recovery 情報をサマリに反映する手順を記述しており、(1) 抽出ソース（run-*.sh 出力 / PR commit 履歴 / review retrospective のいずれか）、(2) 表示位置（Notes カラム or 独立セクション）、(3) 1-3 行程度の concise 表示形式 を含む" --> Step 5 の追加ロジックが抽出ソース・表示位置・表示形式の 3 要素を網羅している

### Post-merge

- 次回 `/auto` 実行時に CI FAIL → recovery が発生した場合、完了サマリの Notes または独立セクションでその概要が確認できる

## Notes

- 抽出ソースは「Step 4 の run-*.sh Bash 呼び出しで得た LLM コンテキスト」であり、出力ファイルの保存は不要
- XL ルートの Auto Retrospective（Step 4a）は既に Notes カラムに詳細情報を含む。本変更は M/L/patch ルートの通常成功時にも CI 情報を提供することが目的
