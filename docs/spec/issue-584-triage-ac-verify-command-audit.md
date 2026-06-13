# Issue #584: triage-skill: AC verify command 整合性監査を明示ステップとして体系化

## Overview

`/triage` skill に AC verify command 整合性監査を明示ステップ（Step 7）として追加し、検出対象パターンを Domain file に体系化する。2026-06-13 の `/auto` セッションで 3/14 Issue（21%）に verify command 欠陥を発見した実績を「保証された責務」に格上げする。

実装の柱:
1. `skills/triage/SKILL.md` に Step 7（サイズ情報取得後）として監査ステップを追加
2. `skills/triage/skill-dev-verify-audit.md`（Domain file）に 5 パターンの詳細チェックリストを配置
3. 監査結果はコメント投稿のみ（Issue body 自動書き換えなし）

## Changed Files

- `skills/triage/SKILL.md`: Single Issue Execution に Step 7「AC Verify Command Integrity Audit」を追加（Step 6 直後）; 旧 Step 7-10 を Step 8-11 に繰り下げ; Bulk Execution Step 3 ループ内に監査サブステップを追加
- `skills/triage/skill-dev-verify-audit.md`: 新規 Domain file（`type: domain`, `skill: triage`, `load_when` なし＝無条件ロード）

## Implementation Steps

1. `skills/triage/SKILL.md` — Single Issue Execution に Step 7 を追加し、旧 Step 7-10 を Step 8-11 に繰り下げ (→ AC 1)

   追加する Step 7 の内容（Step 6 直後に挿入）:

   ```markdown
   ### Step 7: AC Verify Command Integrity Audit

   Read `${CLAUDE_PLUGIN_ROOT}/skills/triage/skill-dev-verify-audit.md` for the verify command audit patterns and follow the "Processing Steps" section.

   Skip this step if the issue body contains no `<!-- verify: ... -->` patterns.
   ```

   同時に旧ステップを繰り下げ:
   - `### Step 7: Value Assignment` → `### Step 8: Value Assignment`
   - `### Step 8: Lightweight Analysis` → `### Step 9: Lightweight Analysis`
   - `### Step 9: Triage Marker` → `### Step 10: Triage Marker`
   - `### Step 10: Completion Report` → `### Step 11: Completion Report`

   また Step 11 の `next-action-guide.md` 呼び出し内の `SIZE={triaged size}` は繰り下げ後も変わらない（Size は Step 6 で取得済み）。

2. `skills/triage/SKILL.md` — Bulk Execution Step 3 ループに監査サブステップを追加 (→ AC 1)

   Step 3 の issue ループの最後（`7. Duplicate comment:` の後）にサブステップを追加:

   ```
   8. AC verify command audit: if the issue body contains `<!-- verify: ... -->` patterns,
      read ${CLAUDE_PLUGIN_ROOT}/skills/triage/skill-dev-verify-audit.md and follow the
      "Processing Steps" section. Post audit comment if issues are found (non-destructive).
   ```

3. `skills/triage/skill-dev-verify-audit.md` を新規作成: frontmatter + Pattern 1（grep 引数順誤り）+ Pattern 2/3（常時 PASS / 常時 FAIL）+ 非破壊的振る舞い仕様 (→ AC 2, 3, 4, 5, 7, 8)

   Frontmatter:
   ```yaml
   ---
   type: domain
   skill: triage
   ---
   ```
   （`load_when` なし: 全リポジトリで無条件ロード）

   「Pattern 1: grep 引数順誤り」セクションに「引数順」を含む記述を配置。
   「Pattern 2: 常時 PASS な verify command」「Pattern 3: 常時 FAIL な verify command」セクションを配置。
   「## Non-Destructive Audit Behavior」セクションに「non-destructive」を含む記述と、コメント投稿テンプレートを配置。

4. `skills/triage/skill-dev-verify-audit.md` に Pattern 4（patch route × gh pr checks）と Pattern 5（destructive command 安全性チェック）を追加 (→ AC 6, 7)

   「Pattern 4: patch route × `gh pr checks` 不整合」セクションに「patch route」を含む記述を配置。
   「Pattern 5: destructive command 安全性チェック」セクションを追加。
   修復提案コメントテンプレートを確認し、非破壊的（Issue body 自動書き換えなし）を明示。

## Verification

### Pre-merge

- <!-- verify: grep "AC verify command 整合性監査|verify command audit" "skills/triage/SKILL.md" --> `/triage` SKILL.md に新ステップ「AC verify command 整合性監査」が追加されている
- <!-- verify: file_exists "skills/triage/skill-dev-verify-audit.md" --> Domain file が存在する
- <!-- verify: grep "type: domain" "skills/triage/skill-dev-verify-audit.md" --> Domain file が `type: domain` frontmatter を持つ
- <!-- verify: grep "grep 引数順|引数順" "skills/triage/skill-dev-verify-audit.md" --> grep 引数順誤りパターンが Domain file に文書化されている
- <!-- verify: grep "常時 PASS|常時 FAIL" "skills/triage/skill-dev-verify-audit.md" --> 常時 PASS / 常時 FAIL パターンが文書化されている
- <!-- verify: grep "patch route|gh pr checks" "skills/triage/skill-dev-verify-audit.md" --> patch route × gh pr checks 不整合パターンが文書化されている
- <!-- verify: rubric "skills/triage/SKILL.md and skill-dev-verify-audit.md together specify a non-destructive audit: triage posts a comment with detected issues and suggested fixes, but does NOT auto-edit the Issue body" --> 監査は非破壊的（コメント投稿のみ）であることが明記されている
- <!-- verify: grep "non-destructive|post.*comment" "skills/triage/skill-dev-verify-audit.md" --> Domain file に非破壊的監査の説明キーワードが存在する（rubric 補足）
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存 bats テストが green

### Post-merge

- 次回の `/triage --backlog` 実行で verify command 監査コメントが新規 Issue に投稿されることを観察 <!-- verify-type: opportunistic -->

## Notes

### Auto-Resolve Log

以下の曖昧ポイントをモデル判断で自動解決した（`--non-interactive` モード）:

**1. Domain file の `load_when` 条件**

- **選択**: `load_when` なし（無条件ロード）
- **理由**: Issue の目的は「保証された責務に格上げ」（全リポジトリで監査を保証）。`file_exists_any: [scripts/validate-skill-syntax.py]` を条件にすると、wholework 開発リポジトリ以外（ユーザープロジェクト）では監査が実行されず目的と矛盾する。他の triage domain file は存在しないため既存パターンとの整合性問題もない。

**2. Step 配置（Step 番号）**

- **選択**: Size Assignment（Step 6）の直後を Step 7 とし、旧 Step 7-10 を 8-11 に繰り下げ
- **理由**: Pattern 4（patch route × gh pr checks）は Size 情報が必要なため Step 6 以降に配置する必要がある。Issue 提案の「Step 4.5」は小数ステップ（`validate-skill-syntax.py` が検出してエラー）のため使用不可。整数ステップで Size Assignment 直後の Step 7 が最適位置。

### Simplicity Rule Note

Pre-merge 検証項目が 9 件（light 上限 5 件を超過）。Issue body の AC がすでに 9 件定義されており、verify command sync rule に従い verbatim コピーのため削減不可。SHOULD レベルの変更（docs/workflow.md の triage 説明更新）は実装ステップ上限（5 件）を考慮しスコープ外とした。

### bats テスト

Domain file（`skills/triage/skill-dev-verify-audit.md`）は `validate-skill-syntax.py` の検証対象外（SKILL.md のみ対象）のため新規テスト不要。既存 bats テストへの影響なし。

### 翻訳同期

変更対象は `skills/triage/` 配下のみ（`docs/*.md` 非対象）のため `docs/ja/` 同期不要。

## Code Retrospective

### Deviations from Design

- Step 7 の見出し文字列は「AC Verify Command Integrity Audit」（英語）とし、SKILL.md 本文中の説明テキストに「verify command audit patterns」を含めることで、verify command `grep "verify command audit"` パターンマッチを確保した。Spec の仮見出しに含まれた「AC verify command 整合性監査」（日本語）は本文には含めなかった（英語優先の SKILL.md 規約に従う）。

### Design Gaps/Ambiguities

- Stale test assertion check: SKILL.md から削除されたステップ見出し文字列（`Step 7: Value Assignment` 等）を `tests/` で検索したが、triage SKILL.md の内部ステップ名をテストは直接参照していないため stale assertion なし。
- `validate-skill-syntax.py` はドメインファイル（`skill-dev-verify-audit.md`）を検証対象外とすることを Spec が明示していたため、domain file の frontmatter バリデーションは手動で確認した（`type: domain`, `skill: triage` の存在確認）。

### Rework

- N/A（1 回の実装で完了、リワークなし）

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- Spec と実装は完全一致。Step 7 配置（Size Assignment 直後）、5 パターン構成、非破壊的振る舞い仕様のいずれも Spec の設計通り実装されていた。

### Recurring Issues

- CONSIDER 課題が 2 種（Pattern 4 の Bulk Execution Size 参照先未明示、$NUMBER コンテキスト未明示）は同一のルート原因（Single Issue / Bulk Execution の二コンテキストをまたぐ変数説明）。Domain file 記述ガイドラインとして「Bulk Execution での変数参照元を明示せよ」を今後のパターンとして意識する価値がある。

### Acceptance Criteria Verification Difficulty

- 全 9 AC に明示的 verify command があり、UNCERTAIN なし。rubric verify command（AC 7）は grader 実行なしで PASS/FAIL を判定可能であった（SKILL.md + Domain file が共同で非破壊的監査を仕様化していることが diff から自明）。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- 全 AC PASS（9/9）、CI 全 SUCCESS、MUST 課題ゼロ。CONSIDER 課題 3 件を修正済み
- Pattern 4 の "Detection approach:" ブロック追加と "Posting the Comment" `$NUMBER` 説明追加（追記のみ、既存 verify command との矛盾なし）

### Deferred Items
- Post-merge 観察: 次回 `/triage --backlog` で監査コメントが新規 Issue に投稿されることを opportunistic で確認
- Issue #584 の Post-merge AC は `/merge` 完了後に観察

### Notes for Next Phase
- MUST 課題なし、レビュー対応済み。`/merge 608` でマージ可能
- AC 9（bats テスト green）は CI で確認済み（PASS）
- Issue #584 の全 Pre-merge AC は `[x]` 完了
