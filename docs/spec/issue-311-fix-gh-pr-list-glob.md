# Issue #311: auto/code: gh pr list --head の glob 非対応により PR 番号抽出が失敗

## Overview

`gh pr list --head "<pattern>"` は glob / ワイルドカードをサポートせず exact match のみ解釈する。`"*issue-N-*"` 形式で PR 番号抽出を試みている 4 箇所（`scripts/run-auto-sub.sh` 2 箇所 / `scripts/run-code.sh` 1 箇所 / `skills/auto/SKILL.md` 1 箇所）は実際のブランチ名 `worktree-issue-N-{short-title}` にマッチせず空配列を返す。Approach B（client-side filter）へ書き換え、regression テストを追加する。

## Reproduction Steps

```bash
gh pr list --head "*issue-308-*" --json number --jq '.'
# → []  (glob not supported; exact match only)

gh pr list --json number,headRefName \
  --jq '.[] | select(.headRefName | contains("issue-308-")) | .number' | head -1
# → 309 (client-side filter; works)
```

`#308` の `/auto --batch` 実行時、`run-code.sh --pr` は PR #309 作成に成功したが、その後の `run-auto-sub.sh` の glob マッチが空配列を返し `Error: Could not retrieve PR number for issue #308` で exit 1。review/merge/verify を手動継続した。

## Root Cause

`gh pr list --head <pattern>` は内部で GitHub API の `head` フィルタへ exact match として渡される。docs/CLI ヘルプともに glob/ワイルドカードをサポートする記述はなく、`*issue-N-*` は文字列リテラル `*issue-N-*` として解釈されるためマッチしない。`#6` (2025-10) の Auto Retrospective で既知だったが放置され、`#308` (2026-04-21) で再発した。

修正方針: **Approach B（client-side filter）** を採用。`--json number,headRefName` で全 open PR 取得後、jq で `contains("issue-N-")` フィルタを適用する。

- Approach A (`--search "head:issue-N"`) は `worktree-issue-N-*` 形式への対応が不透明なため見送り
- Approach B は repo 全体の open PR を取得するため僅かに遅いが、実用上問題なし。確実にマッチする

## Changed Files

- `scripts/run-auto-sub.sh`: Size M (line 122) と Size L (line 142) の `gh pr list --head "*issue-${SUB_NUMBER}-*" --json number -q '.[0].number'` を `gh pr list --json number,headRefName --jq ".[] | select(.headRefName | contains(\"issue-${SUB_NUMBER}-\")) | .number" | head -1` に書き換え — bash 3.2+ 互換
- `scripts/run-code.sh`: line 78 の `EXISTING_PR` 抽出で同じパターン変換（`--state open` フラグは保持） — bash 3.2+ 互換
- `skills/auto/SKILL.md`: line 165 の指示文字列を Approach B に書き換え、注釈 `(also handles worktree branch names like worktree-issue-*)` は「client-side filter により worktree branch names も含めてマッチする」旨に更新
- `tests/run-auto-sub.bats`: regression テスト 1 件追加（`worktree-issue-N-{short-title}` 形式ブランチ名で PR 抽出成功を確認、gh args ログで glob pattern 不使用と新形式採用を検証）
- `tests/run-code.bats`: 既存 idempotency guard テスト群（213/221/253/280 行付近）が新実装下で PASS することを確認。既存 mock は `gh pr list` を flag 非依存で echo するだけなので mock 更新不要（必要に応じて `--json number,headRefName` 対応を追記）

## Implementation Steps

1. `scripts/run-auto-sub.sh` の line 122 (Size M case) と line 142 (Size L case) の `gh pr list` 行を Approach B に書き換え（→ AC1, AC4）
2. `scripts/run-code.sh` の line 78 の `EXISTING_PR` 抽出ロジックを同じ Approach B に書き換え、`--state open` を保持（→ AC2, AC4）
3. `skills/auto/SKILL.md` line 165 の PR 抽出指示文字列を Approach B の client-side filter 形式に書き換え（→ AC3, AC4）
4. `tests/run-auto-sub.bats` に regression テスト `@test "PR extraction: uses client-side headRefName filter (#311 regression)"` を追加。mock gh で args をログ取得、`--head "*issue-*"` glob 形式が使われていないこと + `--json number,headRefName` 形式で呼び出されていることを assert（→ AC5, AC6）
5. `bats tests/run-auto-sub.bats` と `bats tests/run-code.bats` をローカル実行し、全テスト PASS を確認（→ AC6, AC7）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "--head \"*issue-" --> `run-auto-sub.sh` から glob 形式 `--head "*issue-*"` が除去されている
- <!-- verify: file_not_contains "scripts/run-code.sh" "--head \"*issue-" --> `run-code.sh` から同形式が除去されている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "--head \"*issue-" --> `skills/auto/SKILL.md` から同形式が除去されている
- <!-- verify: rubric "scripts/run-auto-sub.sh, scripts/run-code.sh, and skills/auto/SKILL.md all describe PR number extraction via client-side filtering on headRefName (e.g., `gh pr list --json number,headRefName --jq` with a `contains(\"issue-N-\")` filter or equivalent), not via the non-functional glob pattern on --head" --> 3 ファイルすべてで PR 番号抽出が client-side filter 方式に切り替わっている（scripts 2 箇所 + SKILL.md 1 箇所）
- <!-- verify: rubric "tests/run-auto-sub.bats contains at least one test case that verifies PR number extraction succeeds when the branch name follows the worktree-issue-N-{short-title} format" --> `worktree-issue-N-{short-title}` 形式ブランチ名で PR 抽出成功を確認する regression テストが `tests/run-auto-sub.bats` に存在する
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `run-auto-sub.bats` 全テストが PASS する
- <!-- verify: command "bats tests/run-code.bats" --> `run-code.bats` の既存 idempotency guard テスト群が新実装下で PASS する

### Post-merge

- 実際の XL Issue または M/L Issue で `/auto` を実行し、`worktree-issue-N-{short-title}` 形式のブランチ名で PR 抽出が成功することを確認

## Notes

- **Approach B 採用理由**: Approach A (`--search "head:issue-N"`) は gh/GitHub Search API の先頭語一致仕様で `worktree-issue-N-*` 形式へのマッチが不透明。Approach B は全 open PR を取得するコスト（通常は数 PR 程度）と引き換えに確実性を得る。`| head -1` で複数マッチ時の最初の 1 件に限定
- **bash 3.2+ 互換性**: 変更する 2 ファイル (`run-auto-sub.sh` / `run-code.sh`) は既存の `$(...)` コマンド置換とパイプのみで、macOS system bash (3.2) でも動作する
- **既存 mock 影響評価**: `tests/run-code.bats` の gh mock (line 51-64) は `pr list` に対して flag 非依存で echo（default 空 or override で "456"）するため、Approach B の `--json number,headRefName --jq "..."` 形式で呼び出しても動作変わらず。`tests/run-auto-sub.bats` の gh mock (line 82-104) も同様。既存テスト群の mock 更新は不要
- **regression テストの設計**: 既存 mock が permissive すぎて bug (`--head "*issue-*"` の glob 非対応) を検知できなかった。新テストでは gh args をログ取得し「glob pattern は使われていない」「client-side filter 形式で呼ばれている」を両側 assert することで、将来の regression を検知可能にする
- **auto-resolved ambiguity points**（`/issue` 時点で記録済み）: `tests/run-code.bats` の更新範囲 / rubric の SKILL.md 取り込み / 発生履歴の line number 修正 の 3 件は Issue body の retrospective コメントに記録済み
