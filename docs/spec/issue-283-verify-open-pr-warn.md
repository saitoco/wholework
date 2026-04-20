# Issue #283: verify: マージ前実行時に OPEN PR を検出して早期警告を追加

## Overview

`/verify` スキルの Step 2 に OPEN PR 検出ロジックを追加する。merged PR が見つからない（`PR_NUMBER` が空）かつ `--base` 未指定の場合、`git checkout` 実行前に OPEN PR を検索し、見つかった場合は `VERIFY_FAILED` マーカーと警告メッセージを出力して早期終了する。これにより、PR 未マージ状態での `/verify` 実行によるフォールス FAIL を防ぐ。

## Reproduction Steps

1. Issue にリンクされた PR を OPEN 状態（未マージ）のまま残す
2. `/verify $ISSUE_NUMBER` を実行する
3. Step 2 で merged PR が見つからず BASE_BRANCH=main にデフォルトされる
4. git checkout main → ファイルが存在しない状態で acceptance criteria を検証
5. 条件 1〜N が「ファイル未存在」で FAIL となる（フォールス FAIL）

## Root Cause

Step 2 は merged PR を検索し、見つからない場合は patch route（直接 main コミット）と判断して BASE_BRANCH=main を設定する。しかし OPEN PR が存在する場合も同様にデフォルト分岐に落ちるため、ファイルが main に存在しない状態で verify が続行される。OPEN PR の有無を確認する分岐がなかったことが原因。

## Changed Files

- `skills/verify/SKILL.md`: Step 2 の「merged PR が見つからなかった場合」の分岐内（`BASE_BRANCH=main` デフォルト設定の直後、`git checkout` 実行前）に OPEN PR 検出ロジックを追加 — bash 3.2+ 互換

## Implementation Steps

1. `skills/verify/SKILL.md` Step 2 の "Default to `BASE_BRANCH=main` if no PR is found or base branch cannot be fetched." の直後（`git checkout "${BASE_BRANCH}"` の前）に以下を追加する（`--base` 未指定の分岐内）（→ 受け入れ基準 1〜3）:

   ```bash
   OPEN_PR=$(gh pr list --search "closes #$ISSUE_NUMBER" --state open --json number,title --jq ".[0].number")
   ```

   `OPEN_PR` が空でない場合は `VERIFY_FAILED` マーカーを出力して早期終了する:
   ```
   VERIFY_FAILED
   Warning: PR #$OPEN_PR is open but not yet merged.
   /verify is designed to run after merge. Please merge PR #$OPEN_PR first, then re-run `/verify $ISSUE_NUMBER`.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "OPEN_PR" "skills/verify/SKILL.md" --> Step 2 に OPEN PR 検出ロジックが追加されている
- <!-- verify: grep "open but not yet merged\|未マージ" "skills/verify/SKILL.md" --> 警告メッセージが追加されている
- <!-- verify: rubric "OPEN PR が存在する場合に VERIFY_FAILED マーカー出力と早期終了を行う処理が verify スキルの Step 2 に追加されている" --> 早期警告ロジックが実装されている

### Post-merge

- (なし)

## Notes

- 挿入位置は「`PR_NUMBER` が空かつ `--base` 未指定の場合」の分岐内、`BASE_BRANCH=main` 設定直後、`git checkout` の前
- `--base` が明示指定された場合は OPEN PR 検出を行わない（`--base` 分岐に入る時点で merged PR 検索ごとスキップされるため）
- 複数 OPEN PR が存在する場合は `.[0].number` で最初の PR のみを警告対象とする（既存の merged PR 検索と同パターン）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue本文にAuto-Resolved Ambiguity Pointsが事前記録されており、受け入れ条件の曖昧さが最小化されていた。verifyコマンドも具体的で自動検証に適した形式。

#### design
- Spec（`issue-283-verify-open-pr-warn.md`）は変更ファイル・挿入位置・条件分岐が明確に記述されており、実装との乖離なし。

#### code
- 単一コミット（`e6d4654`）でSpec通り実装。reworkなし。パッチルート（直接main）は小規模変更として適切な判断。

#### review
- パッチルート（PR不使用）のため正式レビューなし。変更規模（14行追加）はパッチルートに適切。

#### merge
- `closes #283` を含むコミットで直接mainへ適用。コンフリクトなし。

#### verify
- 全3条件がPASS（grep×2、rubric×1）。verifyコマンドがIssue本文の受け入れ条件と完全一致しており、自動検証率100%。

### Improvement Proposals
- N/A
