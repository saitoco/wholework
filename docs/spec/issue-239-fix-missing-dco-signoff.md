# Issue #239: Fix Missing DCO Sign-off in Sub-agent Commits

## Overview

`/auto` の `/code` フェーズで sub-agent が生成する git commit に `Signed-off-by:` が欠落する問題を修正する。Claude Code のグローバル CLAUDE.md が提示する HEREDOC パターンに `-s` が含まれないため、sub-agent がそちらを優先してしまう。各 commit 実行ステップの直後に assertion guard を追加し、DCO 準拠を強制する。あわせて `skills/code/SKILL.md` の feature commit 直前に明示的 DCO 警告を追加する。

## Reproduction Steps

1. Issue を作成して `/auto N` を PR ルートで実行する
2. `/code` フェーズが `claude -p --dangerously-skip-permissions` で sub-agent として起動する
3. sub-agent がグローバル CLAUDE.md の HEREDOC パターン (sans `-s`) で feature commit を生成する
4. `git log -1 --format='%B'` で `Signed-off-by:` 行が欠落していることを確認する
5. PR の DCO check が FAILURE になる

## Root Cause

- Claude Code グローバル CLAUDE.md の "Committing changes with git" セクションが `-s` を含まない HEREDOC パターンを提示している
- sub-agent はこのグローバル指針を SKILL.md の `git commit -s -m` 指示より優先する
- `skills/code/SKILL.md` に DCO 準拠を明示した警告が存在しない
- 各 commit ステップに post-commit assertion が存在しないため、sign-off 欠落が実行時に検出できない

**採用方針**: 方針 1 (assertion guard) + 方針 2 (DCO 警告) の組み合わせ。方針 3 (事後 amend) は非採用 — recovery flow は複雑で再発防止効果が低い。

## Changed Files

- `skills/code/SKILL.md`: DCO 警告を feature commit (L271) 直前に追加、assertion guard を L271/L381 の commit 直後に追加 — bash 3.2+ 互換
- `skills/spec/SKILL.md`: assertion guard を L558/L609 の commit 直後に追加 — bash 3.2+ 互換
- `skills/review/SKILL.md`: assertion guard を L721 の commit 直後に追加 — bash 3.2+ 互換
- `skills/verify/SKILL.md`: assertion guard を L475 の commit 直後に追加 — bash 3.2+ 互換
- `modules/doc-commit-push.md`: assertion guard を commit (Step 5) 直後に追加 — bash 3.2+ 互換
- `skills/review/external-review-phase.md`: assertion guard を L47/L88/L129 の commit 直後に追加 — bash 3.2+ 互換 (scope 記載、acceptance criteria 外)
- `skills/doc/translate-phase.md`: assertion guard を L144 の commit 直後に追加 — bash 3.2+ 互換 (scope 記載、acceptance criteria 外)
- `docs/reports/literalism-audit.md`: Follow-up Issues テーブルに Issue #239 (sign-off 欠落) のエントリを追記

## Implementation Steps

1. `skills/code/SKILL.md` — feature commit (L271) の直前に DCO 警告を追加し、L271・L381 の各 `git commit` コードブロック直後に assertion guard を追加する (→ 受入条件 1, 6)

   DCO 警告テキスト (feature commit コードブロック直前に追加):
   ```
   **DCO compliance: use `git commit -s` to add `Signed-off-by:`. Do NOT use the global HEREDOC pattern from `~/.claude/CLAUDE.md` — it omits `-s`.**
   ```

   assertion guard (各 commit コードブロック直後に追加):
   ```bash
   git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
   ```

2. `skills/spec/SKILL.md`, `skills/review/SKILL.md`, `skills/verify/SKILL.md` — 各 `git commit` コードブロック直後に同じ assertion guard を追加する (→ 受入条件 2, 3, 4)。`skills/review/SKILL.md` は元のコードブロックに `git push origin HEAD` が含まれていたため、commit/guard/push の 3 ブロックに分割して追加した。

3. `modules/doc-commit-push.md` — Step 5 の `git commit` 行直後 (`git push origin HEAD` の前) に assertion guard を追加する (→ 受入条件 5)。元のブロックを commit/guard/push の 3 ブロックに分割した。

4. `skills/review/external-review-phase.md` — commit 手順 (7.2, 7.4, 7.6) の箇条書きにおいて、Commit 行の直下に `- Verify sign-off: ...` の箇条書き形式で assertion guard を追加した (コードブロックではなくインライン形式を選択した理由: 元の手順が箇条書きで記述されており、コードブロックでは構造が浮く)。`skills/doc/translate-phase.md` は commit がコードブロック形式だったため、commit/guard/push の 3 ブロックに分割して追加した (scope 記載、acceptance criteria 外)。

5. `docs/reports/literalism-audit.md` — "### Follow-up Issues" テーブルに以下を追記する (→ 受入条件 7):
   ```
   | #239 | Multiple SKILL.md files | Sub-agent sign-off non-compliance; add DCO assertion guards to enforce `Signed-off-by:` in all commits |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "grep -q \"\\^Signed-off-by:\\\"" "skills/code/SKILL.md" --> `skills/code/SKILL.md` に sign-off ガードアサーション (grep 検証) が追加されている
- <!-- verify: grep "grep -q \"\\^Signed-off-by:\\\"" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に sign-off ガードアサーションが追加されている
- <!-- verify: grep "grep -q \"\\^Signed-off-by:\\\"" "skills/review/SKILL.md" --> `skills/review/SKILL.md` に sign-off ガードアサーションが追加されている
- <!-- verify: grep "grep -q \"\\^Signed-off-by:\\\"" "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` に sign-off ガードアサーションが追加されている
- <!-- verify: grep "grep -q \"\\^Signed-off-by:\\\"" "modules/doc-commit-push.md" --> `modules/doc-commit-push.md` に sign-off ガードアサーションが追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "DCO" --> `skills/code/SKILL.md` に DCO 準拠の明示的警告が含まれる
- <!-- verify: file_contains "docs/reports/literalism-audit.md" "sign-off" --> literalism-audit レポートに本 Issue を follow-up として追記 (または別レポートで関連付け)

### Post-merge

- 任意の Issue で `/auto N` を `--pr` ルートで実行し、生成される全中間コミットに `Signed-off-by:` が含まれる (PR の DCO check が緑)
- patch ルート Issue で `/code N --patch` を実行し、main へ直接コミットされる change に sign-off が含まれる

## Notes

**設計方針 auto-resolve (non-interactive モード)**:
- Issue 提案の 3 方針のうち、方針 1 (assertion guard) + 方針 2 (DCO 警告) を採用
- 方針 3 (post-commit amend) は非採用 — recovery flow は複雑かつ事後修正のため、副作用として "Amended: " や "amend" が commit history に混入するリスクがある
- `skills/code/SKILL.md` のみ DCO 警告を追加 (最も sign-off 欠落が頻発するフェーズ、かつ acceptance criteria 6 が明示的に要求)
- `external-review-phase.md` と `translate-phase.md` は acceptance criteria に含まれないが Issue scope に記載があるため対応対象とする

## Code Retrospective

### Deviations from Design

- Specには`external-review-phase.md`の対象として行番号 L47/L88/L129 が挙げられているが、これらはコードブロックではなく箇条書きテキスト内のインライン記述だった。コードブロック直後への追加ではなく、コミット行の直下の箇条書きとして guard を追加する形で対応した。`translate-phase.md` はコードブロック形式だったためSpec通り別ブロックで追加した。
- `skills/review/SKILL.md` の review retrospective commit は、specが「L721 直後に追加」と記載しているが、実際は `git push origin HEAD` との関係上、push の前にガードを挿入する必要があったため、commit ブロックと push ブロックを分離する形で対応した。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
