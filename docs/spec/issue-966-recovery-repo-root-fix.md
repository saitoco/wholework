# Issue #966: auto: リカバリ sub-agent の Spec 更新コミットが誤って wholework リポジトリに push される

## Consumed Comments

- saito / MEMBER / first-class / 根本原因を `scripts/run-auto-sub.sh` の `_repo_root` 算出ロジック (`dirname "$SCRIPT_DIR"`) と特定、#962 (`append-consumed-comments-section.sh`) と同一パターンである重複候補を報告 (対応方針は `/code` 時判断に委ねる) / https://github.com/saitoco/wholework/issues/966#issuecomment-4925668272
- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (Triage結果: Type=Bug Size=S Value=4、重複候補対応方針、AC構造化の根拠、Auto-Resolved Ambiguity Points) / https://github.com/saitoco/wholework/issues/966#issuecomment-4925679257

## Overview

`scripts/run-auto-sub.sh` のリカバリ関連関数 (Tier 2/Tier 3 sub-agent recovery、manual recovery、resume preamble) が Spec 更新コミットや `docs/reports/orchestration-recoveries.md` を `git add`/`commit`/`push` する際、対象リポジトリのルート (`_repo_root`) をスクリプト自身の格納パス (`${CLAUDE_PLUGIN_ROOT}/scripts/`) から算出しており、実際に `/auto` を実行している呼び出し元プロジェクトのリポジトリルートと一致しない。このため、リカバリ記録コミットが誤って `saitoco/wholework` (プラグイン本体) に push される。`_repo_root` の算出ロジックを呼び出し元の実際の作業ディレクトリ (CWD) ベースに修正する。

## Reproduction Steps

1. downstream プロジェクトのリポジトリ (CWD) で `/auto --batch` 等を実行し、`${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $NUMBER` が呼び出される (`${CLAUDE_PLUGIN_ROOT}` はプラグインのインストール/キャッシュパスであり、CWD とは別ディレクトリ)
2. code-patch 等のフェーズで wrapper が非ゼロ終了し、Tier 2/Tier 3 リカバリ (`_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` / Tier 3 の `orchestration-recoveries.md` 更新ブロック) または `--write-manual-recovery` (`_write_manual_recovery_to_spec`) が発火する
3. これらの関数内で `_repo_root="$(dirname "$SCRIPT_DIR")"` (`SCRIPT_DIR` はスクリプト自身の格納先) が計算され、`git -C "$_repo_root" add/commit/push` が実行される
4. `SCRIPT_DIR` が指すディレクトリはプラグイン本体の `scripts/` であるため、`_repo_root` はプラグインリポジトリ (`saitoco/wholework`) のルートに解決され、Spec 更新コミットが誤ってそちらへ push される

**実際に発生した事例 (本リポジトリで確認済み)**: `saitoco/wholework` の git 履歴に、wholework 自身の Issue #268 (実際のタイトル: 「drift: verify SKILL.md の retro/verify ラベル作成指定を setup-labels.sh SSoT に整合」) とは無関係な内容 (タイトル「our-tests: TestProcedureSection の CTA ボタンが全ロケールで機能しない」、つまり別プロジェクトの Issue #268) を持つ `docs/spec/issue-268-recovery.md` が、コミット `e4349353` (Tier 3 recovery, `_write_tier3_recovery_to_spec` 由来) と `09f9900e` (manual recovery, `_write_manual_recovery_to_spec` 由来) によって作成・追記されていた。同時に `docs/reports/orchestration-recoveries.md` にも、コミット `c2650d1a` (`run_phase_with_recovery` 内 Tier 3 push ブロック由来) によって同一 Issue #268 の誤エントリ (診断内容に `select.tsx`, `globals.css` 等、wholework 自身には存在しないフロントエンドファイルへの言及あり) が追加されていた。

## Root Cause

`scripts/run-auto-sub.sh` 内に以下 8 箇所、`_repo_root` (または `repo_root` / `_REPO_ROOT`) を次のパターンで算出している箇所が存在する:

```bash
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
_repo_root="$(dirname "$SCRIPT_DIR")"
```

| # | 関数 | 行 (現状) | 変数名 |
|---|------|-----------|--------|
| 1 | `_write_manual_recovery_to_spec()` | 69-71 | `_repo_root` (ローカル `_script_dir` 経由) |
| 2 | `_write_tier2_recovery_to_spec()` | 207-208 | `_repo_root` |
| 3 | `_write_tier3_recovery_to_spec()` | 247-248 | `_repo_root` |
| 4 | `_write_wrapper_retry_recovery()` | 298-299 | `_repo_root` |
| 5 | `_observe_code_milestone()` | 353-354 | `repo_root` |
| 6 | `run_phase_with_recovery()` (Tier 3 push ブロック) | 522 | `_repo_root` |
| 7 | Size M resume preamble | 604 | `_REPO_ROOT` |
| 8 | Size L resume preamble | 674 | `_REPO_ROOT` |

`SCRIPT_DIR` はスクリプト自身の格納ディレクトリ (`dirname "$0"`、または `WHOLEWORK_SCRIPT_DIR` 環境変数) を指す。`run-auto-sub.sh` は `skills/auto/SKILL.md` から常に `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER` という絶対パスで呼び出され (`${CLAUDE_PLUGIN_ROOT}` はプラグイン自身のインストール/キャッシュパス)、Bash ツール呼び出し時の CWD は `/auto` セッションが実際に作業しているプロジェクトリポジトリのままである。したがって `dirname "$SCRIPT_DIR"` は「プラグイン本体の格納ルート」に解決され、「呼び出し元プロジェクトのリポジトリルート」とは一致しない。CWD がプラグイン自身のリポジトリと一致するケース (wholework 自身を `/auto` で自己適用する場合) でのみ偶然一致し、downstream プロジェクトから呼び出された場合は常に誤ったリポジトリを指す。

`scripts/spawn-recovery-subagent.sh` / `scripts/apply-fallback.sh` / `scripts/reconcile-phase-state.sh` も同じ `SCRIPT_DIR` 定義パターンを持つが、これらは `-C $_repo_root` 形式での git commit/push を独自に行っていないため、本 Issue の対象外 (`apply-fallback.sh` の DCO auto-fix ハンドラは `git commit --amend`/`git push` を CWD 前提で直接実行しており、別の仕組み)。

**既存の正しい実装パターン**: `scripts/worktree-merge-push.sh:41` は `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` という CWD ベースの解決を既に採用しており、本修正はこのパターンに統一する。`git rev-parse --show-toplevel` は worktree 内では worktree 自身のルートを返す (実測確認済み) ため、`/auto` の XL 並列実行時に worktree 内から呼び出された場合も意図通り動作する。

**#962 との関係**: `scripts/append-consumed-comments-section.sh` (#962 で報告) も同一パターン (`_repo_root="$(dirname "$SCRIPT_DIR")"`) を持つが、2026-07-09 時点で #962 は未修正 (OPEN) であり、参考にできる確立済み修正パターンは存在しない。#962 は別スクリプトを対象とした別 Issue として独立に進行中のため、本 Issue のスコープは `scripts/run-auto-sub.sh` に限定する。

## Changed Files

- `scripts/run-auto-sub.sh`: `set -euo pipefail` の直後 (`--write-manual-recovery` 早期リターン分岐より前) にグローバル `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` を追加し、Root Cause 表の 8 箇所すべての `_repo_root`/`repo_root`/`_REPO_ROOT` 算出式を `$REPO_ROOT` を参照する形に置き換える — bash 3.2+ 互換 (mapfile 等の bash4+ 構文は使用しない)
- `tests/run-auto-sub.bats`: 独自の `$MOCK_DIR/git` モック定義 (14 箇所) に `rev-parse --show-toplevel` ハンドラを追加し `$BATS_TEST_TMPDIR` を返すようにする — bash 3.2+ 互換
- `docs/spec/issue-268-recovery.md`: 削除 (確認済みの誤 push ファイル、コミット `e4349353` + `09f9900e`)
- `docs/reports/orchestration-recoveries.md`: `## 2026-07-09 08:44 UTC: code-patch-tier3-recovery` セクション (Issue #268, phase: code-patch のエントリ、コミット `c2650d1a` 由来) を削除
- `docs/tech.md` / `docs/structure.md` / `docs/workflow.md` / `docs/migration-notes.md`: [Steering Docs sync candidate] `run-auto-sub.sh` の記述箇所を grep 済みだが `_repo_root`/`dirname .. SCRIPT_DIR` 算出ロジックへの直接言及は無し (grep 確認済み、ヒット 0 件) — 内部実装のバグ修正であり公開インターフェース/挙動の説明に変更はない想定。`/code` で念のため最終確認

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `set -euo pipefail` 直後に `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` を追加し (SCRIPT_DIR はスクリプト自身の格納パス解決専用であり repo root 解決には使わない、という区別を示す短いコメントを添える)、Root Cause 表の 8 箇所の代入式右辺を `$REPO_ROOT` に置き換える (変数名 `_repo_root`/`repo_root`/`_REPO_ROOT` 自体は変更しない) (→ 受入条件 AC1, AC2, AC3)
2. `tests/run-auto-sub.bats` の `$MOCK_DIR/git` モック定義 14 箇所 (`grep -n '\$MOCK_DIR/git' tests/run-auto-sub.bats` で列挙可能) に `rev-parse --show-toplevel` ケースを追加し `$BATS_TEST_TMPDIR` を echo するようにする (既存モックはこの呼び出しに対して未定義の catch-all `exit 0` で空文字を返すため、Step 1 の変更後は `REPO_ROOT` が空文字列になり `docs/spec/issue-42-test.md` 等の既存アサーションが壊れる) (after 1) (→ AC2 の回帰防止)
3. `docs/spec/issue-268-recovery.md` を削除し、`docs/reports/orchestration-recoveries.md` から `## 2026-07-09 08:44 UTC: code-patch-tier3-recovery` セクション全体 (`Issue #268, phase: code-patch` を含む) を削除する (→ 受入条件 AC4=Post-merge)
4. `bats tests/` (フルスイート — `tests/auto-sub-observability.bats` が `run-auto-sub.sh` の挙動に依存するクロスファイルテストカップリングがあるため、narrow scope ではなくフルスイートで確認する) を実行し、Step 1-2 の変更が既存テストを壊していないことを確認する (after 1, 2) (→ AC2 の検証)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh 等リカバリ系スクリプトが Spec 更新コミットを作成・push する際の CWD / git remote 解決ロジックについて、原因調査の結果が記録されている" --> リカバリ sub-agent が Spec 更新コミットを作成・push する際の CWD / git remote 解決ロジックの原因が特定されている
- <!-- verify: rubric "scripts/run-auto-sub.sh の _repo_root 算出ロジックが、スクリプト自身の格納パス (dirname \"$SCRIPT_DIR\") からではなく、呼び出し元の実際の作業ディレクトリ (git rev-parse --show-toplevel 等) から算出されるよう修正されている" --> 対象プロジェクトリポジトリ以外への誤 push が発生しないよう修正されている
- <!-- verify: grep "git rev-parse --show-toplevel" "scripts/run-auto-sub.sh" --> `_repo_root` が CWD ベースの git ルート解決ロジックに置き換えられている (補助チェック)
- <!-- verify: command "bats tests/" --> 既存テストスイート (`tests/run-auto-sub.bats`、クロスカップリングのある `tests/auto-sub-observability.bats` を含む) が全て PASS する (Spec 追加項目 — Issue body には無いが `run-auto-sub.sh` は他テストからも参照される挙動変更のため full suite で確認する。この追加によりカウントが Issue body の Pre-merge 項目数と一致しない)

### Post-merge

- <!-- verify: file_not_exists "docs/spec/issue-268-recovery.md" --> <!-- verify-type: auto --> 誤って `saitoco/wholework` に作成された recovery Spec ファイルがクリーンアップされている
- <!-- verify: file_not_contains "docs/reports/orchestration-recoveries.md" "Issue #268, phase: code-patch" --> <!-- verify-type: auto --> `orchestration-recoveries.md` の誤エントリがクリーンアップされている

## Notes

- **Issue body 側 AC3 との差分**: Issue body の Post-merge AC3 は当初 `<!-- verify-type: manual -->` (「該当する場合」という条件付き記述、`/issue` 時点では対象ファイル未特定) だったが、本 Spec 作成時の調査で対象ファイルを具体的に特定できたため (`docs/spec/issue-268-recovery.md` と `docs/reports/orchestration-recoveries.md` の該当エントリ)、`modules/verify-patterns.md §11` の「manual を自動化可能な verify command に置き換える」指針に従い `file_not_exists` / `file_not_contains` による `verify-type: auto` の 2 項目に置き換えた。Issue body 側もこの内容で更新する。
- **Pre-merge 検証項目数の不一致について**: Issue body の Pre-merge AC は 3 件だが、本 Spec の Pre-merge 検証は 4 件 (`bats tests/` によるフルスイート確認を追加)。`run-auto-sub.sh` は `tests/auto-sub-observability.bats` からもクロス参照される挙動変更 (`modules/verify-patterns.md §24`) であり、Step 2 のテストモック修正が正しく機能することを確認する目的で追加した。Issue body 側のカウント不一致は許容 (SKILL.md の Count alignment check は warning-and-continue 方針)。
- **`_write_manual_recovery_to_spec` の早期リターン経路への配慮**: `--write-manual-recovery` サブコマンドは `SCRIPT_DIR` (153 行目) 到達前の早期分岐 (112-120 行目) で `exit 0` するため、新設する `REPO_ROOT` はこの早期分岐より前 (`set -euo pipefail` 直後) に計算する必要がある。
- **#962 との重複整理は本 Issue のスコープ外**: `scripts/append-consumed-comments-section.sh` の同型パターン修正は #962 側で独立に対応する。
- **`_repo_root` 修正の設計判断**: 8 箇所の個別 inline 修正ではなく、グローバル `REPO_ROOT` 一箇所に集約する設計を採用。理由: (1) AC3 の補助チェック `grep "git rev-parse --show-toplevel"` は文字列が1回でも存在すれば PASS するため集約で十分、(2) 変数名 (`_repo_root`/`repo_root`/`_REPO_ROOT`) は変更せず代入式右辺のみ差し替えることで既存の参照箇所すべてに影響を波及させずに済み、diff サイズと回帰リスクを最小化できる。
- **テストモックへの影響範囲の根拠**: `tests/run-auto-sub.bats` の `$MOCK_DIR/git` モック実装を実際に読み込んで確認した結果、14 箇所の custom git mock がいずれも `rev-parse --show-toplevel` を未処理のまま catch-all `exit 0` (空文字出力) を返すことを確認した。この分析に基づき Implementation Step 2 を設計した。

## Code Retrospective

### Deviations from Design
- Implementation Steps 1・3・2 の順でコミットを分割した (Spec は Step 番号順の単一コミットを想定していないため計画通り)。Step 4 (`bats tests/` フルスイート) はコミット後にまとめて実行し、Step 2 のコミットメッセージに `(closes #966)` を付与して patch route の closing commit とした。

### Design Gaps/Ambiguities
- None

### Rework
- `run-code.sh` の実行が外部要因 (バックグラウンドタスクの停止) により中断され、`tests/run-auto-sub.bats` の未コミット修正と `bats tests/` フルスイート未実行の状態で worktree が取り残された。`/auto` 親セッションが Tier 1 (reconcile-phase-state.sh) で状態を確認した上で、残作業 (bats 実行確認・コミット・Code Retrospective 追記) を手動リカバリとして完了させた。詳細は Issue #966 の Auto Retrospective (`run-auto-sub.sh --write-manual-recovery` により記録) を参照。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Root Cause 表の8箇所を個別修正せず、グローバル `REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` 一箇所に集約する設計を採用 (Spec の設計判断どおり)
- テストモック側の `rev-parse --show-toplevel` ハンドラは既存の `$MOCK_DIR/git` カスタムモック14箇所すべてに追加し、`$BATS_TEST_TMPDIR` を返すことで既存アサーションとの整合を維持
- patch route の closing commit (`closes #966`) はテストモック修正コミット (Step 2) に付与し、本体 fix コミット (Step 1) とは分離したまま維持

### Deferred Items
- #962 (`append-consumed-comments-section.sh` の同型パターン修正) との重複整理は本 Issue のスコープ外のまま据え置き (Spec Notes 記載どおり)
- Post-merge AC (誤 push ファイルのクリーンアップ) は `docs/spec/issue-268-recovery.md` の削除と `orchestration-recoveries.md` のエントリ削除としてすでに Step 3 で実施済みだが、他プロジェクトの誤 push ファイルが他にも存在しないかの網羅的な横断確認は行っていない (本 Issue のスコープは wholework 自身のリポジトリ内で確認済みのファイルに限定)

### Notes for Next Phase
- `bats tests/` フルスイートは exit code 0 / not ok 0件で PASS 済み (`.tmp/bats-full-966.log` に記録、`.tmp/` は gitignore 対象のためコミットには含めない)
- verify フェーズでは Post-merge AC の `file_not_exists`/`file_not_contains` の自動検証に加え、Pre-merge の rubric 系検証 (原因特定・修正内容の適合性) も確認すること

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| code  | patch | SUCCESS (manual recovery) | `run-code.sh` background task stopped externally mid-run; parent session completed remaining work (bats run confirmation, test-mock commit, Code Retrospective, worktree merge) manually |
| verify | -    | SUCCESS | All 5 acceptance conditions PASS on first attempt |

### Orchestration Anomalies
- `run-code.sh`'s internal auto-retry (silent no-op detection) fired once, then its second-attempt stale-worktree cleanup failed (`Failed to remove stale worktree` / `Failed to delete stale branch`) because the worktree carried an administrative `git worktree lock` from the first session that was never released (the session ended via external background-task termination rather than the normal exit path). The parent `/auto` session subsequently lost visibility into the retry attempt (background task reported `killed`/`stopped`), requiring manual reconciliation: `git worktree unlock` → merge via `worktree-merge-push.sh` → cleanup.

### Manual recovery (code-patch)
- **Date**: 2026-07-09 14:48 UTC
- **Issue**: #966, phase: code-patch
- **Source**: parent session manual recovery
- **Recovery type**: background-task-killed-manual-completion
- **Outcome**: success

### Improvement Proposals
- See `## Verify Retrospective` → `### Improvement Proposals` (filed as #969: `run-code.sh` stale worktree cleanup should call `git worktree unlock` before `git worktree remove --force`).

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Triage (Type=Bug, Size=S, Value=4) は妥当。#962 (`append-consumed-comments-section.sh` の同型パターン) を重複候補として issue コメントで報告しつつ自動クローズしなかった判断は適切 (対応方針の決定を `/code` 時に委ねている)。

#### spec (design)
- 独立した `## Spec Retrospective` セクションは記録されていないが、Root Cause 表で8箇所すべてを列挙し、`worktree-merge-push.sh` の既存パターン (`git rev-parse --show-toplevel`) を修正方針として明示した設計は的確だった。Post-merge AC を `verify-type: manual` から `file_not_exists`/`file_not_contains` の `verify-type: auto` に更新した判断も適切 (実際に本 verify で両方 PASS 確認できた)。

#### code
- 実装内容 (8箇所の `$REPO_ROOT` 統一、テストモック14箇所の `rev-parse --show-toplevel` 追加、誤 push ファイルの削除) は Spec 通りに完了し、`bats tests/` フルスイート (1115 tests) が exit code 0 / not ok 0件で PASS した。
- **Rework**: `run-code.sh` のバックグラウンドセッションが外部要因 (harness によるバックグラウンドタスクの停止) で中断された。中断前に `run-code.sh` 自身の内蔵 auto-retry (silent no-op 検出) が一度発火していたが、2回目の試行のworktreeクリーンアップが `Failed to remove stale worktree` / `Failed to delete stale branch` で失敗しており (詳細は Improvement Proposals 参照)、結果的に `/auto` 親セッションによる手動リカバリ (bats実行確認・テスト修正コミット・Code Retrospective追記・worktree merge・manual recovery記録) が必要になった。この手動リカバリ自体は上記 `## Auto Retrospective` に既に記録済みのため、verify retrospective としては原因側 (下記 Improvement Proposals) のみを新規記録する。

#### review / merge
- patch route (Size S) のため review/merge フェーズは実行されず、対象外。

#### verify
- Pre-merge rubric 2件・grep 1件・Post-merge file_not_exists/file_not_contains 2件、全5条件が PASS。FAIL/UNCERTAIN なし、auto-retry (verify側) は発火していない。

### Improvement Proposals
- `scripts/run-code.sh` の stale worktree クリーンアップ (178-184行目付近、`run-code.sh` 内蔵 auto-retry が "silent no-op" を検出した際に発火) は `git worktree remove --force "$WORKTREE_PATH"` のみを実行しており、`git worktree unlock` を事前に呼び出していない。セッションが正常な `ExitWorktree`/`worktree-merge-push.sh` の終了経路を通らずに異常終了 (今回のような外部要因によるバックグラウンドタスク停止、クラッシュ等) した場合、セッション開始時に設定された worktree lock (例: `claude session code/issue-N (pid ... start ...)`) が残存したままとなり、`git worktree remove --force` だけではロックを解除できず失敗する (今回実際に `Warning: Failed to remove stale worktree` / `Warning: Failed to delete stale branch` が発生し、2回目の retry 試行は残存 worktree 内でそのまま継続していた)。`git worktree unlock "$WORKTREE_PATH" 2>/dev/null` を `git worktree remove --force` の前に追加することで、異常終了後の retry パスでもクリーンな状態から再開できるようにすべき。
