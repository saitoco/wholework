# Issue #1213: auto: 再呼び出し保証のない実行サーフェスでの background task 完了通知待ちを全 phase で構造的に防止

> **現在の作業対象は iteration 2 (2026-08-10)。** 実装内容は下部の `## Iteration 2 (fix cycle, 2026-08-10)` 節を参照すること。本ファイル冒頭の `## Overview` / `## Changed Files` / `## Implementation Steps` は iteration 0 (2026-08-07) の記録であり、履歴として保持している。`## Verification` のみは全 iteration 分を統合した現行リスト (Issue 本文の Acceptance Criteria と 1:1) に更新済み。

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

**iteration 2 の spec フェーズで consume したコメント** (cutoff: `2026-08-10T04:18:35Z` — 直近の `phase/*` ラベル付与時刻, Primary で解決):

- saito / MEMBER / first-class / Issue Retrospective — スコープを wrapper 側一括担保へ転換した判断根拠 (`/spec` はフルスイート実行の指示自体を持たない、`test-runner.md` / `execution-context.md` の読み手が限定的、という 3 つの調査事実)、ユーザー確認で決定した 2 点 (全 phase を wrapper 側で担保 / `run-spec.sh` の auto-retry 欠如は #1329 へ切り出し)、AC を outcome-based に保ち手段を固定しない方針、系譜 4 世代の整理 / https://github.com/saitoco/wholework/issues/1213#issuecomment-5235850418
- saito / MEMBER / first-class / Triage AC audit — iteration 2 の 3 件目 rubric AC が Pattern 2 (常時 PASS リスク) に該当。要求 3 要素のうち「方式を選んだ理由」「4 世代の経緯」が Issue 本文に既出のため、実装が進まなくても grader が PASS しうる。修復案 2 種を提示 / https://github.com/saitoco/wholework/issues/1213#issuecomment-5235867942

両コメントとも本フェーズで反映済み: 前者は Iteration 2 の設計方針そのもの、後者は Issue 本文の AC 修正 (rubric の判定対象を `modules/execution-context.md` に限定 + `section_contains` の機械的裏取りを追加) として適用した。

**iteration 2 の review フェーズで consume したコメント** (cutoff: `2026-08-10T05:26:04Z` — 直近の `phase/*` ラベル付与時刻, Primary で解決, COMMENT_SCOPE=issue+pr):

No new comments since last phase. Cross-phase marker exception scan (`type=verify-fail` / `type=preview-ac-unverified`) は line 32 の iteration-1 verify-fail marker のみを検出したが、これは spec フェーズで既に consumed 済み (上記) のため再掲しない。PR #1332 のコメントも 0 件。

## Changed Files

- `skills/code/SKILL.md`: Step 9 の実行サーフェス制約を、Behavioral Change Detection 分岐内 (旧位置: check 2 の `bats tests/` コードフェンス直後) から、Step 9 冒頭 (`**Operate route**: ...` 行の直後、Behavioral Change Detection 見出しより前) の分岐非依存な位置へ移動。旧位置の記述は "See the execution surface constraint above" 形の短い参照へ置換 (`run_in_background` という語自体は旧位置から除去)
- `skills/review/SKILL.md`: Step 12.3 "Lightweight Re-check" の `Re-run tests/validation` 箇条書きに、同一制約への実行判断地点直近のローカルなリマインダーを追加 (ファイル冒頭の既存ガード (`## Non-Interactive Mode Behavior` 節) だけでは #1212 の再発を防げなかったため)
- `modules/execution-context.md`: "Re-invocation Guarantee and Notification-Dependent Waiting" 節の Callers テーブルを更新 — `skills/code/SKILL.md` の参照箇所説明を新位置に、`skills/review/SKILL.md` の参照箇所説明に Step 12.3 のローカルリマインダーを追加

## Implementation Steps

1. `skills/code/SKILL.md` Step 9: "**Operate route**: skip this entire Step 9 ..." 行の直後に、実行サーフェス制約を述べる新規段落を追加する。文言は既存の `${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" 参照を維持しつつ、「Step 9 内のどのテストコマンド (フルスイート override / `test-runner.md` への委譲) にも適用される」旨を明記する。続けて、Behavioral Change Detection 分岐内 (check 2、`bats tests/` コードフェンスの `(Same pre-check guard applies — ...)` 行の直後) にあった旧ガード文 ("When `/code` itself is running in an execution surface without a re-invocation guarantee...") を削除し、"(...See the execution surface constraint above for foreground/timeout requirements.)" という短い参照に置き換える (→ acceptance criteria AC1, AC2, AC2b)
2. `skills/review/SKILL.md` Step 12.3 (681 行目付近, "### 12.3. Lightweight Re-check"): `- Re-run tests/validation` 箇条書きの末尾に、フルスイート実行を選択する場合は `## Non-Interactive Mode Behavior` 節の foreground 制約がここにも適用される旨のローカルなリマインダーを追記する。`${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` § "Re-invocation Guarantee and Notification-Dependent Waiting" を参照する (→ acceptance criteria AC4)
3. (after 1, 2) `modules/execution-context.md` の "## Callers" テーブル、"Re-invocation Guarantee and Notification-Dependent Waiting" 節の行を更新する: `skills/code/SKILL.md` の説明を「Behavioral Change Detection foreground-execution note」から「Step 9 execution surface constraint, stated once before the Behavioral Change Detection subsection」に、`skills/review/SKILL.md` の説明に「; Step 12.3 Lightweight Re-check local reminder」を追加する (→ SSoT Module Cross-Check の整合性維持。`skills/code/SKILL.md` の "SSoT Module Cross-Check" ステップが `/code` 時に自動検証する)

## Verification

全 iteration 分を統合した現行リスト。Issue 本文の `## Acceptance Criteria` と 1:1 で対応する (Pre-merge 14 件 / Post-merge 3 件)。

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md において、再呼び出し保証のない実行サーフェス (--non-interactive / fork / Workflow) での background task 完了通知待ちを禁じる指示が、フルスイート実行の先行分岐に依存しない位置に配置されている" --> (iteration 0) 実行サーフェス制約の指示が分岐非依存な位置に配置されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 9" "run_in_background" --> (iteration 0) `skills/code/SKILL.md` の Step 9 冒頭 (分岐非依存な位置) に `run_in_background` の扱いが明記されている
- <!-- verify: section_not_contains "skills/code/SKILL.md" "Behavioral Change Detection" "run_in_background" --> (iteration 0) 旧ネスト位置 (Behavioral Change Detection 分岐内) から実行サーフェス制約の記述 (`run_in_background`) が除去されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する
- <!-- verify: section_contains "skills/review/SKILL.md" "12.3" "foreground" --> (iteration 0) `skills/review/SKILL.md` の Step 12.3 (Lightweight Re-check) に実行サーフェス制約 (foreground 実行) への言及が追加されている
- <!-- verify: section_contains "skills/code/SKILL.md" "Step 9" "bats --jobs" --> (iteration 1) Step 9 のフルスイート override が並列形 (`bats --jobs`) を指定している
- <!-- verify: section_not_contains "skills/code/SKILL.md" "Step 9" "bats --jobs $(" --> (iteration 1) Step 9 のフルスイート override がコマンド置換 (`$(...)`) を含まない (worktree isolation guard 回避のため、job 数はリテラル値へ分解する)
- <!-- verify: section_contains "modules/test-runner.md" "Step 2" "600000" --> (iteration 1) `modules/test-runner.md` Step 2 が Bash tool の timeout ceiling (600000ms) を明記している
- <!-- verify: command "bats tests/code.bats tests/review.bats tests/test-runner.bats" --> (iteration 1) 追加した構造テスト (14 件) が pass する
- <!-- verify: rubric "再呼び出し保証のない実行サーフェスでの background task 完了通知待ちを禁じる制約が、個々の SKILL.md 本文への記述に依存しない経路で担保されている。少なくとも issue / spec / code / review / merge の 5 phase に制約が届くことが、実装または文書から確認できる" --> (iteration 2) 制約が SKILL.md 本文非依存の経路で全 phase に届く
- <!-- verify: rubric "skills/spec/SKILL.md がフルスイート実行の指示を持たないにもかかわらず spec phase で本事象が発生した事実を踏まえ、SKILL.md に該当指示を持たない phase でも制約が有効となる理由が、実装または文書で説明されている" --> (iteration 2) 指示を持たない phase でも有効である理由が説明されている
- <!-- verify: rubric "modules/execution-context.md に、本 iteration が実装した制約注入の方式 (注入箇所のファイルパスと、prompt へ前置される仕組み) と適用範囲 (どの phase に届くか)、およびその方式を選んだ理由 (phase 単位の SKILL.md 本文追記が取りこぼしを繰り返した経緯) が追記されている。Issue 本文ではなく実装成果物側の記述で判定すること" --> (iteration 2) 採用方式とその選択理由が実装成果物 (`modules/execution-context.md`) に記録されている
- <!-- verify: section_contains "modules/execution-context.md" "Wrapper-Level Constraint Injection" "guard-prefix.sh" --> (iteration 2) 上記 rubric の機械的裏取り — 注入箇所を説明する節が `modules/execution-context.md` に存在する
- <!-- verify: command "bats tests/run-spec.bats tests/run-issue.bats tests/run-merge.bats tests/run-code.bats tests/run-review.bats" --> (iteration 2) wrapper 群の bats スイート 5 本が回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前 3 項が担う)

### Post-merge

- 次回以降の `/auto` の code phase ログで、フルスイート実行が並列形 (`bats --jobs`) で起動され、バックグラウンド移行なしに完了していることを観察する <!-- verify-type: observation event=auto-run session=next -->
- 次回以降の `/auto` の review phase ログで、フルスイート実行が並列形 (`bats --jobs`) で起動され、バックグラウンド移行なしに完了していることを観察する <!-- verify-type: observation event=auto-run session=next -->
- 次回以降の `/auto` の spec phase で、フルスイート実行またはバックグラウンドタスク待ちが発生した場合に silent no-op にならないことを観察する <!-- verify-type: observation event=auto-run session=next -->

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

## Iteration 2 (fix cycle, 2026-08-10)

### Overview (iteration 2)

iteration 0/1 が採った「制約文を `skills/*/SKILL.md` の適切な位置に置く」というアプローチは、**その SKILL.md にフルスイート実行の指示がある phase にしか届かない**。2026-08-10 に `/spec` phase (#1130) で同一の失敗モードが再発し、`skills/spec/SKILL.md` にはフルスイート実行の指示が存在しないこと (= エージェントの自発的判断で実行していたこと) が確認された。

本 iteration は、制約の担保層を SKILL.md 本文から **`claude -p` を起動する wrapper 層** へ移す。`scripts/guard-prefix.sh` の `GUARD_PREFIX` は 5 本の wrapper (`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh`) すべてが source し、それぞれの `PROMPT` の**先頭**に前置される既存の共有文字列である。ここに制約を 1 箇所追記すれば、SKILL.md に指示を持たない phase を含む全 5 phase に届く。

### Root Cause (iteration 2)

これまでの 3 世代はいずれも「制約文の配置」を変えていたが、**配置を変えても届かない phase が存在する**ことが今回判明した。

| 事実 | 確認コマンド | 結果 |
|---|---|---|
| `modules/test-runner.md` を読む skill | `grep -ln "modules/test-runner.md" skills/*/SKILL.md` | code / review / verify の 3 つのみ |
| `modules/execution-context.md` を参照する skill | `grep -ln "execution-context.md" skills/*/SKILL.md` | code / review の 2 つのみ |
| `skills/spec/SKILL.md` のフルスイート実行指示 | 同ファイルの `bats` 言及を全件確認 | すべて「Spec に何を書くか」の規約。実行指示は 0 件 |

いずれも Issue 本文の記載どおりで、実装との矛盾はなかった (Step 6 の conflict detection: 検出なし)。

`/spec` は指示がないままエージェントの自発的判断でフルスイートを実行し、バックグラウンド待ちに入った。**指示を持たない phase には、本文をどこに置いても制約は届かない。** 同じ理由で `issue` / `merge` も潜在的に同じ穴を持つ。

### Changed Files (iteration 2)

- `scripts/guard-prefix.sh`: `GUARD_PREFIX` に background task 完了通知待ちを禁じる段落を 1 つ追加 (既存 3 段落の 2 段落目「autonomous mode」の直後に挿入)。bash 3.2+ 互換 (文字列代入のみ、新規構文なし)。**実装上の必須制約**: `GUARD_PREFIX` は二重引用符で囲まれた bash 文字列のため、追記テキストにバッククォート・`$`・二重引用符・バックスラッシュを含めてはならない (バッククォートと `$(` はコマンド置換として評価され、`"` は文字列を途中で閉じる)。コード片の引用はバッククォートなしの素の表記で書く
- `modules/execution-context.md`: 「Re-invocation Guarantee and Notification-Dependent Waiting」節に `### Wrapper-Level Constraint Injection` サブ節を新設 — 注入箇所 (`scripts/guard-prefix.sh`)・注入の仕組み (5 wrapper の `PROMPT` 先頭に前置)・適用範囲 (issue / spec / code / review / merge の 5 phase、exhaustive)・SKILL.md に指示を持たない phase でも有効な理由・phase 単位の本文追記が 4 世代にわたり取りこぼした経緯を記載。あわせて同ファイル末尾の `## Callers` リストに `scripts/guard-prefix.sh` の行を追加
- `tests/run-spec.bats`: `claude` mock の prompt スキャンに新制約の検出を追加し、`@test` を 1 件追加
- `tests/run-issue.bats`: 同上
- `tests/run-merge.bats`: 同上
- `tests/run-code.bats`: 同上
- `tests/run-review.bats`: 同上
- `docs/structure.md`: `scripts/guard-prefix.sh` の説明行 (「Skill runners:」直下) に background-wait 制約の担保を追記
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記 `docs/structure.md` の変更に対応する日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

`modules/orchestration-fallbacks.md:500` も `guard-prefix.sh` に言及するが、sourceable helper パターンの例示としての言及であり内容変更は不要 (grep で確認済み)。

### Implementation Steps (iteration 2)

1. `scripts/guard-prefix.sh` の `GUARD_PREFIX` に、background task 完了通知待ちを禁じる段落を追加する (→ AC10, AC11)。挿入位置は既存 2 段落目 (`You are running in autonomous mode ...` で始まる段落) の直後、3 段落目 (`Boundary: ...`) の前。段落は次の要素を含む: (a) このプロセスには再呼び出し保証がなく完了通知は届かないという事実、(b) `run_in_background: true` / Workflow / 完了前に返る Agent・Task ディスパッチの完了待ちでターンを終えてはならないという MUST、(c) foreground で同期実行し同一ターン内で結果を消費すること、(d) Bash tool の 600000 ms timeout ceiling を超えるコマンドは自動的にバックグラウンドへ移行するため、コマンド側を短縮すること (bats 全スイートなら並列実行)、(e) それでもバックグラウンド移行された場合は完了通知を待たず失敗として報告すること、(f) 詳細は `modules/execution-context.md` の該当節を参照する旨。**バッククォート・`$`・二重引用符・バックスラッシュを一切使わない素のテキストで書く** (Changed Files の必須制約を参照)
2. `modules/execution-context.md` の「Re-invocation Guarantee and Notification-Dependent Waiting」節に `### Wrapper-Level Constraint Injection` サブ節を新設する (after 1) (→ AC11, AC12, AC13)。記載内容は Changed Files のとおり。適用範囲の列挙には **(exhaustive)** マーカーを付す (`modules/skill-dev-checks.md` § Exhaustive/Example Markers)
3. `modules/execution-context.md` 末尾の `## Callers` リストに `scripts/guard-prefix.sh` の行を追加する (after 2)。既存の「"Re-invocation Guarantee and Notification-Dependent Waiting" section:」の箇条書きに追記する形とし、「wrapper 経由で全 phase の prompt に前置される」旨を明記する
4. `tests/run-spec.bats` / `tests/run-issue.bats` / `tests/run-merge.bats` / `tests/run-code.bats` / `tests/run-review.bats` の 5 本すべてで、既存の `claude` mock 内にある prompt スキャンブロック (`if echo "$arg" | grep -q 'IMPORTANT - HEADLESS SKILL EXECUTION'; then ... PROMPT_HAS_GUARD=1 ...`) の直後に、新制約を検出する分岐を追加し `PROMPT_HAS_BG_GUARD=1` を `$CLAUDE_CALL_LOG` へ書き出す (after 1) (→ AC14)。検出キーワードは `GUARD_PREFIX` 側にしか現れない語句を選ぶこと (各 bats の SKILL.md モックは数行のスタブなので衝突しないが、将来の誤検出を避けるため実装時に `grep` で一意性を確認する)。あわせて各ファイルの既存 `@test "guard: prompt contains HEADLESS SKILL EXECUTION guard text"` の直後に `@test` を 1 件追加し、`grep -q "PROMPT_HAS_BG_GUARD=1" "$CLAUDE_CALL_LOG"` を assert する。呼び出し形式は各ファイルの既存 guard テストと同一 (`run bash "$SCRIPT" 123` → `[ "$status" -eq 0 ]`)。5 本とも `setup()` で実体 `scripts/guard-prefix.sh` を `$MOCK_DIR` へ `cp` 済みのため、テストは出荷される文字列そのものを検証する
5. `docs/structure.md` の `scripts/guard-prefix.sh` 行を更新する (after 1) — 現行「includes anti-early-stop and boundary reminders for autonomous execution」に、再呼び出し保証のない実行サーフェスでの background 完了通知待ち禁止を全 phase へ配る役割を追記する
6. `docs/ja/structure.md` の対応行を同期する (after 5)。`docs/translation-workflow.md` の Sync Procedure に従い、日本語で記述する

### Alternatives Considered (iteration 2)

| 案 | 内容 | 不採用の理由 |
|---|---|---|
| `--append-system-prompt` フラグを各 wrapper に追加 | `claude -p` の起動引数として制約を渡す | 注入点が 5 箇所に分散し、`guard-prefix.sh` という既存の集約点を使わない分だけ保守面で劣る。既存の bats mock (prompt を検査する形) も作り直しになる |
| 新規 module (`modules/background-wait-guard.md`) を作り全 SKILL.md から読ませる | 「Read and follow」パターンで共有 | **本 Issue が修正しようとしている失敗そのもの** — SKILL.md 本文への記述に依存するため、読む指示を持たない phase には届かない。4 世代目の繰り返しになる |
| 環境変数 (`WHOLEWORK_NO_REINVOCATION=1`) を wrapper が export し、SKILL.md 側で分岐 | 実行文脈の機械的な伝達 | 分岐を書くのは SKILL.md 本文なので上と同じ穴。加えて `--non-interactive` が既に同じ情報を運んでいるため冗長 |
| 既存の SKILL.md 側ガード (code Step 9 / review Step 12.3 / test-runner.md) を削除して wrapper 注入へ一本化 | 重複の排除 | iteration 0/1 の Pre-merge AC 4 件 (`section_contains` / `section_not_contains`) が当該記述の存在を検証しており、削除すると回帰する。役割分担も異なる — wrapper 注入は phase 横断の backstop、SKILL.md 側は実行判断地点直近の具体的な手順 (並列 `bats --jobs` の書き方など)。両方残す |

### Tool Dependencies (iteration 2)

#### Bash Command Patterns
none — 実装は既存ファイルの編集のみ。検証に使う `bats` / `grep` は既存の `allowed-tools` で足りる

#### Built-in Tools
none — `Read` / `Edit` / `Grep` はいずれも `/code` の既存 `allowed-tools` に含まれる

#### MCP Tools
none

### Uncertainty (iteration 2)

- **`section_contains` が参照する見出しは実装で新設されるもの**: AC13 の `section_contains "modules/execution-context.md" "Wrapper-Level Constraint Injection" "guard-prefix.sh"` は、Implementation Step 2 が新設する `### Wrapper-Level Constraint Injection` 見出しに依存する。Spec 作成時点では同ファイルに当該見出しは存在しない (`grep -n "Wrapper-Level" modules/execution-context.md` が 0 件であることを確認済み)。
  - **検証方法**: Step 2 完了後に `section_contains` を実行し PASS することを確認する。`section_contains` の heading 引数は部分一致なので、見出しレベル (`###`) は判定に影響しない
  - **影響範囲**: Implementation Step 2。見出し文字列を変更する場合は Issue 本文の AC13 も同時に更新すること
- **`GUARD_PREFIX` への追記が bash 文字列として安全であること**: 二重引用符文字列内でのバッククォート・`$`・`"` の混入はコマンド置換または文字列の早期終端を引き起こす。
  - **検証方法**: 実装後に `bash -n scripts/guard-prefix.sh` (構文チェック) と、`source scripts/guard-prefix.sh && printf '%s' "$GUARD_PREFIX" | grep -c "re-invocation"` で意図どおりの文字列が入っていることを確認する。5 本の bats テストが実体の `guard-prefix.sh` を source するため、CI でも間接的に担保される
  - **影響範囲**: Implementation Step 1

### Notes (iteration 2)

**Autonomous Auto-Resolve Log** (非対話モードのため `AskUserQuestion` 不可。`modules/ambiguity-detector.md` の three-tier policy に従い auto-resolve):

- **注入方式に `scripts/guard-prefix.sh` の拡張を採用** — 理由: 5 本の wrapper がすでに source し `PROMPT` 先頭へ前置する集約点が実在するため、1 ファイルの変更で 5 phase に届く。既存パターンとの一貫性 (heuristic「既存のコードベースパターンに沿う選択肢を優先」) と最小変更 (heuristic「安全ならより単純な方」) の両方を満たす。
  - Other candidates: `--append-system-prompt` フラグ追加 / 新規 module + 全 SKILL.md からの Read / 環境変数 + SKILL.md 分岐 (いずれも Alternatives Considered 参照)
- **既存の SKILL.md 側ガードは削除せず維持** — 理由: iteration 0/1 の Pre-merge AC 4 件が当該記述の存在を検証しており、削除は回帰になる。副作用が最小の選択肢 (heuristic「下流の副作用が最も少ない選択肢を優先」)。
  - Other candidates: wrapper 注入へ一本化して SKILL.md 側を削除
- **Triage AC audit コメントの修復案は「記録先を実装成果物側に限定する」案を採用** — 理由: 監査が指摘した常時 PASS リスク (rubric が要求する 3 要素のうち 2 要素が Issue 本文に既出) を、判定対象を `modules/execution-context.md` に限定することで解消できる。監査コメントが併記を推奨していた `section_contains` による機械的裏取りも AC として追加した (Pre-merge AC 13 件目 → 14 件へ)。
  - Other candidates: 「実装の実体のみを問う形へ絞る」案 (`rubric "制約注入を実装した箇所 ... が特定でき ..."`) — 実装箇所の特定は git diff から grader が読めるが、「方式を選んだ理由」の記録要件が落ちるため不採用
- **AC14 (`command "bats ..."`) の対象ファイルを 3 本から 5 本へ拡張** — 理由: 本 iteration は `tests/run-code.bats` / `tests/run-review.bats` も変更するため、元の 3 本のままでは変更したテストが AC で回らない。AC の目的 (回帰保護) は変えていない。

**allowed-tools impact chain check**: Changed Files に `modules/*.md` (`modules/execution-context.md`) を含むため Case 2 のゲートを実行した。追記内容は `scripts/guard-prefix.sh` というパスを含むが、これは「wrapper がこのファイルを source する」という説明であって、skill に新しいスクリプト呼び出しを指示するものではない。読み手 (`grep -rl "modules/execution-context.md" skills/*/SKILL.md` → `skills/code/SKILL.md`, `skills/review/SKILL.md`) のいずれも `guard-prefix.sh` を実行しないため、`allowed-tools` の追加は不要。新規 `scripts/*.sh` の追加もないため Case 1 は非該当。

**`scripts/check-forbidden-expressions.sh` のスキャン対象外**: 同スクリプトの `SCAN_DIRS` は `skills/ modules/ agents/ tests/ docs/` であり `scripts/` を含まない。`scripts/guard-prefix.sh` への追記は禁止表現スキャンの対象外だが、`modules/execution-context.md` と `docs/structure.md` への追記は対象になる。

**本 iteration のスコープ外 (別 Issue)**:
- `run-spec.sh` の `auto-retry-on-fail` 欠如 → #1329 (復旧機構であり予防ではないため、本 Issue の除外規定に該当)
- Tier 2 detector の signature 追加 → #1323 (検出側)
- wrapper 以外の `claude -p` 起動経路 (`scripts/spawn-recovery-subagent.sh` の Tier 3 recovery sub-agent、`scripts/run-auto-sub.sh:782`) は phase 実行ではなく recovery agent の起動であり、AC が列挙する 5 phase に含まれない。同種の制約が必要かは別途判断する

**wrapper を持たない skill について**: `/verify` / `/triage` / `/audit` / `/doc` / `/auto` は `run-*.sh` を持たず常に main context (対話セッション内) で実行される。main context には再呼び出し保証があるため MUST rule の適用対象外であり、wrapper 層での注入が「全 phase をカバーする」という主張と矛盾しない。この点も `### Wrapper-Level Constraint Injection` に明記する。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜3 を Spec の記述通りに実施した。

### Design Gaps/Ambiguities

- Step 10 (Verify Command Consistency) の "Patch route branch-scoped CI AC exclusion" は patch route 限定の記載だが、pr route でも同じ構造的な問題が生じる: Step 10 は PR 作成 (Step 11) より前に実行されるため、AC4 (`github_check "gh pr checks" "Run bats tests"`) はこの時点では PR が存在せず判定不能 (UNCERTAIN) になる。今回は AC4 のチェックボックスのみ未チェックのまま残し (他 4 件は PASS で `[x]` 化)、CI 確認は `/review` に委ねた。SKILL.md にはこの pr route 側の扱いが明文化されていないため、次回同様のケースがあれば SKILL.md 側への追記を検討する価値がある。

### Rework

N/A — 実装・テスト・verify いずれも一発で完了し、手戻りは発生しなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1〜6 を逐語適用した。`GUARD_PREFIX` への追記文言はバッククォート・`$`・二重引用符 (先頭/末尾以外) ・バックスラッシュを含まない素のテキストで作成し、検出キーワードには `no re-invocation guarantee` を採用 (`GUARD_PREFIX` にのみ現れることを実装前後で `grep` により確認)。
- `modules/execution-context.md` の `### Wrapper-Level Constraint Injection` サブ節には、注入箇所・仕組み・適用範囲 (exhaustive マーカー付き) ・wrapper なし skill への非適用理由・4 世代の経緯を Spec Implementation Step 2 の指示通りに記載した。
- Issue Pre-merge AC の iteration 2 分 5 件 (rubric 3 件・section_contains 1 件・command 1 件) はすべて手動検証で PASS したためチェック済みに更新した。rubric/section_contains は fork context でも safe mode の対象外 (read-only 系) のため通常評価されるが、command 型 (AC14) は safe mode で skip されるため、`/code` セッション自身が `bats` を直接実行し 192 件 PASS を確認したうえで手動でチェックした。

### Deferred Items
- `run-spec.sh` の `auto-retry-on-fail` 欠如 → #1329 (spec phase から引き継ぎ、本 Issue のスコープ外)。
- Tier 2 detector の signature 追加 → #1323 (spec phase から引き継ぎ)。
- wrapper 以外の `claude -p` 起動経路 (`scripts/spawn-recovery-subagent.sh`、`scripts/run-auto-sub.sh:782` の Tier 3 recovery sub-agent) への同種制約の要否は未判断のまま。
- Post-merge observation AC 3 件 (code / review / spec) は `session=next` により次回以降の `/auto` 実行時に評価される。

### Notes for Next Phase
- `/review` は Pre-merge AC 5 件 (iteration 2 分) が全てチェック済みであることを CI 経由で再確認できる。rubric 3 件は静的な文書レビューでも再確認可能。
- 本セッション自体、並行する他セッションの CPU 競合により `bats` フルスイート実行が Bash tool の 600000ms timeout ceiling を複数回超過してバックグラウンド移行した (Code Retrospective 参照)。`/review` が同様のフルスイート実行を行う場合、同じ競合が再現しうることを踏まえておくとよい。
- `docs/structure.md` / `docs/ja/structure.md` は日英同期済み。追加の翻訳同期作業は不要。

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

## issue retrospective (iteration 2)

`/issue` フェーズが Issue コメントとして残した retrospective の転記 (出典: https://github.com/saitoco/wholework/issues/1213#issuecomment-5235850418)。

### スコープ転換の判断根拠

reopen コメントの項目 2 (phase 横断での取りこぼし防止) を、調査によって方式レベルまで確定させた。決め手は次の 3 事実である。

| 事実 | 確認コマンド |
|---|---|
| `modules/test-runner.md` を読む skill は code / review / verify のみ | `grep -ln "modules/test-runner.md" skills/*/SKILL.md` |
| `modules/execution-context.md` を参照する skill は code / review のみ | `grep -ln "execution-context.md" skills/*/SKILL.md` |
| `skills/spec/SKILL.md` にフルスイート実行の指示は存在しない | 同ファイルの `bats` 言及はすべて「Spec に何を書くか」の規約 |

当初は `modules/test-runner.md` への集約を有力案と考えていたが、`/spec` は test-runner.md を読まないため届かないことが判明した。さらに `/spec` はフルスイート実行を指示されてすらおらず、エージェントの自発的判断で実行していた。これにより「制約文をどこに配置するか」という iteration 0/1 のアプローチは、指示を持たない phase には原理的に届かないことが確定した。残る `issue` / `merge` / `doc` / `triage` / `audit` も同じ穴を持つ。

結論として、`claude -p` を起動する唯一の層である `scripts/run-*.sh` 側での一括注入へ方針転換した。wrapper は `--non-interactive` を渡す当事者であり、再呼び出し保証がないことを起動時点で知っている。

### ユーザー確認で決定した 2 点

| 論点 | 決定 | 却下した選択肢 |
|---|---|---|
| スコープに含める phase | 全 phase を wrapper 側で一括担保 | spec のみ追加 (4 世代目の繰り返しになる) / 検出側 #1323 を優先 (予防を諦める) |
| `run-spec.sh` の auto-retry 欠如 | 別 Issue に切り出す → #1329 | 今回のスコープに含める / 揃えない理由を明記するだけ |

### AC の設計方針: 手段を固定しない

新規 AC はいずれも結果 (どの phase に制約が届くか) で記述し、実現方式を固定していない。これは #1293 の先例に倣ったもので、同 Issue ではタイトルが特定方式を示唆していたが AC が outcome-based だったため、`/issue` の実測による反証を受けて `/spec` が別方式へ切り替えられた。本 Issue も 4 世代目にして初めて方式を変えるため、AC が手段を縛らないことの価値が高い。

### 既存 AC の扱い

iteration 0/1 の Pre-merge AC 9 件はすべてチェック済みだが削除せず維持した。fix cycle の検証履歴であり、`(iteration 1)` / `(iteration 2)` のプレフィックスで世代を区別する既存の方式を踏襲している。Post-merge の未達 AC 1 件 (review phase の observation) もそのまま残した。

### タイトル更新と系譜

タイトルの `code/review:` プレフィックスがスコープと不整合になったため `auto:` へ変更した。component は wrapper 群 (`scripts/run-*.sh`) の管轄である `auto` とし、系譜が 4 世代に伸びたため `(#994 の再発)` は本文の系譜表に委ねて外した。reopen コメントが記載していた系譜に #1175 が含まれており、当初の把握 (3 世代) より 1 世代長かった。

## spec retrospective (iteration 2)

### Minor observations

- Issue 本文の事実主張 3 件 (`test-runner.md` の読み手、`execution-context.md` の読み手、`skills/spec/SKILL.md` にフルスイート実行指示がないこと) を Step 6 の conflict detection で全件再検証したが、いずれも実装と一致していた。`/issue` フェーズが調査コマンドを本文に明記していたため検証コストがほぼゼロで済んだ。事実主張に確認コマンドを併記する書き方は再現性が高い。
- 注入点として `scripts/guard-prefix.sh` が既に存在していたことが、この iteration の設計を大きく単純化した。#557 が「5 wrapper に散在していた GUARD_PREFIX を 1 ファイルへ抽出」した結果が、3 世代あとの本 Issue で phase 横断制約の集約点として機能している。抽出のリファクタリングが後から別目的で効いた例。
- `modules/execution-context.md` の Callers リストは「どの skill がこの module を読むか」を追跡する目的で維持されているが、今回追加する `scripts/guard-prefix.sh` は module を読む側ではなく「module が定義した規則を配る側」である。同じリストに載せると意味が二重になるため、行の書き方で役割の違いを明示する必要がある (Implementation Step 3 に反映済み)。

### Judgment rationale

- **Spec 冒頭の `## Verification` を全 iteration 統合リストへ更新した判断**: iteration 1 の review retrospective が「fix cycle で Spec の Implementation Steps / AC が旧 iteration のまま残り、新実装を検証する AC が 1 件も存在しない状態で PR が作られた」と記録していた。同じ構造が iteration 2 でも成立しうるため、Spec 側の Verification を Issue 本文と 1:1 に揃えることで予防した。一方 `## Changed Files` / `## Implementation Steps` は iteration ごとの節に分ける既存方式を維持し、冒頭に「現在の作業対象は iteration 2」というポインタを置く形で折衷した。両方を統合リスト化しなかったのは、履歴としての iteration 0/1 の実装記録を失いたくないため。
- **Triage AC audit の 2 案から「記録先を実装成果物側に限定する」を選んだ理由**: もう一方の案 (実装箇所の特定を問う形) は、実装の実体は git diff から grader が読めるものの「方式を選んだ理由」という記録要件が落ちる。本 Issue は 4 世代目にして初めて方式を変えるケースであり、なぜ変えたかの記録は将来の 5 世代目を防ぐ資産になる。判定対象を `modules/execution-context.md` に限定すれば、要件を落とさずに常時 PASS リスクだけを外せる。
- **AC の追加を 1 件に留めた理由**: 監査コメントは `section_contains` の併記を推奨していたが、AC を増やすほど `/merge` の pre-merge AC gate で未チェック項目が残るリスクが上がる (iteration 1 で実際に 4 件未チェックによる merge ブロックが起きている)。rubric の裏取りとして最小限の 1 件だけを追加した。

### Uncertainty resolution

- **`section_contains` の見出しレベル依存**: 新設する `### Wrapper-Level Constraint Injection` が `##` ではなく `###` であることが判定に影響するかを `modules/verify-executor.md` で確認した。heading 引数は先頭の `#` を除去した上での部分一致であり、レベルは判定に影響しない。ただし節の範囲は「同レベル以上の次の見出しまで」なので、`###` 節の直後に別の `###` が来る配置なら意図した範囲になる — Implementation Step 2 の配置で成立する。
- **`GUARD_PREFIX` への追記が bash 文字列として安全か**: 既存の `GUARD_PREFIX` は二重引用符文字列で、現状バッククォートも `$` も含んでいない。追記テキストにコード片をバッククォートで囲む書き方をすると即座にコマンド置換になるため、素のテキスト表記に統一する方針を Implementation Step 1 と Changed Files の双方に明記した。実装時の検証手順 (`bash -n` + `source` して `grep`) も Uncertainty 節に残した。
- **wrapper を持たない skill をどう扱うか**: `/verify` / `/triage` / `/audit` / `/doc` / `/auto` は `run-*.sh` を持たず常に main context で走る。main context には再呼び出し保証があるため MUST rule の適用対象外であり、wrapper 層の注入で「全 phase をカバーする」という AC の主張と矛盾しないことを `modules/execution-context.md` の Per-Skill Context Table で確認した。この整理を実装成果物にも書き残す (Implementation Step 2)。

## Code Retrospective (iteration 2)

### Deviations from Design

N/A — Implementation Steps 1〜6 を Spec の記述通りに実施した。

### Design Gaps/Ambiguities

- **verify-executor の safe mode が AC14 (`command` 型) を UNCERTAIN にする**: 本 iteration の実装セッション自体が `--non-interactive` (fork context) で走っており、`modules/execution-context.md` の Fork Context 表に従うと `command` verify command は safe mode で常にスキップ (UNCERTAIN) される。Step 10 の自動検証だけでは AC14 (`bats tests/run-spec.bats ...` の 5 本) を確認できないため、`/code` セッション自身が `bats` を直接実行して 192 件 PASS を手動確認し、その結果に基づいて Issue の checkbox を手動で `[x]` 化した。これは iteration 0/1 の Code Retrospective が指摘した「pr route の Step 10 が `github_check` を UNCERTAIN にする」問題と同型で、対象が `command` 型 AC 全般に広がる。SKILL.md にはこの safe-mode 由来の AC 未検証パターンへの一般的な対処 (「該当 AC は実装者自身が直接実行して確認する」) が明文化されていないため、次回同様のケースがあれば SKILL.md 側への追記を検討する価値がある。
- **本セッション自体が本 Issue の主題を実地で再現した**: `bats tests/run-code.bats tests/run-issue.bats tests/run-merge.bats tests/run-spec.bats tests/run-review.bats` (計 192 件) の実行中、他の並行セッションによるシステム全体の CPU 競合により、Bash tool の 600000ms timeout ceiling を複数回超過し、コマンドが自動的にバックグラウンドへ移行した。これは `modules/execution-context.md` の corollary (「明示 `timeout` だけでは foreground 実行を保証しない」) がまさに説明する状況であり、今回追加した wrapper 層のガードが対象とする失敗モードそのものである。実際には本セッションはこの `/code` 実行全体を 1 つの継続した対話として扱われており、バックグラウンドタスクの完了通知がターンをまたいで正常に届いたため silent no-op には陥らなかった。ただし、これは「なぜ問題が起きなかったか」の観察であり、`--jobs` 分割実行や UNCERTAIN リトライなどの追加防御を要する場面が今後もありうることを示す実例として記録する。

### Rework

N/A — 実装は Spec の Implementation Steps をそのまま適用し、手戻りは発生しなかった。
