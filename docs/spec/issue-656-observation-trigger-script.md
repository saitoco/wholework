# Issue #656: verify: observation trigger スクリプト（observation-trigger.sh）を実装

## Overview

`verify-type: observation event=<name>` AC の自動 trigger 機構として、`scripts/observation-trigger.sh` を新規作成する。

設計は `modules/observation-trigger.md` に従い、各 emitter（`/review`、`/auto`、`claude-watchdog.sh`、`/verify`）が event 発火時に `observation-trigger.sh --event <name>` を呼び出す one-liner 形式に統合する。スクリプトは内部で `opportunistic-search.sh --event <name>` を呼び出し、matched Issue に comment を投稿して `/verify <N>` 再実行を促す（comment-posting のみ; AI judgment は行わない）。

## Changed Files

- `scripts/observation-trigger.sh`: 新規作成 — bash 3.2+ 互換
- `skills/review/SKILL.md`: event-based observation scan ブロック（観察イベントスキャン）を `observation-trigger.sh` one-liner に置き換え; `observation-trigger.sh:*` を allowed-tools に追加
- `skills/auto/SKILL.md`: event-based observation scan ブロックを `observation-trigger.sh` one-liner に置き換え; allowed-tools の `opportunistic-search.sh:*` を `observation-trigger.sh:*` に変更（auto skill は opportunistic-verify.md を持たないため opportunistic-search.sh の直接呼び出しがなくなる）
- `scripts/claude-watchdog.sh`: watchdog-kill 発火後のインライン処理ブロックを `observation-trigger.sh --event watchdog-kill` one-liner に置き換え — bash 3.2+ 互換
- `skills/verify/SKILL.md`: FAIL → reopen ブロック内（`gh issue reopen "$NUMBER"` 直後）に `observation-trigger.sh --event fix-cycle` 呼び出しを追加; `observation-trigger.sh:*` を allowed-tools に追加
- `tests/observation-trigger.bats`: 新規作成 — `opportunistic-search.sh` を `WHOLEWORK_SCRIPT_DIR` mock で、`gh` を PATH mock で代替
- `docs/structure.md`: scripts 件数 55→57（実際 56+1）、tests 件数 74→78（実際 77+1）に修正; `scripts/observation-trigger.sh` のエントリを追加
- `docs/ja/structure.md`: `docs/structure.md` の変更をミラー
- `modules/observation-trigger.md`: 「Future Extension」節を「実装済み（#656）」に更新

## Implementation Steps

1. `scripts/observation-trigger.sh` を新規作成する: `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` パターンを使用; `--event <name>`（必須）と `--dry-run`（オプション）を受け付ける; `${SCRIPT_DIR}/opportunistic-search.sh --event "$EVENT_NAME"` を呼び出し結果 JSON をパース; 各 Issue number に `gh issue comment "$N" --body "observation event \`${EVENT_NAME}\` detected. Run \`/verify ${N}\` to verify the condition and update the checkbox."` を実行（`2>/dev/null || true` で non-fatal）。（→ AC 1, 2, 3）
2. `skills/review/SKILL.md` の event-based 観察スキャンブロック（`opportunistic-search.sh --event ...` 呼び出し + JSON 処理インライン 8行）を `observation-trigger.sh` one-liner 2行に置き換え; allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh:*` を追加（`opportunistic-search.sh:*` は opportunistic-verify.md が使うため残す）。（after 1）（→ AC 4）
3. `skills/auto/SKILL.md` の event-based 観察スキャンブロック（`opportunistic-search.sh --event auto-run` + JSON 処理インライン 7行）を `observation-trigger.sh --event auto-run` one-liner に置き換え; allowed-tools の `opportunistic-search.sh:*` を `observation-trigger.sh:*` に変更。（after 1）（→ AC 5）
4. `scripts/claude-watchdog.sh` の watchdog-kill 観察スキャンブロック（approx 15行のインライン処理）を `observation-trigger.sh --event watchdog-kill` one-liner に置き換え; `skills/verify/SKILL.md` の FAIL → reopen ブロック（`ISSUE_STATE` が `CLOSED` の場合の `gh issue reopen` 直後）に `observation-trigger.sh --event fix-cycle` 呼び出しを追加し allowed-tools にも追加。（after 1）（→ ACs 6, 7）
5. `tests/observation-trigger.bats` を新規作成（テストケース: 引数エラー、--dry-run、マッチなし時の沈黙、マッチ 1 件時のコメント投稿、複数マッチ、`opportunistic-search.sh` エラー時の継続）; `docs/structure.md`・`docs/ja/structure.md`・`modules/observation-trigger.md` を更新。（parallel with 2, 3, 4）（→ ACs 8, 9）

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/observation-trigger.sh" --> `scripts/observation-trigger.sh` が新規作成されている
- <!-- verify: grep "--event" "scripts/observation-trigger.sh" --> `--event <name>` 引数を受け取る処理が実装されている
- <!-- verify: grep "opportunistic-search.sh" "scripts/observation-trigger.sh" --> `opportunistic-search.sh` を呼び出す処理が実装されている
- <!-- verify: grep "observation-trigger.sh" "skills/review/SKILL.md" --> `/review` skill に `observation-trigger.sh` 呼び出しが配線されている
- <!-- verify: grep "observation-trigger.sh" "skills/auto/SKILL.md" --> `/auto` skill に `observation-trigger.sh` 呼び出しが配線されている
- <!-- verify: grep "observation-trigger.sh" "scripts/claude-watchdog.sh" --> `claude-watchdog.sh` に `observation-trigger.sh` 呼び出しが配線されている
- <!-- verify: grep "observation-trigger.sh" "skills/verify/SKILL.md" --> `/verify` skill の FAIL → reopen 箇所に `observation-trigger.sh --event fix-cycle` 呼び出しが追加されている
- <!-- verify: file_exists "tests/observation-trigger.bats" --> bats テストファイル `tests/observation-trigger.bats` が新規作成されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト（正常系・異常系）が CI で PASS している

### Post-merge

なし

## Notes

- 設計は `modules/observation-trigger.md` を参照
- dispatch 実装は comment-posting のみ（auto-resolve #1）: `run-verify.sh` が存在せず shell から非対話的に `/verify` を spawn できないため、`claude-watchdog.sh` の既存パターンに合わせ comment-posting に一本化
- review/auto emitter の AI judgment インライン処理は削除（auto-resolve #2）: 全 emitter の実装統一を優先し、最シンプルな comment-posting に一本化。AI judgment による checkbox 更新は今後の follow-up で検討
- bats テストスコープ: `observation-trigger.sh` 単体テストのみ（auto-resolve #3）。emitter 配線は grep verify command による pre-merge 静的検証でカバー
- `scripts/claude-watchdog.sh` の変数名（`_watchdog_event_results` 等）は削除される; 全体の行数が削減される
- `docs/structure.md` の件数修正: scripts (55→57: 現在の実数 56 + 新規 1)、tests (74→78: 現在の実数 77 + 新規 1) — 既存ドリフト分も含めて修正

## Code Retrospective

### Deviations from Design

- Spec では `tests/` 件数を「74→78」と記載していたが、実際のドキュメントには「74 ファイル」と記載されており、実数は77（+1で78）。件数差分は既存ドリフトのため deviation なし — Spec の通り修正した。
- `verify/SKILL.md` への `observation-trigger.sh --event fix-cycle` の追加場所: `gh issue reopen "$NUMBER"` の直後（Spec 通り）に配置し、`emit verify_reopen_cycle event` ブロックの前に挿入。

### Design Gaps/Ambiguities

- `--dry-run` フラグの動作: Spec には「`opportunistic-search.sh` 引数として渡す」とは記載されていなかったが、`--dry-run` 時は `opportunistic-search.sh` 呼び出し自体をスキップするシンプルな実装を選択。ghost API call を避けるという点で合理的。
- `gh issue comment` の引数配置: `observation-trigger.sh` では「`/verify ${N}` を再実行してください」ではなく英語メッセージ（Spec の文面に従い "Run `/verify ${N}` to verify the condition and update the checkbox."）を使用。CLAUDE.md で「スクリプトのユーザー向けメッセージは英語」とは定められていないが、スクリプト内のコメント言語が英語という慣習に従った。

### Rework

- N/A（設計通り実装できた。テストは一発 PASS）

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `observation-trigger.sh` は comment-posting dispatch のみ（AI judgment なし）: Spec auto-resolve #1/#2 に従いシンプルな shell-only 実装を採用。`run-verify.sh` が存在しないためシェルからの `/verify` spawn は不可。
- emitter 統合は one-liner 置き換え: `/review`・`/auto` のインライン処理（AI judgment + checkbox update）は削除し、`observation-trigger.sh` 呼び出し一行に統一。
- `verify/SKILL.md` への `fix-cycle` 追加: `gh issue reopen` 直後に配線し、CLOSED→OPEN 遷移時のみ発火する形を維持（OPEN 時の reopen スキップ branch にはない）。

### Deferred Items
- AI judgment による observation AC チェックボックス自動更新は削除された（follow-up 候補）。comment-posting のみでユーザー手動 `/verify` 再実行が必要。
- `gh issue comment` のメッセージ内容（英語）の最終化は review フェーズで確認。

### Notes for Next Phase
- bats テスト 8件は全 PASS、SKILL.md syntax validation も OK。CI (bats CI run) は PR #671 で確認。
- `ISSUE_STATE` が `OPEN` の場合（`gh issue reopen` は実行されない）の `fix-cycle` 発火パスは verify/SKILL.md では配線されていないが、これは Spec の "CLOSED 時のみ reopen" 設計に準拠。必要なら別途検討。
