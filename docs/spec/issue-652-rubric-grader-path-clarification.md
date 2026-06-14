# Issue #652: verify-executor: rubric grader のファイル解決パス明示化

Size XS — Spec は省略。Issue body から要件を直接読み取り実装。

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
- `modules/verify-executor.md` の「Rubric Command Semantics」セクション末尾に新サブセクション「File path resolution in rubric graders (worktree-safe reads)」として追加した（Issue body の Auto-Resolve Log 指定どおり）
- content 直接埋め込みを第一推奨、`$PWD` 信頼を代替として明示（Issue body の Auto-Resolve Log どおり）
- PR #651 / Issue #632 の具体的な事例を Example として記載し、verify command（grep "#632|#651"）をPASSさせた

### Deferred Items
- None

### Notes for Next Phase
- 変更対象は `modules/verify-executor.md` のみ（1ファイル、21行追加）
- Pre-merge ACs 3件すべて PASS 済み（section_contains × 2、grep × 1）
