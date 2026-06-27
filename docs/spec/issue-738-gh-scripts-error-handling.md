# Issue #738: scripts/gh-*.sh: unify explicit error handling for API failures

## Overview

`scripts/gh-*.sh` 8 個のうち 4 個 (`gh-check-blocking.sh`, `gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-extract-issue-from-pr.sh`) は既に明示的 error handling (exit code チェック + stderr メッセージ + non-zero exit) を持つ。残る 4 個 (`gh-graphql.sh`, `gh-label-transition.sh`, `gh-pr-merge-status.sh`, `gh-pr-review.sh`) は `set -euo pipefail` のみで、GitHub API 失敗時に stderr へ識別可能なメッセージを出力しない。本 Issue はこれら 4 個に明示的 error handling を追加し、API failure を発見可能にする。

## Changed Files

- `scripts/gh-pr-merge-status.sh`: `gh pr view` 呼び出し (line 45) に `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `scripts/gh-label-transition.sh`: `gh issue edit` 3 呼び出し (lines 68, 90, 92) を `if ! ...; then echo "Error..." >&2; exit 1; fi` パターンに変更 — bash 3.2+ compatible
- `scripts/gh-graphql.sh`: `gh api graphql` 2 呼び出し (cache path line 274, no-cache path line 291) に `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `scripts/gh-pr-review.sh`: 2 箇所のパイプライン heredoc ブロック (lines 91-93, 120-130) を python3 出力を変数キャプチャ → `echo | gh api` へ分離リファクタ; `gh api` 呼び出しに `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `tests/gh-pr-merge-status.bats`: "error: gh pr view failure" テスト追加
- `tests/gh-label-transition.bats`: "error: gh issue edit failure" テスト追加
- `tests/gh-graphql.bats`: "error: gh api graphql failure" テスト追加
- `tests/gh-pr-review.bats`: "error: gh api POST failure" テスト追加

## Implementation Steps

1. `scripts/gh-pr-merge-status.sh` — `gh pr view` に error handling 追加 (→ AC1)
   - line 45: `JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus)` を
     `JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus) || { echo "Error: failed to fetch PR #$PR" >&2; exit 1; }` に変更

2. `scripts/gh-label-transition.sh` — `gh issue edit` 3 箇所に error handling 追加 (→ AC1)
   - line 68: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"` を `if ! gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"; then echo "Error: failed to update labels for issue #$ISSUE_NUMBER" >&2; exit 1; fi` に変更
   - line 90: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}" --add-label "phase/$TARGET_PHASE"` を同パターンに変更
   - line 92: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"` を同パターンに変更

3. `scripts/gh-graphql.sh` — `gh api graphql` 2 箇所に error handling 追加 (→ AC1)
   - cache path (line 274): `RAW_RESPONSE=$(gh api graphql "${GH_ARGS[@]}")` を `RAW_RESPONSE=$(gh api graphql "${GH_ARGS[@]}") || { echo "Error: gh api graphql failed" >&2; exit 1; }` に変更
   - no-cache path (line 291): `gh api graphql "${GH_ARGS[@]}"` を `gh api graphql "${GH_ARGS[@]}" || { echo "Error: gh api graphql failed" >&2; exit 1; }` に変更

4. `scripts/gh-pr-review.sh` — heredoc パイプライン 2 箇所をリファクタ + error handling 追加 (→ AC1, AC3)
   - `--with-line-comments` path (lines 91-93): python3 ... <<'PYEOF' | gh api ... を変数キャプチャ方式に変更:
     ```
     REVIEW_PAYLOAD=$(python3 - "$REVIEW_BODY_FILE" "$LINE_COMMENTS_FILE" "$EVENT" <<'PYEOF'
     ...python content (unchanged)...
     PYEOF
     )
     echo "$REVIEW_PAYLOAD" | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input - || {
         echo "Error: failed to post review for PR #$PR_NUMBER" >&2
         exit 1
     }
     ```
   - `--no-line-comments` path (lines 120-130): 同パターンで変更

5. `tests/gh-*.bats` 4 ファイルにそれぞれ "error: API failure" テスト追加 (→ AC4)
   - `gh-pr-merge-status.bats`: `gh` mock が exit 1 の場合に script が exit 1 かつ "Error" を含む出力をすること
   - `gh-label-transition.bats`: `gh issue edit` が失敗した場合に exit 1 かつ "Error" メッセージが出力されること (setup の gh mock を exit 1 に上書き)
   - `gh-graphql.bats`: `gh api graphql` が失敗した場合に exit 1 かつ "Error" メッセージが出力されること
   - `gh-pr-review.bats`: `gh api repos/.../reviews` POST が失敗した場合に exit 1 かつ "Error" メッセージが出力されること

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-*.sh のうち少なくとも 7 個が gh CLI 呼び出し直後に明示的 error handling (exit code チェック + stderr メッセージ + non-zero exit) を持つ" --> 7 個以上の gh-*.sh が API failure を観察可能にする error handling を持つ
- <!-- verify: grep "Error.*>&2" "scripts/gh-check-blocking.sh" --> gh-check-blocking.sh が API failure 時に明示的な stderr エラーメッセージを持つ (代表スクリプト確認)
- <!-- verify: command "bash -n scripts/gh-issue-edit.sh && bash -n scripts/gh-issue-comment.sh && bash -n scripts/gh-graphql.sh && bash -n scripts/gh-label-transition.sh && bash -n scripts/gh-extract-issue-from-pr.sh && bash -n scripts/gh-pr-merge-status.sh && bash -n scripts/gh-check-blocking.sh && bash -n scripts/gh-pr-review.sh" --> 主要 gh-*.sh の syntax check 通過 (修正後の sanity check)
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green (回帰検出)

### Post-merge

- 次回 GitHub API rate limit / permission error が発生した際、silent pass through せず stderr で発見可能になっていることを観察

## Consumed Comments

- saitoco (MEMBER, first-class): Issue Retrospective + Auto-Resolve Log — 3 点の曖昧ポイントの解決記録を確認、AC が更新済であることを確認 [https://github.com/saitoco/wholework/issues/738#issuecomment-4815837827]

## Notes

- `gh-pr-review.sh` のリファクタは heredoc パイプライン (`python3 <<'PYEOF' | gh api`) を変数キャプチャ方式に変更するが、動作は等価。既存テストはモック `gh` が `echo "$REVIEW_PAYLOAD" | gh api ...` で同じく呼ばれるため影響なし
- `gh-graphql.sh` の error メッセージは QUERY_NAME が空の場合もあるため "gh api graphql failed" というシンプルな形にする (QUERY_NAME を含めると空文字が混入する可能性)
- `gh-label-transition.sh` line 68 は `ENTERED_WORKTREE` の "already set" パスの `gh issue edit` 呼び出し — 3 箇所すべて同じパターンで統一
- `gh-check-blocking.sh` は audit report で「唯一 error handling があった」と記録されているが、現在は 3 個 (`gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-extract-issue-from-pr.sh`) も既に完全対応済み (Issue 記述時点から実装が進んだ)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI failing (`ci_failing`) を non-interactive auto-resolve として処理し、マージを続行。Issue #765 の pre-existing false positive が CI failure の主因と review phase で確認済み。
- `--squash --delete-branch` でスカッシュマージ完了。BASE_BRANCH = main のため `closes #738` により Issue は自動クローズ。
- Phase Handoff を main にコミット (worktree branch で ff-only merge 後にコミット + push)。

### Deferred Items
- Forbidden Expressions check false positive は Issue #765 で引き続き追跡中。merge phase では自動解決として通過させた。
- AC4 の `github_check "gh run list ..."` を `gh pr checks` ベースの verify command に更新する改善は後続 Issue または次回 Spec 改訂で対応。

### Notes for Next Phase
- verify phase: PR #767 のスカッシュコミットが main に着地済み。`scripts/gh-*.sh` 4 個の error handling 追加が対象。
- Post-merge verify: `bash -n scripts/gh-*.sh` の syntax check と bats テスト (`tests/gh-*.bats`) を実行して回帰がないことを確認。
- 本番観察 (手動): 次回 GitHub API rate limit / permission error が発生した際に stderr で発見可能になっているか確認。

## Code Retrospective

### Deviations from Design

- 設計では `gh-pr-review.sh` の `--with-line-comments` path が lines 91-93 に位置すると記載されているが、実際の行番号は正確ではなかった。Spec の行番号はあくまで参照用であり、実際のファイル内容を読んで適用した。
- `gh-graphql.sh` の no-cache path (`gh api graphql "${GH_ARGS[@]}"`) は設計では単純な `|| { echo "Error..." >&2; exit 1; }` パターンで追加できるとされていたが、pipe 内の最終コマンドにあたるため set -e だけでは検出されないケースへの対処として明示的 error handling を追加した。これは設計意図と合致している。

### Design Gaps/Ambiguities

- Spec には `gh-label-transition.sh` の "already set" パス (line 68) が独立した branch であることが記載されているが、else ブランチの 2 箇所 (lines 90, 92) との区別が当初不明確だった。実装時にファイルを読んで 3 パターンに分けた。

### Rework

- None

## review retrospective

### Spec vs 実装の乖離パターン

Code Retrospective に `gh-graphql.sh` の no-cache path が "pipe 内の最終コマンド" と記述されているが、実際は `else` ブロックの最終コマンドであり shell pipeline 内ではない。`set -euo pipefail` があれば単独でもエラー検出される。実装の正しさは問題ないが、Retrospective の説明が若干不正確。Spec 記述時に実装の詳細 (pipe vs 非 pipe) を明記すると今後の誤解を防げる。

### 繰り返し問題のパターン

CONSIDER のみ 3 件検出された:
1. bats テストのエラーパスカバレッジが複数コードパスの一部のみをカバー (gh-graphql.bats, gh-label-transition.bats)
2. Spec Code Retrospective の記述精度

同一パターンの複数コードパスのうち一部のみテストするパターンが 2 件あった。複数コードパスがある場合 (特に `if-else` の各ブランチ)、少なくとも 1 パスがエラー経路をカバーしていれば実用上十分だが、「全パスカバー vs 代表パスのみカバー」の判断基準を Spec に明記するとコードレビューでの CONSIDER 指摘を減らせる。

### 受け入れ条件の検証難易度

- rubric + grep + command (CI reference) で3件の pre-merge 条件を PASS 判定できた。
- `github_check "gh run list ..."` は safe モードの allowlist 外のため UNCERTAIN だったが、`gh pr checks` での CI 状態確認で実質的に PASS 相当を確認。
- `gh run list` を `gh pr checks` で代替できるよう verify command を更新すると UNCERTAIN を PASS に変換できる (Spec 品質改善候補)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Auto-Resolved Ambiguity Points セクションが 3 点の曖昧解消を体系的に整理 (存在しないファイル名修正、CI verify command 形式選択、rubric mechanical safety net 補完)。`/issue` フェーズが Spec への準備として機能。

#### spec
- Implementation Steps が 4 ファイルの error handling 追加と 4 ファイルの bats テスト追加を漏れなく列挙し、Phase Handoff (`<!-- phase: merge -->`) で次フェーズへ正確に橋渡し。
- 行番号参照 (`line 68, 90, 92` 等) が code 実装時に実ファイルとずれていた (Spec の参照番号は Spec 作成時点の snapshot; 後続 commit で番号がずれた)。Spec の Code Retrospective でこれが記録されている。

#### code
- Code Retrospective に「`gh-graphql.sh` no-cache path は pipe 内の最終コマンドではなく else ブロックの最終コマンド」という不正確な記述があったが、review retrospective で訂正されている。実装そのものは正しい。
- Rework なし。

#### review
- 3 件の CONSIDER (test path coverage、Retrospective 記述精度、verify command 形式) が建設的な観察として記録された。
- 同一パターンの複数 if-else ブランチで代表パスのみテストする pattern が 2 件検出 — Spec の test guideline 改善余地として記録。

#### merge
- `ci_failing` (`Forbidden Expressions check` の pre-existing false positive) を non-interactive auto-resolve で通過。本 Issue の変更とは無関係な #765 で追跡中の課題。

#### verify
- AC4 (`github_check "gh run list ..." "success"`) が #733 と同様 workflow 全体 conclusion の failure (`Forbidden Expressions check` 失敗) で literal FAIL になったが、`Run bats tests` job 単独は success。intent (CI bats green) を満たすため代替検証で PASS。
- `github_check` の workflow-level vs job-level の divergence が #733 / #738 で連続発生。Tier 2 (lesson) から Tier 1 (recurring pattern) に格上げ要検討。

### Improvement Proposals

- **PROPOSAL** (skill-infra, recurring): `github_check` verify command で workflow 全体ではなく特定 job の conclusion を見られる sub-form を導入。#733 / #738 で連続発生した「workflow 全体は別 job の失敗で FAIL だが bats job は success」というパターンに対する構造的解決。例: `github_check_job "Run bats tests" "success"` のような job 名直接指定の sub-form を verify-executor.md に追加。
- **PROPOSAL** (skill-infra): Spec の test guideline に「同一パターンの if-else 複数ブランチに対するテスト方針 (全パスカバー vs 代表パスのみカバー) の判断基準」を明記。review phase の CONSIDER 指摘 (本 Issue で 2 件) を減らす予防策。
- **OBSERVATION** (one-time): `Forbidden Expressions check` の pre-existing false positive (Issue #765) が複数の Issue (#733, #738) で CI を blocking している。#765 解決の優先度を再評価する価値あり。
