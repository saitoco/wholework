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

## Code Retrospective

### Deviations from Design

- N/A（設計通りに実装）

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- 実装は Spec 通りで divergence なし。ただしレビューで `MUTATION_EXIT=$?` が jq 代入前に必要という点が発覚 — Spec の実装ステップに「mutation の exit code を `$?` で保持する前に jq を実行しない」旨の明示がなかった。LLM 実行向けの pseudo-bash としては意図が伝わるが、将来 shell script 化した場合に確実なバグになる。Spec の Implementation Steps に exit code 保持順序を明示する習慣が望ましい。

### Recurring Issues

- exit code 保持パターン（`MUTATION_EXIT=$?` を先に保存）は shell script への変換を見据えると共通ベストプラクティス。他のモジュールで同様のパターン（command substitution の直後に別コマンドを実行）がある場合は一括で確認する価値がある。

### Acceptance Criteria Verification Difficulty

- rubric / section_contains の verify command は全て PASS で判定容易だった。github_check も CI GREEN で問題なし。UNCERTAIN なし。verify command の質は良好。

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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC は rubric（挙動変更の意味検証）+ section_contains（warn 記述）+ github_check×2 の構成で UNCERTAIN なし。auto-resolved scope（fix #1 のみ、#2/#3 除外、Value は #457 へ）は妥当。

#### design
- root cause（mutation 成功は `projectV2Item.id` 返却で判定可能なのに read-back 不一致を失敗扱いしていた）を正確に特定。warn-only 再設計はクリーン。

#### code
- Spec 通り、deviation/rework なし。`MUTATION_EXIT=$?` を jq 代入前に保持する exit-code 順序はレビューで補正（#518 内で resolved）。

#### review
- light review が exit-code 保持順序（`MUTATION_EXIT=$?`）の必要性を検出し SHOULD として resolved、Important 注記更新を CONSIDER として resolved、regression tests を SHOULD skip。MUST なし。LLM 実行向け pseudo-bash の shell-script 化を見据えた良い指摘。

#### merge
- squash merge クリーン、CI 全 green、コンフリクトなし。

#### verify
- pre-merge 4/4 PASS（rubric=実装確認 / section_contains=warn / github_check×2）。
- **#517 fix の実 pr-route dogfooding 確認**: 条件3/4 の `github_check "gh pr checks"` が、verify worktree ブランチ（PR 非紐づけ）上で #517 の PR number injection により `gh pr checks 524` に書き換わり、ジョブ名 `Run bats tests` / `Validate skill syntax` で正しく PASS 判定。これは #517（PR number injection）の post-merge opportunistic 条件「pr route Issue で merge 後に /verify を実行し gh pr checks ヒントが merged PR を参照して PASS する」を実環境で初めて確認したもの。
- post-merge opportunistic 条件（eventual-consistency 遅延時の冗長ラベルフォールバック抑止）は遅延再現が必要なため未チェック・phase/verify 維持。

### Improvement Proposals

- N/A — exit-code 保持順序（`MUTATION_EXIT=$?` を command substitution の直後に保持）の観察は #518 のレビューで当該コードについて resolved 済み。「他モジュールへの横断 sweep」は投機的で現時点で具体的欠陥が未確認のため、backlog noise 削減方針（#484 の Improvement Proposal 三層判定）に照らし新規起票はしない。再発が観測された時点で起票する。
