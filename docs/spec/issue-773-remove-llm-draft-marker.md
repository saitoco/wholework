# Issue #773: audit/auto-session: narrative draft の [LLM draft] marker を撤去

## Overview

`scripts/get-auto-session-report.sh` の `--narrative-draft` 挿入処理から
`[LLM draft — human review required]` blockquote prefix を削除し、
draft 内容をそのまま挿入するよう変更する。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- None. Issue 本文の要件通り 3 ファイル変更で実装完了。

### Design Gaps/Ambiguities

- `replacement = r'\1' + draft_content` パターンで Python regex の group reference 問題が潜在していた。draft_content が数字で始まる場合 (`1.` リスト)、`\1` + `1...` = `\11` として解釈され re.PatternError が発生。Lambda 置換 (`lambda m: m.group(1) + draft_content`) で修正した。元々 `r'\1> ' + MARKER + '\n\n' + draft_content` のときは `> ` が separator になっていたため問題が顕在化していなかった。
- test 2 (`[LLM draft marker is attached`) は削除した marker の存在を assert していたため、marker 非存在を assert する形に更新が必要だった。

### Rework

- None.
