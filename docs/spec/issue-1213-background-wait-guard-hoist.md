# Issue #1213: code: 再呼び出し保証のない実行サーフェスでの background task 完了通知待ちを構造的に防止 (#994 の再発)

## Overview

`skills/code/SKILL.md` Step 9 の実行サーフェス制約 (`--non-interactive` / fork / Workflow など再呼び出し保証のない実行サーフェスでは `bats tests/` フルスイートを background 実行せず foreground + 明示 `timeout` で実行する、という #994 由来のガード) が、Behavioral Change Detection 分岐の内側にネストされた位置にあるため、別経路からフルスイート実行を判断した場合に指示が視界に入らず、#1102 (2026-08-06) で同一事象が再発した。

本 Spec は、この制約の**配置位置**を分岐非依存かつ実行判断の直前に来るよう修正する。加えて、Issue コメントで報告された `/review` フェーズでの同型再発 (#1212, PR #1222, 2026-08-07) を踏まえ、`skills/review/SKILL.md` にも同種の是正を行う。

## Reproduction Steps

1. `/code` (または `/review`) を `--non-interactive` / fork-executed Skill / Workflow tool のいずれか (再呼び出し保証のない実行サーフェス) で実行する。
2. `/code` の Step 9 Behavioral Change Detection、または `/review` の Step 12.3 Lightweight Re-check が、変更ファイルのスコープ判断によりフルテストスイート (`bats tests/`) の実行を選択する。
3. エージェントが `bats tests/` を `run_in_background: true` で起動し、完了通知を待つ形でターンを終える。
4. 再呼び出し保証がないため通知は届かず、phase は `claude` プロセス自体は exit 0 で終了しつつ実質的に未完了 (silent no-op) となる。`reconcile-phase-state.sh` が `matches_expected:false` を検出する。

## Root Cause

配置位置の問題である。実行サーフェス制約の記述は「テストコマンドを実行する直前」ではなく「特定の分岐の内側」に置かれており、かつ過去 2 回、位置を変えない修正がすでに試みられた上で再発している。

- **`skills/code/SKILL.md`**: 制約文は Step 9 "Behavioral Change Detection" 分岐 (check 2 の「追加テストファイルが変更対象を参照している場合」) の内側、`bats tests/` のコードフェンスより**後**に置かれている。#1123 (PR #1149, 2026-08-04) がこの文言を `modules/execution-context.md` の単一 SSoT を参照する形に書き換えたが、**配置位置そのものは変更しなかった** (`git show 9dc07088 -- skills/code/SKILL.md` で確認: 変更は文言のみ、行位置は同一)。この書き換え後の 2026-08-06 に #1102 で同一事象が再発しており、内容 (文言・SSoT 参照) だけを直しても位置の問題は解消しないことが実測で裏付けられている。
- **`skills/review/SKILL.md`**: `## Non-Interactive Mode Behavior` 節 (Step 1 より前、ファイル冒頭付近) に #1097 (2026-07-31) が追加した同種のガードが**既に存在する** (`skills/review/SKILL.md:39`)。分岐に依存しない一般的な記述だが、実際にフルスイート実行が判断される Step 12.3 "Lightweight Re-check" (`### 12.3.` 見出し、681 行目) までは約 600 行離れている。2026-08-07 の #1212 (PR #1222) では、この既存ガードがありながら同型の background 待機が発生した。分岐非依存な位置に置くだけでも、実行判断地点から遠すぎると有効に機能しないことを示す実測である。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Triage AC audit — AC2 (`file_contains "run_in_background"`) が実装前から存在する文字列のため常時 PASS になる Pattern 2 の欠陥、AC3 (`gh run list --branch=main`) が Size M (pr route) と不整合という 2 件の verify command 修正提案、AC1 rubric への `section_contains` 補助案、post-merge observation AC の否定形表現への指摘 / URL: https://github.com/saitoco/wholework/issues/1213#issuecomment-5205481074
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: review フェーズでの再発実測 (#1212 / PR #1222, session `33233-1786023637`) — 同一失敗モードが `/review` でも発生し、code フェーズと異なり built-in auto-retry がなく未コミット変更が worktree に残存した実害を報告。`skills/review/SKILL.md` へのスコープ拡大、および wrapper 側検出改善 (案 2) ・fallback 未コミット検出 (案 3、新規提案) を検討事項として提示 / URL: https://github.com/saitoco/wholework/issues/1213#issuecomment-5211151564

**cutoff 解決の注記**: 両コメントの `createdAt` は本フェーズの cutoff (`.tmp/auto-events.jsonl` の `phase_start` イベント、Fallback A) より前だが、この cutoff は本ラン自身が起動直前に記録した自己参照的な値であり (`phase/*` ラベル履歴が存在しない初回フェーズのため)、機械的に適用すると両コメントを排除してしまう。同じ wrapper が記録した `comments_consumed` イベント (count=2, trust_breakdown MEMBER:2) が実際の全コメント数と一致していることから、両コメントを consumed 済みとして扱った。

- saito / MEMBER / first-class / <!-- wholework-event: type=verify-fail phase=verify issue=1213 iteration=1 --> / https://github.com/saitoco/wholework/issues/1213#issuecomment-5213905136
## Changed Files

- `skills/code/SKILL.md`: Step 9 の実行サーフェス制約を、Behavioral Change Detection 分岐内 (旧位置: check 2 の `bats tests/` コードフェンス直後) から、Step 9 冒頭 (`**Operate route**: ...` 行の直後、Behavioral Change Detection 見出しより前) の分岐非依存な位置へ移動。旧位置の記述は "See the execution surface constraint above" 形の短い参照へ置換 (`run_in_background` という語自体は旧位置から除去)
- `skills/review/SKILL.md`: Step 12.3 "Lightweight Re-check" の `Re-run tests/validation` 箇条書きに、同一制約への実行判断地点直近のローカルなリマインダーを追加 (ファイル冒頭の既存ガード (`## Non-Interactive Mode Behavior` 節) だけでは #1212 の再発を防げなかったため)
- `modules/execution-context.md`: "Re-invocation Guarantee and Notification-Dependent Waiting" 節の Callers テーブルを更新 — `skills/code/SKILL.md` の参照箇所説明を新位置に、`skills/review/SKILL.md` の参照箇所説明に Step 12.3 のローカルリマインダーを追加

## Implementation Steps

1. `skills/code/SKILL.md` Step 9: "**Operate route**: skip this entire Step 9 ..." 行の直後に、実行サーフェス制約を述べる新規段落を追加する。文言は既存の `${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" 参照を維持しつつ、「Step 9 内のどのテストコマンド (フルスイート override / `test-runner.md` への委譲) にも適用される」旨を明記する。続けて、Behavioral Change Detection 分岐内 (check 2、`bats tests/` コードフェンスの `(Same pre-check guard applies — ...)` 行の直後) にあった旧ガード文 ("When `/code` itself is running in an execution surface without a re-invocation guarantee...") を削除し、"(...See the execution surface constraint above for foreground/timeout requirements.)" という短い参照に置き換える (→ acceptance criteria AC1, AC2, AC2b)
2. `skills/review/SKILL.md` Step 12.3 (681 行目付近, "### 12.3. Lightweight Re-check"): `- Re-run tests/validation` 箇条書きの末尾に、フルスイート実行を選択する場合は `## Non-Interactive Mode Behavior` 節の foreground 制約がここにも適用される旨のローカルなリマインダーを追記する。`${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" を参照する (→ acceptance criteria AC4)
3. (after 1, 2) `modules/execution-context.md` の "## Callers" テーブル、"Re-invocation Guarantee and Notification-Dependent Waiting" 節の行を更新する: `skills/code/SKILL.md` の説明を「Behavioral Change Detection foreground-execution note」から「Step 9 execution surface constraint, stated once before the Behavioral Change Detection subsection」に、`skills/review/SKILL.md` の説明に「; Step 12.3 Lightweight Re-check local reminder」を追加する (→ SSoT Module Cross-Check の整合性維持。`skills/code/SKILL.md` の "SSoT Module Cross-Check" ステップが `/code` 時に自動検証する)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md において、再呼び出し保証のない実行サーフェス (--non-interactive / fork / Workflow) での background task 完了通知待ちを禁じる指示が、フルスイート実行の先行分岐に依存しない位置に配置されている" --> 実行サーフェス制約の指示が分岐非依存な位置に配置されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 9" "run_in_background" --> `skills/code/SKILL.md` の Step 9 冒頭 (分岐非依存な位置) に `run_in_background` の扱いが明記されている
- <!-- verify: section_not_contains "skills/code/SKILL.md" "Behavioral Change Detection" "run_in_background" --> 旧ネスト位置 (Behavioral Change Detection 分岐内) から実行サーフェス制約の記述 (`run_in_background`) が除去されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する
- <!-- verify: section_contains "skills/review/SKILL.md" "12.3" "foreground" --> `skills/review/SKILL.md` の Step 12.3 (Lightweight Re-check) に実行サーフェス制約 (foreground 実行) への言及が追加されている

### Post-merge

- 次回以降の `/auto` の code phase ログで、Behavioral Change Detection がフルスイート実行を選択した場合に foreground 実行 (または明示 `timeout`) が行われた形跡が残ることを観察する <!-- verify-type: observation event=auto-run session=next -->
- 次回以降の `/auto` の review phase ログで、Step 12.3 がフルスイート実行を選択した場合に foreground 実行 (または明示 `timeout`) が行われた形跡が残ることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

**AC 修正の経緯 (Consumed Comments の Triage AC audit 反映)**:
- 旧 AC2 (`file_contains "skills/code/SKILL.md" "run_in_background"`) は、`run_in_background` という文字列自体が #994 の時点ですでに存在するため、実装を伴わずに常時 PASS する欠陥があった (`skill-dev-verify-audit.md` Pattern 2)。本 Issue が是正するのは「文字列の有無」ではなく「配置位置」のため、`section_contains`/`section_not_contains` のペアに置き換えた。
- 旧 AC3 (`github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`) は、Size M (pr route) にもかかわらず `--branch=main` で main の CI 結果を参照しており、この PR 自身の CI を検証できていなかった。`github_check "gh pr checks" "Run bats tests"` に置き換えた (`.github/workflows/test.yml` のジョブ表示名 "Run bats tests" と一致することを確認済み。同パターンは本リポジトリの既存 Spec 群 (issue-281, issue-1069, issue-1152 等) でも採用されている確立した書き方)。
- post-merge observation AC は「発生しないことを観察する」という否定形で反証可能性に乏しかったため、「foreground 実行の形跡が残ることを観察する」という肯定形に書き換え、対象フェーズ (code/review) ごとに分割した。

**スコープ判断 (Consumed Comments の 2 件目、review フェーズ再発実測の反映)**:
- 採用: `skills/review/SKILL.md` への是正拡大。同一 root cause (制約の配置位置) による同型再発が同日 (2026-08-07) に実測されており、first-class input として明確な根拠がある。
- 見送り (別 Issue 検討を推奨): コメントが挙げた「案 2: wrapper 側検出の拡大 (`run-review.sh`、`post-fallback-review-summary.sh` 実行前後のタイミング考慮)」および「案 3 (新規提案): fallback が未コミット作業の存在を検出する」。いずれも本 Issue の既存 Pre-merge AC には含まれておらず、prose 配置の是正とは異なる新規メカニズムの設計を要するため、Size M / light depth の本 Spec には含めない。今回の配置修正後も同型再発が観測される場合に、改めて起票を検討する。

**`docs/reports/orchestration-recoveries.md` の記述精度について**: 同ファイル 79 行目のインシデント記録 (#1212 の手動復旧記録) は「the #994 guard in skills/code/SKILL.md has no counterpart in skills/review/SKILL.md」と記載しているが、これは不正確である。`skills/review/SKILL.md:39` (`## Non-Interactive Mode Behavior` 節) に #1097 (2026-07-31) 由来の同種ガードが実在する。正確には「ガードが存在しない」のではなく「ガードは存在するが実行判断地点 (Step 12.3) から遠すぎて有効に機能しなかった」であり、本 Spec の是正方針 (Step 12.3 へのローカルなリマインダー追加) はこの精緻化された理解に基づく。同ファイルは append-only の履歴記録のため本 Spec では変更しない。

**Related への追加候補** (Issue 本文更新時に反映): #1212 (review フェーズでの再発実測、本コメントの出典), #1053 (review 異常終了の下流影響という点で隣接)。

**関連する過去 Spec** (disposable、参照のみ): `docs/spec/issue-994-code-bats-foreground-guidance.md` (最初のガード追加), `docs/spec/issue-1097-review-headless-foreground.md` (review 側ガード追加), `docs/spec/issue-1123-manual-recovery-review-rerun.md` (SSoT 統合、内容のみ変更・位置は不変)。

## Iteration 1 (fix cycle, 2026-08-07, PR #1247)

### Trigger

前サイクル (iteration 0, 本 Spec の Implementation Steps 1〜3) は着地・merge・verify PASS したが、約 2 時間後の `/auto 1234` code phase で同一の失敗モード (silent no-op) が 4 回連続再発し、`auto-retry-on-fail` 上限 (3/3) に到達した。`/verify` が post-merge observation AC 2 件のうち 1 件を FAIL 判定し、本 Issue を reopen した。

### Root Cause (iteration 1)

iteration 0 が追加したガード (「再呼び出し保証のない実行サーフェスでは foreground + 明示 `timeout` で実行する」) には暗黙の前提があった: **明示 `timeout` を指定すれば foreground 実行が保証される**、という前提である。しかし Bash tool の `timeout` パラメータには 600000ms (10 分) の上限があり、これを超えるコマンドは tool 側が自動的にバックグラウンドへ移行させる。iteration 0 で採用した `timeout: 600000` は実測 (`docs/reports/orchestration-recoveries.md` #1234 記録) で不十分だったことが判明した: serial `bats tests/` フルスイートの実測時間が 10 分の ceiling を超え、"foreground で起動したはずのコマンドが勝手にバックグラウンドへ移行する" 状態になり、エージェントが完了通知を待ってターンを終えた。

### Changed Files (iteration 1)

- `modules/test-runner.md`: Step 1 に並列 bats 実行 (`bats --jobs`) の推奨と job 数のリテラル解決手順、GNU `parallel` 不在時の sharded serial fallback を追加。Step 2 に caller 指定の `timeout` も 600000ms を超えられない旨を明記
- `skills/code/SKILL.md`: Step 9 の実行サーフェス制約に "timeout だけでは foreground を保証しない" corollary を追加。Behavioral Change Detection のフルスイート override を並列形に変更し、job 数をリテラル値へ分解する二段階コマンドに置換 (worktree isolation guard がコマンド置換 `$(...)` を拒否するため)
- `skills/review/SKILL.md`: Non-Interactive Mode Behavior に同じ corollary を追加。job 数解決も同じ二段階コマンドに統一
- `modules/execution-context.md`: SSoT の MUST rule に tool ceiling corollary を追加し、Precedents に #1213/#1234 を追記 (review フェーズで検出された SSoT 未更新の是正)
- `tests/code.bats`, `tests/review.bats`, `tests/test-runner.bats`: 上記変更を検証する構造テストを追加 (計 17 件)

### Implementation Steps (iteration 1)

1. `modules/test-runner.md` Step 1 に並列実行の推奨(job 数はリテラル値への分解を明記)と GNU `parallel` 不在時の sharded serial fallback を追加。Step 2 に 600000ms ceiling の明記を追加 (→ Issue AC: `section_contains "modules/test-runner.md" "Step 2" "600000"`)
2. `skills/code/SKILL.md` Step 9 の実行サーフェス制約に ceiling corollary を追加し、Behavioral Change Detection のフルスイート override を `nproc`/`sysctl` の結果をリテラル値に分解する二段階コマンドへ置換 (→ Issue AC: `section_contains "Step 9" "bats --jobs"`, `section_not_contains "Step 9" "bats --jobs $("`)
3. `skills/review/SKILL.md` の Non-Interactive Mode Behavior に同じ corollary と二段階コマンドを追加
4. `modules/execution-context.md` の SSoT に corollary を追加し、3 つの consumer ファイルとの整合を取る
5. `tests/code.bats` / `tests/review.bats` / `tests/test-runner.bats` に構造テストを追加 (→ Issue AC: `command "bats tests/code.bats tests/review.bats tests/test-runner.bats"`)

### Verification (iteration 1)

- `bats --jobs 18 tests/` — 1525 passed, 0 failed
- `python3 scripts/validate-skill-syntax.py skills/code/SKILL.md skills/review/SKILL.md` — 0 errors, 0 warnings
- `bash scripts/check-forbidden-expressions.sh` — 違反なし
- worktree isolation guard の再現確認: `/review` セッション内で `echo $(echo test)` を実行し、コマンド置換が一律ブロックされることを直接確認 (`/code` も Step 2 で必ず worktree に入るため同じ制約を受ける)

### review フェーズでの発見 (iteration 1)

`/review` の Code Review (Step 10) が、iteration 1 の実装自体にも構造的な問題を発見した:
- **MUST**: `bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/` に含まれる `$(...)` コマンド置換が、`/code`/`/review` が必ず入る worktree セッション内で worktree isolation guard に一律ブロックされる (実際に `/review` セッション内で再現確認)。job 数をリテラル値に分解する二段階コマンドへ修正した
- **MUST**: 本サイクルの実装内容 (並列形・ceiling ルール) を検証する Pre-merge AC が Issue に存在しなかった (iteration 0 の AC がそのまま残っていた)。Issue #1213 に AC 4 件を追加し、Post-merge observation AC 2 件を「バックグラウンド移行なしに完了したことを観察する」という反証可能な形に書き換えた
- **SHOULD**: GNU `parallel` 不在時の fallback (旧: 単純な serial `bats tests/` 再実行) が ceiling 超過を再現するリスクがあったため、sharded serial batches (test-file group 単位での分割実行) に変更した
- **SHOULD**: `modules/execution-context.md` (SSoT) が未更新のまま 3 つの consumer ファイルに同じ corollary が重複していた (SSoT Reverse Reference antipattern) — SSoT を先に更新する形に是正した
- **SHOULD**: `skills/code/SKILL.md` に記載していた実測テスト件数 ("1516 tests passing") が実際の値 (1525) と不一致だったため、具体的な件数を削除した

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜3 を Spec の記述通りに実施した。

### Design Gaps/Ambiguities

- Step 10 (Verify Command Consistency) の "Patch route branch-scoped CI AC exclusion" は patch route 限定の記載だが、pr route でも同じ構造的な問題が生じる: Step 10 は PR 作成 (Step 11) より前に実行されるため、AC4 (`github_check "gh pr checks" "Run bats tests"`) はこの時点では PR が存在せず判定不能 (UNCERTAIN) になる。今回は AC4 のチェックボックスのみ未チェックのまま残し (他 4 件は PASS で `[x]` 化)、CI 確認は `/review` に委ねた。SKILL.md にはこの pr route 側の扱いが明文化されていないため、次回同様のケースがあれば SKILL.md 側への追記を検討する価値がある。

### Rework

N/A — 実装・テスト・verify いずれも一発で完了し、手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate (`check-pre-merge-ac.sh`) は unchecked_count=0 で全 9 件 (iteration 0 の 5 件 + iteration 1 の 4 件) チェック済みだったため、override マーカーなしで通常フローのまま squash merge を実行した。
- `review_incomplete_fallback` チェックは `reconcile-phase-state.sh` の diagnosis が "Review Response Summary found" (organic completion) を示しており、fallback 起因ではないと判定した。
- `mergeable=UNKNOWN` が 2 回連続したが `gh-pr-merge-status.sh` の内蔵リトライで `mergeable=true, reason=clean` に解決したため、追加対応は不要だった。

### Deferred Items
- Post-merge observation AC (code phase / review phase の 2 件) は `verify-type: observation event=auto-run session=next` により次回以降の `/auto` 実行時に評価される — `/verify` に引き継ぐ。
- `cause=background-notification-wait` の閾値到達監視 (現在 2/3) — 本 Issue の修正が有効なら 3 件目は発生しないはずで、この閾値到達の有無自体が実効性の指標になる。`/verify` で観測を継続すること。

### Notes for Next Phase
- `/verify` は Post-merge observation AC 2 件 (並列形・バックグラウンド移行なしでの完了) を次回 `/auto` 実行ログから評価すること。
- squash merge・remote branch 削除は正常完了 (`gh pr merge --squash --delete-branch` エラーなし)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 起票時点のスコープは `skills/code/SKILL.md` / `run-code.sh` に限定されていたが、#1212 の review フェーズ実測をコメントとして投稿した結果、`/spec` がこれを consume して **code / review 両方**へ拡大した。AC も 3 件 → 5 件、Post-merge も 1 件 → 2 件 (code phase / review phase) に増えている。L0 (Issue コメント) 経由でスコープが拡張された良い事例

#### spec
- watchdog kill (1800s 無出力) が発生したが実害なし。`## Design Complete` コメント (02:27:09Z) は kill (11:32 JST) より前に投稿済みで、Spec 作成・push・Size 再評価 (M → L) はすべて完了していた。**作業完了後にターンを終える直前で kill された**形

#### code
- Deviations / Rework とも N/A。Implementation Steps 1〜3 を逐語適用
- Design Gaps で **pr route 側の Step 10 問題**を指摘している: Step 10 (Verify Command Consistency) は PR 作成 (Step 11) より前に実行されるため、`github_check "gh pr checks"` 形式の AC は判定不能 (UNCERTAIN) になる。#1212 で明文化したのは patch route 側 (`branch-scoped CI AC exclusion`) のみで、pr route 側は未記載。今回は AC4 のチェックボックスを未チェックのまま残して `/review` に委ねる運用で回避した

#### review
- **本 Issue が修正対象としている失敗モードそのものが、本 Issue の review フェーズで発生した**。最終出力は「バックグラウンドタスクの完了通知を待ちます。」。#1212 に続く連続 2 回目
- ただし review の**指摘内容は極めて有用**だった。code フェーズはガードを分岐非依存な位置へ引き上げたが、review はさらにその下の「なぜガードがあっても守られなかったか」を特定している — `modules/test-runner.md` Step 2 が `timeout: 120 seconds` を固定値で指示しており、フルスイート (実測 ~407s) は**前景で回しても 120 秒で打ち切られる**。つまり #994 が追加した「前景で実行せよ」というガードは、それ単体では物理的に守れない指示だった。この制約こそがエージェントを `run_in_background: true` へ逃がす圧力になっていた
- この修正 (`test-runner.md` の caller-supplied timeout、`skills/review/SKILL.md` の明示 timeout 要件、bats テスト 4 件) が失われていたら、ガードを引き上げても同じ失敗が続いていた可能性が高い

#### merge
- merge gate (`review_incomplete_fallback=true`) がブロックし、**work loss を防いだ 2 例目**。Tier 3 sub-agent も `action=abort` で人間判断を求める正しい挙動
- 親セッションが手動復旧: diff 精査 → `bats tests/` 1507 件 PASS → sign-off 付き commit (`3a382d81`) → push → `decision=override fallback=true` マーカー → merge 再実行。`--write-manual-recovery` で `cause=background-notification-wait` として記録済み
- squash merge 時に残置ワークツリー (`review+pr-1225`) がブランチを保持していたため `--delete-branch` が失敗したが、merge フェーズ自身が worktree/branch を cleanup して解決している

#### verify
- Pre-merge 5 件全 PASS。AC3 (`section_not_contains`) は「旧位置から除去されたこと」を検証する negative assertion で、実際に切り出したセクションの `grep -c` が 0 であることを独立に確認した。**ガードの移動を伴う Issue では positive (新位置に存在) と negative (旧位置に不在) を対で置くのが有効**という良い設計例
- `cause=background-notification-wait` の manual recovery が本日 2 件 (#1212, #1213) 記録された。`recoveries-auto-fire.threshold` は 3 なので、次に 1 件出れば閾値到達で起票候補になる

### Improvement Proposals
- **pr route 側の Step 10 と `gh pr checks` AC の関係を SKILL.md に明文化する** — Code Retrospective の Design Gaps が指摘した内容。#1212 が patch route 側 (`branch-scoped CI AC exclusion`) を明文化した際の対称ケースであり、隣接する既存 Issue はない。ただし本セッションは締めに入るため、次サイクルの起票候補として本節に記録するに留める (Tier 2 相当)
- `cause=background-notification-wait` の閾値到達監視 — 現在 2/3。次の 1 件で `recoveries-auto-fire` の起票候補になるが、`.wholework.yml` で `enabled: false` (#1179) のため自動起票はされず、`/verify` Step 15 が Recommend を出力する形になる。本 Issue の修正が有効なら 3 件目は発生しないはずで、**この閾値到達の有無自体が #1213 の実効性の指標**になる

## review retrospective (iteration 1, PR #1247)

### Spec vs. implementation divergence patterns

`/verify` FAIL による reopen 後、`/code` が直接 fix cycle の実装に入り、`/spec` の再実行 (新しい `## Design Complete` コメント) が行われなかった。結果として、本 Spec の Implementation Steps / Pre-merge AC が iteration 0 (guard 配置修正) の内容のまま残り、iteration 1 が実際に実装した内容 (並列 bats 実行・timeout ceiling ルール) を検証する AC が 1 件も存在しない状態で PR が作成された。`/review` の Code Review (Step 10, review-spec 観点) がこの乖離を MUST として検出し、Step 12/13 で Issue AC・Spec の両方を修正したことで是正されたが、`/review` が拾わなければ merge・`/verify` はこの PR の実質的な変更を一度も検証しないまま通過していた可能性が高い。fix cycle (reopen 後の再実装) が Spec 更新を経ずに実装へ直行できる経路自体が、この種の AC カバレッジ欠落を構造的に許容している。

### Recurring issues

本 PR の実装自体 (`bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/`) が、worktree セッション内での `$(...)` コマンド置換ブロックという既知の制約 (`docs/spec/issue-1181-recovery-record-consolidation.md`、`docs/sessions/56516-1785934632-2026-08-05/session.md` で先例あり) に抵触していた。`/code`/`/review` は共に worktree に必ず入るため、SKILL.md や module ファイルが「エージェントが worktree セッション内で実行する」ことを想定した Bash コマンド例を書く際は、コマンド置換の使用を避けるか、少なくともこの制約への言及を伴うべきである。`modules/verify-executor.md` の `command "..."` 形式で使われる `$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)` は verify-executor 経由の実行 (Bash tool 経由の直接実行ではない) なので影響を受けないが、SKILL.md 本文内でエージェントが直接実行することを想定した同型パターンは今後も同じ落とし穴になりうる。横断的な grep (`$(nproc` や `$(sysctl` など worktree セッション内で実行されうるコマンド置換パターン) による棚卸しは、次の類似 Issue が出た際の検討候補として記録する。

### Acceptance criteria verification difficulty

Nothing to note — Pre-merge AC 5 件 (iteration 0) は全て静的検証で PASS、CI も全件 SUCCESS だった。Step 12 で追加した iteration 1 の AC 4 件は `/verify` 実行時に評価される。

## Verify Retrospective (iteration 1 — fix cycle 後)

Pre-merge 9 件全 PASS、Post-merge 2 件 SKIPPED (`session=next` 未伝播)。iteration 1 で追加した AC 6〜9 も全て PASS。

### iteration 0 のガードがなぜ失敗を防げなかったか

iteration 0 は「前景実行 + 明示 `timeout`」を要求したが、**`timeout: 600000` は Bash tool の上限値**であり、超過したコマンドは tool が自動的にバックグラウンドへ移行させる。つまりガードは失敗を**防がず先送りしていた**。

`/auto 1234` の code phase での実測 (2026-08-07 14:46–16:14 JST):

| 項目 | 実測 |
|---|---|
| silent no-op | **4 回連続** |
| auto-retry | **3/3 上限到達** |
| 空転 | 約 88 分 |
| 同一実装の書き直し | 4 回 (各試行が前回の worktree を stale として削除) |

3 回目のログが決定的だった: 「10分のタイムアウトを超えたためバックグラウンドに移行しました。完了通知を待って Step 9 以降を継続します。」

**設計上の教訓**: 「ガードを分岐非依存な位置に置く」(iteration 0 の主眼) だけでは不十分で、**そのガードが物理的に守れる指示になっているか**の検証が要る。iteration 0 の Verify Retrospective は「前景実行のガードだけでは不十分だった (120s 固定 timeout がフルスイートを打ち切る)」と一段深い原因を捉えていたが、その修正 (`timeout: 600000` の明示) が **上限値そのものであること**を見落としていた。制約値を指示に書くときは、その値が上限か否かを確認する必要がある。

### iteration 1 の対処が 4 層になった理由

| 層 | 内容 | 役割 |
|---|---|---|
| 1 | ceiling ルールの明文化 | なぜ timeout だけでは不十分かを SKILL.md に残す |
| 2 | 並列実行への切り替え (`bats --jobs`) | 主対策 — 上限を超えなければ分岐自体が発生しない |
| 3 | 「バックグラウンド移行されたら待たずに失敗として報告」 | 第二の防御 — 層 2 が効かない環境での最後の砦 |
| 4 | `--jobs` 不在時の分割実行フォールバック | 層 2 の前提 (GNU parallel) が崩れた場合の退避 |

層 3 が重要。iteration 0 の失敗は「前景で起動したはずが勝手にバックグラウンドになった」状況でエージェントが待機したことなので、**移行が起きた後の行動**を規定しないと同じ穴が残る。

### `/review` が捉えた 2 つの MUST

- **コマンド置換 `$(...)` が worktree セッション内でブロックされる** — 親セッションも本日実際に遭遇 (`too complex to verify that it stays inside the worktree`)。review が再現確認のうえリテラル分解へ修正した。SKILL.md 本文に「エージェントが worktree 内で直接実行する Bash 例」を書く際の一般的な落とし穴で、`modules/verify-executor.md` の `command "..."` 形式 (verify-executor 経由なので影響なし) と混同しやすい
- **fix cycle の実装を検証する Pre-merge AC が存在しなかった** — reopen 後の Issue body は iteration 0 の AC しか持たず、iteration 1 の実装 (並列化・ceiling 明記・構造テスト) を検証する条件がなかった。review が AC 4 件を追加し、Post-merge observation AC 2 件を「foreground 実行の形跡」から「並列形で起動され、バックグラウンド移行なしに完了」へ**反証可能な文言に書き換えた**

後者は fix cycle 一般の構造的ギャップ。`/verify` FAIL → reopen → `/code` の経路では、Issue body の AC が iteration 0 のまま据え置かれるため、新しい実装の検証条件が自動では追加されない。今回は `/review` が気づいたが、機構としては保証されていない。

### merge gate が 3 例目として機能した

`/merge` が「未チェック pre-merge AC 4 件 (#6〜#9)」でブロックした。これは #1212/#1213 iteration 0 の override ケース (review が作業を残したまま終了) とは性質が異なり、**実際に AC を検証すれば解決する**ケースだった。親セッションが 4 件を検証して checkbox を更新し、merge を再実行して通過している。gate が「AC を追加したが検証しなかった」という抜けを正しく捕捉した。

### Improvement Proposals

- **fix cycle で Issue body の AC が iteration 0 のまま据え置かれる構造的ギャップ** — `/verify` FAIL → reopen → `/code` の経路で、新しい実装を検証する Pre-merge AC が自動では追加されない。今回は `/review` が MUST として指摘して 4 件追加したが、機構としては保証がない。`/code` の fix-cycle 経路 (`skills/auto/SKILL.md` Step 2a で検出される状態) に「iteration N の実装を検証する AC を Issue body へ追加する」ステップを設ける余地がある。ただし既存 Issue (#1096「新規追加する検証系テストの assert が実装前に FAIL することを確認させる」、#1125「パーサ系変更への negative/edge case 実測ステップの定型化」) と検証設計という点で隣接するため、独立起票せず本節に記録するに留める (Tier 2)
- **制約値を指示に書く際、その値が上限か否かを確認する** — iteration 0 が `timeout: 600000` を「実測 ~407s をカバーする値」として書いたが、実際は tool の上限値であり超過時の挙動 (自動バックグラウンド移行) が指示の前提を壊していた。同種のパターン (tool/API の上限値をそのまま指示に埋め込む) は他にもありうるが、現時点で具体的な再発候補が特定できていないため、横断棚卸しは次に類似事例が出た時点で判断する (Tier 3)
