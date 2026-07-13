# Issue #1007: get-auto-session-report: Issues processed 集計への PR 番号混入を修正

## Consumed Comments

No new comments since last phase.

## Overview

`/auto --batch` の L3 retrospective で `get-auto-session-report.sh --metrics-only` が出す「Issues processed」が実 Issue 数と一致しない (session 37830-1783901301 で 9 vs 実 3件)。原因は2つに分かれる:

1. **PR 番号の混入**: `run-review.sh` / `run-merge.sh` を親セッションが PR 番号で直接呼ぶ経路 (auto-retry 等) で、`EMIT_ISSUE_NUMBER` に PR 番号がそのまま入り、`phase_start`/`phase_complete` イベントの `issue` フィールドが PR 番号になる (#1001, #1002 相当)。
2. **observation dispatch 分の集計仕様未定義**: batch 完了フローの Event-based observation scan が dispatch した `/verify` 単体実行 (#797 #857 #977 #996 相当) も `.issue` に正しい Issue 番号で計上されるが、「batch 処理 Issue と扱いが同じでよいか」が文書化されていない。

本 Issue は (1) を emit 側の修正で解消し、(2) を集計仕様として文書化する。

## Reproduction Steps

1. `/auto --batch N` 実行中に `/verify` FAIL からの auto-retry などで、親セッションが `run-auto-sub.sh` の `run_phase_with_recovery()` を経由せず `scripts/run-review.sh <PR番号>` または `scripts/run-merge.sh <PR番号>` を直接呼ぶ (`EMIT_PHASE_NAME` が未 export の状態)。
2. 対象スクリプトの `_EMIT_PHASE_OWNED` 分岐 (`EMIT_PHASE_NAME` が空の場合に実行) が `export EMIT_ISSUE_NUMBER="$PR_NUMBER"` を実行し、`emit_event "phase_start"` を呼ぶ。この時点では実 Issue 番号の解決 (`gh-extract-issue-from-pr.sh`) はまだ行われていない。
3. `.tmp/auto-events.jsonl` に `"issue":<PR番号>` の `phase_start`/`phase_complete` 行が記録される。
4. `get-auto-session-report.sh` の `ISSUES_PROCESSED` (`scripts/get-auto-session-report.sh` 174-176行目) は `.issue` の distinct count であり、PR 番号行を独立した Issue として計上してしまう。

## Root Cause

`scripts/run-review.sh` (70-76行目) と `scripts/run-merge.sh` (67-73行目) はいずれも、`_EMIT_PHASE_OWNED` 分岐内で `export EMIT_ISSUE_NUMBER="$PR_NUMBER"` を無条件に実行する。実 Issue 番号の解決 (`gh-extract-issue-from-pr.sh` 呼び出し) は各スクリプトの後段 (run-review.sh 166行目 / run-merge.sh 166行目、`reconcile-phase-state.sh` やラベル遷移のためだけに使用) で行われており、emit 側では再利用されていない。

正規の `/auto` オーケストレーション経路 (`run-auto-sub.sh` の `run_phase_with_recovery()`) では、`_EXTRA_SELF_ISSUE` (実 Issue 番号) を用いて呼び出し前に `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` を正しく export するため (`scripts/run-auto-sub.sh` 530-537行目)、`run-review.sh`/`run-merge.sh` 側の `_EMIT_PHASE_OWNED` 分岐は `EMIT_PHASE_NAME` が既に設定済みのため発火しない。バグが顕在化するのは、この正規経路を経由せず親セッションが直接呼ぶ場合のみ。

なお (2) の observation dispatch 分は上記のバグとは異なる性質で、`.issue` には正しい Issue 番号が入っている (`Skill(skill="wholework:verify", args="$N")` による直接呼び出しのため PR 番号は介在しない)。Issue 本文が指摘する通り、これは「集計の意味論の問題」であり、コード修正ではなく定義の明文化で解消する。

## Changed Files

- `scripts/run-review.sh`: `gh-extract-issue-from-pr.sh` によるIssue番号解決を `_EMIT_PHASE_OWNED` 分岐より前に移動し、`EMIT_ISSUE_NUMBER` を解決済み Issue 番号 (解決失敗時は PR 番号にフォールバック) に修正。後段の重複呼び出しを削除 — bash 3.2+ 互換
- `scripts/run-merge.sh`: 同上 — bash 3.2+ 互換
- `tests/run-review.bats`: 新規テスト2件追加 (`EMIT_ISSUE_NUMBER` が解決済み Issue 番号を使うこと / 解決失敗時に PR 番号へフォールバックすること)
- `tests/run-merge.bats`: 新規テスト2件追加 (同上)
- `tests/get-auto-session-report.bats`: 新規テスト1件追加 (batch Issue と observation dispatch 専用 Issue が混在するフィクスチャで「Issues processed」が両方を計上することを固定化)
- `docs/workflow.md`: `/audit auto-session` を説明する段落 (172行目) に「Issues processed」の集計定義 (batch/XL 完走 Issue と observation dispatch 専用 Issue を区別なく計上し、両者は `sub_start` イベントの有無で判別可能) を追記
- `docs/ja/workflow.md`: 上記の日本語ミラーを同期 (165行目、`docs/translation-workflow.md` の Sync Procedure に従う)

**Steering Docs sync candidate として検出したが変更不要と判断したファイル (grep 実施済み):**

- `docs/structure.md` / `docs/ja/structure.md`: `run-review.sh` / `run-merge.sh` / `get-auto-session-report.sh` への言及は Scripts 一覧の1行役割説明のみで、イベント発行ロジックの内部修正は記述に影響しない
- `docs/tech.md` / `docs/ja/tech.md`: phase/effort matrix の該当行はモデル・effort 選定の説明であり、本修正の対象外
- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: CLI シグネチャ・フラグの変更を伴わないため interface change に該当せず、追記不要

## Implementation Steps

1. `scripts/run-review.sh` を修正する。現状166-167行目の
   ```bash
   _REVIEW_ISSUE=$("$SCRIPT_DIR/gh-extract-issue-from-pr.sh" "$PR_NUMBER" 2>/dev/null \
     | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue_number',''))" 2>/dev/null || echo "")
   ```
   を `_EMIT_PHASE_OWNED=""` の直前 (現状70行目の直前) に移動し、166-167行目からは削除する (後段の `if [[ -n "$_REVIEW_ISSUE" ]]` 以降の利用はそのまま残す)。`_EMIT_PHASE_OWNED` 分岐内の `export EMIT_ISSUE_NUMBER="$PR_NUMBER"` を `export EMIT_ISSUE_NUMBER="${_REVIEW_ISSUE:-$PR_NUMBER}"` に変更し、直後に `export EMIT_PR_NUMBER="$PR_NUMBER"` を追加する (`run-auto-sub.sh` の `run_phase_with_recovery()` が `_EXTRA_SELF_ISSUE` 使用時に設定する `EMIT_PR_NUMBER` と同じ規約 — `scripts/emit-event.sh` がドキュメント化済みのオプション変数に揃える) (→ acceptance criteria 1)
2. `scripts/run-merge.sh` に同様の修正を行う (現状166-167行目の `_MERGE_ISSUE=$(...)` を `_EMIT_PHASE_OWNED=""` の直前に移動、`export EMIT_ISSUE_NUMBER="${_MERGE_ISSUE:-$PR_NUMBER}"` + `export EMIT_PR_NUMBER="$PR_NUMBER"` に変更) (parallel with 1) (→ acceptance criteria 1)
3. `tests/run-review.bats` と `tests/run-merge.bats` のそれぞれに以下2件のテストを追加する (after 1, 2):
   - 「`EMIT_PHASE_NAME` 未設定時、`EMIT_ISSUE_NUMBER` が解決済み Issue 番号を使うこと」: `emit-event.sh` モックを `emit_event() { echo "$1 issue=$EMIT_ISSUE_NUMBER" >> "$EMIT_LOG"; }` に差し替え (既存の `gh-extract-issue-from-pr.sh` デフォルト mock は `{"issue_number": 99}` を返す)、PR 番号 (例: 88) とは異なる 99 が `issue=` として記録されることを確認する
   - 「Issue 番号解決失敗時、`EMIT_ISSUE_NUMBER` が PR 番号にフォールバックすること」: `gh-extract-issue-from-pr.sh` モックを空文字 + exit 1 を返す形に差し替え、`issue=<PR番号>` が記録されることを確認する
   (→ acceptance criteria 1, 3)
4. `tests/get-auto-session-report.bats` に新規テストを1件追加する (after 1, 2)。フィクスチャは既存テスト (`session_id filter` テスト) と同じ JSONL 形式で、同一 `session_id` 内に次の2種類の Issue を混在させる: (a) batch Issue — `sub_start` (size 付き) + `phase_start`/`phase_complete` (`phase` は `code-patch` 等) を持つ、(b) observation dispatch 専用 Issue — `sub_start` を持たず `phase_start`/`phase_complete` (`phase=verify`) のみを持つ。`--metrics-only --no-github` の出力に `Issues processed | 2` が含まれること (両方が計上され、区別なく合算されること) を検証する (→ acceptance criteria 2, 3)
5. `docs/workflow.md` の `/audit auto-session` を説明する段落 (「...Recovery Events.」の直後、「Details: ...」の直前) に、「Issues processed」が batch/XL パイプラインを完走した Issue と observation dispatch 専用の `/verify` 再実行 Issue の両方を区別なく計上すること、両者は該当 Issue 番号に `sub_start` イベントが存在するか否かで判別可能であることを追記する。`docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/workflow.md` の対応段落 (「...5 セクション構成。」の直後、「詳細: ...」の直前) に日本語ミラーを同期する (parallel with 1-4) (→ acceptance criteria 2)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-review.sh / scripts/run-merge.sh のイベント emit、または scripts/get-auto-session-report.sh の集計ロジックの修正により、PR 番号が Issues processed に独立計上されない実装になっている" -->
- <!-- verify: rubric "batch 処理 Issue と observation dispatch (verify のみ) の集計上の扱い (含める/分離する/別行にする等) が実装または docs に明記されている" -->
- <!-- verify: command "bats tests/get-auto-session-report.bats" -->

### Post-merge

- 次回 `/auto --batch` の L3 retrospective で「Issues processed」が実 Issue 数と一致することを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- **SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文の Auto-Resolved Ambiguity Points (`/issue` フェーズで非対話モードにより自動解決済み) を実装方針として採用した: (a) 修正箇所は emit 側 (`run-review.sh`/`run-merge.sh`) — 集計側フィルタのみでは Issue 番号解決後もイベントが PR 番号のまま記録され続ける不完全な対症療法になるため、(b) observation dispatch の扱いは `docs/workflow.md` の `/audit auto-session` 記述への追記で文書化 — 同ファイルに既に `get-auto-session-report.sh` の集計動作に関する記述があり一貫した参照先となるため。
- **`EMIT_PR_NUMBER` 追加の根拠**: `run-auto-sub.sh` の `run_phase_with_recovery()` は `_EXTRA_SELF_ISSUE` 使用時 (review/merge フェーズの正規経路) に `EMIT_PR_NUMBER` を設定しており (`scripts/emit-event.sh` がドキュメント化済みのオプション変数)、`_EMIT_PHASE_OWNED` 分岐 (直接呼び出し経路) だけがこの規約を欠いていた。Issue 番号を正しく `EMIT_ISSUE_NUMBER` に入れる修正と合わせて追加することで、どちらの経路でも `.pr` フィールドから元の PR 番号を追跡できるようにする (この修正がないと `.issue` 修正後は PR 番号の記録が完全に失われる)。
- **observation dispatch の判別方法**: `sub_start` イベントは `run-auto-sub.sh` (699行目) が Issue ごとに1回だけ発行し、batch/単一 Issue/XL sub-issue のいずれの経路でも呼ばれる。一方 Event-based observation scan の dispatch (`skills/auto/SKILL.md` の `## Event-based observation scan`) は `Skill(skill="wholework:verify", args="$N")` を直接呼ぶため `run-auto-sub.sh` を経由せず `sub_start` を発行しない。この非対称性が「batch 処理 Issue」と「observation dispatch 専用 Issue」を機械的に判別する唯一の既存シグナルであり、Step 5 の docs 追記および Step 4 の bats テストはこれを固定化する。
- **`tests/get-auto-session-report.bats` フィクスチャ形式**: 既存テスト (`session_id filter` テスト、ファイル冒頭) と同じ1行1JSON形式。batch Issue 側は `{"ts":"...","issue":<N>,"event":"sub_start","session_id":"<sid>","size":"S"}` に続けて `phase_start`/`phase_complete` (`phase` は任意の値、例: `code-patch`) を追加。observation dispatch 側は `sub_start` を含めず `{"ts":"...","issue":<M>,"event":"phase_start","session_id":"<sid>","phase":"verify"}` と対応する `phase_complete` のみを追加する。
- **旧 recovery 記録**: `docs/spec/issue-1007-recovery.md` は本 Issue の `/issue` (triage) フェーズで発生した manual recovery (skip-forward) の記録であり、本 Spec とは独立したファイルとして残す (削除・統合は本 Spec のスコープ外)。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 をすべて Spec の記述通りに実施した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

### Notes
- `/code` 実行開始時、Issue のラベルは既に `phase/code` だった (Spec 作成コミット後、`phase/ready` を経由せず前回セッションの中断状態が残存していたと推定)。`reconcile-phase-state.sh --check-precondition code-pr` は `matches_expected:false` (phase/ready 不在) を返したが、Spec は完成済みで実装に十分な情報があったため、非対話モードの auto-resolve 方針 (Spec 不在時の代替読み込み) を「Spec は存在するが precondition ラベルのみ欠けているケース」に準用し、警告を出しつつ実装を継続した。

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — Implementation Steps 1-5 followed exactly (emit-side fix, EMIT_PR_NUMBER export, bats tests, docs sync), no structural divergence found in the diff.

### Recurring issues
- Nothing to note — no recurring issue patterns observed in this review.

### Acceptance criteria verification difficulty
- Nothing to note — all 3 pre-merge conditions (rubric x2, bats command) resolved cleanly to PASS with no UNCERTAIN; the rubric wording explicitly allowing either "emit 側" or "集計側" fix location avoided ambiguity at verification time.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Merge proceeded directly (mergeable=true, reason=clean; CI success, review approved) — no conflict resolution needed.
- Squash-merged PR #1013 into main and deleted the remote branch.

### Deferred Items
- Post-merge AC (次回 `/auto --batch` の L3 retrospective での「Issues processed」実 Issue 数一致の観察) remains for post-merge observation — not verifiable at merge time.

### Notes for Next Phase
- `/verify` should confirm the post-merge observation AC by checking the next `/auto --batch` L3 retrospective for correct "Issues processed" counts.
- No MUST/SHOULD/CONSIDER issues were raised during review; merge was clean.

## Auto Retrospective

### Manual recovery (code-pr)
- **Date**: 2026-07-13 18:28 UTC
- **Issue**: #1007, phase: code-pr
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success

### Manual recovery (review)
- **Date**: 2026-07-13 18:28 UTC
- **Issue**: #1007, phase: review
- **Source**: parent session manual recovery
- **Recovery type**: respawn
- **Wrapper exit code**: unknown
- **Outcome**: success
