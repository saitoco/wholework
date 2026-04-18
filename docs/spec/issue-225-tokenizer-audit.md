# Issue #225: 新 tokenizer (1.0-1.35×) 対応の文字数 / token 前提監査

## Overview

Claude Opus 4.7 の新 tokenizer (1.0–1.35× 多トークン) に対応するため、Wholework の distributable components (`skills/`, `agents/`, `modules/`, `scripts/`) 全体を監査し、文字数 / token 前提箇所を特定する。発見箇所は inline 修正または follow-up Issue 起票で対処し、監査結果を `docs/reports/tokenizer-audit.md` に記録する。

監査対象パターン（Issue Purpose より）：
1. `max_tokens` / `max-tokens` / `MAX_TOKENS` の明示設定値
2. `head -c N` など文字数ベースの truncation
3. `head -n N` など行数ベースの制限
4. `1 char ≈ 1 token` の暗黙前提（コメント / ドキュメント記述）
5. 文字数による分割 / chunking 処理
6. ログ / 出力 truncation サイズ

先例: `docs/reports/literalism-audit.md` (C5), `docs/reports/progress-scaffolding-audit.md` (C6)

## Changed Files

- `docs/reports/tokenizer-audit.md`: new file — tokenizer audit report

## Implementation Steps

1. Audit `skills/` (22 .md files), `agents/` (6 .md files), `modules/` (27 .md files), `scripts/` (34 files) for 6 patterns using Grep/Read; record all hits with file:line, pattern type, and risk level (LOW / MEDIUM / HIGH)
   - Pattern 1: `grep -rn "max_tokens\|max-tokens\|MAX_TOKENS" skills/ agents/ modules/ scripts/`
   - Pattern 2: `grep -rn "head -c" skills/ agents/ modules/ scripts/`
   - Pattern 3: `grep -rn "head -n" scripts/` (manual check — confirm token vs. pagination)
   - Pattern 4: `grep -rn "char.*token\|token.*char\|1 char" skills/ agents/ modules/ scripts/`
   - Pattern 5: `grep -rn "chunk\|split.*char\|char.*split" skills/ agents/ modules/ scripts/`
   - Pattern 6: `grep -rn "truncat" skills/ agents/ modules/ scripts/`
   (→ acceptance criteria: Findings section)

2. For each finding: apply inline fix if single-file and LOW-risk; open follow-up Issue if multi-file or MEDIUM/HIGH risk (→ acceptance criteria: Remediation section)

3. Write `docs/reports/tokenizer-audit.md` with Summary / Findings / Remediation sections following `literalism-audit.md` structure; include Preserved section for intentional character-count usage found (→ acceptance criteria: file_exists, section_contains)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/tokenizer-audit.md" --> 監査レポートが `docs/reports/tokenizer-audit.md` に作成されている
- <!-- verify: section_contains "docs/reports/tokenizer-audit.md" "## Findings" "." --> Findings セクションに文字数 / token 前提箇所の一覧が記載されている
- <!-- verify: section_contains "docs/reports/tokenizer-audit.md" "## Remediation" "." --> Remediation セクションに inline 修正 / follow-up Issue 番号が記載されている

### Post-merge

- 発見箇所の修正が完了、または follow-up Issue 起票済み（inline 修正は本 PR に含め、follow-up Issue 番号は Remediation セクションに記載）

## Notes

### 事前調査結果（non-interactive mode auto-resolve）

/spec 実行時に以下の調査を実施済み。/code での再調査でも同様の結果が得られる想定。

**Pattern 1 — max_tokens**: `skills/`, `agents/`, `modules/`, `scripts/` 全体でゼロヒット。explicit max_tokens 設定なし。

**Pattern 2 — head -c**: ゼロヒット。character-based truncation なし。

**Pattern 3 — head -n**: `scripts/triage-backlog-filter.sh:64` のみ — `head -n "$LIMIT"` は GitHub API ページネーション制限（user-configurable、トークン推定に非依存）。**token-sensitive ではない**。

**Pattern 4 — 1 char ≈ 1 token 暗黙前提**: ゼロヒット。コード・コメント・ドキュメントに記述なし。

**Pattern 5 — character-based chunking**: ゼロヒット。

**Pattern 6 — truncation**: `modules/measurement-scope.md` 等での "truncation" 言及はドキュメント記述（監査スコープ外の説明文）。実装コードでの token 起因 truncation なし。

**その他の文字数閾値（token 非依存と判定）:**
- `skills/doc/SKILL.md:490` — `20 characters or less` (short-line exclusion) はコンテンツ分類ヒューリスティック（ツール名・URL 等のフィルタ）。トークン予算非依存。
- `skills/spec/SKILL.md:356` — `max 30 characters` は Spec ファイル名の kebab-case 命名規則（URL-safety 制約）。トークン予算非依存。

**結論**: HIGH / MEDIUM リスク findings なし。inline 修正・follow-up Issue 起票は不要の可能性が高い。/code では上記 grep を再実行して confirm した後、`docs/reports/tokenizer-audit.md` を作成すること。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue 受け入れ条件の verify コマンドは `file_exists` + `section_contains` のみで構成されており、明確で自動検証しやすい設計だった。"." を text パターンに使うのはセクション存在確認として有効。

#### design
- Spec の Notes セクションで事前調査結果（grep 結果）を記録し、findings が 0件になる根拠を先行して示した設計は適切。実装時の再確認も一致した。

#### code
- Initial Write でパスが worktree 外（main リポジトリの絶対パス）になったため cp + rm で修正が必要になった（Code Retrospective に記録済み）。worktree 内では相対パスを使うべき。

#### review
- patch route（PR なし、main 直コミット）のためレビューなし。単一ファイル新規作成かつ findings 0件の低リスク変更なのでスキップは妥当。

#### merge
- `closes #225` が patch コミットに含まれており、Issue は自動クローズされている。

#### verify
- Pre-merge 条件 3件すべて PASS。Post-merge manual 条件（修正完了/follow-up 起票）は findings 0件のため実質的に満たされているが、verify-type: manual なのでユーザー確認扱い。`phase/verify` ラベルを付与した。

### Improvement Proposals
- N/A

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- Write tool uses absolute paths, but the worktree CWD differs from the main repo path. The file was initially written to the main repo (`/Users/saito/src/wholework/docs/reports/tokenizer-audit.md`) instead of the worktree. Copied to worktree and removed from main repo before commit. Spec warning at Step 2 ("verify CWD first, use CWD-relative paths") applies.

### Rework
- File path correction: Initial Write to absolute main-repo path; needed cp + rm to move to worktree before commit.
