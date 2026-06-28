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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- polling backoff を `gh-pr-merge-status.sh` 内部に閉じ込める設計を採用。merge/SKILL.md の routing ロジックを変更しないため regression リスクが低い。
- exit 2 を polling timeout 専用とし、exit 1 を gh fetch error 専用に分離。両者を区別することで呼び出し元の error handling が精緻になる。
- `RETRY_DELAYS=(30 60)` の 2 ステップのみ (合計待機 90s 上限)。GitHub metadata sync は通常 30〜60s 以内に解決するため、過度な待機を避けつつリスクを低減できる判断。

### Deferred Items
- polling 成功/abort をログ以外の手段 (exit code 以外の structured output 等) で呼び出し元に通知する仕組みは本 Issue スコープ外。merge/SKILL.md での error handling 改善は別途検討。
- `RETRY_DELAYS` の値を `.wholework.yml` で設定可能にする拡張は現時点で不要だが、将来の要望に備えて Spec Notes に記録済み。

### Notes for Next Phase
- CI で `bats tests/` が全 11 件 PASS することを確認する (polling test も含む)。
- `exit 2` が `merge/SKILL.md` または `run-merge.sh` 側で適切にハンドリングされているか確認推奨 (本 PR では変更なし)。
- Post-merge AC は `verify-type: observation event=auto-run` のため次回 merge phase での実観察が必要。
