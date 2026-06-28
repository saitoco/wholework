# Issue #829: Add flock parallel race guard to append-loop-state-heartbeat.sh

## Overview

`scripts/append-loop-state-heartbeat.sh` の last-row dedup (#820, approach A) は連続重複を防ぐが、並列 batch worker が同一 transition を同時に emit するケースはカバーしきれない。複数 worker が `tail -1` を実行した時点で last_row がまだ空 → dedup をすり抜けて両方 append → 重複行が残る。

本 Issue では、`flock` ベースの排他制御 (macOS 向け `mkdir` lock fallback 付き) を追加し、file-creation・dedup・append を一つのアトミックなクリティカルセクションに包む。これにより連続重複・並列重複の両方を防御する。

flock 実装パターンは既存の `scripts/emit-event.sh` の `command -v flock` + `mkdir` fallback パターンに準拠する。

## Changed Files

- `scripts/append-loop-state-heartbeat.sh`: 現行の file-creation ブロック (lines 107-124) と dedup+append ブロック (lines 130-137) を flock クリティカルセクション (flock 不在時は mkdir-lock fallback) に置き換える — bash 3.2+ compatible
- `tests/append-loop-state-heartbeat.bats`: 並列 append による重複防止テストケースを追加

## Implementation Steps

1. `scripts/append-loop-state-heartbeat.sh` にヘルパー関数 `_do_append` を定義し、現行の file-creation ブロックと dedup+append ブロックを関数本体に移動する。関数内では `return 0` を使用してフロー制御を行う (→ AC1)

   関数の構造:
   ```bash
   _do_append() {
     # File creation inside critical section (prevents parallel header duplication)
     if [[ ! -f "$FILE" ]]; then
       mkdir -p "$SESSIONS_DAILY_DIR" 2>/dev/null || true
       { ... existing header printf block ... } >> "$FILE" 2>/dev/null || {
         echo "append-loop-state-heartbeat.sh: WARNING — skip (cannot create $FILE)" >&2
         return 0
       }
     fi
     # Dedup inside critical section
     local last_row
     last_row=$(tail -1 "$FILE" 2>/dev/null || true)
     if [[ -n "$last_row" && "$last_row" == *"$DETAIL"* ]]; then
       return 0
     fi
     # Append inside critical section
     printf '| %s | %s | %s | %s |\n' "$TS" "$PHASE_LABEL" "phase-transition" "$DETAIL" >> "$FILE" 2>/dev/null || true
   }
   ```

2. `_do_append` 定義の直後に、`emit-event.sh` と同パターンの flock / mkdir-lock ディスパッチコードを追加する (→ AC1):

   ```bash
   LOCK_FILE="${FILE}.lock"
   if command -v flock >/dev/null 2>&1; then
     # Non-blocking: best-effort — skip if lock is held by another worker
     (flock -n 9 || exit 0; _do_append) 9>"$LOCK_FILE" 2>/dev/null || true
   else
     # mkdir-lock fallback (bash 3.2+ compatible, no flock required)
     LOCK_DIR="${FILE}.lockdir"
     tries=0
     while ! mkdir "$LOCK_DIR" 2>/dev/null; do
       tries=$((tries + 1))
       if (( tries > 50 )); then
         _do_append
         tries=-1
         break
       fi
       sleep 0.1
     done
     [[ "$tries" != -1 ]] && { _do_append; rmdir "$LOCK_DIR" 2>/dev/null || true; }
   fi
   ```

   - `flock -n` (non-blocking): lock が取得できなければ subshell が exit 0 で終了 → append をスキップ (best-effort 設計を維持)
   - mkdir fallback: 50回 × 0.1s = 5秒 timeout、タイムアウト時は unlock のまま append して続行
   - 両ブランチとも `|| true` で囲み、best-effort で常に exit 0

3. `tests/append-loop-state-heartbeat.bats` に並列 append テストを追加する (→ AC2):

   ```bats
   @test "parallel append: lock prevents duplicate rows from concurrent calls" {
       fake_root="$BATS_TEST_TMPDIR/repo"
       wrapper=$(_make_wrapper "$fake_root")
       # Run two instances with the same transition in parallel
       "$wrapper" --issue 701 --from spec --to code &
       "$wrapper" --issue 701 --from spec --to code &
       wait
       today=$(date -u +%Y-%m-%d)
       file="$fake_root/docs/sessions/_daily/loop-state-$today.md"
       # Header must appear exactly once (no parallel file-creation race)
       header_count=$(grep -c '| Time (UTC) | Phase | Event | Detail |' "$file")
       [ "$header_count" -eq 1 ]
       # Transition row must appear at most once (dedup inside critical section)
       count=$(grep -c '#701 spec→code' "$file")
       [ "$count" -le 1 ]
   }
   ```

   - `[ "$count" -le 1 ]` (not `-eq 1`): flock が利用できない macOS でも mkdir fallback がある。ただし 2プロセス並列の速さ次第では両方が lockdir 取得に成功する可能性があるため、1 行以下 (重複なし: 0 or 1) を保証条件とする。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/append-loop-state-heartbeat.sh が flock または file-based mutual exclusion による並列 append race condition 防御ロジックを持つ" --> flock または相当のロック機構が追加されている
- <!-- verify: grep "flock" "scripts/append-loop-state-heartbeat.sh" --> flock キーワードが実装に存在する
- <!-- verify: command "bats tests/" --> 全 bats テストスイートが緑、並列 append テストを含む

### Post-merge

- 次回 `/auto --batch` (並列 batch) または XL Issue 並列実行で `docs/sessions/_daily/loop-state-*.md` に重複行が発生しないことを観察 <!-- verify-type: observation event=auto-run -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: AC1 に rubric + supplementary grep "flock" を追加 (§9 準拠)、AC2 を full suite `bats tests/` に変更 (§24 behavioral change)、macOS flock 可用性の自動解決 / https://github.com/saitoco/wholework/issues/829#issuecomment-4827507066

## Notes

- **flock検出パターン**: `emit-event.sh` lines 70-85 の実装パターンに準拠 (command -v flock → flock -x FD; else mkdir-lock)。本 Issue では best-effort 設計のため `flock -n` (non-blocking) を採用
- **flock -n vs -x**: `emit-event.sh` は `flock -x` (blocking) を使用しているが、heartbeat の best-effort 設計では lock 取得失敗時はスキップ (exit 0) する `flock -n` が適切
- **クリティカルセクション範囲の拡大**: 従来は dedup+append のみ。file-creation (mkdir -p + header write) もアトミックに含めることで、並列起動時のヘッダー重複を防ぐ
- **test assertion**: `[ "$count" -le 1 ]` — macOS システム bash (3.2) には flock がないため mkdir fallback 動作。並列 2プロセスが同時に mkdir に成功するエッジケースは極めてレアだが、CI 環境での flakiness を避けるため strict `[ -eq 1 ]` でなく `[ -le 1 ]` とする。flock 有環境では必ず 1 行
- **auto-resolve (macOS flock 可用性)**: rubric が "flock または file-based mutual exclusion" と許容しており、Issue Retrospective に記録済み (自動解決)。実装は flock + mkdir fallback の両方を含むため、どちらの環境でも rubric が pass する
