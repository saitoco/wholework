# Issue #1491: event-emission: 残存した PGID pointer による session_id の誤帰属を防ぐ

## Overview

`scripts/emit-event.sh` の `restore_auto_session_pointer()` が、書いた Bash 呼び出し (process group) の終了後も残る `.tmp/auto-session-<PGID>` を、所有者を確かめずに採用する穴を塞ぐ。あわせて、Issue 本文の仮説 (別セッションの Bash 呼び出しで PGID が再利用され、残存 pointer が拾われた) を検証し、結果を Spec と `modules/event-emission.md` に記録する。

この Spec の調査で、**2026-10-03 のインシデントは仮説の経路では起きていない**ことが分かった。#1365 / #1481 / #1484 の `/verify` のイベントが batch セッション (`190537-1790984033`) の `session_id` で記録されたのは、同じセッション自身の `/review` (PR #1489) が Event-based observation scan で起動した入れ子の `/verify` が、環境変数の継承で本セッションの `session_id` と `pr` (1489) を持ったためだった (根拠は Notes)。一方、所有者を確かめずに残存 pointer を採用する機構そのものは実在し、素の bash で再現できたので、AC どおり塞ぐ。

方針は次の 3 点。新しい script は足さない。

- **機構の修正 (AC1)**: `scripts/emit-event.sh` に `read_pgid_pointer()` (内部ヘルパー `_process_elapsed_seconds()` つき) を足し、PGID pointer を「その process group のリーダーが起動した後に書かれたものだけ」採用する。pointer の mtime とリーダーの経過時間 (`ps -o etime=`) を比べ、判定できないときは採用しない (fail-closed)。`restore_auto_session_pointer()` の step 4 をこれに切り替える
- **検証結果の記録 (AC2)**: `modules/event-emission.md` に、仮説の検証結果 (インシデントでは否定、機構は再現) と、見かけ上別セッションのイベントの見分け方を書く。`docs/product.md` と `docs/ja/product.md` の Session ID の行を 1 文だけ合わせる
- **テスト (AC3)**: `tests/emit-event.bats` に新規 8 件を足す (実装前に 7 件が FAIL し、1 件は退行ガード)

意図的に範囲外としたもの (理由は Notes): 5 つの `run-*.sh` と `run-auto-sub.sh` の inline な pointer 読み取り、issue-scoped pointer (`.tmp/auto-session-issue-<N>`) の残存、入れ子 `/verify` の Sub-Issue Completion Timeline 上の見せ方。

## Reproduction Steps

**機構 (所有者を確かめない採用)**: 再現できた (2026-10-04、変更前の `scripts/emit-event.sh`)。

1. 作業ディレクトリ (git repo でなくてよい。`git worktree list` が何も返さなければ CWD 相対の `.tmp/` を引く) に `.tmp/auto-session-<PGID>` を作る。`<PGID>` は呼び出し元の process group (`ps -o pgid= -p $$ | tr -d ' '`)、内容は `STALE-SID-FROM-PREVIOUS-OWNER`、mtime は `touch -t 202401010000` で 2024-01-01 にする
2. `unset AUTO_EVENTS_LOG AUTO_SESSION_ID` して `scripts/emit-event.sh` を source し、`restore_auto_session_pointer` を呼ぶ
3. 結果: `AUTO_SESSION_ID=[STALE-SID-FROM-PREVIOUS-OWNER]`、`AUTO_EVENTS_LOG=[.tmp/auto-events.jsonl]` (採用された)。このとき process group のリーダーの経過時間は 00:00 で、pointer は約 1000 日前に書かれていた。リーダーの起動より前に書かれた pointer は、その process group が書いたものではない
4. 変更後は `SID=[] LOG=[]` (採用しない)。テストで固定する (Implementation Step 2)

**インシデントの経路 (PGID の再利用)**: 再現できない。否定した (Root Cause と Notes)。

## Root Cause

**機構 (潜在)**: PGID pointer は、書いた Bash 呼び出し (process group) の間だけ意味を持つ。`/auto` は `run-*.sh` / `run-auto-sub.sh` の直前に毎回、同じ Bash 呼び出しの中で書き直す (`skills/auto/SKILL.md` Step 1)。しかし誰も消さず (メインリポジトリの `.tmp/` に数字だけの名前で 36 件が残っており、うち 14 件は 8 件 batch の 1 セッション分)、OS は PID カウンタが一周すると PGID を再利用する。`restore_auto_session_pointer()` の step 4 は pointer の所有者を確かめずに採用するので、再利用された PGID を受け取った別の process group が、残存 pointer を採用しうる。

**2026-10-03 のインシデント**: 原因は上の機構ではない。#1365 / #1481 / #1484 の `phase_start` と `retro_proposal_classified` は、batch セッションの `/review` (PR #1489、Issue #1479 の pr route) の実行中に、`/review` の Event-based observation scan (`observation-trigger.sh --event pr-review-light`) が拾った Issue に対して起動した入れ子の `Skill(wholework:verify)` が出したものである。この repo は `autonomy: L3` なので、一致した Issue ごとに順次 `/verify` が走る。入れ子の `/verify` は review phase の環境 (`AUTO_EVENTS_LOG` / `AUTO_SESSION_ID` / `EMIT_PR_NUMBER`) を継承するので、`restore_auto_session_pointer()` は step 1 (`AUTO_EVENTS_LOG` が設定済み) で何もせず返り、pointer は読まれない。`session_id` が batch セッションのものなのは起動元がそのセッション自身だからで、誤帰属ではない。`pr: 1489` は review phase の PR 番号が継承されたもの。

L3 の振り返り (`docs/sessions/190537-1790984033-2026-10-03/session.md`) が 3 件を別セッションの verify と読んだのは、3 件が batch 対象 8 件に無い Issue で、同じ時間帯に別セッション (`393456-1790987493`) の verify (#1112 など 5 件) とその commit も実在し、review の終了時の `concurrent_commit_detected` に 6 件の verify commit が並んだため。別セッションの 5 件は、別の `session_id` で正しく記録されていた。

## Changed Files

- `scripts/emit-event.sh` (bash 3.2+ 互換。新しい script ではなく既存 script への関数追加):
  - `restore_auto_session_pointer()` の上のコメント (`# Restores AUTO_SESSION_ID/AUTO_EVENTS_LOG from pointer files when the caller's` で始まる塊) の直前に、`_PGID_POINTER_SLACK_SEC`、`_process_elapsed_seconds()`、`read_pgid_pointer()` を足す (Implementation Step 1)
  - `restore_auto_session_pointer()` の step 4 の `cat "${_prefix}.tmp/auto-session-${_pgid}"` を `read_pgid_pointer` の呼び出しに差し替える
  - 同関数の上のコメントの resolution order の item 4 と、続く `# issue-scoped is checked before PGID ...` の段落を更新する
- `tests/emit-event.bats`: 新規 8 件と補助関数 2 つを、ファイル末尾 (`persist_auto_session_pointer deletes the issue-scoped pointer file when session id is empty (Issue #1075)` の後) に追加する (Implementation Step 2)
- `modules/event-emission.md`: resolution order の item 4 の文言、`issue-scoped (step 3) is checked before PGID (step 4) ...` の段落の末尾、`**Manual Orchestration (...)**` の段落と `**Worktree-CWD independence (Issue #1006)**` の段落の間の 2 段落を足す (Implementation Step 3)
- `docs/product.md`: Terms の `Session ID (`AUTO_SESSION_ID`)` の行 (Implementation Step 4)
- `docs/ja/product.md`: 同じ行の日本語版 (翻訳同期。`docs/translation-workflow.md`)
- [Steering Docs sync candidate] keyword "restore_auto_session_pointer" (この Issue が変更する関数名) skipped: matched 47 files (no discriminating power)。測定範囲: `grep -rl "restore_auto_session_pointer" docs/ tests/ scripts/ modules/` (全ファイル種別、`docs/spec/` `docs/sessions/` `docs/reports/` を含む)
- [Steering Docs sync candidate] keyword "emit-event.sh" (変更する script のファイル名) skipped: matched 107 files (no discriminating power)。測定範囲は同じ
- [Steering Docs sync candidate] keyword "auto-session-" (pointer ファイル名の接頭辞) skipped: matched 170 files (no discriminating power)。測定範囲は同じ
- [Steering Docs sync candidate] keyword "read_pgid_pointer" (この Issue が導入する名前): 他の file にヒットなし (0 files、`docs/ tests/ scripts/ modules/ skills/`)。新規の内部ヘルパーで、写す先は無い
- 上の 3 keyword は判別力が無いので個々の hit は評価していない。`docs/product.md` の Session ID の行は、pointer 解決の記述を直接読んで特定した (keyword の hit からではない)
- [Outbound pointer sync candidate] なし: `modules/event-emission.md` が指す先 (`skills/auto/SKILL.md` Step 1 / Step 6 の pointer 再生成の記述、`scripts/emit-skill-event.sh`、`skills/review/SKILL.md` の Event-based observation scan) の内容を、この Issue の変更で変える必要は無い。`skills/auto/SKILL.md` の 36・81・90 行目は「PGID pointer は作った Bash 呼び出しでだけ有効」と述べており、新しい検証と整合する
- Listing-side sub-check: 発火しない (subcommand の追加・削除なし、file の追加・削除・改名なし、ディレクトリ構成の変更なし)。`docs/structure.md` と `README.md` は対象外
- 変更しない (確認済み):
  - `docs/structure.md` / `docs/ja/structure.md`: Key Files の `scripts/emit-event.sh` の行は公開関数 (`emit_event()` `restore_auto_session_pointer()` `persist_auto_session_pointer()`) だけを挙げ、内部ヘルパー (`_emit_comments_consumed` `_append_consumed_comments_section`) は挙げていない (`grep -c` で 0 件)。`read_pgid_pointer()` も内部ヘルパーなので追記しない
  - `scripts/run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` (2 か所): inline な `cat ".tmp/auto-session-${PGID}"` を変えない (Notes の「スコープの境界」)
  - `skills/auto/SKILL.md` / `skills/audit/SKILL.md` / `modules/orchestration-fallbacks.md`: pointer の書き込み手順の記述。書き込み側は変わらない
  - `scripts/emit-skill-event.sh` / `scripts/collect-run-facts.sh` / `scripts/run-auto-sub.sh` (`--write-manual-recovery`): `restore_auto_session_pointer()` の呼び出し側。関数の入出力は変わらない
  - `tests/run-code.bats` ほか #1317 系のテスト (5 ファイル): wrapper の inline スニペットを再掲して検証しており、wrapper 本体を変えないので影響しない

## Implementation Steps

1. `scripts/emit-event.sh` を編集する (→ AC1)
   - `restore_auto_session_pointer()` の上のコメント (`# Restores AUTO_SESSION_ID/AUTO_EVENTS_LOG from pointer files when the caller's` で始まる塊) の直前、`persist_auto_session_pointer()` の閉じ括弧 `}` の後に、空行 1 つを挟んで次のブロックを足す (字面どおり。英語のみ。コードは一時コピーで検証済み。Notes 参照):

```bash
# Seconds a PGID pointer may predate the start of its process-group leader and still be
# treated as written by that group. It absorbs the 1-second granularity of `ps -o etime=`
# and of file mtimes plus minor clock skew, and stays far below the time an OS needs to
# recycle a PGID.
_PGID_POINTER_SLACK_SEC=60

# Prints the elapsed running time of process $1 in whole seconds, parsed from
# `ps -o etime=` (POSIX format [[dd-]hh:]mm:ss). Prints nothing and returns 1 when the
# process does not exist or the value cannot be parsed. 10# forces decimal: zero-padded
# fields such as 08 or 09 are otherwise rejected as invalid octal. bash 3.2+ compatible.
_process_elapsed_seconds() {
  local _etime _rest _d=0 _h=0 _m=0 _s=0 _f
  _etime="$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')"
  [[ -z "${_etime}" ]] && return 1
  if [[ "${_etime}" == *-* ]]; then
    _d="${_etime%%-*}"
    _etime="${_etime#*-}"
  fi
  case "${_etime}" in
    *:*:*) _h="${_etime%%:*}"; _rest="${_etime#*:}"; _m="${_rest%%:*}"; _s="${_rest#*:}" ;;
    *:*)   _m="${_etime%%:*}"; _s="${_etime#*:}" ;;
    *) return 1 ;;
  esac
  for _f in "${_d}" "${_h}" "${_m}" "${_s}"; do
    [[ "${_f}" =~ ^[0-9]+$ ]] || return 1
  done
  echo $(( 10#${_d} * 86400 + 10#${_h} * 3600 + 10#${_m} * 60 + 10#${_s} ))
}

# Prints the session id stored in PGID pointer file $1, but only when the file was last
# written no earlier than the start of process-group leader $2 (minus
# _PGID_POINTER_SLACK_SEC). A PGID pointer is only meaningful for the lifetime of the Bash
# tool call (process group) that wrote it, nothing deletes it afterwards, and the OS
# recycles PGID numbers, so a file left behind by an earlier owner of the same number must
# never be adopted: doing so attributes this group's events to a session that ended long
# ago (Issue #1491). Fail-closed: when the file is absent or unreadable, or the leader's
# elapsed time or the file's mtime cannot be determined, nothing is printed and the caller
# resolves no session id (same policy as #1224 / #1317: prefer session_id loss over
# misattribution). Otherwise the file content is printed exactly as `cat` would. Every
# failure path returns 0, so a `set -e` caller is never aborted. The stat form follows
# scripts/gh-graphql.sh. bash 3.2+ compatible.
read_pgid_pointer() {
  local _file="$1" _pgid="$2" _elapsed _mtime _now
  [[ -f "${_file}" ]] || return 0
  _elapsed="$(_process_elapsed_seconds "${_pgid}")" || return 0
  if [ "$(uname)" = "Darwin" ]; then
    _mtime="$(stat -f '%m' "${_file}" 2>/dev/null)" || return 0
  else
    _mtime="$(stat -c '%Y' "${_file}" 2>/dev/null)" || return 0
  fi
  [[ "${_mtime}" =~ ^[0-9]+$ ]] || return 0
  _now="$(date +%s)"
  (( _now - _mtime <= _elapsed + _PGID_POINTER_SLACK_SEC )) || return 0
  cat "${_file}" 2>/dev/null || true
}
```

   - `restore_auto_session_pointer()` の step 4 を差し替える (アンカー: `_sid="$(cat "${_prefix}.tmp/auto-session-${_pgid}" 2>/dev/null || echo '')"`):

```bash
  if [[ -z "${_sid}" ]]; then
    local _pgid; _pgid=$(ps -o pgid= -p $$ | tr -d ' ')
    _sid="$(read_pgid_pointer "${_prefix}.tmp/auto-session-${_pgid}" "${_pgid}")"
  fi
```

   - 同関数の上のコメントを更新する。(a) item 4 の行 `#   4. ${root}/.tmp/auto-session-<PGID> exists -> adopt it` を次の 4 行にする。(b) 段落 `# issue-scoped is checked before PGID ...` の最後の行 `# pick up a stale pointer left by an unrelated session.` の直後に次の 2 行を足す:

```bash
#   4. ${root}/.tmp/auto-session-<PGID> exists and is not stale
#                                              -> adopt it (read_pgid_pointer(): the file must
#                                                  not predate the start of its process-group
#                                                  leader; Issue #1491)
```

```bash
# Since Issue #1491 step 4 also rejects such a stale pointer itself (read_pgid_pointer()),
# which covers callers that have no issue-scoped pointer.
```

   - fail-safe 重要度の境界条件 (Notes の判定。コードは上のとおりこれを満たす): (a) 空入力 = pointer が無い・空・`_pgid` が空のときは何も出力せず 0 で返る (呼び出し側は「pointer なし」として step 5 の no-op へ)。(b) 大きな入力 = 内容は `cat` のまま通し、長さの制限は足さない (従来どおり。`AUTO_SESSION_ID` の内容検証はこの Issue の範囲外)。(c) 特殊文字 (`>` `"` 改行 CRLF 多バイト) = 内容は通すだけで解釈しない (従来どおり)。pointer のパスは常に二重引用符で囲む。`_pgid` が数字でなければ `_process_elapsed_seconds` が空を返して fail-closed。(d) 依存コマンドの失敗 = `ps` / `stat` / `date` の失敗・空・非数値は fail-closed (何も出力しない)。理由は #1224 / #1317 の方針 (誤帰属より session_id の欠落を選ぶ)。すべての失敗経路は `return 0` で、`set -e` の呼び出し元 (`collect-run-facts.sh` など) を abort させない
   - 実装後に `bash -n scripts/emit-event.sh` を通す (CI の `macOS shell compatibility` job も `bash -n` で bash 3.2 の構文を検査する)
2. (after 1) `tests/emit-event.bats` に新規テストを追加する (→ AC1, AC3)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/emit-event.bats` に下記 8 件) を追加したうえでスイートが PASS すること。既存の最後のテスト (`persist_auto_session_pointer deletes the issue-scoped pointer file when session id is empty (Issue #1075)`) の後ろに、空行を挟んで次を足す (字面どおり。assertion は `[ ... ] || false` か `[[ ... ]] || false`。`skills/code/skill-dev-validation.md` の「Bash 3.2: Bare `[[ ]]` Assertions Do Not Propagate `set -e`」):

```bash
# Prints a `touch -t` timestamp (YYYYMMDDhhmm.SS) for N days ago: GNU date first, BSD date as fallback.
_days_ago_touch_ts() {
    date -d "$1 days ago" +%Y%m%d%H%M.%S 2>/dev/null || date -v-"$1"d +%Y%m%d%H%M.%S
}

# ps mock for the PGID pointer tests (Issue #1491): the caller's PGID is fixed at 424242 and the
# leader's elapsed time comes from MOCK_ETIME (default 10:00; set but empty means no such process).
_mock_ps_for_pgid_pointer() {
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

@test "restore_auto_session_pointer adopts a PGID pointer written after its process-group leader started (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    mkdir -p "$BATS_TEST_TMPDIR/work8/.tmp"
    echo "pgid-session-1491" > "$BATS_TEST_TMPDIR/work8/.tmp/auto-session-424242"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work8\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"SID=[\$AUTO_SESSION_ID] LOG=[\$AUTO_EVENTS_LOG]\""
    [ "$status" -eq 0 ]
    [ "$output" = "SID=[pgid-session-1491] LOG=[.tmp/auto-events.jsonl]" ] || false
}

@test "restore_auto_session_pointer ignores a PGID pointer left by an earlier owner of the same PGID (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    mkdir -p "$BATS_TEST_TMPDIR/work9/.tmp"
    echo "stale-session-1491" > "$BATS_TEST_TMPDIR/work9/.tmp/auto-session-424242"
    touch -t 202401010000 "$BATS_TEST_TMPDIR/work9/.tmp/auto-session-424242"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work9\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"SID=[\$AUTO_SESSION_ID] LOG=[\$AUTO_EVENTS_LOG]\""
    [ "$status" -eq 0 ]
    [ "$output" = "SID=[] LOG=[]" ] || false
}

@test "read_pgid_pointer fails closed when the process-group leader cannot be inspected (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    mkdir -p "$BATS_TEST_TMPDIR/work10"
    echo "orphan-session" > "$BATS_TEST_TMPDIR/work10/auto-session-424242"
    export MOCK_ETIME=""
    run bash -c "source \"$SCRIPT\" && read_pgid_pointer \"$BATS_TEST_TMPDIR/work10/auto-session-424242\" 424242"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || false
}

@test "_process_elapsed_seconds parses the real ps etime of a live process (Issue #1491)" {
    run bash -c "source \"$SCRIPT\" && _process_elapsed_seconds \$\$"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]] || false
}

@test "_process_elapsed_seconds parses every POSIX etime shape including zero-padded fields (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    local pair
    for pair in "00:00=0" "05:12=312" "08:09=489" "01:05:12=3912" "09:09:09=32949" "2-03:04:05=183845" "1-18:18:45=152325"; do
        export MOCK_ETIME="${pair%%=*}"
        run bash -c "source \"$SCRIPT\" && _process_elapsed_seconds 1"
        [ "$status" -eq 0 ]
        [ "$output" = "${pair#*=}" ] || false
    done
}

@test "_process_elapsed_seconds rejects an empty or unparsable etime (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    local bad
    for bad in "" "abc" "12" "1:2:3:4" "aa:bb" "-05:00" "1-"; do
        export MOCK_ETIME="$bad"
        run bash -c "source \"$SCRIPT\" && _process_elapsed_seconds 1"
        [ "$status" -eq 1 ]
        [ -z "$output" ] || false
    done
}

@test "read_pgid_pointer compares the pointer age with the leader's elapsed time, not a fixed cap (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    mkdir -p "$BATS_TEST_TMPDIR/work11"
    echo "older-than-leader" > "$BATS_TEST_TMPDIR/work11/ptr-31d"
    touch -t "$(_days_ago_touch_ts 31)" "$BATS_TEST_TMPDIR/work11/ptr-31d"
    echo "newer-than-leader" > "$BATS_TEST_TMPDIR/work11/ptr-29d"
    touch -t "$(_days_ago_touch_ts 29)" "$BATS_TEST_TMPDIR/work11/ptr-29d"
    export MOCK_ETIME="30-00:00:00"
    run bash -c "source \"$SCRIPT\" && read_pgid_pointer \"$BATS_TEST_TMPDIR/work11/ptr-29d\" 424242"
    [ "$status" -eq 0 ]
    [ "$output" = "newer-than-leader" ] || false
    run bash -c "source \"$SCRIPT\" && read_pgid_pointer \"$BATS_TEST_TMPDIR/work11/ptr-31d\" 424242"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || false
}

@test "restore_auto_session_pointer does not abort a set -e caller when the PGID pointer is stale (Issue #1491)" {
    _mock_ps_for_pgid_pointer
    mkdir -p "$BATS_TEST_TMPDIR/work12/.tmp"
    echo "stale-session-1491" > "$BATS_TEST_TMPDIR/work12/.tmp/auto-session-424242"
    touch -t 202401010000 "$BATS_TEST_TMPDIR/work12/.tmp/auto-session-424242"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work12\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && set -euo pipefail && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"survived SID=[\${AUTO_SESSION_ID:-}]\""
    [ "$status" -eq 0 ]
    [ "$output" = "survived SID=[]" ] || false
}
```

   - 8 件の役割: (1) 新しい pointer は採用する (退行ガード。実装前も PASS)。(2) リーダーより古い pointer は採用しない (**インシデントの機構の再現。実装前は FAIL**)。(3) リーダーを調べられないときは採用しない (fail-closed)。(4) 実機の `ps` の `etime` を読める (プラットフォームの実際の形式)。(5) `etime` の全形式 (`mm:ss` / `hh:mm:ss` / `dd-hh:mm:ss`、`08` `09` のゼロ埋め) を読む。(6) 読めない形式は拒否する。(7) 比較の基準がリーダーの経過時間で、固定の上限ではない (30 日稼働のリーダーに対し 29 日前の pointer は採用、31 日前は棄却)。(8) 棄却しても `set -e` の呼び出し元を abort させない。(2)〜(8) は実装前に FAIL する (関数が無い、または採用してしまう)
   - `tests/emit-event.bats` の既存の `setup()` が `MOCK_DIR` を `PATH` の先頭に置き `AUTO_EVENTS_LOG` を export する。(1)(2)(8) は `bash -c` の中で `unset AUTO_EVENTS_LOG AUTO_SESSION_ID` する (既存の `restore_auto_session_pointer` のテストと同じ形)。`$BATS_TEST_TMPDIR` は git repo の外にある前提 (既存テストと同じ。`git worktree list` が空になり CWD 相対の `.tmp/` を引く)
   - bats が無い環境では、(1)〜(8) を素の bash で確認する (Notes の「プロトタイプによる事前検証」と「bats が未インストール」)。bats の実行は push 後の CI の `Run bats tests` job に任せ、Code Retrospective に「bats 未実行」と書く
3. (parallel with 1, 2) `modules/event-emission.md` を編集する (→ AC1, AC2)。追記は英語のみ (CI の `language-convention` job が検査する)。非推奨語 (`docs/product.md` § Terms の Formerly called の欄) を含めない (`scripts/check-forbidden-expressions.sh`。`modules/` も走査対象。`/auto` の旧称は大文字始まりの 1 語なので、本文では小文字の dispatch を使う)
   - resolution order の item 4 (アンカー: ``4. `.tmp/auto-session-<PGID>` exists — adopt it``) を次にする:

```markdown
4. `.tmp/auto-session-<PGID>` exists and is not stale — adopt it (`read_pgid_pointer()`: the file must not predate the start of its process-group leader; see "Stale PGID pointer validation (Issue #1491)" below)
```

   - 段落 `issue-scoped (step 3) is checked before PGID (step 4) because ...` (アンカー: `issue-scoped (step 3) is checked before PGID (step 4)`) の末尾の文 `... could otherwise pick up a stale pointer left by an unrelated session.` の直後に、半角スペースを挟んで次の 1 文を足す:

```markdown
Since Issue #1491, step 4 also rejects such a stale pointer on its own (see "Stale PGID pointer validation (Issue #1491)" below), which covers callers that have no issue-scoped pointer.
```

   - `**Manual Orchestration (Issue #1224, wrapper fallback removed in #1317)**: ...` の段落と `**Worktree-CWD independence (Issue #1006)**: ...` の段落の間に、空行を挟んで次の 2 段落を足す:

```markdown
**Stale PGID pointer validation (Issue #1491)**: a `.tmp/auto-session-<PGID>` file is only meaningful for the Bash tool call (process group) that wrote it — `/auto` rewrites it in the same Bash call right before every `run-*.sh` / `run-auto-sub.sh` invocation (`skills/auto/SKILL.md` Step 1) — yet nothing deletes it afterwards (one 8-Issue batch on 2026-10-03 left 14 of them), and the OS recycles PGID numbers once its PID counter wraps around. A later, unrelated process group that received a recycled number could therefore adopt a remnant and attribute its events to a session that ended long ago. `restore_auto_session_pointer()` step 4 now goes through `read_pgid_pointer()` (`scripts/emit-event.sh`): the pointer is adopted only when its file was last written no earlier than the start of the PGID's leader process (leader age from `ps -o etime=`, file age from its mtime, with a 60-second slack for the 1-second granularity of both and minor clock skew). A file that predates the current leader of its PGID was written by an earlier owner of that number and is ignored. The check is fail-closed: a missing leader, an unparsable `ps` value, or an unreadable mtime also resolve no session id, which keeps the #1224 / #1317 policy of preferring session_id loss over misattribution. Known gaps, deliberately out of scope for #1491: (1) the inline `cat ".tmp/auto-session-${PGID}"` reads in the five `run-*.sh` wrappers and in `run-auto-sub.sh` are unchanged — under `/auto` the pointer they read was rewritten in the same Bash call, so it is current, and only a manual wrapper invocation could meet a remnant; moving them onto `read_pgid_pointer()` also requires updating the per-test `emit-event.sh` stubs of the wrapper test suites (65 definitions in 7 files), so it is a separate change; (2) the issue-scoped pointer `.tmp/auto-session-issue-<N>` has no owning process to compare against and is not validated.

**Hypothesis check for the 2026-10-03 misattribution report (Issue #1491)**: the L3 retrospective of batch session `190537-1790984033` reported `/verify` events for #1365, #1481 and #1484 (`phase_start`, `retro_proposal_classified`) recorded under that session's `session_id` although another session seemed to have run them, and hypothesized that a recycled PGID had adopted a remnant pointer. The path was **negated for that incident**; the mechanism itself is real, was reproduced in isolation (a pointer for the caller's own PGID with an old mtime was adopted before the validation above and is ignored after it, `tests/emit-event.bats`), and is what the validation closes. Evidence: (1) the events carry `"pr":1489`; `emit_event()` adds `pr` only from `EMIT_PR_NUMBER` in the emitting process's environment, which `run-auto-sub.sh` (`run_phase_with_recovery()`) and `run-review.sh` / `run-merge.sh` export for review and merge phases and which pointer resolution never sets, so the emitters were descendants of that session's own `/review` run for PR #1489, not a foreign process group; (2) `/review`'s Event-based observation scan runs nested `Skill(skill="wholework:verify", ...)` calls sequentially at autonomy L2/L3, and the three runs were sequential, began right after that review's own Opportunistic Verification events and ended before its `wrapper_exit`; (3) a nested run inherits `AUTO_EVENTS_LOG` and `AUTO_SESSION_ID` from the review phase's environment (resolution order step 1), so no pointer file is consulted at all; (4) PGID recycling was impossible in that window: the PGIDs of all 36 remnant pointers in the repository's `.tmp/` increase strictly with their mtimes over 36.6 hours, i.e. the PID counter (`kernel.pid_max` 4194304) never wrapped around; (5) the genuinely concurrent session in the same log (`393456-1790987493`, `/verify` of #1112, #1113, #1125, #1133 and #1139) recorded its events under its own `session_id` with no `pr` field. Lesson: an event that looks foreign in a session report may be a legitimate descendant — a nested `/verify` dispatched by `/review` carries the batch session's `session_id` and the review's PR number in `pr` — so check the `pr` field and the time window against that session's review phase before suspecting pointer misattribution.
```

   - 追記後に `bash scripts/check-forbidden-expressions.sh` が通ること、追記部分に日本語の文字 (CJK) が無いことを確認する
4. (parallel with 1, 2, 3) steering を同期する (→ 受入条件なし。SHOULD レベルの整合)
   - `docs/product.md` の Terms の `Session ID (`AUTO_SESSION_ID`)` の行で、``via a 2-tier fallback (issue-scoped pointer file → PGID pointer file); the `.tmp/auto-session-current` fallback`` を ``via a 2-tier fallback (issue-scoped pointer file → PGID pointer file, which is ignored when it was written before its process-group leader started, #1491); the `.tmp/auto-session-current` fallback`` にする。アンカー: `process-group leader started`
   - `docs/ja/product.md` の同じ行 (`Session ID (`AUTO_SESSION_ID`)`) で、`2 段階フォールバック (issue-scoped ポインタファイル → PGID ポインタファイル) で解決される。` の直後に `PGID ポインタファイルは、そのプロセスグループのリーダーが起動する前に書かれたものを採用しない (#1491)。` を足す。括弧は半角で前後に半角スペースを入れる (グローバル規約)。アンカー: `リーダーが起動する前`
   - 実装後に `bash scripts/check-translation-sync.sh` で `docs/ja/product.md` が IN_SYNC になることを確認する (commit 後にだけ正確)
5. (after 1, 2, 3, 4) 検証を通す (→ AC3)
   - `bash -n scripts/emit-event.sh`、`bash scripts/check-forbidden-expressions.sh`、`skills/code/language-convention-check.md` の手順 (CI の `language-convention` job と同じ検査)、`bash scripts/check-bare-bracket-assertions.sh` (新規テストに bare assertion が無いこと)
   - bats があれば `bats tests/emit-event.bats tests/emit-skill-event.bats tests/run-fact-matching.bats tests/run-auto-sub.bats` (`restore_auto_session_pointer` を使うテスト) の後に全件 `bats tests/`。無ければ、素の bash での確認 (Step 2 の末尾) を代替にし、全件は push 後の CI の `Run bats tests` job に任せる

## Verification

### Pre-merge

- <!-- verify: rubric "PGID ごとの pointer ファイル .tmp/auto-session-<PGID> について、残存による誤帰属を防ぐ仕組み (使用後の削除、作成時刻や所有プロセスの検証、古いファイルの掃除など) が scripts または modules/event-emission.md に実装・記載されている" --> PGID pointer の残存による誤帰属を防ぐ仕組みがある
- <!-- verify: rubric "誤帰属が起きた経路 (PGID の再利用で古い pointer を拾う) が再現または否定され、その結果が Spec か modules/event-emission.md に記録されている" --> 仮説の経路が検証されている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 並行セッションが稼働する中で `/auto --batch` を実行し、`get-auto-session-report.sh` の Sub-Issue Completion Timeline に、そのセッションが処理していない Issue が現れないことを観察する <!-- verify-type: observation event=auto-run when=mode:batch -->
  - Expected output structure:
    - Timeline の各 Issue 行は、(i) その batch の対象 Issue、または (ii) そのセッション自身が起動した入れ子の `/verify` (`/review` の Event-based observation scan、終了時の observation dispatch) の対象 Issue のどちらかである。(ii) は batch 対象外なので `?/?` の行になるが、起動元が本セッションなので FAIL にしない
    - 別の並行セッションが処理した Issue は、そのイベントが別の `session_id` で記録されるため、この Timeline に現れない。確認は `.tmp/auto-events.jsonl` の `session_id` と `pr` フィールドで行う (`pr` が付いたイベントは、その PR の review / merge phase の子孫が出したもの)
    - 並行セッションが無かった run は SKIPPED (判定材料なし) とし、PASS にしない

## Notes

- **仮説の検証結果 (AC2 の記録。結論: インシデントでは否定、機構は再現)**:
  - 結論: 2026-10-03 のインシデントで #1365 / #1481 / #1484 のイベントが batch セッションの `session_id` で記録されたのは、PGID の再利用で残存 pointer が拾われたからではない。入れ子の `/verify` が review phase の環境を継承した結果で、起動元は本セッション自身 (誤帰属ではない)
  - 根拠 (すべて 2026-10-04 に確認):
    1. `pr` フィールド: 3 件の verify の `phase_start` / `retro_proposal_classified` (計 5 行。#1484 は review の終了に間に合わず `retro_proposal_classified` が無い) はすべて `"pr":1489`。`emit_event()` が `pr` を足すのは `EMIT_PR_NUMBER` が呼び出しプロセスの環境にあるときだけ (`scripts/emit-event.sh` の `if [[ -n "${EMIT_PR_NUMBER:-}" ]]`)。これは `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` (review / merge の PR 番号) と、自分で phase を持つ `scripts/run-review.sh` / `scripts/run-merge.sh` が export する。pointer の解決 (`restore_auto_session_pointer()`) が設定するのは `AUTO_SESSION_ID` と `AUTO_EVENTS_LOG` だけで、PGID pointer を採用した別セッションのプロセスに `pr: 1489` は付かない
    2. 機構の一致: `skills/review/SKILL.md` の Event-based observation scan (`observation-trigger.sh --event pr-review-light`) は、L2 / L3 で一致した Issue ごとに `Skill(skill="wholework:verify", args="$N")` を順次起動する。3 件はどれも `verify-type: observation event=pr-review-light` の AC を持つ (#1365 は `keyword=workflow`、#1481 と #1484 は `session=next`)。PR #1489 の review は light で、この repo は `autonomy: L3` (`.wholework.yml`)
    3. 時刻の一致 (UTC、2026-10-03): review phase の `phase_start` 01:26:56 → review 自身の Opportunistic Verification (`skill=/review` の `opportunistic_verify_result` 4 件) 01:37:10 → #1365 の `phase_start` 01:38:21 (`retro_proposal_classified` 01:42:51) → #1481 の `phase_start` 01:43:04 (同 01:45:54) → #1484 の `phase_start` 01:46:03 (最後の `opportunistic_verify_result` 01:48:16) → review の `wrapper_exit` 01:48:47。3 件は重ならず順次で、review の内側に収まる。各 verify の consumed-comments commit (`af6b569e` が #1365、`9390fe4c` が #1481、`7da3cbd5` が #1484) は `phase_start` の 14〜20 秒後に入っている
    4. 環境の継承: 入れ子の `/verify` は wrapper が export した `AUTO_EVENTS_LOG` / `AUTO_SESSION_ID` を継承する (`modules/event-emission.md` の `restore_auto_session_pointer()` の項)。`restore_auto_session_pointer()` は step 1 で返り、pointer は読まれない
    5. PGID の再利用は起きえない: メインリポジトリの `.tmp/` の数字だけの名前の pointer 36 件を mtime 順に並べると、PGID は 36.6 時間 (2026-10-02T16:37Z〜2026-10-04T05:15Z) にわたり厳密に増加する (逆転 0 件)。PID カウンタ (`kernel.pid_max` = 4194304) は一周していない。インシデント時刻 (JST 10:38〜10:46) のカウンタは、前後の pointer (JST 10:13:54 の PGID 715294 と JST 10:51:44 の 830334) から約 80 万で、同じ batch が同じ周回の中でそれ以前に作った pointer の PGID はすべてそれより小さい
    6. 本当に別のセッションは正しく記録されていた: 同じログの `393456-1790987493` (2026-10-03T00:31:33Z 開始) が #1112 / #1113 / #1125 / #1133 / #1139 を verify した 5 件 (01:25:46〜01:28:05) は、自分の `session_id` で、`pr` フィールド無しで記録されている。commit は `034c0a6d` `f5c88348` `40854d58` `6ffb3562` `d264aad1`
  - 機構の再現 (AC2 の「再現」側): Reproduction Steps のとおり、変更前は古い pointer が採用された。実装後は Implementation Step 2 のテスト (2) で固定する
  - 測定範囲と出所:
    - 5 行のイベント: `docs/sessions/190537-1790984033-2026-10-03/events.jsonl` (コミット済み、474 行) を `jq -c 'select(.issue==1365 or .issue==1481 or .issue==1484)'` で絞る
    - 時刻の突き合わせと別セッションの 5 件: メインリポジトリの `.tmp/auto-events.jsonl` (gitignore、2026-10-04 時点で 739 行。手元の `.tmp` にしか無く再取得できない) の 2026-10-03T01:25Z〜01:52Z。commit は `git log --since='2026-10-03T01:25:00Z' --until='2026-10-03T01:52:00Z' --format='%h %aI | %s' origin/main` で再取得できる (author の時刻は JST で出る)
    - 残存 pointer: メインリポジトリの `.tmp/` で `^auto-session-[0-9]+$` に一致する名前 (`auto-session-issue-N` `auto-session-current` `auto-session-<SID>.json` は除く) 36 件、2026-10-04 に測定。うち 14 件が `190537-1790984033` を含む。`kernel.pid_max` は実行環境の値 (`/proc/sys/kernel/pid_max`)。batch もこの環境で動いた
- **Issue 本文と実装の食い違い** (light のため記録のみ):
  - Issue 本文の Background は、#1365 / #1481 / #1484 の verify を「別セッションが実行した」とするが、上のとおり本セッション自身の `/review` が起動した入れ子の `/verify` だった。同じ時間帯に別セッションの verify も実在した (#1112 など 5 件、別の `session_id`)。L3 session retrospective が 3 件を別セッション由来と読んだのは、batch 対象 8 件に無い Issue で、`concurrent_commit_detected` (review の終了時に 6 件の verify commit が並ぶ) と時間帯が重なったため
  - 仮説 (PGID の再利用) は Issue 本文でも「未検証」と書かれ、AC2 がその検証を求めている。結果は否定。AC1 の「仕組み」は、実在し再現できた機構の予防として実装する。Issue の AC の文言は変えない (要件は `/issue` が確定済み)
  - Post-merge の観察 AC は、この変更の効果を測るものではない。PGID の再利用は起きにくく、入れ子の `/verify` (review の observation scan、終了時の observation dispatch) の Issue は `?/?` の行として今後も Timeline に現れる。起動元が本セッションなので誤帰属ではない。判定の目安は Post-merge の `Expected output structure`。結果は変更の有無によらず PASS になる見込みが高いので、AC の文言の見直しは `/verify` の振り返りで判断してよい
- **設計の判断 (所有者の検証を採る理由と不採用案)**:
  - 採用: 読み取り時の検証 (pointer の mtime が process group リーダーの起動より後か)。理由は (1) 非破壊で何度読んでも同じ結果になる (同じ Bash 呼び出しの中で複数の emit が同じ pointer を読みうる。読み取りで消す案はそれを壊す)、(2) 書き込み側 (`skills/auto/SKILL.md` と `modules/orchestration-fallbacks.md` にある `printf` の手順。LLM が実行する) を変えずに済む、(3) リーダーの起動時刻は PID が再利用されても前の持ち主の値とは別物なので、PGID の再利用そのものを見分けられる
  - 不採用 (使用後の削除): wrapper の EXIT trap で消す案は、外部 kill (SIGKILL / OOM。このプロジェクトで頻発) で trap が走らず残存が残るので、結局検証が要る。最初の reader が消す案は、同じ Bash 呼び出しの中の後続の読み取りから pointer を奪う。`/auto` の再生成は「呼び出しごとに 1 回書く」前提で、2 回目以降の読み取りを救う手当てが無い
  - 不採用 (古いファイルの掃除): 検証で残存 pointer は無害になるので必須ではない。掃除は削除という副作用を足し、基準 (何時間で古いとするか) の根拠も要る。単体では PGID の再利用 (PID 空間の小さい環境では分単位) を防げない。必要なら別 Issue
  - 不採用 (固定の経過時間の上限): 数分で pointer を捨てる案は、長時間続く Bash 呼び出しの後の読み取りで正当な pointer を落とす。リーダーの経過時間との比較なら、呼び出しが何時間続いても正当な pointer は通る (テスト (7) が固定する)
  - 不採用 (pointer の内容に owner token を持たせる): 書き込み側が複数 (SKILL.md の手順を LLM が実行する) で、旧形式の pointer も残るので、読み取り側だけで完結する検証を選んだ
  - slack の値 (60 秒): 正当な pointer は `now - mtime <= elapsed` を満たす (リーダーの起動後に書かれるため)。slack が吸収するのは、`ps` と mtime の 1 秒の粒度と、小さな時計のずれだけ。PGID を再利用するには PID カウンタの一周が要り、最短でも分単位なので、60 秒は防御を弱めない
- **スコープの境界 (意図的に変えないもの。follow-up 候補)**:
  1. 5 つの `run-*.sh` と `run-auto-sub.sh` (2 か所) の inline な `cat ".tmp/auto-session-${PGID}"`: `/auto` 経由では、同じ Bash 呼び出しの中で pointer を書き直した直後に読むので、常に現在のセッションの値になる。残存 pointer に当たりうるのは手動の wrapper 起動だけで、`restore_auto_session_pointer()` 経由の読み取りより呼び出し回数が桁違いに少ない。変えない最大の理由はテスト: wrapper が `read_pgid_pointer` を呼ぶには `source emit-event.sh` を pointer の読み取りより前に移す必要があり、wrapper のテストが `$MOCK_DIR/emit-event.sh` に置く per-test の stub (`cat > "$MOCK_DIR/emit-event.sh"` が 7 ファイルで 65 件。測定: `grep -c -E 'cat > "\$MOCK_DIR/emit-event.sh"'` を `tests/run-auto-sub.bats` `run-merge.bats` `run-spec.bats` `run-code.bats` `run-review.bats` `run-issue.bats` `auto-sub-observability.bats` に実行した合計) が `read_pgid_pointer` を持たないので、すべて更新が要る。#1317 系の 5 ファイルのテスト (各 4〜5 件) は wrapper の該当行を inline で再掲して検証しており (wrapper 本体を呼ばない)、本体を変えるとテストと本体が食い違う。別 Issue で stub の更新とテストの置き換えを合わせて扱う
  2. issue-scoped pointer (`.tmp/auto-session-issue-<N>`): 所有 process が無く、比べる起点が無い。standalone の `/verify` は #1075 の自己修復 (`--persist-session ""`) で消す。standalone の `/spec` `/code` `/review` `/issue` が `emit-skill-event.sh <N> ...` を呼ぶと、同じ Issue の古い issue-scoped pointer を採用しうる、同種の残存リスクがある (2026-10-04 時点で 32 件が残存)。TTL が要る別の設計なので別 Issue
  3. 入れ子 `/verify` の Timeline 上の見せ方: `get-auto-session-report.sh` は batch 対象外の Issue を `?/?` の行で出し、`pr` には親の review の PR 番号が付く。今回の誤読の原因なので、行に observation dispatch 由来であることを示す、または入れ子の `/verify` に `pr` を継承させない、という改善の余地がある。観測の見せ方の問題で pointer とは別なので、`/verify` の振り返りで拾う
- **fail-safe 重要度の判定: 該当 (基準 (c))**: `read_pgid_pointer()` / `restore_auto_session_pointer()` は「失敗時に安全側の既定値 (session_id なし) を返す」設計で、`2>/dev/null` / `|| echo ''` / `|| true` を含む。pointer を採用するか棄却するかを決める点でゲート・検証器の性格も持つ。境界条件 (空入力、大きな入力、特殊文字、依存コマンドの失敗) は Implementation Step 1 に明記した。要点は、判定できないときは採用しない (fail-closed。#1224 / #1317 と同じ方針) ことと、どの失敗経路も `return 0` で `set -e` の呼び出し元を abort させないこと
- **新規テストケース (必須)**: `restore_auto_session_pointer` に新しい分岐 (棄却) が入るので、既存スイートが PASS するだけでなく、新規ロジックを検証する新規テストを `tests/emit-event.bats` に足す (Implementation Step 2 の 8 件)。実装前に 7 件が FAIL し (1 件は退行ガードで実装前も PASS)、実装後に 8 件が PASS する。
  - bats test の入力形式: pointer ファイル = 1 行の session id (`echo "<sid>" > .../auto-session-424242`)。PGID は `ps` の mock で 424242 に固定する (`ps -o pgid=` の問い合わせに 424242、`ps -o etime=` の問い合わせに `MOCK_ETIME` (既定 `10:00`、設定済みで空なら「プロセスなし」) を返す)。pointer の mtime は `touch -t` で操作する (`202401010000` = 古い、指定なし = 今)。経過時間の比較 (7) は `date -d "N days ago"` (GNU) / `date -v-Nd` (BSD) で作った `touch -t` 用の文字列を使う。assertion は `[ ... ] || false` 形式。`@test` 名は ASCII の英語
  - パターン検出 script のテスト fixture による自己参照、`WHOLEWORK_SCRIPT_DIR` の mock、新規 script の追加は無いので、それらの確認項目は該当しない
- **プロトタイプによる事前検証 (2026-10-04)**: Implementation Step 1・2 の字面どおりのコードとテストを、実ファイルを変えずに `scripts/emit-event.sh` の一時コピーへ適用して確認した (いずれも素の bash。bats は無い)。(1) Step 2 の 8 件を bats 風の簡易ハーネスで実行: 変更前は 7 件が FAIL (test 1 のみ PASS)、変更後は 8 件が PASS。(2) 既存の `tests/emit-event.bats` 25 件は変更前後で同じ結果 (24 件はスタブ `git`、`git worktree` を使う 1 件 (#1006) は実 `git` で確認、いずれも PASS)。(3) 変更後のコピーは `bash -n` が通る。(4) `etime` のパースは `00:00` `05:12` `08:09` `01:05:12` `09:09:09` `2-03:04:05` `10-00:00:00` `1-18:18:45` を正しく読み、`""` `abc` `12` `1:2:3:4` `aa:bb` `-05:00` `1-` を拒否した。(5) `set -euo pipefail` の下で、古い pointer・pointer なしのどちらも abort しない。字面を変える場合は、境界条件 (Implementation Step 1) とテスト (Step 2) を保つこと
  - ハーネスの注意: `if ( ... ); then` の中では `set -e` が無効になり、失敗した assertion を見逃す (最初の版で全件 PASS と誤判定した)。素の bash で確認する場合は、サブシェルを if の外で実行して終了ステータスを取ること
- **bats が未インストール**: この環境の `command -v bats` は何も出力しない (2026-10-04。`shellcheck` も無い)。この Issue は pr route なので、`/code` が bats を実行できなくても、push 後の CI の `Run bats tests` job と `/review` の CI 参照が代わりに確認する。`/code` は上の素の bash での確認を代替にし、Code Retrospective に「bats 未実行」と書く
- **外部仕様の確認 (出所: 2026-10-04 取得)**:
  - POSIX `ps` の `etime`: "In the POSIX locale, the elapsed time since the process was started, in the form: [[dd-]hh:]mm:ss" (出所: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/ps.html)。`pgid` は "The decimal value of the process group ID."。この環境 (Linux procps、ロケールは日本語) の `ps -o etime=` が `00:00` と `1-18:18:45` を返すことを確認した。macOS (BSD `ps`) の実機は未確認 (Uncertainties)
  - mtime の取得: `scripts/gh-graphql.sh` の `is_cache_valid` と同じ、`uname` が `Darwin` かどうかの分岐 (`stat -f '%m'` / `stat -c '%Y'`) を使う。GNU の `stat -f` は別の意味 (ファイルシステム情報) で mtime が取れないので、BSD 形式を先に試す書き方は取らない (2026-10-04 に確認: GNU で `stat -f '%m' file` は失敗する)
  - PGID の性質: この環境では各 Bash 呼び出しが独立した process group になり、`$$` と PGID が同じ値になる (`ps -o pid=,pgid=` で確認)。リーダーが生きている間、その PID は別の process group に再割り当てされない
- **ツール検出パターンの一貫性**: `stat` の OS 分岐は `scripts/gh-graphql.sh` の既存の形式に揃えた。`ps -o ... -p` の形は wrapper の `ps -o pgid= -p $$ | tr -d ' '` に揃えた。新しい検出方式は導入しない
- **verify command の扱い**: Pre-merge の 3 件は Issue 本文 (SSoT、`modules/verify-patterns.md` §18) をそのまま写した。AC1 / AC2 の rubric には数値リテラル・定数名が無いので、`file_contains` の併記は要らない。決定的な裏付けは Implementation Step 2 のテストと、`modules/event-emission.md` の追記が担う。AC3 の `command "bats tests/"` は全件実行で、`modules/verify-patterns.md` §24 のとおり `command` の 60 秒では収まらない。pr route なので `/review` が PR の CI (`Run bats tests` job) を参照して確定する (`modules/verify-executor.md` § "CI Reference Fallback")。Issue の文言は変えない
- **verify-type の確認 (Post-merge)**: `observation` (`event=auto-run when=mode:batch`) は `modules/verify-classifier.md` の定義 (特定の event の発火後に評価する) に合う。「並行セッションが稼働する中で」という前提は保証されない (Firing Likelihood Check) が、`.tmp/auto-events.jsonl` の `session_id` で並行セッションの有無を確認でき、証拠 (Timeline の行と `session_id` / `pr`) は記述できる。`modules/verify-classifier.md` の方針 (observation は 2 部構成で書く) に従い、Spec 側の Post-merge に `Expected output structure` を足した。Issue 本文の AC は変えない
- **Size の再評価**: 確定の Changed Files は 5 件 (`scripts/emit-event.sh`、`tests/emit-event.bats`、`modules/event-emission.md`、`docs/product.md`、`docs/ja/product.md`)。軸 1 は M (3-5 件)。軸 2 は script ロジックの変更で +1、既存関数の局所的な硬化で原因と方式が検証済みで -1、相殺して M。triage 時の Size M から変更なし (pr route)。CI Dependency Minimum Override は該当しない (CI workflow・並列実行・共有 fixture の変更なし。新規テストは per-test の mock だけを使う)
- **その他の確認結果**:
  - 監査・調査型の Issue ではない (機構の修正が主で、AC2 は仮説 1 件の検証。複数の既存項目を分類して判定を残す型ではない)。Notes に書いた識別子 (`restore_auto_session_pointer` `persist_auto_session_pointer` `Event-based observation scan` `EMIT_PR_NUMBER` `run_phase_with_recovery` など) は、すべて 2026-10-04 に grep で実在を確認した
  - 外部 package の追加なし (依存バージョンの確認は不要)。adapter パターンの調査は不要 (verify command は built-in の `rubric` / `command` のみ)。credential / security に関わる設計は無い。UI は無い (Step 9 は対象外)
  - allowed-tools impact chain check: 新規の `scripts/*.sh` は無い。`modules/*.md` の変更は軽量ゲートが機械的に発火する (追記する本文が `scripts/emit-event.sh` などのパスに言及する) ので、読み手を列挙した (`grep -rl "modules/event-emission.md" skills/*/SKILL.md`: `skills/audit/SKILL.md` `skills/auto/SKILL.md` `skills/verify/SKILL.md`)。この変更は新しい script の呼び出しを導入しない (関数の追加だけ) ので、`allowed-tools` の更新は要らない
  - 追記する本文の制約: `scripts/` `modules/` は英語指定のパスで日本語を含めない (`scripts/check-language-convention.py`)。非推奨語 (`docs/product.md` § Terms の Formerly called) を使わない (`scripts/check-forbidden-expressions.sh` は `docs/spec/` `modules/` `tests/` も走査する。`/auto` の旧称は大文字始まりの 1 語が対象なので、本文では小文字の dispatch を使う)。`docs/ja/product.md` は日本語で、括弧は半角、前後に半角スペース
- **未確認事項 (Uncertainties。検証方法と影響範囲)**:
  - macOS の `ps -o etime=` の実機の出力形式: POSIX の定義どおり `[[dd-]hh:]mm:ss` と想定する (BSD `ps` も同じ形式の想定)。CI の macOS job は `bash -n` だけで実行はしない。想定と違う場合は `_process_elapsed_seconds` が空を返し、step 4 は常に fail-closed になる (PGID pointer 経路が使えず、`--write-manual-recovery` の `session_id` が欠落する。誤帰属はしない)。検証は macOS での手動確認 (`ps -o etime= -p $$` と新テスト (4) の実行)。影響範囲は Implementation Step 1 のみ
  - 時計の不連続 (NTP の step、VM の resume): 時計が呼び出しの途中でずれると、その 1 回の判定が fail-closed 側に倒れうる (`session_id` の欠落で、誤帰属はしない)。許容する。slack 60 秒を超えるずれは稀
  - sandbox 実行 (呼び出しごとに PID namespace が新しい環境) での挙動: 未検証。pointer は書き直された直後で新しく、残存 pointer は古いので、判定は同じ向きに働くと想定する。影響範囲は step 4 の読み取りのみ

## Consumed Comments

No new comments since last phase.
