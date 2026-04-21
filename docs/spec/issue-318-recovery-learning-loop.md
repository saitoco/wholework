# Issue #318: auto/audit: recovery 事例を learning loop で永続化

## Overview

`/auto` の orchestration 改善サイクルで発見された recovery 事例・fallback パターン・診断結果を
横断的に永続化する learning loop を構築する。具体的には:

1. **永続化先**: `docs/reports/orchestration-recoveries.md` — append-only の cross-Issue 横断ログ
2. **書き込み機構**: `/auto` Step 4a での 3 source からの一括 append
3. **参照機構**: `/audit recoveries` 新 perspective — 未起票の既知問題を頻度ベースで検出・起票

Spec retrospective (per-Issue, disposable) との役割分担:
- **Spec retrospective**: per-Issue 実行記録、phase 単位の異常と改善提案、廃棄前提
- **orchestration-recoveries.md**: cross-Issue 横断ログ、永続、symptom → recovery → outcome の再発検出用

## Changed Files

- `docs/reports/orchestration-recoveries.md`: new file — cross-Issue recovery log; structured append-only format (Context / Diagnosis / Recovery Applied / Outcome / Improvement Candidate); newest entry first
- `scripts/collect-recovery-candidates.sh`: new script — parse orchestration-recoveries.md; count symptom-short frequency; exclude 起票済み entries; apply --threshold K filter; output candidate list — bash 3.2+ compatible
- `skills/auto/SKILL.md`: Step 4a に orchestration-recoveries.md への append 機構を追加 (3 source; Source 2 は #316 ship 後に有効); 既存 Spec retrospective の git add/commit/push と同一フロー
- `skills/audit/SKILL.md`: `recoveries` subcommand を追加 (Command Routing + subcommand section Steps 1-5); description frontmatter に recoveries perspective を追記; allowed-tools に `collect-recovery-candidates.sh` を追加
- `tests/audit-recoveries.bats`: new file — collect-recovery-candidates.sh の bats テスト (4 test cases)
- `docs/workflow.md`: `/audit` 節の見出し・説明に `recoveries` perspective を追記
- `docs/structure.md`: audit 行の Role 説明更新; scripts count 42→43; `collect-recovery-candidates.sh` を Project utilities 節に追加
- `docs/ja/workflow.md`: `docs/workflow.md` の翻訳同期
- `docs/ja/structure.md`: `docs/structure.md` の翻訳同期

## Implementation Steps

1. `docs/reports/orchestration-recoveries.md` を新規作成: ファイル冒頭に format 説明ヘッダー (フィールド定義・責務分担・役割分担 with Spec retrospective) を記載; ログエントリ部は空 (初期状態) (→ 受入条件 A)

2. `scripts/collect-recovery-candidates.sh` を新規作成: orchestration-recoveries.md を読み込み symptom-short 行 (`## YYYY-MM-DD ...`) と Improvement Candidate 行を parse; `起票済み #NNN` を含むエントリを除外; 同一 symptom-short の出現回数を集計; `--threshold K` (default 3) 以上のものをタブ区切り `<symptom-short>\t<count>` で stdout 出力; `--issues-json PATH` で既存 open issues JSON を受け取り symptom-short が issue title に含まれる場合は duplicate としてスキップ; bash 3.2+ 互換 (mapfile 不使用; while IFS= read -r 使用) (→ bats テストの前提)

3. `tests/audit-recoveries.bats` を新規作成: fixtures/orchestration-recoveries-sample.md を設置; 4 test cases: (a) parse — fixture からエントリを抽出し count が正しい, (b) threshold — K=3 で head 件数が 2 件絞り込まれる, (c) exclusion — `起票済み #NNN` 付きエントリが候補から除外される, (d) issues-json — fixture JSON 内の symptom-short が重複として除外される (→ 受入条件 E・F)

4. `skills/auto/SKILL.md` Step 4a を修正: 既存の Spec retrospective commit 前に「recovery event append」サブステップを追加; 3 source (fallback catalog 適用時・anomaly detector 検出時・#316 recovery sub-agent 成功時 — source 2 は `#316 ship 後に有効` と明記) それぞれについて recovery event entry (Issue の format 仕様準拠) を Write/Edit で `docs/reports/orchestration-recoveries.md` の先頭に prepend; `git add docs/reports/orchestration-recoveries.md` を既存 Spec retrospective の `git add` と同一コマンドに統合 (→ 受入条件 B)

5. `skills/audit/SKILL.md` 修正: Command Routing に `recoveries` routing を追加; `recoveries` subcommand section を新設 (Steps 1-5: Context collection / Candidate detection — `collect-recovery-candidates.sh` 呼び出し / Duplicate check — LLM semantic match / Results output / Issue generation + log entry 更新 `起票済み #NNN`); description frontmatter を更新; allowed-tools に `${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` を追加。`docs/workflow.md` `/audit` 節の見出しと説明を更新 (`recoveries` 追記)。`docs/structure.md` Key Files audit 行と scripts 節 (count 42→43) を更新。`docs/ja/workflow.md`・`docs/ja/structure.md` を翻訳同期 (→ 受入条件 C・D)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/orchestration-recoveries.md is documented as the cross-Issue recovery log with a structured append-only format (Context / Diagnosis / Recovery Applied / Outcome / Improvement Candidate), and its relationship to per-Issue Spec retrospectives is clarified (disposable vs. persistent, per-Issue vs. cross-Issue)." --> 永続化フォーマットと Spec retrospective との責務分離が記載されている
- <!-- verify: rubric "skills/auto/SKILL.md Step 4a (Auto Retrospective) appends recovery events from the three sources (orchestration-fallbacks catalog application, orchestration-recovery sub-agent success, wrapper anomaly detector) to docs/reports/orchestration-recoveries.md in the same commit/push flow as the Spec retrospective. The sub-agent source is noted as dependent on #316 shipping." --> `/auto` Step 4a での 3 source からの append 機構が実装されている
- <!-- verify: rubric "skills/audit/SKILL.md defines a 'recoveries' subcommand with Steps 1-5 mirroring the existing drift/fragility subcommand structure (Context collection / Candidate detection with frequency threshold K=3 default / Duplicate check / Results output / Issue generation), and updates the log entry's Improvement Candidate field to '起票済み #NNN' after filing." --> `/audit recoveries` subcommand が追加されている
- <!-- verify: file_exists "skills/audit/SKILL.md" --> audit skill が存在する (recoveries perspective は同一ファイル内に追加想定)
- <!-- verify: file_exists "tests/audit-recoveries.bats" --> bats テストファイルが存在する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが CI で PASS する

### Post-merge

- 意図的に同一 symptom-short で K=3 回以上 recovery event を `orchestration-recoveries.md` に書き込み、`/audit recoveries` が該当を起票候補として提示することを確認
- `/audit recoveries` 起票後、対応するログエントリの `Improvement Candidate` が `起票済み #NNN` に更新され、次回実行時に候補から除外されることを確認
- 既存 `/audit drift` / `/audit fragility` と個別実行で併用して結果が干渉しないことを確認

## Notes

- **#316 soft dependency**: Source 2 (orchestration-recovery sub-agent) は #316 ship 前は無効。Source 1 (fallback catalog) と Source 3 (anomaly detector) の 2/3 source で learning loop は成立するため blocker 化しない。Step 4a の実装では `#316 ship 後に有効` と明記するだけでよい
- **`/audit` 統合実行への recoveries 含有見送り**: 既存 drift+fragility 統合挙動へのスコープ拡大を避けるため `recoveries` は明示指定のみ。成熟後に別 Issue で統合を検討
- **翻訳同期**: `docs/ja/workflow.md`・`docs/ja/structure.md` は機械翻訳ではなく日本語形式の変更のみ (recoveries 追記)。`/code` 実装者が日本語で直接編集する
- **verify 件数**: Issue 受入条件 6 件に対し Spec verification も 6 件 (light 上限 5 を 1 件超過。verbatim copy ルール優先)

## Code Retrospective

### Deviations from Design

- `skills/auto/SKILL.md` Step 4a の既存ステップ番号を維持するため、新規 recovery event append ロジックを「ステップ 4」として挿入し、従来の「commit and push」を「ステップ 5」に繰り下げた。Spec では「Spec retrospective の git add/commit/push と同一フロー」としか記載されておらず、ステップ番号付与は実装判断。
- `skills/auto/SKILL.md` の `allowed-tools` に `Edit` を追加（Spec 未記載）。validate-skill-syntax.py によって skill 本文中で Edit ツールを使用しているが frontmatter に含まれていないエラーが検出されたため追加。

### Design Gaps/Ambiguities

- `collect-recovery-candidates.sh` の重複チェック（`--issues-json`）は substring match（`grep -qF "$sym"`）を使用。Spec では「symptom-short が issue title に含まれる」と記載されており literal match として解釈した。semantic match はスクリプトではなく `/audit recoveries` Step 3 の LLM 判断層で行う設計との整合。
- Spec の bats テスト説明 "(b) threshold — K=3 で head 件数が 2 件絞り込まれる" の「2 件絞り込まれる」は「2 件が通過する」の意味と解釈し、fixture に `code-pr-extraction-fail`（3 回）を追加してテスト条件を満たした。

### Rework

- `tests/audit-recoveries.bats` のテスト名 (c) に日本語（`起票済み`）を含めたため bats の parse エラー（0 tests executed）が発生。SKILL.md の注意事項「bats test names must be in English」を見落とし。ASCII に修正後に再実行して PASS 確認。
