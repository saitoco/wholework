# Issue #1109: verify: event 発火済み observation AC の評価手順を定義する

## Overview

`<!-- verify-type: observation event=<name> -->` を持つ post-merge AC について、`event` が既に発火した後の `/verify` 実行時にどう評価するかが定義されていない。`modules/verify-executor.md` の verify-type 解釈テーブルは observation を常に SKIPPED とする一方、`scripts/observation-trigger.sh` の通知コメントは「`/verify` を再実行して checkbox を更新せよ」と案内しており、両者が矛盾している。本 Spec では、event 発火済みかどうかを判定したうえで PASS/FAIL/UNCERTAIN を評価する分岐を `/verify` に追加し、判定に使える証拠収集手段を列挙する。

## Reproduction Steps

1. Issue に `<!-- verify-type: observation event=<name> -->` タグの post-merge AC が存在する状態で PR がマージされ、Issue が `phase/verify` になる。
2. `<name>` に対応するイベント (例: `/auto` 完了) が発火し、`scripts/observation-trigger.sh` が `opportunistic-search.sh --event <name>` 経由でこの Issue をマッチし、「observation event `<name>` detected. Run `/verify N` to verify the condition and update the checkbox.」というコメントを投稿する。
3. 案内どおりユーザー (または L2/L3 自律度での自動ディスパッチ) が `/verify N` を再実行する。
4. `modules/verify-executor.md:244` の現行規定により、observation 条件は event 発火の有無に関わらず常に SKIPPED (`detail: "observation: waiting for event=<name>"`) と判定される — `skills/verify/SKILL.md` のどのステップにも「発火済みコメントを検出して評価する」分岐が存在しない。
5. checkbox は更新されず、Issue は `phase/verify` に留まり続ける。event が実際に発火した事実は再実行のたびに失われる。

## Root Cause

`modules/verify-executor.md` の verify-type 解釈テーブル (observation 行) は「通常の `/verify` 実行では常にスキップし、event 発火時に再評価される」とだけ記述しているが、「event 発火時に再評価される」具体的な処理経路が `skills/verify/SKILL.md` のどこにも実装されていない。`scripts/observation-trigger.sh` はイベント発火の事実をコメントとして Issue に残すだけで、そのコメントを読み取って評価に反映する消費側のロジックが欠落している。結果として、`/verify` を再実行しても常に同じ SKIPPED 判定に戻り、checkbox は永久に更新されない。

## Changed Files

- `modules/verify-executor.md`: verify-type 解釈テーブルの `observation` 行 (L244) を、常に SKIPPED とする記述から「event 発火済みなら評価、未発火なら従来どおり SKIPPED」に分岐させる記述に更新する。評価手順の詳細は `skills/verify/SKILL.md` Step 8c を参照させる。
- `skills/verify/SKILL.md`:
  - Step 4 の post-merge 条件振り分け (Pre-merge/Post-merge 説明の箇条書き) に observation 条件専用の分岐 (Step 8c へのルーティング) を追加する
  - Step 7 の Post-merge Briefing テーブルの "Claude Executable?" 列ガイダンスを、observation 条件について発火済み/未発火で表示を分ける記述に更新する
  - Step 8 に新設の "Step 8c: Observation Post-merge Conditions" を追加する (発火判定 → 証拠収集 → PASS/FAIL/UNCERTAIN/SKIPPED 判定)
  - Step 8 の "Post-Step 8 checkpoint: flip post-merge PASS checkboxes" の PASS 判定元列挙に Step 8c を追加する
  - Step 11(a) の "Conditions subject to reopen judgment" 箇条書きに、Step 8c で PASS/FAIL と確定した observation 条件を追加する
- Steering Docs sync candidate (grep 済み、変更不要と確認):
  - `docs/structure.md` L113, L202 (`modules/observation-trigger.md` / `scripts/opportunistic-search.sh` の役割説明のみで、`/verify` の評価分岐には言及していないため現状のまま正確)
  - `docs/workflow.md` L223, L262 (「opportunistic/observation/manual unchecked → phase/verify」という粒度の説明は本修正後も真であり、個々の observation AC が発火済みなら checked になり得るという詳細まで踏み込んでいないため更新不要)
  - `tests/opportunistic-search.bats` / `tests/audit-auto-session.bats` / `tests/issue.bats` (いずれも observation-trigger.sh / opportunistic-search.sh / `/issue` 側の AC 生成に関するテストで、本 Issue が変更する `/verify` の評価ロジックとは無関係)

## Implementation Steps

1. `modules/verify-executor.md` の verify-type 解釈テーブル `observation` 行 (L244 付近) を、event 発火済み/未発火で分岐する記述に更新する。発火済みの場合の評価手順は `skills/verify/SKILL.md` Step 8c を参照する形にする。(→ 受入条件 3)
2. `skills/verify/SKILL.md` Step 4 の post-merge 条件振り分けの箇条書き ("Post-merge + with hints" / "Post-merge + without hints" の2分岐) に、`<!-- verify-type: observation event=... -->` を持つ条件を Step 8c にルーティングする3つ目の分岐を追加する。(→ 受入条件 1)
3. `skills/verify/SKILL.md` の Step 8b ("Manual Post-merge Conditions") の直後に新設の "Step 8c: Observation Post-merge Conditions" を追加する。(after 2) (→ 受入条件 1, 2)
   - **発火判定**: AC の `event=<name>` を抽出し、Step 4 のカットオフに縛られない専用の全履歴検索で判定する:
     ```bash
     gh issue view "$NUMBER" --json comments --jq '.comments[].body' \
       | grep -F "observation event" | grep -F "detected" | grep -F -- "$EVENT_NAME"
     ```
     一致なし → 従来どおり SKIPPED (`detail: "observation: waiting for event=<event-name>"`)。一致あり → 証拠収集に進む。
   - **証拠収集** (ベストエフォート。すべての情報源が毎回揃うわけではない):
     - 直近の `/auto` 実行ログ・phase 出力
     - `.tmp/auto-events.jsonl` の該当 session_id のイベント (ファイルが現存する場合)
     - read-only な `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event <name>` の再実行結果 (副作用なし: `gh issue comment` / `gh issue edit` を呼ばないことを確認済み)
     - 対象リポジトリの `.wholework.yml` 設定・ディレクトリ/ファイル構成 (条件の前提が本リポジトリで成立するか)
   - **判定**: 収集した証拠から条件充足 → PASS、反証あり → FAIL、証拠不十分/曖昧 → UNCERTAIN、観測対象の前提自体が本リポジトリで成立しない (例: 参照している `config=` キーが unset/false、参照しているディレクトリ・機能が存在しない) → SKIPPED (理由を Step 9 の `## Acceptance Test Results` コメントの Details 列に記録)
4. `skills/verify/SKILL.md` の以下3箇所を Step 8c 追加に合わせて更新する: (after 3) (→ 受入条件 1)
   - Step 7 の "Claude Executable?" 列ガイダンス: observation 条件について、未発火なら "— (waiting for event)"、発火済みなら "Yes — evaluate now (event fired)" (詳細は Step 8c) と表示を分岐させる
   - "Post-Step 8 checkpoint: flip post-merge PASS checkboxes" の PASS 判定元の列挙 ("Step 8a auto-verify PASS or Step 8b \"Claude Execute\" PASS") に "or Step 8c fired-and-evaluated PASS" を追加する
   - Step 11(a) の "Conditions subject to reopen judgment" 箇条書きに "Post-merge `<!-- verify-type: observation ... -->` conditions confirmed as PASS or FAIL in Step 8c (conditions remaining SKIPPED — not yet fired, or prerequisite unmet — are excluded)" を追加する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md に、observation AC の event が既に発火している場合は SKIPPED にせず PASS/FAIL/UNCERTAIN を判定する分岐が追加されている。発火済みかどうかの判定方法も示されている" --> event 発火済み observation AC の評価分岐が追加されている
- <!-- verify: rubric "判定に使える証拠収集手段が複数列挙されている (少なくとも auto 実行ログ、auto-events.jsonl、read-only な opportunistic-search.sh の実行結果を含む)" --> 証拠収集手段が列挙されている
- <!-- verify: rubric "modules/verify-executor.md の verify-type テーブルの observation 行が、常に SKIPPED とする記述から、event 発火状況に応じて分岐する記述へ更新されている" --> `verify-executor.md` の記述が新しい分岐と整合している
- <!-- verify: command "bats tests/verify.bats" --> `tests/verify.bats` が PASS する

### Post-merge

- observation AC を持つ Issue に対して event 発火後に `/verify` を実行し、条件が満たされている場合に checkbox が更新され `phase/done` へ遷移することを確認する <!-- verify-type: manual -->

## Notes

- **発火判定を Step 4 のカットオフに依存させない理由**: `modules/l0-surfaces.md` の Comment Consumption Procedure が使う cutoff (直近の `phase/*` ラベル付与時刻) は、observation-trigger.sh のコメントが `/verify` 自身の直前のラベル遷移より前に投稿されていた場合、通常のカットオフ判定では拾えない可能性がある (l0-surfaces.md 自身も verify-fail / preview-ac-unverified マーカーについて同様の理由で cutoff 非依存の "Cross-phase marker exception" を設けている)。observation の発火コメントは通常の `<!-- wholework-event: ... -->` 形式のマーカーではなく素のプレーンテキストであるため、この既存の cross-phase 例外にも該当しない。このため Step 8c は Step 4 の消費結果に頼らず、AC ごとに `event=<name>` を対象にした専用の全履歴検索を行う設計とした。
- **`config=` ゲートとの役割分担**: `opportunistic-search.sh` の `config=` ゲート (`modules/observation-trigger.md` 参照) は、フラットな boolean キー1つで表現できる前提条件を通知コメント投稿前にフィルタする。Step 8c の「前提不成立時は SKIPPED」判定はこれと重複するものではなく、`config=` で表現しきれない前提 (ディレクトリ構成など) を証拠収集後に発見した場合の受け皿として設けている。
- **Issue Retrospective からの引き継ぎ**: `/issue` フェーズの Auto-Resolve Log により、「対応方針 (案) 4.」の記録先は "Notes" ではなく `## Acceptance Test Results` の Details 列に統一済み。本 Spec の Implementation Steps 3 もこの用語に合わせている。

## Autonomous Auto-Resolve Log

- **`/code 1109 --pr --non-interactive` Step 3 (phase/ready ラベルチェック)**: Issue のラベルは `phase/ready` ではなく既に `phase/code` だった。タイムライン (`labeled phase/ready` → 3分後に `unlabeled phase/ready` / `labeled phase/code`) から、前回の `/code` 実行がラベル遷移 (Step 4) までは完了したが、ブランチ・worktree・PR を残さず中断したと判断した。Spec (`docs/spec/issue-1109-verify-observation-eval.md`) は Design Complete まで完了しており内容も完備しているため、AskUserQuestion による確認を経ずに既存 Spec を使って実装を続行した。

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1109 --non-interactive` の Issue Retrospective。曖昧ポイント1件 (「対応方針 (案) 4.」の記録先を Notes から Details 列へ) を自動解決し、Background の事実確認 (`modules/verify-executor.md:244` と `scripts/observation-trigger.sh:79` の矛盾) を実施した記録。AC 変更なし。 (https://github.com/saitoco/wholework/issues/1109#issuecomment-5138255302)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background が `modules/verify-executor.md:244` と `scripts/observation-trigger.sh:79` という 2 箇所の矛盾を行番号付きで特定しており、`/issue` の事実確認でも実コードと一致することが確認された。矛盾を「仕様 A と仕様 B が食い違う」形で提示できたため、Spec 以降の設計判断が最短で進んだ。
- 曖昧点の自動解決 (記録先を「Notes」から既存の `## Acceptance Test Results` Details 列へ統一) は、既存の出力フォーマットに存在しない項目名を導入しないための修正であり妥当。AC テキストは変更されていない。

#### spec
- Changed Files に「Steering Docs sync candidate (grep 済み、変更不要と確認)」として `docs/structure.md` / `docs/workflow.md` / 3 つの bats を挙げ、それぞれ不要と判断した根拠まで書いている。この形式自体は良い。
- **ただし監査対象の選定に漏れがあった**。`modules/observation-trigger.md` と `modules/verify-classifier.md` が「常に SKIPPED」という pre-fix の記述を保持したままで、`modules/verify-executor.md` だけが更新される非対称な状態になっていた。review retrospective が指摘するとおり、監査対象を「PR diff で変更したファイル」ではなく「同じ仕様事項を別角度から記述している既存ドキュメント」まで広げる必要があった。
- **回帰テストが Implementation Steps に明記されていなかった**。Pre-merge AC の `command "bats tests/verify.bats"` は既存スイートの PASS しか保証せず、既存スイートに `observation` 関連ケースが皆無だったため、新設した Step 8c のロジックを実際には一切検証していなかった。

#### code
- worktree の変更 3 ファイルは Spec の Changed Files と完全一致し、Implementation Steps 5 箇所 (Step 4 routing / Step 7 列ガイダンス / Step 8c 新設 / Post-Step 8 checkpoint / Step 11(a)) をすべて実装していた。設計逸脱なし。
- **code フェーズは silent no-op で 3 回連続失敗した**。`/code` が headless (`claude -p`) で bats テストスイートをバックグラウンド実行し、届かない完了通知を待ってターンを終える — #1097 として起票済みのパターンそのものの再現。3 回目は並行セッションが main に未コミット変更を持っていたため `check-verify-dirty` のガードで停止した。
- 親セッションが worktree の状態を検査し (Changed Files 一致・Implementation Steps 網羅・bats 90 件 PASS・validator 通過を確認)、commit → rebase → push → PR 作成で復旧した。`/code` 自身の commit ステップは実行されていないため `## Code Retrospective` は存在しない。

#### review
- `/review` が 3 件の実質的な欠陥を検出し、いずれも同一 PR 内で修正した。
  - Documentation Consistency: `modules/observation-trigger.md` / `modules/verify-classifier.md` の pre-fix 記述の残存 (spec の監査漏れを回収)
  - Bug: Step 8c の `gh issue view` 失敗を「未発火」と誤認する経路 → UNCERTAIN 化
  - Bug: 発火判定の部分一致衝突 (`event=auto` が `event=auto-run` にマッチしうる) → バッククォート完全一致へ
  - Test Quality: 新ロジックの回帰テストが皆無 → `tests/verify.bats` に 7 件追加
- **AC 検証では 3 件とも原理的に捕捉できなかった**。rubric AC は「分岐が追加されているか」「証拠収集手段が列挙されているか」を問うており、その分岐の内部的な正しさ (エラーハンドリング・マッチの厳密性) やテストの実効性は問えない。review の付加価値が明確に出た事例。

#### merge
- pre-merge AC ゲート (#1060 で導入) が 4/4 checked を確認して通過。`mergeable=true` / CI 9 件 SUCCESS / approved で squash merge 完了。
- `gh pr merge --delete-branch` のローカルブランチ削除が失敗した (`worktree-code+issue-1109` が worktree で使用中)。リモートブランチ削除と PR MERGED は成功しており、merge フェーズはスコープ外として残存を許容した。この判断は妥当。
- 親セッション側の観測: `scripts/gh-pr-merge-status.sh` が CI の `IN_PROGRESS` を `ci_status: failing` / `reason: ci_failing` と分類した。実際には 7 件 SUCCESS + 2 件 IN_PROGRESS で失敗は 0 件。CI 完了後に再実行したところ `mergeable: true / clean / success` に変わった。in-progress と failing を同一視すると、merge 可否の判断が誤る (親セッションは一度 merge を見送った)。

#### verify
- 自動検証 4 件すべて PASS。`bats tests/verify.bats` は 15 件 (review が追加した 7 件を含む) すべて PASS。
- post-merge の manual AC は、**条件が充足される observation AC を持つ Issue が現時点で存在しない**ため実行不可と判定した。`auto-run` でマッチする 10 件 (#839, #841, #843, #984, #995, #1009, #1035, #1037, #1107, #1113) はいずれも観測前提が本リポジトリで成立せず、Step 8c の判定では SKIPPED になる。
- 参考として、本 Issue のマージ**前**に #1027 と #1026 で「event 発火後に `/verify` → PASS 判定 → checkbox 更新 → `phase/done`」の流れを実測している。ただし当時は判定手順を都度即興で組み立てており (それ自体が本 Issue の起票理由)、マージされた Step 8c の手順による確認には代えられない。

### Improvement Proposals

- **`scripts/gh-pr-merge-status.sh` が CI の `IN_PROGRESS` を `failing` と分類する**。PR #1121 では 7 件 SUCCESS + 2 件 IN_PROGRESS の状態で `{"mergeable": false, "reason": "ci_failing", "ci_status": "failing"}` を返した。失敗は 0 件であり、CI 完了後は `{"mergeable": true, "reason": "clean", "ci_status": "success"}` に変わった。`/merge` Step 1 はこの JSON で分岐するため、in-progress を failing と扱うと「CI 失敗」として誤った経路 (AskUserQuestion / 非対話時の自動解決) に入る。`ci_status` に `pending` 相当の値を追加し、`reason` も `ci_pending` として区別すべき。呼び出し側は pending なら待機、failing なら中断という分岐にできる。
- **`scripts/validate-skill-syntax.py` の単一バッククォート正規表現ストリッパーが、二重バッククォートのインラインコード表記を誤処理する**。`/review` の修正作業中に Step 8c へ二重バッククォート形式のインラインコードを導入したところ、ストリッパーが誤マッチして文書の広い範囲を巻き込み、無関係な `<!-- verify: ... -->` プレースホルダーを「未知の verify コマンド」として誤検出した。SKILL.md 本文で二重バッククォートを使えないという暗黙の制約が生まれており、しかもエラーメッセージからは原因が読み取れない。ストリッパーを二重バッククォート対応にするか、少なくとも制約として明文化すべき。
- **新しい分岐ロジックを追加する Issue で、対応する回帰テストの追加が Implementation Steps に明記されない**。#1109 では Pre-merge AC の `command "bats tests/verify.bats"` が既存スイートの PASS しか保証せず、既存スイートに `observation` 関連ケースが皆無だったため新ロジックを一切検証していなかった。`/review` の Test Quality finder が検出して 7 件追加したが、本来は Spec 段階で担保すべき。Verification 節の command AC を「既存スイートが PASS すること」ではなく「新ロジックを検証する新規ケースを追加したうえでスイートが PASS すること」と書かせる運用が必要。(関連: #1096 は「新規 assert が実装前に FAIL することを確認させる」で、本提案は「そもそも新規 assert を追加させる」側)
- **Steering Docs sync candidate の監査対象が「PR diff で変更したファイル」に閉じている**。#1109 では `modules/observation-trigger.md` / `modules/verify-classifier.md` が同じ仕様事項 (observation AC の扱い) を別角度から記述していたにもかかわらず監査対象から漏れ、pre-fix の記述が残った。`/spec` の監査手順に「変更する仕様事項を表すキーワード (例: `verify-type: observation`) で `grep -rl` し、ヒットした全ファイルを監査対象に含める」を追加すべき。(関連: #1073 はタグ・enum の意味論拡張時の消費箇所洗い出し、#1089 は sync candidate check のゲート条件に `modules/` を含める — 本提案はキーワード横断検索による対象選定という第三の角度)

## review retrospective

### Spec vs. implementation divergence patterns

Spec の Notes 節はステアリングドキュメント同期の監査対象として `docs/structure.md` / `docs/workflow.md` のみを検討しており、`modules/observation-trigger.md` と `modules/verify-classifier.md` が漏れていた。両ファイルとも本 Issue が修正した「常に SKIPPED」という pre-fix の記述をそのまま残しており、`modules/verify-executor.md` だけが更新される非対称な状態になっていた。監査対象の選定は「PR diff で変更したファイル」に閉じず、「同じ仕様事項を別の角度から記述している既存ドキュメント」まで広げる必要がある。今回は `/review` の Documentation Consistency 観点で検出・修正したが、次回以降は Spec 作成時点で `grep -rl "verify-type: observation"` 等の横断検索を Implementation Steps に含めることを検討したい。

### Recurring issues

新設した Step 8c のロジックに対する回帰テストが Implementation Steps に明記されておらず、Pre-merge AC `command "bats tests/verify.bats"` の PASS が新ロジックを実際には検証していなかった (既存スイートに `observation` 関連ケースが皆無)。`skill-dev-recheck.md` の Type=Bug 重み付けにより `/review` の review-light エージェントがこれを検出したが、本来は Spec の Implementation Steps に「対応する bats ケースを追加する」ことを明記すべきだった。新しい分岐ロジックを追加する Issue では、Verification 節の command AC を「既存スイートが PASS すること」だけでなく「新ロジックを検証する新規ケースを追加すること」まで含めて記述する運用を検討したい。

### Acceptance criteria verification difficulty

3件の rubric 系 AC は diff の内容と一致しており UNCERTAIN なく判定できた。ただし `/review` の修正作業中、Step 8c の説明文に二重バッククォート形式のインラインコード (`` `text` `` ``) を導入したところ、`scripts/validate-skill-syntax.py` の素朴な単一バッククォート正規表現ストリッパーが誤マッチし、文書の広い範囲を巻き込んで無関係な `<!-- verify: ... -->` プレースホルダーを「未知の verify コマンド」として誤検出した。この地雷は AC 自体には現れないが、SKILL.md 本文を編集する際は二重バッククォートのインラインコード表記を避けるべきという運用上の注意点として記録する。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC ゲート (`check-pre-merge-ac.sh`) は 4件すべて checked (unchecked_count=0) を確認済みのため、ゲート通過は無条件で進行した。
- PR #1121 は mergeable=true / CI success / review approved だったため、コンフリクト解消ステップ (Step 3) は不要でそのまま squash merge を実行した。
- squash merge 自体は成功したが、`gh pr merge --delete-branch` のローカルブランチ削除は失敗した (`worktree-code+issue-1109` ブランチが別 worktree `.claude/worktrees/code+issue-1109` で使用中のため)。リモートブランチは削除済み、PR は MERGED 済みであることを確認し、ローカル残存ブランチ・worktree はそのまま維持した (今回のスコープ外の削除操作は行わない判断)。

### Deferred Items
- Post-merge の観察系 AC (`event 発火後に /verify を実行し checkbox が更新されることを確認する`) は `verify-type: manual` のため引き続き人手確認待ち。
- ローカルに残存する `worktree-code+issue-1109` ブランチと `.claude/worktrees/code+issue-1109` worktree の後片付けは未実施 (別セッションの作業物である可能性があるため、merge フェーズの範囲外として保留)。

### Notes for Next Phase
- `/verify` 実行時、Post-merge の manual AC 1件が残っている点に注意。
- SKILL.md / モジュールファイルを編集する際は二重バッククォートのインラインコード表記 (`` `text` ``) を避けること — `scripts/validate-skill-syntax.py` の正規表現ストリッパーがこれを誤処理する。
