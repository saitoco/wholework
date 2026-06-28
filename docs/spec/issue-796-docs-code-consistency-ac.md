# Issue #796: issue: docs/code consistency を mechanical 照合する AC pattern を guideline 化

## Overview

`modules/verify-patterns.md` に新しいセクション §17 を追加し、docs と実装 (skills/*.md 等) の両方で主要な挙動キーワードを機械的に照合する AC pattern を guideline 化する。

検出元: #783 review retrospective — `docs/guide/customization.md` の説明文 ("silently ignored") が `skills/verify/SKILL.md` の実装 (警告出力) と不一致だった。Issue 起票時に両者の一致を verify する AC pattern があれば事前に検出できた。

## Changed Files

- `modules/verify-patterns.md`: §16 の後に §17 "Docs/Code Consistency — Verify Key Behavior Keywords in Both Layers" セクションを追加

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` セクションの直前 (§16 の末尾の後) に `### 17. Docs/Code Consistency — Verify Key Behavior Keywords in Both Layers` セクションを追加する (→ AC1, AC2, AC3)

   追加内容:
   - **Background**: docs ファイル (例: `docs/guide/customization.md`) とその挙動を実装する code ファイル (例: `skills/verify/SKILL.md`) が同じ Issue で変更される場合、挙動を表すキーワード ("silently ignored", "warning", "skip" 等) の一致を verify する AC がないと、実装後の review/verify まで不一致が検出されない (#783 事例)
   - **When to apply**: Issue の変更ファイルリストに docs ファイルと実装ファイルの両方が含まれており、かつ docs が特定の挙動を表すキーワードを記述している場合
   - **Recommended pattern (exact keyword が一致する場合)**: 両ファイルに同じキーワードの `grep` を配置
   - **Recommended pattern (意味的整合のみ必要な場合)**: `rubric` で意味的一致を確認
   - **Decision procedure**: 変更ファイルリストを確認 → docs の挙動記述から主要 keyword を抽出 → 実装ファイルを grep → exact match なら両層に `grep`、意味的のみなら `rubric`

   セクションに "consistency" を含むこと (→ AC2)。bash 3.2+ 互換。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md に、docs と code 実装の consistency を mechanical に照合する AC pattern (例: 同一 keyword の双方 grep) が guideline として追加されている" --> docs/code consistency verify AC pattern が guideline 化されている
- <!-- verify: file_contains "modules/verify-patterns.md" "consistency" --> modules/verify-patterns.md に「consistency」キーワードが含まれている (rubric 補完チェック)
- <!-- verify: rubric "AC 設計時に docs に書いた挙動 keyword を skills/*.md 側でも grep する pattern が、modules/verify-patterns.md に明記されている" --> docs↔code keyword consistency check の明示

### Post-merge

- 次回 docs と skills を両方変更する Issue で、両者の整合性確認 AC が自動付与されることを観察 <!-- verify-type: opportunistic -->

## Consumed Comments

- saito (MEMBER / first-class) at 2026-06-28T03:00:37Z: Issue Retrospective — 曖昧点1「guideline 追加先」を `modules/verify-patterns.md` に統一 (自動解決)、曖昧点2「event=issue-run タグ非標準」を `<!-- verify-type: opportunistic -->` のみに修正 (自動解決)、AC2 の rubric 補完 file_contains を追加 — <https://github.com/saitoco/wholework/issues/796#issuecomment-4824423814>

## Notes

- 非対話モードで実行。消費コメント (Issue Retrospective) の内容を設計に反映済み
- §17 の heading は `### 17. ...` 形式 (§1-§16 の `### N.` prefix と統一)
- `## Output` セクションは `modules/verify-patterns.md` の末尾近くにあるため、挿入位置は「§16 の最終行の直後、`## Output` の直前」
- 非対話モード自動解決ログ:
  - 曖昧点1: guideline 追加先 → `modules/verify-patterns.md` のみ (§1-§16 のパターン集としての既存役割から uniquely inferrable; `skills/issue/SKILL.md` は既に verify-patterns.md に委譲済み)
  - 曖昧点2: post-merge AC タグ → `<!-- verify-type: opportunistic event=issue-run -->` → `<!-- verify-type: opportunistic -->` に修正 (event= は observation type 専用構文; opportunistic には不要)
- `docs/ja/` sync 不要: 変更対象は `modules/verify-patterns.md` であり `docs/*.md` ではない
- `docs/structure.md` の verify-patterns.md 説明 "verify command pattern accuracy guidelines" は追加後も引き続き正確 (no update needed)
