# Issue #1020: run-auto-sub: --write-manual-recovery の EXIT_CODE 検証仕様を SKILL.md の記述と一致させる

## Overview

`scripts/run-auto-sub.sh --write-manual-recovery` の `_validate_recovery_args` は EXIT_CODE 引数を `^[0-9]+$` の数値のみ許容し、文字列 `unknown` を渡すと exit 1 で拒否する。一方 `skills/auto/SKILL.md` の External kill pre-check / Stop-and-Report Fallback 節は「EXIT_CODE が未観測の場合は `unknown` を渡す」という指示になっており、実装と矛盾する。

Issue 本文の Auto-Resolved Ambiguity Points の判断により、実装 (`_validate_recovery_args` の数値限定チェック) は変更せず、ドキュメント側の記述を「未観測時は引数を省略する」に統一する方向で修正する。コードベース調査の結果、同一の矛盾した文言が `modules/orchestration-fallbacks.md` (`#manual-recovery-spec-write`。`run-auto-sub.sh` 自身が SSoT として参照) および `docs/workflow.md` / `docs/ja/workflow.md` (External kill respawn 節) にも存在することを確認したため、これらも合わせて修正する。

## Consumed Comments

No new comments since last phase.

## Reproduction Steps

1. `/verify 1017` 実行中、外部kill pre-check手順に沿って以下を実行する (EXIT_CODE が未観測のため、当時の `skills/auto/SKILL.md` の記述通り文字列 `unknown` を渡す):
   ```bash
   bash scripts/run-auto-sub.sh --write-manual-recovery 1017 code respawn unknown
   ```
2. 次のエラーで exit 1 になることを確認する (2026-07-16 実環境で再現済み):
   ```
   _validate_recovery_args: invalid exit_code: 'unknown'
   ```

## Root Cause

`_validate_recovery_args` (`scripts/run-auto-sub.sh` 106-109行目) は EXIT_CODE (第4引数) が非空の場合に `^[0-9]+$` でのみ検証し、`unknown` を含む非数値文字列を意図的に拒否する。この意図は同ファイル312-315行目のコメント (dispatch 側で EXIT_CODE を `unknown` にデフォルト化してから渡すと数値チェックが常に FAIL するため、未指定時は空文字列のまま渡す設計であるという説明) と、`docs/spec/issue-1005-record-external-kill-respawn.md` の Code Retrospective (同じ問題が #1005 実装時に一度発生し、「dispatch では空文字列のまま渡し、`emit_event` の表示専用の値としてのみ `unknown` にデフォルト化する」という設計で解消した記録) から裏付けられる、既存の意図的な設計判断である。

一方、`skills/auto/SKILL.md` の External kill pre-check (Recording (mandatory)) と Stop-and-Report Fallback (Manual recovery hand-off) の2箇所、およびそれらの参照元/ミラーである `modules/orchestration-fallbacks.md` (`#manual-recovery-spec-write`) と `docs/workflow.md` / `docs/ja/workflow.md` (External kill respawn) は、いずれも「EXIT_CODE が未観測の場合は文字列 `unknown` を渡す」という指示のままになっており、この意図的な実装制約と矛盾している。バグの本質はドキュメントと実装の不一致であり、検証ロジック自体の欠陥ではない。

## Changed Files

- `skills/auto/SKILL.md`: 「External kill pre-check」節の Recording (mandatory) 箇条書き (927-931行目付近) と「Stop-and-Report Fallback」節の Manual recovery hand-off 段落 (1037行目) の EXIT_CODE 引数説明を、「未観測時は `unknown` を渡す」から「未観測時は引数を省略する (`unknown` という文字列は渡さない)」に修正する
- `modules/orchestration-fallbacks.md`: `manual-recovery-spec-write` の Fallback Steps (571-575行目) を同様に修正する。`run-auto-sub.sh` 自身のコードコメントがこのファイルの当該アンカーを SSoT として参照しているため、SKILL.md 側だけを直すと同じ矛盾がこの参照元経路に残存する
- `docs/workflow.md`: 「External kill respawn」段落 (119行目) の EXIT_CODE 引数説明を同様に修正する
- `docs/ja/workflow.md`: 上記 `docs/workflow.md` の変更を日本語ミラーに反映する (112行目)。`docs/translation-workflow.md` の Sync Procedure に基づく必須同期
- `tests/run-auto-sub.bats`: 既存の `--write-manual-recovery` バリデーションテスト群 (2139-2152行目付近) の近くに、EXIT_CODE に文字列 `unknown` を渡すと `_validate_recovery_args` が拒否することを確認する新規テストケースを追加する。テスト名には `-f 'exit_code'` フィルタにマッチさせるため部分文字列 `exit_code` を含める (bash 3.2+ 互換、既存テストと同じ `run bash "$SCRIPT" ...` パターンを踏襲するため追加の git/gh モックは不要)

## Implementation Steps

1. `skills/auto/SKILL.md` の2箇所 (External kill pre-check → Recording (mandatory)、Stop-and-Report Fallback → Manual recovery hand-off) を修正する。コマンドテンプレートを `EXIT_CODE` → `[EXIT_CODE]` (省略可能であることを明示) に変え、EXIT_CODE が未観測の場合は引数を省略する旨・文字列 `unknown` を渡してはいけない旨を明記する (→ acceptance criteria A)
2. `modules/orchestration-fallbacks.md` の `manual-recovery-spec-write` Fallback Steps を同じ方針で修正する (→ acceptance criteria A)
3. `docs/workflow.md` と `docs/ja/workflow.md` の External kill respawn 段落を同じ方針で修正する (`docs/translation-workflow.md` の Sync Procedure に従い両ファイルを同一コミットで更新する) (→ acceptance criteria A)
4. `tests/run-auto-sub.bats` に、EXIT_CODE として文字列 `unknown` を渡した場合に `_validate_recovery_args` が exit 1 で拒否することを確認する新規 `@test` を追加する。テスト名は部分文字列 `exit_code` を含めること (例: `"validate: --write-manual-recovery rejects literal 'unknown' exit_code (must omit the argument instead)"`)。アサーションは既存の同種テスト (2139-2152行目、`run bash "$SCRIPT" --write-manual-recovery ARGS` → `[ "$status" -ne 0 ]`) と同じパターンでよく、追加の git/gh モックは不要 (バリデーション失敗は git/gh 呼び出し前に `set -euo pipefail` 経由でスクリプト全体を終了させるため) (→ acceptance criteria B)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の _validate_recovery_args が EXIT_CODE=unknown を許容するか、もしくは skills/auto/SKILL.md の External kill pre-check / Stop-and-Report Fallback 節が unknown を渡す代わりに引数省略を指示するよう修正されている（ドキュメントと実装が一致している）" --> ドキュメントと実装が一致した状態になっている
- <!-- verify: command "bats tests/run-auto-sub.bats -f 'exit_code'" --> `_validate_recovery_args` の exit_code 検証を対象とした bats テスト (unknown 拒否ケースを含む) が PASS する

### Post-merge

なし

## Notes

- **Scope 拡張の判断根拠**: Issue 本文の AC1 rubric は `skills/auto/SKILL.md` の2節のみを名指ししているが、全文 grep (`unknown.*could not be observed` 等のパターン) の結果、同一の矛盾した文言が `modules/orchestration-fallbacks.md` と `docs/workflow.md` / `docs/ja/workflow.md` にも存在することを確認した。`run-auto-sub.sh` 自身のコードコメントが `modules/orchestration-fallbacks.md#manual-recovery-spec-write` を SSoT として参照しており、`docs/workflow.md` はユーザー向け workflow 説明の一次情報源であるため、これらを未修正のまま残すと同じ混乱が別の参照経路 (モジュールを直接読む、または `docs/workflow.md` を読む運用者) から再発する。rubric の充足条件は「SKILL.md 側の2節」に限定されていないため (どちらの方向で修正されていても rubric は満たされる)、この scope 拡張は rubric と矛盾しない。
- **調査方法の補足 (Steering Docs sync candidate check)**: `skills/auto/SKILL.md` が Changed Files に含まれるため、`grep -l "run-auto-sub\|/auto\b" docs/*.md docs/ja/*.md` によるスキル名ベースの候補洗い出しを実施したが、ヒット数が多く (13ファイル) 一般的すぎたため、より的確なキーワード `write-manual-recovery` で絞り込み、実際に古いコマンドテンプレートを含む `docs/workflow.md` / `docs/ja/workflow.md` のみを Changed Files に採用した。`docs/tech.md` にも `--write-manual-recovery` への言及があるが、EXIT_CODE 引数のリテラルテンプレートを含まないため (引数一覧を展開せず `run-auto-sub.sh --write-manual-recovery` とだけ記載) 修正対象外と判断した。
- **実装非変更の判断根拠**: `_validate_recovery_args` の数値限定チェックは、`run-auto-sub.sh` 自身のコードコメント (312-315行目) および `docs/spec/issue-1005-record-external-kill-respawn.md` の Code Retrospective に記録された過去の意図的な設計判断 (dispatch 側で EXIT_CODE を先にデフォルト化すると数値チェックが常に FAIL するため、未指定時は空文字列のまま渡す) と整合しているため、実装は変更しない。ドキュメント側の記述を実装に合わせる方向で統一する。
- **bats フィルタとの整合性**: 修正前時点で `bats tests/run-auto-sub.bats -f 'exit_code'` を実行すると、`exit_code` を含む既存テスト名が0件のため `1..0` で exit 0 (trivial pass) になることを確認済み。Implementation Step 4 で `exit_code` を含む実テストケースを追加することで、この verify command が実質的な検証として機能するようにする。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 を計画通りに実施した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Notes の「実装非変更の判断根拠」通り、`_validate_recovery_args` の数値限定チェックには手を入れず、ドキュメント側 (`skills/auto/SKILL.md` 2箇所、`modules/orchestration-fallbacks.md`、`docs/workflow.md`/`docs/ja/workflow.md`) のみを修正する方針を踏襲した。

### Deferred Items
- None

### Notes for Next Phase
- Behavioral Change Detection により、`skills/auto/SKILL.md` を直接参照する構造テスト (auto.bats, auto-batch.bats, auto-xl-concurrency.bats, auto-completion-report.bats, operate-route.bats, check-file-overlap.bats など) が direct counterpart 以外にも複数存在すると判定されたため、`bats tests/run-auto-sub.bats -f 'exit_code'` だけでなくフルスイート (`bats tests/`, 1207 件) を実行し、0 failures を確認済み。/verify での再実行時もこの前提を踏襲してよい。
- `scripts/check-translation-sync.sh` はこの Issue と無関係な既存の同期ギャップ (`docs/guide/autonomy.md` の ja 訳未作成、`docs/guide/index.md` の ja 訳が outdated) を検出したが、いずれも本 Issue の Changed Files に含まれないため対応不要と判断した。
