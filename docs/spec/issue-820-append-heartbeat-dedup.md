# Issue #820: scripts: append-loop-state-heartbeat.sh の同 transition 重複行を抑制

## Overview

`scripts/append-loop-state-heartbeat.sh` が `docs/sessions/_daily/loop-state-{DATE}.md` に append する際、同一 (issue, from→to, snapshot) の行が重複して記録される。retry-on-kill によるリトライや並列 batch worker の同時 append が原因として推測される。本 Issue では append 前に直前行と比較して同一 transition の連続記録を抑制する (dedup) ロジックを追加する。

## Reproduction Steps

1. 並列 batch 実行 (`/auto --batch`) 中に `run_phase_with_recovery` のリトライが発生、または同じ transition を同タイミングで emit する複数の worker が存在する
2. `append-loop-state-heartbeat.sh` が同一引数 (`--issue N --from X --to Y`) で 2 回以上呼ばれる
3. `docs/sessions/_daily/loop-state-{DATE}.md` に同一の `#N X→Y snapshot:[...]` 行が 2 行以上記録される

## Root Cause

`scripts/append-loop-state-heartbeat.sh` の DETAIL 変数代入直後 (`printf '| %s | %s | %s | %s |\n'` 行) は、ファイル末尾の直前行チェックなしで無条件 append する。同じ DETAIL 文字列 (`#${ISSUE} ${FROM}→${TO} snapshot:[${SNAPSHOT}]`) を持つ呼び出しが連続した場合に重複行が生じる。

## Changed Files

- `scripts/append-loop-state-heartbeat.sh`: DETAIL 文字列構築直後、`printf` append 前に dedup チェックを追加 — bash 3.2+ compatible
- `tests/append-loop-state-heartbeat.bats`: dedup 動作を確認するテストケースを追加 (AC2 は既存テストが緑でも合格だが品質向上のため追加)

## Implementation Steps

1. `scripts/append-loop-state-heartbeat.sh` の DETAIL 変数代入行 (`DETAIL="#${ISSUE} ${FROM}→${TO} snapshot:[${SNAPSHOT}]"`) の直後、`printf '| %s | %s | %s | %s |\n'` 行の直前に dedup チェックを挿入 (→ AC1):
   ```bash
   # Dedup: skip if last row already contains this transition (best-effort)
   if [[ -f "$FILE" ]]; then
     LAST_ROW=$(tail -1 "$FILE" 2>/dev/null || true)
     if [[ -n "$LAST_ROW" && "$LAST_ROW" == *"$DETAIL"* ]]; then
       exit 0
     fi
   fi
   ```
   - ファイルが存在しない場合や `tail` が失敗した場合は通常の append にフォールバック (best-effort)
   - timestamp は dedup 判定に使用しない (issue, from→to, snapshot が同じであることが冪等性の基準)
   - `[[ == *"$DETAIL"* ]]` は bash 3.2+ で動作するパターンマッチ

2. `tests/append-loop-state-heartbeat.bats` に dedup テストケースを追加 (→ AC2):
   ```bash
   @test "duplicate transition: skips append when last row matches" {
       fake_root="$BATS_TEST_TMPDIR/repo"
       wrapper=$(_make_wrapper "$fake_root")
       "$wrapper" --issue 701 --from spec --to code
       "$wrapper" --issue 701 --from spec --to code  # 同一引数 → dedup される
       today=$(date -u +%Y-%m-%d)
       file="$fake_root/docs/sessions/_daily/loop-state-$today.md"
       count=$(grep -c '#701 spec→code' "$file")
       [ "$count" -eq 1 ]
   }
   ```
   - 既存テストとのリグレッションを防ぐため `bats tests/append-loop-state-heartbeat.bats` でフルスイートを実行して確認する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/append-loop-state-heartbeat.sh が同一 (issue, from→to, snapshot) の直前行と一致する場合に append を skip するロジックを持つ、もしくは flock 等で並列 append の race condition を防ぐロジックを持つ" --> append dedup ロジックが追加されている
- <!-- verify: command "bats tests/append-loop-state-heartbeat.bats" --> 既存 bats テストが緑、または dedup の新規ケースが追加されて緑

### Post-merge

- 次回 `/auto --batch` 実行時に `docs/sessions/_daily/loop-state-*.md` に同 transition の重複行が出現しないことを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- dedup は直前行のみと比較する (last-row dedup)。実際の重複パターンは連続する同一行 (例: 同タイムスタンプの 2 行) であるため `tail -1` のみで十分。ファイル全行のスキャンは不要。
- approach A (tail dedup) を採用。approach B (flock) は並列 race condition を防ぐが、実装がシンプルで既存の best-effort 設計と一貫する approach A で AC の「もしくは」(OR) 条件を満たす。Issue コメントの Auto-Resolve Log (Auto-Resolved Ambiguity #1) に記録済み。
- bats テスト追加は AC2 上は任意 ("既存テストが緑" でも合格) だが、dedup ロジックのリグレッション防止のため追加する。Issue コメントの Auto-Resolved Ambiguity #2 に記録済み。

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (Auto-Resolve Log: approach A/B OR 接続の確認、bats テスト追加が任意であることの確認) / https://github.com/saitoco/wholework/issues/820#issuecomment-4826400420

## Code Retrospective

### Deviations from Design
- None — Spec の実装ステップと完全に一致。dedup チェックは DETAIL 変数代入直後、printf append 直前に挿入した。

### Design Gaps/Ambiguities
- snapshot が異なる場合 (同 issue・同 transition だが snapshot 変化) はデュープとして検出されない。Spec Notes で "直前行のみ比較" と明記されており設計上の意図 — 連続する完全一致行のみが重複対象。

### Rework
- None — 初回実装でテスト 10/10 all pass。

## review retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. 実装は Spec の実装ステップと完全に一致している。dedup ロジックの挿入位置 (DETAIL 変数代入直後、printf 直前) も Spec 通り。

### Recurring Issues

Nothing to note. 4 観点レビューで MUST/SHOULD/CONSIDER いずれの課題も検出されず。

### Acceptance Criteria Verification Difficulty

Nothing to note. AC1 (rubric) はスクリプト本体の読み取りで確認。AC2 (bats) は CI reference fallback (CI job "Run bats tests" SUCCESS) で PASS 判定。UNCERTAIN 0 件。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- `mergeable=true`, CI SUCCESS, approved のため競合解決不要でスカッシュマージを直接実行。
- `closes #820` が PR body に含まれ、base branch が `main` のため Issue は自動クローズされる。
- Phase Handoff を Spec に記録し、verify フェーズへ引き継ぐ。

### Deferred Items
- post-merge AC (observation event=auto-run): 次回 `/auto --batch` 実行後に `loop-state-*.md` の重複行を手動観察。
- flock による並列 race condition 対策は別 Issue で対応 (Spec Notes に記載済み)。

### Notes for Next Phase
- verify フェーズでは pre-merge AC (rubric + bats) の事後確認が主タスク。
- post-merge AC は observation 型のため verify コマンドでは自動検証不可 — 手動観察で判断。
- マージコミットは main に反映済み。worktree-code+issue-820 ブランチは削除済み。
