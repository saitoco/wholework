# Issue #918: commit-template: コミットメッセージテンプレートの Co-Authored-By を Sonnet 4.6 → Sonnet 5 に一括更新

## Consumed Comments

- saito / MEMBER / first-class / triage フェーズの Issue Retrospective — Auto-Resolve Log (pre-merge AC の検証方式を repo-wide rubric-grep から10ファイル個別の `file_not_contains` に変更した理由: 歴史的記録ファイルへの誤検知回避) とタイトル正規化・Type/Size/Value 判定根拠を記録。Issue 本文には既に反映済みのため Spec への追加アクションなし / https://github.com/saitoco/wholework/issues/918#issuecomment-4885300051

## Overview

コミットメッセージテンプレート内にハードコードされた `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` を `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` に一括更新する。2026-06-30 以降、bare `sonnet` CLI エイリアスの実行時点解決先は既に Sonnet 5 (`docs/tech.md` model-effort-matrix、#914 で確定済み) であり、これらのテンプレートから生成される実際のコミットの co-author 表記を実態に整合させる。

対象は Issue 本文に列挙された10ファイル。grep で全一致確認済み (詳細は `## Changed Files` 参照)。同一文字列は歴史的記録ファイル5件にも存在するが、いずれも本 Issue のスコープ外 (`## Notes` の Exclusions 参照)。

## Changed Files

- `agents/orchestration-recovery.md`: change — commit テンプレート内の `Claude Sonnet 4.6` (1箇所) を `Claude Sonnet 5` に置換
- `modules/doc-commit-push.md`: change — 同上 (1箇所)
- `scripts/append-consumed-comments-section.sh`: change — 同上 (1箇所)。文字列リテラルの置換のみで新規 bash 構文は導入しない (bash 3.2+ 互換維持)
- `scripts/run-auto-sub.sh`: change — 同上 (4箇所)。文字列リテラルの置換のみで新規 bash 構文は導入しない (bash 3.2+ 互換維持)
- `skills/auto/SKILL.md`: change — 同上 (4箇所)
- `skills/code/SKILL.md`: change — 同上 (2箇所)
- `skills/merge/SKILL.md`: change — 同上 (1箇所)
- `skills/review/SKILL.md`: change — 同上 (2箇所)
- `skills/verify/SKILL.md`: change — 同上 (1箇所)
- `skills/doc/translate-phase.md`: change — 同上 (1箇所)

## Implementation Steps

1. 上記10ファイル内の `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>` (計18箇所) をすべて `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` に置換する (→ acceptance criteria 1-11)
2. `grep -rn "Claude Sonnet 4.6" agents/orchestration-recovery.md modules/doc-commit-push.md scripts/append-consumed-comments-section.sh scripts/run-auto-sub.sh skills/auto/SKILL.md skills/code/SKILL.md skills/merge/SKILL.md skills/review/SKILL.md skills/verify/SKILL.md skills/doc/translate-phase.md` を実行し、対象10ファイルに残存がゼロであることを確認する (after 1) (→ acceptance criteria 2-11)

## Verification

### Pre-merge

- <!-- verify: rubric "以下10ファイルのコミットメッセージテンプレート内の `Co-Authored-By: Claude Sonnet 4.6` 表記が `Co-Authored-By: Claude Sonnet 5` に更新されている" --> 該当ファイルの co-author テンプレートが Sonnet 5 に更新されている
      <!-- verify: file_contains "skills/code/SKILL.md" "Claude Sonnet 5" -->
- <!-- verify: file_not_contains "agents/orchestration-recovery.md" "Claude Sonnet 4.6" --> `agents/orchestration-recovery.md` に旧表記が残っていない
- <!-- verify: file_not_contains "modules/doc-commit-push.md" "Claude Sonnet 4.6" --> `modules/doc-commit-push.md` に旧表記が残っていない
- <!-- verify: file_not_contains "scripts/append-consumed-comments-section.sh" "Claude Sonnet 4.6" --> `scripts/append-consumed-comments-section.sh` に旧表記が残っていない
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "Claude Sonnet 4.6" --> `scripts/run-auto-sub.sh` (4箇所) に旧表記が残っていない
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "Claude Sonnet 4.6" --> `skills/auto/SKILL.md` (4箇所) に旧表記が残っていない
- <!-- verify: file_not_contains "skills/code/SKILL.md" "Claude Sonnet 4.6" --> `skills/code/SKILL.md` (2箇所) に旧表記が残っていない
- <!-- verify: file_not_contains "skills/merge/SKILL.md" "Claude Sonnet 4.6" --> `skills/merge/SKILL.md` に旧表記が残っていない
- <!-- verify: file_not_contains "skills/review/SKILL.md" "Claude Sonnet 4.6" --> `skills/review/SKILL.md` (2箇所) に旧表記が残っていない
- <!-- verify: file_not_contains "skills/verify/SKILL.md" "Claude Sonnet 4.6" --> `skills/verify/SKILL.md` に旧表記が残っていない
- <!-- verify: file_not_contains "skills/doc/translate-phase.md" "Claude Sonnet 4.6" --> `skills/doc/translate-phase.md` に旧表記が残っていない

### Post-merge

なし

## Notes

### Exclusions (対象外ファイル)

以下は同一文字列 `Claude Sonnet 4.6` を含むが、意図的に旧モデル名を残す歴史的記録であり置換対象外 (grep で存在確認済み):
- `docs/reports/sonnet-5-tokenizer-impact.md` — 完了済み計測レポート (計測時点のモデル世代の記録)
- `docs/spec/issue-53-doc-commit-push-guide.md` / `issue-694-l3-auto-session-retrospective.md` / `issue-822-manual-recovery-auto-retrospective.md` / `issue-914-default-parent-sonnet-5.md` — disposable Spec (`docs/product.md` Terms「Spec」の定義に準拠し、実行当時の記録として保持)

### 実測件数

Issue 本文は「計約17箇所」と記載しているが、grep 実測では10ファイル合計18箇所 (内訳は `## Changed Files` 参照)。近似表記の範囲内であり、対象ファイル一覧・各ファイルの検証方式には影響ない。

## Phase Handoff

<!-- phase: merge -->

### Key Decisions
- `gh-pr-merge-status.sh` の結果が mergeable=true (reason=clean, CI success, review approved) だったため、conflict 解決ステップ (Step 3) をスキップし squash merge を直接実行した
- squash merge 後、worktree を介さず現在の作業ディレクトリ (main ブランチ) で `git fetch` → `git merge origin/main --ff-only` により Spec を含む squash commit を取り込んだ

### Deferred Items
- None

### Notes for Next Phase
- Post-merge AC は「なし」のため `/verify 918` での追加確認事項はない
- Base branch は `main` のため `closes #918` により Issue は merge 時点で自動クローズ済み

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps の記載通りに実施し、逸脱なし

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — 実装は Spec の Implementation Steps 通りで、Spec と PR diff の間に構造的な乖離はなかった

### Recurring issues
- Nothing to note — review-light の4観点すべてで issue 検出なし。単純文字列置換タスクとして issue の再発パターンは見られなかった

### Acceptance criteria verification difficulty
- Nothing to note — 全11条件が `file_contains`/`file_not_contains` の機械的チェックのみで PASS/FAIL を判定でき、UNCERTAIN は発生しなかった。verify command の過不足も見られなかった
