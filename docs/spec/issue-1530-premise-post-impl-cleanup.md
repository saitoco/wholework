# Issue #1530: premise: 実装の完了で意図的に崩れた前提の後始末の指針を決める

## Overview

`<!-- premise: ... -->` マーカーは「Issue の実装前のコードベース状態」を表すため、その Issue の実装が完了すると前提は意図的に崩れ、`check-premise-expiry.sh` は EXPIRED を返す (設計どおりの挙動)。`/audit premise` は `--state open` で取得するので CLOSED の Issue は既に対象外だが、実装がマージ済みで `/verify` 待ち (OPEN のまま `phase/verify`) の Issue は毎回 EXPIRED として報告されうる。実装済みの Issue が増えるほど、再トリアージが要る本物のシグナル (まだ直っていない前提の失効) と、ノイズ (直したから崩れた前提) が読み分けられなくなる。

Issue 本文は 2 方針の選択を `/spec` に委ねていた。本 Spec は次のとおり決める。

- **採用: 方針 1 (`/audit premise` の側で絞る)**。取得 JSON に `labels` を加え、`phase/verify` または `phase/done` ラベルの Issue (実装がマージ済み) を新規スクリプト `scripts/filter-premise-targets.sh` で評価対象から外す。外した Issue は Layer 1 / Layer 2 のどちらにも渡らず、除外した件数と Issue 番号を結果表の前に 1 行で出す。マーカーは Issue 本文に残し、書き換えない
- **不採用: 方針 2 (`/verify` の側で外す / `premise-resolved` に書き換える)**。`/verify` は `phase/done` への遷移と同じ手順で Issue を CLOSE し、`/audit premise` は OPEN のみ取得するため、書き換えたマーカーは二度と評価されない閉じた Issue の本文に載るだけで、`/audit premise` の報告ノイズは 1 件も減らない。マーカーは HTML コメントで、レンダリングされた Issue を読む人には見えないため、「後から読む人への明示」にもならない。そのうえ、`/verify` の完了ごとに Issue 本文への書き込み (L0 の mutation) が増え、最長の SKILL.md にも手順が増える
- いずれの方針でも必要な「マーカーを付ける側の説明」として、`skills/issue/SKILL.md` の Premise marker 節と、`scripts/check-premise-expiry.sh` のヘッダ (前提式の SSoT) に、完了後の扱いを明記する

不採用理由と採用方式の権威ある記録は、PR の diff に含まれる `skills/audit/SKILL.md` の premise Design Rationale に置く。rubric grader には Spec ファイルが渡されない (`modules/verify-executor.md` の `rubric` 行) ため、Spec だけに書くと AC から構造的に見えなくなる。本 Spec の記述はその控えである。

## Changed Files

- `scripts/filter-premise-targets.sh`: new file。`gh issue list --json number,title,body,labels` の JSON 配列を標準入力から受け取り、`phase/verify` または `phase/done` ラベルを持つ Issue を除いた配列を標準出力へ、除外した Issue を `EXCLUDED: #N (label)` 行として標準エラーへ出す。処理できない入力は警告付きで素通しし、常に exit 0 (fail-open)。bash 3.2+ 互換 (`mapfile` / `${VAR,,}` 不使用)、外部コマンドは `cat` と `jq` のみ
- `tests/filter-premise-targets.bats`: new file。除外の正例・負例、ラベル形状と類似ラベルの境界、特殊文字、fail-open、評価器 (`check-premise-expiry.sh`) と合成した検出力テスト (対照テスト付き)、`skills/audit/SKILL.md` との配線テストを含む
- `skills/audit/SKILL.md`: (1) frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/filter-premise-targets.sh:*` を追加 (`check-premise-expiry.sh:*` の直後)。(2) premise サブコマンドの Design Rationale に「Lifecycle after implementation」ブロックを追加。(3) premise の Step 1 (Context Collection) の取得を `labels` 付き + フィルタ経由に変更。(4) Step 2 Layer 2 に marker 化候補の寿命に関する注意を 1 文追加。(5) Step 3 に除外サマリー行の出力を追加
- `skills/issue/SKILL.md`: Step 4 の「Premise marker for codebase-state-dependent statements」節の末尾 (「Place the marker in a prose section ...」の段落の直後) に、実装の完了後にマーカーがどう扱われるかの段落を追加する。`allowed-tools` は変更しない (スクリプト呼び出しを伴わないため。本文では `${CLAUDE_PLUGIN_ROOT}/` 接頭辞なしの `scripts/...` 表記にとどめる — #1127 の Code Retrospective が記録した `validate-skill-syntax.py` の本文参照チェックを避けるため)
- `scripts/check-premise-expiry.sh`: ヘッダコメントのみ変更 (ロジック不変)。冒頭の SSoT 宣言を「前提式の文法と限界、およびマーカーの寿命」に広げ、「Lifecycle: when a marker stops being evaluated」の節を追加する。既存の `tests/check-premise-expiry.bats` は評価器の挙動が不変のため変更不要
- `docs/structure.md`: Key Files > Scripts > Tooling の `scripts/check-premise-expiry.sh` の行の直後に `scripts/filter-premise-targets.sh` の行を追加する。Directory Layout にはファイル数コメントを置かない方針 (同ファイルの Maintenance rule) なので数の更新は不要
- `docs/ja/structure.md`: [translation sync] `docs/structure.md` と同じ追加を日本語で反映する

**Steering Docs sync candidate** (最終的な include / exclude は `/code` が各ファイルを読んで判断する):

- `docs/workflow.md` と `docs/ja/workflow.md`: `/audit premise` を説明する 1 文が「open Issue 本文のマーカーを再評価する」とだけ述べている。`phase/verify` / `phase/done` の Issue は対象外になったので、括弧書きで加えるか判断する
- `docs/product.md` と `docs/ja/product.md`: Terms の `Premise marker` 行に「実装が完了すると評価されなくなる」旨の一文を加えるか判断する (行の記述は現状でも誤りではないため任意)
- [Steering Docs sync candidate] keyword "/audit premise" skipped: matched 16 files (no discriminating power) (測定範囲: `docs/ tests/ scripts/ modules/` 配下、固定文字列 `grep -rl -F` の一致ファイル数)
- keyword `check-premise-expiry.sh` (5 files、測定範囲は同上): `docs/structure.md` / `docs/ja/structure.md` の既存行は記述が引き続き正確なので変更不要 (隣に新規行を追加)。`tests/check-premise-expiry.bats` は評価器の挙動が不変のため変更不要。`docs/spec/issue-1127-*.md` は使い捨ての過去 Spec のため対象外
- keyword `Premise marker` (3 files): `docs/product.md` / `docs/ja/product.md` (上記候補) と過去 Spec のみ。keyword `premise-expired` (1 file): 過去 Spec のみで対象なし
- Listing-side sub-check (新規ファイルの追加に該当): 候補集合は `ssot_for` に `directory-layout` を持つ `docs/structure.md` とルートの `README.md`。`README.md` は `grep -n -i "audit\|premise\|scripts/" README.md CLAUDE.md` が 0 件のため変更不要 (`CLAUDE.md` も同じ grep で 0 件)
- `modules/`: `grep -rn "premise:\|audit premise\|premise-expired\|check-premise" modules/` が 0 件のため変更不要

## Implementation Steps

1. `scripts/filter-premise-targets.sh` を新規作成する (→ 受入条件 1)。

   **インターフェース**: `gh issue list --state open --json number,title,body,labels --limit 100 | scripts/filter-premise-targets.sh`。引数は取らない (引数があれば `Usage: filter-premise-targets.sh (reads a JSON array on stdin)` を標準エラーに出して exit 1)。標準入力は `gh issue list --json` が出力する JSON 配列 (各要素はオブジェクトで、`labels` は `name` を持つオブジェクトの配列)。標準出力は同じ配列から対象 Issue を除いたもの (`jq -c` のコンパクト形式、残した要素は無加工)。標準エラーは除外した Issue ごとに 1 行 `EXCLUDED: #<N> (<label>[,<label>])`。

   **除外条件**: `labels[].name` が `phase/verify` または `phase/done` と**完全一致**する Issue。`retro/verify` / `phase/verify-extra` / `Phase/Verify` / `not-phase/verify` のような類似名は除外しない (`retro/verify` は実在するラベルで名前に `verify` を含む点に注意)。

   **アルゴリズム (副作用の向きが紛らわしい手法を避け、手順を明示する)**:
   1. `INPUT="$(cat)"` で標準入力を読む
   2. `INPUT` が空または空白のみ (`[ -z "${INPUT//[[:space:]]/}" ]`) なら、標準エラーに `Warning: filter-premise-targets.sh: empty input — nothing to filter` を出し、標準出力には何も出さず exit 0
   3. `printf '%s' "$INPUT" | jq -e 'type == "array"' >/dev/null 2>&1` が非ゼロ (不正な JSON / 配列でない / `jq` が無い) なら、標準エラーに `Warning: filter-premise-targets.sh: input is not a JSON array (or jq is unavailable) — passing it through unfiltered` を出し、`printf '%s\n' "$INPUT"` で入力をそのまま標準出力へ出して exit 0
   4. jq の定義 (プロトタイプで検証済み): `def names: [ (.labels? // [])[]? | .name? // empty ]; def hits: [ names[] | select(. == "phase/verify" or . == "phase/done") ];`
   5. 残す配列: `jq -c "$JQ_DEFS"'[ .[] | select((hits | length) == 0) ]'`。失敗または空なら 3 と同じ警告と素通しで exit 0
   6. 除外行: `jq -r "$JQ_DEFS"'.[] | select((hits | length) > 0) | "EXCLUDED: #\(.number) (\(hits | join(",")))"'` の出力が空でなければ標準エラーへ出す
   7. 残す配列を `printf '%s\n'` で標準出力へ出し、exit 0

   `set -e` には頼らず (`set -uo pipefail`)、コマンド置換の失敗は `|| FILTERED=""` のように明示的に扱う。jq 1.5 以降で動く構文のみを使う (`def` / `select` / `//` / `.[]?` / `join` / `length`)。

   **分岐の挙動全列挙** (`skills/spec/skill-dev-constraints.md` の「ブランチ分岐ロジックの挙動全列挙」に準じる):
   - 正常終了条件: 標準入力が JSON 配列。標準出力 = 絞り込み後の配列、標準エラー = `EXCLUDED:` 行、exit 0
   - timeout 条件: なし。ネットワークや外部 I/O を持たず、標準入力と `jq` のみで完結する。呼び出し側 (Bash tool) の timeout に従う
   - kill 条件: なし。長時間ループを持たない
   - error path: 入力側の失敗はすべて「警告 + 素通し (空入力のみ空出力) + exit 0」。引数が渡された場合のみ exit 1
   - 監視継続: 該当なし (watchdog ではない)

   **fail-safe critical のエッジケース** (このスクリプトは「どの Issue を評価するか」を決めるゲートであり、失敗時の安全側の既定値 (素通し) を持つ):
   - 空入力 / 空白のみ: 上記 2。上流の `gh` 失敗で空になった場合に `[]` を出すと「前提マーカーなし」と誤読されるため、空出力 + 警告にする
   - 巨大入力: 上限を設けない。`gh issue list --limit 100` の本文つき出力を `jq` で一括処理する (bats に 300 件の入力ケースを置く)
   - 特殊文字: 本文の `>` / `"` / 改行 / CRLF / 多バイト文字はシェルに展開せず `jq` が JSON 文字列として往復させる。残した要素の `body` が入力と一致することをテストする
   - 依存コマンドの失敗: `jq` が無い / 失敗する場合は fail-open (素通し + 警告)。理由: 対象を誤って減らすと「失効した前提を見逃す」という本機構が防ごうとしている silent false negative を再生産する。失敗時に増えるのはノイズだけ
   - ラベル形状の異常 (`labels` が欠落 / `null` / 文字列配列 / オブジェクト、要素がオブジェクトでない): 除外せず残す (従来どおり評価される)

2. `tests/filter-premise-targets.bats` を新規作成する (after 1) (→ 受入条件 4, 5)。

   `check-premise-expiry.bats` と同じ `bats_require_minimum_version 1.5.0`、`PROJECT_ROOT` / `SCRIPT` の取り方、`run --separate-stderr` を使う。入力 JSON はクォートが多いので、`cat > "$BATS_TEST_TMPDIR/issues.json" <<'EOF'` でフィクスチャファイルに書き、`run --separate-stderr bash "$SCRIPT" < "$BATS_TEST_TMPDIR/issues.json"` で渡す。否定アサーションは `! cmd` ではなく `if ...; then false; fi` 形式にする (`docs/tech.md` の BATS 規約と #1292)。`WHOLEWORK_SCRIPT_DIR` のモックは不要 (このスクリプトを呼ぶスクリプトは無い)。

   カバーするケース (exhaustive):
   - 除外 (正例): `phase/verify` と `phase/done` の Issue が落ち、`phase/ready` / `phase/code` / ラベルなしの Issue が残る。標準出力は有効な JSON 配列で順序が保たれ、標準エラーに `EXCLUDED: #<N> (<label>)` が出る
   - 完全一致 (負例): `retro/verify` / `phase/verify-extra` / `Phase/Verify` / `not-phase/verify` だけを持つ Issue は除外されない
   - ラベル形状: `labels` 欠落 / `null` / `[]` / 文字列配列 / オブジェクトの Issue は残る。オブジェクトでない配列要素 (例: `42`) も残る
   - 残した要素が無加工: 要素の `jq -c` 表現が入力と一致する。`body` の `>` / `"` / 改行 / CRLF / 多バイト文字が往復で保たれる
   - 大きな入力: `jq -n` で 300 件 (各 1 KB 級の本文、3 件に 1 件が `phase/verify`) を生成し、残る件数と `EXCLUDED:` の行数が期待どおり
   - 空配列 `[]` → 標準出力 `[]`、`EXCLUDED:` なし、exit 0
   - fail-open: 空入力 / 空白のみ → exit 0、標準エラーに `Warning:`、標準出力は空。不正な JSON と、配列でない JSON (オブジェクト) → exit 0、標準出力が入力と一致、標準エラーに `Warning:`
   - fail-open (`jq` が無い): `cat` だけを symlink した一時ディレクトリを `PATH` に指定して実行 → exit 0、素通し、`Warning:`
   - usage: 引数あり → exit 1
   - **検出力テスト (崩れた前提 / 直っていない前提の読み分け)**: 使い捨ての git リポジトリ (`git init -q` + `git add`、commit 不要) に `sub/a.txt` (内容 `token here`) を置く。同一の本文 `<!-- premise: grep_count "token" "sub/" -eq 0 -->` を持つ 2 つの Issue (#201 は `phase/verify`、#202 は `phase/code`) の JSON をフィルタに通し、残った Issue の本文を `scripts/check-premise-expiry.sh` で評価して (`/audit premise` の Step 1 から Step 2 Layer 1 の流れの再現)、EXPIRED が報告されるのは #202 だけで、#201 は評価器に渡らないことを確認する
   - **対照テスト (検出力の担保)**: 同じ入力をフィルタの代わりに素通し (`cat`) に通すと、#201 と #202 の両方で EXPIRED が報告されることを確認する。検出力テストのアサーションが空振りでないこと (入力に本当に失効済みの前提が含まれること) を、スイート内で示す
   - 配線テスト: `load 'helpers/markdown-section'` を使い、`md_section "$AUDIT_SKILL" "## premise Subcommand"` で取り出した節に `--json number,title,body,labels` と `filter-premise-targets.sh` が含まれること、および `skills/audit/SKILL.md` に `${CLAUDE_PLUGIN_ROOT}/scripts/filter-premise-targets.sh:*` (frontmatter の `allowed-tools` 形式) があることを確認する。節の取り出しは `section="$(md_section ...)"` の素の代入で受け、見出しの改名でテストが静かに通らないようにする

   既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/filter-premise-targets.bats` の上記ケース) を追加したうえでスイートが PASS すること。実装前の状態 (フィルタが素通し) では検出力テストが FAIL することを、対照テストの結果で確認する。

3. `skills/audit/SKILL.md` を更新する (after 1) (→ 受入条件 1, 3)。

   編集アンカーに注意: `gh issue list --state open --json number,title,body --limit 100` の行は drift / fragility / premise の 3 か所に同一行がある (ファイル全体の `grep -n` で行 73 / 714 / 866)。premise の Step 1 は「`Fetch open Issues:`」の段落 (ファイル内で一意) で特定する。
   - frontmatter `allowed-tools`: `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh:*, ` の直後に `${CLAUDE_PLUGIN_ROOT}/scripts/filter-premise-targets.sh:*, ` を追加する
   - Design Rationale: `- **A folded into the `drift` subcommand** ...` の箇条書きの後、`**Detection scope and its limits**` の段落の前に、次の内容のブロックを追加する (英語、見出しは新設せず太字の見出し行 + 箇条書き)。内容: 「A premise marker describes the codebase state before the Issue's implementation, so implementing the Issue is expected to break it (e.g., a `grep_count ... -eq 10` premise reads 16 once the fix is merged). For an Issue whose implementation has landed, EXPIRED is therefore by design and carries no signal」。続けて 4 項目: **Adopted** (Step 1 が `scripts/filter-premise-targets.sh` で `phase/verify` / `phase/done` の Issue を Layer 1 / 2 の前に外す。CLOSED は `--state open` で既に対象外、残る隙間は `/verify` 待ちで OPEN のままの Issue。マーカーは本文に残し書き換えない)、**Rejected** (`/verify` が `phase/done` で書き換える案: `/verify` は同じ遷移で Issue を CLOSE し、本 subcommand は OPEN のみ取得するので、書き換えたマーカーは二度と評価されない閉じた Issue に載るだけで報告ノイズを減らさない。マーカーは HTML コメントでレンダリング時に見えないので後から読む人への明示にもならない。すべての `/verify` 完了に Issue 本文への書き込みを足し、最長の SKILL.md に手順を足すのに対して運用上の効果がない)、**Trade-off** (実装済み Issue の中で、Issue が意図的に変えない状態を表す前提 (Out of Scope の領域など) も監視されなくなる。そうした前提は、有効な前提として扱われるフォローアップ Issue に置く。`skills/issue/SKILL.md` が著者にそう案内する)、**Known limitation** (`/verify` は FAIL で Issue を reopen するとき `phase/*` ラベルをすべて外すので、fix cycle の間 (`/code` が `phase/*` を付け直すまで) は再び評価対象になり、部分的な修正で既に崩れた前提が EXPIRED と報告されうる)
   - Step 1: `Fetch open Issues:` の次のコードブロックを `gh issue list --state open --json number,title,body,labels --limit 100 | ${CLAUDE_PLUGIN_ROOT}/scripts/filter-premise-targets.sh` に置き換え、直後に説明を足す (英語): 標準出力が評価対象の Issue (同じ JSON 形)、標準エラーの `EXCLUDED: #<N> (<label>)` 行は除外した Issue (Step 3 のサマリー用に控える)、フィルタは fail-open (入力が JSON 配列でない / `jq` が使えないときは警告を出して入力をそのまま通すので、失敗してもノイズが増えるだけで失効した前提を隠さない)、取得そのものが失敗した場合 (gh のエラー) は空の結果を「マーカーなし」と報告せずエラーを報告して止まる、また 100 件の上限はフィルタの前に適用される (従来から)
   - Step 2 Layer 2: 末尾の「... cannot be mechanically evaluated.」の文の後に、marker 化候補を報告するときの注意を 1 文足す (英語): マーカーは Issue の実装が完了する (`phase/verify` に達する) まで評価されるだけなので、実装後も監視したい記述はこの Issue のマーカーではなくフォローアップ Issue に置くべき
   - Step 3: `Display a table:` のコードブロックの前に、`EXCLUDED:` 行が 1 件以上あったときだけ出す 1 行を足す (英語): `Excluded (implementation already landed): #<N1>, #<N2> (<count> Issues)`。これらの Issue は Layer 1 / 2 のどちらにも渡さず、表の行も持たない。`--dry-run` でも表示する
   - 半角 `!` を SKILL.md 本文のコードフェンス外に書かない。CJK 文字を入れない (language convention check の対象)

4. `skills/issue/SKILL.md` の Premise marker 節と `scripts/check-premise-expiry.sh` のヘッダを更新する (after 3) (→ 受入条件 2, 3)。

   3 か所 (audit の Design Rationale、issue の節、ヘッダ) の記述を矛盾させない。AC3 の rubric が 3 ファイルの一致を見る。
   - `skills/issue/SKILL.md`: 「Place the marker in a prose section ...」の段落の直後に、「**After the implementation lands:**」で始まる段落を追加する (英語)。内容: 前提は Issue の実装前の状態を表すので、実装すると意図的に崩れる (`grep_count ... -eq 10` が 16 になる例)。その時点の EXPIRED は設計どおりでシグナルではない。したがって `/audit premise` は Issue が `phase/verify` (実装がマージ済みで `/verify` 待ち) または `phase/done` に達するとマーカーを評価しなくなり、CLOSED の Issue は最初から評価されない。マーカーは本文に無加工で残り、剥がす処理も書き換える処理もなく `/verify` も編集しない。この Issue の実装後も監視し続けたい記述 (この Issue が意図的に変えない Out of Scope の領域についての前提など) は、この Issue のマーカーに頼らず、有効な前提として扱われるフォローアップ Issue に書く。`${CLAUDE_PLUGIN_ROOT}/scripts/` の完全形は本文に書かない
   - `scripts/check-premise-expiry.sh` ヘッダ: 冒頭の「SSoT for the supported premise expression syntax and its limits」を「... and for the marker's lifecycle after implementation (below)」の趣旨に広げ、末尾の `# bash 3.2+ compatible` 行の直前に「Lifecycle: when a marker stops being evaluated」の節を追加する (英語のコメント)。内容: このスクリプトは純粋な評価器で、渡された本文のマーカーをすべて評価し、その本文を持つ Issue のことを知らない。前提は実装前の状態を表し、実装で崩れるのが想定なので、実装済みの Issue の EXPIRED は設計どおりでシグナルではない。対象 Issue の選別は呼び出し側の責務で、`/audit premise` の Step 1 が `scripts/filter-premise-targets.sh` で `phase/verify` / `phase/done` の Issue を外し、CLOSED の Issue は取得されない。マーカーは書き換えも剥がしもされず、本文に残ったまま評価されなくなる (`/verify` で書き換える案は不採用で、理由は `skills/audit/SKILL.md` の premise Design Rationale)。実装後も監視したい前提は、その Issue のマーカーではなくフォローアップ Issue に置く
   - CJK 文字を入れない。ヘッダの既存の表・限界の記述は変更しない
   - 3 と 4 の編集後、CI と同じ検証を行う: `python3 scripts/validate-skill-syntax.py skills/` (本文のスクリプト参照と `allowed-tools` の整合、半角 `!` の検出)、および `git diff -U100000 origin/main...HEAD -- skills/ modules/ scripts/` の出力を `python3 scripts/check-language-convention.py` に通す (追加行の CJK 混入の検出)。`scripts/*.sh` は CI の macOS ジョブが `bash -n` で構文を確認するので、新スクリプトは bash 3.2 で構文が通ること

5. ドキュメントを同期する (after 1, 3, 4) (→ 受入条件 3 の整合維持)。

   - 必須: `docs/structure.md` の Key Files > Scripts > Tooling に `scripts/filter-premise-targets.sh` の行を追加する (`scripts/check-premise-expiry.sh` の行の直後)。内容: `/audit premise` 用に標準入力の `gh issue list --json number,title,body,labels` 配列から `phase/verify` / `phase/done` の Issue (実装が完了済みで前提は意図的に崩れている) を除き、`EXCLUDED: #N (label)` を標準エラーに出す。fail-open (空または解析不能な入力は警告付きで素通し、常に exit 0)。`/audit premise` Step 1 から呼ばれる。`docs/ja/structure.md` に同内容を日本語で反映する (`docs/translation-workflow.md` の Sync Procedure に従い、コードフェンス数の一致を確認する)
   - 任意 (候補を `/code` が読んで判断): `docs/workflow.md` / `docs/ja/workflow.md` の `/audit premise` の文に除外条件の括弧書き、`docs/product.md` / `docs/ja/product.md` の `Premise marker` 行に寿命の一文。足す場合は 3 か所の記述と矛盾させない
   - 同期後に `scripts/check-translation-sync.sh` で ja ミラーの整合を確認する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md の premise サブコマンド、または skills/verify/SKILL.md の phase/done への遷移のどちらかに、実装の完了によって崩れた前提を扱う手順がある" --> `/audit premise` の対象から外すか、`/verify` が `phase/done` で書き換えるか、どちらかの方針が実装されている
- <!-- verify: rubric "skills/issue/SKILL.md の Premise marker の節に、Issue の実装が完了して前提が崩れたあとマーカーがどう扱われるか (対象外になる / 書き換わる) の説明がある" --> `skills/issue/SKILL.md` の premise マーカーの節に、実装の完了後にマーカーがどう扱われるかが書かれている
- <!-- verify: rubric "scripts/check-premise-expiry.sh のヘッダコメントに、実装の完了によって崩れた前提がどう扱われるか (採用した方針) が明記されており、skills/audit/SKILL.md と skills/issue/SKILL.md の説明と一致している" --> `scripts/check-premise-expiry.sh` のヘッダの SSoT の説明が、採った方針と整合している
- <!-- verify: rubric "tests/ に、実装の完了によって崩れた前提の扱いを検証する新規テストケースが git diff に追加されている。追加されたテストは、実装が完了した Issue の (崩れた) 前提と、まだ実装が完了していない Issue の前提の両方を入力に使い、採用した方針の下では前者だけが評価対象から外れて後者は報告対象のまま残ることを検証しており、崩れた前提まで報告してしまう実装 (対象を絞らない実装) に対しては FAIL する形になっている" --> `tests/` に、実装の完了によって崩れた前提の扱いを検証する新規テストケースが増えている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存のテストを含む CI が通っている

### Post-merge

なし (Issue 本文のとおり)

## Notes

### 方針選定と記録の置き場所

- 方針 1 を採用し方針 2 を不採用とした理由は Overview のとおり。決め手は「`/verify` が同じ遷移で Issue を CLOSE する」こと。方針 2 の効果は閉じた Issue の本文に限られ、`/audit premise` の報告は変わらない。Issue 本文 (決めること 2) も同じ指摘を既に書いている
- 「両方」は採らない。方針 2 を足しても `/audit premise` の挙動は 1 つも変わらず、足す理由が「明示」だけになるが、HTML コメントは読む人に見えない
- rubric grader は Spec を見ないので、根拠は PR diff に含まれるファイルに置く (`skills/audit/SKILL.md` の Design Rationale が権威ある記録、`scripts/check-premise-expiry.sh` のヘッダが寿命の SSoT、`skills/issue/SKILL.md` が著者向けの案内)。#1127 の Spec Notes が同じ構造的事情を記録している
- フィルタを `check-premise-expiry.sh` の引数にせず別スクリプトにした理由: 評価器を「渡された本文のマーカーを評価するだけの純粋関数」に保つため。フィルタを別にすると、除外した Issue が Layer 1 / Layer 2 のどちらにも到達しないことが構造的に保証される (評価器に `--phase-label` を渡す案では Layer 2 (LLM 判断) の除外を SKILL.md の散文に頼ることになり、非決定的になる)。呼び出し形は `filter-session-verified-issues.sh` (標準入力のフィルタ、fail-open の素通し) の先例と、それを `skills/auto/SKILL.md` がパイプで呼ぶ先例に合わせた

### Issue 本文に加えた変更 (この /spec で実施)

`/issue` の Issue Retrospective が「Triage AC audit の修正案は `/spec` が取り込む想定」と明記しているため、Issue 本文の Acceptance Criteria を次のとおり修正した。要件 (何を満たすか) は変えず、verify command の検出力と書式だけを直した (`docs/product.md` の `/issue` (What) / `/spec` (How) の境界に抵触しない)。

1. AC2 と AC3 が改行なしで 1 行に連結していた (`... 説明がある" -->- [ ] \`scripts/check-premise-expiry.sh\` ...`) のを、別々の行に分けた。連結により行頭のチェックボックスが 4 件しか数えられず、AC3 は `gh-issue-edit.sh --checkbox` や `/verify` の AC 列挙から見えない状態だった (行頭 `^- \[[ xX]\]` の件数で 4 件から 5 件に回復)
2. AC3 の rubric を、現状でも「矛盾していない」を満たしてしまう常時 PASS の形から、採った方針がヘッダに明記されており audit / issue の説明と一致していることを要求する形に強化した (Triage AC audit の指摘と修正案のとおり。`modules/verify-patterns.md` §26 の「空振りの PASS を避ける」と同じ考え方)
3. AC4 の rubric に、検出力の要件 (崩れた前提と直っていない前提の両方を入力にし、対象を絞らない実装で FAIL する形) を加えた。Triage AC audit は別 AC の追加を提案したが、`/spec` の light の上限 (Pre-merge 5 件) を守るため、同じ新規テスト要件を扱う AC4 の rubric に統合した。rubric grader は Spec を見ないので、要件を Spec だけに置くと検証されない

### カットオフ前のコメントの扱い

Comment Consumption のカットオフ (直近の `phase/issue` 付与、`2026-10-16T00:59:58Z`) より前の 2 件 (Issue Retrospective と Triage AC audit) は消費対象外 (`## Consumed Comments` は "No new comments since last phase.")。ただし内容が AC の品質に直結するため背景として読み、上記の修正案を取り込んだ。

### 事実照合 (conflict なし)

Issue 本文 Background の主張をコードと照合し、すべて一致した。

- premise の Step 1 は `gh issue list --state open --json number,title,body` で OPEN のみ取得し、`labels` を含まない (`skills/audit/SKILL.md` の premise Step 1)
- `/verify` は `phase/done` への遷移と同じ手順で、`ISSUE_STATE` が `OPEN` のときに `gh issue close` する (`skills/verify/SKILL.md` Step 11 (a))
- `/audit premise` の Layer 2 は、マーカーの無い散文を marker 化候補として挙げる (Step 2)
- 参考実測: このリポジトリの現在の OPEN の Issue は 23 件で、うち `phase/verify` が 1 件、`phase/done` が 0 件 (`gh issue list --state open --label ...`、取得時点の値)。問題は件数の増加に伴って顕在化する性質で、現時点の規模では小さい

### 設計上のトレードオフと既知の制限

- 実装済み Issue の Out of Scope 領域などを表す前提も監視されなくなる (方針 1 の既知の欠点)。著者向け案内として、監視を続けたい前提はフォローアップ Issue に置くよう `skills/issue/SKILL.md` に書く
- `/verify` の FAIL で reopen された Issue は `phase/*` ラベルがすべて外れる (`skills/verify/SKILL.md` Step 11 (b))。fix cycle の間は再び評価対象になり、部分的な修正で崩れた前提が EXPIRED と報告されうる。軽微 (advisory な診断で、コメント投稿は式ごとに 1 回の重複防止つき) なため、追加の除外条件は設けない
- `gh issue list ... --limit 100` の上限はフィルタの前に適用される (従来から)。`phase/verify` の Issue が枠を使うと、評価される未実装 Issue が減りうる。サーバー側の `--search` 除外は検索インデックスの遅延と除外サマリーを失うため採らない
- 観測事項: `check-premise-expiry.sh` はコードフェンスやインラインコード内のマーカーのサンプルも実マーカーとして扱う。この Issue 自身の本文 (Background の説明とフェンス内のサンプル) を評価器に通すと `UNEVALUABLE` が 2 件出る (実測)。本 Issue の対象外 (式の文法と抽出の変更は Out of Scope) だが、サンプルを本文に書く Issue が `/audit premise` の表にノイズを足す。この Issue 自身は実装後に `phase/verify` に達するため、新しいフィルタで対象外になる

### 判定記録

- audit / investigation 型の Issue か: いいえ。既存項目を分類して判断根拠を残す調査ではなく、評価対象を絞る機能と指針の実装である。識別子の存在確認の追加ステップは不要 (ただし本 Spec に書いた識別子 — 行番号、ラベル名、ファイル名 — は `grep` / 実測で確認済み)
- fail-safe critical か: はい。フィルタは「どの Issue を評価するか」を決めるゲートで、失敗時の安全側の既定値 (素通し) を持つ。エッジケースは Implementation Steps の 1 に列挙した
- Tool detection pattern: `scripts/` に `command -v jq` の先例は無く (`grep -rn "command -v jq" scripts/` が 0 件)、既存スクリプトは `jq` を直接呼ぶ (`docs/tech.md` Key Dependencies が `jq` を挙げる)。新スクリプトは事前検出ではなく、`jq -e 'type == "array"'` の失敗で `jq` の欠如も含めて素通しにする
- allowed-tools impact chain: Case 1 (新規 `scripts/*.sh`)。新スクリプトを呼ぶ SKILL.md は `skills/audit/SKILL.md` のみ (`grep -rn "check-premise-expiry" scripts/ skills/` の呼び出し元は audit と、参照のみの issue)。audit の `allowed-tools` への追加は Changed Files に含めた。Case 2 (`modules/*.md` の変更) は該当しない
- `WHOLEWORK_SCRIPT_DIR` モック: 新スクリプトを呼ぶのは SKILL.md (LLM) のみでスクリプトは無いため不要
- 新ロジックの新規テスト要件: AC4 と Implementation Steps の 2 に記載。`/code` は新規テストケースを追加したうえでスイートが PASS することを確認する (light のため `## spec retrospective` は書かず、この Notes に記録)
- Size 再評価: M 維持。Changed Files の素の件数は 7 (必須) だが、実質的な実装・検証対象は 5 ファイル (新規 2、変更 3) で、残り 2 件は structure.md の 1 行追加とその ja ミラー。複雑さは、複数スキルにまたがる + スクリプトの新規ロジック (+1) と、`filter-session-verified-issues.sh` と既存の premise 節の横展開 (-1) で相殺する。同型の #1349 (8 件) は M、#1127 (ja ミラー込みで 12 件、新サブコマンドと新文法) は L だった。route は `pr` (`ALWAYS_PR` は未設定)

### bats テストの入力形式

フィルタの入力は `gh issue list --json number,title,body,labels` と同じ形の JSON 配列。

```json
[
  {"number": 101, "title": "pending", "body": "text", "labels": [{"name": "phase/ready"}, {"name": "triaged"}]},
  {"number": 102, "title": "landed", "body": "text", "labels": [{"name": "phase/verify"}, {"name": "retro/verify"}]},
  {"number": 103, "title": "no labels key", "body": "text"}
]
```

期待: 標準出力は #101 と #103 の要素 (入力と同一)、標準エラーは `EXCLUDED: #102 (phase/verify)`。検出力テストは、`grep_count "token" "sub/" -eq 0` の前提が失効する使い捨て git リポジトリを用意し、同一本文の Issue を `phase/verify` / `phase/code` の 2 件にして評価器の EXPIRED 報告対象を比べる。

### Uncertainties

- **`gh ... | script` のパイプが audit スキルの permission で通るか**: `skills/auto/SKILL.md` が `printf ... | "${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh" ...` を同じ形で呼ぶ先例があり、`gh issue list:*` と新スクリプトの両方が `allowed-tools` に入るため通る見込み。マージ後の最初の `/audit premise --dry-run` で確認する。通らなければ 2 コマンドに分ける (影響範囲: Implementation Steps 3)
- **jq 1.6 / 1.7 の差**: プロトタイプは jq 1.7 で検証。式は jq 1.5 以降の構文のみで、CI (ubuntu / macOS) の bats で確認される (影響範囲: Implementation Steps 1, 2)
- **スクリプト全体のアルゴリズム (Implementation Steps 1)**: 検証済み。使い捨てのプロトタイプ (`.tmp/`、検証後に削除) を 8 ケース (正常 / 空入力 / 空白のみ / `[]` / 不正 JSON / 非配列 JSON / `jq` 欠如 (`PATH` に `cat` だけ) / 引数あり) で実行し、いずれも本 Spec の記述どおりの exit code・標準出力・標準エラーになることを確認した。`>` / `"` / CRLF / 多バイト文字を含む本文は往復で保たれ、外部コマンドは `cat` と `jq` のみで足りる (`jq` が無い場合も fail-open で素通しになる)
- **`gh issue list --json labels` の形状**: 検証済み。`gh` 2.101.0 のヘルプが `labels` を JSON フィールドに挙げ、実出力は `[{"color","description","id","name"}]` (出所: このリポジトリの `gh issue list --state open --json number,labels --limit 2`、取得日 2026-10-16)

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- Spec の Implementation Steps からの逸脱はない。任意とされた `docs/workflow.md` / `docs/ja/workflow.md` の括弧書きと `docs/product.md` / `docs/ja/product.md` の `Premise marker` 行の一文は、3 か所の説明と矛盾しない短い追記として含めた

### Design Gaps/Ambiguities
- Spec の Step 3 は Step 1 の説明に「取得そのものが失敗したときはエラーで止まる」を求めていたが、パイプ (`gh ... | filter`) では `gh` の失敗がフィルタの空入力として届く。フィルタは空入力で警告 + 空出力にするため、SKILL.md 側の「空の結果を『マーカーなし』と報告しない」という指示と組み合わせて機能する。両者が揃って初めて silent false negative を防げる点を Step 1 の記述に残した
- `check-premise-expiry.sh` の冒頭 SSoT 文は、括弧書きが 2 つ連続する形になった (「... lifecycle ... (see "Lifecycle" below) (referenced by ...」)。意味は通るが読みやすさは落ちる。ヘッダ全体の再構成は Spec の範囲外なので留めた

### Rework
- 検出力テストで使う評価器の呼び出しを、worktree isolation guard の制約 (`$(...)` や複合コマンドの拒否) に合わせて単純なコマンドに分ける作業が複数回発生した。bats 本体はガードの対象外だが、スモークテストの手順で分割が必要だった

### Test Notes
- Confirmed pre-implementation FAIL for 2 new test(s): 配線テスト (audit premise 節の `--json number,title,body,labels` / `filter-premise-targets.sh`、`allowed-tools` の追記) は SKILL.md 更新前の実行で FAIL した。検出力テストは、対照テスト (フィルタを `cat` に置換) で #201 / #202 の両方が EXPIRED になることを示し、入力に失効済みの前提が実際に含まれていることを確認した
- フルスイート `bats --jobs 4 tests/` (2243 件) は FAIL なし
- rubric AC 4 件は独立した grader サブエージェント (敵対的な指示、Spec 非公開) で判定し、すべて PASS。AC 5 (`github_check "gh pr checks"`) は PR 作成前のため Step 10 の対象外とし、未チェックのまま `/review` に委ねる

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の Implementation Steps と PR の差分に構造的な乖離はなかった。除外条件・fail-open の分岐表・テスト範囲・SKILL.md / docs の更新が Spec どおりに入っている

### Recurring issues
- 指摘事項なし (MUST / SHOULD / CONSIDER いずれも 0 件)。`review-light` のサブエージェントが結果を返さずバックグラウンド化したため、orchestrator が 4 観点を自前で実施した (Sub-agent Result Fallback)。軽量レビューの実行形態に起因する事象で、PR の内容とは無関係

### Acceptance criteria verification difficulty
- AC 5 件すべて PASS。rubric 4 件は差分の内容で判定でき、`github_check "gh pr checks" "Run bats tests"` は PR 作成後の CI 結果で確定した (UNCERTAIN なし)
- `gh pr view --json authorAssociation` は存在しないフィールドで失敗する。投稿者の trust 判定は `gh api repos/{owner}/{repo}/pulls/<N> --jq .author_association` で行う必要があった

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- `review-light` は結果を返さなかったため、orchestrator が 4 観点を自前で実施し、指摘 0 件で COMMENT として投稿した
- Parser/Validator のエッジケース事前確認は、対象が `filter-premise-targets.sh` の 1 ファイルのみだったため、サブエージェントを使わず orchestrator がリポジトリルート以外の CWD から直接実行した (メタ文字・入れ子配列ラベルで期待どおりの挙動)

### Deferred Items
- マージ後の最初の `/audit premise --dry-run` で、`gh issue list ... | filter` のパイプが audit の permission で通るかを確認する (code フェーズから引き継ぎ。Spec の Uncertainties)
- `/verify` の FAIL で reopen された Issue は fix cycle の間再び評価対象になる (Spec の既知の制限)

### Notes for Next Phase
- AC 5 件はすべて `[x]`。Post-merge の条件はなし
- CI は 17 チェックすべて成功、base ブランチとの競合なし。`/merge 1532` に進める
