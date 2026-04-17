# Issue #195: test: run-spec.sh と run-auto-sub.sh に bats テストを追加

## Overview

`scripts/run-spec.sh` (78 LOC) と `scripts/run-auto-sub.sh` (201 LOC) に bats テストが存在しない。他の `run-*.sh` は全てテスト済み。既存の `run-*.bats` パターン (claude/gh/timeout mock + MOCK_DIR + WHOLEWORK_SCRIPT_DIR) を踏襲して新規テストファイルを作成する。

## Changed Files

- `tests/run-spec.bats`: new file — run-spec.sh のテスト。引数バリデーション、claude 呼び出し引数 (model/effort/permissions)、`--opus` オプション、frontmatter parsing、CLAUDECODE 環境変数 unset — bash 3.2+ compatible
- `tests/run-auto-sub.bats`: new file — run-auto-sub.sh のテスト。引数バリデーション、Size 4 分岐 (XS/S/M/L)、XL エラー、phase/ready スキップ、patch lock 機構、`--base` フラグ伝播。`WHOLEWORK_SCRIPT_DIR` でsibling scripts をモック — bash 3.2+ compatible

## Implementation Steps

1. `tests/run-spec.bats` を作成する。既存の `tests/run-issue.bats` の setup パターン (claude mock + gh mock) をベースに、以下のテストケースを実装する (→ AC #1, #3, #4):
   - 引数なし / 非数値 / 不明オプション → error exit
   - デフォルト → `--model claude-sonnet-4-6`, `--effort max`, `--dangerously-skip-permissions`
   - `--opus` → `--model claude-opus-4-6`
   - SKILL.md 不在 → error ("SKILL.md not found")
   - frontmatter `---` 不在 → error ("frontmatter not found")
   - `CLAUDECODE` が `env -u` で unset されること

   frontmatter テスト用に `$BATS_TEST_TMPDIR` に SKILL.md ダミーを作成し、`WHOLEWORK_SCRIPT_DIR` を `$MOCK_DIR` にセット。`$MOCK_DIR/../skills/spec/SKILL.md` にダミーファイルを配置して SKILL_FILE パスを解決させる

2. `tests/run-auto-sub.bats` を作成する。以下のモック構成を setup() に配置する (→ AC #2, #5, #6, #7, #8):
   - `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` で sibling scripts (run-spec.sh, run-code.sh, run-review.sh, run-merge.sh, run-verify.sh, get-issue-size.sh, phase-banner.sh) を全て MOCK_DIR 配下のモックに差し替え
   - `gh` mock: `issue view --json labels` でラベル応答、`pr list` で PR 番号応答を制御
   - `git` mock: `rev-parse --show-toplevel` でリポジトリルート応答

   テストケース:
   - 引数なし / 非数値 / `--base` 引数欠落 / 不明オプション → error exit
   - Size XS: run-code.sh `--patch` が呼ばれ、run-review.sh / run-merge.sh は呼ばれない
   - Size S: 同上 (XS と同じ phase 構成)
   - Size M: run-code.sh `--pr` + run-review.sh `--light` + run-merge.sh + run-verify.sh
   - Size L: run-code.sh `--pr` + run-review.sh `--full` + run-merge.sh + run-verify.sh
   - Size XL: "Further sub-issue splitting is required" error exit
   - phase/ready あり → run-spec.sh 呼ばれない
   - phase/ready なし → run-spec.sh 呼ばれる
   - `--base release/v1` → 子スクリプトに `--base release/v1` が伝播
   - PATCH_LOCK: XS route で lock dir が作成→解放される

3. ローカルで `bats tests/run-spec.bats tests/run-auto-sub.bats` を実行し全テスト PASS を確認 (→ AC #9)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/run-spec.bats" --> `tests/run-spec.bats` が存在する
- <!-- verify: file_exists "tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が存在する
- <!-- verify: file_contains "tests/run-spec.bats" "frontmatter" --> `tests/run-spec.bats` に SKILL.md frontmatter parsing 関連のテストが含まれている
- <!-- verify: file_contains "tests/run-spec.bats" "sonnet" --> `tests/run-spec.bats` に Sonnet モデル指定の検証が含まれている（Issue #227 により alias 形式に更新済み）
- <!-- verify: file_contains "tests/run-auto-sub.bats" "Size XS" --> `tests/run-auto-sub.bats` に Size XS 分岐テストが含まれている
- <!-- verify: file_contains "tests/run-auto-sub.bats" "Size L" --> `tests/run-auto-sub.bats` に Size L 分岐テストが含まれている
- <!-- verify: file_contains "tests/run-auto-sub.bats" "PATCH_LOCK" --> `tests/run-auto-sub.bats` に patch lock 機構のテストが含まれている
- <!-- verify: file_contains "tests/run-auto-sub.bats" "phase/ready" --> `tests/run-auto-sub.bats` に phase/ready ラベル検出による spec skip テストが含まれている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テスト CI が PASS する

### Post-merge

- 主要ケース (正常系・引数不正・外部コマンド失敗) が網羅されていることを次回関連 PR レビュー時に確認する

## Notes

### bats テスト入力データ形式

- `get-issue-size.sh` mock: stdout に Size 文字列 (`XS`/`S`/`M`/`L`/`XL`) を 1 行出力、exit 0
- `gh issue view --json labels -q '.labels[].name'` mock: ラベル名を改行区切りで出力 (例: `phase/ready\ntriaged`)
- `gh pr list --json number -q '.[0].number'` mock: PR 番号 (例: `99`) を 1 行出力
- `run-*.sh` sibling mocks: 引数をログファイルに記録して exit 0。呼び出し検証用

### WHOLEWORK_SCRIPT_DIR mock パターン

run-auto-sub.sh は `$SCRIPT_DIR/run-code.sh` 等で sibling scripts を呼び出す。`export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定し、`$MOCK_DIR/run-code.sh` 等のモックスクリプトを配置する。各モックは引数をログファイルに記録して exit 0 とする。これにより sibling 呼び出しが実際のスクリプトではなくモックに解決される (#188 で導入した規約)。

### frontmatter テスト用のダミー SKILL.md

run-spec.sh は `SKILL_FILE="${SCRIPT_DIR}/../skills/spec/SKILL.md"` で SKILL.md を参照する。テスト側では `MOCK_DIR/../skills/spec/SKILL.md` にダミーファイル (frontmatter + body) を配置し、frontmatter 正常系と不在系をテストする。ダミー生成は `$BATS_TEST_TMPDIR` 配下のディレクトリ構造で実現する。

### patch lock テストの範囲

`acquire_patch_lock` の成功 (mkdir + PATCH_LOCK_DIR の存在確認) と `release_patch_lock` の成功 (rmdir + 不在確認) をテストする。timeout (300s) シナリオは sleep mock の複雑性ゆえ scope 外。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- verify コマンドの `file_contains "tests/run-auto-sub.bats" "Size: XS"` / `"Size: L"` が miscalibrated だった。Spec ではテスト名パターンを `"Size: XS"` と想定していたが、実際には bats の `@test` 名は `"Size XS:"` (コロン位置が異なる) になる。これは run-auto-sub.sh のログ出力 `echo "Size: ${SIZE}"` と混同した可能性がある。verify hint は `"Size XS"` / `"Size L"` に修正した。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. All Spec-specified test cases were implemented as described. The verify hint correction (`"Size: XS"` → `"Size XS"`) was pre-identified and documented in Code Retrospective before review, demonstrating good self-correction during implementation.

### Recurring issues

Nothing to note. No repeated issue patterns were observed across the two test files.

### Acceptance criteria verification difficulty

The `github_check` condition (bats test CI PASS) was PENDING at review time because CI was still running. This is expected behavior for a test-addition PR. Consider adding a note in future Specs that CI-dependent verify conditions may be PENDING on first review attempt — this is acceptable and `/merge` should wait for CI completion before proceeding.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective および Spec Retrospective セクションが存在しない。これ自体は問題ではないが（#195 は Spec 段階で設計議論が少なかったため）、今後 `/issue` と `/spec` が retrospective セクションを追加する際にフォーマット統一を意識すること。

#### design
- N/A（Spec Retrospective セクションなし）

#### code
- verify hint の誤校正 (`"Size: XS"` → `"Size XS"`) が Code Retrospective に記録されており、実装中に自己修正されている。これは `/spec` 段階で verify hint を生成する際に、bats テスト名の命名規則をより正確に反映させる余地があることを示す。

#### review
- PR #205 のレビューは 1 件。CI PENDING 条件を `/review` 段階で UNCERTAIN として記録し、`/merge` を CI 完了後に実施した判断は適切。

#### merge
- squash merge で競合なし。クリーンな実装。

#### verify
- 条件 1-9 はすべて PASS（ファイル存在・内容確認・CI PASS）。
- 前回の `/verify` 実行時は条件 9（bats テスト CI PASS）が PENDING（CI in_progress）だったが、今回の再実行で CI 完了確認（success）し PASS に昇格。
- Post-merge 条件 10（opportunistic）は次回関連 PR レビュー時の手動確認のため未チェックのまま。`phase/verify` ラベルで管理。

### Improvement Proposals
- `/spec` が verify hint を生成する際、bats テスト名で頻用される文字列パターン（`@test "XXX"` の命名規則）を考慮し、`file_contains` のキーワードをテスト名形式に合わせて生成するよう `/spec` プロンプトにガイダンスを追加することを検討する。
