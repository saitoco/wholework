# Issue #1236: opportunistic-verify: 判定結果をイベント化し空振り AC の retire 候補を集計可能にする

## Overview

`modules/opportunistic-verify.md` の opportunistic verification は `/issue`/`/spec`/`/code`/`/review`/`/verify` の完了時に走り、`verify-type: opportunistic` な未チェック AC を PASS/FAIL/SKIP 判定するが、判定結果はどこにも記録されない。実測 (session `33233-1786023637`) では 6 回の実行すべてで同じ 14 件が SKIP と判定され、この 84 回の判定コストが記録されないため「どの AC が何回空振りしたか」を事後集計できない。

本 Issue は次の 2 点を実装する:
1. `modules/opportunistic-verify.md` の判定 (Step 2 AI Retrospective) 完了直後に、判定した条件 1 件につき 1 イベント `opportunistic_verify_result` を emit する (#1159 の `retro_proposal_classified` と同じ non-wrapper emitter パターンを踏襲)。
2. `skills/audit/SKILL.md` の `stats --retention` に、この蓄積イベントを集計して「連続 SKIP 回数が多い AC」を retire 候補として報告する新セクションを追加する (Section 10 Recovery Candidate Frequency と同じ「専用スクリプト + 閾値表示」パターンを踏襲)。

実際の retire 実行 (AC の削除・再型付け) は本 Issue のスコープ外 — 判断材料の提供までとする。

## Changed Files

- `modules/opportunistic-verify.md`: Input に呼び出し元スキル自身の Issue/PR 番号を追加。既存 Step 2 (AI Retrospective) の直後に新 Step 3 「Persist Judgment Results (Event Emission)」を挿入し、旧 Step 3 (Update Checkboxes) → Step 4、旧 Step 4 (All Conditions PASS → Label Transition) → Step 5 に繰り下げ。Output にイベント emit の記述を追加
- `scripts/emit-event.sh`: ヘッダーコメントの "Documented event schemas" ブロックに `opportunistic_verify_result` のスキーマ説明を追加 (`retro_proposal_classified` ブロックに倣う形式)。`emit_event()` 本体の関数ロジックは変更しない (汎用実装のため無改修で新イベント型に対応済み)
- `modules/event-emission.md`: 「Non-Wrapper Emitters」節に `opportunistic_verify_result` の説明段落を追加 (`retro_proposal_classified` 段落に倣う形式)
- `scripts/collect-opportunistic-retire-candidates.sh`: 新規。コミット済み `docs/sessions/*/events.jsonl` から `opportunistic_verify_result` イベントを収集し、`(issue, ac_index)` 単位でグルーピングして「末尾から連続する SKIP 回数」を算出するスクリプト。bash 3.2+ compatible
- `tests/collect-opportunistic-retire-candidates.bats`: 新規。上記スクリプトの bats テスト (空ログ、閾値未満、末尾 SKIP 連続、末尾が PASS/FAIL でリセット、複数グループのソート順)
- `skills/audit/SKILL.md`: `allowed-tools` に新スクリプトのエントリを追加。`stats --retention` の Section 10 (Recovery Candidate Frequency) の直後、Retire-Proposal Comment Posting の直前に「Section 11: Opportunistic Verify Retire Candidates」を追加
- `docs/structure.md`: Directory Layout の `scripts/` ファイル数コメントを更新。Key Files > Scripts > Project utilities に新スクリプトのエントリを追加。[Steering Docs sync candidate]
- `docs/ja/structure.md`: 上記 `docs/structure.md` の変更を日本語で反映 (`docs/translation-workflow.md` の Sync Procedure に従う)。[Steering Docs sync candidate]

## Implementation Steps

1. `modules/opportunistic-verify.md` を編集する (→ acceptance criteria 1, 2):
   - `## Input` に箇条書きを追加: 「**Calling Issue/PR number**: 呼び出し元スキルが現在処理している Issue (または PR から解決した Issue) 番号。呼び出し元スキル自身のコンテキストから取得 (`/spec`/`/code`/`/issue`/`/verify` は自身の `$NUMBER`、`/review` は PR から解決済みの Issue 番号) — Step 3 のセッションポインタ解決に使用」
   - 既存の `### 2. Cross-Reference with Current Execution Results (AI Retrospective)` の直後に新しい `### 3. Persist Judgment Results (Event Emission)` を挿入する:

     ````markdown
     ### 3. Persist Judgment Results (Event Emission)

     Step 2 の判定ループ内で、各条件の PASS/FAIL/SKIP 判定が確定した直後、次の条件に進む前に、条件 1 件につき 1 イベントを emit する (集約しない — 理由は Notes 参照):

     ```bash
     source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"
     restore_auto_session_pointer <呼び出し元スキル自身の Issue/PR 番号>
     if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
       EMIT_ISSUE_NUMBER=<この条件が属する候補 Issue 番号 N> emit_event "opportunistic_verify_result" \
         "skill=<呼び出し元スキル名 (例: /spec)>" \
         "result=<PASS|FAIL|SKIP>" \
         "ac_index=<1-based index>"
     fi
     ```

     - **`AUTO_EVENTS_LOG` ガード (必須)**: `AUTO_EVENTS_LOG` が未設定かつ `restore_auto_session_pointer` でも復元できない場合 (`/auto` 外のスタンドアロン実行等) は emit をスキップする — `modules/event-emission.md` の他の non-wrapper emitter と同じ方針
     - **`ac_index`**: 候補 Issue 本文の全チェックボックス列挙 (pre-merge + post-merge 通し) における当該条件の 1-based 位置。`scripts/gh-issue-edit.sh --checkbox` および `scripts/check-pre-merge-ac.sh` と同じ global-index 規約。Step 1/2 で既に取得済みの Issue 本文に対し `^- \[[ xX]\]` 行をカウントして決定する
     - **`EMIT_ISSUE_NUMBER` と `restore_auto_session_pointer` の対象が異なる**点に注意: `restore_auto_session_pointer` には呼び出し元スキル自身の Issue/PR 番号 (セッションポインタ解決用) を渡すが、`EMIT_ISSUE_NUMBER` には判定対象の候補 Issue 番号 N (イベントの `issue` フィールドに記録される、集計時に意味を持つ値) を渡す
     ````

   - 旧 `### 3. Update Checkboxes` を `### 4. Update Checkboxes` に、旧 `### 4. All Conditions PASS → Label Transition` を `### 5. All Conditions PASS → Label Transition` に番号を繰り下げる
   - `## Output` の箇条書きに追加: 「`opportunistic_verify_result` イベント: 判定した条件 1 件につき 1 件、`AUTO_EVENTS_LOG` 設定時に emit (Step 3)」

2. `scripts/emit-event.sh` のヘッダーコメント「Documented event schemas」ブロックに、`retro_proposal_classified` ブロックの直後へ次の説明を追加する (→ acceptance criteria 1, 2, 5):

   ```
   # opportunistic_verify_result: modules/opportunistic-verify.md の判定結果 (PASS/FAIL/SKIP) を
   # 条件 1 件ごとに emit する。Step 2 (AI Retrospective) で各条件の判定が確定した直後に emit される
   # (#1236)。1 件ずつ emit し集約しない — 理由は modules/opportunistic-verify.md 側のコメント、
   # および Issue #1236 の Spec Notes を参照。
   #   skill=<skill-name>            呼び出し元スキル名。例: /spec, /review, /verify, /issue, /code
   #   result=<PASS|FAIL|SKIP>       この条件の判定結果
   #   ac_index=<n>                  候補 Issue 本文の全チェックボックス列挙 (pre-merge + post-merge
   #                                  通し) における 1-based 位置。gh-issue-edit.sh --checkbox と同じ
   #                                  global-index 規約
   #   EMIT_ISSUE_NUMBER には判定対象の候補 Issue 番号が入る (呼び出し元スキル自身の Issue 番号では
   #   ない場合がある)
   ```

   同時に `modules/event-emission.md` の「## Non-Wrapper Emitters」節、`retro_proposal_classified` の説明段落の直後に次を追加する:

   > **`opportunistic_verify_result` (Issue #1236)**: `modules/opportunistic-verify.md` — `run-*.sh` wrapper ではない — が、判定した条件 1 件ごとに、その条件の PASS/FAIL/SKIP 判定が確定した直後に emit する。他の non-wrapper emitter と同様、`AUTO_EVENTS_LOG` ガードの直前に `source emit-event.sh` + `restore_auto_session_pointer` (呼び出し元スキル自身の Issue 番号を渡す) を呼び、`AUTO_EVENTS_LOG` が未設定のままなら emit をスキップする。`EMIT_ISSUE_NUMBER` には判定対象の候補 Issue 番号 (呼び出し元スキル自身の Issue 番号ではない) が入る — retire 候補集計 (`/audit stats --retention` Section 11、`scripts/collect-opportunistic-retire-candidates.sh`) で意味を持つのはこちらの値のため。

3. `scripts/collect-opportunistic-retire-candidates.sh` を新規作成する (→ supports acceptance criteria 3, 6):
   - Usage: `collect-opportunistic-retire-candidates.sh [SESSIONS_DIR] [--threshold N]` (`SESSIONS_DIR` 省略時 `docs/sessions`、`--threshold` 省略時 `1` — 実際の閾値フィルタは呼び出し元の `skills/audit/SKILL.md` 側で行う。`collect-recovery-candidates.sh` と同じ役割分担)
   - 処理: `find "$SESSIONS_DIR" -mindepth 2 -maxdepth 2 -name events.jsonl` で全セッションログを列挙し `cat` で連結 (該当ファイルなしなら空出力・exit 0) → `jq -s` で `.event == "opportunistic_verify_result"` のみ抽出 → `group_by([.issue, .ac_index])` でグルーピング → 各グループを `.ts` 昇順ソートし、末尾から `result == "SKIP"` が連続する件数 (trailing SKIP streak) を算出 (末尾が PASS/FAIL なら 0) → `--threshold` 以上のグループのみ、trailing streak 降順で出力
   - 出力: 1 行 1 候補、タブ区切り `<issue>\t<ac_index>\t<skill>\t<trailing_skip_count>\t<total_observations>` (`skill` はグループ内最新イベントの値)。該当なしは空出力・exit 0
   - jq 実装の骨子 (trailing streak 算出部分):
     ```
     .sorted_results | reverse
     | reduce .[] as $r ({stop:false, count:0};
         if .stop then . elif $r == "SKIP" then .count += 1 else .stop = true end)
     | .count
     ```
   - 引数エラー (存在しない `SESSIONS_DIR` 等) は空出力・exit 0 として扱う (`collect-recovery-candidates.sh` の「ファイル未存在時は空出力」方針を踏襲。ログが1件も無いのは正常系のため)

4. `tests/collect-opportunistic-retire-candidates.bats` を新規作成する (→ acceptance criteria 6): `collect-recovery-candidates.bats` と同様、`BATS_TEST_TMPDIR` 配下にインラインで `<tmpdir>/session-a/events.jsonl` 等のフィクスチャを作成する形式。最低限のシナリオ:
   - `SESSIONS_DIR` が存在しない → 空出力・exit 0
   - 単一グループ、全件 SKIP、件数 >= threshold → 出力に含まれる
   - 単一グループ、末尾が PASS (末尾より前は SKIP) → trailing_skip は 0 として算出され、`--threshold 1` でも出力から除外される
   - 複数グループ → trailing_skip 降順でソートされて出力される
   - `--threshold` 未満のグループ → 出力から除外される
   - `.event` が `opportunistic_verify_result` 以外のイベント混在ログ → 無視される (集計対象外)

5. `skills/audit/SKILL.md` を編集する (→ acceptance criteria 3, 4)。あわせて `docs/structure.md` / `docs/ja/structure.md` の Steering Docs sync candidate 対応も本 Step で行う (Issue 本文に対応する AC が無い SHOULD レベルの改善のため、専用の Pre-merge verify command は追加しない):
   - `allowed-tools` frontmatter の `${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` の直後に `, ${CLAUDE_PLUGIN_ROOT}/scripts/collect-opportunistic-retire-candidates.sh:*` を追加
   - `#### Section 10: Recovery Candidate Frequency` の末尾 (「This section is read-only display only...」の行) の直後、`#### Retire-Proposal Comment Posting` の直前に、次の新セクションを挿入する:

     ````markdown
     #### Section 11: Opportunistic Verify Retire Candidates

     Aggregate `opportunistic_verify_result` events (emitted by `modules/opportunistic-verify.md`, see `modules/event-emission.md`) recorded across all committed sessions, to report acceptance conditions whose most recent judgments are all `SKIP` as retire candidates.

     1. Run:
        ```bash
        ${CLAUDE_PLUGIN_ROOT}/scripts/collect-opportunistic-retire-candidates.sh docs/sessions --threshold 5
        ```
        (閾値は固定値 5 — `.wholework.yml` では設定不可。理由: 本リポジトリの既存の retention 閾値 (Section 8/9 の phase/verify dwell 30/60/90 日、Icebox dwell 90/180 日) も固定値運用の実績があり、`opportunistic_verify_result` の実データがまだ蓄積されていない段階で設定項目を増やす必要は薄いため。実データが蓄積した段階で `.wholework.yml` 設定可能化を再検討する)
     2. `docs/sessions/` が存在しない、またはコマンドが出力なしの場合: "No opportunistic verify retire candidates found." と表示しこのセクションの残りをスキップする
     3. 出力 (`<issue>\t<ac_index>\t<skill>\t<trailing_skip_count>\t<total_observations>` 1行1候補) から次を算出する:
        - **Retire candidate count**: 出力行数の合計
     4. 次の表を表示する:

        | Metric | Value | Threshold | Status |
        |--------|-------|-----------|--------|
        | Opportunistic verify retire candidates (>= 5 consecutive SKIP) | N | > 0 | OK / NOTIFY |

     5. retire candidate が1件以上あれば、各候補を Issue 番号・`ac_index`・skill・trailing SKIP streak 件数・総観測件数とともに列挙する

     This section is read-only display only — no comment posting or Issue creation (Section 10 と同じスコープ制限。実際の AC retire・再型付けの判断は人手、または #1158/#1165 系のフォローアップ Issue に委ねる)。
     ````

   - `docs/structure.md` の Directory Layout ツリー、`scripts/` 行のファイル数コメントを `(76 files)` → `(78 files)` に更新する (実測値ベース、詳細は Notes 参照)
   - `docs/structure.md` の Key Files > Scripts > Project utilities、`collect-recovery-candidates.sh` エントリの直後に次を追加する: `` - `scripts/collect-opportunistic-retire-candidates.sh` — aggregate `opportunistic_verify_result` events from committed `docs/sessions/*/events.jsonl`; group by (issue, ac_index) and report groups whose most recent consecutive judgments are all `SKIP` (trailing-SKIP streak), for `/audit stats --retention` Section 11 ``
   - `docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/structure.md` に上記2点の変更を日本語で反映する (対応英語箇所は `docs/ja/structure.md` の該当行 — L114 付近の `scripts/` ファイル数コメント、L195 付近の `collect-recovery-candidates.sh` 相当セクション)

## Alternatives Considered

- **集計データソースを `.tmp/auto-events.jsonl` にする案**: 不採用。同ファイルは gitignore 対象かつセッションローカルで過去データを保持しない。#1135・#913・#904 の各 Spec が同じ理由でコミット済み `docs/sessions/*/events.jsonl` を採用しており、本 Issue も同じ判断を踏襲する
- **`skills/audit/SKILL.md` に集計ロジックを直接 jq ワンライナーで書き、専用スクリプトを新設しない案**: 不採用。Issue 本文が「Section 10 の `collect-recovery-candidates.sh` パターンをそのまま踏襲できる」と明示しており、trailing-SKIP-streak 算出はテスト価値の高いロジック (境界値: 末尾が PASS/FAIL でのリセット、閾値ちょうど等) のため、bats でテスト可能な専用スクリプトとして切り出す方が測定基盤としての信頼性が高い

## Verification

### Pre-merge
- <!-- verify: rubric "modules/opportunistic-verify.md の Processing Steps に、判定結果 (PASS/FAIL/SKIP) を opportunistic_verify_result イベントとして emit する手順が追加されている。AUTO_EVENTS_LOG 未設定時に skip するガードを含むこと" --> 判定結果の emit 手順が `opportunistic-verify.md` に追加されている
- <!-- verify: file_contains "modules/opportunistic-verify.md" "opportunistic_verify_result" --> `opportunistic-verify.md` にイベント名が記載されている
- <!-- verify: rubric "skills/audit/SKILL.md に、opportunistic_verify_result イベントを集計して連続 SKIP 回数の多い AC を retire 候補として報告するセクションが追加されている。閾値の決め方が記述されていること" --> `/audit` に retire 候補の報告セクションが追加されている
- <!-- verify: file_contains "skills/audit/SKILL.md" "opportunistic_verify_result" --> `audit/SKILL.md` にイベント名が記載されている
- <!-- verify: rubric "イベント件数の増加 (候補 N 件 × skill 実行ごと) に対する方針が Spec または実装コメントに記録されている。1 件ずつ emit するか集約するかの判断根拠を含むこと" --> イベント件数増加への方針が記録されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する

### Post-merge
- 次回以降の `/auto` 完走後、`.tmp/auto-events.jsonl` に `opportunistic_verify_result` イベントが記録され、`jq` で skill 別・result 別に集計できることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **SPEC_DEPTH=light 自動判定**: Size=M (pr route) のため `--light`/`--full` 未指定でも light に auto-detect。Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) は light のためスキップ。Issue 本文の曖昧ポイントは `/issue` フェーズで既に自動解決済み (下記2点)、`/spec` 側での追加解決は不要だった
- **イベント件数増加への方針 (acceptance criteria 5 対応)**: 1 件ずつ emit し集約はしない。理由: #1159 の `retro_proposal_classified` が同種の「複数候補の判定結果」を 1 proposal = 1 event の粒度で運用しており、`/audit` 側の集計もこの粒度を前提にした実績がある。集約案 (`result=SKIP` の候補番号を配列で1イベントに持たせる等) は `/audit` 側の集計ロジックを複雑化させる一方、JSON サイズ増という懸念自体は解消しない。Issue 本文の Auto-Resolved Ambiguity Points で既に確定済みの判断であり、本 Spec はこれを implementation Step 1/2 に落とし込んだ
- **retire 候補の閾値 (固定値 5)**: Issue 本文で既に確定済み。同じ `/audit` 内の phase/verify dwell 閾値 (30/60/90 日、Section 8) も固定値運用の実績があり、実データ蓄積前に `.wholework.yml` の設定項目を増やす必要は薄いため
- **データソース設計判断**: `/audit` の集計対象は `.tmp/auto-events.jsonl` ではなくコミット済み `docs/sessions/*/events.jsonl` (glob) とした。前者は gitignore 対象・セッションローカルで過去データを保持しない。`docs/spec/issue-1135-external-kill-root-cause.md`・`docs/spec/issue-913-notable-judgment-jq-summary.md`・`docs/spec/issue-904-token-usage-model-unknown.md` の3件が同じ理由で同じデータソースを採用しており、本 Issue も踏襲した
- **`ac_index` の算出方法**: 候補 Issue 本文の全チェックボックス行 (`^- \[[ xX]\]`、pre-merge + post-merge 通し) における 1-based 位置とし、`scripts/gh-issue-edit.sh --checkbox` / `scripts/check-pre-merge-ac.sh` と同じ global-index 規約に揃えた。`scripts/opportunistic-search.sh` の出力 (`{"number": N, "condition": "text"}`) には index が含まれないため、emit 時に Step 1/2 で既に取得済みの Issue 本文から LLM が数え上げて決定する (新規スクリプト化はしない — Step 2 自体が AI Retrospective による LLM 判定のため、emit もその場で LLM が行う一体の処理と位置づけた)
- **呼び出し元 5 スキル (`/issue`/`/spec`/`/code`/`/review`/`/verify`) の SKILL.md は変更不要と判定**: `modules/opportunistic-verify.md` は "Read and follow" パターンで呼ばれる共有モジュールであり、Step 3 が必要とする「呼び出し元スキル自身の Issue/PR 番号」は各呼び出し元が実行時点で既に自身のコンテキストとして保持している (5 スキルとも Issue 番号または PR 番号を主引数として動作するため)。呼び出し元 SKILL.md 側での明示的な受け渡し記述の追加は不要と判断した。`/review` は PR 番号から Issue 番号への解決を自身のフローの中で opportunistic-verify.md 呼び出し (SKILL.md L894) より前に既に完了させている
- **`docs/structure.md` の `scripts/` ファイル数コメント**: 実測 (`ls scripts/*.sh scripts/*.py | wc -l`、`scripts/git-hooks/` 配下は Directory Layout で別行のため除外) は本 Issue 着手前時点で 77 件、ドキュメント記載は「(76 files)」で既に 1 件分の既存 drift があった。本 Issue で 1 件追加するため、実測ベースで正しい値「(78 files)」に更新する (既存 drift の補正を兼ねる)
- **`docs/structure.md` の `tests/` ファイル数コメントは今回更新しない**: 実測 (`ls tests/*.bats | wc -l`) は本 Issue 着手前時点で 110 件、ドキュメント記載は「(95 files)」で 15 件分の既存 drift があるが、この drift は本 Issue 提出前から存在する無関係な蓄積であり、Step 10 の file count 更新指示は明示的に `modules/` と `scripts/` のみを対象としている (`tests/` は対象外)。本 Issue のスコープを追加テストファイル 1 件の範囲に留めるため、この既存 drift の是正は対象外とし `/audit drift` 等の別トラックに委ねる
- **`docs/guide/customization.md` / `docs/environment-adaptation.md` は変更不要と判定 (grep で事前確認済み)**: いずれも `.wholework.yml` の `opportunistic-verify: true` という**設定キー**の説明箇所であり、本 Issue はこの設定キーの意味・挙動 (スキル完了時に quick verify command を実行する) を変えない — 判定結果を追加でイベント記録するだけの内部実装強化のため、ユーザー向け設定リファレンスの記述は現状のまま正確である
- **Smoke Test セクションは付与しない**: 本 Issue は MCP ツール呼び出しや外部サービス呼び出しを含まない (`gh`/`jq`/bash のみ) ため対象外
- **UI Design Phase は非該当**: バックエンド/スクリプト/モジュール変更のみで対話的 UI 要素を含まないため `skills/spec/figma-design-phase.md` の Auto-detection Criteria に従いスキップした
- **Pre-merge Verification 6件は Issue 本文の Acceptance Criteria と完全一致**: Verify command sync rule に従い verbatim コピーした。Implementation Step 5 に含めた `docs/structure.md`/`docs/ja/structure.md` の Steering Docs sync candidate 対応は、Issue 本文に対応する AC が無い SHOULD レベルの改善のため、独自の Pre-merge verify command は追加していない (Count alignment は 6/6 で警告なし)

## Consumed Comments
- saito (MEMBER, first-class): `/issue --non-interactive` による Issue Refinement の Issue Retrospective。Background のコード参照 (`modules/opportunistic-verify.md` の判定フロー、`skills/verify/SKILL.md` Step 14、#1159 の `retro_proposal_classified` イベント) を grep で事実確認済みで正確だったこと、Size M (検出上限3) に対し曖昧ポイント2件 (イベント emit 粒度、retire 候補の閾値) を自動解決3条件 (既存パターンから一意推論可能・過去の類似判断が存在・AC 本文が選択に非依存) を満たすとして自動解決したこと、AC 構成・整合性チェック (checkbox format 等) は違反なしだったことを記録。本 Spec はこの自動解決結果 (1件ずつ emit、閾値固定値5) をそのまま設計に反映した — https://github.com/saitoco/wholework/issues/1236#issuecomment-5213997574

## Code Retrospective

### Deviations from Design
- **`skills/issue/SKILL.md` / `skills/review/SKILL.md` の `allowed-tools` に `emit-event.sh` を追加した**: Spec Notes は「呼び出し元 5 スキルの SKILL.md は変更不要」と判定していたが、`scripts/validate-skill-syntax.py` の cross-file validation が `modules/opportunistic-verify.md` から新たに参照される `emit-event.sh` について、それを read する `/issue` と `/review` の `allowed-tools` に欠落があると実際に検出した (`/code`/`/spec`/`/verify` は既存の `retro_proposal_classified` 用途で既に `emit-event.sh:*` を持っていたため検出されなかった)。Spec の判定は「呼び出し元スキル自身の Issue/PR 番号の受け渡し記述」の要否についてのものであり、`allowed-tools` の要否は別軸の懸念だったため、Spec の判断自体は誤りではないが、スコープの見落としがあった。cross-file validation がこの見落としを機械的に捕捉した

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Fixed the 1 MUST finding (`modules/opportunistic-verify.md` Step 3's `ac_index` computation referenced an Issue body never fetched in Step 1/2) and both SHOULD findings (dangling `## Notes` cross-reference; Japanese text in `modules/event-emission.md` violating CLAUDE.md's English-for-module-docs convention), plus 3 of 5 CONSIDER findings (Japanese text in `skills/audit/SKILL.md` / `scripts/emit-event.sh`; missing `--threshold` argument/numeric validation and hard-failing `jq` pipeline in `scripts/collect-opportunistic-retire-candidates.sh`) — all confirmed independently by 3 review agents and 8 verification passes before fixing
- Used the static Task fan-out (Agent tool, `run_in_background: false`) instead of the Workflow-tool path for Step 10, despite `capabilities.workflow: true` being set: `skills/review/SKILL.md` has `context: fork` and ARGUMENTS carried `--non-interactive`, so `workflow-guidance.md`'s Pre-flight section correctly routed away from the Workflow tool (no re-invocation guarantee in this execution surface)
- Ran the Base Branch Conflict Pre-check and confirmed via an actual test merge (`git merge --no-commit --no-ff origin/main`, aborted afterward) that all 4 `changed in both` files auto-resolve cleanly with both sides' content preserved — no MUST finding from that check
- Left 2 CONSIDER findings unfixed as genuine scope-reduction decisions (not oversights): `ac_index`'s position-based grouping key drifting if Issue body checkboxes are edited (larger design change — condition-text hash — deferred as a follow-up), and 3 minor documentation-consistency nits (call sites not stating Issue/PR number explicitly, `docs/structure.md` missing an event-emission annotation, `skills/audit/SKILL.md` frontmatter description not extended) — all verified safe/cosmetic, not correctness gaps

### Deferred Items
- Post-merge observation AC (`.tmp/auto-events.jsonl` に `opportunistic_verify_result` が記録され集計可能であることの確認) remains deferred to the next `/auto` run, per the Issue's own `session=next` verify-type — unchanged from the code phase's handoff, still unresolvable within `/review`
- `scripts/collect-opportunistic-retire-candidates.sh`'s `ac_index` position-based grouping key risk (see Key Decisions above) is deferred as a possible follow-up Issue, not fixed in this PR
- `gh-pr-review.sh`'s self-review 422 fallback detection is broken (see review retrospective below) — not fixed in this PR since it's out of scope for Issue #1236; flagged for retro-proposal aggregation in the next `/verify`

### Notes for Next Phase
- `/merge` should confirm the 3 fix commits (pushed after the initial review post) are included in the merge — CI re-ran green on all 9 jobs after the fixes
- No AC/policy changes were made during fix work; Step 13 concluded no Issue body update is needed

## review retrospective

### Spec vs. implementation divergence patterns
- The Spec-level defect that produced this PR's only MUST finding (`ac_index` computed from an Issue body never fetched in Step 1/2) was not caught by the Spec's own AC verify commands — the `rubric` checks for AC1/AC5 confirmed the *textual presence* of the emit procedure and its rationale, but none of the 6 Pre-merge conditions asserted the procedure's internal logical consistency (that every referenced data source is actually available at the point it's used). This is a structural blind spot for `rubric`-based verification of multi-step Processing Steps text: a rubric can confirm "a step exists that does X" without confirming "X is executable as written." No corrective action taken in this PR (out of scope), but future Specs for shared modules with sequential Processing Steps could benefit from an explicit AC asserting step-to-step data-dependency correctness, not just presence.

### Recurring issues
- Japanese text leaking into English-designated documentation (module docs, skill docs, source comments) recurred across 3 separate files in this single PR (`modules/event-emission.md`, `skills/audit/SKILL.md`, `scripts/emit-event.sh`), all following the same pattern: content was transcribed near-verbatim from the (correctly Japanese, per CLAUDE.md) Spec Notes/Issue body rationale into shipped English-designated artifacts, without a translation step. This is the second Issue in recent history where Spec-to-shipped-doc transcription introduced a language violation (cf. `skills/review/skill-dev-recheck.md`'s existing "Transcription Divergence Check" for spike-report aspirational-language drift, a related but distinct check). No corrective action taken in this PR; worth considering whether a similar transcription check could cover Japanese-in-English-designated-files specifically, since `check-forbidden-expressions.sh` does not check language.

### Acceptance criteria verification difficulty
- No difficulty in this PR's own 6 Pre-merge conditions (all cleanly PASS via `rubric`/`file_contains`/`github_check`) — the difficulty surfaced instead in Step 10 code review (see above), not Step 8 AC verification.
- Incidentally discovered, unrelated to this Issue's own ACs: `scripts/gh-pr-review.sh`'s self-review 422 fallback detection is broken due to a redirection-order bug (`API_STDERR=$(... 2>&1 >/dev/null)` — GitHub's REQUEST_CHANGES-on-own-PR error detail is written to the API response body on **stdout**, not to `gh`'s own stderr, so the fallback's `grep -qi "request changes on your own pull request"` never matches against the captured `API_STDERR`, which only ever contains the generic `gh: Unprocessable Entity (HTTP 422)` line). This means `/review` posting a MUST-containing review on a self-authored PR (the common case for this project's fully-autonomous `/auto` runs) always hits the "Error: failed to post review" hard-fail path instead of the intended COMMENT fallback — confirmed by direct reproduction against PR #1252 in this session, and worked around manually by replicating the script's own fallback logic outside the script. This is a real, currently-live tooling defect outside Issue #1236's scope; flagged here for `/verify`'s retro-proposal aggregation rather than fixed inline.
