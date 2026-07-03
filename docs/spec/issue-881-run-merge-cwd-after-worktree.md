# Issue #881: merge: run-merge.sh の後処理が worktree 削除後の CWD 前提で失敗

## Overview

`/auto` の merge フェーズで `scripts/run-merge.sh` を実行すると、squash-merge 自体は成功しているにもかかわらず、wrapper の trailing steps (`emit-event.sh` source、`handle-permission-mode-failure.sh` 呼び出し、`.tmp/auto-events.jsonl` などの相対パス参照) が「No such file or directory」で失敗し、wrapper 全体が exit code 1 を返す false-failure が発生している。原因は `SCRIPT_DIR` が (self-hosted wholework 環境で) リンク worktree 内の絶対パスに解決され、その後の merge/cleanup シーケンスで当該 worktree ディレクトリ自体が削除されるため。本 Issue では `scripts/run-merge.sh` の trailing steps を worktree 削除後の CWD でも安全に実行できるよう修正する。また `run-code.sh` / `run-review.sh` に同種の脆弱性が存在しないか調査し、結果を記録する (修正は別 Issue にスコープ、本 Issue には含めない)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Triage フェーズの Issue Retrospective。Type=Bug・Size=S の判定根拠、AC2 (調査のみに限定するスコープ) の自動解決理由、および Background に記載された `SCRIPT_DIR` (L14)・`emit-event.sh` source (L36)・`handle-permission-mode-failure.sh` 呼び出し (L153) の行番号・内容が現状の `scripts/run-merge.sh` と一致することの事実確認を含む。 (https://github.com/saitoco/wholework/issues/881#issuecomment-4872582710)

## Reproduction Steps

1. `/auto` (または直接 `run-merge.sh $PR_NUMBER`) を、`$0` の解決先が `.claude/worktrees/*/scripts/run-merge.sh` のようなリンク worktree 内パスになる状態で実行する (self-hosted wholework 環境で、先行フェーズの worktree が session 側 CWD として残った状態などで発生し得る)
2. `run-merge.sh` の `SCRIPT_DIR` (L14) がそのリンク worktree 内絶対パスに解決される
3. `claude -p` 子プロセスが `/merge` skill を実行し、squash-merge (`gh pr merge --squash --delete-branch`) と `/merge` 自身の worktree lifecycle (Step 2 Entry → Step 6 Exit) を完了する
4. この過程で、`SCRIPT_DIR` が指すリンク worktree ディレクトリ自体が削除される
5. `claude -p` 呼び出し完了後、`run-merge.sh` の trailing steps (`handle-permission-mode-failure.sh` 呼び出し、`gh-extract-issue-from-pr.sh` 呼び出し、`reconcile-phase-state.sh` 呼び出し、`emit_event` による `.tmp/auto-events.jsonl` 書き込み) が「No such file or directory」で失敗し、squash-merge 自体は成功しているにもかかわらず wrapper が exit code 1 を返す

実際の発生例: Issue #875 の `/auto 875` 実行時、PR #879 の merge フェーズで観測 (詳細は `docs/spec/issue-875-abolish-data-layer-md.md` の Verify Retrospective 参照)。

## Root Cause

`scripts/run-merge.sh` L14 の `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` は `$0` から解決される絶対パスをそのまま採用しているだけで、そのパスの実在性を後続処理の前に再検証しない。self-hosted wholework 環境ではこのパスがリンク worktree 内を指すことがあり、squash-merge + `/merge` 自身の worktree cleanup シーケンス (`claude -p` 子プロセス内、`/merge` skill の Step 2 Worktree Entry → Step 6 Worktree Exit) が完了する過程で当該 worktree ディレクトリが削除される。`claude -p` 呼び出しが返った後、親プロセスである `run-merge.sh` が trailing steps で `$SCRIPT_DIR` 配下の絶対パス参照 (`handle-permission-mode-failure.sh` 等の呼び出し) や CWD 相対パス参照 (`.tmp/auto-events.jsonl`) を実行しようとすると、参照先ディレクトリが既に存在しないため失敗する。squash-merge 自体は正常に完了しているため、これは false-failure であり、Tier 1 (`reconcile-phase-state.sh --check-completion`) による override が毎回必要になっていた。

## Changed Files

- `scripts/run-merge.sh`: L14 (`SCRIPT_DIR=...`) の直後に `MAIN_REPO_ROOT` の早期キャプチャと `cd` フォールバックを追加 — bash 3.2+ compatible
- `tests/run-merge.bats`: worktree 削除後の CWD でも trailing steps が失敗しないことを検証するテストケースを追加 — bash 3.2+ compatible
- `docs/tech.md`: [Steering Docs sync candidate] `run-merge.sh` の説明が最新か確認。本修正は内部の CWD 耐性強化であり、CLI インターフェース (`run-merge.sh <pr-number>`) やモデル/effort 設定に変更はないため、恐らく変更不要
- `docs/structure.md`: [Steering Docs sync candidate] `run-merge.sh` の説明が最新か確認。同上の理由で恐らく変更不要
- `docs/migration-notes.md`: [Steering Docs sync candidate] `run-merge.sh` への言及が最新か確認。インターフェース変更がないため恐らく変更不要
- `docs/ja/tech.md`: [Steering Docs sync candidate] `docs/tech.md` の日本語訳。英語版の変更有無に応じて追従 (恐らく変更不要)
- `docs/ja/structure.md`: [Steering Docs sync candidate] `docs/structure.md` の日本語訳。英語版の変更有無に応じて追従 (恐らく変更不要)
- `docs/ja/migration-notes.md`: [Steering Docs sync candidate] `docs/migration-notes.md` の日本語訳。英語版の変更有無に応じて追従 (恐らく変更不要)

## Implementation Steps

1. `scripts/run-merge.sh` の L14 (`SCRIPT_DIR=...`) 直後に、`MAIN_REPO_ROOT` の早期キャプチャと `cd` フォールバックを追加する (→ 受入条件 AC1)

   ```bash
   SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
   # Capture the main repository root now, before the merge/cleanup sequence
   # below can remove the worktree this script started in. `git worktree
   # list` always lists the main worktree first, even from a linked worktree,
   # and that entry is never a target of `git worktree remove`.
   MAIN_REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')"
   if [[ -n "$MAIN_REPO_ROOT" ]]; then
     cd "$MAIN_REPO_ROOT"
     [[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"
   fi
   ```

   `git worktree list` が失敗する場合 (git リポジトリ外での実行など) は `MAIN_REPO_ROOT` が空文字になり、`if` が false のため既存の挙動 (CWD 変更なし) を維持する。既存 bats テストは `$BATS_TEST_TMPDIR` (非 git ディレクトリ) で実行されるため、この分岐は既存テストの挙動に影響しない。挿入位置は L14 の直後 (`check-verify-dirty.sh` 呼び出しより前) — これにより `check-verify-dirty.sh` (session isolation check) 自体も、CWD がリンク worktree 内にあった場合に本来意図された main repo 視点の `git status` で実行されるようになる副次的な正常化効果もある。

2. `tests/run-merge.bats` に、main repo + linked worktree を実際に構成し (`git init` + `git worktree add`)、mock `claude` が起動直後にその linked worktree を `rm -rf` するシナリオで、`run-merge.sh` の trailing steps (`handle-permission-mode-failure.sh` 呼び出し、`gh-label-transition.sh` 呼び出しなど) が exit code 0 で完走することを検証するテストケースを追加する (→ 受入条件 AC1) (after 1)
   - 既存の `setup()` は `$BATS_TEST_TMPDIR` (非 git) で実行されるため、新規テストケースはテスト内で独自に一時 git リポジトリ + linked worktree を構成し、`run` 呼び出し後は `cd "$BATS_TEST_TMPDIR"` で安全なディレクトリに戻すこと (linked worktree 削除後もテストハーネス自身の CWD が不正にならないようにするため)

3. AC2 の調査結果 (下記 Notes の「AC2 investigation results」参照。`run-code.sh` / `run-review.sh` は `run-merge.sh` と同一の SCRIPT_DIR/CWD 依存パターンを持つことを Spec 作成時点で確認済み) を Issue #881 のコメントとして投稿する (→ 受入条件 AC2) (parallel with 1, 2)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-merge.sh の trailing steps が worktree 削除後のCWDでも失敗しないよう、worktree削除前の絶対パスキャプチャまたは親リポジトリルートへの明示cdで修正されている" --> `scripts/run-merge.sh` の trailing steps (emit-event.sh source、handle-permission-mode-failure.sh 呼び出し、`.tmp/auto-events.jsonl` などの相対パス参照) が、worktree が削除された後の CWD でも失敗しないよう修正されている
- <!-- verify: rubric "run-code.sh と run-review.sh についても worktree削除後のCWD前提による同種の脆弱性がないか確認され、結果がIssueコメントまたはSpecに記録されている" --> 同種の CWD 前提の脆弱性が `run-code.sh` / `run-review.sh` など他の `run-*.sh` wrapper に存在しないか確認され、結果が記録されている

### Post-merge

なし

## Notes

### AC2 investigation results (Spec フェーズで調査済み)

`run-code.sh` と `run-review.sh` を調査した結果、両スクリプトとも `run-merge.sh` と **同一の構造的脆弱性パターン** を持つことを確認した。

- **`run-code.sh`**: L49 で同一の `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` パターンを使用。L65 (`AUTO_EVENTS_LOG` 相対パス)、L73 (`AUTO_SESSION_ID` 相対パス)、L75 (`emit-event.sh` source)、L77-95 (EXIT trap `_maybe_emit_phase_complete`)、L271 以降の trailing steps (`handle-permission-mode-failure.sh`、L280 `reconcile-phase-state.sh`、L314 `gh-pr-merge-status.sh` 呼び出し、emit_event 呼び出し) が同様に影響を受け得る。加えて `run-code.sh` 固有の追加リスクとして、L299 の `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` (auto-retry 再実行) が `$0` の絶対パス解決に依存しており、`$0` の指すディレクトリが削除されていた場合はリトライ機構自体が動作しなくなる、より深刻な失敗モードになり得る。`/code` skill 自身も `modules/worktree-lifecycle.md` の Direct Caller であり、Step 2 で `code/issue-N` worktree に Entry、Exit で `push-and-remove` (PR route) または `merge-to-main` (patch route) により worktree を削除するため、`run-merge.sh` と同一の時系列パターン (親 bash プロセスの CWD/SCRIPT_DIR がリンク worktree 内解決 → 子 `claude -p` セッションの worktree 削除 → trailing steps 失敗) が成立し得る。
- **`run-review.sh`**: `run-merge.sh` とほぼ同一の構造 (L16 SCRIPT_DIR、L32/L36 相対パス、L38 `emit-event.sh` source、L40-58 EXIT trap、L152 以降の trailing steps)。`/review` skill も `modules/worktree-lifecycle.md` の Direct Caller として `push-and-remove` Exit を使用するため、同じ脆弱性パターンが成立し得る。

いずれも本 Issue のスコープ (AC1) では **修正しない**。Issue 本文の Auto-Resolved Ambiguity Points の通り、修正は別 Issue として起票する方針とする (Implementation Step 3 でこの調査結果を Issue コメントとして記録)。

### Design rationale

`git worktree list --porcelain` の最初の `worktree` エントリは常に main worktree (削除不可・`git worktree remove` の対象外) を指すため、CWD がどのリンク worktree であっても、そのリンク worktree が後で削除されても、安定した復帰先として利用できる。`git rev-parse --git-common-dir` でも近い結果を得られるが、`.git` が repo root の直下にあるという前提を追加で必要とするため、`git worktree list --porcelain` の方が前提が少なく単純である (self-hosted wholework の `.claude/worktrees/spec+issue-881` から実行して動作確認済み: 最初のエントリが `/Users/saito/src/wholework` になることを確認)。

`WHOLEWORK_SCRIPT_DIR` が設定されている場合 (bats テストの mock 環境) は、既存の `-d "$SCRIPT_DIR"` チェックによりフォールバックは発火しない (mock ディレクトリは削除されないため)。

### Scope boundary confirmation

triage retrospective (Issue #881 コメント、Consumed Comments 参照) で、Background 記載の行番号・内容 (`SCRIPT_DIR` L14、`emit-event.sh` source L36、`handle-permission-mode-failure.sh` 呼び出し L153) が現状の `scripts/run-merge.sh` と一致することが確認済み。

## Code Retrospective

### Deviations from Design

- Implementation Step 1 のコード片に `|| true` を追加した。Spec 記載のままの `MAIN_REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '...')"` を `set -euo pipefail` 環境下でそのまま実装すると、git リポジトリ外 (既存 bats テストの `$BATS_TEST_TMPDIR` など) で `git worktree list` が非ゼロ終了した際、`pipefail` によりパイプライン全体が失敗扱いになり、`set -e` によりコマンド置換を含む変数代入文全体でスクリプトが異常終了する (bash の既知の挙動: `VAR=$(failing_pipeline)` は `set -e` 下で代入自体の失敗として中断要因になる)。この回帰で既存 `tests/run-merge.bats` 24 件が exit code 不一致で failing した。`|| true` を式全体の末尾に付与することで、git リポジトリ外実行時も `MAIN_REPO_ROOT=""` となり既存の分岐 (`if [[ -n "$MAIN_REPO_ROOT" ]]`) が正しく機能するよう修正した。
- Implementation Step 2 のテストシナリオを、Spec 記載の「mock claude が起動直後に linked worktree を rm -rf する」という時系列から、「run-merge.sh 起動前に (別プロセス・別フェーズの cleanup によって) 該当 worktree が既に削除されている」という時系列に変更した。理由は Design Gaps/Ambiguities を参照。

### Design Gaps/Ambiguities

- `[[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"` のフォールバック判定は、L14 直後 (`claude` サブプロセス起動より大幅に前) で一度だけ評価される。そのため「`claude` サブプロセスの実行中に (そのサブプロセス自身の worktree cleanup によって) SCRIPT_DIR が指す worktree が削除される」という時系列では、判定時点ではまだ worktree が存在するためフォールバックが発火せず、`SCRIPT_DIR` は削除予定の worktree パスを指したままになる。この場合、claude サブプロセス終了後の `"$SCRIPT_DIR/handle-permission-mode-failure.sh"` 等の絶対パス参照は依然として失敗し得る (一方 `cd "$MAIN_REPO_ROOT"` によるカレントディレクトリの安定化は、この時系列でも常に有効に働く)。今回の実装で確実に修正されるのは (a) CWD 相対パス参照 (`.tmp/auto-events.jsonl` 等) と、(b) `run-merge.sh` 起動前に SCRIPT_DIR が既に無効だったケース、の 2 パターン。「claude サブプロセス実行中に SCRIPT_DIR 自身が削除される」パターンへの対応が必要な場合は、`claude` 起動直前に `[[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"` を再評価するなどの追加対応を要する可能性がある。#887 (run-code.sh / run-review.sh の同種修正) 着手時に、この時系列差分を踏まえて設計を検討すること。
- 上記の理由により、Implementation Step 2 のテストは Spec 記載の「claude 実行中に rm -rf」ではなく「run-merge.sh 起動前に worktree 削除済み」のシナリオで実装した (`WHOLEWORK_SCRIPT_DIR` を削除済み worktree パスに設定してから起動)。この時系列であれば `[[ -d "$SCRIPT_DIR" ]]` 判定が正しく発火し、`SCRIPT_DIR` が `$MAIN_REPO_ROOT/scripts` にフォールバックされるため、trailing steps を含め全体が exit code 0 で完走することを実際に確認した (修正前のコードでは同テストが `[ "$status" -eq 0 ]` で fail することも確認済み)。

### Rework

- 上記 pipefail 回帰の発覚後、`scripts/run-merge.sh` に `|| true` を追加し、`tests/run-merge.bats` 全 27 件および `tests/` 配下の全 1045 件 (behavioral change 判定により full suite 実行) が pass することを再確認した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec 記載のコードに `|| true` を追加した (`set -euo pipefail` 下での `git worktree list` 失敗によるスクリプト全体異常終了を防止するため)。詳細は Code Retrospective の Deviations from Design を参照。
- AC1 検証は `tests/run-merge.bats` への実テストケース追加で行い、修正前のコードでは実際に `[ "$status" -eq 0 ]` が fail することを確認した上でテストの有効性を担保した。
- AC2 は Spec Notes に既にあった調査結果を Issue #881 のコメントとして再掲し、発見した `run-code.sh` / `run-review.sh` の脆弱性修正を follow-up Issue #887 として切り出した。

### Deferred Items
- `run-code.sh` / `run-review.sh` の同種脆弱性の修正は Issue #887 に切り出し済み (本 Issue のスコープ外)。
- 「claude サブプロセス実行中に SCRIPT_DIR 自身が削除される」時系列への対応 (Design Gaps/Ambiguities 参照) は本 Issue では未対応。#887 着手時に設計を検討する必要がある。

### Notes for Next Phase
- `/review` フェーズでは、`scripts/run-merge.sh` の `|| true` 追加箇所が Spec のコード片と異なる点をレビュー観点として認識しておくこと (Design Gaps/Ambiguities に理由を記載済み)。
- `tests/run-merge.bats` の新規テストケース名は `worktree-recovery: SCRIPT_DIR pointing at a removed worktree falls back to main repo and completes trailing steps`。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- `run-spec.sh` (`claude -p` サブプロセス) 実行中、worktree セッション内で親リポジトリ絶対パスを使った Write が発生し、ファイルが誤って親リポジトリ側に配置される事故が発生した (spec フェーズ完了報告の補足に記載)。即座に検知・自己復旧され、最終的な commit/push には影響していない。
- 特筆すべき点: この事故は Issue #860 (`scripts/hook-worktree-path-guard.sh` による PreToolUse hook structural block) が既に main にマージ済み (2026-07-03T03:34:34Z、本 spec フェーズ開始 (2026-07-03T04:27Z 頃) より前) の状態で発生している。本来この hook が block するはずのパターンであり、`claude -p` サブプロセス実行環境で hook が意図通り機能していない可能性がある (plugin キャッシュの版ずれ、`claude -p` 起動時の hooks.json 読み込みタイミング等の仮説はあるが未検証)。

#### design
- (観察なし)

#### code
- 上記 Code Retrospective 記載の pipefail regression rework 以外に特筆すべき観察なし。

#### review
- (patch route のため review フェーズなし)

#### merge
- (patch route のため merge フェーズなし)

#### verify
- 観察なし。AC1/AC2 とも一発 PASS。

### Improvement Proposals
- Issue #860 の `hook-worktree-path-guard.sh` が `run-spec.sh` / `run-code.sh` / `run-review.sh` 等が起動する `claude -p` サブプロセスセッションで実際に発火しているか調査する。発火していない場合、原因 (plugin キャッシュ版ずれ、hooks.json 読み込みタイミング、`${CLAUDE_PLUGIN_ROOT}` 解決の違い等) を特定し、必要な修正を行う。今回は自己検知・復旧により実害はなかったが、hook が効いていないとすれば #860 の structural enforcement が `claude -p` 経由の全フェーズで無効化されていることになり、影響範囲は広い。
