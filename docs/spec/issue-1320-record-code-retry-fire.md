# Issue #1320: recoveries: auto-retry-on-fail の code_retry_fire を orchestration-recoveries.md に記録

## Overview

`run-code.sh` の `auto-retry-on-fail` が silent no-op を検出してリトライを発火すると `code_retry_fire` イベントが emit されるが、`.tmp/auto-events.jsonl` (gitignore 対象) にしか記録が残らず、`docs/reports/orchestration-recoveries.md` にもSpec にも到達しない。同じ「wrapper 自己リトライ」である `wrapper-retry-on-kill` は既に `run-auto-sub.sh` が `orchestration-recoveries.md` へ記録している。本 Issue はこの非対称を解消し、`code_retry_fire` の発火実績を永続 SSoT に記録する。

Issue 本文の検討候補 (案 A: emit 直前に `run-code.sh` 自身が記録 / 案 B: `/auto` Step 5 の L3 retrospective が事後に記録) のうち、**案 A を採用する**。判断根拠は `## Notes` を参照。

## Changed Files

- `modules/orchestration-fallbacks.md`: `## wrapper-retry-on-kill` セクション (現在 500-531 行、閉じの `---` は 531 行目) の直後、`## external-kill-parent-respawn` (533 行目) の直前に、新規セクション `## auto-retry-on-fail (code_retry_fire)` を追加。bash 3.2+ 互換 (prose のみ、コード変更なし)
- `scripts/run-code.sh`: `_write_code_retry_recovery()` 関数を追加し、既存の `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` 行 (現在 320 行目) の直前で呼び出す。bash 3.2+ 互換
- `tests/run-code.bats`: 新規記録経路のテストケースを追加
- [Steering Docs sync candidate] `docs/tech.md` (`## Architecture Decisions` 内 "code-side auto-retry (silent no-op)" 箇条書き、130 行目付近): `code_retry_fire` の exec ベース再起動を既に説明済み。新設する `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` への相互参照を追加するかは任意 (どの AC からも要求されていない) — `/code` が読んで要否を判断する

## Implementation Steps

1. `modules/orchestration-fallbacks.md` に `## auto-retry-on-fail (code_retry_fire)` セクションを追加する (→ 受入条件 1)。`wrapper-retry-on-kill` セクションと同じ構造 (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) に従い、以下を明示する:
   - **Symptom**: `run-code.sh` が silent no-op (`reconcile-phase-state.sh` の `matches_expected:false`) を検出し、`auto-retry-on-fail` (AUTONOMY_TIER=L2/L3 かつ `auto-retry-on-fail.enabled: true` の場合) が `code_retry_fire` を emit した上で `exec bash "$0" ...` により自己再起動する (`scripts/run-code.sh:308` emit / `:320` exec)
   - **Applicable Phases**: code (patch/pr 両ルート)。`run-code.sh` の呼び出し経路 (`/auto` 単一 Issue の直接ディスパッチ、`run-auto-sub.sh` 経由の XL sub-issue / Batch Mode、単独実行) を問わない
   - **Fallback Steps**: `exec` 直前に `run-code.sh` 自身が `docs/reports/orchestration-recoveries.md` へ `code-retry-fire` エントリを記録し、コミット・プッシュする (Step 2/3 で実装)
   - **Escalation**: なし — リトライ枯渇後のエスカレーションは既存の `code-patch-silent-no-op` (Tier 2/3、475 行目の Fallback Steps 1 が `auto-retry-on-fail` 枯渇済みかどうかを既にチェックしている) がカバーする
   - **Rationale**: `wrapper-retry-on-kill` との非対称の解消であること、`exec` によりリトライ後のプロセスは fresh context になり 1 回目の失敗を観測できないため記録は `exec` 前でなければならないこと、記録主体を `run-auto-sub.sh` の `run_phase_with_recovery()` ではなく `run-code.sh` 自身に置いた理由 (`## Notes` 参照) を記載する
2. `scripts/run-code.sh` に `_write_code_retry_recovery(issue, iteration)` 関数を追加する (→ 受入条件 2, 4)。`scripts/run-auto-sub.sh` の `_write_wrapper_retry_recovery()` (511-577 行目) と同じ python3 heredoc によるマーカー挿入方式で、`docs/reports/orchestration-recoveries.md` の `<!-- Log entries appear below, newest first. -->` 直後に以下の H2 エントリを挿入する:
   - 見出し: `## <UTC日時>: code-retry-fire`
   - `### Context`: `Issue #<issue>`, `phase: <_RECONCILE_PHASE>` (`code-patch`/`code-pr`)、`Source: run-code.sh auto-retry-on-fail`、`Wrapper: run-code.sh, iteration: <iteration>/<AUTO_RETRY_MAX_ITERATIONS>`
   - `### Diagnosis`: `- cause: silent-no-op`、reconcile 結果 (`matches_expected:false` を含む JSON) の要約
   - `### Recovery Applied`: `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire`
   - `### Outcome`: `retry fired (iteration <N>/<M>)` — `wrapper-retry-on-kill` と異なり、本記録はリトライ結果が判明する前 (exec 直前) に書くため、success/escalated ではなく発火の事実のみを記録する
   - `### Improvement Candidate`: `未起票`
   - レポートファイルのパスは `${MAIN_REPO_ROOT:-.}/docs/reports/orchestration-recoveries.md` (`MAIN_REPO_ROOT` は `scripts/run-code.sh` 冒頭で既に計算済み)。ファイルが存在しない場合は何もせず `return 0` (`apply-fallback.sh`/`spawn-recovery-subagent.sh`/`run-auto-sub.sh` の既存 3 実装と同じ skip-if-absent 規約)
3. 同関数内で `git -C "$repo_root" add docs/reports/orchestration-recoveries.md` → `git commit -s -m "Record code_retry_fire recovery for issue #<issue>"` → push-with-retry (`scripts/run-auto-sub.sh` の `_push_with_retry()` 82-103 行目と同じ fetch+rebase 方式、最大 3 回) を行う (→ 受入条件 2, 3)。いずれかのステップが失敗しても `|| true` + stderr 警告に留め、リトライ自体をブロックしない。`_write_code_retry_recovery` の呼び出しは既存の `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` 行の直前に置く (exec で処理が置き換わる前に完了させることで、受入条件 3 の fresh context 制約を構造的に満たす)
4. `tests/run-code.bats` に新規 `@test` を追加する (→ 受入条件 4)。モックされたリポジトリルートに `<!-- Log entries appear below, newest first. -->` マーカーを含む `docs/reports/orchestration-recoveries.md` を作成し、既存の "preflight stashes" テスト (849 行目付近) と同じ `$MOCK_DIR/git` ロギングパターンで `git` をモックした上でリトライ発火シナリオ (`reconcile-phase-state.sh` が 1 回目 `matches_expected:false` を返す) を実行し、(a) ファイルに `code-retry-fire` の H2 エントリが追記されること、(b) 2 回目の `claude` 呼び出し (exec 後) より前に `git add`/`commit`/`push` が呼ばれたことをログから確認する。`docs/reports/orchestration-recoveries.md` を作成しない既存テスト群は本関数が `return 0` で早期終了するため無変更のまま回帰しないことを合わせて確認する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/orchestration-fallbacks.md に auto-retry-on-fail (code_retry_fire) を対象とする独立したパターン節が追加されており、wrapper-retry-on-kill 節と同様に docs/reports/orchestration-recoveries.md への記録主体がどのスクリプトまたは skill ステップであるかが明示されている" --> `orchestration-fallbacks.md` に記録主体を明示した独立節がある
- <!-- verify: rubric "code_retry_fire の発火時に docs/reports/orchestration-recoveries.md へエントリが追記される経路が実装されている (scripts/run-code.sh / scripts/run-auto-sub.sh / skills/auto/SKILL.md のいずれか)。実装は既存エントリと同じ見出し・フィールド構成に従っている" --> 記録経路が実装されている
- <!-- verify: rubric "採用した記録経路が、run-code.sh:320 の exec による自己再起動で fresh context になる制約下でも記録を失わない設計になっている — すなわち記録のタイミングまたは記録主体が、リトライ後のプロセスが 1 回目の失敗を観測できることに依存していない" --> fresh context 制約下でも記録が失われない
- <!-- verify: command "bats tests/run-code.bats" --> `tests/run-code.bats` の既存スイートが回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前 3 項が担う)

### Post-merge

- 次に `code_retry_fire` が発火した session で、対象 Issue のエントリが `docs/reports/orchestration-recoveries.md` に追加されていることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### Auto-Resolved Ambiguity Point: 案 A を採用 (Issue 本文で /spec に委ねられていた判断)

**案 A (emit 直前に `run-code.sh` 自身が記録) を採用し、案 B (`/auto` Step 5 の L3 retrospective が事後に記録) は不採用とする。**

- 理由: `run-auto-sub.sh` の `run_phase_with_recovery()` (`wrapper-retry-on-kill` の記録層、`_write_wrapper_retry_recovery()` の呼び出し元) は **XL sub-issue 実行と Batch Mode の Issue のみを経由**する。`/auto` の単一 Issue 直接ディスパッチ (`skills/auto/SKILL.md` patch/pr ルートの Step、実運用で最も支配的な経路) は `run-code.sh` を Bash tool で直接呼び出しており、`run-auto-sub.sh` を経由しない (`skills/auto/SKILL.md` 409/440 行目)。Issue 本文の案 B の記載「`/auto` を経由が支配的な運用実態を踏まえれば B が軽い」は、この単一 Issue 直接ディスパッチが `run-auto-sub.sh` を経由しないという構造を踏まえていない — 実際には案 B (L3 retrospective または `run_phase_with_recovery()` 層への実装) はこの支配的経路をカバーできず、XL/Batch 経路でしか記録されない
- 案 A は `run-code.sh` 自身に実装するため、単一 Issue 直接ディスパッチ・XL sub-issue・Batch Mode・単独 `run-code.sh` 実行のいずれの呼び出し形態でも一律にカバーする
- 案 A のトレードオフとして Issue 本文が挙げていた「並行セッションとの競合」「worktree からの書き込み経路」は、調査の結果いずれも解消可能と判断した:
  - `run-code.sh` のトップレベル bash コード (`code_retry_fire` の emit と `exec` を含む) は `MAIN_REPO_ROOT` (`git worktree list --porcelain` で事前計算済み) に `cd` した**メインリポジトリ**で実行されており、`/code` の `claude -p` 子プロセスが独自に Enter/ExitWorktree するワークツリーの中では実行されない。したがって `modules/worktree-lifecycle.md` の worktree 書き込みパス制約は該当しない — `run-auto-sub.sh` の `_write_wrapper_retry_recovery()` と全く同じ実行コンテキスト (ラッパースクリプト自身がメインリポジトリで動く) である
  - 並行セッション競合は `scripts/run-auto-sub.sh` の `_push_with_retry()` (fetch + rebase を最大 3 回リトライ) と同じ方式を踏襲することで、既存の Tier 2/Tier 3/`wrapper-retry-on-kill` 記録と同水準の耐性を持たせる

### recoveries-auto-fire (#1179 opt-out) との関係

本リポジトリの `.wholework.yml` は `recoveries-auto-fire.enabled: false` (#1179 により default opt-out) だが、これは `orchestration-recoveries.md` に集積済みのエントリから頻度検知して Issue を自動起票するかどうかのスイッチであり、エントリの記録自体(本 Issue のスコープ) を制御するものではない。`wrapper-retry-on-kill`/Tier 2/Tier 3 の記録がこの設定に関わらず常時行われているのと同様、`code_retry_fire` の記録も無条件で行う。

### allowed-tools impact chain check

`modules/orchestration-fallbacks.md` の変更内容が `scripts/run-code.sh` という `scripts/*.sh` パスを含むため確認した。`modules/orchestration-fallbacks.md` の reader (`grep -rl "modules/orchestration-fallbacks\.md" skills/*/SKILL.md`) は `skills/auto/SKILL.md` と `skills/verify/SKILL.md` の 2 件。両方とも `run-code.sh` は既存スクリプトとして allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*` が既に含まれていることを確認済み (新規追加ではないため)。ギャップなし。

### Symptom-short 命名

新規エントリの H2 見出し (`symptom-short`) は `code-retry-fire` (kebab-case) とする。`wrapper-retry-on-kill`/`code-patch-silent-no-op` の命名規則に合わせた。`scripts/collect-recovery-candidates.sh` は見出しの `UTC: ` 以降を汎用的にパースする実装 (ハードコードされた既知シンボルのリストは持たない) であるため、本追加による同スクリプト側の変更は不要。

## Consumed Comments
No new comments since last phase.
