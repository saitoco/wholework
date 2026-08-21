# Issue #1155: test: _write_wrapper_retry_recovery の escalated 分岐にテストカバレッジを追加

## Overview

`scripts/run-auto-sub.sh` の `_write_wrapper_retry_recovery()` は exit code に応じて `docs/reports/orchestration-recoveries.md` へ書き込むエントリの `### Outcome` を `success` / `escalated (retry also killed)` に分岐させるが、`escalated (retry also killed)` 側 (`exit_code_arg != 0`) を検証するテストが `tests/run-auto-sub.bats` に存在しない。既存の `success` 分岐テスト (`retry-on-kill: wrapper-retry-on-kill recovery writes canonical H2 entry`, 2564 行目) と対になる新規 `@test` を追加し、両分岐が canonical な H2 形式でエントリを書くことをテストで機械的に担保する。単一テストファイルへの追加のみで、実装コード (`scripts/run-auto-sub.sh` 本体) の変更は伴わない。

## Changed Files

- `tests/run-auto-sub.bats`: 新規 `@test` ケースを追加 (`_write_wrapper_retry_recovery()` の `escalated (retry also killed)` 分岐を検証)。既存の `retry-on-kill: wrapper-retry-on-kill recovery writes canonical H2 entry` (2564 行目) の直後に配置。

## Implementation Steps

1. `tests/run-auto-sub.bats` の既存 `retry-on-kill: wrapper-retry-on-kill recovery writes canonical H2 entry` テスト (2564 行目) の直後に、新規 `@test "retry-on-kill: wrapper-retry-on-kill recovery writes escalated Outcome on retry-also-killed"` を追加する (→ acceptance criteria AC1, AC2, AC3)。既存テストの隔離パターン (`git`/`gh` モック、`docs/reports/orchestration-recoveries.md` の事前作成、`get-issue-size.sh` → `XS`) をそのまま踏襲し、`run-code.sh` モックのみ変更する: カウンタで呼び出し回数を記録しつつ、**1 回目・2 回目とも `exit 143`** を返すようにする (`scripts/retry-on-kill.sh` の Branch B [early kill → retry] → Branch D [retry also killed → escalate] を発火させ、`_RETRY_ON_KILL_FIRED=true` かつ再試行後も exit 137/143 という条件を満たす)。アサーション:
   - `[ "$(cat "$COUNTER_FILE")" -eq 2 ]` (再試行が実際に発生したこと)
   - H2 見出し正規表現: `^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: wrapper-retry-on-kill$`
   - `Wrapper: run-code.sh, exit code: 143`
   - `### Outcome` セクション配下に `escalated (retry also killed)` が含まれる
   - 旧 H3 形式 (`### wrapper-retry-on-kill (`) が含まれないこと
   - `run bash "$SCRIPT" 42` の終了ステータスは `[ "$status" -eq 143 ]` を assert する (**`[ "$status" -eq 0 ]` を成功分岐テストからそのまま転用しないこと** — 理由は Notes 参照)
2. Step 1 で追加したテストを含む `bats tests/run-auto-sub.bats` (フルスイート) が PASS することを確認する (after 1) (→ acceptance criteria AC4)。

## Verification

### Pre-merge

- <!-- verify: rubric "tests/run-auto-sub.bats に、_write_wrapper_retry_recovery() を exit_code_arg が 0 以外の値で呼び出し、docs/reports/orchestration-recoveries.md へ書かれたエントリの ### Outcome セクションが 'escalated (retry also killed)' になることを検証するテストが追加されている" --> `escalated` 分岐のテストが追加されている
- <!-- verify: file_contains "tests/run-auto-sub.bats" "escalated (retry also killed)" --> テストファイルに `escalated (retry also killed)` の文字列が含まれている (rubric 判定の機械的な補助チェック)
- <!-- verify: rubric "追加されたテストが、Outcome の文字列だけでなく canonical H2 形式 (## YYYY-MM-DD HH:MM UTC: wrapper-retry-on-kill 見出しと Context/Diagnosis/Recovery Applied/Outcome/Improvement Candidate の 5 セクション) も併せて検証している" --> H2 形式の 5 セクション構成も併せて検証している
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が PASS する

### Post-merge

なし

## Notes

- **bats test 入力データ形式**: 新規テストの `run-code.sh` モックは既存の成功分岐テスト (2564 行目) と同じカウンタパターンを使うが、両方の呼び出しで `exit 143` を返す点のみ異なる (成功分岐は 1 回目 `exit 143` → 2 回目 `exit 0`)。`WHOLEWORK_RETRY_ON_KILL_MAX_SEC` の early-kill window (デフォルト 300s, `scripts/retry-on-kill.sh`) は明示的にオーバーライドしない — モックは瞬時に完了するため実測 elapsed は window を十分下回り、Branch B (early kill → retry) → Branch D (retry also killed → escalate) が確実に発火する。
- **既存 precedent との重要な差分 (終了ステータス)**: 既存の成功分岐テストは `run bash "$SCRIPT" 42` の後 `[ "$status" -eq 0 ]` を assert しているが、これは escalated 分岐にはそのまま転用できない。`run_phase_with_recovery()` (`scripts/run-auto-sub.sh:657`) は `_write_wrapper_retry_recovery()` 呼び出し後、tier1 (`reconcile-phase-state.sh`) → tier2 (`apply-fallback.sh`) → tier3 (`spawn-recovery-subagent.sh`) の順に回復を試みる。`tests/run-auto-sub.bats` の `setup()` が既定で用意するこれら 3 スクリプトのモック (reconcile: `{"matches_expected":false}` / apply-fallback: `exit 1` / spawn-recovery: `exit 1`) はいずれも「回復失敗」を返す設定になっている。回復に失敗すると `run_phase_with_recovery()` は元の exit code (143) をそのまま `return` し (`scripts/run-auto-sub.sh:881`)、呼び出し元 (`scripts/run-auto-sub.sh:972` 付近、XS route の `run_phase_with_recovery "code-patch" ...`) は `if` で戻り値を捕捉していないため、スクリプト冒頭の `set -euo pipefail` (`scripts/run-auto-sub.sh:7`) により `run-auto-sub.sh` プロセス全体がその場で exit code 143 のまま終了する。したがって新規テストは `[ "$status" -eq 143 ]` を assert すること。
- 上記はいずれも、Issue 本文の `/spec` への申し送り (テスト隔離が必須・`orchestration-recoveries.md` 事前作成が必要・H2 見出し timestamp は正規表現かプレフィックス一致で照合) を踏襲した上で、コードベース調査 (`scripts/run-auto-sub.sh:657-881`, `scripts/retry-on-kill.sh`, `tests/run-auto-sub.bats` の `setup()`) から追加で判明した実装上の注意点であり、SPEC_DEPTH=light のため `## spec retrospective` は省略し本セクションに集約した。
- 本 Issue はテストファイル1点のみの変更であり、`modules/doc-checker.md` の Impact Determination Criteria (ワークフロー変更・ディレクトリ構成変更等) に該当しないため、ドキュメント同期は不要と判断した。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective コメント。`/triage 1155` 実行時の申し送り (テスト隔離必須・`orchestration-recoveries.md` 未作成時の早期 return による false-pass リスク・H2 見出し timestamp を固定文字列で assert しないこと) を記録済みであることを確認する内容。Issue 本文にも要点は転記済みのため、本 Spec への追加反映は不要と判断した。 / https://github.com/saitoco/wholework/issues/1155#issuecomment-5373708352

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1・2 をそのまま実施した。

### Design Gaps/Ambiguities

- Notes の「終了ステータスは `[ "$status" -eq 143 ]` を assert すること」という指示は、実装コード (`run_phase_with_recovery` が `_write_wrapper_retry_recovery` 呼び出し後に元の exit code をそのまま `return` し、呼び出し元が戻り値を捕捉しないため `set -euo pipefail` でスクリプト全体が exit 143 する) と一致することを実行確認した。事前に運用への影響を懸念する余地はなかった。

### Rework

N/A — 手戻りなし。テスト単体実行 (`bats --filter`) で 1 回目から意図した分岐 (escalated) を検証できた。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 既存の success 分岐テスト (2564 行目) の直後に新規 `@test` を追加し、`run-code.sh` モックのみ両呼び出しとも `exit 143` を返すよう変更した。それ以外の隔離パターン (`git`/`gh` モック、`orchestration-recoveries.md` 事前作成) は転用した。
- 成功分岐テストの `[ "$status" -eq 0 ]` は転用せず、Spec Notes の指示通り `[ "$status" -eq 143 ]` を assert した。
- H2 の 5 セクション構成 (Context/Diagnosis/Recovery Applied/Outcome/Improvement Candidate) をそれぞれ個別に `grep -q "^### {section}$"` で検証し、rubric AC3 (H2 形式の 5 セクション構成の検証) を機械的にも担保した。

### Deferred Items
- None

### Notes for Next Phase
- `bats tests/run-auto-sub.bats` フルスイート (98 tests) が PASS 済み。新規テストは `retry-on-kill: wrapper-retry-on-kill recovery writes escalated Outcome on retry-also-killed` という名前で 89 番目。
- 実装コード (`scripts/run-auto-sub.sh`, `scripts/retry-on-kill.sh`) の変更は伴わない。テストファイル1点のみの変更。

## Issue Retrospective

### 実施内容

- Background の事実主張 (`_write_wrapper_retry_recovery()` の exit code 分岐、既存 success テストの有無、`escalated` 文字列 0 件、`orchestration-recoveries.md` への該当エントリ 0 件) をコードベース照合で確認 — すべて裏付けあり
- Steering Documents (`docs/product.md` / `docs/tech.md`) を参照し、用語 (`wrapper-retry-on-kill`, `orchestration recovery`) と Forbidden Expressions を確認 — 抵触なし、追加対応不要
- 曖昧性検出: 本 Issue は Size M (検出上限 3) だが、AC 本文がすでに具体的で曖昧点は検出されなかった (0 件)
- AC 分類・verify command 見直し:
  - AC1 の rubric に対する補助チェックとして `<!-- verify: file_contains "tests/run-auto-sub.bats" "escalated (retry also killed)" -->` を追加 (rubric + supplementary file_contains のガイドラインに従い、rubric の判定対象に固定文字列定数が含まれるため機械的な安全網を追加)
  - `### Post-merge` セクションが存在しなかったため `なし` で追加し、標準フォーマットに揃えた
- Background の 2 箇所 (「`escalated` 文字列は 0 件」「recoveries-auto-fire 対象エントリ 0 件」) に `<!-- premise: grep_count ... -->` マーカーを付与 — 本 Issue の実装によってこれらの前提は変化する (「テストが存在しない」状態を埋めるのが本 Issue の目的そのもののため)、`/audit premise` による再評価対象として明示した
- チェックボックス書式・observation 型 AC の `session=next` 整合性を機械チェック — いずれも問題なし
- Blocked-by 依存関係チェック — オープンなブロッカーなし
- サブ Issue 分割評価 — non-interactive mode のためスキップ (Size M・単一ファイル変更のため元々不要)

### Consumed Comments

- saito / MEMBER / first-class / `/triage 1155` 実行時の申し送りコメント。テスト隔離の必須要件 (未隔離だと本番の `orchestration-recoveries.md` に commit + push されてしまう)、`orchestration-recoveries.md` 未作成時の早期 return による false-pass リスク、H2 見出し timestamp を固定値で assert しないこと、の 3 点を記録。Issue 本文にも要点を転記済み / https://github.com/saitoco/wholework/issues/1155#issuecomment-5182722378
