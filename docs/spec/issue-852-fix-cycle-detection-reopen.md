# Issue #852: auto: Fix-cycle Detection を verify-fail marker 不在の reopen ケースまで拡張

## Overview

`/auto $N` で reopen 後の Issue を処理する際、Fix-cycle Detection (Step 2a) が verify-fail marker を
必須 criterion としているため、verify-fail marker 不在の reopen ケースを fix-cycle として認識できない。
結果として `reconcile-phase-state.sh code-patch --check-completion` が stale な `phase/verify` ラベルを
根拠に completion: true を返し、code phase がスキップされる。

本 Issue では以下 2 点を修正する:
- A) SKILL.md Step 2a Fix-cycle Detection の criterion を OR 拡張 (verify-fail marker OR reopened-after-merge)
- B) `_completion_code_patch` fallback ブロックで `reopen_ts != null` のケースに `_handle_mismatch` を呼ぶ

## Reproduction Steps

1. Issue に `phase/verify` ラベルが残存したまま reopen される (前回 close 時の label)
2. `/auto $N` → Step 2a: verify-fail marker なし → criterion 1 不満足 → 通常 Step 3 へ進む
3. Step 3 で `phase/verify` ラベルが unexpected path を引き起こす
4. `reconcile-phase-state.sh code-patch --check-completion` が呼ばれる
5. `reopen_ts` が非 null (issue は reopen されている) → fresh commit 検索 → 見つからない → fallback へ
6. fallback: `phase/verify` ラベル検出 → `completion: true` を emit
7. `run-auto-sub.sh` は code phase を「既に完了」扱いでスキップ → 新 AC 実装が走らない

## Root Cause

**Fix B (メイン):** `scripts/reconcile-phase-state.sh` `_completion_code_patch` の fallback ブロック (line
~235) が `reopen_ts` の値に関係なく `phase/verify` ラベルを completion の根拠として扱う。`reopen_ts != null`
のケースでは `phase/verify` は前回の verify run で付いた stale なラベルであり、completion の根拠にならない。

**Fix A (補完):** SKILL.md Step 2a の criterion 1 が verify-fail marker のみを check しているため、
verify-fail marker なしで reopen された Issue を fix-cycle と認識できない。criterion の OR 拡張と
`phase/verify` ラベルの criterion 2 緩和が必要。

## Changed Files

- `scripts/reconcile-phase-state.sh`: `_completion_code_patch` fallback ブロックに `reopen_ts != null`
  チェックを追加 — bash 3.2+ compatible
- `tests/reconcile-phase-state.bats`: reopen_ts 非 null + phase/verify + fresh commit なし →
  matches_expected false のテストを追加
- `skills/auto/SKILL.md`: Step 2a Fix-cycle Detection の criterion 1 を OR 拡張、criterion 2 を緩和、
  reopen ケースで phase/verify → phase/ready reset ロジックを追加

## Implementation Steps

1. `scripts/reconcile-phase-state.sh` `_completion_code_patch` 修正 (→ AC3)

   fallback ブロック (line ~230 以降) を以下のように変更する:

   ```bash
   # Fallback: check phase labels or issue state for async external commit areas.
   local labels state
   labels=$(gh issue view "$ISSUE_NUMBER" --json labels -q '.labels[].name' 2>/dev/null) || true
   state=$(gh issue view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null) || true

   # When issue was reopened (reopen_ts != null), phase/verify is stale from the previous
   # verify run and must not be treated as a completion signal.
   if [[ -n "$reopen_ts" && "$reopen_ts" != "null" ]]; then
     _handle_mismatch "$mismatch_diag" "$actual_json"
     return
   fi

   if echo "$labels" | grep -qE '^phase/(verify|done)$' || [[ "$state" == "CLOSED" ]]; then
     _emit_result "true" "async external commit area: closes #${ISSUE_NUMBER} not in git log but phase label or state confirms completion" "$actual_json"
     return
   fi
   ```

   注意: 既存の `reopen_ts` 変数は関数スコープ全体で定義されているため、fallback ブロックから直接参照可能。

2. `tests/reconcile-phase-state.bats` 新テスト追加 (→ AC4, AC5)

   既存の "async external commit" テスト (line ~961) の直後に追加:

   ```bash
   @test "code-patch completion: reopen_ts non-null + phase/verify label + no fresh commit -> matches_expected false" {
       cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
   #!/bin/bash
   echo "2026-06-01T00:00:00Z"
   exit 0
   MOCK_EOF
       chmod +x "$MOCK_DIR/gh-graphql.sh"

       cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
   #!/bin/bash
   if [[ "$*" == *"--json labels"* ]]; then echo "phase/verify"; exit 0; fi
   if [[ "$*" == *"--json state"* ]]; then echo "OPEN"; exit 0; fi
   exit 0
   MOCK_EOF
       chmod +x "$MOCK_DIR/gh"

       cat > "$MOCK_DIR/git" << 'MOCK_EOF'
   #!/bin/bash
   if [[ "$1" == "fetch" ]]; then exit 0; fi
   if [[ "$1" == "log" ]]; then echo ""; fi
   exit 0
   MOCK_EOF
       chmod +x "$MOCK_DIR/git"
       export PATH="$MOCK_DIR:$PATH"

       run bash "$SCRIPT" code-patch 55 --check-completion --strict
       [ "$status" -eq 1 ]
       [[ "$output" == *'"matches_expected":false'* ]]
   }
   ```

3. `skills/auto/SKILL.md` Step 2a 拡張 (→ AC1, AC2)

   **Criterion 1** を以下に置き換える:

   > 1. **verify-fail marker exists OR Issue has been reopened after the most recent merge**:
   >    - verify-fail marker check: At least one Issue comment contains `<!-- wholework-event: type=verify-fail`
   >    - OR reopened check: `gh-graphql.sh --query get-last-reopen -F "num=$NUMBER"` が非 null のタイムスタンプを返す
   >    - いずれか一方が真であれば criterion 1 を満たす

   **Criterion 2** を以下に緩和する:

   > 2. **No `phase/code`, `phase/review`, `phase/spec` labels present**: (phase/verify は許容する)

   **fix-cycle 検出時のアクション** に以下を追記する:

   > - verify-fail marker なし (reopen のみで検出した場合): `phase/verify` ラベルが残存している可能性があるため、
   >   code phase 実行前に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER ready` を実行して
   >   `phase/verify` を `phase/ready` に reset する。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md Step 2a (Fix-cycle Detection) の criterion 1 が verify-fail marker exists 単独ではなく、reopened-after-merge 等の OR 条件を含むよう拡張されている" --> SKILL.md Step 2a criterion 1 が OR 条件に拡張されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "### Step 2a: Fix-cycle Detection" "reopened" --> SKILL.md Step 2a に "reopened" キーワードが追加されている (criterion 拡張の裏付け)
- <!-- verify: rubric "scripts/reconcile-phase-state.sh の _completion_code_patch 関数で、reopen_ts が利用可能 (非 null) かつ fresh commit なし の状態では phase/verify ラベルを根拠に completion: true を返さないよう変更されている" --> reconcile-phase-state.sh で reopen_ts != null 時に phase/verify を根拠にした completion が阻止されている
- <!-- verify: grep "reopen.*phase/verify|phase/verify.*reopen" "tests/reconcile-phase-state.bats" --> bats test に reopen + phase/verify の組み合わせを検証するテストが追加されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> bats tests/reconcile-phase-state.bats が全件 PASS する

### Post-merge

- 次回 reopen 後の Issue に対して `/auto $N` を実行した際、code phase が正しく実行されることを観察

## Notes

- **自動解決済み曖昧ポイント** (Issue retrospective コメントより転記):
  - Fix 適用スコープ (code-patch のみ): `_completion_code_pr` は open PR 有無チェックであり phase/verify
    フォールバックが存在しない。code-patch ルートのみに修正を適用する。
  - criterion 2 緩和範囲: phase/verify のみ許容。phase/done は reopen 後のシナリオで通常発生しない想定。
  - reopen_ts 変数の参照可否: `_completion_code_patch` 内で `local reopen_ts` として定義されているため
    fallback ブロックから直接参照可能。追加変数不要。
- `reopen_ts != null` チェックを fallback ブロックの先頭に移動することで、CLOSED 状態や phase/done は
  引き続き completion の根拠として機能する (reopen + re-close の場合: fresh commit check で通常検出済み)。
- 既存テスト "async external commit - no closes #N + phase/verify label -> matches_expected true" は
  `reopen_ts == null` (gh-graphql.sh が "null" を返す) のケースであり、本 fix 後も変更不要。

## Consumed Comments

- `saito` (MEMBER / first-class): Issue Retrospective コメント — 曖昧ポイントの自動解決ログ (Fix 適用スコープ、criterion 2 緩和範囲、reopen_ts 参照可否) および AC 変更内容 (verify command 追加、テスト実装注意点) を記録

## Code Retrospective

### Deviations from Design

- `skills/auto/SKILL.md` の allowed-tools に `gh-graphql.sh` が未登録だったため validate-skill-syntax.py でエラーが発生。Spec には記載がなかったが `${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*` を追加して解消した。
- Spec の Implementation Step 1 では fallback ブロック全体を新しいコードで置き換える形で記述されていたが、実際には既存の labels/state 取得コードを保持し、`reopen_ts != null` チェックのみ先頭に挿入する最小変更で実装した (意図は同じ)。

### Design Gaps/Ambiguities

- `docs/workflow.md` の Fix-cycle Detection 説明文も古い criteria を記述していたため更新が必要だったが、Spec には記載がなかった。実装中に発見して追加した (`docs/ja/workflow.md` も同様)。

### Rework

- `skills/auto/SKILL.md` の allowed-tools への `gh-graphql.sh` 追加は validate-skill-syntax.py エラーが発覚してから行ったため、1 コミットで完結できなかった。Spec の stale-test-check に相当するチェックを allowed-tools 側にも事前に行うべきだった。

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- None found. Implementation matches the Spec exactly for all 3 fixes (reconcile-phase-state.sh fallback guard, SKILL.md Step 2a OR extension, bats test). The Code Retrospective's noted deviations (minimal-change approach, allowed-tools addition, workflow.md sync) were all correctly classified as out-of-spec discoveries handled during /code.

### Recurring Issues

- None. No repeated issue types across the 4 review perspectives.

### Acceptance Criteria Verification Difficulty

- All 5 pre-merge ACs were auto-verifiable (2 rubric, 1 section_contains, 1 grep, 1 command via CI fallback). No UNCERTAINs encountered.
- One SHOULD finding identified by review-light: `get-last-reopen` GraphQL query returns any reopen event without merge-time filtering, creating a false-positive fix-cycle detection risk in SKILL.md Step 2a. This is a behavior scope concern beyond the AC definitions — no verify command would have caught it pre-merge.

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- All 5 pre-merge ACs PASS; CI all SUCCESS. No MUST issues found.
- SHOULD finding (get-last-reopen without merge-time cross-check) skipped — out of scope for this Bug fix PR; should be tracked as a follow-up Issue.
- Review posted as COMMENT event (no REQUEST_CHANGES).

### Deferred Items
- SHOULD: `get-last-reopen` query returns any reopen event with no merge-time filter → could produce false-positive fix-cycle detection if Issue is reopened before any merge. Consider a follow-up Issue to add merge-time cross-check in SKILL.md Step 2a.
- post-merge AC (verify-type: manual) remains for /verify phase.

### Notes for Next Phase
- No MUST issues → `/merge 855` can proceed immediately.
- post-merge AC requires manual observation on the next `/auto $N` run after a reopen.
