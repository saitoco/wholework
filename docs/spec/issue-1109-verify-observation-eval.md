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

## Consumed Comments

- saito (MEMBER, first-class): `/issue 1109 --non-interactive` の Issue Retrospective。曖昧ポイント1件 (「対応方針 (案) 4.」の記録先を Notes から Details 列へ) を自動解決し、Background の事実確認 (`modules/verify-executor.md:244` と `scripts/observation-trigger.sh:79` の矛盾) を実施した記録。AC 変更なし。 (https://github.com/saitoco/wholework/issues/1109#issuecomment-5138255302)
