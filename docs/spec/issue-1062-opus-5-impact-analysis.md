# Issue #1062: analysis: Claude Opus 5 (2026-07-24) の impact analysis と phase-specific matrix 更新

## Overview

2026-07-24 に Anthropic がリリースした Claude Opus 5 (`claude-opus-5`) について、`docs/tech.md` § Phase-specific model and effort matrix の記述を事実修正し、評価した上で見送った判断を記録として残す。`opus` alias の auto-resolve 仕様により Opus 5 は既に Wholework 上で稼働している (Opus 経路 7 箇所: `run-spec.sh --opus`、`issue-scope`/`issue-risk`/`issue-precedent`、`review-bug`/`review-spec`、`frontend-visual-review`) 一方、repo 内に "Opus 5" の記述はゼロだった (documentation drift、grep で確認済み) 。これは alias pin policy が明示的に受容したリスクが現実化したケースであり、`#628`/`#903` と同じ reactive-recalibration SOP で対応する。

本 Issue のスコープ:

- `docs/reports/claude-opus-5-impact-strategy.md` を先行レポート (`claude-sonnet-5-impact-strategy.md`) と同形式で新規作成する
- `docs/tech.md` の事実修正 4 点 (effort calibration 注記、alias 解決先、Fable 5 注記、cyber classifier リスク新規記載)
- default parent 切替 (Sonnet 5 → Opus 5) の見送り判定と再評価トリガーの記録
- watch 項目 2 点 (prompt cache 512 token 化、rate limit 別枠) の記録
- `agents/review-bug.md` の cyber classifier 注記を Opus 5 実行時にも成立する記述に一般化

sub-agent の `effort:` frontmatter 導入 (blocked-by 子 Issue #1063) と `run-spec.sh --opus` の effort 再校正 (blocked-by 子 Issue #1064) はいずれも本 Issue のスコープ外であり、子 Issue に委譲する。

## Changed Files

- `docs/reports/claude-opus-5-impact-strategy.md`: new file — `docs/reports/claude-sonnet-5-impact-strategy.md` と同じ §1 / §3〜§10 構成 (§2 は Fable 5 固有論点のため Sonnet 5 レポートと同様に省略)
- `docs/tech.md`: change — Phase-specific model and effort matrix 直後の注記段落群を編集 (詳細は Implementation Steps 2-4)
- `agents/review-bug.md`: change — cyber classifier 注記 (10 行目) を Opus 5 実行時にも成立する記述に一般化

## Implementation Steps

1. `docs/reports/claude-opus-5-impact-strategy.md` を新規作成する。`docs/reports/claude-sonnet-5-impact-strategy.md` を構造テンプレートとして使用し、以下の見出しに揃える (§2 は省略): `## 1. Executive Summary` / `## 3. Key Claude Opus 5 changes (relevant to Wholework)` / `## 4. Impact analysis (concrete)` / `## 5. Strategic recommendations` / `## 6. Impact summary table` / `## 7. Migration checklist` / `## 8. Candidate Issues (execution plan)` / `## 9. Non-goals` / `## 10. References`。
   - ヘッダ: Report date 2026-07-29、Model launched Claude Opus 5 (`claude-opus-5`) — 2026-07-24、Scope は Opus 経路 7 箇所に限定される旨を明記する (Sonnet 5 の default parent 切替とは異なり全経路影響ではない点を Sonnet 5 レポートとの対比として書く)。
   - §1 Executive Summary: Issue 本文 Background の Opus 5 主要特徴 (価格 $5/$25、1M context default/max、128K max output、effort ladder 5 段階 [`low`/`medium`/`high`/`xhigh`/`max`, default `high`]、prompt cache 最小 512 token、rate limit 別枠、cyber classifier、Fable 5 blocked biology リクエストのルーティング先変更) を要約し、alias pin policy が受容したリスクが現実化した最初の記録ケースである旨を記述する。
   - §3: Issue 本文 Background の特徴一覧を Sonnet 5 レポート §3 のサブセクション構成 (3.1 Pricing 等の番号立て) に準じて再構成する。
   - §4: default parent 切替の評価 (見送り・理由・再評価トリガー — `docs/tech.md` に書く内容と整合させる) と、Opus 経路 sub-agent の effort frontmatter 導入 (#1063)・`run-spec.sh --opus` の effort 再校正 (#1064) を deferred 項目として記述する。
   - §8: markdown table 形式とし、各行に **Priority** (`medium`/`medium`) と **Est. Size** (`M`/`M`) の列を値付きで含める。#1063 (`agents: Opus sub-agent に effort frontmatter を導入し親セッション継承から分離する`) と #1064 (`spec: run-spec.sh --opus の effort を Opus 5 指針で再校正する`) を行として含め、それぞれの役割を本文中に明記する。
   - §9 Non-goals: sub-agent effort frontmatter 実装 (#1063 に委譲)、`run-spec.sh --opus` effort 再校正 (#1064 に委譲)、default parent の実切替 (見送り確定) を明記する。
   (→ Pre-merge AC1, AC2, AC8)

2. `docs/tech.md` の `**Opus 4.8 effort calibration**` 段落 (matrix 表の直後) を 2 段落に分割する。
   - 新設: `**Opus 5 effort calibration**` — 「coding/agentic は `xhigh` 開始、それ以外は `high` 開始、そこから下方 sweep (`low`/`medium` が想定以上に強い)、`max` は極端に困難かつレイテンシ非感応な場合に限定」という指針を記述し、末尾に「Sub-agent `model: opus` / `model: sonnet` alias values in agent frontmatter auto-resolve to the current Opus (5).」を置く (`(4.8)` ではなく `(5)` にすること — Pre-merge AC4 が旧文字列 `auto-resolve to the current Opus (4.8)` の残存有無を検査する)。
   - 既存段落は **見出し文字列 `Opus 4.8 effort calibration` を一字一句変更せず** 保持し、「historical、`#922` が本注記を判定根拠として引用しているため保持」である旨を注記に追記する。末尾の alias 解決文 (`auto-resolve to the current Opus (4.8)`) は新設の Opus 5 段落に移したためこちらからは削除する。
   - **注意 (citation 保護)**: `docs/tech.md` の `**Sonnet 5 effort recalibration — spec (#922, C3)**` 段落が `the "Opus 4.8 effort calibration" note above` という形でこの見出しを直接引用している (`docs/tech.md:124`)。見出し文言を変更・削除すると `#922` の引用が解決不能になるため、既存見出しの文字列は保持必須。
   (→ Pre-merge AC3, AC4)

3. `docs/tech.md` の `**Fable 5 (Mythos class)**` 段落を編集する。
   - コスト比較の基準を `~3.3× Sonnet 4.6` から `~3.3× Sonnet 5` (standard pricing 基準) に更新する (`2× Opus 4.8` 側は Opus 5 と同額のため変更不要)。
   - 段落末尾に、biology 系リクエストのルーティング先変更 (Fable 5 の biology 分類でブロックされたリクエストは Opus 4.8 ではなく **Opus 5** にルーティングされるようになった。cyber 系ルーティング [Opus 4.8 のまま] は変更なし) を追記する。
   (→ Issue 本文 Proposal B.3。対応する Pre-merge AC は無いが Issue 本文 Proposal で明示的にスコープ内とされているため実施する。Notes 参照)

4. `docs/tech.md` の `**Alias pin policy**` 段落の直後に新規段落を 2 つ追加する。
   - `**Opus 5 default parent evaluation — deferred (#1062)**`: Sonnet 5 → Opus 5 の default parent 切替を評価した上で見送ったこと、理由 3 点 ((a) `#914` の default parent 確定が約 4 週間前と直近であること、(b) `#921`/`#922`/`#923` の Sonnet 5 effort 再校正が全て maintain 判定で終わっていること、(c) Opus 5 は Sonnet 5 の 1.7〜2.5 倍コスト [introductory $2/$10 比 2.5倍、standard $3/$15 比 1.7倍] であり測定チェーン [`#877`/`#878` 相当] を再実施するに見合う品質差の根拠が無いこと)、および再評価トリガー (Sonnet 5 の品質不足の証跡が今後出た場合、または Claude Max の default model が Opus 5 になった点が Wholework の default parent 判断にとって重みを持つと判断された場合) を記述する。
   - `**Opus 5 watch items**`: (1) prompt cache 最小プロンプトが **512** token (Opus 4.8 の 1024 から半減) である点、(2) Opus 5 の rate limit が Opus 4.x の統合プールとは別枠であり `/auto --batch` の L/XL Opus sub-agent 並列展開時の headroom に影響し得る点、の 2 点を記録する。
   (→ Pre-merge AC6, AC7)

5. `agents/review-bug.md` の 10 行目 (`> **Note (Fable 5):** ...`) を編集し、Fable 5 実行時に限定されない記述に一般化する。review-bug のデフォルトモデル (frontmatter `model: opus`) が現在 Opus 5 に解決されること、Opus 5 自体が cyber classifier を持つこと (Fable 5 比 ~85% 低頻度、flagged 時は Opus 4.8 へ fallback) を明記し、Fable 5 実行時の既存記述 (security-related queries が Opus 4.8 へルーティングされ得る) と並記して両ケースを網羅する。
   (→ Pre-merge AC5)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/claude-opus-5-impact-strategy.md" --> <!-- verify: grep "## 1. Executive Summary" "docs/reports/claude-opus-5-impact-strategy.md" --> <!-- verify: grep "## 8. Candidate Issues" "docs/reports/claude-opus-5-impact-strategy.md" --> `docs/reports/claude-opus-5-impact-strategy.md` が新規作成され、先行レポートと同じ主要セクション (Executive Summary / Candidate Issues) を持つ
- <!-- verify: rubric "docs/reports/claude-opus-5-impact-strategy.md の §8 Candidate Issues セクションが markdown table 形式であり、各行に Priority (urgent/high/medium/low) と Est. Size (XS/S/M/L/XL) の 2 列が値付きで存在する" --> レポート §8 Candidate Issues の各行に Priority と Est. Size 列が付与されている
- <!-- verify: file_contains "docs/tech.md" "Opus 5" --> <!-- verify: rubric "docs/tech.md の Phase-specific model and effort matrix 直後の注記段落群に、Opus 5 の effort 指針 (coding/agentic は xhigh 開始・それ以外は high 開始、そこから下方 sweep、max は限定的に使用) が記述されている" --> `docs/tech.md` の effort calibration 注記が Opus 5 の指針に更新されている
- <!-- verify: file_not_contains "docs/tech.md" "auto-resolve to the current Opus (4.8)" --> `docs/tech.md` の sub-agent alias 解決先の記述が Opus 4.8 を現行として指していない
- <!-- verify: file_contains "agents/review-bug.md" "Opus 5" --> <!-- verify: rubric "agents/review-bug.md の cyber classifier に関する注記が Fable 5 実行時に限定されず、Opus 5 実行時にも成立する記述に一般化されている" --> `agents/review-bug.md` の cyber classifier 注記が Opus 5 でも成立する旨に一般化されている
- <!-- verify: rubric "docs/tech.md に、default parent を Sonnet 5 から Opus 5 へ切り替える案を評価した上で見送ったこと、その理由、および将来の再評価トリガーが記述されている" --> `docs/tech.md` に default parent 切替の見送り判定と再評価トリガーが記録されている
- <!-- verify: file_contains "docs/tech.md" "512" --> <!-- verify: rubric "docs/tech.md に Opus 5 の watch 項目として prompt cache 最小プロンプトの 512 token 化と、rate limit が Opus 4.x プールと別枠である点の 2 点が記録されている" --> `docs/tech.md` に watch 項目 2 点が記録されている
- <!-- verify: rubric "docs/reports/claude-opus-5-impact-strategy.md に、本 Issue から派生した子 Issue (sub-agent effort frontmatter 導入 / run-spec.sh --opus effort 再校正) の Issue 番号と役割が言及されている" --> レポートに子 Issue の番号と役割が明記されている

### Post-merge

- 次回 `/audit drift` narrative check で Opus 5 関連の documentation drift が検出されない (verify-type: opportunistic)
- レポート §8 の Candidate Issues のうち Priority=high 以上のものが起票済み、または既存 Issue にマッピング済みである (verify-type: manual — #1063/#1064 はいずれも Priority=medium のため該当なしの見込みだが、`/verify` 時点で最新の Priority を再確認すること)

## Notes

- **`docs/ja/tech.md` はスコープ外**: Issue Retrospective コメント (Consumed Comments 参照) で、`docs/ja/tech.md` は `/doc translate` による生成物であるため受入条件の verify command 対象から除外する判断が既に記録されている。本 Spec もこの判断を踏襲し、Changed Files / Implementation Steps に含めない。`docs/translation-workflow.md` の一般的な sync procedure (top-level `docs/*.md` 変更時は `docs/ja/` ミラーを同期) より、Issue 個別の明示的な triage 判断を優先した。
- **`docs/reports/` は翻訳同期対象外**: `docs/translation-workflow.md` § Exclusions により `docs/reports/` は sync 対象外と明記されている。先行する `claude-sonnet-5-impact-strategy.md` も `docs/ja/reports/` ミラーは「独立した手動判断」として扱われている (同レポート §9 Non-goals) 。本 Issue でも `docs/ja/reports/claude-opus-5-impact-strategy.md` は作成しない (Out of Scope に準じる、必要になれば別途判断)。
- **Fable 5 段落の biology routing 追記に専用 verify command が無い理由**: Implementation Step 3 (Fable 5 段落のコスト基準更新 + biology routing 追記) は Issue 本文 Proposal B.3 で明示的にスコープ内とされているが、対応する Pre-merge Acceptance Criteria は存在しない (Issue 本文 Verify command sync rule に従い Issue 本文の AC 一覧を SSoT として扱うため、Spec 側で新規 AC を追加していない)。実施はするが機械検証はされない SHOULD レベルの修正として扱う。
- **citation 保護 (重要)**: `docs/tech.md:124` の `#922` 再校正段落が `**Opus 4.8 effort calibration**` という見出し文字列を直接引用している。Implementation Step 2 でこの見出しをリネームすると `#922` の引用が解決不能になるため、既存見出しの文字列は変更せず保持し、新設の `**Opus 5 effort calibration**` 段落を別途追加する 2 段落構成を採用した (Issue 本文の Auto-Resolved Ambiguity Points で既に「既存注記を Opus 5 向けに改稿するが Opus 4.8 固有の記述は履歴的注記として残す」方針が決定済み — 本 Notes はその実装レベルの具体化)。
- **Simplicity rule と Pre-merge Verification 件数の関係**: light depth の目安件数は 5 件だが、Pre-merge Verification は Issue 本文の `## Acceptance Criteria > Pre-merge` (8 件) を verbatim でコピーする Verify command sync rule が優先されるため、8 件のまま据え置いている。Implementation Steps 側は 5 件に収まるようグルーピングした。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective コメント。(1) #1063/#1064 を sub-issue ではなく blocked-by で連結した理由 (本 Issue が Size M の単独完結タスクであり sub-issue 分割時の XL 昇格ルールと整合しないため、および Sonnet 5 の先行連鎖 [#876 他] も blocked-by 構成だったため)、(2) Triage 判定根拠 (Type=Task、Size=M、Value=5、Priority=high)、(3) `docs/ja/tech.md` を受入条件の verify command 対象から除外した判断、を記録。(https://github.com/saitoco/wholework/issues/1062#issuecomment-5111778278)

### /code phase

No new comments since last phase (cutoff: 2026-07-29T02:02:15Z, most recent `phase/*` label assignment).

## Code Retrospective

### Deviations from Design

- None. All 5 Implementation Steps were executed as specified, including the two-paragraph split for the effort calibration note (heading text preserved verbatim for `#922`'s citation) and the placement of the deferral/watch-item paragraphs directly after the Alias pin policy paragraph.

### Design Gaps/Ambiguities

- None found during implementation. The Spec's Notes section (citation protection, `docs/ja/tech.md` exclusion, `docs/reports/` translation-sync exclusion) matched the actual repository state exactly, so no additional judgment calls were required beyond what the Spec already resolved.

### Rework

- One process correction, not implementation rework: while updating Issue #1062's pre-merge checkboxes, a `.tmp/` scratch file was first written via a `python3 -c` Bash invocation, which violates the global CLAUDE.md rule requiring the Write tool for all `.tmp/` file creation (Bash redirects/scripts are prohibited for this purpose). Caught before committing; the file was deleted and recreated correctly via Read + Write. No implementation file was affected.

## review retrospective

### Spec vs. implementation divergence patterns

None. Implementation matched the Spec's 5 Implementation Steps exactly. The single review finding (dangling `(§ Implementation Steps N)` self-references inside the newly created report) was a documentation-quality slip introduced when Spec-internal section-reference phrasing leaked into the disposable report's own prose — not a Spec/code divergence, since the Spec never specified that phrasing for the report body.

### Recurring issues

None. The one SHOULD finding was a single, isolated instance (an internal cross-reference naming mismatch), not a pattern repeated across multiple files or sections in this PR.

### Acceptance criteria verification difficulty

None. All 8 Pre-merge conditions carried well-specified verify commands (`file_exists` / `grep` / `file_contains` / `file_not_contains` / `rubric`) and all resolved to PASS deterministically on the first pass — no UNCERTAIN classifications and no verify command corrections were needed.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash-merged PR #1067 into `main` with no conflicts (`mergeable=true`, `reason=clean`, CI green, review approved) — no rebase/conflict-resolution path was needed.
- Wrote this Phase Handoff after fast-forwarding the worktree to `origin/main` (which now contains the squash commit), per the standard merge-phase handoff procedure.

### Deferred Items
- None beyond what prior phases already deferred to `#1063`/`#1064` (sub-agent `effort:` frontmatter, `run-spec.sh --opus` effort recalibration) — merge surfaced no new deferrable work.

### Notes for Next Phase
- `/verify 1062` should check the 2 Post-merge conditions recorded in the Verification section: (1) no Opus 5-related drift surfaces in the next `/audit drift` narrative check (opportunistic), (2) re-confirm `#1063`/`#1064` are still Priority=`medium` at verify time (below the Priority=high filing threshold).
- Issue #1062 is expected to auto-close via `closes #1062` in the PR body since `BASE_BRANCH=main`; verify should double check `state=CLOSED` and `phase/verify` label landed correctly.

## Auto Retrospective

### Manual recovery (merge)
- **Date**: 2026-07-29 03:02 UTC
- **Issue**: #1062, phase: merge
- **Source**: parent session manual recovery
- **Recovery type**: completion-override
- **Wrapper exit code**: unknown
- **Outcome**: success

### Manual recovery (review)
- **Date**: 2026-07-29 03:02 UTC
- **Issue**: #1062, phase: review
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success
