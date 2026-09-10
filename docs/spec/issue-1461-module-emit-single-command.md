# Issue #1461: modules: opportunistic-verify / retro-proposals の複合 source コマンドを単一コマンド化する

## Overview

`modules/opportunistic-verify.md` と `modules/retro-proposals.md` は、`source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` + `restore_auto_session_pointer` + ガード + `emit_event` という複合コマンドを prescribe している。この形は worktree isolation guard に拒否される (#1458 が `skills/verify/SKILL.md` 側 15 箇所で解消した問題の残余)。

本 Issue は次の 3 点を行う。

1. `scripts/emit-verify-event.sh` を `scripts/emit-skill-event.sh` へ改名し、module 側が必要とする引数 (`--emit-issue` / `--session-id` / 非数値 `<issue>`) をサポートするようインターフェースを拡張する
2. `scripts/collect-run-facts.sh` に `--session-from-issue <N>` を追加し、`modules/opportunistic-verify.md` Step 1 の facts 解決ブロック (emit ではない複合コマンド) も単一コマンド化する
3. 両 module の該当ブロックと地の文を書き換え、`skills/*/SKILL.md` 6 件の `allowed-tools` を更新する (`emit-skill-event.sh:*` 追加 / `emit-event.sh:*` 削除)

## Reproduction Steps

本 Spec 作成セッション (`/spec 1461`、worktree `spec/issue-1461` 内、2026-09-10) で実測した。

1. worktree セッション内で、`modules/retro-proposals.md` Step 6 が prescribe している複合コマンドをそのまま実行する:
   ```bash
   source "/Users/saito/src/wholework/scripts/emit-event.sh"
   restore_auto_session_pointer 1461
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then echo "would emit"; fi
   ```
2. → `This session is isolated in the worktree ..., but this command is too complex to verify that it stays inside the worktree. Refusing to run it` で拒否される。
3. 同じセッションで単一コマンド形を実行する:
   ```bash
   AUTO_EVENTS_LOG=.tmp/probe-events.jsonl bash scripts/emit-verify-event.sh 1461 spec_guard_probe phase=spec
   ```
4. → exit 0。`{"ts":"2026-09-10T01:04:17Z","issue":1461,"event":"spec_guard_probe","session_id":"90128-1788933783","phase":"spec"}` が書き込まれ、`session_id` も正しく解決された。

## Root Cause

`source` によるシェル関数呼び出しは worktree isolation guard が静的に検証できず、複合コマンド全体が拒否される (`modules/worktree-lifecycle.md` § "`source`-based shell function calls are blocked by the worktree isolation guard" に既知制約として記録済み)。#1458 は `skills/verify/SKILL.md` 側だけを wrapper 化し、この 2 module は Code Retrospective (Deviations from Design) で明示的にスコープ外として残した。

なお、Issue 本文の起票時の主張「`/spec` `/code` `/review` は自身の worktree 内で opportunistic verification を実行する」は事実誤認であり、`/spec` 調査で訂正済み (Issue 本文 § "実際の reader 集合と、修正すべき理由" 参照)。現状 6 reader すべてが Worktree Exit 後に読むため、直ちに拒否は起きない。修正の根拠は (a) その順序不変条件が機械的に強制されておらず 6 skill にまたがって手作業で維持されていること、(b) `modules/worktree-lifecycle.md` Entry step 1 が明示する nested `Skill()` dispatch 由来の `foreign` worktree 経路が存在すること、(c) 置換により `emit-event.sh:*` を 6 skill の `allowed-tools` から削除できること、の 3 点である。

## Changed Files

- `scripts/emit-verify-event.sh` → `scripts/emit-skill-event.sh`: `git mv` で改名。ヘッダーコメントを `/verify` 専用から汎用 (SKILL.md 本文および `modules/*.md` から呼ばれる単一コマンド wrapper) へ書き換え。`--emit-issue <N>` / `--session-id <SID>` の 2 フラグと非数値 `<issue>` の扱いを追加。bash 3.2+ 互換。実行権限を維持する
- `tests/emit-verify-event.bats` → `tests/emit-skill-event.bats`: `git mv` で改名。ファイル冒頭コメントと `SCRIPT=` の path を更新し、新規 3 分岐 (`--emit-issue` / `--session-id` / 非数値 `<issue>`) の新規テストケースを追加
- `scripts/collect-run-facts.sh`: `--session-from-issue <N>` フラグを追加し、session 解決ラダーの 3 番目 (`.tmp/auto-session-current` フォールバックより前) に配置。ヘッダーコメントの Usage 行と "Session resolution order" 行を更新。bash 3.2+ 互換
- `tests/run-fact-matching.bats`: `--session-from-issue` の新規テストケースを追加。`setup()` が `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているため、新規ケースでは実 `scripts/emit-event.sh` を `$MOCK_DIR` へコピーする (Notes の "WHOLEWORK_SCRIPT_DIR mock" 参照)
- `modules/opportunistic-verify.md`: Step 1 の facts 解決ブロックを `collect-run-facts.sh --session-from-issue` の単一コマンドへ、Step 3 の emit ブロックを `emit-skill-event.sh` の単一コマンドへ置換。`restore_auto_session_pointer` を含む地の文 3 箇所 (現行 39 / 87 / 89 行目) も書き換える
- `modules/retro-proposals.md`: Step 6 "Tier classification persistence" の emit ブロックを `emit-skill-event.sh` の単一コマンドへ置換。`restore_auto_session_pointer` を含む地の文 4 箇所 (現行 74 / 75 / 76 / 172 行目) も書き換える
- `skills/verify/SKILL.md`: 本文 15 箇所の `emit-verify-event.sh` を `emit-skill-event.sh` に置換。frontmatter `allowed-tools` の `${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh:*` を `${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh:*` に置き換え、`${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を削除。行数が変わった場合は `<!-- skill-body-lines: N -->` マーカーを `wc -l` 実測値に更新する (`tests/verify.bats` の回帰テスト対象)
- `skills/auto/SKILL.md`, `skills/code/SKILL.md`, `skills/issue/SKILL.md`, `skills/review/SKILL.md`, `skills/spec/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh:*` を追加し、`${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を削除。`skills/audit/SKILL.md` は対象外 (地の文で module 名に言及するだけで読み込まないため、`validate-skill-syntax.py` の `MODULES_REF_PATTERN` に一致しない — grep 済み)
- `modules/event-emission.md`: [Steering Docs sync candidate — 直接読解による検出] 4 箇所を更新。182 行目 (`emit-verify-event.sh` の名前)、192 行目 (`--persist-session` の呼び出し形とスクリプト名)、200 行目 (`retro_proposal_classified` の "calls `source emit-event.sh` + `restore_auto_session_pointer`" 記述)、202 行目 (`opportunistic_verify_result` の同記述)
- `docs/structure.md`: [Steering Docs sync candidate — 機械的スイープで検出] 175 行目の `scripts/emit-verify-event.sh` エントリを `scripts/emit-skill-event.sh` へ改名し、説明の「used exclusively by `skills/verify/SKILL.md`」を実際の caller 集合 (`skills/verify/SKILL.md` 本文 + `modules/opportunistic-verify.md` / `modules/retro-proposals.md` 経由で 6 skill) に更新。エントリのアルファベット順位置も見直す
- `docs/ja/structure.md`: `docs/translation-workflow.md` の Sync Procedure に基づき、上記 `docs/structure.md` の変更を日本語ミラー (168 行目) に反映する
- `modules/worktree-lifecycle.md`: [Outbound pointer sync candidate] § "`source`-based shell function calls are blocked by the worktree isolation guard" の「There is no rewrite that avoids `source` for a function call, so this is a hard blocker」という記述が、本 Issue の変更で 2 例目の反例を持つことになる。wrapper script パターン (`scripts/emit-skill-event.sh`、および `scripts/collect-run-facts.sh --session-from-issue`) を第一選択として記述し、defer/skip フォールバックはその次に降格する。#1458 の merge Phase Handoff § Deferred Items が follow-up として持ち越した項目でもある

**Steering Docs sync candidate 機械的スイープの記録** (`grep -rl <keyword> docs/ tests/ scripts/ modules/ | wc -l`、閾値 8 超で skip):

- `emit-verify-event.sh` → 8 件 (閾値内、個別評価済み): `docs/structure.md` / `docs/ja/structure.md` / `modules/event-emission.md` / `tests/emit-verify-event.bats` / `scripts/emit-verify-event.sh` を上記 Changed Files に採用。`docs/sessions/8142-1788873286-2026-09-08/session.md` と `docs/spec/issue-1456-*.md` / `docs/spec/issue-1458-*.md` は履歴記録のため除外
- `collect-run-facts.sh` → 51 件、skip: matched 51 files (no discriminating power)
- `retro-proposals.md` → 42 件、skip: matched 42 files (no discriminating power)
- `opportunistic-verify.md` → 29 件、skip: matched 29 files (no discriminating power)
- `emit-event.sh` → 105 件、skip: matched 105 files (no discriminating power)
- `--session-from-issue` / `--emit-issue` → 0 件 (新規導入キーワード、既存参照なし)
- `docs/migration-notes.md`: 本 Issue は CLI シグネチャを変更するが、同ファイルに `emit-verify-event.sh` / `emit-event.sh` / `collect-run-facts.sh` の記載は無い (grep 済み) ため対象外

## Implementation Steps

1. `scripts/emit-verify-event.sh` を `git mv scripts/emit-verify-event.sh scripts/emit-skill-event.sh` で改名する (→ 受入条件 3, 4)

   ヘッダーコメントを次の趣旨に書き換える (usage 行を含む):

   ```
   # emit-skill-event.sh - Single-command wrapper for skill/module event emission.
   #
   # Replaces the `source emit-event.sh` + restore_auto_session_pointer + guard +
   # emit_event compound snippet that skills/verify/SKILL.md (#1458) and
   # modules/opportunistic-verify.md / modules/retro-proposals.md (#1461)
   # previously embedded inline (rejected by the worktree isolation guard as
   # "too complex to verify that it stays inside the worktree").
   #
   # Usage:
   #   emit-skill-event.sh <issue> <event> [--require-session-id|--unconditional]
   #                       [--emit-issue <N>] [--session-id <SID>] [key=value ...]
   #   emit-skill-event.sh --persist-session <sid-or-empty> <issue>
   ```

   実行権限 (`chmod +x`) を維持する (`git mv` は保持するが、`test -x` で確認すること)。

2. `scripts/emit-skill-event.sh` のインターフェースを拡張する (after 1) (→ 受入条件 3, 4)

   `set -uo pipefail` を維持し `set -e` は使わない (`[[ cond ]] && exit 0` 形との組み合わせは #1458 で明示的に避けた既知の落とし穴)。既存の `--persist-session` 分岐と `--require-session-id` / `--unconditional` の 3 モードは挙動を変えない。

   変更点 (`SCRIPT_DIR` 定義の直後、`source` の直前に依存チェックを挿入し、`MODE` 解析ループを拡張する):

   ```bash
   # (a) 依存スクリプト存在チェック — SCRIPT_DIR 定義直後、source の直前
   if [[ ! -f "$SCRIPT_DIR/emit-event.sh" ]]; then
     echo "Error: emit-event.sh not found under $SCRIPT_DIR" >&2
     exit 1
   fi
   source "$SCRIPT_DIR/emit-event.sh"

   # (b) MODE 解析を「先頭のフラグを順不同で読むループ」へ拡張
   #     (既存の if/elif 単発判定を置き換える。`key=value` 引数は `--` で始まらないので
   #      ループはフラグ列の終端で自然に停止する)
   MODE="standard"
   EMIT_ISSUE_OVERRIDE=""
   SESSION_ID_ARG=""
   while [[ "${1:-}" == --* ]]; do
     case "$1" in
       --require-session-id) MODE="require-session-id"; shift ;;
       --unconditional)      MODE="unconditional"; shift ;;
       --emit-issue)
         if [[ $# -lt 2 ]]; then echo "Error: --emit-issue requires an argument" >&2; exit 1; fi
         EMIT_ISSUE_OVERRIDE="$2"; shift 2 ;;
       --session-id)
         if [[ $# -lt 2 ]]; then echo "Error: --session-id requires an argument" >&2; exit 1; fi
         SESSION_ID_ARG="$2"; shift 2 ;;
       *) echo "Error: unknown option: $1" >&2; exit 1 ;;
     esac
   done

   # (c) --session-id は restore の前に export する
   #     (restore_auto_session_pointer は既に設定済みの AUTO_SESSION_ID を
   #      authoritative として採用する — resolution order step 2)
   if [[ -n "$SESSION_ID_ARG" ]]; then
     AUTO_SESSION_ID="$SESSION_ID_ARG"
     export AUTO_SESSION_ID
   fi

   # (d) 非数値 <issue> の扱い: 数値のときだけ issue-scoped ポインタ解決に使う
   if [[ "$ISSUE" =~ ^[0-9]+$ ]]; then
     restore_auto_session_pointer "$ISSUE"
     EMIT_ISSUE="$ISSUE"
   else
     restore_auto_session_pointer
     EMIT_ISSUE="0"
   fi

   # (e) --emit-issue の上書きと数値バリデーション
   if [[ -n "$EMIT_ISSUE_OVERRIDE" ]]; then
     if [[ "$EMIT_ISSUE_OVERRIDE" =~ ^[0-9]+$ ]]; then
       EMIT_ISSUE="$EMIT_ISSUE_OVERRIDE"
     else
       echo "Warning: --emit-issue is not a positive integer, using 0: $EMIT_ISSUE_OVERRIDE" >&2
       EMIT_ISSUE="0"
     fi
   fi
   ```

   最終行の `EMIT_ISSUE_NUMBER="$ISSUE" emit_event "$EVENT" "$@"` を `EMIT_ISSUE_NUMBER="$EMIT_ISSUE" emit_event "$EVENT" "$@"` へ変更する。

   `ISSUE="${1:?usage: ...}"` の usage 文言も新しい usage 行に合わせて更新する。

   **fail-safe 挙動 (このスクリプトは `AUTO_EVENTS_LOG` 未解決時に `exit 0` する「安全側デフォルト」設計のため、edge case を明記する)**:
   - **空文字 `<issue>`**: `${1:?...}` は空文字を「未設定」とは扱わないので usage エラーにならず、非数値扱いで (d) の else 分岐に入る (`restore_auto_session_pointer` を引数なしで呼び、`EMIT_ISSUE=0`)
   - **非数値 `<issue>`** (例 `batch-<session-id>`): 同上。`emit_event()` は `"issue":${_issue}` を引用符なしで書くため、非数値をそのまま渡すと JSON が壊れる。`0` への置換は **fail-closed** (JSON 破損を防ぐ側に倒す)
   - **`--emit-issue` が非数値/空**: stderr に警告を出して `0` を採用 (同じく fail-closed)。emit 自体は続行する
   - **`key=value` の値に `>` / `"` / 改行 / タブ / マルチバイト文字が含まれる場合**: `emit_event()` 側の既存サニタイズ (改行除去・タブ→空白・`\` と `"` のエスケープ) に委ねる。本スクリプトで追加のサニタイズは行わない。`>` は既に quote 済みシェル変数の中にあるためリダイレクトにはならない。**CR (`\r`) は `emit_event()` がサニタイズしないため、CRLF 入力は JSON 文字列中に生の CR を残す** — これは既存の `emit-event.sh` の挙動であり、Issue の Out of scope (「`scripts/emit-event.sh` 自体の実装変更」) に該当するため本 Issue では修正しない (Notes 参照)
   - **入力長**: 上限・切り詰めは設けない。呼び出し側が切り詰める (`modules/retro-proposals.md` の `title=` は 80 文字に切り詰め済み)
   - **依存コマンド失敗**: `$SCRIPT_DIR/emit-event.sh` が存在しない場合は (a) で stderr にエラーを出し **exit 1 (fail-closed)**。理由: sibling script の欠落は実行時条件ではなくパッケージング不具合であり、現状の暗黙の exit 127 より可視化する方が良い。`git`/`ps` 等 `restore_auto_session_pointer()` 内部の依存が失敗した場合は同関数が既に fail-open (ポインタ未解決 → 空 prefix / no-op) で、その先はモード別ガードが `exit 0` する既存挙動を維持する

3. `tests/emit-verify-event.bats` を `git mv tests/emit-verify-event.bats tests/emit-skill-event.bats` で改名し、新規テストケースを追加する (after 2) (→ 受入条件 4)

   既存 11 ケースの `SCRIPT=` path とファイル冒頭コメントを新しいスクリプト名へ更新する (既存ケースの検証内容は変更しない)。**既存スイートが PASS することだけでなく、Step 2 で追加した新規分岐を検証する新規テストケースを追加したうえでスイートが PASS すること**。最低限のカバレッジ:
   - `--emit-issue <N>` を渡すと、出力 JSON の `issue` フィールドが positional `<issue>` ではなく `<N>` になる
   - `--emit-issue` に非数値を渡すと stderr に警告が出て `issue` が `0` になり、exit 0 で emit される
   - 非数値 positional `<issue>` (例 `batch-abc`) で `issue` が `0` になり、JSON が `jq` でパース可能である
   - `--session-id <SID>` を渡すと、ポインタファイルが存在しなくても出力 JSON の `session_id` が `<SID>` になる
   - フラグ順不同 (`--emit-issue` と `--require-session-id` の併記) が期待どおり解釈される
   - `$SCRIPT_DIR/emit-event.sh` が無い場合 (`WHOLEWORK_SCRIPT_DIR` を空ディレクトリに向ける) に exit 1 かつ stderr にエラーが出る

   bats アサーションは `[[ "$output" ... ]]` の裸形を避け `|| false` を付ける (`scripts/check-bare-bracket-assertions.sh` / #1412)。

4. `scripts/collect-run-facts.sh` に `--session-from-issue <N>` を追加する (parallel with 1, 2, 3) (→ 受入条件 1, 4)

   引数パースループに次のケースを追加する (既存 `--issue` と同じ形):

   ```bash
   --session-from-issue)
     if [ $# -lt 2 ]; then
       echo "Error: --session-from-issue requires an argument" >&2
       exit 1
     fi
     SESSION_FROM_ISSUE="$2"
     shift 2
     ;;
   ```

   `SESSION_FROM_ISSUE=""` を既存の `SESSION_ARG=""` 群の隣で初期化し、既存 `--issue` の数値バリデーションの直後に同形のバリデーションを置く:

   ```bash
   if [ -n "$SESSION_FROM_ISSUE" ] && ! echo "$SESSION_FROM_ISSUE" | grep -qE '^[0-9]+$'; then
     echo "Error: --session-from-issue must be a positive integer: $SESSION_FROM_ISSUE" >&2
     exit 1
   fi
   ```

   session 解決ラダーを次の順序に拡張する。新ステップは `AUTO_SESSION_ID` env の直後、`.tmp/auto-session-current` の直前に挿入する:

   ```
   --session > AUTO_SESSION_ID env > --session-from-issue (issue-scoped pointer) > .tmp/auto-session-current
   ```

   ```bash
   if [ -z "$SESSION_ID" ] && [ -n "$SESSION_FROM_ISSUE" ]; then
     if [ -f "$SCRIPT_DIR/emit-event.sh" ]; then
       # shellcheck source=/dev/null
       . "$SCRIPT_DIR/emit-event.sh"
       restore_auto_session_pointer "$SESSION_FROM_ISSUE"
       SESSION_ID="${AUTO_SESSION_ID:-}"
     else
       echo "Warning: emit-event.sh not found under $SCRIPT_DIR; skipping --session-from-issue resolution" >&2
     fi
   fi
   ```

   **設計上の判断 (明示)**:
   - **`source` は遅延実行**: トップレベルではなくこの分岐の中で `source` する。`tests/run-fact-matching.bats` が `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を全ケースに適用しているため、トップレベルで無条件 `source` すると `set -euo pipefail` 下で既存 20 件超のケースが一斉に失敗する
   - **依存欠落時は fail-open** (警告を出してラダーを続行し、`.tmp/auto-session-current` へ進む)。Step 2 の `emit-skill-event.sh` を fail-closed にしたのとは逆方向だが、理由が異なる — こちらでは `--session-from-issue` は既存ラダーへの *追加* ステップに過ぎず、オプショナルなヘルパーの欠落でスクリプト全体を失敗させると既存パイプラインを壊す
   - **ラダー 3 番目に置く理由**: `--session` と env は明示的/in-band で authoritative。issue-scoped ポインタは `.tmp/auto-session-current` より前でなければならない — 後者は #1224 が「並行 `/auto` セッション下で構造的に誤帰属する」として `restore_auto_session_pointer()` 自身からは削除したフォールバックであるため
   - **`restore_auto_session_pointer` は `AUTO_EVENTS_LOG` が既に設定済みなら即 return する**。その場合 `SESSION_ID` は空のままラダーを進む (既存挙動と同じ)

   ヘッダーコメントの Usage 行と "Session resolution order" 行を上記に合わせて更新する (`modules/run-fact-matching.md` 33 行目がこのヘッダーを SSoT と宣言しているため、ヘッダー更新で同期は足りる)。

5. `tests/run-fact-matching.bats` に `--session-from-issue` の新規テストケースを追加する (after 4) (→ 受入条件 4)

   **既存スイートが PASS することだけでなく、Step 4 で追加した新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること**。`setup()` が `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているため、新規ケースの中で実 `scripts/emit-event.sh` を `$MOCK_DIR` へコピーしてから実行する (`cp "$PROJECT_ROOT/scripts/emit-event.sh" "$MOCK_DIR/"`)。最低限のカバレッジ:
   - `--session-from-issue <N>` が `.tmp/auto-session-issue-<N>` ポインタから session id を解決し、facts JSON の `session_id` に反映される
   - ポインタファイルが存在しない場合は `.tmp/auto-session-current` へフォールバックする
   - `--session` を併記した場合は `--session` が優先される
   - 非数値の値で exit 1 かつ `Error: --session-from-issue must be a positive integer` が stderr に出る
   - `$MOCK_DIR` に `emit-event.sh` が無い状態では警告を出して既存ラダーを継続する (fail-open)

6. `modules/opportunistic-verify.md` を書き換える (after 2, 4) (→ 受入条件 1, 3)

   受入条件 1 の `file_not_contains` はコードブロック外の地の文も対象になるため、`restore_auto_session_pointer` という文字列をファイルから完全に除去すること。

   - **Step 1 "Resolve `--facts`"**: 複合ブロック (現行 32-37 行目の fenced block) を次の単一コマンドに置換する。

     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh --session-from-issue <calling skill's own Issue/PR number>
     ```

     直後の解説 (現行 39 行目) を、`restore_auto_session_pointer` という関数名に触れずに書き換える: session id 解決は `collect-run-facts.sh` の `--session-from-issue` が担い、issue-scoped ポインタが `.tmp/auto-session-current` フォールバックより先に評価されること、および完全な解決順序の SSoT は `modules/event-emission.md` § "Non-Wrapper Emitters" と `scripts/collect-run-facts.sh` のヘッダーコメントであること。「**Run this as a single Bash tool call**」の段落 (別プロセスへ export が引き継がれない問題の説明) は、単一コマンド化によって前提そのものが消えるため削除する
   - **Step 1 の分岐説明** (現行 41-43 行目): `.tmp/facts-${AUTO_SESSION_ID}.json` を `.tmp/facts-<calling Issue number>.json` に変更する (`AUTO_SESSION_ID` が LLM 側から見えなくなるため。`.tmp/context-<calling Issue number>.md` と同じ命名規約に揃う。このファイル名の外部消費者は無い — grep 済み)。分岐条件は「`AUTO_SESSION_ID` が解決したか」から「コマンドが exit 0 で JSON を stdout に出したか」に変更する。exit 非 0 (session 未解決) の場合は `--facts` を省略する。Step 1 の呼び出し例 (現行 49 行目) の `[--facts ...]` も同じファイル名に更新する
   - **Step 3 "Persist Judgment Results"**: 複合ブロック (現行 77-83 行目) を次の単一コマンドに置換する。

     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh" <calling skill's own Issue/PR number> opportunistic_verify_result \
       --emit-issue <candidate Issue number N this condition belongs to> \
       "skill=<calling skill name (e.g., /spec)>" \
       "result=<PASS|FAIL|SKIP>" \
       "ac_index=<1-based index>"
     ```

     続く箇条書きを書き換える: `AUTO_EVENTS_LOG` ガード (現行 87 行目) は「スクリプトが内部で適用するので呼び出し側の `if` は不要」に、`EMIT_ISSUE_NUMBER` と session 解決対象の差異 (現行 89 行目) は「positional `<issue>` が session ポインタ解決用の呼び出し元 Issue/PR 番号、`--emit-issue` が判定対象の候補 Issue 番号 (イベントの `issue` フィールドに載る)」に、いずれも関数名を出さずに書き換える。`ac_index` の箇条書きは変更しない

7. `modules/retro-proposals.md` を書き換える (after 2) (→ 受入条件 2, 3)

   受入条件 2 の `file_not_contains` も地の文を含むため、`restore_auto_session_pointer` という文字列をファイルから完全に除去すること。

   - **Step 6 "Tier classification persistence"**: 複合ブロック (現行 66-72 行目) を次の単一コマンドに置換する。

     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh" <NUMBER> retro_proposal_classified \
       "tier=<1|2|3>" \
       "title=<proposal title, first 80 chars>" \
       "reason=<one-line classification rationale>" \
       "action=<issue_created|memory_proposal|spec_only>"
     ```

   - **Numeric guard の箇条書き** (現行 74 行目): 「呼び出し側が `EMIT_ISSUE_NUMBER=0` を渡し引数なしで復元関数を呼ぶ」から「`NUMBER` が非数値 (`/auto` L3 の `BRIDGE_NUMBER="batch-<session-id>"` 等) でもそのまま渡してよい。スクリプトが数値判定を行い、非数値なら issue-scoped ポインタ解決を省略しイベントの `issue` を `0` にする」へ書き換える。`emit_event()` が `"issue":${_issue}` を引用符なしで書くため非数値は JSON を壊す、という理由は残す
   - **`/auto` parent-session callers の箇条書き** (現行 75 行目): 「`AUTO_SESSION_ID="<literal SESSION_ID>"` をブロック先頭で設定する」から「`--session-id "<literal SESSION_ID>"` フラグを付けて呼び出す」へ書き換える。in-band 引き渡しが非数値 `NUMBER` ケースで唯一信頼できる経路である、という理由は残す
   - **`AUTO_EVENTS_LOG` guard の箇条書き** (現行 76 行目): 「スクリプトが内部でガードを適用するので呼び出し側の `if` は不要」へ書き換える
   - **Output 節** (現行 172 行目): 「emitted ... when `AUTO_EVENTS_LOG` is set (directly or via `restore_auto_session_pointer`)」を「emitted ... when the session pointer resolves (see step 6)」相当へ書き換える

8. `skills/verify/SKILL.md` を更新する (after 1) (→ 受入条件 4)

   本文 15 箇所の `emit-verify-event.sh` を `emit-skill-event.sh` に置換する (呼び出し引数は変更しない — 既存 3 モードは互換)。frontmatter `allowed-tools` の `${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh:*` を `${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh:*` に置き換え、`${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を削除する。

   置換後に `wc -l skills/verify/SKILL.md` を実行し、値が `<!-- skill-body-lines: N -->` マーカーと一致しない場合はマーカーを実測値に更新する (`tests/verify.bats` の "skill-body-lines marker stays in sync with wc -l" が回帰テスト)。

9. 他 5 skill の `allowed-tools` を更新する (after 1, 6, 7) (→ 受入条件 4)

   `skills/auto/SKILL.md`, `skills/code/SKILL.md`, `skills/issue/SKILL.md`, `skills/review/SKILL.md`, `skills/spec/SKILL.md` の frontmatter `allowed-tools` について、`${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を `${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh:*` に置き換える (同一位置での置換)。`skills/audit/SKILL.md` は変更しない。

   完了後に `python3 scripts/validate-skill-syntax.py skills/` を実行し 0 error であることを確認する (cross-file 検証が、両 module の参照する全スクリプトが各 reader の `allowed-tools` に含まれることを機械的に保証する)。あわせて `grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/emit-event\.sh' skills/ modules/` が 0 件であることを確認し、`emit-event.sh:*` の削除が安全であったことを裏取りする。

10. ドキュメントを同期する (after 1, 6, 7) (→ 受入条件 3)

    - `modules/event-emission.md`: 182 / 192 / 200 / 202 行目を Changed Files 記載どおり更新する。200 / 202 行目の「calls `source emit-event.sh` + `restore_auto_session_pointer`」という記述を `scripts/emit-skill-event.sh` 経由の新メカニズムに書き換える。182 行目の解決順序リスト自体 (1-5) は `restore_auto_session_pointer()` の内部仕様として維持してよい (このファイルは受入条件 1/2 の `file_not_contains` 対象外)
    - `docs/structure.md`: 175 行目のエントリを改名し、caller 記述を更新する
    - `docs/ja/structure.md`: 168 行目を同内容で日本語反映する (`docs/translation-workflow.md` Sync Procedure)
    - `modules/worktree-lifecycle.md`: § "`source`-based shell function calls are blocked by the worktree isolation guard" を、wrapper script パターンを第一選択とする記述に改める

## Verification

### Pre-merge

- <!-- verify: file_not_contains "modules/opportunistic-verify.md" "restore_auto_session_pointer" --> `modules/opportunistic-verify.md` に `restore_auto_session_pointer` の直接呼び出しが残っていない
- <!-- verify: file_not_contains "modules/retro-proposals.md" "restore_auto_session_pointer" --> `modules/retro-proposals.md` に `restore_auto_session_pointer` の直接呼び出しが残っていない
- <!-- verify: rubric "modules/opportunistic-verify.md と modules/retro-proposals.md の event emission 手順が、source を伴う複合コマンドではなく、worktree isolation guard に拒否されない単一コマンド呼び出しで記述されている" --> 両 module の event emission が単一コマンド形の wrapper 呼び出しで記述されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> `bats tests/` の全テストが CI 上で green (PR route)

### Post-merge

- 次回 `/spec` `/code` `/review` のいずれかを worktree route で実行した際、スキル完了時の opportunistic verification の event emission が回避策なしで成功することを観察 <!-- verify-type: opportunistic -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/emit-skill-event.sh:*` — 6 skill (`auto`/`code`/`issue`/`review`/`spec`/`verify`) の `allowed-tools` に追加が必要
- `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` — 同 6 skill から削除する (置換後は SKILL.md 本文・`modules/*.md` のいずれからも参照されない)
- `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*` — `modules/opportunistic-verify.md` の 5 reader (`code`/`issue`/`review`/`spec`/`verify`) に既に登録済み (追加不要、grep 済み)

### Built-in Tools

- なし (既存の `Read` / `Write` / `Edit` / `Glob` / `Grep` で足りる)

### MCP Tools

- なし

## Uncertainty

- **worktree isolation guard の拒否条件が「`source` を含む複合コマンド」であること**: harness 側の実装であり公開仕様が無いため、外部ドキュメントでは確認できない。
  - **検証方法**: 本 Spec 作成セッション (worktree `spec/issue-1461` 内) で実測済み。`modules/retro-proposals.md` が prescribe する複合コマンドをそのまま実行して拒否されること、および `bash scripts/emit-verify-event.sh 1461 spec_guard_probe phase=spec` の単一コマンド形が exit 0 で正常に emit されることを確認した (Reproduction Steps 参照)。
  - **出所**: `/spec 1461` 実行セッション (session_id `90128-1788933783`)、worktree `/Users/saito/src/wholework/.claude/worktrees/spec+issue-1461`、2026-09-10T01:04:17Z。emit された JSON 行は Reproduction Steps 手順 4 に転記済み。
  - **影響範囲**: Implementation Steps 2, 4, 6, 7 (単一コマンド化の方針全体)
- **`set -euo pipefail` 下で `emit-event.sh` を source し `restore_auto_session_pointer` を呼んでも異常終了しないか**: `restore_auto_session_pointer()` は `[[ cond ]] && return 0` 形の短絡評価を 2 箇所含み、#1458 Spec はこの形と `set -e` の組み合わせを落とし穴として記録している。`collect-run-facts.sh` は `set -euo pipefail` を使うため、Implementation Step 4 の前提になる。
  - **検証方法**: 本 Spec 作成セッションで `set -euo pipefail` のスクリプトから source + 呼び出しを実行し、`before` / `after rc=0` の両方が出力され exit 0 で終了することを実測済み。`emit-event.sh` はトップレベルに `set` 文も実行文も持たず関数定義とコメントのみのため、source 自体も副作用を持たない (grep 済み)。
  - **出所**: 同上セッション。`.tmp/probe-set-e.sh` として実行 (一時ファイルのため commit していない。再実行手順は Implementation Step 4 のコード片から再現可能)。
  - **影響範囲**: Implementation Step 4

## Consumed Comments

- saito (MEMBER, first-class): `/issue --non-interactive` の Issue Retrospective。曖昧ポイント 3 件の自動解決ログ (`emit-verify-event.sh` の再利用方針 / 非数値 `NUMBER` 対応の具体化を `/spec` へ委譲 / `allowed-tools` 見直し対象 7 skill の個別判定を `/spec` へ委譲) と、Pre-merge AC 4 の verify command を `command "bats tests/"` から `github_check "gh pr checks" "Run bats tests"` へ変更した記録。本 Spec は 3 件すべてを解決済み — 再利用方針は「改名して流用」、非数値 `NUMBER` は Implementation Step 2 (d) のスクリプト側数値判定、`allowed-tools` 対象は grep で 6 skill と確定 (audit を除外)。 (https://github.com/saitoco/wholework/issues/1461#issuecomment-5611001693)

## Notes

### 実装との矛盾 (Conflict with implementation)

Issue 本文の起票時の記述と実装に 2 件の矛盾があり、いずれも非対話モードの自動解決として本文を訂正した (AC は変更していない)。

- **「この 2 module は 7 つの skill から参照されている」**: `grep -l` ベースの数値で、`skills/audit/SKILL.md` を含んでいた。実際の reader は `${CLAUDE_PLUGIN_ROOT}/modules/xxx.md` 形式で参照する 6 skill (`auto`/`code`/`issue`/`review`/`spec`/`verify`)。`skills/audit/SKILL.md:566` は `opportunistic_verify_result` イベントの集計元として module 名を地の文で言及するだけで読み込まない。`validate-skill-syntax.py` の `MODULES_REF_PATTERN` (`\$\{CLAUDE_PLUGIN_ROOT\}/modules/([a-zA-Z0-9_-]+\.md)`) と同じ判定基準を採用した。**解決**: `allowed-tools` 更新対象を 6 skill に確定し、Issue 本文を訂正
- **「`/spec` `/code` `/review` は自身の worktree 内でスキル完了時の opportunistic verification を実行する」**: 誤り。`/spec` Step 14 (Worktree Exit) → Step 17 (Opportunistic Verification)、`/code` Step 14 → Step 15、`/review` `## Worktree Exit (push-and-remove)` → Opportunistic Verification (しかも `detect-foreign-worktree.sh` が `none` を返すことを明示的に assert する)、`/verify` Step 13 → Step 14 と、すべて Worktree Exit 後に配置されている。`/issue` と `/auto` 親セッションは worktree を持たない。**解決**: Issue を却下せず、順序不変条件の脆さ・`foreign` worktree 経路・`emit-event.sh:*` 削除という 3 つの実在する根拠に置き換えて本文を訂正した (Root Cause 参照)

### 自動解決ログ (Autonomous Auto-Resolve Log)

- **`scripts/emit-verify-event.sh` を `scripts/emit-skill-event.sh` へ改名して流用** — reason: `/issue` フェーズが既に「新規 module 専用スクリプトは重複のため不採用、既存スクリプトの再利用・拡張」を決定済み。そのうえで本 Issue 後は 6 skill から呼ばれる共通 wrapper になるため、`/verify` 専用に見える名前は誤解を招く。改名の影響範囲は 8 ファイル (履歴記録 3 件を除くと 5 ファイル) で機械的に完結することを grep で確認した。
  - Other candidates: 名前を据え置いて拡張のみ行う案 (差分は小さいが `/spec` `/code` `/review` `/issue` `/auto` から "verify" という名前のスクリプトを呼ぶことになる)
- **`--emit-issue <N>` フラグで session ポインタ用 issue と emit 対象 issue を分離** — reason: `modules/opportunistic-verify.md` Step 3 は `restore_auto_session_pointer <呼び出し元 Issue>` と `EMIT_ISSUE_NUMBER=<候補 Issue>` が異なる、という既存仕様を持つ。既存スクリプトは positional `<issue>` を両方に使うため、この分離を表現できるフラグが必須。
  - Other candidates: positional 引数を 2 個にする案 (`/verify` の既存 15 箇所すべての呼び出し形が壊れるため不採用)
- **非数値 `<issue>` はスクリプト側で自動判定 (呼び出し側に分岐を書かせない)** — reason: `modules/retro-proposals.md` の `NUMBER` は `/auto` L3 route で `batch-<session-id>` になりうる。現行 module は「非数値なら `EMIT_ISSUE_NUMBER=0` を渡し引数なしで復元関数を呼べ」と LLM に分岐を要求しているが、スクリプト側で `^[0-9]+$` を判定すれば呼び出し形が 1 つで済む。fail-closed (JSON 破損防止) の方向に倒す判断とも整合する。
  - Other candidates: `--session-only` のような別コマンドに分離する案 (`/issue` の自動解決ログが挙げていた候補。呼び出し側の分岐が残るため不採用)
- **`modules/opportunistic-verify.md` Step 1 は `collect-run-facts.sh --session-from-issue` で単一コマンド化** — reason: このブロックは emit ではなく facts JSON の取得であり、emit wrapper に相乗りさせると名前と責務が乖離する。session id を必要としているのは `collect-run-facts.sh` 自身なので、その解決ラダーに 1 ステップ足すのが最も自然。`collect-run-facts.sh:*` は 5 reader すべての `allowed-tools` に既に登録済みで、追加の権限変更も不要。
  - Other candidates: (a) emit wrapper に `--run-facts` モードを足す案 / (b) 別途 `scripts/resolve-run-facts.sh` を新設する案 (どちらも責務配置が悪い、または新規スクリプト増加)
- **`emit-event.sh:*` は 6 skill すべての `allowed-tools` から削除** — reason: `grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/emit-event\.sh' skills/ modules/` の結果、参照元は本 Issue で置換する 2 module のみで、SKILL.md 本文からの参照は 0 件。置換後は `validate-skill-syntax.py` の cross-file 検証が要求しなくなるため、#1458 が見送った削除が安全に実行できる。
  - Other candidates: 併記のまま残す案 (最小権限の観点で劣り、Issue Scope が明示的に問うている論点でもある)

### その他

- **fail-safe critical 判定**: `scripts/emit-skill-event.sh` は判定基準 (c) 「失敗時に安全側デフォルトを返す設計」に該当する (`AUTO_EVENTS_LOG` 未解決時の `exit 0`)。edge case の期待挙動は Implementation Step 2 末尾に明記した。`scripts/collect-run-facts.sh` も既存の fail-open パターン (`2>/dev/null || true` を多用) を持つため、新規追加分の fail-open 方向とその理由を Implementation Step 4 に明記した
- **audit/investigation 型 Issue 判定**: 該当しない。本 Issue は既存項目の分類・判定結果を成果物として残すものではなく、スクリプトと module を変更する実装 Issue であるため、identifier 存在検証ステップの追加は不要
- **CR (`\r`) サニタイズは対象外**: `emit_event()` は改行・タブ・`\`・`"` はサニタイズするが CR はしない。CRLF を含む値は JSON 文字列中に生の CR を残す。Issue の Out of scope が「`scripts/emit-event.sh` 自体の実装変更」を除外しているため本 Issue では修正せず、既知の制約として記録するに留める。#1458 の merge Phase Handoff § Deferred Items が挙げた「`issue`/`event` 値の validate/sanitize」と同系統の課題
- **WHOLEWORK_SCRIPT_DIR mock**: Implementation Step 4 は `scripts/collect-run-facts.sh` に sibling script の `source` を新規追加する。`tests/run-fact-matching.bats` は `setup()` で `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を全ケースに適用しているため、(a) `source` を分岐内の遅延実行にする、(b) 新規ケースで実 `emit-event.sh` を `$MOCK_DIR` へコピーする、の 2 点を Implementation Steps に明記した。この 2 点が無いと既存 20 件超のケースが一斉に失敗する
- **新規テストケース要求のまとめ**: Implementation Step 2 (`emit-skill-event.sh` の 3 分岐追加) と Step 4 (`collect-run-facts.sh` の解決ラダー 1 ステップ追加) はいずれも既存スクリプトへの新規分岐追加に該当する。受入条件 4 (`github_check "gh pr checks" "Run bats tests"`) は既存スイートの PASS だけでなく、`tests/emit-skill-event.bats` と `tests/run-fact-matching.bats` への新規ケース追加を伴うことを Step 3 / Step 5 に明記した
- **`skills/verify/SKILL.md` の `skill-body-lines` マーカー**: 本 Issue の変更は文字列置換と frontmatter 1 行の編集のみで行数は変わらない見込みだが、`tests/verify.bats` の回帰テストがあるため Implementation Step 8 に実測確認を含めた (#1458 で同マーカーの追従漏れが実際に FAIL を起こした前例がある)
- **`docs/migration-notes.md` は対象外**: 本 Issue は CLI シグネチャを変更するが、同ファイルに対象 3 スクリプトの記載は無い (grep 済み)

## issue retrospective

### Ambiguity Resolution (Non-Interactive Auto-Resolve)

#### Autonomous Auto-Resolve Log

- **`scripts/emit-verify-event.sh` の再利用方針** — reason: #1458 の Verify Retrospective (Improvement Proposals) が「本 Issue と同じ wrapper 方針で解消できる」と明記しており、既存スクリプトの再利用・拡張が最も既存パターンと整合する。新規に module 専用スクリプトを作ることはコード重複を生むため不採用。
  - Other candidates: `modules/opportunistic-verify.md` / `modules/retro-proposals.md` 専用の新規ラッパースクリプトを別途作成する案
- **`modules/retro-proposals.md` の非数値 `NUMBER` (`batch-<session-id>`) 対応の具体化** — reason: 既存 `scripts/emit-verify-event.sh` は `<issue>` を必須引数として扱うため、非数値ケース (`EMIT_ISSUE_NUMBER=0` + 引数なし `restore_auto_session_pointer`) をサポートするインターフェース拡張の要否・形が未確定。Acceptance Criteria のテキスト (file_not_contains / rubric) はこの実装詳細に依存しないため、具体的なインターフェース設計は `/spec` のコードベース調査に委ねるのが最も低リスク。
  - Other candidates: 非数値ケースを別コマンド (例: `--session-only`) に分離する案
- **`allowed-tools` 見直し対象の 7 skill (`audit`/`auto`/`code`/`issue`/`review`/`spec`/`verify`) の個別判定** — reason: Scope は「`skills/*/SKILL.md` の allowed-tools を見直す」と一般化して記載されているが、現在どの skill が `emit-event.sh:*` を frontmatter に宣言しているかは実装時の grep 調査が必要で、Acceptance Criteria テキストには影響しない。Issue 本文への事前列挙は不要と判断し、`/spec` の調査に委ねた。
  - Other candidates: 7 skill 全てを Scope に明示列挙する案

### Acceptance Criteria Change

- Pre-merge AC 4 の verify command を `command "bats tests/"` から `github_check "gh pr checks" "Run bats tests"` に変更した。本 Issue は Size=L (`get-issue-size.sh` で確認) であり、`modules/size-workflow-table.md` の Size-to-Workflow Mapping Table では L は PR route。`skills/issue/SKILL.md` の AC Writing Guide は Size M/L で `github_check "gh pr checks"` 形を用いることを明記しており、`command` hint のままだと `/review` safe mode で UNCERTAIN 扱いになる。同種の route 不整合修正は `docs/spec/issue-998-operate-completion-signature.md` (Design Gaps/Ambiguities) に前例がある。

### Consumed Comments

No new comments since last phase.

## spec retrospective

### Minor observations

- Issue 本文の「N 個の skill から参照されている」という主張が `grep -l` ベースで、実際の consumer (`validate-skill-syntax.py` の `MODULES_REF_PATTERN`) の判定基準と一致していなかった。参照数の主張は、その数値を実際に消費する仕組みの matching rule で再導出しないと 1 件ずれる (`skills/audit/SKILL.md` が地の文で module 名に言及するだけで reader に計上されていた)。
- `/issue` Step 5 (Background Factual Claim Verification) は本 Issue の Background の 2 件の事実誤認 (reader 数、worktree 内実行の有無) を検出できなかった。どちらも「5 つの SKILL.md の step 順序を実際に読む」ことでしか判定できず、Background の文面だけでは真偽が決まらない種類の主張だった。
- `/spec` の "WHOLEWORK_SCRIPT_DIR mock addition check" は「`scripts/` 配下に新規スクリプトを追加する場合」にのみ発火する。今回のように「既存スクリプトに sibling script の `source` を新規追加する」ケースは同じ失敗モード (mock ディレクトリに実体が無く既存スイートが一斉に落ちる) を持つが、チェックの発火条件に含まれていない。

### Judgment rationale

- Issue Scope が `/spec` に委ねた「改名か流用か」は、改名の影響範囲を先に測って (`git grep -l` で 8 ファイル、履歴記録 3 件を除くと 5 ファイル) から決めた。改名コストが機械的置換に収まることを確認したうえで、6 skill から呼ばれる共通 wrapper が `/verify` 専用に見える名前を持つ不整合の方を重く見た。
- `modules/opportunistic-verify.md` Step 1 のブロックは emit ではなく facts JSON の取得であり、`/issue` の自動解決ログが決めた「既存 emit スクリプトを再利用」をそのまま当てはめると `emit-*.sh` に `--run-facts` モードを足すことになり責務が乖離する。「session id を必要としているのは `collect-run-facts.sh` 自身」という所在に基づいて `--session-from-issue` を同スクリプト側に置いた。
- `emit-skill-event.sh` は依存欠落で fail-closed (exit 1)、`collect-run-facts.sh` の `--session-from-issue` は fail-open (警告してラダー継続) と、同一 Issue 内で逆方向の判断をしている。前者は `source` がスクリプトの存在理由そのもの、後者は既存ラダーへの追加ステップに過ぎない、という違いに基づく。両方の理由を Implementation Steps に明記した。

### Uncertainty resolution

- worktree isolation guard が複合 `source` コマンドを拒否するという Issue の前提を、本 Spec 作成セッション自身の worktree 内で実測して確認した (拒否メッセージの再現と、単一コマンド形の成功の両方)。推測ではなく一次観測として Reproduction Steps に記録し、出所 (session_id / worktree path / タイムスタンプ) を Uncertainty 節に添えた。
- #1458 Spec が「`set -e` と `[[ cond ]] && exit 0` の組み合わせは異常終了する既知の落とし穴」と記録していたため、`set -euo pipefail` の `collect-run-facts.sh` から `restore_auto_session_pointer` を呼べるか不明だった。実測の結果、短絡評価が AND リストの最終コマンドでない限り `set -e` は発火せず、正常に exit 0 で完了する。#1458 の注意書きは「新規スクリプトの書き方の指針」としては妥当だが「既存関数を `set -e` 下から呼べない」という意味ではない。
- 新規分岐ロジックに対する新規テストケース要求のまとめ: Implementation Step 2 (`emit-skill-event.sh` に `--emit-issue` / `--session-id` / 非数値 `<issue>` の 3 分岐を追加) と Step 4 (`collect-run-facts.sh` の session 解決ラダーに 1 ステップ追加) が該当する。受入条件 4 は既存スイートの PASS だけでは不十分で、`tests/emit-skill-event.bats` に 6 ケース (`--emit-issue` 正常 / `--emit-issue` 非数値 / 非数値 positional / `--session-id` / フラグ順不同 / 依存欠落 exit 1)、`tests/run-fact-matching.bats` に 5 ケース (ポインタ解決 / フォールバック / `--session` 優先 / 非数値バリデーション / 依存欠落 fail-open) の新規追加を要する。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions

- `scripts/emit-verify-event.sh` を `scripts/emit-skill-event.sh` へ改名して流用する (新規スクリプトは作らない)。本 Issue 後は 6 skill から呼ばれる共通 wrapper になるため。改名の影響範囲は 5 ファイル (履歴記録を除く) で機械的に完結することを grep で確認済み。
- 非数値 `<issue>` の判定を LLM 側ではなくスクリプト側 (`^[0-9]+$`) に置く。`modules/retro-proposals.md` から呼び出し形の分岐を消せるうえ、`emit_event()` の unquoted `"issue":${_issue}` による JSON 破損を fail-closed で防げる。
- `modules/opportunistic-verify.md` Step 1 (facts 解決、emit ではない) は emit wrapper に相乗りさせず、`scripts/collect-run-facts.sh` に `--session-from-issue <N>` を追加して解決する。session id を必要としているのは同スクリプト自身であり、`collect-run-facts.sh:*` は 5 reader すべての `allowed-tools` に登録済みで権限変更も不要。
- `emit-event.sh:*` は 6 skill (`auto`/`code`/`issue`/`review`/`spec`/`verify`) すべての `allowed-tools` から削除する。参照元が本 Issue で置換する 2 module のみであることを grep で確認済み。`skills/audit/SKILL.md` は reader ではないため対象外。

### Deferred Items

- `emit_event()` の CR (`\r`) 未サニタイズは本 Issue では修正しない。Issue の Out of scope (「`scripts/emit-event.sh` 自体の実装変更」) に該当する。#1458 merge Phase Handoff の「`issue`/`event` 値の validate/sanitize」と同系統の未対応課題として残る。
- `/spec` の "WHOLEWORK_SCRIPT_DIR mock addition check" が「既存スクリプトへの sibling `source` 新規追加」を発火条件に含んでいない点は、本 Issue のスコープ外。spec retrospective に観測として記録済み (Improvement Proposal の起票は `/verify` フェーズで集約される)。
- Post-merge AC は `verify-type: opportunistic`。次の `/spec` `/code` `/review` の実行が実際の確認機会であり、本 PR 内で追加対応は不要。

### Notes for Next Phase

- 受入条件 1/2 の `file_not_contains "modules/*.md" "restore_auto_session_pointer"` は **コードブロック外の地の文も対象**。両 module の該当行 (opportunistic-verify: 39/87/89、retro-proposals: 74/75/76/172) の書き換えを忘れると FAIL する。#1458 でも同じ注意が Implementation Step に明記されていた。
- Implementation Step 4 の `source` は必ず分岐内の遅延実行にすること。トップレベルで無条件 `source` すると `tests/run-fact-matching.bats` が `setup()` で `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を全ケースに適用しているため、既存 20 件超が一斉に失敗する。
- Step 9 完了後に `python3 scripts/validate-skill-syntax.py skills/` が 0 error であることと、`grep -rn '\${CLAUDE_PLUGIN_ROOT}/scripts/emit-event\.sh' skills/ modules/` が 0 件であることの両方を確認すること。前者は追加漏れ、後者は削除の安全性を担保する。
- `skills/verify/SKILL.md` の `<!-- skill-body-lines: N -->` マーカーは `tests/verify.bats` の回帰テスト対象。行数が変わった場合は `wc -l` 実測値へ更新する (#1458 で実際に FAIL した前例あり)。
