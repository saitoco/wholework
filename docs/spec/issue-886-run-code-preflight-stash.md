# Issue #886: run-code: auto-retry 前に parent-main untracked file を preflight stash

## Overview

`run-code.sh` の auto-retry (`auto-retry-on-fail.enabled: true` かつ `autonomy: L2/L3`) は、silent no-op 検出時に `exec bash "$0" ...` で自身を再実行する。この再実行は `check-verify-dirty.sh` の呼び出し (script 冒頭) を再度通過するため、silent no-op の副産物として parent-main に残った untracked file があると `check-verify-dirty.sh` が exit 1 (`has_other=true` 分岐) となり、"Error: parent main has uncommitted changes. Resolve before proceeding." で retry 自体が abort する。auto-retry は「silent no-op を挽回する」ための機構であるにもかかわらず、その副産物 (stray file) 自体が次の試行を機械的にブロックする設計上の矛盾があった。

本 Spec は Issue 提案の Option A (preflight で stray untracked file を stash へ退避) を採用しつつ、コードベース調査で判明した安全上のギャップ (Notes 参照) を修正した設計を採る: stash 対象から `docs/sessions/**` (他の並行セッションが書き込み中の未コミット L3 session retrospective) を明示的に除外する。

## Reproduction Steps

1. `.wholework.yml` に `autonomy: L2` または `L3`、`auto-retry-on-fail.enabled: true` を設定した環境で `/auto` (または `run-code.sh` 単体) が code phase を実行する。
2. claude subprocess が silent no-op (exit 0 だが `reconcile-phase-state.sh` が `matches_expected:false` を返す状態、例: commit のみで push 未実行) となり、その副産物として parent-main root に untracked file を残す (実例: Issue #876 の silent no-op で残った `docs/ja/reports/claude-sonnet-5-impact-strategy.md`)。
3. `run-code.sh` の reconcile チェックが `matches_expected:false` を検出し、`AUTO_RETRY_ENABLED=true` かつ `CODE_RETRY_COUNT < AUTO_RETRY_MAX_ITERATIONS` の条件を満たすため `CODE_RETRY_COUNT` をインクリメントして `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` で再実行する。
4. 再実行された `run-code.sh` の冒頭で `check-verify-dirty.sh` が手順2の untracked file を再検出する。この file は `docs/spec/issue-N-*.md` の unrelated spec file パターンに一致しないため `has_other=true` となり exit 1 → "Error: parent main has uncommitted changes. Resolve before proceeding." で abort する。

## Root Cause

`check-verify-dirty.sh` の呼び出し箇所 (`scripts/run-code.sh` 冒頭、line 51-53) は初回実行・retry 再実行のいずれでも共通して通過する、単一の呼び出しである。`exec bash "$0" ...` によるリトライ再実行 (line 301) はプロセスを丸ごと置き換えて `run-code.sh` を最初から実行し直すため、この共通呼び出し箇所を再度通過する。

silent no-op は「claude が exit 0 で終了したが、期待される commit/push などの完了シグネチャに一致しない」状態であり、その過程で意図せず parent-main に untracked file を書き残すことがある (例: Issue #876 のケース)。この stray file は初回実行時の `check-verify-dirty.sh` (silent no-op の *前* に通過済み) には影響しないが、retry 再実行時の `check-verify-dirty.sh` (silent no-op の *後* に通過) には影響し、`has_other=true` (`docs/spec/issue-N-*.md` 以外の parent-main dirty file が1つでもあれば true) の分岐で exit 1 となる。

auto-retry は「silent no-op から自動的に回復する」ための機構だが、silent no-op 自身が生んだ副産物によって次の retry 試行が機械的にブロックされる — 回復機構が自らの回復対象によって無効化される設計上の矛盾が根本原因である。

## Changed Files

- `scripts/run-code.sh`: `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` の直前に、parent-main の stray untracked file を stash へ退避する preflight ブロックを追加 — bash 3.2+ compatible
- `tests/run-code.bats`: 上記 preflight が発火し retry が成功するシナリオの test case を追加 — bash 3.2+ compatible
- `docs/tech.md`: [Steering Docs sync candidate] 「code-side auto-retry (silent no-op)」の記述 (§ Architecture Decisions) に preflight stash ステップの言及を追加するか確認
- `docs/ja/tech.md`: [Steering Docs sync candidate] 上記日本語ミラー (`docs/translation-workflow.md` 準拠、docs/tech.md を更新する場合のみ)

## Implementation Steps

1. `scripts/run-code.sh` の auto-retry ブロック内、`emit_event "code_retry_fire" ...` の呼び出しブロックの直後、`exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` の直前に、以下の preflight ブロックを追加する:
   ```bash
   _STRAY_UNTRACKED=$(git ls-files --others --exclude-standard -- ':!docs/sessions/**' 2>/dev/null | head -5)
   if [ -n "$_STRAY_UNTRACKED" ]; then
     echo "auto-retry preflight: stashing parent-main untracked files: $_STRAY_UNTRACKED" >&2
     git stash push --include-untracked -m "auto-retry preflight for #$ISSUE_NUMBER" -- ':!docs/sessions/**' 2>/dev/null || true
   fi
   ```
   `-- ':!docs/sessions/**'` パススペックは、他の並行セッションが書き込み中の未コミット `docs/sessions/*-*/*` (L3 session retrospective) を stash 対象から除外するためのもの (Notes 参照)。CWD は script 冒頭から一貫して parent-main root のため `cd` や新規変数は不要 (Issue の Auto-Resolved Ambiguity Points を踏襲)。stash 失敗時も `|| true` で retry を継続する (best-effort、double-fail 防止)。 (→ acceptance criteria AC1, AC2)
2. `tests/run-code.bats` に、parent-main に stray untracked file がある状態で auto-retry が preflight stash を経由して成功する test case を追加する。既存の「auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry」テストの `RETRY_COUNTER_FILE` パターン (`reconcile-phase-state.sh` mock が1回目は `matches_expected:false`、2回目以降は `matches_expected:true` を返す) を土台にし、追加で次の3点を mock する: (a) `$MOCK_DIR/claude` が1回目の呼び出し時のみ stray file (例: `$BATS_TEST_TMPDIR/stray-output.md`) を作成する、(b) `$MOCK_DIR/check-verify-dirty.sh` がその stray file の存在有無で exit 0/1 を切り替える (存在すれば exit 1, 存在しなければ exit 0)、(c) `$MOCK_DIR/git` が `ls-files --others --exclude-standard` サブコマンドで stray file 名を返し、`stash push` サブコマンドで stray file を削除しつつ呼び出しログを記録する。アサーション: `run bash "$SCRIPT" 123 --pr` の `status -eq 0`、`output` に `"auto-retry preflight: stashing parent-main untracked files"` を含む、git stash 呼び出しログファイルが存在する。 (after 1) (→ acceptance criteria AC3)
3. `docs/tech.md` の「code-side auto-retry (silent no-op)」記述 (§ Architecture Decisions) に、preflight stash ステップの追加を簡潔に反映する。反映する場合は `docs/translation-workflow.md` の Sync Procedure に従い `docs/ja/tech.md` の対応行も同期する。 (parallel with 1, 2)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-code.sh" "auto-retry preflight" --> `scripts/run-code.sh` の auto-retry 再実行 (`exec bash "$0"`) 直前に parent-main untracked file の preflight stash 処理が追加されている (Option A)
- <!-- verify: rubric "scripts/run-code.sh の auto-retry preflight ブロックは parent-main untracked file を stash push --include-untracked で退避し、terminal に log line を出す" --> preflight stash が発火した場合、terminal に「auto-retry preflight: stashing parent-main untracked files: ...」の log line が出力される
- <!-- verify: rubric "tests/run-code.bats (または新規 tests/*preflight*.bats) に parent-main に untracked file がある状態で auto-retry が preflight stash 経由で成功する test case が含まれる" --> bats test で preflight stash が発火するシナリオを検証

### Post-merge

- 次回 silent no-op → auto-retry 発火時、parent-main untracked file が preflight stash に退避されて retry が続行することを観察 <!-- verify-type: observation event=code-auto-retry-preflight -->

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — `/issue 886` の Issue Retrospective。Type=Bug, Size=S, Value=3 の triage 結果、および (1) preflight 挿入位置を「exec 再実行直前」に、(2) parent-main 参照方法を CWD 直接操作に、それぞれ auto-resolve した根拠を記録 (いずれも Issue body の `## Auto-Resolved Ambiguity Points` に既に反映済み)。 (https://github.com/saitoco/wholework/issues/886#issuecomment-4874224286)

## Notes

- **stash 対象の安全範囲を Issue 原文の擬似コードから修正**: Issue 本文の Option A 擬似コードは `git ls-files --others --exclude-standard` (除外パスなし) で検出した stray file を、パススペック指定なしの `git stash push --include-untracked` で退避する設計だった。コードベース調査の結果、`.claude/worktrees/` は `.gitignore` で除外済み (line 9) のため他 worktree のファイルが誤って巻き込まれるリスクは無いことを確認したが、`docs/sessions/` は `.gitignore` で除外されていないため、並行実行中の別セッションが書き込み中の未コミット `docs/sessions/{SID}-{DATE}/session.md` 等が `git ls-files --others --exclude-standard` の結果に含まれてしまうことを確認した。`check-verify-dirty.sh` 自身は `docs/sessions/*-*/*` を "other-session" として明示的に非ブロッキング扱いする設計であり、その方針と矛盾しないよう、本 Spec では `git ls-files` と `git stash push` の両方に `-- ':!docs/sessions/**'` パススペック除外を追加した。この除外構文の実際の挙動は分離したサンドボックス git リポジトリ (git 2.55.0) で実地検証済み: `git ls-files --others --exclude-standard -- ':!docs/sessions/**'` が対象パターンを正しく除外し、`git stash push --include-untracked -- ':!docs/sessions/**'` が `docs/sessions/**` 配下のファイルを working directory に残したまま他の stray file のみを stash することを確認した。
- **Issue 原文の技術的主張の検証**: Issue body の Proposal セクションに記載された次の2点はコードベース調査で正確性を確認済み (齟齬なし): (1) `check-verify-dirty.sh` は `scripts/run-code.sh` 冒頭 (実際の line 51-53) で1回だけ呼ばれ、`exec bash "$0"` によるリトライ再実行時にも同じ呼び出しを再度通過する。(2) `run-code.sh` はこの時点まで実質的に `cd` しておらず (`SCRIPT_DIR` 取得用の subshell 内 `cd` を除く)、`PARENT_REPO_ROOT` のような変数はコードベース全体に存在しない。
- `scripts/check-verify-dirty.sh` は本 Issue のスコープ外であり、変更しない (Issue の Related セクション記載の通り、呼び出し元としての動作は不変)。
- Preflight stash は best-effort。stash 失敗時も `|| true` で retry を継続する (double-fail 防止、Issue Notes 記載の方針を踏襲)。
- stash の cleanup (stash に残った内容の扱い) は本 Issue のスコープ外 (Issue Notes に明記の通り、意図的に stash に残し後で手動確認)。

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1-3 を Spec 記載通りの順序・内容で実装。パススペック除外、preflight 挿入位置、CWD 直接操作方針とも Spec 通り)

### Design Gaps/Ambiguities
- N/A (Spec の Notes セクションで stash 対象の安全範囲、Issue 原文の技術的主張の検証が既に完了しており、実装時に新たな曖昧点は発生しなかった)

### Rework
- N/A

## Autonomous Auto-Resolve Log

- **`closes #886` の記載タイミング**: patch route の Step 8 (Implement) で実装コミットと test/docs コミットを既に作成済みで、いずれのコミットメッセージにも `closes #886` を含めていなかった。Step 11 の該当ルールは「commit 時に `closes #N` を含める」ことを求めるが、Step 8 の中間コミットは複数ステップに分割してコミットする設計のため、どの中間コミットに含めるべきか Spec に明記がなかった。Step 12 (Code Retrospective) のコミットが patch route で push 前の最後のコミットになることから、このコミットメッセージに `(closes #886)` を含めることで、`worktree-merge-push.sh` が main に ff-only merge した際に GitHub の自動クローズが機能するようにした。
  - 理由: patch route は squash されず全コミットがそのまま main に反映されるため、いずれか1つのコミットに `closes #N` が含まれていれば自動クローズは成立する。最後のコミットに含めるのが最も自然で、以降の手順変更を要さない
  - 他候補: Step 8 の実装コミットを `git commit --amend` して `closes #886` を追加 — 却下 (グローバル方針で amend は明示的要求がない限り避けるべきとされているため)

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1, 2 を記載通りに実装 (`scripts/run-code.sh` の preflight ブロック追加、`tests/run-code.bats` へのシナリオテスト追加)。`docs/sessions/**` 除外のパススペックは Spec Notes の安全検証結果をそのまま踏襲した
- Step 3 (docs/tech.md 反映) も実施し、`docs/ja/tech.md` を `docs/translation-workflow.md` の Sync Procedure に従って同期。`check-translation-sync.sh` で `docs/tech.md: IN_SYNC` を確認済み
- 新規 bats テストは既存の "auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry" テストの `RETRY_COUNTER_FILE` パターンを踏襲しつつ、claude/check-verify-dirty.sh/git の3点を追加 mock する構成にした (Spec Implementation Step 2 の指定通り)

### Deferred Items
- Post-merge AC (`次回 silent no-op → auto-retry 発火時の観察`, verify-type: observation) は本 Issue のスコープ外のまま (次回自然発生時に `/verify` で観察)
- stash の cleanup は Issue Notes 記載通りスコープ外のまま、意図的に未対応

### Notes for Next Phase
- Behavioral Change Detection により `scripts/run-code.sh` を参照する他テストファイル (auto.bats 等) が複数存在することを確認、フルスイート (`bats tests/`) を実行し全 1048 件 PASS を確認済み
- 禁止表現チェック (`check-forbidden-expressions.sh`) と skill 構文検証 (`validate-skill-syntax.py`) はいずれも既存の無関係な warning 1件を除き問題なし
- `docs/product.md` など他の翻訳ギャップ (OUTDATED/MISSING_JA) は本 Issue 変更前から存在する既存ギャップであり、本 Issue のスコープ外
