# Issue #887: code/review: run-code.sh / run-review.sh の trailing steps が worktree 削除後の CWD 前提で失敗する脆弱性の修正

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Triage フェーズの Issue Retrospective。Type=Bug・Size=S の判定根拠と3件の Auto-Resolved Ambiguity Points (trailing steps のスコープ範囲、`exec bash "$0"` auto-retry の scope 外化、Post-merge AC 不要) の記録。内容は既に Issue 本文に反映済みのため、本 Spec への追加アクションなし。 (https://github.com/saitoco/wholework/issues/887#issuecomment-4882442038)

## Overview

`scripts/run-code.sh` と `scripts/run-review.sh` は、precedent Issue #881 (`scripts/run-merge.sh`) で修正済みのものと同一の構造的脆弱性を持つ。`SCRIPT_DIR` が worktree 削除後に無効化されるパスを指したままになり、trailing steps (`emit-event.sh` source、`handle-permission-mode-failure.sh` 呼び出し、`.tmp/auto-events.jsonl` などの CWD 相対パス参照) が「No such file or directory」で失敗する false-failure が発生し得る。#881 で確立済みの修正パターン (`MAIN_REPO_ROOT` の早期キャプチャ + 明示 `cd` + `SCRIPT_DIR` フォールバック) を両スクリプトに適用する。

## Reproduction Steps

1. self-hosted wholework 環境で、`run-code.sh $ISSUE_NUMBER` (または `run-review.sh $PR_NUMBER`) を、`$0` の解決先または `WHOLEWORK_SCRIPT_DIR` がリンク worktree 内パスを指す状態で実行する (先行フェーズの worktree が session 側 CWD として残る、または環境変数が持ち越されるケース)
2. `SCRIPT_DIR` (run-code.sh L49 / run-review.sh L16) がそのリンク worktree内絶対パスに解決される
3. `claude -p` 子プロセスが `/code` (または `/review`) skill を実行し完了する。この前後で、当該リンク worktree ディレクトリが削除される (該当 skill 自身の worktree lifecycle Exit、または先行フェーズの cleanup による)
4. `claude -p` 呼び出し完了後、trailing steps (`handle-permission-mode-failure.sh` 呼び出し、`reconcile-phase-state.sh` 呼び出し、run-code.sh では追加で `gh-pr-merge-status.sh` 呼び出し、`emit_event` による `.tmp/auto-events.jsonl` 書き込みなど) が「No such file or directory」で失敗し、`/code`・`/review` 自体は成功しているにもかかわらず wrapper が exit code 1 を返す

実際の発生パターンは #881 (`run-merge.sh`) と同一。詳細な発生機序は `docs/spec/issue-881-run-merge-cwd-after-worktree.md` の Reproduction Steps / Root Cause を参照。

## Root Cause

`run-code.sh` L49 と `run-review.sh` L16 の `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` は、#881 で修正済みの `run-merge.sh` (修正前) と同一のパターンで、解決した絶対パスの実在性を後続処理の前に再検証しない。self-hosted wholework 環境ではこのパスがリンク worktree 内を指すことがあり、`/code`・`/review` 自身も `modules/worktree-lifecycle.md` の Direct Caller として worktree の Entry/Exit (削除) を行うため、`run-merge.sh` と同一の時系列パターン (SCRIPT_DIR 解決 → worktree 削除 → trailing steps 失敗) が成立し得る。

`run-code.sh` 固有の追加リスクとして L309 の `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` (auto-retry 再実行) があるが、Issue 本文の Auto-Resolved Ambiguity Points の通り本 Issue のスコープ外とする (`$0` の絶対パス解決という別種の失敗モードであり、trailing steps の CWD 安全化では解決しないため)。

## Changed Files

- `scripts/run-code.sh`: L49 (`SCRIPT_DIR=...`) の直後に `MAIN_REPO_ROOT` の早期キャプチャと `cd` フォールバックを追加 (#881 の `scripts/run-merge.sh` 修正と同一パターン。`git worktree list --porcelain` の末尾に `|| true` を付与し `set -euo pipefail` 下での非 git ディレクトリ実行時の異常終了を防止 — #881 Code Retrospective で確認済みの既知の相互作用) — bash 3.2+ compatible
- `scripts/run-review.sh`: L16 (`SCRIPT_DIR=...`) の直後に同一パターンを追加 — bash 3.2+ compatible
- `tests/run-code.bats`: `WHOLEWORK_SCRIPT_DIR` が削除済みリンク worktree を指す状態で trailing steps が exit code 0 で完走することを検証する `worktree-recovery` テストケースを追加。既定の `$MOCK_DIR/git` no-op モックは `worktree` サブコマンドを実装していないため、当該テスト冒頭でのみ `rm -f "$MOCK_DIR/git"` して実 git に戻す — bash 3.2+ compatible
- `tests/run-review.bats`: 同様の `worktree-recovery` テストケースを追加 (git は元々モックされていないため実 git がそのまま使われる) — bash 3.2+ compatible
- `docs/structure.md`: [Steering Docs sync candidate] `run-code.sh`/`run-review.sh` の説明が最新か確認。本修正は内部の CWD 耐性強化でありCLIインターフェースに変更はないため、恐らく変更不要
- `docs/tech.md`: [Steering Docs sync candidate] 同上の理由で恐らく変更不要
- `docs/migration-notes.md`: [Steering Docs sync candidate] `run-code.sh`/`run-review.sh` への言及が最新か確認。インターフェース変更がないため恐らく変更不要
- `docs/ja/structure.md`: [Steering Docs sync candidate] 英語版の変更有無に追従 (恐らく変更不要)
- `docs/ja/tech.md`: [Steering Docs sync candidate] 同上
- `docs/ja/migration-notes.md`: [Steering Docs sync candidate] 同上

## Implementation Steps

1. `scripts/run-code.sh` の L49 (`SCRIPT_DIR=...`) 直後に、`MAIN_REPO_ROOT` の早期キャプチャと `cd` フォールバックを追加する (→ 受入条件 AC1)

   ```bash
   SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
   # Capture the main repository root now, before /code's own worktree
   # lifecycle (Step 2 Entry -> Exit) or a concurrent phase's cleanup can
   # remove the worktree this script started in. `git worktree list` always
   # lists the main worktree first, even from a linked worktree, and that
   # entry is never a target of `git worktree remove`.
   MAIN_REPO_ROOT="$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')" || true
   if [[ -n "$MAIN_REPO_ROOT" ]]; then
     cd "$MAIN_REPO_ROOT"
     [[ -d "$SCRIPT_DIR" ]] || SCRIPT_DIR="$MAIN_REPO_ROOT/scripts"
   fi
   ```

   挿入位置は L49 直後・L50 の `check-verify-dirty.sh` 呼び出しより前 (#881 の `run-merge.sh` と同一の挿入規約)。`git worktree list` が失敗する場合 (bats テストの `$BATS_TEST_TMPDIR` など非 git ディレクトリでの実行時) は `MAIN_REPO_ROOT` が空文字になり `if` が false のため、既存の挙動 (CWD 変更なし) を維持する。

2. `scripts/run-review.sh` の L16 (`SCRIPT_DIR=...`) 直後に、同一のコード片を追加する (→ 受入条件 AC2) (parallel with 1)

3. `tests/run-code.bats` に、main repo + linked worktree を実際に構成し (`git init` + `git worktree add`)、`WHOLEWORK_SCRIPT_DIR` が削除済みの linked worktree を指す状態で `run-code.sh` の trailing steps が exit code 0 で完走することを検証する `worktree-recovery` テストケースを追加する (`tests/run-merge.bats` の同名テストと同一パターンを踏襲。既定の `$MOCK_DIR/git` no-op モックは `worktree` サブコマンドを実装していないため、テスト冒頭で `rm -f "$MOCK_DIR/git"` して実 git に戻し、main repo の `scripts/` には `cp "$MOCK_DIR"/*.sh` でモック一式をコピーする) (→ 受入条件 AC1) (after 1)

4. `tests/run-review.bats` に同様の `worktree-recovery` テストケースを追加する (git は元々モックされていないため `rm -f` は不要) (→ 受入条件 AC2) (after 2, parallel with 3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-code.sh の trailing steps が worktree削除後のCWDでも失敗しないよう、worktree削除前の絶対パスキャプチャまたは親リポジトリルートへの明示cdで修正されている" --> `scripts/run-code.sh` の trailing steps (emit-event.sh source、handle-permission-mode-failure.sh 呼び出し、相対パス参照など) が worktree 削除後の CWD でも失敗しないよう修正されている
- <!-- verify: rubric "scripts/run-review.sh の trailing steps が worktree削除後のCWDでも失敗しないよう、worktree削除前の絶対パスキャプチャまたは親リポジトリルートへの明示cdで修正されている" --> `scripts/run-review.sh` の trailing steps (emit-event.sh source、handle-permission-mode-failure.sh 呼び出し、相対パス参照など) が worktree 削除後の CWD でも失敗しないよう修正されている

### Post-merge

なし

## Notes

### Design rationale (#881 との整合性)

`run-merge.sh` (#881) で確立済みの修正パターンをそのまま適用する。`git worktree list --porcelain` の最初の `worktree` エントリは常に main worktree (削除不可・`git worktree remove` の対象外) を指すため、CWD がどのリンク worktree であっても、そのリンク worktree が後で削除されても、安定した復帰先として利用できる。詳細な設計根拠は `docs/spec/issue-881-run-merge-cwd-after-worktree.md` の Design rationale を参照。

### 既知の残存リスク (#881 Code Retrospective からの引き継ぎ事項への回答)

#881 の Code Retrospective (Design Gaps/Ambiguities) は、「`claude` サブプロセス実行中に、そのサブプロセス自身の worktree cleanup によって `SCRIPT_DIR` が指す worktree が削除される」という時系列が、SCRIPT_DIR 直後の一度きりのフォールバック判定では捕捉できないことを指摘し、本 Issue (#887) 着手時にこの時系列差分を踏まえて設計を検討するよう求めていた。

本 Spec の結論: `cd "$MAIN_REPO_ROOT"` は claude 起動前に一度だけ実行され、以降のスクリプト実行中ずっと CWD として維持される (bash は、退避済みの CWD が後から削除されても影響を受けない) ため、CWD 相対パス参照 (`.tmp/auto-events.jsonl` 等) はこの時系列差分の影響を受けず常に修正される。一方 `$SCRIPT_DIR` を使った絶対パス参照 (`handle-permission-mode-failure.sh` 等) は、フォールバック判定時点で存在していたが claude 起動後に削除されるという狭い時間窓では理論上依然として失敗し得る。ただし、本修正適用後は claude 起動前に CWD が `$MAIN_REPO_ROOT` へ安定化済みのため、`/code`・`/review` 自身が Step 2 Entry で新規作成する worktree は `$SCRIPT_DIR` が指していた既存パスとは別ディレクトリになり、`/code`・`/review` 自身の Step Exit がそのまま `$SCRIPT_DIR` を巻き込んで削除することは無い。残るのは「無関係な並行プロセスが `$SCRIPT_DIR` の指すディレクトリを claude 実行中に削除する」という、#881 の fix でも同程度に許容されている範囲の残存リスクのみと判断する。本 Issue の AC (「絶対パスキャプチャまたは明示cdで修正」) はこの適用範囲で満たされるとみなし、追加対応 (trailing step 実行直前での `$SCRIPT_DIR` 再検証など) が必要になった場合は別 Issue とする。

### Bash 3.2 互換性

#881 で確認済みの `|| true` を含むコード片をそのまま流用する。macOS システム bash (3.2) でも動作する構文のみを使用。
