# Issue #249: code: Step 8 diff で除去したリテラルが tests/ に残存しないか検知

## Overview

`/code` Step 8（実装フェーズ）で `scripts/`・`modules/`・`skills/` 配下のファイルを変更した際、除去されたリテラル文字列（diff の `-` 行として現れる文字列定数）が `tests/` 配下の `.bats` ファイルに残存していないかを grep で検知し、残存があれば警告を出力する手順を Step 8 に追加する。

背景：`/code --patch` が `scripts/run-spec.sh` の `claude-opus-4-6` を `claude-opus-4-7` に置換した際、`tests/run-spec.bats` に stale アサーション `claude-opus-4-6` が残存して CI test が FAIL した（Issue #215）。Spec の AC verify hint は実装ファイル側のみを検証するためテスト側 stale を検知できず、patch route では CI required gate がないためローカルでテストが失敗しても commit が通るリスクがある。

## Changed Files

- `skills/code/SKILL.md`: Step 8 に stale test assertion 検知サブセクション（`#### Stale Test Assertion Check`）を追加

## Implementation Steps

1. `skills/code/SKILL.md` の `### Step 8: Implement` セクション内、`#### Follow-up Issue Creation` の直前に `#### Stale Test Assertion Check` サブセクションを追加する（→ 受け入れ基準 1・2・3）

   追加内容の要件：
   - 検知対象ファイル: `scripts/`・`modules/`・`skills/` 配下の変更ファイル
   - 除去されたリテラル（removed literal）の定義を明示すること: `git diff` の `-` 行として現れる文字列定数（コメント行・空白のみ変更は除外）
   - 検索先: `tests/` 配下の `.bats` ファイル
   - 偽陽性対策: コメント行（`#` 始まり）は grep 結果から除外
   - 残存があれば警告メッセージを出力し、stale アサーションの更新を促す
   - `tests/` への grep コマンド例を含めること（例: `grep -rn "REMOVED_LITERAL" tests/ | grep -v '^\s*#'`）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/code/SKILL.md" "Step 8" "tests/" --> Step 8 (Implement) に `tests/` 残存リテラルの grep 検知手順が追記されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 8" "removed literal" --> Step 8 の記述に「除去されたリテラル（removed literal）」の定義が明示されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 8" "grep" --> Step 8 の検知手順に `tests/` への grep コマンド例が含まれている

### Post-merge

- `scripts/` 配下のファイルを 1 行リテラル置換する Size=S patch route 実装時に、Step 8 で `tests/` 残存チェックの警告または grep 結果が出力されることを確認

## Notes

- SPEC_DEPTH=light（Size=S、patch route）
- 検知手順はマークダウン記述（SKILL.md）への追加のみ。bats テスト変更は不要（SKILL.md は直接 bats テストの対象外）
- doc 影響なし（README.md・docs/workflow.md・CLAUDE.md はいずれも code skill Step 8 を参照していないことを grep で確認済み）
