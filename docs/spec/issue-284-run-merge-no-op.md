# Issue #284: fix: run-merge.sh の no-op false-success(CI wait 早期 return + mergeable UNKNOWN 未処理 + post-validation 欠如)

## Overview

`/auto 281` merge phase の観測で `run-merge.sh` が 33 秒 exit 0 で返るが PR 未マージという no-op false-success が発生。3 層の root cause(CI 待機早期 return / mergeable=UNKNOWN 未処理 / post-validation 欠如)に対する 4 箇所の多層防御修正を加え、no-op を 3 層いずれかで遮断する。rubric と hard-pattern の併用で実装意図も semantic に検証する。

## Changed Files

- `scripts/wait-ci-checks.sh`: `gh pr checks --watch --interval 60 --required` から `--required` 依存を外し、required 未設定リポジトリでも全 check 完了を待機するロジックに変更。bash 3.2+ 互換
- `scripts/gh-pr-merge-status.sh`: `MERGEABLE=UNKNOWN` または `mergeStateStatus=UNKNOWN` 時、3 秒 backoff × 最大 5 回 retry を追加。retry 全失敗時は現状通り `{reason: unknown}` を返す。bash 3.2+ 互換
- `skills/merge/SKILL.md`: Step 1 分岐テーブル(現 L61-65)に `reason: unknown` 明示 branch を追加 — 1 回 sleep 10s → 再 `gh-pr-merge-status.sh` 呼出、それでも unknown なら非対話モード auto-resolve で merge attempt 続行
- `scripts/run-merge.sh`: claude -p 完了後に `gh pr view $PR_NUMBER --json state` 確認の post-validation を追加。`state != "MERGED"` なら warning 出力 + exit 1。bash 3.2+ 互換
- `tests/wait-ci-checks.bats`: `--required` 非依存挙動の検証テスト追加
- `tests/gh-pr-merge-status.bats`: UNKNOWN retry 挙動の検証テスト追加(mock gh を連続 UNKNOWN→MERGEABLE の順に応答させる)
- `tests/run-merge.bats`: post-validation 挙動の検証テスト追加(mock claude + mock gh で state != MERGED 時 exit 1 確認)

## Implementation Steps

1. `scripts/wait-ci-checks.sh:11-17` を変更 — `timeout $TIMEOUT_SEC gh pr checks "$PR_NUMBER" --watch --interval 60 --required` の `--required` 除去。代替案: `gh pr checks "$PR" --watch --interval 60`(全 check 対象に監視)を `|| true` 付きで実行。既存の `command -v timeout`/`gtimeout`/素実行の 3 分岐構造は維持 (→ AC 1, 2)

2. `scripts/gh-pr-merge-status.sh:44-65` を変更 — `JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus)` を `for` loop 内(`i=1..5`)でラップ。MERGEABLE/STATE 取得後に `if [[ "$MERGEABLE" == "UNKNOWN" || "$STATE" == "UNKNOWN" ]]; then sleep 3; continue; fi` を追加。5 回 retry 後も UNKNOWN なら現状最終 else 節に落ちる (→ AC 3, 4)

3. `skills/merge/SKILL.md` Step 1(L61-65)の mergeability 分岐テーブルに `reason: unknown` branch を追加 — 「**reason=unknown**: 10 秒待機後、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-merge-status.sh "$NUMBER"` を再実行。再取得も unknown なら非対話モードでは auto-resolve で Step 4 へ進む(対話モードでは user 判断)」を書き足す (→ AC 5)

4. `scripts/run-merge.sh:73-86` の EXIT_CODE 判定直後(現 L86 の `echo "---"` 直前)に post-validation ブロックを挿入 — `if [[ $EXIT_CODE -eq 0 ]]; then local PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state 2>/dev/null || echo ""); if [[ "$PR_STATE" != "MERGED" ]]; then echo "Warning: /merge exited 0 but PR #${PR_NUMBER} is not MERGED (state=${PR_STATE}); reporting no-op failure" >&2; EXIT_CODE=1; fi; fi` (→ AC 6, 7)

5. `tests/{wait-ci-checks,gh-pr-merge-status,run-merge}.bats` に上記挙動を検証するテストケースを追加(各ファイルの既存 setup/mock パターンを踏襲) (→ AC 8, 9)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/wait-ci-checks.sh" "--watch --interval 60 --required" --> `wait-ci-checks.sh` から `--watch --interval 60 --required` の固定組合せが除去されている
- <!-- verify: rubric "scripts/wait-ci-checks.sh は required check 未設定のリポジトリでも全 CI check の完了を待機する実装になっている(--required 依存なし)" --> wait 実装が required 非依存
- <!-- verify: grep "UNKNOWN" "scripts/gh-pr-merge-status.sh" --> `gh-pr-merge-status.sh` に UNKNOWN 処理が追加されている
- <!-- verify: rubric "scripts/gh-pr-merge-status.sh は MERGEABLE=UNKNOWN または mergeStateStatus=UNKNOWN 時に backoff 付き retry を行う実装を含む" --> UNKNOWN retry 実装
- <!-- verify: file_contains "skills/merge/SKILL.md" "reason: unknown" --> `skills/merge/SKILL.md` Step 1 分岐に `reason: unknown` の明示ハンドリングが追加されている
- <!-- verify: grep "PR_STATE\|state.*MERGED\|mergedAt" "scripts/run-merge.sh" --> `run-merge.sh` の post-claude 段階に merge 実行検証ロジックが追加されている
- <!-- verify: rubric "scripts/run-merge.sh は claude -p 完了後に PR の state を gh pr view で確認し、MERGED でなければ非 0 exit する post-validation を含む" --> post-validation 実装
- <!-- verify: command "bats tests/wait-ci-checks.bats tests/gh-pr-merge-status.bats tests/run-merge.bats" --> 既存 3 bats の更新テスト含む全テストがローカル PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テストが CI で PASS する

### Post-merge

- 実 Issue(サイズ M 以上)で `/auto` を実行し、merge phase が確実にマージを実行するか、マージできない場合は非 0 exit で下流を止めることを確認(verify-type: opportunistic)

## Notes

- **多層防御の狙い**: 4 箇所の修正(wait-ci-checks / gh-pr-merge-status / merge SKILL Step 1 / run-merge post-validation)はいずれも独立に no-op 検知可能。1 箇所の regression でも他 3 層で抑止できる
- **run-merge.sh post-validation の位置**: 現行の watchdog kill 時の reconcile ロジック(L76-86)より後ろ(`echo "---"` 直前)に配置。watchdog reconcile で EXIT_CODE=0 になった場合でも post-validation で再確認できる
- **UNKNOWN retry の合計待機時間**: 3s × 5 = 15s(worst case)。wait-ci-checks の後続で走るため、CI 完了直後の GitHub internal state 計算時間を吸収するには十分と判断
- **`gh pr view --json state -q .state`**: SPEC 追加時点で `gh-pr-merge-status.sh` が既に `gh pr view` を使っているので allowed-tools 追加は不要(merge SKILL.md/run-merge.sh の`gh`汎用許可で covered)
- **bats test input format**: mock gh で JSON 出力を stub する方式は既存 `tests/gh-pr-merge-status.bats` の `make_gh_mock` ヘルパーを再利用。新たに連続応答を返す mock helper(初回 UNKNOWN → 2 回目以降 MERGEABLE)を追加する必要あり
- **self-reference exclusion**: 本件のテストは `.bats` 自身が検証対象文字列(`--required`, `UNKNOWN` 等)を含むが、検証対象は `scripts/*.sh` / `skills/merge/SKILL.md` のみで bats ファイルは含まれないため、false positive 懸念は軽微。必要なら tests/*.bats を検証パスから除外
- **rubric + hard-pattern 併用**: 静的 grep だけでは「retry 実装かどうか」を意味レベルで捉えきれないため、各層に `rubric` 付き AC を用意して grader に意図確認を委譲
- **#283 との補完**: #283 は verify 側で未マージ PR を検知する保険。本 Issue は merge 側の元栓を閉じる。両方マージされれば二重防御
- **Architecture Decisions impact 確認**: 本変更は `.wholework.yml` 新キー追加や `claude -p` CLI flag 変更を含まないため、`docs/tech.md` Architecture Decisions への影響なし。`tech.md` 更新不要
