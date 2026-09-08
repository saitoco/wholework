# Issue #1458: verify: worktree 実行中に isolation guard へ拒否される複合コマンドを単一コマンド化する

## Overview

`/verify` は Step 3 (Worktree Entry) が全ルートで必須であり、以降の Step は必ず worktree 内で実行される。しかし `skills/verify/SKILL.md` が明示している event emission コマンド形 (`source .../emit-event.sh` → `restore_auto_session_pointer` → `if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then emit_event ...; fi`、SKILL.md 内 14 箇所) と、Step 1 のセッションポインタ永続化コマンド (`source .../emit-event.sh` → `persist_auto_session_pointer ...`、1 箇所) は、`source` を伴う複合コマンドであるため worktree isolation guard に「too complex to verify that it stays inside the worktree」として拒否される。

`scripts/emit-verify-event.sh` を新設し、この 15 箇所すべてを `bash scripts/emit-verify-event.sh ...` という単一コマンド呼び出しに置き換える。

## Reproduction Steps

1. `/verify N` を実行し、Step 3 (Worktree Entry) を経て worktree セッション内に入る。
2. Step 1 (phase_start emit) または Step 8b/Step 11 の event emission 分岐、あるいは Step 11 FAIL 分岐に到達する。
3. SKILL.md が指示する `source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` を含む複合コマンド (`restore_auto_session_pointer` / `persist_auto_session_pointer` 呼び出し + `if` ガード) を実行しようとする。
4. worktree isolation guard が「too complex to verify that it stays inside the worktree」として拒否する。
5. 実際に 2026-09-08 の `/verify 1456` 実行で発生し、`.tmp/` にワンショットのヘルパースクリプトを書いて `bash .tmp/xxx.sh` の単純形で実行する回避を要した。

## Root Cause

`source` によるシェル関数呼び出しは、worktree isolation guard がそのコマンドが worktree 内に留まることを静的に検証できないため、単独では拒否される (`modules/worktree-lifecycle.md` § "`source`-based shell function calls are blocked by the worktree isolation guard" に既知の制約として記録済み)。`skills/verify/SKILL.md` の該当箇所は `source` + 関数呼び出し + `if` ガード + 関数呼び出しという複数文からなる複合コマンドをコードブロックとして毎回インラインに埋め込んでおり、これが拒否される複合構造そのものである。

Background に記載された「Step 1 の `persist_auto_session_pointer` 呼び出し (1 箇所)」も同じ `source` 依存の複合コマンドであり、同じ拒否パターンに該当する。

修正方針: `source` + 関数呼び出しロジックを `scripts/` 配下の実行可能スクリプトに切り出し、SKILL.md 側は `bash scripts/emit-verify-event.sh <args>` という単一の plain コマンドを呼ぶだけにする。Background に記載された実際の回避策 (`.tmp/` のワンショットヘルパースクリプトを `bash .tmp/xxx.sh` の単純形で実行) が現に guard を通過したことが、この方針の有効性を裏付けている。

## Changed Files

- `scripts/emit-verify-event.sh`: 新規追加。event emission (`<issue> <event> [--require-session-id|--unconditional] [key=value ...]`) とセッションポインタ永続化 (`--persist-session <sid-or-empty> <issue>`) の両方を単一コマンドで実行できるようにするラッパースクリプト。bash 3.2+ 互換。実行権限 (`chmod +x`) を付与する
- `tests/emit-verify-event.bats`: 新規追加。上記スクリプトの bats テスト
- `skills/verify/SKILL.md`: 14 箇所の event emission 複合スニペットと Step 1 の persist 複合スニペット (計 15 箇所) を `scripts/emit-verify-event.sh` への単一コマンド呼び出しに置換。`allowed-tools` frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh:*` を追加し、直接呼び出しがなくなる `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` エントリを削除 (同一位置で置き換え)
- `modules/event-emission.md`: [Steering Docs sync candidate — 直接読解による検出] § "Non-Wrapper Emitters" が「Every `AUTO_EVENTS_LOG`-gated emit site in `skills/verify/SKILL.md` calls `source emit-event.sh` + `restore_auto_session_pointer $NUMBER` immediately before the guard」および「`persist_auto_session_pointer` with it immediately after the phase banner」「all 11 `restore_auto_session_pointer $NUMBER` emit sites」と、本 Issue で置き換える旧メカニズムを直接記述している。`scripts/emit-verify-event.sh` 経由の新メカニズムを反映するよう更新する
- `docs/structure.md`: [Steering Docs sync candidate — 直接読解による検出] Scripts セクションの `scripts/emit-event.sh` エントリの説明末尾「`skills/verify/SKILL.md` (explicit bash call, no wrapper)」が本 Issue で不正確になる (直接呼び出しがなくなるため)。`scripts/emit-verify-event.sh` の新規エントリを追加し、`emit-event.sh` 側の説明を更新する (Key Files 節の保守規約に基づく)
- `docs/ja/structure.md`: `docs/translation-workflow.md` の Sync Procedure に基づき、`docs/structure.md` の変更を日本語ミラーに反映する

**Steering Docs sync candidate 機械的スイープの補足**: `docs/tech.md` Step 10 の keyword discriminating-power filter (`grep -rl <keyword> docs/ tests/ scripts/ modules/ | wc -l` が 8 件超で skip) を抽出キーワード `emit-event.sh` (103 件)・`restore_auto_session_pointer` (44 件)・`persist_auto_session_pointer` (12 件) に適用したところ、いずれも閾値超過で個別列挙を skip した。上記の `modules/event-emission.md` / `docs/structure.md` の 2 件は、この機械的スイープではなく Step 6 のコードベース直接読解 (該当ファイルを実際に Read して内容を確認) によって検出したもので、両者は独立した根拠である。

## Implementation Steps

1. `scripts/emit-verify-event.sh` を新規作成する (→ 受入条件 1)

   インターフェース:
   ```
   scripts/emit-verify-event.sh <issue> <event> [--require-session-id|--unconditional] [key=value ...]
   scripts/emit-verify-event.sh --persist-session <sid-or-empty> <issue>
   ```

   処理内容 (擬似コード。`set -uo pipefail` を用い `set -e` は使わない — `[[ cond ]] && exit 0` 形の短絡評価と `set -e` の組み合わせは、条件が偽のときに文全体の終了ステータスが非0になりスクリプトを異常終了させる既知の落とし穴のため、ガード判定は必ず `if` 文で書く):

   ```bash
   #!/bin/bash
   set -uo pipefail
   SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
   source "$SCRIPT_DIR/emit-event.sh"

   if [[ "${1:-}" == "--persist-session" ]]; then
     SID="${2:-}"
     ISSUE="${3:?usage: emit-verify-event.sh --persist-session <sid-or-empty> <issue>}"
     persist_auto_session_pointer "$SID" "$ISSUE"
     exit 0
   fi

   ISSUE="${1:?usage: emit-verify-event.sh <issue> <event> [--require-session-id|--unconditional] [key=value ...]}"
   EVENT="${2:?event name required}"
   shift 2

   MODE="standard"
   if [[ "${1:-}" == "--require-session-id" ]]; then
     MODE="require-session-id"; shift
   elif [[ "${1:-}" == "--unconditional" ]]; then
     MODE="unconditional"; shift
   fi

   restore_auto_session_pointer "$ISSUE"

   if [[ "$MODE" == "standard" ]]; then
     if [[ -z "${AUTO_EVENTS_LOG:-}" ]]; then exit 0; fi
   elif [[ "$MODE" == "require-session-id" ]]; then
     if [[ -z "${AUTO_EVENTS_LOG:-}" || -z "${AUTO_SESSION_ID:-}" ]]; then exit 0; fi
   fi
   # unconditional: no guard check (recoveries_threshold_fire の既存挙動を保存 — Notes 参照)

   EMIT_ISSUE_NUMBER="$ISSUE" emit_event "$EVENT" "$@"
   ```

   `chmod +x scripts/emit-verify-event.sh` を実行する。

2. `tests/emit-verify-event.bats` を新規作成する (after 1) (→ 受入条件 4)

   `tests/emit-event.bats` / `tests/verify-executability-marker.bats` の規約 (MOCK_DIR で `flock` をモック、`AUTO_EVENTS_LOG` を tmpdir に設定) に従い、最低限以下をカバーする:
   - `--persist-session <sid> <issue>` がポインタファイルを書き込む / 空 sid で削除する
   - standard モード: `AUTO_EVENTS_LOG` 未設定時は no-op (イベント行が書かれない)、設定時は emit される
   - `--require-session-id` モード: `AUTO_EVENTS_LOG` のみ設定 (`AUTO_SESSION_ID` 未設定) では no-op、両方設定で emit される
   - `--unconditional` モード: `AUTO_EVENTS_LOG` 未設定でも emit される (デフォルトパス `.tmp/auto-events.jsonl` に書かれる)
   - key=value 引数が JSON に正しく反映される (例: `verify_executability` の `ac_index`/`executable`/`reason`)
   - 使用法エラー (引数不足) で exit 1

3. `skills/verify/SKILL.md` を変更する (after 1) (→ 受入条件 2, 3, 5)

   以下の対応表に従い、15 箇所すべての複合スニペットを単一コマンド呼び出しに置換する。置換後のテキストに `restore_auto_session_pointer $NUMBER` という文字列 (旧複合スニペットの説明目的であっても) を残さないこと — 受入条件 3 の `file_not_contains` はコードブロック外の地の文も対象になる。

   | 箇所 (現在の文脈) | モード | 新しい単一コマンド (概形) |
   |---|---|---|
   | Step 1: `--session-id` 解析直後のポインタ永続化 | persist | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" --persist-session "<SID or empty>" "$NUMBER"` |
   | Step 1: banner 直後の `phase_start` | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER phase_start phase=verify` |
   | Step 8b: `verify_executability` | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER verify_executability ac_index={N} executable={true\|false} reason={slug or empty}` (該当時は `capability=`/`detail=` も付与 — 周辺の既存プローズ通り) |
   | Step 8b: `verify_user_confirm` | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER verify_user_confirm ac_index={N} "response={the selected option text}"` |
   | Step 11 (PASS/SKIPPED 等の早期分岐): `phase_complete` (4箇所: 早期分岐 + FAIL max-iterations + PENDING + UNCERTAIN 相当の各終端) | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER phase_complete phase=verify` |
   | Step 11 FAIL 分岐 (reopen): `verify_reopen_cycle` | require-session-id | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER verify_reopen_cycle --require-session-id iteration=${NEXT_ITERATION} reopen_reason=pre_merge_ac_fail` |
   | Step 11 FAIL 分岐: `verify_fail_marker_posted` (2箇所、同形) | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER verify_fail_marker_posted iteration=${NEXT_ITERATION} failed_ac_count=${FAIL_COUNT}` |
   | Step 11 tier-gated auto-retry: `verify_retry_fire` | standard | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER verify_retry_fire iteration=${NEXT_ITERATION} trigger_reason=ac_fail budget_remaining_tokens=unknown` |
   | Step 15 (recovery threshold 自動起票): `recoveries_threshold_fire` | unconditional | `bash "${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh" $NUMBER recoveries_threshold_fire --unconditional symptom={group-key} count={count} issue_number={new_issue_number}` |

   frontmatter `allowed-tools` の `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を `${CLAUDE_PLUGIN_ROOT}/scripts/emit-verify-event.sh:*` に置き換える (同一位置)。

4. ドキュメント同期 (after 1, parallel with 2/3) (→ 受入条件は無いが Changed Files 記載の整合性維持のため必須)

   - `modules/event-emission.md` § "Non-Wrapper Emitters": 「calls `source emit-event.sh` + `restore_auto_session_pointer $NUMBER` immediately before the guard」という記述を、「calls `scripts/emit-verify-event.sh $NUMBER <event> [key=value ...]` (#1458) — internally sources `emit-event.sh`, calls `restore_auto_session_pointer`, and applies the guard before calling `emit_event`」に置き換える。同様に `persist_auto_session_pointer()` の段落も `--persist-session` 経由に書き換える。「all 11 `restore_auto_session_pointer $NUMBER` emit sites」のような箇所数のハードコードは、今後のドリフトを避けるため具体的な数値を書かない表現に改める
   - `docs/structure.md`: `scripts/emit-event.sh` エントリ末尾の「`skills/verify/SKILL.md` (explicit bash call, no wrapper)」を削除し (直接呼び出しがなくなるため)、直後のアルファベット順の位置に `scripts/emit-verify-event.sh` の新規エントリを追加する
   - `docs/ja/structure.md`: 上記 `docs/structure.md` の変更を日本語で反映する (`docs/translation-workflow.md` Sync Procedure に従う)

## Verification

### Pre-merge

- <!-- verify: command "test -x scripts/emit-verify-event.sh" --> `scripts/emit-verify-event.sh` が実行可能な形で追加されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "emit-verify-event.sh" --> `skills/verify/SKILL.md` が新スクリプトを参照している
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "restore_auto_session_pointer $NUMBER" --> `skills/verify/SKILL.md` に複合 emit スニペットが残っていない
- <!-- verify: command "bats tests/emit-verify-event.bats" --> 新スクリプトのテストが追加されている
- <!-- verify: rubric "skills/verify/SKILL.md Step 1 のセッションポインタ永続化 (persist_auto_session_pointer 呼び出し) が、source を伴う複合コマンドではなく、worktree isolation guard に拒否されない単一コマンド形で記述されている" --> Step 1 のセッションポインタ永続化コマンドも worktree 内で実行可能な単一コマンド形に置き換わっている

### Post-merge

- 次回 `/verify N` の worktree 実行で、event emission が回避策なしで成功することを観察 <!-- verify-type: opportunistic -->

## Consumed Comments

- saito (MEMBER, first-class): Existing Issue Refinement (`--non-interactive`) の Issue Retrospective。曖昧ポイント自動解決 (Step 1 の `persist_auto_session_pointer` 呼び出しを Scope/AC に追加) と、テスト AC の強化 (存在チェック→実行チェック) を報告。本 Spec の Scope/Implementation Steps に反映済み。 (https://github.com/saitoco/wholework/issues/1458#issuecomment-5585813024)
- saito (MEMBER, first-class): Triage AC audit の警告コメント。「Step 4 の設定値解決手順」に対する rubric AC が常時 PASS になる懸念を指摘。現在の Issue 本文を確認したところ、当該 Scope 項目・AC は既に本文から除外され、Out of Scope セクションに理由 (Step 4 は `Read` ツールベースの記述のままで変更不要) が記録済みであることを確認した。本 Spec 作成時点で追加対応は不要。 (https://github.com/saitoco/wholework/issues/1458#issuecomment-5585874844)

## Notes

- **`verify_reopen_cycle` の実装正規化**: 現状 (`main` ブランチ時点) `verify_reopen_cycle` は `emit_event()` を使わず、同じフィールド構成 (`ts`/`issue`/`event`/`session_id`/`iteration`/`reopen_reason`) を生の `printf` で組み立てている (#902 で `source`+`restore_auto_session_pointer` が追加された際も printf 形は維持された — `docs/spec/issue-902-verify-session-instrumentation.md` 参照)。本 Issue で単一スクリプト化する際、`emit_event()` 経由に統一する (JSON 形状は同一なので既存コンシューマへの影響なし)。ガード条件は `AUTO_EVENTS_LOG` と `AUTO_SESSION_ID` の両方が必要という既存の意図的な設計 (「`/auto` セッション内でのみ emit」) を `--require-session-id` フラグとして維持する
- **`recoveries_threshold_fire` のガード欠如を意図的に保存**: 現状この箇所には `restore_auto_session_pointer` 呼び出しも `AUTO_EVENTS_LOG` ガードも存在しない。`docs/spec/issue-702-verify-recoveries-auto-file.md` の原設計では、この emit 行に到達する時点で既に `AUTONOMY_TIER=L2/L3 AND RECOVERIES_AUTO_FIRE_ENABLED=true` という上位条件で到達性がガードされているため、ローカルガードが省略されたとみられる。本 Issue の目的はコマンド形の単一化であり挙動変更ではないため、`--unconditional` フラグでこの既存挙動をそのまま保存する
- **新規スクリプトのテストカバレッジ**: `scripts/emit-verify-event.sh` は完全新規ファイルのため「既存ブランチへの新規ロジック追加」チェックの直接対象ではないが、同等の要求として Implementation Step 2 に 3 モード (`standard`/`--require-session-id`/`--unconditional`) + `--persist-session` の全分岐をテストする方針を明記した
- **Steering Docs sync candidate**: `docs/structure.md`/`modules/event-emission.md` は Step 10 の keyword discriminating-power filter (機械的スイープ) ではなく、Step 6 でのコードベース直接読解によって検出した。詳細は Changed Files 節末尾を参照
