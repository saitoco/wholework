# Issue #90: spec: 日本語ミラーファイルの acceptance condition 作成ガイドラインを追加

## Overview

Issue #84（verify command 用語統一）の実装で、`docs/ja/tech.md` への acceptance condition を英語パターンで作成したため、日本語ミラーファイルの書式を英語パターンに合わせてしまう副作用が発生した。

本 Issue では `/spec` ガイドラインの "SHOULD-level acceptance criteria consideration" セクションに、日本語ミラーファイル（`docs/ja/*`）向けの acceptance condition 作成時の注意事項を追加する。具体的には、日本語パターンを使用するか、書式への影響を Notes に明示することを求める。

## Changed Files

- `skills/spec/SKILL.md`: "SHOULD-level acceptance criteria consideration" セクションに `docs/ja/*` ファイル向けの bullet を追加

## Implementation Steps

1. `skills/spec/SKILL.md` の "SHOULD-level acceptance criteria consideration" セクション（"Consistency with existing patterns" 行の直後）に以下の bullet を追加する（→ 受け入れ条件 A, B）:
   ```
   - `docs/ja/*` files (Japanese mirror files): use Japanese-format patterns in verify commands to avoid unintended format changes; if an English pattern must be used, note the format impact explicitly in Notes
   ```

## Verification

### Pre-merge

- <!-- verify: grep "docs/ja" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` の acceptance condition 作成ガイドラインに `docs/ja/` ファイルへの言及が追加されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "Japanese" --> `skills/spec/SKILL.md` に日本語ミラーファイル向けの注意事項（日本語パターン使用、または書式影響を Notes に明示）が記載されている

### Post-merge

- `/spec` スキル実行時に `skills/spec/SKILL.md` の新しいガイドラインが参照されることを確認

## Notes

- `file_contains "skills/spec/SKILL.md" "Japanese"` は現時点で既に PASS（line 231, 323 に `Japanese` が存在）。実装後はガイドライン本文中にも `Japanese` が含まれる形になる
- 追加箇所は `**SHOULD-level acceptance criteria consideration:**` セクションの最終 bullet 行直後（line 296 付近）
