# Issue #776: audit/auto: session retro 生成を /auto Step 5 に一本化し /audit auto-session を thin reader に整理

## Overview

現状、同一 session の retro が `/auto` Step 5 (`session.md`) と `/audit auto-session --full` (`data-layer.md` 内の narrative draft) の 2 経路で生成され、SSoT が曖昧になっている。

本 Issue では session retro 生成責務を `/auto` Step 5 に一本化する:
- `/auto` Step 5 が batch/XL route で常時 `data-layer.md` を生成 (notable 条件外でも)、`session.md` は notable 時のみ継続
- `/audit auto-session` は既存ファイルを表示する thin reader に変換; ファイルが無い場合のみ fallback 生成
- `/audit auto-session --full` の LLM narrative 生成経路を削除
- `auto-session-narrative-prompts.md` を削除 (dead code)

## Changed Files

- `skills/auto/SKILL.md`: L3 auto-retrospective を再構成 — route guard 後に常時 `data-layer.md` 生成を追加、notable 判定後に `session.md` 生成を継続 — bash 3.2+ compatible
- `skills/audit/SKILL.md`: frontmatter description から `--full` 記述を削除; routing・Argument Parsing から `--full` 言及を削除; Step 3 (LLM Narrative Draft) を削除; auto-session subcommand を thin reader (既存表示 + fallback 生成) に再設計
- `scripts/get-auto-session-report.sh`: `--narrative-draft` オプション・`NARRATIVE_DRAFT_PATH` 変数・narrative 挿入ブロックを削除 — bash 3.2+ compatible
- `skills/audit/auto-session-narrative-prompts.md`: delete (narrative 生成が `/auto` Step 5 に移ったため不要)
- `tests/audit-auto-session-full.bats`: delete (全テストが削除対象の `--narrative-draft` 機能をカバー)
- `tests/get-auto-session-report.bats`: `--narrative-draft` @test ブロック (lines 107-123) を削除
- `docs/environment-adaptation.md`: Domain Files テーブルから `auto-session-narrative-prompts.md` 行を削除 (line 157)
- `docs/ja/environment-adaptation.md`: 同テーブルの日本語行を削除 (line 147) (translation sync)
- `docs/workflow.md`: `/audit auto-session` 説明から `--full` モード・narrative draft 記述を削除 (line 166)
- `docs/ja/workflow.md`: 同等の日本語記述を削除 (translation sync)

## Implementation Steps

1. **`skills/auto/SKILL.md` L3 auto-retrospective 再構成** (→ AC1, AC2)
   - Route guard (step 1) 後、notable 判定 (step 2) の**前**に新しいステップを挿入:
     - Session dir 作成: `SESSION_DIR="docs/sessions/${AUTO_SESSION_ID}-${DATE}"` と `mkdir -p "$SESSION_DIR"`
     - Events 抽出: `jq -c 'select(.session_id == "'"$AUTO_SESSION_ID"'")' .tmp/auto-events.jsonl > "$SESSION_DIR/events.jsonl"`
     - data-layer.md 生成: `"${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh" "$AUTO_SESSION_ID" --output "$SESSION_DIR/data-layer.md"` (best-effort; エラーは警告のみで続行)
   - Notable 判定後: notable でない場合は data-layer.md + events.jsonl をコミットして L3 ステップを終了
   - Notable の場合: 既存の session.md 生成ステップを継続 (ただし session.md 内の cross-link は `data-layer.md` が常に存在するため確実にリンクできる)
   - 既存 step 3a (cross-link) は session.md format に組み込み済みのため削除可

2. **`skills/audit/SKILL.md` thin reader 再設計** (→ AC3, AC4, AC7, AC8)
   - frontmatter description (line 3): `--full` 関連記述 (`/audit auto-session --full <session-id>` 文) を削除
   - Command Routing (line 23): `auto-session --full <session-id>` のルーティング例を削除
   - Usage string (line 27): `--full` を Usage 表示から削除
   - Output Template Structure (line 859): "Narrative Section (skeleton)" の `or --full for LLM-assisted draft` 注記を削除
   - Argument Parsing (lines 865-866): `--full` bullet と "may appear before or after --full" を削除
   - Step 3: LLM Narrative Draft (`--full` mode only) セクションを全削除
   - Step 4 (now Step 3) Japanese sibling: `--full` 条件分岐 ("post Step 3 if `--full` was set") を削除
   - auto-session subcommand を thin reader に再設計:
     - Step 1 の前に存在確認: `docs/sessions/${SESSION_ID}*/data-layer.md` が存在するか glob チェック
     - 存在する場合: ファイルパスを出力し表示 (`cat`); `session.md` が同 dir に存在すれば cross-link を追記
     - 存在しない場合: 既存の Step 1 (get-auto-session-report.sh 実行) を fallback として実行し生成
     - `fallback` という単語を追加 (AC8 section_contains 用)

3. **`scripts/get-auto-session-report.sh` `--narrative-draft` 削除** (→ AC5, AC6)
   - line 6 の Usage コメントから `[--narrative-draft <path>]` を削除
   - line 16-17 の `--narrative-draft` オプション説明コメントを削除
   - line 46 の `NARRATIVE_DRAFT_PATH=""` 変数初期化を削除
   - lines 63-65 の `--narrative-draft` argument parsing case (`--narrative-draft)` ... `;;`) を削除
   - lines 848-892 の narrative draft 適用ブロック (`# Apply narrative draft if --narrative-draft was specified` から `fi` まで) を削除

4. **不要ファイル削除とテスト更新** (→ AC9, AC10)
   - `skills/audit/auto-session-narrative-prompts.md` を削除
   - `tests/audit-auto-session-full.bats` を削除
   - `tests/get-auto-session-report.bats`: lines 107-123 の `@test "--narrative-draft: draft content inserted into report"` ブロックを削除

5. **ドキュメント更新** (→ 文書整合性)
   - `docs/environment-adaptation.md` line 157: `auto-session-narrative-prompts.md` 行を削除
   - `docs/ja/environment-adaptation.md` line 147: 日本語等価行を削除
   - `docs/workflow.md` line 166: `/audit auto-session --full` 関連の文 ("Additionally generates LLM drafts..." および `--full` オプション説明) を削除
   - `docs/ja/workflow.md`: 同等の日本語記述を削除

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 5 が batch/XL route で常時 docs/sessions/{SID}-{DATE}/data-layer.md を生成する記述に更新されている (notable 条件外でも data-layer は生成、session.md は notable 時のみ)" --> /auto Step 5 に data-layer 生成を内包
- <!-- verify: grep "data-layer.md" "skills/auto/SKILL.md" --> SKILL.md に data-layer.md 生成への参照が追加されている
- <!-- verify: rubric "skills/audit/SKILL.md auto-session subcommand から --full flag および narrative draft 関連の記述 (Step 3 全体および Argument Parsing の --full 記述) が削除されている" --> audit auto-session --full の記述削除
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "--full" --> SKILL.md auto-session subcommand から --full 言及が削除されている
- <!-- verify: rubric "scripts/get-auto-session-report.sh から --narrative-draft オプションが削除されている (LLM narrative 挿入ロジックの撤去)" --> get-auto-session-report.sh から narrative 挿入ロジック削除
- <!-- verify: file_not_contains "scripts/get-auto-session-report.sh" "--narrative-draft" --> --narrative-draft オプションがスクリプトから削除されている
- <!-- verify: rubric "skills/audit/SKILL.md auto-session subcommand に既存ファイル表示モード (fallback で data-layer 生成) の記述が追加されている" --> audit auto-session が thin reader として再設計されている
- <!-- verify: section_contains "skills/audit/SKILL.md" "## auto-session Subcommand" "fallback" --> auto-session subcommand に fallback 記述が追加されている
- <!-- verify: rubric "skills/audit/auto-session-narrative-prompts.md が削除されている (narrative 生成が /auto Step 5 に移ったため不要; 自動解決: 使用停止の明記より削除を採用)" --> narrative-prompts.md の削除
- <!-- verify: file_not_exists "skills/audit/auto-session-narrative-prompts.md" --> narrative-prompts.md が削除されている

### Post-merge

- 次回 batch session 完了後、`/auto` Step 5 が data-layer.md を notable 条件外でも生成することを観察 (verify-type: manual)
- 次回 `/audit auto-session <SID>` 実行で既存 data-layer.md が表示され、--full フラグが unrecognized として扱われることを観察 (verify-type: manual)
- 次回 single-Issue route session で `/audit auto-session <SID>` を手動実行し data-layer.md が fallback 生成されることを観察 (verify-type: manual)

## Notes

### Auto-Resolved Ambiguity Points (/issue --non-interactive, 2026-06-28)

| 曖昧ポイント | 解決方針 | 理由 |
|---|---|---|
| `narrative-prompts.md` の処理: 削除 vs 使用停止の明記 | **削除** を採用 | Wholework distributable component として dead code を残さない方針と一致 |
| AC2 (`grep "data-layer.md"`) の false-pass リスク | **警告記録のみ** | `skills/auto/SKILL.md` line 742 に既存 cross-link があり AC2 は実装前から PASS する可能性。AC1 rubric を primary verification として扱うこと |
| AC4 `file_not_contains "--full"` のスコープ | **適切** と判断 | `--full` 言及は全て auto-session subcommand の文脈 (description/routing/Argument Parsing/Step 3/Step 4) のみ |

### Implementation Notes

- `skills/auto/SKILL.md` Step 5 の section heading は現在 `### Step 5: Completion Report` (line 567) — data-layer 生成追加後も見出し変更は不要 (L3 セクション内の一部として扱う)
- `skills/audit/SKILL.md` の `--full` 言及箇所 (line 3, 23, 27, 859, 865, 866, 947, 949, 952, 993, 996) を全て削除する。削除漏れに注意
- Step 3 (get-auto-session-report.sh) の削除は Python ブロック (lines 850-889) も含む
- `docs/ja/` ファイルの更新はパターンが日本語なので `file_not_contains` より手動確認が適切

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved ambiguity points, verify command improvements / https://github.com/saitoco/wholework/issues/776#issuecomment-4820239570
