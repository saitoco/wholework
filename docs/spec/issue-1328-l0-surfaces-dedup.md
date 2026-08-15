# Issue #1328: l0-surfaces: Bash wrapper fallback 呼び出し元列挙の重複を解消

## Issue Retrospective

### 曖昧性解決の判断根拠

Issue 本文自体は #1316 review retrospective からの機械的転記であり、Background/Purpose/対象箇所は明確。`/spec` に委ねると明記されている設計判断 (リンクのみにするか要約を残すか) 以外に、追加で解決すべき曖昧ポイントは検出されなかった。

### 主要な方針決定 (Q&A)

Step 1 のコメント消費手続きで Triage AC audit コメント (2026-08-10, @saito, MEMBER) を検出し、以下の方針で Pre-merge AC を再設計した:

- 当初の3件目のAC (`<!-- verify: grep "Bash wrapper fallback" "modules/l0-surfaces.md" -->`) は、`modules/l0-surfaces.md` の該当見出しが本 Issue の実装前から既に存在するため常時 PASS し、検証シグナルを提供しないという指摘を採用。
- 代替として `section_contains` で l0-surfaces.md 内の特定要素を確認する案も検討したが、l0-surfaces.md 自体は本 Issue の実装で変更されない不変ファイルであるため、そちらを対象にした AC も同様に常時 PASS してしまう (同じ問題の再現)。
- 最終的に、3件目の独立 AC を削除し、代わりに既存の rubric AC (docs/structure.md / modules/worktree-lifecycle.md それぞれ) へ `file_not_contains` の補助チェックを追加する形にした。対象文字列は各ファイルの重複記述に含まれ、実装完了後に消えるべき特徴的なフレーズ (`gated off for` / `Size XS/S early-exit branch`) を選定し、rubric + supplementary パターン (`/issue` Step 4 参照) に沿わせた。

### Acceptance Criteria 変更理由

- AC1 (`docs/structure.md`): rubric に加え `file_not_contains "docs/structure.md" "gated off for"` を追加。この文字列は現状 `docs/structure.md` と `modules/l0-surfaces.md` の双方に重複して存在しており、リンク化後は `docs/structure.md` からのみ消える想定。
- AC2 (`modules/worktree-lifecycle.md`): rubric に加え `file_not_contains "modules/worktree-lifecycle.md" "Size XS/S early-exit branch"` を追加。同フレーズは現状 `modules/worktree-lifecycle.md` と `modules/l0-surfaces.md` の双方に存在し、リンク化後は前者からのみ消える想定。
- 旧AC3 (`grep "Bash wrapper fallback" "modules/l0-surfaces.md"`) は削除。常時PASSで検証シグナルを持たないため。

### Consumed Comments (at /issue time)

- saito / MEMBER / first-class / Triage AC audit: 3件目のverify commandが常時PASSするパターンであることを指摘し、より具体的な文字列を対象にするか section_contains への変更を提案 / https://github.com/saitoco/wholework/issues/1328#issuecomment-5237595903
