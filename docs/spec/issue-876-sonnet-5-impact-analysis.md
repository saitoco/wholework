# Issue #876: Claude Sonnet 5 (2026-06-30) の impact analysis と phase-specific matrix 更新

## Overview

2026-06-30 に Anthropic が Claude Sonnet 5 (`claude-sonnet-5`) を発表した ( [announcement](https://www.anthropic.com/news/claude-sonnet-5) ) 。本 Issue は Sonnet 5 が Wholework の phase-specific model/effort matrix および skill 挙動に与える影響を分析し、`docs/reports/claude-fable-5-impact-strategy.md` と同構成の impact strategy レポートを起票する。

本 Spec のスコープは Migration path Phase 1 (レポート起票 + skill/script 影響箇所インベントリ + tech.md への軽量注記追加) に限る。Phase 2 (default parent 実際の切替) 、Phase 3 (effort 再校正) 、Phase 4 (`--effort=` フラグ露出) は本 Issue のレポート §8 で提案する follow-up Issue に切り出す。関連 blocked-by 子 Issue: `#877` (verify 再測定) 、 `#878` (tokenizer 影響測定) 。

## Consumed Comments

No new comments since last phase.

## Changed Files

- `docs/reports/claude-sonnet-5-impact-strategy.md`: new file — Fable 5 レポートと同構成 (§1〜§10) 。 §3 で Sonnet 5 の変更点、§4 で Wholework への具体的影響、§5 で戦略勧告、§6 で priority table、§7 で Migration checklist、§8 で Candidate Issues (Priority/Est. Size 列付き) を含む。少なくとも 200 行規模を想定
- `docs/tech.md`: change — Phase-specific model/effort matrix section の "Fable 5 (Mythos class)" 段落の直後に **Sonnet 5** 段落を追加。内容: default parent (現状 Sonnet 4.6) との位置づけ、Opus 4.8 との cost/perf 比較、tokenizer 1.0〜1.35× 影響への言及、および `docs/reports/claude-sonnet-5-impact-strategy.md` へのリンク。matrix 表本体は変更しない (実際の default 切替は Phase 2 の別 Issue で扱う)

**"No change needed" 判定**:
- `docs/ja/tech.md`: `docs/tech.md` の変更に追従した ja mirror 更新が必要。ただし本 Issue のスコープを保つため、この更新は本 Spec の Implementation Steps に含めず、tech.md 変更 PR 時に `docs/translation-workflow.md` の sync 手順で機械的に反映する扱い (verify command 対象外) 。**Steering Docs sync candidate**: 次回の tech.md 変更時に更新確認する
- `docs/ja/reports/claude-sonnet-5-impact-strategy.md`: `docs/translation-workflow.md` の Exclusions で `docs/reports/` は sync 対象外と明記されているため、本 Issue では作成しない
- `docs/structure.md`: `docs/reports/` ディレクトリツリー entry は既存記述で新規ファイルを個別に列挙していないため、structure.md の更新は不要 (直近の `sonnet-effort-recalibration.md` / `tokenizer-audit.md` 追加時にも structure.md に個別列挙されていない先例あり)

## Implementation Steps

**Step recording rules:**
- Insertion positions specified by nearby code context (not line numbers)
- Each step maps to acceptance criteria

1. `docs/reports/claude-sonnet-5-impact-strategy.md` を新規作成。冒頭に English/日本語言語スイッチャー ( `docs/reports/claude-fable-5-impact-strategy.md` L1 と同形式) 、Report date/Author/Model launched/Scope/Status フィールド、Companion クロスリンク (Fable 5 レポート) を配置 (→ acceptance criteria A)
2. §1 Executive Summary を執筆: Sonnet 5 の agentic 性能向上と cost/perf 特性、Wholework 設計哲学との整合、主要な移行判断 (default parent 見直し・effort 再校正・sub-agent 継続判断) 、必要な follow-up Issue 数の要約 (→ acceptance criteria A)
3. §2 "Does Wholework still have a reason to exist?" 相当のセクションは Sonnet 5 では省略可 (Fable 5 report で議論済みかつ Sonnet 5 は Fable 5 より下位 tier のため既存議論が transitive に成り立つ) 。省略の旨を §1 末尾に 1 行明記 (→ acceptance criteria A)
4. §3 Key Sonnet 5 changes を執筆: pricing ($2/$10 導入・$3/$15 標準・Opus 4.8 との比較) 、tokenizer 1.0〜1.35× 変更 (Opus 4.7 と同種) 、effort カーブの広がり (medium/xhigh の cost/perf 特性) 、cyber safeguard レベル (Fable 5 より緩い) を項目別に整理 (→ acceptance criteria A)
5. §4 Impact analysis を執筆: (4.1) default parent 切替判定の decision matrix、 (4.2) phase 別 effort 再校正の候補、 (4.3) sub-agent (Opus alias) の継続判断根拠、 (4.4) tokenizer 影響 (→ #878 に委譲) 、 (4.5) `/verify` 動作改善の期待値 (→ #877 に委譲) 、 (4.6) 判定基準 draft (Issue body § B との整合) を含む (after 4) (→ acceptance criteria A, B)
6. §5 Strategic recommendations と §6 Impact summary table を執筆: 各推奨に Priority (P0〜P3) を付与し、Fable 5 report §6 と同形式の table を作る (after 5) (→ acceptance criteria A)
7. §7 Migration checklist を執筆: 最低 3 項目のチェックボックス ( `- [ ]` ) 形式で本 Issue で実施する項目 (レポート作成完了・tech.md 注記追加・candidate Issues 起票済み) を含む。追加でオプション項目 (Phase 2 準備、Phase 3 準備、Phase 4 の Icebox 判定など) を任意で列挙 (after 6) (→ acceptance criteria E)
8. §8 Candidate Issues (execution plan) を執筆: markdown table 形式で `# / Title (Japanese) / Priority / Est. Size / Phase impact` の 5 列。行に本 Issue の子 Issue `#877` `#878` を明示的に含め、Phase 2/3/4 の予定 Issue を C1〜Cn として列挙。Priority=urgent/high/medium/low、Size=XS/S/M/L/XL を厳守 (after 7) (→ acceptance criteria B, C)
9. §9 Non-goals と §10 References を執筆: Non-goals では本 Issue で扱わない範囲 (Fable 5 default swap、per-agent frontmatter model 個別変更、default parent 実際の swap) 、References では Anthropic 公式アナウンス URL、Fable 5/Opus 4.7 report への相互リンク、tech.md § model-effort-matrix へのリンクを含む (after 8) (→ acceptance criteria A)
10. `docs/tech.md` の "Fable 5 (Mythos class)" 段落 (`**Fable 5 (Mythos class)**: Fable 5 ( \`claude-fable-5\` ) ...`) の直後 (かつ "SSoT note:" の前) に **Sonnet 5** 段落を挿入。内容: Sonnet 5 が Sonnet 4.6 と比べ agentic 性能で向上し Opus 4.8 に迫る cost/perf、tokenizer 更新の含意、matrix 本体の default 切替は本注記段階では行わず Phase 2 Issue で扱う旨、`docs/reports/claude-sonnet-5-impact-strategy.md` への参照リンク (parallel with 1-9) (→ acceptance criteria D)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/claude-sonnet-5-impact-strategy.md" --> <!-- verify: section_contains "docs/reports/claude-sonnet-5-impact-strategy.md" "## 1. Executive Summary" "Sonnet 5" --> <!-- verify: grep "## 8. Candidate Issues" "docs/reports/claude-sonnet-5-impact-strategy.md" --> Impact analysis report が Executive Summary / Candidate Issues の主要セクションを持って新規作成されている (AC A)
- <!-- verify: file_contains "docs/reports/claude-sonnet-5-impact-strategy.md" "#877" --> <!-- verify: file_contains "docs/reports/claude-sonnet-5-impact-strategy.md" "#878" --> 子 Issue #877 / #878 への言及が report に含まれている (AC B)
- <!-- verify: rubric "docs/reports/claude-sonnet-5-impact-strategy.md の §8 Candidate Issues セクションが markdown table 形式であり、各行に Priority (urgent/high/medium/low) と Est. Size (XS/S/M/L/XL) の 2 列が値付きで存在する" --> §8 Candidate Issues の各行に Priority と Est. Size が付与されている (AC C)
- <!-- verify: file_contains "docs/tech.md" "Sonnet 5" --> <!-- verify: file_contains "docs/tech.md" "claude-sonnet-5-impact-strategy.md" --> `docs/tech.md` に Sonnet 5 注記段落が追加されレポートへのリンクが張られている (AC D)
- <!-- verify: grep "## 7. Migration checklist" "docs/reports/claude-sonnet-5-impact-strategy.md" --> <!-- verify: rubric "docs/reports/claude-sonnet-5-impact-strategy.md の §7 Migration checklist に少なくとも 3 個の checkbox 項目 (`- [ ]` または `- [x]`) が含まれる" --> §7 Migration checklist に checkbox 項目が 3 個以上含まれている (AC E)

### Post-merge

- 次回 `/audit drift` narrative check で Sonnet 5 関連の documentation drift が検出されない <!-- verify-type: opportunistic -->
- レポート §8 の Candidate Issues のうち Priority=high 以上のものが起票済み (`#877` / `#878` を含む) または既存 Issue にマッピング済みである <!-- verify-type: manual -->

## Alternatives Considered

- **matrix 本体の default swap を本 Issue で実施**: rejected — CI-sensitive な変更で Size M 以上相当 ( [[feedback_ci_sensitive_size_m]] ) 、かつ実測データ ( #878 tokenizer 、 #877 verify) 前の swap は risk 過大。Migration path C の Phase 2 で単独 Issue として扱う
- **§2 "Does Wholework still have a reason to exist?" セクションを再実装**: rejected — Sonnet 5 は Fable 5 の下位 tier であり scaffold dissolution 圧は Fable 5 report で議論済み。transitive に成り立つため §1 末尾で言及するのみ
- **Sonnet 5 用の新しい report ファイル名パターン (`sonnet-5-migration.md` 等) を採用**: rejected — 既存 report 命名 (`claude-fable-5-impact-strategy.md`, `claude-opus-4-7-optimization-strategy.md`) との一貫性を優先し `claude-sonnet-5-impact-strategy.md` を採用
- **§8 Candidate Issues を Issue 起票済みリストに限定**: rejected — Phase 2/3/4 の予定 Issue も含めた execution plan として提示することで、reader が本 Issue の scope 境界を理解できる

## Tool Dependencies

### Bash Command Patterns

- `gh issue view:*` — 子 Issue 番号 (#877, #878) の cross-reference 用 (既に allowed-tools 済み)

### Built-in Tools

- `Write` — new report file 作成
- `Edit` — `docs/tech.md` の Sonnet 5 段落追加
- `Read` — 参照ソース (Fable 5 report, Opus 4.7 report, tech.md) の読み込み

### MCP Tools

- none

## Uncertainty

- **Sonnet 5 実運用時の cost 精度**
  - 導入価格 ($2/$10 per MTok, 〜2026-08-31) と標準価格 ($3/$15) の切替時期および現行 Wholework ワークロードでの実効コストは実測がない
  - **Verification method**: report §5 で "コスト projection は導入価格前提" と明記し、Phase 2 の default swap Issue で実測比較を条件とする。実測自体は本 Issue のスコープ外
  - **Impact scope**: §5 Strategic recommendations、 §8 Candidate Issue #C (Phase 2 default swap) の priority 判断
- **Sonnet 5 tokenizer 1.0〜1.35× のコンテンツ別分布**
  - Wholework の実際の prompt (Spec/Issue body/git diff/events.jsonl 等) で比率がどこに落ちるかは実測前は不明
  - **Verification method**: `#878` tokenizer 影響測定 Issue で扱う。本 Spec は report §4.4 で #878 に委譲する旨を明記
  - **Impact scope**: §4.4 tokenizer 影響サブセクション、Phase 2 の watchdog 校正判断

## Notes

- **子 Issue との関係整理**: `#876` (本 Issue、親) blocks `#877` (verify 再測定) と `#878` (tokenizer 影響測定) 。 blocked-by 関係は `gh-graphql.sh --query add-blocked-by` で既に設定済み ( [[github-issue-relationships]] ) 。 report §8 でこの依存関係を可視化する
- **`docs/ja/reports/` の翻訳**: `docs/translation-workflow.md` Exclusions で `docs/reports/` は sync 対象外と明記されている。 Fable 5 report の ja 版は例外的翻訳の扱いであり、本 Issue では新規 ja mirror を作らない (verify command 対象外) 。将来ニーズが高まれば別 Issue で翻訳判断
- **`docs/tech.md` matrix 本体を触らない理由**: 本 Issue は analysis-only。実際の default parent 変更 (Phase 2) は CI 影響が大きく、Size M 以上相当 ( [[feedback_ci_sensitive_size_m]] ) 。 tech.md には注記段落を追加するのみで、matrix 表本体は現行の Sonnet 4.6/Opus/Fable 5 記述を維持する
- **Fable 5 再展開 (2026-07-01) の触れ方**: report §4 内で 1〜2 段落程度、Fable 5 opt-in 方針の継続と、Sonnet 5 との tier 分離 (Sonnet 5 は default 候補、Fable 5 は opt-in) を明記する。Fable 5 の cyber classifier false-positive リスクは既存の Fable 5 report で扱われているため詳細は cross-reference で済ませる
- **[[sonnet-5-migration]] memory との整合**: 本 Spec 完了後、memory の "How to apply" 節に report path (`docs/reports/claude-sonnet-5-impact-strategy.md`) を追加できる状態になる。 memory 更新は本 Issue のスコープ外 (別途 CLAUDE.md session retrospective で判断)
- **Simplicity rule**: Implementation Steps は 10 個 (light 5 個、full 10 個の上限内) 、pre-merge verification は 5 項目で full 上限内

## spec retrospective

### Minor observations
- 本 Issue は `/issue` を経由せず gh CLI で直接起票したため、Issue body に `## Acceptance Criteria` が欠けていた。 `/spec` Step 10 の verify command sync rule と Count alignment check を満たすため、 `/spec` 側で AC を追加し body update した。今後 impact-analysis 系 Issue を手動起票する際は `## Acceptance Criteria` セクションを最初から含めるテンプレを持つと healing がスムーズ

### Judgment rationale
- **matrix 本体を触らない判断**: default parent の Sonnet 4.6 → Sonnet 5 実 swap は CI-sensitive Size M 以上相当 ( [[feedback_ci_sensitive_size_m]] ) 、かつ実測データ (子 Issue #877 / #878) 前の swap は risk 過大。本 Issue は analysis-only とし、matrix 表本体は Phase 2 の別 Issue で扱う分離を採用
- **Fable 5 report §2 相当セクションの省略**: Sonnet 5 は Fable 5 の下位 tier で「scaffold dissolution 圧」の議論は transitive に成り立つため、§1 末尾で言及するのみとし §2 セクションは省略。report 全体の scope を Phase 1 の inventory に集中させる
- **報告書 §8 の "実装済み Issue vs 予定 Issue" の混在方針**: 起票済み ( #877 / #878) と Phase 2/3/4 の予定 Issue を同じ table に列挙して execution plan を可視化する Fable 5 report §8 の慣行を踏襲。読者が本 Issue の scope 境界を理解しやすくする

### Uncertainty resolution
- **Sonnet 5 実運用 cost**: 実測前は projection。Phase 2 の default swap Issue に「1 週間サンプリング + 実測比較」を precondition として書き込むことで、本 Spec ではレポート §5 内の projection 明記のみで済ませる
- **Tokenizer 1.0〜1.35× 分布**: 全面的に子 Issue #878 に委譲。本 Spec は report §4.4 で #878 への delegation を明示する記述のみを要件化

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- レポート `docs/reports/claude-sonnet-5-impact-strategy.md` を Fable 5 report と同構成 (§1〜§10) で作成し、§2 (existential question) は Sonnet 5 の tier 位置ゆえ省略
- `docs/tech.md` matrix 表本体は変更せず、"Fable 5 (Mythos class)" 段落の直後に **Sonnet 5** 段落を追加する note-only 方針で、実 default 切替は Phase 2 の別 Issue に委譲
- §8 Candidate Issues table に起票済み ( #877 / #878) と Phase 2/3/4 予定 Issue を混在列挙。Priority と Est. Size 列を必須

### Deferred Items
- default parent の実 swap (Sonnet 4.6 → Sonnet 5): Phase 2 の別 Issue、実測データ (子 Issue #877 / #878) 完了後
- effort re-calibration (`run-*.sh` の phase 別 effort 見直し): Phase 3 の複数の patch/S 相当 Issue
- `--effort=` フラグ露出 (Size × model × effort 3 軸): Phase 4、Icebox 判定含む
- `docs/ja/reports/claude-sonnet-5-impact-strategy.md`: `docs/translation-workflow.md` Exclusions 対象、本 Issue では作成せず

### Notes for Next Phase
- レポート §8 の Candidate Issues 列 (Priority / Est. Size) は verify rubric で機械検証されるため、markdown table 形式を厳守する
- `docs/tech.md` Sonnet 5 段落は "Fable 5 (Mythos class)" 段落と "SSoT note:" の間に挿入。段落順序が variable な場合は Fable 5 段落末尾を anchor に Edit する
- `#877` / `#878` は既に blocked-by 関係が設定済み ([[github-issue-relationships]]) 。report §8 内でこの依存関係を可視化する際、body テキストで補足する形で問題なし
- Simplicity rule 制約: Implementation Steps 10 個 / pre-merge verify 5 項目で full 上限。追加項目を提案する際は既存の再構成が必要
