# Issue #518: project-field-update: verify-after-write の Projects V2 eventual-consistency 誤フォールバックを解消

## Overview

`modules/project-field-update.md` の Size 用 verify-after-write が、`updateProjectV2ItemFieldValue` mutation が成功（exit 0 かつ `projectV2Item.id` 返却）しているにも関わらず、Projects V2 の eventual-consistency による読み戻し不一致を「書き込み失敗」と誤判定して `size/*` ラベルへ不要にフォールバックする。

fix #1（本 Issue のスコープ）: mutation の成功（exit 0 かつ `projectV2Item.id` 返却）を一次の書き込み成功判定とし、読み戻し不一致は warn-only（eventual-consistency 監視）に留め、ラベルフォールバックは mutation 自体が error のときのみ実行する方式へ変更する。

## Reproduction Steps

1. Projects V2 Size フィールドが設定された GitHub リポジトリで `/triage` または `/issue` を実行する
2. `updateProjectV2ItemFieldValue` mutation が exit 0 で成功し `projectV2Item.id` が返る
3. GitHub Projects V2 の eventual-consistency により、読み戻し（`get-issue-size.sh --no-cache`）がまだ反映されていない
4. verify-after-write のリトライ（最大 3 回、合計 ~6s）で全て不一致
5. ラベルフォールバックが実行される → フィールド設定成功 + `size/*` ラベル冗長付与

## Root Cause

`modules/project-field-update.md` の "Verify-after-write (for Size field)" が、読み戻し（`get-issue-size.sh --no-cache`）の不一致を mutation 失敗として扱い、3 回リトライ後にラベルフォールバックを実行する設計になっている。しかし mutation 自体の成功/失敗は `projectV2Item.id` の返却で判断できる。読み戻し不一致の実際の原因は Projects V2 の eventual-consistency であり、mutation が成功していてもラベルフォールバックが発火する。

## Changed Files

- `modules/project-field-update.md`: Step 4 を mutation 出力をキャプチャして `projectV2Item.id` を確認するように変更、Verify-after-write セクションを warn-only 監視（ラベルフォールバックなし）に変更

## Implementation Steps

1. `modules/project-field-update.md` の Step 4 を変更する: 現在の `gh-graphql.sh --query update-field-value ...` 呼び出しを、出力をキャプチャして `projectV2Item.id` の存在を確認する形に変更する。mutation 出力を変数に格納し、`.data.updateProjectV2ItemFieldValue.projectV2Item.id` の値を `jq` で抽出する。exit code が非 0 か返却 ID が empty の場合は mutation 失敗として Step 5（ラベルフォールバック）へ進み、exit code 0 かつ返却 ID が non-empty の場合はフィールド書き込み成功とみなして warn-only read-back へ進む。（→ AC #1）

2. `modules/project-field-update.md` の "Verify-after-write (for Size field)" セクションを変更する: セクションの目的を「warn-only eventual-consistency monitoring」として明示し、読み戻し不一致は warn を出力するに留め、リトライ全失敗後も「mutation confirmed だが read-back mismatch — probable eventual-consistency delay、ラベルフォールバックなし」という warning を出力するに変更する。セクション末尾の「3 回とも不一致ならラベルフォールバック」の記述を削除する。（→ AC #1, AC #2）

## Verification

### Pre-merge

- <!-- verify: rubric "modules/project-field-update.md の Size 用 verify-after-write が、updateProjectV2ItemFieldValue mutation の成功（exit 0 かつ projectV2Item.id 返却）を一次の書き込み成功判定とし、読み戻し（get-issue-size.sh --no-cache）の不一致/空は warning に留めて即ラベルフォールバックせず、ラベルフォールバックは mutation 自体が error のときのみ実行する方式に変更されている" --> mutation 成功を一次判定とし、読み戻し不一致は warn どまりでラベルフォールバックしない方式になっている
- <!-- verify: section_contains "modules/project-field-update.md" "Verify-after-write" "warn" --> Verify-after-write セクションに warning（warn）の記述がある
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の bats テストが green（既存テストにリグレッションがない）
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> CI の skill 構文検証が green

### Post-merge

- merge 後に `/triage` または `/issue` で Size を設定し、Projects V2 Size フィールドが正しく設定され、eventual-consistency 遅延時にも `size/*` ラベルへ冗長フォールバックしないことを実運用で確認 <!-- verify-type: opportunistic -->

## Notes

### Step 4 の変更詳細

`jq -r '.data.updateProjectV2ItemFieldValue.projectV2Item.id // empty'` で ID を抽出する。`gh-graphql.sh` の `--jq` フラグを使って直接取得する方法も使用できる（`--jq '.data.updateProjectV2ItemFieldValue.projectV2Item.id // empty'`）。どちらの形式でも実装可。

### verify-after-write セクションの変更詳細

変更後のフロー:
1. `get-issue-size.sh --no-cache $NUMBER` で読み戻し
2. 一致 → monitoring 完了
3. 不一致/空 → warn を出力してリトライループへ（3 回: 1s, 2s, 3s 待機）
4. 3 回とも不一致 → 「Size フィールド書き込みは mutation 確認済み、読み戻し不一致は probable eventual-consistency delay、ラベルフォールバックなし」の warning を出力して処理完了
5. ラベルフォールバックは一切実行しない

`section_contains "modules/project-field-update.md" "Verify-after-write" "warn"` が PASS するよう、セクション内に "warn" という文字列を含む記述を明示的に入れる（例: "output a warn"、"warn and continue" 等）。

### 影響範囲

- `skills/triage/SKILL.md`、`skills/issue/SKILL.md` は「Complete on GraphQL success; only execute Step 5 label fallback on failure」の記述のままで意味的に整合する。変更不要。
- bats テスト変更なし（module の LLM 実行ステップ変更のみで shell script 変更なし）。
