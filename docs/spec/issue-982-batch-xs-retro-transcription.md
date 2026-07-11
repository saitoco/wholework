# Issue #982: auto: batch 経由 XS patch route に Issue Retrospective の Spec 転記を追加

## Overview

`/auto` の単一 Issue 経路 (patch route XS/S) は Step 4b で、XS Issue が完了した際に Issue コメントの `## Issue Retrospective` を Spec ファイルへ転記し、`/verify` の retro-proposals パイプラインおよび cross-session retro audit が issue retrospective を収集できるようにしている。しかし `/auto --batch` (Count mode / List mode) は phases を `run-auto-sub.sh` に委譲しており、同スクリプトには Step 4b 相当の転記処理が存在しない (grep 確認済み — Tier2/3 recovery 用の Spec 書き込みのみ)。このため batch 経由で処理された XS Issue は、Issue Retrospective コメントが存在していても Spec に転記されず、retro-proposals パイプラインと cross-session audit から不可視になる。

Issue body の Auto-Resolved Ambiguity Points により、実装先は `run-auto-sub.sh` (bash) ではなく `skills/auto/SKILL.md` の Batch Mode ステップ (List mode の Step 6 "Verify orchestration" 直前、Count mode の対応箇所) と確定している。既存の単一 Issue 経路と同じ `Step 4b: Issue Retrospective Transcription` を Count mode / List mode の両方から呼び出し、XS Size のみに限定して転記を実行する。あわせて Step 4b 自体に「Spec に `## Issue Retrospective` が既に存在する場合はスキップする」冪等性チェックを追加し、3 箇所の呼び出し元 (単一 Issue 経路 / Count mode / List mode) すべてで重複転記を防止する。

## Changed Files
- `skills/auto/SKILL.md`: Step 4b に冪等性チェックを追加し、Count mode / List mode に呼び出し箇所 (Size 保持を含む) を追加
- `tests/auto-batch.bats`: List mode / Count mode 双方の SKILL.md セクションに Step 4b 参照が存在することを確認する構造テストを追加

## Implementation Steps

1. `### Step 4b: Issue Retrospective Transcription (XS patch route only)` を修正する (→ acceptance criteria AC2):
   - 冒頭の説明文に「単一 Issue 経路の Step 4 に加え、Batch Mode の Count mode / List mode からも呼び出される」旨を追記する
   - 内部の Step 2 (Spec ファイルパス決定) に次を追記: 「**冪等性チェック**: 既存の Spec ファイルが既に `## Issue Retrospective` 見出しを含む場合、Step 3-4 をスキップする (既に転記済みのため重複転記しない)」

2. `### Count mode (--batch N)` の `#### Process Each Issue` を修正する (→ acceptance criteria AC1):
   - Step 3 (Size 再チェック) の文言を「call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is M, L, or XL: ...」に変更 (結果を変数として保持するのみで、既存の M/L/XL 除外挙動は変更しない)
   - 既存 Step 4 (run-auto-sub.sh 実行) の直後に新規 Step 5 を追加: 「**If `$ISSUE_SIZE` is XS**: transcribe issue retrospective to Spec (see Step 4b)」

3. `### List mode (--batch N1 N2 ...)` を修正する (→ acceptance criteria AC1):
   - Step 3 (Size 再チェック) の文言を「call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; retain the result as `$ISSUE_SIZE`; if `$ISSUE_SIZE` is XL: ...」に変更 (結果を変数として保持するのみで、既存の XL 除外挙動は変更しない)
   - 既存 Step 5 (run-auto-sub.sh 実行) と既存 Step 6 (Verify orchestration) の間に新規 Step 6 を挿入: 「**XS only**: transcribe issue retrospective to Spec (see Step 4b)」。既存 Step 6 (Verify orchestration) は Step 7 に繰り下げる (Step 5 の "On success: proceed to step 6" は新規挿入 Step 6 を指すため文言変更不要)

4. `tests/auto-batch.bats` にテストを追加する (→ acceptance criteria AC1, AC2):
   - 既存の `list_mode_section()` ヘルパーを使い、新規 `@test "List mode section: Issue Retrospective Transcription reference present"` を追加 (`grep -q 'Step 4b'` で確認)
   - 既存の `list_mode_section()` に倣った `count_mode_section()` ヘルパー (`awk '/^### Count mode/{found=1} /^### / && !/Count mode/{found=0} found{print}'`) を新規追加し、対応する `@test "Count mode section: Issue Retrospective Transcription reference present"` を追加

## Verification
### Pre-merge
- <!-- verify: rubric "run-auto-sub.sh または skills/auto/SKILL.md の batch mode 処理に、XS patch route 完了時に Issue コメントの ## Issue Retrospective を検索して Spec ファイル ($SPEC_PATH/issue-N-*.md、なければ新規作成) へ転記する Step 4b 相当の処理が存在する" --> batch 経由 XS patch route で Issue Retrospective の Spec 転記が実行される
- <!-- verify: rubric "Issue Retrospective コメントが存在しない場合は転記をスキップし、既存 Spec が存在する場合は重複転記しない (冪等) ことがテストまたは処理記述で保証されている" --> コメント不在時スキップ・重複転記防止が保証されている

### Post-merge
- 次回 `/auto --batch` で XS Issue を処理した際、Issue Retrospective が Spec に転記されることを観察<!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - 対象 Issue の Spec ファイル ($SPEC_PATH/issue-N-*.md) に `## Issue Retrospective` セクションが存在する
    - セクション内容が Issue コメントの `## Issue Retrospective` と一致する

## Notes

- **Auto-Resolved Ambiguity Points (Issue body より継承)**: 実装先は `run-auto-sub.sh` (bash) ではなく `skills/auto/SKILL.md` (LLM 層) の Batch Mode ステップと確定済み。理由: 単一 Issue 経路の Step 4b も SKILL.md 側 (LLM 層) で実装されており、bash 側に実装するとコメント本文からの短縮タイトル生成やセクション整形など Claude 判断を要するロジックの再実装が必要になり、既存パターンから乖離し複雑度が増すため。AC1 の rubric 文言は両実装先を許容する表現のため、AC テキストの変更は不要と判断。
- **Issue body vs 実装の整合性確認**: Issue body の「`run-auto-sub.sh` には Step 4b 相当の転記処理が存在しない」という記述は、`scripts/run-auto-sub.sh` の grep 調査 (`_write_tier2_recovery_to_spec` / `_write_tier3_recovery_to_spec` のみ存在し、Issue Retrospective 転記処理は存在しない) により正確であることを確認した。コンフリクトなし。
- **関連するが対象外の観察**: Size S の Issue は `/spec` フェーズを通るが、`SPEC_DEPTH=light` の場合 `/spec` の Step 13 (Spec Retrospective。Issue Retrospective の Spec 転記を含む) はスキップされる。そのため S サイズの Issue も同種の可視性ギャップを抱えている可能性があるが、これは Issue #982 の Purpose (「単一 Issue 経路との対称性回復」= XS 限定) の範囲外であり、本 Spec の実装対象には含めない。将来の別 Issue での検討候補として記録する。
- `docs/workflow.md` はバッチモードの挙動を要約する形で記述しており、単一 Issue 経路の Step 4b 自体も同文書には記載がない。既存の抽象度と整合させ、本 Issue でも `docs/workflow.md` の更新は行わない。
- Step 4b の `git push origin main` は単一 Issue 経路で既に採用されている既存パターンであり、batch mode からの呼び出しもこれをそのまま再利用する (batch 処理は Count/List いずれも Issue を逐次処理するため、同一セッション内での競合はない)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Issue #982 自身の Issue Retrospective — 実装先のあいまいさ解決根拠 (SKILL.md 側の Batch Mode ステップへの実装を推奨) を記録。内容は Issue body の Auto-Resolved Ambiguity Points セクションと同一。 / URL: https://github.com/saitoco/wholework/issues/982#issuecomment-4948305940

No new comments since last phase (code phase cutoff: 2026-07-11T18:48:25Z).

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 were followed as written; no reordering, omission, or approach change.

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented both Step 4b's idempotency-check text and the Count/List mode call sites exactly as specified in the Spec's Implementation Steps — no deviation.
- Added a `count_mode_section()` awk helper to `tests/auto-batch.bats` mirroring the existing `list_mode_section()` helper, so both batch modes have symmetric structural test coverage for the Step 4b reference.
- Since this Issue only edits `skills/auto/SKILL.md` (a file referenced by multiple test files beyond its direct counterpart), ran the full `bats tests/` suite per the Behavioral Change Detection check rather than scoping to `tests/auto-batch.bats` alone; all tests passed.

### Deferred Items
- None — Issue #982's scope is XS-only symmetry restoration; the Spec's Notes section already records the related-but-out-of-scope observation about Size S Issues under `SPEC_DEPTH=light` as a candidate for a future Issue.

### Notes for Next Phase
- Patch route (Size S): this Issue commits directly to `main`, so `/review` and `/merge` phases do not apply. `/verify` is the next phase.
- Post-merge AC is an `observation` type gated on the next real `/auto --batch` run processing an XS Issue — no action needed until that event fires naturally.
