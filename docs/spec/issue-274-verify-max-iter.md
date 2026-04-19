# Issue #274: verify: reopen ループに明示的な max_iterations を導入

## Overview

`/verify → reopen → /fix` ループに上限を設ける。`.wholework.yml` に `verify-max-iterations: N`（default 3、max 20）を追加し、verify FAIL 時の reopen 判定前に `<!-- verify-iteration: N -->` マーカー（Issue コメント内）でカウンタを管理する。カウンタが上限未満なら通常の reopen を行い、上限到達時は reopen せず `phase/verify` に留めて "max iterations reached (N/N)" コメントを投稿する。`/auto` はこれを検出して連鎖実行を停止する。

## Changed Files

- `modules/detect-config-markers.md`: `verify-max-iterations` → `VERIFY_MAX_ITERATIONS` 行を Marker Definition Table に追加（integer、default 3、range 1-20）；YAML Parsing Rules に integer 制約を追記；Output Format セクションに追記
- `docs/guide/customization.md`: YAML example に `verify-max-iterations` 行を追加；Available Keys テーブルに行を追加
- `docs/ja/guide/customization.md`: 翻訳同期（YAML example・テーブルに日本語説明を追加）
- `skills/verify/SKILL.md`: Step 4 の `detect-config-markers.md` 保持変数に `VERIFY_MAX_ITERATIONS` を追加；Step 9 FAIL 分岐に counter 読み取り・増分・上限チェック・コメント投稿ロジックを追加（`get-verify-iteration.sh` 呼び出し、`<!-- verify-iteration: N -->` マーカー付きコメント、"max iterations reached (N/N)" テンプレート）
- `skills/auto/SKILL.md`: Step 4 verify フェーズ結果判定に "verify 出力に `MAX_ITERATIONS_REACHED` が含まれる場合は連鎖実行を停止" の記述を追加
- `scripts/get-verify-iteration.sh`: 新規スクリプト — Issue コメントから `<!-- verify-iteration: N -->` マーカーを読み取り、最大 N（なければ 0）を返す — bash 3.2+ 互換
- `tests/get-verify-iteration.bats`: 新規 bats テスト — `get-verify-iteration.sh` の動作を検証
- `docs/tech.md`: Architecture Decisions の `/auto` セクションに `verify-max-iterations` による verify-reopen ループ保護の説明を追記
- `docs/structure.md`: scripts count 36→37、"Project utilities" セクションに `scripts/get-verify-iteration.sh` エントリを追加；tests count 36→37
- `docs/ja/structure.md`: 翻訳同期（上記と同一内容を日本語で追加）

## Implementation Steps

1. **Config 定義追加**（→ 受け入れ条件 1, 2）
   - `modules/detect-config-markers.md`: Marker Definition Table に `verify-max-iterations` | `VERIFY_MAX_ITERATIONS` | Integer（1-20、範囲外・非数値は 3 にフォールバック）| `3` 行を追加。YAML Parsing Rules に "watchdog-timeout-seconds と同様の integer 扱い（≤0、非数値、または >20 の場合は 3 にフォールバック）" を追記。Output Format セクションに `VERIFY_MAX_ITERATIONS` 変数を追記
   - `docs/guide/customization.md`: YAML example コメントに `verify-max-iterations: 3` を追加（`# Verify reopen loop limit (default: 3, max: 20)` コメント付き）；Available Keys テーブルに `verify-max-iterations` | integer | `3` | `Limit verify-reopen loop iterations; stops at N failures` 行を追加
   - `docs/ja/guide/customization.md`: 同一内容を日本語で追加（「verify reopen ループの最大試行回数（default: 3、max: 20）」）

2. **カウンタ読み取りヘルパー + テスト**（→ 受け入れ条件 7, 8）
   - `scripts/get-verify-iteration.sh`: 新規スクリプト。引数: `<issue-number>`。`gh issue view "$ISSUE_NUMBER" --json comments --jq '.comments[].body'` でコメント本文を取得し、`grep -oE '<!-- verify-iteration: [0-9]+ -->'` で全マーカーを抽出、最大値を echo（なければ 0）。数値以外の引数はエラー終了。bash 3.2+ 互換（`grep -oE` を使用、`mapfile` 不使用）
   - `tests/get-verify-iteration.bats`: `WHOLEWORK_SCRIPT_DIR` モック方式でテスト。ケース: コメントなし→0; マーカー 1 件→N; 複数マーカー→最大値; 非数値引数→エラー

3. **`/verify` SKILL.md 変更**（→ 受け入れ条件 3, 4, 5）
   - Step 4 `Resolving configuration values` の保持変数リストに `VERIFY_MAX_ITERATIONS` を追記
   - Step 9 FAIL 分岐（CLOSED path・OPEN path 両方）の reopen ステップ直前に以下を挿入:
     1. `CURRENT_ITERATION=$(...scripts/get-verify-iteration.sh "$NUMBER")`; `NEXT_ITERATION=$((CURRENT_ITERATION + 1))`
     2. `NEXT_ITERATION < VERIFY_MAX_ITERATIONS` なら: `<!-- verify-iteration: ${NEXT_ITERATION} -->` 付きコメントを投稿してから既存 reopen 処理を実行
     3. `NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` なら: "max iterations reached (${NEXT_ITERATION}/${VERIFY_MAX_ITERATIONS})" + `<!-- verify-iteration: ${NEXT_ITERATION} -->` を含むコメントを投稿; `phase/verify` に留める（reopen・close なし）; ターミナルに `MAX_ITERATIONS_REACHED` 文字列を出力

4. **`/auto` SKILL.md 変更**（→ 受け入れ条件 6）
   - Step 4 patch/pr route の verify フェーズ結果判定に注記を追加: "verify 出力に `MAX_ITERATIONS_REACHED` が含まれる場合は max iterations 到達を意味する。連鎖実行を停止し、Step 5 へ（human judgment required と付記）"

5. **ドキュメント同期**（SHOULD 対応）
   - `docs/tech.md`: Architecture Decisions `/auto` セクション末尾に "verify-max-iterations (default: 3, max: 20, configurable via .wholework.yml) caps the verify-reopen loop; when the counter reaches the limit, the Issue stays in phase/verify and awaits human judgment" を追記
   - `docs/structure.md`: scripts カウント 36→37（`get-verify-iteration.sh` 追加分）; "Project utilities" セクションに `scripts/get-verify-iteration.sh` エントリを追加; tests カウント 36→37
   - `docs/ja/structure.md`: 同一内容を日本語で追記

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/detect-config-markers.md" "verify-max-iterations" --> `modules/detect-config-markers.md` の Marker Definition Table に `verify-max-iterations` 行が追加されている
- <!-- verify: file_contains "docs/guide/customization.md" "verify-max-iterations" --> `docs/guide/customization.md` に `verify-max-iterations` 設定の説明が追加されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "verify-iteration" --> `skills/verify/SKILL.md` に iteration counter の読取・増分・上限チェックのロジックが追加されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "max iterations reached" --> 上限到達時のコメントテンプレート（例: "max iterations reached (N/N)"）が定義されている
- <!-- verify: grep "verify-iteration" "skills/verify/SKILL.md" --> counter 管理は `<!-- verify-iteration: N -->` Issue コメント marker 方式で行われる旨が明記されている（label を増やさない）
- <!-- verify: file_contains "skills/auto/SKILL.md" "max iterations" --> `skills/auto/SKILL.md` が max iterations 到達を検出したら `/code` の連鎖を停止する旨が記述されている
- <!-- verify: command "find tests -name '*max-iter*.bats' -o -name '*verify-iter*.bats' -type f | grep -q ." --> max_iterations 周りを検証する bats テストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 追加されたテストを含む全 bats テストが CI で PASS する

### Post-merge

- 実 Issue で意図的に verify FAIL を繰り返させ、counter が `<!-- verify-iteration: 1 -->` → `2` → `3` と進み、3 回目で reopen が停止することを確認 <!-- verify-type: opportunistic -->

## Notes

- `VERIFY_MAX_ITERATIONS` の値の扱い: `watchdog-timeout-seconds` と同様の integer パース（≤0、非数値、または >20 の場合は default 3 にフォールバック）
- NEXT_ITERATION >= VERIFY_MAX_ITERATIONS で停止する設計: NEXT_ITERATION=3、max=3 のとき停止 → 2 回 reopen 後、3 回目 verify FAIL で停止。カウンタ値 1→2→(3: max-reached コメント内)
- Issue OPEN path（auto-close 無効リポジトリ）でも同様の counter ロジックを適用すること
- `run-auto-sub.sh` は exit code ではなく出力内容で判断する LLM ではないため、max iterations 到達時に run-verify.sh が exit 0 を返すと run-auto-sub.sh は "成功" と判断する。XL route での sub-issue 処理中に max iterations に到達した場合の run-auto-sub.sh 対応は本 Issue のスコープ外（フォローアップ Issue で対応）
- pre-merge 検証項目が 8 件で SPEC_DEPTH=light の推奨上限（5件）を超えているが、Issue 本体の受け入れ条件から全て verbatim コピーのため維持する
- patch route のため `github_check "gh pr checks"` → `github_check "gh run list --workflow=test.yml ..."` に変換済み（PR が存在しないため）

## Code Retrospective

### Deviations from Design

- `skills/auto/SKILL.md` の変更対象として Spec には「patch/pr route の verify フェーズ結果判定に注記を追加」と記載されていたが、pr route の Step 10 記述も同様に更新した（Spec の記述は「Step 4」とまとめていたが、実際には patch route の Step 5 と pr route の Step 10 の両方に適用）。

### Design Gaps/Ambiguities

- `docs/ja/tech.md` は Spec の Changed Files リストに明示されていなかったが、`docs/tech.md` を更新したため `docs/ja/` ミラーの同期も必要と判断して追加実装した。

### Rework

- N/A
