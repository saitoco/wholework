# Issue #1042: run-auto-sub.sh: batch mode で auto-stop-at 未対応を修正

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要約: 「Issue Retrospective」— `/issue` non-interactive 実行時の Auto-Resolve Log (AC スコープを List+Count 両モードに拡張、stop-at 到達時の粒度を明確化) と、`run-auto-sub.sh` grep による Background 事実確認 (pr route 主系列に stop-at check が無いことを確認)、Triage 結果 (Type=Bug, Size=M, Value=3) を記録。本 Spec の設計判断 (Changed Files を `run-auto-sub.sh` 内部修正に一本化する方針) と整合していることを確認済み / URL: https://github.com/saitoco/wholework/issues/1042#issuecomment-5053468973

### /code phase (cutoff: phase/ready assigned 2026-07-23T02:10:33Z)

No new comments since last phase.

## Overview

`/auto --batch` (Count mode `--batch N` / List mode `--batch N1 N2 ...`) 経由で呼ばれる `scripts/run-auto-sub.sh` の pr route (Size M/L) 主系列は、`code-pr` phase 完了後に `review` phase を、`review` phase 完了後に `merge` phase を、`.wholework.yml` の `auto-stop-at` 設定を一切確認せず無条件に実行する。このため `auto-stop-at: review` を設定していても、batch mode 経由の Issue は human review を経ずに auto-merge される (tofas repo での実インシデントとして報告済み)。

単独 `/auto N` の pr route sequence (`skills/auto/SKILL.md` Step 4) には phase 完了ごとの stop-at check が実装済みだが、`run-auto-sub.sh` にはこの仕組みが移植されていない。既存の唯一の `auto-stop-at` 読み取り箇所 (Tier 3 recovery の `action=skip` 検知後の継続判定、Issue #980 で追加) は、`XS|S)` ケースの局所的なリカバリ分岐に限定されており、`M)`/`L)` ケースの通常系列 (無条件 code→review→merge) には一切適用されていない。

本 Issue では `run-auto-sub.sh` 内部に `auto-stop-at` 設定を読み込み、`M)`/`L)` ケースの通常系列に phase 完了ごとの stop-at check を追加する。`run-auto-sub.sh` は List mode/Count mode の共通呼び出し先であるため (`skills/auto/SKILL.md` L1078, L1119)、この 1 ファイルの修正で両モードを同時にカバーする。

## Reproduction Steps

1. `.wholework.yml` に `auto-stop-at: review` を設定したリポジトリで、Size M または L の Issue (もしくは `always-pr: true` 設定下の XS/S Issue) を対象に `/auto --batch N1 N2 ...` (List mode) または `/auto --batch N` (Count mode、`always-pr: true` により pr route に昇格するケース) を実行する。
2. `run-auto-sub.sh` 内部で `EFFECTIVE_SIZE` が `M` または `L` と判定され、`case "$EFFECTIVE_SIZE" in M) ... L) ...` ブランチに入る。
3. `run_phase_with_recovery "code-pr" ...` 実行後、`PR_NUMBER` を取得し、`run_phase_with_recovery "review" ...` (light/full) が無条件に呼ばれる。
4. 続けて `run_phase_with_recovery "merge" ...` が `auto-stop-at` の値を一切確認せず無条件に呼ばれ、PR が squash merge される。
5. 結果: `auto-stop-at: review` を設定していたにもかかわらず、human review 段階を経ずに PR が auto-merge される (実際に tofas repo で #318 #320 の PR #322/#323 が観測された事例)。

## Root Cause

`scripts/run-auto-sub.sh` の Size ベース case 文 (`M)`/`L)` ブランチ) は、`run_phase_with_recovery "code-pr" ...` → `run_phase_with_recovery "review" ...` → `run_phase_with_recovery "merge" ...` を、`.wholework.yml` の `auto-stop-at` 設定を一切参照せずに直列実行する設計になっている。

対照的に単独 `/auto N` の pr route sequence (`skills/auto/SKILL.md` Step 4, L432-455) は phase 完了ごとに `EFFECTIVE_STOP_AT` (`--stop-at` フラグ > `AUTO_STOP_AT` config > デフォルト `"verify"` の優先順位、Step 2 で算出) を確認し、該当 phase で停止する仕組みを持つ。しかし `skills/auto/SKILL.md` の `--batch` 検出ロジック (Step 1, L94-101) は batch mode 判定時に **Step 2 (`EFFECTIVE_STOP_AT` を算出する箇所) を含む Steps 2–6 を丸ごとスキップして** Batch Mode セクションへ分岐する。このため、そもそも batch mode の LLM 主導フロー (Count mode / List mode) 側には `EFFECTIVE_STOP_AT` という変数自体が存在せず、単純に「呼び出し元から `run-auto-sub.sh` へ `EFFECTIVE_STOP_AT` を渡す」形の修正は成立しない。

`run-auto-sub.sh` 内で唯一 `auto-stop-at` を読む箇所は、Tier 3 recovery が `action=skip` を返した際の継続判定 (`XS|S)` ケース内、Issue #980 で追加) のみであり、`get-config-value.sh auto-stop-at verify` を呼んで `code`/`spec` なら停止、`review` なら review のみ継続、それ以外 (`merge`/`verify`) なら review+merge 継続、という 3 分岐を実装済みである。この 3 分岐ロジックは正しく動作しているが、`M)`/`L)` ケースの通常系列 (Tier 3 recovery を経由しない、大多数のケース) には一切適用されていない — これが本 Issue が対象とする欠落である。

なお `EFFECTIVE_SIZE` への `always-pr: true` 昇格判定 (L857-863) は `run-auto-sub.sh` 内部で行われるため、Count mode の SKILL.md レベルでの Size フィルタ (M/L/XL を除外) を経由した XS/S Issue であっても、`always-pr: true` 設定下では internal に `M` へ昇格し `M)` ケースに到達しうる。したがって `run-auto-sub.sh` 内部のみを修正する本アプローチは、List mode と Count mode の双方 (および Count mode 内での pr route 昇格ケース) を一箇所で正しくカバーする。

## Changed Files

- `scripts/run-auto-sub.sh`: `ALWAYS_PR` 読み込み直後に `AUTO_STOP_AT` config 値を一度だけ読み込み (`get-config-value.sh auto-stop-at verify`、Tier 3 skip 分岐で既に使われているものと同一パターン)、`M)`/`L)` ケースの通常系列に stop-at check を追加する。Tier 3 skip 分岐の局所的な `_STOP_AT` 読み込みはこのホイストされた変数の再利用に置き換える (重複読み込みの解消、挙動変更なし)。bash 3.2+ compatible (既存の `if`/`case`/`[[ ]]` 構文のみ、新規 bash4+ 構文なし)。
- `tests/run-auto-sub.bats`: Size M + `auto-stop-at: review` (review は実行され merge は実行されないこと) および Size M + `auto-stop-at: code` (review・merge とも実行されないこと) を検証する新規テストを 2 件追加する。
- Steering Docs sync candidate 確認済み (`grep -rn "run-auto-sub.sh\|auto-stop-at\|AUTO_STOP_AT" docs/ tests/ scripts/` 実行): `docs/workflow.md:107`、`docs/guide/customization.md:155,161-171` (および `docs/ja/` 対訳ミラー) は `auto-stop-at` を「`/auto` パイプラインを指定 phase で停止する」という汎用的な記述に留めており、batch mode 除外の言及は元々存在しない。修正後にこの記述が完全に正確になるだけであり、テキスト変更は不要と判断した (更新不要)。`docs/spec/issue-783-*.md` / `issue-980-*.md` 等は disposable な過去 Spec のため sync candidate から除外した (`docs/tech.md` 「Spec-first (disposable)」方針)。`docs/migration-notes.md` は `run-auto-sub.sh` の呼び出しシグネチャ (`run-auto-sub.sh <sub-issue-number> [--base <branch>]`) 変更を伴わないため対象外。

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `ALWAYS_PR=$("$SCRIPT_DIR/get-config-value.sh" always-pr false 2>/dev/null || echo false)` の直後に `AUTO_STOP_AT=$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify 2>/dev/null || echo verify)` を追加する。`XS|S)` ケース内の Tier 3 skip 分岐 (`_STOP_AT=$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify 2>/dev/null || echo verify)` の行) を削除し、以降の `$_STOP_AT` 参照 3 箇所 (if 条件、elif 条件、echo 内挿入 2 箇所) を `$AUTO_STOP_AT` に置き換える (挙動変更なし、読み込み一本化のみ) (→ 受入条件1)。
2. (after 1) `M)` ケース内、`echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"` の直後・`echo "${LOG_PREFIX} --- review phase (light): PR #${PR_NUMBER} ---"` の直前に、以下の stop-at gate を追加する (→ 受入条件1):
   ```bash
   if [[ "$AUTO_STOP_AT" == "spec" || "$AUTO_STOP_AT" == "code" ]]; then
     echo "${LOG_PREFIX} Stopped at phase: code (auto-stop-at=${AUTO_STOP_AT})"
   else
     echo "${LOG_PREFIX} --- review phase (light): PR #${PR_NUMBER} ---"
     _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "review" "$PR_NUMBER" "$SCRIPT_DIR/run-review.sh" --light

     if [[ "$AUTO_STOP_AT" == "review" ]]; then
       echo "${LOG_PREFIX} Stopped at phase: review (auto-stop-at=review)"
     else
       echo "${LOG_PREFIX} --- merge phase: PR #${PR_NUMBER} ---"
       _EXTRA_SELF_ISSUE="$SUB_NUMBER" run_phase_with_recovery "merge" "$PR_NUMBER" "$SCRIPT_DIR/run-merge.sh"
     fi
   fi
   ```
   既存の無条件呼び出し (review 呼び出し1行、merge 呼び出し1行) を上記ブロックで置き換える。メッセージ文言は単独 `/auto N` (`skills/auto/SKILL.md` L439, L442) と同一の "Stopped at phase: X (auto-stop-at=Y)" 形式に揃える。
3. (after 1, parallel with 2) `L)` ケース内の同一箇所 (`echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"` の直後、`--- review phase (full)` の直前) に、ステップ2と同型の stop-at gate を追加する (`--light`/`review` ではなく `--full`/`review` である点のみ異なる) (→ 受入条件1)。
4. (after 2, 3) `tests/run-auto-sub.bats` に新規テストを2件追加する (→ 受入条件2):
   - `"Size M + auto-stop-at: review: run-review.sh is called, run-merge.sh is not called"` — `.wholework.yml` に `auto-stop-at: review` を追記し (デフォルトの Size M mock のまま) `bash "$SCRIPT" 42` を実行、`RUN_CODE_LOG` に `42 --pr` が含まれること、`RUN_REVIEW_LOG` が存在すること、`RUN_MERGE_LOG` が存在しないこと、`$output` に `"Stopped at phase: review"` が含まれることを確認する。
   - `"Size M + auto-stop-at: code: run-review.sh and run-merge.sh are not called"` — `.wholework.yml` に `auto-stop-at: code` を追記し同様に実行、`RUN_REVIEW_LOG`/`RUN_MERGE_LOG` がいずれも存在しないこと、`$output` に `"Stopped at phase: code"` が含まれることを確認する。
   - 既存テスト "Size M: run-code.sh --pr, run-review.sh --light, run-merge.sh called" (L256) および "Size L: ..." (L265) が無修正で PASS することを回帰確認する (デフォルト `auto-stop-at` 未設定 = `"verify"` のケース)。

## Verification

### Pre-merge
- <!-- verify: rubric "run-auto-sub.sh または batch mode (List mode と Count mode の両方) の呼び出し側で .wholework.yml の auto-stop-at 値を読み、指定 phase 完了後に該当 Issue の後続フェーズ呼び出しを止めるロジックが実装されている。バッチ内の他 Issue の処理は継続すること" --> `auto-stop-at` が batch mode (List mode / Count mode 双方) 経由でも honor される実装
- <!-- verify: rubric "auto-stop-at: review 設定下で /auto --batch を実行した際、review phase 完了後に停止し merge phase を呼ばないことを bats などで確認できるテストが追加されている" --> テスト追加 (bats 想定)

### Post-merge
- tofas repo (または他の `auto-stop-at` 設定 repo) で `/auto --batch` を実行し、指定 phase で停止することを確認 <!-- verify-type: manual -->

## Notes

- SPEC_DEPTH=light (Size M → pr route 自動判定、非対話モード)。blocked-by なし (HAS_OPEN_BLOCKING=false)。
- **スコープ決定 (auto-resolve)**: `auto-stop-at: spec` は `auto-stop-at: code` と同一の「review 前で停止」扱いとした。単独 `/auto N` の SKILL.md パスは spec と code を別個の停止点として区別するが、`run-auto-sub.sh` の既存 Tier 3 skip 分岐 (Issue #980) は既に spec/code を同一視する 3 分岐を採用しており、本修正はその既存の慣例に合わせた。spec phase 完了直後・code phase 開始前に完全に停止する gate (spec phase は case 文より前で無条件実行されるため、別途の構造変更が必要) は、報告された実インシデントの再現条件に含まれないため out of scope とした。
- **既存 Spec からの先例**: `docs/spec/issue-980-run-auto-sub-tier3-skip.md` の Notes は「`run-auto-sub.sh` 全体への `auto-stop-at` retrofit は本 Issue (#980) のスコープ外と判断し、必要であれば別途の改善候補として起票する」と明記していた。本 Issue (#1042) はその明示的なフォローアップである。
- **共通ヘルパー化の見送り**: 同 Spec の review retrospective (Recurring issues) は「`auto-stop-at` を読み取る箇所が複数に分散しており、値を追加/変更するたびに全呼び出し箇所を手動で網羅する必要がある構造」を指摘し、継続可否を bool に正規化する共通ヘルパー関数化を提案していた。本 Issue でも stop-at 判定箇所が 3 箇所 (Tier3 skip 分岐、`M)`、`L)`) に増えるが、既存コードとの差分を最小化する方針を優先し、共通関数の新規導入は見送った (`M)`/`L)` の判定ロジック自体は同一パターンの複製であり、既存の Tier3 skip 分岐のスタイルとも一致する)。4 箇所目の出現時は共通ヘルパー化を再検討する価値がある。
- Review phase の depth (`--light`/`--full`) は M/L 既存の使い分けをそのまま維持し、stop-at gate の追加によって変更しない。

## Smoke Test

該当なし (Issue body に外部/MCP ツール呼び出しの verify command は含まれない)。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1–4 の通りに実装した (AUTO_STOP_AT のホイスト、M)/L) への stop-at gate 追加、bats テスト2件追加)。

### Design Gaps/Ambiguities
- N/A — Spec Notes の auto-resolve 決定 (spec/code 同一視、共通ヘルパー化見送り) が実装時の判断をすべてカバーしており、新たな曖昧点は発生しなかった。

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns
- N/A — Implementation Steps 1–4 と PR diff の間に構造的な乖離は見られなかった。`AUTO_STOP_AT` のホイスト位置、M)/L) の stop-at gate の分岐構造、echo メッセージ文言 (単独 `/auto N` との整合) はいずれも Spec 記載通りに実装されていた。

### Recurring issues
- rubric 検証で PASS と判定した後の追加調査で、`auto-stop-at: merge` がバッチモードの `/verify` 呼び出し抑制には反映されないという別種のギャップを発見した (PR #1043 review コメントに記録)。ただしこれは本 Issue が対象とする「review 停止インシデント」とは異なる箇所 (`skills/auto/SKILL.md` の Verify orchestration ステップ) に起因し、Tier3 skip 分岐 (#980) にも同型の限界が既に存在していたため、本 PR による新規回帰ではなく既存の設計限界と判断した。
- Spec Notes が指摘した「`auto-stop-at` を読み取る箇所が複数箇所に分散している」構造的懸念 (共通ヘルパー化見送りの判断根拠) は、今回の追加調査でさらに裏付けられた形になる — stop-at 判定箇所は `run-auto-sub.sh` 内の3箇所に加え、`skills/auto/SKILL.md` の単独 `/auto N` 経路とバッチモード Verify orchestration ステップにも分散しており、後者は今回未対応のまま残っている。共通ヘルパー化の再検討タイミングで、この分散範囲全体 (SKILL.md 側も含む) を対象に含めることを推奨する。

### Acceptance criteria verification difficulty
- N/A — 2件の rubric 条件はいずれも UNCERTAIN なく明確に PASS 判定できた。Issue Notes に auto-resolve 済みのスコープ決定 (spec/code 同一視、粒度定義) が明記されていたため、rubric grader の判断材料が十分だった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST issue なし、CI 全 SUCCESS のため `COMMENT` イベントでレビューを投稿 (event=REQUEST_CHANGES には該当せず)。
- CONSIDER 2件 (サブプロセス呼び出しコスト、`auto-stop-at: merge` のバッチモード非対応) はいずれも本 Issue のスコープ外と判断し、修正は行わずフォローアップ候補として記録するに留めた。

### Deferred Items
- Post-merge AC (tofas repo での `/auto --batch` 実行確認) は未消化のまま — `/verify` フェーズで manual 検証として扱う (Code Retrospective からの引き継ぎ、変更なし)。
- `auto-stop-at: merge` がバッチモードの Verify orchestration ステップ (`skills/auto/SKILL.md`) に反映されない件は、別 Issue としての起票を推奨 (本 PR のスコープ外)。

### Notes for Next Phase
- `/merge` 実行時に追加の確認事項なし。CI 全 SUCCESS、AC 2件 PASS 済み。
- Post-merge AC (manual) は `/verify` フェーズで tofas repo 等での実行確認が必要。
