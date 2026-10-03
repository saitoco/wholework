# Issue #1477: spec: Changed Files に、変更対象の一覧を持つ文書を候補として挙げる検査を追加

## Overview

`/spec` Step 10 の「Steering Docs sync candidate check」は、変更対象ファイルの名前やキーワードを起点に、それを参照している文書を探す inbound 方向の検査である。このため、変更対象を「列挙している側」の文書 (Directory Layout や Key Files 表を持つ steering 文書、repo ルートの README) は、次のいずれかの形で候補から漏れる。

- 変更ファイルの名前を含まない文書 (README のコマンド一覧、件数コメントつきのディレクトリツリー) は拾われない
- 名前が含まれていても、キーワードが discriminating-power filter (8 ファイル超でスキップ) で落ちる
- 拾われても、既存の記述には新しい項目が含まれないので、「サブコマンドやファイルを足せば必ず古くなる」という関係が検査の形として表現されない

downstream で同じ逸脱が 2 つの Issue で連続し、どちらも `/code` が自力で直した (Changed Files には無かった)。

この Issue では、Step 10 に「Listing-side sub-check」を足す。変更の種類 (サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構成の変更) を起点に、一覧を持つ文書を Changed Files の候補として機械的に挙げる。候補の集合は次の 2 種類に固定する (Issue 本文の自動解決どおり)。

- `$STEERING_DOCS_PATH/` 直下で、frontmatter の `ssot_for` に `directory-layout` を持つ文書 (このリポジトリでは `docs/structure.md`)
- repo ルートの `README.md`

候補が 1〜2 件に限られるので、既存の discriminating-power filter の対象外とし、既存の inbound 検査・Outbound pointer 検査との違いも SKILL.md に明記する。

変更するファイルは `skills/spec/SKILL.md` (Step 10 の追記) と `tests/spec.bats` (drift を防ぐ content-assertion テスト) の 2 つ。Issue 本文の AC1 の verify command は、triage の AC 監査の指摘どおり、この `/spec` 実行で修正済み (詳細は Notes)。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の `Steering Docs sync candidate check` と `Outbound pointer sync candidate check` の間に、太字ラベルのブロック `**Listing-side sub-check of the Steering Docs sync candidate check (...)**` を追加する (約 30 行。本文は Implementation Steps の Step 1)。親チェックの本文と、既存テストが assert している文字列は変更しない。見出し (`###` / `####`) は使わない
- `tests/spec.bats`: 新サブ検査の content-assertion テストを末尾に追加する (helper 関数 1 つと `@test` 4 件。既存の 14 件は変更しない)。`awk`、`grep -q`、here-string だけを使うので bash 3.2 互換
- [Steering Docs sync candidate] keyword "Steering Docs sync candidate" skipped: matched 206 files (no discriminating power)
  - 測定範囲: `docs/ tests/ scripts/ modules/` の全ファイル (コマンド: `grep -rl "Steering Docs sync candidate" docs/ tests/ scripts/ modules/ 2>/dev/null | wc -l`)。大半は `docs/spec/` と `docs/sessions/` の過去記録
  - 参考: `docs/spec/` と `docs/sessions/` を除く実質的な参照元は 3 件。`tests/spec.bats` (Changed Files に含む)、`scripts/check-verify-dirty.sh`、`tests/verify-dirty-detection.bats` (後 2 件は次の「読み手の確認」を参照)
- [Steering Docs sync candidate] キーワード `directory-layout` (この Issue が導入する参照): 2 件 (測定範囲は `docs/ tests/ scripts/ modules/` の全ファイル。コマンド: `grep -rl "directory-layout" docs/ tests/ scripts/ modules/`)。`docs/structure.md` (frontmatter の宣言そのもの) と、過去の Spec `docs/spec/issue-71-doc-template-frontmatter.md` のみ。どちらも変更不要
- [Steering Docs sync candidate] 読み手の確認: `scripts/check-verify-dirty.sh` は、Spec の `## Changed Files` から「ラベル付きでもよい箇条書きの先頭のバッククォートで囲まれたパス」を抽出して own-issue-scope の manifest を作る (同スクリプトの manifest 構築部分のコメントと `sed -nE` の正規表現で確認)。新サブ検査が出すエントリも既存と同じラベル `[Steering Docs sync candidate]` を使い、パスを先頭のバッククォートに入れる形のままなので、`scripts/check-verify-dirty.sh` と `tests/verify-dirty-detection.bats` は変更不要
- [Steering Docs sync candidate] 変更不要の確認: `docs/structure.md`、`README.md`、`README.ja.md`、`docs/workflow.md`、`docs/guide/*.md`、`modules/doc-checker.md`、`modules/skill-dev-doc-impact.md` は、Steering Docs sync candidate check・Outbound pointer sync candidate check・新サブ検査のいずれの名前も記述していない (測定範囲は上記 7 グループ、キーワードは `sync candidate` / `Listing-side` / `Steering Docs sync`、結果は 0 件)。ファイルの追加もディレクトリ構成の変更も無いので、`docs/structure.md` のファイル数コメントも変わらない
- [Outbound pointer sync candidate] なし: `skills/spec/SKILL.md` の Step 10 が指す先 (`modules/doc-checker.md` など) は今回の変更の影響を受けない。`tests/spec.bats` に外向きのポインタは無い
- `docs/ja/` translation sync check: `docs/translation-workflow.md` を確認した。同期義務はトップレベルの `docs/*.md` が Changed Files に含まれる場合だけで、今回は含まれないので対象外

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10 に、親チェック (`**Steering Docs sync candidate check (...)**`) のサブ検査として次のブロックを追加する (→ AC1, AC2, AC3, AC4)
   - 位置: 親チェックの最後の行 ``**Skip** if Changed Files does not include SKILL.md files, files under `modules/`, or files under `scripts/`.`` とその後の空行の直後で、`**Outbound pointer sync candidate check (when a Changed Files entry itself points elsewhere):**` の直前。追加するブロックと次のブロックの間は空行 1 行にする
   - 見出し (`###` / `####`) は使わず、太字ラベルのブロックにする。`###` 以上の見出しを入れると、AC1 の `section_contains ... "Step 10" ...` の走査範囲が途中で切れる (Notes の「section 系 AC の走査範囲」参照)
   - 親チェックの本文は変更しない。既存の `tests/spec.bats` が assert している文字列 (`Discriminating-power filter`、`weakest keyword class`、`do not fall back to a broader search` など) を壊さない
   - 追記は英語のみ。半角の `!` は使わない。`check-forbidden-expressions.sh` の対象語 (旧称の語) は書かない

   ```markdown
   **Listing-side sub-check of the Steering Docs sync candidate check (regardless of SPEC_DEPTH; only when applicable):**

   The check above is **inbound** and keyword-driven: it lists a document only when that document mentions the changed file's name or another extracted keyword, and it drops a keyword that matches too many files. A document that *enumerates* the change target — a Key Files table, a directory tree with file-count comments, a command or subcommand list — can therefore be missed (it may not mention the changed file at all, or the keyword may be filtered out). Even when such a document is hit, its existing entry does not mention the new item, so a keyword hit alone gives no reason to update it. This sub-check starts from the *kind of change* instead of from a keyword, and lists the enumerating documents directly.

   **Fires when** the Issue's change does any of the following (exhaustive; decide from the Issue body and the planned Implementation Steps). The changed files do not have to include SKILL.md files, `modules/`, or `scripts/` — the gate of the check above does not apply here:
   - adds or removes a subcommand of an existing script or skill (a new first-argument operation such as `scripts/foo.sh <subcommand>` or `/skill <subcommand>`)
   - adds a new file, or removes or renames one
   - changes the directory structure (a new, renamed, moved, or removed directory)

   Steps:
   1. Build the candidate set (exact; do not widen it):
      - every document directly under `$STEERING_DOCS_PATH/` whose frontmatter `ssot_for` list contains `directory-layout`: run `grep -l "directory-layout" "$STEERING_DOCS_PATH"/*.md`, then confirm that each hit is an `ssot_for` entry in the leading frontmatter block, not body prose (`docs/structure.md` in this repository)
      - the repository-root `README.md`

      Translation outputs (`docs/{lang}/`, `README.{lang}.md`) are not candidates; the `docs/ja/` translation sync check below handles them.
   2. For each candidate, add a **Steering Docs sync candidate** entry to the Changed Files section, naming the enumeration to re-check, e.g., `docs/structure.md`: [Steering Docs sync candidate] re-check the Directory Layout tree (file-count comments) and the Key Files entry of the changed script; update if needed. If the candidate is already in the Changed Files list, extend its existing entry instead of adding a second one.
   3. As in the check above, the `/code` phase makes the final include/exclude decision by reading each candidate; this step only guarantees that the candidates are not silently omitted.

   **Not subject to the Discriminating-power filter**: the 8-file threshold of the check above does not apply to this sub-check, and no candidate is skipped for "matching too many files". That filter exists because a keyword grep can return an unbounded hit list with no way to tell the relevant hits apart. Here the candidates are chosen by document role (the `ssot_for` declaration and the root README), not by keyword hits, so the set is limited to a few listing documents (one or two in practice) and every one of them is worth a look.

   **Differs from adjacent checks:**
   - **Steering Docs sync candidate check (inbound)**: starts from the changed file's name or keyword and searches outward, so an enumerating document that does not mention that name or keyword is missed, and a keyword with no discriminating power is skipped. This sub-check starts from the kind of change and does not depend on any keyword hit.
   - **Outbound pointer sync candidate check**: starts from the pointers written in a changed file's own body, so an enumerating document that the changed file never points to is out of its reach. This sub-check does not depend on any pointer in the changed files.

   It complements, and does not replace, the Change Types table in `modules/doc-checker.md` (read at the top of this Step): that table is a judgment aid whose firing depends on recognizing the change as one of its types, while this sub-check fires mechanically on the three conditions above.

   **Skip** if the change adds or removes no subcommand, adds no file and removes or renames none, and changes no directory structure (e.g., a behavior-only edit to existing files).

   *Example: in a downstream repository, two consecutive Specs listed only a script and its procedure document in Changed Files, while the change added a subcommand or a new script; both times `/code` had to fix the steering document holding the Directory Layout, and the README, as drift it found on its own.*
   ```

2. (after 1) `tests/spec.bats` の末尾に、次のコメント・helper・テスト 4 件を追加する。既存のテストは変更しない。これは Step 1 が既存スキルに足す新しい条件分岐 (発火条件つきのサブ検査) に対する新規テストケースの追加であり、既存スイートが PASS することに加えて、新規テスト 4 件が追加されて PASS することを求める (→ AC1, AC2, AC3, AC4 の drift 防止)
   - 4 件はいずれも、サブ検査ブロックの範囲 (太字ラベルの行から `**Outbound pointer sync candidate check` の行の手前まで) に限定して assert する。範囲の外に同じ文字列があっても PASS しない
   - 追記する前に、末尾の既存テスト (`patch_route_verify_command_check_section` を使うもの) との間に空行を 1 行入れる

   ```bash
   # Content-assertion tests for the Steering Docs sync candidate check's listing-side
   # sub-check (added for #1477). Guards the sub-check against accidental removal or drift:
   # the ssot_for: directory-layout detection key, the explicit firing conditions, the
   # difference from the inbound and Outbound pointer checks, and the exemption from the
   # discriminating-power filter. Assertions are scoped to the sub-check's own block (from its
   # bold label to the next check's label) so that the strings cannot be satisfied elsewhere.

   listing_side_subcheck_section() {
       awk '/^\*\*Listing-side sub-check of the Steering Docs sync candidate check/{found=1} found && /^\*\*Outbound pointer sync candidate check/{exit} found{print}' "$1"
   }

   @test "spec skill Steering Docs sync candidate check has a listing-side sub-check keyed on ssot_for directory-layout" {
       listing_side_subcheck_section "$SKILL_FILE" | grep -q 'frontmatter `ssot_for` list contains `directory-layout`'
   }

   @test "spec skill listing-side sub-check states its firing conditions" {
       section="$(listing_side_subcheck_section "$SKILL_FILE")"
       grep -q 'adds or removes a subcommand' <<<"$section"
       grep -q 'adds a new file' <<<"$section"
       grep -q 'changes the directory structure' <<<"$section"
   }

   @test "spec skill listing-side sub-check differs from the inbound and Outbound pointer checks" {
       section="$(listing_side_subcheck_section "$SKILL_FILE")"
       grep -q 'starts from the kind of change' <<<"$section"
       grep -q 'does not depend on any pointer' <<<"$section"
   }

   @test "spec skill listing-side sub-check is not subject to the discriminating-power filter" {
       section="$(listing_side_subcheck_section "$SKILL_FILE")"
       grep -q 'Not subject to the Discriminating-power filter' <<<"$section"
       grep -q 'chosen by document role' <<<"$section"
   }
   ```

3. (after 1, 2) 検証する (→ AC1, AC2, AC3, AC4)
   - `python3 scripts/validate-skill-syntax.py skills/` が 0 エラー
   - `bash scripts/check-forbidden-expressions.sh` が PASS
   - `git diff -U100000 -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py` が exit 0 (コミット前の差分に対して実行する)
   - `bats tests/spec.bats` が PASS。`bats` がこの環境に無い場合は、新規テスト 4 件の本体を直接実行して代える。helper と同じ `awk` プログラムの入力に、実装前の内容 (`git show HEAD:skills/spec/SKILL.md` の出力をパイプで渡す。一時ファイルは作らない) と実装後の `skills/spec/SKILL.md` を順に与え、各テストの `grep -q '<文字列>'` が、実装前は FAIL、実装後は PASS になることを確認する (`/code` の New Verification-Test Pre-implementation FAIL Check)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Steering Docs sync candidate check に、サブコマンドやファイル構成の一覧を持つ文書を Changed Files の候補に挙げるサブ検査が追加されている" --> <!-- verify: section_contains "skills/spec/SKILL.md" "Step 10" "directory-layout" --> `/spec` に一覧側の文書を拾うサブ検査がある
- <!-- verify: rubric "追加されたサブ検査が、どのような変更のときに発火するか (サブコマンド追加・新規ファイル追加・ディレクトリ構成変更など) を明示している" --> 発火条件が明示されている
- <!-- verify: rubric "追加されたサブ検査が、既存の inbound 検査および Outbound pointer sync candidate check とどう違うかを述べている" --> 既存の 2 つの検査との違いが書かれている
- <!-- verify: rubric "追加されたサブ検査が、既存の discriminating-power filter (8 ファイル超でスキップ) の対象外であること、およびその理由 (候補が一覧を持つ少数の文書に限られること) を述べている" --> discriminating-power filter の対象外であることが明記されている

### Post-merge

- サブコマンドを 1 つ増やす Issue で `/spec` を実行し、一覧を持つ文書が Changed Files に入ることを確認する <!-- verify-type: opportunistic -->

## Notes

### 自動解決ログ (non-interactive, SPEC_DEPTH=light)

非対話モードのため、次の判断はユーザー確認なしで決めた。Issue 本文の「自動解決した曖昧点」(一覧を持つ文書の範囲、post-merge AC の verify-type、filter 非適用の AC 化) はそのまま踏襲している。

- **Issue 本文の前提と現状の実装**: Background の記述 (inbound 検査であること、Outbound pointer 検査が既にあること、discriminating-power filter が 8 ファイル超でスキップすること、`ssot_for: directory-layout` を `docs/structure.md` が宣言していること) は、`skills/spec/SKILL.md` Step 10 と `docs/structure.md` の frontmatter の現状と一致した。矛盾は無い
- **親チェックのゲートを継承しない**: 親チェックは「Changed Files に `SKILL.md`、`modules/`、`scripts/` のいずれかを含むとき」だけ動く。新サブ検査は、新規ファイルの追加やディレクトリ構成の変更が `agents/`、`tests/`、`examples/` 配下だけで起きる場合も対象にしたいので、独立した発火条件 (`Fires when`) を持たせた。ラベルの `(regardless of SPEC_DEPTH; only when applicable)` は、同じ Step 10 の「Tag/enum semantic extension consumer sweep」と同じ書き方
- **「新規ファイルの追加」に削除・改名も含める**: Issue の発火条件は「サブコマンドの追加・削除」「新規ファイルの追加」「ディレクトリ構成の変更」。ファイルの削除・改名でも、ディレクトリツリーとファイル数コメントは古くなる。名前を指す Key Files の行は既存の Feature deletion impact chain check と Symbol impact discovery が拾うが、件数コメントやツリーは拾わないので、発火条件を `adds a new file, or removes or renames one` にした
- **候補の検出方法**: `$STEERING_DOCS_PATH/` 直下を非再帰の glob (`"$STEERING_DOCS_PATH"/*.md`) で見るので、`docs/{lang}/` 配下の翻訳は自然に外れる。`README.{lang}.md` は `README.md` ではないので外れる。`grep -l "directory-layout"` のヒットは本文の言及も拾うので、frontmatter の `ssot_for` の項目であることを確認する手順を入れた
- **`modules/doc-checker.md` との関係**: doc-checker の Change Types 表には「Project structure changes (directory/file placement)」の行があり、`README.md` と `structure.md` を挙げている。ただし表は文書名を固定で持ち、サブコマンドの追加に当たる行が無く、発火は変更の種類をモデルが判定することに依存する。新サブ検査は置き換えではなく補完として、1 文で関係を書いた (AC3 が求める差分の対象は inbound 検査と Outbound pointer 検査の 2 つなので、`Differs from adjacent checks` の箇条書きは 2 項目のままにした)
- **検討した別案**:
  - 親チェックの discriminating-power filter の本文に「この filter は一覧側の検査には適用しない」と書き足す案は採らない。親チェックの本文を変えると、既存テストが assert している文字列に近い箇所を触ることになる。Issue も「サブ検査を足す」としている
  - サブ検査を Outbound pointer 検査の後ろに置く案は採らない。AC1 は「Steering Docs sync candidate check に、サブ検査が追加されている」ことを求めており、親チェックの直後に置くのが最も素直な読み方で、Outbound pointer 検査の冒頭の `the Steering Docs sync candidate check above` も壊れない
  - `modules/doc-checker.md` の Change Types 表に行を足す案は採らない。Issue と AC1 は `skills/spec/SKILL.md` の Step 10 を対象にしている

### 検証コマンドの扱い

- **AC1 の `section_contains` を修正した**: triage の AC 監査コメント (https://github.com/saitoco/wholework/issues/1477#issuecomment-5964742436) の指摘どおり、見出し引数の `"### Step 10"` を `"Step 10"` に直し、Issue 本文を更新した。`section_contains` の見出し引数は、見出し行から先頭の `#` と空白を除いた文字列への部分一致で判定される (`modules/verify-executor.md` の `section_contains` の行)。`"### Step 10"` のままだと `No heading matched` で恒久的に UNCERTAIN になる。この Spec の Verification は更新後の Issue 本文と一致している (Pre-merge 4 件、Issue 本文も 4 件)
- **section 系 AC の走査範囲 (verify-patterns §29 のパターン 4)**: `section_contains ... "Step 10" ...` は `### Step 10: Create Spec` から次の `###` 以上の見出し (`### Step 11: Title Drift Check`) の手前までを走査する。現状は 308〜902 行で、追記案を差し込んだ状態では 308〜932 行になる (測定範囲は `skills/spec/SKILL.md`、見出しの抽出はコードフェンス内を除く)。新ブロックは太字ラベルで見出しを使わないので、この範囲に入る。将来このブロックに `###` 以上の見出しを入れると AC1 の範囲外になるので、見出しは入れないこと
- **文字列の存在確認**: `directory-layout` は現状の `skills/spec/SKILL.md` に 0 件で、実装で導入する。追記案を `skills/spec/SKILL.md` のコピーにメモリ上で差し込み、次を確認済み: `section_contains "Step 10" "directory-layout"` 相当が PASS になる (実装前は FAIL)、`"Step 10"` を含む見出しは 1 件だけ、`validate-skill-syntax.py` は 0 エラー 0 警告 (追記の前後とも)、`check-language-convention.py` は exit 0、追記案に半角 `!` と旧称の語は無い、差し込み後のテキストは元のテキストへの純粋な挿入なので既存の行は 1 行も変わらない (既存の `tests/spec.bats` が Step 10 の親チェック周辺で assert する 10 個の文字列の残存も個別に確認した)
- **rubric の AC (AC2〜AC4)**: 採点者が追記ブロックの中で根拠を見つけやすいよう、ブロック内の語を AC の語に合わせた。AC2 は `Fires when` の 3 項目、AC3 は `Differs from adjacent checks` の 2 項目 (inbound 検査と Outbound pointer 検査)、AC4 は `Not subject to the Discriminating-power filter` の段落 (8 ファイルのしきい値が適用されないことと、候補が document role で決まり少数に限られるという理由)
- **ACs と Out of Scope**: Issue 本文に `## Out of Scope` は無く、AC と矛盾する項目は無い

### 新規ロジックの新規テスト要件 (SPEC_DEPTH=light のため Step 13 の retrospective は無く、ここに記録する)

- Implementation Step 1 は、既存スキルに新しい条件分岐 (発火条件つきのサブ検査) を足す。Step 2 で `tests/spec.bats` に新規テストケース 4 件を追加し、既存スイートの PASS に加えて、新規テストが実装前に FAIL し実装後に PASS することを求める
- 4 件は #1073、#1089、#1096、#1327 が Step 10 の各チェックに足した content-assertion テストと同じ流儀。Issue の Pre-merge AC には command 型の AC が無いので、AC は増やさず (Issue 本文と Spec の Pre-merge を 4 件のまま揃えるため)、要求は Implementation Steps に置いた
- bats テストの入力形式: テスト対象は `skills/spec/SKILL.md` のテキスト。helper `listing_side_subcheck_section` が太字ラベルの行から次のチェックのラベルの行の手前までを出力し、各テストはその出力に固定文字列を `grep -q` で照合する
- `bats` はこの環境に無い。`/code` 環境も同様の見込み (直近の #1478 の Code Retrospective が同じ状況を記録している)。Step 3 に、`bats` が無い場合の代替確認 (各テストの `awk | grep -q` を直接実行) を書いた

### その他

- **範囲外の観察 (変更しない)**: Step 10 冒頭の `Read ... modules/doc-checker.md and use the "Impact Assessment" section` が指すセクション名は、`modules/doc-checker.md` に存在しない (実際の見出しは `## Impact Determination Criteria`。測定: `grep -n "Impact Assessment" skills/spec/SKILL.md modules/doc-checker.md` で SKILL.md の 314 行だけがヒットし、doc-checker.md 側は 0 件)。この Issue の対象ではないので直していない
- **post-merge AC の見込み**: `verify-type: opportunistic` の条件は、サブコマンドを足す Issue が次に `/spec` されるまで、`/spec` の完了のたびに SKIP になる。`.wholework.yml` は `autonomy: L3` なので、`phase/verify` で 90 日以上解決しない場合は `/audit stats --retention` の Level 3 auto-retire の対象になる。`verify-classifier.md` の opportunistic の定義 (「`/spec` を実行したときに X を確認する」型) には合っているので、分類はそのまま踏襲した
- **Costly/irreversible な Step**: 無し (SKILL.md とテストの編集のみ)。`spec-approval-needed` マーカーと Deferral Protocol は不要
- **allowed-tools の影響**: 新しい `scripts/*.sh` も `modules/*.md` の変更も無い。追記ブロックは `${CLAUDE_PLUGIN_ROOT}/scripts/` を参照しないので、`skills/spec/SKILL.md` の `allowed-tools` は変更しない
- **この Issue の変更は自分自身には発火しない**: 新サブ検査の発火条件 (サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構成の変更) は、この Issue の変更 (既存ファイル 2 つの編集) に当たらない。そのため `docs/structure.md` と `README.md` は Changed Files の候補に入れていない

## Consumed Comments

No new comments since last phase.

- 参考: cutoff (`phase/spec` の付与、2026-10-03T02:42:25Z) より前に投稿された 2 件のコメントは、前回の `/spec` 実行で消費済み (wrapper の `comments_consumed` イベントが count=2)。今回の consume 対象は 0 件
  - saito / MEMBER / first-class / `/issue` の Issue Retrospective (曖昧点の自動解決ログ、AC の変更理由) / https://github.com/saitoco/wholework/issues/1477#issuecomment-5964742303
  - saito / MEMBER / first-class / triage の AC 監査 (AC1 の `section_contains` の見出し引数に `#` を含み常時 UNCERTAIN になる指摘。修正を `/spec` に指示) / https://github.com/saitoco/wholework/issues/1477#issuecomment-5964742436 → この Spec で Issue 本文の AC1 を修正済み

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1・2 の本文をそのまま `skills/spec/SKILL.md` と `tests/spec.bats` に反映した

### Design Gaps/Ambiguities
- この環境に `bats` が無く、`bats tests/spec.bats` と全体スイートは実行できなかった。代替として、helper と同じ `awk` プログラムと各テストの `grep -F` を直接実行し、新規テスト 4 件 (assert 文字列 8 個) が実装後に全て PASS することを確認した。全体スイートの回帰は未確認 (今回の変更は既存行を 1 行も変えない純粋な挿入)
- Confirmed pre-implementation FAIL for 4 new test(s): `git show HEAD:skills/spec/SKILL.md` を helper の `awk` に通すとサブ検査ブロックが 0 行になり、4 件とも実装前は必ず FAIL する

### Rework
- なし

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec 記載のブロックと 4 テストを逐語で実装した。親チェックの本文と既存テストの assert 文字列は変更していない
- 見出しを使わず太字ラベルのブロックにしたので、AC1 の `section_contains ... "Step 10" ...` の走査範囲 (308〜933 行の手前) に新ブロックが入る

### Deferred Items
- Post-merge AC (サブコマンドを増やす Issue で `/spec` を実行して確認) は opportunistic のまま未チェック。該当する Issue が次に `/spec` される機会に確認する

### Notes for Next Phase
- `bats` が無い環境のため、新規テストは `awk | grep -F` の直接実行で確認した。`/verify` で `bats tests/spec.bats` が動く環境があれば再確認すると確実
- Pre-merge AC 4 件 (rubric 3 件、section_contains 併用 1 件) は `/code` の Step 10 でチェック済み
