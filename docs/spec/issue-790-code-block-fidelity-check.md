# Issue #790: doc: translation workflow に source/target code block fidelity check を追加

## Overview

`/doc translate` で生成される翻訳ドキュメントにおいて、code block (` ``` ` フェンス) が prose 翻訳時に omit されるドリフトが発生しやすい (#781 review retrospective で検出)。
本 Issue では `skills/doc/translate-phase.md` の Step 3 (翻訳処理) に code block fidelity check (コードフェンス数の一致確認) を追加し、`docs/translation-workflow.md` のSync Procedure にも同等の確認手順を明記する。

## Changed Files

- `skills/doc/translate-phase.md`: Step 3 の Write 呼び出し直後に **Code Block Fidelity Check** サブステップを追加 — source と translated output のコードフェンス (` ``` `) 数を比較し、不一致時はユーザーに警告してミラー修正を行う
- `docs/translation-workflow.md`: Sync Procedure に **Step 5: Code Block Fidelity Check** を追加 — sync 後に英語 source とミラーのコードフェンス数を照合するよう明記
- `docs/ja/translation-workflow.md`: `docs/translation-workflow.md` の変更を日本語ミラーに同期

## Implementation Steps

1. **`skills/doc/translate-phase.md` Step 3 にコードフェンス fidelity check サブステップを追加**
   (→ 受入条件 AC1, AC2)

   Step 3 の翻訳ループ内、各ファイルの Write 呼び出し直後に以下のサブステップを挿入:

   ```
   **Code Block Fidelity Check (apply after writing each file):**
   After writing the translated output, verify code block count:
   1. Count ` ``` ` code fence markers in the source file
   2. Count ` ``` ` code fence markers in the just-written translated output
   3. If counts differ, output a warning:
      "Warning: Code block count mismatch in {output_path}: source has {N} code fence markers, translation has {M}. Review the translation and ensure all code blocks are preserved."
   4. On mismatch, re-read the source to locate missing code blocks and insert them into the translated output at the appropriate positions before proceeding to the next file.
   ```

2. **`docs/translation-workflow.md` Sync Procedure に Step 5 を追加**
   (→ 受入条件 AC1, AC2)

   既存の Step 4 の直後に:

   ```
   5. Verify code block fidelity: count ` ``` ` (code fence markers) in the English source and the synced mirror. If the counts differ, locate the missing code blocks in the source and insert them into the mirror at the correct positions.
   ```

3. **`docs/ja/translation-workflow.md` を同期** (after 2)
   (→ 翻訳ワークフロー Sync Procedure 準拠)

   Step 5 の日本語訳を `docs/ja/translation-workflow.md` の同期手順に追加:

   ```
   5. コードブロックの整合性確認: 英語 source とシンクしたミラーの ` ``` `（コードフェンスマーカー）数を数える。数が異なる場合は、source 内の欠落したコードブロックを特定し、ミラーの正しい位置に挿入する。
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "docs/translation-workflow.md または /doc translate skill (skills/doc/translate-phase.md) に、source と target の code block 数の一致確認 / 内容 equivalence チェックの手順が追加されている" --> translation workflow に code block fidelity check が追加されている
- <!-- verify: rubric "code block fidelity check の具体的な実装方法 (例: block 数比較、または equivalence 確認ステップ) が記述されている" --> fidelity check の具体手順が明示されている

### Post-merge

- 次回 `/doc translate` 実行時に code block fidelity check が発火することを観察 <!-- verify-type: opportunistic -->

## Notes

- **実装場所の自動解決** (issue retrospective より引継): `docs/translation-workflow.md` と `skills/doc/translate-phase.md` の両方に追加する方針を採用。AC1 の rubric は OR 条件であるため、どちらか一方への補助チェック (`file_contains`, `grep`) は false FAIL リスクがあり追加しない。
- **verify-type の確認**: 既存 AC の `verify-type: opportunistic` は正当。`doc-translate` イベントは `verify-classifier.md` の valid event 一覧に存在せず、unknown event fallback として `opportunistic` 扱いが正しい。
- **翻訳同期**: `docs/translation-workflow.md` は `type: project` ファイルであるため、変更時は `docs/ja/translation-workflow.md` の同期が必要 (translation-workflow.md Sync Procedure 準拠)。

## Consumed Comments

- `saito` (MEMBER / first-class): Issue Retrospective コメント — verify-type 修正、AC1 rubric 内ファイルパス修正、pre-merge AC の rubric 補助チェック判断の3点を自動解決済みとして記録

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- `phase/ready` ラベルが付与されていない状態で code phase が開始された (labels: `triaged`, `phase/code`, `retro/verify`)。Non-interactive auto-resolve により Issue 本文と Spec から直接実装を進めた。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/doc/translate-phase.md` の Step 3 Write 呼び出し直後に Code Block Fidelity Check サブステップを追加した。Spec では Step 3 の翻訳ループ内での挿入を指定しており、コードフェンス数比較 → 警告出力 → 不一致時に source から欠落コードブロックを再挿入する 4 ステップ形式を採用した。
- `docs/translation-workflow.md` Sync Procedure に Step 5 として code block fidelity check を追記した。既存の Step 4 と同一レベルの具体手順で記述し、視認性を保つ形式を選択した。
- `docs/ja/translation-workflow.md` には Step 5 の日本語訳を追加した。英語版 Step 5 と同等の内容・構造を維持した。

### Deferred Items
- `/doc translate` 実行時の実際の code block fidelity check 発火は `verify-type: opportunistic` として post-merge 観察に委ねた (#790 AC Post-merge)。

### Notes for Next Phase
- 実装は 3 ファイルへの追加のみ。既存ロジックへの変更はなし。verify phase では rubric AC2 つが PASS であることを確認する。
- `docs/translation-workflow.md` と `docs/ja/translation-workflow.md` の Step 5 が対称的に追加されている点を確認する。
