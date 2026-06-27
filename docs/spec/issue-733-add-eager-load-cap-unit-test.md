# Issue #733: test: add direct unit test for scripts/check-eager-load-capability.sh

## Overview

`scripts/check-eager-load-capability.sh` は `/audit drift` の eager-load 共通モジュールへの capability guidance 混入を検出するスクリプト。既存の `tests/audit-eager-load-capability.bats` は integration スコープのみカバーし、以下の edge case が未カバー:
- empty Glob (adapter ファイルなし → exit 0 の明示的検証)
- verify-executor.md (第2ターゲットファイル) での検出
- domain file 存在時の抑制動作
- 複数 capability の同時検出

新規ファイル `tests/check-eager-load-capability.bats` にこれらをカバーする直接 unit test を追加する。

## Changed Files

- `tests/check-eager-load-capability.bats`: 新規作成 — scripts/check-eager-load-capability.sh の direct unit test (4 @test ケース) — bash 3.2+ 互換
- `docs/structure.md`: テストファイル数カウント `(86 files)` → `(87 files)` に更新
- `docs/ja/structure.md`: 同カウント更新を日本語ミラーに反映 (translation sync)

## Implementation Steps

1. `tests/check-eager-load-capability.bats` を新規作成し、以下 4 件の @test を実装する (→ AC1, AC2, AC3)

   - `empty Glob: no adapter files exits 0 with no output` — `modules/*-adapter.md` がゼロ件のとき exit 0 かつ出力なし
   - `detection: adapter with contaminated verify-executor.md reports issue` — adapter 存在、verify-executor.md に capability セクション見出し、domain file なし → ISSUE 行出力 (第2ターゲットファイルのカバレッジ; integration test でカバー済みの verify-patterns.md とは別)
   - `no-issue: domain file presence suppresses detection` — adapter + 汚染済み verify-patterns.md + skills/ 下に domain file 存在 → 出力なし
   - `multi: two adapters both contaminating verify-patterns.md report two ISSUE lines` — 2 adapter + 両方の capability セクション + domain file なし → ISSUE 行が 2 件

   テストは `BATS_TEST_TMPDIR` を使用 (bats builtin; mktemp -d 手動管理不要)。`WHOLEWORK_SCRIPT_DIR` mock は不要 (本スクリプトは `--root` フラグのみで依存スクリプトを呼ばない)。

2. `docs/structure.md` の `tests/` 行のカウントを `(86 files)` → `(87 files)` に更新する (→ SHOULD 文書整合性)

3. `docs/ja/structure.md` の対応行も同様に `(86 files)` → `(87 files)` に更新する (→ translation sync)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/check-eager-load-capability.bats" --> direct unit test ファイルが新規作成されている
- <!-- verify: file_contains "tests/check-eager-load-capability.bats" "@test" --> 最低 4 件以上の @test (empty Glob / capability detection / domain file 不在判定 / 複数 capability 検出) を含む
- <!-- verify: command "bats tests/check-eager-load-capability.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green

### Post-merge

- 次回 check-eager-load-capability.sh を変更する Issue で direct unit test が regression を検出することを観察

## Notes

- `check-eager-load-capability.sh` は `-adapter.md` サフィックス除去に `basename "$adapter" -adapter.md` を使用。adapter ファイル名が `X-adapter.md` 形式でない場合は capability 名が正しく抽出されないが、現状の bundled adapter は全て `-adapter.md` 形式のため対象外。
- `verify-executor.md` の第2ターゲット検証: integration test は verify-patterns.md のみカバー。unit test でこのギャップを埋める。
- Auto-resolved (Issue Retrospective より transfer):
  - AC2 の `file_contains "@test"` は件数保証なし — カウント制約は AC3 の `bats` 実行 (green = 全テスト通過) で間接担保する (`verify-patterns.md §1` の UNCERTAIN 警告による)
  - 「empty Glob」は AC2 括弧リストの初出; スクリプトが `if [ -z "$capabilities" ]; then exit 0; fi` で明示処理しており、regression ポイントとして重要
  - 「不正な domain file frontmatter」のテストは除外 — スクリプトはファイル名ベースで capability 名を抽出し frontmatter を解析しないため価値が低い

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / auto-resolved ambiguity points (AC2 count mismatch, empty Glob missing, fix scope) を整理した Issue Retrospective / https://github.com/saitoco/wholework/issues/733#issuecomment-4814293379

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- 既存 integration test (`tests/audit-eager-load-capability.bats`) が `setup()` で `mktemp -d` を手動管理しているが、Spec は bats builtin の `BATS_TEST_TMPDIR` を使用するよう明示していた。新規ファイルは `BATS_TEST_TMPDIR` を採用し (bats 1.13.0 で利用可能確認)、`teardown()` での手動削除も不要になった。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `BATS_TEST_TMPDIR` を使用し teardown 不要のシンプルなテスト構造を採用 (bats 1.13.0 確認済み)
- 4 @test: empty Glob / verify-executor.md detection / domain file suppression / multi-capability detection — Spec の実装ステップを忠実に実装

### Deferred Items
- AC4 (`github_check CI`) は main へのマージ後 CI 実行で確認 (patch route のため push 後に自動実行)

### Notes for Next Phase
- `/verify` は AC1–AC3 が既にチェック済み (Issue body に反映)。AC4 のみ CI 完了後に確認が必要
- 変更ファイル: `tests/check-eager-load-capability.bats` (新規)、`docs/structure.md`、`docs/ja/structure.md` (カウント 86→87 更新)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Auto-Resolved Ambiguity Points が AC2 count constraint mismatch / empty Glob 漏れ / fix scope を事前に整理。`/issue` retrospective が次フェーズに正確に橋渡しされた。

#### spec
- Spec の implementation steps が 4 @test を漏れなく列挙し、code phase で忠実に実装された。Bats 1.13.0 の `BATS_TEST_TMPDIR` 採用方針も明示。

#### code
- Design Gap として「既存 integration test の `mktemp -d` パターンと新規ファイルの `BATS_TEST_TMPDIR` パターンの不統一」が記録されたが、新規ファイルでよりシンプルな方を採用するのは合理的な判断。Rework なし。

#### review
- patch route のため review phase スキップ (Size S)

#### merge
- patch route のため merge phase スキップ (main 直接コミット `b67c906`)

#### verify
- AC4 (`github_check CI`) の verify command 形式が workflow 全体の conclusion を見るため、本 Issue と無関係な job (`Forbidden Expressions check`) の失敗で FAIL になった。actual の bats job 自体は success。intent (CI bats 全件 green) は満たされているため代替検証で PASS と判定。

### Improvement Proposals
- **PROPOSAL** (skill-infra): `github_check` verify command で workflow 全体ではなく特定 job の conclusion を見られる sub-form を検討。例: `github_check_job "gh run view ID --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success"`。現在は workflow 全体の lint 失敗で意図しない FAIL が発生し、verify 出力の信頼性を損なう。
