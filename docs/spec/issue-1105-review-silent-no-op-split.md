# Issue #1105: detect-wrapper-anomaly: review の silent no-op を独立パターンとして切り出し

## Overview

`scripts/detect-wrapper-anomaly.sh` の review 分岐は、PR にコメント/レビューが 0 件の "silent no-op" ケースも `review-completion-false-negative` (marker 欠落/非標準見出しを想定したパターン) に一括で吸収してしまう。両者は復旧手順が異なる (marker 追記 vs 再実行) にもかかわらず同一パターン名で報告されるため、Tier 2 リカバリが誤った復旧手順を試みる (実例: #1069 / PR #1077)。本 Issue は `gh pr view` でコメント/レビュー件数を確認し、両方 0 件のときだけ新パターン `review-silent-no-op` を報告するよう分岐を追加する。あわせて `silent-no-op` 系分岐の `IMPROVEMENT_HINT` がフェーズに関わらず固定文言 (`run-code.sh` / "code phase") を出す欠陥 (実例: #1255 / PR #1269) を修正し、phase に応じた再実行コマンド・番号種別を案内する。

## Reproduction Steps

1. review フェーズで `claude -p` が PR にコメント/レビューを一切投稿せずに終了する (例: ~840 秒の watchdog silence 後に exit 0)
2. `run-auto-sub.sh` の `_complete_phase_after_success` (exit 0 の場合) 、または Tier 1 リカバリ手前のログ内容が、`reconcile-phase-state.sh` の `"matches_expected":false` / `"phase":"review"` を含む
3. `detect-wrapper-anomaly.sh` の `elif` チェーンでは、`review-completion-false-negative` の分岐条件 (`matches_expected:false && phase:review && !matches_expected:true`) が `EXIT_CODE` を問わず先着でマッチし、`EXIT_CODE == "0"` ブロック側にのみ実装されている `_review_confirmed_posted` ライブチェック (`gh pr view --json reviews` で Acceptance Criteria Verification Results 投稿を確認) に到達しない
4. 結果、実際は PR コメント 0 件の genuine no-op であっても `review-completion-false-negative` として報告され、Tier 2 が「marker 追記」という的外れな復旧手順を提示する

## Root Cause

`review-completion-false-negative` 分岐 (`scripts/detect-wrapper-anomaly.sh` の該当 `elif`) が `EXIT_CODE` を条件に含まないまま `EXIT_CODE == "0"` ブロックより前に位置しているため、review フェーズの完了実測 (`_review_confirmed_posted`) に基づく抑止が及ばない。この分岐自体に PR コメント/レビュー件数の実測チェックがないことが根本原因であり、`review-completion-false-negative` 側にも同種のライブチェックを追加する必要がある。

副次的な欠陥として、`silent-no-op` 分岐の `IMPROVEMENT_HINT` が phase を無視して `run-code.sh $ISSUE_NUMBER` / "code phase" を固定出力する。review/merge フェーズでは `run-auto-sub.sh` の `run_phase_with_recovery "review" "$PR_NUMBER" ...` / `run_phase_with_recovery "merge" "$PR_NUMBER" ...` 呼び出し規約により `$ISSUE_NUMBER` に実際は PR 番号が入るため、スクリプト名・番号種別の両方が誤った案内になる (実例: #1255 / PR #1269, `run-code.sh 1269` という誤案内)。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`:
  1. ヘルパー関数 `_phase_retry_hint(phase, number)` を追加 (log file 存在チェック後、パターンマッチング開始前)。`review`/`merge`/`code*`/その他で再実行コマンドと番号種別 (Issue番号 vs PR番号) を切り替えて1行の案内文を返す (bash 3.2 互換 — `case` 文のみ使用)
  2. `review-completion-false-negative` 分岐に `gh pr view "$ISSUE_NUMBER" --json comments,reviews` によるコメント/レビュー件数チェックを追加。`jq` で `.comments | length` / `.reviews | length` を抽出し、両方 `"0"` のときは新パターン `review-silent-no-op` を、それ以外 (コメント/レビューが存在、または `gh`/`jq` 失敗で件数が空文字のまま) は従来の `review-completion-false-negative` を報告
  3. `silent-no-op` 分岐 (既存) の `IMPROVEMENT_HINT` を `_phase_retry_hint()` 経由に変更
- `modules/orchestration-fallbacks.md`: `review-completion-false-negative` エントリの直後に `review-silent-no-op` のカタログエントリ (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale の5節、既存エントリと同一スキーマ — `tests/orchestration-fallbacks.bats` のスキーマ検証テストが5節の存在とカウント一致を要求) を追加
- `tests/detect-wrapper-anomaly.bats`:
  1. 既存テスト `"review-completion-false-negative: detects matches_expected false with phase review"` を更新 — 新設した `gh pr view` 呼び出しが実環境の `gh` に依存して不定になることを避けるため、`gh` をコメント/レビューが存在するケースにモックする (negative case として明示化)
  2. 新規テスト: `gh` が 0 件/0 件を返し `review-silent-no-op` になる positive case
  3. 新規テスト: `gh pr view` 失敗時に従来の `review-completion-false-negative` へフォールバックする fail-safe case
  4. 新規テスト: review フェーズおよび merge フェーズで `silent-no-op` 系パターン発火時、`IMPROVEMENT_HINT` に `run-code.sh`/"code phase" という誤った文言が含まれないことを検証する回帰テスト (各1件)

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` に `_phase_retry_hint()` ヘルパー関数を追加する (→ acceptance criteria 5)
2. `review-completion-false-negative` 分岐を、`gh pr view "$ISSUE_NUMBER" --json comments,reviews` の結果に基づき `review-silent-no-op` / `review-completion-false-negative` に振り分けるよう変更する (after 1) (→ acceptance criteria 1, 2)
3. `silent-no-op` 分岐の `IMPROVEMENT_HINT` を `_phase_retry_hint()` 経由に変更する (after 1) (→ acceptance criteria 5)
4. `modules/orchestration-fallbacks.md` に `review-silent-no-op` カタログエントリを追加する (parallel with 1, 2, 3) (→ acceptance criteria 3)
5. `tests/detect-wrapper-anomaly.bats` の既存テスト更新および新規テスト追加 (positive/negative/fail-safe/phase別回帰) を行う (after 2, 3) (→ acceptance criteria 4, 6, 7)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh が review 分岐で PR のコメント/レビュー件数を確認し、0 件のときは review-silent-no-op を、存在するときは従来の review-completion-false-negative を報告するよう分岐している。gh 失敗時は従来パターンにフォールバックする" --> PR コメント件数によるパターン分岐が実装されている
- <!-- verify: grep "review-silent-no-op" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` に `review-silent-no-op` パターンが存在する
- <!-- verify: grep "review-silent-no-op" "modules/orchestration-fallbacks.md" --> `orchestration-fallbacks.md` に `review-silent-no-op` のカタログエントリが追加されている
- <!-- verify: rubric "detect-wrapper-anomaly.sh の新分岐を検証する bats テストが追加されている。PR コメント 0 件で review-silent-no-op になること、およびコメントが存在する場合は従来の review-completion-false-negative のままであること (negative case) の両方を検証している" --> 新分岐の bats テストが positive / negative 両方追加されている
- <!-- verify: rubric "scripts/detect-wrapper-anomaly.sh の silent-no-op 系分岐 (silent-no-op および review-silent-no-op) の IMPROVEMENT_HINT が phase ごとに適切な再実行手段と番号種別 (Issue番号 vs PR番号) を案内するよう修正されている。code フェーズでは run-code.sh と Issue番号を、review/merge フェーズでは phase に応じた再実行コマンドと PR番号であることを案内する文言になっている" --> IMPROVEMENT_HINT がフェーズ非依存の固定文言 (run-code.sh / code phase 固定) から脱却しフェーズ別の案内になっている
- <!-- verify: rubric "detect-wrapper-anomaly.sh の bats テストに、review フェーズおよび merge フェーズで silent-no-op 系パターンが発火した際の IMPROVEMENT_HINT が run-code.sh や code phase という誤った文言を含まないことを検証する回帰テストケースが追加されている" --> フェーズ別 IMPROVEMENT_HINT の回帰テストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge

- review が silent no-op で終了した実例に対して検出を実行し、`review-silent-no-op` として報告されることを確認する <!-- verify-type: manual -->

## Notes

- **`tests/orchestration-fallbacks.bats` は変更不要**: 同ファイルはスキーマ汎用検証 (`### Symptom`/`### Applicable Phases`/`### Fallback Steps`/`### Escalation`/`### Rationale` の5節が同数存在すること、`### Rationale` に `#N` 参照があること) のみをチェックしており、パターン名をハードコードしていない。新エントリが5節構成で `#1105`/`#1069` 等の Issue 参照を含めば自動的に通過するため、テストファイル自体の変更は不要であることを確認済み (`grep` で全 `@test` を確認)
- **`scripts/apply-fallback.sh` は変更不要**: 同スクリプトの Tier 2 自動リカバリハンドラは `dco-signoff-missing-autofix` / `code-patch-silent-no-op` / `json-mode-silent-hang` の3種のみで、`review-completion-false-negative` 自体に自動ハンドラが存在しない (Tier 3 の人間/recovery sub-agent 判断に委ねる設計)。分離後の `review-silent-no-op` も同様に自動ハンドラなしで問題ない
- **allowed-tools 影響なし**: `detect-wrapper-anomaly.sh` は既存スクリプトの内部変更のみ (新規スクリプト追加なし)。内部で追加する `gh pr view` 呼び出しは bash スクリプト内部からのサブプロセス実行であり、Claude Code の allowed-tools 許可対象 (LLM が直接呼ぶ Bash コマンド) ではないため対象外。`modules/orchestration-fallbacks.md` の新エントリが参照する `reconcile-phase-state.sh` は既存カタログ内で頻出しており新規スクリプト参照ではないため、`skills/auto/SKILL.md` / `skills/verify/SKILL.md` の allowed-tools 追加は不要 (両者とも既に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*` を保有していることを確認済み)
- **bash 3.2 互換**: `_phase_retry_hint()` は `case`/`[[ ]]`/local 変数のみ使用し、`mapfile` 等の bash 4+ 専用構文は使用しない (macOS 標準 bash 対応)
- **BRE メタ文字チェック**: 本 Spec の `grep` verify command 2件はいずれも `\|`/`\(`/`\)`/`\+`/`\?` を含まないため、ERE 書き換えは不要
- **patch route チェック対象外**: Size M のため pr route (PR が実在)。`github_check "gh pr checks"` はそのまま有効

## Consumed Comments
No new comments since last phase.
