# Issue #902: verify: /verify セッション計装追加 (phase_start/phase_complete + AskUserQuestion回数) — #877 再測定の代理指標限界を解消

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (1周目) — 曖昧ポイント 3 件の自動解決ログ、AC1 への `file_contains` 補助追加、Post-merge AC の verify-type を opportunistic に修正、#898/#899 重複申し送り (現状維持) / https://github.com/saitoco/wholework/issues/902#issuecomment-4883879006
- saito / MEMBER / first-class / `/issue --non-interactive` (Fix Cycle 再オープン) の Issue Retrospective — Pre-merge AC1〜3 のチェック状態維持、新規 AC の振る舞いベース記述方針、Post-merge AC 流用方針の自動解決ログ / https://github.com/saitoco/wholework/issues/902#issuecomment-4885232080

## Overview

`/verify` skill の実行に `phase_start`/`phase_complete` (phase=verify) イベント発火と、interactive mode での `AskUserQuestion` 呼び出し回数を記録する `verify_user_confirm` イベント発火を追加する。目的は、#877 (`docs/reports/verify-sonnet-5-remeasurement.md`) で NO-GO 判定の根拠となった「`/verify` 実行時の実際の摩擦を直接計測する手段がない」という計装ギャップを解消し、将来の再測定 (Sonnet バージョン比較や設計変更の効果測定) が GitHub アーティファクトの代理指標ではなく実測値に基づいて行えるようにすることである。

**現状 (1周目・マージ済み)**: 上記の発火ロジック自体 (Step 1 の `phase_start`、Step 8b の `verify_user_confirm`、Step 11 の全5終端分岐の `phase_complete`) は実装・レビュー・pre-merge verify PASS 済みでマージ済み (Pre-merge AC1〜3、下記 Verification 参照)。しかし `/verify #915` 実行時の Post-merge opportunistic 検証で FAIL し、Fix Cycle として再オープンされた。

**Fix Cycle (今回のスコープ)**: 根本原因は、ガード条件 `if [[ -n "${AUTO_EVENTS_LOG:-}" ]]` の判定に必要な `AUTO_EVENTS_LOG`/`AUTO_SESSION_ID` が、`/auto` の in-session `Skill(wholework:verify, ...)` 呼び出し経由では一度も真にならないこと。コードベース調査の結果、これは単一の欠落ではなく2箇所の欠落が組み合わさったものと判明した (Issue 本文の Auto-Verified Fact Check よりも一歩踏み込んだ調査結果):

1. **読み取り側の欠落**: `skills/verify/SKILL.md` には `run-review.sh` 等が持つ pointer-file 復元ロジックが一切存在しない。
2. **書き込み側の欠落 (今回の調査で新たに判明)**: 読み取り側を直しても、`.tmp/auto-session-${PGID}` は「pointer file 書き込みと読み取りが同一 Bash tool call 内で行われる」ことに依存する仕組みであり (`/auto` の「Pointer file regeneration required before every run-*.sh call」節参照)、`/verify` は wrapper を持たず `Skill()` 呼び出しで別の Bash tool call として実行されるため PGID は原理的に一致しない。フォールバック先の `.tmp/auto-session-current` も、現状どの script/skill からも書き込まれていない (`scripts/run-code.sh` 内のコメントが "defensive dead code unless a future code path restores writes to that file" と明記 — Issue #791 iteration B で設計意図はあったが書き込み側は未実装のまま)。

したがって `/verify` 側のみの修正 (pointer file の読み取りロジック追加) では Fix Cycle は解決しない。`/auto` 側 (`skills/auto/SKILL.md` の AUTO_SESSION_ID generation ステップ) が `.tmp/auto-session-current` を実際に書き込むよう変更することが必須である。

## Changed Files

- `scripts/emit-event.sh`: 新規関数 `restore_auto_session_pointer()` を追加。`AUTO_EVENTS_LOG` が未設定の場合のみ `.tmp/auto-session-${PGID}` → `.tmp/auto-session-current` の順で `AUTO_SESSION_ID` を探索し、値が見つかった場合のみ `AUTO_SESSION_ID`/`AUTO_EVENTS_LOG` (デフォルト `.tmp/auto-events.jsonl`) を export する。見つからない場合は何もしない (standalone `/verify` 実行を計装対象外とする既存方針を維持)。bash 3.2+ 互換。
- `skills/verify/SKILL.md`: `AUTO_EVENTS_LOG` (または `AUTO_EVENTS_LOG`+`AUTO_SESSION_ID`) でガードされている全発火箇所 (Step 1 `phase_start`、Step 8b `verify_user_confirm`、Step 11 の `phase_complete` ×5分岐、および同箇所に同居する `verify_fail_marker_posted` ×2・`verify_retry_fire` ×1・`verify_reopen_cycle` ×1) で、ガード `if` の前に `source emit-event.sh` + `restore_auto_session_pointer` 呼び出しを追加する。
- `skills/auto/SKILL.md`: 「AUTO_SESSION_ID generation」ステップ (Step 1、全ルート判定より前、一度きりの生成箇所) で、既存の `.tmp/auto-session-${PGID}` 書き込みと同時に `.tmp/auto-session-current` (PGID非依存の安定ポインタ) にも同じ `SESSION_ID` を書き込む。
- `modules/event-emission.md`: 「Non-Wrapper Emitters」節に `restore_auto_session_pointer()` の役割を追記する。
- `skills/audit/SKILL.md`: 「Session Boundary Identification」節に `.tmp/auto-session-current` の役割を追記する。Issue #770 retrospective が指摘した「shared state 変更時に参照先ドキュメントが Changed Files から漏れる」再発パターン (同一の `.tmp/auto-session-*` 仕組みで既に2回発生済み) を踏まえた明示的追加。
- `tests/emit-event.bats`: `restore_auto_session_pointer()` の bats テストを追加 (詳細は Implementation Steps 5 参照)。
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `scripts/emit-event.sh` の説明行 (`emit_event()` のみ言及) を、新関数 `restore_auto_session_pointer()` も踏まえて更新が必要か確認する。既存の `_emit_comments_consumed` 等の関数もこの行に列挙されていないため、必須ではなく任意判断とする。

## Implementation Steps

1. `scripts/emit-event.sh` に `restore_auto_session_pointer()` 関数を追加する:
   ```bash
   restore_auto_session_pointer() {
     [[ -n "${AUTO_EVENTS_LOG:-}" ]] && return 0
     local _pgid; _pgid=$(ps -o pgid= -p $$ | tr -d ' ')
     local _sid
     _sid="$(cat ".tmp/auto-session-${_pgid}" 2>/dev/null || cat ".tmp/auto-session-current" 2>/dev/null || echo '')"
     [[ -z "${_sid}" ]] && return 0
     AUTO_SESSION_ID="${AUTO_SESSION_ID:-$_sid}"
     AUTO_EVENTS_LOG=".tmp/auto-events.jsonl"
     export AUTO_SESSION_ID AUTO_EVENTS_LOG
   }
   ```
   `AUTO_EVENTS_LOG` が既に設定済みの場合は何もしない (env var 最優先の既存優先順位チェーン `env var > PGID file > auto-session-current > empty` — Issue #791 spec 記載 — を維持)。`/verify` は wrapper を持たないため実運用では PGID 分岐はほぼ常に不一致となり `auto-session-current` 分岐が実質的な復元経路になるが、将来 wrapper が追加された場合の互換性のため PGID 分岐も残す (`run-code.sh` に既にある「dead code だが害はない」という前例と同じ扱い)。ポインタが見つからない場合は `AUTO_EVENTS_LOG` を設定しないため、standalone `/verify` 実行は引き続き計装対象外のまま。(→ acceptance criteria D)

2. `skills/verify/SKILL.md` 内で `AUTO_EVENTS_LOG:-` を grep して全ガード箇所を洗い出し、各箇所で既存の
   ```bash
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
     source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
     EMIT_ISSUE_NUMBER=$NUMBER emit_event "..." ...
   fi
   ```
   の形を
   ```bash
   source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
   restore_auto_session_pointer
   if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
     EMIT_ISSUE_NUMBER=$NUMBER emit_event "..." ...
   fi
   ```
   に置き換える (`source` をガードの外側・前に移動し、直後に `restore_auto_session_pointer` を呼ぶ)。`verify_reopen_cycle` 箇所 (`AUTO_EVENTS_LOG`+`AUTO_SESSION_ID` の複合ガード、`emit_event()` を使わず printf で直接書き込む箇所) は現状 `source` 自体が無いため、ガード直前に `source` + `restore_auto_session_pointer` を新規追加する。(parallel with 3) (→ acceptance criteria D)

3. `skills/auto/SKILL.md` の「AUTO_SESSION_ID generation」ステップ内、`printf '%s\n' "$SESSION_ID" > ".tmp/auto-session-${PGID}"` の直後に以下を追加する:
   ```bash
   printf '%s\n' "$SESSION_ID" > ".tmp/auto-session-current"
   ```
   (Step 1 の一度きりの生成箇所のみに適用する。「Pointer file regeneration required before every `run-*.sh` call」節の再生成ブロックは対象外 — そちらは wrapper script 向けの既存 PGID 方式のままで正しく機能しているため変更不要。) (parallel with 2) (→ acceptance criteria D)

4. `modules/event-emission.md` の「Non-Wrapper Emitters」節と `skills/audit/SKILL.md` の「Session Boundary Identification」節に、Changed Files に記載した `restore_auto_session_pointer()` / `.tmp/auto-session-current` の役割を追記する。(after 1, 2, 3) (→ acceptance criteria D)

5. `tests/emit-event.bats` に以下のテストケースを追加する (既存テストの `cd "$BATS_TEST_TMPDIR"` + `bash -c "source \"$SCRIPT\" && ..."` パターンに準拠。`setup()` が `AUTO_EVENTS_LOG` をグローバル export しているため、各テスト内で明示的に `unset` すること):
   - `.tmp/auto-session-current` が存在し `AUTO_EVENTS_LOG`/`AUTO_SESSION_ID` が未設定のとき、`restore_auto_session_pointer` 呼び出し後に両方が正しく設定されること
   - ポインタファイル (`.tmp/auto-session-${PGID}` と `.tmp/auto-session-current` の両方) が存在しないとき、`restore_auto_session_pointer` 呼び出し後も `AUTO_EVENTS_LOG` が未設定のままであること (standalone 実行の除外方針が維持されることの検証)
   - `AUTO_EVENTS_LOG` が呼び出し前から設定済みのとき、`restore_auto_session_pointer` がその値を上書きしないこと
   (after 1) (→ acceptance criteria E)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/verify/SKILL.md または関連 script に、verify フェーズの phase_start/phase_complete イベント発火ロジックが追加されている" --> <!-- verify: file_contains "skills/verify/SKILL.md" "phase_start" --> <!-- verify: file_contains "skills/verify/SKILL.md" "phase_complete" --> `/verify` 実行開始時・終了時に `scripts/emit-event.sh` 経由で `phase_start`/`phase_complete` (phase=verify) イベントが `.tmp/auto-events.jsonl` に記録される
- <!-- verify: rubric "skills/verify/SKILL.md に AskUserQuestion 呼び出し回数を記録するイベント発火ロジックが追加されている" --> interactive mode で `AskUserQuestion` が呼び出されるたびに専用イベント (例: `verify_user_confirm`) が記録される
- <!-- verify: rubric "bats テストで新規イベント発火が検証されている" --> 追加した2種のイベント発火について bats テストが追加されている
- <!-- verify: rubric "AUTO_EVENTS_LOG/AUTO_SESSION_ID が呼び出し元セッションから引き継がれていない状態でも、/verify 実行時にこれらの値が復元され phase_start/phase_complete (phase=verify) が発火する仕組みが実装されている" --> `/auto` の in-session `Skill()` 呼び出し経由 (例: `--batch` List mode) で `/verify` が実行された場合でも、`AUTO_EVENTS_LOG`/`AUTO_SESSION_ID` が必要に応じて復元され、`phase_start`/`phase_complete` (phase=verify) イベントが `.tmp/auto-events.jsonl` に記録される
- <!-- verify: rubric "上記の復元ロジックについて bats テストが追加されている" --> 環境変数が未設定な状態からの復元ロジックについて bats テストが追加されている

### Post-merge
- 次回 `/verify` 実行時に、`/auto` の in-session `Skill()` 呼び出し経由の場合を含め、`.tmp/auto-events.jsonl` へ `phase_start`/`phase_complete` (phase=verify) と `verify_user_confirm` (該当時) が実際に記録されることを確認 <!-- verify-type: opportunistic -->

## Notes

- **`/issue` フェーズの自動解決 (1周目・再掲)**: 実装場所 (SKILL.md インライン)、`phase_complete` の全終端分岐発火、`AUTO_EVENTS_LOG` 単独ゲートの 3 点は 1周目の `/issue` フェーズで自動解決済み。本 Spec のガード構成 (`if [[ -n "${AUTO_EVENTS_LOG:-}" ]]`) はその決定を踏襲する。
- **Issue #900 との整合性確認 (1周目・再掲)**: `scripts/get-auto-session-report.sh` の Verify Phase Residuals 検出はライブラベル参照方式に切り替え済みで、本 Issue の `phase_start`/`phase_complete` (phase=verify) イベントには依存しない。
- **`.tmp/auto-session-current` の staleness リスクは受容する (今回の自動解決)**: `/auto` セッションが異常終了した場合、`.tmp/auto-session-current` は次回 `/auto` 起動まで残留し続ける。この間に無関係な standalone `/verify N` 実行があると、誤って計装対象に含まれる可能性がある。しかし (a) `.tmp/` 配下の他の `auto-session-*` ファイル群も同様にセッション終了時クリーンアップを持たない既存の設計慣行であること、(b) 影響が「摩擦計測データに低頻度のノイズが混入する」程度でデータ破損や機能不全を伴わないこと、(c) `/auto` Step 1 が毎回無条件に上書きするため実際の残留期間は短いこと、から能動的なクリーンアップ (TTL チェック等) は追加せず Size S の範囲に収める。将来 staleness が実測で問題になった場合は別 Issue で対応する。
- **`run-review.sh` 等との差分**: `run-review.sh`/`run-code.sh`/`run-merge.sh` は wrapper が nested Claude session を起動する前に env var を export するため、nested session の全 Bash tool call が OS 環境変数として自動継承する。`/verify` は `Skill()` 経由で親セッションと同一プロセスの一部として実行され、各 Bash tool call が独立した新規プロセスグループになる (`skills/auto/SKILL.md` の「SESSION_ID does not persist as a shell variable across separate Bash tool calls」と同じ制約)。そのため `restore_auto_session_pointer` は発火箇所ごとに毎回呼び出す必要があり、Step 1 で一度呼べば足りるものではない。
- **重複 Issue のクローズ状況 (1周目・再掲)**: #898・#899 は `/issue` フェーズで本 Issue (#902) を正 (canonical) として重複クローズ済み。

## review retrospective

### Spec vs. implementation divergence patterns

実装は Implementation Steps 1〜5 の内容と厳密に一致していた (発火箇所・イベント名・フィールド名・Step 11 の5終端分岐カバレッジすべて)。ただし Step 3 のコードスニペットに含まれていた `${N}`/`${RESPONSE}` という bash 変数代入前提の記法は、本 Spec 自身がそのまま実装へ転記した結果であり、コード化フェーズで新たに生じた乖離ではない。`skills/verify/SKILL.md` の既存慣例 (`{N}` のようなプレースホルダーは `$` なしで書く。実際の bash 変数を指す場合のみ `${NEXT_ITERATION}` のように `$` を使う) との不整合が Spec 作成時点から埋め込まれていたことになる。次回同種の Spec 作成時は、SKILL.md 内の既存コードスニペット記法 (代入済み変数か prose プレースホルダーか) を踏襲するよう明記するとよい。

### Recurring issues

なし。今回の2件の SHOULD 指摘 (記法不整合、`docs/structure.md` の記述漏れ) はいずれも単発の軽微な指摘であり、過去レビューで繰り返し出ているパターンとは異なる。

### Acceptance criteria verification difficulty

3件すべて rubric ベースで、うち1件は `file_contains` による補助検証も付与されていたため、判定に迷う UNCERTAIN は発生しなかった。Post-merge の1件は `verify-type: opportunistic` であり `/merge` 後の次回 `/verify` 実行で観測されるため、本レビューでの判定対象外として扱った。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Squash merge を実行 (mergeable=true、conflict なし)。マージコミット `fdee8d3d`
- レビュー指摘対応の追加コミット `78fafc29` を含めてマージ完了

### Deferred Items
- `scripts/get-auto-session-report.sh` の Metrics 出力キャベア文言 (「The verify phase does not emit phase_start/phase_complete events...」) は本実装後は事実と異なる記述になるが、Spec の Notes 記載通りスコープ外として別 Issue 送りとする
- Post-merge AC (opportunistic): 次回 `/verify` 実行で `phase_start`/`phase_complete`/`verify_user_confirm` の実記録を観測する必要あり

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC を rubric + file_contains の多層構成にした設計は verify で機械的に検証でき良好。Size S は妥当
- spec がクローズ済み #900 の「/verify は実データ上 phase==verify イベントを emit していない」証拠を発見し Background 主張を裏付けた

#### design
- `/verify` は #485 で run-verify.sh が削除され wrapper を持たないため、skill 本体からインラインで emit する設計は正しい。`phase_complete` を Step 11 の全終端分岐で発火する判断も妥当

#### code
- **silent no-op アノマリ (手動リカバリ)**: code-pr フェーズが worktree branch `worktree-code+issue-902` に実装コミット `ae0d6165` を作成したが push / PR 作成に至らず終了。run-code.sh の auto-retry が 3/3 まで回ったが各回とも no-op (コミット済みを検知せず push+PR に進めなかった) だった。parent session が手動で push + PR #909 作成してリカバリ
- これは #906/#907 で対応中の `code-patch-silent-no-op` の **pr-route 変種**。run-auto-sub.sh が持つ `code_phase_milestone` (post-commit → push-and-pr) resume は、/auto pr route が直接呼ぶ standalone `run-code.sh --pr` 経路には効かないため取りこぼした
- 実装自体は fixup/amend なしで妥当

#### review
- review-light が SHOULD 2件 (`${N}`/`${RESPONSE}` 記法統一、docs/structure.md 更新) を検出・即修正。CI 全 SUCCESS。有効に機能した

#### merge
- conflict なし squash merge。ただし本実装により `get-auto-session-report.sh` の verify-phase caveat 文言が事実と drift する点を merge handoff が検出し deferred 化した

#### verify
- pre-merge 3件すべて file_contains/rubric/bats で PASS。post-merge (opportunistic) は本 verify 実行が計装反映前スキルで走ったため未計測 → phase/verify で opportunistic pending

### Improvement Proposals
- **code フェーズの AC 駆動 follow-up Issue 作成に重複チェックが無い**: #877 の code フェーズが AC4 (「follow-up Issue 作成」) を満たすため `gh issue create` で #902 を直接起票したが、既に同趣旨の #898/#899 が存在していた。code フェーズの follow-up 起票は retro-proposals の dedup パイプラインを通らず open Issue との照合が無いため、三重重複 (#898/#899/#902) を招いた。code フェーズの follow-up Issue 作成前に軽量な open-issue 重複チェック (retro-proposals の dedup ロジック共用) を挟むことを提案する (複数箇所で follow-up 起票が発生する構造的問題)
- **`get-auto-session-report.sh` の verify-phase caveat 文言 drift**: 本 Issue の計装追加により「The verify phase does not emit phase_start/phase_complete events...」という caveat が事実と異なる記述になった。`scripts/get-auto-session-report.sh` (および関連ドキュメント) の当該文言を、verify phase も phase_start/phase_complete を emit する前提に更新する必要がある (merge phase handoff で deferred 化済み)

### Notes for Next Phase
- `/verify` 実行時、Post-merge AC の opportunistic 観測 (`.tmp/auto-events.jsonl` への実イベント記録確認) を忘れずに行うこと
