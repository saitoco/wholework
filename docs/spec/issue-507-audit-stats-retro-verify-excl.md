# Issue #507: audit/stats: Outcome 計算から retro/verify ラベル付き Issue を除外する

## Overview

`/audit stats` の Section 5 (Outcome) で First-try 成功率・Completed 率・Rework 数・Phase 後戻りポイントを集計する際、`retro/verify` ラベル付き Issue を母集団から除外する。現状は除外が行われていないため、実装失敗ではない upstream 移管 close Issue が「失敗」扱いとなり、Highlights 自動検出が偽陽性を起こす。Section 4 (Work Origin) の集計には影響させない（既に独立カテゴリ扱い）。

## Reproduction Steps

1. `retro/verify` ラベル付きで `not planned` close された Issue が複数存在するリポジトリで `/audit stats` を実行する
2. Section 5 Outcome の特定 Content segment の First-try 失敗率が実態より大幅に高い値になる
3. Highlights に 2x 超の偽陽性検出が現れる

## Root Cause

Step 2 Computation の Outcome 計算母集団が `filtered_issues` 全体であり、`retro/verify` ラベル付き Issue（実装失敗ではなく wholework インフラ改善提案）が除外されていない。Section 4 (Work Origin) は既に `retro/verify` を独立カテゴリとして扱っているが、Outcome との整合性が取れていない。

## Changed Files

- `skills/audit/SKILL.md`: Step 2 Computation に Outcome Exclusion Filter サブセクションを追加。Section 5: Outcome の説明を更新し、除外母集団を明示・集計対象件数の注記表示を追加

## Implementation Steps

1. `skills/audit/SKILL.md` の Step 2 Computation 内 `#### Work Origin Classification` セクションの直後に `#### Outcome Exclusion Filter` サブセクションを追加する (→ acceptance criteria AC3)
   - 内容: `retro_verify_count`（filtered_issues 内の retro/verify ラベル付き件数）と `outcome_population`（filtered_issues から retro/verify ラベル付き Issue を除外した集合）を定義
   - 明記: Section 4 (Work Origin) の集計には retro/verify ラベルによる除外を適用しない。Section 4 は全 `filtered_issues` を母集団として使用する

2. `skills/audit/SKILL.md` の Step 3 Report Generation 内 `#### Section 5: Outcome` を更新する (→ acceptance criteria AC1, AC2)
   - `outcome_population` を使用して全 Outcome サブ項目（By Size、Phase 後戻りポイント、By Content segment、Trend）を集計することを明示
   - セクション先頭に "Outcome 集計対象: N 件 (うち retro/verify ラベル付き M 件を除外)" の注記表示を追加（N = count(outcome_population)、M = retro_verify_count）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/audit/SKILL.md" "Section 5" "retro/verify" --> `skills/audit/SKILL.md` の Section 5 (Outcome) で `retro/verify` ラベルによる除外仕様が明示されている
- <!-- verify: section_contains "skills/audit/SKILL.md" "Outcome" "除外" --> Outcome セクションの説明に除外母集団の明示がある
- <!-- verify: rubric "skills/audit/SKILL.md の stats Subcommand 内に Section 4 (Work Origin) の集計には retro/verify ラベルによる除外を適用しないことが明記されている" --> Section 4 (Work Origin) の集計には除外を適用しない旨が SKILL.md に記載されている

### Post-merge

- saito/trading リポジトリで `/audit stats --since 2026-05-01` を実行し、backend segment の First-try 成功率が #279, #280 を除外した値に変化することを確認 <!-- verify-type: manual -->
- Outcome レポートに「対象 N 件 / 除外 M 件」表示が含まれることを確認 <!-- verify-type: manual -->
- 既存の trading レポート (`docs/stats/2026-05-26.md`) で Highlights "backend 75% failure rate" が再計算後に消える/変わることを確認 <!-- verify-type: manual -->

## Notes

- 変更対象は `skills/audit/SKILL.md` のみ（SKILL.md は仕様記述ファイルであり、テキスト追記のみで対応可能）
- bats テストファイル `tests/audit-stats.bats` は存在しないため、テスト追加は不要
- Section 5 の"Outcome 集計対象"注記は retro_verify_count が 0 の場合も常に表示する（除外処理が機能していることを明示するため）
- Highlights 自動検出の 2x failure rate criterion は Section 5 の Outcome データを参照するため、Outcome Exclusion Filter 適用後のデータが自動的に使用される（Highlights セクション自体の変更は不要）
- Section 4 (Work Origin) は `retro/verify` を独立カテゴリ "retrospective" として集計しており、除外適用外とすることで整合性が保たれる

## Code Retrospective

### Deviations from Design
- 1件目コミットで `feat:` プレフィックスを使用したが、Issue Type が Bug であるため `fix:` が正しかった。commit message は既に push 済みのため修正せず。

### Design Gaps/Ambiguities
- Spec の Phase Handoff Notes では AC2 `section_contains "Outcome" "除外"` が `#### Section 5: Outcome` にマッチすると想定していたが、実装で追加した `#### Outcome Exclusion Filter` が document order で先に出現し先にマッチした。`section_contains` は heading の部分一致で最初のマッチを使用するため、英語のみで書いた `#### Outcome Exclusion Filter` の内容に "除外" が含まれず AC2 が FAIL した。対処: `#### Outcome Exclusion Filter` の先頭に日本語説明行を追加して "除外" を含めることで PASS にした。

### Rework
- AC2 FAIL 検出後に `#### Outcome Exclusion Filter` 先頭に日本語説明行を追加する修正コミットが1件発生した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `#### Outcome Exclusion Filter` を Step 2 Computation に追加し、`retro_verify_count` と `outcome_population` を定義した
- `#### Outcome Exclusion Filter` 先頭に日本語説明行を追加することで AC2 `section_contains "Outcome" "除外"` を充足させた（`section_contains` は最初にマッチする heading を使用するため、新規追加 heading も対象になる）
- Section 4 (Work Origin) の除外非適用はサブセクション内の Note 行で明記した（AC3 rubric 充足）

### Deferred Items
- テストカバレッジなし（`tests/audit-stats.bats` 未存在）
- saito/trading での実機確認（Post-merge AC 3件 `verify-type: manual`）は post-merge 残存

### Notes for Next Phase
- Pre-merge AC 3件はすべて PASS 確認済み（Issue チェックボックス更新済み）
- 変更は `skills/audit/SKILL.md` の 2箇所のみ: `#### Outcome Exclusion Filter` 新設と `#### Section 5: Outcome` 更新
- Post-merge AC はいずれも saito/trading での実行確認が必要な manual AC

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec | patch | SUCCESS | |
| code | patch | SUCCESS (orchestration anomaly) | run-code.sh exit 1 で wrapper failure → reconcile が code-pr 期待で false mismatch、しかし実装は patch route として完了し main に push 済み（commit 69a99d7, 1329f61, 5a66708）|
| verify | -    | PARTIAL | Pre-merge 3 件 PASS、Post-merge 3 件 manual SKIPPED |

### Orchestration Anomalies
- `run-code.sh` が exit 1 で終了したが、reconcile-phase-state は `code-pr` phase を期待して `no open PR found` を返した。実態は patch route（S サイズ）で直接 main commit + push 完了済み。route mismatch（reconcile が code-patch でなく code-pr をチェックした）が原因。
- Tier 3 recovery (`spawn-recovery action=retry`) が一度発動し、stale worktree クリーンアップ後に再実行された。再実行は実際には成功（直接コミット）したが、reconcile は依然 code-pr 期待だったため exit 1 のまま返ってきた。
- 親セッションで実状態を Tier 1 (Observe) として確認: Issue は CLOSED + `phase/verify`、commit 3 件あり、`closes #507` で自動クローズ済み → patch route として完了している。手動で `/verify` を起動した。

### Improvement Proposals
- `reconcile-phase-state.sh` の `code-pr` / `code-patch` phase 選択が wrapper 内で正しく行われていない可能性。size auto-detect で patch route と判定された後の reconcile call で phase を `code-patch` に切り替える必要がある（route 判定後に reconcile phase を更新する分岐の追加）。
- Tier 3 recovery の `action=retry` が現状はオリジナル wrapper を同じ引数で再呼び出すが、wrapper 内部の reconcile mismatch (route 判定誤り) は再試行では解消しないため、別パターン（recovery 経由で reconcile phase を明示）として catalog 化が必要。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC1 の verify command を `section_contains "stats Subcommand" "retro/verify"` から `section_contains "Section 5" "retro/verify"` に修正したのは Refinement で実装変更を正確に検出するうえで有効だった（既存記述による偽陽性回避）。

#### spec
- pre-merge AC 3 件すべてに verify command が割り当てられており、すべて Section 抽出系（`section_contains`）または意味判定系（`rubric`）で実装変更を正確に検出する設計。Code Retrospective に AC2 FAIL → 日本語説明行追加で PASS の rework が記録されており、verify-design 結合の弱点（heading 抽出と「除外」キーワードの直接配置の必要性）が学びになっている。

#### code
- 1 件の rework（`#### Outcome Exclusion Filter` 先頭に日本語説明行追加で AC2 を充足）が発生。verify command の `section_contains` 仕様（最初にマッチする heading section が対象）を考慮した設計が必要だった。

#### review
- なし (patch route)。

#### merge
- patch route のため main 直 push。run-auto-sub.sh wrapper が exit 1 で帰ってきたが実態は完了。

#### verify
- Pre-merge 3 件全 PASS。Post-merge 3 件は saito/trading 実行が必要で Claude 不可、guide のみ → `phase/verify` 留め。

### Improvement Proposals
- Auto Retrospective の Improvement Proposals 参照（reconcile-phase-state の route mismatch、Tier 3 retry の効果範囲）。
