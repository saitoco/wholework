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

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background が現状の運用観察と marker の advisory 性質を明確に分析しており、設計判断 (削除) に必要な情報が揃っていた。

#### spec
- XS patch route につき Spec phase skip。Issue body から要件読み取りで直接 code 実装に移行。

#### code
- 実装で `\1` group reference の Python regex 解釈問題が顕在化し、Lambda 置換に修正した。元コード `r'\1> ' + MARKER + '\n\n' + draft_content` は `> ` separator により問題が masking されていた。MARKER 削除が regex 解釈の死角を露呈させたパターン。
- Marker 削除に伴いテストの assertion 方向を反転 (marker 存在 → 非存在) する必要があり、Code Retrospective に記録済み。

#### review/merge
- XS patch route につき独立 review/merge phase なし。code phase 内で完結。

#### verify
- 全 3 pre-merge AC + 1 post-merge manual AC を全 PASS。post-merge AC は source code から default 挙動が確定するため Claude Execute で in-session 完結。

### Improvement Proposals

1. **regex group reference + 動的 replacement 文字列の gotcha 文書化**: `r'\1' + user_provided_string` パターンは user_provided_string が数字で始まる場合に `\1` + `1` = `\11` として解釈される Python 仕様。`re.sub` を使用する Spec / SKILL.md 例で「動的文字列を group reference の直後に置く場合は Lambda 置換に切替」のガイダンスを追加 (今回は code phase で発覚、early detection 余地)。

