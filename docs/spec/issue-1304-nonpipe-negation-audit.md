# Issue #1304: test-runner: pipe を伴わない否定アサーション 78 件を棚卸しし検出力ゼロの箇所を解消

## Consumed Comments

| login | authorAssociation | trust tier | 要旨 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue` Existing Issue Refinement Step 15 の triage AC audit。AC1 (`section_contains ... "Out of Scope" "pipe"`) が現状の main で既に PASS する常時 PASS 欠陥 (Pattern 2) であることを実測付きで指摘し、「本 Issue の作業後にのみ真になる状態を対象にする」修復案を提示。AC2〜AC5 は問題なしと判定 | https://github.com/saitoco/wholework/issues/1304#issuecomment-5229888761 |

本 Spec は当該コメントを消費し、AC1 を `section_not_contains` 形式へ差し替えた (Notes § Auto-Resolve Log 参照)。

## Overview

`tests/*.bats` に残る **pipe を伴わない否定アサーション**を #1292 と同じ判定基準 (非最終文なら defective、真の最終文なら safe) で棚卸しし、検出力ゼロのアサーションを `if cmd; then false; fi` 形式へ書き換える。

Spec フェーズで全 76 件を機械的に分類した結果、**defective 26 件 / safe 50 件**が確定した。加えて Issue 本文が `/spec` に判断を委ねていた「grep を伴わない裸の `!` 否定」は実測 2 件のみで、2 件とも defective であったため本 Issue に編入する (Notes § Auto-Resolve Log 参照)。合計 **28 件**の書き換えとなる。

さらに、#1292 が pipe 形式にスコープ限定して 76 件を見落とした直接原因である `modules/test-runner.md` の記述 (問題形式を `! cmd | grep -q pattern` と例示) を一般化し、判定が pipe の有無に依存しないことを SSoT 側に明記する。

## Changed Files

### SSoT / ドキュメント

- `modules/test-runner.md`: `### bats Negation Assertion Pitfall` に `#### Scope — the pipe is irrelevant` (h4) を追加し、`! grep -q pattern file` のような pipe なし形式にも同じ判定が適用されること、分類は表層形ではなく「真の最終文かどうか」で行うことを明記する。文字列 `regardless of whether a pipe is present` を含めること (AC7 の照合キー)。`!` は必ずインラインコード内に置く
- `tests/test-runner.bats`: 既存の shallow presence test の慣行に従い `@test "test-runner: negation pitfall is documented as pipe-independent"` を末尾に追加 (`grep -q -F "regardless of whether a pipe is present" "$TEST_RUNNER"`)
- `docs/reports/bats-negation-assertion-audit.md`: H1 と `## Purpose` を #1292/#1304 両対応に更新、`## Non-Piped Form Audit (Issue #1304)` (h2) と `## Bare Negation Audit (Issue #1304)` (h2) を新設、`## Out of Scope` を書き換え (見出しは残す)、`## Remediation Record` に #1304 分を追記

### 非 pipe + grep 形式の defective 26 件 (12 ファイル)

- `tests/ci-failure-classifier.bats`: 30, 35 行目を書き換え
- `tests/gh-graphql.bats`: 69, 240, 242, 286, 333 行目を書き換え
- `tests/observation-trigger.bats`: 76, 198 行目を書き換え (76 は `if ... fi` 内のため構造を変える — Notes § 個別対応)
- `tests/opportunistic-search.bats`: 513 行目を書き換え
- `tests/orchestration-fallbacks.bats`: 92 行目を書き換え (93 は safe のため据え置き)
- `tests/retro-proposals.bats`: 149 行目を書き換え (142 は safe のため据え置き)
- `tests/run-code.bats`: 470 行目を書き換え (400, 471 は safe のため据え置き)
- `tests/run-issue.bats`: 306, 339 行目を書き換え (236, 307, 340 は safe のため据え置き)
- `tests/run-merge.bats`: 757 行目を書き換え (328, 415, 729, 758 は safe のため据え置き)
- `tests/run-review.bats`: 776 行目を書き換え (563, 748, 777 は safe のため据え置き)
- `tests/run-spec.bats`: 393, 428 行目を書き換え (206, 283, 394, 429 は safe のため据え置き)
- `tests/worktree-merge-push.bats`: 212, 313, 387, 388, 465, 623, 624 行目を書き換え (132, 162, 258, 355, 389, 670 は safe のため据え置き)

### 裸の `!` 否定 (grep なし) の defective 2 件

- `tests/reclaim-stale-worktrees.bats`: 136, 159 行目を書き換え

### 変更不要と判断したファイル (grep 検証済み)

- `docs/structure.md` / `docs/ja/structure.md`: `modules/test-runner.md` の一行説明は "quality check execution and result analysis" で役割自体は変わらないため更新不要 (`grep -rn "test-runner.md" docs/` で 2 件確認)
- `docs/ja/reports/`: `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示除外しているため ja ミラー不要 (実際に `docs/ja/reports/bats-negation-assertion-audit.md` は存在しない)
- `scripts/validate-skill-syntax.py`: `validate_modules_scripts_in_allowed_tools()` は `modules/*.md` が参照する `scripts/*.sh` を allowed-tools と突合するが、本 Issue の `modules/test-runner.md` 変更は散文追加のみで新規スクリプト参照を含まないため、reader SKILL.md の `allowed-tools` 更新は不要 (allowed-tools impact chain Case 2 の lightweight gate 不一致)

## Implementation Steps

1. 非 pipe + grep 形式の defective 26 件を `if cmd; then false; fi` 形式へ書き換える。既存の grep フラグ (`-q` / `-qE` / `-q -F` / `-q --`) とパターン文字列は一切変更しない (#1292 の前例を踏襲)。26 件はいずれも 1 行 → 1 行の置換であり行数が変わらないため、後続の書き換えで行番号がずれることはない。対象行の完全な一覧は Notes § defective インベントリ (26 件) を参照。safe と分類した 50 件は**一切変更しない** (→ acceptance criteria AC3, AC4)

2. 裸の `!` 否定 2 件 (`tests/reclaim-stale-worktrees.bats:136` の `! git -C "$MAIN_REPO" branch -d worktree-code+pr-1149 2>/dev/null`、`:159` の `! git -C "$MAIN_REPO" branch -d worktree-code+issue-5000 2>/dev/null`) を `if git -C "$MAIN_REPO" branch -d <branch> 2>/dev/null; then false; fi` へ書き換える。直前の `# sanity: plain -d must fail` コメントはそのまま残す (parallel with 1) (→ acceptance criteria AC4)

3. `modules/test-runner.md` の `### bats Negation Assertion Pitfall` 内、既存の `**Exception (safe case)**:` 段落の直後に `#### Scope — the pipe is irrelevant` (h4) を追加する。内容: (a) 同じ欠陥は pipe を全く含まない否定 (`! grep -q pattern file` のようにファイルを直接読む形) にも成立し、`regardless of whether a pipe is present` — `!` は pipe の有無によらずコマンドの終了ステータスを `set -e` の対象から外す; (b) したがって分類は表層形ではなく「当該行が `@test` の真の最終文かどうか」だけで行う; (c) 全形式の棚卸し結果は `docs/reports/bats-negation-assertion-audit.md` を参照。文字列 `regardless of whether a pipe is present` を逐語で含めること。`!` はインラインコード内にのみ書く (parallel with 1, 2) (→ acceptance criteria AC7)

4. `tests/test-runner.bats` の末尾に、既存の shallow presence test と同一の書式で以下を追加する: `@test "test-runner: negation pitfall is documented as pipe-independent" { grep -q -F "regardless of whether a pipe is present" "$TEST_RUNNER"; }` (否定を含まない素の `grep` のため本 Issue の落とし穴自体には該当しない)。(after 3) (→ acceptance criteria AC7 の構造的裏付け)

5. `docs/reports/bats-negation-assertion-audit.md` を更新する。(after 1, 2)
   - H1 を `# bats Negation Assertion Audit (Issues #1292, #1304)` に、`## Purpose` を両 Issue を対象とする記述に更新する
   - `## Non-Piped Form Audit (Issue #1304)` (h2) を `## Safe (true final statement) — 12 entries, no change` の直後に新設し、検索コマンド (`grep -rnE '^\s*!\s*.*grep' tests/*.bats | grep -vE '\|\s*grep'`)、測定スコープ (2026-08-09、`HEAD=f4d8fe6d`、`tests/*.bats` 直下)、サマリ行 `**76 matches total, across 21 files** — 26 defective, 50 safe.` (文字列 `26 defective` を逐語で含めること)、defective 26 件の表 (File:Line / 元の形 / 是正内容)、safe 50 件の一覧を記録する
   - `## Bare Negation Audit (Issue #1304)` (h2) を続けて新設し、`tests/reclaim-stale-worktrees.bats:136,159` の 2 件 (いずれも defective) を同じ書式で記録する
   - `## Out of Scope` は**見出しを残したまま**本文を書き換える。文字列 `Both categories are noted here for reference only` を削除し (AC1 の照合キー)、#1292 が out of scope としていた 2 カテゴリが本 Issue で解消済みであること、および `tests/*.bats` の先頭 `!` 否定 90 件の全体分割 (pipe 12 / 非 pipe+grep 76 / 裸 2) が全件棚卸し済みであることを記述する
   - `## Remediation Record` に #1304 で書き換えた 28 件を追記する
   - 記録後、`## Non-Piped Form Audit` と `## Bare Negation Audit` の defective 表の各行が `## Remediation Record` に対応記載を持つことを突合する (Findings/Remediation 整合、`skills/spec/skill-dev-constraints.md` #238)
   (→ acceptance criteria AC1, AC2, AC6)

6. `bats --jobs <N> tests/` を前景実行し全件 PASS を確認する (`<N>` は `nproc 2>/dev/null || sysctl -n hw.logicalcpu` で解決。`modules/test-runner.md` の並列実行ガイダンスに従う)。書き換えたアサーションが FAIL した場合は、それまで検出力ゼロで隠れていた真の欠陥が露出したことを意味する — アサーションの前提が正しければ被検証コード側を修正し、アサーションの前提自体が誤っていれば当該アサーションを訂正したうえで、いずれの場合も `## Remediation Record` にその旨を記録する (単に元の `!` 形式へ戻すことは禁止)。(after 1, 2, 4, 5) (→ acceptance criteria AC5)

## Verification

### Pre-merge

- <!-- verify: section_not_contains "docs/reports/bats-negation-assertion-audit.md" "Out of Scope" "Both categories are noted here for reference only" --> 既存監査レポートの `## Out of Scope` 節が本 Issue の棚卸し結果を反映して更新されている (`## Out of Scope` 見出し自体は残す)
- <!-- verify: rubric "docs/reports/bats-negation-assertion-audit.md に、非 pipe 形式 (`! grep -q pattern file` 等) の否定アサーションを defective (非最終文) / safe (真の最終文) に分類した結果が、ファイルまたはパターンごとの件数付きで記録されている" --> 非 pipe 形式の棚卸し結果が監査レポートに記録されている
- <!-- verify: command "test $(grep -c '^\s*! grep -q \"phase_start\"' tests/run-code.bats) -eq 0" --> 実測確認済みの defective 事例 (`tests/run-code.bats:470`) が書き換えられている
- <!-- verify: rubric "docs/reports/bats-negation-assertion-audit.md で defective と分類された非 pipe 形式のエントリ (grep を伴わない裸の `!` 否定 2 件を含む) が、すべて if cmd; then false; fi 形式へ書き換えられている。safe と分類されたエントリは変更されていないこと" --> defective のみが書き換えられ safe は据え置かれている
- <!-- verify: command "bats tests/" --> 既存テストスイートが PASS する
- <!-- verify: section_contains "docs/reports/bats-negation-assertion-audit.md" "Non-Piped Form Audit" "26 defective" --> 監査レポートの非 pipe 形式節に defective 件数が明記されている
- <!-- verify: file_contains "modules/test-runner.md" "regardless of whether a pipe is present" --> 落とし穴が pipe の有無に依存しないことが `modules/test-runner.md` に明記されている

### Post-merge

- 次回 bats テストを追加または変更する Issue で、否定アサーションが pipe の有無にかかわらず正しい形式で書かれていることを観察する

## Tool Dependencies

### Bash Command Patterns
- none (既存の `bats` / `grep` のみ。新規スクリプト追加なし)

### Built-in Tools
- none (`Read` / `Edit` / `Write` はいずれも `/code` の `allowed-tools` に登録済み)

### MCP Tools
- none

## Notes

### Auto-Resolve Log (non-interactive mode)

1. **AC1 の常時 PASS 欠陥を修復** (消費コメント由来 / Issue 本文へ反映済み)
   旧 AC1 `section_contains "docs/reports/bats-negation-assertion-audit.md" "Out of Scope" "pipe"` は、現行 `## Out of Scope` 節が既に `pipe` を複数箇所含むため実装前から PASS する。triage AC audit コメントの修復案「本 Issue の作業後にのみ真になる状態を対象にする」に従い `section_not_contains ... "Both categories are noted here for reference only"` へ差し替えた。当該文字列は現行レポート 102 行目に**単一行として**実在する (複数行にまたがる文字列は行指向マッチで永久に不一致になるため、単一行であることを確認済み)。`section_not_contains` は見出し不一致時に UNCERTAIN を返すため、実装では `## Out of Scope` 見出しを削除しない制約を Implementation Step 5 に明記した。

2. **裸の `!` 否定 2 件を本 Issue のスコープに含める** (Issue 本文が `/spec` に委任)
   Issue 本文は「件数と性質が異なる (意図的に失敗を許容している箇所が混ざる可能性)」を分割理由の候補として挙げていたが、実測の結果その前提が成立しなかった — 該当は `tests/reclaim-stale-worktrees.bats:136,159` の 2 件のみで、2 件とも直前に `# sanity: plain -d must fail (branch not fully merged into main)` という明示的な意図コメントを持つアサーションであり、意図的な失敗許容ではない。かつ両者とも非最終文 = 検出力ゼロ。同一機構・同一修正形式・2 件という規模から、別 Issue に分割する費用対効果がないと判断し編入した。これにより `tests/*.bats` の先頭 `!` 否定 90 件が全カテゴリ棚卸し済みとなり、監査レポートに未処理の残余カテゴリがなくなる。

3. **`modules/test-runner.md` の pipe 非依存性明文化を追加** (AC7 として新設)
   Issue の Purpose が「`modules/test-runner.md` の規約が実コードベース全体で守られている状態にする」と明示しており、かつ #1292 のスコープ限定 → 76 件見落としの直接原因が同ファイルの pipe 前提の例示であったため、恒久対策として範囲内と判断した。コード側 28 件の修正は一度きりだが、SSoT の記述を一般化しない限り同じスコープ誤りが再発する。

### 実装方針と verify command の整合

- Implementation Step 3 が書く逐語文字列 `regardless of whether a pipe is present` は AC7 (`file_contains "modules/test-runner.md" ...`) の照合キーと一致する。現状 `modules/test-runner.md` には存在しない (実装後に導入される文字列)
- Implementation Step 5 が書く逐語文字列 `26 defective` は AC6 (`section_contains ... "Non-Piped Form Audit" "26 defective"`) の照合キーと一致する。`## Non-Piped Form Audit` 節は現状存在しないため、実装前は UNCERTAIN、実装後に PASS となる
- AC1 の照合キー `Both categories are noted here for reference only` は現行 102 行目に存在する (実装前 FAIL → 実装後 PASS)
- AC3 の `grep -c` は実測で現在 1 件ヒット (実装前 FAIL)。書き換え後 0 件で PASS

### 実測値と #1292 監査レポートの記載の食い違い

#1292 の `## Out of Scope` は非 pipe 形式を「76 candidate lines across **roughly 30 files**」と記録しているが、実測のファイル数は **21 ファイル**である (件数 76 は一致)。Implementation Step 5 の新設節では実測値 21 を記録すること。

**測定スコープ** (`modules/measurement-scope.md` 準拠): 2026-08-09、`HEAD=f4d8fe6d`、対象は `tests/*.bats` 直下のみ (#1292 が `find tests -mindepth 2 -name "*.bats"` でサブディレクトリに `.bats` が存在しないことを確認済みのため非再帰 glob で漏れなし)。

`tests/*.bats` の先頭 `!` 否定 90 件の全体分割 (exhaustive):

| カテゴリ | 検索コマンド | 件数 | defective | safe |
|---|---|---|---|---|
| pipe 形式 | `grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats` | 12 | 0 (#1292 で 9 件修正済み) | 12 |
| 非 pipe + grep | 上記を `grep -vE '\|\s*grep'` で除外 | 76 | 26 | 50 |
| 裸の `!` (grep なし) | `grep -rnE '^\s*!\s' tests/*.bats \| grep -v grep` | 2 | 2 | 0 |
| **合計** | — | **90** | **28** | **62** |

### 分類手法

#1292 の `## Judgment Criteria` (非最終文なら defective、真の最終文なら safe) をそのまま踏襲。Spec フェーズでは以下の手順で機械的に分類した:

1. 候補行ごとに、直前の `@test ` 行から次の `@test ` 行 (または EOF) までを囲みブロックとみなす
2. そのブロック内で**最後に現れる**桁 0 の `}` をブロック終端とする (ヒアドキュメント内のモック本体に桁 0 の `}` が現れうるため、最初の `}` で打ち切ると誤って safe と判定する)
3. 候補行とブロック終端の間に空行・コメント以外の文が 1 つでもあれば defective

素朴な「最初の桁 0 の `}`」実装と上記実装の双方で 26/50 の同一結果が得られたことを確認済み。

### defective インベントリ (26 件)

Implementation Step 1 の対象。`->` の右は当該行の直後に続く文 (非最終文であることの根拠)。

| File:Line | 元の形 | 直後の文 |
|---|---|---|
| `tests/ci-failure-classifier.bats:30` | `! grep -q "The runner has received a shutdown signal" "$VERIFY_SKILL"` | `grep -q "modules/ci-failure-classifier.md" "$VERIFY_SKILL"` |
| `tests/ci-failure-classifier.bats:35` | `! grep -q "The runner has received a shutdown signal" "$VERIFY_EXECUTOR"` | `grep -q "modules/ci-failure-classifier.md" "$VERIFY_EXECUTOR"` |
| `tests/gh-graphql.bats:69` | `! grep -q "repo view" "$GH_CALL_LOG"` | `grep -q "api graphql.*-F owner=myowner" "$GH_CALL_LOG"` |
| `tests/gh-graphql.bats:240` | `! grep -q "api graphql" "$GH_CALL_LOG"` | `! grep -q "repo view" "$GH_CALL_LOG"` |
| `tests/gh-graphql.bats:242` | `! grep -q "repo view" "$GH_CALL_LOG"` | `cache_teardown` |
| `tests/gh-graphql.bats:286` | `! grep -q "repo view" "$GH_CALL_LOG"` | `grep -q "api graphql" "$GH_CALL_LOG"` |
| `tests/gh-graphql.bats:333` | `! grep -q "api graphql" "$GH_CALL_LOG"` | `cache_teardown` |
| `tests/observation-trigger.bats:76` | `! grep -q "issue comment" "$BATS_TEST_TMPDIR/gh-calls.log"` (`if ... fi` 内) | `fi` の後に `[ "$output" = "42" ]` |
| `tests/observation-trigger.bats:198` | `! grep -q "issue comment" "$BATS_TEST_TMPDIR/gh-calls.log"` | `[ "$output" = "42" ]` |
| `tests/opportunistic-search.bats:513` | `! grep -q -- "--session\|--facts-file" "$MOCK_DIR/collect-run-facts-args.txt"` | `echo "$output" \| jq -e 'length == 1' > /dev/null` |
| `tests/orchestration-fallbacks.bats:92` | `! grep -q '^## ci-flake-retry' "$CATALOG"` | `! grep -q '^## gh-pr-list-head-glob' "$CATALOG"` |
| `tests/retro-proposals.bats:149` | `! grep -q "/Users/" "$GH_CALLS_LOG"` | `grep -q "<absolute-path>" "$GH_CALLS_LOG"` |
| `tests/run-code.bats:470` | `! grep -q "phase_start" "$EMIT_LOG"` | `! grep -q "phase_complete" "$EMIT_LOG"` |
| `tests/run-issue.bats:306` | `! grep -q "phase_start" "$EMIT_LOG"` | `! grep -q "phase_complete" "$EMIT_LOG"` |
| `tests/run-issue.bats:339` | `! grep -q "wrapper_exit" "$EMIT_LOG"` | `! grep -q "token_usage" "$EMIT_LOG"` |
| `tests/run-merge.bats:757` | `! grep -q "phase_start" "$EMIT_LOG"` | `! grep -q "phase_complete" "$EMIT_LOG"` |
| `tests/run-review.bats:776` | `! grep -q "phase_start" "$EMIT_LOG"` | `! grep -q "phase_complete" "$EMIT_LOG"` |
| `tests/run-spec.bats:393` | `! grep -q "phase_start" "$EMIT_LOG"` | `! grep -q "phase_complete" "$EMIT_LOG"` |
| `tests/run-spec.bats:428` | `! grep -q "wrapper_exit" "$EMIT_LOG"` | `! grep -q "token_usage" "$EMIT_LOG"` |
| `tests/worktree-merge-push.bats:212` | `! grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"` | `merge_count=$(grep -c "merge test-branch --ff-only" "$GIT_LOG")` |
| `tests/worktree-merge-push.bats:313` | `! grep -q "merge test-branch --ff-only" "$GIT_LOG"` | `fetch_count=$(grep -c "fetch . test-branch:main" "$GIT_LOG")` |
| `tests/worktree-merge-push.bats:387` | `! grep -q "merge test-branch --ff-only" "$GIT_LOG"` | `! grep -qE "^rebase " "$GIT_LOG"` |
| `tests/worktree-merge-push.bats:388` | `! grep -qE "^rebase " "$GIT_LOG"` | `! grep -q "push" "$GIT_LOG"` |
| `tests/worktree-merge-push.bats:465` | `! grep -qE "^rebase origin/main" "$GIT_LOG"` | `grep -q -- "fetch . +test-branch:main" "$GIT_LOG"` |
| `tests/worktree-merge-push.bats:623` | `! grep -q "rebase origin/main" "$GIT_LOG"` | `! grep -qE "\-C .+ rebase" "$GIT_LOG"` |
| `tests/worktree-merge-push.bats:624` | `! grep -qE "\-C .+ rebase" "$GIT_LOG"` | `grep -q "push origin main" "$GIT_LOG"` |

### 個別対応: `tests/observation-trigger.bats:76`

唯一 `if ... fi` の内側にある defective。単純な行置換では表現できないため、条件を `&&` で連結して 3 行の構造を保つ:

```bash
    if [ -f "$BATS_TEST_TMPDIR/gh-calls.log" ] && grep -q "issue comment" "$BATS_TEST_TMPDIR/gh-calls.log"; then
        false
    fi
```

### safe 50 件 (変更禁止)

`tests/append-consumed-comments-section.bats:248` / `tests/auto-recovery.bats:143` / `tests/claude-watchdog.bats:118,133` / `tests/observation-trigger.bats:127,141,155,175` / `tests/orchestration-fallbacks.bats:93` / `tests/post-fallback-review-summary.bats:42,113,165` / `tests/retro-proposals.bats:142` / `tests/run-auto-sub.bats:585,883,1325,1374,1413,1527,1725,1988,2220` / `tests/run-code.bats:400,471` / `tests/run-issue.bats:236,307,340` / `tests/run-merge.bats:328,415,729,758` / `tests/run-review.bats:563,748,777` / `tests/run-spec.bats:206,283,394,429` / `tests/spawn-recovery-subagent.bats:142` / `tests/verify-executor.bats:24,37,57` / `tests/verify.bats:128` / `tests/wait-ci-checks.bats:368` / `tests/worktree-merge-push.bats:132,162,258,355,389,670`

### 実装リスク: 書き換えが潜在的な失敗を露出させうる

これまで検出力ゼロだったアサーションが有効化されるため、被検証コードが実際にはアサーションを満たしていない場合、`bats tests/` が新たに RED になりうる。#1292 では 9 件の書き換え後も 1639 件全件 PASS だったが、28 件という規模ではその保証はない。Implementation Step 6 に、FAIL 時に元の `!` 形式へ戻すことを禁じ、真因側を修正するか前提誤りとしてアサーションを訂正し `## Remediation Record` に記録する手順を明記した。

### skill-dev 制約チェックの適用結果

- **allowed-tools impact chain (Case 2)**: `modules/*.md` が Changed Files に含まれるため lightweight gate を適用。`modules/test-runner.md` への追記内容は散文のみで `scripts/*.sh` パスを一切参照しないため gate 不一致 → reader SKILL.md の `allowed-tools` 更新は不要。`scripts/validate-skill-syntax.py` の `validate_modules_scripts_in_allowed_tools()` が同等の検査を機械的に行うため、CI でも裏取りされる
- **Audit report Findings/Remediation 整合 (#238)**: Implementation Step 5 の最終サブ項目として突合手順を明記済み
- **New subsection heading level (#296)**: 新設見出しのレベルを Implementation Step 3 (h4) と Step 5 (h2) で明示済み
- **Documentation condition step (#273)**: AC7 (ドキュメント条件) に対応する Implementation Step 3 を配置済み
- **Test replacement scenario coverage (#526)**: 本 Issue はテストの削除・置換ではなくアサーション形式の書き換えであり、grep パターンとフラグを保存することで検証シナリオは 1 対 1 で維持される
- **SKILL.md validator MUST 制約**: `skills/*/SKILL.md` は Changed Files に含まれないため非該当。`scripts/validate-skill-syntax.py` の本文検査は SKILL.md のみを対象とする

### External Specification Check は非該当

対象は bash 言語コア (`set -e` と `!` 否定の相互作用) であり、外部コマンドのオプションでも API スキーマでもない。#1292 が Spec フェーズで 3 パターンの実地検証を行い結論を `docs/spec/issue-1292-bats-negation-pitfall.md` § 実地検証 に記録済みのため、本 Issue では再検証せずその結果を踏襲する。

### スコープ外 (follow-up 候補、本 Issue では起票しない)

`scripts/check-forbidden-expressions.sh` に「非最終文の `!` 否定アサーション」検出パターンを追加すれば機械的な再発防止になるが、本 Issue の AC は棚卸しと解消に限定されており、post-merge AC も観察ベースである。検出器の追加は独立した設計判断を要するため本 Issue には含めない。

## spec retrospective

### Minor observations

- #1292 の監査レポート `## Out of Scope` は非 pipe 形式を「76 candidate lines across roughly 30 files」と記録していたが、実測のファイル数は 21 だった。生 grep の件数 (76) は正確だったのに対し、ファイル数だけが目視推定のまま「roughly」付きで残っていた。Out of Scope のような「次の Issue への申し送り」に数値を書く場合、後続の Spec がそれを見積もり根拠にするため、推定値なら推定であることを明示するか一度実測しておくほうが安全。
- 分類ヒューリスティックのブロック終端検出で、「桁 0 の `}` のうち最初のもの」を `@test` ブロックの終端とみなす素朴な実装は誤りになりうる。`tests/*.bats` の 92 ファイルで `@test` 出現数と桁 0 の `}` 出現数が一致しておらず、原因はヒアドキュメント内のモックスクリプト本体と `setup()`/`teardown()` 関数だった。正しくは「直前の `@test` 行から次の `@test` 行までの範囲内で最後に現れる桁 0 の `}`」を取る。今回は素朴版と堅牢版の双方で 26/50 の同一結果が得られたため実害はなかったが、一致したこと自体が分類の妥当性の根拠になっている。
- `run` + `[ "$status" -ne 0 ]` 形式 (`tests/test-runner.bats:60-61` など) は本落とし穴の影響を受けない。`!` を使わずに終了ステータスを変数経由で検査するため、`set -e` の除外規則に触れない。棚卸し対象の判定時にこの形式を defective と誤認しないよう、検索コマンドが先頭 `!` に限定されていることが効いている。

### Judgment rationale

- **Issue 本文による `/spec` へのスコープ判断委任が機能した**。「裸の `!` 否定を含めるかは `/spec` の判断に委ねます。件数と性質が異なる (意図的に失敗を許容している箇所が混ざる可能性) ため、分けたほうが妥当かもしれません」という書き方が、委任と同時に「何を測れば判断できるか (件数・意図的許容の有無)」を指定していたため、実測 2 件・両方とも明示的アサーションという結果から機械的に「分割しない」を導けた。委任だけで判断軸を書かない形だと `/spec` 側で判断軸の設計からやり直しになる。
- **triage AC audit → `/spec` コメント消費のチェーンが 3 例目として機能した** (#1283 AC2、#1292 AC3 に続く)。`/issue` が Issue 本文を非破壊のままコメントで指摘し、`/spec` が消費して修復する分業が、Issue 本文の自動編集による情報喪失なしに欠陥を解消している。
- **AC7 (`modules/test-runner.md` の一般化) を範囲内と判断した根拠**は、コード側 28 件の修正が一度きりであるのに対し SSoT の記述が pipe 前提のままだと同じスコープ誤りが再発する点。実際 #1292 → #1304 はまさにその再発であり、Issue の Purpose 文も `modules/test-runner.md` を名指ししている。スコープ拡大ではなく Purpose の充足条件と整理した。

### Uncertainty resolution

- **`section_not_contains` の針文字列が複数行にまたがるリスク**: AC1 の修復候補として最初に検討した `left to a follow-up Issue rather than this one` は、レポート原文では 2 行に折り返されていた。行指向マッチでは永久に不一致 = 常時 PASS となり、修復したはずの AC1 に同じ欠陥を作り込むところだった。単一行に収まる `Both categories are noted here for reference only` に差し替えて解決。`section_not_contains` / `file_not_contains` の針を選ぶときは、原文での改行位置まで確認する必要がある。
- **`section_not_contains` は見出し不一致で UNCERTAIN を返す**という仕様を踏まえ、「両カテゴリが解消済みなら `## Out of Scope` 節ごと削除する」案を棄却した。見出しを残して本文のみ書き換える制約を Implementation Step 5 に明記済み。
- **書き換えが潜在的失敗を露出させるリスク**は Spec フェーズでは解消できない (被検証ファイルが実行時生成の `$EMIT_LOG` 等のため静的判定不可)。#1292 は 9 件の書き換え後も全件 PASS だったが 28 件では保証がないため、Implementation Step 6 に「元の `!` 形式へ戻すことを禁じ、真因側を修正するか前提誤りとして訂正し `## Remediation Record` に記録する」という対処手順を明記して `/code` へ引き渡した。

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1–6 were followed as written; the defective inventory (26 entries) and bare-negation set (2 entries) from the Spec's Notes were used verbatim with no re-classification.

### Design Gaps/Ambiguities

- **AC5's verify command (`command "bats tests/"`) cannot complete within `modules/verify-executor.md`'s fixed 60-second `command` timeout for a suite this size.** Measured: `bats --jobs 18 tests/` (parallel, 1642 tests) completes in well under 2 minutes; `bats tests/` (serial, the literal form AC5 specifies) did not finish even within the Bash tool's 600-second ceiling and was auto-backgrounded. This means AC5 will return UNCERTAIN via verify-executor at both `/code` Step 10 and `/verify`, regardless of implementation correctness — a systemic gap in the `command` verify type for large-suite full-run assertions, not something introduced by this Issue. Filed as follow-up #1310 (not fixed here — redesigning verify-executor's timeout model is out of this Issue's scope). Step 10 checked AC1–4, 6, 7 (all PASS) and left AC5 unchecked with this UNCERTAIN classification recorded.
- The Spec's Implementation Step 6 anticipated that *rewritten* assertions might expose a previously-hidden real defect (detection-power-zero → activated). In practice, none of the 28 rewritten assertions failed. The only 2 FAILs surfaced by the full-suite run were in `tests/post_merge_check.bats` — a file untouched by this Issue — and were confirmed (via serial re-run, isolated `--jobs` re-run, and a re-run against unmodified `main`) to be a pre-existing flake specific to parallel execution, unrelated to any of this Issue's 28 rewrites. Filed as follow-up #1308.

### Rework

- N/A — no rework was required; all 28 rewrites were 1-line replacements (per Spec Notes) except the pre-identified `tests/observation-trigger.bats:76` structural exception, which matched the Spec's prescribed 3-line form exactly on first attempt.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- pre-merge AC ゲートは 7/7 チェック済み (`check-pre-merge-ac.sh` unchecked_count=0) のため、override マーカーなしでゲートを通過した。
- PR #1309 は `mergeable=true, reason=clean, ci_status=success, review_status=approved` を確認の上、squash merge + delete-branch を実行した。

### Deferred Items

- follow-up #1308: `tests/post_merge_check.bats` の並列実行時フレーク (本 Issue の変更とは無関係、引き続き未対応)。
- follow-up #1310: `command` verify type の 60 秒固定タイムアウトによる全件スイート実行系 AC の構造的検証不能問題。
- CONSIDER 級のドキュメント一貫性指摘 3 件 (`docs/reports/bats-negation-assertion-audit.md:48,247,253`) は未対応のまま。

### Notes for Next Phase

- `/verify` (post-merge) で AC3 を full mode 再検証すれば PASS になる見込み (grep 件数は diff 確認で 0 件と判明済み。`/review` 時点では safe-mode の `command` 型制約により `[ ]` のまま据え置かれていた)。
- Post-merge 観察条件 (次回 bats テストを追加/変更する Issue での否定アサーション形式の観察) は `/verify` に委ねる。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — Implementation Steps 1–6 通り、defective インベントリ 28 件全件を diff で突合し完全一致を確認した (13 ファイル全件サンプル検証済み)。Spec/PR 間の構造的乖離は検出されなかった。

### Recurring issues

`docs/reports/bats-negation-assertion-audit.md` を単一ファイルで #1292/#1304 の 2 Issue にまたがって累積更新する構成が、SHOULD/CONSIDER 級のドキュメント一貫性指摘を複数件 (計 4 件: test-runner.md の Correct form 例が pipe 形式のみだった件、集計表の時点混在に見える表現、"heading only" の記述と実内容の不一致、旧セクションに Issue 番号が付与されていない件) 誘発した。個々の指摘は軽微だが、レポートが Issue をまたいで蓄積される設計そのものが「新旧セクションの記法統一」を継続的な認知負荷として生み続けている。今回は SHOULD 1件のみ修正し CONSIDER 3件は見送ったが、次にこのレポートへ追記する Issue (#1292/#1304 のような "audit を拡張する" 系) が出た場合、追記前に既存セクションとの記法整合 (Issue 番号サフィックスの要否、時点表現の統一) を確認する一手間を Spec フェーズのチェックリストに加えると再発を防げる可能性がある。

### Acceptance criteria verification difficulty

AC3 (`command "test $(grep -c '^\s*! grep -q \"phase_start\"' tests/run-code.bats) -eq 0"`) は `/review` の safe mode で UNCERTAIN となった。AC5 (`command "bats tests/"`) が `/code` Code Retrospective で特定した「`command` 型の 60 秒固定タイムアウトが全件スイート実行系 AC を検証不能にする」問題 (follow-up #1310) とは異なる、もう一つの `command` 型の構造的弱点: AC3 はタイムアウトとは無関係な軽量・決定的なテキストレベルのチェック (grep 件数比較) だが、`command` 型は safe mode で一律 CI reference fallback 頼みとなり、defective なアサーション自体が「検出力ゼロ」(パターンが残っていても CI は SUCCESS のまま) であるためこの AC は原理的に CI 参照でも判定不能だった。実装は diff 確認で充足を独立確認できたが、機構上 UNCERTAIN が確定的に残る。`modules/verify-patterns.md` §9 の "hard-pattern を使うべき条件" (実装が含む正確な文字列を書ける場合) に該当するため、本来 `file_not_contains "tests/run-code.bats" "! grep -q \"phase_start\""` のような safe-mode 対応 (`always_allow`) の verify type で表現できた可能性がある。follow-up #1310 のスコープ (command 型のタイムアウト構造) とは別に、「`command` 型が実は hard-pattern で代替可能なケースを spec 作成時に見分ける」観点を `modules/verify-patterns.md` §9 に追記する価値があるかもしれない (Issue 化は次の `/verify` の集約判断に委ねる)。
- `docs/reports/` は `docs/translation-workflow.md` § Exclusions により ja ミラー対象外。監査レポート更新時に `docs/ja/reports/` は作成していない。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時に「裸の `!` 否定を本 Issue のスコープに含めるかは `/spec` の判断に委ねる」としたうえで「件数と性質が異なる (意図的に失敗を許容している箇所が混ざる可能性) ため、分けたほうが妥当かもしれません」と付記した。**この懸念は実測で否定された** — 該当は 2 件のみで、2 件とも `# sanity: plain -d must fail` という明示的アサーションの直後にあり「意図的に失敗を許容している箇所」ではなく、いずれも非最終文で同一判定基準の defective だった。実測に基づかない推測を Notes に残したことで `/spec` が調査対象として拾えた形だが、推測の確度は明示すべきだった
- triage が AC1 (`section_contains "Out of Scope" "pipe"`) の常時 PASS 欠陥を検出した。本セッション 4 例目の verify command 欠陥検出

#### spec
- **AC1 修復の第一候補が同じ欠陥の作り込みになるところを回避した**。修復案の針文字列が原文で 2 行に折り返されており、行指向マッチで永久に不一致 = 常時 FAIL になる構成だった。単一行に収まる針へ変更している
- **#1292 がスコープを pipe 形式に限定した直接原因**を `modules/test-runner.md` の例示が pipe 前提だった点に特定し、pipe 非依存性の明記を AC7 として追加。同種のスコープ漏れの再発防止が AC に組み込まれた
- 対象を 76 → 78 件、defective を 26 + 2 = 28 件へ確定。#1292 の 9 件と合わせ、`tests/*.bats` 全体で **99 件中 37 件が defective** だったことになる
- 実装リスク (検出力ゼロだったアサーションが有効化され `bats tests/` が新たに RED になりうる) を引き渡し、「元の `!` 形式へ戻すことを禁じ真因側を修正する」手順を Implementation Step 6 に明記した

#### code
- Implementation Steps 1-6 を逸脱なく実施、rework ゼロ。defective インベントリ 28 件を diff で全件突合し完全一致を確認
- `command` 型 AC5 (`bats tests/`) の検証中に「`command` 型の 60 秒固定タイムアウトが全件スイート実行系 AC を構造的に検証不能にする」問題を特定し follow-up #1310 を起票

#### review
- `/review --full` は Spec/実装の構造的乖離 0 件。指摘は SHOULD/CONSIDER 級のドキュメント一貫性 4 件で、いずれも `docs/reports/bats-negation-assertion-audit.md` を #1292/#1304 の 2 Issue にまたがって累積更新する構成に起因した
- AC3 が safe mode で UNCERTAIN 確定になる構造を特定し、`/verify` の集約判断に委ねた (下記 Improvement Proposals で処理)

#### merge
- **merge フェーズが 1 度失敗し、親セッションが手動復旧した (下記 Manual recovery)**

#### verify
- pre-merge 7 件はすべて merge 前に検証済みで SKIPPED、observation 1 件は `auto-run` 未発火で SKIPPED。FAIL / UNCERTAIN ゼロ

### Manual recovery (parent session)

`docs/reports/orchestration-recoveries.md` に本 Issue のエントリが存在しないため、`skills/verify/SKILL.md` Step 12 の規定に従いここに記録する。

- **症状**: `run-auto-sub.sh` が merge フェーズで exit 1。Tier 3 recovery が `[spawn-recovery] action=abort: tier3 cannot recover this failure` を出力し復旧不能と判定
- **観測した状態**: PR #1309 は OPEN、CI 全 job SUCCESS (DCO / bats / skill syntax / forbidden expressions / language convention / macOS shell compat)、しかし `mergeable: UNKNOWN` / `mergeStateStatus: UNKNOWN`
- **診断**: GitHub のマージ可能性計算は非同期であり、`UNKNOWN` は計算未完了を示す一過性の状態。実装・コンフリクト・CI いずれにも問題なし
- **復旧手順**: 5 秒待って `gh pr view 1309 --json mergeable,mergeStateStatus` を再クエリ → `MERGEABLE` / `CLEAN` に解決。`run-merge.sh 1309` を単体で再実行し PR #1309 を MERGED、Issue を `phase/verify` へ遷移させた
- **所要**: 親セッションの介入 1 回 (再クエリ + merge 再実行)。Tier 1/2/3 いずれも発火せず、`manual_intervention` イベントも emit されていない (#875 の既知構造ギャップ)
- **付随事象**: 復旧後、ローカル main が origin と ahead 2 / behind 2 で分岐していた。ahead 側は並行セッションの #1294 作業 (未 push) で、`git pull --rebase` により保全したうえで解消した

### Improvement Proposals

- **[Tier 2 / 既存 Issue へ追記] `command` 型が safe mode で原理的に判定不能になるケースの見分け方** — `/review` retrospective が `/verify` の集約判断に委ねた項目。AC3 はタイムアウトとは無関係な軽量・決定的チェックだが、`command` 型は safe mode で一律 CI reference fallback となり、検証対象の defective アサーションが「検出力ゼロ」であるため CI 参照でも原理的に判定できず UNCERTAIN が確定的に残った。`modules/verify-patterns.md` §9 の hard-pattern 条件に該当し `file_not_contains` (`always_allow`) で代替可能だった。**同系統の `command` 型構造的弱点を扱う既存 Issue #1310 が存在するため新規起票せず追記で処理** (issuecomment-5230338531)。#1310 のスコープはタイムアウト機構、本観察は safe mode fallback 機構と原因は異なるが、AC 型選択ガイドとして同じ場所に着地させるのが自然と判断した
- **[Tier 3 / Spec 記録のみ] 監査レポートの Issue 横断累積が記法統一の認知負荷を生む** — `docs/reports/bats-negation-assertion-audit.md` を #1292/#1304 の 2 Issue で累積更新する構成が、SHOULD/CONSIDER 級のドキュメント一貫性指摘を 4 件誘発した (Correct form 例の pipe 偏り、集計表の時点混在表現、"heading only" 記述と実内容の不一致、旧セクションの Issue 番号欠落)。個々は軽微で今回は SHOULD 1 件のみ修正。`/review` retrospective が「次に同レポートへ追記する Issue が出た場合、既存セクションとの記法整合を Spec フェーズのチェックリストに加える」という再発防止案を記録済み。3 例目が出た時点で起票を検討する
