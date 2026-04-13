# Issue #146: ci: run-*.sh に gh pr checks --watch 待機を追加して auto の連続性を改善

## Overview

`/auto` の自動ワークフローで CI 完了前に `run-merge.sh` / `run-review.sh` / `run-verify.sh` が claude を起動すると、内部で CI 状態を確認した claude が「停止して確認を求める」出力をして exit してしまう問題がある（PR #139 / PR #142 で実観測）。

新規スクリプト `scripts/wait-ci-checks.sh` を作成し、上記 3 つの run-*.sh から claude 起動前に呼び出すことで、CI 完了まで event-driven に待機してから claude を起動できるようにする。

- `wait-ci-checks.sh`: `timeout $WHOLEWORK_CI_TIMEOUT_SEC gh pr checks <PR> --watch --interval 60 --required || true` でラップ（デフォルト 1200 秒）
- `run-verify.sh` はイシュー番号を受け取るため、PR を検出してから wait（patch route は PR 不在のためスキップ）

## Changed Files

- `scripts/wait-ci-checks.sh`: new file — CI 完了待機スクリプト
- `scripts/run-merge.sh`: `wait-ci-checks.sh` 呼び出しを claude 起動前に追加
- `scripts/run-review.sh`: `wait-ci-checks.sh` 呼び出しを claude 起動前に追加
- `scripts/run-verify.sh`: PR 検出ロジックと `wait-ci-checks.sh` 呼び出しを claude 起動前に追加（PR 不在時スキップ）
- `docs/tech.md`: Environment Variables セクションを追加し `WHOLEWORK_CI_TIMEOUT_SEC` の仕様を記載
- `docs/structure.md`: Scripts セクションに `wait-ci-checks.sh` を追加、ファイル数を 29 → 30 に更新
- `tests/wait-ci-checks.bats`: new file — wait-ci-checks.sh の bats テスト
- `tests/run-merge.bats`: setup の mock に `wait-ci-checks.sh` を追加
- `tests/run-review.bats`: setup の mock に `wait-ci-checks.sh` を追加
- `tests/run-verify.bats`: setup の mock に `wait-ci-checks.sh` と PR 検出用 `gh pr list` レスポンスを追加

## Implementation Steps

1. `scripts/wait-ci-checks.sh` を新規作成する (→ 受け入れ基準 A, B, C)

   ```bash
   #!/bin/bash
   # wait-ci-checks.sh - Wait for required CI checks to complete on a PR
   # Usage: ./scripts/wait-ci-checks.sh <pr-number>
   #
   # Environment variables:
   #   WHOLEWORK_CI_TIMEOUT_SEC: Maximum wait time in seconds (default: 1200)
   set -euo pipefail
   PR_NUMBER="${1:?Usage: wait-ci-checks.sh <pr-number>}"
   TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"
   echo "Waiting for CI checks on PR #${PR_NUMBER} (timeout: ${TIMEOUT_SEC}s)..." >&2
   timeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 --required || true
   echo "CI check wait complete for PR #${PR_NUMBER}" >&2
   ```

2. `scripts/run-merge.sh` と `scripts/run-review.sh` を更新する (after 1) (→ 受け入れ基準 D, E)

   両スクリプトで、`echo "---"` の直後・`SKILL_FILE=` 行の直前に以下を挿入する:
   ```bash
   # Wait for CI checks to complete before running claude
   "$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"
   ```

3. `scripts/run-verify.sh` を更新する (after 1) (→ 受け入れ基準 F)

   `echo "---"` の直後・`SKILL_FILE=` 行の直前に PR 検出と wait 呼び出しを挿入する:
   ```bash
   # Detect associated PR for CI wait (patch route has no PR)
   VERIFY_PR_NUMBER=$(gh pr list --search "is:merged linked:issue:$ISSUE_NUMBER" --json number -q '.[0].number' 2>/dev/null || echo "")
   if [[ -n "$VERIFY_PR_NUMBER" ]]; then
     "$SCRIPT_DIR/wait-ci-checks.sh" "$VERIFY_PR_NUMBER"
   else
     echo "No PR found for issue #${ISSUE_NUMBER} (patch route), skipping CI wait" >&2
   fi
   ```

4. `docs/tech.md` に `WHOLEWORK_CI_TIMEOUT_SEC` の仕様を記載する (parallel with 1, 2, 3) (→ 受け入れ基準 G)

   `## Gotchas` セクションの直前に新規セクションを追加する:
   ```markdown
   ## Environment Variables

   | Variable | Default | Description |
   |----------|---------|-------------|
   | `WHOLEWORK_CI_TIMEOUT_SEC` | `1200` | Maximum wait time in seconds for `wait-ci-checks.sh`. Set to a lower value (e.g., `60`) to test timeout behavior. |
   ```

5. テストと構造ドキュメントを更新する (parallel with 4)

   - `tests/wait-ci-checks.bats` を新規作成する（`wait-external-review.bats` と同パターン: mock `gh`, mock `timeout`, 正常系・タイムアウト系のテスト）
   - `tests/run-merge.bats` の `setup()` に `wait-ci-checks.sh` の mock を追加し、呼び出し検証テストを追加する
   - `tests/run-review.bats` の `setup()` に同様の mock を追加する
   - `tests/run-verify.bats` の `setup()` 内の `gh` mock に `gh pr list --search "is:merged linked:issue:*" --json number` に応答する分岐を追加し、wait 呼び出し検証テストを追加する
   - `docs/structure.md` の `scripts/` 行を `29 files` → `30 files` に更新し、Process management サブセクションに `wait-ci-checks.sh` のエントリを追加する

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/wait-ci-checks.sh" --> `scripts/wait-ci-checks.sh` が新規作成されている
- <!-- verify: file_contains "scripts/wait-ci-checks.sh" "WHOLEWORK_CI_TIMEOUT_SEC" --> `scripts/wait-ci-checks.sh` 内で環境変数 `WHOLEWORK_CI_TIMEOUT_SEC`（デフォルト 1200）が参照され、`timeout` コマンドに渡されている
- <!-- verify: file_contains "scripts/wait-ci-checks.sh" "gh pr checks" --> `scripts/wait-ci-checks.sh` 内で `gh pr checks --watch` が使用されている
- <!-- verify: file_contains "scripts/run-merge.sh" "wait-ci-checks.sh" --> `scripts/run-merge.sh` が claude 起動前に `wait-ci-checks.sh` を呼び出すように更新されている
- <!-- verify: file_contains "scripts/run-review.sh" "wait-ci-checks.sh" --> `scripts/run-review.sh` が claude 起動前に `wait-ci-checks.sh` を呼び出すように更新されている
- <!-- verify: file_contains "scripts/run-verify.sh" "wait-ci-checks.sh" --> `scripts/run-verify.sh` が claude 起動前に `wait-ci-checks.sh` を呼び出す（PR 不在時はスキップ）ように更新されている
- <!-- verify: file_contains "docs/tech.md" "WHOLEWORK_CI_TIMEOUT_SEC" --> `docs/tech.md` に新規スクリプトと環境変数の仕様が記載されている

### Post-merge

- `/auto` 実行時に CI 進行中でもフェーズ遷移が止まらず、CI 完了後に merge 判定が進行することを確認
- `WHOLEWORK_CI_TIMEOUT_SEC=60` 等の短い値で override した状態で `/auto` を実行し、タイムアウトが正しく発火することを確認

## Notes

- `|| true` の扱い: タイムアウトや `gh pr checks` 失敗時でも後続 claude に制御を渡し、claude 側の既存 judgment ロジックで abort/続行を判断する
- `run-verify.sh` の PR 検出に使う `gh pr list --search "is:merged linked:issue:$ISSUE_NUMBER"` は GitHub の `linked:issue` 検索クオリファイアを使用。PR が見つからない場合（patch route）はスキップする
- `gh pr checks --watch` は gh CLI 標準の event-driven 待機機構で、内部で 60s 間隔ポーリング（`--interval 60` で指定）するが呼び出し側は `timeout` + `--watch` のみでよい
- docs/structure.md のファイル数カウント（29 → 30）は wait-ci-checks.sh 追加による更新

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- bats テストで `timeout` が PATH モックで上書きできるか確認が必要だった（wait-ci-checks.sh は絶対パス呼び出しのため PATH モックが通らない懸念）。実際には wait-ci-checks.sh 内で `timeout` を PATH 経由で呼ぶため、各 bats テストの setup() に timeout モックを追加することで解決した
- run-merge.sh / run-review.sh では `"$SCRIPT_DIR/wait-ci-checks.sh"` と絶対パスで呼ぶため、既存テストが timeout コマンドの有無に依存するリスクがあった。timeout モック追加で macOS 環境での可搬性も確保した

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 承認条件は全て `file_exists` / `file_contains` verify コマンド付きで記述されており、自動検証可能な形式だった
- Spec の Implementation Steps も具体的な bash スニペットが含まれており、実装者の解釈余地が少なく設計された
- `run-verify.sh` の patch route スキップ条件が Issue 本文から Spec に引き継がれ、承認条件にも反映されていた点は優れた仕様転写

#### design
- 設計は実装と完全に一致（Code Retrospective に "N/A"）。スニペット付き Spec が設計意図の正確な伝達に有効だった
- `|| true` の扱いと patch route スキップロジックが明示されており、実装判断を不要にした

#### code
- テストモックの `timeout` 追加という設計時に明示されていなかった課題があったが、実装時に自己解決されている
- patch route（PR なし）での直接 main コミット形式のため、review フェーズが省略された。小規模変更では妥当だが、テスト追加を伴うためレビューがあった方が望ましかった可能性がある

#### review
- PR なし（patch route）のためフォーマルなレビューは行われなかった
- bats テストの mock 漏れ（timeout モック）はレビューがあれば事前に検出できた可能性がある

#### merge
- patch route のため直接 main へコミット。コンフリクトなし

#### verify
- 全 7 件の pre-merge 条件が PASS
- 2 件の post-merge opportunistic 条件はユーザー検証が必要（実際の `/auto` 実行環境が必要）
- PR なし（patch route）のため `gh pr checks` 系の verify コマンドは使用されていなかったため、patch route の UNCERTAIN 判定ロジックは今回は不要だった

### Improvement Proposals
- N/A
