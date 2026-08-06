# Issue #1186: verify: チェック済み AC の再検証を既定でスキップし二重検証コストを削減

## Overview

`/verify` は現在、再実行のたびに **すべての acceptance condition を、チェック済み (`[x]`) か否かに関わらず再検証する**。pre-merge AC は `/review` の pre-merge AC gate (`check-pre-merge-ac.sh`) により merge 前に全件チェック済みとなるため、`/verify` の初回実行時点で既に「チェック済みの全件再検証」が発生する構造になっている。実測 (#1157 の再々検証、2026-08-05) では、チェック済み 6 件の再検証 (1405 件の bats テスト実行を含む) が新規情報をゼロ件しか生まず、唯一の未チェック条件のみが新規情報 (UNCERTAIN) を生んだ。

Issue 本文の「方針確定 (2026-08-06)」注記により対応方針は確定している: **A. 一律スキップ** — `[x]` のチェック済み AC は pre-merge / post-merge を問わず再検証せず SKIPPED として扱う。opt-in の再検証フラグは導入しない。merge 後も継続検証したい条件は Post-merge セクションに同一内容の AC を重複記載することで表現する。

コードベース調査の結果、スキップ規則を追加すべき箇所は 2 箇所に限定されることを確認した:
- **Step 5 (pre-merge)**: 「treat all conditions as auto-verification targets」としており、チェック済み条件を除外していない
- **Step 8a (post-merge + hint)**: 「For post-merge conditions that have `<!-- verify: ... -->` hints」としており、同様にチェック済み条件を除外していない

一方、**Step 8b (manual)** と **Step 8c (observation)** は既に「For each **unchecked** post-merge condition」という条件で unchecked のみを対象にしており、今回の変更は不要。また、Step 5 には `ac-tier: preview` AC 向けの既存スキップ規則があり、今回追加する一般規則はこれと矛盾せず併存する (preview AC が `[x]` になっていれば一般規則で SKIPPED、`[ ]` のままなら既存の preview 規則が処理する)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / summary: トリアージ自動連鎖の Issue Retrospective。Type=Task・Size=M・Value=3 を確定、post-merge observation AC に `session=next` を追加、タイトルの "pre-merge" 限定表現を除去、ambiguity point 0 件、verify command 5 件を Pattern 1〜6 で監査済み (問題なし) / URL: https://github.com/saitoco/wholework/issues/1186#issuecomment-5199530052

- saito / MEMBER / first-class / ## 追加実測: `/verify 1175` と `/verify 1118` (2026-08-06) / https://github.com/saitoco/wholework/issues/1186#issuecomment-5199747782
## Changed Files
- `skills/verify/SKILL.md`: Step 5 に「already-checked AC skip rule」を追加 (pre-merge)、Step 8a の対象条件を unchecked に限定し同スキップ規則を適用 (post-merge + hint)、Step 6 の「Re-runs」箇条書きを新方針に合わせて書き換え、Step 11(a) の SKIPPED 括弧書きを整合、`## Notes` に Post-merge 重複記載による継続検証運用を追記 — bash 非対象 (Markdown skill 定義ファイル)
- `tests/verify.bats`: already-checked AC skip rule (pre-merge / post-merge+hint) と unchecked AC が従来どおり検証されることを検証するテストを追加

## Implementation Steps

1. `skills/verify/SKILL.md` の `### Step 5: Verify Each Condition (Pre-merge Only)` において、既存の pre-merge-preview AC skip rule 段落 (「...duplicate the AC in the `### Post-merge` section without the `<!-- ac-tier: preview -->` tag; `/verify` will then execute it against `PRODUCTION_URL`...」で終わる段落) の直後、`**Patch route detection (run before verification):**` 段落の直前に、新しい小見出し `**Already-checked AC skip rule (default; applies to every Pre-merge condition):**` を挿入する。内容: 既に `- [x]` になっている Pre-merge AC は検証対象から除外し、note「already checked; skipped by default」を付けて SKIPPED として記録する (verify command は再実行しない)。これは `ac-tier: preview` AC に限らず全 re-run のデフォルト挙動である。`- [ ]` のままの条件は従来どおり Verification priority のステップで処理する。継続的な再チェックが必要なプロジェクトは `### Post-merge` に AC を重複記載する (`## Notes` 参照) — opt-in 再検証フラグは提供しない。あわせて `#### Step 8a: Auto-verify Post-merge Conditions with Hints` の冒頭文を「still `- [ ]` (unchecked)」の条件に限定するよう書き換え、既に `- [x]` の post-merge + hint 条件にも同じ already-checked AC skip rule (SKIPPED, note「already checked; skipped by default」) を適用する一文を追加する。(→ acceptance criteria 1, 2)
2. `skills/verify/SKILL.md` の `### Step 6: Update Pre-merge Checkboxes (Immediate Lock-in)` にある箇条書き `- **Re-runs**: re-verify all conditions (idempotent). Re-verify even if already checked; report via comment if result changes` を、チェック済み (`[x]`) 条件は Step 5/Step 8a の already-checked AC skip rule により既定でスキップされ SKIPPED として報告される (再検証しない) こと、`- [ ]` のままの条件のみ毎回 (再) 検証されることを述べる記述に置き換える。あわせて `### Step 11: Apply Verification Results` の `**(a) All auto-verification target conditions are PASS or SKIPPED...` にある括弧書き `SKIPPED is ignored as environment conditions were unmet` を `SKIPPED is ignored as environment conditions were unmet or the condition was already checked` に拡張し、本 Issue で追加される SKIPPED 理由と既存の環境未充足理由の両方を一貫して説明する。(after 1) (→ acceptance criteria 1)
3. `skills/verify/SKILL.md` 末尾の `## Notes` 箇条書きに、継続的に post-merge で再検証したい条件は既にチェック済み (`[x]`) の条件の再検証に依存せず `### Post-merge` セクションに別の AC として重複記載すべきこと (チェック済み条件は Step 5 / Step 8a により既定でスキップされる) を述べる 1 行を追加する。(parallel with 1, 2) (→ acceptance criteria 3)
4. `tests/verify.bats` に、既存の `step5_section`/`step8c_section` と同じ awk 抽出パターンで `step6_section` (見出し `### Step 6: `) と `step8a_section` (見出し `#### Step 8a: `、終端は次の `#### ` または `### ` 見出し) ヘルパーを追加し、以下を検証するテストを追加する: (a) Step 5 セクションに already-checked AC skip rule の本文と SKIPPED の note 文言が含まれる、(b) Step 8a セクションに post-merge + hint 条件向けの同スキップ規則が含まれる、(c) Step 6 セクションから旧文言「Re-verify even if already checked」が除去され、スキップ既定方針の説明に置き換わっている、(d) Step 5 / Step 8a セクションに unchecked (`- [ ]`) 条件の処理経路の記述が引き続き残っており、「未チェック AC は従来どおり評価される」という回帰カバレッジが確保されている。(after 1, 2) (→ acceptance criteria 4, 5)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/verify/SKILL.md に、チェック済み ([x]) の AC は pre-merge / post-merge を問わず再検証せずスキップする旨が明記されている。現行 Step 6 の 'Re-verify even if already checked' の記述が新方針に沿って更新され、矛盾する記述が残っていない" --> チェック済み AC を pre-merge / post-merge を問わずスキップする方針が SKILL.md に明記されている
- <!-- verify: rubric "スキップされた AC が verify 結果コメントおよびターミナル出力で SKIPPED として理由付きで報告されることが SKILL.md に定められている (silent skip になっていない)" --> スキップが SKIPPED として理由付きで報告される
- <!-- verify: rubric "merge 後も継続検証したい条件は Post-merge セクションに AC を重複記載する運用が SKILL.md または関連ドキュメントに記載されており、opt-in 再検証フラグが導入されていない" --> 重複記載による継続検証の運用が記載され、再検証フラグは導入されていない
- <!-- verify: rubric "tests/ 配下に、チェック済み pre-merge AC と チェック済み post-merge AC の双方がスキップされること、および未チェック AC は従来どおり評価されることを検証するテストが追加されている" --> チェック済み/未チェック双方の経路を検証するテストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge
- 次回 `/verify` 実行時に、チェック済み AC が再実行されず SKIPPED として報告されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **SHOULD-level ドキュメント同期確認**: `docs/workflow.md` (`/verify` の説明行) と `docs/guide/customization.md` (`ac-tier: preview` 関連記述) を確認したが、いずれも「条件は毎回再検証される」という明示的な記述は持っておらず、本変更によるドリフトは発生しない。README.md の `/verify` 言及も高レベルな要約のみで影響なし。更新不要と判断。
- `tests/run-fact-matching.bats` のフィクスチャは post-merge AC が `[x]` チェック済みの場合を run-fact matching スキャン対象外として既にモデル化している (`scan-pending-ac.sh` は unchecked のみ走査する別メカニズム)。本変更と矛盾しないことを確認済み。
- Step 8b (manual) と Step 8c (observation) の post-merge 処理は「For each unchecked post-merge condition」として既に unchecked のみを対象にしているため、今回のスキップ規則は Step 5 (pre-merge) と Step 8a (post-merge + hint) の 2 箇所のギャップを埋めるだけでよい。
- Issue 本文の記述と既存実装 (Step 5 の `ac-tier: preview` 前例、Step 6 の該当行) を照合したが、矛盾は検出されなかった。

## issue retrospective

**Triage (auto-chain)**: `triaged` ラベル未付与だったため triage を自動実行。Type=Task (precedent: #1163 と同系統の retro/verify 起票、既存動作の再分類・最適化に分類)、Priority=未検出、Size=M (SKILL.md 本体 + tests/ 追加分の見積り)、Value=3 (Impact=2: `skills/verify/SKILL.md` は複数 skill から参照される shared component、Alignment=4: product.md Vision の `/verify` post-merge 検証コスト最適化と直接合致)。重複候補・滞留・依存関係の異常は検出されませんでした。

**AC 修正 (session=next 補完)**: Post-merge の observation 条件 `<!-- verify-type: observation event=auto-run -->` に `session=next` を追加しました。本 Issue の Background は `skills/verify/SKILL.md` を変更対象として参照しており、observation 条件は harness の skill キャッシュ特性上、この Issue を処理する会話セッション内では評価不能 (変更が着地した後に開始する次セッションでのみ判定可能) です。`scripts/check-skill-change-observation-ac.sh` による機械チェックで欠落を検出し (exit 2)、規約 (`modules/verify-classifier.md` § observation Type) に従って補完しました。

**タイトル更新 (drift 補正)**: 旧題「verify: チェック済み **pre-merge** AC の再検証を既定でスキップし二重検証コストを削減」は、本文の「方針確定」注記でスコープが pre-merge / post-merge 問わずチェック済み AC 全般に拡張された結果、本文と乖離していました。新題「verify: チェック済み AC の再検証を既定でスキップし二重検証コストを削減」に更新し、"pre-merge" 限定の含みを除去しています。

**ambiguity 判定**: Issue 本文には既に「方針確定 (2026-08-06)」注記で対応方針 A (一律スキップ)・明示フラグ不採用・既存の `ac-tier: preview` スキップ前例との整合が明記されており、新たな ambiguity point は検出されませんでした (Clarification Questions は 0 件)。

**verify command 監査**: 5 件の `<!-- verify: ... -->` を Pattern 1〜6 で監査。`command "bats tests/"` は Pre-merge に配置されていますが、対応する CI job (`test.yml` の `Run bats tests`) が存在し、かつスクリプトが失敗時に非ゼロ exit を返す設計のため Pattern 6-5 (常時 UNCERTAIN) には該当しません。他の 4 件は `rubric` で問題なし。監査コメントの投稿は不要と判断しました (findings なし)。

**Scope Assessment**: non-interactive モードのため sub-issue splitting 評価はスキップしました (Size M のため元々対象外)。

## spec retrospective

### Minor observations
- Nothing to note

### Judgment rationale
- SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) と Step 8 (Uncertainty) はスキップ。トリアージ retrospective で ambiguity point 0 件と既に確認されており、整合する。
- Step 9 (UI Design Phase) は SPEC_DEPTH に関わらず実行対象だが、本 Issue は `/verify` skill 内部ロジックの変更でありインタラクティブ UI 要素を一切含まないため、Figma MCP の可用性確認を行わずに「UI design not needed」と判定してスキップした。Issue 内容から明白に非該当と判断できるケースであり、不要なツール呼び出しを避けた。
- スキップ規則の実装箇所を Step 5 と Step 8a の 2 箇所に絞り込んだ判断根拠: Step 8b/8c は既に "For each unchecked post-merge condition" という文言で unchecked のみを対象にしていることをコード調査で確認済み。Step 4 の分類一覧 (pre-merge/post-merge+hint/no-hint/observation) 自体は変更せず、実際にループ処理を行う Step 5/8a 側にスキップ規則を追加する設計とした — Step 4 は「対象を分類する」役割にとどまり、「対象をどう処理するか」は各 Step の責務であるため。

### Uncertainty resolution
- Nothing to note

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- スキップ規則の実装箇所を Step 5 (pre-merge) と Step 8a (post-merge+hint) の 2 箇所に限定した。Step 8b/8c は既に unchecked のみを対象にしており変更不要と判断した
- 一般規則 (already-checked AC skip rule) と既存の `ac-tier: preview` 固有規則は併存させ、preview 規則を置き換えない設計とした (両者は矛盾せず、preview AC が `[x]` の場合は一般規則が適用されるだけ)
- opt-in 再検証フラグは導入せず、継続検証は Post-merge セクションへの AC 重複記載で表現する方針を Notes に明記した (Issue 本文の確定方針どおり)

### Deferred Items
- Post-merge の observation AC (`event=auto-run session=next`) は本セッション内では評価不能。次回 `/auto` 完了後の `/verify` 実行で SKIPPED 報告を観察する必要がある
- `docs/workflow.md` / `docs/guide/customization.md` は更新不要と判断したが、`/code` 実装時に SKILL.md の文言が固まった時点で念のため再確認が望ましい

### Notes for Next Phase
- `/code` は Implementation Steps 1〜3 (SKILL.md 編集) と Step 4 (bats テスト追加) を、Spec に記載した挿入位置 (段落の文脈で指定、行番号ではない) に従って実装すること
- `tests/verify.bats` に `step6_section`/`step8a_section` ヘルパーを追加する際、既存の `step5_section`/`step8c_section` の awk パターンに厳密に合わせること (見出しレベル `###` vs `####` の違いに注意)
- 新規追加する文言 ("already checked; skipped by default" 等) は Pre-merge verify command (rubric) が期待する語彙と一致させ、SKILL.md 本文とテストで同一の exact phrase を使うこと
