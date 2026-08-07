# Issue #1117: reconcile-phase-state: issue フェーズの completion check が triaged ラベルを見てしまうシグネチャ誤りを修正

## Overview

`scripts/reconcile-phase-state.sh` の `_completion_issue()` は issue フェーズの完了判定 (`--check-completion`) を `triaged` ラベル単独の有無で行っている。しかし `triaged` は triage サブフロー (`/triage`、あるいは `/issue` Step 2/8 の triage 自動チェーン) が付与するラベルであり、`/issue` Step 3 の `gh-label-transition.sh $NUMBER issue` が付与する `phase/issue` とは付与元が異なる別のラベルである。この不一致により、triage が完了しさえすれば `/issue` Step 3 のラベル遷移が失敗・skip されていても completion check が `matches_expected:true` を返してしまう (#1115 で実際に発生)。

`_completion_issue()` の成功シグネチャを、同ファイルの `_completion_spec()` が既に採用しているフェーズラベルファミリー判定 (`phase/(ready|code|review|merge|verify|done)`) と同型のパターン (`phase/(issue|ready|code|review|merge|verify|done)`) に変更し、`run-issue.sh` に既に組み込まれている silent no-op 検出 (#520) がこの種のケースを正しく捕捉できるようにする。

## Reproduction Steps

1. 対象 Issue に対して triage サブフロー (`/triage`、または `/issue` の triage 自動チェーン) が先に実行され、`triaged` ラベルが付与される。
2. `/issue` (`run-issue.sh`) を実行するが、Step 3 のラベル遷移 (`gh-label-transition.sh $NUMBER issue` による `phase/issue` 付与) が何らかの理由で実行されない、または失敗する (#1115 で実際に観測された事象)。
3. `/issue` の実処理 (Step 1〜14 相当) 自体は完了して `claude -p` プロセスが exit 0 で終了し、`run-issue.sh` 内蔵の completion check (`scripts/reconcile-phase-state.sh issue $NUMBER --check-completion`) が実行される。
4. 実際のラベルは `triaged retro/verify` (`phase/issue` 以降のフェーズラベルなし) にもかかわらず、`_completion_issue()` が `triaged` ラベル単独の有無だけを見ているため `matches_expected:true` が返り、silent no-op が検出されない。

## Root Cause

`scripts/reconcile-phase-state.sh:129-142` の `_completion_issue()` が `echo "$labels" | grep -q "^triaged$"` を成功シグネチャとして使用している。`triaged` は triage サブフローが付与するラベルであり、`/issue` Step 3 が付与する `phase/issue` とは付与元が独立したラベルである。そのため「`triaged` は付与済みだが `phase/issue` は未付与」という状態が起こり得るが、現在の実装はこの2つを区別できない。

同ファイルの `_completion_spec()` (181-210行目) は同種の完了判定を `phase/(ready|code|review|merge|verify|done)` というフェーズラベルファミリーの正規表現マッチで行っており、`_completion_issue()` もこのパターンに揃えることで根本的に解消できる。`_completion_issue()` の呼び出し元は `scripts/run-issue.sh:126` の1箇所のみ (grep で確認済み) であり、影響範囲は限定的。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_issue()` (129-142行目) の成功シグネチャを `grep -q "^triaged$"` から `grep -qE '^phase/(issue|ready|code|review|merge|verify|done)$'` に変更し、`_emit_result`/`_handle_mismatch` に渡す診断メッセージをラベルファミリー判定に即した文言に更新する。bash 3.2+ 互換 (同ファイル内の `_completion_spec()` が既に使用している `grep -E` パターンを踏襲するのみで、新規の bash 4+ 構文は導入しない)。
- `modules/phase-state.md`: Phase Table (32行目以降) の `issue` 行の Success Signature 列を `` `triaged` label on issue `` から `` `phase/(issue\|ready\|code\|review\|merge\|verify\|done)` label on issue `` に変更する (36行目)。
- `tests/reconcile-phase-state.bats`: 既存の issue completion テスト2件 (67-95行目) を新シグネチャに合わせて更新し、#1115 の再現ケース (`triaged` のみ付与・`phase/issue` 以降のラベルなし → `matches_expected:false`) を新規追加する。

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` の `_completion_issue()` を修正する。ラベル判定を `echo "$labels" | grep -qE '^phase/(issue|ready|code|review|merge|verify|done)$'` に変更し、`_emit_result`/`_handle_mismatch` の診断メッセージを「issue #${ISSUE_NUMBER} has phase/issue or a later phase label」/「issue #${ISSUE_NUMBER} has no phase/issue or later phase label」相当の文言に更新する (→ acceptance criteria 1)
2. `modules/phase-state.md` の Phase Table `issue` 行の Success Signature 列を新シグネチャ (`phase/(issue|ready|code|review|merge|verify|done)` 形式のラベル判定) の記述に更新する (→ acceptance criteria 2)
3. `tests/reconcile-phase-state.bats` の既存2ケースを更新する (after 1): `"issue completion: triaged label present -> matches_expected true"` は mock ラベルを `phase/issue` + `size/S` に変更しテスト名を新シグネチャに合わせて更新、`"issue completion: triaged label absent -> mismatch (strict exit 1)"` は mock ラベル (`size/S` のみ、`phase/*` なし) を維持しつつテスト名を新シグネチャの表現に更新する。加えて #1115 再現ケース (mock ラベル: `triaged` + `retro/verify`、`phase/issue` 以降のラベルなし → `--strict` で exit 1、`matches_expected:false`) を新規テストとして追加する (→ acceptance criteria 3)
4. `bats tests/reconcile-phase-state.bats` を実行し、更新後の全ケースが pass することを確認する (after 1, 3) (→ acceptance criteria 3)

## Verification

### Pre-merge
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の _completion_issue() が、issue フェーズの完了判定において triaged ラベル単独ではなく、phase/issue 以降のフェーズラベル (phase/issue, phase/ready, phase/code, phase/review, phase/merge, phase/verify, phase/done のいずれか) の有無を成功シグネチャとして使用するよう修正されている" --> `_completion_issue()` の成功シグネチャが `phase/issue` 以降のラベルを判定するよう修正されている
- <!-- verify: section_contains "modules/phase-state.md" "Phase Table" "phase/(issue" --> `modules/phase-state.md` の Phase Table `issue` 行が新しい成功シグネチャ (`phase/(issue|ready|code|review|merge|verify|done)` 形式のラベル判定) を記載している
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> `tests/reconcile-phase-state.bats` が新シグネチャおよび #1115 の再現ケース (`triaged` のみ・`phase/issue` 以降のラベルなし → `matches_expected:false`) を含めて全て pass する

### Post-merge
- triage 済みだが `phase/issue` 未遷移の実 Issue に対して `reconcile-phase-state.sh issue --check-completion` (または `run-issue.sh` の再実行) を行い、`matches_expected:false` として silent no-op が検出されることを本番相当の環境で確認する

## Notes

- `_completion_issue()` の呼び出し元は `scripts/run-issue.sh:126` の1箇所のみ (grep で確認済み)。影響範囲は限定的。
- Background の一部前提 (「issue/spec フェーズに completion check が存在しない」「silent no-op 検出の仕組みがない」) は Issue リファインメント時の追加調査で誤りと判明済み — 該当の仕組み (`_completion_issue()`/`_completion_spec()`、および #520 の wrapper 内蔵 silent no-op 検出) はいずれも既存。本 Issue が修正するのは `_completion_issue()` の判定シグネチャのみであり、新しい仕組みの追加ではない。詳細は Issue body の「追加調査による軌道修正」セクションを参照。
- `docs/spec/issue-314-phase-state-reconciler.md` (reconciler 導入時の Spec) および `docs/spec/issue-1115-review-pending-not-failure.md` (本 Issue の検出元、`## Verify Retrospective` に一次情報あり) は disposable Spec につき更新対象外 (`docs/tech.md` の Spec-first disposable 方針)。
- スコープ外 (Issue body で明示済み): `skills/auto/SKILL.md` Step 3 への reconcile 呼び出し追加、`run-issue.sh`/`run-spec.sh` の wrapper 機構そのものの新規実装、`skills/issue/SKILL.md` のラベル遷移ステップの位置変更。理由は Issue body 参照。
- README.md / docs/workflow.md には `_completion_issue()` の具体的なラベル判定に関する記述がないため、Steering Docs sync candidate には該当しない (grep で確認済み)。

## Autonomous Auto-Resolve Log

- **Proceeded with implementation despite `phase/ready` being absent** — reason: `reconcile-phase-state.sh code-pr 1117 --check-precondition` reported `matches_expected:false` because the Issue's current label is `phase/code` (a later phase than `phase/ready`) rather than `phase/ready` itself, and the precondition check only matches the exact `phase/ready` string. The Spec (`docs/spec/issue-1117-fix-issue-completion-signature.md`) already existed and was fully fleshed out, indicating the `/spec` phase had genuinely completed before this run; the missing `phase/ready` label reflects a label-state artifact from a prior `/code` attempt on this Issue (no PR or remote branch existed), not a missing Spec. Proceeded using the existing Spec as authoritative.
  - Other candidates: hard-abort and request `/spec 1117` be re-run (rejected — Spec content was already complete and directly usable; re-running `/spec` would have been redundant and wasted a session).

## Code Retrospective

### Deviations from Design
- None. Implementation followed the Spec's Implementation Steps and Changed Files list exactly (`scripts/reconcile-phase-state.sh` `_completion_issue()`, `modules/phase-state.md` Phase Table, `tests/reconcile-phase-state.bats`).

### Design Gaps/Ambiguities
- The Spec did not anticipate that this Issue's own label state (`phase/code` present, `phase/ready` absent) would trip the `code-pr` precondition check performed by the very script this Issue modifies (`reconcile-phase-state.sh`). Not a defect in the Spec — the precondition check is a separate code path (`_precondition_code_pr()`) from the one being fixed (`_completion_issue()`); noted here only because it was a self-referential surprise worth recording. See Autonomous Auto-Resolve Log above.

### Rework
- None.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate: all 3 pre-merge acceptance conditions already checked on the Issue; `review_incomplete_fallback` check reported `matches_expected:true` (organic review completion, not fallback-origin) — proceeded without needing an override marker.
- `gh-pr-merge-status.sh` reported `mergeable=true, reason=clean` after two `UNKNOWN` polling retries; no conflicts, squash-merged directly via `gh pr merge --squash --delete-branch`.

### Deferred Items
- The Post-merge AC ("confirm on a real triaged-but-not-phase/issue Issue that `matches_expected:false` is now detected") remains unchecked, carried forward for `/verify` to confirm post-merge.

### Notes for Next Phase
- `/verify` should check whether a real triaged-but-not-`phase/issue` case has occurred naturally rather than fabricating one, per the Post-merge AC.

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1117#issuecomment-5213109567

## review retrospective

### Spec vs. implementation divergence patterns
Nothing to note. `review-light` confirmed the diff matches the Spec's Changed Files and Implementation Steps exactly, with no structural divergence.

### Recurring issues
Nothing to note. This was a narrowly-scoped, single-purpose bugfix (one regex signature change plus matching test/doc updates); no repeated issue patterns observed across the 4 review aspects.

### Acceptance criteria verification difficulty
Nothing to note. All 3 Pre-merge conditions carried well-formed verify commands (`rubric`, `section_contains`, `command`) and resolved cleanly — no UNCERTAIN classifications. The `command` condition resolved via CI reference fallback without ambiguity, since the CI job name ("Run bats tests") unambiguously corresponded to the target test file.

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- **Background の事実主張 2 件が両方とも誤りであることを refinement が検出した**。起票時 (2026-07-31、#1115 の観測起点) の本文は「`reconcile-phase-state.sh` に `issue`/`spec` フェーズの completion check が存在しない」「`skills/auto/SKILL.md` Step 3 は実行後にラベル遷移を検証するステップを持たない」と主張していたが、codebase 調査で両機構とも #314 / #520 で既に実装済みと判明した
- これは「陳腐化した前提」ではなく **起票時点から誤っていた前提**である (#314/#520 は #1117 起票より前に着地済み)。#1127 (`audit`: Issue 本文に書かれた前提条件の失効検出) は失効の検出を扱うため、このケースは射程外
- 結果として真因を「`_completion_issue()` が `phase/issue` ではなく無関係な `triaged` ラベルを成功シグネチャにしている取り違え」と特定でき、スコープが「新規メカニズムの構築」から「1 箇所の正規表現修正 + テスト回帰保護」へ縮小した。タイトルも実態に合わせて更新された
- **この検出は refinement が機能した成功例**として記録する。起票時の前提を実装と突き合わせる手順が働かなければ、存在する機構を二重に作る変更になっていた

#### spec

- スコープ縮小後の Implementation Steps は 1 regex + Phase Table 記載 + bats ケースの 3 点に収まり、Deviations from Design なしで完走した

#### code / review / merge

- 特記なし。review の 4 観点すべてで再発パターンなし、pre-merge AC gate も override marker なしで通過。`gh-pr-merge-status.sh` が `UNKNOWN` を 2 回返した後 `mergeable=true` に落ち着いたが、既存のポーリング機構の範囲内

#### verify

- **post-merge AC (opportunistic) を本 run で確定できた**。Phase Handoff が「実 Issue で自然発生したケースを使い、状態を捏造しないこと」を明示していたため、本リポジトリで triage 後に未着手のまま `triaged` のみになっている #939 を対象にした (ラベル操作なし、read-only 実行)。`matches_expected:false` + 診断文 `has no phase/issue or later phase label` を確認
- 対照として #1063 (`phase/issue`) と #1108 (`phase/verify`) が `true` を返すことも確認し、`^phase/(issue|ready|code|review|merge|verify|done)$` の全域が機能していることを検証した。**PASS 判定の判別力を確保するために対照を取った** — session `11623` の AC 10 誤 PASS (出力の劇的な変化を解釈に合わせて読み、条件と突き合わせなかった) と同型の失敗を避ける意図
- pre-merge 3 件は #1186 の規則で SKIPPED。うち AC3 は `command "bats tests/reconcile-phase-state.bats"` なので、再実行すればフルスイートのコストが発生していた

#### 失敗モードの区別 (誤った推測の訂正を含む)

本 verify の実行中に「`_completion_issue()` のシグネチャ誤りが、2026-08-06 の `run-issue.sh 1119` external kill (#1146 に記録) を検出できなかった原因でもあるのではないか」という推測を立てたが、**これは誤りである**。#1146 のコメントが記録するとおり、当該 kill では wrapper が `run-issue.sh` L114 の実行中に落ちており、`print_end_banner` にも L125-133 の `reconcile-phase-state --check-completion` にも到達していない。completion check が呼ばれていないため、そのシグネチャの正誤は無関係。

2 つは別の失敗モードである:

| 失敗モード | 症状 | 本 Issue の修正で変わるか |
|---|---|---|
| ラベル未遷移の silent no-op (#1115) | wrapper は完走し completion check に到達するが、ラベルが遷移していない | **変わる** — 旧シグネチャは `triaged` present で誤って `true`、新シグネチャは `false` |
| wrapper 自体の external kill (2026-08-06 #1119) | wrapper が completion check 行に到達せず終了、終端バナーも `wrapper_exit` も残らない | 変わらない — check が呼ばれないため |

後者の検出は終端バナーの不在に依存しており、それが #1228 (issue/spec phase の `wrapper_exit` emit 欠落) と #1146 の論点である。

### Improvement Proposals

N/A — 上記の観察はいずれも既存の追跡先があるか、記録のみで足りる:

- 起票時点から誤っていた Background 前提の検出 → refinement が機能した成功例として記録。#1127 は失効検出が射程で本ケースは射程外だが、機構 (`/issue` の codebase 突き合わせ) が働いているため新規起票不要
- 2 つの失敗モードの区別 → 本節に記録。#1228 / #1146 が後者を追跡中
