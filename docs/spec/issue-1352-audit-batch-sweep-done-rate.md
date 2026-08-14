# Issue #1352: audit: stats --retention にバッチ sweep 経由 done 率の指標を追加

## Overview

`/audit stats --retention` は現状、`phase/verify` の滞留日数分布 (Section 8)・Icebox 滞留 (Section 9)・recovery candidate 頻度 (Section 10)・opportunistic-verify retire candidate (Section 11) を報告するが、`phase/verify` backlog の消化経路 (opportunistic-verify / observation dispatch / batch sweep) 別の `phase/done` 到達率を比較する指標は存在しない。

Blocked by #1349 (CLOSED) — `scripts/rank-verify-backlog.sh` + `/audit verify-backlog` サブコマンド (ランキング選抜 → `wholework:verify` 順次実行) を実装済み。#1351 (CLOSED) はその定期実行方法として `/loop 1h /audit verify-backlog --top 10` (L1, 対話セッションからの人手起動) を選定済み。本 Issue はこの2件の後続として、バッチ sweep 経由で処理された Issue の `phase/done` 到達率を、既存の2経路 (opportunistic-verify / observation dispatch) と並べて継続的に比較できる指標を `/audit stats --retention` に追加する。

調査の結果、3経路のうち **observation dispatch のみ**が既存の Issue コメントマーカー (`<!-- wholework-event: type=observation-trigger ... -->`, `scripts/observation-trigger.sh` が投稿) で判別可能で、**opportunistic-verify** は `docs/sessions/*/events.jsonl` に蓄積された `opportunistic_verify_result` イベント (Section 11 が既に使っているデータソース) で判別可能。**batch sweep には判別手段が存在しない** (#1349 の実装は `/verify` 呼び出しに `--session-id` を付与しない設計だったため) — 本 Issue で新設する。詳細は Notes を参照。

## Changed Files

- `skills/audit/SKILL.md`:
  - `verify-backlog` Subcommand の Step 2 に、`wholework:verify` 呼び出し直前でバッチ sweep ディスパッチマーカーを投稿する処理を追加
  - `--retention` Option に `Section 12: Verify Path Done-Rate Comparison` を新設 (Section 11 の直後、`#### Retire-Proposal Comment Posting` の直前)
  - `### Step 4: Save` の "Sections 8, 9, and 10" という文言を "Sections 8, 9, 10, 11, and 12" に修正 (Section 11 追加時 (#1236) に更新されていなかった既存の drift を、同じ文への編集のついでに是正する — Notes 参照)
  - `allowed-tools` frontmatter に `${CLAUDE_PLUGIN_ROOT}/scripts/collect-verify-path-done-rate.sh:*` を追加
- `modules/l0-surfaces.md`: `## Machine-Readable Event Marker` に `type=batch-verify-dispatch` の説明を新設
- `scripts/collect-verify-path-done-rate.sh`: 新規ファイル — 経路別 done 率集計スクリプト
- `tests/collect-verify-path-done-rate.bats`: 新規ファイル — 上記スクリプトの bats テスト
- `docs/structure.md`: Scripts 一覧 (Project utilities) に `collect-verify-path-done-rate.sh` を追加。Directory Layout の `scripts/ (86 files)` を `(87 files)`、`tests/ (122 files)` を `(123 files)` に更新
- `docs/ja/structure.md`: 上記 `docs/structure.md` 変更分の日本語ミラー同期 (`docs/translation-workflow.md` 準拠、既存の全角括弧表記は維持)
- `tests/audit-retention.bats`: 変更不要 (Read で確認済み — `scripts/compute-escalation-level.sh` のみを対象とし、本 Issue はそのスクリプトに変更を加えない)

## Implementation Steps

1. `skills/audit/SKILL.md` の `verify-backlog` Subcommand `### Step 2: Sequential Verify Execution` を変更する (→ 受入条件 AC3)。各 Issue 番号 `$N` について、`Skill(skill="wholework:verify", args="$N")` を呼び出す**直前**に、以下のマーカーコメントを投稿する処理を追加する:
   ```
   <!-- wholework-event: type=batch-verify-dispatch phase=audit issue=$N -->
   Selected by `/audit verify-backlog` ranking (batch verify sweep). Running `wholework:verify` now.
   ```
   投稿方法は `.tmp/batch-verify-dispatch-$N.md` に Write ツールで書き込み、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/batch-verify-dispatch-$N.md` で投稿後に削除する (Step 15 の Issue Comment 投稿と同じ temp file ライフサイクル。`gh-issue-comment.sh` は既存 `allowed-tools` でカバー済み)。投稿失敗は best-effort とし (`observation-trigger.sh` と同じ扱い)、後続の `/verify` ディスパッチをブロックしない。

2. `modules/l0-surfaces.md` の `## Machine-Readable Event Marker` に、既存の `type=verify-executability` 節の直後に `**type=batch-verify-dispatch**` の説明を新設する (parallel with 1) (→ 受入条件 AC3)。内容:
   - 投稿者: `/audit verify-backlog` Step 2 (Implementation Step 1 参照)
   - Attributes: `phase=audit`, `issue=<N>` (`event=` 属性はなし — batch sweep には observation dispatch のような named event が存在しないため)
   - 例示コメント (Implementation Step 1 と同じ本文)
   - 解決方針: `type=pre-merge-ac-gate` / `type=preview-ac-unverified` と異なり latest-wins 解決は不要。消費者 (`scripts/collect-verify-path-done-rate.sh`) は「このIssueに対して少なくとも1件マーカーが存在するか」のみを見る (Issue コメントは append-only なので、複数回の batch sweep 対象になった Issue でも古いマーカーが有効な証跡であり続ける)

3. `scripts/collect-verify-path-done-rate.sh` を新規作成する (after 1, 2) (→ 受入条件 AC1, AC2)。仕様:
   - Usage: `scripts/collect-verify-path-done-rate.sh [--limit N]`。`--limit`: `gh issue list` のページサイズ (デフォルト `1000`。Section 10 の `gh issue list --state all --limit 1000` と同じ規約)。取得件数が `--limit` に達した場合は stderr に警告。
   - `gh issue list --state all --json number,labels,comments --limit "$LIMIT"` で全 Issue (labels + comments 込み) を1回で取得する (`gh issue view` の N+1 呼び出しを避ける — `collect-verify-retention-stats.sh` と異なるアプローチ)。`gh` 失敗時は **3経路すべて** fail-open (processed=0, done=0, rate=N/A、exit 0) とする — 一部の経路だけ部分計算すると「gh 失敗で不明」と「実測 0%」が区別できなくなるため、全経路を揃えて fail-open する。
   - 各 Issue について `is_done` (`labels[].name` に `phase/done` を含むか) を判定する。
   - **batch-sweep 集合**: `comments[].body` のいずれかが `<!-- wholework-event: type=batch-verify-dispatch` を含む Issue。
   - **observation-dispatch 集合**: `comments[].body` のいずれかが `<!-- wholework-event: type=observation-trigger` を含む Issue (既存マーカー、`scripts/observation-trigger.sh` が投稿— 本スクリプトは読み取るだけで投稿側には手を加えない)。
   - **opportunistic-verify 集合**: `docs/sessions/*/events.jsonl` (Glob で列挙、`collect-opportunistic-retire-candidates.sh` と同じ規約) から `event == "opportunistic_verify_result"` のイベントを収集し、`.issue` の一意な値の集合を作る。上記 `gh issue list` の結果に存在しない Issue 番号 (削除済み等) は集計から除外し、除外件数を stderr に警告として出力する。
   - 3集合は互いに排他ではない (同じ Issue が複数経路の集合に含まれ得る — 例: observation dispatch で解決しなかった Issue が後日 batch sweep で再選抜される)。集合ごとに独立して `processed_count` (集合のサイズ) と `done_count` (集合のうち `is_done` な Issue 数) を数え、`rate = done_count / processed_count` を計算する (`processed_count` が 0 の場合は `rate` を `N/A` とする。0除算を避ける)。
   - stdout: `<path>\t<processed_count>\t<done_count>\t<rate>` 形式で3行 (`path` は `batch-sweep` / `observation-dispatch` / `opportunistic-verify` の固定スラグ)。`rate` はパーセント表記 (小数点1桁、例 `80.0%`) または `N/A`。
   - bash 3.2+ 互換 (`mapfile` 不使用。jq でのデータ処理を主体にする — `collect-opportunistic-retire-candidates.sh` と同じアプローチ)。

4. `tests/collect-verify-path-done-rate.bats` を新規作成する (after 3) (→ 受入条件 AC1, AC2)。`tests/rank-verify-backlog.bats` と同じ `gh` モック規約 (`PATH` 経由でモック `gh` を差し込み、`gh issue list` 呼び出しに対して固定 JSON を返す) に加え、`docs/sessions/{SID}/events.jsonl` 相当の一時ディレクトリ・JSONL フィクスチャを用意する (`collect-opportunistic-retire-candidates.bats` と同じ規約)。最低限のケース:
   - `<!-- wholework-event: type=batch-verify-dispatch` マーカー付きコメントを持つ Issue が `batch-sweep` の `processed_count` に計上され、`phase/done` ラベル付きなら `done_count` にも計上されることを確認
   - `<!-- wholework-event: type=observation-trigger` マーカー付きコメントを持つ Issue が `observation-dispatch` に計上され、`batch-sweep` には計上されないことを確認 (経路の取り違えがないことの回帰テスト)
   - フィクスチャ `events.jsonl` 内の `opportunistic_verify_result` イベント (同一 Issue に対する複数イベントを含む) が `opportunistic-verify` の `processed_count` に一意 Issue 数として計上され、`phase/done` ラベルと突き合わされることを確認
   - 集合が空の経路について `rate` が `N/A` になる (0除算しない) ことを確認
   - `gh` 失敗時に3経路すべて `processed=0 done=0 rate=N/A` で exit 0 になる (fail-open) ことを確認

5. `skills/audit/SKILL.md` の `--retention` Option に `Section 12: Verify Path Done-Rate Comparison` を追加する (after 3) (→ 受入条件 AC1, AC2, AC3)。挿入位置: Section 11 の最終文 ("...同じ scope restriction... #1158/#1165 series).") の直後、`#### Retire-Proposal Comment Posting` 見出しの直前。内容:
   - `${CLAUDE_PLUGIN_ROOT}/scripts/collect-verify-path-done-rate.sh --limit 1000` を実行し、TSV 出力を3行パースする
   - Path / Processed / Done / Rate の4列 Markdown テーブルで表示 (行: `Batch sweep (/audit verify-backlog)` / `Observation dispatch` / `Opportunistic-verify`)
   - テーブル直後に「経路判別方法」の3行サマリを表示する (batch sweep: 新設マーカー、observation dispatch: 既存マーカー、opportunistic-verify: 既存イベント + 集計範囲の注記 — Notes 参照)
   - 3経路すべて `processed_count=0` の場合は "No verify path dispatch data available yet." と表示しテーブルを省略する
   - `### Step 4: Save` の文言更新 ("Sections 8, 9, and 10" → "Sections 8, 9, 10, 11, and 12") と `allowed-tools` frontmatter への新スクリプト追加も本 Step で行う
   - `docs/structure.md` / `docs/ja/structure.md` の同期 (Scripts 一覧・ファイル数コメント) も本 Step で行う

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md の stats --retention サブコマンドに、直近のバッチ sweep 実行 (#1349 のコマンド経由) で処理された Issue 数と、そのうち phase/done に到達した件数・比率が報告される指標が追加されている" --> バッチ sweep 経由の done 率指標が追加されている
- <!-- verify: rubric "同指標が、既存の opportunistic-verify / observation dispatch 経由の done 率と並べて比較表示される形になっている" --> 経路別の比較表示になっている
- <!-- verify: rubric "docs/spec/issue-1352-audit-batch-sweep-done-rate.md に、バッチ sweep 経由かどうかを判別する方法 (Issue コメントのマーカー、auto-events.jsonl の session_id 分類等) が記録されている" --> 経路判別方法が記録されている

### Post-merge

- 次回 `/audit stats --retention` 実行時に、バッチ sweep 経由の done 率が他経路と比較可能な形で表示されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **AC3 rubric 文言への Spec ファイルパス明示 (Auto-Resolve Log)**: Issue 本文の AC3 原文は「...が Spec に記録されている」とのみ記述しており対象ファイルパスを含んでいなかった。`modules/verify-executor.md` の rubric コマンド仕様は「Spec files are not passed to the grader」と明記しており、これは #1351 の Code Retrospective で実際に踏んだのと同型の問題 (rubric グレーダーが根拠ファイルに到達できない) を再発させる。#1351 の対応 (Issue 本文の rubric 文言にファイルパスを明示する形へ修正) に倣い、本 Spec の Verification 節・Issue 本文の AC3 の両方を `docs/spec/issue-1352-audit-batch-sweep-done-rate.md` を明示する文言に修正した。他の候補 (修正しない・rubric を file_contains 系に置き換える) は、AC3 が「判別方法の記録」という定性的な内容を問うており厳密な文字列一致では表現しづらいため不採用。
- **バッチ sweep の経路判別に session_id ではなく Issue コメントマーカーを選んだ理由**: `modules/event-emission.md` の `restore_auto_session_pointer()` 解決順序 (5段階) は、`AUTO_SESSION_ID` が未設定かつ issue-scoped/PGID いずれのポインタファイルも存在しない場合 fail-closed で no-op する。#1349 の `verify-backlog` Subcommand は `Skill(skill="wholework:verify", args="$N")` を `--session-id` 付与なしで呼ぶ設計であり (#1349 Spec 記載: 「`/verify` は単体実行で自己解決するため不要」)、かつ `/loop 1h /audit verify-backlog --top 10` は `/auto` Step 1 のセッション初期化を経由しない対話セッションから起動される (#1351 の選定結果) ため、上記5段階のいずれにも該当せず `AUTO_EVENTS_LOG` が設定されない — つまり **batch sweep 経由の `/verify` 呼び出しは現状 `auto-events.jsonl` に一切記録されない**。この構造的な欠落を踏まえ、`observation-trigger.sh` が既に使っている Issue コメントマーカー方式 (append-only な GitHub state に判別情報を残す) を採用した。session_id ベースの分類は、`/verify` 呼び出しに `--session-id` を追加する改修と `docs/sessions/*/events.jsonl` へのコミットを伴う設計変更が必要になり、本 Issue (Size S) のスコープを超えるため不採用。
- **opportunistic-verify 集計の既知の範囲制限**: `docs/sessions/*/events.jsonl` は `/auto` の L3 auto-retrospective (`skills/auto/SKILL.md` Step 5) が `batch`/`sub_issue` (XL) ルートの場合のみ生成する (`skills/auto/SKILL.md`: 「L3 auto-retrospective (batch/XL routes only...)」)。したがって単発 Issue の `/auto` 実行中に発生した `opportunistic_verify_result` イベントは `docs/sessions/*/events.jsonl` にコミットされず、本 Issue の opportunistic-verify 集計から漏れる。この制限は Section 11 (Opportunistic Verify Retire Candidates, #1236) が既に同じデータソースで抱えている既存の制約であり、本 Issue が新たに導入するものではない。3経路中 opportunistic-verify のみこの制約を持つ非対称性は Section 12 の表示にも一言注記する (Implementation Step 5)。
- **3経路は互いに排他ではない**: 同一 Issue が observation dispatch で解決せず後日 batch sweep で再選抜される、といったケースが起こり得るため、`processed_count` の合計は Issue 総数と一致しない。これは意図的な設計 (経路ごとの効果を独立に測定する) であり、Section 4 (Work Origin Classification) のような排他分類とは異なる。
- **`gh issue list --json comments` の採用理由**: `gh search issues --match comments` (Search API) との比較検討を行った。Search API は本リポジトリの既存スクリプトでの前例がなく、GitHub 側のレート制限が Core API と別枠 (認証済みで 30 req/min) でより厳しいため、既存の `gh issue list --json ...` (Core API、Section 1/Section 10 で使用中の規約) を用いる設計とした。実際に `gh issue list --state all --json number,comments --limit N` で comments 込みの一括取得が1回の呼び出しで機能することを本 Spec 作成セッション内で実地確認済み (`collect-verify-retention-stats.sh` の「Issue あたり `gh issue view` 1回、約800 Issue」という既存の N+1 パターンより効率的)。
- **Step 4 Save 文言の "Sections 8, 9, and 10" 表記**: #1236 (Section 11 追加) 時点で "Sections 8, 9, and 10" のまま更新されておらず、Section 11 が抜けていた既存 drift。本 Issue で同じ文を編集する (Section 12 を追加する) ついでに "Sections 8, 9, 10, 11, and 12" に是正する。
- 全角括弧表記 (`docs/ja/structure.md` の既存行) はグローバル CLAUDE.md の半角括弧規約の対象外 (既存ファイルの既存表記を維持するのみで、新規に日本語文を執筆する箇所ではないため)。

## Consumed Comments
No new comments since last phase.

## Code Retrospective

### Deviations from Design
N/A — Implementation Steps 1-5 を Spec の記載順どおりに実装した。

### Design Gaps/Ambiguities
- `bash scripts/check-forbidden-expressions.sh` を実行したところ、本 Issue で変更していない `docs/spec/issue-1349-rank-verify-backlog-batch.md` (旧称: Dispatch という用語をそのまま引用した既存の Retrospective 記述) が無関係にフラグされ exit 1 になることを確認した。`git stash` で本 PR の変更を退避した状態でも同じ失敗が再現したため、本 Issue が持ち込んだものではないベースブランチの既存事象と判断し、対応をスコープ外とした。同種の問題 (無関係ファイルの forbidden expression が無関係 PR をブロックする) は既に #1139 で追跡済みのため、新規 follow-up Issue は起票しなかった。

### Rework
N/A

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Fixed the pre-existing forbidden-expression violation in `docs/spec/issue-1349-rank-verify-backlog-batch.md:140` inline (added the 旧称 prefix) rather than waiting on #1139, following the same precedent #1139 itself documents (PR #1138) — currently the only available path to unblock CI for an unrelated pre-existing violation.
- All 3 pre-merge rubric AC verified PASS directly against `skills/audit/SKILL.md` Section 12, `modules/l0-surfaces.md`, and the Spec's existing path-discrimination Notes section; no checkbox edits were needed (already `[x]` from a prior state).

### Deferred Items
- None — the only MUST finding (CI-blocking forbidden expression) was resolved in this phase.

### Notes for Next Phase
- `/merge` can proceed: no unresolved MUST issues remain and CI is 11/11 SUCCESS as of the fix commit.
- The post-merge AC (`verify-type: observation event=auto-run session=next`) resolves on the next `/audit stats --retention` run after merge — `/verify` should look for Section 12 output rather than trying to construct its own auto-run signal.
- #1139 remains open and unrelated to this PR's own scope — this PR's inline fix does not close it; the systemic diff-scope-limiting fix is still pending.

## review retrospective

### Spec vs. implementation divergence patterns
Nothing to note — Implementation Steps 1-5 were followed as specified. The lightweight integrated review (review-light, all 4 aspects) found no MUST/SHOULD/CONSIDER-level issues against the diff, the Spec, or the steering documents.

### Recurring issues
- This PR hit the same structural pattern already tracked by #1139 (first observed on PR #1138, per #1139's own Background section): CI's `Forbidden Expressions check` failed on a pre-existing violation living in a *different* Issue's Spec file (`docs/spec/issue-1349-rank-verify-backlog-batch.md:140`, missing the 旧称/Formerly-called exemption phrasing around a deprecated term reference), unrelated to this PR's own diff. Following the same precedent #1139 documents, `/review` fixed it inline (adding the 旧称 prefix) since no diff-scope-limiting exception exists yet. A second occurrence of this exact pattern strengthens the case for prioritizing #1139's scope-limited check mode — this is recurring friction, not a one-off.

### Acceptance criteria verification difficulty
Nothing to note — all 3 pre-merge AC were `rubric` type with the target Spec file path named explicitly in the Issue body text (an Auto-Resolve Log correction already applied at Issue-authoring time, following the precedent set by #1351). The grader therefore had direct evidence access for all 3, and each verified as PASS without ambiguity.
