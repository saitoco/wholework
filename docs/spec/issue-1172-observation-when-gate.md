# Issue #1172: observation: observation AC に when= 実行文脈ゲートを追加し観察不能な dispatch を抑止

## Overview

`verify-type: observation` の AC は `event=<name>` だけで発火条件を宣言するため、`event=auto-run` を持つ AC は「任意の `/auto` 完走」でマッチする。実際には条件の多くが `/auto` の実行文脈 (route / mode / recovery tier) に依存しており、文脈が一致しない実行でも dispatch されて必ず SKIPPED に終わる (親 Issue #1118 の実測: 12 件中 7 件が実行文脈依存)。

本 Issue では、Issue 本文の対応方針 **B (`when=` 相当の実行文脈条件属性の追加)** を採用し、`config=` ゲートと同型の宣言的属性 `when=<axis>:<value>` を `opportunistic-search.sh` の gate 段に追加する。照合に使う実行文脈は #1171 が拡張した `scripts/collect-run-facts.sh` の出力 (`route` / `mode` / `recovery_tiers`) をそのまま消費し、並行する独自の収集機構は作らない。

あわせて対応方針 **C (表現できない条件の扱いの明文化)** を `modules/observation-trigger.md` に記述し、確率的事象 (#1113 の jq エラー等) は「dispatch されて SKIPPED になるのが正常」であり抑止は #1099 の冪等性ガードが担う、という分担を確定させる。

## Changed Files

- `scripts/opportunistic-search.sh`: `--facts-file <path>` 引数の追加、run facts の遅延解決関数 `resolve_run_facts()` の追加、マッチループへの `when=` ゲート追加、ヘッダーコメントの更新 — bash 3.2+ 互換 (`mapfile` / `${VAR,,}` / 連想配列を使わない)
- `scripts/observation-trigger.sh`: `--facts-file <path>` の受理と `opportunistic-search.sh` への転送、ヘッダーコメントと Usage 行の更新 — bash 3.2+ 互換
- `modules/observation-trigger.md`: `## Condition Check Gate (when=)` 節の新設 (宣言可能な軸の表 **(exhaustive)**、fail-open 規則、`--facts-file` の Arguments 行、`--when=` verify modifier との名前衝突の注記)、`## Conditions That Cannot Be Pre-Excluded` 節の新設 (対応方針 C)、`## Notes` の `session=next` 対比記述への `when=` 追記
- `modules/verify-classifier.md`: `### observation Type: Event Values and Syntax` に `when=<axis>:<value>` の属性説明を追加 (`config=<key>` 節の直後、同じ書式)
- `modules/run-fact-matching.md`: `collect-run-facts.sh` の出力が `when=` ゲートからも消費されることを明記する相互参照を `## Fact JSON Fields` 節に追記
- `tests/opportunistic-search.bats`: `when=` ゲートのテスト追加 (マッチ / 除外 / 宣言なし無条件マッチ / 判定不能時 fail-open / 未知軸 fail-open / AND 結合)、`$MOCK_DIR/collect-run-facts.sh` モックの追加
- `tests/observation-trigger.bats`: `--facts-file` 転送テストの追加 (既存の `--context-file` 転送テストと同型)
- GitHub Issue #995 の post-merge observation AC (リポジトリ内ファイルではない): `<!-- verify-type: observation event=auto-run -->` に `when=route:operate` を追加。Post-merge AC の参照ケースとして必要 (詳細は Notes の「Issue 本文との整合」参照)
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] L202-203 (ja: L194-195) の `opportunistic-search.sh` / `observation-trigger.sh` の 1 行説明が `when=` ゲート追加後も正確かを確認し、必要なら更新する。更新する場合は英日両方を同時に更新する (`docs/translation-workflow.md`)。現時点の記述 (「opportunistic skill search and observation event scan」) は依然として正確であり、変更不要と判断している
- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: [Steering Docs sync candidate] L486 (ja: L481) の `opportunistic-search.sh` 項は英語化移行時の履歴記録であり、`**Interface changes**: None` は当時の移行に対する記述。本 Issue のインターフェース追加は履歴の対象外のため変更不要 (grep で内容を確認済み)

## Implementation Steps

1. `scripts/opportunistic-search.sh` に `--facts-file <path>` の引数解析を追加する。引数なしの `--facts-file` はエラー終了 (既存の `--context-file` と同型)。パスが存在しない場合は stderr に警告を出して変数をクリアし、Step 2 の遅延収集にフォールバックする。ヘッダーコメントの Usage / Examples / ゲート説明も同時に更新する (→ 受け入れ条件 1, 2)

2. (1 の後) `scripts/opportunistic-search.sh` に run facts の遅延解決関数 `resolve_run_facts()` を追加する。1 プロセス内で最初の `when=` 付き行を処理するときに 1 回だけ実行し、結果を変数にキャッシュする。`--facts-file` が有効ならその内容を読み、無ければ `"${SCRIPT_DIR}/collect-run-facts.sh"` を引数なしで呼ぶ (session 解決は同スクリプトのラダー `--session > AUTO_SESSION_ID > .tmp/auto-session-current` に委ねる)。取得結果が空・JSON として不正・`(.issues | length) == 0 and .mode == "unknown"` のいずれかなら stderr に警告を出してゲートを無効化する (fail-open) (→ 受け入れ条件 2)

3. (2 の後) `scripts/opportunistic-search.sh` のマッチループ (既存の `keyword=` ゲートと `config=` ゲートの直後) に `when=` ゲートを追加する。`grep -oE 'when=[^ >]+'` で値を抽出し末尾ダッシュを除去 (既存 2 ゲートと同一の抽出方式)、カンマ区切りの各節を AND 条件として評価し、1 つでも不成立なら `continue` で当該行を除外する。節の評価は軸ごとに jq で行う: `route:<v>` は `any(.issues[]?; .route == $v)`、`mode:<v>` は `.mode == $v`、`recovery-tier:<v>` は `any(.issues[]?; ((.recovery_tiers // []) | map(tostring)) | index($v) != null)`。未知の軸・不正な書式 (`:` を含まない、値が空) は stderr に警告を出して当該節を無視する (fail-open) (→ 受け入れ条件 1, 5)

4. (3 と並行可) `scripts/observation-trigger.sh` に `--facts-file <path>` の引数解析を追加し、`opportunistic-search.sh` 呼び出しへ `--context-file` と同じ形で転送する。ヘッダーコメントと Usage 行も更新する (→ 受け入れ条件 1)

5. (3 の後) `modules/observation-trigger.md` に `## Condition Check Gate (when=)` 節を新設する。`## Condition Check Gate (config=)` 節の直後に配置し、同節と同じ構成 (Problem / 属性の例 / Matching specification) を踏襲する。記載事項: 宣言可能な軸の表 **(exhaustive)** (`route` / `mode` / `recovery-tier` と対応する fact JSON フィールド・取りうる値)、カンマ区切り AND の意味論、fail-open となる 3 条件 (facts 取得不能 / facts に run context なし / 未知の軸)、`--facts-file` の Arguments 表への行追加、`when=` は run facts が `/auto` 実行を記述するため `event=auto-run` を前提とする旨、`modules/verify-executor.md` の verify command 修飾子 `--when="shell condition"` とは別機構である旨の注記 (→ 受け入れ条件 3, 4)

6. (5 の後) `modules/observation-trigger.md` に `## Conditions That Cannot Be Pre-Excluded` 節を新設する (対応方針 C)。確率的事象 (#1113 の jq エラー発生など)・時系列比較 (#1159)・fact JSON に表現のない recovery 種別 (#1009 / #1123) はどの属性でも事前除外できないこと、これらは「dispatch されて SKIPPED になるのが正常」であること、コメント蓄積の抑止は #1099 の冪等性ガードが担うこと、を明記する (→ 受け入れ条件 3)

7. (5 の後) `modules/verify-classifier.md` の `### observation Type: Event Values and Syntax` に `when=<axis>:<value>` の説明を追加する。`config=<key>` の段落の直後、`session=next` の段落の前に配置し、属性例・軸の一覧・省略時は無条件マッチ (後方互換) である旨・機構の詳細は `modules/observation-trigger.md` § Condition Check Gate (`when=`) を参照する旨を書く。あわせて `modules/run-fact-matching.md` の `## Fact JSON Fields` 節に、同 JSON が `when=` ゲートからも消費される旨の相互参照を 1 行追記する (→ 受け入れ条件 1, 2, 3)

8. (3 の後) `tests/opportunistic-search.bats` に `when=` ゲートのテストを追加する。`setup()` に `$MOCK_DIR/collect-run-facts.sh` のモック (環境変数 `MOCK_RUN_FACTS` の内容を出力) を追加し、`export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を当該テスト内で設定する。検証経路: (a) 実行文脈一致でマッチ、(b) 不一致で除外、(c) `when=` 宣言なし AC の無条件マッチ (後方互換)、(d) facts 判定不能時の fail-open + 警告、(e) 未知軸の fail-open + 警告、(f) カンマ区切り AND の一方不成立で除外、(g) `--facts-file` 経由の明示指定。`@test` 名は既存の `config gate:` / `context gate:` に倣い `when gate:` プレフィックスで統一する。あわせて `tests/observation-trigger.bats` に `--facts-file` 転送テストを追加する (→ 受け入れ条件 5, 6)

9. (8 の後) GitHub Issue #995 の post-merge observation AC 1 行に `when=route:operate` を追加する (`<!-- verify-type: observation event=auto-run when=route:operate -->`)。`gh-issue-edit.sh` を用い、対象は当該 1 行のみ。既存 12 件の AC の一括書き換えは行わない (→ Post-merge 条件)

## Alternatives Considered

| 案 | 内容 | 判断 |
|----|------|------|
| **A. `event=` の細分化** | `event=auto-run-operate` / `event=auto-run-batch` のように event 名を実行文脈で分割 | **不採用**。軸が増えるたびに event 名が組み合わせ爆発する (route 3 値 × mode 3 値 × tier 3 値 = 27)。`KNOWN_EVENTS` と `modules/verify-classifier.md` の emitter 表を軸追加のたびに更新する必要があり、`keyword=` ゲート導入時 (#794) に同じ理由で退けた判断と同型 |
| **B. `when=` 実行文脈条件属性** | `config=` と同型の宣言的属性を gate 段に追加 | **採用**。既存 gate 段 (`keyword=` / `config=`) と同じ抽出・除外パターンを再利用でき、新規 CLI 引数も原則不要。event 名前空間を増やさずに軸を追加できる |
| **C. 表現できない条件の明文化** | 確率的事象は事前除外を諦め、`modules/observation-trigger.md` に扱いを明記 | **併用採用**。B の代替ではなく補完。B でカバーできない残余 (#1113 / #1159 / #1009 / #1123) の扱いを確定させる |
| **D. `/auto` が facts を先に生成して渡す** | `skills/auto/SKILL.md` の Event-based observation scan の前に `collect-run-facts.sh` を実行し `--facts-file` で渡す | **不採用 (将来の最適化余地として残す)**。現行の `/auto` は observation scan → run-fact reconciliation の順で、facts JSON は scan 時点でまだ存在しない。順序変更は single-issue route と batch route の 2 箇所の SKILL.md 改変を伴い、本 Issue のスコープに対して侵襲的。`--facts-file` 引数だけ先に用意しておけば、将来この最適化を SKILL.md 側の変更だけで導入できる |

## Verification

### Pre-merge

- <!-- verify: rubric "observation AC が実行文脈 (route / mode / recovery tier のうち少なくとも route を含む) への依存を宣言できる仕組みが実装されている。event= の細分化・when= 相当の属性追加のいずれでもよいが、採用方式と他案を採らなかった判断根拠が記録されている" --> 実行文脈条件を宣言する仕組みが実装され、方式選定の根拠が記録されている
- <!-- verify: rubric "照合に用いる実行文脈が scripts/collect-run-facts.sh の出力を消費する形で実装されている。並行する独自の実行文脈収集機構を新設していないこと。collect-run-facts.sh を使わない判断をした場合は、その根拠が記録されていること" --> 実行文脈の取得が `collect-run-facts.sh` と重複していない
- <!-- verify: rubric "modules/observation-trigger.md に、宣言可能な実行文脈の軸と、事前に除外できない条件 (確率的事象など) の扱いが明記されている" --> 宣言可能な軸と除外不能条件の扱いがドキュメント化されている
- <!-- verify: grep "when=" "modules/observation-trigger.md" --> `observation-trigger.md` が実行文脈条件の属性に言及している
- <!-- verify: rubric "tests/opportunistic-search.bats に、実行文脈が一致する場合のマッチ・一致しない場合の除外・条件宣言なし AC の無条件マッチ (後方互換) の 3 経路を検証するテストが存在する" --> 3 経路を検証するテストが追加されている (negative case を含む)
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト全件が CI で PASS する (pr route)

### Post-merge

- pr route の `/auto` 完走後に `scripts/observation-trigger.sh --event auto-run --dry-run` を実行し、operate route を要求する AC (#995) がマッチ集合から除外されていることを確認する

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*` — Implementation Step 9 で Issue #995 の body を更新する。`skills/code/SKILL.md` の `allowed-tools` に登録済みのため追加不要
- `gh issue edit:*` — 同上。登録済みのため追加不要

### Built-in Tools

- `Read` / `Edit` / `Write` / `Grep` / `Glob` — いずれも `skills/code/SKILL.md` に登録済み

### MCP Tools

- なし

## Uncertainty

- **遅延収集時の session 解決が `/auto` 実行外では stale になりうる**: `resolve_run_facts()` が `collect-run-facts.sh` を引数なしで呼ぶ場合、session は `AUTO_SESSION_ID` env → `.tmp/auto-session-current` の順で解決される。`/auto` 実行中は Step 1 で `.tmp/auto-session-current` が書かれるため現在の session に解決される (`skills/auto/SKILL.md` L39-45 で確認済み) が、`/review` の `pr-review-full` emitter や手動実行では直前の `/auto` session を指したままになりうる。
  - **検証方法**: `scripts/collect-run-facts.sh` の session 解決ラダー (L103-114) とポインタ書き込み箇所 (`skills/auto/SKILL.md` Step 1) の読み合わせで確認済み。実装後は `--facts-file` を渡すテスト (Step 8-g) で決定的経路を担保する
  - **影響範囲**: Implementation Steps 2, 5。`when=` は `event=auto-run` を前提とする旨を Step 5 のドキュメントに明記して対処する

- **`resolve_run_facts()` の `gh` 呼び出しコスト**: `collect-run-facts.sh` は `--no-github` なしで呼ぶと size 補完・`gh pr view`・operate marker probe で `gh` を叩く。observation scan 1 回につき最大 1 度だけ発生する。
  - **検証方法**: `collect-run-facts.sh` の実装読解で、呼び出しが session 内 Issue 数に比例し 1 プロセス 1 回にキャッシュされることを確認済み
  - **影響範囲**: Implementation Step 2。`when=` 付き AC が 1 件も無い実行ではそもそも収集が走らないため、既存の実行コストは増えない

## Notes

### Issue 本文との整合 (非対話モードでの自動解決)

Issue 本文の `## Notes` は「既存 12 件の AC 本文を一括で書き換えることは本 Issue のスコープに含めない」と記述しているが、Post-merge 条件は「operate route を要求する AC (#995) がマッチ集合から除外されていること」の確認を要求している。#995 の AC は現状 `<!-- verify-type: observation event=auto-run -->` で `when=` を持たないため、本文を変更しない限り無条件マッチのままとなり Post-merge 条件が原理的に成立しない。

**自動解決**: 「一括書き換え」の禁止は 12 件全件への機械的適用を指すと解釈し、Post-merge 条件が名指しする #995 の 1 行のみを参照ケースとして注釈する (Implementation Step 9)。残る 11 件は本 Issue のスコープ外とし、後続の運用で個別に判断する。

### `--when=` verify modifier との名前衝突

`modules/verify-executor.md` には既に `--when="shell_condition"` という **verify command の修飾子** が存在する (`<!-- verify: command "..." --when="which bats" -->`)。本 Issue が追加する `when=<axis>:<value>` は **`verify-type:` タグ側の属性** であり、位置・構文・意味論のいずれも異なる別機構である。Implementation Step 5 でこの区別を `modules/observation-trigger.md` に明記し、実装時に `validate-skill-syntax.py` の `--when=` 除去ロジック (L620/L626) に影響しないこと (対象タグが異なるため無関係) を確認する。

### 軸の選定根拠と将来の拡張余地

親 Issue #1118 の実測 12 件のうち、`route` / `mode` / `recovery-tier` の 3 軸で #995 (route) / #1136・#1037 (mode) / #984 (recovery tier) をカバーする。fact JSON には `pr_state` と `anomalies` も存在するが、#1150 (open PR + recovery) / #1009・#1123 (recovery 種別) は「recovery の種別」という fact JSON に存在しない粒度を要求するため、軸を増やしても解決しない。`pr-state` 軸と `anomaly` 軸は同じ jq パターンで追加できるため、必要が生じた時点で軸表に行を足す形の拡張余地として残す (Implementation Step 5 の軸表は現時点で **(exhaustive)**)。

### fail-open を選んだ理由

#1055 (`get-config-value.sh` の nested key 非対応により `config=capabilities.*` が無言で常時除外される) の再発を避けるため、`when=` ゲートは判定不能時・未知軸時に **無条件マッチ側へ倒す** (fail-open) 設計とし、いずれも stderr に警告を出す。fail-closed にすると誤記した 1 文字が AC を永久に dispatch 不能にし、#1055 と同じ silent failure を再生産する。これは `keyword=` ゲートの「`--context-file` が存在しない場合はゲート無効化」の先例と同じ方向である。

### 実装上の注意

- 両スクリプトとも `set -euo pipefail` 配下のため、jq の非ゼロ終了を `if ! ...` で受ける形にし、`|| true` の乱用でエラーを握り潰さないこと
- `grep -oE 'when=[^ >]+'` の末尾ダッシュ除去 (`sed 's/-*$//'`) は既存 2 ゲートと同一処理。`when=route:operate-->` のようにスペースなしで閉じタグが続く記法にも対応させる
- bash 3.2 (macOS system bash) 互換: カンマ分割は `IFS=','` の一時変更で行い、`readarray` / `mapfile` は使わない

## Consumed Comments

No new comments since last phase.

## spec retrospective

### Minor observations

- 親 Issue #1118 の Background に「12 件の実マッチ + 依存対象の分類表」が既に載っていたため、軸の選定 (`route` / `mode` / `recovery-tier`) は Issue 段階のデータをそのまま採用でき、codebase investigation では fact JSON との対応付けだけで済んだ。sub-issue に分割するとき、母集団の実測表を親側に残しておくと子の spec phase が安価になる好例
- `modules/observation-trigger.md` の gate 節は `keyword=` (#794) → `config=` (#1088) → 本 Issue の `when=` で 3 つ目になる。3 節とも「Problem → 属性例 → Matching specification」の同一構成で書かれており、4 つ目が現れたら共通の抽出ヘルパー (`grep -oE '<attr>=[^ >]+' | sed 's/-*$//'`) をスクリプト側の関数に切り出す余地がある。現時点では 3 箇所の重複で済んでおり、`project_skill_consolidation_trigger` と同種の「3 つ目が判断点」の状態にある
- `--when="shell condition"` (verify command 修飾子、`modules/verify-executor.md`) という同名の既存機構が別のタグ位置に存在することは、Step 6 の grep で初めて判明した。Issue 本文は属性名を `when=` と指定していたため名前は動かせず、ドキュメント側で区別を明記する対処を選んだ。属性名を新設する Issue では、起票時点で `grep -rn '<attr>='` を掛けておくと衝突を事前に検出できる

### Judgment rationale

- **`--facts-file` と遅延収集の二本立てにした理由**: 現行 `/auto` は observation scan → run-fact reconciliation の順で facts JSON が scan 時点に存在しない。遅延収集だけなら SKILL.md を触らずに済む一方、`/auto` 側で 1 回に集約する将来の最適化経路も残したかった。`--facts-file` は `--context-file` と同型の 6 行程度の追加で済み、かつ bats テストを決定的に書ける副次効果がある
- **軸を 3 つに絞った理由**: fact JSON には `pr_state` と `anomalies` も存在するが、実測 12 件のうち残る未カバー分 (#1150 / #1009 / #1123) はいずれも「recovery の種別」という fact JSON に存在しない粒度を要求する。軸を増やしても解決しないため、軸表を **(exhaustive)** として確定させ、拡張余地は Notes に明記する形にした
- **fail-open を選んだ理由**: #1055 の silent 常時除外が本 Issue の Related に挙がっているとおり、gate の fail-closed は誤記 1 文字で AC を永久に dispatch 不能にする。`keyword=` ゲートの先例 (`--context-file` 不在でゲート無効化) と同方向であり、警告を stderr に出すことで沈黙も避けた

### Uncertainty resolution

- **設計時の不確実性「遅延収集時に session を解決できるか」**: `collect-run-facts.sh` の解決ラダー (`--session` > `AUTO_SESSION_ID` env > `.tmp/auto-session-current`) と `skills/auto/SKILL.md` Step 1 のポインタ書き込みを読み合わせ、`/auto` 実行中は必ず現在の session に解決されることを確認した。`AUTO_SESSION_ID` は wrapper 経由でしか export されないため、env だけに依存する設計にしなくて正解だった
- **未解決のまま残した点**: `/review` の `pr-review-full` emitter や手動実行では `.tmp/auto-session-current` が直前の `/auto` session を指したままになりうる。`when=` は run facts が `/auto` 実行を記述する以上 `event=auto-run` 前提である旨をドキュメントに明記する対処にとどめ、機構的な強制 (event 名による gate の有効/無効切り替え) は入れないことにした。強制すると将来 `/auto` 以外の run facts が現れたときに再度剥がす必要が出るため

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1-9 を記載順にそのまま実装した。逸脱なし

### Design Gaps/Ambiguities

- N/A — Spec の各ステップが対象ファイル・挿入位置・jq パターンまで具体的に指定しており、実装中に解釈の余地が生じる箇所はなかった

### Rework

- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- `/merge 1178 --non-interactive` の pre-merge AC gate で 7 件全て `[x]` を確認し、追加の override 記録なしでそのまま squash merge を実行した
- mergeable 判定は `reason=clean` (CI success, review approved) だったため conflict 解決フローは不要だった

### Deferred Items

- review フェーズで見送った 4 件 (CONSIDER 判定: doc 文言曖昧さ・malformed clause テスト欠如・spec retrospective 記述精度・`keyword=`/`config=` ゲートへの横展開) は本 PR スコープ外のまま。個別 Issue 化は未実施
- `scripts/observation-trigger.sh:87` の stderr discard は既存動作として対象外のまま

### Notes for Next Phase

- Post-merge 条件 (Issue #995 の operate route AC がマッチ集合から除外されることの確認) は `/verify` で `scripts/observation-trigger.sh --event auto-run --dry-run` を実行して確認すること
- squash commit: `543e8712` (「Issue #1172: observation AC に when= 実行文脈ゲートを追加 (#1178)」)

## review retrospective

### Spec vs. implementation divergence patterns

- Spec Implementation Step 3 が「`grep -oE 'when=[^ >]+'` で値を抽出 (既存 2 ゲートと同一の抽出方式)」と明記しており、実装はこれをそのまま踏襲した。しかし review-bug×2 の検証で、この抽出パターンが AC の行全体 (HTML コメントタグ外の prose も含む) を対象にしているため、条件文が `when=...` という文字列を説明目的で引用すると `grep -o` の複数マッチが改行区切りで返り、カンマのみで分割するクローズパーサが破損することが判明した (本 PR で修正済み)。Spec 段階では「既存ゲートと同一パターンを踏襲する」ことが安全側の判断として書かれていたが、実際には `keyword=` / `config=` ゲートも同じ脆弱性を潜在的に持っている (本 Issue のスコープ外として今回は未修正)。既存パターンの踏襲は「実績があるから安全」とは限らないことを示す一例
- Spec の Implementation Step 3 は「1 つでも不成立なら `continue` で除外」という記述だったが、Code フェーズでは意図的に early-break しない実装を選択した (Phase Handoff の Key Decisions に記録済み)。この逸脱は Code Retrospective の「Deviations from Design」に N/A と記載されていたが、実際には記録すべき逸脱だった (review-spec が指摘、Notes へ追記は見送り)

### Recurring issues

- review-bug の 2 エージェント (diff bug scan / security scan) が独立に同一の根本原因 (`when=` 属性抽出のマルチライン衝突) を異なる再現手順で検出し、2 段階検証でも揃って PASS 判定となった。並列 diff scan と security scan という異なる着眼点からの収束は、bash の unquoted 展開・`grep -o` の複数マッチという「見た目は動くが境界値で壊れる」クラスの bug に対して有効なシグナルだった
- `keyword=` (#794) → `config=` (#1088) → `when=` (本 Issue) と 3 つ目の condition check gate が追加され、3 節とも同一の「行全体から属性を `grep -oE` で抽出」パターンを共有している。Spec の Notes は「4 つ目のゲートが現れた時点で共通ヘルパーへの切り出しを検討する」としているが、今回 3 つ目の時点で潜在バグが顕在化した。抽出パターンの共通化は「重複除去」ではなく「同じバグを 3 箇所に埋め込まない」という正当化も持つため、次に `keyword=` / `config=` のいずれかを触る Issue が出た時点で本 PR の修正 (HTML コメントタグ内への抽出範囲限定) を横展開する価値がある

### Acceptance criteria verification difficulty

- Pre-merge AC 7 件中 5 件が `rubric` (意味論的判断) で、実装の存在・ドキュメント化・テスト網羅性を検証した。これらは全て PASS だったが、rubric は「設計判断が記録されているか」「軸が文書化されているか」を検証するものであり、bash の unquoted 展開や `grep -o` の複数行マッチといったコードレベルの correctness bug は検出対象外だった。今回それらのバグは `/review` Step 10 の multi-perspective review (review-bug×2 + 2 段階アドバーサリアル検証) で初めて発見された。Feature タイプかつ bash ロジックが複雑な Issue では、rubric ベースの AC 設計だけでは correctness を担保できず、`--full` review の code-level bug detection が実質的な安全網として機能した
