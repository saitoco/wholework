# Issue #707: verify: FAIL 時に機械可読 marker 付き comment を append し、次フェーズ skill が consume

## Overview

`/verify` FAIL 検出時に機械可読 marker (`<!-- wholework-event: type=verify-fail ... -->`) 付きの comment を Issue へ append する。ユーザーと Claude が同じ場所 (comment) を参照することで FAIL コンテキストを取得できるようにする。

AC body の checkbox は引き続き mutable SSoT、comment は append-only な history として機能する (R1 #705 の append-only / mutable 分離原則に従う)。

Marker 形式は `modules/l0-surfaces.md` の SSoT フォーマット (`<!-- wholework-event: type=<type> phase=<phase> issue=<N> -->`) に準拠し、`iteration` を追加属性として付与する。

## Changed Files

- `skills/verify/SKILL.md`: Step 9 (b) の FAIL フローに FAIL marker comment 投稿ステップと `verify_fail_marker_posted` イベント emit ステップを追加 — bash 3.2+ 互換
- `scripts/emit-event.sh`: `verify_fail_marker_posted` イベント型のスキーマドキュメントを追加 — bash 3.2+ 互換
- `docs/workflow.md`: Verify Fail Flow セクションに FAIL marker comment 投稿の記述を追加
- `docs/ja/workflow.md`: `docs/workflow.md` 変更の翻訳同期 (Japanese mirror)

## Implementation Steps

**Step 1**: `skills/verify/SKILL.md` Step 9 (b) の FAIL フロー両ブロックに FAIL marker comment ステップを追加 (→ AC1)

_`NEXT_ITERATION < VERIFY_MAX_ITERATIONS` ブロック_: 「Remove all `phase/*` labels」(`gh-label-transition.sh "$NUMBER"`) の直後、「Output guidance for the user」の直前に以下ステップを挿入:

```
    - Post a machine-readable FAIL marker comment:
      Write the following to `.tmp/verify-fail-comment-$NUMBER.md` with Write tool:
      ```
      <!-- wholework-event: type=verify-fail phase=verify issue=$NUMBER iteration=$NEXT_ITERATION -->
      ## /verify FAIL — {TIMESTAMP}

      **Failed acceptance conditions:**
      {for each FAIL condition from auto-verification targets:}
      - [ ] {condition text}
        - Reason: {failure reason from verify execution}

      **Next action**: `phase/*` ラベル削除済み、Issue reopen 済み (CLOSED の場合)。次走時 (`/code --patch $NUMBER` 等) はこの comment を一級入力として読み込んでください。
      ```
      Then post:
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh "$NUMBER" ".tmp/verify-fail-comment-$NUMBER.md"
      rm -f .tmp/verify-fail-comment-$NUMBER.md
      ```
    - Emit `verify_fail_marker_posted` event (only when `AUTO_EVENTS_LOG` is set):
      ```bash
      if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
        source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
        EMIT_ISSUE_NUMBER=$NUMBER emit_event "verify_fail_marker_posted" \
          "iteration=${NEXT_ITERATION}" \
          "failed_ac_count=${FAIL_COUNT}"
      fi
      ```
      (`comment_id` は `gh-issue-comment.sh` がコメント ID を返さないため省略)
```

_`NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` ブロック_: 「Post a comment with the max-iterations notice」の直後、「Assign `phase/verify` label」の直前に同様の FAIL marker comment 投稿ステップと `verify_fail_marker_posted` イベント emit ステップを追加。Next action テキストは「Max iterations reached. Issue stays in `phase/verify` for human judgment.」に変更する。

**Step 2**: `scripts/emit-event.sh` に `verify_fail_marker_posted` イベント型スキーマを追加 (→ AC2)

既存のイベントスキーマドキュメントコメントブロック (末尾) に以下を追加:

```bash
# verify_fail_marker_posted: /verify FAIL 時に machine-readable marker comment を Issue に append した
#   iteration=<n>                 verify iteration counter (NEXT_ITERATION)
#   failed_ac_count=<n>           number of FAIL conditions in auto-verification targets
```

**Step 3**: `docs/workflow.md` の Verify Fail Flow セクションを更新 (→ doc sync)

`### Verify Fail Flow` セクションの冒頭説明文:

変更前:
```
When `/verify` detects a FAIL among auto-verification targets, it reopens the Issue and removes all `phase/*` labels.
```

変更後:
```
When `/verify` detects a FAIL among auto-verification targets, it appends a machine-readable FAIL marker comment (see `modules/l0-surfaces.md` for the `wholework-event: type=verify-fail` format), reopens the Issue, and removes all `phase/*` labels.
```

フローダイアグラム内の `"FAIL"` 分岐ラベルテキストは変更不要 (ダイアグラムレベルは高水準のため)。

**Step 4**: `docs/ja/workflow.md` の対応セクションを日本語で同期更新 (→ translation sync)

`### Verify Fail フロー` セクションの冒頭説明文を日本語で対応更新:

変更前:
```
`/verify` が自動検証対象の中で FAIL を検出すると、Issue を reopen し全 `phase/*` ラベルを除去します。
```

変更後:
```
`/verify` が自動検証対象の中で FAIL を検出すると、機械可読 FAIL marker comment を Issue に append し (`modules/l0-surfaces.md` の `wholework-event: type=verify-fail` フォーマット参照)、Issue を reopen し全 `phase/*` ラベルを除去します。
```

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/verify/SKILL.md" "wholework-event: type=verify-fail" --> `/verify` SKILL.md に FAIL marker comment 投稿ステップが追記されている
- <!-- verify: file_contains "scripts/emit-event.sh" "verify_fail_marker_posted" --> `verify_fail_marker_posted` イベント型が追加されている
- <!-- verify: grep "wholework-event: type=verify-fail" "modules/l0-surfaces.md" --> `modules/l0-surfaces.md` に verify-fail marker type が記載されている

### Post-merge

- `/verify N` を意図的に FAIL させ、Issue に機械可読 marker 付き comment が append され、`gh issue view --json comments` で当該 marker が grep できることを観察 <!-- verify-type: manual -->
- 次走 `/code --patch N` (または auto-retry) で本 comment が consume されたことが Spec retrospective に記録されることを観察 <!-- verify-type: opportunistic -->

## Consumed Comments

- saito (MEMBER / first-class) — 2026-06-20T16:12:15Z: Post-merge AC の verify-type タグ修正 (A1: manual, A2: opportunistic) + #705 ブロッカー解消確認 (https://github.com/saitoco/wholework/issues/707#issuecomment-4758940147)

## Notes

**[Auto-resolve A1] AC3 既存コンテンツで充足**:
`modules/l0-surfaces.md` には #705 (R1) で既に `<!-- wholework-event: type=verify-fail phase=verify issue=42 -->` がExample として記載されており、AC3 の `grep "wholework-event: type=verify-fail" "modules/l0-surfaces.md"` は現状でも PASS する。l0-surfaces.md への変更は不要。

**[Auto-resolve A2] comment_id を省略**:
`scripts/gh-issue-comment.sh` は Comment ID を返さないため、`verify_fail_marker_posted` イベントの `comment_id` フィールドを省略する。`iteration` と `failed_ac_count` で代替識別が可能。

**[Auto-resolve A3] marker 属性フォーマット**:
Issue 提案の `phase-at-fail=verify` は l0-surfaces.md SSoT の `phase=verify` と異なる。SSoT フォーマット (`phase=verify`) を採用し、Issue 固有の `phase-at-fail` ではなく標準属性を使用する。`iteration` は追加属性として付与する。

**次フェーズ skill での consume (実装外)**:
`/code` 再走時・`/spec` 再走時での `type=verify-fail` comment consume は Issue #707 の対象外。l0-surfaces.md の Comment Consumption Procedure は既に bot 例外 (`<!-- wholework-event:` marker 付き comment を consume する) を定義しており、スキル側の consume 実装は別 Issue で追加する。

## Code Retrospective

### Deviations from Design

- Step 11(b) の参照は Spec 中では "Step 9 (b)" と記載されていたが、SKILL.md の実際のステップ番号は "Step 11 (b)" であったため、SKILL.md の実際の構造に合わせて実装した (Spec の参照番号の誤りを実装で解消)

### Design Gaps/Ambiguities

- Spec では `FAIL_COUNT` 変数を参照しているが、この変数は SKILL.md の既存フローで定義されていない。`verify_fail_marker_posted` emit 時の `failed_ac_count` パラメータとして参照している。実装ではそのまま記述し、実行時に LLM が FAIL 条件数を適切に解釈することを前提とする (シェルスクリプトではなく SKILL.md の LLM 実行指示)
- TIMESTAMP の具体的な取得方法 (`date -u +%Y-%m-%dT%H:%M:%SZ` 等) は Spec に明記されていないが、SKILL.md 内では LLM が実行時に解釈するため明記不要と判断

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- SKILL.md への追加は 2 箇所 (NEXT_ITERATION < VERIFY_MAX_ITERATIONS ブロックと >= VERIFY_MAX_ITERATIONS ブロック) に対称的に実装した
- `FAIL_COUNT` 変数は SKILL.md 内の LLM 実行コンテキストで解釈されるため、シェル変数定義なしで参照
- docs/ja/workflow.md は Step 4 として同一コミットで同期更新済み

### Deferred Items
- `type=verify-fail` comment の次フェーズ consume (/code 再走時・/spec 再走時) は別 Issue 対象
- `FAIL_COUNT` (変数名) が将来 SKILL.md に明示定義される場合は当該箇所の更新が必要

### Notes for Next Phase
- AC3 (`modules/l0-surfaces.md` の verify-fail marker) は既存コンテンツで充足済み、l0-surfaces.md への変更なし
- pre-merge AC 3 件すべて PASS 確認済み (checkbox 更新済み)
- bats テスト全件 PASS、validate-skill-syntax.py PASS、forbidden expressions チェック PASS

## Review Retrospective

### Spec vs Implementation Divergence Patterns

- 構造的な divergence なし。Spec の全実装ステップが diff に反映されている。
- 既知の偏差 (FAIL_COUNT 未定義、comment_id 省略) は Code Retrospective で事前文書化済みのため、review 時点で追加の divergence 発見はなかった。Code phase での自己レビューが review phase の divergence 発見コストを低減している。

### Recurring Issues

- 対称的な実装ブロック (block 1 / block 2) で "Next action" テキストの言語が非一致 (block 1: 日本語、block 2: 英語)。SKILL.md への対称追加では両ブロックのテキスト内容も対称チェックが必要というパターン。CONSIDER レベルのため今回は修正せず記録のみ。

### Acceptance Criteria Verification Difficulty

- Pre-merge AC 3 件すべて `file_contains`/`grep` 系コマンドで auto-verify 可能。UNCERTAIN ゼロ。
- Code phase で checkbox が 1 件先行更新 ([x]) されており、verify-executor が正確なステータスを反映できた。
- CI bats テスト失敗 (setup-labels.bats) は main ブランチでも同一失敗があり、pre-existing failure として確認済み。verify コマンドによる AC 確認とは独立して評価できた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI failing (setup-labels.bats pre-existing failure) の状態でも non-interactive auto-resolve により squash merge を実行。pre-existing failure であることは review phase で確認済み。
- `--delete-branch` により head ブランチ `worktree-code+issue-707` は削除済み。

### Deferred Items
- setup-labels.bats の CI 失敗修正は別 Issue で対処予定。
- `type=verify-fail` comment の consume 実装 (/code 再走時) は別 Issue 対象。

### Notes for Next Phase
- post-merge AC 2 件: A1 (manual: `/verify N` FAIL で marker comment が Issue に append されることを観察)、A2 (opportunistic: 次走 `/code --patch N` で consume 記録確認)。
- closes #707 により Issue は自動クローズ済み (BASE_BRANCH=main)。verify は Issue の状態確認から開始すること。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec 中の Step 番号参照 (Step 9(b)) が実装時点の SKILL.md 構造 (Step 11(b)) と不一致だった。Spec 作成時の参照タイミングと実装時のステップ番号ずれを示すパターン。

#### code
- 対称的な実装ブロック (block 1/block 2) で出力テキスト言語が不一致 (block 1: 日本語、block 2: 英語)。Review で CONSIDER レベルとして記録のみ。
- FAIL_COUNT 変数が SKILL.md 内で明示定義されていない状態で参照されているが、LLM 実行コンテキストでの解釈に依存する設計。

#### review
- Spec vs 実装の divergence ゼロ。Code phase での自己レビューが review コストを低減。

#### merge
- setup-labels.bats の pre-existing CI failure 状態で auto-resolve squash merge を実行。pre-existing と確認済み。

#### verify
- pre-merge AC 3 件すべて `file_contains`/`grep` 系で auto-verify 可能、UNCERTAIN ゼロ。
- post-merge AC 2 件 (manual + opportunistic) は将来観測待ち。

### Improvement Proposals
- N/A
