# Issue #510: verify: post-merge manual AC の UX 改善 — pre-merge 先行確定 + Claude 実行可能性判定 + 都度確認

## Overview

`/verify` の UX を 2 方向で改善する。

**現状の問題:**
1. pre-merge と post-merge の AC を一括検証してから checkbox flip するため、post-merge が SKIP に終わっても pre-merge 成果の確定が遅れる
2. `verify-type: manual` の post-merge AC を merge 直後に一律 AskUserQuestion で確認するため、ユーザが未着手でも回答を求められ SKIP → 再 verify が必要になる
3. Claude が実行可能な条件 (curl 疎通確認、gh コマンド結果判定など) でも一律 user 確認に振り、Claude の検証能力を活用できない

**改善方針:**
- **ordering**: pre-merge AC を先に full verification → checkbox flip + Issue body 更新 → その後 post-merge に着手。post-merge が SKIP でも pre-merge 成果は GitHub Issue 上で確定済み
- **post-merge intelligence**: manual AC ごとに Claude 実行可能性を rubric ベースで判定。実行可能なら「Claude 実行 / 手動検証 (ガイド表示) / SKIP」の都度確認 UX、実行不可なら検証ガイドのみ表示 (AskUserQuestion なし)

## Changed Files

- `skills/verify/SKILL.md`: Step 5 の pre-merge フィルタ追加・inner Step 5 削除、Step 6 の pre-merge 先行 flip 変更、新 Step 7 (post-merge briefing) 挿入、新 Step 8 (post-merge processing) 挿入、旧 Step 7-13 を新 Step 9-15 へ繰り下げ (参照番号更新含む)

## Implementation Steps

1. **Step 5 改修** (→ AC1): 先頭に「pre-merge 条件のみを対象とする」フィルタを追加し、inner Step 5 (Manual AC Confirmation via AskUserQuestion) を Step 5 スコープから削除する。inner Steps 1-4 は pre-merge 条件にのみ適用する。post-merge 条件 (セクションあり場合の post-merge 行) はこのステップでは処理しない

2. **Step 6 改修** (→ AC1): 対象を「pre-merge PASS conditions の checkbox flip のみ」に変更する。post-merge AC 処理に入る前にこの flip を実行し、GitHub Issue body を即時更新することで pre-merge 成果を確定させる旨を明記する

3. **新 Step 7: post-merge briefing 追加** (→ AC2): post-merge AC の個別処理に入る前に AC 一覧を表示するステップを旧 Step 7 の直前に挿入する。表示内容: post-merge AC の総件数 + 各条件の要約テキスト + 条件タイプ (`<!-- verify: ... -->` コマンドあり / manual) + manual 条件への Claude 実行可能性の 1 行クイックプレビュー。このステップでは実行も AskUserQuestion も行わない

4. **新 Step 8: post-merge processing 追加** (→ AC3, AC4, AC5):
   - Step 8a: `<!-- verify: ... -->` hint を持つ post-merge 条件を auto-verify する (inner Steps 1-4 と同ロジック)
   - Step 8b: `<!-- verify-type: manual -->` 条件を 1 件ずつ処理する:
     - Claude 実行可能性を rubric ベースで判定する (実行可能例: curl URL 疎通確認、gh コマンド結果判定、ファイル/ディレクトリ存在確認、git log/status 結果判定、process listing; 実行不可例: ブラウザ目視確認、production 環境のユーザ行動観察、UI/UX 評価、外部サービス dashboard 確認)
     - 実行可能と判定した場合: AskUserQuestion "Condition X: Claude が `<コマンド/手順>` で検証可能です。実行しますか?" を提示。選択肢: "Claude 実行" / "手動検証 (ガイド表示)" / "SKIP"。"Claude 実行" 選択時はコマンドを実行して PASS/FAIL を判定し checkbox flip する
     - 実行不可と判定した場合: 検証ガイド (具体的 URL / コマンド / 期待状態) のみ表示し、AskUserQuestion は行わない。checkbox flip も保留する
   - Step 8 完了後: post-merge PASS 条件 (Step 8a/8b の PASS 結果) の checkbox を flip する

5. **旧 Step 7-13 を新 Step 9-15 へ繰り下げ** (内部整合性): 挿入した 2 ステップ分を繰り下げる。旧 Step 9 (Apply Verification Results) の参照 "confirmed as PASS or FAIL in Step 5 (SKIP responses are excluded)" を "confirmed as PASS or FAIL in Step 8 (SKIP responses are excluded)" に更新する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md の Step 順序が変更され、pre-merge AC の検証 + checkbox flip + Issue body 更新が post-merge manual AC 処理よりも先に実行される設計が記述されている" --> pre-merge 先行確定の処理順序が記述されている
- <!-- verify: rubric "skills/verify/SKILL.md に、post-merge AC の個別処理に入る前に AC 一覧 (件数 + 各条件要約 + Claude 実行可能性プレビュー) を briefing として提示する step が追加されている" --> post-merge briefing step が追加されている
- <!-- verify: rubric "skills/verify/SKILL.md に、post-merge manual AC ごとに Claude 実行可能性を判定するロジック (rubric ベース) が追加されている" --> Claude 実行可能性判定が追加されている
- <!-- verify: rubric "skills/verify/SKILL.md に、Claude 実行可能と判定された manual AC は AskUserQuestion で『Claude 実行 / 手動検証 / SKIP』の選択肢を都度提示する処理が記述されている" --> 都度確認 UX が記述されている
- <!-- verify: rubric "skills/verify/SKILL.md に、Claude 実行不可と判定された manual AC は検証ガイド (具体的 URL/コマンド/期待状態) のみ表示して checkbox flip を保留する処理が記述されている" --> 手動検証ガイド表示フローが記述されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テスト CI が成功

### Post-merge

- `/verify N` を実行し、pre-merge AC が先に検証されて checkbox がチェック・コミット・プッシュされた後で初めて post-merge manual AC の処理が始まることを実機確認 <!-- verify-type: manual -->
- post-merge AC を複数含む Issue で `/verify N` を実行し、個別 AskUserQuestion に入る前に AC 一覧の briefing (件数 + 各条件要約 + Claude 実行可能性プレビュー) が表示されることを実機確認 <!-- verify-type: manual -->
- Claude 実行可能な post-merge manual AC (curl/gh/file check 等) を含む Issue で `/verify N` を実行し、`Claude 実行 / 手動検証 / SKIP` の都度確認 UX が機能することを実機確認 <!-- verify-type: manual -->
- Claude 実行不可な post-merge manual AC (UI 目視等) のみを含む Issue で `/verify N` を実行し、検証ガイド表示後すぐ完了 (AskUserQuestion で eager に尋ねない) し、ユーザの手動検証後 `/verify N` 再実行で closeout される流れを実機確認 <!-- verify-type: manual -->

## Notes

- 実装対象は `skills/verify/SKILL.md` のみ。bats テスト (スクリプト) には変更なし。CI チェック (AC6) は既存テストの通過確認
- 実装ステップ数 5 = light 上限。Pre-merge 検証項目は 6 件 (Issue AC 駆動のため light 上限 5 を 1 件超えるが、Issue body 準拠のため全件収録)
- post-merge briefing は新 Step 7 として旧 Step 7 (Post Comment) の直前に挿入する。旧 Step 7 の番号は新 Step 9 へ繰り下がる

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の AC 設計は明確。rubric ベースの pre-merge 検証 6 件 + manual 4 件の構成はスコープ分離が適切。
- 「AC6 の `github_check` を `gh run list` 形式に自動変更」という auto-resolved ambiguity がIssue bodyに記録されており、パッチルート対応が設計段階で考慮されていた点は良好。
- Specの実装ステップ記述は Changed Files、Implementation Steps、Verification の三部構成で簡潔。

#### design
- Spec の設計 (pre-merge 先行確定 + post-merge briefing + intelligence) と実装 diff が一致。設計逸脱なし。
- 旧 Step 5 の inner Step 5 削除と新 Step 7/8 挿入による step 繰り下げは、Spec の "旧 Step 7-13 を新 Step 9-15 へ繰り下げ" 記述どおりに実装されている。

#### code
- コミット履歴は Spec 追加 → 実装の 2 コミットのみ。fixup/amend パターンなし。
- 実装 diff は SKILL.md の 88 行追加 / 41 行削除で、設計に沿った Step 追加と番号繰り下げが確認できる。

#### review
- PR が存在しないパッチルートのため PR review コメントは存在しない。CI (bats tests) が success であることが自動検証で確認済み。

#### merge
- パッチルート (direct commit to main)。PR merge プロセスなし。2 コミットとも sign-off あり。

#### verify
- Pre-merge AC 6 件はすべて PASS（rubric 5 件 + github_check 1 件）。
- Post-merge manual AC 4 件は実機確認が必要なため UNCERTAIN/保留扱い（AskUserQuestion 動作はユーザが実際に `/verify N` を実行しないと確認不可）。
- `github_check "gh run list"` 形式がパッチルートで正常に機能することを確認。

### Improvement Proposals
- N/A

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | — | SUCCESS | AC 2 件 (gh pr checks → gh run list、不適切 supplementary 削除) を refinement で修正 |
| spec | — | SUCCESS | Spec 作成・コミット・プッシュ |
| code | patch | SUCCESS (watchdog kill, manual fallback) | run-code.sh 1800s 沈黙 → SIGTERM (exit 143)。worktree branch `worktree-code+issue-510` に implementation commit `407fcb1` 完了済み、main へ未 merge。parent session で `worktree-merge-push.sh --from worktree-code+issue-510` 手動実行で復旧 |
| verify | — | SUCCESS (Skill tool path) | 6/6 pre-merge auto PASS、4 post-merge manual pending。新 /verify 設計通り Skill tool 経由起動・post-merge briefing + Claude 実行可能性判定が動作確認できた |

### Orchestration Anomalies

- **[code-watchdog-merge-push-incomplete]** code phase で implementation commit 完了後、`worktree-merge-push.sh` 段階で watchdog 1800s 沈黙 → SIGTERM。`reconcile-phase-state.sh code-patch --check-completion` が `matches_expected:false` (commit on main 不在) を返したが、worktree 内には完了済 commit が残存。`worktree-merge-push.sh --from` 手動実行で復旧。これは #469 (code-completed-no-pr / pr route) と類似だが patch route 版 (PR 不在のため "merge-push incomplete" として区別)
- **(recurring)** watchdog 1800s kill は #469 / #485 / #510 で 3 回連続発生。実装完了後の長時間処理 (PR creation, merge-push, GitHub API レイテンシ) が原因。`.wholework.yml` の `watchdog-timeout-seconds: 3600` 等の延長を user 側で設定する short-term workaround は可能だが、code-watchdog 後の自動 reconcile + fallback が根本対策

### Improvement Proposals

- **patch route の code phase に code-completed-no-pr 相当の自動 reconcile + merge-push fallback を追加**: 現在 `code-completed-no-pr` (pr route) は `orchestration-fallbacks.md` にエントリ済みで `detect-wrapper-anomaly.sh` で自動検出されるが、patch route の "implementation commit 完了済 + main 未 merge" パターン (本 anomaly) は未対応。`apply-fallback.sh` で同 worktree branch を merge-push する自動 fallback を追加すれば、3 connsecutive 発生中の摩擦が解消する。新規 anomaly pattern: `code-patch-merge-push-incomplete`、catalog anchor 名: `code-patch-merge-push-incomplete`
