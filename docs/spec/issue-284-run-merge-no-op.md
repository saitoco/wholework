# Issue #284: fix: run-merge.sh の no-op false-success(CI wait 早期 return + post-validation 欠如)

## Overview

`/auto 281` merge phase の観測で `run-merge.sh` が 33 秒 exit 0 で返るが PR 未マージという no-op false-success が発生。2 層(予防: `wait-ci-checks.sh` の `--required` 依存除去 / 防衛: `run-merge.sh` の post-claude 段階に `gh pr view --json state` による MERGED 検証追加)で遮断する。初版の 4 層案から scope 縮小(UNKNOWN retry と SKILL.md 分岐追加は冗長と判断)。

## Changed Files

- `scripts/wait-ci-checks.sh`: `gh pr checks --watch --interval 60 --required` から `--required` 除去、全 check を watch 対象にする(required 未設定環境でも機能)。bash 3.2+ 互換
- `scripts/run-merge.sh`: 既存 watchdog reconcile ロジック(現 L76-86)より後ろに `gh pr view $PR_NUMBER --json state` 確認の post-validation を追加。`state != "MERGED"` なら `EXIT_CODE=1` 上書き + warning 出力。bash 3.2+ 互換
- `tests/wait-ci-checks.bats`: `--required` 非依存の挙動検証ケース追加
- `tests/run-merge.bats`: post-validation 挙動検証ケース追加(mock gh で `state` を `OPEN`/`MERGED` に切替えて exit code を確認)

## Implementation Steps

1. `scripts/wait-ci-checks.sh:11-17` を変更 — 既存の `command -v timeout`/`gtimeout`/素実行の 3 分岐構造は維持したまま、各 `gh pr checks` 呼出から `--required` を除去する。コメント L6 の仕様注記も整合更新 (→ AC 1, 2)

2. `scripts/run-merge.sh` の現 `echo "---"`(L86 前後)直前に post-validation ブロックを挿入 — EXIT_CODE が 0 のときのみ `gh pr view "$PR_NUMBER" --json state -q .state 2>/dev/null` で state を取得し、`MERGED` でなければ warning を stderr 出力して `EXIT_CODE=1` に上書き。watchdog reconcile の後ろに置くことで、reconcile で 0 になった場合も再確認する (→ AC 3, 4)

3. `tests/wait-ci-checks.bats` / `tests/run-merge.bats` に上記挙動の検証を追加 — `tests/wait-ci-checks.bats` は mock gh の呼出引数に `--required` が含まれないことを assert。`tests/run-merge.bats` は mock gh の `pr view --json state` 応答を `OPEN`/`MERGED` で切替え、exit code の期待値を assert (→ AC 5, 6)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/wait-ci-checks.sh" "--watch --interval 60 --required" --> `wait-ci-checks.sh` から `--watch --interval 60 --required` の固定組合せが除去されている
- <!-- verify: rubric "scripts/wait-ci-checks.sh は required check 未設定のリポジトリでも全 CI check の完了を待機する実装になっている(--required 依存なし)" --> wait 実装が required 非依存
- <!-- verify: grep "PR_STATE\|state.*MERGED\|mergedAt" "scripts/run-merge.sh" --> `run-merge.sh` の post-claude 段階に merge 実行検証ロジックが追加されている
- <!-- verify: rubric "scripts/run-merge.sh は claude -p 完了後に PR の state を gh pr view で確認し、MERGED でなければ非 0 exit する post-validation を含む(既存 watchdog reconcile より後ろに配置)" --> post-validation 実装
- <!-- verify: command "bats tests/wait-ci-checks.bats tests/run-merge.bats" --> 更新された 2 bats がローカル PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テストが CI で PASS する

### Post-merge

- 実 Issue(サイズ M 以上)で `/auto` を実行し、merge phase が確実にマージを実行するか、マージできない場合は非 0 exit で下流を止めることを確認(verify-type: opportunistic)

## Notes

- **scope 縮小の経緯**: 初版は 4 層防御(wait-ci-checks / gh-pr-merge-status UNKNOWN retry / merge SKILL.md reason:unknown 分岐 / post-validation)を提案。trade-off 分析で「wait-ci-checks が正しく待てば mergeable=UNKNOWN 滞在は稀」「SKILL.md 分岐追加は prompt-based で将来 drift の種」という観点から中間 2 層を削除。post-validation で silent failure を顕在化できれば rare な model misfire は下流 orchestrator で対処可能
- **post-validation の位置**: 現行 watchdog kill 時 reconcile ロジック(L76-86)より後ろ。reconcile で EXIT_CODE=0 になったケースでも post-validation で再確認できる二重防御的な配置
- **UNKNOWN retry が不要な理由**: GitHub の mergeable 計算は CI 完了後は秒単位で完了する。wait-ci-checks が全 check 完了まで待てば、その後の `gh pr view` は CLEAN/BLOCKED 等の決定的 state を返す確率が高い。稀に UNKNOWN が残っても post-validation が検知して exit 1 を返すので silent failure にはならない
- **bats test の mock 方針**: 既存 `tests/wait-ci-checks.bats` の `setup` で `MOCK_DIR` + PATH prepend パターン、`tests/run-merge.bats` の `CLAUDE_CALL_LOG` 記録パターンをそのまま再利用。新 mock は不要
- **self-reference 懸念なし**: 検証対象は `scripts/*.sh` のみ。bats ファイルに `--required` や `MERGED` 等の文字列が含まれても verify command が bats を直接 grep しないため false positive 懸念は軽微
- **rubric + hard-pattern 併用**: 静的 grep だけでは「post-validation が既存 reconcile より後ろに配置されているか」を意味レベルで捉えきれないため、`rubric` で grader に意図確認を委譲(2 箇所)
- **#283 との補完**: #283 は verify 側の保険(未マージ PR 検知で早期 FAIL)、既に `/verify` SKILL.md に実装済み(Step 2 の OPEN_PR 検知ロジック L91-103 で確認)。本 Issue は merge 側の元栓。両方揃うことで二重防御
- **Architecture Decisions impact なし**: 本変更は `.wholework.yml` 新キー追加や `claude -p` CLI flag 変更を含まないため `docs/tech.md` 更新不要

## Code Retrospective

### Deviations from Design

- N/A: 実装はスペック通り。`docs/structure.md` と `docs/ja/structure.md` の "required CI checks" 記述更新を追加(スペックに明示なかったが doc-checker で検出)。

### Design Gaps/Ambiguities

- N/A: スペックの実装ステップは明確で曖昧な点なし。`docs/structure.md` 同期はスペックの範囲外だったが doc-checker モジュールで自動検出できた。

### Rework

- N/A: 1 回の実装で完了。

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- 実装は全体的にスペック通り。`--required` 除去・post-validation 追加ともに仕様通りの位置に実装された。
- スペック外の追加（docs/structure.md更新）は Code Retrospective で既に捕捉されており、レビュー時に再指摘となったが実用上問題なし。スペックに doc 更新が必要な場合は実装ステップに明示するとより明確になる。

### Recurring Issues

- `gh pr view` 失敗時の空文字列 fallback（`|| echo ""`）が誤警告トリガーになり得るパターンは今後の bash スクリプトでも注意が必要。API 呼び出し失敗時は空文字列チェック（`-n`）を併用するのが一貫した防御パターンとなる。

### Acceptance Criteria Verification Difficulty

- UNCERTAIN なし。全条件が静的 grep・rubric・bats・CI チェックで確定的に判定可能だった。verify command の網羅性は良好。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文に root cause と scope 縮小経緯が詳細に記載されており、spec との整合性確認が容易だった。4 層→2 層の意思決定プロセスが明示されていた点は今後の spec 品質の参考になる。

#### design
- 初版 4 層設計から 2 層への scope 縮小(UNKNOWN retry と SKILL.md 分岐を除外)は実装結果と完全に一致。設計判断が正確だった。`docs/structure.md` 同期はスペック外だったが doc-checker で自動検出されており、スペックに doc 更新の要否を明示すると完全性が上がる。

#### code
- リワークなし、1 回の実装で完了。commit history は squash merge で PR #285 として 1 コミット。fixup/amend パターンなし。doc-checker によるスペック外追加(docs/structure.md)は自動検出された軽微な補足。

#### review
- PR #285 には 1 レビュー・1 コメント。`gh pr view` 失敗時の空文字列 fallback (`|| echo ""`) が誤警告トリガーになり得るパターンへの指摘があり、`-n` チェックとの組み合わせが防御パターンとして共有された。verify で UNCERTAIN なし — レビューで見逃した条件ゼロ。

#### merge
- PR #285 を通じたクリーンマージ。CI 全 pass 確認後マージ。コンフリクトなし。

#### verify
- 6 条件すべて PASS。file_not_contains・rubric×2・grep・command(bats)・github_check の多様な verify command が機能した。post-merge opportunistic 条件(実 Issue での `/auto` 実行確認)のみユーザー検証待ち。`phase/verify` ラベルで追跡中。

### Improvement Proposals
- N/A
