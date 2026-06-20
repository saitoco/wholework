# Issue #719: merge: pre-merge check の pre-existing FAILURE と新規 FAILURE を baseline diff で区別

## Overview

merge フェーズが遭遇する pre-merge check の FAILURE を **pre-existing (base ブランチで既に FAIL) か新規発生か** を機械的に区別し、`--non-interactive` モードの auto-resolve policy に正確な判断材料を渡す。

背景インシデント (#702 verify retrospective): `/auto` の merge フェーズで Forbidden Expressions CI check が pre-existing FAILURE (`docs/spec/issue-710-blocked-by-workflow.md` を対象) だったため、`--non-interactive` auto-resolve policy がそのままマージを続行した。現状の policy は pre-existing でも新規でも同じく「FAIL を許容してマージ」する挙動を取り、真に MUST 修正すべき新規 FAILURE を見逃すリスクがある。

初期スコープは **Forbidden Expressions check** を対象とし、modular 設計 (check 名の dispatch table) で将来の全 check 化に拡張可能にする (Auto-Resolved: 背景インシデントに直結する least-risk な対象)。

採用方針は Issue 提案の **案 A (baseline diff)**。案 B (`docs/baseline-failures.md` SSoT) は将来の派生 Issue として deferred。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (Auto-Resolve Log: 初期スコープを Forbidden Expressions に設定、Post-merge AC1 の verify-type を `manual` に修正) / https://github.com/saitoco/wholework/issues/719#issuecomment-4758529826

この retrospective の内容は本 Spec の設計前提にすべて織り込み済み (Step 13 で `## issue retrospective` として Spec へ転記)。

## Changed Files

- `scripts/pre-merge-check.sh`: 新規作成 — baseline diff 分類器。対象 check を base ブランチと PR head ブランチで実行し、結果を NEW_FAILURE / PRE_EXISTING / FIXED / CLEAN に分類。bash 3.2+ 互換 (mapfile / 連想配列を使わない)。
- `scripts/run-merge.sh`: `wait-ci-checks.sh` 呼び出し直後・`SKILL_FILE=` 代入直前に baseline pre-merge gate を追加。`pre-merge-check.sh` を呼び、NEW_FAILURE (exit 2) のみ merge を abort。bash 3.2+ 互換。
- `modules/orchestration-fallbacks.md`: `## baseline-failure` catalog エントリを追加 (pre-existing vs 新規 FAILURE の handling パターン)。
- `skills/merge/SKILL.md`: 「Non-Interactive Mode Behavior」セクションに、run-merge.sh の baseline gate が Forbidden Expressions 新規 FAILURE を claude 起動前に弾く旨の注記を追加。
- `tests/pre-merge-check.bats`: 新規作成 — 分類ロジックの bats テスト (実 git fixture + bare origin remote + stub check + gh mock)。
- `tests/run-merge.bats`: `setup()` に `pre-merge-check.sh` の mock (default exit 0) を追加 (既存テストの set -e 失敗を防ぐ) + NEW_FAILURE→abort の新規テストを追加。
- `docs/structure.md`: Process management リストに `pre-merge-check.sh` を追加。scripts カウント (58→59) と tests カウント (79→80) を更新。
- `docs/ja/structure.md`: 上記の日本語ミラー同期 — エントリ追加 + カウント更新 (58→59 ファイル, 79→80 ファイル)。

## Implementation Steps

1. **`scripts/pre-merge-check.sh` を新規作成** (→ acceptance criteria A, B)
   - Usage: `pre-merge-check.sh <pr-number> [check-name]` — `check-name` 既定値 `forbidden-expressions`。
   - `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"`、`set -euo pipefail`。
   - 引数なし → usage を stderr に出力し exit 1。
   - check dispatch table (modular、現状 1 エントリ): `case "$CHECK" in forbidden-expressions) CHECK_REL="scripts/check-forbidden-expressions.sh" ;; *) echo "Error: unknown check: $CHECK" >&2; exit 1 ;; esac`。
   - ref 解決: `HEAD_REF=$(gh pr view "$PR" --json headRefName -q .headRefName)` と `BASE_REF=$(gh pr view "$PR" --json baseRefName -q .baseRefName)`。いずれか空なら stderr エラーで exit 1。
   - `git fetch --quiet origin "$HEAD_REF" "$BASE_REF"`。失敗時は stderr エラーで exit 1。
   - 関数 `run_check_on_ref(ref)`: `mktemp -d` で親一時dir を作り、その配下 `wt` パスへ `git worktree add --detach "$wt" "origin/$ref"`。`$wt/$CHECK_REL` が存在しなければ stderr エラーで exit 1 (env error)。`( cd "$wt" && bash "$CHECK_REL" ) >/dev/null 2>&1` の exit code を捕捉し `baseline_status` / `current_status` 変数 (名称に "baseline" を含む) に格納。`git worktree remove --force "$wt"` と `rm -rf` で後始末 (失敗は `|| true`)。
   - 分類ロジック (全ブランチ列挙、下記「ブランチ分岐の挙動全列挙」参照)。
   - 各ステータスは `0` = PASS、非 0 = FAIL として扱う。

2. **`scripts/run-merge.sh` に baseline pre-merge gate を追加** (after 1) (→ acceptance criteria C)
   - 挿入位置: `"$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"` の直後、`SKILL_FILE="${SCRIPT_DIR}/../skills/merge/SKILL.md"` の直前。
   - pointer comment `# See modules/orchestration-fallbacks.md#baseline-failure` (文字列 "baseline" を含む) と説明コメント (例: `# Baseline pre-merge gate: distinguish pre-existing vs new FAILURE before merge`) を付与。
   - `set +e; "$SCRIPT_DIR/pre-merge-check.sh" "$PR_NUMBER"; PRE_MERGE_CHECK_EXIT=$?; set -e` で実行。
   - 全ブランチ列挙 (下記参照): exit 2 → エラー出力して `exit 1`; exit 0 → そのまま続行; その他非 0 → 警告出力して続行 (fail-open)。

3. **`modules/orchestration-fallbacks.md` に `## baseline-failure` エントリを追加** (parallel with 1, 2) (→ acceptance criteria D)
   - 既存 catalog の schema (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) に従う。Applicable Phases: merge (run-merge.sh の pre-merge gate)。Rationale に #719 (本 Issue) と #702 (起点インシデント) を記載。

4. **`skills/merge/SKILL.md` の「Non-Interactive Mode Behavior」に注記を追加** (parallel with 1, 2, 3)
   - 1〜2 文で「Forbidden Expressions (および将来の baseline-gated checks) は run-merge.sh が `pre-merge-check.sh` で claude 起動前に pre-screen する。新規 (非 pre-existing) FAILURE は Step 1 到達前に merge を abort し、pre-existing FAILURE は通過させる」旨を記載。

5. **`tests/pre-merge-check.bats` を新規作成** (after 1)
   - `setup()`: bare remote (`git init --bare`) を `origin` として作成し、作業 repo に `main` ブランチと feature ブランチを push。`WHOLEWORK_SCRIPT_DIR` 配下に stub `check-forbidden-expressions.sh` (`grep -rq 'FORBIDDEN' skills/ 2>/dev/null && exit 1 || exit 0`) を配置。`gh` mock を PATH に置き `headRefName`/`baseRefName` を返す。各 ref のツリーに `skills/x.md` を配置 (FORBIDDEN の有無でシナリオを作る)。
   - シナリオ: NEW_FAILURE (base PASS / head FAIL → exit 2)、PRE_EXISTING (両方 FAIL → exit 0 + "PRE_EXISTING")、CLEAN (両方 PASS → exit 0 + "CLEAN")、FIXED (base FAIL / head PASS → exit 0 + "FIXED")、usage error (引数なし → exit 1)、unknown check 名 → exit 1。

6. **`tests/run-merge.bats` を更新** (after 2)
   - `setup()` に `$MOCK_DIR/pre-merge-check.sh` の mock (`#!/bin/bash` / `exit 0`、chmod +x) を追加 — 既存テストが run-merge.sh の新規呼び出しで `set -e` 失敗しないようにする。
   - 新規テスト: pre-merge-check.sh mock を `exit 2` に差し替え、`run bash "$SCRIPT" 88` が `status -eq 1` かつ出力に abort メッセージを含むことを確認。

7. **`docs/structure.md` を更新** (after 1, 5) (→ acceptance criteria E, F)
   - 「Process management:」リストに `- \`scripts/pre-merge-check.sh\` — ...` エントリを追加。
   - Directory Layout の scripts カウントを `(58 files)` → `(59 files)` に、tests カウントを `(79 files)` → `(80 files)` に更新。

8. **`docs/ja/structure.md` を同期** (after 7) (→ acceptance criteria G)
   - 同位置に日本語エントリを追加。scripts カウントを `（58 ファイル）` → `（59 ファイル）`、tests カウントを `（79 ファイル）` → `（80 ファイル）` に更新。

### ブランチ分岐の挙動全列挙

**`pre-merge-check.sh` の分類 (`baseline_status` / `current_status` の組合せ):**

| baseline | current | 分類 | stdout | exit code |
|----------|---------|------|--------|-----------|
| 0 (PASS) | ≠0 (FAIL) | NEW_FAILURE | `NEW_FAILURE: ...` | 2 |
| ≠0 (FAIL) | ≠0 (FAIL) | PRE_EXISTING | `PRE_EXISTING: ...` | 0 |
| ≠0 (FAIL) | 0 (PASS) | FIXED | `FIXED: ...` | 0 |
| 0 (PASS) | 0 (PASS) | CLEAN | `CLEAN: ...` | 0 |
| — | — | env error (引数欠落 / unknown check / ref 解決失敗 / fetch 失敗 / check script 不在) | stderr エラー | 1 |

- 監視継続: なし (分類後に exit)。

**`run-merge.sh` の baseline gate (`PRE_MERGE_CHECK_EXIT` の分岐):**

| `PRE_MERGE_CHECK_EXIT` | 意味 | 挙動 |
|------------------------|------|------|
| 2 | NEW_FAILURE | `echo "Error: ..." >&2`; `exit 1` (claude 起動前に merge を abort、Stop-and-Report) |
| 0 | CLEAN / FIXED / PRE_EXISTING | そのまま続行 (PRE_EXISTING の警告は pre-merge-check.sh が既に stdout 出力済み) |
| その他非 0 (1 等) | env error | `echo "Warning: pre-merge-check.sh could not complete (exit N); proceeding (fail-open)." >&2`; 続行 |

- 監視継続: gate 通過後は既存の claude 起動フローへ続行。`exit 1` 時は EXIT trap `_maybe_emit_phase_complete` が exit code 非 0 のため `phase_complete` を emit せず (正しい挙動)。

## Alternatives Considered

- **案 B (`docs/baseline-failures.md` SSoT 手動管理)**: 採用せず (将来の派生 Issue へ deferred)。手動メンテと expire 漏れリスクがあり、初期実装では baseline diff の自動性 (案 A) を優先。案 A で baseline 比較が「動かしてはいけない」高頻度 check が出てきた場合の補完として将来導入を検討。
- **gate を `skills/merge/SKILL.md` 側 (claude 実行内) に置く**: 採用せず。Issue 提案は「run-merge.sh の `--non-interactive` policy 改修」を明示しており、wrapper 側 (claude 起動前) に置くことで (1) 新規 FAILURE 時に merge skill のトークン消費を回避、(2) baseline diff の git/worktree 操作を deterministic な bash で完結できる。SKILL.md には Step 4 で注記のみ追加。
- **CI ジョブ結果 (`gh pr checks` / `gh run list`) で baseline 比較**: 採用せず。CI のジョブ粒度・実行タイミングに依存する。案 A の local 再実行は CI 非依存で deterministic、かつ Issue 提案 (案 A) の「対象 check を各ブランチで実行」という記述に忠実。
- **両 ref に同一の check 定義を適用 (unified check def)**: 採用せず。各 ref 自身の `scripts/check-forbidden-expressions.sh` を実行する (案 A の literal な解釈、最も単純)。PR が check スクリプト自体を変更する場合に非対称が生じうるが、初期スコープ (term list ベースの Forbidden Expressions check) では実害が小さいため Notes に既知の制約として記載。

## Verification

### Pre-merge
- <!-- verify: file_exists "scripts/pre-merge-check.sh" --> `scripts/pre-merge-check.sh` が新規作成されている
- <!-- verify: grep "baseline" "scripts/pre-merge-check.sh" --> baseline diff ロジック (base ブランチ check 実行) が含まれている
- <!-- verify: file_contains "scripts/run-merge.sh" "baseline" --> `run-merge.sh` の baseline gate が pre-existing vs 新規 FAILURE を区別する
- <!-- verify: file_contains "modules/orchestration-fallbacks.md" "baseline-failure" --> pre-existing FAILURE の handling パターンが orchestration-fallbacks catalog に登録されている
- <!-- verify: file_contains "docs/structure.md" "pre-merge-check.sh" --> `pre-merge-check.sh` が structure.md の Scripts 一覧に追加されている
- <!-- verify: grep "(59 files)" "docs/structure.md" --> scripts カウントが 59 に更新されている
- <!-- verify: grep "59 ファイル" "docs/ja/structure.md" --> 日本語ミラーの scripts カウントが 59 に同期されている

### Post-merge
- 別 PR で意図的に Forbidden Expressions FAIL を作り、本改修後の `pre-merge-check.sh` が「新規 FAILURE」として正しく abort することを観察 <!-- verify-type: manual -->
- `docs/spec/issue-710-blocked-by-workflow.md` の Forbidden Expressions pre-existing FAILURE を別 Issue で解消後、本改修が baseline=PASS 状態で正常動作することを確認 <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns
- none (run-merge.sh が呼び出す bash→bash 連携。merge SKILL.md の allowed-tools は既に `${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh:*` を含む。pre-merge-check.sh は run-merge.sh から呼ばれるため skill の allowed-tools 追加は不要)

### Built-in Tools
- `Write`: 新規ファイル作成 (pre-merge-check.sh, pre-merge-check.bats)
- `Edit`: 既存ファイル編集 (run-merge.sh, orchestration-fallbacks.md, merge/SKILL.md, run-merge.bats, structure.md, ja/structure.md)

### MCP Tools
- none

## Uncertainty

- **各 ref 自身の check スクリプトを実行する非対称性**: PR が `scripts/check-forbidden-expressions.sh` 自体を変更すると base と head で異なる check 定義が走る。
  - **検証方法**: 初期スコープ (term list ベースの check) では実害が小さい。設計上の既知制約として Notes に記載済み。将来 unified check def が必要になれば拡張。
  - **影響範囲**: Implementation Step 1 (`run_check_on_ref`)
- **`git worktree add --detach origin/<ref>` の挙動**: 安定した標準 git 動作 (detached worktree 作成 → 後始末で `git worktree remove --force`)。bash 3.2 / macOS 互換 (mapfile / 連想配列不使用)。外部仕様検証は不要。
  - **影響範囲**: Implementation Step 1, 5

## Notes

### Auto-Resolve Log (`--non-interactive` mode)

- **gate の設置場所 → `run-merge.sh` (wrapper、claude 起動前)** — 判断理由: Issue 提案が「run-merge.sh の `--non-interactive` policy 改修」を明示。新規 FAILURE 時のトークン消費回避 + deterministic な bash 完結。other candidates: merge SKILL.md 内 (claude 実行中)。
- **env error 時の挙動 → fail-open (警告 + 続行、exit 2 のみ hard-abort)** — 判断理由: check インフラのエラーで全 merge をブロックするより、既存の GitHub merge-state gate + 人手判断に委ねる方が least-risk。other candidates: fail-closed (env error でも abort)。
- **両 ref の check 定義 → 各 ref 自身のスクリプト** — 判断理由: 案 A の literal 解釈で最も単純。other candidates: unified check def (PR head のスクリプトを両ツリーに適用)。

### 設計メモ

- **scope (Auto-Resolved, /issue 由来)**: 初期実装対象は Forbidden Expressions check のみ。dispatch table により modular 拡張可能。全 check 自動化は将来。
- **dogfood**: 現在 main では Forbidden Expressions check が pre-existing FAILURE (`docs/spec/issue-710-blocked-by-workflow.md` が deprecated term を含む) のため、本 Issue の code PR を `/auto` でマージする際、新 gate は baseline=FAIL / current=FAIL → PRE_EXISTING と分類して通過するはず (本機能のセルフ検証になる)。Post-merge AC2 はこの pre-existing 解消後の baseline=PASS 動作確認。
- **CI 全体 conclusion を pre-merge AC に使わない理由**: 上記 pre-existing FAILURE のため `gh run list --workflow=test.yml ... conclusion` は失敗を返す。よって CI-success 系の `github_check` は本 PR の pre-merge AC に採用せず、ファイルベースの deterministic check のみを採用。
- **bats テスト入力フォーマット** (`tests/pre-merge-check.bats`): stub check は CWD (一時 worktree) 配下の `skills/` を `grep -rq 'FORBIDDEN'` で走査し、ヒットで exit 1。fixture は各 ref のツリーに `skills/x.md` を配置し、`FORBIDDEN` 文字列の有無で 4 分類を作る。`gh` mock は `pr view --json headRefName -q .headRefName` / `... baseRefName ...` に branch 名を返す。bare remote を `origin` として用意し `git fetch origin` / `origin/<ref>` worktree を機能させる。
- **派生 Issue**: 案 B (`docs/baseline-failures.md` SSoT 化) が必要になったら別 Issue。`docs/spec/issue-710-blocked-by-workflow.md` の Forbidden Expressions 解消も本 Issue とは独立の別 Issue。
- **L2→L1 経路**: 本改修は L2 内部の判定ロジック改修 (run-merge.sh が baseline diff を実行)。#704 マトリクスの A〜E 経路には該当せず、tier gate も不要。

## issue retrospective

### Auto-Resolve Log

- **対象 check の初期スコープ → Forbidden Expressions check を initial target に設定**
  - 判断理由: 背景インシデント (#702) は Forbidden Expressions check の pre-existing FAILURE が起点。最初の実装は triggering incident に直結する check を対象とするのが least-risk。提案の「案 A」は「全 check 自動」を目標としているが、initial scope を絞ることで実装リスクを低減しつつ、modular 設計により将来の全 check 化に対応できる。
  - AC テキストへの影響: なし (既存の AC は "baseline diff ロジックが含まれている" という design-agnostic な表現)

### AC 変更

- **Post-merge AC1 の `verify-type` 修正**: 非標準値 → `manual`
  - 理由: 旧称: observation 系の event 指定は標準 verify-type (auto/opportunistic/manual) に含まれない非標準値。人間が観察して確認する条件であるため `manual` が正確。

## spec retrospective

### Minor observations
- Issue の AC C (`file_contains "scripts/run-merge.sh" "baseline"`) は run-merge.sh がポリシーロジックを保持する前提で書かれていたが、実際の run-merge.sh は merge SKILL.md へ委譲する薄い wrapper だった。gate を run-merge.sh の claude 起動前 bash gate として設置することで AC を満たしつつ、Issue の「run-merge.sh の policy」という文言にも合致させた。AC 文言だけからは SKILL.md 変更とも読めたため、wrapper が正しい locus であることを調査で確定した。

### Judgment rationale
- gate を wrapper (claude 起動前) に置いた: 新規 FAILURE 時に merge skill のトークン消費を回避でき、baseline diff の git/worktree 操作を deterministic な bash で完結できるため。
- env error 時は fail-open (警告 + 続行): check インフラの障害で全 merge をブロックするより、既存の GitHub merge-state gate + 人手判断に委ねる方が least-risk。
- 両 ref とも各 ref 自身の check スクリプトを実行: 案 A の literal 解釈で最小実装。unified check def は将来拡張時に検討。

### Uncertainty resolution
- merge フェーズが Forbidden Expressions FAILURE を「どこで」遭遇するか当初不明だったが、調査の結果 merge SKILL.md は check を直接実行せず、`gh-pr-merge-status.sh` の `ci_failing` (CI ジョブ結果) 経由であることを確認。baseline diff を local 再実行にすることで CI 非依存・deterministic に解決した。
- pre-existing FAILURE が現在 main に実在する (`docs/spec/issue-710-blocked-by-workflow.md`) ことを確認。本 PR 自体が PRE_EXISTING 分類のセルフ検証 (dogfood) になる。同時に、CI 全体 conclusion を pre-merge AC に使えないこと (forbidden-expressions ジョブが落ち run conclusion=failure になるため) も判明し、ファイルベースの deterministic AC のみを採用した。

## Code Retrospective

### Deviations from Design

- `pre-merge-check.sh` の `run_check_on_ref` 関数で `worktree add` の出力を `>/dev/null 2>&1` に変更した (Spec は `2>/dev/null` のみ)。worktree 作成は verbose なため標準出力も抑制した方がクリーン。
- `_check_exit` の初期化を `local _check_exit=0` としたかったが、bash 3.2 互換のため `_check_exit=0` で代入し `( cd "$wt" && bash "$CHECK_REL" ) ...; _check_exit=$?` パターンにした。サブシェルで捕捉。
- `tests/pre-merge-check.bats` の `_setup_feature_branch` でブランチ固有の marker file (`skills/marker-${branch}.md`) を追加する設計変更が必要だった。Spec のシナリオ記述はコンテンツ差が前提だったが、base と head が同一コンテンツのテストケース (PRE_EXISTING, CLEAN) では `git commit` が空コミットで失敗するため。

### Design Gaps/Ambiguities

- Spec の `tests/pre-merge-check.bats` シナリオ説明は「skills/x.md に FORBIDDEN 文字列の有無で分類を作る」としていたが、PRE_EXISTING (base=FAIL / head=FAIL) と CLEAN (base=PASS / head=PASS) のシナリオで base と head が同一コンテンツになるため、git commit が空コミットエラーとなることがシナリオ設計上の見落としだった。marker ファイル追加で解消。
- Spec Notes に「本 Spec を含む docs/spec/* は forbidden-expressions の SCAN_DIRS に含まれる」との注記があり、retrospective で deprecated term を直接引用しないよう注意が必要だった。実際に遵守した。

### Rework

- `tests/pre-merge-check.bats` の `_setup_feature_branch` 関数を初版実装後に修正した (marker file 追加)。実行時に PRE_EXISTING と CLEAN テストが失敗し、空コミット問題と判明したため 1 回目テスト実行後に即時修正。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI failing (reason=ci_failing) は pre-existing Forbidden Expressions failure によるものと確認済み (review Phase Handoff から引継ぎ)。non-interactive モードで auto-resolve し、マージを続行した。
- `gh pr merge 723 --squash --delete-branch` が正常完了。closes #719 かつ BASE_BRANCH=main のため Issue は自動クローズされる。
- Phase Handoff write は worktree-local の Spec ファイルに対して実行し、main に push した。

### Deferred Items
- 全 check 自動化 (dispatch table 拡張) は将来の改善。
- 案 B (`docs/baseline-failures.md` SSoT 化) は必要になったら別 Issue。
- `docs/spec/issue-710-blocked-by-workflow.md` の Forbidden Expressions pre-existing FAILURE 解消は独立の別 Issue (Post-merge AC2 の前提)。
- CONSIDER 3 件は任意で対応 (blocking なし)。

### Notes for Next Phase
- Issue #719 は main マージ済み。`pre-merge-check.sh` の dogfood 検証 (Post-merge AC1: 別 PR で意図的 FAIL → abort 確認) を手動で行うこと。
- Post-merge AC2 (issue-710 の pre-existing FAILURE 解消後の CLEAN 動作確認) は issue-710 完了後に実施。
- `run-merge.bats` の emit 系テスト (tests 21, 23) は pre-existing failures — スコープ外。

## review retrospective

### Spec vs. Implementation Divergence Patterns

Spec の Implementation Step 5 は `tests/pre-merge-check.bats` のシナリオを 6 種列挙したが、実装では `env error: headRefName empty` と `env error: baseRefName empty` の 2 シナリオを追加した。これは Spec 記述の粒度不足ではなく env error ハンドリングの具体的なテストケース設計の結果であり、設計意図には合致している。Spec のシナリオ列挙は「最低限」の記述であることが多く、実装時に網羅的テストが追加されることは正常なパターン。

また、`SCRIPT_DIR` 変数が `WHOLEWORK_SCRIPT_DIR` 環境変数への依存を宣言しているが、実装内で未使用であることを確認した。Spec は `WHOLEWORK_SCRIPT_DIR` を参照しているが、`CHECK_REL` が worktree 相対パスを使うため `SCRIPT_DIR` が不要になった実装上の乖離。将来 dispatch table が sibling scripts を直接呼ぶ場合に使用されることが期待される設計の先取り可能性がある。CONSIDER レベルで記録。

### Recurring Issues

- `fail-open` シナリオ (env error → continue) のテストが Spec に記述されているが、対応するテストが追加されなかった (fail-open path は間接的に既存テストがカバー)。behavior spec と test coverage の対応が明示されていないパターンは、テスト追加の際に繰り返し発生する可能性がある。
- review-bug の SHOULD 検出 (EXIT trap 不在、ref バリデーション不足) は両方とも検証で false positive として排除された。自動マージ文脈の shell utility script に対する汎用セキュリティルールの適用は過検出しやすい。

### Acceptance Criteria Verification Difficulty

- 7 件すべての AC が `file_exists` / `grep` / `file_contains` による deterministic チェックで PASS。UNCERTAIN が 0 件というのは AC 設計が適切だった証左。
- CI の Forbidden Expressions check FAILURE は pre-existing と明示されており、review フェーズでの誤判断リスクがなかった (Phase Handoff が有効に機能)。
- verify command の構文エラーや false negative は発生せず、AC の品質は高かった。
