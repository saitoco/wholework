# Issue #839: merge: mergeable=unknown を polling backoff で metadata sync 遅延と genuine failure を区別

## Overview

`scripts/gh-pr-merge-status.sh` が `MERGEABLE==UNKNOWN && STATE==UNKNOWN` を返した際、現状は即座に `reason=unknown` を出力する。merge SKILL.md の non-interactive auto-resolve がこれを受けて強行 merge を試みる挙動があり、GitHub metadata sync 遅延と CI failure / protection rule mismatch を区別できない事故リスクがある (#831 retrospective 発生源)。

polling backoff (初回 30s 待機 → 再確認 → 2 回目 60s 待機 → 再確認 → max retries 超過で非ゼロ exit) を `gh-pr-merge-status.sh` スクリプト内に追加し、metadata syncing と genuine failure を区別する。polling で解決した場合は既存ルーティングロジックをそのまま通す。

## Changed Files

- `scripts/gh-pr-merge-status.sh`: `MERGEABLE==UNKNOWN && STATE==UNKNOWN` ケースに polling backoff (sleep + re-check、max retries 後 exit 2) を追加 — bash 3.2+ compatible
- `tests/gh-pr-merge-status.bats`: `setup()` に sleep no-op mock と stateful gh mock helper 追加; polling 成功シナリオ (UNKNOWN×2 → CLEAN) + max retries abort シナリオの 2 テスト追加

## Implementation Steps

1. `scripts/gh-pr-merge-status.sh` の初回 fetch 後 (`MERGEABLE` / `STATE` 取得直後)、既存 if/elif chain の前に polling backoff ブロックを追加 (→ AC1):
   - `RETRY_DELAYS=(30 60)` (bash 3.2+ compatible array)
   - `[[ "$MERGEABLE" == "UNKNOWN" && "$STATE" == "UNKNOWN" ]]` の場合のみ発火
   - while ループ内: `retry_count >= ${#RETRY_DELAYS[@]}` なら stderr にエラーメッセージを出力し `exit 2`; それ以外は delay を取得し stderr に進行ログ出力 → `sleep "$delay"` → `gh pr view` 再取得 → `MERGEABLE`/`STATE` 更新 → `retry_count` インクリメント
   - polling で解決後、既存 if/elif chain (CLEAN/HAS_HOOKS/CONFLICTING/BLOCKED/UNSTABLE/BEHIND/else) がそのまま判定
   - スクリプト冒頭の `# reason values:` コメントに exit 2 の注釈を追加

2. `tests/gh-pr-merge-status.bats` に以下を追加 (→ AC2):
   - `setup()` に sleep no-op mock (`cat > "$MOCK_DIR/sleep" <<'MOCK'; #!/bin/bash; exit 0; MOCK; chmod +x "$MOCK_DIR/sleep"`)
   - stateful gh mock helper `make_gh_mock_stateful()`: counter file (`$BATS_TEST_TMPDIR/gh_call_count`) を使い、最初の N 回は `UNKNOWN/UNKNOWN`、以降は指定した `mergeable/state` を返す
   - `@test "polling: UNKNOWN twice then CLEAN resolves to clean"`: `make_gh_mock_stateful 2 "MERGEABLE" "CLEAN"` → exit 0、`"mergeable": true`、`"reason": "clean"` を検証
   - `@test "polling: max retries exceeded with UNKNOWN exits non-zero"`: `make_gh_mock "UNKNOWN" "UNKNOWN"` (常時 UNKNOWN) → exit が non-zero であることを検証

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-pr-merge-status.sh に MERGEABLE==UNKNOWN のケースで polling backoff (sleep + re-check) ロジックが追加されており、max retries 後に非ゼロ exit で abort する" --> <!-- verify: grep "sleep" "scripts/gh-pr-merge-status.sh" --> `scripts/gh-pr-merge-status.sh` に `MERGEABLE==UNKNOWN` のケースで polling backoff (sleep + re-check) ロジックが追加されており、max retries 後に非ゼロ exit で abort する
- <!-- verify: command "bats tests/gh-pr-merge-status.bats" --> `tests/gh-pr-merge-status.bats` に polling 成功シナリオ (複数回の UNKNOWN 後に CLEAN になる) と max retries 後 abort シナリオが追加されている

### Post-merge

- 次回 merge phase で `mergeable=UNKNOWN` が観察された際、polling backoff が機能することを観察 <!-- verify-type: observation event=auto-run -->

## Consumed Comments

- `saito` (MEMBER / first-class): Issue Retrospective — 実装場所 (`gh-pr-merge-status.sh` を選択)・non-interactive fallback (abort)・スコープ (UNKNOWN ケースのみ) の自動解決ログ、AC 変更内容 (rubric 特定化、grep "sleep" 追加、command "bats tests/gh-pr-merge-status.bats" に変更) を記録

## Notes

- **自動解決事項** (消費コメントより転記):
  1. 実装場所: `scripts/gh-pr-merge-status.sh` に polling を閉じ込め、`merge/SKILL.md` の routing ロジックをシンプルに保つ
  2. Non-interactive mode 最終 fallback: max retries 後は `exit 2` (非ゼロ) で abort — CI bypass リスク回避
  3. スコープ: `MERGEABLE==UNKNOWN && STATE==UNKNOWN` ケースのみ。既存 BLOCKED→review_pending / UNSTABLE→ci_failing / BEHIND→behind_base は変更しない
- **bash 3.2+ 互換性**: `RETRY_DELAYS=(30 60)` と `${#RETRY_DELAYS[@]}`、`${RETRY_DELAYS[$retry_count]}` はすべて bash 3.2 で動作する (macOS system bash)
- **exit 2 の意味**: polling timeout abort を示す。`exit 1` は gh fetch error 専用として残す
- **sleep mock**: bats テストで `sleep` を no-op mock にしないと各テストが 90 秒かかるため、setup() に追加することで全テストに適用
- **stateful gh mock**: counter file を `$BATS_TEST_TMPDIR` に置くことで各テスト run ごとにリセットされる (bats の tmpdir はテストごとに独立)

## Code Retrospective

### Deviations from Design

- N/A — Spec の Implementation Steps どおりに実装した。polling backoff ブロックの挿入位置、RETRY_DELAYS の値、exit 2 の使用、stateful mock の counter file パスいずれも Spec 記載と一致。

### Design Gaps/Ambiguities

- `make_gh_mock_stateful` のヒアドキュメント内で `$counter_file` を展開する際、`<<MOCK` (unquoted) を使うことで変数が実際のパスに展開される。`<<'MOCK'` にすると展開されず mock が壊れる点は Spec 未記載だった (実装中に把握)。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

- Spec と実装は完全一致。polling backoff ブロックの挿入位置、`RETRY_DELAYS=(30 60)`、`exit 2`、stateful mock ヘルパーのすべてが Spec 記載通りに実装されていた。divergence なし。

### Recurring issues

- なし。コードの変更範囲が小さく、各ファイルの変更が明確に分離されていた (script に機能追加、test にテスト追加)。

### Acceptance criteria verification difficulty

- `rubric` + `grep "sleep"` の 2 重 verify は効果的。ただし `grep "sleep"` 単独では `sleep` を使う他の用途と区別できないため、rubric の意味的判定が補完として重要だった。
- `command "bats tests/gh-pr-merge-status.bats"` は safe mode で CI 代替検証 (SUCCESS) を使用できた。CI fallback が機能した事例。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- REVIEW_DEPTH=light (Size=M) で軽量統合レビューを実施。全 AC が PASS、CI が全 SUCCESS のため MUST/SHOULD 問題なし。
- review-light エージェントタイプが未登録 (available agents に存在しない) のため、モジュールを読み込んで inline で 4 観点レビューを実施した。
- CONSIDER 1 件 (bats abort テストの exit code 特定性不足) は skip。機能的に正しく regression リスクは低い。

### Deferred Items
- CONSIDER: bats abort テストで `[ "$status" -eq 2 ]` ではなく `[ "$status" -ne 0 ]` を使用中。exit code 精緻化は機能的に問題ないが、将来の変更時の regression 検知精度を高めるための改善候補。
- merge/SKILL.md での exit 2 ハンドリングは本 PR スコープ外 (code フェーズより引き継ぎ)。
- Post-merge AC は `verify-type: observation event=auto-run` のため次回 merge phase での実観察が必要。

### Notes for Next Phase
- 全 AC が PASS、全 CI が SUCCESS。MUST 問題なし。`/merge 845` を実行可能。
- `exit 2` が `merge/SKILL.md` または `run-merge.sh` 側で適切にハンドリングされているかの確認推奨 (本 PR では変更なし。code フェーズからの引き継ぎ事項)。
- Post-merge AC は `verify-type: observation event=auto-run` として設定済み。次回 merge phase で `mergeable=UNKNOWN` が観察された際に polling backoff の動作を確認。
