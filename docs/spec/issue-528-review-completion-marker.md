# Issue #528: reconcile-phase-state: review 完了署名のローカライズ分散による /auto false-negative を解消

## Overview

`/auto` の review phase で「wrapper は exit 1 だが review 自体は実質成功」という false-negative が発生する。原因は review 完了の機械検出が見出しテキスト（ローカライズ対象）に依存していること。

採用方針は **言語非依存の機械可読マーカー方式**（Issue でユーザー確認済み・合意トークン `review-summary`）:
- `skills/review/SKILL.md` のサマリテンプレートにマーカー `<!-- review-summary -->` を埋め込む
- `scripts/reconcile-phase-state.sh` がそのマーカーを検出して review 完了を判定
- 既存の見出しテキスト署名（`## Review Response Summary` / `## レビュー回答サマリ`）は後方互換 fallback として保持

既存の `<!-- phase: -->`（`modules/phase-handoff.md`）/ `<!-- verify-iteration: N -->`（`scripts/get-verify-iteration.sh`）と同じ確立済みの HTML コメントマーカー検出パターンに揃える。

## Reproduction Steps

1. `/auto N` を実行し review phase に到達
2. review LLM が要約コメントを日本語慣習でローカライズして投稿（実際の見出し例: `## レビューレスポンスサマリー`）
3. `scripts/reconcile-phase-state.sh review N --pr P --check-completion` が呼ばれる
4. `_completion_review()` の grep（`## Review Response Summary|## レビュー回答サマリ`）が `## レビューレスポンスサマリー` にマッチせず `matches_expected:false` を返す
5. CI 全 PASS・サマリ投稿済・MUST なしで実質完了しているのに、`/auto` 親が不要な recovery 判断を強いられる

## Root Cause

`scripts/reconcile-phase-state.sh:250` の `_completion_review()` と `modules/phase-state.md:40`（SSoT）が認識する成功署名が `## Review Response Summary` と `## レビュー回答サマリ` の 2 種に固定されており、`skills/review/SKILL.md:671` が規定する英語見出しを review LLM が和文ローカライズした変種（`## レビューレスポンスサマリー` 等）を含まない。見出しテキストはローカライズで揺れるため、テキスト署名による完了検出は構造的に脆弱。修正は完了シグナルを見出しテキストから言語非依存の機械可読マーカーへ移すことが妥当。

## Changed Files

- `skills/review/SKILL.md`: Step 14.1 のサマリテンプレート見出し直下にマーカー行 `<!-- review-summary -->` を追加し、ローカライズ時もマーカーを逐語保持する旨の注記を追記
- `scripts/reconcile-phase-state.sh`: `_completion_review()` の grep パターンにマーカー検出を追加（既存 2 署名は fallback として保持）— bash 3.2+ compatible
- `modules/phase-state.md`: review row の Success Signature をマーカー方式に更新（SSoT、既存テキスト署名は fallback として併記）
- `tests/reconcile-phase-state.bats`: 「localized 見出し + マーカー → matches_expected true」の回帰テストを追加

## Implementation Steps

1. `skills/review/SKILL.md` の Step 14.1 サマリテンプレート（` ```markdown ` フェンス内、`## Review Response Summary` 見出し直下）にマーカー行 `<!-- review-summary -->` を追加。テンプレート直後に「マーカー行は見出しをローカライズしても逐語的に必ず含める。`reconcile-phase-state.sh` がこの言語非依存マーカーで review 完了を検出する」旨の注記を追記（プロース内のマーカーは inline code バッククォートで囲む）（→ 受入条件 1, 2）
2. `scripts/reconcile-phase-state.sh` の `_completion_review()` の grep パターンにマーカー検出を追加。既存 2 署名は fallback として保持 — bash 3.2+ compatible（→ 受入条件 1, 3, 6）
3. `modules/phase-state.md` の review row の Success Signature をマーカー方式に更新（SSoT）。既存テキスト署名を fallback として併記し、Step 2 の reconcile 実装と整合させる（→ 受入条件 4, 5）
4. `tests/reconcile-phase-state.bats` の `# --- review completion ---` ブロックに回帰テストを追加: gh mock が `## レビューレスポンスサマリー` + `<!-- review-summary -->` を出力し、`matches_expected:true` を検証（→ 受入条件 7, 8）

## Verification

### Pre-merge

- <!-- verify: rubric "review 完了の機械検出が要約見出しのローカライズ（和文/英文/任意の翻訳変種）に依存せず、言語非依存の機械可読マーカーで動作する。review SKILL.md がサマリテンプレートにマーカーを埋め込み、reconcile-phase-state.sh がそのマーカーを検出する方式である" --> review 完了検出がローカライズ非依存のマーカー方式になっている
- <!-- verify: file_contains "skills/review/SKILL.md" "review-summary" --> review SKILL.md のサマリテンプレートにマーカー `review-summary` が埋め込まれている（rubric 補足・機械検証）
- <!-- verify: file_contains "scripts/reconcile-phase-state.sh" "review-summary" --> reconcile-phase-state.sh の review completion 検出がマーカー `review-summary` を参照している（rubric 補足・機械検証）
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の review completion 検出ロジックと modules/phase-state.md の review success signature 定義が整合している（SSoT 維持）。両者ともマーカー方式を記述している" --> reconcile と phase-state の署名定義が整合している
- <!-- verify: file_contains "modules/phase-state.md" "review-summary" --> phase-state.md の review success signature 定義がマーカー `review-summary` を記述している（SSoT 補足・機械検証）
- <!-- verify: file_contains "scripts/reconcile-phase-state.sh" "Review Response Summary" --> 既存テキスト署名が後方互換 fallback として保持されている
- <!-- verify: file_contains "tests/reconcile-phase-state.bats" "review-summary" --> reconcile の review completion bats テストにマーカー検出ケースが追加されている（behavior test）
- <!-- verify: github_check "gh pr checks --json name,state --jq '[.[] | select(.name | test(\"bats\"; \"i\")) | .state] | unique | join(\",\")'" "SUCCESS" --> bats テスト CI が SUCCESS

### Post-merge

- 次回以降の `/auto` の review phase で、日本語ローカライズされたサマリ見出しが投稿されても reconcile が `matches_expected:true` を返し、false-negative recovery が発生しないことを実運用で確認する

## Notes

- **grep パターン**: Step 2 のマーカー検出は `grep -qE` に `<!--[[:space:]]*review-summary[[:space:]]*-->` を OR 追加する想定（POSIX `[[:space:]]` で内部空白の揺れを許容、bash 3.2 互換）。既存パターン `## Review Response Summary|## レビュー回答サマリ` は撤去せず保持。
- **bats テスト入力フォーマット**: `_completion_review()` は `gh pr view --pr P --json comments -q '.comments[].body'` の stdout を `grep` で検査する。既存テスト（line 287-329）に倣い、新規テストの gh mock はコメント body 行を `echo` で出力する。回帰テストは見出し行 `## レビューレスポンスサマリー`（既存 2 署名に非マッチな変種）+ マーカー行 `<!-- review-summary -->` を出力し、マーカーのみで `matches_expected:true` になることを検証する。
- **Forbidden Expressions 回避**: `skills/review/SKILL.md` のマーカー（`<!--` に半角 `!` を含む）は、テンプレートの ` ```markdown ` コードフェンス内、および注記プロースでは inline code バッククォートで囲んで記述する（半角 `!` の禁止はコードフェンス・inline code 外のみ対象）。
- **スコープ = review phase のみ**（Issue 自動解決済み）: reconcile-phase-state.sh の他フェーズ（issue/spec/code-patch/code-pr/merge/verify）の成功署名はラベル・git state・PR state・英語 gh キーワードで検出しており、ローカライズ脆弱なのは review の見出しのみ。汎用化は対象外。
- **マーカー欠落リスク**: review LLM がマーカーを出力しないケースは、保持した既存テキスト署名 fallback が受ける（defense-in-depth）。
