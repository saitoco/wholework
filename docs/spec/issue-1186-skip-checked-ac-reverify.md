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

### code フェーズ (cutoff: 2026-08-06T02:22:36Z)

- login: saito / authorAssociation: MEMBER / trust tier: first-class / summary: 方針 A を裏づける追加実測 2 件 (`/verify 1175`: チェック済み 4 件が全て SKIPPED 相当・新規情報ゼロ、`/verify 1118`: チェック済み AC ゼロのため方針 A の影響を受けず未チェック AC の評価は損なわれない) と、フル bats スイート 3 本同時実行時の負荷観測 (load average 倍増) を記録。設計・実装方針への変更要求はなく、既存の Implementation Steps をそのまま実行すればよい / URL: https://github.com/saitoco/wholework/issues/1186#issuecomment-5199747782
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

## Code Retrospective

### Deviations from Design
- Nothing to note. Implementation Steps 1〜4 は Spec に記載した挿入位置・文言のとおりに実装した。

### Design Gaps/Ambiguities
- Nothing to note. Spec の investigation (Step 5/8a への限定、Step 8b/8c 対象外の確認) がそのまま実装に反映された。

### Rework
- Nothing to note. Rubric verify command 4 件と `bats tests/` はいずれも初回実装で PASS した。

## review retrospective

### Spec vs. implementation divergence patterns
- `/code` の Notes for Next Phase は「Step 5 の already-checked AC skip rule 文言と Step 8a の追加文が既存の pre-merge-preview AC skip rule と矛盾なく併存しているかを確認すること」を明示的に依頼しており、`/review` (review-light agent) がまさにこの点を検証した結果、実装は機能的には矛盾していない (両ルールとも同じ SKIPPED 結果に収束する) が、Spec の Overview (13行目) に書かれていた「preview 規則を置き換えない設計」という優先関係の説明が SKILL.md 本文には転記されていなかった、という CONSIDER レベルのドキュメント明確性ギャップを検出した。Spec に書いた設計意図が実装ファイル本体まで一貫して伝播しているかを確認する Notes for Next Phase の運用が機能した好例。review 中に一文追記して解消済み

### Recurring issues
- Base Branch Conflict Pre-check (`git merge-tree`) が、本 Spec ファイル自身に対する base (main) 側との "changed in both" 競合を検出した。原因は、姉妹コミット (`aa416dfe Add consumed comments fallback for issue #1186 (code phase)`) が同一 Issue #1186 の同じ Consumed Comments 段落に、別セッションから低品質な fallback 形式で追記していたこと。本 PR ブランチ側は同じソースコメントをより完全な形式 (見出し付きサブセクション) で既に記録していたため内容欠落はなく MUST 化は不要と判断したが、同一 Issue に対して複数セッション (fallback 投稿スクリプトと通常の `/code` セッション) が並行して Spec の同じ段落へ書き込みうる構造自体は、他 Issue でも再発しうるパターンとして記録しておく

### Acceptance criteria verification difficulty
- Nothing to note. rubric 4 件・`command "bats tests/"` 1 件のいずれも曖昧さや verify command の不備なく PASS 判定できた。`command "bats tests/"` は safe mode のため CI 参照フォールバック (`Run bats tests` job SUCCESS) で判定した

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- review-light agent (4観点統合) を実行し、CONSIDER 1件 (Step 5 の already-checked AC skip rule と既存 pre-merge-preview AC skip rule の優先関係が SKILL.md 本文で未明記) を検出・修正した。MUST/SHOULD はゼロ
- Base Branch Conflict Pre-check で本 Spec ファイル自身の base 側競合を検出したが、内容欠落なしと判断し MUST 化しなかった (詳細は review retrospective 参照)
- Pre-merge の 5 条件は Issue body で既に `[x]` だったが、`/review` Step 8 は `/code` の判定を独立に再検証し (rubric 4件を SKILL.md 本文の直接確認で、`command "bats tests/"` を CI 参照フォールバックで)、いずれも PASS を確認した

### Deferred Items
- Post-merge の observation AC (`event=auto-run session=next`) は本セッション内では評価不能。次回 `/auto` 完了後の `/verify` 実行で SKIPPED 報告を観察する必要がある (未着手のまま持ち越し)

### Notes for Next Phase
- `/merge` では通常の pre-merge AC gate に加え、`docs/spec/issue-1186-skip-checked-ac-reverify.md` の base 側競合 (Consumed Comments 段落の重複) が実際の `git merge`/squash merge で問題を起こさないか (fast-forward 前提が崩れていないか) を確認すること
- `/verify` の次回実行 (session=next) で、post-merge observation AC が SKIPPED として正しく報告されるかを観察すること

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` triage が 2 点の drift を自動補正した。(1) `check-skill-change-observation-ac.sh` が exit 2 で欠落を検出し post-merge 条件に `session=next` を補完、(2) タイトルの「pre-merge AC」限定表現を、本文の方針確定注記でスコープが拡張されていたことに合わせて「AC」全般へ更新。**起票時点で本文とタイトルの間に生じた drift を、実装が始まる前に triage が吸収した事例**

#### spec
- 調査でスキップ規則の追加箇所を Step 5 と Step 8a の 2 箇所に絞り込み、Step 8b/8c は既に unchecked のみを対象としているため変更対象外と判定した。この絞り込みが正確だったため実装に手戻りが発生していない
- 既存の `ac-tier: preview` skip rule という前例と併存させる設計にしたことで、新しい概念を導入せずに済んでいる

#### code
- 手戻りゼロ。rubric 4 件と `bats tests/` がいずれも初回実装で PASS

#### review
- `/code` の Notes for Next Phase が「両 skip rule が矛盾なく併存しているか確認せよ」と明示的に依頼し、`/review` がまさにその点で CONSIDER 1 件を検出した。**Spec に書いた設計意図が実装ファイル本体まで転記されているかを次フェーズに申し送る運用が機能した好例**
- `/review` Step 8 は pre-merge 5 条件を独立に再検証している。本 Issue が止めたのは `/verify` 側の再検証であり、merge 前ゲートである `/review` での検証は責務として妥当 — 二重になっていたのは `/verify` 側だったという整理が実行結果からも裏付けられた

#### merge
- 特記事項なし。base 側競合は内容欠落なしと判断され MUST 化されず、squash merge も問題なく完了

#### verify
- **本 Issue が導入したルールを、本 Issue 自身の verify が最初に適用した。** Pre-merge 5 件すべてが SKIPPED ("already checked; skipped by default") となり、`command "bats tests/"` の再実行 (1400+ テスト) が回避された。直前に同一セッションで実行した `/verify 1157` (旧ルール) は 6 件を全て再実行し、うち `bats tests/` 1405 件を含めて新規情報ゼロだった — 両者の対比が本 Issue の効果の実測値になっている
- **skill 自己更新の非伝播が本 Issue でも発生した**。本 verify を実行したセッションにロードされていた `skills/verify/SKILL.md` は変更前の旧版 (Step 6 に `Re-verify even if already checked` が残る) だった。ただし `/issue` triage が `session=next` を自動補完していたため、post-merge 条件は次セッション評価として扱われ、#1157 の条件 7 が陥った「UNCERTAIN のまま永久滞留」の構造は回避されている。**#1168 が導入した仕組みが、#1157 と同型の状況で実際に機能した初めての事例**
- 本実行では、ロード済み旧版ではなく main に着地した新ルール (`9ccba45d`) を直接読んで適用した。LLM-native prose skill の自己更新非伝播に対する実務上の回避策として機能したが、これは実行者が非伝播を認識していた場合にのみ成立する

### Improvement Proposals

- **Tier 2 (convention — memory 提案)**: `append-consumed-comments-section.sh` の deterministic fallback が、通常の `/code` / `/verify` セッションが既に記録した `## Consumed Comments` 段落へ**重複して簡易形式で追記する**。本 Issue では姉妹コミット `aa416dfe` がこれを引き起こし、`/review` の Base Branch Conflict Pre-check が Spec ファイル自身の "changed in both" 競合として検出した (内容欠落はなく MUST 化は不要と判断された)。#1157 の Spec でも同じ重複が発生している (詳細形式 1 件 + 簡易形式 4 件の併存)。同一 Issue に対して fallback スクリプトと通常セッションが並行して同じ段落へ書き込みうる構造自体は他 Issue でも再発する
  - **Tier 2 とした判断根拠**: 実害は現時点で「Spec の可読性低下」と「conflict pre-check のノイズ」に留まり、内容欠落は発生していない。fallback は LLM がセクションを書き忘れた場合の安全網として機能しており、冪等性チェック (既に記録済みなら追記しない) を足せば済む単一箇所の修正。`modules/retro-proposals.md` の新デフォルト (判断が難しい場合は Tier 2) にも合致する

## Auto Retrospective

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | — | SUCCESS | Size M 設定、`session=next` 補完、タイトル drift 補正 |
| spec | pr | SUCCESS | |
| code | pr | SUCCESS | PR #1190。**`code_retry_fire` 2 回 (`trigger_reason=silent_no_op`)** を経て成功 |
| review | pr (`--light`) | SUCCESS | CONSIDER 1 件検出・修正、CI 全 SUCCESS |
| merge | pr | SUCCESS | **watchdog kill されたが `Exit code: 0`、PR は実際に MERGED** |
| verify | — | SUCCESS | 全 6 条件 SKIPPED |

### Orchestration Anomalies

- **`merge` フェーズが watchdog に kill されたにもかかわらず `Exit code: 0` で成功扱いになった**。`.tmp/auto-events.jsonl` に `{"ts":"2026-08-06T03:54:14Z","issue":1186,"event":"watchdog_kill","pr":1190,"phase":"merge","pid":"96898","silent_window_sec":"600","timeout_setting":"600"}` が記録されており、wrapper ログにも `watchdog: no output for 600s, killing process (pid=96898)` と `watchdog: retrying disabled; please re-run the skill manually` が残っている。それでもログ末尾は `Exit code: 0` で、`reconcile-phase-state.sh merge --check-completion` は `pr_state: MERGED` を返した。**merge 自体は kill 前に完了しており実害はなかった**が、「kill されたのに成功扱い」という状態は設計上の想定と異なる
  - **#1140 の post-merge 条件に対する反証データ**: #1140 ac4 は「次回以降の `/auto` 実行で、正常終了したフェーズに対して `watchdog_kill` イベントが新規追加されていないことを確認する」を要求している。本 run では**正常終了した merge フェーズに対して watchdog_kill が新規追加された**。#1140 の `/verify` 時にこの実測データを参照すべき
  - **#939 (watchdog silent window の実測と再校正) にも該当**: merge フェーズの既定 timeout は 600s (`WATCHDOG_TIMEOUT_MERGE_DEFAULT`)。CI 待ちを含む merge が 600s 無言になるのは異常ではなく、既定値が実測に対して短い可能性を示す
- **`code` フェーズで `code_retry_fire` が 2 回発火した** (02:36:12 iteration=1、02:50:17 iteration=2、いずれも `trigger_reason=silent_no_op`)。最終的に PR #1190 が作成され completion check も通ったため実害はないが、silent no-op 検出とリトライが 2 回連続で必要だった点は #1117 / #1175 の扱う領域と重なる

### Improvement Proposals

- N/A — 上記 2 件はいずれも既存 Issue が追跡中 (#1140 / #939 / #1117 / #1175)。本 run の実測データは各 Issue の判断材料として有効だが、新規起票は不要
