# Issue #721: spec: allowed-tools impact chain check を追加し新規 run-*.sh の SKILL.md エントリ漏れを Spec 段階で検出

## Overview

`/spec` の Step 10 (Create Spec) に `#### allowed-tools impact chain check` サブ節を追加する。Spec の "Changed Files" に新規 `scripts/*.sh` が含まれる場合、関連 SKILL.md の `allowed-tools` に明示エントリが存在するかを Spec 段階で検出し、欠落があれば Notes セクションに記述する。

背景: Issue #700 の verify retrospective で、PR #717 にて `run-code.sh` を新規追加した際、`skills/verify/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*` の明示エントリが必要だったにもかかわらず、Spec の Notes で「`*.sh` ワイルドカードでカバー済み」と誤判定し `/code` フェーズで rework 1 commit が発生した。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の "Shell script bash compat note" サブ節の直後に `#### allowed-tools impact chain check` サブ節を追加 — bash 3.2+ compatible

## Implementation Steps

1. `skills/spec/SKILL.md` Step 10 の `**Shell script bash compat note:**` ブロック (line ~497-499) の直後に `#### allowed-tools impact chain check` サブ節を挿入する (→ AC1, AC2, AC3)

   挿入する内容:

   ```
   #### allowed-tools impact chain check

   When Changed Files includes new `scripts/*.sh` files (especially `run-*.sh` patterns — scripts called directly by Skills during execution), perform an allowed-tools impact chain check:

   1. Extract new `scripts/*.sh` filenames from the Spec's "Changed Files" section
   2. For each new script, grep `skills/*/SKILL.md` frontmatter `allowed-tools` for the literal entry `${CLAUDE_PLUGIN_ROOT}/scripts/<script-name>:*`
   3. If a SKILL.md calls the new script but lacks the explicit entry, record the gap in the Spec's Notes section: "`skills/<skill>/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/<new-script>:*` の追加が必要"
   4. Wildcard claims (`*.sh`) are not acceptable — use literal match against the actual `allowed-tools` value; a wildcard covering `scripts/*.sh` is not present in any existing SKILL.md allowed-tools pattern

   **Skip** if no new `scripts/*.sh` files are being added.
   ```

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" --> `skills/spec/SKILL.md` Step 10 に `allowed-tools impact chain check` 節が追加されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "run-*.sh" --> impact chain check 節に `run-*.sh` パターン解析が記述されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "literal" --> ワイルドカード許容しない literal match 要件が明示されている
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) bats 全件 green (patch route)

### Post-merge

- 次回新規 `run-*.sh` 追加 Spec で `allowed-tools impact chain check` が機能し、code phase rework がゼロになることを確認 <!-- verify-type: manual -->

## Notes

**自動解決済み曖昧ポイント (Issue Retrospective より引き継ぎ):**

- **追加場所を Step 10 のサブ節とする**: Issue 本文の「Step 10 に追加」を「Step 10 の中にサブ節 (`#### allowed-tools impact chain check`) として追加」と解釈。verify commands は配置に依存しないため影響なし。既存 SKILL.md Step 10 に `####` heading は存在しないため、本 Issue が初導入となる。
- **Post-merge verify-type は `manual`**: `observation event=spec` は `verify-classifier.md` に定義された valid event name ではないため (定義済み: `pr-review-full`, `pr-review-light`, `auto-run`, `watchdog-kill`, `fix-cycle`)、「次回新規 `run-*.sh` 追加 Spec 実行時の手動観察」という意図に対して `manual` が意味的に正確。

**`section_contains` 動作確認:**

`section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "run-*.sh"` は partial match ルールで `#### allowed-tools impact chain check` heading を検出する (heading 行から `#` と空白を除去した文字列 "allowed-tools impact chain check" が完全一致)。挿入するテキストに `run-*.sh` および `literal` が含まれることを確認済み。

**ドキュメント更新不要**: `skills/spec/SKILL.md` の内部ロジック追加であり、スキルの追加/削除/名称変更ではないため、README.md / docs/workflow.md / CLAUDE.md の更新は不要。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: verify-type: manual への変更と Step 10 サブ節配置の auto-resolve 記録 / https://github.com/saitoco/wholework/issues/721#issuecomment-4759114220
