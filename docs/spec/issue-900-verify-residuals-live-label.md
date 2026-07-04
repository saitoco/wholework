# Issue #900: audit/auto: Verify Phase Residuals が phase=verify イベント不在により常に空を返す構造的欠陥を解消

## Consumed Comments

No new comments since last phase.

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (Step 3)**: Issue #900 のラベルは `triaged`, `phase/code`, `retro/verify` のみで `phase/ready` が存在しなかった (`reconcile-phase-state.sh --check-precondition` も同じ理由で `matches_expected=false` を返した)。ただし Spec (本ファイル) は既に作成済みであり内容も充実しているため、auto-resolve として実行を続行した。`phase/code` ラベルが既に付与されている状態は、直前の `/code` 実行が Step 4 (ラベル遷移) まで到達した後 commit 前に中断した (worktree branch が merge されず破棄された) ことを示唆する。

## Overview

`scripts/get-auto-session-report.sh` の `### Verify Phase Residuals` セクションは、`phase_start`/`phase_complete` (`phase=="verify"`) イベントの差分で残留 Issue を検出する設計だが、`/verify` はラッパーなしの Skill 呼び出しでありこれらのイベントを一切 emit しない。そのため本セクションは実装以来一度も残留を検出したことがない。検出方式を「セッション中に処理された Issue 番号」×「現在の `phase/verify` ラベル状態 (live lookup)」に置き換える。

## Reproduction Steps

1. `/auto --batch` などで複数 Issue を処理するセッションを実行し、少なくとも1件が `phase/verify` ラベルのまま残る状態を作る (実例: 2026-07-03 batch セッション `10389-1783051154` で #883/#885/#886 が `phase/verify` に残置)。
2. `scripts/get-auto-session-report.sh <session-id> --metrics-only` を実行し Metrics セクションを生成する。
3. `### Verify Phase Residuals` が `(none)` と表示されることを確認する — 同じセッションの Summary テーブルの `phase/verify remaining` (`VERIFY_REMAINING`) は 1 以上であるにもかかわらず不一致となり、検出ロジックが live なラベル状態から構造的に切り離されていることが分かる。

## Root Cause

`VERIFY_RESIDUALS` (`scripts/get-auto-session-report.sh:250-259`) は `phase_start(phase=="verify")` 集合と `phase_complete(phase=="verify")` 集合の差分として残留 Issue を計算する。しかし `/verify` は fork なしでユーザーセッション内で実行される wrapper-less Skill であり (`docs/tech.md` fork context 表参照)、`phase=="verify"` を伴う `phase_start`/`phase_complete` イベントをそもそも emit しない。`.tmp/auto-events.jsonl` の全履歴を検索しても `phase=="verify"` のイベントは0件であることが確認されており、両集合は常に空集合 — 差分は常に空となる。したがって本セクションは #667 実装以来、一度も実際の残留 Issue を検出できていない。

## Changed Files

- `scripts/get-auto-session-report.sh`: `VERIFY_RESIDUALS` の計算方式を、`phase_start`/`phase_complete` (`phase=="verify"`) イベント差分から、既存の GitHub state lookups ループ (`FULLY_CLOSED`/`VERIFY_REMAINING` を計算している箇所、現在の行463-480付近) に統合した live `phase/verify` ラベル判定に置き換える。`### Verify Phase Residuals` レンダーブロック (現在の行635-650付近) に `--no-github` 時の明示的な注記分岐を追加する。Metrics 冒頭のキャベア (現在の行586付近) にある「verify phase は計上されない」という記述を、Phase Activity Summary / Sub-Issue Completion Timeline の phase breakdown にのみ当てはまるよう文言を精緻化する (Verify Phase Residuals は本 Issue の修正後は live label 方式で計上されるため)
- `tests/audit-auto-session.bats`: 既存の `"success: verify-type breakdown appears in Verify Phase Residuals section"` テスト (現在の行137-175) は `phase_start(phase="verify")` の合成イベント + `--no-github` に依存しており、本修正後は前提が成立しなくなる (live label 方式では `--no-github` 時は検出不能になる設計のため)。`gh` を `PATH` 経由でモックする方式 (`tests/get-issue-type.bats` と同じ慣習) に書き換え、`--no-github` を外して実際に live label 判定経路を通すよう修正する。ファイル冒頭のコメント (「Uses ... `--no-github` flag for hermetic execution」) にこの1テストが例外である旨を追記する
- `tests/get-auto-session-report.bats`: `phase/verify` ラベルを持つ Issue が実際に `### Verify Phase Residuals` セクションで検出されることを assert する新規テストケースを追加する (Issue body AC2 の rubric 記述がこのファイルを名指ししているため)。同ファイルに `--no-github` 時の明示的な注記表示を確認するテストケースも追加する
- `skills/code/skill-dev-validation.md`: Known Failure Patterns 表の `VERIFY_RESIDUALS always empty` 行 (現在の行52) の Root Cause 記述が「jq context loss」のみを原因としているが、現在のコードは既に `. as $all` で正しくバインドされており実際の空集合原因ではない。本 Issue (#900) で判明した「`phase=="verify"` イベントが本番で一度も emit されない」という、より深い構造的原因を追記する

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `VERIFY_RESIDUALS` jq計算 (現在の行250-259) を削除し、`VERIFY_RESIDUALS=""` と `VERIFY_RESIDUALS_NO_GITHUB_NOTE=""` の初期化に置き換える。`phase_start`/`phase_complete` (`phase=="verify"`) イベントへの依存を完全に除去する (→ acceptance criteria 1)
2. (after 1) 既存の GitHub state lookups ブロック (`FULLY_CLOSED`/`VERIFY_REMAINING` を `ISSUE_NUMS` の各 Issue についてループ計算している箇所、現在の行463-480) を拡張する: `phase/verify` ラベルに一致する分岐で `_num` を `VERIFY_RESIDUALS` に改行区切りで追記する。`NO_GITHUB == true` の分岐では `VERIFY_RESIDUALS_NO_GITHUB_NOTE="(--no-github mode: cannot detect phase/verify residuals via live label lookup. Re-run without --no-github to populate this section.)"` を設定する (→ acceptance criteria 1, 3)
3. (after 2) `### Verify Phase Residuals` レンダーブロック (現在の行635-650) を修正し、`VERIFY_RESIDUALS_NO_GITHUB_NOTE` が非空ならそれを出力して終了、空なら既存の空/非空判定に進むよう分岐を追加する。Metrics 冒頭のキャベア (現在の行586) の文言を「Phase Activity Summary / Sub-Issue Completion Timeline の phase breakdown には verify phase が計上されない」旨に限定するよう修正する。あわせて `skills/code/skill-dev-validation.md` の `VERIFY_RESIDUALS always empty` 行の Root Cause 記述に、本番で `phase=="verify"` イベントが一度も emit されない構造的原因 (#900) を追記する (→ acceptance criteria 1)
4. (after 3) `tests/audit-auto-session.bats` の `"success: verify-type breakdown appears in Verify Phase Residuals section"` テストを書き換える: `WHOLEWORK_ISSUE_BODY_DIR` によるフィクスチャ設定は維持しつつ、`$BATS_TEST_TMPDIR/mocks/gh` に fake 実行可能ファイルを作成して `PATH` の先頭に追加する (`tests/get-issue-type.bats` と同じ慣習)。この mock は `gh issue view <471|645> --json labels ...` に対して `phase/verify` ラベルを返し、`gh pr list --search ... --json number ...` に対して空を返すようにする。`run bash "$SCRIPT" ...` 呼び出しから `--no-github` を外す。ファイル冒頭のコメントにこの1テストが `gh` mock 方式である旨を追記する (→ acceptance criteria 2)
5. (after 3, parallel with 4) `tests/get-auto-session-report.bats` に新規テストケースを追加する: `$BATS_TEST_TMPDIR/mocks/gh` mock (手順4と同様の方式) で特定の Issue 番号に `phase/verify` ラベルを付与し、`--no-github` を付けずに実行して `### Verify Phase Residuals` セクションにその Issue が実際に検出されることを assert する。別のテストケース (または既存テストへの assertion 追加) で `--no-github` 実行時に `VERIFY_RESIDUALS_NO_GITHUB_NOTE` の文言が出力されることを assert する (→ acceptance criteria 2, 3)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/get-auto-session-report.sh のVerify Phase Residuals検出ロジックが、phase=verifyのphase_start/phase_completeイベント(常に空集合)に依存しない実装に置き換えられている" --> `scripts/get-auto-session-report.sh` の `VERIFY_RESIDUALS` 計算が、存在しない `phase_start`/`phase_complete` (`phase=="verify"`) イベントに依存しない方式に置き換えられている
- <!-- verify: rubric "tests/get-auto-session-report.batsに、phase/verifyラベルを持つIssueがVerify Phase Residualsセクションで実際に検出されることを検証するテストケースが追加されている" --> bats test で、`phase/verify` ラベルを持つ Issue が実際に "Verify Phase Residuals" セクションに検出されることを assert するテストケースが追加されている
- <!-- verify: rubric "--no-githubモードでVerify Phase Residualsが検出できない場合の明示的な注記または代替挙動が実装されている" --> `--no-github` モード使用時の挙動 (検出不能である旨の明示) が記述されている

### Post-merge

- <!-- verify-type: observation event=auto-run --> 次回 `/auto --batch` 完走後、実際に `phase/verify` に残る Issue が Verify Phase Residuals セクションに正しく表示されることを観察

## Notes

- **Option A採用の経緯**: Issue body は Option A (`gh issue list --label phase/verify --state all --json number` による直接クロスチェック) を推奨案として提示していたが、Spec では既存の `FULLY_CLOSED`/`VERIFY_REMAINING` 計算ループ (`ISSUE_NUMS` の各 Issue について `gh issue view --json labels` を既に呼んでいる) に統合する方式を採用した。理由: (1) 新しい gh 呼び出しパターンを追加せず既存の per-issue ラベル取得を再利用できる、 (2) `VERIFY_REMAINING` のカウントと `VERIFY_RESIDUALS` のリストが同一ループ・同一データソースから計算されるため、両者の不整合が構造的に起こり得なくなる (現状は別々のメカニズムで計算されており、偶然にも一致しない可能性があった)。Option A の「live label ベースで検出する」という意図は維持しつつ、実装レベルでより minimal-diff かつ一貫性の高い手段を選んだ。
- **`tests/audit-auto-session.bats` の既存テストが本修正で壊れる件**: 同ファイルの `"success: verify-type breakdown appears in Verify Phase Residuals section"` テストは、コメントで明示されている通り「Issue 471: has verify phase_start but no phase_complete (residual)」という、本 Issue が破棄対象とする前提 (合成イベントによる残留判定) に依存していた。本修正後はこの前提が意味を持たなくなるため、`gh` mock ベースへの書き換えが必須。Changed Files と Implementation Steps に明記済み。
- **AC2 のテスト追加先**: Issue body の rubric 記述が `tests/get-auto-session-report.bats` を名指ししているため、新規テストは同ファイルに追加する。ただし `tests/audit-auto-session.bats` の既存テスト修正も (回帰防止のため) 別途必須であり、両ファイルとも Changed Files に含めた。
- **キャベア文言の扱い**: Metrics 冒頭のキャベア「verify phase は計上されない」は Phase Activity Summary / Sub-Issue Completion Timeline の phase breakdown については本修正後も真であり続ける (`/verify` は依然として `phase_start`/`phase_complete` を emit しないため)。Verify Phase Residuals セクションについてのみ真でなくなるため、キャベア全体を削除せず記述範囲を限定する。
