# Issue #515: verify: SKILL.md・モジュール群のコンテキスト規模を削減し tool call parse 失敗を抑制

## Overview

`/verify` 実行中に `The model's tool call could not be parsed (retry also failed).` が頻発している。このエラーは累積コンテキストが大きいときと tool 引数が複雑なときに発生確率が上がり、`/verify` は両条件を満たしやすい。

本 Issue の中核（対応方針 A・必須）は、`skills/verify/SKILL.md` 最大の塊である **Step 11（検証結果の適用）の OPEN/CLOSED 分岐の重複解消**である。現状 Step 11 は「When Issue is CLOSED」(L396–462) と「When Issue is OPEN」(L464–526) がほぼ同一の大ブロック（PASS/FAIL/PENDING/UNCERTAIN 判定 + iteration counter 処理、合計約 132 行）を二重に持っている。これを Issue state でパラメータ化し、判定ロジックを一度だけ記述する形へ統合して重複を解消する（移設ではなく dedup）。

補助的改善 B〜D（遅延ロード徹底・冗長散文の圧縮・大きな tool 引数の分割）は Issue 上で「必須ではない」と明記されており、本 Spec では中核 A に集中し B〜D はスコープ外とする（Notes 参照）。

### 採用アプローチ: 共有モジュール抽出ではなく「同一ファイル内 state パラメータ化」

Issue の Auto-Resolved Ambiguity（抽出先モジュール名は例示・実装者が in-file dedup を選択可能）に従い、本 Spec では **`skills/verify/SKILL.md` 内での state パラメータ化（in-file dedup）** を採用する。判断根拠は Notes「Auto-Resolve Log」を参照。要点:

- Step 11 は条件分岐ではなく `/verify` で**常に到達**する中核処理。新規モジュールへ抽出しても Step 11 到達時に必ず Read されるため peak context は減らず、モジュールの定型ヘッダ（Purpose/Input/Output）分むしろ増える。in-file dedup（約 132 行 → 約 66 行）が peak context を最小化し、本 Issue の主目的に最も適う。
- 先例 `modules/phase-state.md`（#438）は**複数 caller**（reconcile スクリプト + `/auto`）で共有されるため module 化が妥当。Step 11 のロジックは caller が `/verify` のみの単一利用であり、`skill-dev-checks.md` の「2 つ以上の skill で使う場合に module 抽出」基準にも合致しない。
- 変更ファイルが `skills/verify/SKILL.md` 1 ファイルに収まり、`docs/structure.md` のモジュール数・一覧や `docs/ja/structure.md` ミラー更新が不要となり低リスク。

## Changed Files

- `skills/verify/SKILL.md`: Step 11 の「When Issue is CLOSED」「When Issue is OPEN」2 ブロック（L396–526）を、検出済み Issue state でパラメータ化した単一の判定ブロックへ統合（dedup）。bash 3.2+ 互換（新規シェルスクリプトの追加はなく、本ファイルはコードブロック内のコマンド列のみ）。

（`docs/workflow.md` / `README.md` / `CLAUDE.md` / `docs/structure.md` は変更不要。dedup は挙動保存のリファクタであり、これらが記述する verify の skill 一覧・phase 説明・ディレクトリ構成は不変。grep で Step 11 内部／OPEN-CLOSED への外部参照が無いことを確認済み。）

## Implementation Steps

1. Step 11 冒頭（`### Step 11: Apply Verification Results`）の state 検出（`gh issue view "$NUMBER" --json state --jq '.state'`）と「Conditions subject to reopen judgment」リスト（L385–389）はそのまま残し、検出結果を `ISSUE_STATE`（`OPEN` または `CLOSED`）として後続の判定で参照する旨を明記する。（→ acceptance criteria #2, #5）

2. 「Branch on Issue state」以降の 2 サブセクション「#### When Issue is CLOSED ...」「#### When Issue is OPEN ...」（L396 から Step 11 末尾 L526 まで）を、4 つの結果ブランチ — (a) all PASS/SKIPPED、(b) FAIL あり、(c) PENDING のみ、(d) UNCERTAIN のみ — を一度だけ列挙する単一判定ブロックへ置換する。ブランチ列挙には (exhaustive) マーカーを付す。state 依存の差分のみを各ブランチ内で条件付与する。（after 1）（→ acceptance criteria #1, #2, #5）

3. ブランチ (a) all PASS/SKIPPED: opportunistic/manual の未チェックが残る場合 → `phase/verify`、全チェック済み → `phase/done` の経路を一度だけ記述する。close 動作は state 非依存に「Issue が現在 OPEN の場合のみ `gh issue close "$NUMBER"` を実行して必ず CLOSED 状態にする」と一度だけ記述する（CLOSED 標準フローの XL 親 Issue が `closes #N` で自動クローズされないケースと、auto-close 無効リポジトリの OPEN ケースの両方を吸収）。（after 2）（→ acceptance criteria #5）

4. ブランチ (b) FAIL あり: iteration counter 処理を一度だけ記述する。`CURRENT_ITERATION=$(... get-verify-iteration.sh "$NUMBER")`、`NEXT_ITERATION=$((CURRENT_ITERATION + 1))`（変更前後の値・計算タイミングは現行実装と同一でリオープン／コメント投稿の前に算出）。`NEXT_ITERATION < VERIFY_MAX_ITERATIONS` の場合: `<!-- verify-iteration: ${NEXT_ITERATION} -->` コメントを投稿し、state 依存の単一条件「`ISSUE_STATE` が CLOSED のときのみ `gh issue reopen "$NUMBER"` を実行（OPEN は既に open なので reopen 不要）」を付与し、その後 state 共通で `gh-label-transition.sh "$NUMBER"`（phase ラベル除去）を実行、修正サイクルへ戻す案内を出力する。`NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` の場合: max-iterations コメント投稿 + `phase/verify` 付与 + `MAX_ITERATIONS_REACHED` 出力（state 共通）。（after 2）（→ acceptance criteria #2, #5）

5. ブランチ (c) PENDING のみ／(d) UNCERTAIN のみ: それぞれ一度だけ記述する（`phase/verify` 付与のみ・reopen/close なし・ユーザ通知）。state 非依存。（after 2）（→ acceptance criteria #5）

6. 統合後の Step 11 が verify SKILL.md の `allowed-tools` に未登録のスクリプト／コマンドを新たに導入していないことを確認する（`gh issue reopen/close/view`、`gh-label-transition.sh`、`get-verify-iteration.sh`、`gh-issue-comment.sh` はいずれも登録済み。新規モジュール非追加のため allowed-tools 変更・KNOWN_TOOLS 変更は不要）。body 中に半角 `!`・小数 Step 番号・3 連バッククォートを混入させない（validate-skill-syntax.py 制約）。（after 2, 3, 4, 5）（→ acceptance criteria #3）

7. `python3 scripts/validate-skill-syntax.py skills/` が PASS することを確認し、`wc -l skills/verify/SKILL.md` が 639 未満であることを確認する。スクリプト／テストは未変更（markdown のみの変更）であり既存 bats（`tests/get-verify-iteration.bats` 等）は green を維持する。（after 6）（→ acceptance criteria #1, #3, #4）

## Verification

### Pre-merge

- <!-- verify: command "test $(wc -l < skills/verify/SKILL.md) -lt 639" --> `skills/verify/SKILL.md` の行数が現状ベースライン（639 行）から削減されている（`command` のため `/review` safe mode では UNCERTAIN、`/verify` full mode で確定判定）
- <!-- verify: rubric "skills/verify/SKILL.md の Step 11（検証結果の適用）における OPEN/CLOSED 状態分岐の PASS/FAIL/PENDING/UNCERTAIN 判定と iteration counter 処理が、共有モジュールへの抽出または同一ファイル内の state パラメータ化により一度だけ記述されており、単なる移設ではなく重複が解消されている" --> Step 11 の OPEN/CLOSED 重複が（移設ではなく）解消されている
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> CI の skill 構文検証がリファクタ後も green
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の既存 bats テストが green でリファクタによる回帰がない
- <!-- verify: rubric "verify の機能カバレッジ（pre-merge/post-merge 判定、iteration counter、reopen/close 分岐、PENDING/UNCERTAIN 処理）が SKILL.md と抽出先モジュールに維持されており、リファクタによる判定ロジックの欠落・分岐漏れがない" --> 機能カバレッジが維持されている

### Post-merge

- 実プロジェクトで `/verify N` を複数回実行し、`The model's tool call could not be parsed` の発生頻度が改善していることを定性的に確認 <!-- verify-type: manual -->

## Notes

### Auto-Resolve Log（非対話モードでの自動解決）

- **dedup アプローチ = 同一ファイル内 state パラメータ化（in-file dedup）** — 理由: (1) Step 11 は `/verify` で常に到達する中核処理であり、新規モジュールへ抽出しても Step 11 到達時に必ず Read され peak context は減らず、定型ヘッダ分むしろ増える。in-file dedup（約 132 行 → 約 66 行）が peak context を最小化し主目的に最も適う。(2) `skill-dev-checks.md` の「2 つ以上の skill で共有する場合に module 抽出」基準に対し Step 11 ロジックは単一 caller。(3) 変更 1 ファイルに収まり structure.md / docs/ja ミラー更新が不要で低リスク。
  - 他候補: 共有モジュール `modules/verify-apply-results.md` 抽出（先例 `phase-state.md` #438、tech.md「Shared module pattern」「Progressive disclosure」）。本 Issue が「実装者が命名または in-file dedup を選択可能」と明記しているため不採用だが、rubric は意味的 dedup をどちらの形でも許容する。
- **スコープ = 中核 A のみ、補助 B〜D は次回送り** — 理由: Issue が B〜D を「必須ではない」と明記。A 単独で全 AC を充足し、Simplicity Rule（full: 実装ステップ・pre-merge 検証各 10 以内）にも収まる。
- **FAIL（上限未到達）時のユーザ案内を両 state で統一** — 現状 CLOSED は詳細な `/code --patch` `/code --pr` `/spec` 案内、OPEN は簡素な「user selects next action」。両者とも「修正サイクルへ戻す」目的で等価のため、詳細な案内へ統一する（機能の退行ではなく改善。rubric #5 の機能カバレッジは維持）。

### 設計時チェック結果

- **Issue body と実装の矛盾**: なし。Issue が指摘する「Step 11 が OPEN/CLOSED の大ブロックを二重に持つ（約 132 行）」は実ファイル L396–526 と一致する（検証済み）。
- **挙動保存の確認**: 本変更は dedup（挙動保存リファクタ）。`docs/workflow.md` が記述する verify 挙動（FAIL → reopen + phase/* 除去、全 PASS → phase/done）は不変。`README.md` / `CLAUDE.md` / `docs/structure.md` の skill 一覧・phase 説明・ディレクトリ構成も不変。grep で Step 11 内部／`When Issue is OPEN/CLOSED` への外部参照が無いことを確認済みのため doc 同期は不要。
- **Tool Dependencies**: 追加なし。Step 11 が使用する `gh issue reopen/close/view`、`gh-label-transition.sh`、`get-verify-iteration.sh`、`gh-issue-comment.sh` はすべて verify SKILL.md の `allowed-tools` に登録済み。新規モジュール非追加のため `validate-skill-syntax.py` の「module 参照スクリプト ⊆ allowed-tools」クロスチェックには影響しない。KNOWN_TOOLS 変更も不要。
- **counter 変数**: iteration counter（`NEXT_ITERATION = CURRENT_ITERATION + 1`）は現行ロジックを保存（値・タイミング不変）。dedup により記述箇所が 2 → 1 になるのみ。
- **adapter survey**: 対象外（新規 verify command type の追加なし）。
- **構造の選択肢**: state 依存差分を小さな表で表現する場合は (exhaustive) マーカーを付す。表現形式は実装者裁量（rubric が意味的 dedup を検証）。

### AC 整合性

- Issue body pre-merge AC: 5 件 / Spec pre-merge 検証: 5 件（一致）。`<!-- verify: ... -->` は Issue body から逐語コピー。
- Size = L（pr route）のため PR が存在し `github_check "gh pr checks"` は適合（patch route 変換不要）。CI ジョブ名 `Validate skill syntax` / `Run bats tests` は `.github/workflows/test.yml` に存在することを確認済み。

## issue retrospective

`/issue 515` リファインメントの判断記録（Issue コメントから転記）。

### Triage（auto-chain）

- Title 正規化: 動作を先頭にした名詞止め「verify: SKILL.md・モジュール群のコンテキスト規模を削減し tool call parse 失敗を抑制」
- Type=Task（リファクタリング/保守）, Priority=high（「頻発」「複数セッションで再現」「別セッションのレビューでも指摘」= 反復する実害）, Size=L（コア skill のリファクタで機能デグレ防止の検証が必要）, Value=4
- 重複候補なし（個別機能ではなく skill 全体のコンテキスト規模が対象で verify 改善 Issue 群とトピックが異なる）

### 成功指標の方針決定（ユーザー確認）

AC #1 の行数チェック `test ... -lt 639` は「1 行でも減れば PASS」となり、Step 11 を遅延ロード module へ移設するだけ（dedup なし）でもすり抜ける点を提起。真の目標は「実行時累積コンテキストの削減」であるため成功指標をユーザーに確認 → **「行数削減 + dedup rubric」方式を採用**。行数 < 639 を「削減が起きた」シグナルとして維持しつつ、重複解消の実体は rubric で担保。補助改善 B〜D は必須化しない。

### Auto-Resolve した曖昧点（issue フェーズ）

- 共有モジュール抽出パターン: `modules/phase-state.md`（#438）と tech.md「Shared module pattern」「Progressive disclosure」を踏襲（先例から一意に推論可能）
- 抽出先モジュール名: `verify-apply-results.md` は例示。同一ファイル内 dedup も許容するため AC では特定ファイル名を強制せず rubric で意味検証
- 機能カバレッジの検証方法: `validate-skill-syntax.py`（構文 mechanical）+ rubric（意味的カバレッジ）の組み合わせ。`tests/get-verify-iteration.bats` が iteration counter ヘルパをスクリプトレベルで補助カバー

### AC 変更理由 / Scope Assessment

- pre-merge AC に verify command を付与（行数=command、dedup=rubric、構文/テスト=github_check、カバレッジ=rubric）。verify-patterns §9 に基づき rubric を中心に mechanical command と組み合わせ
- 単一目標への凝集したリファクタで分割不要と判断（Size L 維持）。補助改善 B〜D は実装者裁量の任意項目として body に保持

## Code Retrospective

### Deviations from Design

- なし（Spec の実装ステップに従い in-file dedup を実施）

### Design Gaps/Ambiguities

- `CLOSED` 状態での「all checked」ブランチ: 旧実装は「Confirm the Issue is closed. If not closed, close with gh issue close」という記述があったが、実際のコードブロックには `gh issue close` コマンドがなかった（テキストと実装の乖離）。Spec の方針「ISSUE_STATE が OPEN の場合のみ close」に従い統一し整合性を解消した。

### Rework

- なし

## spec retrospective

### Minor observations

- 転記元 Issue Refinement Retrospective は pre-merge AC を「3 → 4 項目」と記録しているが、現行 Issue body の pre-merge AC は 5 項目（command 行数 / rubric dedup / github_check 2 件 / rubric coverage）。Spec の pre-merge 検証も 5 項目で一致を確認済み。記録上の軽微な数え違いで実害なし。
- 補助改善 B〜D は本 Issue では任意。verify の context 削減を継続課題とするなら、特に C（`verify-executor.md` 翻訳テーブル等 eager-load module の圧縮）が peak context により効くため follow-up 候補。

### Judgment rationale

- **dedup を in-file state パラメータ化で実装**（module 抽出ではなく）と判断。Step 11 は `/verify` で常に到達する中核処理であり、module 抽出は peak context を減らさず定型ヘッダ分むしろ増える。先例 phase-state.md は複数 caller 共有が module 化の根拠であり、単一 caller の Step 11 には当てはまらない。Issue が両方式を許容しているため rubric AC はどちらでも PASS する。
- FAIL（上限未到達）時のユーザ案内を両 state で詳細版に統一する判断は、機能の退行ではなく改善（OPEN 側の簡素な案内を CLOSED 側の詳細案内へ揃える）。

### Uncertainty resolution

- 行数 < 639 の達成可能性: dedup により約 132 行 → 約 66 行へ削減され ~573 行となる見込みで、ベースライン 639 を確実に下回る（不確実性なし）。
- allowed-tools 整合: 統合後 Step 11 が参照する全スクリプト／gh コマンドが verify SKILL.md の allowed-tools に既登録であることを確認（新規モジュール非追加のため validate-skill-syntax のクロスチェックにも影響なし）。
- CI ジョブ名・route: `Validate skill syntax` / `Run bats tests` が `.github/workflows/test.yml` に存在。Size L の pr route で `gh pr checks` が適合することを確認。
