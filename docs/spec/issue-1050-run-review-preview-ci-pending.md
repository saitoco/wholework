# Issue #1050: run-review: preview/CI 待機未確定時の silent no-op 終了を防止

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (曖昧性自動解決ログとタイトルドリフト記録)。内容は Issue body の `## Autonomous Auto-Resolve Log` に既に反映済みで、本 Spec の設計に追加で取り込む新規情報はなし / https://github.com/saitoco/wholework/issues/1050#issuecomment-5133601470

`/code` フェーズ (cutoff: 2026-07-30T16:56:39Z、`phase/ready` ラベル付与時刻): 新規コメントなし。

## Overview

`scripts/run-review.sh` は `wait-ci-checks.sh` を呼び出した後、その結果を一切判別せずに無条件で `claude -p` の review セッションを起動している。このため次の 2 パターンで、待機対象が確定しないまま review セッションが起動し、silent no-op (セッションが実質的な作業をせず exit 0 で終了) → `post-fallback-review-summary.sh` のフォールバックスタブ投稿 → review phase が complete 扱いになる、という誤った完了判定が発生する。

1. `capabilities.pr-preview: true` の downstream プロジェクトで、PR preview (Amplify Console Web Preview 等) のビルドが CI check (lint 等) より遅く完了するケース
2. `pull_request: synchronize` が発火せず CI check-suite 自体が作成されない、または `wait-ci-checks.sh` がタイムアウトするケース

本 Issue は `scripts/run-review.sh` に、(a) `wait-ci-checks.sh` の実行結果 (`ci_result:` 行) を判別する分岐、および (b) `capabilities.pr-preview: true` 時に PR preview デプロイの完了を確認する分岐、の 2 つを追加し、いずれの場合も未確定であれば `claude -p` を起動せずに明示的な `PENDING` 終了とすることで、silent no-op → フォールバックスタブによる誤った complete 扱いを防止する。

## Reproduction Steps

1. `capabilities.pr-preview: true` を設定したプロジェクトで、ホスティング側 (例: AWS Amplify) が GitHub **Deployments API** 経由で preview ビルド状況を通知する構成の PR を作成する
2. lint 等の GitHub Actions check (Checks API 側) は早く完了するが、Amplify 側の preview ビルド (Deployments API 側) はまだ `pending`/`in_progress` のままの状態で `/review` を起動する (`run-auto-sub.sh` 経由の `run-review.sh $PR_NUMBER`、または直接実行)
3. `scripts/run-review.sh:102` の `wait-ci-checks.sh` 呼び出しは `gh pr checks` (Checks API) のみを見ているため、lint 等が完了した時点で「CI checks pending: 0」と判定して待機を終了する — Deployments API 側の preview ビルド状況は一切見ていない
4. `run-review.sh` は `wait-ci-checks.sh` の結果を判別せず、そのまま `claude -p` で review セッションを起動する
5. セッション内部で preview URL 未確定を検知した際、`skills/review/SKILL.md` Step 8.0 が想定する UNCERTAIN 分類に到達せず、「ビルド完了を待っています」等の非同期完了待ちを宣言したまま応答を終了する — `claude -p` は 1 ターン完結のステートレスプロセスであるため、実際には「待つ」ことができず、そのままプロセスが終了する (silent no-op)
6. `run-review.sh` は `EXIT_CODE=0` かつ `reconcile-phase-state.sh` が `matches_expected:false` を返したことを検知し、`post-fallback-review-summary.sh` を実行してフォールバックスタブを投稿、`matches_expected:true` に回復させて review phase を complete 扱いにする — 実体のあるレビューは 1 件も投稿されていない

4 例目 (CI check-suite 自体が作成されない、または `wait-ci-checks.sh` がタイムアウトするケース) も、`run-review.sh` が `wait-ci-checks.sh` の結果を判別しない同じ構造的欠陥により、同じ誤った complete 扱いに至る。

## Root Cause

`scripts/run-review.sh:102` は `wait-ci-checks.sh` の実行結果 (成功/タイムアウト/zero-checks) を一切判別せず、無条件で次のステップ (`claude -p` 起動) に進む。加えて `wait-ci-checks.sh` は `gh pr checks` (Checks API) のみを参照するため、Amplify/Vercel/Netlify 等が GitHub **Deployments API** で報告する preview デプロイ状況には構造的に非対応であり (`skills/review/SKILL.md` Step 8.0 は `{{base_url}}` 解決のために既に Deployments API を参照しているが、これは review セッション内部の静的検証ロジックであり、セッション起動前の wrapper 側の事前条件チェックではない)、どちらの経路にも「起動前に前提条件が整っているか」を確認する責務が存在しない。

この構造的欠落により、前提条件が整っていない状態でも `claude -p` セッションが常に起動され、セッション側が (ステートレスな 1 ターン完結プロセスの制約上、実際には不可能な)「非同期の完了待ち」を宣言して終了した場合、`post-fallback-review-summary.sh` のフォールバック投稿ロジック (本来は異なる障害モード=セッションのクラッシュからの回復用) がこれを覆い隠し、review phase を誤って complete 扱いにする。

したがって修正は `claude -p` を起動する **前** の wrapper 側 (`scripts/run-review.sh`) に置く必要がある — ステートレスなセッション内部でこの問題を解決することはできない。

## Changed Files

- `scripts/run-review.sh`: `wait-ci-checks.sh` の実行結果 (`ci_result:` 行の `pending=`/`zero_checks=`) を判別する分岐と、`capabilities.pr-preview: true` 時の PR preview デプロイ待機分岐を追加。いずれも未確定時は `claude -p` を起動せず `PENDING: ...` を出力して exit code 2 で終了する — bash 3.2+ 互換
- `tests/run-review.bats`: 新規分岐 (CI pending/zero-checks、preview デプロイ未確定/確定) のテストケースを追加。`sleep` を no-op でモック (`tests/wait-ci-checks.bats` の慣例に合わせる)
- `docs/tech.md`: `HAS_PR_PREVIEW_CAPABILITY` capability flag の説明行に `run-review.sh` の preview デプロイ待機ゲートを追記し、Environment Variables 表に `WHOLEWORK_PREVIEW_TIMEOUT_SEC` の行を追加
- `docs/ja/tech.md`: [Steering Docs sync candidate] `docs/translation-workflow.md` の Sync Procedure に従い、`docs/tech.md` の上記 2 箇所の変更を日本語で反映

## Implementation Steps

**Step 1 (→ acceptance criteria A, C)**: `scripts/run-review.sh` の既存コメント `# Wait for CI checks to complete before running claude` と直後の呼び出し `"$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"` (フェーズバナー出力の直後、`SKILL_FILE=...` 行より前) を、標準出力をキャプチャして `ci_result:` 行を解析するロジックに置き換える。`wait-ci-checks.sh` の進捗メッセージは stderr 出力のため、`$(...)` によるキャプチャでもリアルタイムのログ表示は変わらない (stdout のみキャプチャ対象になる)。

```bash
# Wait for CI checks to complete before running claude
_ci_wait_output=$("$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER")
echo "$_ci_wait_output"
_ci_result_line=$(echo "$_ci_wait_output" | grep '^ci_result:' || true)
_ci_pending=$(echo "$_ci_result_line" | grep -oE 'pending=[0-9]+' | cut -d= -f2 || echo 0)
_ci_zero_checks=$(echo "$_ci_result_line" | grep -oE 'zero_checks=[a-z]+' | cut -d= -f2 || echo false)

_pending_reason=""
if [[ "${_ci_pending:-0}" -gt 0 || "${_ci_zero_checks:-false}" == "true" ]]; then
  _pending_reason="CI check wait did not reach a confirmed state for PR #${PR_NUMBER} (${_ci_result_line:-no ci_result line captured})"
fi
```

**Step 2 (after 1) (→ acceptance criteria A, B, C)**: Step 1 の直後に、`.wholework.yml` の `capabilities.pr-preview: true` を bash 側で検出し (ブロック形式 `capabilities:\n  pr-preview: true` のみ対応 — 詳細は Notes 参照)、有効な場合のみ GitHub Deployments API で PR ブランチの最新デプロイ `state` を `WHOLEWORK_PREVIEW_TIMEOUT_SEC` (デフォルト 600 秒) を上限にポーリングする分岐を追加する。`skills/review/SKILL.md` Step 8.0 の `{{base_url}}` 解決で既に使われている Deployments API 参照パターン (`gh api repos/:owner/:repo/deployments?ref=<branch>` → `.../statuses`) を踏襲する。

```bash
if [[ -z "$_pending_reason" ]] && [[ -f .wholework.yml ]] \
   && grep -A 20 '^capabilities:' .wholework.yml 2>/dev/null | grep -qE '^[[:space:]]*pr-preview:[[:space:]]*true'; then
  echo "Waiting for PR preview deployment on PR #${PR_NUMBER}..." >&2
  _preview_timeout_sec="${WHOLEWORK_PREVIEW_TIMEOUT_SEC:-600}"
  _preview_branch=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
  _preview_state=""
  if [[ -n "$_preview_branch" ]]; then
    _preview_start=$(date +%s)
    while [[ $(( $(date +%s) - _preview_start )) -lt "$_preview_timeout_sec" ]]; do
      _deploy_id=$(gh api "repos/:owner/:repo/deployments?ref=${_preview_branch}&per_page=10" -q '.[0].id' 2>/dev/null || echo "")
      if [[ -n "$_deploy_id" && "$_deploy_id" != "null" ]]; then
        _preview_state=$(gh api "repos/:owner/:repo/deployments/${_deploy_id}/statuses?per_page=1" -q '.[0].state' 2>/dev/null || echo "")
        [[ "$_preview_state" == "success" ]] && break
      fi
      sleep 30
    done
  fi
  if [[ "$_preview_state" != "success" ]]; then
    _pending_reason="PR preview deployment not confirmed for PR #${PR_NUMBER} (branch=${_preview_branch:-unknown} state=${_preview_state:-none})"
  else
    echo "PR preview deployment ready for PR #${PR_NUMBER}" >&2
  fi
fi
```

**Step 3 (after 2) (→ acceptance criteria A, C)**: Step 1・2 の直後に、`_pending_reason` が非空であれば `claude -p` を起動せず、既存の終了処理 (バナー出力・`Exit code:` 出力) を経て exit code 2 で終了する単一の分岐を追加する。

```bash
if [[ -n "$_pending_reason" ]]; then
  echo "PENDING: ${_pending_reason}; skipping review session" >&2
  EXIT_CODE=2
  echo "---"
  echo "=== run-review.sh: Finished /review for PR #${PR_NUMBER} ==="
  print_end_banner "pr" "$PR_NUMBER" "review"
  echo "Exit code: ${EXIT_CODE}"
  echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
  exit $EXIT_CODE
fi
```

**Step 4 (after 3) (→ acceptance criteria A, B, C)**: `tests/run-review.bats` に以下のテストケースを追加する。`setup()` に `sleep` の no-op モック (`tests/wait-ci-checks.bats` と同じ慣例) を追加し、既存の `wait-ci-checks.sh` モックはデフォルトのまま (`ci_result:` 行なし) を維持することで既存テストの回帰を防ぐ。

- `wait-ci-checks.sh` モックが `ci_result: total=1 passed=0 failed=0 pending=1 cancelled=0 zero_checks=false` を返すケース → claude が呼ばれず (`CLAUDE_CALL_LOG` が空)、`status -eq 2`、出力に `PENDING:` を含む
- `wait-ci-checks.sh` モックが `ci_result: total=0 passed=0 failed=0 pending=0 cancelled=0 zero_checks=true` を返すケース → 同上
- `.wholework.yml` に `capabilities:\n  pr-preview: true` を設定し、`gh api` モックが deployment state `pending` を返し続けるケース (`WHOLEWORK_PREVIEW_TIMEOUT_SEC=1` 等の短縮値を指定) → claude が呼ばれず `status -eq 2`
- 同条件で `gh api` モックが deployment state `success` を返すケース → claude が通常通り呼ばれ `status -eq 0`
- `capabilities.pr-preview` が未設定のプロジェクト (既存のテスト用 `.wholework.yml`) では preview 分岐が発火しないこと (既存テストの回帰確認)

**Step 5 (parallel with 4) (→ SHOULD: ドキュメント同期)**: `docs/tech.md` の `HAS_PR_PREVIEW_CAPABILITY` 行末尾に「`run-review.sh` が preview デプロイ待機ゲートとしてもこのフラグを参照する」旨を追記し、Environment Variables 表に `WHOLEWORK_PREVIEW_TIMEOUT_SEC` (デフォルト `600`) の行を追加する。`docs/translation-workflow.md` の Sync Procedure に従い、同内容を `docs/ja/tech.md` にも日本語で反映する。

## Verification

### Pre-merge

- <!-- verify: rubric "run-review.sh または review skill が、pr-preview capability 有効時の preview URL 疎通 (ビルド完了) 待ち、および wait-ci-checks.sh がタイムアウトまたは zero-checks で終了した場合の CI 待機未確定、の双方について、silent no-op → fallback スタブ complete 扱いではなく、疎通/確定を待つ、または明示的に PENDING として終了する設計になっている" --> preview 未稼働時と CI 待機タイムアウト/zero-checks 時の両方で、挙動が「silent no-op → fallback スタブ」ではなく「疎通待ち」または「明示的 PENDING 終了」になっている
- <!-- verify: grep "preview" "scripts/run-review.sh" --> wrapper 側に preview 関連の待機または判定ロジックが存在する
- <!-- verify: grep "PENDING" "scripts/run-review.sh" --> wrapper 側に CI 待機タイムアウト/zero-checks 時の明示的 PENDING 判定ロジックが存在する

### Post-merge

- preview ビルドが長引く PR、または CI check-suite が作成されず待機がタイムアウトする PR で `/review` を実行し、いずれのケースでも fallback スタブのみで complete 扱いにならず PENDING として扱われることを確認する <!-- verify-type: opportunistic -->

## Notes

- **exit code 2 の選定理由**: `run-review.sh` は既に exit 0 (成功)・非 0 (`claude -p` 自体の失敗、`reconcile-phase-state.sh` の recheck 失敗時は 1)・143 (SIGTERM) を使用している。`_maybe_emit_phase_complete` の EXIT トラップは exit code が 0 または 143 の場合のみ `phase_complete` の backfill 判定を行うため、PENDING を 0/143 以外の値 (2) にすることで「フェーズは未完了のまま」という状態が構造的に保たれる。`run-auto-sub.sh` の `run_phase_with_recovery` は非 0 exit を Tier 1 (`reconcile-phase-state.sh` 完了チェック) → Tier 2 (`apply-fallback.sh`) → Tier 3 (`spawn-recovery-subagent.sh`) の順で処理するが、本 Issue のスコープは `scripts/run-review.sh` (AC2/AC3 の grep 対象) に限定されており、Tier 1-3 側の PENDING 専用ハンドリング追加は本 Issue の対象外とする。Tier 1 は完了シグネチャなしを正しく検出し、Tier 3 まで到達した場合もログ中の `PENDING: ...` メッセージから「待てば解決する」という診断は可能なため、既存の recovery cascade と非破壊的に共存する。
- **preview capability 検出のスコープ限定**: `run-review.sh` は bash wrapper であり、`modules/detect-config-markers.md` が定義する LLM 駆動の `capabilities.*` 解釈 (inline hash `capabilities: { pr-preview: true }` とブロック形式の両方に対応) を利用できない。既存の `scripts/get-config-value.sh` も「nested keys (`capabilities.browser` 等) は非対応」と明示的にスコープを限定しており、本 Issue でもこの前例に倣い、bash 側の検出はブロック形式 (`capabilities:\n  pr-preview: true`) のみに対応する簡易 grep とする。inline hash 形式は本 Issue のスコープ外とし、必要になった場合は別 Issue で `get-config-value.sh` 等への共通化を検討する。
- **preview デプロイ待機のタイムアウト設計**: `WHOLEWORK_PREVIEW_TIMEOUT_SEC` のデフォルト 600 秒は、既存の `wait-ci-checks.sh` 呼び出し (デフォルト上限 1200 秒) と合わせても review phase の watchdog 上限 (`WATCHDOG_TIMEOUT_REVIEW_SECONDS` デフォルト 2600 秒、`docs/tech.md` #903 再較正) を超えない。両方の待機が上限に達した場合はいずれも PENDING として `claude -p` を起動せずに終了するため、実際にレビューセッションへ進むケースでは待機時間が上限に達することは想定されない。
- **`skills/review/SKILL.md` 側は変更しない**: 本 Issue の AC2/AC3 は `scripts/run-review.sh` を明示的に対象としており、AC1 の rubric も「run-review.sh または review skill」のいずれかで要件を満たせば良いと記述している。`claude -p` はステートレスな 1 ターン完結プロセスであるため、前提条件が未確定な状態を検知して "待つ" ことは wrapper 側でのみ可能であり (Root Cause 参照)、修正を `scripts/run-review.sh` に集約することで `skills/review/SKILL.md` Step 8.0 の既存 UNCERTAIN 分類ロジックとは独立に (かつそれを壊さずに) 前提条件を保証できる。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜5 のコードブロックをそのまま適用し、設計からの逸脱はなかった。

### Design Gaps/Ambiguities
- N/A — 実装過程で新たに発見された設計上の曖昧性はなかった。`wait-ci-checks.sh` の `ci_result:` 行が stdout のみに出力される (進捗ログは stderr) という Spec の前提は実装スクリプトの現物確認で裏付けが取れた。

### Rework
- N/A — 手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 3件 (rubric/grep判定) がすべて PASS/チェック済みであることを確認し、squash merge を実行した。
- `--non-interactive` モードで実行し、pre-merge AC ゲート・mergeability 判定はいずれも auto-resolve 不要でクリーンに通過 (mergeable=true, reason=clean)。

### Deferred Items
- Post-merge AC (opportunistic): preview ビルドが長引く PR、または CI check-suite 作成前にタイムアウトする PR での `/review` 実況確認は、引き続き opportunistic 検証に委ねる (未解消のまま `/verify` に引き継ぐ)。
- `_preview_branch` の URL エンコード対応は、`skills/review/SKILL.md` Step 8.0 側の既存パターンとまとめて別 Issue で検討する候補として見送ったまま。

### Notes for Next Phase
- `closes #1050` により Issue は squash merge (`d8e0cf92`) で自動クローズされる見込み。base branch は `main`。
- Post-merge AC は opportunistic 検証待ちのまま — `/verify` 実行時に未チェックのまま残る想定 (手動で機会があれば検証)。

## review retrospective

### Spec vs. implementation divergence patterns
- N/A — `review-light` エージェントが Implementation Steps 1〜3 のコードブロックと `scripts/run-review.sh` L101-147 を文字単位で突合し、逸脱なしと確認した。

### Recurring issues
- SHOULD 指摘 1件: 新規追加した preview デプロイ待機ループ内の `gh api` 呼び出しに per-call timeout がなく、`wait-ci-checks.sh` が同一 PR で既に確立していた `timeout --kill-after=10 30 ... || gtimeout 30 ... || <bare>` フォールバックパターンが踏襲されていなかった。同一 Issue/PR 内に手本となる前例があるにもかかわらず新規コードで再適用されなかったケースであり、「ポーリングループを新規追加する際は、同一リポジトリ内の既存ポーリング実装 (wait-ci-checks.sh 等) のタイムアウト境界パターンを踏襲する」という観点を Spec の Implementation Steps または review チェックリストに明記する余地がある。次回同様のポーリングループ追加時は、Spec 作成段階で既存の類似実装への参照を明示すると手戻りを防げる可能性がある。

### Acceptance criteria verification difficulty
- Nothing to note — Pre-merge AC 3件はいずれも `rubric` / `grep` で明確に PASS 判定でき、UNCERTAIN は発生しなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- リファインメント時にタイトルが「preview ビルド未完了時」→「preview/CI 待機未確定時」に更新された。#1066 で `wait-ci-checks.sh` を bucket ベースに直した結果、問題の範囲が preview ビルド固有ではなく CI 待機全般に及ぶことが明確になったためで、同一 batch 内の先行 Issue の成果がスコープ定義に反映された good case。

#### spec / code
- 2 経路 (CI 待機未確定 / preview 未確定) を単一の `_pending_reason` 変数に集約し、終了処理を 1 箇所 (L151-159) にまとめる構成になっており、分岐の見通しが良い。preview 経路を「CI 側が確定済みの場合のみ実行」とガードしている点も、二重待機を避ける設計として妥当。
- Deviations / Rework とも N/A。

#### review
- `--light` で実施。修正コミット 2 件が追加され silent no-op なし (comments 0→1、reviews 0→1、`matches_expected: true`)。

#### merge
- CI 7 SUCCESS / 2 実行中の状態から `run-merge.sh` が完了まで待機して squash merge。conflict なし。

#### verify
- pre-merge 3 件すべて PASS、FAIL / UNCERTAIN なし、auto-retry 発火なし。
- post-merge の opportunistic 1 件は未チェックのまま `phase/verify` 留置 (設計どおり)。

### Improvement Proposals

- **`run-review.sh` が新設した `EXIT_CODE=2` (PENDING) を、呼び出し側が他の非 0 終了と区別していない**: 本 PR は preview/CI 待機が確定しない場合に `PENDING: ...; skipping review session` を出力して `EXIT_CODE=2` で終了する経路を追加した (L151-159)。これは「失敗」ではなく「まだ判定できないので待つべき」という**第三の終了状態**である。しかし `scripts/run-auto-sub.sh` と `skills/auto/SKILL.md` を検索した範囲では、exit code 2 を特別扱いする分岐は存在しない (auto 側の `PENDING` 言及は batch 完了レポートの `PENDING_LIST` = `phase/verify` ラベル集計で、本件とは無関係)。
  - **想定される経路**: `/auto` の pr route step 8 は「review が失敗したら completion check を実行し、`matches_expected: true` なら成功に上書き、そうでなければ Step 6 (3-Tier recovery) へ」と規定している。PENDING 終了時は review セッション自体が起動していないため Review Response Summary は当然存在せず、Tier 1 は `matches_expected: false` を返す。Tier 2 の anomaly detector にも該当パターンは登録されていないため、Tier 3 (recovery sub-agent) まで進む。**意図どおりに動作した結果が、復旧機構を起動させる**という逆転が起きうる。
  - **本 Issue の AC との関係**: 本 Issue の AC 3 件は wrapper 側の挙動のみを対象としており、いずれも PASS。呼び出し側の対応はスコープ外であり、AC の不備ではない。
  - **対応方針 (案)**: (a) `/auto` の review フェーズ分岐に exit code 2 の明示的なハンドリングを追加し、3-Tier recovery に流さず「CI/preview 確定待ちのため再実行が必要」として扱う (再実行は待機時間を置いてから)。(b) `reconcile-phase-state.sh review --check-completion` に PENDING 状態を表現できる第三の返り値を持たせる。(c) Tier 2 の `detect-wrapper-anomaly.sh` に `review-pending-not-failure` パターンを登録し、fallback catalog 側で「失敗ではない」と判定して再実行に導く。(a) が最も直接的だが、`run-code.sh` など他 wrapper が将来同じ PENDING セマンティクスを持つ場合を考えると (b) の方が拡張性がある。

### 観察

- 本 Issue もフェーズ分割方式 (issue / spec / code / review / merge を個別のバックグラウンド呼び出しで起動) で **kill ゼロ完走**。batch 全体での集計は「分割: 完走 6/6 (#1051, #1054, #1052, #1053, #1050 と #1066 の途中から)、連結 (`run-auto-sub.sh`): #1066 で kill 3 回」。Size M の pr route が 2 件 (#1053, #1050) とも分割で完走したことで、#1066 の kill が Size L 固有ではなく実行方式に依存する可能性が補強された。ただし依然として交絡は残る (#1066 のみ Size L)。
- preview 系の多層防御が本 batch で 3 層とも揃った: #1066 (上流 — code がビルド成功を保証)、#1050 (中間 — review が未確定なら PENDING で止まる)、#1053 (下流 — verify が preview tier AC を fail-open しない)。
