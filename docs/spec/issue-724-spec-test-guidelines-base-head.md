# Issue #724: spec-test-guidelines: base/head 比較 bats テストで branch-specific marker file パターンを追加

## Overview

`scripts/pre-merge-check.sh` の bats テスト実装中に、PRE_EXISTING (base=FAIL / head=FAIL) と CLEAN (base=PASS / head=PASS) シナリオで base と head が同一コンテンツになり `git commit` が空コミットエラーで失敗した。この問題は `_setup_feature_branch` に branch-specific marker file を追加することで回避できたが、Spec 段階でこのパターンを認識できれば code rework を防げた。

`skills/issue/spec-test-guidelines.md` に「git base/head 比較テストでは branch-specific marker file を追加する」パターンを追加することで、将来の git diff ベース比較ロジックの bats テスト設計時にこの問題を Spec 段階で予防できるようにする。

## Changed Files

- `skills/issue/spec-test-guidelines.md`: `## base/head 比較 bats テスト` 節を追加 — 空コミット回避用 branch-specific marker file パターンと適用シナリオ表を記述 (bash 3.2+ compatible: local 変数・echo のみ使用)

## Implementation Steps

1. `skills/issue/spec-test-guidelines.md` の末尾に `## base/head 比較 bats テスト` 節を追加する (→ AC1, AC2, AC3):
   - 節見出し: `## base/head 比較 bats テスト`
   - `空コミット` 回避の rationale と `git commit` 失敗シナリオの説明
   - `_setup_feature_branch` 関数の bash 実装例 (`marker-${branch}.md` ファイルを追加)
   - PRE_EXISTING / CLEAN シナリオで同一コンテンツになる旨の説明と `marker-` パターンが必要なシナリオ一覧表
   - 適用対象: git diff ベースの比較ロジック (`pre-merge-check.sh`、将来の diff ベーススクリプト)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "base/head 比較 bats テスト" --> `skills/issue/spec-test-guidelines.md` に base/head 比較 bats テスト節が追加されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "marker-" --> branch-specific marker file pattern が記述されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "空コミット" --> 空コミット回避の rationale が記述されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) bats 全件 green (patch route)

### Post-merge

- 次回 git diff ベース比較ロジックの Spec で `base/head 比較 bats テスト` 節が参照され、code phase で marker file 追加 rework がゼロになることを確認 <!-- verify-type: manual -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: post-merge verify-type を `observation event=spec` から `manual` に修正、post-merge 条件に `- [ ]` チェックボックスを追加 / [#issuecomment-4758917559](https://github.com/saitoco/wholework/issues/724#issuecomment-4758917559)

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-4759084582
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5200981287
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5212260231
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5225314201
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5229258017
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5235400401
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5246553662
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5255740764
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5296375420
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5296602813
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5304271319
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5304480467
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5305440413
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5310544334
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5310627468
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5313336697
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5327719751
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5327842414
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5329479668
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5341226974
- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/724#issuecomment-5341308562
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=7 / https://github.com/saitoco/wholework/issues/724#issuecomment-5354364044
## Notes

- 対象ファイル `skills/issue/spec-test-guidelines.md` は現時点で存在確認済み (domain file, type: domain, skill: issue)
- 既存セクション: Behavior Test Recommendation Guidelines / github_check パターン / SKILL.md verify commands / 境界値テスト / validate-skill-syntax.py 個別指定 / PoC・計測系 AC 設計ガイドライン
- 新節は末尾に追加する (既存セクションとの依存関係なし)
- `skills/` 以下のファイルは `docs/ja/` 翻訳対象外のため translation sync 不要
- テストファイル (`tests/pre-merge-check.bats`) は変更なし — 実装済みのパターンをガイドラインとして文書化するのみ
- Issue Retrospective で指摘の post-merge verify-type は Issue body 上で既に `manual` に更新済み

## Code Retrospective

### Deviations from Design
- None. Implementation followed the Spec exactly: appended `## base/head 比較 bats テスト` section at the end of `skills/issue/spec-test-guidelines.md` as specified.

### Design Gaps/Ambiguities
- The section heading level: the issue body proposed `### base/head 比較 bats テスト` (level 3), but the Spec specified `## base/head 比較 bats テスト` (level 2), which matches the existing section heading style in the file. Used level 2 as specified in the Spec.

### Rework
- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used level-2 heading `## base/head 比較 bats テスト` (matching existing section style), not level-3 as suggested in the issue body.
- Added a scenario table (`PRE_EXISTING / CLEAN / NEW_FAILURE / FIXED`) to make the applicability explicit.
- Content written in English body text with Japanese technical terms (`空コミット`, `marker-`) to match the existing file style.

### Deferred Items
- AC4 (github_check CI green) will be verified after push and CI completion.

### Notes for Next Phase
- All 3 file_contains ACs are already checked (`- [x]`) in the Issue body; only the `github_check` CI AC remains.
- No new scripts, modules, or structure changes — documentation-only change, so `/verify` should be straightforward.
- `validate-skill-syntax.py` does not scan domain files — no syntax validation concern for `spec-test-guidelines.md`.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 本文の `### base/head 比較 bats テスト` (レベル3見出し提案) を、既存節スタイルに合わせレベル2に変更する判断が適切だった

#### code
- rework なし。Spec の Implementation Steps をそのまま実装

#### review/merge
- patch route のため review/merge フェーズなし

#### verify
- pre-merge AC 4 件全 PASS。post-merge observation 条件は Issue body 上で `manual` → `observation event=auto-run` へ再変更されている (Spec の Verification 節記載時点の `manual` は古いスナップショット、Issue body が SSoT)

### Improvement Proposals
- N/A

### 2026-08-16 re-run (/auto --batch 1362 1358 1125 951 1329 1086 1328 1092 1085 セッションからの再評価)

`/auto --batch 1362 1358 1125 951 1329 1086 1328 1092 1085` (session `63449-1786797049`) の Batch Completion Report observation scan で `event=auto-run` が dispatch された (comment 履歴上は9回目の fired だが、Verify Retrospective への persist はこれが初回 — 過去の dispatch は都度 SKIPPED で "notable content なし" として Step 12 の skip 条件に該当し続けていたと推測される)。

#### verify (再評価分)

- 本 batch の 9 Issue (#1362, #1358, #1125, #951, #1329, #1086, #1328, #1092, #1085) の Spec を `grep -l "base/head 比較 bats\|marker-\${branch}\|branch-specific marker file"` で横断確認したが、いずれも該当なし。9 Issue のいずれも git diff ベース比較ロジックの bats テストを新規実装するものではなく、本条件が観察対象とする「次回 git diff ベース比較ロジックの Spec で本節が参照される」シナリオの前提自体が発生しなかった
- SKIPPED と判定 (観察対象の前提が本 run で成立しなかったため)

#### Improvement Proposals (再評価分)
- N/A — 前提未発生の health signal であり、改善提案の閾値には未到達

### 2026-08-16 re-run (2) (/auto --batch 1132 1348 1072 1363 1095 セッションからの再評価)

`/auto --batch 1132 1348 1072 1363 1095` (session `24095-1786827554`) の Batch Completion Report observation scan で `event=auto-run` が再度 dispatch された。

#### verify (再評価分)

- 本 batch の 5 Issue (#1132, #1348, #1072, #1363, #1095) の Spec を同様に grep 横断確認したが該当なし。前提未発生が継続。
- SKIPPED と判定 (観察対象の前提が本 run でも成立しなかったため)

#### Improvement Proposals (再評価分)
- N/A — 前提未発生の health signal であり、改善提案の閾値には未到達

### 2026-08-17 re-run (3) (/auto --batch 1096 1229 1243 1302 1273 セッションからの再評価)

`/auto --batch 1096 1229 1243 1302 1273` (session `58212-1786837134`) の Batch Completion Report observation scan で `event=auto-run` が再度 dispatch された。

#### verify (再評価分)

- 本 batch の 5 Issue (#1096, #1229, #1243, #1302, #1273) の Spec を同様に grep 横断確認したが該当なし。前提未発生が継続。
- SKIPPED と判定 (観察対象の前提が本 run でも成立しなかったため)

#### Improvement Proposals (再評価分)
- N/A — 前提未発生の health signal であり、改善提案の閾値には未到達

### 2026-08-18 re-run (4) (/auto --batch 1395 1382 1390 1391 セッションからの再評価)

`/auto --batch 1395 1382 1390 1391` (session `4899-1787037881`) の Batch Completion Report observation scan で `event=auto-run` が再度 dispatch された。

#### verify (再評価分)

- 本 batch の 4 Issue (#1395, #1382, #1390, #1391) の Spec を同様に grep 横断確認したが該当なし。前提未発生が継続。
- SKIPPED と判定 (観察対象の前提が本 run でも成立しなかったため)

#### Improvement Proposals (再評価分)
- N/A — 前提未発生の health signal であり、改善提案の閾値には未到達

### 2026-08-20 re-run (5) (/auto 1417 セッションからの再評価)

`/auto 1417` (session `71172-1787214280`) の完了後の event-based observation scan で `event=auto-run` が再度 dispatch された。

#### verify (再評価分)

- 本セッションの Spec (issue #1417, `preview-basic-auth-command` config key追加) を含め repository 全体を grep 横断確認したが該当なし。前提未発生が継続。
- SKIPPED と判定 (観察対象の前提が本 run でも成立しなかったため)

#### Improvement Proposals (再評価分)
- N/A — 前提未発生の health signal であり、改善提案の閾値には未到達
