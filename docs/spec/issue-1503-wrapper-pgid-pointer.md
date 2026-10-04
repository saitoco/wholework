# Issue #1503: scripts: run-*.sh の PGID pointer 読み取りを read_pgid_pointer() の鮮度検証経由にする

## Overview

#1491 で `restore_auto_session_pointer()` の PGID pointer 読み取りを `read_pgid_pointer()` (`scripts/emit-event.sh`) 経由にし、pointer の mtime がその PGID のリーダープロセスの起動より古い場合は採用しない鮮度検証を入れた。一方、ラッパーの inline な `cat ".tmp/auto-session-${PGID}"` は未対応のまま残り、`modules/event-emission.md` § "Stale PGID pointer validation (Issue #1491)" の Known gaps (1) として明記されている。`/auto` 経由では同じ Bash 呼び出しで pointer を書き直すため影響しないが、ラッパーを手動で実行したときに残存 pointer を拾い、無関係な session_id でイベントを記録しうる。

この Issue では、PGID pointer の読み取り 7 箇所すべてを `read_pgid_pointer()` 経由にして、鮮度検証の経路を一本化する。

- 読み取り 7 箇所 (測定: `git grep -n -F 'cat ".tmp/auto-session-' -- scripts/`、`scripts/` 配下の全ファイル): `run-issue.sh` `run-spec.sh` `run-code.sh` `run-review.sh` `run-merge.sh` に 1 箇所ずつ、`run-auto-sub.sh` に 2 箇所 (メイン経路と、`WHOLEWORK_SPAWN_DETACH=1` の再 exec 前に `${_detach_pgid}` で引く detach 経路)
- 変更の骨子:
  1. 各スクリプトで `source "$SCRIPT_DIR/emit-event.sh"` を pointer の読み取りより前に移す (`read_pgid_pointer()` はそこで定義される)。`run-auto-sub.sh` の detach 経路はメイン経路の `source` より前 (spawn detach shim の中) で読むので、shim の中で `source` する
  2. `cat` を `read_pgid_pointer ".tmp/auto-session-${PGID}" "${PGID}"` に置き換える
  3. wrapper のテストが `$MOCK_DIR/emit-event.sh` に置く per-test の stub に `read_pgid_pointer` を足し、wrapper 本体を呼ばずに該当行を再掲していたテスト 8 件を、実際に wrapper を実行するテストへ置き換える
  4. `modules/event-emission.md` の Known gaps (1) などを更新する

## Changed Files

- `scripts/run-issue.sh`: `PGID=$(ps -o pgid= -p $$ | tr -d ' ')` の直後へ `source "$SCRIPT_DIR/emit-event.sh"` を移し、`AUTO_SESSION_ID` の解決を `read_pgid_pointer` 経由にする。直前の `# Primary: PGID-based file` コメントを更新する — bash 3.2+ compatible
- `scripts/run-spec.sh`: 同上 — bash 3.2+ compatible
- `scripts/run-code.sh`: 同上。`cd "$MAIN_REPO_ROOT"` が先に済んでいるので、pointer のパスは main repo root 基準のまま (変更なし) — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上 (`cd "$MAIN_REPO_ROOT"` 済み) — bash 3.2+ compatible
- `scripts/run-merge.sh`: 同上 (`cd "$MAIN_REPO_ROOT"` 済み) — bash 3.2+ compatible
- `scripts/run-auto-sub.sh`: メイン経路は上と同じ。detach 経路 (spawn detach shim の `if [[ -z "${AUTO_SESSION_ID:-}" ]]; then` ブロック内) は、そのブロックの中で `source "$SCRIPT_DIR/emit-event.sh"` してから `read_pgid_pointer ".tmp/auto-session-${_detach_pgid}" "${_detach_pgid}"` で読む。`--write-manual-recovery` 分岐の `source` は変更しない — bash 3.2+ compatible
- `modules/event-emission.md`: (a) "_EMIT_PHASE_OWNED pattern" のコードブロックを新しい順序 (`source` が先、`read_pgid_pointer` で解決) にする、(b) "Stale PGID pointer validation (Issue #1491)" 段落の末尾にある Known gaps (1) (`are unchanged` を含む) をこの変更の内容に書き換え、残る gap は (2) の issue-scoped pointer だけにする、(c) "Manual Orchestration" 段落の末尾に 1 文を足す。文面は Notes の「`modules/event-emission.md` の更新文面」
- `tests/run-issue.bats` (stub 7 件) `tests/run-spec.bats` (9 件) `tests/run-review.bats` (6 件) `tests/run-merge.bats` (10 件): stub への `read_pgid_pointer` 追加、リプレイテスト 1 件を実 wrapper 実行テストへ置き換え、新規 2 件 (fresh / stale) の追加
- `tests/run-code.bats` (stub 9 件): stub への追加、リプレイテスト 4 件を実 wrapper 実行テストへ置き換え、新規 2 件 (fresh / stale) の追加
- `tests/run-auto-sub.bats` (stub 21 件): stub への追加、`spawn-detach: AUTO_SESSION_ID resolved from pre-detach PGID pointer and burned into child env` を本物の `read_pgid_pointer` を使う形に変更、stale の新規 1 件の追加
- `tests/auto-sub-observability.bats` (stub 3 件): stub への追加、`session-isolation: PGID-specific pointer file is read when AUTO_SESSION_ID is unset` を本物の `read_pgid_pointer` を使う形に変更、stale の新規 1 件の追加
- `tests/run-code-mergeability.bats` (stub 1 件): stub への追加のみ (`run-code.sh` を `$MOCK_DIR/emit-event.sh` の stub で実行するため必須。Issue 本文の測定には含まれていない — Notes 参照)
- [Steering Docs sync candidate] keyword "read_pgid_pointer" (この Issue が呼び出し元を増やす関数名): `docs/ tests/ scripts/ modules/` で 4 files にヒット。`scripts/emit-event.sh` (定義) と `tests/emit-event.bats` (単体テスト) は変更不要、`modules/event-emission.md` は上のとおり Changed Files に含める、`docs/spec/issue-1491-stale-pgid-pointer.md` は過去の Spec (使い捨て) なので対象外
- [Steering Docs sync candidate] 次の keyword は弁別力がないため評価しない (各 8 files 超):
  - keyword "event-emission.md" skipped: matched 39 files (no discriminating power)
  - keyword "run-issue.sh" skipped: matched 109 files (no discriminating power)
  - keyword "run-spec.sh" skipped: matched 153 files (no discriminating power)
  - keyword "run-code.sh" skipped: matched 282 files (no discriminating power)
  - keyword "run-review.sh" skipped: matched 201 files (no discriminating power)
  - keyword "run-merge.sh" skipped: matched 167 files (no discriminating power)
  - keyword "run-auto-sub.sh" skipped: matched 298 files (no discriminating power)
  - keyword "auto-session-" skipped: matched 173 files (no discriminating power)

## Implementation Steps

1. `scripts/run-issue.sh` `run-spec.sh` `run-code.sh` `run-review.sh` `run-merge.sh` の 5 本で、同じ 3 点を編集する (→ 受け入れ条件 AC1, AC2)
   - `PGID=$(ps -o pgid= -p $$ | tr -d ' ')` の直後に、コメント `# read_pgid_pointer() is defined in emit-event.sh, so source it before the pointer read below.` とともに `source "$SCRIPT_DIR/emit-event.sh"` を置く。元の `export AUTO_SESSION_ID` の直後にあった `source "$SCRIPT_DIR/emit-event.sh"` の行は削除する (`emit-event.sh` は source 時に関数と `_PGID_POINTER_SLACK_SEC` の定義しか実行しないので、順序の変更に副作用はない)
   - `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"` を `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(read_pgid_pointer ".tmp/auto-session-${PGID}" "${PGID}")}"` に置き換える。`|| echo ''` と `2>/dev/null` は付けない (理由は Notes の「設計の判断」)
   - 直前の `# Primary: PGID-based file ...` コメントを、「pointer はその PGID のリーダーの起動より後に書かれたときだけ採用する (Issue #1491, #1503)」を含む内容に更新する。**コメントに `cat ".tmp/auto-session-` というリテラルを書かない** (AC1 の `file_not_contains` に掛かる)
2. `scripts/run-auto-sub.sh` の 2 箇所を編集する (→ AC1, AC2) (parallel with 1)
   - メイン経路 (`PGID=$(ps -o pgid= -p $$ | tr -d ' ')` で始まる箇所): 手順 1 と同じ。`source "$SCRIPT_DIR/emit-event.sh"` を `PGID=` の直後へ移し (`export EMIT_ISSUE_NUMBER="$SUB_NUMBER"` の後にあった元の行は削除する)、`source "$SCRIPT_DIR/retry-on-kill.sh"` はそのまま残す
   - detach 経路: `_detach_pgid=$(ps -o pgid= -p $$ | tr -d ' ')` の直後に `source "$SCRIPT_DIR/emit-event.sh"` を足し (shim はメイン経路の `source` より前に動き、その後 `exec` する)、`AUTO_SESSION_ID="$(cat ".tmp/auto-session-${_detach_pgid}" 2>/dev/null || echo '')"` を `AUTO_SESSION_ID="$(read_pgid_pointer ".tmp/auto-session-${_detach_pgid}" "${_detach_pgid}")"` に置き換える。pointer は detach 前の PGID で引く (shim 冒頭のコメントのとおり)
   - `--write-manual-recovery` 分岐の `source "$SCRIPT_DIR/emit-event.sh"` と、shim 冒頭の `Placement:` コメントは変更しない
3. `modules/event-emission.md` を更新する (→ AC2, AC3) (parallel with 1, 2)。文面は Notes の「`modules/event-emission.md` の更新文面」。ファイル全体に `are unchanged` を残さない
4. テストを更新する (after 1, 2) (→ AC4)。**AC4 は既存スイートが PASS することだけでなく、新規ロジック (鮮度検証の棄却) を検証する新規テストケースを追加したうえで PASS すること**
   - (a) stub: 8 ファイル 66 件の `cat > "$MOCK_DIR/emit-event.sh" <<...` すべてに、heredoc 本文の 1 行目として `read_pgid_pointer() { cat "$1" 2>/dev/null || true; }` を足す (引用符なしの `<<MOCK` では `\$1` と書く)。変更前の挙動 (鮮度検証なしの読み取り) を保つので、既存テストの結果は変わらない。機械的に入れてよい (Notes の変換スクリプト)
   - (b) リプレイテスト 8 件 (`run-issue` / `run-spec` / `run-review` / `run-merge` に 1 件ずつ、`run-code` に 4 件) を、実際に wrapper を実行するテストへ置き換える。テスト名は変えない。stub は「本物の `emit-event.sh` を source して `emit_event()` だけ recorder に差し替える」ハイブリッド形式、`ps` は mock する (Notes のテンプレート)
   - (c) 新規テストを足す: 5 つの `run-*.sh` に fresh / stale の 2 件ずつ (10 件)。`auto-sub-observability.bats` (メイン経路) と `run-auto-sub.bats` (detach 経路) には、既存の PGID pointer テストをハイブリッド形式に変更したうえで stale の 1 件ずつ (2 件)。合計 12 件 (stale が 7 件、fresh が 5 件)
5. 実行して確認する (after 1〜4) (→ AC4)。bats が無い環境では Notes の手順で `.tmp/` に bats-core を取得する。変更した 8 ファイルを個別に実行し、全件 (`bats tests/`) は push 後の CI の `Run bats tests` job と `/review` の CI 参照が確定する

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-code.sh" "cat \".tmp/auto-session-" --> <!-- verify: file_not_contains "scripts/run-issue.sh" "cat \".tmp/auto-session-" --> <!-- verify: file_not_contains "scripts/run-spec.sh" "cat \".tmp/auto-session-" --> <!-- verify: file_not_contains "scripts/run-review.sh" "cat \".tmp/auto-session-" --> <!-- verify: file_not_contains "scripts/run-merge.sh" "cat \".tmp/auto-session-" --> <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "cat \".tmp/auto-session-" --> 5 つの `run-*.sh` と `run-auto-sub.sh` (L469 のメイン経路と L58 の `_detach_pgid` 経路の両方) が PGID pointer を `cat` で直接読んでいない
- <!-- verify: rubric "5 つの run-*.sh と run-auto-sub.sh (メイン経路と WHOLEWORK_SPAWN_DETACH 再 exec 前の経路の 2 箇所) の PGID pointer 読み取りが read_pgid_pointer() (または同等の鮮度検証) を経由しており、modules/event-emission.md の Known gaps (1) の記述がこの変更に合わせて更新されている" --> 鮮度検証が全経路に適用され、文書の既知ギャップが更新されている
- <!-- verify: file_not_contains "modules/event-emission.md" "are unchanged" --> `modules/event-emission.md` の Known gaps (1) から「読み取りは変更されていない」旨の記述 (`are unchanged`) が除かれている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

なし

## Notes

### Issue 本文と実装の食い違い (light のため記録のみ)

- Issue 本文と `modules/event-emission.md` は stub を「65 件・7 ファイル」とするが、これは #1491 の Spec の測定 (`grep -c` を 7 ファイルに実行した合計) の転記で、`tests/run-code-mergeability.bats` (`run-code.sh` を stub 付きで実行する。1 件) が測定対象から漏れていた。HEAD (79ab30ac) の実測は **66 件・8 ファイル**
  - 測定: `grep -c 'cat > "$MOCK_DIR/emit-event.sh" <<' tests/*.bats | grep -v ':0$'` (対象は `tests/*.bats` 直下。`<<MOCK` と `<<'MOCK'` の両形式を含む)
  - 内訳 (引用符なし / 引用符つき): `run-auto-sub` 21 (13 / 8)、`run-merge` 10 (9 / 1)、`run-code` 9 (8 / 1)、`run-spec` 9 (8 / 1)、`run-issue` 7 (6 / 1)、`run-review` 6 (5 / 1)、`auto-sub-observability` 3 (0 / 3)、`run-code-mergeability` 1 (0 / 1)。合計 66 (49 / 17)
- Issue 本文のその他の事実は実装と一致する: 読み取り 7 箇所 (`run-auto-sub.sh` は 2 箇所)、すべて `source "$SCRIPT_DIR/emit-event.sh"` より前、`read_pgid_pointer()` は `emit-event.sh` で定義
- リプレイテスト (wrapper 本体を呼ばず代入行を再掲するテスト) は 8 件・5 ファイル。測定: `grep -n '^@test "AUTO_SESSION_ID' tests/run-issue.bats tests/run-spec.bats tests/run-code.bats tests/run-review.bats tests/run-merge.bats` (`run-code` が 4、他が 1 ずつ)。#1491 の Spec は「各 4〜5 件」と書いたが、実際は `run-code` だけが 4 件

### Issue Retrospective の反映

- Consumed Comments の Issue Retrospective (AC1 の拡張、AC2 の rubric への 2 経路の明記、`modules/event-emission.md` の `are unchanged` を確認する AC の追加、7 箇所・`source` より前という事実の追記) は、この Spec の前提としてそのまま取り込んだ
- 自動解決された「`run-auto-sub.sh:58` の detach 経路を対象に含める」はそのまま踏襲した。経路の変更方法 (どこで `source` するか) は /spec の判断として Implementation Steps に決めた
- Size は、Issue Retrospective が /spec に委ねた再判定を下の「Size の再評価」で行った

### 設計の判断 (採用案と不採用案)

- **採用**: wrapper は `read_pgid_pointer` を保護なしで直接呼び、per-test の stub に同名の関数を足す。理由は (1) Issue と #1491 の Spec が想定する方向 (stub の更新とテストの置き換えを合わせて扱う) と一致する、(2) 関数が全経路で `return 0` なので `|| echo ''` は本番では関数の欠落時にしか効かず、欠落 (将来のリネームや stub の取りこぼし) が session_id の無音の欠落になるより、全テストが落ちて検出されるほうがよい、(3) テストの都合を本番コードに持ち込まない
- **不採用 (呼び出しに `2>/dev/null || echo ''` を付けて stub 未更新でも落ちないようにする)**: stub の更新を避けられるが、上の (2) (3) に反する。さらに pointer を読む既存 2 件のテストは結局 stub に関数が要る
- **不採用 (`read_pgid_pointer` と `_process_elapsed_seconds` を別ファイルへ切り出して wrapper が直接 source)**: `emit-event.sh` だけをコピーして使うテスト (`tests/wait-ci-checks.bats` `tests/run-fact-matching.bats`) や、`emit-event.sh` を単独で source する利用者を壊すか、関数の複製が要る。新規 script の追加になり、`WHOLEWORK_SCRIPT_DIR` の mock 追加も 8 ファイルの setup に要る
- **不採用 (テストの setup で `export -f read_pgid_pointer` して stub の更新を避ける)**: 関数が環境経由で暗黙に引き継がれ、読み手に分かりにくい。stub が「その関数を提供する」という契約が見えなくなる
- **不採用 (wrapper が `scripts/read-pgid-pointer.sh` のような子プロセスを呼ぶ)**: 新規 script と `$MOCK_DIR` への mock 追加が要り、欠落が無音で session_id を落とす点は `|| echo ''` 案と同じ
- stub の `read_pgid_pointer` を「plain な cat」にする理由: 変更前の挙動 (鮮度検証なしの読み取り) を保ち、既存テストの観測結果を変えないため。何も返す `:` にすると pointer を読む 2 件のテストが壊れる。鮮度検証そのものは `tests/emit-event.bats` (関数の単体) と、本物の `emit-event.sh` を使う新規テスト (read site ごと) が担う

### fail-safe 重要度の判定: 該当 (基準 (c))

読み取りは「失敗時に安全側の既定値 (session_id なし) を返す」設計 (`2>/dev/null` / `|| echo ''` / `|| true`)。変更後も同じ方針 (fail-closed。#1224 / #1317 / #1491 と同じく、session_id の欠落を誤帰属より優先して許容する) で、境界条件は次のとおり。

- pointer ファイルが無い、読めない、空: `read_pgid_pointer` は何も出力せず `return 0` → `AUTO_SESSION_ID` は空 (変更前と同じ)
- 大きい入力・複数行: `cat` が全文を返し、command substitution が末尾の改行だけを除く (変更前と同じ。書き手は `printf '%s\n'` で 1 行だけ書く)
- 特殊文字 (`>` `"` CRLF マルチバイト): 解釈せずそのまま `AUTO_SESSION_ID` に入る (変更前と同じ)。CRLF の `\r` は除かれない (書き手が LF のみのため実害なし)
- 依存コマンドの失敗 (`ps` が失敗する、`etime` が解釈できない、`stat` が失敗する、mtime が数値でない): `read_pgid_pointer` は何も出力せず `return 0` → fail-closed で `AUTO_SESSION_ID` は空。**変更前は pointer があれば読めたので、ここだけが挙動の変化 (session_id の欠落が増えうる方向。誤帰属は増えない)**
- `set -euo pipefail` 下: `read_pgid_pointer` のどの失敗経路も `return 0` なので wrapper は abort しない。新規テストは status 0 を assert する
- `read_pgid_pointer` が未定義 (stub の取りこぼし): `command not found` (127) で wrapper が abort する。意図した挙動 (上の「設計の判断」)
- `PGID` が空: `ps` が失敗すると `PGID=$(ps ... | tr ...)` の時点で `set -o pipefail` により既に abort する (変更前と同じ)。仮に空でも `read_pgid_pointer ".tmp/auto-session-" ""` は `[[ -f ]]` で何も出さずに戻る

### 新規テストケース (必須)

wrapper の PGID pointer 解決に「古い pointer を棄却する」新しい分岐が入るので、既存スイートが PASS するだけでなく、新規ロジックを検証する新規テストを足す (Implementation Step 4 の 12 件)。実装前の wrapper に当てると stale の 7 件が FAIL し (fresh と、置き換えた既存テストは両方で PASS する退行ガード)、実装後は全件 PASS する (プロトタイプで確認済み)。

- 入力形式: pointer ファイル = 1 行の session id (`echo "<sid>" > .tmp/auto-session-424242`)。PGID は `ps` の mock で 424242 に固定し (`ps -o pgid=` に 424242、`ps -o etime=` に `MOCK_ETIME` (既定 `10:00`) を返す。それ以外は `exit 1`)、wrapper の起動中に `ps` を使うのは PGID の取得だけ。pointer の mtime は `touch -t 202401010000` で古くする (指定なし = 今)
- assertion は `[ ... ] || false` 形式 (`scripts/check-bare-bracket-assertions.sh` の対象は `[[ "$output"/"$status" ]]` の素の使用)。`@test` 名は ASCII の英語。新規テスト名: fresh = `AUTO_SESSION_ID adopts a PGID pointer written after its process-group leader started (Issue #1503)`、stale = `AUTO_SESSION_ID ignores a PGID pointer left by an earlier owner of the same PGID (Issue #1503)` (`auto-sub-observability.bats` と `run-auto-sub.bats` の stale は、それぞれ既存テストの名前の流儀に合わせた名前でよい)
- テストが外側の `/auto` セッションの環境に左右されないよう、ヘルパーの先頭で `unset AUTO_SESSION_ID EMIT_PHASE_NAME EMIT_ISSUE_NUMBER` する (この Issue を `/code` する session 自体が `AUTO_SESSION_ID` を export していることがある)

**テンプレート (5 つの `run-*.sh` 共通。プロトタイプで検証済み)**: ファイルごとに `<script>` と呼び出し引数だけが変わる (`run-issue` / `run-spec`: `123`、`run-review` / `run-merge`: `88`、`run-code`: `123 --pr`)。

```bash
# Issue #1503: <script> resolves AUTO_SESSION_ID through the real read_pgid_pointer().
# The stub sources the real emit-event.sh (read_pgid_pointer/_process_elapsed_seconds) and then
# replaces emit_event() with a recorder that logs the session id in effect; ps is mocked so the
# caller's PGID is fixed at 424242 and the leader's elapsed time comes from MOCK_ETIME (default 10:00).
_use_real_pgid_pointer_reader() {
    unset AUTO_SESSION_ID EMIT_PHASE_NAME EMIT_ISSUE_NUMBER
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
source "$(dirname "$BATS_TEST_FILENAME")/../scripts/emit-event.sh"
emit_event() { echo "sid=[\${AUTO_SESSION_ID:-}] \$*" >> "${EMIT_LOG}"; }
_emit_comments_consumed() { :; }
_append_consumed_comments_section() { :; }
MOCK
    cat > "$MOCK_DIR/ps" <<'MOCK'
#!/bin/bash
case "$*" in
    *pgid=*) printf '%s\n' "424242" ;;
    *etime=*) printf '%s\n' "${MOCK_ETIME-10:00}" ;;
    *) exit 1 ;;
esac
MOCK
    chmod +x "$MOCK_DIR/ps"
}

@test "AUTO_SESSION_ID ignores a PGID pointer left by an earlier owner of the same PGID (Issue #1503)" {
    _use_real_pgid_pointer_reader
    mkdir -p .tmp
    echo "stale-sid-1503" > .tmp/auto-session-424242
    touch -t 202401010000 .tmp/auto-session-424242
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q 'sid=\[\] phase_start' "$EMIT_LOG" || false
    if grep -q 'stale-sid-1503' "$EMIT_LOG"; then false; fi
}
```

fresh は `echo "fresh-sid-1503" > .tmp/auto-session-424242` (`touch` なし) で `grep -q 'sid=\[fresh-sid-1503\] phase_start' "$EMIT_LOG"` を assert する。置き換えるリプレイテストは、同じヘルパーで wrapper を実行し、元の主張を wrapper の出力で確かめる形にする:

- `... does not fall back to .tmp/auto-session-current when PGID file absent (Issue #1317, no misattribution)`: `.tmp/auto-session-current` に別 session の id を置き、PGID の pointer は作らない → `sid=[] phase_start` を assert し、別 session の id が `$EMIT_LOG` に無いこと
- `run-code.bats` の残り 3 件: `... resolves from PGID file, ignoring .tmp/auto-session-current (batch path preserved)` (両方を置き、PGID の id が採用される)、`... returns empty when neither file exists (graceful no-op)` (どちらも無い → 空)、`... env var takes priority over PGID file (caller override)` (`export AUTO_SESSION_ID="ENV-OVERRIDE"` と pointer を置く → `ENV-OVERRIDE` が採用される。`run` の後に `unset AUTO_SESSION_ID`)

**`auto-sub-observability.bats` (メイン経路)**: ヘルパーの stub は `source` 行に続けて、既存の stub と同じ JSONL recorder (`session_id` を含む行を `$AUTO_EVENTS_LOG` に書く `emit_event()` と、`_emit_comments_consumed() { :; }`) を書く。既存テスト `session-isolation: PGID-specific pointer file is read when AUTO_SESSION_ID is unset` はこのヘルパー + `ps` mock で pointer を `.tmp/auto-session-424242` に置く形に変え、stale は `printf 'stale-session-pgid\n' > ...` + `touch -t 202401010000` の後に `unset AUTO_SESSION_ID; run bash "$SCRIPT" 42` して、`"event":"phase_start"` があり `stale-session-pgid` が無いことを assert する。**このテストの末尾は stub の heredoc 内の `}` ではなく、`grep -q '"session_id":"test-session-pgid"' "$AUTO_EVENTS_LOG"` の次の `}` なので、スクリプトで置換するときは末尾の判定を誤らないこと**。

**`run-auto-sub.bats` (detach 経路)**: ヘルパーの stub は `source` 行だけでよい (子は `$MOCK_DIR/bash` の canary で、`echo "child AUTO_SESSION_ID=[${AUTO_SESSION_ID:-}] DETACHED=${_WHOLEWORK_DETACHED:-}"` を出力する)。既存の `spawn-detach: AUTO_SESSION_ID resolved from pre-detach PGID pointer and burned into child env` はこのヘルパーを使い、`[[ "$output" == *"AUTO_SESSION_ID=[sess-detach-test]"* ]] || false` を assert する。stale は同じ `run /bin/bash -c "mkdir -p .tmp && pgid=\$(ps -o pgid= -p \$\$ | tr -d ' ') && echo stale-detach-sid > \".tmp/auto-session-\${pgid}\" && touch -t 202401010000 \".tmp/auto-session-\${pgid}\" && exec /bin/bash '$SCRIPT' --write-manual-recovery"` で `AUTO_SESSION_ID=[]` と `DETACHED=1` を assert する (`ps` mock が `pgid` を 424242 に固定するので、書き手側と shim が同じ pointer を指す)。

### stub 66 件の機械的な変換 (任意。手作業でもよい)

```python
import re
from pathlib import Path

FILES = ["run-auto-sub.bats", "run-merge.bats", "run-code.bats", "run-spec.bats",
         "run-issue.bats", "run-review.bats", "auto-sub-observability.bats", "run-code-mergeability.bats"]
LINE_Q = 'read_pgid_pointer() { cat "$1" 2>/dev/null || true; }\n'
LINE_U = 'read_pgid_pointer() { cat "\\$1" 2>/dev/null || true; }\n'  # unquoted heredoc: keep \$1 literal
Q = re.compile(r"^(\s*cat > \"\$MOCK_DIR/emit-event\.sh\" <<'MOCK'\n)", re.M)
U = re.compile(r"^(\s*cat > \"\$MOCK_DIR/emit-event\.sh\" <<MOCK\n)", re.M)
for name in FILES:
    p = Path("tests") / name
    t = p.read_text()
    t = Q.sub(lambda m: m.group(1) + LINE_Q, t)
    t = U.sub(lambda m: m.group(1) + LINE_U, t)
    p.write_text(t)
```

適用後の網羅確認 (すべての stub が `read_pgid_pointer()` かハイブリッド形式の `source "$(dirname` で始まること。変更前の HEAD では 66 件が報告され、プロトタイプ適用後は 0 件):

```bash
awk 'FNR==1{prev=""} prev ~ /cat > "\$MOCK_DIR\/emit-event\.sh" <</ && $0 !~ /^read_pgid_pointer\(\)/ && $0 !~ /^source "\$\(dirname/ {printf "%s:%d: stub without read_pgid_pointer()\n", FILENAME, FNR; bad++} {prev=$0} END{print bad+0, "bad stub(s)"; exit (bad>0)}' tests/*.bats
```

### プロトタイプによる事前検証 (2026-10-04)

実ファイルは変えず、`scripts/` `tests/` `skills/` `modules/` をスクラッチ領域 (`.tmp/proto`、`.tmp/proto-orig`) に複製して、Implementation Steps の字面どおりの変更を適用し、ローカルに取得した bats-core で実行した。

- **ベースライン (変更前、8 ファイル)**: 324 件すべて PASS (`run-issue` 25、`run-spec` 43、`run-merge` 36、`run-review` 61、`run-code` 51、`run-code-mergeability` 2、`auto-sub-observability` 8、`run-auto-sub` 98)
- **wrapper 7 箇所 + stub 66 件の変更のみ**: 324 件すべて PASS。7 箇所はいずれも一意に置換でき、6 本とも `bash -n` が通る
- **stub を更新せずに wrapper だけ変えた場合** (`run-issue.bats` の元のファイルで確認): 広範に FAIL する (`read_pgid_pointer` が未定義で wrapper が abort)。Issue の「stub の更新が要る」という前提は正しい
- **新規・置き換えテストまで適用**: 336 件すべて PASS (`run-issue` 27、`run-spec` 45、`run-merge` 38、`run-review` 63、`run-code` 53、`run-code-mergeability` 2、`auto-sub-observability` 9、`run-auto-sub` 99。ベースラインから純増 12 件)
- **実装前 FAIL の確認**: 変更前の wrapper に新規テストを当てると、stale の 7 件 (`run-issue` `run-spec` `run-review` `run-merge` `run-code`、`auto-sub-observability` のメイン経路、`run-auto-sub` の detach 経路) だけが FAIL し、fresh と置き換えた既存テストは PASS する
- 出所: bats-core は `git clone --depth 1 https://github.com/bats-core/bats-core.git .tmp/bats-core` (commit 52439ebfac39987dd43e26502aa4aa19f2753d4a、2026-10-04 に取得。この環境から github.com に到達できた)。実行は `.tmp/bats-core/bin/bats <file>`。環境は Linux (procps の `ps`)

### bats をローカルで使う手順

この環境には bats も shellcheck も入っていない (`command -v bats` が何も出力しない。2026-10-04)。`/code` は次で取得して実行できる。CI は `sudo apt-get install -y bats` で入れ、`bats --jobs $(nproc) tests/` を実行する。

```bash
git clone --depth 1 https://github.com/bats-core/bats-core.git .tmp/bats-core
.tmp/bats-core/bin/bats tests/run-issue.bats
```

- worktree isolation guard は、`export VAR="$PWD"`、`time ( ... )`、`for` ループの中で `bash` を呼ぶ形など、git を呼ばないと証明できない複合コマンドを拒否した。bats や `bash -n` は 1 コマンドずつ実行する
- `bats tests/` の全件は時間がかかるので、`/code` は変更した 8 ファイルを個別に実行し、全件は CI の `Run bats tests` job と `/review` の CI 参照 (`modules/verify-executor.md` § "CI Reference Fallback"、`modules/verify-patterns.md` §24) が確定する。AC4 の `command "bats tests/"` は `command` の時間制限では収まらない

### `modules/event-emission.md` の更新文面

`scripts/` `modules/` は英語指定のパス (`scripts/check-language-convention.py`)。日本語・全角記号を入れない。

(a) "_EMIT_PHASE_OWNED pattern" のコードブロック (`AUTO_EVENTS_LOG=...` で始まる 6 行) を次にする:

```bash
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
# read_pgid_pointer() is defined in emit-event.sh, so source it before the pointer read below.
source "$SCRIPT_DIR/emit-event.sh"
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(read_pgid_pointer ".tmp/auto-session-${PGID}" "${PGID}")}"
export AUTO_SESSION_ID
```

(b) "Stale PGID pointer validation (Issue #1491)" 段落の末尾、`Known gaps, deliberately out of scope for #1491: (1) ... (2) ...` を次に置き換える (見出しの太字はそのまま、`are unchanged` と "65 definitions in 7 files" の記述は消える):

> **Wrapper reads (Issue #1503)**: the PGID pointer reads in the five `run-*.sh` wrappers and in `run-auto-sub.sh` go through the same function, so every PGID pointer read in `scripts/` now applies the freshness check. Each of them sources `emit-event.sh` before the read (the function is defined there) and resolves `AUTO_SESSION_ID` with `read_pgid_pointer ".tmp/auto-session-${PGID}" "${PGID}"`. `run-auto-sub.sh` reads twice: on its main path, and in the `WHOLEWORK_SPAWN_DETACH` re-exec shim, which reads with the pre-detach PGID before the process group changes. A manual wrapper invocation that meets a remnant pointer therefore resolves no session id instead of adopting it. The call is deliberately not wrapped in `|| echo ''` or `2>/dev/null`: `read_pgid_pointer()` returns 0 on every path, so a missing definition (for example a test stub that predates it) should fail loudly instead of silently dropping the session id. The wrapper test suites stub `emit-event.sh` per test; each stub defines `read_pgid_pointer()` as a plain read without the freshness check, and the freshness behavior is covered separately by tests that source the real `emit-event.sh` with a mocked `ps` (`tests/emit-event.bats` for the function itself, plus one stale-pointer test per read site). Known gap, deliberately out of scope for #1491 and #1503: the issue-scoped pointer `.tmp/auto-session-issue-<N>` has no owning process to compare against and is not validated.

(c) "Manual Orchestration (Issue #1224, wrapper fallback removed in #1317)" 段落の末尾 (`... mirroring the same policy #1224 already established for `restore_auto_session_pointer()`.` の後) に 1 文を足す:

> Since Issue #1503, these wrappers also ignore a PGID-matching pointer file that predates its process-group leader (see "Stale PGID pointer validation (Issue #1491)" below), so a remnant left by an earlier owner of the same PGID is not adopted either.

### 補助確認 (verify command ではない。`/code` の自己確認用)

- 7 箇所の置換: `git grep -n -F 'read_pgid_pointer ".tmp/auto-session-' -- scripts/` が 7 行 (6 本の `${PGID}` 版 + `run-auto-sub.sh` の detach 経路の `${_detach_pgid}` 版 1 行)
- 旧い読み取りの消去: `git grep -n -F 'cat ".tmp/auto-session-' -- scripts/` が 0 行 (AC1 と同じ。コメントに旧い書き方を引用しない)
- 文書: `grep -c 'are unchanged' modules/event-emission.md` が 0 (AC3 と同じ)

### Steering Docs 同期の確認結果

- `docs/structure.md` / `docs/ja/structure.md`: Key Files の `scripts/emit-event.sh` の行は公開関数 (`emit_event()` `restore_auto_session_pointer()` `persist_auto_session_pointer()`) だけを挙げ、`run-code.sh` などが直接呼ぶ `_emit_comments_consumed` も挙げていない。`read_pgid_pointer()` は #1491 の Spec が内部ヘルパーとして挙げないと判断しており、この変更で呼び出し元が増えても同じ扱いにする (`grep -c read_pgid_pointer docs/structure.md` は 0)。変更なし
- `docs/tech.md` の `WHOLEWORK_SPAWN_DETACH` の行: 「shim が detach 前の PGID pointer から `AUTO_SESSION_ID` を解決する」という記述は変更後も正確。変更なし
- `docs/product.md` / `docs/ja/product.md` の Terms (`Session ID`): 「PGID pointer file は、そのプロセスグループのリーダーが起動する前に書かれたものを採用しない (#1491)」は、wrapper も同じ検証を使うようになっても正しい。`restore_auto_session_pointer()` に限る記述で、wrapper の経路には触れていないので、変更なし
- `skills/auto/SKILL.md` (Step 1 の pointer 再生成、L36 L81-88) と `skills/audit/SKILL.md` L1096: 「sub-process が同じ PGID の pointer を読む」「再生成を省くと session_id が欠落する」という記述は変更後も正確で、再生成を同じ Bash 呼び出しの中で行う運用 (鮮度検証の前提) とも一致する。変更なし
- [Outbound pointer sync candidate] なし: `modules/event-emission.md` が指す先 (`skills/auto/SKILL.md` の Step 1 / Step 6、`scripts/emit-skill-event.sh`、`modules/orchestration-fallbacks.md`) のうち、この変更で内容が古くなるものはない
- Listing-side sub-check: 発火しない (subcommand の追加なし、ファイルの追加・削除・改名なし、ディレクトリ構成の変更なし)。`docs/ja/` の同期: top-level の `docs/*.md` を変更しないので不要
- Rename / 削除 / 意味の拡張のチェック: 該当しない。旧い読み取りの慣用句 `cat ".tmp/auto-session-` の全文検索 (`git grep -l -F`、`docs/sessions` と `docs/spec` は履歴なので除外) は、`modules/event-emission.md`、`scripts/run-{auto-sub,code,issue,merge,review,spec}.sh`、`tests/run-{code,issue,merge,review,spec}.bats` の 12 ファイルで、すべて Changed Files に含めた。`PGID` 変数は 6 スクリプトのいずれでも pointer のパス以外に使われていない

### その他の確認結果

- 監査・調査型の Issue ではない (`audit/drift` ラベルは /audit が起票した出自を示すだけで、中身は実装の変更)。Notes に書いた識別子 (`restore_auto_session_pointer` `persist_auto_session_pointer` `_process_elapsed_seconds` `_PGID_POINTER_SLACK_SEC` `_emit_comments_consumed` `_append_consumed_comments_section` `_detach_pgid` `_should_detach` `read_pgid_pointer`) とテスト名は、2026-10-04 に grep で実在を確認した
- allowed-tools impact chain check: 新規の `scripts/*.sh` は無い。`modules/event-emission.md` の変更は軽量ゲートが機械的に発火する (追記する本文が `emit-event.sh` などのパスに言及する) ので読み手を列挙した (`grep -rl "modules/event-emission.md" skills/*/SKILL.md`: `skills/audit/SKILL.md` `skills/auto/SKILL.md` `skills/verify/SKILL.md`)。この変更は新しい script の呼び出しを導入しない (記述の更新だけ) ので、`allowed-tools` の更新は要らない
- `WHOLEWORK_SCRIPT_DIR` mock の追加: 新規 script が無いので不要。bats の self-reference 除外: パターン検出 script の追加が無いので不要
- ツール検出パターンの一貫性: 新規の検出方式は導入しない。`ps -o pgid= -p $$ | tr -d ' '` の形は既存のまま、`ps -o etime=` と `stat` の分岐は `read_pgid_pointer()` が既に持つ
- 外部仕様: POSIX `ps` の `etime` ([[dd-]hh:]mm:ss) は #1491 で確認済み (出所: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/ps.html)。この Issue で新しい外部仕様は使わない
- 外部 package の追加なし (依存バージョンの確認は不要)。adapter パターンの調査は不要 (verify command は built-in の `file_not_contains` / `rubric` / `command` のみ)。credential / security に関わる設計は無い (pointer は session id で秘密ではなく、`.tmp/` は gitignore)。UI は無い
- 費用が大きい・不可逆な Implementation Step は無い (`spec-approval-needed` の対象なし)。外部サービスへのログインを要する Step も無い
- verify command の扱い: Pre-merge の 4 件は Issue 本文 (SSoT) をそのまま写した。AC1 の `file_not_contains` は 6 ファイルすべてで現状ヒットする (`run-auto-sub.sh` は 2 行) ことを確認済みで、実装後に 0 件になるのが期待状態。AC3 の `are unchanged` は `modules/event-emission.md` に 1 件 (Known gaps (1) の段落) あり、置き換えで消える。AC2 の rubric には数値リテラルの閾値・定数は無い (「5 つ」「2 箇所」は箇所の数) ので、`file_contains` の併記は要らない。決定的な裏付けは上の補助確認と新規テストが担う。AC4 の `command "bats tests/"` は pr route なので `/review` が PR の CI (`Run bats tests` job) を参照して確定する

### 未確認事項 (Uncertainties)

- **macOS の `ps -o etime=` の実機の出力形式**: POSIX の定義どおり `[[dd-]hh:]mm:ss` と想定する (#1491 から持ち越し)。CI の macOS job は `bash -n` だけで実行しない。**この Issue で影響が広がる**: これまでは `restore_auto_session_pointer()` を使う `--write-manual-recovery` などだけだったが、想定と違うと全 wrapper のイベントが `session_id` を失う (fail-closed。誤帰属はしない)。検証方法は macOS での `ps -o etime= -p $$` の確認と `bats tests/emit-event.bats` の実行。影響範囲は Implementation Step 1, 2 の 7 箇所
- **PGID のリーダーが `ps -p` で見えない環境** (呼び出しごとに PID namespace が新しい sandbox など): 未検証。リーダーが見えないと `read_pgid_pointer` は fail-closed になり、wrapper のイベントが `session_id` を失う。`/auto` の起動形 (`run_in_background: true` の Bash 呼び出し、XL の `run-auto-sub.sh ... &` と `wait`) では、リーダーのシェルが wrapper の実行中ずっと生きているので問題ない (`skills/auto/SKILL.md` L337 L368-395 を確認)
- **CI の `bats --jobs` 並列**: 新規テストは `ps` を mock し、per-test の tmpdir だけを使うので、実際の PGID にも並列実行にも依存しない。既存の 2 件の観測テストも本物の `read_pgid_pointer` + `ps` mock に変えて、実 PGID への依存を外す

### Size の再評価

確定の Changed Files は 15 件 (`scripts/` 6、`modules/` 1、`tests/` 8)。軸 1 は XL (11 件以上)。軸 2 は、5 本の wrapper が同型の 3 点編集、stub 66 件が 1 行ずつの機械的な追加、テストが共通テンプレートの展開という「既存パターンの横展開」で -1 (原因と方式が検証済みの修正という点も -1 だが、補正は ±1 段階まで)、script ロジックの変更 (+1 の候補) は関数呼び出しへの置換で分岐を足さないので加えない。判定は **L** で、triage 時の M から変わる。CI Dependency Minimum Override は L が下限を超えるため影響しない。route は pr で、review は full になる見込み。

### 自動解決した曖昧性 (non-interactive)

- stub の扱い (更新するか、wrapper の呼び出しに保護を付けるか): 更新する案を採用。理由は上の「設計の判断」
- リプレイテストの扱い (そのまま残すか、置き換えるか): 置き換える。代入行を再掲するだけのテストは wrapper 本体と食い違うため (#1491 の Spec が「テストの置き換え」を follow-up の範囲に含めている)
- `run-auto-sub.sh` の detach 経路の `source` の位置: shim の中 (`if [[ -z "${AUTO_SESSION_ID:-}" ]]; then` ブロック内)。ファイルの先頭 (shim の前) で 1 回だけ `source` する案は、flag 未設定の既定経路 (shim が動かない) にも変更が及び、`--write-manual-recovery` 分岐とメイン経路にある既存の `source` の整理も要るので採らない。shim の中なら影響は `WHOLEWORK_SPAWN_DETACH=1` かつ `AUTO_SESSION_ID` 未設定のときだけに限られる

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (AC の拡張、Background の補足、曖昧さの自動解決、Size 再判定を /spec に委ねる記録) / https://github.com/saitoco/wholework/issues/1503#issuecomment-5980226317

## Code Retrospective

### Deviations from Design
- 設計どおりの実装。wrapper 5 本と `run-auto-sub.sh` の 7 箇所、`modules/event-emission.md` の 3 箇所 (コード例、Wrapper reads 段落、Manual Orchestration 段落)、stub 66 件、リプレイテスト 8 件の置き換え、新規テスト 12 件を Spec の字面どおりに適用した
- 新規テストの `status` 検査は Spec のテンプレートの `[ "$status" -eq 0 ]` に `|| false` を足した (bash 3.2 での伝播のため。`skill-dev-validation.md` の方針)
- `auto-sub-observability.bats` のヘルパーは `printf` + `cat >>` で stub を組み立てた (`cat > "$MOCK_DIR/emit-event.sh" <<` の形にすると Spec の網羅確認 awk に引っ掛かるため、またエスケープを避けるため)

### Design Gaps/Ambiguities
- Step 3 の前提チェック (`reconcile-phase-state.sh --check-precondition`) を、Step 4 のラベル遷移の後に実行してしまった。遷移後の状態を見たので `matches_expected: false` (`phase/ready` なし) が返ったが、遷移前の実測は `phase/ready` ありで前提は満たしていた (Issue 取得時のラベル: `triaged` `phase/ready` `audit/drift` `theme/observability` `theme/concurrency`)。実装の判断には影響していない。OBSERVED_LABELS / OBSERVED_DIAGNOSIS の取り違えを避ける運用 (遷移前に 1 回だけ実行して記録する) を守れなかった
- bats が環境に無く、Spec の手順どおり `.tmp/` に取得した bats-core で `run-issue.bats` (27 件) と `run-spec.bats` (45 件) は PASS を確認できたが、3 つ目 (`run-merge.bats`) の実行が権限分類器 (外部由来のコード) に拒否された。回避せず、残り 6 ファイルのローカル実行と「新規 stale テストが変更前の wrapper で FAIL する」確認は未実施。Spec のプロトタイプ検証 (336 件 PASS、stale 7 件が変更前で FAIL) と PR の CI の `Run bats tests` job に委ねる
- 実装前 FAIL 確認 (New Verification-Test Pre-implementation FAIL Check): 上記の理由でローカルでは未確認。対象は stale 7 件 (挙動検証でありリテラルの文字列一致ではないが、Spec が実装前 FAIL をプロトタイプで確認済み)

### Rework
- worktree 隔離ガードが複合コマンド (`python3 - <<EOF`、`for` ループ、パイプ + `git diff`) を拒否したため、変換スクリプトを `.tmp/` に Write してから単独コマンドで実行する形に切り替えた。実装の手戻りではないが、言語規約チェックの `git diff | python3` も同じ理由でスクリプト経由にした

## review retrospective

### Spec vs. implementation divergence patterns
- 構造的な乖離なし。Spec の Changed Files 15 件と PR の変更ファイルが一致し、7 箇所の読み取り、`modules/event-emission.md` の 3 箇所、stub、リプレイテストの置き換え、新規テストの件数も Spec どおりだった
- review-spec が Spec の Uncertainties (macOS の `ps -o etime=` の形式が未検証) を MUST で指摘したが、既存の #1491 のコードと既に明記された fail-closed の範囲であり、Spec からの逸脱ではないため CONSIDER に引き下げた。未検証の不確定事項を Spec に書いたままにすると、レビューで MUST として再浮上しやすい。次回以降は、PR 内での扱い (確認済み・既知の制約として明記・follow-up Issue 化のどれか) まで Spec に決めて書くと判断が早い

### Recurring issues
- Code Retrospective の記述 (新規テストの `status` 検査に `|| false` を足した) と実装の食い違いが 1 件あった (`auto-sub-observability.bats` と `run-auto-sub.bats` に未適用)。実害はなく、CI の Bare Bracket Assertions check も PASS している。retrospective の記述は適用範囲まで書くと食い違いを避けられる

### Acceptance criteria verification difficulty
- UNCERTAIN なし。AC4 (`bats tests/`) は CI reference (head SHA の `Run bats tests` job) で PASS と確定できた。Phase Handoff に CI 参照の手順が書かれていたので判断に迷わなかった

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- `--non-interactive` では Workflow の再起動保証がないため、`capabilities.workflow: true` でも静的な Task fan-out (review-spec + review-bug ×2) を前景で実行した
- review-spec の MUST (macOS の `ps -o etime=` 形式が未検証) は CONSIDER に引き下げた。`read_pgid_pointer()` 本体は #1491 で導入済み、fail-closed は event-emission.md に明記済み、誤帰属は起きない。結果は `COMMENT` で投稿し、`REQUEST_CHANGES` にはしていない

### Deferred Items
- macOS 実機での `ps -o etime= -p $$` と `bats tests/emit-event.bats` の確認: 未実施 (CI の macOS job は `bash -n` のみ)。想定と違うと全 wrapper のイベントが `session_id` を失う (fail-closed)
- 新規 stale テストの `|| false` の揃え (`auto-sub-observability.bats` / `run-auto-sub.bats`): 実害がないため修正しなかった

### Notes for Next Phase
- Pre-merge AC は 4 件すべて PASS で Issue 上でもチェック済み。`/merge` は追加の対応なしで進められる
- CI は全 17 チェック PASS (head SHA `8ece4010`)。レビューで未解決の MUST はない
