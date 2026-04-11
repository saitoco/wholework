# Issue #86: Add Permission Pattern Probe Test Condition Guideline to /spec Constraint Checklist

## Overview

`settings.json` の `permissions.allow` パターンを変更する Issue の `/spec` 実行時に、#82 の解決過程で発生した2往復の試行錯誤（不完全なテスト条件による誤判定）を防ぐため、`skills/spec/SKILL.md` の Step 10 SHOULD constraints table に permission pattern 検証プロトコルのガイドラインを1行追加する。

追加するガイドライン内容（Issue body § 検証プロトコルの推奨内容より）：
- simple invocation（shell operators なし）でテストする
- settings.local.json に事前承認がない状態で実行する
- セッション再起動後に実行する（settings.json は hot-reload されない）

## Changed Files

- `skills/spec/SKILL.md`: Step 10 SHOULD constraints table に "Permission pattern verification" 行を追加（`| Patch route CI verify | ...` 行の直後、`**SHOULD-level acceptance criteria consideration:**` の前）

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10 SHOULD constraints table の末尾（`| Patch route CI verify | ... | #112 |` 行の直後）に以下の行を追加する（→ 受け入れ基準 A, B, C）：

   ```
   | Permission pattern verification | When implementation includes `settings.json` `permissions.allow` pattern changes, test with simple invocation only (no shell operators: `2>&1`, `|`, `&&`); restart the session before testing (settings.json is not hot-reloaded); ensure no conflicting pre-approval in `settings.local.json` | #82 |
   ```

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 10: Create Spec" "permission pattern" --> `skills/spec/SKILL.md` の constraint checklist（SHOULD constraints table）に permission pattern 検証プロトコルのガイドラインが追加されている
- <!-- verify: grep "simple invocation" "skills/spec/SKILL.md" --> ガイドラインに「simple invocation（shell operators なし）で検証すること」が明記されている
- <!-- verify: grep "shell operator" "skills/spec/SKILL.md" --> ガイドラインに「shell operator を含む invocation は使わない」旨が明記されている

### Post-merge

- 次回 permission pattern 変更を伴う Issue の `/spec` 実行時に、検証プロトコルが自動的に Spec Notes に反映されることを確認

## Notes

- [Issue 自動解決] 配置: constraint checklist（Step 10 SHOULD constraints table）に決定。既存パターン（`Verify existing parser behavior`、`Argument parser edge cases` など "when X, do Y" 形式の12件）と一致するため自動解決
- [Issue 自動解決] grep OR 構文 `\|` → 2つの独立した grep コマンドに分割（verify コマンドの移植性向上、各フレーズの存在を個別に保証）
- `docs/ja/` 配下に `skills/spec/SKILL.md` の日本語ミラーは存在しないため、日本語ミラー更新不要

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は "### Step 10: Create Spec" セクション内の SHOULD constraints table への1行追加という単純・明確な設計。受け入れ条件の verify コマンドも `section_contains` / `grep` と適切に分割されており、自動検証が完全に機能した。

#### design
- 設計は実装と完全一致（1行追加のみ）。Auto-resolved ambiguity（配置先の選定、grep OR 構文の分割）も事前にSpec内に記録されており追跡可能。

#### code
- コミット1件（b995e50）、1ファイル1行追加のみ。fixup/amend なし。設計逸脱なし。

#### review
- Issue #86 はパッチルート（直接 main へのコミット）のため PR なし。レビューコメントなし。

#### merge
- パッチルートでコンフリクトなし。直接 main にコミット済み。

#### verify
- 全3条件が PASS。verify コマンドが正確で自動検証が完全に機能。
- opportunistic 条件（Post-merge）は次回 permission pattern 変更 Issue の `/spec` 実行時に確認予定。

### Improvement Proposals
- N/A
