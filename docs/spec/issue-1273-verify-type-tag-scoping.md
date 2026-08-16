# Issue #1273: verify-type: タグ抽出を HTML コメント内に限定し条件文の引用による誤分類を解消

## Overview

post-merge AC の `verify-type` タグを読む処理が、行内の最初の `verify-type: <t>` 出現を substring で拾う実装になっている。条件文のプロースがタグ名を正当に引用すると、実タグではなくプロース側が抽出され、AC が誤分類される。

タグ抽出を **HTML コメント内に限定**することでこの誤分類を解消する。参照実装は `scripts/collect-verify-retention-stats.sh` (748e3cbe) が既に持っている。あわせて `skills/audit/SKILL.md` の Waiting Count 散文定義を substring から同じ基準へ改め、過去レポートとの非互換を追記注記で扱う。

`/spec` の実装調査で、Issue 本文の影響箇所表のうち 2 行を実測により更新した (詳細は Notes 参照):

- `scripts/check-skill-change-observation-ac.sh` は「誤分類なし」ではなく、**同一行に別の HTML コメントがある場合に誤検知する** (greedy `<!--.*-->` 由来)
- `scripts/get-auto-session-report.sh` は「潜在」ではなく、**実測で誤分類を再現した**

## Reproduction Steps

すべて 2026-08-16、worktree `spec/issue-1273` (base = main) で実測。

1. 次の 5 行を含むファイルを用意する (`.tmp/vt-case-a.md` の `### Post-merge` セクション):

   | # | 行の形 | 実タグ |
   |---|---|---|
   | 1 | 条件文が `` `verify-type: manual` `` を引用、実タグは observation | observation |
   | 2 | 通常の observation 行 | observation |
   | 3 | タグも verify command もない行 | (manual 扱い) |
   | 4 | 条件文が `` `verify-type: observation` `` を引用、実タグは manual | manual |
   | 5 | 先行 HTML コメント (`verify: rubric "...verify-type: observation..."`) + 後続の実タグ manual | manual |

2. `scripts/scan-pending-ac.sh` の awk 抽出ロジック (`match($0, /verify-type: [a-zA-Z_]+/)`) を適用すると、
   期待 `observation / observation / manual / manual / manual` に対し
   実測は **`manual / observation / manual / observation / observation`** — 1・4・5 行目が誤分類。

3. 同じファイルに `skills/*/SKILL.md` への言及を足して `bash scripts/check-skill-change-observation-ac.sh` を実行すると、
   実タグ manual の 5 行目が「`session=next` 欠落の observation AC」として exit 2 で報告される (**誤検知**)。
   4 行目 (プロースが HTML コメント外で引用) は誤検知しない。

4. `printf '%s\n' '- [ ] 未チェックの `verify-type: observation event=auto-run` 行を集計対象から外れていることを確認 <!-- verify-type: manual -->' | grep -qE "verify-type: observation event="`
   → **マッチする** (`scripts/get-auto-session-report.sh:610` と同じ判定。実タグ manual の行が observation として計上される)。

## Root Cause

タグの抽出パターンが **HTML コメント境界を要求していない**ことが唯一の根因。行内のどこに現れた `verify-type: <t>` でもマッチするため、次の 2 経路で誤る:

- **経路 A (プロース引用)**: 条件文が地の文・インラインコードでタグ名を引用する。`scan-pending-ac.sh` / `post_merge_check.sh` / `opportunistic-search.sh` / `get-auto-session-report.sh` が該当。
- **経路 B (別コメント内引用)**: 同一行の別の HTML コメント (典型は `<!-- verify: rubric "..." -->`) がタグ名を含む。`check-skill-change-observation-ac.sh` の `grep -oE '<!--.*-->'` は greedy なので、最初の `<!--` から最後の `-->` までを 1 区間として切り出し、中間のコメント内容ごと `tag` に取り込む。

正しい抽出は `<!--` の直後 (空白のみ許容) に `verify-type:` が続くことを要求すればよい。`scripts/collect-verify-retention-stats.sh:159-162` が既にこの形。

修正の副次効果として、`rank-verify-backlog.sh:117` (`<!--[ \t]*verify:` 済み) / `skills/auto/SKILL.md:1267-1269` (`<!-- verify-type: X` 済み) / `skills/verify/SKILL.md` (`<!-- verify-type: X -->` 済み) と表記基準が揃う。

## Consumed Comments

cutoff: `2026-08-16T05:12:40Z` (直近の `phase/*` ラベル付与)

| login | authorAssociation | trust tier | 要旨 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` Issue Retrospective。Waiting Count 非互換の扱いを (a) で自動解決、AC 変更理由を記録 | https://github.com/saitoco/wholework/issues/1273#issuecomment-5305874685 |
| saito | MEMBER | first-class | `/triage` AC 監査。Pre-merge AC 4 件が「既存テストファイル実行に起因する常時 PASS」(Pattern 2) に該当。修復案として `bats --count --filter` 形を提示し、判断を `/spec` に委譲 | https://github.com/saitoco/wholework/issues/1273#issuecomment-5305895613 |

2 件目の指摘は採用した (Pattern 2 は実在する問題)。ただし修復手段は `--count --filter` 形ではなく `file_contains` + `command` の 2 コマンド形を採る — 理由は Notes「Triage AC 監査の修復案からの逸脱」参照。

## Changed Files

- `modules/verify-classifier.md`: `### Tag Extraction Rule (consumers)` セクションを新設 — タグは HTML コメント内からのみ読むという正準ルール、awk 形 (`[ \t]*`) と `grep -E` 形 (`[[:space:]]*`) の両方の canonical pattern、および consumer 一覧を記載 (SSoT)
- `scripts/scan-pending-ac.sh`: `AWK_PROGRAM` 内の `match(line, /verify-type: [a-zA-Z_]+/)` を HTML コメント限定形へ置換 — bash 3.2+ 互換 (awk のみ)
- `scripts/post_merge_check.sh`: `extract_manual_acs()` の `grep "verify-type: manual"` と `grep -v "ac-tier: preview"` を HTML コメント限定形へ置換 — bash 3.2+ 互換
- `scripts/opportunistic-search.sh`: event モード (`:351`) / opportunistic モード (`:354`) のタグマッチを HTML コメント限定形へ置換。event モードは `event=` 属性も同一コメント内に限定 (awk `index()` で literal 照合)。opportunistic モードの `grep -F "$SKILL_NAME"` は行スコープのまま — bash 3.2+ 互換
- `scripts/check-skill-change-observation-ac.sh`: `tag=$(... grep -oE '<!--.*-->')` の greedy 抽出を `verify-type` コメント限定の非 greedy 形へ置換 — bash 3.2+ 互換
- `scripts/get-auto-session-report.sh`: Verify Phase Residuals 集計 (`:610` / `:611` / `:618`) の observation / opportunistic 判定を HTML コメント限定形へ置換 — bash 3.2+ 互換
- `skills/audit/SKILL.md`: Observation / Opportunistic / Manual の各 Waiting Count 定義 (`:357` / `:361` / `:365`) を「HTML コメント内のタグを読む」基準へ改め、Section 8 のテーブル直後に過去レポート非互換の注記指示を追加
- `tests/scan-pending-ac.bats`: 新規テストケース `html-comment scoped tag extraction` を追加 (3 ケース検証)
- `tests/post_merge_check.bats`: 新規テストケース `html-comment scoped manual extraction` を追加 (3 ケース検証)
- `tests/opportunistic-search.bats`: 新規テストケース `html-comment scoped tag match` を追加 (3 ケース検証)
- `tests/check-skill-change-observation-ac.bats`: 新規テストケース `html-comment scoped tag regression` を追加 (3 ケース検証)
- `tests/audit-auto-session.bats`: 新規テストケース `html-comment scoped residual tally` を追加 (3 ケース検証)。`get-auto-session-report.sh` は `tests/get-auto-session-report.bats` と `tests/audit-auto-session.bats` の 2 ファイルから参照されるが、verify-type breakdown の既存テスト (`:141`) は後者にあるため新規ケースも後者へ置く
- `scripts/collect-verify-retention-stats.sh`: **変更不要** (`:159-162` が既に HTML コメント限定形 — 参照実装。grep で確認済み)
- `scripts/rank-verify-backlog.sh`: **変更不要** (`:117` が `<!--[ \t]*verify:` で既にコメント限定。grep で確認済み)
- `skills/auto/SKILL.md` / `skills/verify/SKILL.md`: **変更不要** (`<!-- verify-type: X` 形で既にコメント限定。grep `-rn "lines containing|contain \`<!-- verify-type"` で全 skills/modules を走査し、substring 形は `skills/audit/SKILL.md` の 3 箇所のみと確認済み)
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `scan-pending-ac.sh` (`:215` / `:207`) / `post_merge_check.sh` (`:213` / `:205`) / `get-auto-session-report.sh` (`:203` / `:195`) / `check-skill-change-observation-ac.sh` (`:258` / `:250`) の説明行を確認済み — いずれも抽出方式に言及せず役割のみを記述しているため**変更不要**。新規ファイル追加もないためファイル数カウントの更新も不要
- `docs/ja/` translation sync: **対象外** (`docs/translation-workflow.md` の同期義務は top-level `docs/*.md` に限定され、本 Issue の Changed Files に該当ファイルなし)

## Implementation Steps

1. `modules/verify-classifier.md` に `### Tag Extraction Rule (consumers)` セクションを追加する。記載内容: (a) `verify-type` タグは HTML コメント内からのみ読む (`<!--` の直後に空白のみを挟んで `verify-type:` が続くことを要求する)、(b) awk 用 canonical pattern `/<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+/` と `grep -E` 用 canonical pattern `<!--[[:space:]]*verify-type:[[:space:]]*<type>` (grep ERE のブラケット内 `\t` は実装依存のため POSIX クラスを使う)、(c) 参照実装 `scripts/collect-verify-retention-stats.sh`、(d) consumer 一覧。「条件文が正当にタグ名を引用しうる」ことを根拠として明記する (→ 受入条件 7)

2. `scripts/scan-pending-ac.sh` の `AWK_PROGRAM` を修正する (→ 受入条件 1)。`vtype = "manual"` 既定の直後にある `if (match(line, /verify-type: [a-zA-Z_]+/)) { vtype = substr(line, RSTART + 13, RLENGTH - 13) }` を、`collect-verify-retention-stats.sh:159-162` と同じ「match → substr → sub で接頭辞除去」形へ置換する。**既定値の意味論は変更しない** — タグ無し行を `manual` に倒す挙動 (ヘッダコメント記載) と、`auto` を候補から除外しない挙動を維持する。あわせてヘッダコメントの `verify_type:` 説明に「HTML コメント内からのみ読む」旨を追記する。`tests/scan-pending-ac.bats` に `@test` 名へ `html-comment scoped tag extraction` を含む新規ケースを追加し、(a) プロースが別のタグ名を引用する行が実タグで分類される、(b) 通常の行が従来どおり分類される、(c) タグも verify command もない行が manual に倒れる、の 3 ケースを検証する (既存の `gh issue list` を `PATH` 経由でモックする setup を踏襲)

3. `scripts/post_merge_check.sh` の `extract_manual_acs()` を修正する (after 1) (→ 受入条件 2)。`grep "verify-type: manual"` を `grep -E '<!--[[:space:]]*verify-type:[[:space:]]*manual'` へ、`grep -v "ac-tier: preview"` を `grep -vE '<!--[[:space:]]*ac-tier:[[:space:]]*preview'` へ置換する (`ac-tier` は `<!-- ac-tier: preview -->` という独立 HTML コメント形 — `skills/issue/SKILL.md:76` で確認済み。除外側を素の substring のまま残すと、プロースが `ac-tier: preview` を引用しただけで実 manual AC が落ちるため、同時に対処する)。`tests/post_merge_check.bats` に `@test` 名へ `html-comment scoped manual extraction` を含む新規ケースを追加し、Step 2 と同じ 3 ケースを検証する

4. `scripts/opportunistic-search.sh` の 2 つのマッチ経路を修正する (after 1) (→ 受入条件 3)。event モードは `grep "verify-type: observation" | grep "event=${EVENT_NAME}"` を、`awk -v evt="$EVENT_NAME"` で `match($0, /<!--[ \t]*verify-type:[ \t]*observation[^>]*/)` した区間に対し `index(tag, "event=" evt) > 0` を評価する形へ置換する (`index()` を使うのは `EVENT_NAME` が無検証の外部入力であり、ERE へ内挿すると正規表現メタ文字の注入面ができるため)。opportunistic モードは `grep "verify-type: opportunistic"` を `grep -E '<!--[[:space:]]*verify-type:[[:space:]]*opportunistic'` へ置換し、`grep -F "$SKILL_NAME"` は**行スコープのまま残す** (スキル名は条件文の散文に正当に現れる — `modules/verify-classifier.md:161` が実例)。`set -euo pipefail` 下でパイプが空になる場合に備え既存の `|| true` を維持する。`tests/opportunistic-search.bats` に `@test` 名へ `html-comment scoped tag match` を含む新規ケースを追加し、Step 2 と同じ 3 ケースを検証する

5. `scripts/check-skill-change-observation-ac.sh` の greedy タグ抽出を修正する (after 1) (→ 受入条件 4)。`tag=$(printf '%s\n' "$line" | grep -oE '<!--.*-->' || true)` を `tag=$(printf '%s\n' "$line" | grep -oE '<!--[[:space:]]*verify-type:[[:space:]]*[a-zA-Z_]+[^>]*' || true)` へ置換する。後続の `case "$tag" in *"verify-type: observation"*)` と `*"session=next"*)` の判定文はそのまま (照合の寛容度を変えない — 現状もコロン直後の空白を要求している)。ヘッダコメントの「False positives are acceptable」記述に、本修正で塞いだ誤検知経路 (同一行の別 HTML コメントによる引用) を追記する。`tests/check-skill-change-observation-ac.bats` に `@test` 名へ `html-comment scoped tag regression` を含む新規ケースを追加し、(a) 先行する `verify: rubric` コメントが `verify-type: observation` を引用しつつ実タグが manual の行を報告しない、(b) 通常の observation 行 (`session=next` 欠落) は従来どおり exit 2 で報告する、(c) `session=next` 付きの observation 行は報告しない、の 3 ケースを検証する

6. `scripts/get-auto-session-report.sh` の Verify Phase Residuals 集計を修正する (after 1) (→ 受入条件 5)。`grep -qE "verify-type: observation event="` を `grep -qE '<!--[[:space:]]*verify-type:[[:space:]]*observation[^>]*event='` へ、`grep -oE "verify-type: observation event=[^ >]+" | sed 's/verify-type: observation event=//'` を `grep -oE '<!--[[:space:]]*verify-type:[[:space:]]*observation[^>]*event=[^ >]+' | sed 's/.*event=//'` へ、`grep -qE "verify-type: opportunistic"` を `grep -qE '<!--[[:space:]]*verify-type:[[:space:]]*opportunistic'` へ置換する。else 節が manual に倒れる既定は変更しない。`tests/audit-auto-session.bats` に `@test` 名へ `html-comment scoped residual tally` を含む新規ケースを追加し、Step 2 と同じ 3 ケース (プロース引用行が実タグで計上される / 通常行が従来どおり計上される / タグ無し行が manual に計上される) を `ISSUE_BODY_DIR` フィクスチャで検証する

7. `skills/audit/SKILL.md` の Waiting Count 定義 3 箇所 (`:357` Observation / `:361` Opportunistic / `:365` Manual) を、「unchecked (`- [ ]`) lines whose tag appears **inside an HTML comment**」の基準へ書き換える (after 1) (→ 受入条件 6)。Manual の `ac-tier: preview` 除外も同じ基準へ揃える。加えて Section 8 のメトリクステーブル直後に、過去レポートとの非互換を扱う注記指示を追加する — 方針 **(a)**: 定義変更を明記し、以降の `docs/stats/YYYY-MM-DD.md` に「measurement method change」の注記を含めること、および #1273 以前のレポート (`docs/stats/2026-08-05.md` の baseline 79 件を含む) の Waiting Count と直接比較しないことを求める。過去レポートの再出力・両方式の並行出力は**行わない** (`docs/stats/2026-08-05.md` § 11 訂正 1 / 訂正 2 と同型の追記注記のみ)

8. 全 bats スイートを実行して回帰がないことを確認する (after 2, 3, 4, 5, 6, 7) (→ 受入条件 8)。並列実行時のみ FAIL するテスト (`tests/post_merge_check.bats` の既知フレーク — `docs/tech.md` § CI bats Parallel/Serial Split) を観測した場合は単独再実行で切り分け、本 Issue の変更に起因しないことを確認したうえで Spec の `## Code Retrospective` に記録する

## Verification

### Pre-merge

- <!-- verify: file_contains "tests/scan-pending-ac.bats" "html-comment scoped tag extraction" --> <!-- verify: command "bats tests/scan-pending-ac.bats" --> `scripts/scan-pending-ac.sh` の verify-type 抽出が HTML コメント内に限定され、bats テストで (a) プロースが別のタグ名を引用する行が実タグで分類される、(b) 通常の行が従来どおり分類される、(c) タグも verify command もない行が manual に倒れる、の 3 ケースが検証されている
- <!-- verify: file_contains "tests/post_merge_check.bats" "html-comment scoped manual extraction" --> <!-- verify: command "bats tests/post_merge_check.bats" --> `scripts/post_merge_check.sh` の manual AC 抽出が HTML コメント内に限定され、同様の 3 ケースが bats テストで検証されている
- <!-- verify: file_contains "tests/opportunistic-search.bats" "html-comment scoped tag match" --> <!-- verify: command "bats tests/opportunistic-search.bats" --> `scripts/opportunistic-search.sh` の observation / opportunistic マッチが HTML コメント内に限定され、同様の 3 ケースが bats テストで検証されている
- <!-- verify: file_contains "tests/check-skill-change-observation-ac.bats" "html-comment scoped tag regression" --> <!-- verify: command "bats tests/check-skill-change-observation-ac.bats" --> `scripts/check-skill-change-observation-ac.sh` のタグ抽出が同一行の別 HTML コメントを巻き込まない形に修正され、誤検知しないこと・通常の検出が維持されることが bats テストで検証されている
- <!-- verify: file_contains "tests/audit-auto-session.bats" "html-comment scoped residual tally" --> <!-- verify: command "bats tests/audit-auto-session.bats" --> `scripts/get-auto-session-report.sh` の Verify Phase Residuals 集計が HTML コメント内に限定され、同様の 3 ケースが bats テストで検証されている
- <!-- verify: rubric "audit SKILL.md の Manual/Observation/Opportunistic Waiting Count 定義が HTML コメント内のタグ抽出を要求しており、過去レポートとの非互換への対処方針が記述されている" --> <!-- verify: file_contains "skills/audit/SKILL.md" "inside an HTML comment" --> `skills/audit/SKILL.md` の Waiting Count 定義が substring ではなく HTML コメント内のタグを見る旨に改められ、過去レポートとの非互換の扱い ((a) 追記注記方式) が明記されている
- <!-- verify: file_contains "modules/verify-classifier.md" "Tag Extraction Rule" --> `modules/verify-classifier.md` にタグ抽出の正準ルール (HTML コメント限定、awk / grep 双方の canonical pattern、consumer 一覧) が SSoT として記載されている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 修正後に `scripts/collect-verify-retention-stats.sh --window 2026-05-07` と `scripts/scan-pending-ac.sh` の manual 分類結果を突き合わせ、両者が一致することを確認する (現状は 19 対 18 で 1 件ずれている)

## Tool Dependencies

### Bash Command Patterns

- 追加なし (`bats`, `grep`, `awk`, `sed` はいずれも既存の `command` verify command 経由で実行される)

### Built-in Tools

- 追加なし (`Read` / `Edit` / `Write` / `Grep` / `Glob` はすべて既存 allowed-tools に含まれる)

### MCP Tools

- なし

## Uncertainty

- **grep ERE のブラケット内 `\t` の解釈**: `grep -E '<!--[ \t]*verify-type:'` はブラケット内 `\t` をタブとして解釈する実装 (macOS で実測、`<!--tverify-type:` は不一致) と、バックスラッシュまたは `t` のリテラル集合として解釈する実装 (GNU grep のドキュメント記載) がある。
  - **検証方法**: いずれの解釈でも通常のタグ (`<!-- verify-type:`、空白 1 個) はマッチするため実害はないが、曖昧さを避けるため grep 経路では POSIX クラス `[[:space:]]*` を使う (Implementation Steps に反映済み)。awk 経路は `[ \t]` が確実にタブとして解釈されるため、参照実装 `collect-verify-retention-stats.sh` と同じ表記を維持する。
  - **影響範囲**: Implementation Steps 3, 4 (opportunistic モード), 5, 6

- **`bats --count --filter` 形を採らないことによる残余**: `file_contains` はテスト名の存在のみを保証し、そのテスト自体が PASS したことは `command "bats tests/<file>.bats"` (スイート全体) で担保する。個別テストの PASS を単独で示す verify command にはなっていない。
  - **検証方法**: 2 コマンドの組は「新規テストが存在する」かつ「そのテストを含むスイートが PASS する」を同時に要求するため、実質的な保証は `--filter` 形と等価。`/review` safe mode で UNCERTAIN にならない点で優位 (Notes 参照)。
  - **影響範囲**: 受入条件 1-5

## Notes

### 実装との矛盾 (Issue 本文の影響箇所表の訂正)

Issue 本文の影響箇所表は 2 行が実装調査と食い違っていた。いずれも `/spec` で実測して確認した。

1. **`scripts/check-skill-change-observation-ac.sh` — 「誤分類なし」は誤り**
   Issue 本文の引用: 「誤分類なし (`/issue` 時点で再検証済み)」「プロース側の `verify-type: observation` 引用は `<!-- -->` の外側にあるため `tag` には含まれず、コメント外の文字列で誤マッチすることはない」
   実装 (`scripts/check-skill-change-observation-ac.sh:39`): `tag=$(printf '%s\n' "$line" | grep -oE '<!--.*-->')` は **greedy** であり、同一行に HTML コメントが 2 つある場合は最初の `<!--` から最後の `-->` までを 1 区間として切り出す。中間のコメント内容 (例: `<!-- verify: rubric "verify-type: observation を確認" -->`) が `tag` に含まれるため、実タグが `manual` の行を observation として誤検出する。`/issue` 時点の検証は「コメント **外**の引用」だけを試したため、この経路が見落とされていた。
   **解決**: AC 4 を「回帰確認テストのみ」から「抽出の修正 + テスト」へ変更し、Implementation Step 5 を追加した。

2. **`scripts/get-auto-session-report.sh` — 「潜在」ではなく実測で再現**
   Issue 本文の引用: 「同上 (`event=` を要求するぶん誤マッチしにくい)」
   実測: 条件文が `` `verify-type: observation event=auto-run` `` を引用する行 (実タグ manual) は `:610` の `grep -qE "verify-type: observation event="` にマッチする。#1251 / #1270 のように AC の型を議論する Issue では現実的な行形。
   **解決**: スコープに含め、受入条件 5 と Implementation Step 6 を追加した。

### 自動解決ログ (非対話モード)

Size L のため検出上限は 5 点 (`modules/ambiguity-detector.md` Size Routing Table)。5 点すべてを自動解決した。

1. **`skills/audit/SKILL.md` の Waiting Count 定義変更に伴う過去レポート非互換の扱い: (a) 追記注記方式を採用** — reason: `docs/stats/2026-08-05.md` § 11 (訂正 1 / 訂正 2) が、代用計測の不整合を過去レポートの再出力・二重表示なしに追記注記のみで扱った既存先例であり、(a) はこれと同型。(b) の並行出力には先例がなく、過去レポート全 5 件 (`docs/stats/2026-04-13` 〜 `2026-08-05`) の再計算コストが発生する。`/issue` 時点の暫定推奨と一致するため方針を確定した。
   - 不採用: (b) 変更前後の両方を出力し移行期間を設ける

2. **`scripts/get-auto-session-report.sh` をスコープに含めるか: 含める** — reason: Issue 本文の影響箇所表に既に列挙されており、Purpose も「`verify-type` タグの抽出を HTML コメント内に限定」と一般化されている。上記のとおり実測で誤分類を再現したため「潜在」ではなく確認済みの不具合。除外すると、修正後の `skills/audit/SKILL.md` の定義と `/audit auto-session` の実測値が食い違い続ける。
   - 不採用: 別 Issue へ切り出す (同根・同一パターンの 1 行修正 3 箇所であり、分割コストが実装コストを上回る)

3. **共通ヘルパースクリプトへ切り出すか、各スクリプトにインライン展開するか: インライン + `modules/verify-classifier.md` に正準ルールを記載** — reason: 抽出は awk / `grep -E` / bash `case` と実行形態がスクリプトごとに異なり、単一の呼び出し可能インタフェースに畳めない。共通スクリプト化すると新規 `scripts/*.sh` の追加となり 6 つの reader SKILL.md の `allowed-tools` 更新が必要になるうえ、worktree 内では `source` ベースの関数呼び出しが isolation guard に阻まれる (`modules/worktree-lifecycle.md` § `source`-based shell function calls)。参照実装 `collect-verify-retention-stats.sh` も既にインライン展開の前例。SSoT はドキュメント側 (`modules/verify-classifier.md`) に置く。
   - 不採用: `scripts/extract-verify-type.sh` を新設して全 consumer から呼ぶ

4. **`opportunistic-search.sh` で `event=` / SKILL_NAME をどこまでコメント内に限定するか: `event=` は限定、SKILL_NAME は行スコープのまま** — reason: `event=` はタグの属性 (`<!-- verify-type: observation event=auto-run -->`、リポジトリ内 94 + 52 件の実例すべてで `verify-type:` の直後に出現) なので同一コメント内に限定するのが正しい。一方スキル名は条件文の散文に正当に現れる (`modules/verify-classifier.md:161` の `` ...when `/spec` runs <!-- verify-type: opportunistic --> `` が実例) ため、コメント内に限定すると既存 AC が一斉にマッチしなくなる。
   - 不採用: 両方ともコメント内に限定 / 両方とも行スコープのまま

5. **`post_merge_check.sh` の `ac-tier: preview` 除外も同時に対処するか: 対処する** — reason: 同一関数内の隣接する 1 行であり、除外側を素の substring のまま残すと、条件文が `ac-tier: preview` を引用しただけで実 manual AC が抽出から落ちる (fail-closed 方向の誤り)。`verify-type` だけ直して `ac-tier` を残すと、同じ関数内で 2 つの異なる基準が併存する。
   - 不採用: `ac-tier` は別 Issue へ切り出す

### Triage AC 監査の修復案からの逸脱

`/triage` AC 監査コメントは Pre-merge AC 4 件を Pattern 2 (既存テストファイル実行に起因する常時 PASS) と判定し、修復案として `` command "test \"$(bats --count --filter '<name>' <file>)\" -gt 0 && bats --filter '<name>' <file>" `` 形を提示した。**指摘は採用するが、修復手段は変更する**:

- 採用しない理由: `modules/verify-patterns.md:32` は `command` 内でのカウント集計 (`test $(...) -ge N` 形) を「CI ジョブと対応づけにくく `/review` safe mode で UNCERTAIN になる」アンチパターンとして明示している。Pre-merge AC は `/review` (safe mode) が評価するため、UNCERTAIN 化は検証の空洞化を招く。
- 代替: `file_contains "tests/<file>.bats" "<新規テスト名の部分文字列>"` (safe mode で `always_allow`、決定的 PASS/FAIL) と `command "bats tests/<file>.bats"` (CI ジョブへマップ可能) の 2 コマンドを同一 AC 行に付す。両者が揃って初めて「新規テストが存在し、それを含むスイートが PASS する」ことを要求するため、Pattern 2 は解消される。
- フィルタ文字列は監査コメントが提示した 4 つをそのまま採用し (追跡可能性のため)、`get-auto-session-report.sh` 用に `html-comment scoped residual tally` を追加した。5 つとも main 上で `bats --count --filter 'html-comment scoped' tests/<file>.bats` が **0** を返すことを実測済み (既存テスト名と衝突しない)。

### fail-safe critical の判定と edge case

`scripts/scan-pending-ac.sh` は「`gh` 失敗時に `[]` を返して exit 0」と明記された fail-open 設計 (criterion (c))、`scripts/opportunistic-search.sh` は `|| true` を含む (同じく (c))、`scripts/check-skill-change-observation-ac.sh` は入力検証で exit 2 を返す validator (criterion (b)) — いずれも fail-safe critical。期待挙動:

- **空入力 / 該当行 0 件**: 従来どおり `[]` / 空出力 / exit 0。本修正はマッチ条件を狭めるだけなので、空入力の経路は不変
- **`>` を含む条件文**: canonical pattern の `[^>]*` は `<!--` の位置から開始するため、コメントより前の散文に `>` があってもマッチ開始位置に影響しない。コメント内では `-->` の `>` で確実に停止する
- **`"` を含む条件文**: `awk index()` / `grep -F` は literal 照合のためクォートの影響を受けない。ERE へ外部入力を内挿しないこと (Step 4 の `EVENT_NAME`) で注入面も作らない
- **CRLF**: 末尾 `\r` は `[a-zA-Z_]+` の文字クラス外なのでタグ名に混入しない (既存の trailing `[ \t\r]+` 除去も維持)
- **マルチバイト**: awk / grep のバイト単位マッチで、日本語の条件文はパターンに影響しない
- **依存コマンド失敗時**: `gh` 失敗時の fail-open (`[]` + exit 0) は**変更しない** — 本 Issue は分類精度の問題であり、可用性方針を変える理由がない

### allowed-tools impact chain check

- **Case 1 (新規 `scripts/*.sh`)**: 該当なし (新規スクリプトの追加はない)
- **Case 2 (`modules/*.md` 変更)**: `modules/verify-classifier.md` を変更する。lightweight gate は**マッチする** (追加内容が参照実装として `scripts/collect-verify-retention-stats.sh` を引用するため)。reader は `grep -rl "modules/verify-classifier\.md" skills/*/SKILL.md` で `audit` / `spec` / `code` / `issue` / `auto` / `verify` の 6 件。ただし追加内容は**引用であって新規スクリプト呼び出しではない**ため、いずれの reader にも `allowed-tools` 追加は不要 (gate の目的は新規呼び出しの検出であり、本件は該当しない)

### 監査・実査型 Issue の判定

**該当しない**。判定理由: 本 Issue の目的は既存項目の分類・区分ではなく抽出ロジックの修正であり、成果物は分類レポートではなくコード変更。Issue 本文の影響箇所表は判断根拠の記録ではあるが、後続プロセスが読む永続的な分類成果物ではない。ただし本 Spec ではその表の 2 行を実測で訂正しており (上記「実装との矛盾」)、Implementation Steps に記載した行番号・関数名・パターンはすべて `grep -n` / `Read` で現物確認済み。

### 新規テストケース要求のサマリ

Implementation Steps 2-7 はいずれも既存スクリプトへの分岐ロジック変更を含むため、受入条件 1-5 は「既存スイートが PASS すること」だけでなく、新規ロジックを検証する新規テストケース (`tests/scan-pending-ac.bats` の `html-comment scoped tag extraction` / `tests/post_merge_check.bats` の `html-comment scoped manual extraction` / `tests/opportunistic-search.bats` の `html-comment scoped tag match` / `tests/check-skill-change-observation-ac.bats` の `html-comment scoped tag regression` / `tests/audit-auto-session.bats` の `html-comment scoped residual tally`) を追加したうえでスイートが PASS することを要求する。

### #1242 との関係

`opportunistic-search.sh` の走査スコープ (セクション非依存) は #1242 で既に着地済み (`POST_MERGE_AWK` による Post-merge セクション限定が `:336-347` に存在)。本 Issue はそのスコープ済み本文に対するタグ抽出の粒度のみを扱うため、両者は重ならない。

### Spec 本文でのタグ表記

本 Spec は `verify-type` タグ名を多数引用するが、実タグと誤認されないよう `<!--` で始まる完全形の記述をサンプルとして書かない (インラインコードでタグ名のみを引用する)。これは本 Issue が扱う誤分類そのものを Spec 自身が引き起こさないための措置であり、修正後は不要になる性質のものではない (`post_merge_check.sh` は Spec ファイルを直接走査するため)。

## issue retrospective

### Auto-Resolve Log (非対話モード)

- **判断が要る点 (Waiting Count 定義変更の過去レポート非互換の扱い): (a) 定義変更を明記し、以降のレポートに「計測方法の変更」注記を入れる** — reason: `docs/stats/2026-08-05.md` § 11 (訂正 1 / 訂正 2) に、代用計測の不整合を過去レポートの再出力・二重表示なしに追記注記のみで扱った既存先例があり、(a) はこれと同型。(b) 並行出力には対応する先例がなく、過去レポート全件の再計算コストが発生する
  - Other candidates: (b) 変更前後の両方を出力し、移行期間を設ける
  - 最終確認と Spec への記録は実装時 (`/spec`) に行う旨、本文に残した

### Acceptance Criteria 変更の理由

このIssueに既に投稿されていた `/triage` の AC verify command 整合性監査コメント (2026-08-08) を消費し、指摘された always-PASS パターン 5 件のうち Pre-merge の 4 件 (AC 1-4 の `grep -n "verify-type" <file>`) を修正した:

- **AC 1-3 (`scan-pending-ac.sh` / `post_merge_check.sh` / `opportunistic-search.sh`)**: 監査コメントの提案どおり、各スクリプトに対応する既存 bats ファイル (`tests/scan-pending-ac.bats` 等) の実行に verify command を差し替えた。「3 ケースを検証している」という条件文も個別 AC に統合し、単独の `ls tests/` AC は削除した (ディレクトリ存在は既存 bats ファイルがある時点で常に真であり、監査コメントが指摘した通り検証にならないため)
- **AC 4 (`check-skill-change-observation-ac.sh`)**: `/issue` フェーズで背景記載の合成再現ケース (`verify-type: manual` 実タグ + プロースでの `observation` 引用) をこのスクリプトに対して実行したところ、誤検知は再現しなかった (`exit 0`)。理由はこのスクリプトの抽出が既に 2 段階 (`grep -oE '<!--.*-->'` で HTML コメント区間を先に切り出し、そのあとでタグ文字列と照合) になっており、コメント外のプロース引用を拾わない構造だったため。影響箇所表の当該行の判定を「同上 (潜在)」から「誤分類なし (再検証済み)」に訂正し、AC の条件文も「修正」ではなく「HTML コメント内タグ抽出のみを見る挙動の回帰テスト確認」に改めた
  > **訂正 (`/spec`, 2026-08-16)**: この判定は誤り。`grep -oE '<!--.*-->'` は greedy であり、同一行に HTML コメントが 2 つある場合 (典型は先行する `verify: rubric` コメント) は中間のコメント内容ごと `tag` に取り込むため誤検知する。`/issue` の再現試行はプロースが HTML コメントの **外側**にあるケースのみを試したため、この経路を見落とした。実測結果と修正方針は本 Spec の `## Notes` § 実装との矛盾 を参照。AC 4 は「回帰テスト確認」から「抽出の修正 + テスト」へ戻した
- **Post-merge AC**: Issue 本文が `skills/audit/SKILL.md` を参照しており、`verify-type: observation` タグを持つ post-merge AC が `session=next` を欠いていたため (self-update propagation check で検出)、`session=next` を付与した

### Consumed Comments

| login | authorAssociation | trust tier | 内容の要約 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/triage` の AC verify command 整合性監査。Pre-merge AC 5 件が always-PASS パターンであると指摘し、AC 1-4 (grep 系) と AC 7 (`ls tests/`) の置き換えを提案 | https://github.com/saitoco/wholework/issues/1273#issuecomment-5226551031 |

## spec retrospective

### Minor observations

- Issue 本文の影響箇所表は「調査済み」と読める形で 7 行が列挙されていたが、実測すると 2 行 (`check-skill-change-observation-ac.sh` / `get-auto-session-report.sh`) が誤っていた。前フェーズが「再検証済み」と明記した行であっても、合成ケースを 1 パターンだけ試した結論は網羅性を保証しない — 同じ根 (substring マッチ) から派生する経路が複数ある場合、経路ごとに再現を試す必要がある。
- `/triage` の AC 監査が提案した修復案 (`bats --count --filter` 形) は Pattern 2 の解消には有効だが、`modules/verify-patterns.md:32` が別途アンチパターンとして挙げるカウント集計形に該当する。監査ロジック同士が衝突しうるため、監査コメントの修復案は `/spec` で他の規約と突き合わせてから採否を決めるのが正しい (監査コメント自身も「判断は `/spec` フェーズに委ねます」と明記していた)。
- `verify-type` タグを扱う Issue の Spec / Issue 本文自体が、修正対象のスクリプトの走査対象 (`docs/spec/*.md` / Issue body) になるという自己参照がある。完全形のタグをサンプルとして書かない運用で回避したが、この制約は本 Issue 固有ではなく、AC の型を議論するすべての Issue に共通する。

### Judgment rationale

- **共通ヘルパー化を採らなかった理由**: 5 つの consumer は awk / `grep -E` / bash `case` と実行形態が異なり、単一の呼び出し可能インタフェースに畳めない。加えて新規 `scripts/*.sh` は 6 つの reader SKILL.md の `allowed-tools` 更新を招き、worktree 内では `source` ベースの関数呼び出しが isolation guard に阻まれる。SSoT はドキュメント側 (`modules/verify-classifier.md`) に置き、実装はインライン展開する — 参照実装 `collect-verify-retention-stats.sh` と同じ形。
- **`opportunistic-search.sh` でスキル名を行スコープに残した理由**: `event=` はタグ属性だがスキル名は条件文の散文に正当に現れる (`modules/verify-classifier.md:161` が実例)。両方を一律にコメント内へ限定すると既存 AC が一斉にマッチしなくなる。「HTML コメント内に限定する」という原則は、その文字列がタグの一部である場合にのみ適用される。
- **`EVENT_NAME` を ERE へ内挿しなかった理由**: `--event` の値は無検証の外部入力であり、正準パターンへ内挿すると正規表現メタ文字の注入面ができる。awk `index()` による literal 照合なら注入面を作らずコメント内スコープを実現できる。

### Uncertainty resolution

- **grep ERE のブラケット内 `\t` の解釈**: macOS の実測ではタブとして解釈された (`<!--tverify-type:` は不一致) が、GNU grep のドキュメントはバックスラッシュまたは `t` のリテラル集合と規定する。いずれの解釈でも通常のタグはマッチするため実害はないが、曖昧さを排すため grep 経路は POSIX クラス `[[:space:]]*` に統一し、awk 経路は `[ \t]` を維持 (awk では確実にタブと解釈される) と決めた。
- **`bats --count --filter` 形の safe mode 挙動**: `/review` は `command` を safe mode で評価し CI 参照フォールバックを試みるため、カウント集計形は UNCERTAIN 化する懸念があった。`file_contains` (`always_allow`) + `command "bats tests/<file>.bats"` (CI ジョブへマップ可能) の 2 コマンド形に置き換えることで、Pattern 2 の解消と safe mode での決定性を両立できることを確認した。
- **フィルタ文字列の衝突**: 5 つのテスト名部分文字列がいずれも既存テストと衝突しないことを `bats --count --filter 'html-comment scoped' tests/<file>.bats` が 0 を返すことで実測確認済み (5 ファイルすべて)。

### 新規テストケース要求 (分岐ロジック追加に伴う)

Implementation Steps 2-6 はいずれも既存スクリプトへの分岐ロジック変更を含むため、受入条件 1-5 は「既存スイートが PASS すること」に加え、新規ロジックを検証する新規テストケースの追加を要求する: `tests/scan-pending-ac.bats` の `html-comment scoped tag extraction` / `tests/post_merge_check.bats` の `html-comment scoped manual extraction` / `tests/opportunistic-search.bats` の `html-comment scoped tag match` / `tests/check-skill-change-observation-ac.bats` の `html-comment scoped tag regression` / `tests/audit-auto-session.bats` の `html-comment scoped residual tally`。

## Code Retrospective

### Deviations from Design

- N/A — all Implementation Steps (1-8) were executed as designed, using the exact canonical patterns specified in the Spec.

### Design Gaps/Ambiguities

- N/A — the Spec's pattern choices (awk `[ \t]*` vs. `grep -E` `[[:space:]]*`, `index()` for `EVENT_NAME`, etc.) were unambiguous and required no further judgment during implementation.

### Rework

- **bash 3.2's `set -e` does not abort a bats `@test` function on a bare `[[ ... ]]` compound-command failure unless it is the function's last statement.** Two of the five new bats test cases (`tests/post_merge_check.bats`, `tests/check-skill-change-observation-ac.bats`) initially wrote 2-3 sequential `[[ "$output" == *"..."* ]]` / `[[ "$output" != *"..."* ]]` assertions where only the last one happened to be gated correctly — the pre-implementation FAIL check for the *last* assertion passed, but re-verification against pre-fix scripts showed the non-final assertions silently passed even when they should have failed. Confirmed the root cause with an isolated `bash -c 'set -e; [[ "abc" != *"abc"* ]]; echo REACHED'` (prints REACHED, exit 0) vs. the single-bracket equivalent `[ "abc" != "abc" ]` (aborts, exit 1) — `[ ]` (a regular builtin) propagates under `set -e`, `[[ ]]` (a compound command) does not, except as the function's final command. Fixed by appending `|| return 1` to every non-final `[[ ]]` assertion in both files. The other three new tests (`tests/scan-pending-ac.bats` used single-bracket `[ ]`; `tests/opportunistic-search.bats` used `echo | jq -e ... > /dev/null` pipelines, which do propagate under `set -e` in bash 3.2) were unaffected and needed no rework.
- Confirmed pre-implementation FAIL for 5 new test(s) (one per consumer script), each re-confirmed against the corrected assertion gating.

### Smoke Test

- N/A — the Spec has no `## Smoke Test` section.

### Full Suite Run

- `bats --jobs 18 tests/` (1809 tests): 1 pre-existing unrelated failure — `tests/code.bats` "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route" (`skills/code/SKILL.md` does not currently contain the string `tests/code.bats` expects). Confirmed this failure reproduces identically on the unmodified `main` branch (outside this worktree, before any of this Issue's commits), so it is not a regression introduced here. Not filed as a follow-up Issue in this session — left for a future `/code` or `/audit drift` run to pick up, since it is orthogonal to this Issue's scope (post_merge_check.bats's own known parallel-only flake, documented in `docs/tech.md` § CI bats Parallel/Serial Split, did not reproduce in this run).

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Implemented all 5 consumer scripts + `modules/verify-classifier.md` + `skills/audit/SKILL.md` exactly per the Spec's Implementation Steps 1-8, with no deviation from the designed canonical patterns.
- Each of the 5 new bats test cases was verified to FAIL against the pre-fix version of its target script before being committed (confirmed via `git show <pre-fix-commit>:<path>`, since the target file's own fix was already committed in an earlier step of this same run — see `docs/tech.md`'s Stale Test Assertion Check convention, applied here in its "new assertion" direction).
- Discovered and fixed a bash 3.2 `set -e` gap in 2 of the 5 new tests (`tests/post_merge_check.bats`, `tests/check-skill-change-observation-ac.bats`): non-final bare `[[ ]]` assertions do not abort the test on failure, only single-bracket `[ ]` or pipeline failures do. Fixed with explicit `|| return 1` on every non-final `[[ ]]` assertion.

### Deferred Items

- Post-merge 受入条件 1 件: `collect-verify-retention-stats.sh --window 2026-05-07` と `scan-pending-ac.sh` の manual 分類結果の突き合わせ (現状 19 対 18)。`/auto` 実行後の observation として次セッションで確認する
- `tests/code.bats` "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route" is a pre-existing FAIL, confirmed to reproduce identically on unmodified `main` — out of this Issue's scope, not filed as a follow-up in this session.

### Notes for Next Phase

- `/verify` should re-run `bats tests/` and treat the `tests/code.bats` pre-existing failure noted above as unrelated to this Issue's change (do not attribute it to this PR).
- When adding new bats assertions that must gate on a **non-final** statement in a `@test` body, prefer single-bracket `[ ]`, a pipeline (`... | jq -e ... > /dev/null`), or an explicit `|| return 1` after a `[[ ]]` — bash 3.2's `set -e` does not abort on a bare non-final `[[ ]]` failure (see Code Retrospective § Rework for the isolated repro).
