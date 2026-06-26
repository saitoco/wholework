# Issue #752: workflow.md: Add auto-session --full / --no-ja to /audit docs

## Overview

`docs/workflow.md` の `/audit` セクション (line 164) に、以下の 2 点が未記載:

1. `auto-session --full <session-id>` の複合利用形 (現在は `--full` のみ言及)
2. `--no-ja` オプション (日本語 sibling ファイルのスキップ)

`skills/audit/SKILL.md` の現行実装と一致させ、ユーザが workflow.md だけで利用可能なオプションを把握できるようにする。`docs/ja/workflow.md` (日本語ミラー) も同様に更新する。

## Changed Files

- `docs/workflow.md`: `/audit auto-session` 記述を変更 — `\`--full\`` → `\`/audit auto-session --full <session-id>\`` に変更、`(existing issue / new / icebox)` 直後に `; \`--no-ja\` to skip Japanese sibling generation` を追加 (bash 3.2+ compat N/A — documentation only)
- `docs/ja/workflow.md`: 対応する日本語ミラー箇所を同様に変更 — `\`--full\` を指定すると` → `\`/audit auto-session --full <session-id>\` を指定すると`、末尾の `human gate を維持）。` 直後に `\`--no-ja\` を付与すると日本語 sibling ファイルの生成をスキップします。` を追加 (bash 3.2+ compat N/A — documentation only)

## Implementation Steps

1. `docs/workflow.md` line 164 の auto-session 記述を以下のように編集する (→ AC1, AC2, AC3):
   - 変更前: `; \`--full\` for LLM-assisted draft of all 4 sections`
   - 変更後: `; \`/audit auto-session --full <session-id>\` for LLM-assisted draft of all 4 sections`
   - さらに `(existing issue / new / icebox)` の直後、`. Period aggregate mode` の前に `; \`--no-ja\` to skip Japanese sibling generation` を挿入する

2. `docs/ja/workflow.md` line 157 の auto-session 記述を以下のように編集する (→ AC4, AC5):
   - 変更前: `\`--full\` を指定すると全 4 セクション`
   - 変更後: `\`/audit auto-session --full <session-id>\` を指定すると全 4 セクション`
   - さらに `（Issue 自動起票は行わず human gate を維持）。` の直後に `\`--no-ja\` を付与すると日本語 sibling ファイルの生成をスキップします。` を追加し、その後に既存の `期間集約モード` の文を続ける

## Verification

### Pre-merge

- <!-- verify: grep "auto-session --full" "docs/workflow.md" --> workflow.md に `auto-session --full` の利用形が記載されている
- <!-- verify: grep "no-ja" "docs/workflow.md" --> `--no-ja` オプションが workflow.md に言及されている
- <!-- verify: rubric "workflow.md の /audit セクションが skills/audit/SKILL.md の現行オプションを網羅している (--full, --no-ja, --since などの追加)" --> 網羅性を満たす
- <!-- verify: grep "auto-session --full" "docs/ja/workflow.md" --> 日本語ミラー (docs/ja/workflow.md) に `auto-session --full` が記載されている
- <!-- verify: grep "no-ja" "docs/ja/workflow.md" --> 日本語ミラーに `--no-ja` オプションが記載されている

### Post-merge

なし

## Consumed Comments

- `saito` / MEMBER / first-class / Issue Retrospective (Auto-Resolve Log: BRE メタキャラ修正、AC4 実装前 PASS 問題、Background スコープ注記追加) / https://github.com/saitoco/wholework/issues/752#issuecomment-4806503789
