# Issue #615: auto: --batch List モードで Issue 間 verify を親セッションがオーケストレート

## Overview

`/auto --batch N1 N2 ...` の List mode で、`run-auto-sub.sh` 成功後に verify が呼ばれない問題を修正する。`run-auto-sub.sh` は spec→code→review→merge までを実行し verify は親セッションに委譲する設計（`# verify is deferred to the parent /auto session` コメントあり）だが、List mode の SKILL.md には親セッションから verify を呼ぶステップがなかった。

修正方針:
- `skills/auto/SKILL.md` の List mode ループに verify オーケストレーションステップ（step 5）を追加
- `run-auto-sub.sh` 成功後にラベルを再フェッチし、`phase/verify` が付与されていれば `Skill(skill="wholework:verify")` を呼ぶ
- `--non-interactive` 検出時は SKIP して `phase/verify` 残しで継続（AskUserQuestion 不可のため）
- `tests/auto-batch.bats` を新規作成し List mode の verify オーケストレーション動作をテスト

## Changed Files

- `skills/auto/SKILL.md`: List mode の step 4 「On success」を「step 5 へ進む」に変更し、step 5（verify オーケストレーション）を追加 — bash 非該当（LLM 実行 Markdown）
- `tests/auto-batch.bats`: 新規ファイル — List mode verify オーケストレーションの構造的テスト — bash 3.2+ compatible
- `docs/workflow.md`: `--batch N1 N2 ...` 説明に verify オーケストレーション動作を追記（SHOULD）
- `docs/ja/workflow.md`: `docs/workflow.md` の変更を日本語翻訳に同期（SHOULD）

## Implementation Steps

1. `skills/auto/SKILL.md` を修正: List mode の `### List mode (--batch N1 N2 ...)` セクション内 step 4 「On success」ブランチを以下の通り変更 (→ 受入条件1):
   - 変更前: `On success: call ${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch $NUMBER complete`
   - 変更後: `On success: proceed to step 5`
   - step 5 を追加: **Verify orchestration** (after run-auto-sub.sh success):
     - Re-fetch current labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
     - If `phase/verify` is present in labels:
       - If `--non-interactive` is NOT in ARGUMENTS: invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session
         - On success: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch $NUMBER complete`
         - On failure or output contains `MAX_ITERATIONS_REACHED`: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch $NUMBER fail`; skip to the next Issue
       - If `--non-interactive` IS in ARGUMENTS: output "Skipping verify for #$NUMBER (non-interactive mode); phase/verify remains"; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch $NUMBER complete`
     - If `phase/verify` is NOT in labels: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch $NUMBER complete`

2. `tests/auto-batch.bats` を新規作成 (→ 受入条件2, 3): 以下の3テストを含む構造的テスト:
   - `@test "List mode section: wholework:verify Skill invocation present"` — List mode セクションに `wholework:verify` が含まれることを確認
   - `@test "List mode section: phase/verify label check present"` — List mode セクションに `phase/verify` が含まれることを確認
   - `@test "List mode section: non-interactive skip behavior present"` — List mode セクションに `non-interactive` が含まれることを確認
   - awk パターン: `'/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}'` で List mode セクションを抽出

3. `docs/workflow.md` の `--batch N1 N2 ...` 説明を更新 (SHOULD): 「each Issue's verify runs in the parent session after run-auto-sub.sh succeeds」を追記、`--non-interactive` 時はスキップする旨を明記

4. `docs/ja/workflow.md` を `docs/workflow.md` の変更に合わせて同期 (SHOULD)

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/auto/SKILL.md" "### List mode" "wholework:verify" --> `skills/auto/SKILL.md` の List mode セクションに `Skill(skill="wholework:verify"` の呼び出しが追加されている
- <!-- verify: file_exists "tests/auto-batch.bats" --> `tests/auto-batch.bats` が存在する
- <!-- verify: command "bats tests/auto-batch.bats" --> `tests/auto-batch.bats` の全テストが green

### Post-merge

- 次回 `/auto --batch` 実行時、AC 検証可能な Issue が `phase/done` に到達することを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- `run-auto-sub.sh` line 3 and 125 に `# verify is deferred to the parent /auto session (issue #485)` コメントがあり、本実装はその設計意図を List mode で実現するもの
- Resume mode (`### Resume mode (--batch --resume)`) は「同じ steps as List mode に従う」と記述されているため、step 5 追加により Resume mode も自動的に verify オーケストレーションを継承する（変更不要）
- step 5 の verify 成功/失敗に応じて `update_batch complete`/`update_batch fail` を分岐させることで、batch completion report にも verify 結果が反映される
- Non-interactive mode 検出: ARGUMENTS に `--non-interactive` が含まれる場合（`claude -p` 経由で `/auto` が呼ばれる場合）は verify をスキップ。`update_batch complete` は呼ぶ（run-auto-sub.sh 自体は成功しているため）
- `tests/auto-batch.bats` は LLM 実行スキル（SKILL.md）のテストであるため、shell スクリプトの動作を直接テストするのではなく、SKILL.md の構造的な内容（文字列の存在）を検証する方式を採用
- 自動解決 (Non-interactive mode): Issue body の「実装アプローチ」「テストファイル」「非対話モード条件」は全て auto-resolve 済み（Issue body の `## Auto-Resolved Ambiguity Points` 参照）
