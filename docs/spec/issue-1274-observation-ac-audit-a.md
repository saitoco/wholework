# Issue #1274: verify: #1163 由来の observation AC 29 行を実査し判定不能分を retire

## Overview

親 #1270 の sub-issue。#1163 が `verify-type: manual` → `verify-type: observation` へ再型付けした **29 AC 行** (`event=auto-run` 27 / `event=fix-cycle` 2) を対象に、**「指定 event が発火したとき、何を根拠に PASS/FAIL を判定できるか」を 1 行ずつ実査**し、A/B/C/D/E に分類して処理する。

#1163 が確認したのは `opportunistic-search.sh --event <name>` の**マッチ集合に含まれること** (dispatch されること) だけで、**発火時に判定できること**は未確認だった。`opportunistic-search.sh:325` は AC 行が `^- \[ \]` + `verify-type: observation` + `event=<name>` にマッチするかしか見ず条件文の意味を解釈しないため、この 2 つは独立している。

成果物はリポジトリ内の記録ファイル 1 本 (`docs/reports/observation-ac-audit-a.md`) と、リポジトリ外の GitHub Issue 操作 (本文編集 / retire コメント / ラベル遷移)。observation dispatch 機構そのものは変更しない。

**実行前提は充足済み**: 親 #1270 の baseline (`docs/reports/observation-ac-audit-summary.md`) は 2026-08-08 計測分が既に存在する (母集団 85 AC 行 / 82 Issue)。分類 D の retire に着手してよい。

## Changed Files

- `docs/reports/observation-ac-audit-a.md`: 新規作成 — 29 AC 行の分類表 (Issue 番号 / AC 行要約 / event / 分類 / 判断根拠)、B/C の変更内容とマッチ集合再確認結果、D の retire 実施記録、E の差し戻し理由と `/verify` 実行時の判定手順、親 #1270 への引き継ぎサマリ
- `docs/structure.md`: 変更不要 — `grep -n "reports" docs/structure.md` で確認済み。Directory Layout tree に `docs/reports/` は既出 (line 62) で、Key Files 側は「スクリプトが消費する report ファイル」のみ列挙する方針 (`orchestration-recoveries.md` / `orchestration-fallbacks-archive.md`) であり、本記録ファイルは消費側スクリプトを持たない。先行する #1163 (`manual-ac-retype-a.md`) も同じ判断で未追加
- `docs/reports/observation-ac-audit-summary.md`: 変更不要 — 親 #1270 の担当。3 sub-issue の記録ファイルを統合するのは親の Pre-merge AC 3 であり、本 Issue が先回りして書くと親の集計対象が二重になる
- `docs/ja/` 同期: 対象外 — `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示的に除外
- リポジトリ外 (GitHub Issue 本文 / コメント / ラベル): 分類 B/C/E は対象 Issue 本文の AC 行を編集、分類 D は本文を編集せず retire コメント投稿 + `phase/verify` → `phase/done` 遷移 (#1166 方式)

## Implementation Steps

1. **前提確認と対象集合の再確定** — `docs/reports/observation-ac-audit-summary.md` の存在を確認し (親 baseline 完了の確認)、対象 29 AC 行の GitHub 実状態を再スキャンする。スキャンは各 Issue 本文の `### Post-merge` 節を切り出し (`opportunistic-search.sh:310` の `POST_MERGE_AWK` と同一境界ロジック)、`^- \[ \]` かつ `verify-type: observation` の行を数える。2026-08-09 実測では **#869 / #759 / #520 の 3 行が既に `- [x]` (PASS)** で、#759 / #520 は `phase/done` 済み。この 3 行は分類 A (実績により判定可能と確定) として記録し追加処理を行わない。残り 26 行が処理対象 (→ acceptance criteria 1)

2. **判定に使える情報源の確定** (1 の後) — 実査の判断基準を先に固定する。`skills/auto/SKILL.md` の `auto-run` dispatch は `observation-trigger.sh --event auto-run --session <SESSION_ID>` を呼び `--context-file` を渡さないため `keyword=` gate は無効、`when=<axis>:<value>` (`route` / `mode` / `recovery-tier` / `execution-context`) と `config=<key>` は有効。`/verify` の `fix-cycle` dispatch (`skills/verify/SKILL.md:625`) は `--event fix-cycle` のみで `--session` すら渡さないため `when=` の run-facts 系 3 軸は fail-open になる。この制約表を記録ファイルの冒頭に置き、以降の B/C 判断の根拠とする (→ acceptance criteria 1)

3. **29 AC 行の 1 行ずつの分類** (2 の後) — 各行について「指定 event の発火時に、条件文が要求する観測対象を実行事実・リポジトリ状態・GitHub 状態のどれから読めるか」を実査し A/B/C/D/E を決める。D と E の切り分けは親 #1270 の基準に従う (`/verify` Step 8b で Claude が実際に操作・確認して PASS/FAIL を出せるなら **E**、条件そのものが本リポジトリで原理的に成立しないなら **D**)。**「今の装備では実行できない」は D の理由にならない** — `.wholework.yml` に capability が無いだけなら E とし `capability=<key>` を併記する (→ acceptance criteria 1)

4. **分類 B/C の条件文書き換え** (3 の後) — 対象 Issue 本文の該当 AC 行のみを編集する。B は #1251 の draft 規約 (形態 1: rubric/条件文が参照ファイルを名指しする、形態 2: 数値条件は母集団定義を条件文自身に含める、形態 3: どの event でどう満たされるかを条件文から読めるようにする) に従い、判定に必要な情報を条件文に含める。gate 属性は `when=` / `config=` のみ付与し `keyword=` は付与しない (Step 2 の制約表による)。C は `event=` を有効 5 値 (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`) の別値へ差し替える。編集は `gh issue view <N> --json body -q .body` → `.tmp/issue-body-<N>.md` を Write → `scripts/gh-issue-edit.sh <N> .tmp/issue-body-<N>.md` → `rm -f` の手順。書き戻し前に `bash scripts/check-ac-checkbox-format.sh .tmp/issue-body-<N>.md` を通す (exit 2 = チェックボックス形式でない箇条書きが残存。`allowed-tools` 制約で実行できない場合のみ python3 等価判定へフォールバック) (→ acceptance criteria 5)

5. **分類 E の `verify-type: manual` 差し戻し** (3 の後、4 と並行可) — 対象 AC 行のタグを `<!-- verify-type: observation event=<name> ... -->` から `<!-- verify-type: manual -->` へ戻す。編集手順と形式検証は Step 4 と同一。差し戻し理由と「`/verify` 実行時に何をすれば判定できるか」を記録ファイルに書く。装備待ちのものは `capability=<key>` を併記する (語彙は `modules/l0-surfaces.md` § `type=verify-executability` の reason 表に準拠。例: `capability=capabilities.browser`) (→ acceptance criteria 1)

6. **分類 B/C 変更後のマッチ集合再確認** (4 の後) — `bash scripts/opportunistic-search.sh --event auto-run --dry-run` (B/C に `fix-cycle` があれば `--event fix-cycle` も) を実行し、書き換えた各 AC 行の Issue 番号がマッチ集合に含まれることを **AC 行単位で個別に**確認する。件数差分ではなく個別含有を正とする (#1163 の検証節と同じ扱い)。意図的にマッチ集合から外した行 (`when=` / `config=` gate により現在の実行文脈では除外される行) はその旨を記録する。母集団は `phase/verify` ラベル保持 Issue 100 件強で `gh issue view` を 1 件ずつ回すため 1 回あたり数分かかる — event ごとに 1 回だけ実行する (→ acceptance criteria 5)

7. **分類 D の retire** (3 の後、6 の後) — #1166 方式。**対象 Issue 本文の `### Post-merge` 節は編集しない**。(a) retire 理由を書いた `.tmp/retire-comment-<N>.md` を Write して `scripts/gh-issue-comment.sh <N>` で投稿 (本文には「Retire 決定」の見出し / retire 理由 / 起点 #1274 への参照を含める)、(b) `scripts/gh-label-transition.sh <N> done` で `phase/verify` → `phase/done` へ遷移。retire 後に当該 Issue の `### Post-merge` に未チェック条件が残る場合は、その Issue は `phase/verify` のままとし記録ファイルにその旨を書く (`phase/done` 遷移は「未チェック条件がゼロになった Issue」に限る) (→ acceptance criteria 3, 4)

8. **記録ファイルの作成と整合確認** (1〜7 の後) — `docs/reports/observation-ac-audit-a.md` を下記構成で作成する。作成後、(a) 分類表の行数が 29 であること、(b) 分類 D の各 Issue についてコメント URL・`### Post-merge` 非編集の確認・遷移後ラベルが書かれていること、(c) 記録した `phase/done` 遷移が `gh issue view <N> --json labels` の実状態と一致することを確認する (→ acceptance criteria 1, 2, 3, 4, 5)

   ```markdown
   # observation AC 実査: 区分 A (#1163 由来 29 AC 行) — #1274
   ## 実行前提と対象集合          (baseline 確認 / 29 行の内訳 / 既 PASS 3 行の扱い)
   ## dispatch 経路の制約         (Step 2 の gate 有効性表)
   ## 分類サマリ                   (A/B/C/D/E の件数と合計 29)
   ## 実査表                       (| Issue | AC 行要約 | event | 分類 | 判断根拠・変更内容・retire 理由・差し戻し理由 |)
   ## 分類 B/C: 変更内容とマッチ集合再確認
   ## 分類 D: retire 実施記録      (コメント URL / 本文非編集の確認 / 遷移後ラベル)
   ## 分類 E: 差し戻し記録         (理由 / `/verify` 実行時の判定手順 / capability=<key>)
   ## 親 #1270 への引き継ぎ         (D/E 内訳、E の「即判定可能」と「装備待ち」の分離)
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/observation-ac-audit-a.md に 29 AC 行すべての分類 (A/B/C/D/E) と、A については判定根拠 (どの情報源で PASS/FAIL が決まるか)、B/C については変更内容、D については retire 理由、E については差し戻し理由と /verify 実行時の判定手順が Issue 番号・AC 行単位で記載されている" --> 担当する 29 AC 行すべてについて、A/B/C/D/E の分類と判断根拠が `docs/reports/observation-ac-audit-a.md` に Issue 単位・AC 行単位で記載されている
- <!-- verify: file_exists "docs/reports/observation-ac-audit-a.md" --> 記録ファイル `docs/reports/observation-ac-audit-a.md` が作成されている
- <!-- verify: rubric "分類 D と判定した AC 行について、retire 理由が対象 Issue のコメントとして投稿され、かつ対象 Issue 本文の ### Post-merge 節が編集されていないことが docs/reports/observation-ac-audit-a.md に Issue 単位で記載されている" --> 分類 D の AC 行が #1166 方式で retire され、対象 Issue 本文の `### Post-merge` は編集されていない
- <!-- verify: rubric "retire 完了により未チェック条件がゼロになった Issue が phase/done へ遷移していることが docs/reports/observation-ac-audit-a.md に Issue 単位で記載され、GitHub 上の実状態と一致している" --> 分類 D の retire により未チェック post-merge 条件が残らなくなった Issue が `phase/done` へ遷移している
- <!-- verify: rubric "条件文を変更した AC について、変更後のマッチ集合への含有が個別に確認され docs/reports/observation-ac-audit-a.md に記録されている" --> 分類 B/C で条件文を変更した AC 行が、変更後も `opportunistic-search.sh --event <name> --dry-run` のマッチ集合に含まれる (または意図的に外れたことが記録されている)

### Post-merge

なし (効果測定は親 #1270 に集約)

## Notes

### Issue 本文との齟齬: 「対象 Issue 34 件」は 29 Issue が正

Issue 本文の「担当範囲」表は `対象 AC 行 29 行 / 対象 Issue 34 件` と書くが、**再型付けされた 29 AC 行が載る Issue は 29 件**である。34 は #1163 の全体スコープ (36 AC 行 / 34 Issue) 由来の数字で、差分 5 件 (#708 #704 #501 #500 #479) は `manual` 維持の対象外行しか持たず本 Issue の実査対象ではない (#719 だけは条件1 が対象外・条件2 が再型付け済みで両方に現れる)。先行 Spec `docs/spec/issue-1163-manual-ac-retype-a.md:34` も Changed Files に「GitHub Issue 本文, 29 AC 行 / 29 Issue」と書いており 29 が正。**非対話モードのため自動解決**: 記録ファイルには 29 AC 行 / 29 Issue を対象として記載し、34 との差分理由を「実行前提と対象集合」節に明記する。

### 実査着手前に確定した GitHub 実状態 (2026-08-09 実測)

29 行のうち **3 行は既に `- [x]` (PASS)** — #869 (`phase/verify` 継続、他条件が未チェックのため) / #759 (`phase/done`) / #520 (`phase/done`)。残り 26 行が未チェックで、すべて CLOSED + `phase/verify`。この 3 行は分類 A として記録するが再処理はしない (Auto-Resolve Log 参照)。実査時点で状態が変わっている可能性があるため Step 1 で再スキャンする。

### `keyword=` gate は `auto-run` / `fix-cycle` 経路では効かない

`modules/observation-trigger.md` § Condition Check Gate (`keyword=`) は `--context-file` が渡されたときのみ有効化される。`--context-file` を渡すのは `modules/opportunistic-verify.md` の opportunistic モード経路だけで、observation の event 経路 (`skills/auto/SKILL.md` の `auto-run` dispatch、`skills/verify/SKILL.md:625` の `fix-cycle` dispatch) はいずれも渡さない。したがって分類 B で `keyword=` を付与しても gate は無効化 (無条件マッチ) され dispatch の空振りは減らない。**分類 B で使える gate は `when=` (`route` / `mode` / `recovery-tier` / `execution-context`) と `config=` の 2 つのみ**。

### `when=` で表現できない軸がある

`modules/observation-trigger.md` の宣言可能軸は 4 つ (`route` / `mode` / `recovery-tier` / `execution-context`) で網羅。**「並列セッション環境」「reopen 済み Issue」「削除系 PR」といった軸は存在しない**ため、#861 / #859 (並列セッション) や #856 / #852 (reopen Issue) は `when=` では前提を宣言できない。同モジュール § "Conditions That Cannot Be Pre-Excluded" は、こうした条件を「毎回 dispatch して SKIPPED で返すのが正しい挙動」と位置づけるが、本 Issue の目的 (`observation-dispatch-threshold` の枠の空振り解消) はそれと逆向きである。この衝突は各行の実査で D / E のどちらに振るかで解消する — `/verify` 実行時に Claude が対象を実際に作って確かめられるなら E、作れないなら D。

### `config=` は boolean 専用

`config=<key>` は `get-config-value.sh` の制約 (フラット kebab-case または block 形式の 1 段ネストのみ、比較は `true`/`false` のみ) を継承する。`autonomy` のような enum キーは表現できない (#704 が `manual` 維持となった理由と同じ制約)。#700 の `auto-retry-on-fail.enabled` は 1 段ネストの boolean なので `config=auto-retry-on-fail.enabled` として表現可能。

### #1251 は未着地 — draft 規約に従う

Issue 本文は「分類 B の書き換えは #1251 の規約に従う」と書くが、**#1251 は 2026-08-09 時点で OPEN** (`triaged,retro/verify`、`phase/*` ラベル未付与) であり規約本体は着地していない。分類 B の書き換えは #1251 本文の Background が示す 3 形態 (形態 1: rubric/条件文が参照ファイルを名指しする、形態 2: 数値条件は母集団定義を条件文自身に含める、形態 3: どの event でどう満たされるかを条件文から読めるようにする) を draft 規約として適用する。

### `check-ac-checkbox-format.sh` は `/code` の `allowed-tools` に未登録

`skills/code/SKILL.md:5` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh:*` は含まれない (`python3:*` は含まれる)。本 Issue は既存 AC の実査が目的であり SKILL.md 変更はスコープ外のため `allowed-tools` への追加は行わず、実行できない場合は python3 等価判定へフォールバックする (#1165 の先例 — 親 #1270 Notes に記録)。この判断により `## Tool Dependencies` 節は不要 (`allowed-tools` frontmatter への追加が発生しない)。

### route は operate ではなく pr

先行する #1166 (retire 方式の出典) は operate route (リポジトリファイル変更なし) だったが、本 Issue は `docs/reports/observation-ac-audit-a.md` を新規作成するため `## Changed Files` にリポジトリファイル項目が存在し、`modules/size-workflow-table.md` § "Diff-less Axis (operate route)" の 2 条件を満たさない。**Size L → pr route** が正。#1166 の Verify Retrospective が記録した「operate route + observation AC の deadlock」(CLOSE されないと `opportunistic-search.sh` の母集団に入らない閉路) は、pr route かつ post-merge AC なしの本 Issue には発生しない。なお当該 deadlock の真因だった母集団の closed 限定は #1242 で解消済み (`opportunistic-search.sh:293` は現在 `--state all`)。

### Pre-merge 検証項目に `file_contains` 補助を追加しない判断

`modules/verify-patterns.md` §9 は rubric に数値リテラルが含まれる場合の `file_contains` 併用を推奨するが、Verification 項目 1 の「29 AC 行」はコード上の定数ではなく記録ファイル内の集計値であり、`file_contains "..." "29"` は誤マッチしやすく判定力が低い。また Issue 本文の Pre-merge AC (5 件) を逐語コピーする「Verify command sync rule」を優先し、件数整合 (Issue 本文 5 件 = Spec 5 件) を維持した。rubric text は対象ファイルを名指ししているため grader の可視範囲の問題 (#1251 形態 1) は生じない。

### Simplicity rule

Implementation Steps 8 個・Pre-merge 検証 5 項目で、いずれも SPEC_DEPTH=full の上限 (各 10) 内。

## Consumed Comments

cutoff: `2026-08-08T14:13:15Z` (直近の `phase/*` ラベル付与時刻)。cutoff 以降のコメント 1 件を消費した。cross-phase marker 例外 (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャンでは該当なし。

- saito / MEMBER / first-class / `/issue 1274 --non-interactive` の Issue Retrospective — 曖昧性の自動解決 1 点 (実行前提の明記) の記録。内容は Issue 本文の `## Auto-Resolved Ambiguity Points` に反映済みで、本 Spec の「実行前提は充足済み」判断の根拠として消費した / https://github.com/saitoco/wholework/issues/1274#issuecomment-5226494380
- saito / MEMBER / first-class / ## Autonomous Auto-Resolve Log / https://github.com/saitoco/wholework/issues/1274#issuecomment-5228146102
