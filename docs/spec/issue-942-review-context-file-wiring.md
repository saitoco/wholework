# Issue #942: review: observation-trigger.sh 呼び出しに --context-file 配線を追加

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Triage 時点の Auto-Resolve Log (対象 Spec ファイルの解決方法は Step 10.0/10.2 の既存 Glob パターンを再利用する、Spec ファイル不在時も `--context-file` を無条件に渡してよい)。Issue body の「Auto-Resolved Ambiguity Points」セクションと同内容だが、Background 事実確認と AC 変更理由の詳細な根拠を含む / URL: https://github.com/saitoco/wholework/issues/942#issuecomment-4887829213

## Overview

Issue #934 で `scripts/opportunistic-search.sh` / `scripts/observation-trigger.sh` に実装された `--context-file <path>` 引数と `keyword=` Condition Check Gate は、呼び出し元が `--context-file` を渡さない限り無条件マッチのまま残る opt-in 機構であり、実際の呼び出し元 (`/review` SKILL.md 等) を配線する対応は #934 のスコープ外とされていた。本 Issue では `/review` SKILL.md の `## Opportunistic Verification` ステップ (`observation-trigger.sh --event pr-review-full`/`pr-review-light` 呼び出し) に対象 Spec ファイルパスを `--context-file` として渡す配線を追加し、`keyword=` 属性を持つ observation AC (例: Issue #794 の `event=pr-review-full keyword=enum`) が実際に条件チェックゲートの恩恵を受けられるようにする。

## Changed Files

- `skills/review/SKILL.md`: `## Opportunistic Verification` セクションの Event-based observation scan 手順に、Spec ファイルパス解決 (Step 10.0/10.2 と同一の Glob パターン `$SPEC_PATH/issue-$ISSUE_NUMBER-*.md` を再利用) と `--context-file` 引数の配線を追加
- `tests/review.bats`: 新規作成。`## Opportunistic Verification` セクション内に `--context-file` 配線が存在することを検証する構造テストを追加 (`tests/issue.bats` / `tests/auto-completion-report.bats` と同じ awk セクション抽出 + grep パターンを踏襲)

## Implementation Steps

1. `skills/review/SKILL.md` の `## Opportunistic Verification` セクション内、`observation-trigger.sh --event pr-review-full`/`pr-review-light` の2行の直前に、Spec ファイルパス解決手順を追加する: `$ISSUE_NUMBER` が非空なら `$SPEC_PATH/issue-$ISSUE_NUMBER-*.md` を Glob し、マッチしたパスを `DESIGN_FILE_PATH` に記録 (マッチなし、または `$ISSUE_NUMBER` が空なら空文字列)。既存の Step 10.0/10.2 と同一パターンを再利用する (→ 受け入れ基準1)
2. (after 1) 同セクションの `observation-trigger.sh --event pr-review-full`/`pr-review-light` 呼び出しそれぞれに `--context-file "$DESIGN_FILE_PATH"` を追加する。値が空文字列でも無条件に渡してよい (`opportunistic-search.sh` 側がパス不在時にゲートを無効化して無条件マッチにフォールバックする安全策を実装済みのため) (→ 受け入れ基準1)
3. (parallel with 1, 2) `tests/review.bats` を新規作成し、`skills/review/SKILL.md` の `## Opportunistic Verification` セクションを awk で抽出した上で `--context-file` 文字列の存在を grep で検証するテストケースを追加する (→ 受け入れ基準2)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/review/SKILL.md の observation-trigger.sh 呼び出しに、対象 Spec ファイルを --context-file として渡す配線が追加されている" --> <!-- verify: section_contains "skills/review/SKILL.md" "## Opportunistic Verification" "--context-file" --> `/review` SKILL.md の `observation-trigger.sh --event pr-review-full`/`pr-review-light` 呼び出しに `--context-file <spec-path>` が渡されている
- <!-- verify: rubric "配線変更に対応する bats テストケースが追加または更新されている" --> 配線変更を検証するテストケースが追加/更新されている

### Post-merge

なし

## Notes

- 変数名 `DESIGN_FILE_PATH` は Step 10.0/10.2 で既に使われている命名を踏襲する。ただし値は Step 10 から引き継がず、Opportunistic Verification ステップ内で改めて Glob 解決する (Triage の Auto-Resolve Log で決定済みの方針)。Step 10 側の変数は同ステップの Task プロンプト埋め込み用のローカルな解決でありスキル全体を通じた永続変数として宣言されていないため、review-only モード分岐や Step 10 未実行パスに依存しない自己完結な解決とする方が安全。
- `tests/review.bats` は本 Issue で新規作成する。`/review` の prose (SKILL.md) 内容を直接検証する構造テストファイルはこれまで存在しなかった (`tests/run-review.bats` は `run-review.sh` のシェルロジックのみを対象とするフィクスチャテスト)。
- Steering Docs sync candidate チェック: `skills/review/SKILL.md` の basename keyword `review` で `docs/*.md`/`docs/ja/*.md` を grep すると19ファイルがヒットするが、いずれも一般語 "review" のマッチによるノイズであり、`--context-file`/`observation-trigger.sh` の呼び出し詳細を記述している箇所はない。`docs/structure.md` にある `observation-trigger.sh`/`opportunistic-search.sh` の1行説明はスクリプト概要のみでフラグ単位の記述はなく、本変更後も正確なまま。実際の sync candidate なし。
- 外部仕様依存チェック: 本 Issue の変更は `scripts/observation-trigger.sh`/`scripts/opportunistic-search.sh` の既存実装 (`--context-file` 引数、空パス・不在パス時のフォールバック挙動) を直接読み込んで確認済みであり、未検証の外部 API/コマンド仕様への依存はない。

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1-3 を計画通りに実装した)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `DESIGN_FILE_PATH` の Glob 解決を Opportunistic Verification ステップ内で自己完結させ、Step 10 側のローカル変数には依存しなかった (Spec Notes の既定方針通り)。
- `tests/review.bats` は `tests/auto-completion-report.bats` の awk セクション抽出パターンをそのまま踏襲し、`## Opportunistic Verification` セクションを次の `## ` 見出し (`## Completion Report`) の直前までで区切った。

### Deferred Items
- None

### Notes for Next Phase
- `phase/ready` ラベルが本 Issue には付与されていなかった (既に `phase/code` へ遷移済みの状態で Spec ファイルは存在) — `reconcile-phase-state.sh --check-precondition` は `matches_expected: false` の warning を返したが、Spec 実体があったため `/code` は Spec を正常に読み込んで続行した。`/review` フェーズでも同様に Spec 存在を前提にして問題ない。
- pre-merge AC 2件は本コミットで両方 PASS 済み (Issue 側チェックボックスも更新済み)。post-merge AC はなし。
