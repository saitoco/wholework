# Issue #1474: triage: 検出力ゼロ AC の監査が /issue 時点ではフィクスチャ未存在で判定不能

## Consumed Comments

- saito / MEMBER / first-class / `/issue` の Issue Retrospective (AC2 の grep パターンを実装後にのみ現れる語句へ変更した判断と、bats AC・observation AC を維持した判断の記録。内容は Issue 本文へ反映済みで、本 Spec の設計に追加の入力はない) / https://github.com/saitoco/wholework/issues/1474#issuecomment-5965624594

## Overview

`skills/triage/skill-dev-verify-audit.md` の Pattern 2 サブパターン「検出力ゼロの成果物を証明する AC (新規テスト追加を主張する AC)」(#1325 で追加) は、Detection approach (b)(c) が「追加されたフィクスチャ」の中身を見ることを要求する。しかしこの監査を呼び出す `/triage` Step 7 (一括実行を含む) と `/issue` Existing Issue Refinement Step 15 はいずれも実装前に走るため、フィクスチャはまだ存在しない。(b)(c) は常に評価不能となり、(d)「判定が難しい場合は検出せず素通しする」が構造的にほぼ常に適用される。

本 Issue は、判定内容と呼び出しフェーズの不整合を解消し、検出力の判定がフィクスチャを参照できるフェーズで行われる形にする。Issue 本文は A (判定フェーズの再配置) と B (フェーズ別の責務分割) の選択を `/spec` に委ねている。本 Spec は **B を主とし、A を既存の `rubric` AC 機構で実現する組み合わせ**を採用する (選択理由は `## Notes`)。

- 実装前 (`/triage` / `/issue`): (a) のみを評価し、(b)(c) は評価しない。(a) を満たす場合は欠陥指摘ではなく注意喚起 (advisory) を 1 件出す。advisory は次フェーズへの依頼 (欠陥を再現する入力を使う / 実装前の状態で FAIL することを確認する / 検出力を問う `rubric` AC を Pre-merge に追加する) を含む
- 実装後: (b)(c)(d) は、検出力を問う `rubric` AC を検証するフェーズが評価する。PR route は `/review` Step 8、patch route は `/review` が走らないため `/verify` Step 5。FAIL は `/review` では MUST 相当で修正を促し、`/verify` では修正サイクルへ戻す。PASS は AC 結果に「十分と判断した」旨が残る
- 変更対象は `skills/triage/skill-dev-verify-audit.md` の 1 ファイルのみ。`/review` と `/verify` の SKILL.md は変更しない

## Reproduction Steps

1. 「新規テスト追加を主張する AC」を含む Issue (例: #1463。`tests/ci-failure-classifier.bats` などを対象とする AC を 3 件持つ) に対して、`/issue` Existing Issue Refinement Step 15 (または `/triage` Step 7) の AC 監査を実行する
2. 監査は当該サブパターンの Detection approach に従う。(a) は AC 本文だけで判定でき、該当する。(b)(c) は追加されたフィクスチャの中身を要求するが、実装前のためフィクスチャは存在せず評価できない
3. (d) が適用され、検出力に関する指摘は出ない

実測 (Issue 本文と `docs/spec/issue-1325-pattern2-detection-power-ac.md` の Verify Retrospective からの転記。本 Spec 作成時の再測定は行っていない): 2026-09-13、session `90128-1788933783` の `/auto --batch --until "label:retro/verify status:Backlog"` で `/issue` が 7 回実行された (#1462 #1464 #1461 #1463 #1466 #1470 #1468) が、検出力に関する指摘は 0 件だった。

## Root Cause

サブパターンは単一フェーズのルールとして書かれているが、判定の入力 (追加されたフィクスチャ) は実装後にしか存在せず、呼び出し元 (`/triage` Step 7、`/issue` Step 15) は実装前に走る。そのため (b)(c) は構造的に評価不能になり、(d) の素通しが常に選ばれる。#1325 は検出力ゼロの AC を検出するルールを追加したが、そのルールが機能しうるフェーズまでは検討していなかった。副次的に、#1325 の Post-merge AC (「以降の `/issue` Step 15 AC 監査で、検出力の確認を促す指摘が出ることを確認する」) も同じ構造のため満たされにくく、`/verify 1325` は UNCERTAIN と判定した。

修正方針: ルールを実装前/実装後のフェーズ別に分割する。実装前は (a) の判定と注意喚起に責務を限定し、(b)(c) は評価しない (素通しにも数えない)。実装後の判定は、検出力を問う `rubric` AC に載せ、その AC を検証するフェーズ (フィクスチャが存在し、grader が diff を読める) に評価させる。

## Changed Files

- `skills/triage/skill-dev-verify-audit.md`: 2 箇所を編集する (prose のみ。`.sh` ではないため bash 互換の考慮は不要。散文は英語、日本語は fenced block と inline code のみ — 理由は `## Notes` の「言語規約」)
  - Pattern 2 の「検出力ゼロの成果物を証明する AC (新規テスト追加を主張する AC)」サブパターン: 見出し行・説明段落・例 (#1130) は変更せず、`Detection approach:` から `Fix options:` 末尾までのブロックを、実装前/実装後のフェーズ分割版に置換する (置換文面は Implementation Steps 1)
  - `### Comment Format Template` 節: 既存の fenced ブロックの直後に advisory entry format を追加する (文面は Implementation Steps 2)

## Implementation Steps

1. `skills/triage/skill-dev-verify-audit.md` の Pattern 2「検出力ゼロの成果物を証明する AC (新規テスト追加を主張する AC)」サブパターンについて、`Detection approach:` の行から `Fix options:` ブロック末尾の行 (`- assert を欠陥固有の挙動への具体的照合へ変更する`) までの連続ブロック (Spec 作成時点で L103-L111 の 9 行) を、下記の文面に置換する。見出し行・説明段落・例 (#1130) は変更しない (→ AC1, AC2)
   - 置換対象の特定: ブロックの先頭は、直後の箇条書きが `- (a) AC がテスト・回帰保護コードの新規追加のみを主張しているか確認する` である `Detection approach:` の行 (この箇条書きはファイル内に 1 件のみ)。`Detection approach:` は同ファイルに 10 件、`Fix options:` も他のサブパターンに多数あるため、見出し文字列だけで検索しないこと。行番号ではなくこのアンカーで位置を決める
   - 文面は逐語で使う。AC2 の grep が `注意喚起` / `` `/issue` 時点 `` / `後段フェーズ` に一致することに依存している。コードフェンス内の行頭 3 スペースは Spec の入れ子表記であり、ファイルに書く文面には含めない
   - 文面の散文は英語にする (`skills/` 配下の言語規約チェックの対象)。既存の日本語行を残す場合も、編集しない行だけを残す

   ````markdown
   Detection approach (split by phase):

   The deciding evidence — the added fixture — exists only after implementation, whereas every caller of this audit (`/triage` Step 7 and Bulk Execution, `/issue` Step 15) runs before it is written. Judged there, (b) and (c) can never be evaluated and (d) always applies, so the original single-phase rule produced no findings in practice (Issue #1474). The steps are therefore split by the phase in which they can be evaluated:

   - (a) Check whether the AC claims only the addition of new tests or regression-protection code. This needs only the AC text, so it is the only step that can be evaluated before implementation.
   - **Before implementation (every caller of this audit) — advisory only**: stop after (a). Do not attempt (b) or (c), because there is no fixture to inspect yet, and do not treat the absence of a finding as a judgment that the fixture is sufficient. When (a) holds, raise one advisory entry (labelled `注意喚起`) instead of a defect finding — see "Advisory entry" below. The judgment itself is left to a later phase.
   - **After implementation (later phase) — judgment**: (b), (c), and (d) apply once the added tests exist, and are evaluated by whichever phase verifies an AC that asks for this judgment (see "Post-implementation channel" below):
     - (b) Check whether the added fixture is actually sensitive to the target defect (where possible, confirm that the test FAILs against the pre-implementation state).
     - (c) If (b) cannot be confirmed, check whether the fixture uses only known values that always yield the safe-side result and never pass through the defect-specific branch.
     - (d) If the judgment is hard, do not flag it (avoid false positives — this audit is a non-destructive comment, and over-reporting burdens the author).

   Post-implementation channel: a `rubric` AC that asks for the fixture's detection power (the advisory proposes one). The phase that verifies the Pre-merge AC runs the grader on the Issue body and the git diff — `/review` Step 8 on the pr route (a FAIL is MUST-equivalent and blocks until the fixture is strengthened), `/verify` Step 5 on the patch route, where `/review` does not run (a FAIL returns the Issue to the fix cycle). A PASS records in the AC result that the fixture was judged sufficient. `/code`'s "New Verification-Test Pre-implementation FAIL Check" (`skills/code/SKILL.md`) covers string-matching asserts only; asserts on process output or exit codes, as in #1130, rely on the `rubric` AC.

   Advisory entry (pre-implementation phases only):
   - One entry per audit run, listing every AC that satisfies (a). It is an advisory, not a defect — the AC wording is not wrong. It tells the next phase that (1) the fixture's detection power cannot be judged yet and will be judged after implementation, (2) the new tests must include an input that reproduces the target defect (an unknown value, an error case, or a boundary value) and are expected to FAIL against the pre-implementation state, and (3) a `rubric` AC asking for that judgment should be added to the Pre-merge section. This follows `modules/verify-patterns.md` § "Pre-implementation anchor selection": require the implementation to conform instead of judging an artifact that does not exist yet.
   - It counts as a finding for "Processing Steps" 4 and 5: it is posted in the same single audit comment as any defect findings, and an Issue with only an advisory still receives the comment (format: "Comment Format Template").
   - Do not raise it when it is unclear whether the AC claims new tests (avoid false positives, as in (d)); when the Issue body already has an AC that asks for the fixture's detection power to be judged after implementation (for example a `rubric` AC naming the fixture's sensitivity or the pre-fix FAIL); or when an earlier comment on the Issue already carries the `注意喚起` heading line (`/triage` and `/issue` Step 15 can both run on the same Issue).
   - The next phase (`/spec`, or `/code` directly for Size XS) reads the comment as prompt-equivalent input (see "Repair handoff for self-generated AC" below). Because the Issue body is never auto-edited, adding the suggested `rubric` AC and stating the fixture requirement in the Implementation Steps are that phase's own work.

   Fix options:
   - Before implementation (AC side): add a `rubric` AC that asks for the fixture's detection power to be judged after implementation, naming the test file and the defect-reproducing input, and state the fixture requirement in the Spec's Implementation Steps.
   - After implementation (fixture side): include an input that reproduces the defect (an unknown value, an error case, or a boundary value) in the fixture.
   - After implementation (fixture side): change the assert to a concrete check of the defect-specific behavior.
   ````

2. (parallel with 1) 同じファイルの `### Comment Format Template` 節で、既存の fenced ブロック (`⚠️ Triage AC audit: verify command に問題があります` で始まるもの) の直後、`### Posting the Comment` の直前に、下記の段落と fenced ブロックを空行 1 行で区切って追加する。既存のブロックは変更しない (→ AC2)
   - fenced ブロック内の日本語は、監査コメントの出力テンプレートである (CLAUDE.md の "Skill output (terminal): Japanese" に対応し、言語規約チェックの除外対象)。文面は逐語で使う。AC2 の grep が `注意喚起` / `` `/issue` 時点 `` / `後段フェーズ` に一致することに依存している
   - 外側の 4 バッククォートと行頭 3 スペースは Spec の表記であり、ファイルには含めない。内側の 3 バッククォートのフェンスはファイルにも書く

   ````markdown
   **Advisory entry format** (the pre-implementation detection-power advisory of Pattern 2). When it is the only entry, use the block below as the whole comment; when defect findings also exist, append it to the same comment after the defect entries, separated by a blank line:

   ```
   ℹ️ Triage AC audit (注意喚起): 検出力の確認が必要な AC があります

   - AC: `<!-- verify: command "bats tests/example.bats" -->` (新規テスト追加を主張)
     - `/issue` 時点では対象のフィクスチャが存在しないため、検出力 (フィクスチャが欠陥に対して感度を持つか) は判定できません。判定は実装後の後段フェーズで行います
     - 次フェーズへの依頼: 新規テストには欠陥を再現する入力 (未知の値・異常系・境界値など) を含め、実装前の状態で FAIL することを確認してください
     - Suggested fix: Pre-merge に次の rubric AC を追加してください: `<!-- verify: rubric "tests/example.bats の新規テストが、欠陥を再現する入力を使用しており、修正前の実装に対して FAIL する形になっている (既知の安全側の値だけで PASS する形ではない)" -->`
   ```
   ````

3. (after 1, 2) 検証する (→ AC1-AC3 全体)
   - AC2 の対象パターンが実装後に 1 件以上ヒットすること: `grep -cE '(/issue|issue)[^。]{0,10}時点|実装後に(評価|判定)|注意喚起|後段フェーズ' skills/triage/skill-dev-verify-audit.md` (実装前は 0 件)
   - 言語規約チェックが違反なしで終わること。`skills/code/language-convention-check.md` の手順 (`git merge-base` で base を求め、`git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`) に従う。違反が出た場合は文面を直す (日本語を fenced ブロック・inline code の外へ出していないか確認する)
   - `bash scripts/check-forbidden-expressions.sh` が exit 0 で終わること (廃止語を文面に入れていないことの確認)
   - 保全の確認: 見出し行 `**検出力ゼロの成果物を証明する AC (新規テスト追加を主張する AC)**:` と、`#1130` の例の段落が 1 件ずつ残っていること。置換前の旧箇条書き `- (a) AC がテスト・回帰保護コードの新規追加のみを主張しているか確認する` が 0 件になっていること (`grep -c` で確認)
   - fenced ブロックの整合: 行頭が ` ``` ` (前に空白があってもよい) の行の数が、実装前の 10 から 2 増えて 12 (偶数) になっていること (`grep -c '^[[:space:]]*```' skills/triage/skill-dev-verify-audit.md`)
   - 変更範囲の確認: `git diff --stat` で、変更が `skills/triage/skill-dev-verify-audit.md` のみ (と、この Spec への追記) であること
   - `bats tests/` を実行する (AC3)。本 Spec 作成時点の環境には `bats` が無かった (`which bats` → not found)。`bats` が使えない場合は、上記の構造検査を grep で行い、全件の実行は CI の bats ジョブ (`Run bats tests`) に委ねたことを `## Code Retrospective` に記録する。patch route なので CI の結果は `gh run list` で確認する (`gh pr checks` は使えない)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/triage/skill-dev-verify-audit.md の『検出力ゼロの成果物を証明する AC』サブパターンについて、Detection approach (b)(c) がフィクスチャを参照可能なフェーズ (実装後) で評価される形になっているか、または /issue 時点の責務が注意喚起のみと明記されている" --> 検出力サブパターンの判定フェーズが、フィクスチャを参照可能なフェーズに整合している
- <!-- verify: grep "(/issue|issue)[^。]{0,10}時点|実装後に(評価|判定)|注意喚起|後段フェーズ" "skills/triage/skill-dev-verify-audit.md" --> 当該サブパターンに、`/issue` 時点の責務と判定フェーズに関する記述が含まれている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 新規テスト追加を主張する AC を含む Issue が実装フェーズを通過した際、検出力に関する判定が該当フェーズで行われることを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - 該当フェーズ (`/review` または `/verify`) の出力またはコメントに、追加されたフィクスチャの検出力に関する言及があること
    - 検出力が不十分と判断された場合は指摘として、十分と判断された場合はその旨が記録されていること

## Notes

### 設計判断 (非対話モード。light 深度のため Step 7 の曖昧点解決は対象外だが、判断は記録する)

- **B を主、A を既存の `rubric` AC 機構で実現する組み合わせを採用**: Issue 本文は A / B / 組み合わせの選択を `/spec` に委ねている
  - A (判定を `/review` または `/verify` へ移す) を単独で採ると、どのフェーズに何を足すかが問題になる。`/review` は PR route でのみ走るため、#1130 (patch route) のような Size XS/S の実例を被覆できない。`/verify` は全 route を被覆するが、`skills/verify/SKILL.md` は `skill-body-lines` / `skill-body-sha` マーカー (stale 検出。`scripts/check-skill-body-hash.sh`、`tests/verify.bats`) を持ち、編集のたびに再計算が要る。さらに `/review` と `/verify` の SKILL.md を足すと Changed Files が複数 skill にまたがり、Size の 2 軸評価 (`modules/size-workflow-table.md`) で S より上がりうる
  - B 単独は「後段フェーズに委ねる」と書くだけになる。後段フェーズの誰もそれを拾わなければ、実際には起きないことを前提にした記述になり、本 Issue が是正する欠陥と同型になる
  - そこで後段フェーズの評価主体を既存機構に求めた。`rubric` AC は `/review` Step 8 (safe / full の両モードで grader を起動し、Issue 本文と git diff を入力にする。`modules/verify-executor.md` の rubric 節) と `/verify` Step 5 で、実装後の diff を入力に評価される。検出力を問う `rubric` AC を Pre-merge に置けば、その AC を検証するフェーズ (PR route は `/review`、patch route は `/verify`) が実装後判定を担う。#1325 の AC1 (rubric) がこの形の実例
  - 実装前に判定せず、実装側に要件を課す扱いは、`modules/verify-patterns.md` § "Pre-implementation anchor selection" (L869) と同じ考え方 (対象が存在しない実装前は選ばず、実装側を合わせさせる)
- **不採用**: `/review` Step 8、`agents/review-spec.md`、`agents/review-light.md` への自動フック、`/verify` Step 5 / Step 12 への自動フック。**フォローアップの契機**: Post-merge の observation AC (`session=next`) が、新規テスト追加を主張する AC を含む Issue の実装フェーズ通過後も UNCERTAIN のままなら、`rubric` AC が追加されない経路が実在することになる。その場合は route 非依存の自動フックを `/verify` に足す別 Issue を起票する
- **advisory に「次フェーズへの依頼」を含める**: `/spec` などの次フェーズは監査コメントだけを読み (Domain file は読まない)、Comment Consumption Procedure で prompt 相当の入力として消費する。コメント自体に、欠陥再現入力の使用・実装前 FAIL の確認・`rubric` AC の追加を書いておけば、消費側は追加情報なしに動ける。Issue 本文は自動編集しない方針 (Domain file の § Non-Destructive Audit Behavior) は維持する
- **ノイズの抑制**: advisory は 1 監査実行につき 1 件 (該当 AC を列挙) にする。Issue 本文に検出力を問う AC が既にある場合、同じ advisory を含むコメントが既にある場合、(a) の判定が曖昧な場合は出さない。`/triage` Step 7 と `/issue` Step 15 は同じ Issue に両方走りうる (`/issue` Step 15 の Note が重複を許容している) ため、既存コメントの確認を入れた
- **(a) の判定範囲は変更しない**: Issue 本文の B の定義 (「新規テスト追加を主張する AC が存在する旨の注意喚起」) に従い、対象は「新規テスト追加を主張する AC」のままにする。Feature の新規テストは実装前 FAIL が自明なので advisory が過剰になる可能性はあるが、実測 (#1463) も Feature であり、範囲を絞るのは本 Issue の範囲外。過剰指摘が観測された場合は、対象を Bug / 既存挙動の修正に絞る別 Issue で扱う

### #1325 の Post-merge AC が満たされうる形になっているかの確認 (Issue 本文の Scope 最終項)

#1325 の Post-merge AC は「以降の `/issue` Step 15 AC 監査で、「新規テストが追加されている」形の AC に対して検出力の確認を促す指摘が出ることを確認する」(`verify-type: observation event=auto-run`)。変更前は (b)(c) が評価不能で (d) に落ちるため、原理的に出なかった。変更後は `/issue` Step 15 が (a) のみで advisory (検出力の確認を促す指摘) を出すため、この AC は満たされうる形になる。#1325 の本文は変更しない (他の Issue 本文の編集は本 Issue の範囲外)。

### 呼び出し側の確認 (「変更不要」の事前検証)

- `skills/issue/SKILL.md` Step 15: 「Read `skill-dev-verify-audit.md` ... follow the "Processing Steps" section」の形式 (`grep -n "skill-dev-verify-audit" skills/issue/SKILL.md` で L651 / L657 を確認)。Step 15 の Note の「Findings are posted as a comment only」と advisory は矛盾しない。変更不要
- `skills/triage/SKILL.md` Step 7 (L163-L167) と一括実行の substep 8: 同じ形式。変更不要
- `skills/review/SKILL.md` / `skills/verify/SKILL.md`: このファイルを参照していない (`grep -rn "skill-dev-verify-audit" skills/review skills/verify` → 0 件)。上記の設計判断により変更しない
- `tests/issue.bats` の L41-L45 は `skills/issue/SKILL.md` の文字列 (`AC Verify Command Integrity Audit` / `skill-dev-verify-audit.md` / `regardless of whether the .triaged. label is present or absent`) だけを検査する。影響なし

### 言語規約 (実装時の最重要制約)

`skills/` 配下は CI の `language-convention` ジョブ (`git diff -U100000 ... -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`) と、`/code` の `skills/code/language-convention-check.md` の対象である。フェンス外・inline code 外・引用符外の日本語散文を追加すると違反になる。既存行を編集すると行全体が diff の `+` 行になり、その行にもともとある日本語も違反として検出される。したがって:

- 新規の散文は英語で書く。日本語は inline code (`注意喚起` など) と fenced ブロック (監査コメントの出力テンプレート。CLAUDE.md の "Skill output (terminal): Japanese" に対応) に限る
- 見出し行・説明段落・例 (#1130) の既存の日本語行は編集しない (編集すると違反になる)。削除される既存の日本語行 (Detection approach (a)-(d) と Fix options の 2 項目) は `-` 行なので検出対象外
- 事前検証済み: Implementation Steps の文面を疑似 diff にして `scripts/check-language-convention.py` に通し、exit 0 を確認した。同じ形式の diff に日本語の散文を 1 行足した対照では exit 1 になることも確認した (検証が空振りでないことの確認)
- 参考: 同じファイルへの #1325 のコミット (`c88ae4e7`) の diff を同スクリプトに通すと、日本語散文を追加した行が違反として検出される。既存の日本語行は、このチェックの導入 (2026-08-09、#1291) 以降に追加された分も含め、解消されていない既存の負債である。本 Issue では解消せず、増やさない

### AC の確認結果

- AC2 (grep): 対象パターンは、実装前の `skills/triage/skill-dev-verify-audit.md` で 0 件 (測定: `grep -cE '(/issue|issue)[^。]{0,10}時点|実装後に(評価|判定)|注意喚起|後段フェーズ' skills/triage/skill-dev-verify-audit.md`、スコープは対象ファイルのみ。`rg -c -e` でも 0 件) であり、常時 PASS ではない。Implementation Steps の文面に対する同パターンのヒットは、`` `/issue` 時点 `` が 1 件、`後段フェーズ` が 1 件、`注意喚起` が 3 件 (疑似 diff の測定、スコープは追加行のみ)
- AC1 (rubric): 現行ファイルは Detection approach にフェーズの区別がなく、`/issue` 時点の責務の記述もない。そのため実装前の状態では FAIL する (常時 PASS ではない)。実装後は「(b)(c) は実装後に評価する」と「実装前は advisory のみ」の両方を明記するので、どちらの読み方でも PASS する
- AC3 (`command "bats tests/"`): 変更は prose の Domain file のみで、`tests/` はこのファイルを読まない (`grep -rln "skill-dev-verify-audit" tests/` → `tests/issue.bats` のみ。検査対象は `skills/issue/SKILL.md`)。`bats` が無い環境での扱いは Implementation Steps 3 を参照

### 計測値 (スコープ付き)

- 対象ファイルの fenced ブロック行数: 10 (行頭が ` ``` ` で、前に空白があってもよい行。スコープ: `skills/triage/skill-dev-verify-audit.md` のみ。コマンド: `grep -c '^[[:space:]]*```' skills/triage/skill-dev-verify-audit.md`)。advisory のテンプレートで 2 増え、実装後は 12 になる
- `Detection approach:` で始まる行: 10 件 (同ファイル。コマンド: `grep -c '^Detection approach' skills/triage/skill-dev-verify-audit.md`)。置換対象は L103 の 1 件
- 置換対象ブロック: L103-L111 の 9 行。見出し行 L97、説明段落 L99、例 L101 は変更しない (いずれも Spec 作成時点の行番号。位置の指定には行番号でなく Implementation Steps 1 のアンカーを使う)
- `tests/*.bats`: 135 ファイル (スコープ: `tests/` 直下のみ。コマンド: `ls tests/*.bats | wc -l`)

### 同期候補・除外・影響確認

- Steering Docs sync candidate check: Changed Files に SKILL.md・`modules/`・`scripts/` を含まないため対象外 (ゲート非該当)
- Listing-side sub-check: 不発 (サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構造の変更なし)
- Outbound pointer sync candidate: 変更対象のファイルが指す `modules/verify-executor.md` / `modules/size-workflow-table.md` / `modules/l0-surfaces.md` は、いずれも今回の変更の影響を受けない
- `docs/environment-adaptation.md` L160 は当該ファイルを「AC verify command integrity audit」と説明するだけで、サブパターンの内容に触れない (変更不要、確認済み)
- `docs/ja/` の同期: `docs/translation-workflow.md` の対象は top-level の `docs/*.md` のみで、`skills/` 配下の Domain file は対象外
- allowed-tools の影響: 新規のスクリプト参照を導入しない (変更するのは prose のみ)。`skills/triage/SKILL.md` と `skills/issue/SKILL.md` の `allowed-tools` は変更不要
- Tag/enum の意味拡張、Rename、Feature 削除、Symbol 影響: いずれも該当しない (新しい語の導入で、既存の識別子の意味拡張・削除・改名はない)

### その他のチェック結果

- Issue 本文と既存実装の突き合わせ: Issue 本文が引用する Detection approach (a)-(d) は、現行ファイルの L104-L107 と一致する。`/issue` Step 15 と `/triage` Step 7 が実装前に走ることも、両 SKILL.md の記述で確認した。矛盾は検出されなかった
- fail-safe critical: 該当なし (prose の Domain file であり、ブロッキングしないコメント専用の監査)
- audit / investigation 型: no (目的は分類表の作成ではなく、ルールの再構成)。ただし文面に書く識別子は、予防として `/spec` 時点で grep / Read により存在を確認した。`skills/review/SKILL.md` L225 `## Step 8: Static Acceptance Criteria Verification`、`skills/verify/SKILL.md` L205 `### Step 5: Verify Each Condition (Pre-merge Only)`、`skills/code/SKILL.md` L292 `#### New Verification-Test Pre-implementation FAIL Check`、`modules/verify-patterns.md` L869 `**Pre-implementation anchor selection ...`、`skills/triage/SKILL.md` L163 `### Step 7: AC Verify Command Integrity Audit`
- 新規テストケースの要否: 該当なし。変更は LLM が読む prose の Domain file のみで、対応する bats テストは存在せず、新設もしない (先例: #1294 / #1315 / #1325 の Spec Notes)。挙動の検証は Post-merge の observation AC が担う
- 廃止語: 文面に `docs/product.md` § Terms の廃止語を含めない (`scripts/check-forbidden-expressions.sh` が `skills/` と `docs/` を走査する)。疑似 diff で 0 件を確認済み。この Spec も同スクリプトの走査対象なので、廃止語は引用せず「廃止語」と記述している
- Patch route: Size S、`always-pr` 未設定のため patch route。Verification に `github_check "gh pr checks"` は含まれない
- AC と Out of scope の整合: Pre-merge / Post-merge のどの条件も、Issue の Out of scope (「既存テストファイルの実行に起因する常時 PASS」サブパターン、監査の非破壊方針の変更) を要求しない。本 Spec も両者を変更しない (非破壊方針は advisory でも維持する)
- Uncertainty: なし。外部仕様への依存もなし
- 軽微な観察 (範囲外、未修正): `skills/triage/skill-dev-verify-audit.md` の冒頭 (`Used in:`) と Pattern 4 は「Bulk Execution Step 3 substep 7」と書くが、現行の `skills/triage/SKILL.md` では AC verify command audit は substep 8 に当たる (substep 7 は duplicate comment)。本 Issue の範囲外のため修正しない
- SPEC_DEPTH=light (Size S) のため、Step 7 (Ambiguity Resolution) と Step 8 (Uncertainty Identification) はスキップした。UI Design Phase にも該当しない

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1・2 の文面を逐語で適用した (置換対象は `Detection approach:` + 旧 (a) 箇条書きのアンカーで特定し、行番号は使っていない)

### Design Gaps/Ambiguities
- `bats` がこの環境に無い (`which bats` → not found) ため、AC3 (`command "bats tests/"`) は実行できなかった。Spec Implementation Steps 3 の方針どおり、grep による構造検査で代替し、全件実行は CI の `Run bats tests` ジョブに委ねる。変更対象は prose の Domain file のみで、`tests/` はこのファイルのパスを参照しない (`grep -rl "skills/triage/skill-dev-verify-audit.md" tests/` → 0 件)
- Step 10 の checkbox 更新は行っていない: AC3 が UNCERTAIN (bats 不在) のため「all PASS」の条件を満たさない。AC1 (rubric) は手動確認で適合、AC2 (grep) は実装後 4 件ヒットで PASS。`/verify` が再判定する

### Rework
- なし。構造検査の結果: AC2 パターンのヒット 4 件 (実装前 0 件)、旧 (a) 箇条書き 0 件、fenced ブロック 12 行 (偶数、実装前 10 から +2)、見出し行と #1130 の例は各 1 件で保全、言語規約チェック・禁止表現チェック・`validate-skill-syntax.py`・`check-allowed-tools.sh` はいずれも違反なし
- worktree 隔離ガードが複合コマンド (`git ... ; ...` や `bash script`) を拒否したため、検証コマンドは単純なコマンドに分割して実行した

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の置換文面を逐語で適用し、見出し行・説明段落・#1130 の例には触れなかった (日本語の既存行を編集すると言語規約チェックで違反になるため)
- 変更は `skills/triage/skill-dev-verify-audit.md` の 1 ファイルのみ。`/review` と `/verify` の SKILL.md は変更していない

### Deferred Items
- AC3 (`bats tests/` 全件) はローカルに `bats` が無く未実行。CI の `Run bats tests` ジョブの結果を `gh run list` で確認する (patch route のため `gh pr checks` は使えない)
- Post-merge の observation AC (`event=auto-run session=next`) は、新規テスト追加を主張する AC を含む次回の Issue が実装フェーズを通過するまで確認できない

### Notes for Next Phase
- `/verify` は AC1 (rubric) と AC2 (grep) を再判定する。AC3 は CI の結果で解決する
- `/verify` 時点で CI が未完了・失敗の場合、`bats` ジョブの失敗は prose 変更では起こりにくいため、無関係な既存失敗の可能性を先に疑う
