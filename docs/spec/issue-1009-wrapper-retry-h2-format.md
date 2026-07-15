# Issue #1009: run-auto-sub: _write_wrapper_retry_recovery のエントリ形式を canonical な H2 に修正

## Overview

`scripts/run-auto-sub.sh` の `_write_wrapper_retry_recovery()` は `docs/reports/orchestration-recoveries.md` に **H3 形式** (`### wrapper-retry-on-kill (phase)`) でエントリを書いており、同ファイルの Entry Format 定義・`write_recovery_entry()`・`_write_manual_recovery_to_recoveries_log()` (#1005 で新設) が前提とする **canonical な H2 形式** (`## YYYY-MM-DD HH:MM UTC: <symptom-short>`) と一致しない。結果として `scripts/collect-recovery-candidates.sh` の H2 専用パーサから wrapper-retry-on-kill の記録が不可視になり、`/audit recoveries` の頻度検出と `recoveries-auto-fire` の閾値判定 (threshold 3) から漏れている。本 Issue はエントリ形式を H2 に修正し、頻度検出対象に含める。

## Reproduction Steps

1. `/auto` 実行中に leaf runner (`run-code.sh` 等) が early-kill window (`WHOLEWORK_RETRY_ON_KILL_MAX_SEC`, デフォルト 300s) 内に exit code 137/143 で終了し、`retry-on-kill.sh` の自動リトライが成功する (`_RETRY_ON_KILL_FIRED=true` かつリトライが exit 0)
2. `run_phase_with_recovery()` が `_write_wrapper_retry_recovery()` を呼び、`docs/reports/orchestration-recoveries.md` にエントリが追記される
3. 追記されたエントリを見ると `### wrapper-retry-on-kill (${phase})` という H3 見出し + フラットな Date/Issue/Source/Exit code/Outcome 箇条書きになっている (Context/Diagnosis/Recovery Applied/Outcome/Improvement Candidate の 5 セクション構成ではない)
4. `scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 1` を実行しても、このエントリの `symptom-short` (`wrapper-retry-on-kill`) は出力に現れない — パーサの見出し検出が `^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: .+` (H2 限定) のため、H3 エントリを素通りする

## Root Cause

`_write_wrapper_retry_recovery()` は #807 で単独実装された際、独自の H3 形式で書き込むように実装された。その後 #1005 で `_write_manual_recovery_to_recoveries_log()` が同ファイル内に新設され、そちらは `docs/reports/orchestration-recoveries.md` の Entry Format 定義に厳密に従う canonical な H2 形式 (5 セクション構成) を採用したが、既存の `_write_wrapper_retry_recovery()` は改修されないまま残った。同一ファイル内に非互換な 2 つのエントリ形式が併存し、`collect-recovery-candidates.sh` の H2 専用パーサからは H3 側が構造的に不可視になっていた。現時点で `docs/reports/orchestration-recoveries.md` に wrapper-retry-on-kill エントリは 1 件も存在しない (grep 確認済み、H3/H2 いずれの形式でも 0 件) — 発生頻度自体は低いが、発生しても記録が可視化されない状態が続いていた。

## Changed Files

- `scripts/run-auto-sub.sh`: `_write_wrapper_retry_recovery()` を canonical な H2 形式 (5 セクション構成) に書き換え。4 番目の引数として retried runner script 名を追加し、呼び出し箇所 (`run_phase_with_recovery()` 内) を更新 — bash 3.2+ 互換を維持
- `tests/run-auto-sub.bats`: `_write_wrapper_retry_recovery()` が H2 形式で出力することを検証するテストを追加
- `tests/collect-recovery-candidates.bats`: H2 形式の `wrapper-retry-on-kill` エントリが頻度パーサで検出されることを検証するテストを追加

Steering Docs sync candidate grep (`grep -l "run-auto-sub.sh" docs/*.md docs/ja/*.md`) は `docs/structure.md` / `docs/tech.md` / `docs/workflow.md` / `docs/migration-notes.md` およびそれぞれの `docs/ja/` ミラーの計 8 件を検出したが、いずれも `run-auto-sub.sh` を一般的なオーケストレータとして言及するのみで、`wrapper-retry-on-kill` エントリ形式の詳細には触れていない (grep 確認済み、0 件)。Steering Docs 側の同期は不要と判断 (詳細は Notes 参照)。

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `_write_wrapper_retry_recovery()` (`_write_tier3_recovery_to_spec()` の直後、`# See modules/orchestration-fallbacks.md#wrapper-retry-on-kill` のポインタコメントが付いた関数) を書き換える (→ 受け入れ条件 A, B)。
   - シグネチャに 4 番目の引数 `RUNNER_SCRIPT_NAME` を追加 (`local runner_name="${4:-run-auto-sub.sh}"` のようにデフォルト値を持たせる)
   - 書き込むエントリを次の canonical な H2 形式に変更する:
     - 見出し: `## <date>: wrapper-retry-on-kill` (phase をサフィックスに含めない — `_write_manual_recovery_to_recoveries_log()` と同じ規約)
     - `### Context`: `- Issue #<issue>, phase: <phase>` / `- Source: retry-on-kill.sh` / `- Wrapper: <runner_name>, exit code: <exit_code_arg>`
     - `### Diagnosis`: `- wrapper (<runner_name>) が early-kill window (WHOLEWORK_RETRY_ON_KILL_MAX_SEC) 内に exit code <exit_code_arg> で終了し、retry-on-kill.sh が自動再試行した`
     - `### Recovery Applied`: `- modules/orchestration-fallbacks.md#wrapper-retry-on-kill`
     - `### Outcome`: 既存の success/escalated 判定ロジックをそのまま流用
     - `### Improvement Candidate`: `_find_known_recoveries_issue "wrapper-retry-on-kill"` を再利用し、マッチした Issue があれば `起票済み #NNN`、なければ `未起票`
   - 旧 H3 テンプレート文字列 (`### wrapper-retry-on-kill (${phase})` と、それに続くフラットな Date/Issue/Source/Exit code/Outcome 箇条書き) を完全に削除する
   - 呼び出し箇所 (`run_phase_with_recovery()` 内、`_RETRY_ON_KILL_FIRED` チェック直後) を `_write_wrapper_retry_recovery "$EMIT_ISSUE_NUMBER" "$phase" "$exit_code" "$(basename "$runner_script")"` に更新する

2. `tests/run-auto-sub.bats` に、既存の `"retry-on-kill: child runner killed once then succeeds, run-auto-sub exits 0"` テストの直後にテストを追加する (after 1) (→ 受け入れ条件 C)。
   - 同テストと同じ XS route + `run-code.sh` (1 回目 exit 143、2 回目 exit 0) のカウンタモックを再利用
   - `$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md` を事前作成 (マーカー行のみ)
   - 既存の `"run-auto-sub: manual recovery: appends canonical H2 entry to orchestration-recoveries.md"` テストと同じパターンで `git`/`gh` をモック
   - アサーション: 結果ファイルが `^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: wrapper-retry-on-kill$` にマッチする行を含む、`Wrapper: run-code.sh, exit code: 0` を含む、旧 `### wrapper-retry-on-kill (` を含まない

3. `tests/collect-recovery-candidates.bats` に、既存の `"normal detection: count >= threshold and no exclusion -> appears in output"` テストの直後にテストを追加する (parallel with 2) (→ 受け入れ条件 C)。
   - `$RECOVERY_FILE` に H2 形式の `wrapper-retry-on-kill` エントリ (最小限の Context/Outcome 本文) を 3 件書き込むフィクスチャを用意
   - `--threshold 3` で実行し、出力に `wrapper-retry-on-kill\t3` が含まれることを確認

4. `bats tests/run-auto-sub.bats tests/collect-recovery-candidates.bats` を実行し、全テスト PASS を確認する (after 2, 3) (→ 受け入れ条件 D)。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の _write_wrapper_retry_recovery() が orchestration-recoveries.md の Entry Format 定義と同じ H2 見出し形式 (## YYYY-MM-DD HH:MM UTC: <symptom-short>) でエントリを書き込む実装になっている" --> `_write_wrapper_retry_recovery()` が canonical な H2 形式 (Context/Diagnosis/Recovery Applied/Outcome/Improvement Candidate の 5 セクション構成) でエントリを書く
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "### wrapper-retry-on-kill (" --> 旧 H3 形式のエントリテンプレート文字列が `scripts/run-auto-sub.sh` から除去されている
- <!-- verify: rubric "tests/ 配下に、H2 形式の wrapper-retry-on-kill エントリが collect-recovery-candidates.sh のパーサで検出されることを検証するテスト、または _write_wrapper_retry_recovery の出力形式を検証するテストが存在する" --> `collect-recovery-candidates.sh` が wrapper-retry-on-kill エントリを頻度検出できる
- <!-- verify: command "bats tests/run-auto-sub.bats tests/collect-recovery-candidates.bats" --> bats テストが PASS する

### Post-merge

- <!-- verify-type: observation event=auto-run --> <!-- verify: rubric "直近の /auto 実行で wrapper-retry-on-kill recovery が発火した場合、docs/reports/orchestration-recoveries.md に H2 形式 (## YYYY-MM-DD HH:MM UTC: wrapper-retry-on-kill) のエントリが記録されており、collect-recovery-candidates.sh の頻度検出対象になっている (該当する recovery 発火が観測されない場合は対象外として扱う)" --> 次回 wrapper-retry-on-kill recovery 発生時、エントリが H2 形式で記録され頻度検出対象になることを観察

## Notes

- **Steering Docs sync 不要の判断根拠**: `grep -l "run-auto-sub.sh" docs/*.md docs/ja/*.md` で 8 件ヒットしたが (`docs/structure.md`, `docs/tech.md`, `docs/workflow.md`, `docs/migration-notes.md` + 各 `docs/ja/` ミラー)、いずれも run-auto-sub.sh を汎用オーケストレータとして言及するのみで `wrapper-retry-on-kill` のエントリ形式詳細 (H2/H3) には触れていないことを個別に確認した (grep 0 件)。Changed Files への追加は行わない。
- **Auto-Resolved Ambiguity Points からの差分 (4 番目の引数追加)**: Issue 本文の Auto-Resolved Ambiguity Points は Diagnosis 文言テンプレートを「wrapper (`<run-*.sh>`) が...」と記述しているが、`_write_wrapper_retry_recovery(issue, phase, exit_code)` の既存シグネチャには実際にリトライされた runner script 名 (`run-code.sh` 等) を渡す手段がなかった。`_write_manual_recovery_to_recoveries_log()` の precedent は Wrapper フィールドに常に `run-auto-sub.sh` (呼び出し元スクリプト自身) を使うが、そちらは manual recovery が run-auto-sub.sh 自身の呼び出しとして発生する経路であるのに対し、wrapper-retry-on-kill は run-auto-sub.sh 内から呼び出した子プロセス (leaf runner) が exit 137/143 した経路であるため、`run-auto-sub.sh` を Wrapper 値に使うと「run-auto-sub.sh 自身がクラッシュした」という誤解を招く。そこで 4 番目の引数 `RUNNER_SCRIPT_NAME` を追加し、呼び出し側 (`run_phase_with_recovery()`) が既に保持している `$runner_script` の basename を渡すよう設計した。Entry Format 定義の `Wrapper: <run-*.sh name>` というフィールド仕様にもこちらの方が忠実である。
- **Post-merge AC への rubric 追加**: Issue 本文の Post-merge AC (`observation` タグ) は verify command が付いておらず、`/verify` が `auto-run` イベント発火時に機械的に再評価する手段がなかった。Option B (rubric 付与) を適用し、Issue 本文と本 Spec の両方に同じ rubric verify command を反映した。
- **バックフィル不要**: `docs/reports/orchestration-recoveries.md` に現時点で wrapper-retry-on-kill エントリ (H3/H2 いずれも) は 1 件も存在しないことを grep で確認済み。本修正は今後の書き込みにのみ影響し、既存データの移行は不要 (Post-merge AC が「次回発生時」の観察として設計されているのはこのため)。
- **動作確認**: 設計した新しい `_write_wrapper_retry_recovery()` のロジックをスクラッチ環境で実行し、`collect-recovery-candidates.sh` のパーサ正規表現 (`^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: .+`) に一致する H2 エントリが生成されることを確認済み。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 一行要約: `/issue 1009 --non-interactive` の Issue Retrospective コメント。Type=Bug, Size=M, Value=2 の判定根拠と、rubric AC への補助 `file_not_contains` 追加理由、Auto-Resolve Log (Diagnosis 文言・Recovery Applied 参照先・Improvement Candidate 記入方法の 3 点) を記録 / URL: https://github.com/saitoco/wholework/issues/1009#issuecomment-4978480709
