# Issue #1103: review: Workflow パスの可用性判定と headless 非互換の解消

## Overview

`capabilities.workflow: true` 環境で `/auto` の review フェーズが構造的に失敗する (headless 実行が Workflow ツールの完了通知を受け取れず silent no-op になる) 問題への対応。Issue Refinement 時点の調査で、根本原因への対応 (headless 実行文脈では Workflow パスに入らず静的 Task fan-out にフォールバックする設計) は個別対応としてではなく `modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" + `skills/review/workflow-guidance.md` の Pre-flight (36-51 行目) として既に一般化された形で実装済みであることが判明している。本 Spec の投資調査でもこれを独立に再確認した。残る作業は (1) 既存記述が Acceptance Criteria を満たすことの確認 (実装変更なし)、(2) 未カバーだった Pre-flight フォールバック分岐への構造的回帰テスト追加、(3) Issue 本文 AC の verify command 精度修正 (Triage AC audit 対応) の3点。

## Reproduction Steps

1. `.wholework.yml` に `capabilities.workflow: true` を設定する。
2. Size M/L の Issue (→ `--review=full`) に対して `/auto` を実行する (`run-review.sh` 経由の headless `claude -p` 起動)。
3. `/review` Step 10 が `skills/review/workflow-guidance.md` の Workflow パスに入り、Workflow ツールを起動する。
4. Workflow ツールはバックグラウンドタスクとして即座に返る。headless `claude -p` には完了通知による再呼び出しが存在しないため、ターンはそのまま終了し `exit 0` / 出力ゼロ (silent no-op) になる — PR にコメントも findings も届かない (実例: Issue #1069 / PR #1077、4 回連続失敗)。

## Root Cause

headless 実行サーフェス (`claude -p`、fork 実行された Skill、Workflow ツール自体の実行パス、`run_in_background: true`) には再呼び出し保証がなく、バックグラウンド完了通知を待ってターンを終了すると二度と再開しない。Workflow ツール自体に同期呼び出しモードは存在しない (Issue #1123 で確認済み)。#1069/#1077 発生当時、`workflow-guidance.md` の Pre-flight は `agentType` の可用性しかチェックしておらず、再呼び出し保証の有無を見ていなかったため、headless セッションが Workflow パスに入って停止していた。

この根本原因は、個別パッチではなく汎用メカニズムとして既に解消済み:

- `modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" — headless `claude -p` / fork 実行 / Workflow ツール自体の実行パス / `run_in_background: true` を再呼び出し保証のない実行サーフェスとして exhaustive に列挙し、MUST ルールを規定。`modules/execution-context.md:93` は本 Issue (#1103) 自体をこのルールの precedent として明示的に列挙している (`grep -n "1103" modules/execution-context.md` で確認済み)
- `skills/review/workflow-guidance.md` 36-51 行目 (`## Pre-flight: agentType Availability Check`) — 分岐条件が `capabilities.workflow` の有無ではなく「実行文脈の再呼び出し保証」になっており、保証が確認できない場合は Workflow パスへ入らず静的 Task fan-out (Steps 10.1–10.3) に `Agent(run_in_background: false)` でフォールバックする分岐が既に記載されている (投資調査で実測: `grep -c "re-invocation guarantee" <Pre-flight セクション>` → 3 件、`grep -c "do NOT launch the Workflow tool for this step" skills/review/workflow-guidance.md` → 1 件で一意)
- `scripts/guard-prefix.sh` — `run-issue.sh`/`run-spec.sh`/`run-code.sh`/`run-review.sh`/`run-merge.sh` の全 5 wrapper がこの MUST ルールを起動時に注入するバックストップとして機能

**有効性の前提**: この Root Cause 分析は、`workflow-guidance.md` 36-51 行目のフォールバック分岐が削除・弱体化された場合、または `modules/execution-context.md` の MUST ルールが撤回された場合に無効となる (Issue 本文が記録する同じ前提)。

## Changed Files

- `tests/workflow-guidance.bats`: Pre-flight の再呼び出し保証フォールバック分岐を対象とする新規 `@test` を 1 件追加 (既存 3 件は Inline Workflow Script の pipeline 構造 (#1010 再発防止) のみが対象で、Pre-flight 側は未カバーだった)
- `skills/review/workflow-guidance.md`: 変更不要 (no change needed) — 36-51 行目が AC1〜AC3 の主張を既に満たしていることを本 Spec 投資調査で確認済み (上記 Root Cause 参照)
- Issue #1103 本文: 本 `/spec` セッション内で Pre-merge AC を修正済み (`gh-issue-edit.sh` 経由。リポジトリファイルではないため本節の対象外だが記録のため明記。詳細は Notes 参照)

## Implementation Steps

1. `tests/workflow-guidance.bats` に `@test "workflow-guidance: Pre-flight falls back to static Task fan-out without re-invocation guarantee"` を追加する。テスト本体は既存 3 テストと同じ grep-guard 構造スタイルで `grep -q "do NOT launch the Workflow tool for this step" "$GUIDANCE_FILE"` を検証する (→ acceptance criteria: bats 構造回帰テスト)
2. (after 1) `bats tests/workflow-guidance.bats` をローカル実行し、既存 3 件 + 新規 1 件の計 4 件すべてが pass することを確認する (→ acceptance criteria: bats 構造回帰テスト)
3. `skills/review/workflow-guidance.md` および `modules/execution-context.md` への実装変更は行わない — 本 Spec の投資調査で AC1/AC2/AC3 の主張を既存記述が満たしていることを確認済み (Root Cause 参照) (→ acceptance criteria: AC1, AC2, AC3)

(Issue #1103 本文の Pre-merge AC 修正 (AC4 削除・AC5 の verify command 精度修正) は Spec 作成と同一セッション内で `gh-issue-edit.sh` により実施済み — 詳細は Notes 参照)

## Verification

### Pre-merge

- <!-- verify: rubric "headless (claude -p / run-*.sh 経由) の実行文脈では /review が Workflow パスに入らない、または Workflow の完了を同期的に待てる形になっている。通知が原理的に届かない理由が根拠として記述されている" --> headless 実行時に Workflow パスへ入らない (または同期待機する) 設計になっている
- <!-- verify: rubric "skills/review/workflow-guidance.md の Pre-flight (agentType Availability Check の見出し配下から Processing Steps 直前までを含む) に、Workflow ツールの再呼び出し保証 (re-invocation guarantee) が確認できない実行文脈では静的 Task fan-out へフォールバックする分岐が記載されている" --> Pre-flight に再呼び出し保証チェックとフォールバック分岐が記載されている
- <!-- verify: section_contains "skills/review/workflow-guidance.md" "## Pre-flight: agentType Availability Check" "re-invocation guarantee" --> Pre-flight セクションに re-invocation guarantee という語が含まれる (rubric の補助的機械チェック)
- <!-- verify: grep "Pre-flight falls back to static Task fan-out without re-invocation guarantee" "tests/workflow-guidance.bats" --> <!-- verify: command "bats tests/workflow-guidance.bats" --> Pre-flight の再呼び出し保証フォールバック分岐に対する構造的回帰テスト (`@test "workflow-guidance: Pre-flight falls back to static Task fan-out without re-invocation guarantee"`) が `tests/workflow-guidance.bats` に追加され、既存テストと合わせて pass する
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストスイートが CI で pass する

### Post-merge

- `capabilities.workflow: true` の状態で Size M/L の Issue に対し `/auto` を実行し、review フェーズが silent no-op にならず完走することを確認する

## Notes

- **AC4 削除 + AC5 verify command 精度修正 (Triage AC audit 対応)**: 元の Issue AC4 (`grep "Workflow" skills/review/workflow-guidance.md`) は検出力ゼロだった — "Workflow" はファイル全体 (見出し・散文) に頻出する汎用語で、未実装の状態でも常に一致する。AC3 の `section_contains ... "re-invocation guarantee"` が AC1/AC2 (rubric) に対する補助的機械チェックとして既に機能しており (`modules/verify-patterns.md` §9 の「rubric + 補助チェック 1 件」パターンに準拠)、AC4 は重複だった。Triage AC audit コメント (saito, MEMBER, first-class, 2026-08-18T13:28:52Z) がこれを指摘し、より具体的な文言への置き換えまたは削除を提案していた。削除を採用した — 理由: (a) AC3 が同じ主張を既にカバーしており独立した検出力を持たない、(b) 削除により Pre-merge AC 件数が 5 件になり、SPEC_DEPTH=light の Spec Simplicity Rule (5 件上限) に一致する。元の AC5 (`command "bats tests/workflow-guidance.bats"` 単体) は新規テストを 1 件も追加しなくても常時 PASS してしまう — 本セッションで実機検証済み (`bats --filter '<存在しないテスト名>' tests/workflow-guidance.bats` → `1..0` を出力し exit 0)。Triage AC audit コメントの提案および直近の precedent (#1279, #1293, #1334, #1363) に倣い、`grep "<新規テスト名>" tests/workflow-guidance.bats` (新規テストの存在確認。実装前は不一致) + `command "bats tests/workflow-guidance.bats"` (スイート全体の pass 確認) の 2 段構えに変更した。`bats --filter` 単体への変更 (audit コメントの当初案、#1279 が採用した方式) は不採用とした — フィルタが 0 件マッチでも exit 0 になる同型のギャップが #1334/#1363 の Spec investigation で指摘されており、grep + フルスイート実行の 2 段構えパターンがより新しく安全な precedent であるため。両修正は本 `/spec` セッション内で `gh-issue-edit.sh` により Issue #1103 本文に適用済み。
- **AC1〜AC3 は実装変更不要と確認**: `skills/review/workflow-guidance.md` 36-51 行目が Pre-flight の再呼び出し保証フォールバック分岐を既に実装している。Issue 本文の「実装状況」セクション自身もこれを記録済みだが、本 Spec は投資調査でこれを独立に再確認した (`grep -c` による実測、Root Cause 参照)。`modules/execution-context.md:93` は Issue #1103 自身をこのルールの precedent として既に列挙している。
- **CI ジョブ名確認済み**: `.github/workflows/test.yml:9` (`name: Run bats tests`) が AC の `github_check` ターゲットと一致することを確認した (Size 再評価前の `gh pr checks` 形での話。Size 再評価後は下記の通り `gh run list` 形に置換済み)。
- **Size 再評価 (Step 18) と AC5 の route-compatibility 修正**: Spec の Changed Files (実際に変更が生じるのは `tests/workflow-guidance.bats` 1 件のみ — `skills/review/workflow-guidance.md` は no change needed) を基に Size を再評価したところ XS (Axis 1: 1 ファイル。Axis 2: bug fix with clear root cause + 既存 grep-guard パターンの copy-and-adapt で減点方向、floor で据え置き。CI Dependency Minimum Override 該当なし) となり、triage 時点の M と乖離したため `modules/project-field-update.md` 経由で Size を XS に更新した (GraphQL mutation 成功、read-back 一致確認済み)。これにより ROUTE=patch (PR なし) が確定し、AC5 の verify command `github_check "gh pr checks" "Run bats tests"` は patch route では無効になる (`modules/size-workflow-table.md` Patch Route 制約)。`skills/spec/SKILL.md` の Patch route verify command check に従い `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` へ auto-fix した (`.github/workflows/` に `dco.yml`/`kanban-automation.yml`/`test.yml` の複数ファイルが存在するため `--workflow=test.yml` を明示)。Issue #1103 本文にも同じ修正を適用済み。
- **新規テストケース要件 (SPEC_DEPTH=light のため Step 13 retrospective を省略し、ここに記録)**: Implementation Step 1 で追加する `@test "workflow-guidance: Pre-flight falls back to static Task fan-out without re-invocation guarantee"` は、既存 (実装済み) の Pre-flight フォールバック分岐テキスト (`do NOT launch the Workflow tool for this step`) を grep-guard する。将来の編集がこの分岐を無言で弱体化・削除した場合に CI で検知できるようにするための回帰テストであり、新機能の実装を伴わない。
- Issue 本文 vs 実装の conflict detection (Step 6): Issue 本文の「実装状況」セクション自身が既に自己修正済みであり、本 Spec の投資調査で追加の乖離は検出されなかった。

## Consumed Comments

`append-consumed-comments-section.sh` の自動生成 (bash fallback) は「新規コメントなし」と書き込んだが、これは誤り — 本セッションの Step 3 (ラベル遷移: phase/issue → phase/spec) 自体が新しい `phase/*` ラベル割当イベントを生成し、fallback スクリプトが独自に再計算する cutoff (Primary: 直近の `phase/*` ラベル割当時刻) を両コメントより後ろに押し上げてしまったため。Step 2 (Worktree Entry 直後の Comment Consumption Procedure、ラベル遷移より前に実施) では正しく cutoff `2026-08-18T13:20:48Z` (phase/issue → phase/spec ラベル遷移前の直近 `phase/*` イベント) を用いて以下 2 件を検出・消費済みであり、以下がその正しい記録:

- saito / MEMBER / first-class / Issue Retrospective (`/issue` フェーズが `modules/execution-context.md:93` の precedent 記載および `workflow-guidance.md` 44-50 行目の既存実装を確認し、旧 AC2 の文言を「Workflow ツール可用性チェック」から「再呼び出し保証チェック」の実装済みの実体に合わせて修正した経緯を記録) / https://github.com/saitoco/wholework/issues/1103#issuecomment-5328811472
- saito / MEMBER / first-class / Triage AC audit (Pre-merge AC1〜AC5 を Pattern 2 常時 PASS の観点で監査。AC1〜AC3 は意図的な常時 PASS として許容可能と判定、AC4 [`grep "Workflow"`] は検出力ゼロのため置換・削除を提案、AC5 [`command "bats tests/workflow-guidance.bats"`] は新規テスト追加なしでも常時 PASS するため `bats --filter` 形式への絞り込みを提案 — 本 Spec は Notes に記載の通り AC4 削除 + grep+フルスイート 2 段構えで対応) / https://github.com/saitoco/wholework/issues/1103#issuecomment-5328861041

Code フェーズ (本セッション): cutoff `2026-08-18T13:41:11Z` (phase/ready ラベル割当時刻) 以降の新規コメントなし。cross-phase marker exception (`type=verify-fail` / `type=preview-ac-unverified`) 該当コメントもなし。

## Code Retrospective

### Deviations from Design
- なし。Spec Implementation Steps 1〜3 の通りに実装した (`tests/workflow-guidance.bats` へのテスト追加のみ、`skills/review/workflow-guidance.md` は変更不要)。

### Design Gaps/Ambiguities
- `skills/code/SKILL.md` Step 8 の「New Verification-Test Pre-implementation FAIL Check」は、新規 assert が参照する「実装対象ファイル」を revert して事前 FAIL を確認する手順を前提としているが、本 Issue のように新規テストが変更対象外のファイル (`skills/review/workflow-guidance.md`、既存実装済みかつ no-change-needed) を grep-guard する回帰テストの場合、revert 対象の「実装対象ファイル」自体が存在しない。この形は Spec Notes が明記する通り「新機能の実装を伴わない回帰テスト」という意図的なケースであり、代わりに `grep -c "do NOT launch the Workflow tool for this step" skills/review/workflow-guidance.md` (結果: 1件、一意) でパターンの特異性を確認し、フルスイート実行 (4/4 PASS) で妥当性を確認した。

### Rework
- なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1〜3 の通り、`tests/workflow-guidance.bats` への新規 `@test` 追加のみを実施し、`skills/review/workflow-guidance.md` / `modules/execution-context.md` への変更は行わなかった (Spec 投資調査で AC1〜AC3 の主張を既存記述が満たすことを確認済みのため)。
- Pre-merge AC1〜AC4 を verify-executor full mode で実行し全て PASS を確認、Issue body のチェックボックスを更新した (`gh-issue-edit.sh` 経由)。AC5 (`github_check "gh run list"`) は patch route の CI 未発生除外ルールにより未チェックのまま据え置いた。

### Deferred Items
- AC5 (bats テストスイートが CI で pass する) — patch route では本コミットがまだ push されておらず CI 未実行のため、この Code フェーズでは検証できない。post-push 後の `/verify` で検証される。
- Post-merge AC (`capabilities.workflow: true` の状態で Size M/L の Issue に対し `/auto` を実行し review フェーズが完走することを確認する) — manual verify-type のため post-merge `/verify` 側の対応。

### Notes for Next Phase
- 本 Issue は patch route (ROUTE=patch、Size XS へ再評価済み) — PR は作成されない。次フェーズは `/verify` (post-push の CI 結果と post-merge AC の確認)。
- 新規テストは既存実装済みの Pre-flight フォールバック分岐に対する回帰テストであり、新機能実装は伴わない。将来 `skills/review/workflow-guidance.md` の当該分岐が弱体化・削除された場合、このテストが CI で検知する。
