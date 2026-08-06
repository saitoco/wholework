# Issue #1188: verify: 並行セッション稼働下で Step 1/2 が他セッションの作業を破壊しうる経路を塞ぐ

## Overview

`/verify` の Step 1 (dirty ファイル分類) と Step 2 (base branch 更新) は、同一リポジトリで並行セッションが稼働している状況を想定していない。`check-verify-dirty.sh` は、検証対象 Issue とは別の Issue の Spec ファイル (`docs/spec/issue-M-*.md`, M != NUMBER) が dirty な場合、その Issue M が現在アクティブに実行中かどうかを判定せず一律 `unrelated_spec_files` として扱う。この分類は exit 2 (「Stash and continue」/「Abort」の2択のみ) に直結し、稼働中セッションの作業を誤って stash してしまうリスクがある。加えて Step 2 の `git pull origin main` は dirty tree かつ `pull.rebase` 設定下で確定的に失敗する。本 Issue は、(1) `check-verify-dirty.sh` に稼働中セッション検出を追加して非破壊的な分類に倒す、(2) Step 1 の exit 2 分岐に「stash せず続行」の選択肢を追加する、(3) Step 2 の base 更新を dirty tree 耐性のある `fetch` + `merge --ff-only` に置き換える、の3点を実施する。

## Reproduction Steps

1. 複数セッションが並行稼働している状態で、Issue #1156 (`phase/code`, `run-auto-sub.sh 1156 --pr` が稼働中) の Spec ファイル `docs/spec/issue-1156-*.md` が dirty (retrospective 追記途中など) になる
2. 別セッションが Issue #1175 に対して `/verify 1175` を実行する
3. `check-verify-dirty.sh 1175` が dirty ファイル `docs/spec/issue-1156-*.md` を検出し、`file_issue(1156) != NUMBER(1175)` のため `unrelated_spec_files` に分類 → exit 2
4. `skills/verify/SKILL.md` Step 1 の exit 2 分岐が「Stash and continue」「Abort」の2択のみを提示。稼働中の #1156 セッションの作業を破壊しない安全な継続手段がない
5. (欠陥2 再現) 欠陥1を回避して続行した場合、Step 2 の `git pull origin main` が `pull.rebase` 設定下で "cannot pull with rebase: You have unstaged changes" により失敗する

## Root Cause

- `check-verify-dirty.sh` の own-issue-scope/foreign-session 判定は検証対象 Issue 自身の Spec の `## Changed Files` マニフェストのみを参照しており、`docs/spec/issue-M-*.md` (M != NUMBER) 形式の dirty ファイルについて Issue M 自体の実行中状態を見る仕組みを持たない。そのため、稼働中セッションの Spec であっても機械的に `unrelated_spec_files` (exit 2) に落ちる。
- `skills/verify/SKILL.md` Step 1 の exit 2 分岐は「Stash and continue」「Abort」の2択のみで、「無関係だが安全に放置できる」ケースに対応する非破壊的な選択肢がない。
- Step 2 の `git pull origin "${BASE_BRANCH}"` は、dirty な working tree かつ `pull.rebase` 設定下で常に失敗する。取り込むコミットが dirty ファイルに触れない限り安全に更新できるにもかかわらず、`pull` は無条件に失敗する。

## Changed Files

- `scripts/check-verify-dirty.sh`: `unrelated_spec_files` (docs/spec/issue-M-*.md, M != NUMBER) について、Issue M が OPEN かつ `phase/done` 以外の `phase/*` ラベルを持つ場合は既存の `foreign-session` 分類 (non-blocking) に倒す。`gh issue view` 失敗時は現行の `unrelated_spec_files` 扱いにフォールバックする。ヘッダーコメント (L1-29) の分類説明も更新する。bash 3.2+ 互換 (既存の while/read パターンを踏襲、mapfile 不使用)
- `skills/verify/SKILL.md`: Step 1 の exit 2 分岐の AskUserQuestion に「Continue without stashing (stash せず続行)」を3番目の選択肢として追加。Step 2 の `git pull origin "${BASE_BRANCH}"` を `git fetch origin "${BASE_BRANCH}"` + `git merge --ff-only "origin/${BASE_BRANCH}"` に置き換え、失敗時は衝突ファイルを明示するエラーを出す
- `tests/verify-dirty-detection.bats`: 稼働中セッション (OPEN + phase/code 等) の unrelated spec ファイルが `foreign-session` に分類され exit 0 になるケース、および CLOSED / `phase/done` の unrelated spec ファイルが従来どおり exit 2 になるケース (回帰確認) を追加する。`gh` は `tests/reconcile-phase-state.bats` の PATH モックパターンに準拠する ([Steering Docs sync candidate] 既存パターンの直接参照)
- `docs/structure.md`: [Steering Docs sync candidate] Key Files > Scripts の `check-verify-dirty.sh` 一行説明に、phase ラベルベースの稼働中セッション再分類を追記
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー行 (`docs/translation-workflow.md` の同期対象) を同様に更新

## Implementation Steps

1. `scripts/check-verify-dirty.sh` の `unrelated_spec_files` 判定ロジックを変更する。dirty ファイルが `docs/spec/issue-M-*.md` (M != NUMBER) にマッチした時点で即座に `unrelated_spec_files` に追加するのではなく、`gh issue view "$M" --json state,labels` で Issue M の状態を取得し、`state == "OPEN"` かつ `labels` に `phase/*` (`phase/done` を除く) が含まれる場合は `classify=foreign-session` として `has_foreign=true` に倒す (既存の own-issue-scope/foreign-session 判定と同じ非ブロッキング経路に合流させる)。`gh` 呼び出し失敗時は警告を stderr に出し、現行の `unrelated_spec_files` 扱いを維持する (フォールバック方向は Notes 参照)。ヘッダーコメント (L1-29) の exit 2 / foreign-session 説明を更新し、`docs/structure.md` と `docs/ja/structure.md` の該当一行説明も同期する。(→ 受入条件 AC1)
2. `skills/verify/SKILL.md` Step 1 の exit 2 分岐 (現行2択の AskUserQuestion) に「Continue without stashing」を3番目の選択肢として追加する。選択時は `git stash` を実行せず継続する。選択肢の説明文に「表示されている dirty ファイルは検証対象 Issue 自身のスコープ外であり、stash せず放置しても検証には影響しない」旨を明記し、既定/推奨候補として提示する。(→ 受入条件 AC2)
3. `skills/verify/SKILL.md` Step 2 の `git pull origin "${BASE_BRANCH}"` を `git fetch origin "${BASE_BRANCH}"` に続けて `git merge --ff-only "origin/${BASE_BRANCH}"` を実行する形に置き換える (parallel with 1, 2)。`merge --ff-only` が失敗した場合 (取り込むコミットが dirty ファイルに触れる、または履歴が分岐している場合) は git のエラー出力をそのまま提示し、`git stash` または `git commit` を促すエラーメッセージを出す。(→ 受入条件 AC3)
4. `tests/verify-dirty-detection.bats` に2ケースを追加する: (a) unrelated spec ファイルの所有 Issue が OPEN + `phase/code` (mock `gh issue view` で再現) → exit 0, `classify=foreign-session`。(b) unrelated spec ファイルの所有 Issue が CLOSED または `phase/done` → 従来どおり exit 2 (回帰確認)。`gh` のモックは `tests/reconcile-phase-state.bats` の `$MOCK_DIR/gh` + `PATH` 前置パターンに準拠する。(after 1) (→ 受入条件 AC4, AC5)

## Verification

### Pre-merge

- <!-- verify: rubric "check-verify-dirty.sh が、dirty な docs/spec/issue-N-*.md について Issue #N の実行中判定を行い、実行中の場合は stash 対象外の分類に倒す実装になっている" --> 稼働中セッションの spec ファイルが stash 対象外に分類される
- <!-- verify: rubric "skills/verify/SKILL.md Step 1 の exit 2 分岐に、stash せず続行する選択肢が記載されている" --> exit 2 分岐に「stash せず続行」が追加されている
- <!-- verify: grep "merge --ff-only" "skills/verify/SKILL.md" --> Step 2 の base 更新が dirty tree 耐性のある手順になっている
- <!-- verify: rubric "tests/ 配下に、稼働中セッションの dirty spec ファイルが stash 対象外に分類されるケースと、無関係な dirty spec ファイルが従来どおり exit 2 になるケースを区別して検証するテストが存在する" --> 両ケースを区別するテストが追加されている
- <!-- verify: command "bats tests/verify-dirty-detection.bats" --> `verify-dirty-detection.bats` が PASS する

### Post-merge

- 並行セッション稼働下で `/verify` を実行した際、稼働中セッションの spec ファイルに対して stash 選択肢が提示されず、base 更新も失敗しないことを観察する <!-- verify-type: observation event=auto-run session=next when=mode:batch -->

## Notes

- **Issue body との食い違いを自動解決 (Auto-Resolve, 非対話モード)**: Issue 本文 AC5 および `/issue` retrospective コメントは `tests/check-verify-dirty.bats` を本 Issue で新規作成する前提だったが、調査の結果 `check-verify-dirty.sh` を対象とする既存テストファイル `tests/verify-dirty-detection.bats` (18ケース) が既に存在することを確認した。新規ファイルを作成すると同一スクリプトのテストが2ファイルに分散するうえ、`bats tests/check-verify-dirty.bats` という verify command は対象ファイルが存在しないため永久に FAIL する。既存ファイルへのテストケース追加を採用し、Spec 作成と同時に Issue 本文 AC5 の verify command を `command "bats tests/verify-dirty-detection.bats"` へ修正済み (`gh-issue-edit.sh` 実行済み)。`docs/structure.md` の `tests/` ファイル数コメントは変更不要 (新規ファイルではないため)。
- **稼働中セッション判定基準の具体化**: Issue 本文の Auto-Resolved Ambiguity Points で「`phase/*` ラベルを主軸とする」方針は決定済み。本 Spec ではこれを具体化し、「Issue M が OPEN かつ `phase/*` ラベルが存在し、それが `phase/done` ではない」を判定基準とした。理由: `phase/ready` (spec完了・未着手) を含む spec 作成後の全フェーズで Spec ファイルへの retrospective 追記が発生しうるため (`docs/tech.md` の「Cross-phase memory mechanisms」参照)、`phase/issue` (通常は Spec 未作成) 以外の全フェーズを対象とする方が安全側に倒れる。CLOSED または `phase/done` のみ従来の `unrelated_spec_files` 扱いを維持する。
- **`gh` 呼び出し失敗時のフォールバック方向**: ネットワーク障害等で `gh issue view` が失敗した場合、「アクティブと判定できなかった」として現行の `unrelated_spec_files` (exit 2、人間判断を仰ぐ) にフォールバックする。理由: exit 2 到達後も Implementation Step 2 の「Continue without stashing」により安全な継続手段が用意されるため、判定不能時に安全側 (exit 2) に倒れても実害は小さい。逆に「アクティブ」と誤判定して stash 対象外にすると、真に無関係な dirty ファイルが放置されたまま Step 2 以降に進んでしまう方向のリスクの方が大きいため、この優先順位は変更しない。
- `scripts/reconcile-phase-state.sh` が同じ `gh issue view "$N" --json state` / `--json labels` の直接呼び出しパターンを採用しており (`WHOLEWORK_SCRIPT_DIR` 経由のサブスクリプト委譲ではない)、`check-verify-dirty.sh` でも同パターンを踏襲する。bats でのモックは `tests/reconcile-phase-state.bats` の `$MOCK_DIR/gh` 作成 + `PATH` 前置パターンに準拠する (`docs/tech.md` § BATS Mocking Convention)。
- **影響範囲の確認**: `check-verify-dirty.sh` は `/verify` Step 1 だけでなく `run-code.sh` / `run-spec.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` からも dirty guard として呼ばれている。これら5つの wrapper は exit 2 を既に非破壊的に扱っている (`Warning: detected other-session dirty files. Proceeding (best-effort).` を出力して続行、stash はしない) ため、本 Issue の分類変更 (一部の unrelated_spec_files が exit 2 → exit 0 に移る) はこれらの wrapper にとって厳密に安全側の変化であり、追加の変更は不要と判断した。`tests/run-code.bats` 等の既存テストは `check-verify-dirty.sh` 自体を mock で差し替えて wrapper 側のロジックのみを検証しているため、実スクリプトのロジック変更の影響を受けない。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue --non-interactive` によるリファインメント実施記録。Triage 結果 (Type=Bug, Size=M, Value=3)、AC 調整 (post-merge observation AC への `session=next` 追加、AC5 への新規テストファイル注記)、および稼働中セッション判定の主判定材料を `phase/*` ラベル軸とする Auto-Resolve 方針を記録。 / URL: https://github.com/saitoco/wholework/issues/1188#issuecomment-5201465090

### code phase (cutoff: 2026-08-06T08:08:52Z)

No new comments since last phase.
