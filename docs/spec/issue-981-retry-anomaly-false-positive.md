# Issue #981: detect-wrapper-anomaly: retry 成功後ログの false-positive anomaly 検出を抑制

## Consumed Comments

No new comments since last phase.

## Overview

`run-auto-sub.sh` の exit-0 informational anomaly check (`detect-wrapper-anomaly.sh` 呼び出し) において、`code-completed-no-pr` パターンがログ全体から「最初の失敗の痕跡」だけを見て検出しており、後続の `code_retry_fire` 内部リトライが成功して PR が作成された場合でも false-positive で anomaly を出力してしまう。同一スクリプト内の兄弟パターン `review-completion-false-negative` に既に存在する「ログ内に後続の `matches_expected:true` があれば抑制する」という reconcile-first authority ガードを、`code-completed-no-pr` にも同様に適用する。

## Reproduction Steps

1. PR route (code-pr phase) の Issue で `/auto`（内部的には `run-auto-sub.sh`）を実行する。
2. `run-code.sh` 内の `claude -p` 呼び出しが watchdog kill もしくは silent no-op で終了し、`reconcile-phase-state.sh code-pr --check-completion` の結果 (`"matches_expected":false`, `"phase":"code-pr"`) が `run-code.sh` 293-294 行目の `echo "reconcile-phase-state result: $_reconcile_out"` で標準出力に書き出される。
3. `AUTO_RETRY_ENABLED=true` かつ tier 条件を満たすため `code_retry_fire` が発火し、`run-code.sh` が `exec` ベースで再実行される (`docs/tech.md` § code-side auto-retry)。再実行の出力は `run-auto-sub.sh` 452 行目が開いた同一の `$log_file` (`.tmp/wrapper-out-<issue>-code.log`) にそのまま追記され続けるため、1 回目 (失敗) と 2 回目 (成功) 両方の `reconcile-phase-state result:` 行が同じログファイルに残る。
4. 2 回目の試行が成功して PR (例: #978) が作成され、最終的に `run-code.sh` は exit code 0 で終了する。
5. `run-auto-sub.sh` の exit-0 informational check (524-533 行目付近) が `detect-wrapper-anomaly.sh --exit-code 0 --phase code-pr` をこのログに対して実行する。`code-completed-no-pr` の elif 条件 (`detect-wrapper-anomaly.sh` 69 行目) は `"matches_expected":false` と `"phase":"code-pr"` がログ内のどこかに存在するかだけを見るため、1 回目 (失敗) の痕跡にマッチし、PR が実際には作成済みにもかかわらず anomaly を誤検出する。

## Root Cause

`scripts/detect-wrapper-anomaly.sh` の `code-completed-no-pr` elif 条件 (69 行目) は、ログ全体に対する `grep -q` の AND 条件のみで構成されており、「その後に成功を示す `matches_expected:true` が同じログ内に存在するか」を見ていない。同一スクリプト内には既に同種のガード (reconcile-first authority) が 2 箇所存在する。

- `review-completion-false-negative` (89 行目): `! grep -q '"matches_expected":true' "$LOG_FILE"` を条件に追加済み。#547 で本パターンを導入した際は未実装で、#932 (review フェーズの類似 false-positive) の解消時にこのガードが追加された。`modules/orchestration-fallbacks.md` の `review-completion-false-negative` § Rationale に「Suppression on recovery (#932)」として記録されている。
- exit-0 ブロックの `silent-no-op` チェック (117 行目): `elif grep -q '"matches_expected":true' "$LOG_FILE"; then :` という reconcile-first authority で silent-no-op 判定自体をスキップする。

`code-completed-no-pr` (#415 で導入) だけがこのガードを持たないまま残っていたため、`code_retry_fire` のように **同一ログファイル内で reconcile チェックが複数回実行され、後続の呼び出しが `matches_expected:true` を返す** ケースを想定できていなかった。`run-code.sh` 293-294 行目の `echo "reconcile-phase-state result: $_reconcile_out"` は `exec` ベースの再実行のたびに実行されるため、リトライ成功時はログの後半に `"matches_expected":true` を含む行が残る。この事実に基づき、`code-completed-no-pr` にも同じ reconcile-first authority ガードを追加するのが根本解決となる。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: `code-completed-no-pr` elif 条件 (69 行目) に `&& ! grep -q '"matches_expected":true' "$LOG_FILE"` を追加し、`review-completion-false-negative` (89-90 行目) と同様の reconcile-first authority ガードを適用する。bash 3.2+ 互換 (既存の `grep -q` 拡張のみ、新規 bash4+ 構文なし)。[Steering Docs sync candidate: `docs/structure.md` / `docs/ja/structure.md` の Key Files 一覧にスクリプトの役割記述があるが、役割自体 ("detect known failure patterns...") は変わらないため更新不要と判断済み]
- `tests/detect-wrapper-anomaly.bats`: 既存テスト "code completed no PR: detects matches_expected false with phase code-pr" (285-293 行目) が変更後も従来通り PASS することを確認する (真の kill-only ケースの回帰確認)。加えて、ログ後半に `"matches_expected":true` が存在する場合に anomaly が抑制される新規テストを追加する ("review-completion-false-negative: suppressed when recheck recovers to matches_expected true" (438-444 行目) と同型)。
- `modules/orchestration-fallbacks.md`: `code-completed-no-pr` § Rationale (294-298 行目付近) に、`review-completion-false-negative` § Rationale の「Suppression on recovery (#932)」(267 行目) と同型の「Suppression on recovery (#981)」記述を追加する。

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `code-completed-no-pr` elif 条件 (69 行目) を変更する (→ 受入条件1)。

   変更前:
   ```bash
   elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"code-pr"' "$LOG_FILE"; then
     PATTERN_NAME="code-completed-no-pr"
   ```

   変更後:
   ```bash
   elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"code-pr"' "$LOG_FILE" && ! grep -q '"matches_expected":true' "$LOG_FILE"; then
     # reconcile-first authority: a later matches_expected:true in the same log (e.g. code_retry_fire retry success) suppresses this anomaly
     PATTERN_NAME="code-completed-no-pr"
   ```

2. (after 1) `tests/detect-wrapper-anomaly.bats` に新規テストを追加する (→ 受入条件2)。
   - 新規テスト名例: `"code completed no PR: suppressed when retry succeeds (later matches_expected true present)"`
   - フィクスチャ例 (1 回目失敗 + 2 回目成功の reconcile 出力を模したログ): `printf '"matches_expected":false\n"phase":"code-pr"\nretry-on-kill: command killed...\n"matches_expected":true\n"phase":"code-pr"\n' > "$LOG_FILE"`
   - 期待結果: `[ "$status" -eq 0 ]` かつ `[ -z "$output" ]` (anomaly が出力されない)
   - 既存テスト "code completed no PR: detects matches_expected false with phase code-pr" (285-293 行目、`matches_expected:true` を含まないフィクスチャ) が変更後も無修正で PASS することを確認する (真の no-retry / kill のみのケースの回帰確認)。

3. (parallel with 1, 2) `modules/orchestration-fallbacks.md` の `code-completed-no-pr` § Rationale に、`review-completion-false-negative` の「Suppression on recovery (#932)」箇条書き (267 行目) と同型の一文を追加する (→ SHOULD: ドキュメント整合性)。
   例: `- Suppression on recovery (#981): if the same log later contains a "matches_expected":true line for phase code-pr (e.g. after code_retry_fire's exec-based retry succeeds), the code-completed-no-pr condition is skipped entirely — the same reconcile-first-authority principle applied to review-completion-false-negative (#932), extended here to the code-pr phase`

## Verification

### Pre-merge
- <!-- verify: rubric "run-auto-sub.sh の exit-0 informational anomaly check (detect-wrapper-anomaly.sh 呼び出し) が、code_retry_fire によるリトライ成功後のログで初回試行の kill 痕跡から false-positive を出力しないよう、ログスキャン範囲の限定またはフェーズ完了根拠による抑制を実装している" --> リトライ成功後の false-positive anomaly 出力が抑制されている
- <!-- verify: rubric "tests/ 配下に、リトライ成功ログ (初回 kill 痕跡 + 完了根拠あり) で anomaly が出力されないこと、および真の silent no-op ログでは従来どおり anomaly が出力されることを検証するテストが存在する" --> 抑制の positive/negative 両ケースを検証するテストが追加されている

### Post-merge
- 次回 `/auto` で watchdog kill → retry 成功が発生した際、false-positive anomaly が出力されないことを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- SPEC_DEPTH=light (Size M → pr route 自動判定)。blocked-by なし (HAS_OPEN_BLOCKING=false)。
- Issue 本文は「run-auto-sub.sh の informational anomaly check、L482-487」と行番号を記載しているが、現行コード (このリポジトリの現在の main) では該当ロジックは 524-533 行目付近にある。挙動の記述自体 (exit-0 経路で `detect-wrapper-anomaly.sh` を呼ぶ) は現行実装と一致しており、単なる行番号ドリフト (Issue 起票後のファイル変更によるもの) と判断した。実装は行番号ではなく `if [[ $exit_code -eq 0 ]]` というコード文脈で特定する。
- 本 Issue の修正は、#547 (`review-completion-false-negative` パターン導入) → #932 (同パターンに reconcile-first authority ガードを追加、review フェーズの false-positive を解消。`modules/orchestration-fallbacks.md` に記録済み) と同一の技術 (ログ内の後続 `matches_expected:true` を検出したら抑制) を `code-completed-no-pr` (#415 で導入) に適用するもの。既存パターンとの一貫性を優先し、新規メカニズムは導入しない。
- 検証方法について: rubric の判定材料として、実装後の `scripts/detect-wrapper-anomaly.sh` の diff と `tests/detect-wrapper-anomaly.bats` の新規テスト実行結果を直接参照できるため、hard-pattern (grep/file_contains) の補助チェックは追加していない。`"matches_expected":true` という文字列自体は同ファイル内の他の 2 箇所 (89, 117 行目) に既存で出現するため、単純な file_contains では「正しい elif ブロックに追加されたか」を一意に検証できず、rubric による意味的検証の方が適切と判断した。

## Code Retrospective

### Deviations from Design
- Spec は Size M による pr route 自動判定を前提 (SPEC_DEPTH=light の由来) だったが、`/code 981 --patch --non-interactive` で `--patch` フラグが明示されたため、フラグ優先順位ルール (`ALWAYS_PR=false` かつ `--patch` 指定 → patch route) により patch route (main へ直接コミット) で実行した。実装内容・Verification 手順は route に依存しないため Spec の Implementation Steps 自体への影響はない。

### Design Gaps/Ambiguities
- N/A — Spec の Implementation Steps (elif 条件変更、bats テスト追加、orchestration-fallbacks.md 追記) は具体的なコード例まで示されており、実装中に曖昧な判断は発生しなかった。

### Rework
- N/A — Implementation Steps の記載順どおり一度で実装完了。bats 41件全PASS (新規テスト含む) を初回実行で確認。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `code-completed-no-pr` elif 条件に `&& ! grep -q '"matches_expected":true' "$LOG_FILE"` を追加し、`review-completion-false-negative` (#932) と同型の reconcile-first authority ガードを適用した。新規メカニズムは導入せず、既存パターンとの一貫性を優先。
- patch route (`--patch` フラグ明示) で実行したため main へ直接コミットし、`/review`/`/merge` はスキップして `phase/verify` へ直接遷移する。

### Deferred Items
- Post-merge AC (「次回 `/auto` で watchdog kill → retry 成功が発生した際、false-positive anomaly が出力されないことを観察」) は observation 型のため、実際の `/auto` 実行での再発時まで確認を保留。

### Notes for Next Phase
- `/verify` では pre-merge の 2 rubric 条件は本フェーズで PASS 判定済み (Issue チェックボックス更新済み)。post-merge の observation 項目は次回 watchdog kill → retry 成功シナリオの発生を待って確認する。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/auto --batch` の issue triage phase (`run-issue.sh 981`) が silent window 300 秒超の時点で外部停止 (kill) された。ただし triage の本質的出力 (`triaged`/`phase/issue` ラベル、Size M、AC + rubric 付きの body) は停止時点で設定済みだったため、親セッションが状態を確認のうえ後続フェーズへ続行した (Issue Retrospective コメントの投稿のみ未実施)。状態ベースの続行判断が機能した事例。

#### spec
- spec phase で Size M → S に降格され、patch route に再計画された。降格判定は正常に機能。

#### code
- 問題なし。patch route で main へ直コミット (930d773c)。

#### review / merge
- patch route のため対象外。

#### verify
- pre-merge 2 件 rubric PASS。抑制条件の実装は「同一ログ内の後続 `matches_expected:true` を完了根拠として抑制」方式。本 batch session 内の #987 code-pr phase で同 false-positive が実際に発生しており、修正の必要性が実例で裏付けられた。
- 【2回目 verify (2026-07-15)】Post-merge observation AC を PASS 確定。同一 batch session 内の Issue #1009 code-pr phase で `code_retry_fire` (silent_no_op トリガー) が2回発火した後、最終的に成功し PR #1021 を作成した実ログを確認したところ、`[anomaly]` 系の false-positive 出力は皆無だった。抑制ロジックが実運用で正しく機能することを実例で確認できたため、全 AC PASS で Issue クローズ。

### Improvement Proposals
- N/A (triage 中断は外部停止であり系統的欠陥ではない。watchdog silent window の較正は既存 #939 が追跡中)
