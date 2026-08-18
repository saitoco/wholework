# Issue #1240: auto: run-auto-sub.sh の sub-issue route 判定に Spec 由来の operate route 降格を追加

## Overview

`/auto` の XL route / `--batch` route が sub-issue を実行する `scripts/run-auto-sub.sh` に、`skills/auto/SKILL.md` Step 3a 相当の operate route (diff-less) 降格判定を追加する。post-spec の Size 再取得ブロック直後に Spec の `## Changed Files` を機械的に検査し、diff-less と判定された場合は Size が M/L であっても `code-patch` dispatch + `code-patch` completion check (operate marker 対応済み) へ切り替える。これにより単一 Issue 経路 (Step 3a) と sub-issue 経路 (`run-auto-sub.sh`) の route 判定ロジックの非対称性を解消する。

## Reproduction Steps

1. XL parent Issue (または `--batch`) 配下に Size M/L の sub-issue があり、その `/spec` が diff-less な Spec (`## Changed Files` が空、`## Implementation Steps` が外部ツール操作のみ) を生成する (実例: #1158 の sub-issue #1166、2026-08-07)。
2. `run-auto-sub.sh` は post-spec Size 再取得後、Size (M/L) のみで route を決定し `run_phase_with_recovery "code-pr" "$SUB_NUMBER" run-code.sh --pr` を dispatch する (diff-less 判定が存在しない)。
3. `/code` 自身は Spec 由来の operate 判定 (Step 0) で `--pr` フラグを上書きし、正しく operate 分岐 (外部操作を実行、commit なし、`## Execution Log` コメント投稿) を完走する。
4. `run-auto-sub.sh` の M/L 分岐は dispatch 直後に `gh pr list` で PR 番号取得を試みるが、operate route は PR を作らないため `PR_NUMBER` が空になり `exit 1` する。
5. Tier 2 (`apply-fallback.sh`) / Tier 3 (`spawn-recovery-subagent.sh`) recovery も、`reconcile-phase-state.sh code-pr --check-completion` が `matches_expected: false` を返す (`_completion_code_pr()` は「PR が存在するか」しか見ないため) ことを理由に空振りする。

## Root Cause

`run-auto-sub.sh` の Size ベース route 分岐 (`case "$EFFECTIVE_SIZE"`) には diff-less 判定が存在せず (`grep -n "operate" scripts/run-auto-sub.sh` は 0 件)、Size M/L の sub-issue は無条件で `run_phase_with_recovery "code-pr" ...` を dispatch する。

`/code` 自身は Spec 由来の operate 判定を Step 0 で独立に行い、渡された `--pr` フラグを上書きして正しく operate 分岐を実行するため、実装側 (`/code`) の diff 実行そのものは問題なく完走する。しかし `run-auto-sub.sh` が完了チェックに渡すフェーズ名は依然 `"code-pr"` のままであり、`reconcile-phase-state.sh` の `_completion_code_pr()` は「`worktree-code+issue-N` ブランチに open な PR があるか」だけを判定基準にする (`modules/phase-state.md` の phase 別 completion 列)。operate route は PR を作らないため、機能的に成功した実行が `matches_expected: false` と誤判定される。

`_completion_code_patch()` は既に operate marker (Execution Log/Execution Plan コメント) を代替 success signature として認識する実装を持つ (#998; `modules/phase-state.md` § "Operate Route Completion Signature") が、`run-auto-sub.sh` が `code-patch` フェーズ名を渡すのは元々 Size XS/S の場合のみであり、Size M/L の operate route sub-issue はこの既存実装の恩恵を受けられない。**修正の本質は dispatch 先のフェーズ名 (`code-patch` vs `code-pr`) の選択であり、`/code` 自身の operate 判定ロジックには手を加えない。**

## Changed Files

- `scripts/run-auto-sub.sh`: `_spec_is_diffless()` ヘルパー関数の追加、post-spec Size 再取得直後への diff-less 判定ステップの追加、`EFFECTIVE_SIZE="OPERATE"` 分岐の追加、`case` 文の `XS|S)` → `XS|S|OPERATE)` への変更。bash 3.2+ 互換 (macOS system bash — `awk`/`sed -nE` のみ使用、`mapfile` 等は不使用)
- `skills/auto/SKILL.md`: XL route (Step 4) セクションに、`run-auto-sub.sh` が sub-issue の Spec から operate 判定を独立に再導出することを説明する段落を追加
- `tests/run-auto-sub.bats`: diff-less な Spec で `code-patch` が選択されることを検証する新規テストケースと、通常の (diff-less でない) Spec では従来通り `code-pr` が選択されることを確認する negative-control テストケースを追加
- [Steering Docs sync candidate] `modules/size-workflow-table.md`: § "Diff-less Axis (operate route)" の Determination criteria が現在「evaluated by `/spec` ... and re-checked by `/code`」とのみ記述しており、`run-auto-sub.sh` (criterion 1 のみのメカニカルな代替判定) に触れていない。SSoT の正確性維持のため追記するか `/code` が判断する (§ "Callers that must apply this override" には既に `scripts/run-auto-sub.sh` が列挙されているが、これは ALWAYS_PR override の文脈であり diff-less 判定の evaluator 列挙とは別)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `_observe_code_milestone()` 関数 (585行目付近で終了) と `run_phase_with_recovery()` 関数の間に `_spec_is_diffless()` ヘルパーを追加する。仕様:
   - 引数はsub-issue番号。`docs/spec/issue-"${number}"-*.md` をグロブし、最初にマッチした実在ファイルを Spec とする (`scripts/check-verify-dirty.sh` の `own_spec_file` 探索と同じ `for f in ...; do [[ -f "$f" ]] && ...; done` 形式)。Spec が見つからなければ diff-less ではない (`return 1`)。
   - **`## Changed Files` という見出し行自体が存在しない Spec は diff-less と判定してはならない** — `grep -q '^## Changed Files' "$spec_file"` で見出しの存在を先に確認し、存在しなければ `return 1`。見出しが「存在するが空 / なし」の場合とは区別すること (根拠: 下記 Notes 参照。既存の `tests/run-auto-sub.bats` の `tier3 recovery during review phase ...` テストが、`## Changed Files` 見出しを持たない最小スタブ Spec (`echo "# Issue #42: test spec" > docs/spec/issue-42-test.md`) を使っており、見出し不在を「空」と同一視する実装だとこのテストを regression させることをプロトタイプ検証で確認済み)。
   - 見出しが存在する場合、`awk '/^## Changed Files/{flag=1; next} /^## /{flag=0} flag' "$spec_file" | sed -nE 's/^[[:space:]]*-[[:space:]]+(\[[^]]*\][[:space:]]+)?`([^`]+)`.*/\2/p'` でセクション内のバックティック付きパスを抽出する (`scripts/check-verify-dirty.sh` の own-issue-scope manifest 抽出と同一パターン — インデント・`[label]` prefix に対応)。
   - 抽出結果が空文字列であれば diff-less (`return 0`)、1件以上あれば diff-less ではない (`return 1`)。
   (→ AC1)

2. 既存の "Always re-fetch SIZE after spec phase" ブロック (`if [[ -z "$SIZE" ]]; then ... fi` で終わる、892行目付近) の直後、`if [[ "$SIZE" == "XL" ]]; then` の前に、`ROUTE_OPERATE=false` を初期化し `_spec_is_diffless "$SUB_NUMBER"` が真なら `ROUTE_OPERATE=true` に設定するブロックを追加する。真の場合、`echo "${LOG_PREFIX} Post-spec operate detection: Spec has no repository file changes, route re-determined as operate."` (`skills/auto/SKILL.md` Step 3a と同一文言) を出力し `emit_event "operate_route_detected"` を呼ぶ (`always_pr_promotion`/`size_refresh` イベントと同様、追加の key=value なしで可 — `EMIT_ISSUE_NUMBER` は471行目付近で既に `$SUB_NUMBER` にセット済みのため `issue=` の重複指定は不要)。(after 1) (→ AC1)

3. `EFFECTIVE_SIZE="$SIZE"` の直後にある既存の `ALWAYS_PR` 昇格判定 (`if [[ "$ALWAYS_PR" == "true" ]] && ...`) を `elif` に変更し、その前に `if [[ "$ROUTE_OPERATE" == "true" ]]; then EFFECTIVE_SIZE="OPERATE"` を追加する (operate 判定が ALWAYS_PR 昇格より優先— `modules/size-workflow-table.md` の priority order に合わせる)。続けて `case "$EFFECTIVE_SIZE" in` の1つ目のアーム `XS|S)` を `XS|S|OPERATE)` に変更する (このアームの本文 — `run_phase_with_recovery "code-patch" ... --patch` の呼び出しと、その後の tier3 skip チェック — はそのまま再利用され、PR 番号取得や review/merge の呼び出しを含まない)。(after 2) (→ AC2, AC3)

4. `skills/auto/SKILL.md` の XL route セクション (Step 4 内、`run-auto-sub.sh` が `ALWAYS_PR` を独立にロードし patch→pr 昇格ロジックを適用することを説明する既存段落の直後) に、`run-auto-sub.sh` が各 sub-issue 自身の Spec から diff-less/operate 判定を独立に再導出すること (Step 3a の "Operate route demotion" に相当)、`## Changed Files` が空なら Size や `always-pr` に関わらず `code-patch` を dispatch すること、`code-patch` フェーズ名を使うことで `reconcile-phase-state.sh` の `code-patch` completion signature (operate marker 対応済み、`modules/phase-state.md` § "Operate Route Completion Signature") が使われる (PR ベースの `code-pr` signature ではなくなる) ことを説明する段落を追加する。(parallel with 1-3) (→ AC4)

5. `tests/run-auto-sub.bats` に2つの新規テストケースを追加する ("Size M + auto-stop-at: review" テストの直前が適切な挿入位置):
   - **Positive**: `## Changed Files` セクションが `なし (operate route ...)` のようにバックティック付きパスを含まない Spec フィクスチャ (`docs/spec/issue-42-*.md`、デフォルト mock の `SUB_NUMBER=42, Size M` を利用) を用意し、`run bash "$SCRIPT" 42` の結果が `status 0`、出力に `"Post-spec operate detection"` を含む、`$RUN_CODE_LOG` に `"42 --patch"` が記録される、`$RUN_REVIEW_LOG`/`$RUN_MERGE_LOG` が作成されないことを確認する。
   - **Negative control**: `## Changed Files` セクションに実際のバックティック付きパス (例: `` - `scripts/example.sh`: ... ``) を含む Spec フィクスチャを用意し、operate 判定が発火しないこと (`$RUN_CODE_LOG` に `"42 --pr"` が記録される、`$RUN_REVIEW_LOG`/`$RUN_MERGE_LOG` が作成される) を確認する — 抽出正規表現が過剰マッチして通常の Size M/L sub-issue を壊さないことの回帰防止。
   - 追加後、`bats tests/run-auto-sub.bats` を実行し全テスト (既存 93 + 新規 2 = 95件) が PASS することを確認する。特に見出しなしスタブ Spec を使う既存の `tier3 recovery during review phase ...` テストが regression していないことを確認する (Step 1 の見出し存在チェックが正しく効いていれば PASS するはず)。
   (after 3) (→ AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: grep -n "operate" scripts/run-auto-sub.sh --> `scripts/run-auto-sub.sh` の post-spec Size 再取得ブロックの直後に、Spec (`docs/spec/issue-<N>-*.md`) の diff-less 判定を行うステップが追加されている
- <!-- verify: rubric "run-auto-sub.sh の route 分岐 (case \"$EFFECTIVE_SIZE\") より前に operate 判定が評価され、成立時は Size や ALWAYS_PR に関わらず code-patch 経路が選択される" --> operate 判定が成立した場合、Size が M/L であっても `code-pr` ではなく `code-patch` dispatch へ切り替わる
- <!-- verify: rubric "operate 判定成立時の run_phase_with_recovery 呼び出しが code-patch フェーズ名を渡している" --> operate route の完了判定に `reconcile-phase-state.sh code-patch` が使われる (operate 実行ログマーカーによる completion signature を honor する)
- <!-- verify: rubric "skills/auto/SKILL.md の XL route (Step 4) の記述が、run-auto-sub.sh 経由の sub-issue でも operate route 判定が honor されることを説明している" --> `skills/auto/SKILL.md` の XL route (Step 4) の記述が、`run-auto-sub.sh` 経由の sub-issue でも operate route 判定が honor されることを反映している
- <!-- verify: grep "operate" "tests/run-auto-sub.bats" --> 既存の `tests/run-auto-sub.bats` に、diff-less な Spec を持つ sub-issue で `code-patch` が選択されることを検証する新規テストケースが追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` の全テストが pass する

### Post-merge

- <!-- verify-type: observation event=auto-run session=next --> 次回 operate route の sub-issue を含む `/auto` XL または `--batch` 実行で、`run-auto-sub.sh` が exit 0 で完走することを確認する

## Notes

- **Verification > Pre-merge が light depth の目安件数 (5件) を超過 (6件)**: Triage AC audit (Consumed Comments 参照) の指摘で、bats テスト系 AC 1件が「常時 PASS (Pattern 2)」の欠陥を抱えていたため 2件に分割した結果。分割前は5件で目安内だったが、欠陥修正を優先し件数超過を許容する。
- **`_spec_is_diffless()` は `modules/size-workflow-table.md` の diff-less 判定基準2つのうち criterion 1 (`## Changed Files` が空) のみを機械的に検査する**: criterion 2 (`## Implementation Steps` が全て外部ツール操作) は `/code` Step 0 が行うような意味論的判定を要し、bash では再現できない。基準1のみで代替するため、理論上は「`## Changed Files` は正しく空だが `## Implementation Steps` にファイル編集が混在する」矛盾した Spec (`/spec` Step 10 の self-review で通常防止される) に対して `run-auto-sub.sh` が誤って diff-less と判定する可能性が残る。ただしこの場合も `/code` 自身の Step 0 判定は独立して動作するため、実際に実行される diff (コミットの有無) 自体は影響を受けない — 影響は dispatch 時に選ばれるフェーズ名 (completion check の種類) に限られる。
- **`scripts/check-verify-dirty.sh` と同一のセクション抽出・パス抽出パターンを再利用する** (Tool detection pattern consistency): `## Changed Files` セクションの単離 (`awk`) とバレット行からのパス抽出 (`sed -nE`、インデント・`[label]` prefix 両対応) は、同スクリプトの own-issue-scope manifest 実装と同一のロジックを踏襲する。異なる抽出ロジックを新規に書くと、書式差異 (インデント付きバレット、`[label]` prefix 付きバレットなど) の扱いが2箇所で乖離するリスクがある。
- プロトタイプ実装で `bats tests/run-auto-sub.bats` を実行し、Implementation Steps の設計 (見出し存在チェックを含む) で新規2テストを含む全95件が PASS することを確認済み。プロトタイプ自体はこの Spec 作成後に revert 済み (`/spec` の責務は設計のみ、実装は `/code` フェーズで行う)。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (non-interactive mode): `ALWAYS_PR=true` による operate 判定抑制の非採用を Background に明記した理由、および Triage AC audit で指摘された2件の Pattern 2 (常時 PASS) verify command 欠陥の修正内容 (SKILL.md 側 grep→rubric、bats 側 `ls tests/`→`command "bats tests/run-auto-sub.bats"`) を記録 / https://github.com/saitoco/wholework/issues/1240#issuecomment-5326721499
- saito / MEMBER / first-class / Triage AC audit: bats テスト AC (`command "bats tests/run-auto-sub.bats"`) が既存93ケース全PASSにより依然 Pattern 2 (常時 PASS) であると指摘し、`grep "operate" "tests/run-auto-sub.bats"` (新規テストケース検出) と既存の `command` AC (回帰保護) への2分割を提案。本フェーズで Issue body および本 Spec の Verification に反映済み / https://github.com/saitoco/wholework/issues/1240#issuecomment-5326773760
