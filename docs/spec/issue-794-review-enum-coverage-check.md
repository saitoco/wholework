# Issue #794: review: enum 定義機能の coverage check pattern を導入

## Overview

Spec が enum (離散値の名前付きセット、例: `auto-stop-at: spec|code|review|merge|verify`) を定義している機能について、review フェーズで「全 enum 値が実装されているか」を系統的にチェックするパターンを追加する。

具体的には:
- `agents/review-spec.md` Perspective 1 に enum coverage check ステップを追加
- `skills/review/SKILL.md` の `## Review Aspects` セクションに enum exhaustiveness check の明示的なガイダンスを追加

これにより、次回同様の enum 実装漏れ (例: #783 での `spec` stop-at 抜け) が review 段階で mechanical に検出できるようになる。

## Consumed Comments

- `saito` (MEMBER, first-class) — Issue Retrospective: 3件の曖昧点 auto-resolve ([コメント](https://github.com/saitoco/wholework/issues/794#issuecomment-4823971290))
  - AC2 verify command 構文 → ripgrep ERE 形式 (`(?i)enum.*(coverage|completeness|exhaustive)`)
  - Post-merge イベント名 → `event=pr-review-full`
  - 実装先 → SKILL.md を優先 (modules 新規作成は AC2 FAIL リスク)

## Changed Files

- `agents/review-spec.md`: Perspective 1 (Spec Deviation Check) に Step 2.5 "Enum coverage check" を追加
- `skills/review/SKILL.md`: `## Review Aspects` セクションに "Enum exhaustiveness check" パラグラフを追加

## Implementation Steps

1. `agents/review-spec.md` Perspective 1 の Step 2 と Step 3 の間に Step 2.5 を挿入 (→ AC1 rubric)
   - 内容: Spec に enum 定義がある場合、各 enum 値に対応する実装 (case 分岐、if-elif チェーン、辞書エントリ等) が PR diff に存在するか確認。欠落は MUST finding

2. `skills/review/SKILL.md` の `## Review Aspects` セクションの末尾に "Enum exhaustiveness check" パラグラフを追加 (→ AC1 rubric + AC2 grep)
   - 内容: "**Enum exhaustiveness check** (review-spec Perspective 1): ..." という見出し付き記述で、Spec の enum 定義に対して全値の実装網羅性を確認する旨を記載

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md または modules/review-* のいずれかに、Spec で enum を定義している機能について全 enum 値が実装されているかをチェックする pattern (rubric テンプレート or 明示的なガイダンス) が追加されている" --> review skill に enum coverage check pattern が導入されている
- <!-- verify: grep "(?i)enum.*(coverage|completeness|exhaustive)" "skills/review/SKILL.md" --> review SKILL.md に enum coverage 関連の記述が追加されている

### Post-merge

- 次回 enum 定義を含む Spec の review 実行時に、enum coverage check が発火することを観察 (event=pr-review-full)

## Notes

- 実装は SKILL.md と review-spec.md の両方に追加することで、ガイダンスの発見可能性と実行可能性を両立
- 「残存リスク」(実装者がモジュール新規作成した場合に AC2 FAIL) は、SKILL.md への追加を必須とすることで回避済み
- review-light.md の Perspective 1 にも自然に反映されるが、SKILL.md の Review Aspects セクションのガイダンスで十分
- docs 翻訳 sync 不要: 変更ファイルは `agents/` と `skills/` であり `docs/*.md` ではない

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/review/SKILL.md` の `## Review Aspects` 末尾に "**Enum exhaustiveness check**" パラグラフを追加した (AC2 grep 一致を保証するため "exhaustive" を含む見出しを採用)
- `agents/review-spec.md` Perspective 1 に Step 2.5 を挿入した (Step 2 と Step 3 の間)
- 両ファイルとも既存の構造に自然に統合でき、新規モジュール作成は不要だった

### Deferred Items
- review-light.md は今回変更しなかった (SKILL.md の Review Aspects でカバー範囲として十分との Spec 判断)
- Post-merge AC (enum coverage check の発火観察) は次回 `/review --full` 実行時に観察する

### Notes for Next Phase
- None (patch route — review フェーズなし)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Nothing to note.

#### design
- Nothing to note.

#### code
- Nothing to note. AC1/AC2 (pre-merge) 再検証も PASS を維持 (`skills/review/SKILL.md:852` に enum exhaustiveness check の記述を確認)。

#### review
- Nothing to note.

#### merge
- Nothing to note (patch route, direct commit — no PR/merge conflict history).

#### verify
- Post-merge の observation 条件 (`event=pr-review-full`) は 2026-06-28〜07-05 の間に計8回発火したが、最初の7回 (PR #928/Issue #902 含む) はいずれも対象 Spec が enum を定義していなかったため SKIPPED だった (詳細は前回記録の通り)。
- 8回目の発火 (`/review 933 --full`, Issue #930) で、対象 Spec (`docs/spec/issue-930-verify-worktree-inheritance.md`) が `none`/`own`/`foreign` の3値 enum を定義しており、review-spec エージェントが実際に Enum exhaustiveness check を評価し Complete coverage を報告した。これにより本 AC は初めて PASS 判定に到達し、Issue #794 は `phase/done` に遷移した。
- 結論: SKIP が7回連続した後の8回目で確定 PASS に到達しており、下記の改善提案 (粒度の細かいイベント新設) は依然として妥当な最適化候補だが、今回のケースでは「無限に確定しない」わけではなく、実用上妥当な回数で収束した。

### Improvement Proposals
- observation 型 AC (`verify-type: observation event=X`) のうち、イベント名が「実行契機」(例: `pr-review-full` = /review --full が完了した) を表すだけで「対象条件の成立」(例: enum を含む Spec だった) までは保証しない場合、SKIP が複数回繰り返されてから確定するまでの `/verify` dispatch オーバーヘッドが発生する (今回は8回、うち7回が無駄な SKIP ラウンドトリップ)。より粒度の細かいイベント (review-spec が実際に enum coverage check を評価したときのみ発火するイベント) を新設するか、observation-trigger.sh 側で「イベント発火 かつ 対象条件充足」の両方を条件にする設計を検討する余地がある。
