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

## review retrospective

### Spec vs. 実装の乖離パターン

- `skills/audit/SKILL.md` の「Session Boundary Identification」セクションが PR の変更ファイルに含まれておらず、古い `.tmp/auto-session-current` 参照が残留した。PR の変更ファイルが変更元 (Session ID 生成ロジック) に特化していたため、参照先ドキュメント (`audit/SKILL.md`) が Spec の "Changed Files" リストから漏れた典型パターン。対策: Issue #770 のような shared state 置換 Issue では、参照元だけでなく参照先ドキュメントも Spec の "Changed Files" に明示すること。

### 繰り返し所見

- 特になし。`skills/audit/SKILL.md` への参照漏れは今回固有の事例で、パターンとしての繰り返しではない。

### 受け入れ基準検証の難しさ

- `rubric` 条件 2 件はいずれも PASS で、verify command の精度に問題なし。AC2 の `file_not_contains` は明確で検証容易。UNCERTAIN なし。
- Post-merge 条件 (2 つの `/auto --batch` 同時起動での観察) は手動検証が必要で自動化が難しいが、現状の verify command 種別 (`manual`) が適切に設定されている。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI 失敗 (bats tests) は main ブランチで pre-existing の既存不具合と確認済み。non-interactive auto-resolve でマージ続行
- PR #793 は `worktree-code+issue-770` ブランチのスカッシュマージで main に着地
- ローカルブランチ削除エラー (code+issue-770 worktree による競合) は無視 — リモートブランチは正常削除済み

### Deferred Items
- `tests/auto-sub-observability.bats` に wrong-PGID decoy テストの追加 (CONSIDER)
- `.tmp/auto-session-${PGID}` ファイルの session 終了時クリーンアップ (CONSIDER)
- `append-loop-state-heartbeat.bats` tests 11-15 の既存不具合修正 (別 Issue で対応)

### Notes for Next Phase
- Post-merge verify: 2 つの `/auto --batch` を同時起動し、各 session の `/audit auto-session --full` report にクロスセッション混入がないことを手動確認すること
- issue #770 は `closes #770` により main へのマージで自動クローズ済み
- verify コマンド (file_not_contains, rubric ×2) はいずれも review フェーズで PASS 確認済み

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background が 2 つの session report (#22753, #98315) の Limits and gaps 両者から具体的に引用、根本原因 (shared mutable pointer) と修正候補 3 案を提示しており、spec 設計の幅を狭めずに方向性を絞れていた。

#### spec
- 修正対象として全 run-*.sh を網羅対象に含めた判断: M/L Issue の直接 Bash tool 呼び出し経路でも sub-script が pointer file を読む点を捕捉。1 ファイル修正に閉じずに source code 全体の影響範囲を解析した spec 品質。
- AC2 の verify command BRE metacharacter fix を Consumed Comments で記録 (saito MEMBER comment) — issue retrospective から spec への流入経路が正常に機能した事例。

#### code
- Watchdog timeout (1800s) で /code session が JSON モード silent run のまま kill された (exit 143)。Tier 3 recovery sub-agent が起動し、worktree の uncommitted work を commit/push/PR create することで recover に成功。**Auto Retrospective 未記載** (recovery が Spec 側に反映される機構が #770 では trigger されなかった)。

#### review
- `skills/audit/SKILL.md` の Session Boundary Identification セクションが PR 変更ファイルに含まれず古い `.tmp/auto-session-current` 参照が残留 → review で指摘・修正。**Spec の "Changed Files" リスト網羅性問題の再発** (#771 の test path 同期問題と同根)。

#### merge
- pre-existing CI failure (bats tests, 同じ append-loop-state-heartbeat.bats) を non-interactive auto-resolve で continue。本 batch session で #787 として既起票済み、follow-up 予定。

#### verify
- pre-merge AC 3 件 PASS、post-merge AC は parallel session 起動が本 verify session 内で不可能のため SKIP (Issue は phase/verify に留まり次回実 batch 並行運用で観察)。
- **Tier 3 recovery が Spec の `## Auto Retrospective` に未記載**だった点を verify retrospective で補完記録。Tier 3 sub-agent の Outcome は success (Recovery Applied: action=recover, steps: 3)、root cause は 1800s watchdog timeout in JSON mode silent run。

### Improvement Proposals

1. **Tier 3 recovery 後の Auto Retrospective 自動追記**: 現状、run-auto-sub.sh の Tier 2 (`apply-fallback.sh` 成功時) は `_write_tier2_recovery_to_spec()` で sub-issue Spec に Auto Retrospective を自動追記するが、**Tier 3 (recovery sub-agent) 成功時は同等の Spec write が走らない**。`spawn-recovery-subagent.sh` が orchestration-recoveries.md にのみ write、Spec 側は更新せず。`/verify` Step 12 の "Tier 2/3 automatic recovery handling" が Spec の Auto Retrospective を SSoT とする想定だが、Tier 3 は SSoT への流入経路がない。Tier 3 でも sub-issue Spec の Auto Retrospective に追記する仕組みの実装が candidate。
2. **Changed Files リスト網羅性問題の再発 (#771 と同根)**: `skills/audit/SKILL.md` の参照が "Changed Files" から漏れた点は #771 の test 同期漏れと同種パターン。"参照元 (実装ロジック) を変更したら参照先 (SKILL.md / 関連 docs / test) も同期する" を機械的にチェックする仕組み — 例えば file_not_contains AC を symbolic naming (variable name / file path) で自動拡散する Spec template ガイダンス — の検討候補。本 batch session で #778 (verify command 対称性) として既起票の論点を更に拡張する位置づけ。
3. **JSON モード watchdog timeout の検出強化**: #770 code-pr は 1800s silent run の間 Claude Code が実作業中だったが watchdog が kill。同様パターンが今後も発生する可能性。JSON mode silent run の watchdog 延長 (e.g., 1800s → 3600s) や進捗 heartbeat (1 commit / N min 等) の検出による reset 機構が candidate。本 batch session で複数 Tier 3 recovery が観察される場合 `/audit recoveries` の自動 fire (`recoveries-auto-fire`) が trigger される想定だが、watchdog kill 特化の予防策として別軸で考慮。
