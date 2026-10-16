# Issue #1531: verify-classifier: 受入条件の主体 (人名) と verify-type: manual の判定を切り離す

## Overview

`verify-type: manual` の判定と `/verify` Step 8b の実行可否の判定が、条件文の主語 (人名) に引きずられ、読み取りだけで確かめられる条件を `manual` + `executable=false` に倒している。判定の軸を「条件文が誰を主語にしているか」から「その回に人の判断が要るか」「条件を満たす証拠は今存在するか」へ移す。変更は判定基準の文言に限り、`reason` 語彙の拡張 (`evidence-not-yet-available`) と除外・スキップ理由の集計粒度は Issue 本文の「スコープ外」のまま触れない。

1. `modules/verify-classifier.md` に、`manual` の判定の注意を新しい `###` 節として足す: 主体の書き方は型を決めない・読み取りで足りる条件は `auto` 側に寄せる・一度だけ人が実行する条件は実行と確認に分ける。Classification Criteria の表と見出しは変更しない
2. `skills/verify/SKILL.md` Step 8b の Claude Executability Judgment に、「この条件を満たす証拠は今存在するか」を先に問い、存在するなら条件文の主語によらず `executable=true` とする旨を足し、Executable examples に「人を主語にした条件でも証拠がログ・ファイルにあれば executable」の例を足す。あわせて Step 7 の `Claude Executable?` 列の説明が「条件文に基づく」と読める 1 箇所を、Step 8b の rubric への参照に揃える
3. `tests/verify.bats` に、Step 8b の新しい問いと例が消えないことを守る構造テストを 2 件足し、編集の最後に `skills/verify/SKILL.md` の `skill-body-lines` / `skill-body-sha` マーカーを再計算する (既存テストと CI の `check-skill-body-hash` ジョブが検証している)

## Changed Files

- `modules/verify-classifier.md`: 新規 `###` 節 `### manual Type: Subject Wording Does Not Decide the Type` を追加する。挿入位置は `### observation Type: Evidence Collection Patterns` 節の末尾段落 (`All four patterns remain best-effort: ...`) の直後・`### Tag Assignment Example` の直前。内容は Implementation Steps 1 と Notes「挿入文案ドラフト」。この 1 節の追加以外は変更しない (Classification Criteria の表・その見出し・`## Purpose`・他の節は差分に出さない — 受入条件 5)
- `skills/verify/SKILL.md`:
  - Step 8b の `**1. Claude Executability Judgment (rubric-based)**` 直下の導入文 `Evaluate whether Claude can directly execute the verification based on the condition text:` を、証拠の存在を先に問う段落に置き換える
  - `- **Executable examples**:` の箇条書き直下に、入れ子の箇条書きを 1 行追加する
  - `- **Non-executable examples**:` の直後 (`**1b. Record the judgment (both branches)**` の直前) に、証拠が今存在しない場合の記録方針の短い段落を追加する
  - Step 7 の `- **Claude Executable?**:` 列の説明の `quick preview judgment based on condition text` を Step 8b の rubric への参照に揃える
  - 最後の編集として `<!-- skill-body-lines: N -->` と `<!-- skill-body-sha: H -->` の値を再計算して書き換える (現状 997 行 / `90e3f8ce`、同期済みを確認)
  - 変更しない: `1b. Record the judgment` / `2a. If executable` / `independent of whether \`AskUserQuestion\` is invoked` のアンカー文言 (`tests/verify.bats` が参照)、frontmatter の `allowed-tools` (新規のスクリプト・ツール参照を足さない)
- `tests/verify.bats`: 既存の Step 8b テスト群の末尾 (`Step 8b: recording happens in both branches, independent of AskUserQuestion` の直後・`Step 9: embeds executability markers via verify-executability-marker.sh, no new comment` の直前) に、構造テスト 2 件を追加する (Implementation Steps 3)
- 以下は Steering Docs sync candidate 確認の記録 (件数はすべて `docs/ tests/ scripts/ modules/` を対象にした `grep -rl -F` の結果で、`docs/spec/` と `docs/sessions/` を含む。2026-10-16 実測):
  - [Steering Docs sync candidate] keyword "verify-classifier.md" skipped: matched 149 files (no discriminating power)
  - [Steering Docs sync candidate] keyword "Step 8b" skipped: matched 36 files (no discriminating power)。参考として履歴 (`docs/spec/`・`docs/sessions/`・`docs/reports/`) を除く 10 件 (`docs/structure.md`・`docs/ja/structure.md`・`modules/l0-surfaces.md`・`modules/verify-executor.md`・`modules/event-emission.md`・`scripts/collect-verify-retention-stats.sh`・`scripts/scan-pending-ac.sh`・`scripts/emit-event.sh`・`scripts/verify-executability-marker.sh`・`tests/verify.bats`) の該当行を読んだ。`tests/verify.bats` を除く 9 件はいずれも Step 8b を名前・目的で指すのみで、判定の根拠 (「条件文に基づく」等) を述べていない。Step 8b の見出しと番号は変えないため参照は有効のまま
  - [Steering Docs sync candidate] keywords "Executable examples" / "Claude Executability Judgment": 合計 3 件で、すべて `docs/spec/` の履歴 Spec (#780・#1170・#1278)。追加候補なし
  - [Steering Docs sync candidate] `executable=true` の消費側 (`grep -rn 'executable=true' skills/ modules/ scripts/`、5 件): `skills/audit/SKILL.md` (N2 バケットの定義)・`modules/l0-surfaces.md` (マーカー例)・`scripts/verify-executability-marker.sh`・`scripts/emit-event.sh`・`skills/verify/SKILL.md`。値の文字列・マーカー形式・語彙は変えず、N2 の意味 (「次の `/verify` で自動解決する見込み」) は変更後も正確なので更新不要
  - [Steering Docs sync candidate] Listing-side sub-check: 発火せず。サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし。`docs/structure.md` の `modules/verify-classifier.md` の 1 行説明 (「post-merge condition verifiability classification ...」) は新しい節を含めても正確なまま
  - [Outbound pointer sync candidate] 追加する節が指す先を確認した: `skills/verify/SKILL.md` Step 8b (Changed Files に含む)・`modules/verify-patterns.md` § 11 (読んで確認済み。§ 11 は `manual` を自動化可能な検証へ置き換える手順で、追加する注意と矛盾せず変更不要)。`skills/verify/SKILL.md` Step 8b が指す `modules/l0-surfaces.md` § Machine-Readable Event Marker は語彙不変のため変更不要
  - `docs/ja/` 同期: Changed Files に `docs/` 直下の `.md` が無いため `docs/translation-workflow.md` の同期対象外
  - その他: `README.md`・`README.ja.md`・`CLAUDE.md`・`docs/workflow.md` は実行可否の判定基準・`verify-type` の分類基準を扱わない (`grep -n -i -E 'executab|verify-type'` のヒットは `README.md` 13 行目の散文 "executable tasks" のみ)。`modules/verify-classifier.md` の内容を参照する他のテスト (`tests/issue.bats`・`tests/spec.bats`・`tests/opportunistic-search.bats`・`tests/verify-executor.bats`) は固定の語句 (`pr-review-light`・Patch Route CI Verification Note 等) のみを検査し、節の追加で影響を受けない

## Implementation Steps

1. `modules/verify-classifier.md`: Changed Files 記載の位置に、新規 `###` 節 (見出しレベルは兄弟の `### observation Type: ...` と同じ h3) `### manual Type: Subject Wording Does Not Decide the Type` を挿入する。内容は英語のみ、CJK 文字を含めない。必須要素 (→ 受入条件 1, 2, 5):
   - `manual` の行は残余の型で、本当に人の判断が要る条件 (視覚的な確認・UX の評価・外部サービスでの操作) に使うこと。注意は表の基準・優先順位を変えず、割り当ての前に適用すること
   - 注意 1: 条件文が人を主語に書いていても、それだけで `manual` にしない。見るべきは「満たされたかを確かめる作業に人の判断が要るか」。`/verify` Step 8b の実行可否も同じ読み方で、証拠の所在 (運用ログ・生成ファイル・設定値・外部サービスの画面) で判断し、文の主語では判断しない
   - 注意 2: 運用ログ・生成ファイル・設定値を読めば判定できる条件は、`verify-type: auto` + `command` / `file_contains` / `rubric` で書く。`auto` は verify command の添付が必須であること (同ファイルの "Constraint: Required Rule When Using auto Type" 参照) と、置き換え候補が `modules/verify-patterns.md` § 11 にあること
   - 注意 3: 人が一度実行する必要があるだけの条件は、実行の受入条件と確認の受入条件の 2 つに分ける。確認は実行が残す証拠 (ログの行・生成ファイル) を読む `auto` で書き、人に残るのは実行だけ
   - 書かないこと: `scripts/*.sh` のパス (allowed-tools 連鎖の対象外にする)、「exhaustive」「always」等の網羅の断定、`docs/product.md` § Terms の旧称 (Formerly called 列) にある非推奨用語 (検証コマンドは `verify command` と書く)
2. `skills/verify/SKILL.md` (parallel with 1): Changed Files 記載のとおり編集する (→ 受入条件 3, 4)。必須要素:
   - 導入段落: 先に「この条件を満たす証拠は今存在するか」を問う (太字)。証拠が今存在するとは、Claude が今読める場所 (運用ログ・生成ファイル・設定値) にあるか、読み取り専用のコマンド (ドライラン・`grep`・検査スクリプト) で今得られること。判断は証拠の所在で行い、条件文が誰を主語にしているかでは行わない。存在するなら `executable=true` と判定する (文言は `regardless of who the condition names as the subject` を含める)
   - Executable examples 直下の入れ子の箇条書き 1 行: 人を主語にした条件 (`<person>` が `<operations host>` で `<cmd> --dry-run` を実行して件数を見る形) でも、証拠が既にログ・生成ファイル・設定値にあれば executable
   - Non-executable examples の後の短い段落: 証拠が今存在しない場合は原因で記録を分ける。まだ作られていない (次の定期実行が未実施でファイルが未生成) 場合は、その回の `executable=false` が正しい判定で、`reason=other` + 待っている対象を書いた `detail` で記録し、証拠が現れた後の `/verify` 再実行で `executable=true` に変わる。人の判断そのもの (視覚的な確認・UX の評価・外部サービスでの操作) が要る場合は対応する `reason`。証拠が既に存在するのに条件文が人を主語にしているだけで non-executable と記録しない
   - Step 7: `quick preview judgment based on condition text (rubric detailed in Step 8b)` を、Step 8b の rubric を使う旨 (証拠の所在が先で、主語は判断に使わない) に置き換える。列の仕様 (`Yes — ...` / `No (...)` / `—`) は変えない
   - 守ること: 半角 `!` を本文に書かない、`Step 8b.1` のような小数のステップ番号を作らない、新しい見出しを作らない、`scripts/` 配下の新規参照を足さない
3. `tests/verify.bats` (after 2): Changed Files 記載の位置に構造テスト 2 件を追加する。入力は `skills/verify/SKILL.md` の実体で、既存ヘルパー `step8b_section` (`md_section "$SKILL_FILE" "#### Step 8b: "`) が返す Step 8b 節。アサートは `grep -q -F` の固定文字列で、`[[ "$output" ... ]]` は使わない。テスト名とアンカーは Notes「挿入文案ドラフト」のとおり (→ 受入条件 3, 4 の回帰保護。新しい判定の分岐を持つ手順なので、既存スイートが PASS することだけでなく、新規テストケース 2 件 (`tests/verify.bats` に `Step 8b: executability judgment asks whether the evidence exists now before reading the subject (Issue #1531)` と `Step 8b: executable examples include a person-subject condition whose evidence is in a log or file (Issue #1531)`) を追加したうえでスイートが PASS すること)
4. `skills/verify/SKILL.md` のマーカー再計算 (after 1, 2, 3): **`skills/verify/SKILL.md` への最後の編集として**行う。`wc -l < skills/verify/SKILL.md` の値で `<!-- skill-body-lines: 997 -->` の数値を、`grep -v '<!-- skill-body-' skills/verify/SKILL.md | shasum -a 256 | cut -c1-8` の値で `<!-- skill-body-sha: 90e3f8ce -->` の 16 進値を書き換える。マーカー行自体は行数を変えず、ハッシュの計算から除外されるため、2 つの更新順序は問わない。後から base ブランチに SKILL.md の変更が入って rebase / merge した場合も、再計算してからコミットする (→ `tests/verify.bats` の 2 テストと CI の `check-skill-body-hash` ジョブ)
5. 自己検証 (after 4): `bash scripts/check-skill-body-hash.sh`、`python3 scripts/validate-skill-syntax.py skills/`、`git diff -- skills/ modules/ | python3 scripts/check-language-convention.py`、`bash scripts/check-forbidden-expressions.sh`、`bats tests/verify.bats`、続けて `bats --jobs <N> tests/` を、それぞれ単一コマンドで実行する (`/code` の Behavioral Change Detection が全スイートを選ぶ)。あわせて `git diff -- modules/verify-classifier.md` の削除行 (`-` で始まる本文行) が 0 件で、追加が新規 1 節のみであることを確認する (→ 受入条件 5)。新規 2 テストは実装前に FAIL する (Step 8b に該当の 4 文字列が 0 件) ことを `git show HEAD:skills/verify/SKILL.md` で確認してから PASS を確認する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-classifier.md に、条件文が人を主語に書いていてもそれだけで manual にしない旨と、判定は証拠の所在 (ログ・ファイル・外部サービス) で行う旨の注意が書かれている" --> `modules/verify-classifier.md` の `manual` の節に、条件文の主体と型の判定を切り離す注意がある
- <!-- verify: rubric "modules/verify-classifier.md に、運用ログ・生成ファイル・設定値を読めば判定できる条件は verify-type: auto 側で書く旨と、人が一度実行する必要があるだけの条件は実行の受入条件と確認の受入条件に分ける旨が書かれている" --> `modules/verify-classifier.md` の同じ注意に、読み取りで判定できる条件は `auto` 側に寄せる旨と、人が一度実行するだけの条件は実行の受入条件と確認の受入条件に分ける旨がある
- <!-- verify: rubric "skills/verify/SKILL.md Step 8b の Claude Executability Judgment が、条件を満たす証拠が今存在するかを先に問い、存在するなら条件文が誰を主語にしていても executable=true と判定する旨を述べている" --> `skills/verify/SKILL.md` Step 8b の実行可否の判定が、「この条件を満たす証拠は今存在するか」を先に問い、存在するなら条件文の主語によらず executable と判定する旨を述べている
- <!-- verify: rubric "skills/verify/SKILL.md Step 8b の Executable examples に、条件文が人を主語にしていても証拠がログやファイルにある場合は executable と判断できる例が足されている" --> `skills/verify/SKILL.md` Step 8b の実行可否の例に、人を主語にした条件でも証拠がログ・ファイルにあれば executable と分かる例がある
- <!-- verify: rubric "modules/verify-classifier.md への追記は manual の節への注意の追加に限られ、Classification Criteria の表の 4 型の定義と優先順位の行が差分で変更されていない" --> 既存の分類の表 (`auto > opportunistic > observation > manual` の優先順位) の意味を変えていない

### Post-merge

- 次に人を主語にした Post-merge の受入条件を持つ Issue で `/verify` を走らせたとき (本変更の反映後に始まった会話セッション以降)、証拠がログ・ファイルにある条件が `executable=true` と判定され、`/verify` の結果コメントの `type=verify-executability` マーカーに `executable=true` として記録される <!-- verify-type: opportunistic -->

## Notes

- **設計判断 (非対話モードでの自動解決): module の追記は新しい `###` 節にする**。却下した案: (1) 分類基準の表の `manual` 行に追記 — 受入条件 5 が表の定義行の差分での変更を禁じるため不可。(2) `## Purpose` に追記 — 同上、追記は「`manual` の節への注意の追加」に限る。(3) 既存の `Constraint: Required Rule When Using auto Type` 節に統合 — `manual` に特化した注意でなくなり、受入条件 1 の「`manual` の節」から外れる。見出しは兄弟節 (`observation Type: ...`) の命名に揃え、`Tag Assignment Example` の前 (型ごとの節が並ぶ領域の末尾) に置く。分類基準の優先順 (auto > opportunistic > observation > manual) の最後に当たる `manual` の節が、`observation` の節群の後に来る並びにもなる
- **設計判断: `reason` 語彙には触れない (Issue 本文の「スコープ外」準拠)**。証拠がまだ存在しない場合の記録は現行語彙の `reason=other` + `detail` で行い、その旨を Step 8b に 1 段落で明記する (Issue 本文の「(a) は現行どおり `reason=other` + `detail` で記録する」の文言化)。`/audit` の Manual Waiting Count は `other` を N4 (人手キュー) に数える (`skills/audit/SKILL.md` の N4 の定義) ため、語彙拡張の別 Issue が入るまでは「証拠待ち」も N4 に入る。これはスコープ外判断の帰結であり、本 Issue では変更しない。段落ごと省く案は、(a) と (b) が同じ `executable=false` に見えて (b) が放置される Background の問題を残すため採らなかった
- **設計判断: 「証拠が今存在する」の範囲**。Issue 本文の Background は、実際に ssh でのドライラン・設定ファイルの `grep`・検査スクリプト・運用ログの読み取りで判定できたと述べている。そこで「Claude が今読める場所にある」に加えて「読み取り専用のコマンドで今得られる」も含める。読み取り専用に限るのは、本番の状態を変える操作を executable と誤判定しないため (Non-executable examples の production 上の操作との境界を保つ)。外部サービスの画面は、Claude が読めない場合は従来どおり non-executable (Issue 本文の提案 3 が証拠の所在に挙げる「外部サービスの画面」と、既存の Non-executable examples の "external service dashboard confirmation" は、「Claude が読めるか」で整合する)
- **設計判断: Step 7 の 1 箇所を揃える**。`Claude Executable?` 列の説明が `based on condition text` のままだと、今回正す誤判定 (条件文の主語で決める) を事前表示の段階で再生産する。参照先を Step 8b の rubric に置き換えるだけで、列の仕様は変えない。Issue 本文の受入条件には含まれない同一ファイル内の整合修正だが、Purpose (「`/verify` が毎回『人が確かめてください』と案内するだけになるのを防ぐ」) の範囲内
- **設計判断: 受入条件は Issue 本文のまま (rubric 5 件)**。`modules/verify-patterns.md` § 9 は rubric に補助の `section_contains` を併用するよう勧めるが、/spec は Issue 本文を SSoT として扱い (Verify command sync rule)、/issue が rubric 5 件に確定した経緯 (Issue Retrospective) もあるため、Issue 本文の AC は書き換えない。決定論的な安全網は、CI で実行される `tests/verify.bats` の構造テストで置く。AC1〜AC4 の rubric は実装前の状態では満たされない (該当の注意・問い・例がまだ無い) ので、常時 PASS にはならない。AC5 は Triage の AC 監査コメントを受けて /issue が差分参照の文言に絞り済み
- **新規テストの要件 (light のため Notes に記録)**: Step 8b に「証拠の存在を先に問う」新しい判定の分岐が加わるため、既存スイートの PASS だけでなく新規ケース 2 件の追加を求める。module 側の追記は文書のみで新規の分岐ではないため、テストは足さない。入力形式: `skills/verify/SKILL.md` の実体、フィクスチャなし、`step8b_section | grep -q -F`。実装前 FAIL の確認 (2026-10-16 実測): 固定文字列 4 つ (下記) は現行の Step 8b に各 0 件。`[[ "$output" ... ]]` を使わないので `scripts/check-bare-bracket-assertions.sh` の対象外
- **`skill-body-*` マーカー**: `skills/verify/SKILL.md` は冒頭に `<!-- skill-body-lines: N -->` と `<!-- skill-body-sha: H -->` を持ち、`tests/verify.bats` の 2 テスト (194〜206 行) と CI の `check-skill-body-hash` ジョブ (`.github/workflows/test.yml`) が実体との一致を検査する。ハッシュは両マーカー行を除いた本文から計算する (`scripts/check-skill-body-hash.sh`)。ベースラインは 997 行 / `90e3f8ce` で一致していることを確認した (2026-10-16)。想定される増分は約 3 行 (入れ子の箇条書き 1 行 + 空行と段落 2 行)。他の Issue が並行して SKILL.md を変更しうるため、コミット直前と rebase / merge 後に再計算する。行数の上限を定める規則は見つからなかった (`docs/tech.md`・`docs/structure.md`・`skills/spec/skill-dev-constraints.md`・`modules/skill-dev-checks.md` を確認)
- **制約への適合 (`skills/spec/skill-dev-constraints.md` を light でも確認した)**: (1) 追記は英語のみで CJK 文字を含めない (CI の `language-convention` が `git diff -- skills/ modules/ scripts/` の追加行を検査)。(2) `docs/product.md` § Terms の旧称 (Formerly called 列) にある非推奨用語を使わず、検証コマンドは `verify command` と書く (CI の `check-forbidden-expressions` が `skills/ modules/ agents/ tests/ docs/ scripts/` を走査し、この Spec 自身も `docs/` 配下なので対象になる)。(3) SKILL.md 本文に半角 `!` を書かない・小数のステップ番号を作らない (`validate-skill-syntax.py`)。(4) 新しい見出しは module の h3 1 つのみで、`SKILL.md` には作らない。(5) `modules/verify-classifier.md` の追記に `scripts/*.sh` のパスを書かないので、allowed-tools 連鎖 (Case 2) の対象外。`skills/verify/SKILL.md` にも `${CLAUDE_PLUGIN_ROOT}/scripts/` の新規参照を足さないので frontmatter は変えない。(6) module の説明に「exhaustive」等の網羅の断定を書かないので、網羅性の機械的検証 (grep) の追加ステップは不要
- **Issue 本文と実装の照合 (矛盾検出)**: Background の主張 — 分類の表が `manual` を「Does not match any of the above」と定め、例が "Confirm no dialog appears"・"Visual browser verification" であること (`modules/verify-classifier.md` 28 行目)、Step 8b の実行可否の判定が条件文を見て行うこと (`skills/verify/SKILL.md` 378 行目の導入文)、`reason` 語彙が `modules/l0-surfaces.md` で「exhaustive, 6 values」と定義されていること (228 行目)、検証が `scripts/verify-executability-marker.sh`・`/audit` の集計・テストに波及すること (すべて実在を確認) — はいずれも実装と一致し、矛盾は無い。補足: 提案 3 の「証拠の所在 (ログ・ファイル・外部サービスの画面)」と既存の Non-executable examples の外部サービスのダッシュボードの扱いは「Claude が読めるか」で整合させた (上記の設計判断)
- **Tag/enum の意味拡張の消費側スイープ**: 該当せず。`verify-type: manual` の値の意味 (人の判断が要る) は広げず、割り当ての判断材料を明確にするだけ。`executable=true` が付く条件の範囲は広がるが、値の文字列・マーカー形式・語彙は不変で、消費側 (`grep -rn 'executable=true' skills/ modules/ scripts/` の 5 件、Changed Files の記録を参照) は値の意味に依存した分岐を持たない。`/audit` の N2 (「次の `/verify` で自動解決する見込み」) は、変更後の方がむしろ正確になる
- **audit/investigation-type の判定**: no (判定基準の文言修正であり、既存項目を分類した結果を後続処理が根拠として読む監査・調査の Issue ではない)。fail-safe critical script: 該当なし (スクリプト変更なし)。外部仕様依存・tool 検出・新規依存パッケージ・adapter 追加: いずれもなし。Costly / irreversible なステップ: なし
- **rubric AC5 の留意 (patch route)**: AC5 は差分を見る rubric なので、`modules/verify-classifier.md` の差分は新規 1 節の追加行だけにする (既存行の改行・空白の整形も含めて触らない)。Implementation Steps 5 の `git diff` による削除行 0 件の確認が、この前提の機械的な裏取りになる
- **Self-hosting と Post-merge**: wholework は自分自身を使うため、`skills/verify/SKILL.md` の変更は、変更が base に入った後に始まった会話セッションで読み込まれてはじめて有効になる (`modules/verify-classifier.md` § observation Type: Event Values and Syntax の `session=next` の説明を参照)。Post-merge の条件は Issue 本文のとおり `opportunistic` (「`/verify` を走らせたとき」の形で、`verify-classifier.md` の `opportunistic` の定義に合う) で、「本変更の反映後に始まった会話セッション以降」と文中に明記済みのため `session=next` は不要 (`session=next` は `observation` のタグの属性)。`event=` を持たない `opportunistic` なので語彙の照合も対象外
- **Size**: Changed Files は 3 件 (Axis 1 = M)。既存パターンの横展開 (−1: #780 の Executable examples への例の追加と #1527 の module 段落 + 内容アサートのテストの踏襲) で S。複数スキルにまたがる増加要因は無い (SKILL.md の変更は `/verify` のみ)。triage 時点の S から Step 18 で再評価する。`ALWAYS_PR=false` (`.wholework.yml` に `always-pr` なし)。Pre-merge に `github_check "gh pr checks"` は無く、route に応じた書き換えは不要
- **コメント消費**: cutoff は直近の `phase/issue` ラベル付与 (2026-10-16T00:28:05Z)。cutoff 以降の 1 件 (Issue Retrospective) は first-class で、内容は Issue 本文の最新版に反映済み。cutoff より前の 2 件 (`executable=false` の 2 種類を整理した追記コメント、Triage の AC 監査コメント) は `/issue` が消費済みで、(a) 証拠待ち / (b) 主体が人名のための誤判定の区別は Background に、AC5 の差分参照化は受入条件に取り込まれている。クロスフェーズのマーカー (`verify-fail` / `preview-ac-unverified`) は無い
- **先行事例**: #780 (Step 8b の Executable examples へ「source code から default 挙動が決まる observation」を追加) — 同じ行への例の追加という形を踏襲。#1527 (`modules/verify-classifier.md` への段落追加 + `tests/*.bats` の内容アサート) — 追記と回帰保護テストの組み合わせ、およびこの Spec の「挿入文案ドラフト」の書き方を踏襲
- **挿入文案ドラフト** (`/code` は趣旨と必須要素を保てば文言を調整してよい。ただしテストが固定文字列で検査する 4 つ — `does the evidence that satisfies this condition exist now?` / `regardless of who the condition names as the subject` / `names a person as the actor` / `already in a log, a generated file, or a configuration value` — を変える場合は、テストの文字列も同じ文言に揃える。英語のみで CJK 文字を含めない):

  `modules/verify-classifier.md` に挿入する節 (`### Tag Assignment Example` の直前、空行 1 行で区切る):

  ```markdown
  ### manual Type: Subject Wording Does Not Decide the Type

  The `manual` row in the table above is a residual class: it is for conditions whose check genuinely needs a human's judgment at verification time (visual confirmation, UX evaluation, an operation on an external service). Apply the notes below before assigning it. They add to the table and do not change its criteria or the priority order.

  1. **The actor named in the text does not decide the type.** A condition written with a person as the subject (for example, "`<person>` runs `<cmd> --dry-run` on `<operations host>` and checks the counts") is not `manual` for that reason alone. Ask whether checking that the condition holds needs a human's judgment, not who the text says performs the action. The same reading applies when `/verify` judges executability (`skills/verify/SKILL.md` Step 8b): decide by where the evidence lives (an operational log, a generated file, a configuration value, an external service screen), not by the subject of the sentence.
  2. **Move conditions that can be settled by reading toward `auto`.** When the evidence is an operational log, a generated file, or a configuration value that can be read, write the condition as `verify-type: auto` with a `command`, `file_contains`, or `rubric` verify command. `auto` requires an attached verify command (see "Constraint: Required Rule When Using auto Type" below); `modules/verify-patterns.md` § 11 lists replacement candidates.
  3. **Split "a person runs it once" from "check the result".** When a person only needs to run something once so that the evidence gets produced, write two conditions: an acceptance condition for the execution, and a separate acceptance condition for the check. The check reads the evidence the run leaves (a log line, a generated file) and is written as `auto`; only the execution stays with the person.
  ```

  `skills/verify/SKILL.md` Step 8b の導入文 (置き換え後):

  ```markdown
  Evaluate whether Claude can directly execute the verification. Ask first: **does the evidence that satisfies this condition exist now?** The evidence exists now when it is already in a place Claude can read (an operational log, a generated file, a configuration value) or Claude can obtain it now with a read-only command (a dry-run, a `grep`, an inspection script). Judge by where the evidence lives, not by who the condition text names as the actor: if the evidence exists now, judge `executable=true` regardless of who the condition names as the subject. Use the examples below to calibrate:
  ```

  `- **Executable examples**:` の行 (既存のまま) の直下に追加する入れ子の箇条書き (インデントは半角スペース 2 つ):

  ```markdown
    - a condition that names a person as the actor (e.g., "`<person>` runs `<cmd> --dry-run` on `<operations host>` and checks the counts") when the evidence is already in a log, a generated file, or a configuration value Claude can read
  ```

  `- **Non-executable examples**:` の行の直後 (空行 1 行を挟む) に追加する段落:

  ```markdown
  When the evidence does not exist now, the cause decides how to record it. Evidence that is still to be produced (for example, the next scheduled run has not happened and the file is not written yet) makes `executable=false` the correct judgment for this run: record `reason=other` with a `detail` naming what is awaited, so it can be told apart from a misjudgment, and re-running `/verify` after the evidence appears flips it to `executable=true`. A condition that needs a human's judgment itself (visual confirmation, UX evaluation, an operation on an external service) takes the matching `reason`. Do not record a condition whose evidence already exists as non-executable only because its text names a person; re-running `/verify` does not resolve that.
  ```

  Step 7 の `Claude Executable?` 列の説明 (該当部分のみ置き換え):

  ```markdown
  - **Claude Executable?**: for manual conditions only — quick preview judgment using the Step 8b rubric (where the evidence lives comes first; who the condition text names as the actor does not decide). For executable conditions, show the candidate command or approach. ...
  ```

  `tests/verify.bats` に追加するテスト (`step8b_section` は既存ヘルパー):

  ```bash
  # Content-assertion tests for the evidence-first executability judgment in Step 8b (added for #1531).
  # The judgment must ask where the evidence lives before reading the condition's subject, and the
  # Executable examples must show a person-subject condition whose evidence is already in a log or file.

  @test "Step 8b: executability judgment asks whether the evidence exists now before reading the subject (Issue #1531)" {
      step8b_section | grep -q -F "does the evidence that satisfies this condition exist now?"
      step8b_section | grep -q -F "regardless of who the condition names as the subject"
  }

  @test "Step 8b: executable examples include a person-subject condition whose evidence is in a log or file (Issue #1531)" {
      step8b_section | grep -q -F "names a person as the actor"
      step8b_section | grep -q -F "already in a log, a generated file, or a configuration value"
  }
  ```

## Code Retrospective

### Deviations from Design
- なし。「挿入文案ドラフト」の文言をそのまま使い、テストの固定文字列 4 件も変更していない。Step 7 の `Claude Executable?` 列も Spec 記載どおりに置き換えた。

### Design Gaps/Ambiguities
- Spec は `skill-body-lines` の想定増分を約 3 行としていたが、実測は 997 → 1000 行 (+3) で想定どおり。
- Spec の Implementation Steps 5 は `git show HEAD:skills/verify/SKILL.md` で実装前 FAIL を確認する手順だが、worktree isolation guard が `git show` を含む複合コマンドを拒否するため、`git show` を単独コマンドで `.tmp/` に書き出してから `grep -c -F` で数える 2 段に分けた (4 文字列とも実装前は 0 件)。
- rubric AC 5 件は独立の採点者を起動せず、差分との照合で直接評価した (patch route では `/review` が走らないため、`/verify` が実装後に改めて評価する)。

### Rework
- なし。

Confirmed pre-implementation FAIL for 2 new test(s) (固定文字列 4 件が実装前の `skills/verify/SKILL.md` に 0 件)。`bats tests/verify.bats` 32 件 PASS、`bats --jobs 4 tests/` の全スイートも失敗 0 件。`git diff -- modules/verify-classifier.md` の削除行は 0 件 (追加は新規 1 節のみ)。

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective: 前フェーズ (/issue) の自動解決ログ。語彙追加 (`reason=evidence-not-yet-available`) のスコープ外化、Post-merge の `opportunistic` 化、受入条件を rubric 5 件に整理した理由 / https://github.com/saitoco/wholework/issues/1531#issuecomment-6205214582

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `modules/verify-classifier.md` への追記は、Classification Criteria の表に触れない新規 `###` 節にした (受入条件 5 が表の定義行の差分での変更を禁じるため)。削除行 0 件を `git diff` で確認済み。
- `skills/verify/SKILL.md` Step 8b の判定は「証拠は今存在するか」を先に問う形にし、`reason` 語彙は触れず、証拠待ちは `reason=other` + `detail` で記録する旨を 1 段落で明記した。

### Deferred Items
- Post-merge の `opportunistic` 条件 (人を主語にした Post-merge 条件を持つ Issue で `/verify` が `executable=true` を記録する) は、本変更の反映後に始まった会話セッションでのみ検証できる。
- `reason` 語彙への `evidence-not-yet-available` 追加と除外理由の集計粒度は、Issue 本文のスコープ外のまま別 Issue 扱い。

### Notes for Next Phase
- patch route のため `/review` は走らない。Pre-merge の rubric 5 件は `/code` で差分との照合により評価済みで、チェック済み。`/verify` は Post-merge の `opportunistic` 条件を扱う。
- `skills/verify/SKILL.md` の `skill-body-lines: 1000` / `skill-body-sha: db37b840` は本変更の最終値。他の Issue が並行して SKILL.md を変更した場合は再計算が必要。
