# Issue #1061: size-workflow-table: Size 由来の route 判定全箇所で always-pr 設定を honor

## Overview

`.wholework.yml` に `always-pr: true` が設定されているとき、`/auto`・`/code`・`run-auto-sub.sh` は Size XS/S を patch から pr へ promote するが、`/spec`・`/issue`・`/triage` と関連モジュールは Size のみから route (および route 依存の挙動) を導出しており `always-pr` を無視している。

本 Issue では `modules/size-workflow-table.md` に `ALWAYS_PR Override` 節を追加して route 決定の SSoT を確立し、Size から route または route 依存の挙動を導出している全箇所がこの override を参照するようにする。

Purpose の「全箇所」に従い、Issue 本文の 対応方針 (案) B に挙げられた 4 箇所に加え、`/spec` のコードベース調査で発見した同一クラスの 3 箇所 (`/code` の Patch route verify command check、`skills/issue/spec-test-guidelines.md` の Route selection、`skills/triage/skill-dev-verify-audit.md` の Pattern 4) も対象に含める (Notes 参照)。

## Reproduction Steps

`.wholework.yml` に `always-pr: true` を設定したリポジトリで以下を実行する。

1. Size を XS または S に設定した Issue を用意し、Pre-merge AC に `<!-- verify: github_check "gh pr checks" "Run bats tests" -->` を含める
2. `/spec <N> --non-interactive` を実行する (`run-spec.sh` 経由)
3. `skills/spec/SKILL.md` Step 10 の「Patch route verify command check」が Size XS/S のみを見て patch route と判定し、`github_check "gh pr checks"` を `github_check "gh run list --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` へ自動修正する (Spec と Issue body の両方を書き換える)
4. 続く `/code` は Step 0 の Flag precedence で `ALWAYS_PR=true` を honor して pr route を選び、PR を作成する
5. 結果として PR が存在するにもかかわらず `gh run list` 形式の AC が残る

`/code` 側でも同様に再現する。上記 4 で ROUTE=pr に解決されているにもかかわらず、`skills/code/SKILL.md` Step 10 の「Patch route verify command check」は「Size is `XS`/`S` or `--patch` flag」という条件で Size から再導出するため、同じ自動修正がもう一度発火する。

`/triage` 側でも再現する。`skills/triage/skill-dev-verify-audit.md` Pattern 4 は「Size XS or S (patch route) の AC が `gh pr checks` を使っていたら欠陥」と判定するため、`always-pr: true` 下では正しい `gh pr checks` を欠陥として書き換えようとする。

## Root Cause

Size → workflow route の導出が複数の skill / module に個別実装されており、**route 決定の単一の SSoT が存在しない**。

- `modules/size-workflow-table.md` の Size-to-Workflow Mapping Table は Size のみで route を決める。`always-pr` に言及しているのは「Diff-less Axis (operate route)」節だけで、そこでは「operate は `always-pr: true` より優先される」という**優先順位の一部**しか記述していない。`always-pr: true` 自体が Size 由来の patch を pr へ promote するという規則が SSoT に書かれていない
- そのため各 caller が個別に `always-pr` を実装するか、実装し忘れるかに分かれた。`/auto`・`/code` Step 0・`run-auto-sub.sh` は実装済み、`/spec`・`/issue`・`/triage` と `modules/verify-classifier.md` は未実装
- さらに「route 値そのもの」ではなく「route 依存の挙動」(Size XS/S ならば PR が存在しない、ゆえに `gh pr checks` は使えない) を Size から導出している箇所が複数あり、これらも同じ理由で `always-pr` を無視している

修正方針は SSoT 側に override 規則を明記し、Size から route または route 依存の挙動を導出する全 caller にその参照を持たせること。個別 caller に条件分岐を足すだけでは、今後追加される caller で同じ欠落が再発する。

## Changed Files

- `modules/size-workflow-table.md`: Size-to-Workflow Mapping Table の直後・「Diff-less Axis (operate route)」節の直前に `### ALWAYS_PR Override` 節を新設 (override 規則、優先順位テーブル (exhaustive)、route 依存挙動への適用、caller 一覧 (exhaustive))
- `modules/verify-classifier.md`: 「Patch Route CI Verification Note」節に `always-pr: true` 例外の段落を追加 (Size だけでなく `ALWAYS_PR` から route を導出する旨)
- `skills/spec/SKILL.md`: Step 5 の retain 変数に `ALWAYS_PR` を追加。Step 10「Patch route verify command check」の発火条件に `ALWAYS_PR=false` を追加し、`ALWAYS_PR=true` 時はチェック自体をスキップする旨を明記。Step 18 の手順 5 に ALWAYS_PR override 適用を追加
- `skills/issue/SKILL.md`: Step 2 / Step 4 の retain 変数に `ALWAYS_PR` を追加。「Acceptance Criteria Writing Guide」の `Note:` 行に `always-pr: true` 例外を追記
- `skills/code/SKILL.md`: Step 10「Patch route verify command check」の発火条件を「Size is `XS`/`S` or `--patch` flag」から「Step 0 で解決済みの ROUTE が `patch`」へ変更 (Step 0 は既に ALWAYS_PR override を適用済み)
- `skills/issue/spec-test-guidelines.md`: 「Route selection」の注記に `always-pr: true` 時は Size によらず `gh pr checks` 形式を使う旨を追記
- `skills/triage/SKILL.md`: 「Configuration Detection」節の retain 変数に `ALWAYS_PR` を追加
- `skills/triage/skill-dev-verify-audit.md`: Pattern 4 の Detect 条件に `ALWAYS_PR=false` を追加し、Detection approach に `ALWAYS_PR` の参照元 (Configuration Detection) と `ALWAYS_PR=true` 時のスキップを明記
- `tests/size-workflow-table.bats`: `ALWAYS_PR Override` 節の shallow test を 2 件追加 — bash 3.2+ 互換 (既存ファイルと同じ `grep -q` パターンのみ使用)

**変更不要と確認済み (grep / Read で検証)**

- `skills/spec/skill-dev-constraints.md` 66 行目「Patch route CI verify」: 「For patch route Issues (no PR)」という route ベースの記述で Size から導出していない。`modules/verify-classifier.md` へ委譲しているため本 Issue の修正でカバーされる
- `modules/verify-patterns.md` 187-189 行目「Note on `gh run list` vs `gh pr checks`」: 同上 (route ベース記述 + `verify-classifier.md` へ委譲)
- `skills/verify/SKILL.md` 196 行目: patch route 判定を Size ではなく `PR_NUMBER` の空判定 (実行時の実態) で行っているため `always-pr` の影響を受けない
- `docs/workflow.md` 52 / 107 行目: `always-pr: true` が Size によらず pr route を強制する旨を既に正しく記述済み。`docs/ja/workflow.md` も同様
- `docs/translation-workflow.md` の同期対象は top-level `docs/*.md` のみ。本 Issue の変更は `modules/` と `skills/` と `tests/` に閉じるため `docs/ja/` 同期は不要

**Steering Docs sync candidate (`/code` が各ファイルを読んで最終判断する)**

- `docs/structure.md` 112 / 117 行目: [Steering Docs sync candidate] `modules/verify-classifier.md` / `modules/size-workflow-table.md` の 1 行説明が最新か確認。節の追加のみでモジュールの役割は変わらないため更新不要の見込み
- `docs/workflow.md` 32 行目: [Steering Docs sync candidate] Size-based routing の記述が `ALWAYS_PR Override` 節の追加後も正しいか、prose と設定リファレンス表の両方の出現箇所を確認
- `docs/guide/customization.md` 154 行目: [Steering Docs sync candidate] `always-pr` の設定リファレンス表セルの記述が SSoT の override 規則と矛盾しないか確認
- `tests/verify-executor.bats` 12-24 行目: [Steering Docs sync candidate] `verify-classifier.md` / `spec-test-guidelines.md` の patch route テンプレート (`--commit` フィルタ) を検証するテスト。本 Issue はテンプレート文字列を変更しないため更新不要の見込み
- `tests/operate-route.bats` 16-20 行目: [Steering Docs sync candidate] `size-workflow-table.md` の operate route 記述を検証するテスト。`ALWAYS_PR Override` 節は operate route 節の**前**に挿入するため既存アサーションに影響しない見込み
- `tests/code.bats`: [Steering Docs sync candidate] Step 0 セクションのみを対象としたテスト。本 Issue の `/code` 変更は Step 10 内のため影響しない見込み

## Implementation Steps

1. `modules/size-workflow-table.md` に `### ALWAYS_PR Override` 節を新設する。挿入位置は「Size-to-Workflow Mapping Table」の表の直後、`### Diff-less Axis (operate route)` 見出しの直前。見出しレベルは h3 (`###`)。記載内容 (→ acceptance criteria 1, 2):
   - `always-pr: true` (`modules/detect-config-markers.md` が `ALWAYS_PR=true` として提供) のとき、Size 由来の `patch` route を `pr` へ promote する。promote 対象は `patch` のみで、`pr` と `split guidance` (XL) は影響を受けない
   - 優先順位テーブル (exhaustive マーカー付き): 1. operate route (`always-pr: true` と明示フラグの双方に優先)、2. 明示的な `--pr` フラグ、3. `ALWAYS_PR=true` (明示的な `--patch` も上書きする。`/code` は `--patch` を無視する旨の警告を出力)、4. 明示的な `--patch` フラグ、5. Size-to-Workflow Mapping Table
   - route 値だけでなく **route 依存の挙動**にも適用される旨: 「Size XS/S ならば patch route ゆえ PR が存在しない」という前提を持つ規則はすべてこの override の対象で、`always-pr: true` 下では PR が存在するため `github_check "gh pr checks"` の AC は有効であり `gh run list` 形式へ書き換えてはならない。`modules/verify-classifier.md` § "Patch Route CI Verification Note" への参照を置く
   - この override を適用する caller 一覧 (exhaustive マーカー付き): `skills/auto/SKILL.md` (Step 2, Step 3a)、`skills/code/SKILL.md` (Step 0, Patch route verify command check)、`skills/spec/SKILL.md` (Patch route verify command check, Step 18)、`skills/issue/SKILL.md` (Acceptance Criteria Writing Guide)、`skills/issue/spec-test-guidelines.md` (Route selection)、`skills/triage/skill-dev-verify-audit.md` (Pattern 4)、`scripts/run-auto-sub.sh`

2. `modules/verify-classifier.md` の「Patch Route CI Verification Note」節に `always-pr: true` 例外の段落を追加する (後続 1) (→ acceptance criteria 6)。挿入位置は同節冒頭の「For Issues implemented via the patch route ...」段落の直後。内容: 本節は Issue が実際に patch route を通る場合にのみ適用される。`always-pr: true` のとき Size XS/S は pr route へ promote される (`${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` § "ALWAYS_PR Override" 参照) ため PR が存在し、`github_check "gh pr checks"` が正しい形式である。route は Size 単独ではなく `ALWAYS_PR` を先に見て導出すること

3. `skills/spec/SKILL.md` の 3 箇所を変更する (後続 1) (→ acceptance criteria 3, 4):
   - Step 5「Reference Steering Documents」の `detect-config-markers.md` Read 指示の文: retain 対象を「`SPEC_PATH` and `STEERING_DOCS_PATH`」から「`SPEC_PATH`, `STEERING_DOCS_PATH`, and `ALWAYS_PR`」へ変更
   - Step 10「Patch route verify command check」: 発火条件を「if Size is `XS` or `S`」から「if `ALWAYS_PR=false` (Step 5 で retain) and Size is `XS` or `S`」へ変更。加えて、`ALWAYS_PR=true` の場合はこのチェック自体をスキップする (自動修正しない) 旨と、その根拠 (`always-pr: true` は XS/S を pr route へ promote するため PR が存在し `github_check "gh pr checks"` が正しい) を `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` § "ALWAYS_PR Override" への参照付きで追記
   - Step 18 の手順 5: Size 由来の route (`XS`/`S` → `patch`、`M`/`L` → `pr`、`XL` → `sub_issue`) を決めた**後**に ALWAYS_PR override を適用する手順を追加。`ALWAYS_PR=true` かつ route が `patch` に解決された場合は `pr` へ promote し、`always-pr: true` is set in .wholework.yml. Promoting to pr route. と出力する

4. `skills/issue/SKILL.md` の 3 箇所を変更する (後続 1) (→ acceptance criteria 5):
   - Step 2「Reference Steering Documents」(New Issue Creation) の retain 対象に `ALWAYS_PR` を追加
   - Step 4「Reference Steering Documents」(Existing Issue Refinement) の retain 対象に `ALWAYS_PR` を追加
   - 「Acceptance Criteria Writing Guide」節の `Note: Size XS/S → patch route → ...` 行の直後に例外を追記: `ALWAYS_PR=true` (`.wholework.yml` の `always-pr: true`、Step 2 / Step 4 で retain) のとき XS/S は pr route へ promote されるため、Size によらず `gh pr checks` 形式を使う。参照先は `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` § "ALWAYS_PR Override"

5. `skills/code/SKILL.md` Step 10「Patch route verify command check」の発火条件を変更する (後続 1) (→ acceptance criteria 7)。現在の「If patch route (Size is `XS`/`S` or `--patch` flag)」を、Step 0 の Route detection で解決済みの ROUTE が `patch` の場合という条件へ置き換える。Step 0 は既に ALWAYS_PR override と operate route 判定を適用済みであり、`ALWAYS_PR=true` 下では XS/S でも ROUTE は `pr` に解決される旨を括弧で補足する。Step 0 の「Flag precedence」ブロック自体は変更しない (Notes「実装との齟齬」参照)

6. `skills/issue/spec-test-guidelines.md` の「**Route selection:**」段落の末尾に例外を追記する (後続 1) (→ acceptance criteria 8)。内容: `.wholework.yml` に `always-pr: true` が設定されている (`ALWAYS_PR=true`) とき XS/S は pr route へ promote されるため、Size によらず `gh pr checks` 形式を使う。参照先は `modules/size-workflow-table.md` § "ALWAYS_PR Override"

7. `skills/triage/SKILL.md` の「## Configuration Detection」節の `detect-config-markers.md` Read 指示の文で、retain 対象を「`STEERING_DOCS_PATH`」から「`STEERING_DOCS_PATH` and `ALWAYS_PR`」へ変更する (後続 1)。この節は Single Issue Execution と Bulk Execution の双方より手前にある共通セクションなので、両経路から `ALWAYS_PR` を参照できる

8. `skills/triage/skill-dev-verify-audit.md` の「### Pattern 4: patch route × `gh pr checks` 不整合」を変更する (後続 7) (→ acceptance criteria 9):
   - Detect 条件を「Issues with Size XS or S (patch route)」から「Issues with Size XS or S **and `ALWAYS_PR=false`** (patch route)」へ変更
   - 「Detection approach:」の箇条書きに 1 項目追加: `ALWAYS_PR` は `skills/triage/SKILL.md` の「Configuration Detection」節 (Single / Bulk 双方の手前にある共通セクション) で retain 済みの値を参照する。`ALWAYS_PR=true` のときは Pattern 4 全体をスキップする — `always-pr: true` は XS/S を pr route へ promote するため `gh pr checks` が正しい形式である (`modules/size-workflow-table.md` § "ALWAYS_PR Override" 参照)

9. `tests/size-workflow-table.bats` に shallow test を 2 件追加する (後続 1) (→ acceptance criteria 10)。既存ファイルと同じ `grep -q "$SIZE_WORKFLOW_TABLE"` パターンを使う (bash 3.2+ 互換):
   - `@test "size-workflow-table: ALWAYS_PR Override section is documented"` — `grep -q "ALWAYS_PR Override"`
   - `@test "size-workflow-table: ALWAYS_PR Override documents patch to pr promotion"` — `grep -q "always-pr: true"` かつ promotion を表す語 (`promot`) の存在を `grep -qi` で確認

## Verification

### Pre-merge

- <!-- verify: rubric "modules/size-workflow-table.md に always-pr: true 時の patch → pr promotion が override として明記され、operate route / explicit flag との優先順位が示されている" --> `size-workflow-table.md` に ALWAYS_PR override が明記されている
- <!-- verify: grep "ALWAYS_PR Override" "modules/size-workflow-table.md" --> `size-workflow-table.md` に `ALWAYS_PR Override` 節が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md の Patch route verify command check が ALWAYS_PR=true の場合に自動修正をスキップする条件を持つ" --> `/spec` の patch route check が `always-pr` を考慮する
- <!-- verify: grep "ALWAYS_PR" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` が `ALWAYS_PR` を参照している
- <!-- verify: rubric "skills/issue/SKILL.md の AC 作成ガイドにある Size XS/S → patch route の注記に、always-pr: true の場合は pr route になる旨が追記されている" --> `/issue` の AC 作成ガイドが `always-pr` を考慮する
- <!-- verify: rubric "modules/verify-classifier.md の patch route 判定の説明に always-pr の考慮が追記されている" --> `verify-classifier.md` が `always-pr` を考慮する
- <!-- verify: rubric "skills/code/SKILL.md の Patch route verify command check の発火条件が、Size XS/S からの再導出ではなく Step 0 で解決済みの ROUTE (ALWAYS_PR override 適用済み) に基づいている" --> `/code` の patch route check が Step 0 の ROUTE を参照する
- <!-- verify: grep "always-pr" "skills/issue/spec-test-guidelines.md" --> `skills/issue/spec-test-guidelines.md` の Route selection が `always-pr` を考慮する
- <!-- verify: grep "ALWAYS_PR" "skills/triage/skill-dev-verify-audit.md" --> `skills/triage/skill-dev-verify-audit.md` の Pattern 4 が `ALWAYS_PR` を考慮する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイート (`tests/size-workflow-table.bats` の ALWAYS_PR Override テストを含む) が CI で PASS する

### Post-merge

- `.wholework.yml` に `always-pr: true` を一時的に設定した状態 (wholework 自体には常設しないため、本リポジトリで一時追加するか、既に `always-pr: true` を設定している downstream プロジェクトを使う) で、Size XS/S のテスト用 Issue に対して `/spec` を非対話モードで実行し、`github_check "gh pr checks"` が `gh run list` 形式へ自動修正されないことを確認する。確認後は `.wholework.yml` の一時変更を元に戻す

## Tool Dependencies

### Bash Command Patterns

- なし (新規スクリプトの追加も新規コマンドパターンの使用もない)

### Built-in Tools

- `Read` / `Edit`: 既存 Markdown ファイルの読み取り・編集。全対象 skill の `allowed-tools` に登録済み

### MCP Tools

- なし

## Uncertainty

- **`rubric` verify command の判定安定性**: AC 1・3・5・6・7 は `rubric` による意味的判定であり、grader の解釈に依存する。AC 2・4・8・9 に決定的な `grep` を併置して補完済み
  - **検証方法**: `/review` safe mode および `/verify` full mode での `rubric` 実行結果を確認する
  - **影響範囲**: Implementation Steps 1, 3, 4, 5 の記述粒度 (grader が判断できる程度に具体的な文言を書く必要がある)
- **`/triage` Bulk Execution からの `ALWAYS_PR` 参照可能性**: `## Configuration Detection` は `## Single Issue Execution` と `## Bulk Execution` の双方より手前にある top-level セクションであるため、prose 実行順序上は両経路から参照可能と判断した。ただし Bulk Execution の各 substep が Configuration Detection の結果を明示的に引き継ぐ記述は現状ない
  - **検証方法**: `skills/triage/SKILL.md` のセクション順序を Read で確認済み (67 行目 Configuration Detection → 73 行目 Single Issue Execution → 279 行目 Bulk Execution)
  - **影響範囲**: Implementation Steps 7, 8。万一参照できない場合は `skill-dev-verify-audit.md` 内で `${CLAUDE_PLUGIN_ROOT}/scripts/get-config-value.sh always-pr false` を直接呼ぶ形へ切り替える (`scripts/run-auto-sub.sh` 867 行目と同じ手段)

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — `/issue 1061 --non-interactive` によるリファインメント結果。トリアージ結果 (Type=Bug / Size=L / Value=3)、Background の技術的主張を grep で照合済みであること、AC2 の常時 PASS パターン検出と `ALWAYS_PR Override` への修正、非対話モードでの Auto-Resolve 2 件、Size=L の sub-issue 分割評価が High-Stakes Decision としてスキップされたこと — https://github.com/saitoco/wholework/issues/1061#issuecomment-5113545811

## Notes

### 実装との齟齬 (Conflict with implementation)

Issue 本文 対応方針 A は「優先順位は既存実装 (`skills/code/SKILL.md` Step 0) に合わせ **operate > explicit flag > ALWAYS_PR > Size** とする」と記述しているが、`skills/code/SKILL.md` 88-92 行目の実際の列挙ルールはこれと一致しない。

- 88 行目の見出し文字列: `**Flag precedence (explicit flag > ALWAYS_PR > Size auto-detection)**`
- 90 行目の実ルール: `ALWAYS_PR=true` AND `--patch` → 「The --patch flag is ignored; pr route is forced」の警告を出して **pr route** を選択

つまり `--patch` に対しては `ALWAYS_PR` が優先する。見出し文字列が実挙動を正しく表していない (`--pr` については見出しどおり明示フラグが先に評価されるが、結果が `ALWAYS_PR=true` と一致するため衝突しない)。

**解決方針 (非対話モードでのモデル判断)**: SSoT (`modules/size-workflow-table.md` の新 `ALWAYS_PR Override` 節) には見出し文字列ではなく実挙動 (operate > `--pr` > `ALWAYS_PR` > `--patch` > Size) を記述する。`skills/code/SKILL.md` 88 行目の見出し文字列自体は変更しない — 本 Issue のスコープ外の文言変更であり、`tests/code.bats` の Step 0 アサーション群に不要な影響を与えうるため。SSoT 側が実挙動を正しく記述していれば、見出し文字列の緩さは新たな drift を生まない。必要なら follow-up Issue で扱う。

### スコープ拡大の根拠

Issue 本文 対応方針 B は 4 箇所を挙げているが、コードベース調査で同一クラスの箇所が 3 つ追加で見つかったため 8 箇所へ拡大した (Issue body の Auto-Resolve Log に記録済み)。

| 追加箇所 | 現在の記述 | 拡大の理由 |
|---|---|---|
| `skills/code/SKILL.md` Step 10 | 「If patch route (Size is `XS`/`S` or `--patch` flag)」 | `/spec` 側だけ直しても同じ自動修正が `/code` 側で発火するため、Background の「具体的な害」の連鎖が残る |
| `skills/issue/spec-test-guidelines.md` | 「Size XS/S → patch route → use `gh run list` form」 | `skills/issue/SKILL.md` の注記と同内容の skill-dev Domain file 版。SKILL.md だけ直すと Domain file 側に古い記述が残る |
| `skills/triage/skill-dev-verify-audit.md` Pattern 4 | 「Detect: Issues with Size XS or S (patch route)」 | `/triage` の AC 監査が正しい `gh pr checks` を欠陥と判定し `gh run list` へ書き換えるため、害の連鎖が `/issue` より前の段階から始まる |

対応方針 B は「(案)」と明記されており、Purpose の「Size から workflow route を導出する**全箇所**で `always-pr` 設定を honor し」が上位の指示と判断した。

### `always-pr` 取得手段の統一

`ALWAYS_PR` の取得手段は 2 系統ある。

- `modules/detect-config-markers.md` の retain (SKILL.md 系: `/auto`・`/code`・`/spec`・`/issue`・`/triage`)
- `scripts/get-config-value.sh always-pr false` の直接呼び出し (`scripts/run-auto-sub.sh` 867 行目 — bash スクリプトのため)

本 Issue では SKILL.md 系はすべて前者に統一する。`skills/triage/skill-dev-verify-audit.md` は Domain file だが、`/triage` SKILL.md の Configuration Detection で retain された値を参照する形とし、Domain file 内から直接 `get-config-value.sh` を呼ぶ形は採らない (取得手段が二系統に分かれるのを避けるため)。

### `allowed-tools` 影響チェック

新規 `scripts/*.sh` の追加はないため、`allowed-tools` の追加は不要。`/triage` の `allowed-tools` には `Read` が含まれており、`detect-config-markers.md` 経由の `.wholework.yml` 読み取りは既存の Configuration Detection ステップで実施済みのため追加変更は生じない。

### 変更ファイル種別と bash 互換

`tests/size-workflow-table.bats` のみがシェルスクリプト系の変更対象。追加するのは既存ファイルと同一の `grep -q` / `grep -qi` パターンのみで、`mapfile` などの bash 4+ 機能は使わない — bash 3.2+ 互換。

### `docs/ja/` 翻訳同期

`docs/translation-workflow.md` の同期義務は top-level `docs/*.md` を対象とする。本 Issue の変更対象は `modules/`・`skills/`・`tests/` に閉じており、`docs/ja/` 配下に対応するミラーは存在しないため翻訳同期は発生しない。
