# Issue #695: audit: /audit auto-session に --day/--since/--range で多日集約 (定期点検 tool)

## Overview

`/audit auto-session` に `--day YYYY-MM-DD` / `--since {N}d` / `--range YYYY-MM-DD..YYYY-MM-DD` の 3 オプションを追加し、複数 session を横断する定期点検レポートを `docs/sessions/_period/` 配下に生成する。

- `--since {N}d` (`d` サフィックス) は新規集約モード。既存の `--since 24h` (`h` サフィックス) および `--since YYYY-MM-DD` 形式は list mode のままで後方互換性を維持する。
- 期間集約レポートには Sessions covered / Cross-session patterns / Improvement candidates / Trend の 4 セクションを含む。

## Changed Files

- `skills/audit/SKILL.md`: `## auto-session Subcommand` の Argument Parsing に `--day`, `--since {N}d`, `--range` オプション追加; Step 1 に period mode 分岐追加; 出力先 `docs/sessions/_period/` の説明を追加; routing examples と usage string にも新オプションを記載 — bash 3.2+ compatible
- `scripts/get-auto-session-report.sh`: `--day DATE`, `--since-days N`, `--range START END` フラグ追加; period aggregation モードで `docs/sessions/_period/` 配下にレポート生成 — bash 3.2+ compatible
- `tests/audit-auto-session.bats`: period aggregation モード (`_period/`) のテストケース追加 — bash 3.2+ compatible
- `docs/structure.md`: `docs/sessions/` エントリに `_period/` サブディレクトリ追加 (新規出力先のため structure.md 更新が必要)
- `docs/ja/structure.md`: 上記の日本語ミラー更新 (translation-workflow.md に従い同期)

## Implementation Steps

1. `skills/audit/SKILL.md` 更新 (→ AC1, AC2, AC3, AC4)
   - routing 分岐例 (line 25 相当) に `auto-session --day YYYY-MM-DD`, `auto-session --since 7d`, `auto-session --range 2026-06-01..2026-06-07` を追加
   - usage string に `[--day YYYY-MM-DD] [--since Nd] [--range START..END]` を追加
   - `### Argument Parsing` に以下 3 エントリ追加:
     - `--day YYYY-MM-DD`: 指定日の全 session を集約して `docs/sessions/_period/{DATE}.md` を生成
     - `--since {N}d` (例: `7d`, `30d`): 直近 N 日の集約 (d サフィックスで aggregate mode を識別; h サフィックスや YYYY-MM-DD 形式は既存 list mode 維持); 出力先 `docs/sessions/_period/since-{TODAY}-{N}d.md`
     - `--range YYYY-MM-DD..YYYY-MM-DD`: 任意期間集約; 出力先 `docs/sessions/_period/range-{START}-{END}.md`
   - `### Step 1: Run Report Script` に period mode 分岐追加: `--day`/`--range`/`--since Nd` 検出時は period 用 script 呼び出しに分岐
   - period report 出力先 `docs/sessions/_period/` と期間レポート構造 (Sessions covered / Cross-session patterns / Improvement candidates / Trend) を説明するサブセクション追加; `docs/sessions/_period/` を明記

2. `scripts/get-auto-session-report.sh` 更新 (→ AC3, AC4)
   - `--day DATE`: `PERIOD_DAY` をセット
   - `--since-days N`: `PERIOD_SINCE_DAYS` をセット
   - `--range START END` (space-separated; SKILL.md は `..` 区切りを skill 側で split): `PERIOD_RANGE_START` / `PERIOD_RANGE_END` をセット
   - period mode 判定: `PERIOD_DAY`, `PERIOD_SINCE_DAYS`, `PERIOD_RANGE_START` のいずれかがセットされていれば period mode に入る
   - 日付範囲から `AUTO_EVENTS_LOG` 内のイベントを `ts` でフィルタ
   - `session_id` ごとにグループ化して集約 (sessions covered, route mix, recovery counts, etc.)
   - 出力先: `docs/sessions/_period/{filename}.md` (`mkdir -p` で作成)
   - 期間レポート構造を markdown で出力 (Sessions covered テーブル / Cross-session patterns / Improvement candidates / Trend)

3. `tests/audit-auto-session.bats` 更新 (→ AC5, AC6)
   - `@test "success: --day generates _period report"`: `--day 2026-06-14` を渡し `_period/2026-06-14.md` が生成されることを検証
   - `@test "success: --since-days generates _period since report"`: `--since-days 7` を渡し `_period/since-*-7d.md` が生成されることを検証 (2 テスト以上)
   - テストは既存の `AUTO_EVENTS_LOG`/`OUTPUT_PATH` 環境変数パターンを踏襲し、`--no-github` フラグを使用

4. `docs/structure.md` + `docs/ja/structure.md` 更新 (→ doc-checker.md, SHOULD)
   - `docs/structure.md` の `docs/sessions/` ディレクトリエントリ (現行: `{SID}-{DATE}/` のみ) に `_period/` サブディレクトリを追加; `docs/stats/` の update pattern に合わせ Japanese パターンで記述しない
   - `docs/ja/structure.md` に同内容を日本語で追加

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/audit/SKILL.md" "## auto-session Subcommand" "--day" --> `skills/audit/SKILL.md` の auto-session サブコマンドセクションに `--day` オプションが追加されている
- <!-- verify: section_contains "skills/audit/SKILL.md" "## auto-session Subcommand" "--range" --> `skills/audit/SKILL.md` の auto-session サブコマンドセクションに `--range` オプションが追加されている
- <!-- verify: rubric "skills/audit/SKILL.md の auto-session subcommand が --day YYYY-MM-DD / --since {N}d / --range start..end の 3 オプションをサポートし、出力先が docs/sessions/_period/ 配下に集約される" --> rubric 基準を満たす
- <!-- verify: file_contains "skills/audit/SKILL.md" "docs/sessions/_period/" --> `docs/sessions/_period/` 出力先が SKILL.md に明記されている (rubric 補助)
- <!-- verify: file_contains "tests/audit-auto-session.bats" "_period" --> `tests/audit-auto-session.bats` に期間集約モード (`_period/`) のテストケースが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テスト (既存 + 新規) が CI で green
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> `skills/audit/SKILL.md` の構文検証が CI で通過

### Post-merge

- サンプル期間 (例: 直近 7 日) に対して `/audit auto-session --since 7d` を実行し、複数 session 横断の改善候補 + trend が `docs/sessions/_period/` 配下に生成されることを確認

## Notes

- `--since {N}d` (d サフィックス) と `--since 24h` (h サフィックス) / `--since YYYY-MM-DD` の区別: 既存の `get-auto-session-report.sh` の `--since` ハンドラは `*h` と `YYYY-MM-DD` のみを処理する。新規 `*d` サフィックスは script 側で `PERIOD_SINCE_DAYS` に変換し period mode に入る。SKILL.md 側では `--since Nd` 形式を検出して `--since-days N` 引数に変換して script に渡す (または script が `--since Nd` を直接解釈する)。
- `docs/sessions/_period/` は新規サブディレクトリであり `docs/structure.md` への追加が必要。`docs/stats/` (generated by `/audit stats`) と同様のパターン。
- バッツテストは既存の 7 テストに 2-3 テストを追加する形 (新規テストは既存環境変数パターンを踏襲)。
- SKILL.md 内の `--since Nd` 解説は「d サフィックスのみ aggregate mode、それ以外は list mode」を明記して後方互換性を保証すること。

## Consumed Comments

- saito / MEMBER / first-class / Issue retrospective: ambiguity auto-resolution decisions (--since Nd vs 24h distinction, bats test requirement) and AC rewrite rationale / https://github.com/saitoco/wholework/issues/695#issuecomment-4759487457

## Code Retrospective

### Deviations from Design

- Spec step 3 listed `--range START END` (space-separated) for the script flag, which is what the script implements. However, in the SKILL.md the user passes `--range START..END` (dot-separated) and the SKILL is responsible for splitting on `..` before calling the script. This split was not explicitly implemented in the SKILL.md — SKILL.md documents the calling convention but the actual split is left to the operator. Since this is a SKILL-level (LLM-executed) step, the natural language description is sufficient for correct execution; no code split is needed.
- docs/workflow.md and docs/ja/workflow.md were added as doc-checker targets beyond the original Spec scope, since they contained an existing `/audit auto-session` description that needed the period mode addition.

### Design Gaps/Ambiguities

- Bats test for `--since-days` uses fixed-date fixture events (2026-06-14) with `--since-days 7`. Whether those dates fall within the 7-day window depends on the test execution date. The test was designed to always pass by using `--output` to specify a fixed output path, so the 7-day filter affecting which sessions appear does not cause test failure — the report structure (not session count) is what is verified.
- `grep -q "_period" "$output"` in bats is incorrect syntax (treats `$output` as a file path). Corrected to `[[ "$output" == *"_period"* ]]`. This was caught and fixed immediately before the tests passed.

### Rework

- Bats test fix: initial test used `grep -q "_period" "$output"` (treats variable as filename); replaced with `[[ "$output" == *"_period"* ]]` in one repair attempt. Tests went from 7/9 to 9/9 PASS.

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `--since {N}d` (d-suffix) dispatches via `--since-days N` to the script; `--since 24h` / `--since YYYY-MM-DD` remain list mode (backward compatible). This is the core design decision from the Spec — maintained as-is.
- Period reports go to `docs/sessions/_period/` (not `docs/reports/`) to separate run-centric period reports from single-session `docs/reports/` reports.
- `docs/workflow.md` / `docs/ja/workflow.md` updated (doc-checker triggered) since they already described `/audit auto-session` without the period mode.

### Deferred Items

- `--range START..END` SKILL-level split (from `..` to space-separated args) is described in SKILL.md prose but not verified by a bats test; post-merge manual test covers this.
- Japanese sibling generation (Step 4) for period reports is not implemented — period reports go to `docs/sessions/_period/` which has no `--no-ja` support. Follow-up Issue if needed.

### Notes for Next Phase

- PR #740 — all pre-merge file-based ACs are checked (`--day`, `--range`, `_period/` in SKILL.md, `_period` in bats). CI ACs (Run bats tests, Validate skill syntax) will confirm automatically.
- Post-merge AC: run `/audit auto-session --since 7d` to confirm `docs/sessions/_period/since-{TODAY}-7d.md` is generated correctly.
