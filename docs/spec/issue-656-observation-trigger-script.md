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

## review retrospective

### Spec vs. Implementation Divergence Patterns

`modules/observation-trigger.md` の Emitter Lookup Table（line 66）が PR によって更新されていなかった。`Future Extension` セクションは「実装済み #656」に更新されていたが、テーブル行だけが「(future)」「not yet implemented」のままで残り、同一ファイル内で矛盾が生じた。Spec には「`modules/observation-trigger.md` の Future Extension 節を更新」と記載されていたが、テーブル行の更新は Spec に明示されていなかったため、実装者が見落としたと考えられる。Spec に変更ファイルの具体的な更新箇所（節名だけでなく行レベルで）を記載することで防げた。

### Recurring Issues

今回の review では SHOULD 1件、CONSIDER 1件のみ。MUST 0件。パターンの繰り返しは見られなかった。Nothing to note.

### Acceptance Criteria Verification Difficulty

全9件の verify command が PASS。`github_check "gh pr checks" "Run bats tests"` は safe mode で CI 結果を参照でき、問題なく PASS を判定できた。`file_exists`・`grep` 系はすべて明確。UNCERTAIN 0件。ファイル内の特定行の更新を検証する verify command（`section_contains` 等）があれば Emitter Lookup Table の stale entry を事前検知できたかもしれない。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #671 を squash merge（`--delete-branch`）: mergeable=true、CI PASS、review approved を確認後、直接 Step 4 に進んだ。コンフリクト解消不要。
- BASE_BRANCH=main のため `closes #656` が自動でIssueをクローズ済み。手動クローズ不要。
- Phase Handoff（review phase）を読み込み: MUST issues なし、Emitter Lookup Table 修正コミット済みを確認。

### Deferred Items
- AI judgment による observation AC チェックボックス自動更新（comment-posting からの upgrade）は引き続き follow-up 候補。
- `observation-trigger.sh` の `--dry-run` 意味論差の文書化は任意レベルで defer。

### Notes for Next Phase
- verify コマンドは全9件 PASS 済み（Pre-merge検証）、Post-merge verifyセクションは「なし」。
- `observation-trigger.sh` が全 emitter に配線済みを静的検証済み。
- opportunistic-verify が有効なプロジェクトでの動作確認が verify フェーズで任意に実施可能。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` triage で Size=M を割り当て、3 件の曖昧点 (dispatch 方法 / 配線 vs 置き換え / bats スコープ) をすべて auto-resolve。それぞれが implementation-time に意思決定が必要な選択肢を pre-resolve し、後段の手戻りなし。

#### spec
- Spec で Size を M→L に再判定 (route は pr のまま、REVIEW_DEPTH のみ --light→--full)。5 step の atomic 実装計画 + Changed Files セクションが正確に実装をガイド。

#### code
- 単一 PR (#671) で全 5 step を first-pass 実装。8 件の bats テスト全 PASS、CI green。fixup/amend なし。`observation-trigger.sh` が `--event` 引数、comment-posting dispatch、`opportunistic-search.sh` 呼び出しの 3 役割を 1 file で過不足なく実装。

#### review
- review-full で 1 SHOULD 1 CONSIDER。SHOULD (Emitter Lookup Table 更新) は resolved として PR 内で対応、CONSIDER (--dry-run 注記) は skipped 判定。MUST なし。Lightweight re-check も validate-skill-syntax 0 errors で PASS。

#### merge
- squash merge 成功 (--delete-branch)。reviewDecision 空のまま precondition warn-only で通過し、CI PASS により問題なくマージ。`closes #656` で自動クローズ。

#### verify
- 9/9 pre-merge AC PASS。Post-merge AC なし。Phase Handoff (merge phase) に記録された情報がすべて再現可能。

### Improvement Proposals
- N/A — workflow が clean に完走し、特筆すべき構造的改善なし。本セッションは #670 (AUTO_EVENTS_LOG export) fix が実環境で機能することを実証した点でも価値あり (events 配線が pr route で正常動作)。
