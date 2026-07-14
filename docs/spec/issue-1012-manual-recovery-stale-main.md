# Issue #1012: run-auto-sub: --write-manual-recovery を stale local main でも記録を失わないよう堅牢化

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / `/issue --non-interactive` の Issue Retrospective コメント (pre-pull 方式採用の Auto-Resolve Log、Size S、Type Bug、Blocked-by なし)。Issue 本文の Auto-Resolved Ambiguity Points セクションと同一内容で、新規情報なし。 / https://github.com/saitoco/wholework/issues/1012#issuecomment-4970951523

## Overview

`run-auto-sub.sh --write-manual-recovery` は、親セッションが Tier 1/2/3 機構外で手動復旧を記録する経路 (`_write_manual_recovery_to_spec` / `_write_manual_recovery_to_recoveries_log`) を持つが、書き込み前に local main (`REPO_ROOT`) を remote と同期しない。直前に別セッションが同一 Issue の Spec や `docs/reports/orchestration-recoveries.md` を merge 済みで local が remote より遅れている場合、commit 後の push が non-fast-forward で拒否され、既存の `_push_with_retry` (fetch+rebase リトライ) も remote 側が同一ファイルの近い箇所を変更していると rebase 競合で失敗し、記録が local commit のまま失われる。両関数の冒頭で `git pull --ff-only` により local main を最新化してから読み書きするよう堅牢化し、既存の `_push_with_retry` はセカンダリのセーフティネットとして維持する。

## Reproduction Steps

1. `run-auto-sub.sh --write-manual-recovery ISSUE spec respawn` 実行前に、別セッションが同一 Issue の `docs/spec/issue-ISSUE-*.md` を変更する PR を merge する (local main は squash commit 未 pull で 1 commit 以上遅れる)
2. `_write_manual_recovery_to_spec` が stale な local 上の Spec ファイルを読み、`## Auto Retrospective` セクションに追記して commit する
3. push が non-fast-forward で拒否される → `_push_with_retry` が `git fetch` + `git rebase` を試みるが、remote 側も同じ `## Auto Retrospective` 近辺を変更しているため rebase が競合し abort する
4. `_write_manual_recovery_to_spec` が WARNING を出力して `return 0` する (記録は local commit のまま未 push)
5. 続く `_write_manual_recovery_to_recoveries_log` も同じ stale な local main 上で同様の commit → push 失敗を繰り返す (実際に #1006 の Spec 記録で発生。session 33265-1783950923)

## Root Cause

`_write_manual_recovery_to_spec` / `_write_manual_recovery_to_recoveries_log` はスクリプト起動時に解決した `REPO_ROOT` (メイン worktree) 上で直接ファイルを読み書きし commit するが、呼び出し前に local main を remote と同期する処理がない。`_push_with_retry` は commit 後の push 失敗時に fetch+rebase でリトライするが、rebase は 3-way マージであり、remote 側が同一ファイルの近い箇所を変更していると自動解決できず abort する。結果として記録は local commit として孤立し、WARNING を出して best-effort で継続する既存設計 (非致命的扱い) のため、呼び出し元は記録喪失に気づかない。

## Changed Files

- `scripts/run-auto-sub.sh`: change — `_push_with_retry` の直後に `_pull_ff_only` ヘルパー (`Usage: _pull_ff_only REPO_ROOT`) を追加し、`_write_manual_recovery_to_spec` (open PR ガード直後) と `_write_manual_recovery_to_recoveries_log` (関数冒頭) の両方でファイル読み書き・commit 前に呼び出す — bash 3.2+ compatible
- `tests/run-auto-sub.bats`: change — remote 側が同一 Spec ファイルを先行更新済み (merge 直後パターン) のケースを再現する回帰テストを追加
- `modules/orchestration-fallbacks.md`: change — `#manual-recovery-spec-write` の Rationale に pre-pull 堅牢化の追記 (Issue #1012 参照)

## Implementation Steps

1. `scripts/run-auto-sub.sh` に `_pull_ff_only` ヘルパー関数を追加する (→ Root Cause, AC1)。`_push_with_retry` の直後 (`_validate_recovery_args` の前) に定義し、シグネチャは `_pull_ff_only REPO_ROOT` (`_push_with_retry` と同型)。本体は `git -C "$repo_root" pull --ff-only` を `if !` で受け、失敗時は stderr に WARNING を出して `return 0` する non-fatal 実装とする (`set -euo pipefail` 下でベア呼び出しにすると pull 失敗時にスクリプト全体が abort するため、必ず `if !`/`||` で捕捉する)。**分解形 (`git fetch origin <branch> && git merge/rebase ...`) ではなく、必ずリテラル文字列 `git pull --ff-only` を使うこと** — 分解すると既存の「push retry: gives up after 3 attempts」テストが `fetch_count`/`rebase_count` を `grep -c "fetch origin main"` / `"rebase origin/main"` で厳密カウント (期待値 2) しているため、余分な 1 件が混入し壊れる。呼び出し箇所は 2 箇所: (a) `_write_manual_recovery_to_spec` の open PR ガード (`if [[ -n "$open_pr" ]]; then ... return 0; fi`) 直後、`local _repo_root="$REPO_ROOT"` の直後 (spec_dir 計算より前)。(b) `_write_manual_recovery_to_recoveries_log` の関数冒頭、`local _recoveries_file=...` の直後、`if [[ ! -f "$_recoveries_file" ]]; then return 0; fi` より前。いずれも pull 失敗時は WARNING を出すのみで、後続の commit/push 処理 (既存の `_push_with_retry` によるフォールバック) にそのままフォールスルーする。
2. `modules/orchestration-fallbacks.md` の `#manual-recovery-spec-write` セクションの Rationale 箇条書き末尾に、stale local main による記録喪失を防ぐため両関数の冒頭で `git pull --ff-only` を実行するようになった旨と Issue #1012 への参照を追記する (after 1)
3. `tests/run-auto-sub.bats` に回帰テストを追加する (after 1) (→ AC2)。既存の「manual recovery: writes Auto Retrospective to spec file」テストと同じ mock 構成をベースに、`git` mock の `pull --ff-only` 分岐で「remote 側が同一 Spec ファイルを先行更新済み」を模擬する副作用 (例: 別フェーズの recovery エントリを `## Auto Retrospective` セクションとして spec ファイルに追記してから exit 0) を実装する。`--write-manual-recovery 42 code push-only` 実行後に (a) `pull --ff-only` が `git` mock ログに記録されていること、(b) 副作用で追記された remote 側エントリと `_write_manual_recovery_to_spec` 自身が追記する `Manual recovery (code)` エントリの両方が最終的な spec ファイルに残っていること (記録喪失なし)、(c) exit status が 0 で `WARNING: could not commit/push` が出力されないこと、を検証する。
4. `bats tests/run-auto-sub.bats` を実行し、新規回帰テストと既存テスト (特に push retry 系の fetch/rebase カウントアサーション) がすべて PASS することを確認する (after 1, 2, 3) (→ AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の --write-manual-recovery 経路が、書き込み前の git pull --ff-only による最新化、または push 失敗時の remote 版への再適用により、stale local main 状態でも記録の push を完遂する実装になっている" --> `--write-manual-recovery` が local main の remote 遅れ (直前 merge の未 pull) 状態でも、Spec / recoveries log の記録を失わず push を完遂する
- <!-- verify: rubric "tests/run-auto-sub.bats に、remote が同一 Spec ファイルを先行更新している状態で --write-manual-recovery が記録を喪失せず完遂することを検証するテストが存在する" --> 同一 Spec ファイルが remote 側で更新済みのケース (merge 直後パターン) の回帰テストが追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> bats テストが PASS する

### Post-merge

- 次回 merge 直後の `--write-manual-recovery` 呼び出しで push が一発成功することを観察

## Notes

- **`git pull --ff-only` は分解形にしない**: `_push_with_retry` の push-failure リトライは `git fetch origin <branch>` + `git rebase origin/<branch>` という分解形を使っており、`tests/run-auto-sub.bats` の「push retry: gives up after 3 attempts」テストがこれらを `grep -c` で厳密カウント (fetch_count/rebase_count = 2) している。新規の pre-pull ヘルパーが同じ文字列パターンの分解形コマンドを発行すると、このカウントに余分な 1 件が混入し既存テストが壊れる。そのため pre-pull は単一コマンドの `git pull --ff-only` を使うこと (Implementation Steps 1 に反映済み)。
- **REPO_ROOT のブランチ想定**: 新規の pre-pull は明示的なブランチ名を指定せず「現在チェックアウト中のブランチ」を対象にする (`git pull --ff-only` 引数なし)。これは既存の `_push_with_retry` の `git push origin HEAD` (同じく現在ブランチを暗黙対象とする) と対称的な設計であり、REPO_ROOT が常に main 相当ブランチをチェックアウトしているという既存コードが既に依拠している前提 (スクリプト冒頭のコメント参照) を継続するのみで、新たな前提を追加するものではない。
- **`modules/orchestration-fallbacks.md#ff-only-merge-fallback` (checkout-less ref-fetch) との違い**: `worktree-merge-push.sh` が使う `git fetch . <from>:<base>` は worktree 分離されたブランチを共有ディレクトリの checkout に触れずマージするためのパターンであり、今回のケース (REPO_ROOT 自身の作業ツリー上のファイルを直接読み書きする必要がある) とは適用シーンが異なる。作業ツリーの実ファイル内容を pull 後に読む必要があるため、working tree を更新する `git pull --ff-only` が適切であり、checkout-less パターンへの統一は不要と判断した。
- **`--ff-only` の外部仕様確認は省略**: `--ff-only` の挙動 (fast-forward できない場合は作業ツリーを変更せず失敗する) は `modules/orchestration-fallbacks.md#ff-only-merge-fallback` で既に本リポジトリ内の確立された前提として扱われており、WebFetch による追加の外部ドキュメント確認は行わなかった。
- **Auto-Resolved Ambiguity Points (Issue #1012 本文より)**: 「書き込み前の pre-pull」vs「push 失敗時の remote 版再適用」の 2 案のうち前者を採用済み (`/issue` フェーズで非対話モード自動解決)。本 Spec はその決定に従う。
- **Steering Docs 更新は不要と判断**: `docs/tech.md` / `docs/workflow.md` (日本語版含む) は `--write-manual-recovery` に言及しているが、いずれも「3 箇所に書き込む」という外部契約レベルの説明に留まり、push 再試行の内部機構には触れていないため、本修正後も記述は正確なまま変更不要 (`grep -l "write-manual-recovery" docs/*.md docs/ja/*.md` で確認)。
