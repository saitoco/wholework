# Issue #1501: hook-worktree-path-guard: 未設定の WHOLEWORK_ISSUE_NUMBER で継承した EMIT_ISSUE_NUMBER を上書きしない

## Overview

`scripts/hook-worktree-path-guard.sh` は、worktree セッション中に親リポジトリの絶対パスへ Edit/Write/NotebookEdit/Read しようとした呼び出しをブロックし、`worktree-path-block` イベントを記録する。この記録で Issue 番号を `EMIT_ISSUE_NUMBER="${WHOLEWORK_ISSUE_NUMBER:-}"` と指定しているが、`WHOLEWORK_ISSUE_NUMBER` はリポジトリのどこにも設定されておらず、`run-*.sh` が export して hook (`claude -p` の子プロセス) が継承するはずの `EMIT_ISSUE_NUMBER` を空文字で上書きしている。その結果、`emit_event` の `${EMIT_ISSUE_NUMBER:-0}` により、イベントは常に `issue=0` で記録される。また `worktree-path-block` イベントは `modules/event-emission.md` に記載が無い。

本 Spec は次の 3 点を行う。

1. hook の `emit_event` 呼び出しから `EMIT_ISSUE_NUMBER` の接頭辞代入を削除し、継承値をそのまま使う (未設定の `WHOLEWORK_ISSUE_NUMBER` への参照も同時になくなる)
2. 継承した Issue 番号がイベントに記録されることを bats の回帰テストで保護する
3. `worktree-path-block` イベントを `modules/event-emission.md` に記載する (あわせて `scripts/emit-event.sh` ヘッダコメントの同イベント記述を実装に整合させる)

## Reproduction Steps

1. worktree 内を CWD にして、`EMIT_ISSUE_NUMBER` が export された環境を用意する。`run-spec.sh` / `run-code.sh` などラッパー配下のセッションはこの状態にある。手動で再現する場合は `export EMIT_ISSUE_NUMBER=4242` を設定し、共有ログを汚さないよう `AUTO_EVENTS_LOG` を絶対パスの一時ファイルに向ける。
2. 親リポジトリの絶対パスを指す Edit 呼び出しを hook に渡す。

   ```bash
   printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"<親リポジトリ>/docs/foo.md"}}' | bash scripts/hook-worktree-path-guard.sh
   ```

   hook は exit 2 でブロックし、`worktree-path-block` イベントを `AUTO_EVENTS_LOG` に追記する。
3. `jq -r 'select(.event == "worktree-path-block") | .issue' <AUTO_EVENTS_LOG>` で `issue` を確認する。期待値は継承した番号だが、実際は常に `0` になる。

実測結果 (2026-10-04、base `e119607e`) は次のとおり。

- 本 Spec 作成セッション (ラッパー経由で `EMIT_ISSUE_NUMBER=1501` / `AUTO_SESSION_ID=1408775-1791113801` が export 済み) の環境で現行 hook を実行すると `{"issue":0,"event":"worktree-path-block","session_id":"1408775-1791113801","tool":"Edit"}` が記録された。同じ継承経路の `session_id` は入るのに `issue` だけが `0` になる。
- `EMIT_ISSUE_NUMBER=4242` を明示して現行 hook を実行しても `issue` は `0` (4242 ではない)。これは後述の新規テスト (a) が修正前に FAIL することと同じ条件である。

## Root Cause

`scripts/hook-worktree-path-guard.sh` の block 分岐 (line 42) は `EMIT_ISSUE_NUMBER="${WHOLEWORK_ISSUE_NUMBER:-}" AUTO_EVENTS_LOG="..." emit_event "worktree-path-block" ...` と、コマンド接頭辞の代入で `EMIT_ISSUE_NUMBER` を無条件に上書きしている。`WHOLEWORK_ISSUE_NUMBER` を設定する箇所はリポジトリのどこにも無い (`git grep -n WHOLEWORK_ISSUE_NUMBER` の一致はこの 1 行のみ。`docs/tech.md` § Environment Variables にも記載が無い)。このため代入値は常に空文字になり、`emit_event()` の `${EMIT_ISSUE_NUMBER:-0}` (`scripts/emit-event.sh:142`) が `0` に落とす。この参照は #885 (commit `835da200`、hook へのイベント記録の接続) で導入されたもので、対応する setter は作られなかった。

修正方針の妥当性: hook は Claude Code プロセスの子として動作し、親の環境変数を継承する (公式 Hooks ドキュメント。出所は Notes 参照)。`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` はいずれも `EMIT_ISSUE_NUMBER` を `export` しているため、上書きを取り除くだけで hook は実行中の Issue 番号をそのまま記録できる。

## Changed Files

- `scripts/hook-worktree-path-guard.sh`: block 分岐の `emit_event "worktree-path-block"` 呼び出しから接頭辞代入 `EMIT_ISSUE_NUMBER="${WHOLEWORK_ISSUE_NUMBER:-}" ` を削除する。継承した `EMIT_ISSUE_NUMBER` がそのまま `emit_event()` に渡り、未設定なら `emit_event()` 既定の `0` になる。代入しない理由を 1〜2 行の英語コメントで残す — bash 3.2+ 互換 (代入接頭辞の削除とコメント追加のみ)
- `tests/hook-worktree-path-guard.bats`: 新規 `@test` を 2 件追加する — (a) `EMIT_ISSUE_NUMBER` を export した環境でブロックしたとき、`worktree-path-block` イベントの `issue` に継承値が入る (修正前の実装では FAIL する)、(b) `EMIT_ISSUE_NUMBER` が未設定のとき `issue` が `0` になる
- `modules/event-emission.md`: `## Non-Wrapper Emitters` の末尾 (`opportunistic_verify_result` 段落の後、`## Backfill` の前) に `worktree-path-block` イベントの段落を追加する (英語)
- `scripts/emit-event.sh`: ヘッダコメントの `worktree-path-block` エントリを実装に整合させる (コメントのみ・動作変更なし) — 対象ツールに `Read` を追加 (#971 で hook は Read を対象に拡張済みだが当該コメントは未更新)、`issue` フィールドの出所を 1 行追記する — bash 3.2+ 互換 (コメントのみ)
- [Steering Docs sync candidate] keyword "worktree-path-block" は 6 ファイルに一致 (識別力フィルタ通過): 変更対象の 3 ファイル (`scripts/hook-worktree-path-guard.sh`, `scripts/emit-event.sh`, `tests/hook-worktree-path-guard.bats`) 以外は履歴 Spec 3 件 (`docs/spec/issue-860-*`, `issue-1136-*`, `issue-1238-*`) のみで、歴史的記録のため更新不要
- [Steering Docs sync candidate] keyword "EMIT_ISSUE_NUMBER" skipped: matched 58 files (no discriminating power)
- [Steering Docs sync candidate] keyword "hook-worktree-path-guard" skipped: matched 21 files (no discriminating power)
- [Steering Docs sync candidate] keyword "event-emission.md" skipped: matched 38 files (no discriminating power)
- [Steering Docs sync candidate] keyword "emit-event.sh" skipped: matched 108 files (no discriminating power)
- (測定範囲: 上記の件数はいずれも `grep -rl "<keyword>" docs/ tests/ scripts/ modules/ | wc -l`、全ファイル、base `e119607e`)

## Implementation Steps

1. (→ AC1) `scripts/hook-worktree-path-guard.sh` を修正する。block 分岐 (`"$PARENT_REPO"/*)`) の `emit_event "worktree-path-block"` 呼び出しから、接頭辞代入 `EMIT_ISSUE_NUMBER="${WHOLEWORK_ISSUE_NUMBER:-}"` だけを削除し、`AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-$PARENT_REPO/.tmp/auto-events.jsonl}"` の接頭辞代入は残す。`source` 行の直後に、`EMIT_ISSUE_NUMBER` を代入しない理由 (hook は Claude Code プロセスの子なので、呼び出し元ラッパーが export した値を継承する。未設定時は `emit_event()` 既定の 0) を英語コメントで 1〜2 行残す。
   このスクリプトは block/allow を決める gate であり、`2>/dev/null || true` も含むため fail-safe critical に当たる。変更箇所 (emit 経路) の端ケース挙動を次のとおり固定する (実測と推論を区別して記す。詳細は Notes)。
   - 未設定 / 空文字: `emit_event()` 既定により `"issue":0` (従来の挙動を維持。実測済み)
   - 数字のみ: そのまま `"issue":<N>` で記録される (今回の修正点。実測済み)
   - 桁あふれする数字列: 数字のみなので JSON として有効な数値のまま記録される (推論。JSON は数値の桁数を制限しない。未実測)
   - 数字以外 (`abc`、`"` / `>` / 改行 / CRLF / 多バイト文字を含む値): `emit_event()` が `"issue":${_issue}` をクォートなしで書くため、不正な JSON 行になる (実測: `EMIT_ISSUE_NUMBER=abc` で `"issue":abc,` となり `jq` が parse error)。ただし `run-*.sh` はいずれも `^[0-9]+$` で検証した値だけを export するため通常経路では到達しない。hook は同じ呼び出しで既に検証なしに継承している `EMIT_PR_NUMBER` / `AUTO_SESSION_ID` と同じく「ラッパーの契約を信頼する」方針とし、追加の検証コードは足さない (判断理由は Notes)。
   - いずれの場合もブロック判定 (exit 2) は変わらない (実測済み: 数字以外・空文字でも exit 2)。
   - 依存コマンドの失敗 (`emit-event.sh` の source 失敗、`emit_event` の書き込み失敗など): 既存の `2>/dev/null || true` により emit だけが fail-open する。イベントは観測用データであり、その失敗がブロック判定を変えてはならないため現状を維持する。なお先頭の `jq` 依存 (不在時は `TOOL_NAME` が空になり allow) は既存設計で、本 Issue では変更しない。
2. (parallel with 1) (→ AC2, AC4) `tests/hook-worktree-path-guard.bats` の末尾に新規 `@test` を 2 件追加する。既存テストの書式 (`FIXTURE_WORKTREE` / `FIXTURE_PARENT`、`INPUT=$(printf ...)`、`run bash -c "echo '$INPUT' | \"$SCRIPT\""`) に合わせる。
   - (a) テスト名 `inside worktree + parent-repo absolute path -> event issue field carries inherited EMIT_ISSUE_NUMBER`: `export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/events.jsonl"` (本番ログへの漏洩防止。#1136 の隔離方針) と `export EMIT_ISSUE_NUMBER=4242` を設定し、`cd "$FIXTURE_WORKTREE"` して Edit と親リポジトリ絶対パスを渡す。`[ "$status" -eq 2 ]` を確認した後、`run jq -r 'select(.event == "worktree-path-block") | .issue' "$AUTO_EVENTS_LOG"` を実行し、`[ "$output" = "4242" ]` を確認する。修正前は `issue` が `0` のため最後のアサーションで FAIL する。
   - (b) テスト名 `inside worktree + parent-repo absolute path -> event issue field is 0 when EMIT_ISSUE_NUMBER is unset`: `setup()` が `EMIT_ISSUE_NUMBER` を unset 済みなので `AUTO_EVENTS_LOG` だけを設定し、(a) と同じ手順で `[ "$output" = "0" ]` を確認する (`modules/event-emission.md` に書く「ラッパー外のセッションは `issue` が 0」の根拠となる)。
   - 裸の `[[ ... ]]` アサーションは使わない (bash 3.2 の pitfall。`[ ... ]` を使う)。(a) は `EMIT_ISSUE_NUMBER=` のリテラルを含むため、AC2 の `file_contains "tests/hook-worktree-path-guard.bats" "EMIT_ISSUE_NUMBER="` を満たす (既存の `setup()` の `unset ... EMIT_ISSUE_NUMBER ...` 行は `=` を含まず一致しない)。
   - 既存スイートが PASS することだけでなく、上記の新規テストケースを追加したうえでスイートが PASS すること (AC4)。
3. (parallel with 1, 2) (→ AC3) `modules/event-emission.md` の `## Non-Wrapper Emitters` の末尾 (`opportunistic_verify_result` 段落の後、`## Backfill` の前) に、`worktree-path-block` の段落を追加する。英語で書き、CJK 文字を含めない (`scripts/check-language-convention.py` が検出する)。見出しの書式は既存段落 (`**\`retro_proposal_classified\` (Issue #1159, ...)**:` など) に合わせる。AC3 の rubric が要求する 4 要素 (イベントの説明、`hook-worktree-path-guard.sh`、親リポジトリ絶対パスへの Edit/Write/NotebookEdit/Read のブロック時に記録されること、`issue` が継承した `EMIT_ISSUE_NUMBER` であること) を含める。提案文は次のとおり (そのまま使ってよい)。

   ```markdown
   **`worktree-path-block` (Issue #885, `issue` field inheritance fixed in #1501)**: emitted by `scripts/hook-worktree-path-guard.sh` — a PreToolUse hook registered in `hooks/hooks.json`, not a `run-*.sh` wrapper — each time it blocks (exit 2) an `Edit` / `Write` / `NotebookEdit` / `Read` call whose `file_path` (`notebook_path` for `NotebookEdit`) is an absolute path under the parent repository while the session's working directory is inside a worktree (`.claude/worktrees/<name>`). Event-specific fields: `tool`, `cwd`, `file_path`, `worktree_root` (field list: `scripts/emit-event.sh` header). The hook process inherits the Claude Code process's environment, so the `issue` field carries the `EMIT_ISSUE_NUMBER` that the calling `run-*.sh` wrapper (or `run-auto-sub.sh`) exported — the hook never assigns it itself — and `session_id` / `pr` likewise come from the inherited `AUTO_SESSION_ID` / `EMIT_PR_NUMBER`. A session that was not launched through a wrapper (e.g. an interactive session) has none of these variables, so the event is recorded with `issue` `0` (the default of `emit_event()`) and an empty `session_id`. The emit is best-effort (`2>/dev/null || true`): a failure never changes the block decision. When `AUTO_EVENTS_LOG` is unset the hook defaults it to `<parent repo>/.tmp/auto-events.jsonl`, not a worktree-local path.
   ```

4. (parallel with 1, 2, 3) (→ 整合性の同期。専用の AC なし) `scripts/emit-event.sh` ヘッダコメントの `worktree-path-block` エントリを更新する (コメントのみ・英語)。説明行と `tool=<name>` の列挙に `Read` を追加し、`issue` フィールドの出所 (呼び出し元ラッパーから継承した `EMIT_ISSUE_NUMBER`。ラッパー外では 0。詳細は `modules/event-emission.md`) を 1 行追記する。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/hook-worktree-path-guard.sh の worktree-path-block イベント記録で、呼び出し元から継承した EMIT_ISSUE_NUMBER が空文字で上書きされず、設定されていればその値が使われる (どこからも設定されない WHOLEWORK_ISSUE_NUMBER だけを参照する形になっていない)" --> 継承した `EMIT_ISSUE_NUMBER` を空で上書きしない (継承値を優先するか、`WHOLEWORK_ISSUE_NUMBER` の参照を削除する)
- <!-- verify: rubric "tests/hook-worktree-path-guard.bats に、EMIT_ISSUE_NUMBER を設定した環境で hook がブロックしたとき worktree-path-block イベントの issue フィールドにその番号が記録されることを検証するテストがあり、修正前の実装では FAIL する" --> <!-- verify: file_contains "tests/hook-worktree-path-guard.bats" "EMIT_ISSUE_NUMBER=" --> 継承した Issue 番号がイベントに記録されることを bats が回帰テストとして保護している
- <!-- verify: grep "worktree-path-block" "modules/event-emission.md" --> <!-- verify: rubric "modules/event-emission.md に worktree-path-block イベントの説明があり、hook-worktree-path-guard.sh が親リポジトリ絶対パスへの Edit/Write/NotebookEdit/Read をブロックしたときに記録されること、および issue フィールドには呼び出し元から継承した EMIT_ISSUE_NUMBER が記録されることが記載されている" --> `worktree-path-block` イベントが `modules/event-emission.md` に記載されている
- <!-- verify: command "bats tests/hook-worktree-path-guard.bats" --> hook の bats が PASS する

### Post-merge

なし

## Notes

- **AC1 の修正方針の決定 (Issue Retrospective からの委任)**: 「継承値を優先する」(`${EMIT_ISSUE_NUMBER:-${WHOLEWORK_ISSUE_NUMBER:-}}` のようなフォールバック連鎖) ではなく、「`EMIT_ISSUE_NUMBER` の接頭辞代入ごと削除する」を採用した。理由は 3 つ。(1) `WHOLEWORK_ISSUE_NUMBER` の setter は存在せず、#885 の commit message にも setter を後続で作る計画の記載が無い。フォールバックに残すと Purpose の「使われていない環境変数を整理する」と矛盾する。(2) 継承は `emit_event()` の既存の `${EMIT_ISSUE_NUMBER:-0}` がそのまま担うため、最小差分で済む。(3) AC1 の rubric はどちらの実装でも同じ判定になる (Issue の Auto-Resolve Log と整合)。不採用案は上記のフォールバック連鎖。
- **数値検証ガードを追加しない判断**: 継承した `EMIT_ISSUE_NUMBER` が数字以外の場合、`emit_event()` は `"issue":${_issue}` をクォートなしで書くため不正な JSON 行になる (実測、Implementation Step 1 参照)。それでもガードを足さないのは次の理由による。(1) ラッパー 6 本 (`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh`) はいずれも `^[0-9]+$` で検証した値 (`run-review.sh` / `run-merge.sh` の `_REVIEW_ISSUE` / `_MERGE_ISSUE` は `gh-extract-issue-from-pr.sh` 由来の数字か空) だけを export するため、通常経路では数字以外が届かない。(2) 同じ `emit_event` 呼び出しが既に検証なしで継承している `EMIT_PR_NUMBER` (`"pr":${EMIT_PR_NUMBER}` もクォートなし) / `AUTO_SESSION_ID` と同じ契約であり、`EMIT_ISSUE_NUMBER` だけにガードを足すと不均一になる。(3) `EMIT_ISSUE_NUMBER` を代入せず継承値のまま `emit_event` を呼ぶ既存の emitter (`wait-ci-checks.sh` の `ci_wait`、`claude-watchdog.sh` の `watchdog_kill` / `max_silent_window`) も検証なしで使っており、先例と揃う。`emit-skill-event.sh` が持つ数値ガードは、位置引数に `batch-<session-id>` という正当な非数値入力がありうる事情に対するもので、本件には当てはまらない。ガードが必要になった場合は `emit_event()` 側で `_issue` を検証する共通修正が筋であり、別 Issue の領分とする。
- **外部仕様の確認 (出所つき)**: 公式 Hooks ドキュメント (https://code.claude.com/docs/en/hooks、取得日 2026-10-04) に次の記述がある。"A hook process inherits the parent environment, apart from the `OTEL_*` exporter variables that Claude Code removes from every subprocess it spawns and, when `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is set to `1`, the variables it strips." / "Handlers run in the current directory with Claude Code's environment." / PreToolUse の exit 2 はツール呼び出しをブロックし、JSON の `permissionDecision: "allow"` でも上書きできない。環境変数の継承は実環境でも確認した: 本 Spec 作成セッション (`run-spec.sh` 経由の `claude -p`) の環境に `EMIT_ISSUE_NUMBER=1501` / `EMIT_PHASE_NAME=spec` / `AUTO_SESSION_ID` / `AUTO_EVENTS_LOG` が export されていた (`printenv`)。`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` は Anthropic / クラウドの認証情報を落とす機能 (出所: 2026-10-04 の WebSearch 結果の要約。一次情報ページ https://code.claude.com/docs/en/env-vars は取得時に当該エントリの手前で途中打ち切りとなり確認できなかった。#1486 の Spec と同じ状況)。Wholework はこの変数を設定しておらず (`git grep` の一致は #1486 の Spec のみ)、`EMIT_ISSUE_NUMBER` が対象になる根拠も無いため影響なしと判断した。当該 opt-in を使う環境でのみ未検証の余地が残る。
- **スコープ外の観測 (follow-up 候補。本 Issue では対応しない)**: ラッパーは `AUTO_EVENTS_LOG` を相対パス `.tmp/auto-events.jsonl` で export する (`run-spec.sh` の `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"`。本セッションの環境値も相対パス)。hook は継承値をそのまま使い (`${AUTO_EVENTS_LOG:-$PARENT_REPO/.tmp/auto-events.jsonl}` は未設定時の既定のみ)、worktree 内の CWD で動くため、ラッパー配下のイベントは共有ログではなく `<worktree>/.tmp/auto-events.jsonl` に書かれる。実測: 本セッションの環境のまま worktree の CWD で現行 hook を手動実行したところ、イベントは worktree ローカルの `.tmp/auto-events.jsonl` に出力された (確認後に削除)。これは #885 の意図 ("not a worktree-local relative path") と食い違い、本 Issue の修正後も `issue` は正しく入るが、`/auto` 配下では保存先が集計ログと別になる可能性が高い。`emit-skill-event.sh` など他の worktree 内 emitter も同じ構造の可能性があるが未検証。AC の対象外 (要件の追加は `/issue` の領分) のため本 Spec では扱わず、`/verify` の retrospective で改善提案として集約する。
- **bats の実行環境**: このホストには `bats` が未インストール (`command -v bats` が空。CI は `apt-get install bats` で導入)。AC4 の `bats tests/hook-worktree-path-guard.bats` は bats が使える環境 (CI など) で実行する必要がある。本 Spec 作成時は bats を実行できなかったため、新規テスト (a) と同じ手順 (hook に `EMIT_ISSUE_NUMBER=4242` を渡し `jq` で `issue` を取得) を手動で現行 hook と修正案のプロトタイプに対して実行し、修正前後の差を確認した。現行 hook は `0` (テスト (a) は FAIL する)、修正案は継承値 (PASS)、未設定時は `0` (テスト (b) は PASS)。`/code` で bats が使えない場合は tooling-availability gap として扱い (`modules/test-runner.md`)、CI の bats ジョブを最終ゲートとする。
- **bats テストの入力形式**: hook への入力は stdin の JSON `{"tool_name":"Edit","tool_input":{"file_path":"<親リポジトリ絶対パス>/docs/foo.md"}}`。環境は `AUTO_EVENTS_LOG` (`$BATS_TEST_TMPDIR` 配下。共有ログ汚染の防止) と `EMIT_ISSUE_NUMBER` (export)。CWD は `$FIXTURE_WORKTREE` (`$BATS_TEST_TMPDIR/parentrepo/.claude/worktrees/test-issue`)。出力は JSONL の 1 行 `{"ts":"...","issue":<N>,"event":"worktree-path-block","session_id":"","tool":"Edit","cwd":"...","file_path":"...","worktree_root":"..."}`。
- **新規テストケースの要否**: Step 1 は新規分岐の追加ではなく代入の削除のため、「新規分岐ロジックには新規テスト」の要件の対象外である。ただし AC2 が回帰テストの追加を要求しているため Step 2 で 2 件追加する。
- **fail-safe critical の判定**: yes。(a) block/allow を決める gate に当たり、(c) `2>/dev/null || true` を含む (`grep -nF` で 41 行目と 46 行目)。端ケース挙動は Implementation Step 1 に記載した。
- **audit/investigation-type の判定**: no。バグ修正とドキュメント追記であり、既存の複数項目を基準に沿って分類・判定する調査ではない (`audit/drift` ラベルは起票経路を示すだけ)。
- **Issue 本文と実装の矛盾検出**: 矛盾なし。Background の事実主張 (hook の動作、`WHOLEWORK_ISSUE_NUMBER` の一致が 1 行のみ、`docs/tech.md` に記載なし、ラッパーが `EMIT_ISSUE_NUMBER` を export、`${EMIT_ISSUE_NUMBER:-0}` による `issue=0`、`modules/event-emission.md` に記載なし) をすべて実コードで確認した。
- **変更不要と確認した対象 (grep 確認済み)**: (1) `docs/tech.md` § Environment Variables — `WHOLEWORK_ISSUE_NUMBER` は元々未記載で、`EMIT_*` はラッパー内部の変数として `modules/event-emission.md` § Usage に記載済み。(2) `docs/structure.md` (179 行目) と `docs/ja/structure.md` (172 行目) の hook エントリ — 役割 (block 対象) のみの記述でイベントやフィールドに触れていない。(3) `modules/worktree-lifecycle.md` § Enforcement (199 行目・203 行目) — block 対象と範囲限界の記述のみ。(4) `hooks/hooks.json` — 登録のみ。(5) `modules/observation-trigger.md` と `scripts/opportunistic-search.sh` の `KNOWN_EVENTS` — `worktree-path-block` は未登録で、本 Issue はイベントを `modules/event-emission.md` に記載するだけであり observation event 化はしない。(6) `docs/ja/` の翻訳同期 — 変更ファイルは `scripts/` / `tests/` / `modules/` のみで `docs/*.md` を含まないため不要 (`docs/translation-workflow.md` 確認済み)。
- **Steering Docs sync の Listing-side サブチェック**: 対象外。既存ファイルの編集のみで、サブコマンド・ファイルの追加/削除/改名・ディレクトリ構造の変更を含まない。Outbound pointer のチェックも該当なし (変更ファイルが指す `modules/observation-trigger.md` などは本 Issue の影響を受けない)。
- **allowed-tools の影響範囲**: 新規スクリプトは無い。`modules/event-emission.md` への追記は `scripts/hook-worktree-path-guard.sh` などのパスに言及するため機械的なゲートには該当するが、読み込み元の SKILL.md (`skills/audit/SKILL.md` / `skills/auto/SKILL.md` / `skills/verify/SKILL.md`) は当該 hook を呼ばず (grep で各 0 件)、追記は記述のみで新たなスクリプト呼び出しを導入しないため、`allowed-tools` の追加は不要。
- **premise マーカーの自己ヒット**: Issue 本文の `<!-- premise: grep_count "WHOLEWORK_ISSUE_NUMBER" "scripts/ skills/ modules/ docs/ tests/" -eq 1 -->` は `docs/` 配下の tracked ファイルをすべて数える。本 Spec (`docs/spec/issue-1501-*.md`) が `WHOLEWORK_ISSUE_NUMBER` を含む時点で件数が変わり、実装後 (hook の該当行が消えた後) も Spec の記述行数分が残る。Issue クローズ前に `/audit premise` を実行すると自己ヒットによる expire 判定 (autonomy: L3 では自動コメント) が出うるが、本 Issue の修正で premise の主張 (「設定箇所がどこにも無い」) 自体が役目を終えるため想定内で、対処不要。
- **Spec 作成時の測定範囲**: 件数・行番号は base `e119607e` (`origin/main`) のもの。`git grep -n WHOLEWORK_ISSUE_NUMBER` はリポジトリ全体の tracked ファイルが対象。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (AC1 の修正方針は Spec に委任、AC2 の file_contains は EMIT_ISSUE_NUMBER= で検出力を確保、Background 事実確認済み) / https://github.com/saitoco/wholework/issues/1501#issuecomment-5979615264
- code phase: `phase/ready` 付与 (2026-10-04T12:07:00Z) 以降の新規コメントなし

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1〜4 をそのとおり実装した (Spec 提案の `event-emission.md` 段落はそのまま採用)

### Design Gaps/Ambiguities
- `bats` がこのホストに未インストールのため、AC4 (`bats tests/hook-worktree-path-guard.bats`) と新規テスト 2 件はローカルで実行できず、CI の bats ジョブを最終ゲートとする (pr route のため `/review` が CI を参照する)。代わりに hook を直接実行して新規テスト (a)/(b) と同じ手順を再現した: 修正前 (`git show HEAD:...` の旧版) は `EMIT_ISSUE_NUMBER=4242` でも `issue=0`、修正後は `4242`、未設定時は `0`、いずれも exit 2
- Step 10 の verify-executor full mode のうち `command "bats ..."` は bats 不在のため UNCERTAIN とし、AC1〜AC4 のチェックボックスは更新していない (`/review` が PR の CI で確認する)

### Rework
- なし

### Pre-implementation FAIL check
- Confirmed pre-implementation FAIL for 1 new test(s) (テスト (a) 相当の手動再現。旧 hook は `issue=0` で `4242` と不一致)。テスト (b) は未設定時の既定動作の固定であり修正前後とも PASS する想定

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- hook の `emit_event` 呼び出しから `EMIT_ISSUE_NUMBER` の接頭辞代入だけを削除し、継承値は `emit_event()` 既定の `${EMIT_ISSUE_NUMBER:-0}` に任せた (Spec Notes の決定どおり。`WHOLEWORK_ISSUE_NUMBER` のフォールバックは残さない)
- `AUTO_EVENTS_LOG` の接頭辞代入は維持した

### Deferred Items
- AC4 (`bats tests/hook-worktree-path-guard.bats`) と新規 bats 2 件は bats 不在のためローカル未実行 — PR の CI bats ジョブで確認 (`/review`)
- Spec Notes の「スコープ外の観測」(ラッパーが相対パスの `AUTO_EVENTS_LOG` を export するため、worktree 配下のイベントが worktree ローカルの `.tmp/auto-events.jsonl` に出る可能性) は本 Issue の対象外のまま。`/verify` の retrospective で改善提案として集約

### Notes for Next Phase
- 変更は `scripts/hook-worktree-path-guard.sh` (代入削除とコメント 2 行)、`scripts/emit-event.sh` (コメントのみ)、`modules/event-emission.md` (段落追加)、`tests/hook-worktree-path-guard.bats` (テスト 2 件追加)
- `check-forbidden-expressions.sh` / `check-language-convention.py` はローカルで問題なし
