# Issue #895: auto: concurrent_commit_detected がフェーズ自身の commit を誤検出

## Overview

`scripts/run-auto-sub.sh` の `run_phase_with_recovery()` 内、`concurrent_commit_detected` イベント発行ロジックは、`git log origin/main --since="@${PHASE_START}"` で検出した origin/main 上の新規 commit を無条件に「並行 commit」として emit している。フェーズ自身が patch route で commit+push した commit も検出対象に含まれてしまうため、単独セッション実行でも毎回誤検出が発生する (2026-07-03 batch セッションで観測: #880, #881, #883, #885, #886 の計 9 commit すべてが自 Issue フェーズの commit だった)。

commit メッセージの subject 行に現在処理中の Issue 番号 (`#N` または `closes #N`) が含まれる commit を検出対象から除外し、他 Issue/他アクター由来の真の並行 commit のみを emit するよう修正する。

## Reproduction Steps

1. `.wholework.yml` で `autonomy: L3` (patch route の commit+push が自動実行される設定) の状態で `/auto --batch` を実行する。
2. 単独セッションであっても、各 Issue の code-patch フェーズが `git commit -s` → `worktree-merge-push.sh` 経由で `origin/main` に commit を push する。
3. `run_phase_with_recovery()` がフェーズ完了直後に `git log origin/main --since="@${PHASE_START}"` を実行すると、たった今 push された自分自身の commit がヒットし、`concurrent_commit_detected` イベントとして emit される。
4. L3 session retrospective の `Concurrent commits detected` 指標に、他セッションが存在しないにもかかわらず非ゼロの値が記録される。

## Root Cause

`concurrent_commit_detected` の検出条件は「`PHASE_START` 時刻以降に `origin/main` に現れた commit」のみであり、その commit がどのアクターによるものかを一切区別していない (`scripts/run-auto-sub.sh` の該当ブロック、`run_phase_with_recovery()` 内)。patch route ではフェーズ自身が正常に `origin/main` へ直接 commit+push するため、この条件は単独セッション・並行稼働ゼロの状況でも構造的に 100% ヒットする。author 情報 (`%an`) も同一ローカル git identity が入るだけで、他アクター介在の判定には使えない。commit メッセージの subject に埋め込まれる Issue 番号 (`closes #N` / 素の `#N`) が、唯一「どの Issue のフェーズが作った commit か」を機械的に判別できる既存シグナルである。

## Changed Files

- `scripts/run-auto-sub.sh`: `run_phase_with_recovery()` 内の `concurrent_commit_detected` emit ループに自 Issue 番号除外フィルタを追加。追加構文は `[[ =~ ]]` と `local` のみで bash 3.2+ (macOS system bash) 互換
- `tests/run-auto-sub.bats`: 自 Issue commit のみのケース (誤検出なし) と、他 Issue commit 混在ケース (検出される) の bats test を追加。bash 3.2+ 互換

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `concurrent_commit_detected` emit ループ (`# concurrent_commit_detected: check for commits on origin/main since phase start` コメントブロック、`run_phase_with_recovery()` 内) を以下のように修正する (→ acceptance criteria AC1):

   ```bash
   # concurrent_commit_detected: check for commits on origin/main since phase start,
   # excluding this issue's own phase commits (identified via #N in the subject line)
   local _commits
   _commits=$(git log origin/main --since="@${PHASE_START}" --format="%H %an" 2>/dev/null || true)
   if [[ -n "$_commits" ]]; then
     local _phase_end; _phase_end=$(date +%s)
     local _since_sec=$(( _phase_end - PHASE_START ))
     local _self_issue_pattern="#${issue}([^0-9]|$)"
     while IFS= read -r _commit_line; do
       [[ -z "$_commit_line" ]] && continue
       local _sha="${_commit_line%% *}"
       local _author="${_commit_line#* }"
       local _subject; _subject=$(git log -1 --format="%s" "$_sha" 2>/dev/null || true)
       if [[ "$_subject" =~ $_self_issue_pattern ]]; then
         continue
       fi
       emit_event "concurrent_commit_detected" "phase=${phase}" \
         "commit_sha=${_sha}" \
         "author=${_author}" \
         "since_phase_start_sec=${_since_sec}"
     done <<< "$_commits"
   fi
   ```

   `$issue` は関数冒頭 `local phase issue runner_script exit_code log_file; phase="$1"; issue="$2"; ...` で既に定義済みの変数をそのまま使う (新規引数・環境変数は不要)。`_self_issue_pattern="#${issue}([^0-9]|$)"` は「`#` + Issue番号」の直後が数字でないこと (または文字列末尾) を要求する境界考慮の一致方式で、桁数の異なる Issue 番号同士の誤マッチ (例: 自 Issue `#89` が他 Issue `#895` の commit に誤マッチ) を防ぐ (Notes 参照、bash で実機検証済み)。既存の SHA/author 抽出ロジックと `emit_event` 呼び出しの引数構成は変更しない。

2. (after 1) `tests/run-auto-sub.bats` の既存 `"concurrent_commit_detected: emit_event called when git log returns commits"` test の直後に、以下のシナリオの test を追加する (→ acceptance criteria AC2 前半・誤検出なしの確認): `$MOCK_DIR/git` を、`log origin/main` 呼び出しでは自 Issue 番号 (`run bash "$SCRIPT" 42` と一致させ `42` を使う) のみの commit 1件 (例: `aaa1111 Test User`) を返し、`log -1 --format=%s <sha>` 呼び出し (SHA 引数で分岐) では同じ commit の subject として `closes #42` を含む文字列を返すよう設定する。アサーション: `run bash "$SCRIPT" 42` 実行後、`emit.log` に `concurrent_commit_detected` が一切出現しないこと。

3. (after 1, parallel with 2) `tests/run-auto-sub.bats` に、自 Issue commit と他 Issue commit が混在するケースの test を追加する (→ acceptance criteria AC2 後半・真の並行 commit 検出の確認): `$MOCK_DIR/git` の `log origin/main` 呼び出しで自 Issue (`#42`) commit と他 Issue (例: `#99`) commit の 2 件を返し、`log -1 --format=%s <sha>` 呼び出しをそれぞれの SHA で分岐させ対応する subject (`closes #42` / `closes #99`) を返す。アサーション: `emit.log` に他 Issue commit の SHA を含む `concurrent_commit_detected`(`commit_sha=<他Issueのsha>`) が出現し、自 Issue commit の SHA を含む emit は出現しないこと。

## Verification

### Pre-merge

- <!-- verify: rubric "run-auto-sub.shのconcurrent_commit_detected検出ロジックが、現在処理中Issue自身のフェーズによるcommitを除外するよう修正されている" --> `scripts/run-auto-sub.sh` の `concurrent_commit_detected` emission ロジックが、現在処理中の Issue 自身のフェーズによる commit を検出対象から除外するよう修正されている
- <!-- verify: rubric "tests/run-auto-sub.batsに、自Issue由来commitのみのケースで誤検出しないこと、および他Issue由来commitが混在するケースで検出されることの両方を検証するテストケースが含まれる" --> bats test で、自 Issue 番号を含む commit のみが存在するケース (誤検出なし) と、他 Issue 番号を含む commit が混在するケース (真の並行 commit として検出) の両方がカバーされている

### Post-merge

- 次回 `/auto --batch` 実行時、`Concurrent commits detected` が単独セッションでは 0 になることを観察 <!-- verify-type: opportunistic -->

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Issue Retrospective コメント。トリアージ結果 (Title 正規化、Type=Bug、Size=S、Value=3) と、Auto-Resolved Ambiguity Points (Issue 番号マッチングは単純部分文字列一致ではなく単語境界を考慮した比較を用いる) を確認。本 Spec の実装方針 (境界考慮の正規表現一致) はこの内容を踏襲した。(https://github.com/saitoco/wholework/issues/895#issuecomment-4882238048)

## Notes

- **Auto-Resolved Ambiguity Points (Issue 本文および Issue Retrospective コメントから継承)**: Issue 番号マッチングは単純部分文字列一致ではなく単語境界を考慮した比較を用いる。桁数の異なる Issue 番号同士 (自 Issue `#89` と他 Issue `#895` 等) の誤マッチを避けるため、`#${issue}` の直後が数字でないこと (`[^0-9]` または文字列末尾) を確認する正規表現境界一致を採用した。分離した bash 実行環境で実機検証済み: issue=89 のとき `pattern="#89([^0-9]|$)"` は `"...(closes #895)"` に非マッチ、`"...(closes #89)"` および `"...#89"` (文字列末尾) には正しくマッチすることを確認した。
- **既存パターンとの整合性**: commit subject 取得に `git log -1 --format="%s" <sha>` を追加する方式は `scripts/get-auto-session-report.sh` の既存パターン (`git log -1 --format='%s%n%b' "$_sha"`) に倣った。正規表現の変数化 (`local pattern=...` を定義してから `[[ $x =~ $pattern ]]` で参照) は `scripts/check-verify-dirty.sh` の `spec_regex` パターン (`spec_regex="^docs/spec/issue-([0-9]+)-"` → `[[ "$file" =~ $spec_regex ]]`) に倣った。
- **commit message 埋め込み位置の確認**: 実際の patch route commit (`6720c061`, `53eb7cd7`, `628ad0d0`, `c734536f`, `0319df9b` 等) の内容を確認した結果、`closes #N` および素の `#N` 参照は常に commit の subject 行 (1行目) に埋め込まれている (`skills/code/SKILL.md` の commit テンプレート `"{prefix} <summary> (closes #$NUMBER)"` も同様、`git commit -s -m` の1行目としてそのまま渡される)。よって `%s` (subject のみ) の取得で十分であり、`%B` (本文全体) の取得は不要と判断した。
- **Doc sync check**: `README.md` / `docs/workflow.md` / `docs/structure.md` / `docs/tech.md` (日本語ミラー含む) を `run-auto-sub.sh` キーワードで grep 済み。いずれも `run-auto-sub.sh` 自体の役割やオーケストレーション動作の記述のみで、`concurrent_commit_detected` の内部検出ロジックを記述している箇所は無し。ドキュメント更新は不要と判断した。
- **Scope 外の関連 Issue**: Issue 本文で言及されている #668 (icebox: 並行 commit と Issue 結果の相関分類) は、本 Issue 着地後に前提の再確認が必要な別 Issue であり、本 Spec のスコープには含めない。

## Auto Retrospective
### Orchestration Anomalies
- **[code-patch-silent-no-op]** Tier 2 fallback applied: phase=`code-patch`, action=run-code.sh-patch-retry, result=recovered.

### Improvement Proposals
- N/A (resolved by Tier 2 fallback catalog)
