# Issue #372: auto: Step 4a 後に Spec の Improvement Proposals を Step 13 相当で自動起票

## Overview

`/auto` の Step 4a（Auto Retrospective 書き込み）は `/verify` Step 13（Improvement Proposals 起票）の完了**後**に実行されるため、Auto Retrospective に記録された Improvement Proposals が初回 `/auto` run では自動起票されず、手動で `/verify` を再実行する必要があった（#365・#386 の 2 件で再発確認）。

Option 1（共有モジュール化）を採用：Improvement Proposal 収集・起票ロジックを `modules/retro-proposals.md` に切り出し、`/verify` Step 13 から共有モジュール呼び出しに置換（後方互換維持）、`/auto` Step 4a の commit+push 完了後にも同モジュールを呼び出す。

## Changed Files

- `modules/retro-proposals.md`: 新規ファイル — `/verify` Step 13 の Improvement Proposal 収集・Issue 化ロジックを共有モジュールとして切り出す
- `skills/verify/SKILL.md`: Step 13 のインラインロジック（Extract〜Create Issue 部分）を `modules/retro-proposals.md` 呼び出しに置換
- `skills/auto/SKILL.md`: Step 4a の commit+push（step 5）後に step 6 を追加し `modules/retro-proposals.md` を呼び出す；allowed-tools に `gh issue create:*` と `Glob` を追加
- `docs/structure.md`: モジュール数を (32 files) → (33 files) に更新；Key Files テーブルに `modules/retro-proposals.md` のエントリを追加
- `docs/ja/structure.md`: 上記に対応する日本語ミラーを同期

## Implementation Steps

1. **`modules/retro-proposals.md` 作成** — `/verify` Step 13 の下記ブロックをそのままモジュールに移植する（後述の Input / Processing Steps 構成で）（→ AC1, AC2, AC3）
   - Input: `SPEC_PATH`, `NUMBER`, `HAS_SKILL_PROPOSALS`
   - Processing Steps: title-normalizer 読込み → Spec ファイル特定（Glob `$SPEC_PATH/issue-$NUMBER-*.md`、不在時は "No Spec file" ログ出力して return）→ 各 retrospective セクションから `### Improvement Proposals` 抽出 → N/A 判定 → 重複排除 → HAS_SKILL_PROPOSALS による分岐（Code / Skill infrastructure 分類 + Domain-classifier 呼び出し）→ open Issues 重複チェック → freshness チェック → `gh issue create --label "retro/verify"` で起票
   - Output: 起票 Issue 番号出力、または "No improvement proposals" ログ

2. **`skills/verify/SKILL.md` Step 13 修正** — Step 13 の「Extract text from `### Improvement Proposals`…」から「Create Issue and add verify commands」末尾までのインラインロジックを削除し、`Read \`${CLAUDE_PLUGIN_ROOT}/modules/retro-proposals.md\` and follow the "Processing Steps" section.` に置換する（title-normalizer 読込みと HAS_SKILL_PROPOSALS 再利用ノートは Step 13 冒頭に残す）（after 1）（→ AC2）

3. **`skills/auto/SKILL.md` Step 4a 修正** — Step 4a の step 5（commit+push）の直後に step 6 を追加（after 1）（→ AC1, AC3）：
   ```
   6. **Collect and create Improvement Proposal Issues**: Read `${CLAUDE_PLUGIN_ROOT}/modules/retro-proposals.md` and follow the "Processing Steps" section. Use `SPEC_PATH` and `HAS_SKILL_PROPOSALS` already retained from this step's `detect-config-markers.md` call. If the shared module returns no proposals, skip silently.
   ```
   また allowed-tools frontmatter の Bash 部分に `gh issue create:*` を追加、非 Bash ツール列に `Glob` を追加する。

4. **`docs/structure.md` 更新** — Directory Layout の `modules/` 行を `(32 files)` → `(33 files)` に変更；Key Files テーブルの `modules/domain-classifier.md` エントリの直後に下記を追加（after 1）（→ SHOULD-level）：
   ```
   - `modules/retro-proposals.md` — Improvement Proposal collection and Issue creation (shared by /verify Step 13 and /auto Step 4a)
   ```

5. **`docs/ja/structure.md` 同期** — 上記 docs/structure.md の変更（モジュール数 + Key Files エントリ）を日本語ミラーに反映する（after 4）（→ SHOULD-level）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Step 4a 後に Spec の ### Improvement Proposals を読んで Issue 化する処理が追加されている (共有モジュール経由 or 直接記述、いずれの形でも可)" --> `/auto` Step 4a 完了後に Auto Retrospective の Improvement Proposals を Issue 起票するフローが `skills/auto/SKILL.md` に追加される
- <!-- verify: rubric "skills/verify/SKILL.md の Step 13 が引き続き Spec の ### Improvement Proposals を走査して Issue 起票する後方互換挙動を維持している (共有モジュールに切り出された場合も呼び出しは残る)" --> 既存 `/verify` Step 13 経路の後方互換 (単独 `/verify` 実行時に従来どおり proposal 起票) が維持される
- <!-- verify: rubric "/auto 内で Improvement Proposals を起票する経路と /verify 単独経路の両方が、同じロジック (共有モジュール) または同等の判定ルールで proposals を Issue 化している (起票判定の重複/相違を生まない)" --> `/auto` 経路と `/verify` 単独経路で起票ロジックが一貫している

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 修正コミット後の main で `Test / Run bats tests` workflow が success する
- M/L pr-route または XS/S patch-route の `/auto` を実行し、Auto Retrospective に Improvement Proposals が記録された場合に手動 `/verify` 再実行なしで `retro/verify` Issue が自動起票されることを実機確認

## Notes

- `/auto` Step 4a の共有モジュール呼び出しタイミングは **commit+push 完了後**（step 5 の直後）。Spec ファイルがローカルにある時点で読み取れるが、push 完了後に呼び出す方が整合性が高い。
- `/auto` Step 4a は M/L/patch route ではアノマリー発生時のみ実行される（XL は常時実行）。アノマリーなし path では呼び出し自体が発生しないため重複起票のリスクはない。
- XL route でアノマリーなし（`### Improvement Proposals` が "N/A"）の場合、共有モジュールは "No improvement proposals" を出力して return するため、冗長な動作はない。
- `/verify` Step 13 が先に実行された場合（通常の M/L pr-route）、共有モジュール内の open Issues 重複チェックが、`/verify` Step 13 で既に起票されたものをスキップするため、二重起票は発生しない。
- `docs/structure.md` の modules/ファイル数: 追加前 32 files（`ls modules/ | wc -l` で確認）→ 追加後 33 files

## Code Retrospective

### Deviations from Design
- N/A — 実装は Spec の実装ステップどおりに進行し、設計からの逸脱なし。

### Design Gaps/Ambiguities
- `modules/retro-proposals.md` の Processing Steps 中に domain-loader の呼び出し（`SKILL_NAME=verify`）を追加したが、Spec の Input 欄には domain file content の受け渡しが明記されていなかった。モジュールが self-contained である（/auto から呼び出した際も domain-loader が使えること）ように、モジュール内部で `domain-loader.md` を読み込む設計とした。

### Rework
- N/A — 一発で実装が確定。

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

`skills/verify/SKILL.md` の Step 13 冒頭に残る `title-normalizer.md` 読み込みと、`modules/retro-proposals.md` の Step 1 での再読み込みが二重になっている（CONSIDER 指摘）。モジュールを self-contained 設計に変更したことが Spec の実装ステップ 2 の記述（「title-normalizer 読込みは Step 13 冒頭に残す」）と矛盾している。Spec 更新か実装調整のいずれかで整合を取る改善余地がある。

### Recurring Issues

なし。

### Acceptance Criteria Verification Difficulty

Pre-merge 条件3件はすべて `rubric` タイプで、diffから機械的に判定可能だった（UNCERTAIN 0件）。`rubric` タイプは verify-executor による自動判定が難しいが、今回はdiffが明確でAI判定が安定していた。Post-merge の実機確認条件1件は `opportunistic` タイプとして適切に設定されており、verify commandの精度は良好。
