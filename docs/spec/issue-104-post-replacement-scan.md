# Issue #104: spec: 用語置換タスクの後処理チェックリストをSpecガイドラインに追加

## Overview

Issue #94（Acceptance check → verify command 置換）のコードレトロスペクティブで、機械的置換後に7ファイル・9箇所の修正が必要になった。根本原因は置換後スキャンの欠如。

検出されたパターン:
- 冠詞の不整合: "An acceptance check" → "An verify command"（"An" のまま残存）
- 複合名詞の冗長: "acceptance check commands" → "verify command commands"（重複）
- 日本語テキストとのスペース不足: 日本語文字列隣接での英語置換後のスペース欠如

`skills/spec/SKILL.md` の Step 10「Rename-type Issue grep check」セクションに後処理チェックリストを追記する。

## Changed Files

- `skills/spec/SKILL.md`: Step 10「Rename-type Issue grep check」セクションに post-replacement scan checklist を追記

## Implementation Steps

1. `skills/spec/SKILL.md` の「Rename-type Issue grep check」セクション末尾（「Pre-investigate exclusion conditions...」段落の直後、「**Multi-file change grep coverage check:**」の直前）に以下の内容を追記する（→ 受け入れ基準 A, B, C）:

   ```
   **Post-replacement scan checklist:**
   
   After completing find-and-replace, scan the changed files for these patterns introduced by mechanical substitution:
   - **Article consistency**: check that articles (a/an) are correct after noun replacement (e.g., "an old-term" → "an new-term" should become "a new-term" when appropriate)
   - **Compound noun redundancy**: check for word doubling when replacing compound nouns (e.g., "old-term commands" → "new-term commands" but "new-term term commands" is redundant)
   - **Japanese boundary space**: check that spacing between Japanese text and replaced English terms is correct after substitution
   ```

## Verification

### Pre-merge

- <!-- verify: grep "article" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に冠詞変化チェック項目が追記されている
- <!-- verify: grep "compound.*noun" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に複合名詞重複チェック項目が追記されている
- <!-- verify: grep "Japanese" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に日本語境界スペースチェック項目が追記されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/spec/" --> `validate-skill-syntax.py` が PASS する

### Post-merge

なし

## Notes

- `grep "Japanese" "skills/spec/SKILL.md"` は既存の「Translate Japanese titles to English」（行313付近）にマッチするため、verify は新規追記前でもPASSする可能性がある。追記内容は「Japanese boundary space」という文脈で区別できる
- Issue body の "Auto-Resolved Ambiguity Points" で実装箇所・verify command 言語・verify command 構造が既に確定済み
- 追記位置は「Pre-investigate exclusion conditions...」段落の直後、「**Multi-file change grep coverage check:**」見出しの直前（既存の "Rename-type Issue grep check" セクション内の最後）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
