# Issue #798: verify: loop-state heartbeat dirty state による /verify ブロックを解消

## Overview

`/code`、`/review`、`/merge` の各フェーズで `append-loop-state-heartbeat.sh` が `docs/sessions/_daily/loop-state-{DATE}.md` に行を追記するが、commit/push しないため dirty state が残る。次の `/verify` 実行時に `check-verify-dirty.sh` が exit 1 (非 spec dirty ファイル) を返し、verify が起動できなくなる。#781 と #783 の verify retrospective で連続して発生した。

案 B を採用: `check-verify-dirty.sh` に loop-state ファイルの built-in 免除パターンを追加し、heartbeat-only diff を exit 0 (clean 扱い) にする。heartbeat スクリプト自体は変更しない。

## Reproduction Steps

1. `/auto --batch` を実行し、あるフェーズ (code/review/merge) が完了する
2. `append-loop-state-heartbeat.sh` が `docs/sessions/_daily/loop-state-YYYY-MM-DD.md` に追記する
3. push せずに次フェーズが `/verify` に進む
4. `check-verify-dirty.sh` が loop-state ファイルを非 spec dirty ファイルとして exit 1 を返す
5. `/verify` が "Cannot run verify" エラーで停止し、手動で `git commit + git pull --rebase` が必要になる

## Root Cause

`check-verify-dirty.sh` のファイル分類ルールが `docs/spec/issue-N-*.md` (unrelated spec) のみを免除対象としており、`docs/sessions/_daily/loop-state-*.md` は "その他の dirty ファイル" として exit 1 に分類される。`append-loop-state-heartbeat.sh` は best-effort 設計で commit しない仕様のため、このファイルが dirty になることは想定内だが、verify 側に免除ロジックがない。

案 B 採用: `check-verify-dirty.sh` に built-in 免除パターンを追加することで解消する。Case A (heartbeat 内 commit/push) は commit 履歴肥大・push race リスクがあり採用しない。

## Changed Files

- `scripts/check-verify-dirty.sh`: `verify-ignore-paths` ロード後に built-in 免除パターン `docs/sessions/_daily/loop-state-*.md` を追加、警告メッセージを汎化 — bash 3.2+ compatible
- `tests/verify-dirty-detection.bats`: loop-state built-in 免除の新規テストケース2件を追加

## Implementation Steps

1. `scripts/check-verify-dirty.sh` の `verify-ignore-paths` ロードブロック (`while IFS= read...` ループ) 直後に以下を挿入 (→ AC1、AC4)
   - Case B 採用コメント: `# Built-in exempt: loop-state heartbeat files are exempt from the dirty check.` + 採用理由 (Case B #798)
   - `ignore_patterns+=("docs/sessions/_daily/loop-state-*.md")`
   - 警告メッセージは変更しない ("excluded by verify-ignore-paths" のまま。user-config と built-in で同一配列を使うため、既存テストへの影響を最小化)

2. `tests/verify-dirty-detection.bats` に2テストケースを追加 (→ AC3)
   - `@test "loop-state heartbeat only dirty: exit 0 (built-in exempt)"`: `docs/sessions/_daily/loop-state-YYYY-MM-DD.md` のみ dirty → exit 0 かつ Warning 出力
   - `@test "loop-state mixed with non-spec dirty: exit 1"`: loop-state + 非 spec ファイルが dirty → exit 1

## Verification

### Pre-merge

- <!-- verify: rubric "loop-state heartbeat の dirty state による /verify の block が解消されている。scripts/append-loop-state-heartbeat.sh または scripts/check-verify-dirty.sh のいずれかが修正され、heartbeat-only diff のケースで /verify が clean state で開始できる" --> heartbeat 関連 dirty state の friction が解消されている
- <!-- verify: command "bats tests/append-loop-state-heartbeat.bats" --> append-loop-state-heartbeat の bats テストが green (案 A 採用時: 新規ケース追加)
- <!-- verify: command "bats tests/verify-dirty-detection.bats" --> verify-dirty-detection の bats テストが green (案 B 採用時: 新規ケース追加)
- <!-- verify: rubric "選択した実装案 (A: heartbeat 内 commit/push、B: verify dirty check 特例) が決定されており、関連ドキュメント (skill SKILL.md または scripts コメント) に方針が記述されている" --> 採用案が決定され記述されている

### Post-merge

- 次回 `/auto --batch` 実行時に heartbeat による dirty state が verify を block しないことを観察 <!-- verify-type: observation event=auto-run -->

## Notes

### Auto-Resolve Log (non-interactive モード)

**案 A vs 案 B の選択 (auto-resolved)**
- **決定**: 案 B 採用 — `check-verify-dirty.sh` に built-in 免除パターンを追加する
- **理由**: heartbeat script の best-effort 設計を変えない; main ブランチ履歴が commit で膨らまない; push race リスクを増やさない; 既存の `verify-ignore-paths` 機構と整合する実装パターン
- **案 A を却下した理由**: best-effort スクリプトに commit/push を追加すると、フェーズ完了ごとに commit が走り commit 履歴が膨らむ; `git push` の race condition リスクが増加する

### 実装詳細

- `_is_ignored()` 関数はすでに `case "$file" in $pat)` bash glob マッチを使用しているため、`docs/sessions/_daily/loop-state-*.md` パターンはそのまま機能する
- 警告メッセージは "excluded by verify-ignore-paths" のまま変更しない。既存の `verify-dirty-detection.bats` の行 95・121 が `[[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]` でアサートしており、メッセージ変更による既存テスト修正コストを避ける
- 新規テストケース `"loop-state heartbeat only dirty: exit 0 (built-in exempt)"` も `[[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]` でアサートする (built-in パターンも同一配列経由のため同一メッセージが出力される)

## Consumed Comments

- saito (MEMBER / first-class) — 2026-06-28T03:56:24Z: Issue Retrospective 記録: AC2 分割 (append-loop-state-heartbeat.bats と verify-dirty-detection.bats を明示) および Post-merge AC の verify-type を `observation event=auto-run` に修正
  URL: https://github.com/saitoco/wholework/issues/798#issuecomment-4824704355

## Code Retrospective

### Deviations from Design

- None. 実装ステップは Spec の通りに実行した。`verify-ignore-paths` ロードブロックの直後に built-in 免除パターンを追加し、テストケースも Spec 通りの 2 件を追加した。

### Design Gaps/Ambiguities

- 警告メッセージが built-in パターン経由でも "excluded by verify-ignore-paths" と表示されることは Spec Notes に明記されていたため問題なし。`_is_ignored()` 関数が `ignore_patterns` 配列を共通で使うため、built-in パターンと user-config パターンで同一メッセージが出力される設計は既存の期待に合致していた。

### Rework

- None. 1 回目のコミットで実装が完了し、全 12 テスト PASS。リワークは発生しなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 案 B (verify 側 dirty check 特例) を採用。Case A は commit 履歴肥大・push race リスクがあり採用しない。
- `ignore_patterns` 配列への追加方式を選択。`_is_ignored()` 関数のシグネチャを変えず、既存 user-config パターンと同一の判定ロジックを共有する。
- 警告メッセージは変更しない ("excluded by verify-ignore-paths" のまま)。既存テスト行 95・121 のアサートが同文字列を期待しており、変更コストを避ける。

### Deferred Items
- Post-merge: 次回 `/auto --batch` 実行時に heartbeat dirty state が verify を block しないことを観察 (verify-type: observation event=auto-run)。

### Notes for Next Phase
- `/review` では `scripts/check-verify-dirty.sh` の変更点 (built-in 免除パターン追加) と `tests/verify-dirty-detection.bats` の新規テストケース 2 件を重点的に確認すること。
- 案 A を採用しなかった理由が Script コメントおよび Spec Notes に記録されている。
- Post-merge AC は `observation event=auto-run` なので verify フェーズでは SKIPPED 扱い。
