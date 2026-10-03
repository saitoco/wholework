# Issue #1480: verify: 定量的改善を問う observation AC にベースラインと最小サンプル数の明記を必須化する

## Overview

率・割合・頻度の「改善」を問う observation 型 AC は、比較対象のベースライン値とその測定元、および判定に必要な最小サンプル数が条件文自身に書かれていないと、原理的に PASS/FAIL を判定できない。実例は #1350: 追加した evidence source は実際に機能した (#1329 では決定的証拠となり PASS) が、修正前の UNCERTAIN/SKIPPED 率が記録されておらず、何件観測すれば「改善」と判定してよいかの閾値も無く、修正後サンプルが n=2 だったため、AC 全体は UNCERTAIN に留まった。

本 Issue は AC を書く側のガイダンスを補強する (`/verify` の判定ロジックや scripts は変更しない):

1. `modules/verify-classifier.md` の observation 型の記述に、定量的改善を問う条件はベースライン値 (測定元つき) と最小サンプル数を条件文自身 (または `Expected output structure` sub-bullet) に含めることを必須とする要件を、新設節として追加する。既存の `### observation Type: Population Definition for Numeric Conditions` (集計値の母集団を明記する要件) とは重複させず、その直後に隣接配置して参照のみ行う
2. 同節に、ベースラインを測定できない場合の代替形 (率・割合の改善ではなく、evidence source が参照されたことのような単発観測に落とす) を併記する
3. AC を生成する `skills/issue/SKILL.md` の該当ステップ (New Issue Creation Step 4 の verify-type タグ付与ブロック) に同要件を反映する。Existing Issue Refinement の Step 7 は Step 4 の手順を丸ごと参照するため、Step 4 側の変更で両フローをカバーする

## Changed Files

- `modules/verify-classifier.md`: `### observation Type: Population Definition for Numeric Conditions` の直後、`### observation Type: Firing Likelihood Check (before assignment)` の直前に、新規 `### observation Type: Baseline and Minimum Sample Size for Quantitative Improvement Conditions` を追加 (内容は Implementation Steps 1 と Notes「挿入文案ドラフト」)
- `skills/issue/SKILL.md`: Step 4 の `**AC authoring convention — evaluator self-sufficiency:**` 段落末尾の参照リストに新節名を追加し、`**Firing likelihood check (before assigning `observation`):**` 段落の直後に新規段落 `**Baseline and minimum sample size check ...**` を追加 (内容は Implementation Steps 2 と Notes「挿入文案ドラフト」)
- 以下は Steering Docs sync candidate 確認の記録 (件数はすべて `grep -rl "<keyword>" docs/ tests/ scripts/ modules/` の結果。`docs/spec/` と `docs/sessions/` を含み、本 Spec 自身は除く。2026-10-03 実測):
  - [Steering Docs sync candidate] keyword "verify-classifier.md" skipped: matched 135 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "Firing Likelihood" skipped: matched 9 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "issue" (`skills/issue/SKILL.md` 由来の bare skill name) skipped: 裸のスキル名は識別力なし。本 Issue が導入する節名は実装前のため他ファイルに存在せず、兄弟節名 (次の行) で代替した
  - [Steering Docs sync candidate] keywords "Population Definition" (3 files) / "Evidence Collection Patterns" (3 files): ヒットは `modules/verify-classifier.md` 自身と、使い捨ての履歴である `docs/spec/issue-1251-*.md` / `docs/spec/issue-1350-*.md` / `docs/spec/issue-1391-*.md` (Consumed Comments の 1 行) のみ。Changed Files 以外の追加候補なし
  - [Outbound pointer sync candidate] 変更ファイル自身が指す参照先を確認: `modules/verify-classifier.md` の追加節は同ファイル内の Population Definition / Firing Likelihood Check 節と `skills/verify/SKILL.md` Step 8c (SKIPPED の扱い) を指す。Step 8c は変更しない方針 (Notes「最小サンプル数未満の判定を SKIPPED とする根拠」参照)。`skills/issue/SKILL.md` の追加段落が指す `modules/verify-classifier.md` は Changed Files に含まれる。追加候補なし

## Implementation Steps

1. `modules/verify-classifier.md`: `### observation Type: Population Definition for Numeric Conditions` の最終段落 (`**When an aggregate count cannot be avoided**: ...`) の直後、`### observation Type: Firing Likelihood Check (before assignment)` の直前に、新規節 `### observation Type: Baseline and Minimum Sample Size for Quantitative Improvement Conditions` を挿入する。内容 (英語のみ。CJK 文字を含めない — Notes「言語規約」参照):
   - 導入: 率・割合・頻度の改善を問う observation 条件は、比較用の入力を条件文自身 (または `Expected output structure` sub-bullet) に書くことを必須とする。評価者が後から再構成することを前提にしない
   - 要件 (a) **Baseline value and its measurement source**: 変更前の比較対象値と、その測定元 (記録しているログ・レポート・Issue) および走査範囲。ベースラインと変更後の観測は同一母集団で測る (上の Population Definition を参照)。設計の材料にしただけで率を算出・記録していないデータはベースラインではない
   - 要件 (b) **Minimum sample size**: 判定してよい変更後観測数の最小値 (「十分な件数」ではなく具体的な数。想定される event の発生頻度で到達できる値を選ぶこと — 到達不能な最小値は恒久的な SKIPPED を生み、直後の Firing Likelihood Check が防ごうとしている失敗と同型になる)、およびそれ未満の間の判定 (PASS/FAIL にせず SKIPPED = サンプル待ち。`/verify` Step 8c が未発火 event を SKIPPED とするのと同じ扱い)
   - 参考事例として #1350 (追加 evidence source は機能したが、修正前の率が未記録・閾値が未定義・修正後 n=2 のため UNCERTAIN のまま) を 1 文で記載する
   - 代替形: ベースラインが測定できない場合 (修正前の率が記録されておらず、今から再構成もできない) は「率・割合が改善する」条件を書かず、ベースライン不要で証拠を記述できる単発観測 (例: 追加した evidence source が次回の `/verify` observation dispatch で実際に参照されたこと) に落とす。単発観測にしても直後の Firing Likelihood Check (どの `event=<name>` の発火が証拠を供給し、証拠が何か) は通すこと。通せない場合は同節の alternatives (resolve now / `auto` へ変更 / drop) に従う
   - verify command のための文言要件: 本文に小文字の `minimum sample size` を含める (`grep "[Mm]inimum sample"` は大文字小文字を区別するため、見出しの `Minimum Sample Size` だけでは一致しない)。単発観測の代替形には `evidence source` と `single-shot` の語を含める (→ 受入条件 AC1, AC2, AC3)
2. `skills/issue/SKILL.md` (after 1):
   - (a) Step 4 の `**AC authoring convention — evaluator self-sufficiency:**` 段落末尾の `(Population Definition for Numeric Conditions, Firing Likelihood Check)` を `(Population Definition for Numeric Conditions, Baseline and Minimum Sample Size for Quantitative Improvement Conditions, Firing Likelihood Check)` に更新する (節名の列挙が実際の節構成とずれるのを防ぐ)
   - (b) 同 Step 4 の `**Firing likelihood check (before assigning `observation`):**` 段落の直後、`**Skill self-update propagation check:**` の直前に、新規段落 `**Baseline and minimum sample size check (before assigning `observation` to a rate, proportion, or frequency improvement condition):**` を追加する。内容: 条件文 (または `Expected output structure` sub-bullet) にベースライン値とその測定元、および最小サンプル数を書くことを求め、ベースラインを測定できない場合は単発観測に落とす旨を述べ、SSoT である `modules/verify-classifier.md` § observation Type: Baseline and Minimum Sample Size for Quantitative Improvement Conditions を参照する。小文字の `baseline` を含めること (→ 受入条件 AC4, AC5)
   - Existing Issue Refinement Step 7 は Step 4 の手順を丸ごと参照しているため追加変更は不要 (grep 確認済み: `skills/issue/SKILL.md` line 516)。半角 `!` を使わない (`validate-skill-syntax.py` の制約)
3. 自己検証と全体テスト (after 2): 実装後に AC の verify command を手元で空撃ちする — `grep "[Mm]inimum sample" modules/verify-classifier.md` と `grep "baseline" skills/issue/SKILL.md` がそれぞれ 1 件以上ヒット (実装前はどちらも 0 件)。続けて `python3 scripts/validate-skill-syntax.py skills/`、`git diff -- skills/ modules/ | python3 scripts/check-language-convention.py`、変更ファイルに対する `scripts/check-forbidden-expressions.sh` 相当の確認、`bats tests/` 全件 PASS を確認する (→ 受入条件 AC2, AC5, AC6)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/verify-classifier.md の observation 型の記述に、率・割合・頻度など定量的改善を問う条件はベースライン値 (と測定元) および最小サンプル数を条件文自身に含めることを必須とする要件が追加されている" --> observation 型の記述に定量的改善条件への要件が追加されている
- <!-- verify: grep "[Mm]inimum sample" "modules/verify-classifier.md" --> 当該記述に最小サンプル数への言及がある (実装前の main には存在しない語で検証する)
- <!-- verify: rubric "modules/verify-classifier.md の observation 型の記述に、ベースラインを測定できない場合の代替形として、率・割合の改善ではなく単発観測 (例: evidence source が参照されたこと) に条件を落とす選択肢が併記されている" --> ベースラインが測定できない場合の代替形 (「率」ではなく evidence source が参照されたことのような単発観測に落とす) が併記されている
- <!-- verify: rubric "skills/issue/SKILL.md の AC 生成に関する記述が、定量的改善を問う observation AC についてベースラインと最小サンプル数の明記を求める形になっているか、modules/verify-classifier.md の当該要件を参照している" --> `skills/issue/SKILL.md` にも同要件が反映されている
- <!-- verify: grep "baseline" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の当該記述がベースラインに言及している
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge
- 本 Issue の merge 後に起票または整備された Issue のうち、率・割合・頻度の改善を問う observation AC について、ベースラインと最小サンプル数が条件文に含まれることを観察する (証拠源: merge 日以降に作成・更新された Issue の本文を `gh issue list --search` で走査する) <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - 新規生成された observation AC のうち率・割合・頻度を問うものに、比較対象のベースライン値とその測定元が明記されていること
    - 判定に必要な最小サンプル数が明記されていること
    - 該当する AC が生成されなかった場合は SKIPPED (観測機会なし) として扱われること

## Notes

- **隣接ケース (#1351: event 種別と実際のトリガの不一致) の扱い — 本 Issue のスコープ外と判断 (非対話モードでの自動解決)**: Issue 本文と 2026-09-18 のコメントが判断を `/spec` に委ねている。分割 (スコープ外) を選んだ理由は 3 点。(1) 3 つの「観測不能型」は要求する対策が異なる (フェーズ再配置 = #1474 / 測定基準の明記 = 本 Issue / event 種別の選定規約 = #1351 型) うえ、本 Issue の Pre-merge AC 6 件は測定基準の明記だけを検証しており、選定規約を足すと AC の対象外の変更が混ざる。(2) #1351 型の失敗は、既存の Firing Likelihood Check を形式上は通る (証拠は「backlog 件数の減少」と記述できる) が、待っている事象 (人手による `/loop` 起動) と `event=auto-run` の発火源が対応していない点にあり、Event Values 表の運用規約を新設する別設計になる。実装が `scripts/opportunistic-search.sh` の KNOWN_EVENTS (`scripts/check-known-events-firing.sh` が整合を検査) に及ぶ場合は、文書のみの規約追加と新 event 追加 (コード) を分けて検討する必要がある。(3) Issue 本文の Out of scope が既に除外を明記している。**別 Issue は本 `/spec` 実行では起票していない**: `/spec` は Issue を起票しない運用 (Issue 作成は `/issue` の責務で、手順上も改善提案は `/verify` が集約する) であり、本実行は他スキルを呼び出さない前提のため。必要であれば起票者が `/issue` で起票する。下書き — タイトル案: `verify: observation AC の event 種別と実際のトリガの対応を検証する選定規約を追加する`。要点: #1351 の post-merge AC は人手による `/loop` 起動を待っているのに `event=auto-run` を付けており、`/auto` が走るたびに再評価されて SKIPPED が続く (2026-09-18 時点で `/loop /audit verify-backlog` の実行痕跡ゼロ)。待っている事象と event の発火源が一致することを AC 作成時に確認する規約を、`modules/verify-classifier.md` と `skills/issue/SKILL.md` に追加する (本 Issue と同じ 2 ファイルが中心になる見込み)
- **新節の配置**: Population Definition の直後、Firing Likelihood Check の直前に置く。Issue 本文の「既存の § Population Definition とは重複させず隣接する形で書く」に従い、論理順 (母集団の明記 → ベースラインと最小サンプル数 → 割り当て前の事前チェック) にも合う。Population Definition には既に例示として `baseline of N` の語があるが、あちらは「集計値の母集団を明記する」要件であり、比較対象の測定元・最小サンプル数は扱わない。本節では母集団の一致 (ベースラインと変更後観測を同じ母集団で測る) を述べる際に Population Definition を参照するだけに留める
- **最小サンプル数未満の判定を SKIPPED とする根拠**: `skills/verify/SKILL.md` Step 8c の Judgment は「証拠が不十分または曖昧 = UNCERTAIN」「観測対象の前提が成立していない = SKIPPED」を区別している (未発火 event も SKIPPED)。UNCERTAIN だと Step 11 (d) の手動再確認の促しが発生するが、サンプルの蓄積待ちは構造的に今は解決できない状態であり、未発火 event と同型の「前提未成立」として SKIPPED が妥当 (Step 11 (a) では SKIPPED は無視される)。Step 8c 自体は変更しない: 条件文が自身の判定を明記する (evaluator self-sufficiency) ので、既存の SKIPPED 規則で足りる。Step 8c に「条件文が最小サンプル数を宣言していれば SKIPPED」と明記する案は評価側の改善で、本 Issue の Scope (AC 作成側) の外であり、`skills/verify/SKILL.md` は `skill-body-sha` マーカーの更新も伴うため見送った
- **verify command の存在確認 (文字列照合系)**: `grep "[Mm]inimum sample" "modules/verify-classifier.md"` は実装前の main で 0 件 (`grep -c` の実測、2026-10-03、`modules/verify-classifier.md` 全体)、`grep "baseline" "skills/issue/SKILL.md"` も 0 件 (同、`skills/issue/SKILL.md` 全体)。どちらも実装が導入する文字列であり常時 PASS ではない。`grep` は大文字小文字を区別するため、AC2 は小文字 `minimum sample size` (または `Minimum sample size`) を本文に含める必要がある (見出しの `Minimum Sample Size` は `sample` が大文字で不一致)。Triage の AC 監査 (2026-10-02) が指摘した「常時 PASS の grep」は、`/issue` が AC2 を `[Mm]inimum sample` に差し替え済みで解消している
- **Pre-merge 検証項目数**: 6 件で、`/spec` の light 上限 (5 件) を 1 件超える。verify command 同期規則 (Issue 本文からの逐語コピー) と件数整合チェックを優先して 6 件のまま維持する。意図的な逸脱 (先例: `docs/spec/issue-1063-agent-effort-frontmatter.md`)。Implementation Steps は 3 件で上限内
- **Size は S を維持 (patch route)**: Changed Files は 2 ファイル (Axis 1 = S)。SKILL.md と modules は実行される指示そのものなので「文書のみ変更」の減算は適用しない。`ALWAYS_PR=false` (`.wholework.yml` に `always-pr` 無し) のため patch route。Pre-merge に `github_check "gh pr checks"` は無く、patch route 向けの書き換えは不要
- **言語規約**: `skills/` と `modules/` は英語のみ (CI の `language-convention` ジョブ、`scripts/check-language-convention.py`)。追記は CJK 文字を含めない。Spec 本文 (日本語) 内の英語ドラフトは対象外。禁止表現 (`scripts/check-forbidden-expressions.sh`) は `docs/spec/` も走査するため、旧称 (廃止済み用語) を Spec にも追記文にも書かない。`SKILL.md` 本文では半角 `!` を使わない
- **同期確認済み (変更不要)**: (a) `docs/ja/*`: Changed Files に `docs/` 直下の `.md` が無いため `docs/translation-workflow.md` の同期対象外。(b) `docs/structure.md` line 111 の `modules/verify-classifier.md` 説明 (post-merge 条件の検証可能性分類) は役割が変わらないため変更不要。(c) `docs/guide/` と `docs/workflow.md` の `observation` 言及は設定キー (`observation-dispatch-threshold`) とフェーズ遷移の説明のみで、AC の書き方は扱わない。(d) `skills/verify/SKILL.md` line 446 の参照は `Evidence Collection Patterns` 節のみで、節名の列挙ではない。(e) allowed-tools impact chain check: 追加文は `scripts/*.sh` のパスを参照しないためゲート不成立 (対応不要)。(f) テスト: `tests/issue.bats` / `tests/xl-decomposition.bats` / `tests/verify-executor.bats` は既存文字列の `grep -q` が中心で、本変更は追記のみのため影響しない。文書のみの追記で新規分岐ロジックが無いため、新規 bats テストは追加しない (AC6 の `bats tests/` は回帰確認)
- **#1474 との関係**: #1474 (open、Spec 未作成) の変更対象は `skills/triage/skill-dev-verify-audit.md` と `skills/issue/SKILL.md` Step 15 (AC 検証コマンド監査) で、本 Issue の編集箇所 (Step 4 の verify-type タグ付与ブロック) とは別領域。同一ファイルへの追記だが競合の可能性は低く、patch route の push 時に rebase が必要になれば `worktree-merge-push.sh` のフォールバックが処理する
- **Post-merge AC について**: Issue 本文のまま (observation、`event=auto-run session=next`)。`skills/issue/SKILL.md` を変更するため `session=next` が必要で、付与済み。Firing Likelihood Check は `/issue` 側で通過済みで、該当 AC が 1 件も生成されない場合に SKIPPED のままとなる残余リスクは Issue Retrospective に記録済み。この AC 自体は率の改善を問わないため、本 Issue が追加する要件の対象外
- **コメント消費の cutoff (再実行時の扱い)**: cutoff は `phase/issue` ラベル付与 (2026-10-03T00:10:15Z) とした。SKILL.md Step 2 が「直近の `phase/issue` ラベル付与」と明記しているためで、本実行は前回の `/spec` 試行 (同日 00:14:20Z に `phase/spec` を付与済み) の再実行にあたる。手順の一般則どおり「直近の `phase/*` ラベル付与」を取ると cutoff が 00:14:20Z になり、本 Spec が実際に依拠している Issue Retrospective コメント (00:11:46Z) が対象外となって記録が消える。`## Consumed Comments` には cutoff 以降のコメント (Issue Retrospective の 1 件) のみ記録する。cutoff より前の 2026-09-18 の隣接ケース提起コメントと 2026-10-02 の triage AC 監査コメントは `/issue` で消費済みで、前者は `/spec` への判断委任を含むため上記 Notes の判断に反映し、後者は `/issue` による AC2 差し替えの経緯として確認した
- **前回試行の残骸 (stale worktree) の再利用**: Worktree Entry 時点で `.claude/worktrees/spec+issue-1480` が既に存在し、前回の `/spec` 試行 (ロック所有 pid 246538) が未コミットの Spec 草稿を残していた。ロック所有 pid の消滅、worktree を cwd とするプロセスの不在、`run-auto-sub.sh 1480` → `run-spec.sh 1480` が再ディスパッチ済みで他に 1480 を扱うラッパーが無いことを確認して stale と判断した。草稿は本フェーズの成果物そのもので、追跡対象の差分も branch 独自のコミットも無かったため、破棄せず再利用した。草稿の主張 (挿入位置、実装前の grep ヒット件数、参照箇所の網羅性、`skill-body-sha` の対象範囲、Step 8c の判定規則、先例 Spec の存在など) は実コードに対して再検証したうえで確定している。草稿からの変更は 2 点: Steering Docs sync 記録のヒット対象の訂正 (issue-1391 の追記) と、最小サンプル数の到達可能性に関する指針の追加
- **挿入文案ドラフト** (`/code` は趣旨と必須語を保てば文言を調整してよい。英語・ASCII のみ):

  `modules/verify-classifier.md` に挿入する節:

  ```markdown
  ### observation Type: Baseline and Minimum Sample Size for Quantitative Improvement Conditions

  When an observation condition asks whether a rate, proportion, or frequency **improved** (e.g., "the UNCERTAIN/SKIPPED rate improves", "fewer retries per run than before"), it cannot be judged PASS or FAIL unless the comparison inputs are written into the condition text itself — or into its `Expected output structure` sub-bullet — rather than reconstructed by the evaluator later. Both of the following are **required**:

  1. **Baseline value and its measurement source**: the pre-change value the post-change rate is compared against, and where it was measured — the log, report, or Issue that records it, plus the scan scope it was computed from (and, when the measurement is reproducible, the command that produced it). The baseline and the post-change observation must cover the same population (see Population Definition above). Raw data that was only the material for designing the change is not a baseline unless a rate was actually computed from it and recorded.
  2. **Minimum sample size**: the smallest number of post-change observations at which the condition may be judged, stated as a concrete number rather than "enough samples", and the verdict while fewer samples exist. State `SKIPPED` (waiting for more samples) rather than PASS or FAIL — the same treatment `/verify` Step 8c gives an event that has not fired yet. Choose a number the expected event rate can actually reach: an unreachable minimum turns the condition into a permanent SKIPPED, the same failure the Firing Likelihood Check below guards against.

  Without both, a change that demonstrably works can still leave the condition unresolvable. Reference incident (Issue #1350): the added evidence source was actually used and produced a PASS for one of the two dispatched conditions, but "the UNCERTAIN/SKIPPED rate improves" stayed UNCERTAIN — no pre-change rate had been recorded, no sample-size threshold was defined, and only n=2 post-change samples existed.

  **When the baseline cannot be measured** (no pre-change rate was recorded and it cannot be reconstructed now): do not write a rate or proportion improvement condition. Reduce it to a single-shot observation whose evidence can be described without a baseline — e.g., "the added evidence source is actually referenced in the next `/verify` observation dispatch". The single-shot form must still pass the Firing Likelihood Check below (which `event=<name>` firing supplies the evidence, and what that evidence is); if it cannot, use that check's alternatives (resolve now, fall back to `auto`, or drop the condition).
  ```

  `skills/issue/SKILL.md` に追加する段落:

  ```markdown
  **Baseline and minimum sample size check (before assigning `observation` to a rate, proportion, or frequency improvement condition):**

  Before tagging such a condition `verify-type: observation`, apply `modules/verify-classifier.md` § observation Type: Baseline and Minimum Sample Size for Quantitative Improvement Conditions — the condition text (or its `Expected output structure` sub-bullet) must state the baseline value with where it was measured, and the minimum sample size at which the condition may be judged. If no baseline can be measured, do not write the improvement condition: reduce it to a single-shot observation (e.g., "the added evidence source is actually referenced in the next dispatch") as that section describes.
  ```

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (/issue フェーズの判断: 隣接ケース #1351 の Out of scope 化、AC2 の grep 差し替え、代替形 AC の追加、Post-merge AC の証拠源追記) / https://github.com/saitoco/wholework/issues/1480#issuecomment-5963470410

## Code Retrospective

### Deviations from Design
- なし。Notes の挿入文案ドラフトをほぼそのまま採用した (新節は `modules/verify-classifier.md` の Population Definition 直後、`skills/issue/SKILL.md` は Step 4 の参照リスト更新と新規段落)。

### Design Gaps/Ambiguities
- 実行環境に `bats` が未インストールで、Step 9 の `bats --jobs 4 tests/` (AC6) を実行できなかった。変更は文書の追記のみで、`tests/` に置換した文字列 (`SKILL.md` line 178 の括弧内の節名列挙) を assert するものが無いことを grep で確認した。AC6 のチェックボックスは未チェックのまま `/verify` に委ねる。
- `validate-skill-syntax.py` (0 error)、`check-language-convention.py` (exit 0)、`check-forbidden-expressions.sh` (exit 0) は PASS。AC2 / AC5 の grep は実装前 0 件 → 実装後各 1 件で、空撃ちで PASS を確認した。

### Rework
- なし。

## Phase Handoff

<!-- phase: code -->

### Key Decisions
- 挿入文案ドラフトの趣旨と必須語 (`minimum sample size` / `single-shot` / `evidence source` / `baseline`) を保ったまま採用し、`/verify` Step 8c は変更しなかった。

### Deferred Items
- AC6 (`bats tests/` 全件 PASS) は実行環境に `bats` が無く未検証。`/verify` または CI で確認が必要。

### Notes for Next Phase
- 変更は `modules/verify-classifier.md` と `skills/issue/SKILL.md` の追記のみ (patch route、`closes #1480` 付きコミット)。
- rubric 型 AC (1, 3, 4) は差分の目視確認では満たしているが、`/verify` での機械判定は未実施。
