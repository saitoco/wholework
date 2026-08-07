# Issue #1224: event-emission: /auto を経ない実行での session_id 誤帰属を防ぐ

## Overview

`scripts/emit-event.sh` の `restore_auto_session_pointer()` は、`AUTO_SESSION_ID` / `AUTO_EVENTS_LOG` / issue-scoped ポインタ / PGID ポインタのいずれからも解決できない場合、最終段として `.tmp/auto-session-current` へ無条件にフォールバックする。この `current` ファイルは `/auto` Step 1 のみが書き込む PGID 非依存のグローバルファイルであり、`/auto` の session 初期化を経ずに `run-*.sh` を個別呼び出しし `/verify` を `Skill()` で直接起動するような手動オーケストレーション実行では、呼び出し元自身がこのファイルを書いたことは一度もない。そのため `current` へのフォールバックは、手動オーケストレーション実行にとって常に他セッション (並行実行中の別 `/auto` セッション、または過去に完了した別セッションの残留値) の ID を意味し、誤帰属を引き起こす。

本 Issue は、`restore_auto_session_pointer()` を fail-closed 化し (誤帰属より session_id 欠損を選ぶ)、あわせて手動オーケストレーション時の扱いを `modules/event-emission.md` に明文化する。案 A (fail-closed 化) と案 B (手動初期化手順の明文化) を採用し、案 C (`current` の鮮度判定) は Issue 本文の検討候補どおり閾値の恣意性を理由に不採用とする。

## Reproduction Steps

1. 親セッションが `/auto`（または `run-auto-sub.sh`）を起動せず、`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` を個別に呼び、`/verify` は `Skill()` で直接起動する (`/auto` Step 1 の session 初期化が一度も走らない)
2. この結果、`AUTO_SESSION_ID` env・issue-scoped ポインタ (`.tmp/auto-session-issue-<N>`)・この呼び出しの PGID に一致するポインタ (`.tmp/auto-session-<PGID>`) はいずれも存在しない (`/verify` の各 Bash tool 呼び出しは毎回新しい PGID を持つため)
3. 並行して別の `/auto` セッションが起動しており、その Step 1 が `.tmp/auto-session-current` を自身の session_id で上書きする
4. `/verify` の各 in-session emit 箇所が `source emit-event.sh; restore_auto_session_pointer $NUMBER` を呼ぶ。1-4 段目がすべて未解決のため最終段の `current` にフォールバックし、並行セッションの session_id を採用してしまう
5. `.tmp/auto-events.jsonl` に記録される event の `session_id` が誤った (並行) セッションに帰属する — 2026-08-07 の実測では 5 Issue (#1058, #1078, #1119, #1082, #1075) の event が影響を受け、帰属先が時系列で 3 回変化した

## Root Cause

`restore_auto_session_pointer()` の最終フォールバック段は `.tmp/auto-session-current` を「ポインタを持たない任意の呼び出し元にとっての有効な最終手段」として扱っている。しかし `current` は `/auto` Step 1 のみが書き込むファイルであり、他のどの経路からも書き込まれない。したがって `/auto` Step 1 を経ずにこの段まで到達した呼び出し元にとって、`current` の値が自分自身を指すことは構造的にあり得ない — 必ず「過去に完了した別セッションの残留値」か、並行実行下ではさらに悪いことに「現在動いている無関係な別セッションの値」のいずれかになる。この段を「見つからない場合は no-op」という既存方針 (`persist_auto_session_pointer`/issue-scoped 導入後、他の全段はこの設計) と同列に扱わず、`current` を特別に「一応使えるフォールバック」として残したことが誤帰属の構造的原因である。

## Changed Files

- `scripts/emit-event.sh`: change — `restore_auto_session_pointer()` から `.tmp/auto-session-current` フォールバック段を削除 (fail-closed 化)。関数直前の「Resolution order (exhaustive), Issue #1075」コメントを更新 — bash 3.2+ compatible
- `modules/event-emission.md`: change — 「Non-Wrapper Emitters」節の解決順序リストと「Concurrent-session attribution problem」段落を更新し、手動オーケストレーション時の扱いを追記
- `skills/audit/SKILL.md`: change — 「Session Boundary Identification」節の `.tmp/auto-session-current` の説明行を修正 (`restore_auto_session_pointer()` がこのファイルを最終フォールバックとして読む、という記述が本 Issue の変更後は不正確になるため)
- `tests/emit-event.bats`: change — 既存テスト2件 (Issue #902 由来・Issue #1006 由来) を fail-closed 後の挙動に合わせて修正 — bash 3.2+ compatible (bats は bash 上で動作)

**Steering Docs sync candidate 確認 (`docs/structure.md` / `docs/ja/structure.md`)**: `scripts/emit-event.sh` の説明行 (`emit_event()`/`restore_auto_session_pointer()`/`persist_auto_session_pointer()` の役割を一文で要約するのみで、個別の解決順序やフォールバック段を列挙していない) は本変更後も引き続き正確であり、更新不要と判断した。同じ行について Issue #1006・#1214 の Spec でも同様の結論に至っている (grep 確認済み)。

## Implementation Steps

1. `scripts/emit-event.sh` の `restore_auto_session_pointer()` を変更する。現在の PGID フォールバック行

   ```bash
   _sid="$(cat "${_prefix}.tmp/auto-session-${_pgid}" 2>/dev/null || cat "${_prefix}.tmp/auto-session-current" 2>/dev/null || echo '')"
   ```

   から `.tmp/auto-session-current` の参照を取り除き、

   ```bash
   _sid="$(cat "${_prefix}.tmp/auto-session-${_pgid}" 2>/dev/null || echo '')"
   ```

   とする。PGID ポインタも未解決なら、直後の既存ガード `[[ -z "${_sid}" ]] && return 0` によりそのまま no-op (fail-closed) となる。関数直前の「Resolution order (exhaustive), Issue #1075」コメント (現在 6 段: 1 AUTO_EVENTS_LOG 済設定 / 2 AUTO_SESSION_ID 済設定 / 3 issue-scoped / 4 PGID / 5 current / 6 該当なし) を 5 段 (1-4 は変更なし、5 は「該当なし → no-op、fail-closed。Issue #1224: 以前は `current` にフォールバックしていたが、`current` は `/auto` Step 1 のみが書き込むため、Step 1 を経ない呼び出し元を正しく特定することは構造的にできない」) に書き換える (→ AC1)

2. `modules/event-emission.md` の「Non-Wrapper Emitters」節を更新する (after 1) (→ AC1, AC2):
   - `restore_auto_session_pointer()` の解決順序リストから旧 5 段目 (`.tmp/auto-session-current` を採用) を削除し、旧 6 段目 (「該当なし — no-op」) を新 5 段目として残す。fail-closed 化の経緯を一言添える
   - 「Concurrent-session attribution problem」段落末尾の「`.tmp/auto-session-current` itself was not removed... it remains step 5's last-resort fallback for callers that cannot supply an issue-scoped or in-band id.」を、Issue #1224 でこのフォールバック段が `restore_auto_session_pointer()` から削除された旨に書き換える (ファイル自体や `/auto` Step 1 の書き込み・wrapper script 側の独自フォールバックへの参照は削除されず現状のまま利用される点は明記する)
   - 新規段落として「手動オーケストレーション (Issue #1224)」を追加する: `/auto` Step 1 を経ずに `run-*.sh` を個別呼び出しする、または `Skill(wholework:verify)` を直接起動するセッションは、issue-scoped ポインタも PGID ポインタも `AUTO_SESSION_ID` env も持たないため、fail-closed 化後は session_id 未設定 (instrumentation 対象外) になる旨を明記する。追跡を望む場合の代替手段として、呼び出し前に `AUTO_SESSION_ID` を明示的に export するか、対象 Issue ごとに `persist_auto_session_pointer <id> <issue-number>` で issue-scoped ポインタを書く方法を示す

3. `skills/audit/SKILL.md` の「Session Boundary Identification」節にある `.tmp/auto-session-current` の説明箇条書きを修正する (after 1) (→ AC1)。現在の「Read by `restore_auto_session_pointer()` (`scripts/emit-event.sh`) as the last-resort fallback when a caller has neither a PGID-matching nor an issue-scoped pointer」という記述は、本 Issue の変更後は `restore_auto_session_pointer()` に関して不正確になる。`current` は依然として `/auto` Step 1 が書き込み、`run-issue.sh`/`run-spec.sh`/`run-code.sh`/`run-review.sh`/`run-merge.sh` 自身の (この関数を介さない) 独自インラインフォールバックからは引き続き読まれる点は維持しつつ、`restore_auto_session_pointer()` がこのファイルを読まなくなった旨 (Issue #1224) を反映する

4. `tests/emit-event.bats` の既存テスト2件を、削除されるフォールバック段に依存しない形へ修正する (after 1) (→ AC3, AC4):
   - `restore_auto_session_pointer restores AUTO_SESSION_ID/AUTO_EVENTS_LOG from auto-session-current (Issue #902)`: fixture (`.tmp/auto-session-current` に `test-session-123` を書き込む) はそのまま維持し、`restore_auto_session_pointer` の呼び出しに issue 番号引数 (issue-scoped ポインタも未作成のため未解決になる、例: `9999`) を追加する。期待値を「採用される (`SID=[test-session-123]`)」から「採用されない (`SID=[] LOG=[]`)」に反転させ、テスト名を `restore_auto_session_pointer does not fall back to auto-session-current when no session-specific pointer resolves (Issue #1224, supersedes #902 fallback)` に変更する。これが AC3 が求める「AUTO_SESSION_ID / AUTO_EVENTS_LOG / issue-scoped / PGID すべて未解決かつ current に別セッションの ID がある状況」の再現ケースとなる
   - `restore_auto_session_pointer finds main worktree pointer file from a linked worktree CWD (Issue #1006)`: fixture を `$MAIN_REPO/.tmp/auto-session-current` から `$MAIN_REPO/.tmp/auto-session-issue-1006` (issue-scoped ポインタ) に切り替え、`restore_auto_session_pointer` の呼び出しを `restore_auto_session_pointer 1006` に変更する。これにより、削除されるフォールバック経路に依存せず、本来の検証意図 (linked worktree の CWD からでもメインリポジトリルート配下のポインタファイルを解決できること) を維持する。他のアサーション (`SID=[worktree-session-456]` / `LOG=[${MAIN_REPO}/.tmp/auto-events.jsonl]` / worktree 配下パスでないこと) は変更しない

5. `bats tests/emit-event.bats` を実行し、全テストが PASS することを確認する (after 4) (→ AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "restore_auto_session_pointer() が、AUTO_SESSION_ID / AUTO_EVENTS_LOG / issue-scoped ポインタ / PGID ポインタのいずれからも解決できない場合の挙動を明示的に定義しており、他セッションの ID を持つ可能性のある current ポインタへ無条件にフォールバックしない実装または文書化がある" --> 解決不能時に誤帰属しない挙動が定義されている
- <!-- verify: rubric "modules/event-emission.md に、/auto の session 初期化を経ない実行形態 (wrapper を個別に呼ぶ手動オーケストレーション等) での session_id 解決の扱いが記載されている" --> 手動オーケストレーション時の扱いが文書化されている
- <!-- verify: rubric "tests/emit-event.bats に、AUTO_SESSION_ID / AUTO_EVENTS_LOG / issue-scoped / PGID すべて未解決かつ current に別セッションの ID がある状況を再現する検証ケースが追加されており、bats 実行が通る" --> 該当条件がテストで保護されている
- <!-- verify: command "bats tests/emit-event.bats" --> `tests/emit-event.bats` の bats 実行がすべて通る

### Post-merge

- `/auto` を経由しない wrapper 個別実行で `/verify` を走らせた際、`.tmp/auto-events.jsonl` の event が他セッションの session_id を持たないことを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **案 A/B 併用、案 C 不採用**: Issue 本文の検討候補表のとおり、案 A (fail-closed 化) と案 B (手動初期化手順の明文化) は併用可能であり両方を採用した。案 C (`current` に鮮度判定を持たせる) は閾値設定が恣意的になるという Issue 本文自身のトレードオフ指摘を踏まえ不採用とした
- **集計側の互換性は確認済み**: `scripts/get-auto-session-report.sh` の list mode は `select(.session_id != null and .session_id != "")` で空の session_id を持つ event を既に除外している (grep 確認済み)。fail-closed 化により session_id が空のまま記録される event が増えても、集計側でエラーや誤集計は発生しない
- **スコープ境界 (wrapper script 自身の独自フォールバックは対象外)**: `run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh`、および `collect-run-facts.sh` / `filter-session-verified-issues.sh` は、`restore_auto_session_pointer()` を経由しない**独自のインライン**フォールバック (`AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')}"` という同形のパターン) をそれぞれ持っており、これらは本 Issue の AC (`restore_auto_session_pointer()` と `tests/emit-event.bats` を名指し) の対象外として変更しない。構造的には同種のギャップだが、今回は既存 AC の範囲に留め、新規 Issue の起票は見送る (起票要否は次回の drift/fragility 監査または再発時の判断に委ねる)
- **`run-auto-sub.sh:384` への影響なし**: `--write-manual-recovery` dispatch 内の `restore_auto_session_pointer` 呼び出し (issue 番号引数なし) は、`skills/auto/SKILL.md` Step 6 が同 dispatch の前に PGID ポインタを再生成する設計になっている (#1075 で導入済み) ため、本変更後も PGID ポインタ (残る 4 段目) で解決し、削除されるフォールバック段には到達しない
- **`skills/auto/SKILL.md` Step 1 の記述は変更しない**: 同 Step は `.tmp/auto-session-current` を「PGID-matching / issue-scoped ポインタを持たない呼び出し元向けの最終フォールバック」として書き込む理由を説明しているが、この記述は wrapper script 自身の独自フォールバック (上記の通り維持) にとって引き続き正しいため、変更不要と判断した
- **bats fixture 形式**: ポインタファイルは 1 行のプレーンテキスト (session id 文字列 1 個) であり、テストは `echo "<value>" > <path>` で `$BATS_TEST_TMPDIR` 配下に作成する既存の慣習に従う (新規追加ではなく既存 fixture パターンの流用)

## Consumed Comments
- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1224#issuecomment-5212373223

## review retrospective

### Spec vs. implementation divergence patterns

- The Spec's own Notes (line 78, "`skills/auto/SKILL.md` Step 1 の記述は変更しない") turned out to be based on an incomplete reading of that line's actual wording. The Spec's reasoning treated the line as describing the general "wrapper script's own independent fallback" concept, which does remain correct — but the line's literal text specifically names `restore_auto_session_pointer()` as the consumer of the `.tmp/auto-session-current` last-resort fallback, and that specific claim became false once this PR removed that function's read of the file. `review-light`'s documentation-consistency pass caught the gap between the Spec's stated conclusion and the line's literal content; the code phase's own reasoning did not re-verify the line's exact wording against the diff's actual effect on `restore_auto_session_pointer()`. Takeaway for future Specs: when a Notes entry justifies *not* changing a line by paraphrasing its meaning, double check the paraphrase against the line's literal wording — not just its intended concept — especially when the line names a specific function/symbol that the Implementation Steps are modifying.

### Recurring issues

- Nothing to note — this is the first Issue in recent sessions to remove a fallback step from `restore_auto_session_pointer()`'s resolution order.

### Acceptance criteria verification difficulty

- Nothing to note. All 4 Pre-merge ACs (3 `rubric` + 1 `command`) verified cleanly with no UNCERTAIN and no verify-command syntax issues. The `command "bats tests/emit-event.bats"` AC resolved via CI reference fallback (`Run bats tests` job SUCCESS) since `/review` runs in safe mode.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate: all 4 pre-merge ACs already checked (`unchecked_count=0`) and no `review_incomplete_fallback` — proceeded without an override marker
- `gh-pr-merge-status.sh` reported `mergeable=false, reason=ci_failing`; investigated CI directly rather than treating it as a genuine regression — the "Test" workflow ran twice for the identical commit (`7b5132c3`), with only one run failing on a single unrelated flaky test (`worktree-merge-push.bats`: "`--from with base-diverged and rebase conflict aborts and exits non-zero`"), while the parallel run of the same commit passed the same test. Recorded this as an Auto-Resolve Log comment on Issue #1224 and proceeded with the squash merge per non-interactive auto-resolve policy
- Squash-merged and deleted the remote branch successfully; no rebase/conflict resolution was needed

### Deferred Items
- The Post-merge observation AC (`/auto` を経由しない wrapper 個別実行で `/verify` を走らせた際、event が他セッションの session_id を持たないことを確認する`, `event=auto-run session=next`) remains unverified — it requires a live post-merge manual-orchestration run and is out of scope for `/merge`
- None else

### Notes for Next Phase
- `/verify` should watch for the Post-merge observation AC firing on the next manual-orchestration `/auto`-external run, per `event=auto-run session=next`
- The flaky `tests/worktree-merge-push.bats` case observed during this merge (`--from with base-diverged and rebase conflict aborts and exits non-zero`) is unrelated to this Issue's change; no action taken here, but worth noting if it recurs
