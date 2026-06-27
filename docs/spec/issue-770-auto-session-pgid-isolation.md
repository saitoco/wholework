# Issue #770: auto: resolve session_id pointer race condition in parallel sessions

## Overview

`/auto` が parallel で実行される環境で、`.tmp/auto-session-current` という共有ポインタファイルを通じて session_id が汚染される race condition を修正する。後発 session がポインタファイルを上書きすると、先発 session の sub-process (run-code.sh, run-review.sh, run-merge.sh, run-auto-sub.sh) が誤った session_id でイベントを記録し、`/audit auto-session` レポートにクロスセッション混入が発生する。

PGID (process group ID) ベースのポインタファイル名 `.tmp/auto-session-${PGID}` に変更することで、parallel session 間のファイル衝突を防ぐ。

## Reproduction Steps

1. 2 つのターミナルセッションで同時に `/auto --batch N` を実行する
2. 後発セッションが先発セッションの `.tmp/auto-session-current` を上書きする
3. 先発セッションの後続 run-code.sh が後発セッションの session_id でイベントを記録する
4. `/audit auto-session --full` で先発セッションのレポートに後発セッションの Issue が混入する

## Root Cause

`skills/auto/SKILL.md` Step 1 が `SESSION_ID="$$-$(date +%s)"` を生成し `.tmp/auto-session-current` に書き込む。後続の `run-auto-sub.sh`/`run-code.sh`/`run-review.sh`/`run-merge.sh` は `${AUTO_SESSION_ID:-$(cat .tmp/auto-session-current)}` パターンでこのファイルを読む。parallel session が起動すると後発 session が同一ファイルを上書きし、先発 session の sub-process が誤った session_id を取得する。

Fix: ポインタファイル名に PGID を含めることで、同一 Claude Code セッション内の全 Bash tool 呼び出しが同じ PGID を持つという性質を利用し、parallel session 間のファイル衝突を防ぐ。

## Changed Files

- `skills/auto/SKILL.md`: Step 1 の pointer file 書き込みを `.tmp/auto-session-current` → `.tmp/auto-session-${PGID}` (PGID 取得: `ps -o pgid= -p $$ | tr -d ' '`) に変更 + session boundary isolation の設計文書をコメントとして追加 — bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: L43 の pointer file 読み込みを PGID ベースに変更 — bash 3.2+ 互換
- `scripts/run-code.sh`: L50 の pointer file 読み込みを PGID ベースに変更 — bash 3.2+ 互換
- `scripts/run-review.sh`: L19 の pointer file 読み込みを PGID ベースに変更 — bash 3.2+ 互換
- `scripts/run-merge.sh`: L17 の pointer file 読み込みを PGID ベースに変更 — bash 3.2+ 互換
- `tests/auto-sub-observability.bats`: PGID ベース session isolation を検証する bats test 追加

## Implementation Steps

1. `skills/auto/SKILL.md` Step 1 を変更: `printf '%s\n' "$SESSION_ID" > .tmp/auto-session-current` の前に `PGID=$(ps -o pgid= -p $$ | tr -d ' ')` を追加し、書き込み先を `.tmp/auto-session-${PGID}` に変更。直後にインラインコメントとして session boundary isolation の設計説明 (PGID ベースにより parallel session がそれぞれ独立したポインタを持つことを記述) を追加する (→ AC1, AC3)

2. `scripts/run-auto-sub.sh` L43 を変更: `cat .tmp/auto-session-current` を次のように置換する。直前行に `PGID=$(ps -o pgid= -p $$ | tr -d ' ')` を追加し、L43 を `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat .tmp/auto-session-${PGID} 2>/dev/null || echo '')}"` に変更する (→ AC1, AC2)

3. `scripts/run-code.sh` L50 を同様に変更: 直前行に `PGID=$(ps -o pgid= -p $$ | tr -d ' ')` を追加し、L50 を `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat .tmp/auto-session-${PGID} 2>/dev/null || echo '')}"` に変更する (→ AC1)

4. `scripts/run-review.sh` L19 および `scripts/run-merge.sh` L17 を Step 3 と同様に変更する (→ AC1)

5. `tests/auto-sub-observability.bats` に新規テスト `@test "session-isolation: PGID-specific pointer file is read when AUTO_SESSION_ID is unset"` を追加する。テスト内容: (a) PGID=$(ps -o pgid= -p $$ | tr -d ' ') を取得、(b) `.tmp/auto-session-${PGID}` に test-session-pgid を書き込む、(c) `unset AUTO_SESSION_ID` して run-auto-sub.sh を実行、(d) emit された session_id が test-session-pgid であることを確認する (→ AC1 validation)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/lib/auto-session.sh または skills/auto/SKILL.md で session_id pointer の session-local 化 (e.g., PGID 付きファイル名) または event 側 session_pid 併記の仕組みが導入されている" --> session boundary isolation の仕組み導入
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "auto-session-current" --> run-auto-sub.sh から共有ポインタ `.tmp/auto-session-current` への直接参照が削除されている
- <!-- verify: rubric "skills/auto/SKILL.md または同等 SSoT に session boundary isolation の設計 (なぜ pointer を session-local にするか、parallel session でどう振る舞うか) が文書化されている" --> 設計理由が SKILL.md に明文化されている

### Post-merge

- 2 つの `/auto --batch` を同時起動し、各 session の `/audit auto-session --full` report が他 session の Issue を含まないことを観察

## Notes

- `run-auto-sub.sh` は子プロセスとして run-code.sh, run-review.sh, run-merge.sh を呼び出す。`run-auto-sub.sh` が `AUTO_SESSION_ID` を `export` するため、XL サブ Issue 経路では子プロセスが PGID ファイルを読む機会はないが、M/L Issue の直接 Bash tool 呼び出し経路 (スキル SKILL.md から直接) では run-code.sh 等がポインタファイルを読む必要があるため、すべての run-*.sh を修正する。
- PGID 取得コマンド `ps -o pgid= -p $$ | tr -d ' '` は macOS (bash 3.2) および Linux の両方で動作する。
- Consumed Comments: saito (MEMBER) 2026-06-27T14:56:52Z — AC2 の verify command を BRE metacharacter (`\|`) を含む `grep` から `file_not_contains "scripts/run-auto-sub.sh" "auto-session-current"` に変更する自動解決ログ。この変更は Issue body の AC2 に既に反映済み。
