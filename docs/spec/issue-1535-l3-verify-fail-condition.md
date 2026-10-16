# Issue #1535: auto: L3 notable 判定の Verify FAIL 条件を実際に FAIL した Issue に絞る

## Overview

`skills/auto/SKILL.md` Step 5 の L3 auto-retrospective は、batch route の notable 判定の 1 条件として「Verify FAIL (batch 終了時に `phase/verify` ラベルを持つ Issue に未チェックの `- [ ]` が残る)」を持つ。しかし本物の verify FAIL は `/verify` Step 11 (b) が `phase/*` ラベルを外して Issue を reopen するので、FAIL した Issue に `phase/verify` は (上限到達の最後の FAIL を除いて) 残らない。`phase/verify` と未チェックの `- [ ]` が残るのは、Step 11 (a) が observation / opportunistic / manual 条件の発火や確認を待っている状態で、FAIL ではない。つまりこの条件は FAIL ではなく「待機」を拾っており、`phase/verify` の 302 件中 291 件で Post-merge に未チェックが残っている (Notes「実測」)。そのため recovery・FAIL・kill が 0 件の batch でも、対象 Issue がたいてい `phase/verify` のまま終わって毎回 notable になる。

batch route の「Verify FAIL」を、batch 対象 Issue (`BATCH_LIST`) のうち次のどちらかに当たる Issue が 1 件以上あるときに限る。

- マーカー: この session 中 (`createdAt` が `session_start` 以降) に、コメントの 1 行目が `<!-- wholework-event: type=verify-fail` で始まるマーカーが投稿された
- 未解決の auto 条件: `phase/verify` ラベルが残り、verify command 付きで observation / opportunistic / manual のタグを持たない未チェックの `- [ ]` が残る (`/verify` が UNCERTAIN や PENDING で止めた条件で、マーカーを持たない)

observation / opportunistic / manual 条件を待つだけで `phase/verify` に残る Issue は、この条件に当たらない。理由 (本物の FAIL は `phase/*` ラベルを外して reopen する) は SKILL.md に書く。閾値と他の 3 条件 (Tier 2/3 recovery・実装コミット数・Watchdog kill)、XL route の条件は変えない。Issue 本文の「Auto-Resolved Ambiguity Points」は、未チェックの auto 条件を数えるコマンドと「この session 中」の取得方法を `/spec` の責務とした。この Spec が選んだ方法と却下した案は Notes「設計判断」に記録する。

1. `skills/auto/SKILL.md`: 旧条件の 1 行を、対象・2 つの分岐・数えないものとその理由・判定コマンドを入れ子で述べた 1 項目に置き換える。判定は Issue ごとの `gh issue view --json labels,body,comments` 1 回で、マーカーは jq、未チェックの auto 条件は awk で数える。取得に失敗した Issue・数字でない入力・空の `session_start` は、いずれも条件不成立 (not notable 側) に倒す
2. `tests/auto.bats`: 判定コマンドを SKILL.md から抜き出し、モックの `gh` と fixture で実行するテストと、文言の回帰保護テストを足す

## Changed Files

- `skills/auto/SKILL.md`:
  - Step 5 の L3 auto-retrospective の `3. **Notable judgment**` サブステップ内、batch route の箇条書き `` - Verify FAIL (any Issue label `phase/verify` with unchecked `- [ ]` at batch end) `` (現状 828 行、5 スペースインデントの 1 行) を置き換える。置き換え後は同じ位置に、入れ子の箇条書き (分岐・数えないもの・判定コマンド) と ```` ```bash ```` ブロックを持つ 1 項目になる。内容は Implementation Steps 1 と Notes「挿入文案ドラフト」
  - 変更しない: 最初の ```` ```bash ```` ブロック (jq 集計。`tests/auto.bats` が先頭ブロックを抽出する)、`commit_event` を含む jq 集計の 4 フィールド、他の batch 条件 (Tier 2/3 recovery・実装コミット数・Watchdog kill)、XL route の条件、`3. **Notable judgment**` と `4. **Fetch the Metrics section**` の番号付き行 (テストが範囲の開始と終了に使う)、frontmatter の `allowed-tools` (新規の `${CLAUDE_PLUGIN_ROOT}/scripts/` 参照を足さない。`gh issue view:*` は元から許可されている。`jq` と `awk` は `scripts/validate-skill-syntax.py` の allowed-tools 検査の対象外で、`jq` は同じサブステップが元から使っている)
  - Step 5 の区間 (現状 699〜968 行) に h3 以上の見出しを新設しない (AC1 の `section_contains` が `### Step 5: Completion Report` を起点に次の h3 以上の見出し (`### Step 6: On Failure: 3-Tier Recovery`、969 行) までを走査するため。Notes「`section_contains` の走査範囲」)。コードブロックの先頭に `#` で始まる行 (bash のコメント) も置かない (見出しと誤認する走査を避ける)
  - `skill-body-lines` / `skill-body-sha` マーカーは `skills/auto/SKILL.md` に無く、再計算は不要 (`grep -c "skill-body-" skills/auto/SKILL.md` が 0)
  - bash 3.2+ / zsh 互換: ブロックは `printf`・`tr`・`while read`・`case`・`$(...)`・`jq`・`awk` だけで書き、配列・`mapfile`・`[[ ]]`・`${var,,}`・未クオートの変数による単語分割 (zsh は分割しない) に頼らない。この session の Bash ツールのシェルは zsh だった (`ps -o comm= -p $$` が `zsh`、2026-10-16)
- `tests/auto.bats`: 既存の Notable judgment テスト群の末尾 (`Notable judgment commit count returns 0 for an empty target list or an empty session start (Issue #1533)` の直後・`# Tests for Skill Self-Update Propagation check comparing against origin (Issue #1206)` コメントの直前) に、ヘルパー 4 つ (`notable_judgment_verify_fail_command`・`verify_fail_mock_gh`・`verify_fail_fixture`・`verify_fail_marker_comment`) とテスト 5 件を追加する (Implementation Steps 2)。既存のテスト・ヘルパーは変更しない
- [Steering Docs sync candidate] `modules/verify-classifier.md`: `### Tag Extraction Rule (consumers)` の `**Consumers (exhaustive):**` 表の `skills/auto/SKILL.md` の行 (現状 247 行、`verify-type: manual` / `observation` / `opportunistic` + `ac-tier: preview` exclusion (Pending manual confirmation aggregation)) は、今回 `skills/auto/SKILL.md` が同じ 3 つのタグ (閉じタグまで) と `verify:` command の有無も読むようになるため、その読み取りを 1 句足す候補。最終的な採否は `/code` が行を読んで決める (Implementation Steps 3)。採る場合も変更ファイルは 3 件目の 1 行の文書編集で、Size は S のまま
- 以下は Steering Docs sync candidate 確認の記録 (件数はすべて `docs/ tests/ scripts/ modules/` を対象にした `grep -rl -F` の結果で、`docs/spec/`・`docs/sessions/`・`docs/reports/` を含む。2026-10-16 実測):
  - [Steering Docs sync candidate] keyword "notable" skipped: matched 53 files (no discriminating power)。参考として履歴 (`docs/spec/`・`docs/sessions/`・`docs/reports/`) を除く非履歴ヒットを読んだ (`grep -rln -i notable docs README.md README.ja.md CLAUDE.md skills modules scripts agents tests`)。`docs/structure.md` と `docs/ja/structure.md` は「L3 session retrospectives ... notable batch/XL only」と概括するだけで条件を述べない。`docs/tech.md` と `docs/ja/tech.md` は #913 の経緯の記録。`modules/run-fact-matching.md` は reconcile の schema に notable 判定結果が無い理由の説明。`skills/audit/SKILL.md` は not-notable セッションに `session.md` が無いことの説明。`skills/verify/SKILL.md` と `skills/issue/SKILL.md` は別の規則 (`retrospective skipped: no notable content`)。いずれも更新不要
  - [Steering Docs sync candidate] keyword "verify-fail" skipped: matched 49 files、keyword "type=verify-fail" skipped: matched 36 files、keyword "BATCH_LIST" skipped: matched 19 files (いずれも no discriminating power)。非履歴の `type=verify-fail` ヒット (`docs/workflow.md`・`modules/observation-trigger.md`・`modules/l0-surfaces.md`・`skills/auto/SKILL.md` Step 2a・`skills/verify/SKILL.md`・`scripts/append-consumed-comments-section.sh`) を読んだ。マーカーの書式と投稿を述べるだけで、読み手の一覧は無い。今回の読み手 (L3 notable 判定) を足す箇所は無く、更新不要
  - keyword "Verify FAIL": 6 件。すべて履歴で、内訳は `docs/reports/` 1 件、`docs/spec/` 3 件 (#694、#913、#1533)、`docs/sessions/` 2 件 (この Issue の元になった記録) である。旧条件の文言 (`at batch end`) は、履歴以外では `skills/auto/SKILL.md` の 1 か所だけに出現する (`grep -rn "at batch end" README.md CLAUDE.md docs skills modules scripts agents tests` の履歴以外のヒット)
  - keyword "Notable judgment": 7 件。`tests/auto.bats` (Changed Files に含む) と履歴 6 件。keyword "ALL_TARGETS": 3 件。すべて履歴の `docs/spec/` で追加候補なし
  - `tests/auto.bats` 以外に notable 判定の文言を検査するテストは無い (`grep -n -i "notable\|L3\|batch end\|verify-fail\|Verify FAIL"` を `skills/auto/SKILL.md` を参照する他の 7 テスト (`tests/auto-batch.bats`・`auto-xl-concurrency.bats`・`ci-failure-classifier.bats`・`check-skill-change-observation-ac.bats`・`operate-route.bats`・`run-auto-sub.bats`・`auto-completion-report.bats`) に当てて 0 件)。全スイートの実行は Implementation Steps 4 に入れた
  - [Steering Docs sync candidate] Listing-side sub-check: 発火せず。サブコマンドの追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし
  - [Outbound pointer sync candidate] 置き換える箇条書きが指す `modules/l0-surfaces.md` § AC Enumeration Convention と `modules/verify-classifier.md` § Tag Extraction Rule のうち、前者は変更不要 (fence 除外の規則を参照するだけ)、後者は上の consumers 表の候補として扱う
  - `docs/ja/` 同期: Changed Files に `docs/` 直下の `.md` が無いため `docs/translation-workflow.md` の同期対象外
  - allowed-tools 連鎖: 新規の `scripts/*.sh` も、`scripts/*.sh` の参照を足す `modules/*.md` の変更も無いため対象外 (Case 1・Case 2 とも該当なし)

## Implementation Steps

1. `skills/auto/SKILL.md`: Changed Files 記載の箇条書き 1 行を置き換える。内容は英語のみで、CJK 文字を含めない (→ 受入条件 1, 2)。必須要素:
   - 条件名と対象: `Verify FAIL` を維持し、対象は `BATCH_LIST` (Count mode は選ばれた Issue 群、Until mode は和集合の `ALL_TARGETS`。実装コミット数の条件と同じ集合)。bare な `phase/verify` ラベル判定を使わない旨と理由 (そのラベルは Step 11 (a) の待機でも付く。`session=next` の observation 条件は後続の session が発火するまで Issue をそこに留める)
   - 本物の FAIL の経路: `/verify` Step 11 (b) が `type=verify-fail` マーカーを投稿し、`phase/*` ラベルを外し、CLOSED の Issue を reopen する。上限到達の最後の FAIL (`MAX_ITERATIONS_REACHED`) だけが `phase/verify` を残し、マーカーは投稿する
   - 分岐 1 (マーカー): この session 中に `type=verify-fail` マーカーが投稿された。コメントの 1 行目が `<!-- wholework-event: type=verify-fail` で始まり、`createdAt` が `session_start` 以降。本文の途中でマーカーを引用しただけのコメントは数えない
   - 分岐 2 (未解決の auto 条件): `phase/verify` ラベルが残り、コードフェンス外の未チェックの `- [ ]` 行のうち `<!-- verify:` command を持ち、`verify-type: manual` / `observation` / `opportunistic` のどのタグも持たない行が 1 件以上ある (タグは閉じタグ `-->` までを持つ HTML コメントの内側だけから読む。`modules/verify-classifier.md` § Tag Extraction Rule)。`/verify` が UNCERTAIN や PENDING で止めた条件 (Step 11 (c), (d)) で、マーカーを残さない。`/verify` を実行しなかった batch (`AUTO_STOP_AT` が `merge`、または ARGUMENTS に `--non-interactive`) ではこの分岐を評価しない (List mode step 7 が verify をスキップし、Issue は全条件が未チェックのまま `phase/verify` で待つ設計のため)
   - 数えないもの: observation / opportunistic / manual 条件だけが未チェックの Issue、`session_start` より前に投稿されたマーカーだけを持つ Issue
   - 判定コマンド: Notes「挿入文案ドラフト」の ```` ```bash ```` ブロック。リテラル値の差し替え方 (`session_start` と `BATCH_ISSUES_RE`。実装コミット数の条件と同じ 2 値) を併記する。ブロックはサブステップ内の 2 番目以降の ```` ```bash ```` ブロック (jq 集計ブロックより後) に置き、`gh issue view` を含める (テストが内容で選ぶ)。出力は条件を満たす Issue ごとに 1 行 `#N verify-fail-markers=M unchecked-auto-conditions=K`
   - 判定ゲートの edge case (fail-safe。このコマンドは session.md を書くか否かを決めるゲートの一部で、既定値は「条件不成立」のため明記する。分岐の全列挙は Notes「分岐の全列挙」):
     - 空の入力: `BATCH_ISSUES_RE` が空なら、ループが 1 回も回らず出力なし (`gh` を呼ばない)。`session_start` が空ならマーカー分岐だけを無効にし (`marker=0`)、未解決の auto 条件の分岐は評価する。`body` が null の Issue は未チェック 0 件
     - 特殊文字: `BATCH_ISSUES_RE` の要素は数字だけを `gh` に渡し、数字以外・空の要素は無視する (`;`・`$(...)`・引用符・空白・改行・マルチバイト文字を含む要素を `gh` やシェルに渡さない)。コメントや本文の内容は jq の `--arg` と awk の標準入力だけを通り、シェルの文字列に展開しない。マーカーは 1 行目に固定するので、`>`・`"`・バッククォート・コードフェンスで引用されたマーカーには一致しない。本文の CRLF (`\r\n`) とマルチバイト文字は結果を変えない (`^\s*` は `\r` を許し、awk の `^- \[ \]` は行頭だけを見る)
     - 依存コマンドの失敗: `gh issue view` が失敗した Issue は stderr に `Warning: could not read #N, skipped` を出してその Issue だけ数えない。`jq` の失敗はマーカー 0、`jq` / `awk` の失敗は未チェック 0 に倒す。いずれも条件不成立 (not notable 側) に倒す。理由: 他の 3 条件が recovery・kill・実装規模を独立に検知する。誤って not notable に倒れても `events.jsonl` は commit され、`session.md` だけが書かれない。実装コミット数の条件 (#1533) と Batch Completion Report の best-effort 規則 (`gh issue view` が失敗した Issue はスキップして続行) と同じ向き
     - 大きな入力: 対象 Issue が多い場合 (Until mode の複数 round) は `gh issue view` が Issue ごとに 1 回ずつ順に走るだけで、本文とコメントはパイプで jq / awk に流す
   - 守ること: 半角 `!` を本文 (コードブロック・インラインコード・HTML コメント以外) に書かない、新しい見出しを作らない、`3. **Notable judgment**` と `4. **` の番号付き行を変えない、最初の ```` ```bash ```` ブロックを jq 集計のまま先頭に残す、frontmatter を変えない、`§` 以外の非 ASCII を新たに足さない (`§` は同じ SKILL.md に既出)、コードブロック内にバッククォート 3 連続を書かない (awk の fence 判定は `sprintf("%c%c%c", 96, 96, 96)` で作る。書くとブロックの終端が早まり、抽出テストと `validate-skill-syntax.py` の fence 対応が崩れる)
2. `tests/auto.bats` (after 1): Changed Files 記載の位置に、ヘルパー 4 つとテスト 5 件を追加する (→ 受入条件 1, 2 の回帰保護)。入力は `skills/auto/SKILL.md` の実体と、`$BATS_TEST_TMPDIR` に作る `gh issue view` 形式の JSON fixture およびモックの `gh` (形式は Notes「テスト入力の形式」)。数え方という新しい分岐を持つ手順なので、既存スイートが PASS することだけでなく、新規テストケース 5 件 (`tests/auto.bats` に `Notable judgment batch route Verify FAIL requires a session marker or an unresolved auto condition (Issue #1535)`・`Notable judgment Verify FAIL check counts a session marker or an unresolved auto condition and skips waiting Issues (Issue #1535)`・`Notable judgment Verify FAIL check handles CRLF, multibyte text, null bodies, boundary timestamps and tag look-alikes (Issue #1535)`・`Notable judgment Verify FAIL check skips unreadable Issues and non-numeric entries without running them (Issue #1535)`・`Notable judgment Verify FAIL check disables only the marker branch without a session start and prints nothing for an empty target list (Issue #1535)`) を追加したうえでスイートが PASS すること。アサートは `[[ ... ]] || false` か `[ ... ]` で書き、`[[ ... ]]` を単独で置かない (`scripts/check-bare-bracket-assertions.sh`)
3. [Steering Docs sync candidate] `modules/verify-classifier.md` (after 1): Consumers 表の `skills/auto/SKILL.md` の行を読み、Step 1 の変更後の `skills/auto/SKILL.md` が読む内容 (Pending manual confirmation の集計と、L3 notable 判定の未解決 auto 条件の判定) と食い違うなら、行に 1 句足す。足す場合の文案: 既存の `(Pending manual confirmation aggregation)` の後ろに `; the same three tags (through the closing delimiter) plus \`verify:\` command presence (L3 notable judgment's unresolved auto condition check)` を足す。採否と理由を `## Code Retrospective` に記録する (採らない場合も理由を残す)
4. 自己検証 (after 2, 3): 次をそれぞれ単一コマンドで実行する (worktree isolation guard が複合コマンドを拒否するため)。`bats tests/auto.bats`、`python3 scripts/validate-skill-syntax.py skills/`、`bash scripts/check-allowed-tools.sh`、`git diff -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py`、`bash scripts/check-forbidden-expressions.sh`、続けて `bats --jobs <N> tests/` (全スイート)。あわせて次を確認し、`## Code Retrospective` に記録する:
   - 新規テストが実装前に FAIL すること: `git show HEAD:skills/auto/SKILL.md` を `.tmp/` に書き出して (単独コマンド)、実装前の SKILL.md に新規テストを当てると 5 件とも FAIL する。本 Spec 作成時に、現行の `skills/auto/SKILL.md` で 5 件とも FAIL することを確認済み
   - `git diff -- skills/auto/SKILL.md` の削除行が、置き換える箇条書き 1 行だけであること (jq 集計ブロックなど他の行を触っていない)
   - AC1 の `section_contains` 相当: `sed -n '/^### Step 5: Completion Report/,/^### Step 6/p' skills/auto/SKILL.md | grep -c 'type=verify-fail'` が 1 以上 (実装前は 0、挿入文案のドラフトでは 4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 5 の L3 auto-retrospective の batch route の notable 判定で、Verify FAIL の条件が『phase/verify で未チェックの - [ ] が残る Issue』ではなく、この session 中に type=verify-fail のマーカーが投稿された Issue (または未チェックの auto 条件が残る Issue) に限定されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 5: Completion Report" "type=verify-fail" --> `skills/auto/SKILL.md` Step 5 の L3 notable 判定 (batch route) の「Verify FAIL」の条件が、この session 中に verify-fail マーカー (`<!-- wholework-event: type=verify-fail`) が投稿された batch 対象 Issue、または未チェックの auto 条件 (verify command 付き) が残る batch 対象 Issue に限定されている
- <!-- verify: rubric "skills/auto/SKILL.md の同じ箇所に、observation / opportunistic / manual 条件を待って phase/verify に残る Issue は FAIL ではない (本物の FAIL は phase/* ラベルを外して reopen する) ため notable の理由にしない旨が書かれている" --> observation / opportunistic / manual 条件の発火や確認を待っているだけで `phase/verify` に残る Issue は、この条件に当たらない理由が書かれている

### Post-merge

- 変更の反映後に始まった会話セッションで、recovery・FAIL・kill が 0 件で、対象 Issue が observation 条件待ちで `phase/verify` に残る 2 件 batch を `/auto --batch` で流したとき、L3 notable 判定が notable にならず `L3 session events committed (not notable — session.md skipped).` が出力される<!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - 端末に `L3 session events committed (not notable — session.md skipped).` が出力される
    - その session の `docs/sessions/<AUTO_SESSION_ID>-<date>/` に `events.jsonl` だけがあり、`session.md` がない
    - `Add L3 session data for session <AUTO_SESSION_ID>` のコミットが存在する
    - 該当する batch (recovery・FAIL・kill が 0 件、実装コミットが 3 件未満、対象 Issue が observation 条件待ちで `phase/verify` に残る batch) が実行されないうちは SKIPPED のままとする

## Notes

- **設計判断 (非対話モードでの自動解決): マーカーも未解決の auto 条件も、対象 Issue ごとの `gh issue view --json labels,body,comments` 1 回で判定する**。マーカーは `createdAt >= session_start` かつコメント本文の先頭がマーカーかどうかを jq で、未解決の auto 条件は本文を awk で数える。Issue 本文の「Auto-Resolved Ambiguity Points」が `/spec` の責務とした 2 点 (どのコマンドで数えるか・「この session 中」の取得方法) の答え。却下した案: (1) `events.jsonl` の `verify_fail_marker_posted` イベントを数える — マーカーの投稿直後に `/verify` が emit する (`skills/verify/SKILL.md` Step 11 (b)) ので `session_id` で session に絞れ、`gh` も `session_start` も要らないが、emit は best-effort で session ポインタの復元に依存する (経緯: #1075・#1224・#1491)。受入条件が名指しするのは GitHub 上のマーカーで、L0 の事実が一次情報なので採らない。将来の安価な事前チェックとして残す余地はある。(2) `scripts/` に新規スクリプトを置く — Size S の範囲を超え (スクリプト・bats・`docs/structure.md`・`allowed-tools` の更新が連鎖する)、#1533 と同じく、`tests/auto.bats` が SKILL.md に埋め込んだコマンドを抽出して検証する既存の流儀で足りる。本文のコマンドをテストで直接実行するので、記述と検証が乖離しない。(3) `scripts/rank-verify-backlog.sh` を流用する — 母集団が `phase/verify` の全 Issue (batch 対象でも session でもない)、Post-merge だけを見る、observation タグと rubric を同じ行に持つ形 (Option B) を auto と数える、の 3 点で目的に合わない。(4) `gh api` で Issue のコメントを取る — `gh api` は `/auto` の `allowed-tools` に無く、`gh issue view` は元から許可されている。(5) 未解決の auto 条件の分岐を外してマーカーだけにする — Issue 本文の自動解決が退けた案 (UNCERTAIN や PENDING の Issue はマーカーを持たず取りこぼす)
- **設計判断: マーカーの述語はコメント本文の先頭に固定する**。`test("^\\s*<!-- wholework-event: type=verify-fail ")`。`/verify` Step 11 (b) はファイルの 1 行目にマーカーを書いて投稿するので、先頭に固定しても取りこぼさない (実在のコメント: `https://github.com/saitoco/wholework/issues/1355` のマーカー、1 行目が `<!-- wholework-event: type=verify-fail phase=verify issue=1355 iteration=1 -->`、`createdAt` 2026-08-14T21:54:06Z、2026-10-16 取得。`gh issue view 1355 --json comments`)。`skills/auto/SKILL.md` Step 2a と `modules/l0-surfaces.md` のコメント消費は素の `contains` を使うが、あれは「マーカーが過去にあったか」を見る用途で、本条件は「この session に投稿されたか」を見る。この repo では `/spec` や `/issue` のコメントがマーカーの書式を引用することがあり (この Issue の Design Complete コメントも `type=verify-fail` に触れる)、素の `contains` だと同じ session 内に投稿された引用コメントを誤って数える。末尾の空白までを述語に含めるのは、マーカーが必ず `phase=` 以降の属性を持つため
- **設計判断: 未解決の auto 条件は本文全体 (Pre-merge と Post-merge) を見て、`phase/verify` ラベルを前提にする**。Post-merge だけだと、patch route で `/code` が検証せず未チェックのまま `/verify` に残した Pre-merge の条件 (CI を参照する条件など。`skills/code/SKILL.md` の「CI verification AC exclusion」) を取りこぼす。`/verify` Step 5 は Pre-merge の条件も検証し、UNCERTAIN や PENDING なら Pre-merge に未チェックが残って `phase/verify` で止まる。ラベルを前提にするのは、`phase/code` などで止まった Issue (未検証の auto 条件を持つ) を「verify が未解決」と数えないため (その種の失敗は他の条件が検知する)。fence 除外の規則は `modules/l0-surfaces.md` § AC Enumeration Convention と `scripts/rank-verify-backlog.sh` に揃える。待機タグ (`manual` / `observation` / `opportunistic`) は閉じタグ `-->` までを正準パターン (`([^-]|-[^-]|--[^>])*-->`、`scripts/apply-verify-retire.sh` と同じ) で読む (`skills/spec/skill-dev-constraints.md` の「HTML コメントタグ抽出の閉じタグ検証」、#1271)。閉じていないタグはタグとみなさず、その行は auto 条件のまま数える
- **設計判断: `/verify` を実行しなかった batch では未解決の auto 条件の分岐を評価しない**。List mode step 7 は `AUTO_STOP_AT` が `merge` のとき、または ARGUMENTS に `--non-interactive` があるときに `/verify` をスキップし、Issue は全条件が未チェックのまま `phase/verify` に残る。これは FAIL でも未解決でもなく設計どおりの待機。評価しないことは、`AUTO_STOP_AT` と ARGUMENTS が L3 の時点でも文脈に残っている前提 (このサブステップは既に `TIER3_RECOVERY_PHASE` などの文脈変数を使う)。この分岐を文言だけで書き、コマンドには入れない理由: `AUTO_STOP_AT` と ARGUMENTS は文脈変数でシェルには無く、コマンドに渡すと変数が増える。失われた場合は旧条件と同じ向き (数えすぎ) で、悪化はしない
- **分岐の全列挙 (`skills/spec/skill-dev-constraints.md` の「ブランチ分岐ロジックの挙動全列挙」)**。判定コマンドの分岐を、条件・動作・出力・終了で列挙する。終了コードは常に 0 (最後に実行されるのは `if` か `continue` で、いずれも 0)

  | 分岐 | 条件 | 動作 | 出力・終了 |
  |---|---|---|---|
  | 入力の検証 | `BATCH_ISSUES_RE` の要素が空、または数字以外を含む | その要素を無視し `gh` に渡さない | 出力なし、次の要素へ |
  | 取得失敗 | `gh issue view` が非 0 | その Issue を数えない | stderr に `Warning: could not read #N, skipped`、次の要素へ |
  | マーカー分岐 (無効) | `session_start` が空 | `marker=0` (jq を実行しない) | 未解決の分岐は評価する |
  | マーカー分岐 (jq 失敗) | `jq` が非 0 | `marker=0` | 同上 |
  | マーカー分岐 (通常) | 1 行目がマーカーで `createdAt >= session_start` のコメントがある | `marker` にその件数 | — |
  | 未解決の分岐 (ラベル無し) | `phase/verify` が付いていない | 本文を awk に渡さない (`unresolved=0`) | — |
  | 未解決の分岐 (jq / awk 失敗) | 非 0 | `unresolved=0` | — |
  | 未解決の分岐 (通常) | `phase/verify` があり、fence 外の `^- [ ]` 行に `<!-- verify:` があって待機タグが無い | `unresolved` にその件数 | — |
  | 出力 | `marker > 0` または `unresolved > 0` | 1 行出力 | stdout に `#N verify-fail-markers=M unchecked-auto-conditions=K` |

- **実測 (母集団、2026-10-16)**。旧条件が当たる範囲と新条件が当たる範囲を `phase/verify` ラベルの Issue で測った。スコープ: `gh issue list --label "phase/verify" --state all --limit 500` (302 件で上限 500 未満のため全件)。旧条件に相当する数え方 (Post-merge の fence 外の未チェック `- [ ]` が 1 件以上): `bash scripts/rank-verify-backlog.sh --top 1 --limit 500` の stderr (`#N: auto=A manual=M`) で、`auto=0` かつ `manual=0` が 11 件、残り 291 件が未チェックを 1 件以上持つ (全件 `auto=0`、つまり verify command を持たない待機の条件)。新条件の未解決 auto 条件 (本文全体・待機タグ除外): 4 件 (#1092・#885・#318・#163)。すべて Pre-merge の CI 参照や `command` / `section_contains` の条件が未チェックで残ったもの (#1092 は CLOSED のまま `phase/verify`)。Post-merge に限ると 0 件で `rank-verify-backlog.sh` の `auto=0` と一致する。つまり旧条件は 291 件に当たり、新条件は 4 件に当たる
- **実測 (再現による検証、2026-10-16)**。Issue 本文の表の 2 セッションを、新しい判定コマンドで実データに当てた (`BATCH_ISSUES_RE=... session_start=... bash <抜き出したブロック>`)。セッション `647181-1792110450` (対象 #1531・#1530、`session_start` 2026-10-16T00:27:43Z。`docs/spec/issue-1533-l3-notable-impl-commits.md` に記録された値): 出力なし。セッション `1080384-1792130694` (対象 #1533・#1534、`session_start` 2026-10-16T06:04:54Z。セッション ID の epoch `date -u -d @1792130694` から導いた値で、`.tmp/auto-session-*.json` はリポジトリに無い): 出力なし。旧条件が拾った #1531 と #1533 は、いずれも現在も `phase/verify` を持つ (`gh issue view 1531 --json labels`)。#1533 の実装コミット数の条件 (2 件で閾値 3 未満) と合わせて、2 セッションとも not notable になる。マーカー側は実在のコメントでも確認した: `BATCH_ISSUES_RE=1355 session_start=2026-08-14T00:00:00Z` で `#1355 verify-fail-markers=1 unchecked-auto-conditions=0`、`session_start=2026-08-15T00:00:00Z` で出力なし
- **既知の限界 (いずれも過小評価か、旧条件と同じ向きの数えすぎ。他の 3 条件には影響しない)**: (1) `gh issue view --json comments` が返すコメントの上限は未確認 (100 件で切られるかどうか)。この repo のコメント数の最大は 87 件 (#839、`gh api "repos/{owner}/{repo}/issues?state=all&per_page=100&sort=comments&direction=desc"`、2026-10-16)。100 件を超える Issue でマーカーが切り捨てられても not notable 側に倒れる。(2) 観測 dispatch (`observation-trigger.sh` 由来) で `/verify` が走る batch 対象外の Issue の FAIL は数えない (受入条件が batch 対象 Issue に限定している)。(3) CI が実行中で PENDING のまま batch が終わった Issue も未解決の auto 条件として数える (待機ではなく解決待ちの条件で、再実行が要るため)。(4) `session_start` は UTC の ISO 8601 を前提に文字列比較する (`modules/l0-surfaces.md` Comment Consumption Procedure の Step 2 と同じ前提)。UTC 以外のオフセットで記録されるとマーカーを取りこぼす (not notable 側)。(5) `/verify` スキップの判定は文脈変数に依存する。失われると、スキップした batch で旧条件と同じ数えすぎが起きる
- **Issue 本文と実装の照合 (矛盾検出)**: Background の主張 — 旧条件の文言 (`skills/auto/SKILL.md` 828 行)、`/verify` Step 11 (a) が auto 条件に FAIL / UNCERTAIN が 0 件のときだけ待機に入ること、`session_start` が `.tmp/auto-session-${AUTO_SESSION_ID}.json` の値で #1533 の実装コミット数と同じこと (833 行)、2 セッションの記録 (`docs/sessions/647181-1792110450-2026-10-16/` と `docs/sessions/1080384-1792130694-2026-10-16/` が存在し、後者の `session.md` に同じ指摘がある) — は実装と一致する。**1 点だけ実装と食い違う**: 「FAIL した Issue に `phase/verify` は残らない」は、`/verify` Step 11 (b) の上限到達の分岐 (`NEXT_ITERATION >= VERIFY_MAX_ITERATIONS`) で成り立たない。この分岐はマーカーを投稿したうえで `phase/verify` を付け、Issue の状態は変えない (`MAX_ITERATIONS_REACHED`)。解決: 本条件は FAIL の証拠をラベルではなくマーカーに置くので、この分岐も分岐 1 で拾える。SKILL.md の文言は「最後の FAIL だけが `phase/verify` を残し、マーカーは投稿する」と正確に書く。受入条件 2 の rubric (本物の FAIL は `phase/*` ラベルを外して reopen する) とは矛盾しない (例外を併記する)
- **`section_contains` の走査範囲 (`modules/verify-patterns.md` § 29 の pattern 4)**: AC1 の `section_contains "skills/auto/SKILL.md" "Step 5: Completion Report" "type=verify-fail"` は、見出し `### Step 5: Completion Report` (699 行、部分一致で解決) から次の同レベル以上の見出し (`### Step 6: On Failure: 3-Tier Recovery`、969 行) の直前までを走査する。L3 auto-retrospective は 794〜968 行でこの区間に入っており、区間内に h3 以上の見出しは無い。実装は見出しを足さず、箇条書きの置き換えに留める。文字列の存在確認: `type=verify-fail` は現状 Step 5 の区間に 0 件 (`sed -n '/^### Step 5: Completion Report/,/^### Step 6/p' skills/auto/SKILL.md | grep -c 'type=verify-fail'` = 0) で、挿入文案のドラフトを入れたコピーでは 4 件。AC1 の rubric は文言の揺れに対して、この `section_contains` が配置の安全網になる。Issue Retrospective のコメントは見出しを `### Step 5: Completion Report` と書いているが、Issue 本文の AC は `Step 5: Completion Report` で、どちらも同じ見出しに解決する
- **テスト入力の形式 (bats)**: 入力は (a) `skills/auto/SKILL.md` の実体 (`SKILL_FILE`)、(b) `$BATS_TEST_TMPDIR/vf` に作る `gh issue view <N> --json labels,body,comments` 形式の JSON fixture (`{"labels":[{"name":"phase/verify"}],"body":"...","comments":[{"createdAt":"2026-01-02T01:00:00Z","body":"<!-- wholework-event: type=verify-fail ... -->\n..."}]}`。`jq -n --arg body` で組み立てるので本文の改行・引用符・CRLF を壊さない)、(c) PATH の先頭に置くモックの `gh` (`$VF_DIR/issue-<N>.json` を返し、呼ばれた番号を `$VF_DIR/calls.log` に追記する。fixture が無い番号は exit 1)。コマンドの抽出は、`notable_judgment_section` の範囲から ```` ```bash ```` ブロックを順に読み、`gh issue view` を含むものを返す awk (先頭ブロックは jq 集計なので位置でなく内容で選ぶ。現行の `skills/auto/SKILL.md` では block が無く status 1、挿入文案を入れたコピーでは block を返すことを確認済み)。変数は `run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start=... BATCH_ISSUES_RE=... bash -c "$cmd"` で渡す。`session_start` は固定の `2026-01-02T00:00:00Z` で、現在日時に依存させない。fixture の内容と期待値:

  | 番号 | ラベル | 内容 | 期待 |
  |---|---|---|---|
  | 11 | なし | 開始後に投稿されたマーカー (reopen 済みでラベルが外れた本物の FAIL) | 数える (markers=1) |
  | 12 | phase/verify | verify command を持たない observation 条件 | 数えない |
  | 13 | phase/verify | observation タグと rubric の verify command を同じ行に持つ条件 | 数えない |
  | 14 | phase/verify | verify command 付きの未チェック auto 条件 + manual 条件 | 数える (unchecked=1) |
  | 15 | phase/done | 開始前のマーカー、全条件チェック済み | 数えない |
  | 16 | phase/done | マーカーを引用しただけのコメント 3 件 (インラインコード・コードフェンス・1 行目以外) | 数えない |
  | 17 | phase/verify | コードフェンス内の verify command 付きサンプル行 + manual 条件 | 数えない |
  | 18 | phase/code | 未チェックの auto 条件 (ラベルゲート) | 数えない |
  | 21 | phase/verify | CRLF 改行と日本語の auto 条件 | 数える (unchecked=1) |
  | 22 | phase/verify | `body` が null | 数えない |
  | 23 | phase/verify | インデントされた入れ子のチェックボックス | 数えない |
  | 24 | なし | `session_start` と同一秒のマーカー | 数える (markers=1) |
  | 25 | なし | `deferral=true reason="..."` 付きのマーカー | 数える (markers=1) |
  | 26 | phase/verify | 明示的な `verify-type: auto` タグ | 数える (unchecked=1) |
  | 27 | phase/verify | verify command の文字列に `verify-type: manual` の語句 (タグではない) | 数える (unchecked=1) |
  | 28 | phase/verify | Pre-merge の未チェック auto 条件 (Post-merge は全部チェック済み) | 数える (unchecked=1) |
  | 29 | phase/verify | マーカー 2 件 + 未チェック auto 条件 | 数える (markers=2, unchecked=1) |
  | 30 | phase/verify | 閉じていない `<!-- verify-type: manual` | 数える (タグとみなさない) |
  | 31・32 | phase/verify / fixture なし | 31 は未チェック auto 条件、32 は `gh` が失敗する Issue | 31 は数える。32 は警告してスキップ。`3x`・`abc`・`1;2`・`$(id)`・空の要素は `gh` に渡らない |
  | 41・42 | なし / phase/verify | 41 はマーカーのみ、42 はマーカー + 未チェック auto 条件 | 開始時刻があれば両方、空なら 42 だけ。対象リストが空なら出力なしで `gh` を呼ばない |

  期待値は挿入文案のドラフトの出力形式 `#N verify-fail-markers=M unchecked-auto-conditions=K` に基づく。旧条件との対照として、12 と 13 が「`phase/verify` を持ち未チェックの `- [ ]` がある」(旧条件なら数えた) ことを `jq -e` で確認する
- **新規テストの要件 (light のため Notes に記録)**: 数え方という新しい分岐を持つため、既存スイートの PASS だけでなく新規ケース 5 件の追加を求める。文言の回帰保護 (1 件) は、`type=verify-fail`・`session_start`・`BATCH_LIST`・`Step 11 (b)`・`MAX_ITERATIONS_REACHED`・`` `observation`, `opportunistic`, or `manual` `` の固定文字列と、旧条件の文言 (`` unchecked `- [ ]` at batch end ``) の不在を検査する。実装前 FAIL の確認 (2026-10-16 実測): 現行の `skills/auto/SKILL.md` では、抽出 awk が block を返さず status 1 になり (ヘルパー経由の 4 テストは `|| false` で FAIL)、文言テストは `type=verify-fail` の検査で FAIL する。挿入文案を入れたコピーでは、新規 5 件に加えて既存 33 件 (計 38 件) が PASS する
- **制約への適合 (`skills/spec/skill-dev-constraints.md` を light でも確認した)**: (1) 追記は英語のみで CJK 文字を含めない (CI の `language-convention` が `git diff -- skills/ modules/ scripts/` の追加行を検査。挿入文案のドラフトの差分で `check-language-convention.py` が exit 0 を確認)。(2) `docs/product.md` § Terms の旧称にある非推奨用語を使わない (CI の `check-forbidden-expressions` が `skills/ modules/ agents/ tests/ docs/ scripts/` を走査し、この Spec 自身も対象)。(3) SKILL.md 本文に半角 `!` を書かない・小数のステップ番号を作らない (`validate-skill-syntax.py` が挿入文案のコピーで 0 エラー・0 警告)。(4) 新しい見出しを作らない。(5) `${CLAUDE_PLUGIN_ROOT}/scripts/` の新規参照を足さないので frontmatter の `allowed-tools` は変えない。(6) 「ブランチ分岐ロジックの挙動全列挙」は上の分岐表。(7) 「HTML コメントタグ抽出の閉じタグ検証」は上の設計判断。(8) 「Edge cases」は Implementation Steps 1 の edge case。(9) 「Verify existing parser behavior」は、`gh`・`jq`・`awk` の実際の挙動を下の「外部仕様依存」のとおり実機で確認した
- **audit/investigation-type の判定**: no (判定条件を直す変更で、既存項目を分類した結果を後続処理が根拠として読む監査・調査の Issue ではない)。fail-safe critical: 該当 (notable 判定は session.md を書くか否かを決めるゲートの一部)。edge case は Implementation Steps 1 に列挙した。tool 検出・新規依存パッケージ・adapter 追加: いずれもなし (verify command は組み込みの `rubric` と `section_contains` だけ)。Costly / irreversible なステップ: なし。external-auth-required: なし。URL 到達性確認の対象: なし
- **外部仕様依存の確認 (出所)**: `gh issue view <N> --json labels,body,comments` のフィールド (`labels[].name`・`body`・`comments[].createdAt`・`comments[].body`) を gh 2.101.0 の実出力で確認した (`gh issue view 1535 --json labels,body,comments` と #1355、2026-10-16 取得)。`jq` 1.7 の `test("^\\s*...")`・`--arg`・`index`・`//`、`mawk` (ローカルの `awk`、CI の Ubuntu と同系統) の `sprintf("%c", 96)`・`substr`・ERE の選択、bats 1.11.1 (CI は `apt-get install bats`) で、挿入文案と全テストが通ることを確認した。macOS の BSD awk は実機で未確認だが、使う構文は POSIX の範囲 (`%c` に数値を渡す書式、ERE、`substr`、`sub`)
- **Self-hosting と Post-merge**: wholework は自分自身を使うため、`skills/auto/SKILL.md` の変更は、変更が base に入った後に始まった会話セッションで読み込まれてはじめて有効になる (`modules/verify-classifier.md` § observation Type: Event Values and Syntax の `session=next` の説明)。Post-merge の条件は Issue 本文のとおり `observation` (`event=auto-run session=next`)。`auto-run` は同モジュールのイベント語彙表にあり、語彙の照合に問題はない。「観測したいイベント」と「期待する出力の構造」を分けるため、Spec 側では Option A (入れ子の `Expected output structure:`) の形に整えた (#1533 の Spec と同じ扱い。Issue 本文の文言と意味は変えていない)。#1533 の Post-merge 条件はこの Issue と合わせて初めて満たせる (Issue 本文 Notes)。Post-merge の期待に「実装コミットが 3 件未満」を加えたのは、#1533 の規則では 2 件 batch の実装コミットが 2 件で閾値 3 を下回るため
- **Size**: Changed Files は 2 件 (Axis 1 = S)。Axis 2 は、複数 skill にまたがらず新しい architecture pattern でもない。埋め込みコマンドという分岐の追加 (増やす要因) と、#1533 の方式の横展開 (減らす要因) が相殺して補正なし。CI Dependency Minimum Override の対象外 (CI workflow・テストの並列化フラグ・共有 fixture の変更なし。新規 fixture は各テストの `$BATS_TEST_TMPDIR` に閉じる)。triage 時点の S のまま patch route (`ALWAYS_PR=false`、`.wholework.yml` に `always-pr` なし)。Pre-merge に `github_check "gh pr checks"` は無く、route に応じた書き換えは不要。Steering Docs sync candidate の 1 行編集 (Implementation Steps 3) は Size を変えない
- **コメント消費**: cutoff は直近の `phase/issue` ラベル付与 (2026-10-16T11:25:59Z)。cutoff 以降の 1 件 (`## Issue Retrospective`、saito / MEMBER) は first-class で、内容は Issue 本文の最新版 (AC1 への `section_contains` の併記、Post-merge の observation 条件の検証結果) に反映済み。クロスフェーズのマーカー (`verify-fail` / `preview-ac-unverified`) は無い
- **先行事例**: #1533 (同じ判定ブロックの別の条件。`notable_judgment_section` を使ったコマンド抽出テストと挿入文案ドラフトの書き方)、#913 (jq 集計と判定条件の対応)、#1517 (`notable_judgment_section` の `|| false` の流儀)、#1271 (HTML コメントタグ抽出の閉じタグ検証)、#1349 (`rank-verify-backlog.sh` の fence 除外と auto の数え方)
- **挿入文案ドラフト** (`/code` は趣旨と必須要素を保てば文言を調整してよい。ただしテストが固定文字列で検査する `type=verify-fail`・`session_start`・`BATCH_LIST`・`Step 11 (b)`・`MAX_ITERATIONS_REACHED`・`` `observation`, `opportunistic`, or `manual` ``、および出力形式 `#N verify-fail-markers=M unchecked-auto-conditions=K` と警告文 `Warning: could not read #N, skipped` を変える場合は、テストの文字列も同じ文言に揃える。英語のみで CJK 文字を含めない。このドラフトは `.tmp/` のコピーに適用して、テスト 38 件の PASS・`validate-skill-syntax.py` の 0 エラー・`check-language-convention.py` の exit 0 を確認済み):

  `skills/auto/SKILL.md` の batch route の箇条書き (現状 828 行の 1 行) を置き換える。インデントは、箇条書きが 5 スペース、その入れ子が 7 スペース、コードブロックが 9 スペース:

  ````markdown
       - Verify FAIL: at least one Issue in `BATCH_LIST` (the same target Issues as the implementation commit count below) on which `/verify` actually failed or left an auto condition unresolved. A bare `phase/verify` label check is not used: that label also marks an Issue that is only waiting for an `observation`, `opportunistic`, or `manual` condition to fire or be confirmed (`/verify` Step 11 (a)); a `session=next` observation condition in particular keeps an Issue there until a later session fires it, so the bare check made batches notable even when nothing failed (Issue #1535). A real FAIL goes through `/verify` Step 11 (b), which posts a `type=verify-fail` marker comment, removes the `phase/*` labels, and reopens a closed Issue; only the final FAIL at `MAX_ITERATIONS_REACHED` keeps `phase/verify`, and it posts the marker as well. An Issue counts when either branch below holds at batch end:
         - Marker: it received a `type=verify-fail` marker during this session, that is, a comment whose first line starts with `<!-- wholework-event: type=verify-fail` and whose `createdAt` is at or after `session_start`. A comment that only quotes the marker further down its body does not count.
         - Unresolved auto condition: it still has the `phase/verify` label and at least one unchecked auto condition, that is, a `- [ ]` line outside code fences (see `modules/l0-surfaces.md` § AC Enumeration Convention) that carries a `<!-- verify:` command and none of the `verify-type: manual`, `verify-type: observation`, or `verify-type: opportunistic` tags (read only from inside their own HTML comment, through its closing `-->`, per `modules/verify-classifier.md` § Tag Extraction Rule). `/verify` leaves such a condition unchecked when it ends UNCERTAIN or PENDING (Step 11 (c), (d)), and posts no marker then. Skip this branch when `/verify` did not run for the batch (`AUTO_STOP_AT` is `merge`, or ARGUMENTS contains `--non-interactive`): the Issues then wait in `phase/verify` with every condition unchecked by design.
         - Not counted: an Issue whose only unchecked conditions are `observation`, `opportunistic`, or `manual` ones, and an Issue whose `type=verify-fail` marker was posted before `session_start`.
         - Evaluate both branches with this command, after substituting the literal values (each Bash call is a fresh shell): `session_start` is the value recorded in `.tmp/auto-session-${AUTO_SESSION_ID}.json` and `BATCH_ISSUES_RE` is the Issue numbers of `BATCH_LIST` joined with `|` (digits and `|` only, no spaces, no trailing `|`), the same two values the implementation commit count below uses. It prints one line per counted Issue:
           ```bash
           printf '%s\n' "$BATCH_ISSUES_RE" | tr '|' '\n' | while IFS= read -r issue; do
             case "$issue" in ''|*[^0-9]*) continue ;; esac
             json=$(gh issue view "$issue" --json labels,body,comments 2>/dev/null < /dev/null) || { echo "Warning: could not read #$issue, skipped" >&2; continue; }
             marker=0
             if [ -n "$session_start" ]; then
               marker=$(printf '%s' "$json" | jq --arg since "$session_start" '[.comments[] | select(.createdAt >= $since) | select(.body | test("^\\s*<!-- wholework-event: type=verify-fail "))] | length' 2>/dev/null) || marker=0
             fi
             unresolved=$(printf '%s' "$json" | jq -r 'if (.labels | map(.name) | index("phase/verify")) then (.body // "") else empty end' 2>/dev/null | awk '
               BEGIN { fence = sprintf("%c%c%c", 96, 96, 96) }
               { line = $0; sub(/^[ \t]+/, "", line) }
               substr(line, 1, 3) == fence { in_fence = 1 - in_fence; next }
               in_fence { next }
               /^- \[ \]/ {
                 has_cmd = ($0 ~ /<!--[ \t]*verify:/)
                 waiting = ($0 ~ /<!--[ \t]*verify-type:[ \t]*(manual|observation|opportunistic)([^-]|-[^-]|--[^>])*-->/)
                 if (has_cmd && waiting == 0) cnt++
               }
               END { print cnt + 0 }
             ') || unresolved=0
             if [ "$marker" -gt 0 ] || [ "$unresolved" -gt 0 ]; then
               echo "#$issue verify-fail-markers=$marker unchecked-auto-conditions=$unresolved"
             fi
           done
           ```
           Any output line means this condition is met. Every failure leaves it unmet: an Issue that `gh` cannot read is skipped with a warning on stderr, an entry that is not all digits is ignored, an empty `session_start` disables the marker branch only, and an empty `BATCH_ISSUES_RE` prints nothing. The other notable conditions still apply.
  ````

  `tests/auto.bats` に追加するヘルパーとテスト (既存の `notable_judgment_section` と `SKILL_FILE` を使う。挿入位置は Changed Files のとおり。日本語の文字列は多バイト入力の edge case を検証するテストデータで、コメントや名前ではない。`tests/` に日本語リテラルを含む bats の前例は複数ある):

  ````bash
  # Tests for the batch route Verify FAIL condition in the Notable judgment sub-step (Issue #1535).
  # The condition must count only Issues on which /verify actually failed (a type=verify-fail marker posted
  # during the session) or left an auto condition unresolved, not every Issue waiting in phase/verify.

  # Extract the Verify FAIL check command embedded in the Notable judgment sub-step: the fenced bash block
  # that contains "gh issue view". The first bash block of the sub-step is the jq aggregation, so the block
  # is selected by content, not by position. Exits 1 when the sub-step or the block is missing.
  notable_judgment_verify_fail_command() {
      local section
      section="$(notable_judgment_section "$1")" || return
      printf '%s\n' "$section" | awk '
          /```bash/ { inblk = 1; blk = ""; next }
          inblk && /```/ { inblk = 0; if (blk ~ /gh issue view/) { printf "%s", blk; found = 1; exit } next }
          inblk { blk = blk $0 "\n" }
          END { if (!found) exit 1 }
      '
  }

  # Install a mock gh that serves $VF_DIR/issue-<N>.json for "gh issue view <N> ..." and logs every requested
  # number to $VF_DIR/calls.log. A number without a fixture file makes the mock fail, like an unreadable Issue.
  verify_fail_mock_gh() {
      local dir="$1"
      mkdir -p "$dir/bin"
      cat > "$dir/bin/gh" <<'MOCK'
  #!/bin/bash
  if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
      echo "$3" >> "$VF_DIR/calls.log"
      [ -f "$VF_DIR/issue-$3.json" ] || exit 1
      cat "$VF_DIR/issue-$3.json"
      exit 0
  fi
  exit 1
  MOCK
      chmod +x "$dir/bin/gh"
  }

  # Write one "gh issue view --json labels,body,comments" fixture: verify_fail_fixture DIR NUMBER LABELS_JSON BODY COMMENTS_JSON.
  verify_fail_fixture() {
      jq -n --argjson labels "$3" --arg body "$4" --argjson comments "$5" \
          '{labels: $labels, body: $body, comments: $comments}' > "$1/issue-$2.json"
  }

  # One Issue comment whose first line is the /verify FAIL marker: verify_fail_marker_comment CREATED_AT [EXTRA_ATTRS].
  verify_fail_marker_comment() {
      jq -n --arg t "$1" --arg extra "${2:-}" \
          '{createdAt: $t, body: ("<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1" + $extra + " -->\n## /verify FAIL\n")}'
  }

  @test "Notable judgment batch route Verify FAIL requires a session marker or an unresolved auto condition (Issue #1535)" {
      # Plain assignment (not run) so a missing sub-step fails the test (Issue #1517)
      section="$(notable_judgment_section "$SKILL_FILE")"
      [[ "$section" == *'type=verify-fail'* ]] || false
      [[ "$section" == *'session_start'* ]] || false
      [[ "$section" == *'BATCH_LIST'* ]] || false
      [[ "$section" == *'Step 11 (b)'* ]] || false
      [[ "$section" == *'MAX_ITERATIONS_REACHED'* ]] || false
      [[ "$section" == *'`observation`, `opportunistic`, or `manual`'* ]] || false
      # The bare label check that counted every Issue waiting in phase/verify must be gone
      [[ "$section" != *'unchecked `- [ ]` at batch end'* ]] || false
  }

  @test "Notable judgment Verify FAIL check counts a session marker or an unresolved auto condition and skips waiting Issues (Issue #1535)" {
      local dir="$BATS_TEST_TMPDIR/vf"
      mkdir -p "$dir"
      verify_fail_mock_gh "$dir"
      local cmd
      cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

      local L_VERIFY='[{"name":"phase/verify"}]' L_DONE='[{"name":"phase/done"}]' L_CODE='[{"name":"phase/code"}]' NOC='[]'
      local OBS='- [ ] waits for the next run <!-- verify-type: observation event=auto-run session=next -->'
      local MARK_AFTER MARK_BEFORE QUOTE_INLINE QUOTE_FENCE QUOTE_LATER
      MARK_AFTER="$(verify_fail_marker_comment 2026-01-02T01:00:00Z)"
      MARK_BEFORE="$(verify_fail_marker_comment 2025-12-31T23:59:59Z)"
      QUOTE_INLINE="$(jq -n '{createdAt: "2026-01-02T02:00:00Z", body: "Design notes: the `<!-- wholework-event: type=verify-fail phase=verify issue=1 -->` marker is posted on FAIL."}')"
      QUOTE_FENCE="$(jq -n '{createdAt: "2026-01-02T02:00:01Z", body: "Quoted sample:\n\n```\n<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1 -->\n```\n"}')"
      QUOTE_LATER="$(jq -n '{createdAt: "2026-01-02T02:00:02Z", body: "## Design Complete\n<!-- wholework-event: type=verify-fail phase=verify issue=1 iteration=1 -->\n"}')"

      # 11: a real FAIL: reopened (no phase label), marker posted after the session start
      verify_fail_fixture "$dir" 11 "$NOC" $'### Post-merge\n\n'"$OBS"$'\n' "[$MARK_AFTER]"
      # 12: waiting for an observation condition that has no verify command
      verify_fail_fixture "$dir" 12 "$L_VERIFY" $'### Post-merge\n\n'"$OBS"$'\n' "$NOC"
      # 13: waiting for an observation condition that also carries a verify command (rubric form)
      verify_fail_fixture "$dir" 13 "$L_VERIFY" $'### Post-merge\n\n- [ ] waits <!-- verify-type: observation event=auto-run --> <!-- verify: rubric "x" -->\n' "$NOC"
      # 14: an auto condition left unchecked (UNCERTAIN) next to a manual one
      verify_fail_fixture "$dir" 14 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_contains "a.md" "b" --> an auto condition\n- [ ] a manual one <!-- verify-type: manual -->\n' "$NOC"
      # 15: a marker from before the session start, Issue done and fully checked
      verify_fail_fixture "$dir" 15 "$L_DONE" $'### Post-merge\n\n- [x] <!-- verify: file_exists "a" --> done\n' "[$MARK_BEFORE]"
      # 16: the marker is only quoted (inline code, code fence, not the first line), never posted
      verify_fail_fixture "$dir" 16 "$L_DONE" $'### Post-merge\n\n- [x] ok\n' "[$QUOTE_INLINE,$QUOTE_FENCE,$QUOTE_LATER]"
      # 17: a sample checkbox with a verify command inside a code fence
      verify_fail_fixture "$dir" 17 "$L_VERIFY" $'### Post-merge\n\n- [ ] a manual one <!-- verify-type: manual -->\n\n```markdown\n- [ ] <!-- verify: file_exists "a" --> sample line\n```\n' "$NOC"
      # 18: an unchecked auto condition, but the Issue never reached phase/verify
      verify_fail_fixture "$dir" 18 "$L_CODE" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> never verified\n' "$NOC"

      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="11|12|13|14|15|16|17|18" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = $'#11 verify-fail-markers=1 unchecked-auto-conditions=0\n#14 verify-fail-markers=0 unchecked-auto-conditions=1' ]
      # Every target Issue was read
      [ "$(tr '\n' ' ' < "$dir/calls.log")" = "11 12 13 14 15 16 17 18 " ]

      # Control: the bare label check this condition replaces (phase/verify with any unchecked checkbox) would have
      # counted the two Issues that only wait for an observation condition.
      jq -e '(.labels | map(.name) | index("phase/verify")) != null and (.body | test("- \\[ \\]"))' "$dir/issue-12.json"
      jq -e '(.labels | map(.name) | index("phase/verify")) != null and (.body | test("- \\[ \\]"))' "$dir/issue-13.json"
  }

  @test "Notable judgment Verify FAIL check handles CRLF, multibyte text, null bodies, boundary timestamps and tag look-alikes (Issue #1535)" {
      local dir="$BATS_TEST_TMPDIR/vf"
      mkdir -p "$dir"
      verify_fail_mock_gh "$dir"
      local cmd
      cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

      local L_VERIFY='[{"name":"phase/verify"}]' L_NONE='[]' NOC='[]'
      local OBS='- [ ] waits for the next run <!-- verify-type: observation event=auto-run session=next -->'

      # 21: CRLF line endings and Japanese text
      verify_fail_fixture "$dir" 21 "$L_VERIFY" $'### Post-merge\r\n\r\n- [ ] <!-- verify: file_exists "x" --> 日本語の条件\r\n' "$NOC"
      # 22: null body
      jq -n --argjson labels "$L_VERIFY" '{labels: $labels, body: null, comments: []}' > "$dir/issue-22.json"
      # 23: an indented checkbox is not an acceptance condition line
      verify_fail_fixture "$dir" 23 "$L_VERIFY" $'### Post-merge\n\n- [ ] parent <!-- verify-type: manual -->\n  - [ ] <!-- verify: file_exists "a" --> nested sub-bullet\n' "$NOC"
      # 24: a marker created exactly at the session start second
      verify_fail_fixture "$dir" 24 "$L_NONE" $'### Post-merge\n\n'"$OBS"$'\n' "[$(verify_fail_marker_comment 2026-01-02T00:00:00Z)]"
      # 25: a marker with the optional deferral attributes still counts
      verify_fail_fixture "$dir" 25 "$L_NONE" $'### Post-merge\n\n'"$OBS"$'\n' "[$(verify_fail_marker_comment 2026-01-02T05:00:00Z ' deferral=true reason="pending authorization"')]"
      # 26: an explicit verify-type: auto tag is still an auto condition
      verify_fail_fixture "$dir" 26 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: grep "a" "b" --> text <!-- verify-type: auto -->\n' "$NOC"
      # 27: the words "verify-type: manual" appear inside the command text, not as a tag
      verify_fail_fixture "$dir" 27 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_contains "a.md" "verify-type: manual" --> excludes the verify-type: manual tally\n' "$NOC"
      # 28: an unresolved auto condition in Pre-merge (patch route: /verify is the first verifier)
      verify_fail_fixture "$dir" 28 "$L_VERIFY" $'### Pre-merge\n\n- [ ] <!-- verify: file_exists "y" --> pre cond\n\n### Post-merge\n\n- [x] <!-- verify: file_exists "z" --> done\n' "$NOC"
      # 29: two markers (two iterations) plus an unresolved auto condition
      verify_fail_fixture "$dir" 29 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> still open\n' "[$(verify_fail_marker_comment 2026-01-02T03:00:00Z),$(verify_fail_marker_comment 2026-01-02T04:00:00Z)]"
      # 30: a waiting tag with no closing delimiter is not a tag (Tag Extraction Rule), so the line stays an auto condition
      verify_fail_fixture "$dir" 30 "$L_VERIFY" $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> text <!-- verify-type: manual\n' "$NOC"

      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="21|22|23|24|25|26|27|28|29|30" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = $'#21 verify-fail-markers=0 unchecked-auto-conditions=1\n#24 verify-fail-markers=1 unchecked-auto-conditions=0\n#25 verify-fail-markers=1 unchecked-auto-conditions=0\n#26 verify-fail-markers=0 unchecked-auto-conditions=1\n#27 verify-fail-markers=0 unchecked-auto-conditions=1\n#28 verify-fail-markers=0 unchecked-auto-conditions=1\n#29 verify-fail-markers=2 unchecked-auto-conditions=1\n#30 verify-fail-markers=0 unchecked-auto-conditions=1' ]
  }

  @test "Notable judgment Verify FAIL check skips unreadable Issues and non-numeric entries without running them (Issue #1535)" {
      local dir="$BATS_TEST_TMPDIR/vf"
      mkdir -p "$dir"
      verify_fail_mock_gh "$dir"
      local cmd
      cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

      verify_fail_fixture "$dir" 31 '[{"name":"phase/verify"}]' $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> open\n' '[]'
      # 32 has no fixture: the mock gh fails for it, like an unreadable Issue

      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE='31|32|3x|abc|1;2|$(id)||' bash -c "$cmd"
      [ "$status" -eq 0 ]
      [[ "$output" == *'#31 verify-fail-markers=0 unchecked-auto-conditions=1'* ]] || false
      [[ "$output" == *'Warning: could not read #32, skipped'* ]] || false
      [[ "$output" != *'#32 verify-fail'* ]] || false
      # Only all-digit entries reached gh
      [ "$(tr '\n' ' ' < "$dir/calls.log")" = "31 32 " ]
  }

  @test "Notable judgment Verify FAIL check disables only the marker branch without a session start and prints nothing for an empty target list (Issue #1535)" {
      local dir="$BATS_TEST_TMPDIR/vf"
      mkdir -p "$dir"
      verify_fail_mock_gh "$dir"
      local cmd
      cmd="$(notable_judgment_verify_fail_command "$SKILL_FILE")" || false

      verify_fail_fixture "$dir" 41 '[]' $'### Post-merge\n\n- [ ] waits <!-- verify-type: observation event=auto-run session=next -->\n' "[$(verify_fail_marker_comment 2026-01-02T01:00:00Z)]"
      verify_fail_fixture "$dir" 42 '[{"name":"phase/verify"}]' $'### Post-merge\n\n- [ ] <!-- verify: file_exists "a" --> open\n' "[$(verify_fail_marker_comment 2026-01-02T01:00:00Z)]"

      # With a session start, both Issues count
      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="41|42" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = $'#41 verify-fail-markers=1 unchecked-auto-conditions=0\n#42 verify-fail-markers=1 unchecked-auto-conditions=1' ]

      # Without one, the marker branch is off (41 drops out) but the unresolved-auto-condition branch still applies (42 stays)
      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="" BATCH_ISSUES_RE="41|42" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ "$output" = '#42 verify-fail-markers=0 unchecked-auto-conditions=1' ]

      # An empty target list prints nothing and does not call gh
      rm -f "$dir/calls.log"
      run env PATH="$dir/bin:$PATH" VF_DIR="$dir" session_start="2026-01-02T00:00:00Z" BATCH_ISSUES_RE="" bash -c "$cmd"
      [ "$status" -eq 0 ]
      [ -z "$output" ]
      [ ! -e "$dir/calls.log" ]
  }
  ````

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective: 前フェーズ (/issue) の自動解決ログ。未チェックの auto 条件を数えるコマンドと「この session 中」の取得方法を /spec の責務としたこと、AC1 への section_contains の併記、Post-merge の observation 条件の検証結果 (event=auto-run は語彙表にあり session=next も付与済み)、Background の事実確認 / https://github.com/saitoco/wholework/issues/1535#issuecomment-6214480354

## Code Retrospective

### Deviations from Design
- なし。`skills/auto/SKILL.md` の置き換えと `tests/auto.bats` の追加は、Spec の挿入文案ドラフトとテストドラフトをそのまま適用した (文言の調整なし)
- Implementation Steps 3 (`modules/verify-classifier.md` の Consumers 表): 採用。`skills/auto/SKILL.md` の行に「同じ 3 つのタグ (閉じタグまで) と `verify:` command の有無 (L3 notable 判定の未解決 auto 条件の判定)」を 1 句足した。理由: 新しい判定コマンドが 3 つのタグと `verify:` の有無を実際に読むため、表の記述と食い違う

### Design Gaps/Ambiguities
- なし。Spec のドラフトは `.tmp/` のコピーで検証済みと記載されており、実装時に追加の調整は不要だった
- bats は実行環境にインストール済みだったため、bats-absent AC 除外は適用していない (Pre-merge に bats を実行する AC もない)

### Rework
- なし

### Verification Record
- Confirmed pre-implementation FAIL for 5 new test(s): 実装前の `skills/auto/SKILL.md` を `.tmp/` に書き出し、`SKILL_FILE` を差し替えた一時コピーのテストで #33〜#37 の 5 件がすべて FAIL。実行後に一時コピーは削除した
- `bats tests/auto.bats`: 38 件 PASS。全スイート `bats --jobs 4 tests/`: 2255 件で `not ok` なし
- `validate-skill-syntax.py skills/`: 0 エラー・0 警告。`check-allowed-tools.sh`・`check-language-convention.py`・`check-forbidden-expressions.sh`: 問題なし。`check-bare-bracket-assertions.sh` の警告 1008 件は main と同数 (既存分で、追加分は含まない)
- 置き換えの削除行は対象の 1 行のみ。AC1 の `section_contains` 相当 (`type=verify-fail` の件数) は 4
- Pre-merge の 2 条件 (AC1・AC2) は検証済みとして Issue 本文でチェックを入れた。Post-merge の observation 条件は `session=next` のため未チェックのまま `/verify` に渡す

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の挿入文案ドラフトと bats ドラフトを文言変更なしで適用した (固定文字列を検査するテストとの整合を保つため)
- `modules/verify-classifier.md` の Consumers 表を 1 句更新した (新しい判定コマンドがタグと `verify:` の有無を読むため)

### Deferred Items
- Post-merge の observation 条件 (recovery・FAIL・kill が 0 件の 2 件 batch で `L3 session events committed (not notable — session.md skipped).` が出力される) は、変更反映後の会話セッションで該当 batch が走るまで未確認

### Notes for Next Phase
- Pre-merge の 2 条件はチェック済み。Post-merge は `event=auto-run session=next` の observation 条件で、該当 batch が実行されるまで SKIPPED のままとする設計
- 新しい判定コマンドは SKILL.md Step 5 の `gh issue view` を含む 2 番目の bash ブロック。テストは内容でブロックを選ぶので、ブロックの順序を変えない
