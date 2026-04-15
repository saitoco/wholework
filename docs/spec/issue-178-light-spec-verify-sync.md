# Issue #178: spec: SPEC_DEPTH=light でも Spec verify コマンドを Issue 受け入れ条件に反映する処理を追加

## Overview

`/spec` スキルの Step 10 にある「Verification conditions vs. Issue body acceptance criteria consistency check」は、現在 `Self-review (SPEC_DEPTH=full only)` ブロック内にのみ存在するため、SPEC_DEPTH=light の場合にスキップされている。

これにより Issue #177（SPEC_DEPTH=light）のように、Spec に正確な verify コマンドが記載されているにも関わらず、Issue 本文の受け入れ条件にヒントが付与されず、`/verify` 実行時に AI 判断頼みになる問題が発生した。

本 Issue では、verify コマンドを Issue 本文へ反映する処理を SPEC_DEPTH に関わらず実行されるよう変更し、`/verify` の自動検証精度を向上させる。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の Count alignment check セクションの後に「Verification conditions vs. Issue body acceptance criteria consistency check (regardless of SPEC_DEPTH)」セクションを追加し、Self-review (SPEC_DEPTH=full only) ブロックから同エントリを削除

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10 内、`**Count alignment check (regardless of SPEC_DEPTH):**` セクションの直後（`**Changed-file modification types...**` セクションの直前）に以下のセクションを追加 (→ acceptance criteria 1, 2):

   ```
   **Verification conditions vs. Issue body acceptance criteria consistency check (regardless of SPEC_DEPTH):**

   After creating `## Verification > Pre-merge`, compare Spec items against Issue body items to reflect verify commands:
   - List each Spec `## Verification > Pre-merge` item
   - Compare against Issue body `## Acceptance Criteria > Pre-merge` items
   - Detect: Spec items not in Issue body (omission), or mismatched `<!-- verify: ... -->` hints
   - If mismatched, auto-update Issue body (use Spec's `## Verification > Pre-merge` as source of truth): `mkdir -p .tmp`, write to `.tmp/issue-body-$NUMBER.md`, update with `gh-issue-edit.sh`, delete temp file
   ```

2. `skills/spec/SKILL.md` の `**Self-review (internal consistency check) (SPEC_DEPTH=full only):**` ブロック内から「Verification conditions vs. Issue body acceptance criteria consistency check」の箇条書きエントリ（5行）を削除 (→ 重複回避)

## Verification

### Pre-merge

- <!-- verify: grep "Verification conditions.*regardless of SPEC_DEPTH" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` において「Verification conditions check」が SPEC_DEPTH を問わず実行される仕様が追加されている
- <!-- verify: grep "auto-update Issue body" "skills/spec/SKILL.md" --> Spec の `## Verification > Pre-merge` を正典として Issue 本文を自動更新する仕様が記述されている

### Post-merge

- `/spec {issue-number}` を SPEC_DEPTH=light（Size S/M）で実行したとき、Spec の `## Verification > Pre-merge` セクションの verify コマンドが Issue 本文の `## Acceptance Criteria > Pre-merge` に反映される

## Notes

- 追加するセクションの配置: `**Count alignment check (regardless of SPEC_DEPTH):**` セクションのすぐ後（セクション末尾のコードブロック ``` の後の空行の後）
- Self-review ブロックから削除する 5 行: `- **Verification conditions vs. Issue body acceptance criteria consistency check**:` で始まるエントリ（5 行: 箇条書きヘッダー + 4 サブ箇条書き）
- 削除後の Self-review ブロックには Post-merge skill name alignment の箇条書きが最後のエントリとして残る
- `auto-update Issue body` のテキストは Step 1 の新セクション内に含まれるため、Self-review からの削除後も grep 検索でヒットする

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
