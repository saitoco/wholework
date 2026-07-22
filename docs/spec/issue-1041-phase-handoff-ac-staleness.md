# Issue #1041: phase-handoff: out-of-band AC 更新後の Deferred Items 古い情報露出を解消

## Consumed Comments
- saito (MEMBER, first-class): `/issue 1041 --non-interactive` による refinement retrospective — Title 正規化、Size を M→S に訂正 (委譲構造調査による判定)、AC1 の常時 PASS 欠陥修正・AC4 の verify 対象ファイル修正の記録。(https://github.com/saitoco/wholework/issues/1041#issuecomment-5040751656)

## Overview

Phase Handoff (`modules/phase-handoff.md`) の Read Procedure は、書き手フェーズが記録した `### Deferred Items` を無条件に読み手フェーズの実行コンテキストへ取り込む。書き手が handoff を書いた後、out-of-band (別セッション / 人間の追加介入 / 別 skill の並行実行) で Issue の AC checkbox 状態が変化しても handoff 自体は書き換えられないため (ローテーションは次フェーズの書き込み時のみ発生)、後段フェーズ (`/merge`, `/verify` 等) が古い Deferred Items をそのまま出力レポートに露出させてしまう。本 Issue は Read Procedure に AC checkbox 状態との突き合わせ処理 (Option A) を追加し、あわせて `## Notes` に「最終判断は Issue body」という semantics (Option C) を明文化する。

## Reproduction Steps

1. `/review` が Issue の一部 AC (preview tier 4 件) を Basic Auth (401) により UNCERTAIN と判定し、Phase Handoff の `### Deferred Items` に「preview tier 未検証」として記録する
2. `/review` 完了後、`/merge` 実行前に、out-of-band (ユーザーによる Basic Auth 認証情報共有 + 追試) で該当 4 件の AC が Issue body 上で `[x]` に更新される
3. `/merge` を実行すると、Phase Handoff の Read Procedure がそのまま古い `### Deferred Items` ("preview tier 4 件は未検証") をコンテキストへ取り込み、完了レポートに古い情報として出力する
4. 実際の Issue body ではすでに該当 AC が `[x]` 済みであり、レポートと Issue body の間に不整合が生じる (`saitoco/tofas` #305/#309 で実際に発生)

## Root Cause

`modules/phase-handoff.md` の Read Procedure Step 3 (Read and apply) は `### Deferred Items` を無条件に読み手フェーズのコンテキストへ取り込む設計であり、Issue の現在の AC checkbox 状態と突き合わせる処理を持たない。Phase Handoff は「最新 1 フェーズ分のみ保持」というローテーション方式 (module `## Purpose`) のため、次の書き手フェーズが実行されるまで内容は更新されない。この結果、handoff 記述時点と読み手フェーズ実行時点の間に out-of-band で AC 状態が変化しても、その変化を Read Procedure が検知する手段がなく、古い情報がそのまま後段フェーズの出力に反映される。

`skills/merge/SKILL.md` (L59) と `skills/verify/SKILL.md` (L160) はいずれも独自ロジックを持たず「`modules/phase-handoff.md` の Read Procedure セクションに従う」と完全委譲しているため (`skills/review/SKILL.md` L195、`skills/code/SKILL.md` L214 も同様)、Read Procedure 1 箇所への修正で `/code`・`/review`・`/merge`・`/verify` の4フェーズすべてに自動的に反映される。

## Changed Files

- `modules/phase-handoff.md`: `## Read Procedure` に AC cross-reference (Deferred Items staleness check) ステップを追加 (Option A)。`## Notes` に handoff semantics (書き手視点であり最終判断は Issue body) を追記 (Option C)
- `tests/phase-handoff.bats`: 新しい AC cross-reference ステップの文言を検証する shallow test を追加 (既存ファイルの "shallow tests confirm required sections and contract terms are present" という方針に合わせる)

## Implementation Steps

1. `modules/phase-handoff.md` の `## Read Procedure` セクションに、既存の Step 3 (Read and apply) の後に新しい Step 4「AC cross-reference (Deferred Items staleness check)」を追加する (→ acceptance criteria A1, A2, A4)。記述内容:
   - 冒頭で、本ステップは Read Procedure 内の共通処理であるため `code`/`review`/`merge`/`verify` の呼び出し元 4 フェーズすべてに自動的に適用される旨を明記する
   - `### Deferred Items` の各行から AC 参照 (番号、`ac=` リスト、または Issue チェックリスト行と一致する引用条件文) を抽出する手順を明記する。AC 参照が特定できない行はそのまま維持する (突き合わせをスキップする) と明記する
   - `gh issue view $ISSUE_NUMBER --json body` で現在の Issue body を取得する手順を明記する
   - 抽出した AC 参照から対応するチェックボックス行を特定する手順を明記する (1-based index、`gh-issue-edit.sh --checkbox` と同一の採番規約であることを明記する)
   - チェックボックスがすでに `[x]` の場合の処理を明記する: 当該行を「このフェーズの出力/レポートから除外する」か、あるいは監査目的で全文を残す場合は「`~~取り消し線~~` + 文字列 `(resolved after handoff)` を付記する」のいずれかを選択する、という判定を明記する (Verification AC1 の verify command が検出する具体文字列 `resolved after handoff` をこの付記文言に含める)
   - チェックボックスがまだ `[ ]` のまま、または AC 参照が特定できない場合はそのまま維持する、と明記する
2. (after 1) `modules/phase-handoff.md` の `## Notes` セクションに、Phase Handoff は書き手フェーズの視点および記録時点の AC 状態を反映したものであり、Issue body の AC checkbox が最終判断の source of truth である旨、両者が食い違う場合は Issue body を優先する旨を追記する (→ acceptance criteria A3)
3. (after 1, parallel with 2) `tests/phase-handoff.bats` に、新しい AC cross-reference ステップの文言 (`resolved after handoff` または本ステップの見出し文字列) が `modules/phase-handoff.md` に含まれることを確認する `@test` を追加する

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/phase-handoff.md" "## Read Procedure" "resolved after handoff" --> `modules/phase-handoff.md` の Read Procedure に「Deferred Items と Issue AC checkbox 状態の突き合わせ」節が追加されている (Option A)
- <!-- verify: rubric "modules/phase-handoff.md の Read Procedure に、Deferred Items に含まれる AC がすでに [x] になっている場合はレポート出力から除外するか (resolved after handoff) と補記する処理が明記されている" --> AC 突き合わせのアルゴリズムが明文化されている
- <!-- verify: rubric "modules/phase-handoff.md の semantics (Notes セクション等) に「handoff は書き手の視点、最終判断は Issue body」の趣旨が明記されている (Option C)" --> semantics が明文化されている
- <!-- verify: rubric "modules/phase-handoff.md の Read Procedure に追加された AC 突き合わせ手順が、code/review/merge/verify 共通の委譲構造 (各 skill は個別ロジックを持たず本セクションを参照するのみ) を通じて /merge と /verify の双方に自動的に適用される設計になっている" --> Read Procedure の変更が /merge・/verify 双方の挙動に反映される設計であることが確認できる

### Post-merge

- downstream repo (`saitoco/tofas` 等) で out-of-band AC 更新後に /merge や /verify を走らせ、レポート出力に「Issue で解決済みの AC が古いまま UNCERTAIN 表示される」現象が再発しないことを確認 <!-- verify-type: manual -->

## Notes

- Implementation Step 3 (`tests/phase-handoff.bats` への `@test` 追加) は Issue の Acceptance Criteria には明記されていないが、Step 10 の「Test file search check」に基づき、既存の shallow test ファイルの慣行 (必須セクション/contract 文言の存在確認) に合わせて追加する。Pre-merge verify command には含めない — AC1 の `section_contains` verify command がすでに同じ文字列 (`resolved after handoff`) を検証しており、別途 bats 用の verify command を追加すると Issue body の Pre-merge AC 数 (4件) との Count alignment が崩れるため
- `skills/merge/SKILL.md` / `skills/verify/SKILL.md` は編集不要と判断した。両ファイルとも Phase Handoff の Read 処理を独自実装せず `modules/phase-handoff.md` の Read Procedure セクションへ完全委譲していることを grep で確認済み (`skills/merge/SKILL.md:59`, `skills/verify/SKILL.md:160` はいずれも "Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-handoff.md` and follow the "Read Procedure" section." のみで独自ロジックを持たない)
- `docs/product.md` (Terms: Phase Handoff) および `docs/tech.md` (Cross-phase memory mechanisms) の既存記述は本修正後も引き続き正確であり、更新不要と判断した — Phase Handoff の定義自体 (「書き手が exiting 前に書き、次フェーズが entry 時に読む構造化サマリ」) は変わらず、読み手側の突き合わせロジックが Read Procedure 内部に追加されるのみのため
- Issue Retrospective (`/issue --non-interactive` 実行時) で、AC1 の verify command が実装前から常時 PASS してしまう欠陥 (対象文字列 `Deferred Items` がすでに main の見出しとして存在していたため) と、AC4 の verify 対象ファイルが `skills/merge/SKILL.md` から `modules/phase-handoff.md` の Read Procedure に修正された旨がすでに記録されている。本 Spec の `## Verification` は、この修正後の Issue body を正としてそのまま転記した (Verify command sync rule)
