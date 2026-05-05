# Issue #419: run-verify VERIFY_FAILED False-Positive Fix

## Overview

`scripts/run-verify.sh` detects the `VERIFY_FAILED` marker using `grep -q "VERIFY_FAILED"` (no line-start anchor), causing false positives when the literal string appears anywhere in the verify output — including within quoted Acceptance Criteria text. The fix changes detection to `grep -q "^VERIFY_FAILED"` (line-anchored) so only a marker at line start triggers non-zero exit.

## Reproduction Steps

1. Run `/auto --batch 403 401 400`
2. During Issue #401 verify, the output includes text "Issue #393 類似の VERIFY_FAILED シナリオ" within the Acceptance Criteria body
3. `scripts/run-verify.sh:130` detects "VERIFY_FAILED" in that body text via unanchored `grep -q "VERIFY_FAILED"`
4. `run-verify.sh` returns exit 1 despite verify succeeding
5. `/auto` counts the batch item as failed and enters recovery mode

## Root Cause

`scripts/run-verify.sh:130` uses `grep -q "VERIFY_FAILED"` without a line-start anchor. `skills/verify/SKILL.md` specifies the marker as a standalone-line output, but the wrapper is not anchored — any occurrence in the output body triggers the false positive. `tests/run-verify.bats:119` tests only the standalone-line case and does not cover the body-text false-positive scenario.

## Changed Files

- `scripts/run-verify.sh`: change `grep -q "VERIFY_FAILED"` → `grep -q "^VERIFY_FAILED"` at line 130 — bash 3.2+ compatible
- `skills/verify/SKILL.md`: update VERIFY_FAILED marker output description to explicitly state line-anchored requirement (add "line-anchored")
- `tests/run-verify.bats`: add false-positive regression test — VERIFY_FAILED in body text (non-line-start) must exit 0

## Implementation Steps

1. In `scripts/run-verify.sh`, change line 130 from `grep -q "VERIFY_FAILED"` to `grep -q "^VERIFY_FAILED"` — bash 3.2+ compatible (→ AC1)
2. In `skills/verify/SKILL.md`, change the VERIFY_FAILED marker description near line 77 from `at the start of the error message (\`run-verify.sh\` detects this marker to propagate the error)` to `as a standalone line (line-anchored: \`run-verify.sh\` detects it with \`^VERIFY_FAILED\` pattern)` — also apply consistent phrasing near line 123 (open PR case) (→ AC2)
3. In `tests/run-verify.bats`, add a new `@test` case with name containing "false-positive": mock claude outputs VERIFY_FAILED embedded in body text (not at line start), assert exit 0 (→ AC3, AC4)

## Verification

### Pre-merge

- <!-- verify: grep "\"\\^VERIFY_FAILED\"" "scripts/run-verify.sh" --> `scripts/run-verify.sh` の VERIFY_FAILED 検出が行頭錨点 (`^VERIFY_FAILED`) パターンに変更されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "line-anchored" --> `skills/verify/SKILL.md` のマーカー出力仕様 (独立行) が wrapper 側の行頭錨点 (line-anchored) 検出と整合していると明記されている
- <!-- verify: file_contains "tests/run-verify.bats" "false-positive" --> `tests/run-verify.bats` に false-positive 回帰検出テストケースが追加されている (本文中に "VERIFY_FAILED" を含むが行頭ではない出力が exit 0 となること)
- <!-- verify: command "bats tests/run-verify.bats" --> `bats tests/run-verify.bats` が全件 PASS する

### Post-merge

- Acceptance Criteria 本文に "VERIFY_FAILED" 文字列を含む verify を `/verify 401` 等で再実行した際に wrapper exit 0 で完了することを確認 <!-- verify-type: opportunistic -->

## Notes

- New test name recommendation: `@test "false-positive: VERIFY_FAILED in body text does not cause non-zero exit"` — mock claude outputs `"This AC mentions the VERIFY_FAILED scenario from issue #393"` (not at line start), asserts `[ "$status" -eq 0 ]`
- `tests/run-verify.bats` will contain "VERIFY_FAILED" as a test fixture string, but the pattern `^VERIFY_FAILED` checks only verify output temp files, not source files — no self-reference exclusion needed
- Verify commands copied verbatim from Issue body `## Acceptance Criteria > Pre-merge`

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- Spec Step 2 noted updating "near line 77" and "also apply consistent phrasing near line 123 (open PR case)". The line 123 context was a description line (`If \`OPEN_PR\` is not empty, output \`VERIFY_FAILED\` and abort:`) that did not itself say "standalone line" or "line-anchored" — updated it to match the same wording for consistency.

### Rework

- N/A

## review retrospective

### Spec vs. 実装乖離パターン

特筆事項なし。Spec 記載のステップ 1–3 がすべて diff と 1:1 対応しており、乖離なし。

### 繰り返し課題

特筆事項なし。レビュー指摘事項 0 件。

### 受け入れ条件検証難易度

- AC1 (`grep "\"\\^VERIFY_FAILED\""`): verify コマンドの `\\^` エスケープ解釈が若干複雑 — 実際には `grep -q "^VERIFY_FAILED"` という文字列が存在するかの確認であり、直接 Grep で `\^VERIFY_FAILED` を検索することで判断可能だった。
- AC4 (`command "bats tests/run-verify.bats"`): safe モードのため CI 参照フォールバックを使用 (PASS 確定)。verify コマンドとして `command` を使用した場合、`/review` フェーズでは常に CI 依存になる — CI が未完了の場合は UNCERTAIN になる点に留意が必要だが、今回は問題なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 根本原因・再現ステップ・変更ファイルがSpecに明確に記述され、実装との乖離は一切なかった。
- line 123 の整合性対応（SKILL.md の2箇所への "line-anchored" 統一）がSpecで明示されており、実装者が見落とさなかった点は良い設計。

#### design
- N/A（設計フェーズは spec と統合）

#### code
- 単一クリーンコミット（14954c6）、fixup/amend なし。Specの全ステップが diff と1:1対応。
- Code Retrospective が記録した「line 123 の文脈の差異」は軽微だが、Specに明示されていたため実装で正しく処理された。

#### review
- レビューコメント0件（MUST/SHOULD/CONSIDER すべてゼロ）。CI全件PASS。効果的なレビューだった。
- Review Retrospective が AC1 verify コマンドの `\\^` エスケープの複雑さを指摘済み。今後 `file_contains "scripts/run-verify.sh" "^VERIFY_FAILED"` を代替として検討できる（同等の検証がより読みやすい形で可能）。

#### merge
- PR #420 でコンフリクトなし・クリーンマージ。

#### verify
- Pre-merge 4件すべて PASS（grep, file_contains×2, command）。bats 14件全件PASS（ok 8 false-positive テストを含む）。
- Post-merge opportunistic 条件（`/verify 401` 再実行）はユーザー検証待ち（phase/verify 割り当て済み）。

### Improvement Proposals
- AC1 の verify コマンド (`grep "\"\\^VERIFY_FAILED\"" "scripts/run-verify.sh"`) は機能するが、エスケープ解釈が複雑。同等検証なら `file_contains "scripts/run-verify.sh" "^VERIFY_FAILED"` がより明瞭（将来の類似Issueでの参考例として記録）。
