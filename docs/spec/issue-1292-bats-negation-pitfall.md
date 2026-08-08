# Issue #1292: test-runner: bats の否定アサーションが set -e 下で無効化される落とし穴を共有モジュールに明文化

## Overview

`! cmd | grep -q pattern` 形式の否定アサーションを bats テストの **非最終文** として書くと、`set -e` 下では否定コマンドの失敗が自動終了をトリガーしない (POSIX/bash の仕様) ため、アサーションが検出力ゼロのまま実行が継続してしまう。この落とし穴と正しい記述形式 (`if cmd | grep -q pattern; then false; fi`) を `modules/test-runner.md` (`/code` `/review` `/verify` の3 skill が共有する SSoT) に明文化し、既存の `tests/*.bats` に残る同パターンを機械的に洗い出して `docs/reports/bats-negation-assertion-audit.md` に記録する。#1281 (PR #1290) で実際に踏まれたパターンであり、`tests/collect-recovery-candidates.bats:604-605` に修正後の正しい形が残っている。

## Changed Files

- `modules/test-runner.md`: 新規 `## Notes` セクション (現状このセクションは存在しない) を追加し、`### bats Negation Assertion Pitfall` サブセクションで落とし穴と正しい記述形式を明文化
- `docs/reports/bats-negation-assertion-audit.md`: 新規ファイル — 棚卸し結果 (計21件: 非最終文=検出力ゼロ 9件、最終文=安全 12件)、判定基準、是正記録
- `tests/audit-auto-session.bats`: 66行目を `if ...; then false; fi` 形式へ書き換え
- `tests/get-auto-session-report.bats`: 32, 70行目を `if ...; then false; fi` 形式へ書き換え
- `tests/filter-session-verified-issues.bats`: 39行目を `if ...; then false; fi` 形式へ書き換え
- `tests/collect-recovery-candidates.bats`: 376行目を `if ...; then false; fi` 形式へ書き換え
- `tests/reclaim-stale-worktrees.bats`: 90, 144, 168行目を `if ...; then false; fi` 形式へ書き換え
- `tests/verify.bats`: 154行目を `if ...; then false; fi` 形式へ書き換え

## Implementation Steps

1. `modules/test-runner.md` に新規 `## Notes` セクションを追加し (Purpose/Input/Processing Steps/Output Format の既存4セクションはそのまま維持)、`### bats Negation Assertion Pitfall` サブセクションで以下を明文化する: (a) 問題 — `! cmd | grep -q pattern` を bats `@test` 関数内の**非最終文**として書くと、否定されたコマンドの失敗は `set -e` の自動終了をトリガーしない (POSIX/bash 仕様上、`!` で反転された終了ステータスは常に `-e` の対象外) ため、後続の文が実行され続け、意図した異常検出が起きてもテストは PASS したままになる; (b) 正しい形式 — `if cmd | grep -q pattern; then false; fi` で囲み、パターンが見つかった分岐で明示的に (否定されていない) `false` を実行することで確実に `-e` をトリガーする; (c) 例外 — 否定パイプラインがテスト関数の**真の最終文**である場合は安全 (関数自体の戻り値がそのまま bats の pass/fail 判定に使われるため)。`tests/collect-recovery-candidates.bats:604-605` (非最終文だったため修正された例) と `:611` (真の最終文のため無修正で安全な例) を対比して引用する。(→ acceptance criteria AC1, AC2)

2. Spec フェーズの調査で洗い出し済みの非最終文 (検出力ゼロ) 9件を `if cmd | grep -q ...; then false; fi` 形式へ書き換える。既存の grep フラグ/パターン文字列は変更せず、`-q` フラグが付いていない場合のみ `:604-605` の前例に合わせて追加する。対象 (6ファイル): `tests/audit-auto-session.bats:66`、`tests/get-auto-session-report.bats:32,70`、`tests/filter-session-verified-issues.bats:39`、`tests/collect-recovery-candidates.bats:376`、`tests/reclaim-stale-worktrees.bats:90,144,168`、`tests/verify.bats:154`。Notes に記載する残り12件 (真の最終文で安全) は変更しない。(after 1) (→ Purpose の充足; AC5 を下支え)

3. `docs/reports/bats-negation-assertion-audit.md` を新規作成し、以下を記録する: 検索コマンド (`grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats`、スコープ: `tests/*.bats` 直下116ファイル全件、サブディレクトリに `.bats` ファイルは存在しないため非再帰 glob で漏れなし)、判定基準 (同一 `@test` 関数内で当該行が真の最終文なら安全、そうでなければ検出力ゼロ)、Notes に記載する全21件の内訳 (ファイル:行、該当箇所、分類)、サマリ件数 (計21件: 検出力ゼロ9件・安全12件)、是正記録 (検出力ゼロの9件はStep 2で本 Issue 内で修正済み、安全な12件は変更不要)。(after 2) (→ AC3, AC4)

4. `bats --jobs <N> tests/` (`modules/test-runner.md` の並列実行ガイダンスに従う; `nproc` または `sysctl -n hw.logicalcpu` でジョブ数を解決) を実行し PASS を確認する。Step 1 の文書追加が `tests/test-runner.bats` の section-presence テストを壊していないこと、Step 2 の書き換えが既存の pass/fail 挙動を保っていること (9件の書き換え後もアサーションの前提条件が現状のコードで真であること) の両方を確認する。(after 3) (→ AC5)

## Verification

### Pre-merge
- <!-- verify: rubric "modules/test-runner.md に、bats の否定アサーションを set -e 下で書く際の落とし穴と、if cmd; then false; fi 形式が正しい記述であることが記載されている" --> 落とし穴と正しい形式が共有モジュールに記載されている
- <!-- verify: grep "then false" "modules/test-runner.md" --> 正しい記述形式が具体例として示されている
- <!-- verify: rubric "docs/reports/bats-negation-assertion-audit.md に、既存の tests/*.bats に残る `! ... | grep` 形式の否定アサーション (bats の set -e 下で無効化されるパターン) を洗い出した結果が、ファイルまたはパターンごとの件数付きで記録されている。ゼロ件だった場合もその旨が記録されていること" --> 既存テストの棚卸し結果が docs/reports/bats-negation-assertion-audit.md に記録されている
- <!-- verify: file_exists "docs/reports/bats-negation-assertion-audit.md" --> 棚卸しレポートファイルが作成されている
- <!-- verify: command "bats tests/" --> 既存テストスイートが PASS する

### Post-merge
- 次回 bats テストを追加する Issue で、否定アサーションが正しい形式で書かれていることを観察する

## Notes

### 判断根拠 (non-interactive mode auto-resolve)

- **既存9件の書き換えを本 Issue のスコープに含める**: Issue 本文の Notes は「実際の書き換えを本 Issue に含めるか別 Issue に分けるかは件数を見てから決める」ことを `/spec` に委ねていた。Spec フェーズの調査で件数が計21件 (うち検出力ゼロは9件、6ファイル) と判明し、各修正は `if cmd; then false; fi` で囲むだけの機械的な1行変更のため、Light テンプレートの Implementation Steps 上限 (5) 内に収まる。Issue の Purpose 自体が「レビュー段階の属人的な発見に頼らず防ぐ」ことである以上、現在進行形で検出力ゼロのまま残っている9件を放置せず本 Issue で是正する方が Purpose に整合すると判断した。
- **`skills/issue/spec-test-guidelines.md` への重複記載は見送り**: Issue 本文 Notes が重複管理リスクを指摘し判断を委ねていた。`spec-test-guidelines.md` は `/issue` が読む「AC 設計ガイド」であり、対象は「何をテストすべきか」。今回明文化する内容は「テストコードの書き方 (bash/set -e の挙動)」というレイヤーが異なる関心事であり、実際に新規 bats アサーションを書くフェーズは `/code` である。`modules/test-runner.md` は `/code` `/review` `/verify` の3 skill が読むため、単一箇所で到達範囲は足りると判断し、`spec-test-guidelines.md` 側への追記は行わない。
- **External Specification Check (`skills/spec/external-spec.md`) は非該当と判断**: 対象は tmux/gh/git 等の外部コマンドオプションでも、hooks/API の JSON スキーマでもなく、bash 言語コア (`set -e` と `!` 否定の相互作用) の挙動そのもの。公式ドキュメント参照より実地検証の方が確実なため、本 Spec 作成時に直接 bash で実地検証した (下記)。

### 実地検証 (bash `set -e` + `!` の挙動)

3パターンを実行し、以下を確認した:

1. `! cmd | grep -q pattern` が非最終文で、かつ想定通り「異常検出」すべき状況 (パターンが見つかった) でも、`set -e` はトリガーされず後続処理が継続し、スクリプト全体の終了コードは 0 (成功) のままだった — 落とし穴を実証。
2. 同じ状況を `if cmd | grep -q pattern; then false; fi` に書き換えると、`set -e` が正しくトリガーされ即座に終了コード 1 で終了した — 修正形式の妥当性を実証。
3. `! cmd | grep -q pattern` が関数の**真の最終文**である場合は、関数自体の戻り値が呼び出し元の `set -e` を正しくトリガーした (終了コード 1) — 最終文なら無修正で安全という分類基準を実証。

### 棚卸し結果 (Spec フェーズ調査、Step 3 の入力)

**測定スコープ**: `grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats` (`tests/` 直下の `.bats` ファイル116件全件が対象。`find tests -mindepth 2 -name "*.bats"` で確認した結果サブディレクトリに `.bats` は0件のため、非再帰 glob で漏れはない)。

**判定基準**: 当該行が同一 `@test` 関数内で閉じ `}` の直前 (真の最終文) なら安全、後続に他の文があれば検出力ゼロ (非最終文)。

計21件がヒットし、7ファイルに分布 (`audit-auto-session.bats` 3件、`get-auto-session-report.bats` 4件、`filter-session-verified-issues.bats` 1件、`collect-recovery-candidates.bats` 3件、`reclaim-stale-worktrees.bats` 7件、`verify.bats` 1件、`triage-backlog-filter.bats` 2件)。

**検出力ゼロ (非最終文、要修正) — 9件:**

| ファイル:行 | 現在の記述 |
|---|---|
| tests/audit-auto-session.bats:66 | `! echo "$output" \| grep -q "Issues processed \| 2"` |
| tests/get-auto-session-report.bats:32 | `! echo "$output" \| grep -q "\| #200 \|"` |
| tests/get-auto-session-report.bats:70 | `! echo "$output" \| grep -q "\| #501 \|"` |
| tests/filter-session-verified-issues.bats:39 | `! echo "$output" \| grep -qx "984"` |
| tests/collect-recovery-candidates.bats:376 | `! echo "$output" \| grep -E $'^manual-recovery-review-rerun\t'` |
| tests/reclaim-stale-worktrees.bats:90 | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt1006"` |
| tests/reclaim-stale-worktrees.bats:144 | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt1149"` |
| tests/reclaim-stale-worktrees.bats:168 | `! git -C "$MAIN_REPO" worktree list \| grep -q "wt5000"` |
| tests/verify.bats:154 | `! step6_section \| grep -q -F "Re-verify even if already checked"` |

**安全 (真の最終文、変更不要) — 12件:**

tests/audit-auto-session.bats:46,103 / tests/get-auto-session-report.bats:71,199 / tests/collect-recovery-candidates.bats:460,611 / tests/reclaim-stale-worktrees.bats:91,145,181,206 / tests/triage-backlog-filter.bats:52,130

**スコープ外 (参考)**: `| grep` を伴わない裸の `!` 否定 (例: `tests/reclaim-stale-worktrees.bats:136,159` の `! git branch -d ... 2>/dev/null`) も同種の `set -e` 例外規則の影響を受けうるが、Issue #1292 の対象パターンは `! ... | grep` 形式に明示的にスコープされているため、本棚卸しの対象外とした。

## Consumed Comments

| login | authorAssociation | trust tier | intent | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | Issue Retrospective (triage auto-chain): Type=Task, Size=S に確定。AC3 の記録先を「Spec/Issue コメント」→ `docs/reports/bats-negation-assertion-audit.md` に変更した理由 (rubric grader は Spec ファイルと Issue コメントのどちらも読めないため) を記録。Issue 本文にも同内容が反映済み | https://github.com/saitoco/wholework/issues/1292#issuecomment-5228437961 |

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 を Spec の記載順どおりに実施した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A — Spec フェーズの棚卸し (対象9件・安全12件の分類) がそのまま実装の書き換え対象と一致しており、実装時の再調査・やり直しは発生しなかった。

## review retrospective

### Spec vs. implementation divergence patterns

乖離なし。Implementation Steps 1〜4 の記述と実装内容 (`modules/test-runner.md` の Notes セクション、`docs/reports/bats-negation-assertion-audit.md`、6件の `tests/*.bats` 書き換え) は一致していた。Pre-merge AC 5件はいずれも `/code` 内で PASS 確認済みで、`/review --light` の safe mode 再検証でも同じ結果 (rubric 2件・grep 1件・file_exists 1件・command 1件、全PASS) となった。

### Recurring issues

`docs/reports/bats-negation-assertion-audit.md` の検索コマンド (`grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats`) は `! cmd | grep ...` の **pipe 形式のみ**を対象にしているが、`set -e` 下で `!` の終了ステータスが無効化されるという根本原因は pipe の有無に関係なく成立する。review-light の Perspective 1/2 が独立に、pipe を伴わない `! grep -q pattern file` 形式の非最終文アサーションを別途検出した (`grep -rnE '^\s*!\s*.*grep' tests/*.bats | grep -vE '\|\s*grep'` で76件の生候補、`tests/run-code.bats:470` `tests/run-issue.bats:306` `tests/gh-graphql.bats:69` 等で実際に非最終文=検出力ゼロであることを確認)。Issue #1292 の本文は対象パターンを `! cmd | grep -q ...` の pipe 形式に明示的にスコープしていたため、本 Issue の対応としては監査レポートの Out of Scope 節に当該パターンの存在と件数を明記するに留めた (実際の分類・修正は行っていない)。76件という規模は独立の棚卸し・修正作業に値するため、Improvement Proposal として `/verify` での起票検討を推奨する。

### Acceptance criteria verification difficulty

UNCERTAIN は発生しなかった。5件の Pre-merge AC (rubric 2件・grep 1件・file_exists 1件・command 1件) はいずれも判定に迷いなく PASS 確定できた。`command "bats tests/"` は `bats --jobs 18 tests/` で1639件全件 PASS を確認しており、非対話モードでの並列実行 (foreground, timeout 590000ms) も問題なく機能した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- `/merge 1303 --non-interactive` を実行。pre-merge AC ゲート (5件全 checked)、review-incomplete-fallback チェック (fallback 検出なし) ともにクリアしており、追加の override マーカーは不要と判断した。
- `gh-pr-merge-status.sh` が `mergeable=true, reason=clean` を返したため、Step 3 (Resolve Conflicts) はスキップし、squash merge を直接実行した。

### Deferred Items
- Post-merge AC (次回 bats テストを追加する Issue での観察) は `/verify` に委ねる。
- pipe 無し `! grep -q pattern file` 形式の追加棚卸し・修正 (76件の生候補) は本 Issue のスコープ外 — `/verify` での Improvement Proposal 起票を推奨 (review retrospective に記録済み)。

### Notes for Next Phase
- squash merge 完了、リモートブランチ削除済み。CI 全ジョブ SUCCESS。
- `/verify 1292` で post-merge AC の観察を行うこと。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時点の根拠は「#1281 自身の新規テストコードで 1 件踏んだ」ことのみで、Tier 1 の evidence gate は再発性ではなく共有サーフェス ripple (`modules/test-runner.md` を `/code` `/review` `/verify` の 3 skill が読む) で満たしていた。**棚卸しにより再発性が事後的に裏付けられた** — 既存 `tests/*.bats` に 9 件の defective が実在した
- triage が AC3 の verify command 欠陥を捕捉した。元の rubric は記録先を「Spec または Issue コメント」としていたが、`modules/verify-executor.md` が定める rubric grader の入力スコープ (Issue 本文・git diff・rubric text 内で明示的に名指ししたファイル) にはどちらも含まれず、恒久 UNCERTAIN/FAIL になる構成だった。`docs/reports/bats-negation-assertion-audit.md` を明示参照する形へ修正され、`file_exists` の補助 AC も追加された。本セッションで triage が verify command 欠陥を捕捉したのは #1283 の AC2 に続き 2 例目

#### spec
- Size が S → M へ上方修正され route が patch → pr へ再計画された (Step 3a Post-Spec Size Refresh)。棚卸し対象が 21 件・修正対象 9 件と判明し、実変更が 9 ファイルに及んだため妥当な判断
- Spec フェーズの棚卸し (defective 9 / safe 12 の分類) がそのまま実装の書き換え対象と一致し、code フェーズでの再調査・rework はゼロだった

#### code
- Implementation Steps 1〜4 を逸脱なく実施、rework なし
- `bats --jobs 18 tests/` で 1639 件全 PASS を foreground (timeout 590000ms) で確認。並列実行の flake も発生しなかった

#### review
- **`/review --light` が監査のスコープ漏れを検出した**。監査の検索コマンド `grep -rnE '^\s*!\s*.*\|\s*grep' tests/*.bats` は `! cmd | grep ...` の **pipe 形式のみ**を対象にしているが、根本原因 (`!` の終了ステータスが `set -e` の自動終了対象から外れる) は pipe の有無と無関係に成立する。Perspective 1/2 が独立に pipe 無し形式を検出し、`tests/run-code.bats:470` `tests/run-issue.bats:306` `tests/gh-graphql.bats:69` 等で実際に非最終文 = 検出力ゼロであることを確認した
- Issue 本文が対象を pipe 形式に明示スコープしていたため、本 Issue では監査レポートの `## Out of Scope` 節への明記に留め、分類・修正は行っていない。review retrospective と merge Phase Handoff の双方が `/verify` での起票を明示的に推奨している

#### merge
- pre-merge AC ゲート 5 件全 checked、`review_incomplete_fallback` 未検出で override マーカーなしに squash merge。`mergeable=true (clean)` でコンフリクト解消不要

#### verify
- pre-merge 5 件はすべて merge 前に検証済みで SKIPPED、observation 1 件は未発火で SKIPPED。FAIL / UNCERTAIN ゼロ
- 上記 review 指摘を実測で再確認した: 非 pipe 形式の生候補は **76 件** (`grep -rnE '^\s*!\s*.*grep' tests/*.bats | grep -vE '\|\s*grep'`)、`tests/run-code.bats:470` は直後に `! grep -q "phase_complete" ...` が続く非最終文で defective 確定 (471 行目は最終文なので safe)

### Improvement Proposals

- **pipe を伴わない `! grep -q pattern file` 形式の否定アサーションを棚卸し・修正する** — #1292 が明文化した根本原因 (`!` の終了ステータスが `set -e` の自動終了対象外) は pipe の有無に依存しないが、#1292 の棚卸しは Issue 本文のスコープ規定により pipe 形式 21 件のみを対象とした。非 pipe 形式は生候補 76 件が未分類のまま残っており、うち `tests/run-code.bats:470` `tests/run-issue.bats:306` `tests/gh-graphql.bats:69` は非最終文 = 検出力ゼロであることを実測確認済み。#1292 と同じ判定基準 (非最終文なら defective) で分類し、defective を `if cmd; then false; fi` 形式へ書き換える。`docs/reports/bats-negation-assertion-audit.md` の `## Out of Scope` 節が対象パターンと件数を既に記録しているため、それを起点にできる
