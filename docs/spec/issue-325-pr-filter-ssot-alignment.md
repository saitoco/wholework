# Issue #325: run-auto-sub/run-code: PR 番号抽出フィルタが #310 の新 SSoT worktree-code+issue-N に追従していない

## Overview

2026-04-21 に #310（worktree 命名 SSoT 確立）と #311（glob→client-side filter 修正）がほぼ同時にマージされ、意味的衝突が発生した。#310 で確立した SSoT ブランチ名は `worktree-code+issue-N`（trailing dash なし）だが、#311 が導入した `contains("issue-N-")` フィルタは旧命名の trailing dash を前提にしており、新 SSoT 名にマッチしない。

この不整合により #313 で `/auto` pr route の PR 番号抽出が失敗する regression が発生した。修正は #310 SSoT への完全一致（`== "worktree-code+issue-N"`）に切り替え、既存 regression test を jq filter の実際の動作を検証する形に強化する。

**実装上の選択**: `gh --jq` フラグではなく `| jq -r` パイプ形式に変更する。理由: bats mock の `gh` スクリプトが jq を内部実行せずに JSON を返すだけで済み、実際の jq バイナリがフィルタを処理するため、filter のパターンマッチング挙動を確実に検証できる。`jq` は既存スクリプト（`scripts/gh-pr-merge-status.sh:47-48` 等）で広く使用済み。

## Changed Files

- `scripts/run-auto-sub.sh`: line 122, 142 の PR 番号抽出を `| jq -r "... == worktree-code+issue-N"` に変更 — bash 3.2+ compatible
- `scripts/run-code.sh`: line 78 の idempotency guard を同様に変更 — bash 3.2+ compatible
- `skills/auto/SKILL.md`: line 165 の instruction text を exact-match 形式に更新
- `tests/run-auto-sub.bats`: setup() default mock + `#311 regression` test (line 238) を強化
- `tests/run-code.bats`: idempotency guard テスト 221, 253, 280 の pr list mock を JSON 形式に更新

## Implementation Steps

1. `scripts/run-auto-sub.sh:122,142` のフィルタを変更する (→ 受け入れ条件 1〜3)
   - 変更前: `gh pr list --json number,headRefName --jq ".[] | select(.headRefName | contains(\"issue-${SUB_NUMBER}-\")) | .number" 2>/dev/null | head -1 || true`
   - 変更後: `gh pr list --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${SUB_NUMBER}\") | .number" | head -1 || true`
   - line 122 と line 142 の両方（Size M case と Size L case）を変更する

2. `scripts/run-code.sh:78` の EXISTING_PR idempotency guard を変更する (→ 受け入れ条件 1〜3, after 1)
   - 変更前: `gh pr list --state open --json number,headRefName --jq ".[] | select(.headRefName | contains(\"issue-${ISSUE_NUMBER}-\")) | .number" 2>/dev/null | head -1 || true`
   - 変更後: `gh pr list --state open --json number,headRefName 2>/dev/null | jq -r ".[] | select(.headRefName == \"worktree-code+issue-${ISSUE_NUMBER}\") | .number" | head -1 || true`

3. `skills/auto/SKILL.md:165` の instruction text を更新する (→ 受け入れ条件 1〜2, parallel with 1, 2)
   - 変更前: `Extract PR number via client-side filter (handles worktree branch names like \`worktree-issue-*\`): \`gh pr list --json number,headRefName --jq ".[] | select(.headRefName | contains(\"issue-$NUMBER-\")) | .number" | head -1\``
   - 変更後: `Extract PR number via exact-match filter (matches SSoT branch name worktree-code+issue-N established by #310): \`gh pr list --json number,headRefName | jq -r ".[] | select(.headRefName == \"worktree-code+issue-$NUMBER\") | .number" | head -1\``

4. `tests/run-auto-sub.bats` を強化する (→ 受け入れ条件 4〜5, after 1, 2)
   - setup() の gh mock（line ~97-99）: `gh pr list` の `echo "99"` を JSON `echo '[{"headRefName":"worktree-code+issue-42","number":99}]'` に変更
   - `#311 regression` test (line ~238): mock を `[{"headRefName":"worktree-code+issue-42","number":99}]` を返す形に書き換え; `--head` チェックと固定値 "99" チェックは削除し、PR 99 が review/merge に伝播されること（= jq filter が `worktree-code+issue-42` に実際にマッチしたこと）を assertion として残す

5. `tests/run-code.bats` の idempotency guard mock を更新する (→ 受け入れ条件 6, after 2)
   - test 221 (existing PR detected): mock の `echo "456"` を `echo '[{"headRefName":"worktree-code+issue-123","number":456}]'` に変更（guard が正しく発動することを確認）
   - test 253 (--patch skips guard), test 280 (no route skips guard): 同様に JSON 形式に更新（guard は発動しないが mock を一貫させるため）

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh, scripts/run-code.sh, and skills/auto/SKILL.md all extract PR numbers by matching the exact branch name worktree-code+issue-N (the SSoT established in #310), not via loose substring matches like contains('issue-N-') that assume the pre-#310 pr route naming." --> 3 ファイルすべてで PR 番号抽出が #310 の SSoT `worktree-code+issue-N` への完全一致に揃っている
- <!-- verify: file_not_contains "skills/auto/SKILL.md" "contains(\\\"issue-" --> `skills/auto/SKILL.md` から旧 substring match 形式 `contains("issue-N-")` が除去されている
- <!-- verify: file_not_contains "scripts/run-auto-sub.sh" "contains(\\\"issue-" --> `scripts/run-auto-sub.sh` から旧 substring match 形式が除去されている
- <!-- verify: file_not_contains "scripts/run-code.sh" "contains(\\\"issue-" --> `scripts/run-code.sh` から旧 substring match 形式が除去されている
- <!-- verify: rubric "tests/run-auto-sub.bats has a regression test whose gh mock returns a JSON array containing the branch name worktree-code+issue-N (not a fixed stdout value), and the test asserts that PR number extraction succeeds specifically because the jq filter matches that branch name. Simply asserting that --json number,headRefName was passed to gh is insufficient — the test must exercise the jq filter's pattern-matching behavior." --> `tests/run-auto-sub.bats` の regression テストが、固定値ではなく `worktree-code+issue-${N}` を含む JSON を返す mock を使い、jq filter が実際に当該ブランチをマッチさせて PR 番号を抽出することを検証している
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `run-auto-sub.bats` 全テスト PASS
- <!-- verify: command "bats tests/run-code.bats" --> `run-code.bats` 全テスト PASS

### Post-merge

- 実際に pr route で `/auto N` を実行し、`worktree-code+issue-N` ブランチで PR 番号抽出が成功することを確認

## Notes

- `--jq` から `| jq -r` パイプ形式への変更は、bats テストの testability 向上のための設計判断（Auto-Resolved: Issue body は `--jq` 形式を示していたが、mock gh が jq を内部実行しないため実際のフィルタ挙動を検証できない。パイプ形式なら mock が JSON を返すだけで実 jq バイナリが動作するため、より確実な検証が可能。）
- 旧命名 `worktree-issue-${N}-<short-description>` や `worktree-patch+issue-${N}` 等の旧形式への対応は追加しない（#310 の SSoT で廃止済み）
- `tests/run-auto-sub.bats` setup() の default mock 変更は、tests 165 (Size M), 174 (Size L), 231 (--base flag) が PR 番号抽出を正しく完了するために必要
- tests 253, 280 は `--patch` / no-route で guard が発動しないため mock 更新はテスト通過に不要だが、一貫性のため更新する

## Code Retrospective

### Deviations from Design

- `tests/run-auto-sub.bats` test 11 "phase/ready absent: run-spec.sh is called" も `echo "99"` を返す gh mock を持っており、JSON 形式への更新が必要だった。Spec では setup() default mock と `#311 regression` test のみ言及していたが、test 11 の独立 mock も同様に更新した。

### Design Gaps/Ambiguities

- Spec の「テスト強化」箇所に `tests/run-auto-sub.bats:238` と setup() のみ記載されていたが、同ファイル内のオーバーライド mock を持つ test 11 も影響を受けることが実装時に判明した。Spec に test 11 の mock 更新を追記しておくべきだった。

### Rework

- test 11 の mock 修正: 最初のテスト実行で test 11 が FAIL となり、1 回の修正（mock を JSON 形式に変更）で解決。

## review retrospective

### Spec vs. implementation divergence patterns

特筆事項なし。実装は Spec の変更対象を全て網羅しており、逸脱（test 11 の mock 追加）は Code Retrospective セクションに正直に記録済み。Spec に test 11 のオーバーライド mock への言及がなかった点は `## Design Gaps/Ambiguities` で既に捕捉されている。

### Recurring issues

特筆事項なし。単発の issue であり、パターン的な繰り返しは見られない。

### Acceptance criteria verification difficulty

全条件 PASS。`bats` の `command` 型 verify は safe モードで CI reference fallback を使用しており問題なく解決できた。1 件の CONSIDER レベル指摘（negative test の欠如）あり。テスト内の positive case のみでの検証は今後の Issue で繰り返し発生しやすいパターンのため、verify rubric で「negative case の有無」を明示的に問うことを検討してもよい。
