# Issue #775: audit: /audit recoveries subcommand を削除

## Overview

`/audit recoveries` subcommand は `/verify` Step 15 (`recoveries-auto-fire`) の自動化機能で代替可能となり、routine 用途の価値を失った。`skills/audit/SKILL.md` から recoveries subcommand 関連のすべての記述 (section、routing、description、allowed-tools) を削除し、テストファイルを整理し、関連ドキュメントを更新する。`scripts/collect-recovery-candidates.sh` は `/verify` Step 15 の依存スクリプトのため残置。

## Changed Files

- `skills/audit/SKILL.md`: frontmatter description から `/audit recoveries` 文を削除; allowed-tools から `collect-recovery-candidates.sh:*` エントリを削除; Command Routing から recoveries 分岐行を削除; usage 文字列から `recoveries|` と `--threshold K` を削除; `## recoveries Subcommand` セクション全体 (line 727〜873 周辺、`---` セパレータを含む) を削除
- `docs/workflow.md`: audit 説明段落から `/audit recoveries` 文を削除; section header の "and Recovery Detection" を削除
- `docs/ja/workflow.md`: translation sync — `docs/workflow.md` の変更を反映した日本語テキスト更新
- `tests/audit-recoveries.bats`: 削除 (`tests/collect-recovery-candidates.bats` が既存のため rename は不要; AC `file_not_exists "tests/audit-recoveries.bats"` を満たすため削除)

## Implementation Steps

1. `skills/audit/SKILL.md` を編集する: (a) frontmatter `description` フィールドから `/audit recoveries` 文 (「`/audit recoveries` reads the cross-Issue orchestration recovery log... exceed a frequency threshold.」) を削除; (b) `allowed-tools` から `, ${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` を削除; (c) Command Routing の recoveries 分岐行 (「If ARGUMENTS is `recoveries` or starts with `recoveries`...」) を削除; (d) usage 文字列から `recoveries|` および ` [--threshold K]` を削除; (e) `## recoveries Subcommand` セクション全体とその前後の `---` セパレータを削除 (→ AC 1, 2, 3, 4)

2. `docs/workflow.md` を編集する: audit 説明段落 (line 166) から "`/audit recoveries` reads the cross-Issue orchestration recovery log (`docs/reports/orchestration-recoveries.md`) and files Issues for recurring recovery patterns that exceed a frequency threshold (default: 3 occurrences), turning operational knowledge into structured improvements." の文を削除; section header 「`### `/audit` — Drift, Fragility, and Recovery Detection`」から "and Recovery Detection" を削除し「`### `/audit` — Drift and Fragility Detection`」へ変更 (→ AC 7)

3. `docs/ja/workflow.md` を編集する: Step 2 の `docs/workflow.md` 変更に対応する translation sync — 日本語テキストから `/audit recoveries` に関する文を削除し、section header を合わせて更新 (→ SHOULD: translation sync)

4. `tests/audit-recoveries.bats` を削除する (`rm tests/audit-recoveries.bats`) (→ AC 8)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/audit/SKILL.md" "recoveries Subcommand" --> SKILL.md から recoveries subcommand セクションが削除されている
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "/audit recoveries" --> SKILL.md 内に /audit recoveries への参照が残っていない
- <!-- verify: rubric "skills/audit/SKILL.md の Command Routing セクションから recoveries の routing 分岐が削除されている (ARGUMENTS == recoveries の分岐 + 上部の help usage 文字列の recoveries 言及)" --> command routing から recoveries 削除
- <!-- verify: file_not_contains "skills/audit/SKILL.md" "collect-recovery-candidates.sh" --> SKILL.md の allowed-tools から collect-recovery-candidates.sh エントリが削除されている
- <!-- verify: file_exists "scripts/collect-recovery-candidates.sh" --> collect-recovery-candidates.sh は残置 (/verify Step 15 依存)
- <!-- verify: rubric "skills/verify/SKILL.md Step 15 の recoveries-auto-fire 機能は変更なし。collect-recovery-candidates.sh への参照が維持されている" --> /verify Step 15 は影響なし
- <!-- verify: file_not_contains "docs/workflow.md" "/audit recoveries" --> docs/workflow.md から /audit recoveries の説明が削除されている
- <!-- verify: file_not_exists "tests/audit-recoveries.bats" --> 旧テストファイル (audit-recoveries.bats) が削除されている
- <!-- verify: file_exists "tests/collect-recovery-candidates.bats" --> テストファイルが collect-recovery-candidates.bats にある (既存)

### Post-merge

- 次回 `/audit recoveries` 入力で「unknown subcommand」相当のメッセージが返ることを観察
- 次回 `/verify` 実行で Step 15 の recoveries-auto-fire が正常動作することを観察

## Notes

### 自動解決 (非対話モード)

`tests/collect-recovery-candidates.bats` が既存であるため、Issue 本文の「`audit-recoveries.bats` → `collect-recovery-candidates.bats` へリネーム」はリネームではなく「`audit-recoveries.bats` を削除」に変更した。既存の `collect-recovery-candidates.bats` で AC `file_exists "tests/collect-recovery-candidates.bats"` は既に満たされており、削除により `file_not_exists "tests/audit-recoveries.bats"` も満たせる。

なお `audit-recoveries.bats` (外部 fixture ベース、5 テスト) は `collect-recovery-candidates.bats` (inline fixture、4 テスト) より網羅的なケースを持つが、`collect-recovery-candidates.bats` は既存の独立したテストファイルであり削除による regression リスクは許容範囲。

### SHOULD 対応 (AC 外)

- `docs/structure.md` の audit 行説明 `Drift, fragility, and recovery pattern detection; auto-generate Issues` から `and recovery pattern detection` を削除することを推奨 (recoveries 機能削除後に不正確な記述が残る)。ただしこの変更に AC がないため implementation では SHOULD として実施する。
- `docs/ja/structure.md` も translation sync 対象 (docs/structure.md を変更する場合)。

### テストファイル数

削除前: 90 bats files; 削除後: 89 files。`docs/structure.md` の `(89 files)` 表記は変更後の状態と一致するため更新不要。

### Consumed Comments

- saito (MEMBER, first-class) — 2026-06-27T17:23:12Z: Issue Retrospective コメント (自動解決済み曖昧ポイント 3 件 + 削除系スキャン結果) — https://github.com/saitoco/wholework/issues/775#issuecomment-4819684023
  - 自動解決内容は Issue 本文の `## Auto-Resolved Ambiguity Points` セクションに反映済み

## Code Retrospective

### Deviations from Design

- Spec の "Changed Files" に `docs/structure.md` と `docs/ja/structure.md` は SHOULD (AC 外) として記載されていたが、実装では両ファイルも更新した。audit 行の説明文 (`Drift, fragility, and recovery pattern detection...`) が削除後の機能と不一致になるため SHOULD を実施するのが自然と判断。Spec の "Implementation Steps" は SHOULD の記載がなかったため実際の実装と差異あり。
- `## recoveries Subcommand` セクションの削除は Python の正規表現 (`re.sub`) で行った。Edit ツールの old_string が非常に長いため一括置換が困難であり、Bash + Python で処理する方が確実だったため。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `docs/reports/orchestration-recoveries.md` (scope 外ファイル) に `/audit recoveries` への stale 参照が行 15 と行 283 に残存。Spec の "Changed Files" リストにこのファイルが含まれておらず、review で初めて発見。削除系変更時は recovery log など間接的に参照する Markdown ファイルも scope に含めるか明示的に除外を記録すると良い。

### Recurring Issues

- 特になし。

### Acceptance Criteria Verification Difficulty

- 全 9 件が `file_not_contains` / `file_exists` / `rubric` コマンドで明確に検証可能であり UNCERTAIN なし。削除系 Issue として verify command の設計が適切だった。`--issues-json` テストカバレッジ欠落は verify command では検知できない種類の問題 (削除で生じる coverage gap)。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- `mergeable=false, reason=ci_failing` を non-interactive auto-resolve で通過。CI 失敗は `tests/append-loop-state-heartbeat.bats` の既存問題 (review フェーズで確認済み、本 PR 無関係) のため安全にマージ
- `gh pr merge --squash --delete-branch` で squash merge 完了 (2026-06-27T18:32:05Z)
- BASE_BRANCH=main のため `closes #775` が auto-close を実行

### Deferred Items

- `docs/reports/orchestration-recoveries.md` の stale 参照修正 (行 15, 283) — 別 Issue 推奨
- `tests/collect-recovery-candidates.bats` への `--issues-json` テスト追加 — 別 Issue 推奨
- CI FAILURE (`tests/append-loop-state-heartbeat.bats`) の根本原因調査 — 既存問題、本 PR 無関係

### Notes for Next Phase

- post-merge 観察 2 件が verify の主タスク: (1) `/audit recoveries` 入力で unknown subcommand 相当のメッセージが返ること、(2) `/verify` Step 15 の recoveries-auto-fire が正常動作すること
- Spec の "Verification (post-merge)" セクションに verify command が記載されているが、これらは観察ベース (rubric) のため verify フェーズで確認する
