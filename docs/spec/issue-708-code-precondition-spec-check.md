# Issue #708: phase-state: code-patch/code-pr precondition に Spec exists (Size=XS は例外) を追加し future scope を解除

## Overview

`scripts/reconcile-phase-state.sh` の `--check-precondition code-patch` / `--check-precondition code-pr` は現在 `phase/ready` ラベルのみを確認し、Spec ファイルの存在を確認しない。これを修正し「Spec exists OR Size=XS」の precondition を追加することで、Spec なしの Issue に対して `/code` が誤って実行されるリスクを排除する。

あわせて `modules/phase-state.md` の Phase Table 内 "future scope" 注記を解除し、`skills/code/SKILL.md` Step 3 が `reconcile-phase-state.sh --check-precondition` を呼ぶよう更新する。

## Consumed Comments

- saito (MEMBER / first-class) — Issue Retrospective: 3 件の曖昧ポイントを自動解決済み (AC1 grep パターン変更、AC4 bats コマンド修正、AC6 追加)。既に Issue body に反映済み。
  URL: https://github.com/saitoco/wholework/issues/708#issuecomment-4759202336

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_precondition_code_common()` に Spec 存在チェック + Size=XS 例外ロジックを追加 (変数 `SPEC_EXISTS`、`_handle_mismatch "Spec missing and Size != XS"`) — bash 3.2+ compatible
- `modules/phase-state.md`: Phase Table の code-patch / code-pr 行の "future scope" 注記を "Implemented (Spec exists OR Size=XS)" に更新; JSON Schema に `actual.size` フィールドを追加
- `tests/reconcile-phase-state.bats`: Spec missing シナリオのテスト追加 (code-patch / code-pr 各 2 件); 既存テスト "same phase: precondition passes but completion not yet reached" を Spec ファイル有りに更新 (テスト意図を維持しつつ precondition を通過させる)
- `skills/code/SKILL.md`: Step 3 に `reconcile-phase-state.sh --check-precondition code-patch|code-pr $NUMBER` 呼び出しを追加; Spec missing 警告時の abort 推奨フローを明記

## Implementation Steps

1. `scripts/reconcile-phase-state.sh`: `_precondition_code_common()` を修正 — `phase/ready` チェック通過後に以下を追加: `SPEC_EXISTS=$(ls "${spec_path}/issue-${ISSUE_NUMBER}-"*.md 2>/dev/null | head -1)` (変数名は SPEC_EXISTS を使う)、`SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$ISSUE_NUMBER" 2>/dev/null || true)`; `actual_json` に `"size":"$SIZE"` フィールドを追加; SPEC_EXISTS が空かつ SIZE != "XS" の場合は `_handle_mismatch "Spec missing and Size != XS" "$actual_json"` で exit (→ AC1、AC2)
2. `modules/phase-state.md`: Phase Table の code-patch / code-pr 行 "Spec exists — future scope" を "Spec exists OR Size=XS — Implemented (Spec exists OR Size=XS)" に変更; JSON Schema フィールドテーブルに `actual.size` 行を追加 (When: "When spec precondition is checked with Size check") (→ AC3)
3. `tests/reconcile-phase-state.bats`: 新規テスト 3 件追加 — `"code-patch precondition: Spec missing and Size != XS -> mismatch"`, `"code-patch precondition: Spec missing but Size XS -> matches_expected true"`, `"code-pr precondition: Spec missing and Size != XS -> mismatch"` (各テストで `get-issue-size.sh` モックを `$MOCK_DIR` に配置); 既存テスト `"same phase: precondition passes but completion not yet reached"` を修正: `no-spec` ディレクトリに `issue-42-spec.md` を touch して precondition が通過するようにする (→ AC4、AC5)
4. `skills/code/SKILL.md` Step 3 に追加: XS でない場合に `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh --check-precondition code-patch $NUMBER` (または code-pr) を実行し、`matches_expected` が false の場合は「Spec が見つかりません。\`/spec $NUMBER\` を実行してください」と出力して abort 推奨 (→ AC6)

## Verification

### Pre-merge

- <!-- verify: grep "SPEC_EXISTS" "scripts/reconcile-phase-state.sh" --> `reconcile-phase-state.sh` の code-patch / code-pr precondition に Spec 存在チェックロジックが追加されている
- <!-- verify: grep "Size != XS" "scripts/reconcile-phase-state.sh" --> Size=XS の場合に Spec チェックを skip するロジックがある
- <!-- verify: file_contains "modules/phase-state.md" "Implemented (Spec exists OR Size=XS)" --> Phase Table の future scope 注記が解除されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> phase-state 関連テストが green
- <!-- verify: file_contains "tests/reconcile-phase-state.bats" "Spec missing" --> Spec missing シナリオの bats テストが追加されている
- <!-- verify: grep "check-precondition" "skills/code/SKILL.md" --> `/code` SKILL.md が `reconcile-phase-state.sh --check-precondition` を呼ぶよう更新されている

### Post-merge

- 試験的に `phase/ready` のみ付与・Spec 無しの M Issue に対して `reconcile-phase-state.sh --check-precondition code-pr N` を実行すると `matches_expected: false` を返すことを観察
- 試験的に XS Issue (Spec 無し) に対して同コマンドを実行すると `matches_expected: true` を返すことを観察

## Code Retrospective

### Deviations from Design

- `skills/code/SKILL.md` の `!=` を `is not` に変更: 実装直後に `validate-skill-syntax.py` が body 内の半角 `!` を forbidden expression として検出。Spec には修正方針の記載がなかったため、禁止文字のルール (docs/tech.md § Forbidden Expressions) に従い `!=` → `is not` に自動修正した。
- SKILL.md 変更を 2 コミットに分割: 初回コミット後にバリデーション違反を発見したため、修正コミットを追加した。Spec は 1 コミットを想定していたが、この分割は許容範囲内の deviation。

### Design Gaps/Ambiguities

- `_precondition_code_common()` 内の既存変数 `spec_file` を `SPEC_EXISTS` にリネームした。Spec では「変数名は `SPEC_EXISTS` を使う」と明示されていたが、既存の `_completion_spec()` 等で `spec_file` が使用されている点との一貫性についての指定がなかった。今回は `_precondition_code_common()` のスコープ内のみでリネームし、他関数には影響しない実装を選択した。

### Rework

- `skills/code/SKILL.md` の `!=` 修正により、2 つのコミットが生じた。commit メッセージで理由を明記し、追加プッシュで対処した。

## review retrospective

### Spec vs. implementation divergence patterns

- `actual.size` の JSON Schema ドキュメントが "Present when Spec is missing and Size check is performed" と記述しているが、実装では XS 成功パスで `size` フィールドが `actual_json` に含まれない (ミスマッチパスのみ)。表現が曖昧で CONSIDER 指摘を生じた。次回以降は "Present when ... mismatch occurs" など実装挙動を正確に反映した記述を推奨。
- Phase Table の Implementation Status 列に括弧で Precondition を繰り返す冗長記述が発生。Spec でドキュメント更新内容を具体的に指定する (もしくは既存フォーマットを明示する) と、コードフェーズでの記述ぶれを防げる。

### Recurring issues

- Nothing to note. 今回は異なる種類の CONSIDER 指摘が 2 件のみで、繰り返しパターンなし。

### Acceptance criteria verification difficulty

- 承認基準 6 件全て PASS。`command "bats tests/reconcile-phase-state.bats"` は CI FAILURE だったが、失敗が `setup-labels.bats` (pre-existing) であることを CI ログで確認し PASS 判定できた。Safe mode では CI ログ解析が重要で、`reconcile-phase-state.bats` 新規テストの PASS ライン (ok 534-536) を明示確認できたのは有効。Spec の verify command を `bats tests/reconcile-phase-state.bats` に限定したことで CI ジョブ全体の FAILURE に惑わされなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- CI failing (reason=ci_failing) を検出したが、main ブランチでも同一テスト群 (setup-labels.bats) が pre-existing failure であることを確認し、auto-resolve でマージを続行した。
- `gh pr merge 730 --squash --delete-branch` によるスクワッシュマージが成功 (mergedAt: 2026-06-20T17:49:23Z)。
- BASE_BRANCH=main のため `closes #708` により Issue は自動クローズされる予定。

### Deferred Items

- `actual.size` JSON Schema の記述改善 (CONSIDER): merge フェーズでは対応せず、次サイクルまたは Improvement Proposal で対応。
- Phase Table Implementation Status 列の整理 (CONSIDER): 同上。
- `tests/setup-labels.bats` の pre-existing failures: 本 PR とは無関係、別 Issue での対応が必要。

### Notes for Next Phase

- Post-merge AC (観察的 verify) が 2 件存在: `phase/ready` のみの M Issue に対して `reconcile-phase-state.sh --check-precondition code-pr N` が `matches_expected: false` を返すことの確認、XS Issue での `matches_expected: true` 確認。
- verify コマンドは Spec の Verification セクション (Post-merge) を参照。コマンド実行には `gh issue list` 等で実際の Issue を用意するか、mock 環境での確認でも可。
- setup-labels.bats の pre-existing failures は verify スコープ外。

## Notes

### Auto-Resolve: AC5 ファイル名修正 (non-interactive mode)

Issue body AC5 の verify command が `"tests/test-reconcile-phase-state.bats"` を参照していたが、このファイルは存在しない。実際の bats テストファイルは `tests/reconcile-phase-state.bats` であるため、AC5 を以下に自動修正:

- 修正前: `file_contains "tests/test-reconcile-phase-state.bats" "Spec missing"`
- 修正後: `file_contains "tests/reconcile-phase-state.bats" "Spec missing"`

### 既存テスト更新の必要性

"same phase: precondition passes but completion not yet reached" (line 809) は `MOCK_SPEC_PATH` を空ディレクトリに設定している。新 Spec チェック追加後、このテストは Spec missing として precondition FAIL になるため、`issue-42-spec.md` を作成して precondition が通過するよう修正が必要。

### `actual_json` への `"size"` フィールド追加

`_precondition_code_common()` は SIZE を `get-issue-size.sh` で取得する。Spec missing かつ Size != XS の mismatch 診断を明確にするため、`actual_json` に `"size":"$SIZE"` フィールドを含める。これは `modules/phase-state.md` JSON Schema の `actual.size` 追加と対応する。

### SPEC_DEPTH=light での Verification 件数

Issue body が 6 件の pre-merge AC を持つため Spec light 上限 (5 件) を 1 件超過するが、全 AC を漏れなく反映する。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue AC5 が存在しないファイル名 (`tests/test-reconcile-phase-state.bats`) を参照していたが、`/spec` 段階で auto-resolve により正しい `tests/reconcile-phase-state.bats` に修正。事前に検出できた点は良好。

#### code
- `skills/code/SKILL.md` で半角 `is not` 表現 (元 `!=`) を後追い修正したため、コミット 2 件に分割発生。validate-skill-syntax の forbidden expressions チェックを実装時に意識する必要あり。

#### review
- `actual.size` JSON Schema ドキュメントが "Present when Spec is missing and Size check is performed" と曖昧表現。実装では XS 成功パスで `size` フィールドが含まれない。次回 Spec 記述で実装挙動を正確に反映推奨。
- Phase Table の Implementation Status 列に括弧で Precondition を繰り返す冗長記述あり。Spec のフォーマット指定で防止可能。

#### merge
- CI failing (setup-labels.bats) は main ブランチで pre-existing failure。auto-resolve で squash merge を完遂。

#### verify
- pre-merge AC 6 件すべて PASS。`bats tests/reconcile-phase-state.bats` は CI 全体 FAILURE 中でも対象テストのみ PASS で正確に判定可能だった。verify command を特定ファイルに限定する設計が有効。

### Improvement Proposals
- N/A (Code/Review Retrospective に記録済みの CONSIDER 指摘は単発観察 (Tier 3) のため Spec 内に留める)
