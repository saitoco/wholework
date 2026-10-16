# Issue #1533: auto: L3 notable 判定のコミット数を batch 対象 Issue の実装コミットに絞る

## Overview

`skills/auto/SKILL.md` Step 5 の L3 auto-retrospective は、batch route の notable 判定の 1 条件として「セッションのコミットが 3 件以上」を数える。数え方が `git log --oneline --since="$session_start"` の行数で、observation dispatch の `/verify` が 1 件ごとに積む Consumed Comments フォールバックのコミットや、`/spec`・`/code`・`/merge` が Spec に残すフェーズ記録のコミットまで数えるため、recovery・FAIL・kill がいずれも 0 件の 2 件 batch でも毎回 notable になる。実測では、2 セッションとも全コミット (10 件・11 件) のうち実装コミットは各 2 件だった (Notes「再現による検証」)。

数える対象を、batch 対象 Issue の実装コミット (`closes #N` を含むコミット、または PR のマージコミット) に絞る。閾値 3、他の 3 条件 (Tier 2/3 recovery・Verify FAIL・Watchdog kill)、XL route の条件は変えない。Issue 本文の「Auto-Resolved Ambiguity Points」は「どう数えるか」を `/spec` の責務とした。この Spec が選んだ方法と却下した案は Notes「設計判断」に記録する。

1. `skills/auto/SKILL.md`: batch route の箇条書き `Commit count for this session >= 3 (...)` を、対象・数える基準・数えない理由・数え方のコマンドを入れ子で述べた 1 項目に置き換える。数え方は `git rev-list --count` の 1 コマンドで、patch route の `closes #N` と pr route の PR タイトル `Issue #N:` の 2 パターンを照合する。空の入力や git の失敗は 0 件 (条件不成立) に倒す
2. `tests/auto.bats`: 数え方を実コミット履歴に見立てた fixture で検証するテストと、文言の回帰保護テストを足す

## Changed Files

- `skills/auto/SKILL.md`:
  - Step 5 の L3 auto-retrospective の `3. **Notable judgment**` サブステップ内、batch route の箇条書き `- Commit count for this session >= 3 (`commit_event > 0`; ...)` (現状 829 行、5 スペースインデントの 1 行) を置き換える。置き換え後は同じ位置に、入れ子の箇条書き (対象 Issue・数える基準・数えない理由・数え方のコマンド) を持つ 1 項目になる。内容は Implementation Steps 1 と Notes「挿入文案ドラフト」
  - 変更しない: 最初の ```` ```bash ```` ブロック (jq 集計。`tests/auto.bats` が先頭ブロックを抽出する)、`commit_event` を含む jq 集計の 4 フィールド、他の 3 つの batch 条件、XL route の条件、`3. **Notable judgment**` と `4. **Fetch the Metrics section**` の番号付き行 (テストが範囲の開始と終了に使う)、frontmatter の `allowed-tools` (新規の `${CLAUDE_PLUGIN_ROOT}/scripts/` 参照を足さない。`git` と `jq` は元から本文で使われており、`scripts/validate-skill-syntax.py` の allowed-tools 検査は `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` の参照だけが対象)
  - Step 5 の区間 (現状 699〜954 行) に h3 以上の見出しを新設しない (AC1 の `section_contains` が `### Step 5: Completion Report` を起点に次の h3 以上の見出しまでを走査するため。Notes「`section_contains` の走査範囲」)
  - `skill-body-lines` / `skill-body-sha` マーカーは `skills/auto/SKILL.md` に無く、再計算は不要 (`grep -c "skill-body-" skills/auto/SKILL.md` が 0)
- `tests/auto.bats`: 既存の Notable judgment テスト群の末尾 (`Notable judgment jq aggregation counts matching events and ignores unrelated ones` の直後・`# Tests for Skill Self-Update Propagation check comparing against origin (Issue #1206)` コメントの直前) に、ヘルパー 3 つ (`notable_judgment_commit_count_command`・`batch_session_commit`・`batch_session_repo`) とテスト 4 件を追加する (Implementation Steps 2)。既存のテスト・ヘルパーは変更しない
- 以下は Steering Docs sync candidate 確認の記録 (件数はすべて `docs/ tests/ scripts/ modules/` を対象にした `grep -rl -F` の結果で、`docs/spec/`・`docs/sessions/`・`docs/reports/` を含む。2026-10-16 実測):
  - [Steering Docs sync candidate] keyword "notable" skipped: matched 50 files (no discriminating power)。参考として履歴 (`docs/spec/`・`docs/sessions/`・`docs/reports/`) を除く非履歴ヒットを読んだ (`grep -rn -i notable docs README.md README.ja.md skills modules scripts agents tests`)。`docs/structure.md` と `docs/ja/structure.md` は「L3 session retrospectives ... notable batch/XL only」と概括するだけで条件を述べない。`docs/tech.md` と `docs/ja/tech.md` は #913 の経緯の記録。`modules/run-fact-matching.md` は reconcile の schema に notable 判定結果が無い理由の説明。`skills/audit/SKILL.md` は not-notable セッションに `session.md` が無いことの説明。`skills/verify/SKILL.md` と `skills/issue/SKILL.md` は別の規則 (`retrospective skipped: no notable content`)。いずれも更新不要
  - [Steering Docs sync candidate] keyword "auto" (skill 名) skipped: matched 1036 files (no discriminating power)
  - keyword "commit_event": 2 件。`tests/auto.bats` (Changed Files に含む。jq 集計の 4 フィールドの形を固定しているので `commit_event` は残す) と履歴の `docs/spec/issue-913-notable-judgment-jq-summary.md`
  - keyword "Notable judgment": 6 件。`tests/auto.bats` (含む) と履歴 5 件 (`docs/spec/` 4 件・`docs/reports/` 1 件)
  - keyword "session_start": 8 件。すべて履歴 (`docs/spec/` 6 件・`docs/sessions/` 1 件・`docs/reports/` 1 件) で追加候補なし
  - keyword "BATCH_ISSUES_RE" (この変更で新設する変数名): 0 件 (名前の衝突なし)
  - [Steering Docs sync candidate] Listing-side sub-check: 発火せず。サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし。`docs/structure.md` の `docs/sessions/{SID}-{DATE}/` の説明 (「notable batch/XL only」) は新しい数え方でも正確なまま
  - [Outbound pointer sync candidate] 置き換える箇条書きには他のリポジトリファイルへのポインタを足さない。`skills/auto/SKILL.md` Step 5 の既存ポインタ (`modules/retro-proposals.md`・`scripts/get-auto-session-report.sh` など) は notable 判定の数え方と無関係で、更新不要
  - `docs/ja/` 同期: Changed Files に `docs/` 直下の `.md` が無いため `docs/translation-workflow.md` の同期対象外
  - その他: `README.md`・`CLAUDE.md`・`docs/workflow.md` は L3 の `session.md` の生成条件を扱わない (`grep -rn -e "docs/sessions" -e "session retrospective"` のヒットは `docs/structure.md` の概括・`CLAUDE.md` の言語規約表・`docs/tech.md` の audit 行など)。`tests/auto.bats` 以外に notable 判定の文言を検査するテストは無い (`grep -rn -i notable tests/` が `tests/auto.bats` のみ)

## Implementation Steps

1. `skills/auto/SKILL.md`: Changed Files 記載の箇条書き 1 行を置き換える。内容は英語のみ、CJK 文字を含めない (→ 受入条件 1, 2)。必須要素:
   - 条件名と閾値: `Implementation commit count for this session >= 3` (閾値 3 を維持。batch route のみ)
   - 対象: batch 対象 Issue の実装コミットだけを数え、`session_start` 以降の全コミットは数えない旨。対象 Issue は `BATCH_LIST` (Count mode は選ばれた Issue 群、Until mode は和集合の `ALL_TARGETS`。Batch Completion Report が走査するのと同じ集合)
   - 数える基準: (a) メッセージに `closes #N` を含むコミット (patch route の実装コミット。`/code` Step 11 が件名に `(closes #N)` を付ける)、(b) その Issue の PR のマージコミット (pr route。既定の squash では件名が PR タイトル `Issue #N: ... (#PR)` で、メッセージに `Issue #N:` で始まる行がある)。両方に一致するコミットは 1 件と数える
   - 数えないものと理由: Consumed Comments フォールバック (`Add consumed comments fallback for issue #M (verify phase)`) と Spec のフェーズ記録 (`Add design for issue #N`・`Add code retrospective for issue #N`・`Add merge phase handoff for issue #N` など)。理由は「件数が実行された `/verify` や phase の数に従って増え、batch の実装規模と無関係なので、数えると notable 判定が毎回真になる」(Issue #1533)
   - `commit_event`: 集計には残るが本条件では使わない旨 (events log が `commit` イベントを出さず常に 0)
   - 数え方のコマンド: Notes「挿入文案ドラフト」の `git rev-list --count` ブロック。リテラル値の差し替え方 (`session_start` と `BATCH_ISSUES_RE`) を併記する。ブロックはサブステップ内の 2 番目以降の ```` ```bash ```` ブロック (jq 集計ブロックより後) に置く
   - 判定ゲートの edge case (fail-safe。このコマンドは session.md を書くか否かを決めるゲートの一部のため明記する):
     - 空の入力: `session_start` か `BATCH_ISSUES_RE` が空なら git を実行せず 0 を返す。空の選択肢 `closes #()` は `closes #N` のように番号の無い文言を含むコミットに一致するため (全履歴で 5 件ヒットを実測、Notes「再現による検証」)
     - 特殊文字: Issue 番号は数字だけなので、`BATCH_ISSUES_RE` は数字と `|` だけで組み立てる (空白・末尾の `|`・引用符・`>`・改行・CRLF・マルチバイト文字を入れない)。正規表現は固定の ERE と数字の選択肢だけで、外部の文字列を正規表現として解釈させない
     - 番号の前方一致: `closes #(N)` の直後は非数字か行末 (`([^0-9]|$)`) を要求し、`#1` が `#10`・`#123` に一致しないようにする。`^Issue #(N):` はコロンで終端する
     - 依存コマンドの失敗: `git rev-list` が失敗したら `|| echo 0` で 0 とし、条件不成立 (not notable 側) に倒す。本条件は規模の目安で、他の 3 条件が事象 (recovery・FAIL・kill) の検知を担うため、ここでの失敗が L3 全体を止めてはならない。誤って not notable に倒れても `events.jsonl` は commit される
     - 大きな入力: 対象 Issue が多い場合 (Until mode の複数 round) は選択肢が長くなるだけで、コマンドは 1 回の `git rev-list` (`--since` で履歴の走査を打ち切る) のまま
   - 守ること: 半角 `!` を本文 (コードブロック・インラインコード・HTML コメント以外) に書かない、新しい見出しを作らない、`3. **Notable judgment**` と `4. **` の番号付き行を変えない、最初の ```` ```bash ```` ブロックを jq 集計のまま先頭に残す、frontmatter を変えない、em dash など非 ASCII を新たに足さない
2. `tests/auto.bats` (after 1): Changed Files 記載の位置に、ヘルパー 3 つとテスト 4 件を追加する (→ 受入条件 1, 2 の回帰保護)。入力は `skills/auto/SKILL.md` の実体と、`$BATS_TEST_TMPDIR` に作る git fixture (固定の committer date を持つ空コミット 12 件。形式は Notes「テスト入力の形式」)。数え方という新しい分岐を持つ手順なので、既存スイートが PASS することだけでなく、新規テストケース 4 件 (`tests/auto.bats` に `Notable judgment batch route counts only implementation commits of the target Issues (Issue #1533)`・`Notable judgment commit count counts implementation commits of the target Issues and excludes the rest (Issue #1533)`・`Notable judgment commit count scopes to the given target Issues only (Issue #1533)`・`Notable judgment commit count returns 0 for an empty target list or an empty session start (Issue #1533)`) を追加したうえでスイートが PASS すること。アサートは `[[ ... ]] || false` か `[ ... ]` で書き、`[[ ... ]]` を単独で置かない (`scripts/check-bare-bracket-assertions.sh`)
3. 自己検証 (after 2): 次をそれぞれ単一コマンドで実行する (worktree isolation guard が複合コマンドを拒否するため)。`bats tests/auto.bats`、`python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-allowed-tools.sh`、`git diff -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`、`bash scripts/check-forbidden-expressions.sh`、続けて `bats --jobs <N> tests/` (全スイート)。あわせて次を確認し、`## Code Retrospective` に記録する:
   - 新規テストが実装前に FAIL すること: `git show HEAD:skills/auto/SKILL.md` を `.tmp/` に書き出し (単独コマンド)、`notable_judgment_commit_count_command` と同じ awk を当てて block が見つからない (status 1) ことを確認する。本 Spec 作成時に現行の `skills/auto/SKILL.md` で status 1 を確認済み
   - 2 セッションの再現: Notes「再現による検証」の 2 コマンドが、どちらも 2 を返すこと
   - `git diff -- skills/auto/SKILL.md` の削除行が、置き換える箇条書き 1 行だけであること (jq 集計ブロックなど他の行を触っていない)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 5 の L3 auto-retrospective の notable 判定 (batch route) にあるコミット数の条件が、セッション中の全コミットではなく、batch 対象 Issue の実装コミット (closes #N を含むコミット、または PR のマージコミット) だけを数えるように書かれている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 5: Completion Report" "closes #" --> `skills/auto/SKILL.md` Step 5 の L3 notable 判定で、batch route のコミット数の条件が数える対象を、batch 対象 Issue の実装コミット (`closes #N` を含むコミット、または PR のマージコミット) に限定している
- <!-- verify: rubric "skills/auto/SKILL.md の同じ箇所に、Consumed Comments のフォールバックや Spec のフェーズ記録のコミットを数えない理由 (batch の実装規模と無関係に増え、notable 判定が毎回真になるため) が書かれている" --> Consumed Comments のフォールバックや Spec のフェーズ記録 (`Add design` / `Add code retrospective` / `Add merge phase handoff` など) のコミットを数えない理由が書かれている

### Post-merge

- 変更の反映後に始まった会話セッションで、recovery・FAIL・kill が 0 件の 2 件 batch を `/auto --batch` で流したとき、L3 notable 判定が notable にならない<!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - 端末に `L3 session events committed (not notable — session.md skipped).` が出力される
    - その session の `docs/sessions/<AUTO_SESSION_ID>-<date>/` に `events.jsonl` だけがあり、`session.md` がない
    - `Add L3 session data for session <AUTO_SESSION_ID>` のコミットが存在する
    - 該当する batch (recovery・FAIL・kill が 0 件で対象 Issue が 2 件以下) が実行されないうちは SKIPPED のままとする

## Notes

- **設計判断 (非対話モードでの自動解決): 実装コミットの特定は git のコミットメッセージ照合 2 パターンにする**。`git rev-list --count HEAD --since="$session_start" -E -i --grep='closes #(N1|N2)([^0-9]|$)' --grep='^Issue #(N1|N2):'`。複数の `--grep` は既定で OR (公式ドキュメント `git-rev-list` の `--grep`、実測でも 2 種類のコミットが同時に出る)。却下した案: (1) `events.jsonl` の phase 完了イベントで「実装が着地した Issue 数」を数える — 受入条件が「`closes #N` を含むコミット、または PR のマージコミット」を数えると定めており、コミットを数える定義から外れるため不可。(2) `gh pr list` で PR 番号から `mergeCommit` を引く — Issue ごとのネットワーク呼び出しが要り、判定に必要な情報は git の局所履歴で足りる。(3) コミット数の条件ごと外す — Issue 本文 Notes の「実装コミットが多い batch を振り返り対象にする意図は残す」に反する。(4) スクリプト化 (`scripts/` に新規ファイル) — Size S の範囲を超え (スクリプト・bats・`docs/structure.md`・`allowed-tools` の更新が連鎖する)、`tests/auto.bats` が SKILL.md に埋め込んだ jq コマンドを抽出して検証する既存の流儀で足りる。本文のコマンドをテストで直接実行するので、記述と検証が乖離しない
- **設計判断: 2 パターンの根拠 (実測)**。patch route の実装コミットは `/code` Step 11 が件名に `(closes #N)` を付けることを必須にしている (`skills/code/SKILL.md` の Step 11)。pr route は PR タイトルが `Issue #N: {summary}` (`skills/code/SKILL.md` の PR title format) で、`/merge` Step 4 は `gh pr merge "$NUMBER" $MERGE_FLAG --delete-branch` を subject 指定なしで呼ぶため、既定の squash の件名は PR タイトル + ` (#PR)` になる。squash コミットの本文は PR 内のコミットメッセージの連結で、`closes #N` を含まない (`d094ee7f`・`e97ecb07` で確認)。そのため pr route は `closes #N` では拾えず、PR のマージコミットを別パターンで拾う必要がある。この repo の全履歴で、`Issue #N:` で始まる行を持つコミットは 439 件、うち 438 件が件名の末尾に `(#PR)` を持つ squash マージコミット。残る 1 件 (`65988154`、`Issue #848: ...`) は PR を介さない単一親の直接コミットで、本文に `closes #848` は無いが、この 2 つ目のパターンなら実装コミットとして数えられる (スコープ: 全履歴、`git log -E --grep='^Issue #[0-9]+:'`、2026-10-16 時点)
- **再現による検証 (実測、2026-10-16、git 2.47.3)**。スコープ: 各セッションの L3 retrospective コミットの直前 (`c073306e^`・`3f1c0ef5^`) から `session_start` 以降。コマンド: `git rev-list --count <rev> --since=<session_start> -E -i --grep='closes #(N1|N2)([^0-9]|$)' --grep='^Issue #(N1|N2):'`
  - セッション `19747-1792075390` (対象 #1527・#1528、`session_start` 2026-10-15T14:43:23Z): 全コミット 10 件 (旧方式) → 2 件 (`e97ecb07` = #1527 の squash マージ、`5b487ab0` = #1528 の patch 実装)
  - セッション `647181-1792110450` (対象 #1531・#1530、`session_start` 2026-10-16T00:27:43Z): 全コミット 11 件 (旧方式) → 2 件 (`d094ee7f` = #1530 の squash マージ、`6fb0f718` = #1531 の patch 実装)
  - どちらも Issue 本文の表 (全コミット 10 / 11、うち Consumed Comments 各 5、実装 各 2) と一致し、閾値 3 を下回るので not notable になる
  - 空の選択肢の危険: `closes #(1531|)([^0-9]|$)` は全履歴で 6 件に一致する (#1531 の実装コミット 1 件と、`closes #N` のように `closes #` の直後が数字でない文言を含むコミット 5 件: `994bd2b3`・`5f95d482`・`8bed3cca`・`a10c7f68`・`6ea8fced`。`5f95d482` は別 Issue (#1202) の実装コミットでもある)。番号の前方一致: `closes #(153)([^0-9]|$)` は `closes #1531` に一致しない (0 件)
  - fixture での挙動 (実測): 対象 `1|2` で 5 件、対象 `2` だけで 2 件、対象 `1` だけで 3 件、全コミットの旧方式は 11 件 (期間外の 1 件を除く)
- **設計判断: 起点は `HEAD`、`--since` は置き換え前と同じ**。置き換え前のフォールバック (`git log --oneline --since="$session_start"`) と同じ起点を維持し、「何を数えるか」だけを変える。`--since` は走査を最初の古いコミットで打ち切る (公式ドキュメントの `--since-as-filter` の説明「rather than stopping at the first commit which is older than ⟨date⟩」から読み取れ、committer date が単調でない fixture で 0 件になることも実測した)。main の履歴は通常単調だが、時計のずれ・rebase 後のコミットで崩れうる。公式ドキュメントには全コミットに日付フィルタを適用する `--since-as-filter` があるが、古い git での可用性が確認できず、全履歴の走査コストもあるので採らない。テストの fixture は古い順に作り、期間外のコミットを最古に置く
- **既知の限界 (いずれも過小評価、つまり not notable 側に倒れる。他の 3 条件には影響しない)**: (1) `rebase` 戦略は PR のマージコミットが存在せず、pr route の実装コミットは `closes #N` を持たない (Step 11 の必須は patch route) ので数えられない。`squash` (既定) と `merge` は数えられる。`merge` の GitHub 既定のマージコミットは本文に PR タイトルを持つと理解しているが、この repo では使っておらず実測していない (fixture では `Merge pull request #78` + 本文 `Issue #1: ...` の本文行マッチまでを検証する)。(2) squash の既定メッセージ設定によっては、PR のコミットが 1 件だけだと件名が PR タイトルでなくコミットの件名になり得る。pr route は実装コミットの後に Code Retrospective コミットを積むので、通常は 2 件以上ある。(3) 親セッションのローカル `main` が origin より遅れていると PR のマージコミットが `HEAD` から見えない。置き換え前と同じ起点で、L3 の `git push origin main` も同期済みの `main` を前提とするため、fetch は足さない (sub-step 8 の Skill Self-Update Propagation check は `git fetch origin` + `origin/${BASE_BRANCH}` を使う前例だが、本 Issue は「何を数えるか」に範囲を限る)。(4) 同じ Issue の修正サイクル (verify FAIL → `/code` 再実行) の実装コミットは追加で数える。実装規模の一部なので意図どおり
- **設計判断: `commit_event` は jq 集計に残す**。`tests/auto.bats` が 4 フィールドの形を固定している (3 テスト)。#913 は集計の 4 フィールドを既存の判定条件に 1:1 対応させ、`commit` イベントが emit されないため `commit_event` は常に 0 で `git log` フォールバックだけが実判定だったと記録している。本 Issue はその実判定の数え方を変えるだけで、`commit_event` の除去は範囲外 (別の整理)。本文では「`commit_event` は本条件で使わない」と明記し、将来 `commit` イベントが全コミットを数える形で emit されても同じ欠陥が戻らないようにする
- **`section_contains` の走査範囲 (`modules/verify-patterns.md` § 29 の pattern 4)**: AC1 の `section_contains "skills/auto/SKILL.md" "Step 5: Completion Report" "closes #"` は、見出し `### Step 5: Completion Report` (699 行、部分一致で解決) から次の同レベル以上の見出し (`### Step 6: On Failure: 3-Tier Recovery`、955 行) の直前までを走査する。L3 auto-retrospective は 794〜954 行でこの区間に入っており、区間内に h3 以上の見出しは無い。実装は見出しを足さず、箇条書きの置き換えに留める (新設すると走査範囲が途切れて AC が FAIL か UNCERTAIN になる)。文字列の存在確認: `closes #` は現状 Step 5 の区間に 0 件 (`sed -n 699,954p skills/auto/SKILL.md | grep -c "closes #"` = 0) で、置き換え後の本文が導入する。AC1 の rubric は文言の揺れに対して、この `section_contains` が配置の安全網になる
- **テスト入力の形式 (bats)**: 入力は (a) `skills/auto/SKILL.md` の実体 (`SKILL_FILE`)、(b) `$BATS_TEST_TMPDIR` に `git init` した空コミット 12 件の fixture。コミットは古い順に作り、committer date を `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` で固定する (現在日時に依存させない。`git rev-list --since` は最初の古いコミットで走査を止めるので、期間外のコミットを最古にする)。対象 Issue は #1 と #2。コマンドの抽出は、`notable_judgment_section` の範囲から ```` ```bash ```` ブロックを順に読み、`rev-list --count` を含むものを返す awk (先頭ブロックは jq 集計なので位置でなく内容で選ぶ。合成ドキュメントと現行の `skills/auto/SKILL.md` で動作確認済み: 前者は block を返し、後者は status 1)。変数は `run env session_start=... BATCH_ISSUES_RE=... bash -c "$cmd"` で渡し、fixture のディレクトリへ `cd` してから実行する。fixture の内容と期待値:

  | committer date | 件名 (本文) | 対象 `1\|2` で数えるか |
  |---|---|---|
  | 2026-01-01T00:00:00Z | `chore: old work before the session (closes #1)` | 数えない (`--since` より前) |
  | 2026-01-02T00:00:01Z | `Add design for issue #1` | 数えない (Spec のフェーズ記録) |
  | 2026-01-02T00:00:02Z | `chore: do the thing (closes #1)` | 数える (patch 実装) |
  | 2026-01-02T00:00:03Z | `Add code retrospective for issue #1` | 数えない |
  | 2026-01-02T00:00:04Z | `Issue #2: Do other thing (#77)` (本文 `* feat: x (#2)`) | 数える (squash マージ) |
  | 2026-01-02T00:00:05Z | `Add merge phase handoff for issue #2` | 数えない |
  | 2026-01-02T00:00:06Z | `Add consumed comments fallback for issue #200 (verify phase)` | 数えない (Consumed Comments) |
  | 2026-01-02T00:00:07Z | `fix: unrelated prefix traps (closes #10)` (本文 `closes #20 and closes #123`) | 数えない (番号の前方一致) |
  | 2026-01-02T00:00:08Z | `docs: explain closes #N magic` (本文 `Explains the closes keyword.`) | 数えない (文言だけの言及) |
  | 2026-01-02T00:00:09Z | `Merge pull request #78 from o/branch` (本文 `Issue #1: Do thing via merge commit`) | 数える (merge 戦略の本文行) |
  | 2026-01-02T00:00:10Z | `feat: uppercase keyword in body` (本文 `Closes #2`) | 数える (大文字小文字不問) |
  | 2026-01-02T00:00:11Z | `Issue #1: both patterns at once (closes #1)` | 数える (両パターン一致でも 1 件) |

  期待値: 対象 `1|2` は 5、対象 `2` は 2 (`closes #20` が `#2` に一致しないことの対照)、対象 `1` は 3、`session_start` を `2026-01-02T00:00:00Z` にした全コミットの旧方式は 11 (新方式より大きい)。空の `BATCH_ISSUES_RE`・空の `session_start` は 0 (対照: ガード無しの空の選択肢 `closes #()` は 1 件以上に一致する)
- **新規テストの要件 (light のため Notes に記録)**: 数え方という新しい分岐を持つため、既存スイートの PASS だけでなく新規ケース 4 件の追加を求める。文言の回帰保護 (1 件) は、`closes #N`・`BATCH_LIST`・`rev-list --count`・3 種類のコミットメッセージの文字列・旧フォールバック `git log --oneline --since="$session_start"` の不在を固定文字列で検査する。実装前 FAIL の確認 (2026-10-16 実測): 現行の `skills/auto/SKILL.md` では、抽出 awk が block を返さず status 1 になる (ヘルパー経由の 3 テストは `|| false` で FAIL し、文言テストは `rev-list --count` が 0 件で FAIL する)
- **`premise` マーカーの失効は意図どおり**: Issue 本文 Background の `<!-- premise: grep_count "Commit count for this session" "skills/auto/SKILL.md" -eq 1 -->` は、置き換え後に 0 件になって失効する。実装が着地した Issue (`phase/verify`・`phase/done`) は `/audit premise` の対象から外れる (#1530 の `scripts/filter-premise-targets.sh`) ので、問題にならない。`Commit count for this session` の文言は残さない
- **Self-hosting と Post-merge**: wholework は自分自身を使うため、`skills/auto/SKILL.md` の変更は、変更が base に入った後に始まった会話セッションで読み込まれてはじめて有効になる (`modules/verify-classifier.md` § observation Type: Event Values and Syntax の `session=next` の説明)。Post-merge の条件は Issue 本文のとおり `observation` (`event=auto-run session=next`)。`auto-run` は同モジュールのイベント語彙表にあり、語彙の照合に問題はない。「観測したいイベント」と「期待する出力の構造」を分けるため、Spec 側では Option A (入れ子の `Expected output structure:`) の形に整えた。Issue 本文の文言と意味は変えていない
- **制約への適合 (`skills/spec/skill-dev-constraints.md` を light でも確認した)**: (1) 追記は英語のみで CJK 文字を含めない (CI の `language-convention` が `git diff -- skills/ modules/ scripts/` の追加行を検査)。(2) `docs/product.md` § Terms の旧称にある非推奨用語を使わない (CI の `check-forbidden-expressions` が `skills/ modules/ agents/ tests/ docs/ scripts/` を走査し、この Spec 自身も対象)。(3) SKILL.md 本文に半角 `!` を書かない・小数のステップ番号を作らない (`validate-skill-syntax.py`)。(4) 新しい見出しを作らない。(5) `${CLAUDE_PLUGIN_ROOT}/scripts/` の新規参照を足さないので frontmatter の `allowed-tools` は変えない (allowed-tools 連鎖は Case 1・Case 2 とも対象外: 新規 `scripts/*.sh` も `modules/*.md` の変更も無い)。(6) 「exhaustive」等の網羅の断定を書かないので、網羅性の機械的検証の追加ステップは不要
- **Issue 本文と実装の照合 (矛盾検出)**: Background の主張 — 条件が `git log --oneline --since="$session_start"` の行数で代用されていること (`skills/auto/SKILL.md` 829 行)、Consumed Comments フォールバックと Spec のフェーズ記録が積まれること (`scripts/append-consumed-comments-section.sh`・`skills/code/SKILL.md`・`skills/merge/SKILL.md`・`skills/spec/SKILL.md` に該当のコミットメッセージが実在)、2 セッションの数値 (上記の再現で一致) — はいずれも実装と一致し、矛盾は無い。「XL route の条件にコミット数は無い」(Auto-Resolved Ambiguity Points) も、`skills/auto/SKILL.md` 831〜834 行の XL route の 3 条件で確認した
- **audit/investigation-type の判定**: no (既存の判定条件の数え方を直す変更で、既存項目を分類した結果を後続処理が根拠として読む監査・調査の Issue ではない)。fail-safe critical: 該当 (notable 判定は session.md を書くか否かを決めるゲートの一部)。edge case は Implementation Steps 1 に列挙した。外部仕様依存: `git rev-list` の `--grep` (複数指定は OR)・`-i`・`-E`・`--since`・`--count` を公式ドキュメント (https://git-scm.com/docs/git-rev-list、2026-10-16 取得) と実測で確認した。tool 検出・新規依存パッケージ・adapter 追加: いずれもなし。Costly / irreversible なステップ: なし。external-auth-required: なし
- **Size**: Changed Files は 2 件 (Axis 1 = S)。Axis 2 の補正要因は無い (複数 skill にまたがらず、新しい architecture pattern でもない)。CI Dependency Minimum Override の対象外 (CI workflow・テストの並列化フラグ・共有 fixture の変更なし。新規 fixture は各テストの `$BATS_TEST_TMPDIR` に閉じる)。triage 時点の S のまま patch route (`ALWAYS_PR=false`、`.wholework.yml` に `always-pr` なし)。Pre-merge に `github_check "gh pr checks"` は無く、route に応じた書き換えは不要
- **コメント消費**: cutoff は直近の `phase/issue` ラベル付与 (2026-10-16T06:05:49Z)。cutoff 以降の 1 件 (Issue Retrospective) は first-class で、内容は Issue 本文の最新版 (AC1 への `section_contains` の併記、Post-merge の証拠と SKIPPED の条件、Background の `premise` マーカー) に反映済み。クロスフェーズのマーカー (`verify-fail` / `preview-ac-unverified`) は無い
- **先行事例**: #913 (jq 集計と `commit_event` を判定条件に 1:1 対応させた設計と、`commit` イベントが emit されない記録)、#1517 (`notable_judgment_section` ヘルパーと `|| false` の流儀)、#1206 (`tests/auto.bats` の実 git を使う fixture)、#1531 (S サイズの Spec の書式と挿入文案ドラフトの書き方)
- **挿入文案ドラフト** (`/code` は趣旨と必須要素を保てば文言を調整してよい。ただしテストが固定文字列で検査する `closes #N`・`BATCH_LIST`・`rev-list --count`・`Add consumed comments fallback for issue`・`Add code retrospective for issue`・`Add merge phase handoff for issue` を変える場合は、テストの文字列も同じ文言に揃える。英語のみで CJK 文字を含めない):

  `skills/auto/SKILL.md` の batch route の箇条書き (現状 829 行の 1 行) を置き換える。インデントは、箇条書きが 5 スペース、その入れ子が 7 スペース、コードブロックが 9 スペース:

  ````markdown
       - Implementation commit count for this session >= 3. Count only the implementation commits of this batch's target Issues, not every commit made since `session_start`:
         - Target Issues: each Issue number N in `BATCH_LIST` (in Count mode, the Issues selected for this run; in Until mode, the union `ALL_TARGETS`), the same set the Batch Completion Report iterates over.
         - Counted: a commit whose message contains `closes #N` (the patch route implementation commit; `/code` Step 11 puts `(closes #N)` in its subject), and the merge commit of the Issue's PR (pr route; under the default squash strategy its subject is the PR title `Issue #N: ... (#PR)`, so the message has a line starting with `Issue #N:`). A commit matching both is counted once.
         - Not counted: the Consumed Comments fallback commits (`Add consumed comments fallback for issue #M (verify phase)`, one per `/verify` run, observation-dispatched runs included) and the Spec phase-record commits (`Add design for issue #N`, `Add code retrospective for issue #N`, `Add merge phase handoff for issue #N`, and similar). Their number follows how many `/verify` runs and phases were executed, not how much the batch implemented, so counting them made this condition true for every batch (Issue #1533).
         - `commit_event` from the summary above is not used here: the events log does not currently emit `commit` events, so it stays at `0`. Count with git instead, after substituting the literal values (each Bash call is a fresh shell): `session_start` is the value recorded in `.tmp/auto-session-${AUTO_SESSION_ID}.json`, and `BATCH_ISSUES_RE` is the Issue numbers of `BATCH_LIST` joined with `|` (for example `1530|1531`; digits and `|` only, no spaces, no trailing `|`):
           ```bash
           if [ -n "$session_start" ] && [ -n "$BATCH_ISSUES_RE" ]; then
             git rev-list --count HEAD --since="$session_start" -E -i \
               --grep="closes #(${BATCH_ISSUES_RE})([^0-9]|$)" \
               --grep="^Issue #(${BATCH_ISSUES_RE}):" 2>/dev/null || echo 0
           else
             echo 0
           fi
           ```
           If either value is unavailable or `git` fails, the result is `0` and this condition is not met. Never run the command with an empty `BATCH_ISSUES_RE`: the empty pattern `closes #()` matches any commit that merely mentions `closes #` in prose. The other notable conditions still apply.
  ````

  `tests/auto.bats` に追加するヘルパーとテスト (既存の `notable_judgment_section` と `SKILL_FILE` を使う):

  ```bash
  # Tests for the batch route implementation-commit count in the Notable judgment sub-step (Issue #1533).
  # The count must cover only the implementation commits of the batch target Issues, not every commit of the session.

  # Extract the commit-count command embedded in the Notable judgment sub-step: the fenced bash block
  # that contains "rev-list --count". The first bash block of the sub-step is the jq aggregation, so the
  # block is selected by content, not by position. Exits 1 when the sub-step or the block is missing.
  notable_judgment_commit_count_command() {
      local section
      section="$(notable_judgment_section "$1")" || return
      printf '%s\n' "$section" | awk '
          /```bash/ { inblk = 1; blk = ""; next }
          inblk && /```/ { inblk = 0; if (blk ~ /rev-list --count/) { printf "%s", blk; found = 1; exit } next }
          inblk { blk = blk $0 "\n" }
          END { if (!found) exit 1 }
      '
  }

  # Create one empty commit with a fixed committer date: batch_session_commit REPO DATE SUBJECT [BODY].
  batch_session_commit() {
      local repo="$1" date="$2" subject="$3" body="${4:-}"
      if [ -n "$body" ]; then
          GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
              git -C "$repo" commit -q --allow-empty -m "$subject" -m "$body"
      else
          GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
              git -C "$repo" commit -q --allow-empty -m "$subject"
      fi
  }

  # Build a repo whose history mimics one /auto batch session with target Issues #1 and #2.
  # Commits are created oldest first with increasing dates: `git rev-list --since` stops walking at the
  # first commit older than the cutoff, so the out-of-window commit has to be the oldest one.
  batch_session_repo() {
      local repo="$1"
      git init -q "$repo"
      git -C "$repo" config user.email "test@example.com"
      git -C "$repo" config user.name "Test"
      git -C "$repo" config commit.gpgsign false
      batch_session_commit "$repo" "2026-01-01T00:00:00Z" "chore: old work before the session (closes #1)"
      batch_session_commit "$repo" "2026-01-02T00:00:01Z" "Add design for issue #1"
      batch_session_commit "$repo" "2026-01-02T00:00:02Z" "chore: do the thing (closes #1)"
      batch_session_commit "$repo" "2026-01-02T00:00:03Z" "Add code retrospective for issue #1"
      batch_session_commit "$repo" "2026-01-02T00:00:04Z" "Issue #2: Do other thing (#77)" "* feat: x (#2)"
      batch_session_commit "$repo" "2026-01-02T00:00:05Z" "Add merge phase handoff for issue #2"
      batch_session_commit "$repo" "2026-01-02T00:00:06Z" "Add consumed comments fallback for issue #200 (verify phase)"
      batch_session_commit "$repo" "2026-01-02T00:00:07Z" "fix: unrelated prefix traps (closes #10)" "closes #20 and closes #123"
      batch_session_commit "$repo" "2026-01-02T00:00:08Z" "docs: explain closes #N magic" "Explains the closes keyword."
      batch_session_commit "$repo" "2026-01-02T00:00:09Z" "Merge pull request #78 from o/branch" "Issue #1: Do thing via merge commit"
      batch_session_commit "$repo" "2026-01-02T00:00:10Z" "feat: uppercase keyword in body" "Closes #2"
      batch_session_commit "$repo" "2026-01-02T00:00:11Z" "Issue #1: both patterns at once (closes #1)"
  }

  @test "Notable judgment batch route counts only implementation commits of the target Issues (Issue #1533)" {
      # Plain assignment (not run) so a missing sub-step fails the test (Issue #1517)
      section="$(notable_judgment_section "$SKILL_FILE")"
      [[ "$section" == *'closes #N'* ]] || false
      [[ "$section" == *'BATCH_LIST'* ]] || false
      [[ "$section" == *'rev-list --count'* ]] || false
      [[ "$section" == *'Add consumed comments fallback for issue'* ]] || false
      [[ "$section" == *'Add code retrospective for issue'* ]] || false
      [[ "$section" == *'Add merge phase handoff for issue'* ]] || false
      # The fallback that counted every commit since the session start must be gone
      [[ "$section" != *'git log --oneline --since="$session_start"'* ]] || false
  }

  @test "Notable judgment commit count counts implementation commits of the target Issues and excludes the rest (Issue #1533)" {
      local repo="$BATS_TEST_TMPDIR/batch-session"
      batch_session_repo "$repo"
      local cmd
      cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

      cd "$repo"
      run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="1|2" bash -c "$cmd"
      [ "$status" -eq 0 ]
      # Counted: patch implementation (closes #1), squash merge (Issue #2:), merge-commit body line (Issue #1:),
      # uppercase "Closes #2" in a body, and a commit matching both patterns (counted once) = 5.
      # Excluded: the out-of-window commit, Spec phase records, a Consumed Comments fallback, prefix traps
      # (closes #10 / #20 / #123) and a prose mention of "closes #N".
      [ "$output" = "5" ]

      # Control: the old whole-session count over the same history is larger, so the fixture does hold
      # mechanical commits that the new count has to exclude.
      local whole
      whole="$(git rev-list --count HEAD --since="2026-01-02T00:00:00Z")"
      [ "$whole" -gt "$output" ]
  }

  @test "Notable judgment commit count scopes to the given target Issues only (Issue #1533)" {
      local repo="$BATS_TEST_TMPDIR/batch-session"
      batch_session_repo "$repo"
      local cmd
      cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

      cd "$repo"
      # Issue #2 only: the squash merge and the uppercase "Closes #2"; "closes #20" must not match #2.
      run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="2" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = "2" ]
      # Issue #1 only: the patch implementation, the merge-commit body line and the both-patterns commit.
      run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="1" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = "3" ]
  }

  @test "Notable judgment commit count returns 0 for an empty target list or an empty session start (Issue #1533)" {
      local repo="$BATS_TEST_TMPDIR/batch-session"
      batch_session_repo "$repo"
      local cmd
      cmd="$(notable_judgment_commit_count_command "$SKILL_FILE")" || false

      cd "$repo"
      run env session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = "0" ]
      run env session_start="" BATCH_ISSUES_RE="1|2" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = "0" ]

      # Control: without the guard, the empty alternation would count the commit that only mentions "closes #N" in prose.
      local unguarded
      unguarded="$(git rev-list --count HEAD --since="2026-01-02T00:00:00Z" -E -i --grep='closes #()([^0-9]|$)')"
      [ "$unguarded" -ge 1 ]
  }
  ```

## Code Retrospective

### Deviations from Design
- なし。挿入文案ドラフトとテストの雛形をそのまま採用した

### Design Gaps/Ambiguities
- なし。Spec の Notes に edge case と fixture の期待値が揃っており、実装中に追加の曖昧点は出なかった

### Rework
- なし

### Verification Record
- Confirmed pre-implementation FAIL for 4 new test(s): 実装前の `skills/auto/SKILL.md` (`git show HEAD:...`) の Notable judgment 区間に `rev-list --count` が 0 件で、抽出 awk が block を返さない (ヘルパー経由の 3 テストは `|| false` で FAIL、文言テストは `rev-list --count` の検査で FAIL)
- 2 セッションの再現: `c073306e^` 起点 (対象 #1527・#1528) と `3f1c0ef5^` 起点 (対象 #1531・#1530) のどちらも 2 件を返し、閾値 3 を下回る
- `git diff -- skills/auto/SKILL.md` の削除行は置き換えた箇条書き 1 行だけ
- `bats tests/auto.bats` と全スイート (`bats --jobs 4 tests/`、2247 件) が PASS。`validate-skill-syntax.py`・`check-allowed-tools.sh`・`check-language-convention.py`・`check-forbidden-expressions.sh` はエラーなし。`check-bare-bracket-assertions.sh` は既存の警告のみで追加行に該当なし
- Pre-merge の 2 条件は `section_contains` (`closes #` が 3 件ヒット) と実装の文言確認で PASS として Issue のチェックを更新した

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の挿入文案ドラフトをそのまま `skills/auto/SKILL.md` の batch route 箇条書きへ置き換え、数え方は `git rev-list --count` の 1 コマンド (2 パターンの `--grep` の OR) にした
- 空入力と git 失敗は 0 に倒す fail-safe を本文とテストの両方に入れた (空の選択肢 `closes #()` が散文の言及に一致するため)

### Deferred Items
- Post-merge の observation 条件 (recovery・FAIL・kill が 0 件の 2 件 batch で not notable になること) は、変更反映後の会話セッションで該当する batch が走るまで SKIPPED のまま

### Notes for Next Phase
- `/verify` は Pre-merge 2 条件が既に `[x]` であることを前提に、Post-merge の observation 条件だけを扱う
- Self-hosting のため、変更は反映後に始まった会話セッションで読み込まれてはじめて有効になる

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective: 前フェーズ (/issue) の自動解決ログ。実装コミットの特定方法を /spec の責務としたこと、閾値 3 の維持、XL route を対象外としたこと、AC1 への section_contains の併記、Post-merge の observation 条件への PASS の証拠と SKIPPED の条件の明記、Background への premise マーカーの付与 / https://github.com/saitoco/wholework/issues/1533#issuecomment-6209250218
