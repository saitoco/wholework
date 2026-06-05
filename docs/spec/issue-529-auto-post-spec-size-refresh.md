# Issue #529: auto: spec phase 後に Size を no-cache 再取得し route/review 深度を再判定

## Overview

`/auto` Step 2 で取得した Size はGraphQL レスポンスキャッシュを使用するため、spec phase が Size を更新した場合（例: M→L 再評価）に stale になる。spec phase 成功後・code phase 開始前に `get-issue-size.sh --no-cache` で最新 Size を再取得し、route（patch/pr）と review 深度（`--light`/`--full`）を再判定する `### Step 3a: Post-Spec Size Refresh` を `skills/auto/SKILL.md` に追加する。

ユーザが `--patch`/`--pr`/`--review=...` を明示指定した場合は既存のフラグ優先挙動を維持する。XS は spec をスキップするため対象外。

## Changed Files

- `skills/auto/SKILL.md`: `### Step 3a: Post-Spec Size Refresh` セクションを Step 3 と Step 4 の間に追加（bash 3.2+ 互換、変更なし）

## Implementation Steps

1. `skills/auto/SKILL.md` の `### Step 3:` セクションと `### Step 4:` セクションの間に `### Step 3a: Post-Spec Size Refresh` セクションを追加する（→ AC1, AC2）

   追加内容:
   ```
   ### Step 3a: Post-Spec Size Refresh

   **Run only when** `run-spec.sh` was called and succeeded in Step 3 (i.e., spec was executed — not when `phase/ready` was already set at Step 3 entry, and not when Size was XS which skips spec). Also skip if `--patch`, `--pr`, or `--review=...` flag is present in ARGUMENTS (preserve explicit-flag priority behavior).

   Re-fetch Size to detect updates made by the spec phase:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache "$NUMBER" 2>/dev/null
   ```

   Update ROUTE and REVIEW_DEPTH based on the refreshed Size:

   | Refreshed Size | Route | Review depth |
   |---|---|---|
   | XS or S | patch | — |
   | M | pr | --light |
   | L | pr | --full |
   | XL | sub_issue | — |
   | unset | pr | (safe fallback) |

   If route changed from Step 2, output a log line: "Post-spec Size refresh: Size updated to {NEW_SIZE}, route re-determined as {NEW_ROUTE}." Proceed to Step 4 using the updated ROUTE and REVIEW_DEPTH.
   ```

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/auto/SKILL.md" "--no-cache" --> `skills/auto/SKILL.md` に、spec phase 成功後に Size を `--no-cache` で再取得する記述が追加されている
- <!-- verify: rubric "skills/auto/SKILL.md に、spec phase 成功後・code phase 開始前に get-issue-size.sh を --no-cache で再取得し、その最新 Size から route（patch/pr）と review 深度（light/full）を再判定する記述がある。XS は spec スキップで対象外、ユーザが --patch/--pr/--review を明示指定した場合は再判定で上書きしない旨も読み取れる" --> spec 後の Size 再取得と route / review 深度の再判定が SKILL.md に記述されている

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --branch main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> マージ後、main 上の CI（test.yml: bats / skill syntax 検証）が success になる <!-- verify-type: auto -->
- spec phase で Size が変化する Issue に対し `/auto N` を実行し、変化後の Size に応じた review 深度（例: M→L なら `--full`）および route が自動選択されることを実運用で確認する <!-- verify-type: manual -->

## Notes

- `get-issue-size.sh --no-cache` は既存サポート済み（Usage: `scripts/get-issue-size.sh [--no-cache] <issue-number>`）。新規スクリプト追加なし
- Step 3a の実行条件: run-spec.sh が Step 3 で実際に呼ばれた場合のみ。`phase/ready` が Step 3 入室時に既にあった場合（spec スキップ）はスキップ
- XL route は sub-issue graph で各 sub-issue の route を独立管理するため、本 Step 3a は XL sub-issue の route 変更には影響しない（`run-auto-sub.sh` 管理外）
- ユーザが `--patch`/`--pr`/`--review=...` を明示指定した場合は再判定で上書きしない既存の優先挙動を維持

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Step 3a を Step 3 と Step 4 の間に挿入（Spec の実装計画通り）
- XL route は `run-auto-sub.sh` 管理下のため本 step では扱わないことを明示した
- `--patch`/`--pr`/`--review=...` の明示指定時は再判定しない条件も明記

### Deferred Items
- 実運用での動作確認（post-merge manual AC）は verify phase に委譲

### Notes for Next Phase
- AC1（`file_contains "--no-cache"`）・AC2（`rubric`）ともに pre-merge で PASS 済み
- CI（test.yml）の success 確認は main マージ後に verify phase で実施

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 品質は良好。`file_contains` + `rubric` のペアで pre-merge を機械検証可能にし、スコープ節で XS / フラグ明示 / `--batch` の除外を明確化。Step 3a の挿入位置（Step 3 と Step 4 の間）も適切に特定されていた。

#### design
- 設計は実装と乖離なし。`get-issue-size.sh --no-cache` の既存サポートを再利用し新規スクリプト追加を回避した点は妥当。
- 軽微: Step 3a が `REVIEW_DEPTH` 変数を更新する一方、Step 4 の review 呼び出し（line 220）は依然として Size から再導出（`M→--light, L→--full`）しており、変数の配線がやや冗長。

#### code
- rework なし。design 通り単一ファイル（`skills/auto/SKILL.md`）への patch で完結。patch route で main 直コミット。

#### review
- N/A（Size S・patch route のため review phase なし）。

#### merge
- N/A（patch route 直コミット。コンフリクトなし）。

#### verify
- auto 検証対象（AC1 / AC2 / AC3）全 PASS。AC3 は patch route 非互換の `gh pr checks` を `/issue` リファイン時に `gh run list` 形式へ修正済みで、verify command の route 整合性に問題なし。AC4（manual・実運用確認）は runtime 依存のため未チェックで `phase/verify` 保留。

### Improvement Proposals
- （低優先）Step 4 の review 深度選択（line 220）が Step 3a で再判定した値ではなく Size から再導出している。Step 3a の refresh 済み値を明示参照する形にすると、将来 Step 2 の stale Size に起因する回帰を構造的に防げる。LLM ナラティブ上は Step 3a が Step 4 直前で Size を更新するため現状でも正しく流れるため、優先度は低い。
