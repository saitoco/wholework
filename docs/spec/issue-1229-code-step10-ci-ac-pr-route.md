# Issue #1229: code: Step 10 の CI 検証 AC 除外を pr route にも明文化

## Overview

`skills/code/SKILL.md` Step 10 (Verify Command Consistency) は Step 11 (commit / PR 作成) より前に実行されるため、実装後の状態を参照する CI 検証 AC は Step 10 の時点では判定できない。#1212 が patch route 側 (`github_check "gh run list"` 形式) の除外を「Patch route branch-scoped CI AC exclusion」注記として明文化済みだが、pr route 側 (`github_check "gh pr checks"` 形式 — PR が Step 11 まで存在しないため UNCERTAIN になる) は都度の判断に委ねられており明文化されていない (#1213 の Code Retrospective で実測)。

本 Issue は既存の「Patch route branch-scoped CI AC exclusion」注記を route 非依存の形に一般化し、patch route / pr route 両方の除外条件と、共通する除外理由 (Step 10 が Step 11 より前に実行され、検証対象の状態がまだ存在しない) を 1 箇所に統合する (Issue 本文の対応方針案のうち方針 1 を採用)。

## Changed Files

- `skills/code/SKILL.md`: Step 10 の「**Patch route branch-scoped CI AC exclusion**」見出し・段落 (Step 10 内、「Patch route verify command check」の直後) を route 非依存の「**CI verification AC exclusion (route-agnostic)**」に書き換え、patch route (`github_check "gh run list"`) / pr route (`github_check "gh pr checks"`) 両形式の除外条件を列挙する。同じファイル内でこの見出し名を引用している Step 8 (line 263 付近) と Step 10 自身の checkbox-flip ループ除外文 (line 473 付近) の 2 箇所の相互参照も新見出し名に合わせて更新する (計 3 箇所、grep で網羅確認済み)

## Implementation Steps

1. `skills/code/SKILL.md` Step 10 の「Patch route branch-scoped CI AC exclusion」注記を「CI verification AC exclusion (route-agnostic)」に書き換える: 共通理由 (Step 10 は Step 11 が実装コミット (patch route) または PR (pr route) を作成するより前に実行される) を明記した上で、patch route の `github_check "gh run list"` 形式 (既存の理由 — 無関係な `main` 上の先行コミットを参照してしまう — は変更しない) と pr route の `github_check "gh pr checks" "<job>"` 形式 (新規 — PR が Step 11 まで存在しないため評価不能 = UNCERTAIN) を列挙し、両形式とも Step 10 の verify-executor full-mode パス対象から除外し checkbox を `- [ ]` のまま残す旨を明記する。あわせて、同じファイル内でこの見出し名を "Patch route branch-scoped CI AC exclusion" として引用している Step 8 (spec-approval-needed 段落末尾、line 263 付近) と Step 10 自身 (checkbox-flip ループの除外条件文、line 473 付近) の計 2 箇所の相互参照文言を新見出し名に更新する (→ acceptance criteria AC1, AC2)
2. 本 Issue 自身の PR で CI (bats テスト) が pass することを確認する (→ acceptance criteria AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md の Step 10 において、pr route の github_check \"gh pr checks\" 形式の CI 検証 AC が Step 10 の verify-executor 評価対象から除外されること、およびその条件を checkbox でチェックしないことが明記されている" --> pr route の CI 検証 AC の扱いが Step 10 に明記されている
- <!-- verify: rubric "skills/code/SKILL.md の Step 10 において、pr route の CI 検証 AC 除外注記が、除外理由として Step 10 が Step 11 (commit / PR 作成) より前に実行されるという実行順序に言及している" --> 除外理由として Step 10 と Step 11 の実行順序が明記されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する

### Post-merge

- 次に pr route で `gh pr checks` 形式の CI 検証 AC を持つ Issue の `/code` 実行時、Step 10 が当該 AC を評価対象外として扱い checkbox を未チェックのまま残すことを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

**Consumed Comments からの反映 (AC2 の rubric 修正):** `/spec` 実行前の Comment Consumption Procedure で、cutoff (`phase/issue` ラベル最終付与時刻) 以降に 2 件の first-class (MEMBER, saito) コメントを検出した。(1) 「## Issue Retrospective」— 直前の Triage AC audit が指摘した `section_contains "gh pr checks"` 常時 PASS 欠陥 (本 Issue の pr route 除外注記追加とは無関係に、main 上の既存「Patch route verify command check」段落の `gh pr checks` auto-fix 記述だけで満たされてしまう) を修正し、当該 AC を削除済み (Issue body に反映済み)。(2) 新規の Triage AC audit — 残る AC2 (除外理由の実行順序に関する rubric) が pr route に限定されておらず、既存の patch route 側注記の実行順序言及だけで常時 PASS しうると指摘。提示された修復案 (rubric text を「pr route の CI 検証 AC 除外注記が…」に限定) をそのまま採用し、`/spec` 実行冒頭で `gh-issue-edit.sh` により Issue body の AC2 を修正した。詳細は `## Consumed Comments` 参照。

**Issue #1095 との並行編集リスク (未解決、フォローアップ不要 — 次の `/code` 実行時に自然解消):** `skills/code/SKILL.md` Step 10 の同じ「Patch route branch-scoped CI AC exclusion」段落を対象とする別の Spec が既に存在する (`docs/spec/issue-1095-operate-route-verify-check.md`、Issue #1095、2026-08-16 時点で `phase/ready` — 未実装)。#1095 は同段落に `operate` route の記述を追加する計画で、見出し自体のリネームは必須としていない。本 Issue #1229 と #1095 のどちらの `/code` が先に実行されるかは未定のため、Implementation Step 1 は「現在の見出し名」に依存する記述ではなく変換の意図で記述した。後から `/code` を実行する側は、その時点の実際のファイル内容を読み、先に着地した変更 (route 一覧またはリネーム後の見出し) に自分の担当 route (pr または operate) を追加する形で統合する。両者とも「Step 10 は Step 11 より前に実行される」という同一の根本原因を共有するため、統合先は 1 箇所のままで構造的な矛盾は生じない。

**docs/spec/ 配下の過去 Spec は更新対象に含めない:** 同じ見出し文字列は `docs/spec/issue-1213-*.md` と `docs/spec/issue-1265-*.md` にも引用として出現するが、両 Issue とも CLOSED (完了済み) であり、Spec は使い捨てのため (`docs/tech.md` "Spec-first (disposable)")、過去の完了済み Spec は更新しない。

**新規テストケース要件: 該当なし。** 本 Issue の変更は `skills/code/SKILL.md` の Step 10 の説明文 (prose) の書き換えのみで、`.sh` スクリプトや `modules/*.md` の分岐ロジックを追加・変更しない。既存の bats テストにもこの見出し文字列への依存は見つからなかった (`tests/`, `scripts/`, `modules/` を grep して確認済み)。したがって新規ブランチロジック向けの新規テストケースは不要と判断した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: ## Issue Retrospective — 直前の Triage AC audit で指摘された `section_contains "gh pr checks"` 常時 PASS 欠陥を修正し、該当 AC を Issue body から削除済みであることを記録 / URL: https://github.com/saitoco/wholework/issues/1229#issuecomment-5305140739
- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: Triage AC audit — AC2 の rubric 文言が pr route に限定されておらず常時 PASS しうると指摘し、pr route に限定する修復案を提示。`/spec` 実行時にそのまま採用し Issue body に反映 (対応: Notes 参照) / URL: https://github.com/saitoco/wholework/issues/1229#issuecomment-5305152550
