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
