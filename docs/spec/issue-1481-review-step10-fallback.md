# Issue #1481: review: fork 実行時に Step 10 のサブエージェントの結果を待ったままターンを終えないように

## Overview

fork 実行 (`Skill launched as forked execution`) の `/review` が、Step 10 で起動した `review-light` の結果を待つと宣言したままターンを終え、レビューが完了しない事象が 2 回 (saito/ops PR #141、PR #175) 起きた。Step 10 冒頭には #1443 で入った「Foreground dispatch reminder」がすでにあり、同期で結果を受け取るよう求めている。それでも再発しているので、禁止の文章を足すだけでは効かない。

この Issue では次の 3 点を行う。

- `## Non-Interactive Mode Behavior` の前景実行の規定を、orchestrator による Step 10 のサブエージェント起動にも広げる
- Step 10 に、結果が同じターンの中で得られなかったときに orchestrator 自身が該当する観点のレビューを実行するフォールバックを追加する。フォールバックを使ったことは Review の本文に記録する
- `modules/execution-context.md` の Precedents にある曖昧な参照「#1142 (a fork-executed `/review`)」を明確にする

## Reproduction Steps

1. 対話セッションから `/wholework:review <PR>` (Size M、light) を実行する。fork 実行になる (`Running in the background as @wholework-review`)
2. fork は Step 10.0 で `review-light-<PR>` を起動する。起動は background の teammate として返る
3. fork は「review-light エージェントの結果を待っています。」を最終出力にして completed になる
4. review-light の結果は fork にも親セッションにも届かない。Review Response Summary は投稿されず、続く `/merge` が受入条件のゲートで止まる

## Root Cause

- **結果を受け取れなかったときの手順が無い**: Step 10.0 の手順 4〜5 は「`review-light` を起動し、その出力から抽出する」としか書いていない。10.2 の手順 4 は「失敗したグループは "review unavailable" と記録する」だけで、観点を誰も見ないまま進む。起動が background で返ったときに orchestrator が取れる行動は「待つ」しか書かれていない
- **起動の形は SKILL.md の文章では制御できない可能性が高い**: harness の Agent ツールは、サブエージェントを background で動かし、完了を通知で知らせる形を取りうる。fork 実行の Skill は再起動保証が無いので、ターンを終えた後の通知は届かない (`modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting")。「同期で待て」(#1443) と書いても起動の形自体は変えられないので、確実に効く手段は「結果が手元に無ければ自分でやる」というフォールバックになる
- **前景実行の規定 (L39) の対象範囲が狭い**: test/build コマンドだけが対象で、orchestrator 自身の dispatch は Step 10 冒頭の reminder (L462) にしか書かれていない。非対話モードの要点をまとめた一覧から dispatch が抜けている

対処の妥当性: 観測 2 では、再開させた fork が 4 観点を自分でレビューし、CONSIDER 2 件の検出と修正まで完了した。フォールバックの手順が実際に機能することは確認できている。

## Changed Files

- `skills/review/SKILL.md`:
  - `## Non-Interactive Mode Behavior` の Foreground bullet (L39): 対象を orchestrator による Step 10 のサブエージェント起動 (`review-light` / `review-spec` / `review-bug`) にも広げる。結果が手元に無いまま「待つ」と述べてターンを終えることを禁じ、その場合は Step 10 のフォールバックに移ると明記する
  - `## Step 10` 冒頭の "Foreground dispatch reminder" (L462): L39 との重複を整理する。新設するフォールバック小節への参照を加える
  - `## Step 10` に小節 "Sub-agent Result Fallback" を新設する (Base Branch Conflict Pre-check の直前): 発火条件、orchestrator 自身による代行、Review 本文への記録を定める
  - 10.0 手順 5 と 10.2 手順 4 ("Record failed groups as \"review unavailable\"" を置き換える): 結果が得られなかったサブエージェントについてフォールバックを適用する一文を加える
- `skills/review/workflow-guidance.md`: `## Processing Steps (Workflow Path)` の手順 5 に、Workflow の結果が同じターンの中で得られなかったときは同じフォールバックに移るという一文を加える
- `modules/execution-context.md`:
  - Precedents の「#1142 (a fork-executed `/review`)」を「PR #1143 (a fork-executed `/review`, recorded in #1142's verify retrospective)」に直す。#1481 (Step 10 の dispatch 待ちの再発、フォールバック導入) も追記する
  - `## Callers` の `skills/review/SKILL.md` の記述に Step 10 のフォールバック小節を追記する
- [Steering Docs sync candidate] keyword "execution-context.md" skipped: matched 24 files (no discriminating power)
- [Steering Docs sync candidate] keyword "workflow-guidance.md" skipped: matched 36 files (no discriminating power)
- [Steering Docs sync candidate] keyword "Re-invocation Guarantee": `scripts/guard-prefix.sh` (run-*.sh 経由の headless だけに注入される文言)。対話セッションからの fork 実行には届かないので今回の対象外。headless でも同じフォールバックを促す一文を足すかどうかは `/code` が判断する。その他のヒットは過去 Spec と `docs/structure.md` の一般的な説明で、変更不要

## Implementation Steps

1. `skills/review/SKILL.md` の Step 10 に "### Sub-agent Result Fallback" 小節を新設する。位置は "### Base Branch Conflict Pre-check" の直前。内容は次のとおり (→ AC2, AC3)
   - **発火条件**: Step 10 で起動したサブエージェント (10.0 の `review-light`、10.2 の `review-spec` / `review-bug`、Workflow 経路のパイプライン) の結果が、同じターンの中で手元に無い場合。具体的には、出力が空・エラー・background の teammate / task として返った (戻り値に結果本文が無い) 場合。完了通知を待ってターンを終えることは、どの実行面でも選ばない
   - **代行**: 結果が得られなかったサブエージェントごとに、orchestrator 自身がその観点のレビューを行う。対応は `review-light` → 4 観点 (仕様との乖離・エッジケース・セキュリティ・ドキュメントの整合。`SKIP_REVIEW_BUG=true` のときは観点 1・4 のみ)、`review-spec` → 仕様とドキュメント、`review-bug` → バグとセキュリティ。各 agent ファイル (`agents/review-*.md`) の観点と出力形式 (`**[aspect] path:line**` / `- path:` / `- line:` / severity) に従い、`.tmp/pr-diff-$NUMBER.txt` と Spec を読んで行う。出力はサブエージェントの結果と同じ抽出手順に流す
   - **記録**: Review 本文の General Comments の前に、どのサブエージェントの結果が得られず orchestrator が代わりに実行したかを 1 行ずつ記す (例: `- Sub-agent fallback: review-light result not obtained (backgrounded); orchestrator performed aspects 1-4`)
   - **後始末**: 起動済みのサブエージェントの停止は #1478 の範囲とする。fork 側からの `TaskStop` は拒否されうる (観測 2) ことを一文添え、停止の成否はフォールバックの進行を妨げないと明記する
2. (after 1) 10.0 手順 5 の冒頭と、10.2 手順 4 の "Record failed groups as \"review unavailable\"" を置き換えて、結果が得られなかったサブエージェントに Sub-agent Result Fallback を適用する一文を入れる。10.3 (検証サブエージェント) で結果が得られなかった issue は、検証なしで通すという既存の扱い (上限超過分と同じ) に合わせる旨も一文で書く (→ AC2)
3. (after 1) `## Non-Interactive Mode Behavior` の Foreground bullet (L39) を拡張する。対象に orchestrator 自身による Step 10 のサブエージェント起動 (`review-light` / `review-spec` / `review-bug`、Workflow 経路) を加える。「結果が手元に無いまま待つと述べてターンを終えない。手元に無ければ Step 10 の Sub-agent Result Fallback に移る」と書く。あわせて Step 10 冒頭の reminder (L462) を、L39 と新小節を参照する短い形に整理する (→ AC1)
4. (parallel with 1-3) `skills/review/workflow-guidance.md` の Processing Steps 手順 5 に、Workflow の結果が同じターンの中で得られなかったときは `SKILL.md` Step 10 の Sub-agent Result Fallback に移るという一文を加える (→ AC2)
5. (parallel with 1-4) `modules/execution-context.md` の Precedents の #1142 の記述を直し、#1481 を追記する。`## Callers` の `skills/review/SKILL.md` の記述に Step 10 の Sub-agent Result Fallback を加える (→ AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md の ## Non-Interactive Mode Behavior にある前景実行の規定が、test/build コマンドだけでなく、orchestrator による Step 10 のサブエージェント (review-light / review-spec / review-bug) の起動も対象に含み、サブエージェントの結果が手元に無いまま「待つ」と述べてターンを終えることを禁じている" --> <!-- verify: section_contains "skills/review/SKILL.md" "Non-Interactive Mode Behavior" "review-light" --> `skills/review/SKILL.md` の前景実行の規定が、Step 10 のサブエージェントの起動を対象に含んでいる
- <!-- verify: rubric "skills/review/SKILL.md の Step 10 は、light 経路 (10.0) と full 経路 (10.2) の両方について、サブエージェントの結果が同じターンの中で得られなかった場合 (空・エラー・background 化して戻り値が無い) を失敗として扱い、orchestrator 自身が該当する観点のレビューを実行してから、結果の集約と Review の投稿に進むフォールバック手順を定めている" --> Step 10 (light / full の両経路) に、サブエージェントの結果が得られなかったときに自分で代わりに実行するフォールバック手順がある
- <!-- verify: rubric "skills/review/SKILL.md の Step 10 のフォールバック手順は、フォールバックを使ったこと (どのサブエージェントの結果が得られず、orchestrator が代わりに実行したか) を Review の本文に記録するよう定めている" --> フォールバックを使ったことが Review の本文に記録される
- <!-- verify: file_not_contains "modules/execution-context.md" "#1142 (a fork-executed" --> `modules/execution-context.md` の Precedents にある誤った参照「#1142 (a fork-executed `/review`)」が、正しい Issue 番号に直されている (特定できない場合は除かれている)

### Post-merge

- 変更が main に入った後の会話セッションで、fork 実行 (対話セッションからの `/wholework:review`) の light review が完了したとき、その実行の中で Review Response Summary が PR に投稿されており、Step 10 の結果がサブエージェントの戻り値とフォールバックのどちらで得られたかが Review の本文から判別できる (observation, event=pr-review-light, session=next)

## Notes

- **Issue 本文との相違 (#1142)**: Issue の付記は「#1142 は別件で、番号が誤っている可能性がある」としていた。#1123 の本文とコメントを確認すると、fork 実行の `/review` が「エージェントの完了通知を待機します」で止まった事例は、PR #1143 に対する `/review 1143` で起きた。記録は #1142 の verify retrospective (`docs/spec/issue-1142-spawn-detach-experiment.md`) にある。参照先の Issue としては誤りではないが、事象 (fork 実行の `/review`) の主体は PR #1143 なので、Implementation Step 5 で両方を明記する形に直す。AC4 (`file_not_contains "#1142 (a fork-executed"`) はこの修正で満たされる
- **サブエージェントの `tools:` に SendMessage / Write を足さない判断**: Issue で /spec に委ねられた論点。足さない。理由は 2 つある。(1) SendMessage の宛先は `main` (親セッション) になり、fork 側の orchestrator には届かない。fork はターンを終えると受け取る手段が無い。(2) Write でファイルに書き出しても、orchestrator がファイルの出現を待つ手段は sleep / ポーリングになり、それ自体が通知待ちと同じ形になる。結果が手元に無ければ代行するフォールバックだけで、待ったまま終わる経路は閉じられる
- **Workflow 経路もフォールバックの対象にした**: Workflow ツールは background で動き、完了を通知で知らせる。このリポジトリは `capabilities.workflow: true` なので、`/review --full` では同じ形の取りこぼしが起こりうる。Implementation Step 4 で同じフォールバックに合流させる
- **機械的な検出 (対応案 3) は Out of Scope**: Issue のとおり。再発は Post-merge の observation 条件で確認する
- **新規テスト**: 文書 (SKILL.md / module) の変更だけで、スクリプトに分岐を追加しないので、新規の bats テストは不要
- **Consumed Comments**: 下の `## Consumed Comments` を参照

## Consumed Comments

- saito / MEMBER / first-class / `/issue` の Issue Retrospective (判断の根拠、Q&A で決めた方針、受入条件の変更、Triage の結果) / https://github.com/saitoco/wholework/issues/1481#issuecomment-5956690140
- `/code` 実行時 (phase/ready 以降): 新規コメントなし

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1481#issuecomment-5957262516
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1481#issuecomment-5964181057
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1481#issuecomment-5964223115
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1481#issuecomment-5977220640
## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1〜5 を Spec どおりに実装した。Step 1〜3 は同一ファイル (`skills/review/SKILL.md`) の変更なので 1 コミットにまとめた

### Design Gaps/Ambiguities
- Spec の Changed Files は `guard-prefix.sh` への一文追加を `/code` の判断に委ねていた。対話セッションからの fork 実行には届かない文言であり、Step 10 のフォールバックはどの実行面でも SKILL.md 側で効くため、今回は追加しなかった
- 実行環境に `bats` が無く、bats スイートを実行できなかった。代わりに `tests/review.bats` の `## Non-Interactive Mode Behavior` 節への既存 assertion が見る文字列が変更後も残っていることを grep で確認した。`validate-skill-syntax.py` と `check-forbidden-expressions.sh` は通っている (bare bracket の警告 1031 件は既存)

### Rework
- なし
- 新規テストは追加していないので、Pre-implementation FAIL の確認 (Confirmed pre-implementation FAIL for N new test(s)) は対象外 (N=0)

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の Implementation Steps 1〜5 と差分は一致していた。構造的な乖離は無い

### Recurring issues
- 既存の行 (`前景` を含む Foreground bullet) を編集すると、行全体が + 行になって `scripts/check-language-convention.py` の検査対象に入り、元から地の文にあった日本語が初めて検出された。`/code` は `validate-skill-syntax.py` と `check-forbidden-expressions.sh` しか実行しておらず、CI の Language Convention check に相当する確認を持たなかったため、push 後の CI で初めて FAILURE になった。`skills/` `modules/` `scripts/` の既存行を触る変更では、`/code` 側で変更後の差分を `check-language-convention.py` に通す確認が有効かもしれない (改善提案。Issue 化は `/verify` で集約)
- Review 本文に記録する行を新設する変更では、本文テンプレートにその置き場があるかを併せて見る必要がある (今回は SHOULD として指摘し、テンプレートに追記して解消)

### Acceptance criteria verification difficulty
- 4 つの Pre-merge 条件は rubric / `section_contains` / `file_not_contains` で、UNCERTAIN は無かった。Post-merge の observation 条件は fork 実行の light review を要するため、この実行 (`--non-interactive`、`review-light` が同じターンの戻り値で返った) では確認できない
- 今回の `/review` では `review-light` が同期で結果を返したため、Sub-agent Result Fallback の発火経路そのものは検証できていない

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC は 4 件すべてチェック済みで、review-incomplete-fallback も無かったため、ゲートを通過してそのままマージした
- マージ戦略は `resolve-merge-strategy.sh --flag` の結果 (`--squash`) を使い、コンフリクトは無かったので rebase は行っていない

### Deferred Items
- Post-merge の observation 条件 (fork 実行の light review で Review Response Summary が投稿され、Sub-agent fallback 行から結果の出どころが判別できること) は未確認のまま `/verify` に残る

### Notes for Next Phase
- CI は success でマージした。Post-merge の observation 条件は会話セッションでの fork 実行 light review を要するため、`/verify` では UNCERTAIN になりうる

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- `/issue` の Background の事実確認で、#1443 の "Foreground dispatch reminder" がすでにあることが分かった。それによって、主眼を「禁止の文章を足す」から「結果が無いときの代わりの行動 (フォールバック)」に移せた。再発を防ぐ設計判断として妥当だった
- 付記の「#1142 は誤り」は、調べると誤りではなかった (PR #1143 への fork 実行の `/review` が #1142 の retrospective に記録されていた)。AC4 を `file_not_contains` にしたことで、「誤りの修正」と「曖昧さの解消」のどちらでも同じ形で満たせた

#### design
- サブエージェントの `tools:` に SendMessage / Write を足さない判断 (宛先は親セッション、ファイルを待つ手段はポーリング) は、実装と review で異論なく通った

#### code
- Spec どおりの実装で、手戻りは無かった。ただし既存行を編集したことで、元から地の文にあった `前景` が CI の Language Convention check に初めて掛かり、push 後に FAILURE になった。`/code` の実行環境には `bats` も無く、ローカルでの確認は `validate-skill-syntax.py` と `check-forbidden-expressions.sh` に限られた

#### review
- Language Convention の MUST と、記録行の置き場がテンプレートに無いという SHOULD を検出し、どちらも修正した。今回の review では `review-light` が同じターンの戻り値で返ったので、新設したフォールバックの発火経路は観察できていない

#### merge
- コンフリクトは無く、CI success でマージした

#### verify
- Pre-merge 4 件は `/review` でチェック済みのため SKIPPED (既定)。Post-merge の observation 条件 (event=pr-review-light, session=next) は未発火で SKIPPED。Issue は `phase/verify` に留まる

### Improvement Proposals
- `/code` に、変更後の差分 (`skills/` `modules/` `scripts/`) を `scripts/check-language-convention.py` に通す確認を加える。CI の `language-convention` job (`.github/workflows/test.yml`) は `git diff -U100000 origin/<base>...HEAD -- skills/ modules/ scripts/` を同スクリプトに渡しており、既存行を編集すると、元からあった日本語の地の文が初めて検出される。`/code` が同じ確認をローカルで行えば、push 後の CI FAILURE と review での修正の往復を省ける (#1481 で 1 往復発生)
