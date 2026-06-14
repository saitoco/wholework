# Issue #629: run-auto-sub.sh の Step 3a 相当に route demotion/upgrade を追加

## Overview

`scripts/run-auto-sub.sh` が spec フェーズ後に SIZE を無条件に再取得しないバグを修正する。
現状は「初期 SIZE が empty のときのみ再取得」となっており、triage 済み (SIZE 設定済み) の Issue で spec が Size を変更した場合に古い Size に基づく route で実行される。`skills/auto/SKILL.md` Step 3a (#616) と同等の動作を `run-auto-sub.sh` にも適用する。

## Reproduction Steps

1. XL parent issue の sub-issue (#581/#548 など) を `run-auto-sub.sh` 経由で実行
2. sub-issue の初期 Size が M (triage 済み)、spec フェーズが XS に降格
3. spec 完了後も `case "$SIZE" in` が M のまま → `run-code.sh --pr` が呼ばれる
4. あるべき動作: SIZE=XS → `run-code.sh --patch`

## Root Cause

`scripts/run-auto-sub.sh` の SIZE 再取得が条件付き (line ~152-154):

```bash
if [[ -z "$SIZE" ]]; then
  SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)
fi
```

初期 SIZE が non-empty の場合 (triage 済み) は `if` ブロックに入らず、spec が Size を変更しても再取得されない。`skills/auto/SKILL.md` Step 3a では無条件再取得が実装済み (#616) だが `run-auto-sub.sh` 側への同等適用が漏れていた。

## Changed Files

- `scripts/run-auto-sub.sh`: 条件付き re-fetch を無条件 re-fetch に変更 + INITIAL_SIZE 比較 + ログ + emit_event — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: Size 変更検出の bats テスト 3 ケース追加 (M→XS 下方向 / S→M 上方向 / Size 不変)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の SIZE re-fetch ブロック (spec フェーズ後、`if [[ -z "$SIZE" ]]; then ... fi` の箇所) を以下に置換 (→ 受入条件 AC1, AC2, AC3):

   ```bash
   # Always re-fetch SIZE after spec phase (spec may have re-judged the Size)
   # Mirror of skills/auto/SKILL.md Step 3a (Issue #616 for the parent path)
   INITIAL_SIZE="$SIZE"
   SIZE=$("$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER" 2>/dev/null || true)
   if [[ -n "$INITIAL_SIZE" && "$INITIAL_SIZE" != "$SIZE" ]]; then
     echo "${LOG_PREFIX} Post-spec route demotion/upgrade: ${INITIAL_SIZE} → ${SIZE}, remaining phases re-planned"
     emit_event "size_refresh" "from=${INITIAL_SIZE}" "to=${SIZE}"
   fi
   ```

   `if [[ -z "$SIZE" ]]; then` の直下にある空の `fi` まで含めて完全置換する。その下の `if [[ -z "$SIZE" ]]; then ... exit 1` (SIZE 未設定エラー) はそのまま残す。

2. `tests/run-auto-sub.bats` に 3 つの `@test` を追加 (→ 受入条件 AC5):

   a. **Size downgrade M→XS**: `get-issue-size.sh` が 1 回目 "M"、2 回目 "XS" を返すよう呼び出し回数カウントで制御。phase/ready なし (spec 実行)。結果: `run-code.sh --patch` が呼ばれ、"Post-spec" がログに含まれる。

   b. **Size upgrade S→M**: `get-issue-size.sh` が 1 回目 "S"、2 回目 "M" を返す。phase/ready なし。結果: `run-code.sh --pr` が呼ばれ、"Post-spec" がログに含まれる。

   c. **Size unchanged XS→XS**: `get-issue-size.sh` が常に "XS" を返す。phase/ready なし。結果: "Post-spec" がログに含まれない。

   テスト a/b のカウンタ実装: `CALL_COUNT_FILE="$BATS_TEST_TMPDIR/.size-call-count"` を使い、1 回目と 2 回目で異なる値を返す mock を構築する。

## Verification

### Pre-merge

- <!-- verify: grep "INITIAL_SIZE" "scripts/run-auto-sub.sh" --> SIZE 変更検出のためのコンパリゾンロジックが実装されている
- <!-- verify: grep "route demotion|route upgrade|Post-spec" "scripts/run-auto-sub.sh" --> Size 変更時のログ出力がある
- <!-- verify: grep "size_refresh" "scripts/run-auto-sub.sh" --> emit_event で structured event を出す
- <!-- verify: rubric "scripts/run-auto-sub.sh always re-fetches SIZE after spec phase (not conditionally on initial empty), and the case dispatch uses the post-spec SIZE for route selection, mirroring the Step 3a fix in skills/auto/SKILL.md (Issue #616)" --> #616 と同等の挙動が rubric 基準で確認できる
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テストが green（M→XS 下方向 / S→M 上方向 / Size 不変の最小 3 ケース）
- <!-- verify: command "bash -n scripts/run-auto-sub.sh" --> 構文エラーなし

### Post-merge

- 次回の `/auto --batch` または `/auto <XL>` 実行で、spec が Size を変更した場合に route も追従することを観察

## Notes

- 実装ステップ 1 の置換対象は run-auto-sub.sh の spec フェーズ直後にある `if [[ -z "$SIZE" ]]; then ... fi` ブロックのみ。その後の `if [[ -z "$SIZE" ]]; then echo "Error: Size is not set"` は削除しない (SIZE が依然として空の場合のフェイルセーフ)
- Issue body のコード例では AC2 が `"route demotion|route upgrade|Post-spec"` のいずれかを検索しているが、Spec では実装文字列として "Post-spec" を使用 (Issue body の提案と整合)
- 既存テストの `get-issue-size.sh` モックは常に単一の値を返す設計のため、新テストでは呼び出し回数カウントファイルを使ったステートフルな mock を追加する
- detect-wrapper-anomaly.sh は MOCK_DIR に存在しなくてもよい (`|| true` で無視)
- auto-sub-observability.bats とのテスト分離: 新テストは run-auto-sub.bats に追加する (observability とは別 concern)

## issue retrospective

### トリアージ自動実行

`triaged` ラベルが不在だったため、`/triage 629` を自動実行した。

**結果:**
- Type: Bug（バグ — 条件付き re-fetch が stale SIZE を引き起こす欠陥）
- Priority: high（Issue 本文の `Priority=high` を検出）
- Size: S（変更対象: `scripts/run-auto-sub.sh` 1〜2ファイル、root cause 明確でシンプルな修正）
- Value: 3（Impact=2: 共有コンポーネント, Alignment=4: コアワークフロー精度に直結）

### 曖昧ポイント

検出なし。Issue #629 は背景・根本原因・修正提案・受入条件が明確に記載されている。

### AC5 verify command の更新（自動解決）

- 変更前: `command "bats tests/run-auto-sub.bats"`
- 変更後: `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`
- 理由: Size=S はパッチ経路（PR なし）のため、`github_check "gh run list"` 形式を使用

## spec retrospective

### Minor observations

- Nothing to note

### Judgment rationale

- Issue body の修正提案コードをそのまま実装ステップに採用。提案内容が具体的かつ #616 との対称性が明確なため、別実装の検討は不要と判断した。
- AC2 verify command は `grep "route demotion|route upgrade|Post-spec"` (Issue body 原文) を verbatim コピー。実装ログ文字列として "Post-spec route demotion/upgrade" を使用すれば `Post-spec` にマッチする。

### Uncertainty resolution

- Nothing to note

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- SIZE 再取得を無条件化し、INITIAL_SIZE との比較で変更時のみ `emit_event "size_refresh"` を発行する設計を採用。条件分岐を最小化してコードを単純に保つ。
- テストは既存の `tests/run-auto-sub.bats` に追加。新ファイルではなく既存ファイルへの拡張 (同一 concern)。
- 呼び出し回数カウントファイルを使った mock で first-call / second-call で異なる Size 値を返す設計を採用。

### Deferred Items
- None

### Notes for Next Phase
- 置換対象は `if [[ -z "$SIZE" ]]; then ... fi` ブロックのみ (spec フェーズ直後)。その後の SIZE 未設定エラーチェック `if [[ -z "$SIZE" ]]; then echo "Error..."` は削除しない。
- `detect-wrapper-anomaly.sh` はテスト mock に含めなくてよい (`|| true` で安全に無視される)。
- CI テスト (test.yml) が全 green であることを確認すること。
