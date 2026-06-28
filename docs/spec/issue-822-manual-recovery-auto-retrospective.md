# Issue #822: auto: manual recovery 経路での sub-issue Spec への Auto Retrospective 自動追記

## Overview

`run-auto-sub.sh` の Tier 2/Tier 3 recovery path では `_write_tier2_recovery_to_spec()` / `_write_tier3_recovery_to_spec()` が Spec の `## Auto Retrospective` セクションを自動更新する。しかし parent session が `worktree-merge-push.sh` / `gh pr create` / `run-*.sh` 再実行などを手動で呼び出す **manual recovery 経路** はこのカバレッジ外。

本 Issue は `run-auto-sub.sh` に `--write-manual-recovery ISSUE PHASE RECOVERY_TYPE` サブコマンドを追加し、parent session が manual recovery を実行した際に Spec の `## Auto Retrospective` へ recovery 情報を自動追記できるようにする。あわせて `modules/orchestration-fallbacks.md` に `## manual-recovery-spec-write` エントリを追加し、`skills/auto/SKILL.md` Step 6 と `skills/verify/SKILL.md` Step 12 を対応させる。

## Consumed Comments

- saito (MEMBER / first-class) — `/issue 822` non-interactive 実行時の Auto-Resolve Log。実装場所 = `run-auto-sub.sh`、文書化場所 = `orchestration-fallbacks.md`、test 場所 = `tests/run-auto-sub.bats` を自動解決済。URL: https://github.com/saitoco/wholework/issues/822#issuecomment-4826520796

## Changed Files

- `scripts/run-auto-sub.sh`: `set -euo pipefail` 直後 (`SUB_NUMBER` 代入前) に `_write_manual_recovery_to_spec()` 関数と `--write-manual-recovery` サブコマンド dispatch を追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `## manual-recovery-spec-write` エントリを `## wrapper-retry-on-kill` と `## Operational Notes` の間に追加; `## Operational Notes` に "Manual path" 小節を追記
- `tests/run-auto-sub.bats`: manual recovery spec-write の bats test を追加 (`"run-auto-sub: manual recovery: writes Auto Retrospective to spec file"`)
- `skills/auto/SKILL.md`: Step 6 "Manual recovery hand-off" 注釈を更新し `--write-manual-recovery` 呼び出しを明記
- `skills/verify/SKILL.md`: Step 12 の Tier 2/3 automatic recovery handling 記述を更新し "Manual recovery" 記録も "already recorded" 扱いとする

## Implementation Steps

**Step 1**: `scripts/run-auto-sub.sh` に `_write_manual_recovery_to_spec()` 関数と `--write-manual-recovery` dispatch を追加 (→ AC1)

`set -euo pipefail` の直後 (line 7 と `SUB_NUMBER` 代入の間) に以下を挿入する。既存の `_write_tier3_recovery_to_spec()` と対称的な構造にすること:

```bash
# --write-manual-recovery subcommand: write manual recovery record to sub-issue Spec.
# Usage: run-auto-sub.sh --write-manual-recovery ISSUE [PHASE] [RECOVERY_TYPE]
# See modules/orchestration-fallbacks.md#manual-recovery-spec-write
_write_manual_recovery_to_spec() {
  local issue="$1"
  local phase="${2:-unknown}"
  local recovery_type="${3:-unspecified}"
  local _script_dir="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
  local _repo_root
  _repo_root="$(dirname "$_script_dir")"
  local spec_dir="$_repo_root/docs/spec"
  local spec_file
  spec_file=$(ls "$spec_dir/issue-${issue}-"*.md 2>/dev/null | head -1 || true)

  if [[ -z "$spec_file" ]]; then
    local title
    title=$(gh issue view "$issue" --json title -q '.title' 2>/dev/null || echo "Issue #${issue}")
    mkdir -p "$spec_dir"
    spec_file="$spec_dir/issue-${issue}-recovery.md"
    printf '%s\n' "# Issue #${issue}: ${title}" > "$spec_file"
  fi

  if ! grep -q "^## Auto Retrospective" "$spec_file" 2>/dev/null; then
    printf '\n%s\n' "## Auto Retrospective" >> "$spec_file"
  fi

  local _date
  _date=$(date -u '+%Y-%m-%d %H:%M UTC')
  printf '\n%s\n' "### Manual recovery (${phase})" >> "$spec_file"
  printf '%s\n' "- **Date**: ${_date}" >> "$spec_file"
  printf '%s\n' "- **Issue**: #${issue}, phase: ${phase}" >> "$spec_file"
  printf '%s\n' "- **Source**: parent session manual recovery" >> "$spec_file"
  printf '%s\n' "- **Recovery type**: ${recovery_type}" >> "$spec_file"
  printf '%s\n' "- **Outcome**: success" >> "$spec_file"

  local spec_rel_path="${spec_file#$_repo_root/}"

  if ! git -C "$_repo_root" diff --quiet "$spec_rel_path" 2>/dev/null; then
    if git -C "$_repo_root" add "$spec_rel_path" \
       && git -C "$_repo_root" commit -s -m "Record manual recovery in auto retrospective for issue #${issue}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" \
       && git -C "$_repo_root" push origin HEAD; then
      echo "[#${issue}] [recovery] spec auto retrospective updated for issue #${issue} (manual recovery)"
    else
      echo "[#${issue}] WARNING: could not commit/push manual recovery to spec; continuing" >&2
    fi
  fi
}

if [[ "${1:-}" == "--write-manual-recovery" ]]; then
  shift
  if [[ -z "${1:-}" ]]; then
    echo "Error: --write-manual-recovery requires: ISSUE [PHASE] [RECOVERY_TYPE]" >&2
    exit 1
  fi
  _write_manual_recovery_to_spec "$@"
  exit 0
fi
```

**Step 2**: `modules/orchestration-fallbacks.md` に `## manual-recovery-spec-write` エントリを追加 (→ AC2)

`## wrapper-retry-on-kill` と `## Operational Notes` の間に挿入する。スキーマは既存エントリ (Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale) に従う:

- **Symptom**: parent session が `worktree-merge-push.sh` / `gh pr create` / `run-*.sh` 再実行を手動で呼び出し、sub-issue の Tier 1/2/3 自動回復とは独立した manual recovery を実行した
- **Applicable Phases**: code, review, merge (XL sub-issue の parent session manual recovery)
- **Fallback Steps**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE` を実行し `_write_manual_recovery_to_spec()` に委譲する。RECOVERY_TYPE は取った行動を説明する文字列 (例: `push-only`, `pr-create`, `review-rerun`)
- **Escalation**: スクリプトが非ゼロで終了した場合は warning をログに出力して続行 (spec write 失敗は非致命的)
- **Rationale**: #822 で実装。#800 の Tier 3 path と対称性を持ち、`## Auto Retrospective` セクションへの追記形式 (`### Manual recovery (phase)`) を統一する

また `## Operational Notes` に "Manual path: Spec Auto Retrospective write" 小節を追記し、Tier 2/3 小節と対称的に機構を説明する。

**Step 3**: `tests/run-auto-sub.bats` に bats test を追加 (→ AC3)

既存の `"run-auto-sub: tier3 recovery: writes Auto Retrospective to spec file"` テスト (line 749) の直後に追加する:

```bash
@test "run-auto-sub: manual recovery: writes Auto Retrospective to spec file" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"diff"* && "$*" == *"issue-42"* ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -q "Manual recovery" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -qE "commit.*manual recovery" "$GIT_LOG"
}
```

**Step 4**: `skills/auto/SKILL.md` Step 6 "Manual recovery hand-off" 注釈を更新 (→ post-merge 観察)

現在のテキスト:
> "then follow Step 4a (after all phases are done) to append anomaly details and improvement proposals to the Spec's `## Auto Retrospective > ### Orchestration Anomalies` and `### Improvement Proposals` sections, then proceed to Step 5."

更新後のテキスト (既存文を置き換え):
> "then call `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE` to automatically write the recovery record to the sub-issue Spec's `## Auto Retrospective` section (where RECOVERY_TYPE describes the action taken, e.g., `push-only`, `pr-create`, `review-rerun`). Then proceed to Step 5."

Note: 既存 Tier 2 anomaly detector がパターンを追記済みの場合は `--write-manual-recovery` 呼び出しをスキップして重複を避ける旨を保持する。

半角 `!` 禁止 / decimal step 禁止に注意して編集する。

**Step 5**: `skills/verify/SKILL.md` Step 12 skip 判定を更新 (→ post-merge 観察)

"Tier 2/3 automatic recovery handling" セクション (line ~654-657) の以下の記述を更新:

現在: "check whether `## Auto Retrospective` exists and contains 'Tier 2' or 'Tier 3' recovery records"

更新後: "check whether `## Auto Retrospective` exists and contains 'Tier 2', 'Tier 3', or 'Manual recovery' records"

あわせて "already recorded" 判定ルールの説明文に manual recovery を含める: "`_write_manual_recovery_to_spec()` で追記された `### Manual recovery (phase)` エントリも 'already recorded' として扱い、verify retrospective での重複記録を省略する。"

## Alternatives Considered

**A. `worktree-merge-push.sh` に `--write-to-spec` オプション追加 (不採用)**
- 設計案1の「既存スクリプトへのオプション追加」に相当
- メリット: manual recovery で最も頻繁に呼ばれる `worktree-merge-push.sh` に統合できる
- デメリット: `worktree-merge-push.sh` は push-only を想定しており spec write ロジックを持たせると単一責任原則に反する。また `review-rerun` 経路 (`run-review.sh` 再実行) はカバーできない
- 採用案: `run-auto-sub.sh` に集約し `_write_tier2`/`_write_tier3` との対称性を保持

**B. 新規独立スクリプト `scripts/write-manual-recovery-to-spec.sh` (不採用)**
- 設計案1の「新規 wrapper script 新設」に相当
- メリット: 単機能スクリプトで依存が明確
- デメリット: `run-auto-sub.sh` の `_write_tier2`/`_write_tier3` と実質同じロジックが別ファイルに存在し保守コストが増える。`allowed-tools` への追加も必要
- 採用案: 既存 `run-auto-sub.sh` に新サブコマンドを追加してロジック集約

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh または新規 manual recovery 専用スクリプトで、parent session manual recovery 時に docs/spec/issue-N-*.md の ## Auto Retrospective セクションに recovery 情報を自動追記する関数 (_write_manual_recovery_to_spec 等) が実装されており、_write_tier3_recovery_to_spec と対称的な構造 (spec_dir 参照、git add+commit+push、セクション存在確認) を持つ" --> manual recovery 経路で Spec の `## Auto Retrospective` に自動追記する関数が実装されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md に manual-recovery-spec-write エントリが追加されており、Tier 3 path との対称性 (同じ ## Auto Retrospective セクションへの追記) が記述されている" --> <!-- verify: grep "manual-recovery-spec-write" "modules/orchestration-fallbacks.md" --> `modules/orchestration-fallbacks.md` に `manual-recovery-spec-write` エントリが追加されている
- <!-- verify: rubric "tests/run-auto-sub.bats で manual recovery wrapper 呼び出し時に Spec の ## Auto Retrospective に追記される動作を assert する test が追加されている" --> <!-- verify: grep "manual.*recovery" "tests/run-auto-sub.bats" --> bats test で manual recovery → Spec write 動作が assert されている

### Post-merge

- 次回 manual recovery 発生時に対象 sub-issue の Spec に `## Auto Retrospective` が自動追記されることを観察

## Notes

- **Auto-Resolve Log** (non-interactive 処理):
  - 実装場所: `run-auto-sub.sh` への新関数追加 (primary) — `_write_tier2`/`_write_tier3` との対称性原則に基づく
  - 文書化場所: `modules/orchestration-fallbacks.md` — fallback/recovery パターンカタログへの追記が最自然
  - bats test 追加先: `tests/run-auto-sub.bats` — Tier 3 recovery の Spec write テスト (line 749) と symmetric

- **`_write_manual_recovery_to_spec()` の SCRIPT_DIR 参照**: 他の Tier 2/3 関数とは異なり、`--write-manual-recovery` dispatch は `set -euo pipefail` 直後に配置されるため `SCRIPT_DIR` が未定義。関数内では `WHOLEWORK_SCRIPT_DIR` (テスト用) または `$(dirname "$0")` (本番用) でパスを自己解決する。bats テストは `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` を設定することで `_repo_root = $(dirname $MOCK_DIR) = $BATS_TEST_TMPDIR` が得られる — 既存 tier2/tier3 テストの `git -C "$_repo_root"` pattern と同一の mock 戦略

- **`skills/verify/SKILL.md` Step 12 更新の必要性**: 現在の skip 判定は `## Auto Retrospective` に "Tier 2" または "Tier 3" の文字列があれば "already recorded" と判断する。`_write_manual_recovery_to_spec()` が書く `### Manual recovery (phase)` エントリは "Manual recovery" を含むため、Step 12 を更新して "Manual recovery" も同等に扱う必要がある

- **`allowed-tools` への追加不要**: `skills/auto/SKILL.md` の `allowed-tools` には既に `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` が含まれており、`--write-manual-recovery` サブコマンドもカバーされる

- **テスト内の commit メッセージ grep パターン**: `grep -qE "commit.*manual recovery"` → `_write_manual_recovery_to_spec()` のコミットメッセージは `"Record manual recovery in auto retrospective for issue #N"` なので `"commit.*manual recovery"` にマッチする (git log の形式 `commit <message>` の後半)

## issue retrospective

非対話モード (`--non-interactive`) で `/issue 822` を実行した際の自動解決記録。

### 曖昧ポイントの自動解決

以下の3点を codebase パターンから自動解決した。

#### 1. 実装場所

**解決**: `scripts/run-auto-sub.sh` への新関数追加を primary target とした (新規 manual recovery 専用スクリプトも許容)。

**根拠**:
- `_write_tier3_recovery_to_spec()` (line 148) と `_write_tier2_recovery_to_spec()` (line 110) の両方が `scripts/run-auto-sub.sh` に実装されている
- 対称性原則に基づき、manual recovery 関数も同ファイルへの追加が最自然
- parent session からの standalone 呼び出しが必要な場合は wrapper entrypoint を別途設けることを許容

#### 2. 文書化場所

**解決**: `modules/orchestration-fallbacks.md` に `## manual-recovery-spec-write` エントリを追加。

**根拠**:
- `orchestration-fallbacks.md` は既存の orchestration-level failure パターンのカタログ
- manual recovery 経路の spec write は同ファイルに追記するのが既存パターンと一致

#### 3. bats test 追加先

**解決**: `tests/run-auto-sub.bats` に追加。

**根拠**:
- Tier 3 recovery の Spec write テスト (line 749) が `tests/run-auto-sub.bats` に存在
- symmetric な manual recovery テストも同ファイルへの追加が最も一貫性がある

## spec retrospective

### Minor observations
- Nothing to note

### Judgment rationale
- `_write_manual_recovery_to_spec()` を `set -euo pipefail` 直後に配置した理由: bash の関数は定義後に呼び出し可能。`--write-manual-recovery` dispatch を `SUB_NUMBER` 代入前に置く必要があるため、関数定義もその前に配置した。ロジックを `_write_tier3` と同じ場所 (line 148 近傍) に置くよりも重複呼び出しリスクが低い
- `skills/verify/SKILL.md` Step 12 の更新が必要という判断: Issue body には明示されていないが、"verify session での手動補完が不要になる" という目的には `/verify` が "already recorded" と判定できることが必要。非対話モードで自動解決した

### Uncertainty resolution
- Nothing to note

## Code Retrospective

### Deviations from Design
- `_write_manual_recovery_to_spec()` は Spec に記述の通り `set -euo pipefail` 直後に配置した。設計と一致

### Design Gaps/Ambiguities
- `skills/auto/SKILL.md` の更新で "then follow Step 4a (after all phases are done)" という旧文が `--write-manual-recovery` 呼び出しに完全置換された。Step 4a の `### Orchestration Anomalies` / `### Improvement Proposals` 参照が失われる懸念があったが、`--write-manual-recovery` は recovery record のみ書き込む機能に特化しており、Improvement Proposals は verify phase が担当するという役割分担で整合している

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns
- Spec の 5 実装ファイルはすべて PR diff に反映されており、構造的な乖離なし
- `_write_manual_recovery_to_spec()` の配置 (set -euo pipefail 直後) も Spec 記述と一致

### Recurring issues
- `git diff --quiet` が untracked ファイルを検出できない問題が `scripts/run-auto-sub.sh` の `_write_manual_recovery_to_spec()` (line 46) に存在。既存の `_write_tier2_recovery_to_spec()` (line 196)、`_write_tier3_recovery_to_spec()` (line 243) にも同じパターンが繰り返されており、共通ヘルパー関数化または `git status --porcelain` への統一修正が効果的。後続 Issue として起票を推奨
- `_write_manual_recovery_to_spec()` に `$issue` の数値バリデーションがなく、フォールバックパスでパストラバーサルが可能 (SHOULD)。既存 Tier 2/3 も同様であり、横断的な修正 Issue の余地あり

### Acceptance criteria verification difficulty
- rubric + grep の組み合わせで AC 検証が機械的に実施でき、UNCERTAIN なし
- bats test の verify command (grep "manual.*recovery") が実装を直接確認できており verify command の品質は良好
- POST-MERGE 観察条件 1 件は verify phase が担当

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST 問題は検出されず。SHOULD 4 件、CONSIDER 1 件をラインコメントとして記録
- `git diff --quiet` vs untracked files バグ (SHOULD) は Tier 2/3 にも共通する既知パターンであるため、本 PR のブロッカーとはしない判断
- セキュリティ所見 (path traversal via `$issue`) は内部ツール文脈 + `-recovery.md` 固定サフィックスの制約から SHOULD 止まりとした

### Deferred Items
- `git diff --quiet` → `git status --porcelain` の横断修正は別 Issue で対応推奨
- `$issue` / `$phase` / `$recovery_type` の入力バリデーション追加も別 Issue 候補
- "Manual automatic recovery" の表現矛盾は次回 cleanup で修正

### Notes for Next Phase
- CI 全 SUCCESS、MUST 未検出につき `/merge 830` で直接 merge 可能
- merge 後は next-cycle-seed または verify セッションで上記 SHOULD 問題の起票を検討
