# Issue #932: detect-wrapper-anomaly: review-completion-false-negative が post-fallback recovery 成功後も誤検出

## Consumed Comments

No new comments since last phase.

## Overview

`scripts/detect-wrapper-anomaly.sh` の `review-completion-false-negative` パターン (#547) が、`post-fallback-review-summary.sh` (#915) による recovery が成功し recheck で `matches_expected:true` に復帰しているケースでも、anomaly を誤って報告してしまう問題を修正する。同ファイル内の `EXIT_CODE=0` 分岐 (`silent-no-op` 系) が既に持つ「同一 LOG_FILE 内に後続の `matches_expected:true` が出現していれば抑止する」という reconcile-first authority の手法を、`review-completion-false-negative` 分岐にも同様に適用する。#916 (merge phase live check)・#927 (review phase Review 投稿 live check) に続く、同系統3件目の false positive 修正。

## Reproduction Steps

1. `/auto` の review phase (`run-review.sh`) で、LLM が Review 本体 (Step 11, "Acceptance Criteria Verification Results" を含む) の投稿には成功したが、`## Review Response Summary` コメント (`<!-- review-summary -->` マーカー付き) の投稿を欠落させたまま exit 0 で終了する。
2. `run-review.sh` が `reconcile-phase-state.sh review --pr <N> --check-completion` を実行し、`{"phase":"review","matches_expected":false,"diagnosis":"Review Response Summary not found..."}` を得て、`Warning: claude exited 0 but review phase did not complete (silent no-op). reconcile: {...}` をログに出力する。
3. `run-review.sh` が `post-fallback-review-summary.sh <PR>` を呼び出し、既存の Review に "Acceptance Criteria Verification Results" を確認できたため、`<!-- review-summary -->` マーカー付きのフォールバックコメント投稿に成功する。
4. `run-review.sh` が recheck として再度 `reconcile-phase-state.sh` を実行し、今度は `matches_expected:true` を得て `post-fallback-review-summary: fallback Response Summary posted, review phase recovered. recheck: {...}` をログに出力し、`EXIT_CODE=0` のまま正常終了する。
5. `run-auto-sub.sh` の post-hoc `detect-wrapper-anomaly.sh --log <log> --exit-code 0 --issue <N> --phase review` 呼び出しが、ログ内に (ステップ2由来の) `"matches_expected":false` と `"phase":"review"` が存在することのみを検出し、ステップ4の recovery 成功を考慮せず `review-completion-false-negative` anomaly を誤って報告する。

実際の発生: Issue #927 の `/auto` 実行中 (PR #931 review phase)。`gh pr view 931` で MERGED・`<!-- review-summary -->` マーカー付きコメント投稿済みを確認しており、実害のない誤検出だった。

## Root Cause

`scripts/detect-wrapper-anomaly.sh` は「最初にマッチしたパターンが勝つ」(`# Pattern matching (first match wins; only one pattern is reported per run)`) という `elif` チェーン構造で、ログ内容の静的文字列マッチのみでパターンを判定している。`review-completion-false-negative` 分岐の条件 (`matches_expected:false` かつ `phase:review` が LOG_FILE 内に存在する) は、同一ログ内に**後続**の recheck 成功シグナル (`matches_expected:true`) が存在するかどうかを一切考慮していない。

一方、同ファイルの `EXIT_CODE=0` 分岐内の `silent-no-op` 判定は、`elif grep -q '"matches_expected":true' "$LOG_FILE"; then : # reconcile-first authority` という、同じ静的ログ内に `matches_expected:true` が (どこかに) 存在すれば抑止する仕組みを既に実装済みである。しかし `review-completion-false-negative` 分岐は `elif` チェーンの中で `EXIT_CODE=0` 分岐より**前**に評価されるため、ログが `matches_expected:false` (初回) と `phase:review` を含む時点で先に確定的にマッチしてしまい、後段の `EXIT_CODE=0` 分岐が持つ reconcile-first authority のロジックまで処理が到達しない。

`review-completion-false-negative` パターン (#547) 導入時点では `post-fallback-review-summary.sh` (#915) によるリカバリ機構が存在せず、`matches_expected:false` + `phase:review` の組は常に真の anomaly だったため、この分岐は当時は正しかった。#915 でリカバリ機構が追加されたことで、この判定条件が古くなり、今回の誤検出に至った。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: change — `review-completion-false-negative` の `elif` 条件に `&& ! grep -q '"matches_expected":true' "$LOG_FILE"` を追加し、後続の recheck 成功を検出した場合は anomaly を抑止する
- `tests/detect-wrapper-anomaly.bats`: change — recheck で `matches_expected:true` に復帰するケースで anomaly が抑止されることを検証する bats テストを追加
- `modules/orchestration-fallbacks.md`: change — `review-completion-false-negative` エントリの `### Rationale` に、後続の `matches_expected:true` recheck による抑止条件を追記 (既存の "Exclusivity with reconciler-header-mismatch" bullet と対になる形。SHOULD レベル、専用 verify item なし。#927 と同様の判断)
- `docs/structure.md`: [Steering Docs sync candidate] `detect-wrapper-anomaly.sh` の説明文が本修正後も妥当か確認
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー確認 (`docs/translation-workflow.md` Sync Procedure 準拠)

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` の `review-completion-false-negative` の `elif` 分岐 (条件: `grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"review"' "$LOG_FILE"`。`reconciler-header-mismatch` 分岐の直後、`mid-run-api-error` 分岐の直前に位置する) の条件に `&& ! grep -q '"matches_expected":true' "$LOG_FILE"` を追加する。ログ内に後続の recheck 成功シグナルが存在する場合は本分岐の条件が偽となり、後続の `elif` (`mid-run-api-error` → `EXIT_CODE=="0"` 分岐) に処理が委譲される。既存の `EXIT_CODE=0` 分岐内 `# reconcile-first authority` コメントに倣い、本分岐にも短い説明コメントを付す (→ acceptance criteria A)
2. `tests/detect-wrapper-anomaly.bats` の既存の `"review-completion-false-negative: no detection for unrelated log"` テストの直後に、新規 `@test` を1件追加する (after 1) (→ acceptance criteria B):
   - `"matches_expected":false` + `"phase":"review"` (初回失敗) に続けて、`"matches_expected":true` を含む行 (recheck 復帰。`post-fallback-review-summary.sh` の recovery 成功ログメッセージを模す) をログに含める
   - `--exit-code 1 --phase review` で実行する (既存の sibling テスト "review-completion-false-negative: detects..." / "...reconciler-header-mismatch takes priority..." と同じ規約に倣い、`EXIT_CODE=="0"` 分岐の `gh pr view` live check ロジックから独立させて本分岐の抑止条件のみを検証する)
   - 出力が `review-completion-false-negative` を含まないこと、かつ出力全体が空 (`[ -z "$output" ]`) であることを検証する
3. `modules/orchestration-fallbacks.md` の `review-completion-false-negative` エントリの `### Rationale` に、既存の "Exclusivity with reconciler-header-mismatch" bullet の直後に、後続の `matches_expected:true` recheck (recovery 成功) による抑止条件を説明する1文を追記する (parallel with 1, 2)

## Verification

### Pre-merge

- <!-- verify: rubric "detect-wrapper-anomaly.shのreview-completion-false-negativeパターンが、reconcile-phase-state.shのrecheckでmatches_expected:trueに復帰している場合にanomalyを出力しないよう修正されている" --> `detect-wrapper-anomaly.sh` の `review-completion-false-negative` 判定が、recheck で `matches_expected:true` に復帰している場合には anomaly を報告しないよう修正されている
- <!-- verify: rubric "detect-wrapper-anomaly系bats に、review-completion-false-negative検出後にrecheckでmatches_expected:trueに復帰するケースでanomalyが抑止されるテストが含まれる" --> bats test で、review-completion-false-negative 検出後に recheck で matches_expected:true に復帰するケースに対して anomaly が発生しないことが検証されている

### Post-merge

- 次回 `/auto` の review phase で post-fallback recovery が成功した際、false-positive anomaly が発生しないことを観察 <!-- verify-type: opportunistic -->

## Notes

- **recheck 判定方式 (Issue 本文の Auto-Resolved Ambiguity Points を転記)**: 静的ログ内の後続 `matches_expected:true` 出現を grep で検出する方式を採用する (`reconcile-phase-state.sh --check-completion` の live 再実行ではない)。理由: `detect-wrapper-anomaly.sh` は `--log`/`--exit-code`/`--issue`/`--phase` のみを受け取り `gh`/ネットワーク呼び出しを一切行わない静的ログ解析スクリプトであり、既に同ファイル内の `EXIT_CODE=0` 分岐 (`silent-no-op` 系、reconcile-first authority) が同型の解決策を実装済みである。この既存パターンを `review-completion-false-negative` 分岐にも適用するのが最小差分かつ一貫した実装である。
- **Bug-type conflict check**: Issue 本文の技術的記述 (`run-review.sh`・`reconcile-phase-state.sh`・`post-fallback-review-summary.sh` の挙動、ログメッセージの内容) はいずれもコードベース調査で実際の実装と一致することを確認しており、矛盾は検出されなかった。
- **`docs/reports/orchestration-recoveries.md` は対象外**: 同ファイルは自動生成の追記専用レポートであり、本 Issue のスコープは将来の誤記録の発生を防ぐことにあるため、既存の誤記録レコードを遡って訂正する対象にはしない。
- **`modules/orchestration-fallbacks.md` 更新は SHOULD レベル**: Issue 本文の Acceptance Criteria (Pre-merge 2件) はいずれも `scripts/detect-wrapper-anomaly.sh` とそのテストのみを対象としており、専用の verify command は設定しない (#927 の同種判断を踏襲)。
- **Verify command sync 確認**: 本 Spec の `## Verification > Pre-merge` は Issue 本文 `## Acceptance Criteria > Pre-merge` の2項目と verify コマンドを含め完全一致 (件数一致: Issue 側2件 / Spec 側2件)。Post-merge も Issue 本文の1件と一致 (`verify-type: opportunistic` を含め verbatim コピー)。
