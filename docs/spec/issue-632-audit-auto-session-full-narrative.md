# Issue #632: audit: /audit auto-session --full で narrative section を LLM が draft

## Overview

R2（`/audit auto-session <id>`）が生成する data 層レポートの narrative section（What worked / Limits and gaps / Improvement candidates surfaced / Conclusion）は TBD skeleton のみ提示する。本 Issue は `--full` フラグを追加し、LLM が narrative draft を生成する機能を実装する。draft には `[LLM draft — human review required]` マーカーを付与し、human gate を維持する。Improvement candidates は `gh issue list --search` で既存 Issue との照合を行い、「既存 #XXX に統合提案 / Issue 起票候補 / 凍結推奨」に分類する。

**Conflict resolution (auto-resolve):** Issue 本文は 4 つの narrative section（What worked / Limits and gaps / **Improvement candidates surfaced** / Conclusion）を前提とするが、現状の `scripts/get-auto-session-report.sh` の skeleton は 3 section のみ（"Improvement candidates surfaced" が欠落）。本実装でスクリプトに 4 番目のセクションを追加する（後方互換性あり：既存 bats は `"Narrative Section"` 見出しのみを grep しており、サブセクション変更で壊れない）。

## Changed Files

- `scripts/get-auto-session-report.sh`: narrative skeleton に `### Improvement candidates surfaced` セクションを追加（4 section 化）；`--narrative-draft <path>` フラグを追加し、pre-generated draft ファイルを受け取って報告書内の TBD 行を draft 内容 + `[LLM draft — human review required]` マーカーで置換 — bash 3.2+ compatible
- `skills/audit/auto-session-narrative-prompts.md`: 新規ファイル。4 narrative section それぞれの LLM 向け prompt template と、2 つの参考レポートから抽出した few-shot examples を記載
- `skills/audit/SKILL.md`: (a) command routing に `--full` フラグの処理を追加；(b) Argument Parsing に `--full` を追記；(c) Step 3（`--full` 専用）として LLM narrative draft 生成・分類・挿入フロー追加；(d) Narrative Section 出力テンプレート説明を 4 section に更新
- `tests/audit-auto-session-full.bats`: 新規 bats test ファイル。3 test cases: (a) `--narrative-draft` フラグで draft 内容が挿入されること、(b) `[LLM draft` マーカーが存在すること、(c) classification マーカー（既存 / 新規 / 凍結推奨）が出力に含まれること
- `docs/workflow.md`: `/audit auto-session` 説明を更新し `--full` モード（LLM narrative draft 生成）を記載

## Implementation Steps

1. **`scripts/get-auto-session-report.sh`** — narrative skeleton 拡張 + `--narrative-draft` フラグ追加 (after none) (→ AC: bats テスト)
   - Report の heredoc 末尾に `### Improvement candidates surfaced` セクションを追加し `TBD — fill in after reviewing the session` を記載（4 section 化）
   - 引数パース: `--narrative-draft <path>` フラグをパースし `NARRATIVE_DRAFT_PATH` に格納
   - heredoc で OUTPUT_PATH に書き込み後、`NARRATIVE_DRAFT_PATH` が指定されている場合: python3 を使って `OUTPUT_PATH` 内の narrative 各 TBD 行を draft ファイル内容で置換 + `> [LLM draft — human review required]` ブロック引用マーカーを各セクション先頭に挿入（bash 3.2+ 互換; python3 は既存 `validate-skill-syntax.py` で使用済み）
   - スクリプト先頭の Usage コメントに `--narrative-draft` を追記

2. **`skills/audit/auto-session-narrative-prompts.md`** (新規) (after none, parallel with 1) (→ AC: file_exists, grep prompts, grep few-shot)
   - 4 narrative section それぞれの prompt template を記載:
     - `### What worked`: 「以下の data から、設計通り機能した要素を 3-5 件抽出」
     - `### Limits and gaps`: 「以下の data から、構造的問題を含む観測を 3-5 件抽出」
     - `### Improvement candidates surfaced`: 「Limits の各項目を Issue 起票候補としてフォーマット」（分類ガイド含む）
     - `### Conclusion`: 「全体評価を 2-3 段落で」
   - `## Few-shot examples` セクションに `auto-session-performance-2026-06-13.md` と `auto-batch-list-mode-2026-06-14.md` の narrative section から抜粋をインライン参照

3. **`skills/audit/SKILL.md`** (after 1, 2) (→ AC: grep --full, grep LLM draft, rubric)
   - **Command routing**: `auto-session` ルーティング行を `auto-session --full <id>` ケースも含むよう更新（`--full` フラグは auto-session セクション内で処理）
   - **Argument Parsing**: `--full` フラグを追加（`FULL_MODE=true`）；`<session-id>` は `--full` の後ろまたは前どちらにでも指定可能とする
   - **Narrative Section 出力テンプレート説明**: `"What worked", "Limits and gaps", "Conclusion"` → `"What worked", "Limits and gaps", "Improvement candidates surfaced", "Conclusion"` に更新
   - **Step 3（新規、`--full` 専用）**:
     1. Step 1 で生成したレポートを Read
     2. `gh issue view <N> --json title,body,labels` で Per-Issue Durations テーブルから抽出した各 Issue を取得
     3. `${CLAUDE_PLUGIN_ROOT}/skills/audit/auto-session-narrative-prompts.md` を Read してプロンプトテンプレートと few-shot examples を取得
     4. 各 narrative section の draft を生成（What worked / Limits and gaps / Improvement candidates surfaced / Conclusion）
     5. Improvement candidates 各項目について `gh issue list --search "<keyword>"` で既存 Issue を検索し分類:
        - 既存 Open Issue あり → 「既存 #XXX に統合提案」マーカー
        - 既存なし → 「Issue 起票候補」マーカー + 起票時の本文 skeleton
        - Icebox 候補 → 「凍結推奨（trigger: XXX）」マーカー
     6. draft を `.tmp/narrative-draft-<session-id>.md` に Write ツールで保存
     7. `${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh <session-id> --narrative-draft .tmp/narrative-draft-<session-id>.md --output <report-path>` を実行してレポートに draft を挿入
     8. `.tmp/narrative-draft-<session-id>.md` を削除
     9. 「Narrative draft 完成。`[LLM draft — human review required]` マーカー付き。レビュー・編集後に commit してください。」を出力
   - **SKILL.md 内に** `[LLM draft — human review required]` というマーカー文字列を（説明文の一部として）記載し、verify コマンドが grep できるようにする
   - 完全自動起票は行わない（human gate 維持）を Notes に明示

4. **`tests/audit-auto-session-full.bats`** (新規) (after 1) (→ AC: bats テスト green)
   - setup: `AUTO_EVENTS_LOG`、`OUTPUT_PATH` を `BATS_TEST_TMPDIR` に設定；fixture events JSONL を作成
   - `@test "full mode: --narrative-draft inserts draft content into report"`:
     - `get-auto-session-report.sh abc-999 --output $OUTPUT_PATH --no-github` を実行してベースレポート生成
     - narrative draft fixture ファイルを `.tmp/draft-fixture.md` に作成（各セクションのダミー content を含む）
     - `get-auto-session-report.sh abc-999 --narrative-draft .tmp/draft-fixture.md --output $OUTPUT_PATH --no-github` を実行
     - `$OUTPUT_PATH` にダミー content が含まれることを確認
   - `@test "full mode: [LLM draft marker is attached to narrative sections"`:
     - `--narrative-draft` を指定して実行
     - `grep -q "\[LLM draft" "$OUTPUT_PATH"` で確認
   - `@test "full mode: classification markers appear in narrative draft"`:
     - classification marker（「既存 #」「Issue 起票候補」「凍結推奨」）を含む draft fixture を使用
     - 3 種のマーカーがすべて `$OUTPUT_PATH` に含まれることを確認

5. **`docs/workflow.md`** (after 3) (→ SHOULD) (→ AC: check-translation-sync)
   - `/audit auto-session <session-id>` の説明末尾を更新: 「Narrative skeleton for manual or R3 LLM-assisted fill-in」→「Narrative skeleton for manual fill-in; `--full` for LLM-assisted draft of all 4 sections (What worked / Limits and gaps / Improvement candidates surfaced / Conclusion) with `[LLM draft — human review required]` markers and improvement candidate classification (existing issue / new / icebox)」

## Verification

### Pre-merge

- <!-- verify: grep -- "--full" "skills/audit/SKILL.md" --> `/audit auto-session --full` オプションが文書化されている
- <!-- verify: file_exists "skills/audit/auto-session-narrative-prompts.md" --> narrative prompt template が存在する
- <!-- verify: grep "What worked|Limits and gaps|Improvement candidates" "skills/audit/auto-session-narrative-prompts.md" --> 4 narrative section の prompt が定義されている
- <!-- verify: grep "Few-shot|examples" "skills/audit/auto-session-narrative-prompts.md" --> few-shot examples（過去レポート参照）が含まれている
- <!-- verify: grep "LLM draft.*human review required|\\[LLM draft" "skills/audit/SKILL.md" --> draft マーカーで人間 review 必須を明示
- <!-- verify: rubric "skills/audit/SKILL.md --full mode specifies: LLM draft of all 4 narrative sections, marker requiring human review, improvement candidate classification (existing issue / new / icebox), and no auto-issue-filing (human gate preserved)" --> 仕様が rubric 基準を満たす
- <!-- verify: command "bats tests/audit-auto-session-full.bats" --> bats テストが green（draft 生成 / マーカー付与 / classification の最小 3 ケース）
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期

### Post-merge

- 次回 `/auto` 完走後に `/audit auto-session --full` で narrative draft が生成され、手動執筆と同等の質に達することを確認 (verify-type: manual)
- LLM draft 起点で起票された Improvement Issue が、過去のような手動執筆起点と比べ retrospective の質を落としていないことを 1-2 セッションで観察 (verify-type: observation event=auto-session-report-published)

## Notes

- **自動解決: narrative section 数の不整合**: Issue 本文は 4 section を前提とするが `get-auto-session-report.sh` には 3 section しかない。"Improvement candidates surfaced" を Step 1 でスクリプトに追加することで解消（後方互換性確認済み）。
- **設計方針**: `--full` の LLM 部分は SKILL.md 層で担当（SKILL.md が LLM として narrative を生成）。スクリプトはデータ生成と draft 挿入（`--narrative-draft`）のみを担当。これは既存アーキテクチャ（LLM 推論は SKILL.md、決定論的処理はスクリプト）に準拠。
- **bats テストの対象**: LLM 推論（draft 生成）は bats テスト不可のため、`--narrative-draft` フラグの動作（挿入・マーカー付与）をスクリプトレイヤーでテストする。LLM 品質は Post-merge の観察 AC でカバー。
- **完全自動起票禁止**: Improvement candidates の分類結果は draft に記載するのみ。`gh issue create` は呼ばない（human gate 維持）。
- **python3 使用**: `--narrative-draft` 挿入ロジックには python3 を使用。既存 `scripts/validate-skill-syntax.py` で python3 使用済みのため依存関係の追加なし。

## Code Retrospective

### Deviations from Design

- N/A — 実装は Spec の設計通り。python3 の heredoc 埋め込み（`python3 - arg1 arg2 << 'PYTHON_EOF'`）を採用し、bash 3.2+ 互換性を維持しながら複数行 Python ロジックをスクリプト内に実装した。Spec では「python3 を使用」とのみ記載していたが、bash スクリプト内に直接埋め込む形式はアーキテクチャ判断として適切（外部 .py ファイルを別途追加する必要がない）。

### Design Gaps/Ambiguities

- `check-translation-sync.sh` は git commit タイムスタンプを比較するため、同じセッション内でも commit 前は OUTDATED になる。`docs/workflow.md` 変更後すぐに `docs/ja/workflow.md` を別コミットで追従する必要があることを確認した（Spec には記載なし）。
- bats test の setup で `BATS_TEST_TMPDIR` を使用。fixture JSONL を毎テスト setup で生成し、`--no-github` フラグで hermetic 実行を保証した。test case 3（classification markers）で日本語マーカー文字列（「既存 #」「凍結推奨」）を grep するため、bats が multibyte grep を正しく処理することを確認した。

### Rework

- N/A — 1 回の実装で全テストが PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `--narrative-draft` フラグをスクリプト層に追加し、LLM draft 挿入ロジックは python3 heredoc 埋め込みで実装（外部 .py ファイル不要、bash 3.2+ 互換）
- `[LLM draft — human review required]` マーカーは blockquote prefix（`> `）として挿入。ユーザーが一目でLLM生成コンテンツを識別できる
- Improvement candidates の分類（既存 #/ Issue 起票候補 / 凍結推奨）はSKILL.md記載のみで、自動起票は行わない（human gate 維持）
- bats テストの対象はスクリプト層の `--narrative-draft` 動作のみ。LLM draft 品質は Post-merge の観察 AC でカバー

### Deferred Items
- LLM draft 生成の品質評価: Post-merge で 1-2 セッション観察して確認（manual AC）
- Improvement candidates の起票精度: 実際の `/audit auto-session --full` 実行後に評価（observation AC）
- `docs/ja/workflow.md` 翻訳の自動 sync: 現状は手動追従が必要、Translation workflow の改善は別 Issue

### Notes for Next Phase
- PR #651 の CI が green であることを確認してからマージ
- Post-merge manual AC: 次回 `/auto` 完走後に `/audit auto-session --full <id>` を実行し、narrative draft が実際に挿入されることを確認
- `tests/audit-auto-session-full.bats` の 3 tests はスクリプト層のみをカバー。SKILL.md の Step 3（LLM 推論部分）は bats 対象外

## review retrospective

### Spec vs. 実装乖離パターン

- SKILL.md:1012 の stale コメント（`skeleton-only in this implementation / R3 will add`）が実装済みの `--full` mode と矛盾していた。MUST 修正。Spec の Changed Files 記載に「SKILL.md に `[LLM draft — human review required]` というマーカー文字列を記載する」と書かれているが、**古い注記の削除**については Spec に明示がなかった。実装者が過去の TODO コメントを削除し忘れるパターン — 「置換型変更（旧実装の痕跡残存）」に注意。

### 繰り返しイシュー

- 特記事項なし。MUST 1件、SHOULD 1件のみで繰り返しパターンは検出されず。

### 受け入れ条件検証困難度

- 全 8 項目 PASS。rubric AC が `/review` safe mode で実行されたが、サブエージェントが main ブランチの SKILL.md を読んで FAIL 判定する誤りが発生した（worktree 内の PR ブランチ版を読むべき）。`rubric` コマンドの grader はファイルパスを解決する際に absolute path を指定するか、calling skill が worktree の正しいパスを明示する必要がある。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #651 を squash merge（`--squash --delete-branch`）で main にマージ完了
- conflict なし（mergeable=true, CI=success, review=approved）、conflict resolution ステップはスキップ
- Phase Handoff write を main ブランチ上の Spec に直接コミット・プッシュ

### Deferred Items
- Post-merge manual AC: 次回 `/auto` 完走後に `/audit auto-session --full <id>` を実行し narrative draft が挿入されることを確認（verify-type: manual）
- Improvement Issue 品質観察: 1-2 セッション後に `/audit auto-session --full` 起点の起票品質を評価（verify-type: observation）

### Notes for Next Phase
- verify フェーズは Post-merge AC 2件（manual / observation）をカバーすること
- `skills/audit/auto-session-narrative-prompts.md` の few-shot examples（2レポート参照）の品質は実際の `--full` 実行後に評価可能
- `tests/audit-auto-session-full.bats` 3件はスクリプト層のみカバー。SKILL.md Step 3（LLM 推論部分）は手動 verify が必要
