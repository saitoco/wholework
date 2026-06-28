# Issue #831: recovery-change-detection-fix

## Overview

`scripts/run-auto-sub.sh` の 3 recovery 関数 (`_write_manual_recovery_to_spec`, `_write_tier2_recovery_to_spec`, `_write_tier3_recovery_to_spec`) が `git diff --quiet <spec_rel_path>` で変更検知を行っている。`git diff --quiet` は untracked ファイル (新規ファイル) を検出できないため、初回 Spec 作成時に commit がスキップされる silent failure が発生する。共通ヘルパー関数 `_spec_has_changes()` を導入して `git status --porcelain` ベースに統一する。

## Reproduction Steps

1. recovery が発生する Issue で Spec がまだ存在しない状態 (untracked) で各 recovery 関数が呼ばれる
2. `git diff --quiet <spec_rel_path>` は untracked ファイルに対して exit 0 を返す (差分なしと判定)
3. commit ブロックがスキップされ、Auto Retrospective が Spec に書き込まれたまま push されない

## Root Cause

`git diff --quiet <path>` は staged または modified (tracked) ファイルの変更のみを検出し、untracked (new) ファイルについては何も出力せず exit 0 を返す。`git status --porcelain <path>` は untracked ファイルも `?? path` 形式で出力するため、これを使って変更を検出する。

## Changed Files

- `scripts/run-auto-sub.sh`: `_spec_has_changes()` ヘルパーを追加; lines 46, 196, 243 の `git diff --quiet` 呼び出しをヘルパー呼び出しに置換 — bash 3.2+ compatible
- `tests/run-auto-sub.bats`: 3 関数それぞれについて untracked Spec ファイルで commit が走るテストを追加

## Implementation Steps

1. `scripts/run-auto-sub.sh`: `_write_manual_recovery_to_spec()` 定義 (line 12) の直前に `_spec_has_changes()` ヘルパーを追加する。実装: `git -C "$repo_root" status --porcelain "$spec_rel_path" 2>/dev/null | grep -q .` — untracked (`?? ...`) と modified (`M  ...`) 両方を検出する (→ AC1)

2. `scripts/run-auto-sub.sh`: 以下の 3 箇所の変更検知条件を置換する (→ AC1):
   - line 46: `if ! git -C "$_repo_root" diff --quiet "$spec_rel_path" 2>/dev/null; then` → `if _spec_has_changes "$_repo_root" "$spec_rel_path"; then`
   - line 196: 同上
   - line 243: 同上

3. `tests/run-auto-sub.bats`: 以下の 3 テストを追加する。各テストで Spec ファイルを作成せず (untracked 状態)、`git status --porcelain` が non-empty を返すようにモックし、commit が呼ばれることを assert する (→ AC2):
   - `@test "run-auto-sub: tier2 recovery: commits when spec file is untracked"`
   - `@test "run-auto-sub: tier3 recovery: commits when spec file is untracked"`
   - `@test "run-auto-sub: manual recovery: commits when spec file is untracked"`

## Verification

### Pre-merge

- `scripts/run-auto-sub.sh` で 3 関数の変更検知が `git status --porcelain` ベースに統一され、untracked Spec ファイルでも commit が走る <!-- verify: rubric "scripts/run-auto-sub.sh の _write_tier2_recovery_to_spec / _write_tier3_recovery_to_spec / _write_manual_recovery_to_spec で git diff --quiet が削除され、git status --porcelain ベースの変更検知に統一されている、または共通ヘルパー関数経由になっている" --> <!-- verify: grep "status --porcelain.*spec_rel_path" "scripts/run-auto-sub.sh" -->
- `tests/run-auto-sub.bats` で untracked Spec ファイル → commit 動作が assert されている <!-- verify: github_check "gh pr checks" "Run bats tests" --> <!-- verify: grep "untracked" "tests/run-auto-sub.bats" -->

### Post-merge

- 次回 recovery 発生時に初回 Spec 作成 (untracked) ケースで commit が漏れないことを観察

## Notes

- `orchestration-recoveries.md` への `git diff --quiet` (lines 298, 486) はスコープ外: これらは常に tracked ファイルへの書き込みなので untracked 問題は発生しない。Issue retrospective の Auto-Resolved により確認済み
- `_spec_has_changes()` の引数名を `spec_rel_path` とすること: AC1 の verify command `grep "status --porcelain.*spec_rel_path"` がこのパラメータ名に依存する
- bats テストの git モック戦略: `status --porcelain <spec-path>` に対して non-empty 出力を返し、`diff --quiet` は exit 0 (従来の no-op) を返すことで、新ロジックのみが commit を発動することを確認する

## Consumed Comments

- **saito** (MEMBER, first-class) — bats verify command 形式の修正・rubric 補足 verify 追加・bats test AC 補足 grep 追加の Auto-Resolve Log: https://github.com/saitoco/wholework/issues/831#issuecomment-4827005414

## Code Retrospective

### Deviations from Design

- 既存の 3 テスト (tier2/tier3/manual recovery) の git mock を更新する必要があった。Spec の実装計画には新 3 テストの追加のみ記載されていたが、既存テストも `git diff --quiet` 前提の mock だったため、`git status --porcelain` を返すよう合わせて更新した。これは実装の自然な副作用であり、スコープ変更ではなくテスト整合性の維持。

### Design Gaps/Ambiguities

- `_spec_has_changes()` の引数名 `spec_rel_path` は AC verify command の grep パターンに依存するため Spec Notes に明記されており、実装に迷いはなかった。ただし、Notes がなければ引数名が異なった可能性があるため、verify command と実装の結合度の高さは将来の rename 時に注意が必要。

### Rework

- 既存 tier2/tier3/manual recovery テストの git mock を最初の commit では更新しなかったため、全テスト実行 (bats tests/) で tests 26-28 が FAIL した。2 回目の edit で修正した。新テスト追加時は既存テストへの影響を同時に確認すべきだった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `_spec_has_changes()` を `set -euo pipefail` 直後に配置し、`_write_manual_recovery_to_spec()` の直前に置いた。スコープ的に最も近い位置であり、script の早期定義として読みやすい。
- `git status --porcelain "$spec_rel_path"` の出力を `grep -q .` で non-empty 判定する方式を選択。`wc -l` や変数展開より簡潔で bash 3.2+ 互換。
- 既存テストの git mock を `status --porcelain` 対応に更新した。これにより `git diff --quiet` の旧モックが残らず、テストが新ロジックのみを検証することが確認できる。

### Deferred Items
- `orchestration-recoveries.md` の `git diff --quiet` (lines 298, 486) はスコープ外のまま。これらは常に tracked ファイルへの書き込みなので問題なし。
- AC2 の `github_check "gh pr checks" "Run bats tests"` は CI 実行後に確認。ローカル bats 全 1031 件 PASS 済み。

### Notes for Next Phase
- PR #838 で CI が通ることを `/verify` 前に確認すること。`Run bats tests` ジョブが最重要。
- `_spec_has_changes()` は bash script の先頭部 (line 9-15) に定義済み。`/review` はこの位置を確認してコメント位置の適切性を評価してよい。
- Spec Notes の verify command と実装の結合度についてはレビューコメント不要 (設計上の意図的な依存)。
