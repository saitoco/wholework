# Issue #1499: auto: /review が dispatch した nested /verify を concurrent commit と誤検知し、timeline でも batch 対象と区別できない

## Overview

`/review` の Event-based observation scan は、autonomy L2 / L3 で `pr-review-light` などの observation event に一致した Issue へ `Skill(skill="wholework:verify", ...)` を nested dispatch する。この nested `/verify` が `/auto --batch` の記録に残す跡について、次の 3 つを直す。

1. nested `/verify` が作る commit (subject に別 Issue 番号を含む) が、`scripts/run-auto-sub.sh` の `concurrent_commit_detected` に「並行セッションの commit」として計上される
2. nested `/verify` の `phase_start` だけが記録され、`phase_complete` が記録されない。`scripts/get-auto-session-report.sh` の Sub-Issue Completion Timeline に、終了時刻が「?」の行として現れる
3. Sub-Issue Completion Timeline で、batch 対象の Issue と nested dispatch された Issue が区別なく並ぶ

phase 内の nested dispatch を、並行セッションや誤帰属と区別できるようにして、session report と run facts を正しく読めるようにする。

## Reproduction Steps

実ログ (2026-10-05 に確認。出所と測定範囲は Notes の「調査の出所と測定範囲」) で次のように再現する。

1. `/auto --batch` が pr route の Issue を処理する (例: session `1123127-1791088655` の #1491)。その `/review` (PR #1498) の Event-based observation scan が、一致した #1365 / #1481 / #1484 の `/verify` を順次 nested dispatch する
2. `.tmp/auto-events.jsonl` に、nested の `phase_start` (phase=verify、`"pr":1498`) が 3 件残る。対応する `phase_complete` は、nested の `phase_start` 8 件を含むログ全体で 1 件も無い (Root Cause 2)
3. nested `/verify` が main に入れた commit (`Add consumed comments fallback for issue #1365 (verify phase)` など) が、review phase の終了時に `concurrent_commit_detected` として 3 件 emit される。subject が別 Issue 番号を含むので、3-way 分類 (#1427) の (b) に落ちる
4. `get-auto-session-report.sh 1123127-1791088655 --metrics-only --no-github` の Sub-Issue Completion Timeline で、#1365 / #1481 / #1484 が batch 対象 (#1491 など) と同じ表に、終了時刻 `?` の行として並ぶ

## Root Cause

三つの現象は「review phase の内側で nested `/verify` が走る」ことから出るが、原因はそれぞれ別にある。

1. **誤検知**: `run_phase_with_recovery()` の per-commit 分類 (#1427) は、commit subject の `#N` だけで自己判定する。nested `/verify` の commit は別 Issue の番号を持つので (b) に落ちる。一方、events log には nested dispatch を示す情報が既にある。nested `/verify` の `phase_start` は、親 phase の wrapper が export した `EMIT_PR_NUMBER` を `emit_event()` が継承して、親 phase の PR 番号を `pr` に持つ (`modules/event-emission.md` の #1491 の項が示す機構)。分類がこれを読んでいない
2. **`phase_complete` の欠落**: `run-*.sh` の wrapper は `AUTO_EVENTS_LOG` を CWD 相対の既定値 `.tmp/auto-events.jsonl` のまま export する。nested `/verify` はこれを継承し、`restore_auto_session_pointer()` は step 1 (「`AUTO_EVENTS_LOG` が設定済みなら何もしない」) で返るので、相対パスのまま使う。`/verify` の emit 位置ごとの CWD は次のとおりで、worktree の中で emit したものだけが、worktree 内の `.tmp/auto-events.jsonl` に書かれて Worktree Exit で捨てられる

   | emit 位置 | CWD | main の log に届くか |
   |---|---|---|
   | Step 1 `phase_start` | main repo root (`/review` は Worktree Exit の後に nested dispatch する) | 届く |
   | Step 11 `phase_complete` (と Step 8b の `verify_executability`、FAIL 分岐の `verify_fail_marker_posted` など) | Step 3 の Worktree Entry の後 = `verify/issue-N` worktree | **届かない** |
   | Step 14 `opportunistic_verify_result` | Step 13 の Worktree Exit の後 = main repo root | 届く |

   実ログも同じ形になっている (`phase_start` と `opportunistic_verify_result` (`skill=/verify`、`pr` 付き) はあるが、`phase_complete` は 0 件)。素の bash でも再現した (Notes)。#1006 の「`AUTO_EVENTS_LOG` は CWD に依存させない」原則を、`AUTO_EVENTS_LOG` が未設定で pointer から導く場合にだけ適用し、wrapper 由来の相対パスが設定済みの場合を取りこぼしている
3. **timeline の区別なし**: `get-auto-session-report.sh` は `sub_start` / `phase_*` を持つ Issue を全て同じ表の行にする。`pr` を持つ `phase_start` の情報を、行の区別に使っていない

## Changed Files

- `scripts/run-auto-sub.sh` (bash 3.2+ 互換。既存関数の変更のみ): `run_phase_with_recovery()` の `concurrent_commit_detected` ブロックを 3-way から 4-way に広げる (Implementation Step 1)
  - ブロック直前のコメント (`# Per-commit classification is 3-way (issue #1427)` で始まる塊) を、4-way の説明に差し替える
  - `local _any_issue_pattern="#[0-9]+([^0-9]|$)"` の直後に、nested dispatch の Issue 番号の集合から `_nested_pattern` を作るブロックを足す
  - commit ごとの分類に、(a) の判定の直後、(c) の判定の前に (d) を足す
- `tests/run-auto-sub.bats`: 新規 2 件を、`concurrent_commit_detected: an unrelated commit is still detected during review/merge phase (issue #974)` の直後、`review/merge phase events emit issue=<real Issue number> and pr=<PR number> (issue #987)` の直前に足す (Implementation Step 1)
- `scripts/emit-event.sh` (bash 3.2+ 互換。既存関数の変更のみ): `restore_auto_session_pointer()` の step 1 を、設定済みの相対パスを main repo root に固定する形に変える。関数の上のコメントも更新する (Implementation Step 2)
- `tests/emit-skill-event.bats`: 新規 2 件を、ファイル末尾 (`missing sibling emit-event.sh exits 1 with an error on stderr` の後) に足す (Implementation Step 2)
- `scripts/get-auto-session-report.sh` (bash 3.2+ 互換): Sub-Issue Completion Timeline に、nested dispatch の Issue だけを載せる別表を足す (Implementation Step 3)
- `tests/get-auto-session-report.bats`: 新規 3 件を、ファイル末尾 (`at-risk threshold falls back to phase default when no override is configured` の後) に足す (Implementation Step 3)
- `modules/event-emission.md`: 3 か所を更新する。resolution order の item 1、`**Worktree-CWD independence (Issue #1006)**` の段落の末尾、`**Hypothesis check for the 2026-10-03 misattribution report (Issue #1491)**` の段落の直後 (Implementation Step 4)
- `docs/reports/event-log-schema.md`: `### 4. concurrent_commit_detected` の `**Emission point**` の段落の直後に、除外の段落を足す (Implementation Step 4)
- [Steering Docs sync candidate] keyword "restore_auto_session_pointer" (この Issue が変更する関数名) skipped: matched 49 files (no discriminating power)。測定範囲: `grep -rl "restore_auto_session_pointer" docs/ tests/ scripts/ modules/` (全ファイル、除外なし、2026-10-05)
- [Steering Docs sync candidate] keyword "concurrent_commit_detected" (振る舞いが変わる event 名) skipped: matched 107 files (no discriminating power)。測定範囲は同じ
- [Steering Docs sync candidate] keyword "Sub-Issue Completion Timeline" (出力が変わる節の名前) skipped: matched 67 files (no discriminating power)。測定範囲は同じ
- [Steering Docs sync candidate] keyword "AUTO_EVENTS_LOG" (扱いが変わる環境変数) skipped: matched 96 files (no discriminating power)。測定範囲は同じ
- [Steering Docs sync candidate] keyword "run-auto-sub.sh" skipped: matched 299 files、"get-auto-session-report.sh" skipped: matched 83 files、"emit-event.sh" skipped: matched 110 files (いずれも no discriminating power。測定範囲は同じ)
- 上のキーワードはすべて判別力が無いので、個々の hit は評価していない。`modules/event-emission.md` と `docs/reports/event-log-schema.md` は、変更する振る舞いを直接記述している文書として、記述を読んで特定した (キーワードの hit からではない)
- [Outbound pointer sync candidate] なし: 変更する file が指す先を確認した。`scripts/emit-event.sh` のコメントが指す `modules/event-emission.md` は、すでに Changed Files にある。`modules/event-emission.md` が指す `skills/auto/SKILL.md` (Step 1 / Step 6 の pointer 再生成、L3 retrospective の「Parallel race detected」) と `skills/verify/SKILL.md` (emit 位置) は、この変更で記述が古くならない (Notes)。`docs/reports/event-log-schema.md` が指す先は、足す段落が指す `modules/event-emission.md` だけ
- Listing-side sub-check: 発火しない (subcommand の追加・削除なし、file の追加・削除・改名なし、ディレクトリ構成の変更なし)。`docs/structure.md` と `README.md` は対象外
- 変更しない (確認済み):
  - `docs/workflow.md` / `docs/ja/workflow.md`: 「Issues processed」の文は、batch / XL の Issue と observation dispatch の `/verify` 再実行が合計では区別されないこと、`sub_start` の有無で見分けられることを述べる。この変更は合計の数え方を変えず、文は正しいまま
  - `skills/audit/SKILL.md` の Output Template Structure の項目 3 (「per-issue phase breakdown table (...)」): 別表を足しても、この説明は正しいまま
  - `docs/structure.md` / `docs/ja/structure.md`: Key Files の `scripts/emit-event.sh` と `scripts/get-auto-session-report.sh` の行は公開関数と節の概要だけを述べる。新しい公開関数は無い
  - `skills/verify/SKILL.md` / `skills/review/SKILL.md`: emit 位置と dispatch の手順は変えない。修正は `emit-skill-event.sh` が呼ぶ共通の関数にある (`/verify` の emit 位置はすべて `emit-skill-event.sh` 経由)
  - `skills/auto/SKILL.md`: L3 retrospective の XL route の「Parallel race detected (`concurrent_commit > 0`)」は、XL route の並列 sub-issue 同士 (同じ session) の commit が `concurrent_commit_detected` として数えられることに依る信号である。新しい分類は、`pr` が一致する nested dispatch だけを除外するので、この信号は保たれる (Notes の「設計の判断」)
  - `scripts/collect-run-facts.sh` / `scripts/hook-worktree-path-guard.sh`: 同じ相対パスの問題を持つ隣接箇所だが、この Issue の範囲外 (Notes の「スコープの境界」)

## Implementation Steps

各 Step の (a) は新規テスト、(b) は実装。**(a) を先に追加して、変更前の実装に対して FAIL することを確認してから (b) に進む** (Triage の注意喚起への対応。Notes 参照)。この Spec のコードとテストは、実ファイルを変えずに一時コピーへ字面どおり適用して確認した (結果は Notes の「プロトタイプによる事前検証」)。

1. `scripts/run-auto-sub.sh` と `tests/run-auto-sub.bats` を編集する (→ 受け入れ条件 1, 4)

   **(a)** `tests/run-auto-sub.bats` に新規 2 件を足す (Changed Files の位置。`@test` 名の `issue #1499` は、他のテストの `issue #974` と同じ書き方)。

```bash
@test "concurrent_commit_detected: a commit of a nested-dispatched Issue is not emitted during the review phase (issue #1499)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export AUTO_SESSION_ID="session-1499"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
read_pgid_pointer() { cat "\$1" 2>/dev/null || true; }
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Mock run-review.sh: while the review phase runs, a /verify nested in it (for another Issue,
    # #1365) records its phase_start. In production emit_event() adds the "pr" field from the
    # EMIT_PR_NUMBER that run_phase_with_recovery exports for review/merge phases, so the nested
    # event carries this review phase's PR number (99 under the default gh mock).
    cat > "$MOCK_DIR/run-review.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_REVIEW_LOG"
printf '{"ts":"%s","issue":1365,"event":"phase_start","session_id":"%s","pr":%s,"phase":"verify"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AUTO_SESSION_ID" "$EMIT_PR_NUMBER" >> "$AUTO_EVENTS_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-review.sh"

    # Mock git: origin/main has one commit whose subject names the nested Issue (#1365), like the
    # consumed-comments commit a nested /verify makes.
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  echo "eee5555 Test User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"eee5555"* ]]; then
  echo "Add consumed comments fallback for issue #1365 (verify phase)"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    # Positive control: before any nested phase_start exists (code-pr phase) the same commit is
    # still flagged, so the fixture does reach the emit path.
    grep -q "concurrent_commit_detected phase=code-pr commit_sha=eee5555" "$BATS_TEST_TMPDIR/emit.log"
    # The review phase recorded the nested phase_start, so its commit is not a concurrent commit.
    ! grep -q "concurrent_commit_detected phase=review " "$BATS_TEST_TMPDIR/emit.log"
}

@test "concurrent_commit_detected: nested exclusion does not hide sibling sub-issues, other sessions or earlier windows (issue #1499)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export AUTO_SESSION_ID="session-1499"
    export EMIT_ISSUE_NUMBER="42"

    # Recorded long before this run: same session and same PR number, but outside the review
    # phase window (#2002).
    printf '%s\n' '{"ts":"2020-01-01T00:00:00Z","issue":2002,"event":"phase_start","session_id":"session-1499","pr":99,"phase":"verify"}' > "$AUTO_EVENTS_LOG"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
read_pgid_pointer() { cat "\$1" 2>/dev/null || true; }
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Mock run-review.sh records three phase_start events during the review phase:
    #   #1365: nested /verify of this session (inherits this phase's PR number) -> excluded
    #   #2001: a parallel sibling sub-issue of the same session (no pr field)  -> still detected
    #   #2003: another session's run that happens to carry the same PR number -> still detected
    cat > "$MOCK_DIR/run-review.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_REVIEW_LOG"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"ts":"%s","issue":1365,"event":"phase_start","session_id":"%s","pr":%s,"phase":"verify"}\n' "$NOW" "$AUTO_SESSION_ID" "$EMIT_PR_NUMBER" >> "$AUTO_EVENTS_LOG"
printf '{"ts":"%s","issue":2001,"event":"phase_start","session_id":"%s","phase":"code-patch"}\n' "$NOW" "$AUTO_SESSION_ID" >> "$AUTO_EVENTS_LOG"
printf '{"ts":"%s","issue":2003,"event":"phase_start","session_id":"other-session","pr":%s,"phase":"verify"}\n' "$NOW" "$EMIT_PR_NUMBER" >> "$AUTO_EVENTS_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-review.sh"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  printf '%s\n' "eee5555 Test User" "fff6666 Test User" "ggg7777 Test User" "hhh8888 Test User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"eee5555"* ]]; then
  echo "Add consumed comments fallback for issue #1365 (verify phase)"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"fff6666"* ]]; then
  echo "chore: patch (closes #2001)"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"ggg7777"* ]]; then
  echo "chore: patch (closes #2002)"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"hhh8888"* ]]; then
  echo "chore: patch (closes #2003)"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "concurrent_commit_detected phase=review commit_sha=fff6666" "$BATS_TEST_TMPDIR/emit.log"
    grep -q "concurrent_commit_detected phase=review commit_sha=ggg7777" "$BATS_TEST_TMPDIR/emit.log"
    grep -q "concurrent_commit_detected phase=review commit_sha=hhh8888" "$BATS_TEST_TMPDIR/emit.log"
    ! grep -q "concurrent_commit_detected phase=review commit_sha=eee5555" "$BATS_TEST_TMPDIR/emit.log"
}
```

   変更前の実装では、2 件とも最後の否定 assertion (`! grep -q "... phase=review ..."`) で FAIL する (nested の commit が review phase で emit されるため)。

   **(b)** `scripts/run-auto-sub.sh` の `run_phase_with_recovery()` を 3 か所編集する。

   1 つ目: `# Per-commit classification is 3-way (issue #1427)` から `# same-phase WIP commit by subject alone) for eliminating this false-positive class.` までのコメントを、次に差し替える (他の行は変えない)。

```bash
  # Per-commit classification is 4-way (issues #1427, #1499): a self-issue-number match is
  # always self (a); a commit whose subject references an Issue that a skill nested in this
  # phase worked on is that nested dispatch's own commit (d); a commit whose subject
  # references some *other* issue number is a true concurrent commit (b); a commit whose
  # subject references no issue number at all is assumed to be this phase's own free-form
  # intermediate commit (c) — e.g. the Step 8 "commit after each step completes" WIP commits
  # `/code` patch route makes, which carry no #N reference until the final Step 11 commit.
  # (c) trades detection of genuinely concurrent no-issue-number commits (rare, and
  # indistinguishable from a same-phase WIP commit by subject alone) for eliminating this
  # false-positive class.
```

   2 つ目: `local _any_issue_pattern="#[0-9]+([^0-9]|$)"` の直後に、次を足す。

```bash
    # (d) nested dispatch (issue #1499): Issues whose phase_start was recorded while this phase
    # ran, by a descendant of this phase's wrapper. emit_event() adds the "pr" field from the
    # EMIT_PR_NUMBER exported above for review/merge phases, so a skill nested in this phase
    # (e.g. the /verify that /review's Event-based observation scan dispatches) records its
    # phase_start with this phase's PR number, the same session_id and its own Issue number.
    # Requiring the PR number keeps parallel sibling sub-issues of the same session (no "pr",
    # or another PR's) detectable as concurrent. Any failure leaves the set empty, which keeps
    # the classification as it was before: this is an observability signal, not a gate, so a
    # missed exclusion only costs a misleading event while a wrong exclusion would hide one.
    local _nested_pattern="" _nested_alts="" _nested_issue
    if [[ -n "${EMIT_PR_NUMBER:-}" && -n "${AUTO_SESSION_ID:-}" && -f "${AUTO_EVENTS_LOG:-}" ]]; then
      while IFS= read -r _nested_issue; do
        [[ "$_nested_issue" =~ ^[0-9]+$ ]] || continue
        _nested_alts="${_nested_alts:+${_nested_alts}|}${_nested_issue}"
      done <<< "$(grep "\"session_id\":\"${AUTO_SESSION_ID}\"" "${AUTO_EVENTS_LOG}" 2>/dev/null \
        | jq -rs --argjson pr "${EMIT_PR_NUMBER}" --argjson self "${EMIT_ISSUE_NUMBER}" --argjson since "${PHASE_START}" \
            '[.[] | select(.event == "phase_start" and .pr == $pr and .issue != $self and ((.ts | try fromdateiso8601 catch 0) >= $since)) | .issue] | unique | .[]' 2>/dev/null || true)"
      if [[ -n "$_nested_alts" ]]; then
        _nested_pattern="#(${_nested_alts})([^0-9]|$)"
      fi
    fi
```

   3 つ目: commit ごとの分類で、`if [[ "$_subject" =~ $_self_issue_pattern ]]; then continue; fi` の直後 (`if [[ ! "$_subject" =~ $_any_issue_pattern ]]; then` の前) に、次を足す。

```bash
      if [[ -n "$_nested_pattern" && "$_subject" =~ $_nested_pattern ]]; then
        continue
      fi
```

   境界条件 (fail-safe 重要度の判定は Notes): events log が無い、空、`AUTO_SESSION_ID` / `EMIT_PR_NUMBER` が空、`jq` が失敗する、のどれでも nested の集合は空になり、分類は変更前と同じになる (commit は emit される)。集合に入るのは `jq` が返した整数だけで (`^[0-9]+$` で再確認する)、正規表現に特殊文字は入らない。commit subject は `=~` で照合するだけで、どこにも埋め込まない。

2. `scripts/emit-event.sh` と `tests/emit-skill-event.bats` を編集する (→ 受け入れ条件 2)

   **(a)** `tests/emit-skill-event.bats` の末尾に新規 2 件を足す。1 件目は実 `git` で main repo と linked worktree を作り (`tests/emit-event.bats` の #1006 のテストと同じ流儀。`git` の mock はしない)、wrapper 由来の相対パスで linked worktree の CWD から emit する。2 件目は git 外の CWD で相対パスが変わらないことを固定する (変更前も PASS する退行ガード)。

```bash
@test "a relative AUTO_EVENTS_LOG inherited from a wrapper is anchored to the main repo root when emitting from a linked worktree (issue #1499)" {
    # Models a nested /verify dispatched from /review: run-*.sh export the CWD-relative default
    # AUTO_EVENTS_LOG, and the skill's own Worktree Entry moves the CWD into a linked worktree
    # before its phase_complete emit. The event must reach the main repo's log, not a
    # worktree-local file that is discarded at Worktree Exit.
    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    git init -q "$MAIN_REPO"
    git -C "$MAIN_REPO" config user.email "test@example.com"
    git -C "$MAIN_REPO" config user.name "Test"
    echo "init" > "$MAIN_REPO/file.txt"
    git -C "$MAIN_REPO" add -A
    git -C "$MAIN_REPO" commit -q -m init
    # Resolve to the real path (e.g. macOS /tmp -> /private/tmp) so it matches `git worktree list`.
    MAIN_REPO="$(cd "$MAIN_REPO" && pwd -P)"
    LINKED_WORKTREE="$BATS_TEST_TMPDIR/linked_wt"
    git -C "$MAIN_REPO" worktree add -q -b worktree-verify+issue-1365 "$LINKED_WORKTREE"

    run bash -c "cd \"$LINKED_WORKTREE\" && export AUTO_EVENTS_LOG=.tmp/auto-events.jsonl AUTO_SESSION_ID=sid-1499 && bash \"$SCRIPT\" 1365 phase_complete phase=verify"
    [ "$status" -eq 0 ] || false
    [ -f "$MAIN_REPO/.tmp/auto-events.jsonl" ] || false
    run jq -r '.event' "$MAIN_REPO/.tmp/auto-events.jsonl"
    [ "$output" = "phase_complete" ] || false
    [ ! -e "$LINKED_WORKTREE/.tmp/auto-events.jsonl" ] || false
}

@test "a relative AUTO_EVENTS_LOG stays relative to the CWD outside a git repository (issue #1499)" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=.tmp/auto-events.jsonl AUTO_SESSION_ID=sid-1499 && bash \"$SCRIPT\" 1365 phase_start phase=verify"
    [ "$status" -eq 0 ] || false
    run jq -r '.event' "$WORKDIR/.tmp/auto-events.jsonl"
    [ "$output" = "phase_start" ] || false
}
```

   変更前の実装では、1 件目が FAIL する (event が `$LINKED_WORKTREE/.tmp/` に書かれ、`$MAIN_REPO/.tmp/auto-events.jsonl` が無い)。

   **(b)** `scripts/emit-event.sh` を 3 か所編集する (コメントは英語。`scripts/` は英語のパス)。

   1 つ目: `restore_auto_session_pointer()` の上のコメントの resolution order の item 1 (アンカー: `#   1. AUTO_EVENTS_LOG already set             -> no-op, return 0 (existing behavior preserved)`) を、次に差し替える。

```bash
#   1. AUTO_EVENTS_LOG already set             -> keep it and return 0 (existing behavior preserved);
#                                                  a relative value is first anchored to the main
#                                                  repo root (Issue #1499, see below)
```

   2 つ目: 同じコメントの末尾 (`# the previous CWD-relative behavior. bash 3.2+ compatible.` の行) の直後、関数の定義の前に、空のコメント行を 1 つ挟んで次を足す。

```bash
#
# Issue #1499: the rule above only covered an AUTO_EVENTS_LOG derived from a pointer file.
# run-*.sh wrappers export the CWD-relative default `.tmp/auto-events.jsonl`, and a skill
# nested in a wrapper phase (e.g. the /verify that /review dispatches) inherits it, so step 1
# used to keep the relative value. Once that skill entered its own worktree the value resolved
# inside the worktree, and every later event (phase_complete, ...) went to a worktree-local
# file that is discarded at Worktree Exit. Step 1 now anchors a relative value to the main
# repo root with the same `git worktree list --porcelain` idiom.
```

   3 つ目: 関数の先頭 (アンカー: `  [[ -n "${AUTO_EVENTS_LOG:-}" ]] && return 0` の 1 行) を、次に差し替える。この後の `local _root` 以降は変えない。

```bash
  if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
    if [[ "${AUTO_EVENTS_LOG}" != /* ]]; then
      local _anchor
      _anchor="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || _anchor=""
      if [[ -n "${_anchor}" ]]; then
        AUTO_EVENTS_LOG="${_anchor}/${AUTO_EVENTS_LOG#./}"
        export AUTO_EVENTS_LOG
      fi
    fi
    return 0
  fi
```

   境界条件 (fail-safe 重要度の判定は Notes): 絶対パスは変えない。git の外 (bats の tmpdir など) では `git worktree list` が失敗して `_anchor` が空になり、相対パスのまま残る (従来の挙動)。`git worktree list` の失敗は `|| _anchor=""` で受けるので、`set -e` と `pipefail` の呼び出し元を abort させない。パスに `./` の接頭辞があれば取り除く。

3. `scripts/get-auto-session-report.sh` と `tests/get-auto-session-report.bats` を編集する (→ 受け入れ条件 3, 4, および 2 の代替側)

   **(a)** `tests/get-auto-session-report.bats` の末尾に新規 3 件を足す。1・2 件目は変更前に FAIL する。3 件目は「batch 対象でもある Issue は batch の表に残る」「nested が無ければ別表の見出しが出ない」ことを固定する退行ガード (変更前も PASS する)。

```bash
@test "Timeline: an Issue dispatched inside another Issue's review phase is listed apart from batch targets, with no unknown end time (issue #1499)" {
    # Models session 1123127-1791088655: the review of #1491 (PR #1498) ran a nested /verify for
    # #1365. Its phase_start carries the review's PR number in "pr", and it never recorded a
    # phase_complete.
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-10-04T05:30:00Z","issue":100,"event":"sub_start","session_id":"session-nested","size":"M"}
{"ts":"2026-10-04T05:31:00Z","issue":100,"event":"phase_start","session_id":"session-nested","phase":"code-pr"}
{"ts":"2026-10-04T05:50:00Z","issue":100,"event":"phase_complete","session_id":"session-nested","phase":"code-pr"}
{"ts":"2026-10-04T06:00:00Z","issue":100,"event":"phase_start","session_id":"session-nested","pr":900,"phase":"review"}
{"ts":"2026-10-04T06:14:00Z","issue":200,"event":"phase_start","session_id":"session-nested","pr":900,"phase":"verify"}
{"ts":"2026-10-04T06:20:00Z","issue":100,"event":"phase_complete","session_id":"session-nested","pr":900,"phase":"review"}
{"ts":"2026-10-04T06:21:00Z","issue":100,"event":"sub_complete","session_id":"session-nested","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-nested" --metrics-only --no-github
    [ "$status" -eq 0 ]
    batch_rows="$(echo "$output" | sed -n '/^### Sub-Issue Completion Timeline/,/^#### Nested dispatch/p')"
    nested_rows="$(echo "$output" | sed -n '/^#### Nested dispatch/,/^### Token Usage Aggregate/p')"
    echo "$batch_rows" | grep -q "| #100 |"
    if echo "$batch_rows" | grep -q "| #200 |"; then false; fi
    echo "$nested_rows" | grep -q "| #200 | #100 review (PR #900) |"
    echo "$nested_rows" | grep -q "(completion not recorded)"
    if echo "$nested_rows" | grep -q "– ?"; then false; fi
}

@test "Timeline: a nested Issue that recorded phase_complete shows its end time and phase duration (issue #1499)" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-10-04T05:30:00Z","issue":100,"event":"sub_start","session_id":"session-nested-done","size":"M"}
{"ts":"2026-10-04T06:00:00Z","issue":100,"event":"phase_start","session_id":"session-nested-done","pr":900,"phase":"review"}
{"ts":"2026-10-04T06:14:00Z","issue":200,"event":"phase_start","session_id":"session-nested-done","pr":900,"phase":"verify"}
{"ts":"2026-10-04T06:18:00Z","issue":200,"event":"phase_complete","session_id":"session-nested-done","pr":900,"phase":"verify"}
{"ts":"2026-10-04T06:20:00Z","issue":100,"event":"phase_complete","session_id":"session-nested-done","pr":900,"phase":"review"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-nested-done" --metrics-only --no-github
    [ "$status" -eq 0 ]
    nested_row="$(echo "$output" | grep "| #200 |")"
    [[ "$nested_row" == *"| #100 review (PR #900) |"* ]]
    [[ "$nested_row" == *"2026-10-04T06:14:00Z – 2026-10-04T06:18:00Z"* ]]
    [[ "$nested_row" == *"verify 4m"* ]]
    if [[ "$nested_row" == *"(completion not recorded)"* ]]; then false; fi
}

@test "Timeline: a batch target that was also dispatched nested stays among batch targets, and no nested table appears without nested events (issue #1499)" {
    # #300 is a batch target of its own (sub_start + code-patch) and is also dispatched once from
    # #100's review. It must stay a batch row: only an Issue whose every phase_start is nested counts
    # as a nested dispatch. #100's own review phase_start carries "pr" too but is a review phase.
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-10-04T05:00:00Z","issue":300,"event":"sub_start","session_id":"session-both","size":"S"}
{"ts":"2026-10-04T05:01:00Z","issue":300,"event":"phase_start","session_id":"session-both","phase":"code-patch"}
{"ts":"2026-10-04T05:10:00Z","issue":300,"event":"phase_complete","session_id":"session-both","phase":"code-patch"}
{"ts":"2026-10-04T06:00:00Z","issue":100,"event":"sub_start","session_id":"session-both","size":"M"}
{"ts":"2026-10-04T06:01:00Z","issue":100,"event":"phase_start","session_id":"session-both","pr":900,"phase":"review"}
{"ts":"2026-10-04T06:14:00Z","issue":300,"event":"phase_start","session_id":"session-both","pr":900,"phase":"verify"}
{"ts":"2026-10-04T06:20:00Z","issue":100,"event":"phase_complete","session_id":"session-both","pr":900,"phase":"review"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-both" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "| #300 |"
    echo "$output" | grep -q "| #100 |"
    if echo "$output" | grep -q "^#### Nested dispatch"; then false; fi
}
```

   **(b)** `scripts/get-auto-session-report.sh` を 4 か所編集する (出力の文字列は既存の表と同じく英語。見出しの `Nested dispatch` の `dispatch` は小文字にする。大文字始まりの旧称は `scripts/check-forbidden-expressions.sh` に検出される)。

   1 つ目: `# Sub-Issue Completion Timeline — per-issue with Route, Phase breakdown, PR, Recovery, Notes` の 1 行を、次の 4 行のコメントに差し替え、`COMPLETION_TIMELINE_TABLE=""` の行の直後に `NESTED_TIMELINE_TABLE=""` を足す。結果は次のとおり (`ISSUE_NUMS_FOR_TABLE=...` の行は変えない)。

```bash
# Sub-Issue Completion Timeline — per-issue with Route, Phase breakdown, PR, Recovery, Notes.
# Issues that only ran as a skill nested inside another Issue's review/merge phase (e.g. the
# /verify that /review's Event-based observation scan dispatches) are listed in a separate
# "Nested dispatch" table instead of among the batch targets (issue #1499).
ISSUE_NUMS_FOR_TABLE=$(echo "$PROCESSED_ISSUES_JSON" | jq -r '.[]' 2>/dev/null || true)
COMPLETION_TIMELINE_TABLE=""
NESTED_TIMELINE_TABLE=""
```

   2 つ目: ループの中、`[[ -z "$_phase_breakdown" ]] && _phase_breakdown="—"` の直後 (`  # PR lookup` の前) に、次を足す。

```bash
  # Nested dispatch detection (issue #1499). emit_event() adds a "pr" field only from the
  # EMIT_PR_NUMBER exported by the review/merge phase wrappers, so a phase_start that carries
  # "pr" but is neither a review nor a merge phase was emitted by a skill nested in another
  # Issue's phase, and its "pr" is that parent phase's PR number. An Issue is a nested dispatch
  # only when every phase_start it recorded is of that kind and it has no sub_start: a batch
  # target that was also dispatched nested stays among the batch targets.
  _is_nested=$(echo "$_issue_events" | jq -r '
    def nested_start: .event == "phase_start" and .pr != null and (.phase != "review" and .phase != "merge");
    ([.[] | select(nested_start)] | length) as $n_nested |
    ([.[] | select(.event == "sub_start" or (.event == "phase_start" and (nested_start | not)))] | length) as $n_other |
    ($n_nested > 0 and $n_other == 0)
  ' 2>/dev/null || echo "false")
  if [[ "$_is_nested" == "true" ]]; then
    # Parent phase: the review/merge phase_start of another Issue that carries the same "pr".
    _parent=$(echo "$EVENTS_JSON" | jq -r --argjson n "$_num" '
      ([.[] | select(.issue == $n and .event == "phase_start" and .pr != null) | .pr] | first) as $pr |
      if $pr == null then "?"
      else
        ([.[] | select(.event == "phase_start" and .pr == $pr and .issue != $n and (.phase == "review" or .phase == "merge"))] | sort_by(.ts) | first) as $p |
        if $p == null then "PR #\($pr)" else "#\($p.issue) \($p.phase) (PR #\($pr))" end
      end
    ' 2>/dev/null || echo "?")
    [[ "$_last_ts" == "?" ]] && _last_ts="(completion not recorded)"
    NESTED_TIMELINE_TABLE+="| #${_num} | ${_parent} | ${_first_ts} – ${_last_ts} | ${_phase_breakdown} |
"
    continue
  fi
```

   3 つ目: ループの後、`[[ -z "$COMPLETION_TIMELINE_TABLE" ]] && COMPLETION_TIMELINE_TABLE="| (no events) | — | — | — | — | — | — |"` の直後に、次を足す。

```bash
NESTED_TIMELINE_SECTION=""
if [[ -n "$NESTED_TIMELINE_TABLE" ]]; then
  NESTED_TIMELINE_SECTION="#### Nested dispatch (inside another Issue's phase)

| Issue | Parent phase | Duration | Phase breakdown |
|---|---|---|---|
${NESTED_TIMELINE_TABLE}"
fi
```

   4 つ目: 出力のテンプレートで、`${COMPLETION_TIMELINE_TABLE}` の行と `### Token Usage Aggregate` の見出しの間の空行 1 行を、`${NESTED_TIMELINE_SECTION}` の行に置き換える (別表が無いときの出力は、変更前と同じ行数になる)。

```
${COMPLETION_TIMELINE_TABLE}
${NESTED_TIMELINE_SECTION}
### Token Usage Aggregate
```

   境界条件: `_is_nested` の `jq` が失敗したら `false` になり、従来どおり batch の表に出る。`_parent` の `jq` が失敗したら `?` を出す。`phase_complete` が無い nested の行は、終了時刻に `(completion not recorded)` を出す (`?` は出さない)。`backfilled` の `phase_complete` は従来どおり `(backfilled)` の注記が付く。nested の行は `gh pr list` の PR 探索を行わない。

4. (after 1, 2, 3) ドキュメントを更新する (→ SHOULD: 文書の整合。追記する本文は英語)

   **`modules/event-emission.md`** を 3 か所編集する。

   1 つ目: resolution order の item 1 (`no-op, return immediately (existing behavior preserved)` を含む行) を、次の 1 行に差し替える。

```markdown
1. `AUTO_EVENTS_LOG` already set — keep it and return immediately (existing behavior preserved). A relative value (the `run-*.sh` wrappers export the CWD-relative default `.tmp/auto-events.jsonl`) is first anchored to the main repository root, see "Worktree-CWD independence" below (Issue #1499)
```

   2 つ目: `**Worktree-CWD independence (Issue #1006)**` の段落の末尾 (`preserving the prior CWD-relative fallback.` の後) に、次の文を同じ段落の続きとして足す (先頭に半角スペース 1 つ)。

```markdown
 Issue #1499 extended the same independence to an `AUTO_EVENTS_LOG` that is already set. The `run-*.sh` wrappers export the CWD-relative default and a skill nested in a wrapper phase inherits it, so resolution order step 1 used to keep the relative value: once the nested `/verify` entered its own worktree (Step 3), every later emit — `phase_complete` at Step 11, `verify_executability`, `verify_fail_marker_posted` — resolved inside that worktree and was discarded with it, while `phase_start` (Step 1) and the Step 14 events, emitted from the main repository root, reached the main log. Step 1 now anchors a relative value to the main repository root with the same `git worktree list --porcelain` idiom; an absolute value is left untouched, and outside a git repository the relative value is kept.
```

   3 つ目: `**Hypothesis check for the 2026-10-03 misattribution report (Issue #1491)**` の段落の直後に、空行を挟んで次の段落を足す。

```markdown
**Nested skill dispatch inside a phase (Issue #1499)**: a skill that runs nested in a `review` / `merge` phase (today the `/verify` that `/review`'s Event-based observation scan dispatches at autonomy L2/L3) inherits the phase wrapper's `AUTO_SESSION_ID` and `EMIT_PR_NUMBER`, so its events carry the batch session's `session_id` and the parent phase's PR number in `pr` — and no other process records that `pr` for an Issue other than the one the phase belongs to. Two consumers rely on this signature. `scripts/run-auto-sub.sh` (`run_phase_with_recovery()`) does not emit `concurrent_commit_detected` for a commit whose subject references an Issue that recorded `phase_start` with the phase's PR number, in the phase's session, after the phase started; a parallel sibling sub-issue of the same session carries no matching `pr`, so its commits stay detectable. `scripts/get-auto-session-report.sh` lists an Issue whose every `phase_start` carries `pr` and is neither a `review` nor a `merge` phase (and which has no `sub_start`) in a separate "Nested dispatch" table under Sub-Issue Completion Timeline, with the parent phase resolved from the `review`/`merge` `phase_start` that carries the same `pr`; an Issue that is also a batch target of its own stays among the batch targets. A skill nested in a phase that exports no `EMIT_PR_NUMBER` (every phase other than review and merge) is identified by neither consumer.
```

   **`docs/reports/event-log-schema.md`** を 1 か所編集する。`### 4. concurrent_commit_detected` の `**Emission point**` の段落の直後に、空行を挟んで次の段落を足す。

```markdown
**Exclusions**: a commit is not counted when (a) its subject references this phase's own Issue number (for review/merge phases both the PR number and the originating Issue number, Issues #895 and #974), (b) its subject references no Issue number at all, which is taken as this phase's own intermediate commit (Issue #1427), or (c) its subject references an Issue that a skill nested in this phase worked on, identified from a `phase_start` event of the same session that carries this phase's PR number in `pr` (Issue #1499, see `modules/event-emission.md`). A commit that references any other Issue number is emitted.
```

5. (after 1, 2, 3, 4) 確認する

   - `bats` が使える環境では `bats tests/run-auto-sub.bats tests/emit-skill-event.bats tests/get-auto-session-report.bats` の後に `bats tests/` を実行する。使えない環境 (この環境は未インストール) では、各 Step の (a) と (b) の両方を実行したことを Code Retrospective に書き、`bash -n` を 3 つの script に実行し、push 後の CI の `Run bats tests` job に全件の確認を委ねる (pr route。`/review` が CI を参照する)
   - 各 Step の (a) で、新規テストが変更前の実装に対して FAIL することを確認し、結果を Code Retrospective に書く。期待は次のとおり: `run-auto-sub.bats` の 2 件が FAIL、`emit-skill-event.bats` の 1 件目が FAIL (2 件目は PASS)、`get-auto-session-report.bats` の 1・2 件目が FAIL (3 件目は PASS)
   - `scripts/` と `modules/` の追記に日本語が無いこと (`scripts/check-language-convention.py`)、非推奨語が無いこと (`scripts/check-forbidden-expressions.sh`) を確認する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の concurrent_commit_detected 判定が、同じ phase の実行中に同じ session_id で phase_start を記録した Issue (nested dispatch された Issue) の番号を subject に持つ commit を並行 commit として扱わない" --> nested dispatch の commit が `concurrent_commit_detected` に計上されない
- <!-- verify: rubric "nested dispatch された /verify の phase_complete 欠落について、原因 (emit されない経路) が特定され、phase_complete が記録されるように修正されているか、または get-auto-session-report.sh の Sub-Issue Completion Timeline が phase_complete を欠く nested dispatch の Issue を終了時刻「?」の行として扱わない" --> nested `/verify` の完了が記録される、または timeline で終了時刻「?」の行として現れない
- <!-- verify: rubric "scripts/get-auto-session-report.sh の Sub-Issue Completion Timeline が、batch 対象の Issue と nested dispatch された Issue (phase_start の pr フィールドで親 phase と対応づけられるもの) を区別して表示する" --> nested dispatch された Issue が、Sub-Issue Completion Timeline で batch 対象と区別して表示される
- <!-- verify: rubric "tests/run-auto-sub.bats に、nested dispatch された Issue の commit が concurrent_commit_detected として emit されないことを検証するテストケースがあり、tests/get-auto-session-report.bats に、timeline が nested dispatch を batch 対象と区別することを検証するテストケースがある" --> 上記の振る舞いを検証する回帰テストが追加されている (`tests/run-auto-sub.bats` / `tests/get-auto-session-report.bats`)
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 修正後の `/auto --batch` で pr route の Issue を含む実行 (`event=auto-run`、run facts が `mode:batch` かつ `route:pr` に一致) が行われ、その実行中に `/review` が nested `/verify` を dispatch した場合 (`.tmp/auto-events.jsonl` に、`pr` フィールド付きで `phase=verify` の `phase_start` がある) に、その commit が `concurrent_commit_detected` に計上されず、Sub-Issue Completion Timeline でも batch 対象と区別されることを観察する。nested dispatch が発生しなかった実行では判定せず、SKIPPED として次の実行を待つ <!-- verify-type: observation event=auto-run when=mode:batch,route:pr -->
  - Expected output structure:
    - 判定の材料: その実行の `session_id` で `phase=verify`、`pr` 付きの `phase_start` が 1 件以上ある。無ければ SKIPPED (判定しない)
    - (1) その nested の Issue 番号を subject に持つ commit について、親の review phase の `concurrent_commit_detected` (`phase=review`、`pr` が親と同じ) が無い。commit の subject は `git log -1 --format=%s <commit_sha>` で確かめる。別セッションの commit (別の Issue の `/verify` など) の `concurrent_commit_detected` は残ってよい
    - (2) `get-auto-session-report.sh <session-id> --metrics-only` の Sub-Issue Completion Timeline に `#### Nested dispatch` の表があり、nested の Issue は batch 対象の表ではなくそこに、親の phase (`#<親 Issue> review (PR #<PR>)`) 付きで出る
    - (補足。判定には使わない) nested の行の終了時刻が `(completion not recorded)` ではなく実時刻なら、`phase_complete` の欠落 (Pre-merge の 2 番目) の修正が本番で効いている

## Notes

- **調査の出所と測定範囲** (2026-10-05 に測定。`modules/measurement-scope.md` に従う):
  - 実ログ: メインリポジトリの `.tmp/auto-events.jsonl` (gitignore。1585 行。手元の `.tmp` にしか無く再取得できない)。ここから次を数えた
    - nested の `phase_start` (`select(.event=="phase_start" and .phase=="verify" and .pr!=null)`): ログ全体で 8 件。Issue が挙げる 3 session の 7 件 (`190537-1790984033` の #1365 / #1481 / #1484 (PR #1489)、`1123127-1791088655` の同 3 件 (PR #1498)、`1408775-1791113801` の #1481 (PR #1505)) に加え、2026-10-02T16:51:34Z の `29284-1790959046` の #1365 (PR #1483) が 1 件ある
    - nested の `phase_complete` (`select(.event=="phase_complete" and .phase=="verify" and .pr!=null)`): ログ全体で 0 件
    - 上の 3 session の review phase (PR #1489 / #1498 / #1505) の `concurrent_commit_detected`: 10 件。commit の subject を `git log -1 --format=%s <sha>` で確かめると、7 件は nested の Issue (#1365 / #1481 / #1484) の consumed-comments commit (誤検知)、3 件 (`d264aad1` #1139、`6ffb3562` #1133、`40854d58` #1125) は別セッション (`393456-1790987493`) の `/verify` の commit で本物の並行 commit (#1491 の Notes と一致)
  - 新しい除外ルールを、この 10 件に実際に当てて確かめた。nested の集合は session ごとに `{1365,1481,1484}` / `{1365,1481,1484}` / `{1481}` になり、7 件の誤検知はすべて除外され、別セッションの 3 件は除外されずに残る (本物の並行 commit を隠さない)
  - 同じ集合に、窓 (nested の `phase_start` より後)、PR 番号 (別の PR)、session (別の `session_id`)、自 Issue (self=#1365 と仮定) を変えた反例を当てて、いずれも nested の Issue が集合から外れることを確かめた
  - Timeline の nested 判定 (Implementation Step 3 の `jq`) を 3 session の処理済み Issue すべて (計 38 件) に当てて、nested と判定したのは上の 7 件だけで、batch 対象 (親の #1491 / #1479 / #1501 を含む) の誤判定は 0 件だった。親 phase は 7 件すべてで `#<親 Issue> review (PR #<PR>)` と解決された
- **原因 (Root Cause 2) の検証**: 次の 3 つで確かめた。(1) 実ログ: nested の `phase_start` (Step 1) と `opportunistic_verify_result` (Step 14。`skill=/verify`、`pr` 付き。例: session `1123127-1791088655` の 06:18:23Z の 12 件) は main の log にあり、`phase_complete` (Step 11) だけが無い。`/verify` の emit 位置と CWD の対応は Root Cause の表のとおりで、`skills/verify/SKILL.md` の Step の順序と `skills/review/SKILL.md` の「Worktree Exit の後に nested dispatch」の前提条件から導いた。(2) 素の bash での再現: 一時の git repo と linked worktree を作り、`AUTO_EVENTS_LOG=.tmp/auto-events.jsonl` (相対) で `scripts/emit-skill-event.sh 1365 phase_start phase=verify` を main の CWD から、`phase_complete` を linked worktree の CWD から実行すると、前者は `main/.tmp/auto-events.jsonl` に、後者は `wt/.tmp/auto-events.jsonl` に書かれた。(3) 修正後の複製で同じ操作をすると、両方が main の log に届く (テスト `emit-skill-event.bats` の 1 件目)
- **設計の判断**:
  - nested の識別 (採用): `pr` が一致する `phase_start` に限る。Issue の Background が示すとおり、nested のイベントは親 phase の `pr` を持つ。`pr` を付けるのは review / merge phase の wrapper が export する `EMIT_PR_NUMBER` だけなので (`modules/event-emission.md` の #1491 の項)、`pr` が親 phase の PR 番号と一致し `issue` が違う `phase_start` は、その phase の子孫が出したものと言える
  - 不採用 (同じ session かつ同じ phase の窓だけで nested とみなす): `pr` の条件が無いと、同じ session の並列 sub-issue (XL route) の `phase_start` も nested とみなされ、その commit が `concurrent_commit_detected` から消える。`skills/auto/SKILL.md` の L3 retrospective は、XL route で `concurrent_commit > 0` を「Parallel race detected」として扱っており、この信号が壊れる。Issue の rubric の文言 (「同じ phase の実行中に同じ session_id で phase_start を記録した Issue (nested dispatch された Issue)」) は、括弧の中の nested dispatch に絞った実装でも満たす (`pr` の一致は nested dispatch であることの条件)
  - 不採用 (commit message に目印を入れる): `/verify` の commit の書式を LLM が書く手順に足すことになり、書式のずれで再発する。events log の情報だけで足りる
  - `phase_complete` の修正位置 (採用): `restore_auto_session_pointer()` の step 1。#1006 が「CWD に依存させない」原則を置いた場所で、skill 側の emit はすべて `emit-skill-event.sh` 経由でここを通る。不採用 (wrapper が絶対パスを export): `run-*.sh` 5 本と `run-auto-sub.sh` の変更、それぞれのテストの既定値の期待が要り、手動の wrapper 起動にも効かない。不採用 (timeline だけで隠す): 取りこぼしを表示で隠すだけで、同じ原因で失われている他のイベント (`verify_executability`、`verify_fail_marker_posted` など) が失われたまま残る
  - Timeline の区別 (採用): 別表 `#### Nested dispatch`。列は `Issue | Parent phase | Duration | Phase breakdown`。不採用 (主表の Notes 列や Issue 列に印を付ける): nested の行が batch 対象の表に残り、`Size/Route` の `?/?` など batch 向けの列の意味が崩れる。不採用 (列を足す): 行のスキーマが変わり、既存の消費側 (L3 session.md、テストの行 grep) に影響する。実現方法 (区別列、マーカー、別表) は `/spec` が決めるとした Issue の Auto-Resolved Ambiguity Points に従った
  - nested の Issue の判定 (`_is_nested`): 「`phase_start` がすべて nested の形 (`pr` あり、phase が review でも merge でもない) で、`sub_start` が無い」。batch 対象でもある Issue は batch の表に残す (テスト 3 件目)。親 phase の review 自身の `phase_start` も `pr` を持つので、phase 名で区別する
- **スコープの境界 (意図的に変えないもの。follow-up 候補)**:
  1. `scripts/collect-run-facts.sh`: `EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"` を CWD 相対のまま読む。`/verify` の run fact の照合が worktree の CWD で動くと、nested の `/verify` では log が見つからず `mode: unknown` になりうる。同根の隣接箇所だが、AC の対象は emit 経路で、`collect-run-facts.sh` の `EVENTS_LOG` を固定するにはそのスクリプト用の新しいテストが要る。別 Issue
  2. `scripts/hook-worktree-path-guard.sh`: `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-$PARENT_REPO/.tmp/auto-events.jsonl}"` は、継承した相対パスをそのまま使う。同じ形の隣接箇所で、`worktree-path-block` の emit だけが対象。別 Issue
  3. `/auto` の終了時の observation dispatch (`skills/auto/SKILL.md`。親 session で `Skill(verify)` を直接起動する) の `/verify` は、wrapper の環境を継承せず `pr` を持たない。Timeline では従来どおり主表の `?/?` の行に出る (例: session `1123127-1791088655` の #1200 / #1213 / #1221 / #1224 / #1226)。AC の「nested dispatch」は `pr` で親 phase と対応づけられるものに限られているので、この Issue の対象外
  4. phase の内側で nested dispatch が起きても、`EMIT_PR_NUMBER` を export しない phase (review / merge 以外) では識別できない。現状、phase の内側で nested dispatch を行うのは `/review` の Event-based observation scan だけ (`grep -rn "Skill(skill=" skills/*/SKILL.md modules/*.md` を 2026-10-05 に確認した。`skills/auto/SKILL.md` と `skills/audit/SKILL.md` は親 session から直接起動し、wrapper の phase の内側で起動するのは `skills/review/SKILL.md` だけ)
  5. 過去のログの `concurrent_commit_detected` は書き換えない。過去の session の report には誤検知が残る (nested の `phase_complete` も戻らない)。新しい表示は、`phase_complete` が無い過去の nested の行を `(completion not recorded)` として表示する
  6. 主表の `(no events)` の既定行は、処理済み Issue が nested だけの session では、別表に行があっても出る。稀で害も小さいので変えない
- **#1491 の Post-merge 観察との関係**: #1491 の観察条件は、nested の `/verify` の Issue が Timeline に「`?/?` の行」として現れてよいとする。この変更の後は、`pr` 付きの nested の行は別表 `#### Nested dispatch` に出る。#1491 を判定するときは、別表の行を (ii) (そのセッション自身が起動した入れ子の `/verify`) として扱う。「そのセッションが処理していない Issue が現れない」という判定の本質は変わらない
- **Triage の注意喚起への対応** (Issue コメント https://github.com/saitoco/wholework/issues/1499#issuecomment-5981379525。検出力の確認の依頼): 新規テストは欠陥を再現する入力を使い、変更前の実装で FAIL するようにした。Spec 作成時に、一時コピーで次を確かめた: 新規 7 件のうち 5 件が変更前に FAIL (`run-auto-sub.bats` 2 件、`emit-skill-event.bats` の 1 件目、`get-auto-session-report.bats` の 1・2 件目)、残り 2 件 (`emit-skill-event.bats` の 2 件目、`get-auto-session-report.bats` の 3 件目) は「現状維持」の対照で変更前も PASS する。変更後は 7 件とも PASS。`/code` は Implementation Steps の (a) の順序で同じ確認を行い、結果を Code Retrospective に書く。コメントが提案した rubric AC (「新規テストが欠陥を再現する入力を使い、修正前の実装に対して FAIL する形になっている」) は、Issue 本文に追加していない。`/spec` は AC を増やさず、要件は Implementation Steps の (a) と上の確認で担保する。必要なら人が AC に足せる (Verification の Pre-merge と Issue 本文の件数は 5 件で一致させた)
- **fail-safe 重要度の判定: 該当 (基準 (c))**: `run-auto-sub.sh` の分類ブロックと `restore_auto_session_pointer()` は、失敗時に安全側の既定値を返す設計で、`|| true` / `2>/dev/null` を含み、commit を「並行」と数えるか、log の置き場所を決めるかを判定するゲートの性格を持つ。境界条件:
  - 空・大きな入力: events log が無い / 空 → nested の集合は空 (従来の分類)。大きな log は `grep` で session を絞ってから `jq` に渡す (`_maybe_emit_phase_complete` と同じ形)
  - 特殊文字 (`>` `"` 改行 CRLF 多バイト文字): 正規表現に入るのは `jq` が返した整数だけ (`^[0-9]+$` で再確認)。commit subject は照合するだけで埋め込まない。CRLF の行は `jq` が空白として読む。多バイトの subject でも `=~` は動く
  - 依存コマンドの失敗: `jq` / `grep` の失敗は `|| true` で空の集合になり、commit は従来どおり emit される。理由: この event は観測用の信号でゲートではないので、除外し損ねても誤解を招く event が 1 件増えるだけだが、誤って除外すると本物の並行 commit を隠す。`restore_auto_session_pointer()` は `git worktree list` が失敗したら相対パスのまま残す (従来の挙動) ので、新しい失敗経路はない。`|| _anchor=""` で `set -e` / `pipefail` の呼び出し元を abort させない
  - 部分的に書かれた最後の行 (他の process が追記中): `jq -s` の parse error になり空の集合になる (従来の分類)。`emit_event` は `flock` で行単位に追記するので、実際には稀
- **新規テストケース (必須)**: 新しい分岐 (nested の除外、nested 表の出力、相対パスの固定) が入るので、既存スイートが PASS するだけでなく、新規ロジックを検証する新規テストを足す (Implementation Steps の 7 件)
  - bats test の入力形式: events log は 1 行 1 JSON の JSONL (`{"ts":"2026-10-04T06:14:00Z","issue":200,"event":"phase_start","session_id":"<sid>","pr":900,"phase":"verify"}`)。`ts` は ISO 8601 の UTC で秒単位 (`date -u +%Y-%m-%dT%H:%M:%SZ`)。`run-auto-sub.bats` では、nested の `phase_start` を `run-review.sh` の mock が review phase の最中に `$AUTO_EVENTS_LOG` へ追記する (`pr` は mock が環境の `$EMIT_PR_NUMBER` から取る。本番の `emit_event()` と同じ継承)。`git` は mock で、`log origin/main` が commit 行 (`<sha> <author>`)、`log -1 ... <sha>` が subject を返す。`emit-event.sh` は per-test の stub で、`emit_event` の呼び出しを `emit.log` に書く (行の形: `emit_event concurrent_commit_detected phase=review commit_sha=<sha> author=... since_phase_start_sec=...`)
  - 否定の assertion は、最後の文にするか `if ...; then false; fi` にする (`set -e` は `!` の付いた非終端の文を無視するため)
  - `code-pr` phase と `merge` phase の判定は使わない。`code-pr` は `EMIT_PR_NUMBER` が無く nested の照会を行わないので、1 件目の「対照」(nested の commit が `code-pr` では検出される) にだけ使う。`merge` は、review の mock が書いた nested の `phase_start` と merge の開始が同じ秒に入ると判定が揺れるので、assertion に使わない
  - `emit-skill-event.bats` の `git` は mock せず実 git で repo と linked worktree を作る (`tests/emit-event.bats` の #1006 のテストと同じ流儀)。`WHOLEWORK_SCRIPT_DIR` の mock の追加と、パターン検出 script のテスト fixture による自己参照は、この Issue に該当しない (新規 script の追加なし、検出 script の追加なし)
- **プロトタイプによる事前検証 (2026-10-05)**: Implementation Steps のコードとテストを、実ファイルを変えずに `scripts/` と対象 3 つの bats ファイルの一時コピー (`.tmp/` の下。gitignore。完了時に削除) へ字面どおり適用して確認した。bats が無いので、`@test` / `setup` / `run` / `skip` / `$status` / `$output` を扱う簡易ランナーで実行した (bats 本体ではない)。(1) 変更前: 新規 7 件のうち 5 件が FAIL、2 件が PASS (対照)。(2) 変更後: 新規 7 件がすべて PASS。`run-auto-sub.bats` 101 件、`emit-skill-event.bats` 21 件、`emit-event.bats` 33 件、`get-auto-session-report.bats` 22 件、`audit-auto-session.bats` 9 件、`filter-session-verified-issues.bats` 5 件がすべて PASS。(3) 3 つの script は `bash -n` が通る。(4) 修正後の `get-auto-session-report.sh` を実ログの session `1123127-1791088655` に当てると、#1365 / #1481 / #1484 が `#### Nested dispatch` の表に `#1491 review (PR #1498)` 付きで出て、主表から外れる。字面を変える場合は、境界条件とテストを保つこと
  - 簡易ランナーの限界: `run-fact-matching.bats` の `apply-run-fact-match` の 3 件 (L3 / L1 の tier の判定) は、簡易ランナーでは変更前の実 repo でも FAIL する (今回の変更とは無関係。bats 本体との差による既存の事象と判断した)
- **bats が未インストール**: この環境の `command -v bats` は何も出力しない (2026-10-05。`shellcheck` も無い)。この Issue は pr route なので、`/code` が bats を実行できなくても、push 後の CI の `Run bats tests` job と `/review` の CI 参照が代わりに確認する。`/code` は Implementation Step 5 の代替確認を行い、Code Retrospective に「bats 未実行」と書く
- **外部仕様の確認 (出所: 2026-10-05 取得)**:
  - git: `git worktree list` について "The main worktree is listed first, followed by each of the linked worktrees." と "The first attribute of a worktree is always `worktree`, an empty line indicates the end of the record." (出所: https://git-scm.com/docs/git-worktree)。`awk '/^worktree /{print $2; exit}'` が最初の `worktree` の行 = main worktree のパスを取る前提と一致する。`--porcelain` に `-z` を付けると、改行を含むパスを扱える (今回は使わない。既存の同じ idiom (#1006、`detect-foreign-worktree.sh`、`run-code.sh`) に揃えた)。パスに空白があると `$2` で切れる制約も既存の idiom と同じ
  - jq: `fromdateiso8601` は "parses datetimes in the ISO 8601 format to a number of seconds since the Unix epoch" で、`"2015-03-05T23:51:47Z"` の形を受ける。`try EXP catch EXP` は式が失敗したときに 2 つ目の式を実行する。`--argjson name JSON-text` は JSON のテキストを変数として渡し、`-s` は入力全体を 1 つの配列として 1 回だけ実行する (出所: https://jqlang.org/manual/)。`.ts` が欠けても `try ... catch 0` で 0 になり、窓の外として扱われる
- **ツール検出パターンの一貫性**: 新しい検出方式は導入しない。main repo root の解決は `git worktree list --porcelain | awk ...` (`restore_auto_session_pointer()` と同じ)、events log の絞り込みは `grep "\"session_id\":\"...\"" | jq -rs` (`_maybe_emit_phase_complete()` と同じ) に揃えた
- **verify command の扱い**: Pre-merge の 5 件は Issue 本文 (SSoT、`modules/verify-patterns.md` §18) をそのまま写した。4 件の rubric には数値リテラル・定数名が無いので、`file_contains` の併記は要らない。決定的な裏付けは Implementation Steps のテストが担う。`command "bats tests/"` は全件実行で、`modules/verify-patterns.md` §24 のとおり `command` の 60 秒では収まらない。pr route なので `/review` が PR の CI (`Run bats tests` job) を参照して確定する (`modules/verify-executor.md` § "CI Reference Fallback")
- **verify-type の確認 (Post-merge)**: `observation` (`event=auto-run when=mode:batch,route:pr`) は `modules/verify-classifier.md` の定義に合い、Firing Likelihood Check (発火の可否) は、`when=` で絞り、nested dispatch が発生しなかった実行は SKIPPED とすると Issue の条件文が明記しているので満たす。`modules/verify-classifier.md` の方針 (observation は 2 部構成で書く) に従い、Spec 側の Post-merge に `Expected output structure` を足した。Issue 本文の AC は変えない。この変更は `skills/*/SKILL.md` を変えないので、`session=next` の要件 (`scripts/check-skill-change-observation-ac.sh`) は該当しない
- **Size の再評価**: 確定の Changed Files は 8 件 (`scripts/run-auto-sub.sh`、`tests/run-auto-sub.bats`、`scripts/emit-event.sh`、`tests/emit-skill-event.bats`、`scripts/get-auto-session-report.sh`、`tests/get-auto-session-report.bats`、`modules/event-emission.md`、`docs/reports/event-log-schema.md`)。軸 1 は L (6-10 件)。軸 2 は script ロジックの変更 (分岐の追加) で +1、原因が実ログと再現で検証済みの不具合修正で -1、相殺して L。triage 時の Size M から L に変わる (pr route のまま、review は `--full`)。CI Dependency Minimum Override は該当しない (CI workflow・並列実行・共有 fixture の変更なし)
- **その他の確認結果**:
  - 監査・調査型の Issue ではない (不具合の修正が主で、複数の既存項目を分類して判定を残す型ではない。Notes に書いた識別子 (`restore_auto_session_pointer` `run_phase_with_recovery` `EMIT_PR_NUMBER` `emit-skill-event.sh` `_maybe_emit_phase_complete` `Event-based observation scan` など) は、すべて 2026-10-05 に grep で実在を確認した)
  - Issue 本文と実装の食い違い: なし。Issue の Background の事実 (3-way 分類の (b) に落ちる、nested のイベントは親 phase の `pr` を持つ、`phase_complete` が無い) は、実装と実ログに一致する。Issue の Retrospective の調査メモ (欠落の原因は emit 経路側、`skills/verify/SKILL.md` Step 11 の各分岐は `phase_complete` を emit する) も一致し、経路は「Step 11 の emit が worktree 内の相対パスに書かれる」だった
  - 外部 package の追加なし (依存バージョンの確認は不要)。adapter パターンの調査は不要 (verify command は built-in の `rubric` / `command` のみ)。credential / security に関わる設計は無い。UI は無い (Step 9 は対象外)。MCP の呼び出しは無く、Smoke Test は無い
  - allowed-tools impact chain check: 新規の `scripts/*.sh` は無い。`modules/*.md` の変更は軽量ゲートが機械的に発火する (追記する本文が `scripts/run-auto-sub.sh` などのパスに言及する) ので、読み手を列挙した (`grep -rl "modules/event-emission.md" skills/*/SKILL.md agents/*.md`: `skills/audit/SKILL.md` `skills/auto/SKILL.md` `skills/verify/SKILL.md`)。この変更は新しい script の呼び出しを導入しない (記述の追加だけ) ので、`allowed-tools` の更新は要らない (`skills/verify/SKILL.md` は `emit-skill-event.sh:*` を既に持つ)
  - 追記する本文の制約: `scripts/` `modules/` は英語指定のパスで日本語を含めない (`scripts/check-language-convention.py`)。非推奨語 (`docs/product.md` § Terms の Formerly called) を使わない (`scripts/check-forbidden-expressions.sh` は `docs/spec/` `modules/` `tests/` `scripts/` も走査する。大文字始まりの旧称は検出されるので、出力の見出しや本文では小文字の `dispatch` (`Nested dispatch`) を使った)
  - `docs/ja/` の翻訳同期: 変更する文書は `modules/` と `docs/reports/` だけ。`docs/translation-workflow.md` の同期対象 (トップレベルの `docs/*.md`) に当たらないので、同期は要らない
- **未確認事項 (Uncertainties。検証方法と影響範囲)**:
  - nested `/verify` の emit 時の CWD は、実ログ・`skills/verify/SKILL.md` の Step の順序・素の bash の再現から導いたもので、nested のプロセスの環境を直接観察したものではない。検証は、修正の後に nested dispatch が起きた実行で、nested の `phase_complete` (`pr` 付き) が main の log に出ることの確認 (Post-merge の観察の補足)。影響範囲は Implementation Step 2
  - macOS (BSD) と bash 3.2 での実行は未確認: `<<< "$(...)"`、`${var#./}`、`[[ ... != /* ]]`、`jq` の `try ... catch` / `fromdateiso8601` は標準的な機能で、bash 3.2 と jq 1.5 以上で動く想定。CI の macOS job は `bash -n` だけで実行はしない (#1491 の Notes と同じ)。影響範囲は Step 1・2・3
  - 簡易ランナーは bats 本体ではない。bats 本体で初めて実行されるのは、push 後の CI。差が出た場合は `/code` か `/review` で直す。影響範囲は 7 件のテスト
  - `git worktree list --porcelain` の最初の `worktree` が main repo でない構成 (bare repo など) は未確認。#1006 の既存の idiom と同じ前提で、この Issue は新しい前提を足さない

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (曖昧点の自動解決と `/spec` への調査メモ。欠落の原因は emit 経路側の可能性が高い) / https://github.com/saitoco/wholework/issues/1499#issuecomment-5981366913
- saito / MEMBER / first-class / ℹ️ Triage AC audit (注意喚起: 新規テストの検出力。欠陥を再現する入力で修正前に FAIL することの確認の依頼) / https://github.com/saitoco/wholework/issues/1499#issuecomment-5981379525
