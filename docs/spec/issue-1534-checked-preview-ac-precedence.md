# Issue #1534: verify: 既チェックの preview manual AC と preview-ac-unverified fallback の優先順位を明文化

## Overview

`skills/verify/SKILL.md` Step 5 の 2 つのスキップ規則 (pre-merge-preview AC skip rule と Already-checked AC skip rule) は、`ac-tier: preview` の AC が「fallback 対象」かつ「既に `- [x]`」である場合に矛盾した指示を出す。ここでいう fallback 対象とは、`scripts/resolve-preview-ac-fallback.sh` の出力リストにその AC の index が含まれる場合 (marker 起点)、または出力が空で `REVIEW_SUMMARY_FOUND=false` の場合 (Summary 不在起点) を指す。

- 規則 1 の fallback 分岐: manual AC は UNCERTAIN、auto AC は `PRODUCTION_URL` で再検証
- 規則 2: SKIPPED

規則 2 末尾の「両者は衝突せず同じ SKIPPED に収束する」は、規則 1 の非 fallback 分岐でのみ成立する。人間が merge 前に preview で確認して `- [x]` にした manual AC を UNCERTAIN に落とすと、Step 11 の分岐 (d) で `phase/verify` に滞留し、確認済みの条件の再確認を促してしまう (downstream で発生。実態に合わせて SKIPPED と判定して回避した)。

本 Spec は、**チェックボックス状態を fallback 判定より先に評価する** 優先順位を SKILL.md に明文化する。

- `- [x]` の AC は、fallback 対象かどうかを問わず SKIPPED とする。fallback (UNCERTAIN、または `PRODUCTION_URL` での再検証) は `- [ ]` のままの AC にのみ適用する
- auto の preview 層 AC (verify command あり) も manual と統一して SKIPPED とし、`PRODUCTION_URL` での再検証は行わない。本番確認を継続したい場合は既存の逃げ道 (`### Post-merge` へタグなしで重複記載) を使う
- SKIPPED の note は、非 fallback 対象なら従来の "preview-tier AC; verified/checked at /review against preview URL" を維持し、fallback 対象なら "already checked; skipped by default (preview-tier AC not verified at /review; fallback not applied)" とする (`/review` は検証していないため前者の文言は不正確になる)

変更は `skills/verify/SKILL.md` の prose 明文化と、それに伴うマーカー再計算・テスト追加に限る。`scripts/resolve-preview-ac-fallback.sh` は fallback 対象 index を返すだけで既チェックかどうかを判定しないため、スクリプトの挙動変更は不要。

## Consumed Comments

cutoff: 2026-10-16T06:49:35Z (最新の `phase/issue` ラベル付与時刻)

- saito / MEMBER / first-class / Issue Retrospective (AC 1 を marker 起点・Summary 不在起点の両方に拡張、Notes に tests/verify.bats の依存文字列を追記、premise マーカーを付与、auto の preview 層 AC の扱いは /spec に委譲) / https://github.com/saitoco/wholework/issues/1534#issuecomment-6209865199

## Changed Files

- `skills/verify/SKILL.md`: Step 5 の 2 規則を修正する (詳細は Implementation Steps 1〜2 と 5) — bash 非対象 (Markdown skill 定義ファイル)
  - pre-merge-preview AC skip rule: per-AC 箇条書きの導入文、第 1 箇条 (非 fallback)、新設の第 2 箇条 (`- [x]` の fallback 対象)、既存 fallback 箇条の見出し条件
  - Already-checked AC skip rule: 末尾の "converge" 文を優先順位の段落に置換
  - 冒頭の `<!-- skill-body-lines: N -->` / `<!-- skill-body-sha: H -->` マーカーを再計算 (本文を変えると `tests/verify.bats` の同期テストと CI の Skill Body Hash check が落ちる)
- `tests/verify.bats`: 新規の内容アサーションテスト 3 件を追加する (既存の Step 5 already-checked AC skip rule テスト群の直後)
- [Steering Docs sync candidate] `docs/guide/customization.md`: `/verify` の preview 層 AC fallback を「チェック状態の例外なし」で述べている 2 箇所を再確認する。(a) 設定リファレンス表 `capabilities.pr-preview` 行の "unless `/review`'s latest `type=preview-ac-unverified` marker lists the AC as unverified, in which case `/verify` falls back to a production-URL check"、(b) "At `/verify` (post-merge)" 箇条書き内の "For any AC still listed as unverified in that latest marker, `/verify` falls back ..."。「未チェック (`- [ ]`) の AC に限る。既に `- [x]` の AC は already-checked 規則で SKIPPED (manual / auto 共通)」を追記するかは `/code` が判断する (SHOULD)
- [Steering Docs sync candidate] `docs/ja/guide/customization.md`: 上記の日本語ミラー (128 行付近の表セル、202 行付近の箇条書き)。`docs/translation-workflow.md` に従って同期する
- [Steering Docs sync candidate] `docs/tech.md`: Capability Flags 表の `HAS_PR_PREVIEW_CAPABILITY` 行 (341 行付近) に同種の記述 ("... lists the AC as unverified (...), in which case `/verify` falls back to a production-URL check for the auto subcase ...") がある。上と同じ観点で再確認する (SHOULD)
- [Steering Docs sync candidate] `docs/ja/tech.md`: 上記の日本語ミラー (332 行付近)
- [Steering Docs sync candidate] keyword "preview-ac-unverified" skipped: matched 47 files (no discriminating power)
- [Steering Docs sync candidate] keyword "ac-tier: preview" skipped: matched 30 files (no discriminating power)
- [Steering Docs sync candidate] keyword "resolve-preview-ac-fallback" skipped: matched 22 files (no discriminating power)

## Implementation Steps

1. `skills/verify/SKILL.md` の `### Step 5: Verify Each Condition (Pre-merge Only)` にある pre-merge-preview AC skip rule の per-AC 箇条書き (`**Review completion check ...**` 段落と、`If the same URL/UX verification is also needed against the production URL ...` 段落の間) を次の a〜d のとおり修正する。追加する文言は英語で、半角 `!` を含めない (→ acceptance criteria 1, 3)
   - a. 導入文 `For each \`ac-tier: preview\` AC in this Pre-merge section, using its own 1-based index in the Issue body's full AC enumeration:` を次に置換する

     ```text
     For each `ac-tier: preview` AC in this Pre-merge section, using its own 1-based index in the Issue body's full AC enumeration, read its checkbox state first — the fallback below applies only to an AC still at `- [ ]`, never to one already at `- [x]`:
     ```

   - b. 第 1 箇条 (`**The script's output is non-empty and this AC's index is not in the output list, or the script's output is empty and \`REVIEW_SUMMARY_FOUND=true\`**: unchanged — ...`) の末尾、`... not an abnormal termination.` の直後に ` This holds whether the AC is at \`- [ ]\` or \`- [x]\`.` を追記する
   - c. 第 1 箇条の直後・既存 fallback 箇条の直前に、次の新しい箇条を 1 つ挿入する (list item は 1 行で書く。既存箇条と同じ形式)

     ```text
     - **This AC is already `- [x]` and its index is in the script's output list, or this AC is already `- [x]` and the script's output is empty and `REVIEW_SUMMARY_FOUND=false`** (a fallback target whose checkbox is already checked): the fallback below does not apply. The checked checkbox is itself the record that the AC was confirmed after `/review` left it unverified — a human checked it against the preview before merge, or an earlier `/verify` run locked in its fallback result at Step 6 — so asking for it again (UNCERTAIN) would only hold the Issue at `phase/verify` through Step 11 (d) for a condition that is already confirmed. Record as SKIPPED per the Already-checked AC skip rule below, with the note "already checked; skipped by default (preview-tier AC not verified at /review; fallback not applied)". This applies to manual and auto preview-tier ACs alike: the verify command of an auto AC is not executed against `PRODUCTION_URL` either.
     ```

   - d. 既存 fallback 箇条の見出し部 (`- **This AC's index is in the script's output list** (i.e., ...), **or the script's output is empty and \`REVIEW_SUMMARY_FOUND=false\`** (i.e. ...): do not record as SKIPPED. First check whether this AC has a verify command:`) を次に置換する。直後のサブ箇条 (manual / auto、`PRODUCTION_URL` 分岐) は一切変更しない

     ```text
     - **This AC is still `- [ ]` and its index is in the script's output list** (i.e., `/review` left it UNCERTAIN and never actually verified/confirmed it against the preview URL), **or this AC is still `- [ ]` and the script's output is empty and `REVIEW_SUMMARY_FOUND=false`** (i.e. `/review` ended without posting a Review Response Summary — likely abnormal termination, including when the completion check script itself failed): the fallback applies only to an AC still at `- [ ]` — do not record it as SKIPPED. First check whether this AC has a verify command:
     ```

2. (after 1) `skills/verify/SKILL.md` の `**Already-checked AC skip rule (default; applies to every Pre-merge condition):**` 段落の最後の文 `This rule does not replace the pre-merge-preview AC skip rule above: ... they converge on the same SKIPPED outcome via different notes for different reasons.` を段落から削除し、その直後に空行を挟んで次の新しい段落を追加する。段落冒頭 (`Any Pre-merge condition already at ...` から `... no opt-in re-verification flag is provided.` まで) は無変更で、見出しと note 文字列 (`Already-checked AC skip rule` / `already checked; skipped by default` / ``Conditions still at `- [ ]` are processed as usual``) を維持する (→ acceptance criteria 2, 3, 4)

   ```text
   **Precedence over the pre-merge-preview AC skip rule above — the checkbox state is evaluated first:** an `ac-tier: preview` condition already at `- [x]` always ends as SKIPPED, including when it is a fallback target of that rule (its index is in the script's output list, or the script's output is empty and `REVIEW_SUMMARY_FOUND=false`). The fallback — UNCERTAIN for a manual condition, the `PRODUCTION_URL` check for an auto condition — applies only to a condition still at `- [ ]`. Only the note differs: a condition that was verified/checked at `/review` (not a fallback target) keeps that rule's note ("preview-tier AC; verified/checked at /review against preview URL"), while a fallback target gets "already checked; skipped by default (preview-tier AC not verified at /review; fallback not applied)" because `/review` did not verify it. Manual and auto conditions are treated alike: the checked checkbox is the recorded confirmation (a human check, or an earlier `/verify` run's Step 6 lock-in of its fallback result), so an auto condition's verify command is not re-executed against `PRODUCTION_URL` either. To keep a standing production check regardless, duplicate the AC in the `### Post-merge` section without the `<!-- ac-tier: preview -->` tag, as described above.
   ```

3. (after 1, 2) `tests/verify.bats` に、既存の `@test "Step 5 already-checked AC skip rule: unchecked pre-merge AC is still processed as usual"` の直後 (`@test "Step 8a already-checked AC skip rule: checked post-merge+hint AC ...` の直前) へ、新規テスト 3 件を追加する。既存の `step5_section` ヘルパーを使い、`docs/tech.md` § BATS Markdown Section Extraction に従って `section="$(step5_section)"` の単純代入で受け、否定アサーションは `if ...; then false; fi` で書く。テストが検査する固定文字列は Step 1〜2 で追加した文言と完全に一致させる。実装時に SKILL.md の文言を調整した場合は、同じ事実を検査し続けるようテスト側も合わせる (→ 新規分岐ロジックの回帰テスト要件)

   ```bash
   # Content-assertion tests for the checkbox-first precedence between the pre-merge-preview AC skip
   # rule and the already-checked AC skip rule in Step 5 (added for #1534). An already-checked fallback
   # target must be recorded SKIPPED (not UNCERTAIN) for manual and auto preview-tier ACs alike; the
   # fallback applies only to an AC still unchecked. Plain assignment so a renamed heading fails the test.

   @test "Step 5 pre-merge-preview AC skip rule: fallback branches apply only to an unchecked AC, for both marker and Summary-absent origins (Issue #1534)" {
       section="$(step5_section)"
       printf '%s\n' "$section" | grep -q -F "This AC is still \`- [ ]\` and its index is in the script's output list"
       printf '%s\n' "$section" | grep -q -F "or this AC is still \`- [ ]\` and the script's output is empty and \`REVIEW_SUMMARY_FOUND=false\`"
   }

   @test "Step 5 pre-merge-preview AC skip rule: an already-checked fallback target is recorded SKIPPED for manual and auto ACs alike (Issue #1534)" {
       section="$(step5_section)"
       printf '%s\n' "$section" | grep -q -F "This AC is already \`- [x]\` and its index is in the script's output list"
       printf '%s\n' "$section" | grep -q -F "or this AC is already \`- [x]\` and the script's output is empty and \`REVIEW_SUMMARY_FOUND=false\`"
       printf '%s\n' "$section" | grep -q -F "fallback not applied"
       printf '%s\n' "$section" | grep -q -F "is not executed against \`PRODUCTION_URL\` either"
   }

   @test "Step 5 already-checked AC skip rule: checkbox state is evaluated first and the old convergence wording is gone (Issue #1534)" {
       section="$(step5_section)"
       printf '%s\n' "$section" | grep -q -F "the checkbox state is evaluated first"
       printf '%s\n' "$section" | grep -q -F "is not re-executed against \`PRODUCTION_URL\` either"
       if printf '%s\n' "$section" | grep -q -F "they converge on the same SKIPPED outcome"; then false; fi
   }
   ```

4. (parallel with 3) Steering Docs sync candidate の採否を判断し、採用するものを更新する (SHOULD)。`docs/guide/customization.md` の 2 箇所と `docs/tech.md` の `HAS_PR_PREVIEW_CAPABILITY` 行について、`/verify` の fallback 記述に「未チェック (`- [ ]`) の AC に限る。既に `- [x]` の AC は already-checked 規則で SKIPPED (manual / auto 共通)」という趣旨を 1 文追記する。採用した場合は `docs/translation-workflow.md` に従い `docs/ja/guide/customization.md` と `docs/ja/tech.md` の対応箇所も日本語で同期する (日本語文中の括弧は半角 `()` の前後に半角スペース)。不要と判断した場合は理由を Code Retrospective に残す (→ SHOULD-level ドキュメント整合)

5. (after 1, 2, 3, 4) SKILL.md 本文の編集がすべて終わった後に、冒頭のマーカー 2 つを再計算して更新し、検証を一括実行する。本文を 1 文字でも変えるとハッシュが変わるため、これを必ず最後に行う (→ acceptance criteria 全般の回帰確認)
   - 行数: `wc -l < skills/verify/SKILL.md` の結果で `<!-- skill-body-lines: N -->` を更新する (編集前は 1000)
   - ハッシュ: `grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8` の結果で `<!-- skill-body-sha: H -->` を更新する (編集前は `db37b840`)。マーカー行自体を除外して計算するため、マーカー値の更新で結果は変わらない
   - 実行して全件 PASS を確認: `bash scripts/check-skill-body-hash.sh` / `python3 scripts/validate-skill-syntax.py skills/` / `bats tests/verify.bats` (既存テストに加えて新規 3 件が PASS し、`skill-body-lines` / `skill-body-sha` の同期テスト 2 件も PASS すること) / `bash scripts/check-forbidden-expressions.sh`

## Verification

### Pre-merge
- <!-- verify: rubric "skills/verify/SKILL.md の pre-merge-preview AC skip rule の fallback 分岐 (script 出力リストに AC の index が含まれる場合、および script 出力が空で Review Response Summary が確認できない場合の両方) に、適用対象が `- [ ]` のままの AC に限られる旨の前提条件が明記されている" --> 規則 1 の fallback 分岐 (marker 起点・Summary 不在起点の両方) に、未チェック AC 限定であることが明記されている
- <!-- verify: rubric "skills/verify/SKILL.md の already-checked AC skip rule の記述が、ac-tier: preview の AC が fallback 対象リストに含まれる場合も含めて、`- [x]` なら SKIPPED になるという優先順位を一意に読める形になっている (旧記述の『両者は衝突せず同じ SKIPPED に収束する』という、非 fallback 分岐でのみ成立する説明が残っていない)" --> 規則 2 の reconciliation note が fallback 対象を含む優先順位を明示している
- <!-- verify: rubric "skills/verify/SKILL.md の明文化において、verify command を持つ auto の preview 層 AC が fallback 対象かつ既チェックの場合の扱い (本番 URL に対する再検証を行うか、manual と同様に SKIPPED とするか) が明示されている" --> auto の preview 層 AC についての扱いも明示されている
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "they converge on the same SKIPPED outcome via different notes for different reasons" --> 非 fallback 分岐でのみ成立する旧記述が残っていない

### Post-merge
- なし (Issue 本文に Post-merge 条件はない。この衝突は `/verify` 実行時の prose 解釈の問題であり、本番環境に観測対象となる面がないため、Pre-merge の rubric と `file_not_contains` で検証が完結する)

## Notes

- **判定表 (最終形、exhaustive)**: `ac-tier: preview` の AC が Step 5 でどう扱われるか。

  | fallback 対象か | checkbox | manual preview AC | auto preview AC | SKIPPED の note |
  |---|---|---|---|---|
  | いいえ (`/review` で verified) | `- [ ]` / `- [x]` | SKIPPED | SKIPPED | preview-tier AC; verified/checked at /review against preview URL |
  | はい | `- [x]` | SKIPPED | SKIPPED (`PRODUCTION_URL` での再検証なし) | already checked; skipped by default (preview-tier AC not verified at /review; fallback not applied) |
  | はい | `- [ ]` | UNCERTAIN (人間による確認が必要) | `PRODUCTION_URL` が非空なら本番で実行、空なら UNCERTAIN | 従来どおり (変更なし) |

- **設計判断 (auto と manual の扱い)**: Issue から `/spec` に委ねられた論点。manual / auto を統一して SKIPPED とした。
  - 根拠 1: `- [x]` の意味。fallback 対象の `- [x]` が生じる経路は、人間が merge 前に preview で確認してチェックした場合と、以前の `/verify` 実行が Step 6 で fallback 結果 (PASS) をロックインした場合の 2 つ。どちらも「確認の記録」で、manual と auto に差はない。auto の preview 層 AC は `/issue` が `--when="test -n \"$PREVIEW_URL\""` ガード付きで作る (`skills/issue/SKILL.md` Step 4 (a)) ため、`/code` の localhost 検証では SKIPPED となり事前にチェックされない設計であることも確認した
  - 根拠 2: #1186 の方針 (`[x]` は一律スキップ、opt-in の再検証フラグなし、継続検証は Post-merge への重複記載) との整合。`resolve-preview-ac-fallback.sh` は append-only の marker を latest-wins で読むため、一度 fallback 対象になった AC は以後の再実行でも毎回 fallback 対象になる。auto だけ `[x]` でも本番再検証にすると、Step 6 でロックイン済みの AC が `/verify` の再実行のたびに再実行され、#1186 のコスト削減に反する
  - 根拠 3: 本番確認を維持したい場合の明示的な手段 (Post-merge へタグなしで複製する段落) が既に SKILL.md にある
  - 却下案: auto のみ `- [x]` でも `PRODUCTION_URL` で再検証する。規則が manual / auto で非対称になる上、人間が preview で確認した結果と本番の結果が食い違う場合 (preview 固有の内容など) に FAIL から reopen する経路が生まれ、複雑さに見合う利点がない
- **fail-closed 設計の維持**: `REVIEW_SUMMARY_FOUND` は「完了を確認できなければ verified とみなさない」fail-closed の判定。新設の箇条は既に `- [x]` の AC にのみ作用し、`- [ ]` の AC の挙動 (UNCERTAIN / 本番確認) は変えない。したがって `- [ ]` の AC に新しい fail-open 経路は生じない
- **衝突の再現確認 (実測、測定範囲 `skills/verify/SKILL.md` のみ)**: 修正前は `grep -c -F "they converge on the same SKIPPED outcome via different notes for different reasons" skills/verify/SKILL.md` が 1 件 (230 行)。修正後は 0 件になること。対照群として見出し `Already-checked AC skip rule` (`grep -c -F`、同ファイル) は修正前後とも 1 件で維持される (AC 4 は不在確認のため、修正前の件数を基準点として記録した)。修正前の `wc -l skills/verify/SKILL.md` は 1000 行 (マーカーの `skill-body-lines` も 1000)
- **Issue 本文と既存実装の照合**: 矛盾は検出されなかった。背景の引用 (do not record as SKIPPED / already checked; skipped by default / converge on the same SKIPPED outcome) は SKILL.md 現行文面と一致する。Issue Notes の premise マーカー (`grep_count "[x]" "scripts/resolve-preview-ac-fallback.sh" -eq 0`) は `scripts/check-premise-expiry.sh` が `git grep -F` (固定文字列) で評価するため 0 件で成立する (`grep -cF "[x]"` で 0 件を確認。ERE で評価すると `x` 1 文字にマッチして 7 件になるが、評価系は固定文字列)
- **保持が必要な既存アサート (`tests/verify.bats`)**: Step 5 の見出し文字列 `Already-checked AC skip rule`、note `already checked; skipped by default`、`Conditions still at \`- [ ]\` are processed as usual`、`resolve-preview-ac-fallback.sh`、`latest-wins`、`verify-type: manual`、`no automatic fallback exists`、`Review Response Summary`、`reconcile-phase-state.sh`。Step 8a の `still \`- [ ]\` (unchecked)` と `already checked; skipped by default`、Step 6 の `skipped by default` / ``Only conditions still at `- [ ]` are (re-)verified`` も対象。本変更はいずれの箇所も書き換えない
- **他コンシューマとの整合 (変更不要、文面を読んで確認済み)**:
  - `modules/l0-surfaces.md` の `type=preview-ac-unverified` 説明 (131〜158 行付近) は「`/verify` がこの marker で `/review` が実際に検証したかを判定する」と述べるのみで、新しい優先順位と矛盾しない
  - `skills/review/SKILL.md` の marker 投稿箇所 (300〜312 行付近) も同様
  - `skills/audit/SKILL.md` の Manual Waiting Count (365 行付近) と `skills/auto/SKILL.md` の Pending manual confirmation (1322 行付近) は、いずれも未チェック (`- [ ]`) の行だけを走査する。「チェック済みは待ち行列に入らない」という新しい優先順位と整合している
  - `modules/verify-classifier.md` の Purpose 末尾 (9 行) は一般論で矛盾しない。`docs/structure.md` (210 行) は `resolve-preview-ac-fallback.sh` のスクリプト説明のみ。`docs/workflow.md` / `README.md` / `CLAUDE.md` には `already checked` / `skipped by default` / `preview-tier` / `ac-tier` の記述がない (`grep -n -i` で 0 件)
- **Steering Docs sync candidate check の実施内容**:
  - 識別力フィルタ: `grep -rl -F <keyword> docs/ tests/ scripts/ modules/` の件数 (測定範囲は docs/spec/ と docs/sessions/ を含む 4 ディレクトリ全体)。`preview-ac-unverified` 47、`ac-tier: preview` 30、`resolve-preview-ac-fallback` 22 の 3 つは 8 件超でスキップした (docs/spec/ と docs/sessions/ を除いても 12 / 12 / 9 件で、いずれも 8 件超)。`REVIEW_SUMMARY_FOUND` 1、`already checked; skipped by default` 2、`Already-checked AC skip rule` 2 は 8 件以下のため全文検索した。ヒットは歴史的な Spec (`docs/spec/issue-1053-*`、`docs/spec/issue-1186-*`) と `tests/verify.bats` のみで、前者は使い捨て記録のため対象外、後者は Changed Files に含まれている
  - docs 側の候補 (`docs/guide/customization.md`、`docs/tech.md`、各日本語ミラー) は、上記のキーワード grep ではなく Step 6 の文面調査 (fallback の挙動を説明している箇所を読んだ結果) で見つけた
  - listing 側の確認: 非該当 (サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構造の変更なし)
  - Outbound pointer の確認: 変更する SKILL.md Step 5 の pointer 先 (`modules/l0-surfaces.md` § Machine-Readable Event Marker、`scripts/resolve-preview-ac-fallback.sh`、`## Notes`) の内容は本変更で影響を受けない
  - `docs/migration-notes.md`: CLI シグネチャ・フラグ・引数順の変更を伴わないため対象外
- **新規テスト要件 (新規分岐ロジック)**: SKILL.md に新しい条件分岐 (チェック済み fallback 対象 → SKIPPED) が加わる。既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/verify.bats` に Implementation Step 3 の 3 件) を追加したうえでスイートが PASS すること (Implementation Step 5 で実行)
- **Size / Route**: 確定した変更ファイルは `skills/verify/SKILL.md` と `tests/verify.bats` の 2 件で、トリアージ時の Size S (patch route) を維持する。docs 側の同期候補は 1 文の追記で `/code` が採否を判断する (採用しても documentation-only の軽微な変更)
- **allowed-tools**: SKILL.md 本文に新しい `scripts/` 参照やツールを追加しないため、frontmatter の `allowed-tools` は変更不要。新規 script もない
- **その他の判定 (すべて非該当)**: UI Design (UI を含まない)。audit / investigation 型 (複数項目の網羅的分類ではなく、既存 prose の優先順位の明文化)。Tag/enum の意味拡張 consumer sweep (既存の値の意味拡張ではなく、同一 skill 内の 2 規則の優先順位の明文化。念のため上記のとおり consumer は確認した)。fail-safe critical script (スクリプト変更なし)。Costly/irreversible step、外部サービスへのログイン、Smoke Test (いずれも該当する Step なし)。`.claude/` 配下のファイル変更 (なし)
- **制約**: SKILL.md 本文に半角 `!` を入れない (`validate-skill-syntax.py` が検出)。追加する文言は英語 (Language Convention check)。非推奨用語を使わない (`docs/tech.md` § Forbidden Expressions)
