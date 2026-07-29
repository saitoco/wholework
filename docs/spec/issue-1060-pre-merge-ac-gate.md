# Issue #1060: merge: pre-merge AC 全 PASS を merge のゲート条件にする

## Overview

`/review` が pre-merge AC を UNCERTAIN で終えても merge がブロックされないため、未チェックの pre-merge AC を残したまま merge できてしまう。本 Issue は `/merge` に **pre-merge AC ゲート** を追加し、対象 Issue の `### Pre-merge` 配下のチェックボックスが全てチェック済みであることを merge の前提条件にする。あわせて、`/review` 完了後に残った UNCERTAIN な pre-merge AC を誰がどのフェーズで再検証するかを明文化する。

対応方針は Issue 本文の A (`/merge` ゲート追加) + B-1 (ゲートを検出の単一箇所にする) + B-2 (判断をマーカーコメントとして記録) を採用する。B-3 (UNCERTAIN の MUST 化) は環境要因による過剰ブロックのリスクが Issue 本文に明記されているため不採用。

## Changed Files

- `scripts/check-pre-merge-ac.sh`: 新規。Issue 本文の `### Pre-merge` サブセクション内チェックボックスを走査し、未チェック件数・グローバル 1-based index・条件テキストを JSON 1 行で出力する — bash 3.2+ 互換 (`mapfile`・連想配列は使用しない。awk + jq のみ)
- `tests/check-pre-merge-ac.bats`: 新規。`gh` を PATH モックして本文パターン別の JSON 出力を検証
- `skills/merge/SKILL.md`: frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-pre-merge-ac.sh:*` (Bash パターン) と `Write` を追加 / Step 1 に pre-merge AC ゲートを項目 2 として挿入し既存の項目 2 を項目 3 に繰り下げ / Step 1 内に `#### Post-Review Re-Verification Responsibility` サブセクションを追加
- `skills/review/SKILL.md`: 「FAIL Blocking Behavior」節に、UNCERTAIN は review をブロックしないが未チェックのまま残った pre-merge AC は `/merge` ゲートで検出され再検証は `/review` 再実行が担当する旨を追記
- `modules/l0-surfaces.md`: 「Machine-Readable Event Marker」節に `type=pre-merge-ac-gate` の形式・属性・latest-wins 解決規則を追加
- `docs/structure.md`: Scripts 節 (Project utilities) に `check-pre-merge-ac.sh` の行を追加 / Directory Layout の `scripts/` ファイル数を `(68 files)` → `(69 files)` に変更
- `docs/ja/structure.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に従う)
- `docs/workflow.md`: `### 5. /merge — Merge` にゲートの 1 文を追加
- `docs/ja/workflow.md`: 上記の日本語ミラー同期

**Steering Docs sync candidate (要否は `/code` が各ファイルを読んで最終判断):**

- `modules/phase-state.md`: [Steering Docs sync candidate] `merge` 行の Precondition 列が `PR is OPEN and reviewDecision is APPROVED` のままで、本 Issue が追加する SKILL.md 側ゲートを含まない。`reconcile-phase-state.sh` の precondition 判定は本 Issue のスコープ外 (SKILL.md 内ゲートは別機構) のため変更不要と判断しているが、記述追記の要否を確認すること
- `docs/guide/workflow.md` / `docs/ja/guide/workflow.md`: [Steering Docs sync candidate] `### /merge — Merge the PR` 節にゲートの説明が必要かを確認 (ユーザー向けマニュアル。`grep -rn "/merge" docs/guide/` で該当を確認済み)
- `tests/gh-pr-merge-status.bats` / `tests/run-merge.bats`: [Steering Docs sync candidate] 本 Issue は `gh-pr-merge-status.sh` と `run-merge.sh` を変更しないため更新不要と判断している (grep で両スクリプトへの変更が無いことを確認済み) が、`/code` 側で再確認すること

## Implementation Steps

1. `scripts/check-pre-merge-ac.sh` を新規作成する (→ 受入条件 AC1)
   - **Usage**: `check-pre-merge-ac.sh <issue-number>`
   - **入力**: `gh issue view "$ISSUE_NUMBER" --json body -q .body` の出力
   - **出力 (stdout, JSON 1 行)**: `{"resolved":true,"pre_merge_total":N,"unchecked_count":M,"unchecked_indices":"2,5","unchecked_items":[{"index":2,"text":"..."}]}`
   - **グローバル index の定義**: 本文全体で `^- \[[ xX]\]` に一致する行を先頭から 1 起点で数えた番号。`scripts/gh-issue-edit.sh` の awk パターン (`/^- \[[ xX]\]/`) と完全に同一にすること。これにより `gh-issue-edit.sh --checkbox` および `modules/l0-surfaces.md` の `ac=` 属性と index が相互運用できる
   - **Pre-merge サブセクションの範囲**: `^### Pre-merge` に一致する見出し行の次行から、次に現れる `^## ` または `^### ` の行の直前まで
   - **`text` の生成**: チェックボックス行から先頭の `- [ ] ` / `- [x] ` マーカーと全ての `<!-- ... -->` HTML コメントを除去し、前後の空白を trim した文字列
   - **分岐全列挙 (exhaustive)**:
     - 引数が 1 個でなく、または正の整数でない: usage を stderr に出力し exit 1
     - `gh issue view` が非ゼロ終了、または本文が空: `{"resolved":false,"pre_merge_total":0,"unchecked_count":0,"unchecked_indices":"","unchecked_items":[]}` を出力し exit 0 (fail-open。`run-merge.sh` の `pre-merge-check.sh` と同じ方針)
     - `^### Pre-merge` 見出しが存在しない (セクション分割していない Issue 本文): `resolved":true` かつ `pre_merge_total:0` を出力し exit 0。ゲートは no-op になる
     - Pre-merge サブセクション内に未チェック行が 0 件: `unchecked_count:0`、`unchecked_indices:""`、`unchecked_items:[]` を出力し exit 0
     - 未チェック行が 1 件以上: 該当 index を昇順カンマ区切りで `unchecked_indices` に、`{index,text}` の配列を `unchecked_items` に格納して出力し exit 0
   - **bash 3.2 互換**: `mapfile` / 連想配列 / `${var^^}` を使わず、awk でのスキャンと jq での JSON 組み立てのみで実装する
2. `tests/check-pre-merge-ac.bats` を新規作成する (1 の後)
   - `MOCK_DIR` を `PATH` 先頭に置き `gh` をモックする (`tests/gh-pr-merge-status.bats` と同じ方式)
   - ケース (examples): (a) Pre-merge 全チェック済み → `unchecked_count:0` / (b) Pre-merge に未チェック 2 件 + Post-merge に未チェック 1 件 → `unchecked_count:2` かつ Post-merge 行の index が含まれない / (c) `### Pre-merge` 見出し無し → `pre_merge_total:0` / (d) `gh` 失敗 → `resolved:false` かつ exit 0 / (e) 引数不正 → exit 1 / (f) Acceptance Criteria の外側にもチェックボックスがある本文で index が本文全体基準になっている
3. `skills/merge/SKILL.md` の frontmatter `allowed-tools` を更新する (1・2 と並行可)
   - `Bash(...)` リスト内に `${CLAUDE_PLUGIN_ROOT}/scripts/check-pre-merge-ac.sh:*` を追加 (`gh-pr-merge-status.sh:*` の直後)
   - リスト末尾のビルトインツール列挙に `Write` を追加 (マーカーコメント本文を `.tmp/` に書き出すため)
   - `AskUserQuestion` は `validate-skill-syntax.py` の `FORBIDDEN_ALLOWED_TOOLS` に含まれるため追加しないこと
4. `skills/merge/SKILL.md` の `### Step 1: Check PR State` に pre-merge AC ゲートを挿入する (1・3 の後) (→ 受入条件 AC1, AC2, AC4)
   - 挿入位置: 既存の項目 1 (`gh pr view ... --json headRefName,...` と Phase Handoff read) の直後、既存の項目 2 (`Determine mergeability`) の直前。既存の項目 2 は項目 3 に繰り下げ、その直後の mergeable/reason 分岐の箇条書きはそのまま項目 3 の配下に残す
   - 新項目 2 の本文には以下を明記する (見出し文言に `pre-merge AC` の文字列を含めること — AC2 の `section_contains` が参照する)
     - `ISSUE_NUMBER` が抽出できなかった場合はゲートをスキップし `[pre-merge-ac] No related Issue resolved — skipping gate.` を出力して項目 3 へ進む
     - `${CLAUDE_PLUGIN_ROOT}/scripts/check-pre-merge-ac.sh "$ISSUE_NUMBER"` を実行する
     - **分岐全列挙 (exhaustive)**:
       - `resolved` が `false`: `Warning: pre-merge AC state could not be resolved for issue #$ISSUE_NUMBER; proceeding (fail-open).` を出力して項目 3 へ進む
       - `unchecked_count` が `0`: `[pre-merge-ac] All N pre-merge acceptance conditions are checked.` を出力して項目 3 へ進む
       - `unchecked_count` が 1 以上: (a) 記録済み判断の確認 → (b) 提示と判断、の順に処理する
     - **(a) 記録済み判断の確認**: `gh issue view "$ISSUE_NUMBER" --json comments --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=pre-merge-ac-gate"))] | sort_by(.createdAt) | .[-1].body // empty'` で **最新 1 件のみ** を解決する (latest-wins。複数マーカーの `ac=` 集合を統合しない)。そのマーカーが `decision=override` を持ち、かつ `ac=` の index 集合が `unchecked_indices` の全 index を包含する場合のみ、`[pre-merge-ac] Proceeding under recorded override: <reason>` を出力して項目 3 へ進む
     - **(b) 提示と判断**: 未チェック条件を `#<index> <text>` 形式で 1 行ずつ出力したうえで
       - **対話モード**: AskUserQuestion で `Abort merge` (既定) / `Re-run /review to re-verify` / `Approve and merge anyway` を提示する。`Approve` を選んだ場合は理由を聞き取り `decision=override` マーカーを投稿してから項目 3 へ進む。他の 2 択では処理を停止し、以降のいかなる Step にも進まない
       - **非対話モード**: merge しない。`decision=blocked` マーカーを投稿し、`Error: N unchecked pre-merge acceptance conditions on issue #$ISSUE_NUMBER. Merge blocked.` を出力して非ゼロ終了する
     - **マーカー形式**: Write ツールで `.tmp/pre-merge-ac-gate-$ISSUE_NUMBER.md` に本文を書き出す。1 行目は `<!-- wholework-event: type=pre-merge-ac-gate phase=merge issue=$ISSUE_NUMBER decision=blocked ac=<カンマ区切り index> reason="<1 行の理由>" -->` (override 時は `decision=override`)、以降に未チェック条件の人間可読なリストを書く。投稿は `mkdir -p .tmp` → `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh "$ISSUE_NUMBER" .tmp/pre-merge-ac-gate-$ISSUE_NUMBER.md` → `rm -f .tmp/pre-merge-ac-gate-$ISSUE_NUMBER.md` の順
5. `skills/merge/SKILL.md` の Step 1 内に `#### Post-Review Re-Verification Responsibility` サブセクションを追加する (4 の後) (→ 受入条件 AC3)
   - 見出しレベルは h4 (`####`)。`### Step 2` より前、項目 3 の分岐箇条書きの後に置く (h4 なので `section_contains "skills/merge/SKILL.md" "Step 1" ...` の走査範囲内に留まる)
   - 記述内容: (i) `/review` は UNCERTAIN をブロックしないため、pre-merge AC が未チェックのまま `/review` が完了しうる / (ii) その未チェック状態を検出する責務は `/merge` の pre-merge AC ゲート (単一の検出点) が持つ / (iii) **再検証の実行責務は `/review` の再実行が持つ** — CI 発火待ちや外部ツール未導入といった環境要因が解消した後に `/review $PR_NUMBER` を再実行すると Step 8 が PR ブランチに対して再検証しチェックボックスを更新する / (iv) `/verify` は post-merge フェーズであり merge のゲートとしては機能しないため、この再検証責務を負わない / (v) 環境要因が解消しない場合は override マーカーで明示的な判断として記録したうえで merge する
6. `skills/review/SKILL.md` の `### FAIL Blocking Behavior` 節に追記する (4・5 と並行可) (→ 受入条件 AC3)
   - 挿入位置: 既存の `UNCERTAIN, SKIPPED, PENDING, and POST-MERGE classifications do not block review.` の文の直後
   - 記述内容: UNCERTAIN は review をブロックしないが、UNCERTAIN のまま残った Pre-merge 条件はチェックボックスが未チェックのまま残り、`skills/merge/SKILL.md` Step 1 の pre-merge AC ゲートで merge がブロックされる。その解消 (再検証) は `/verify` ではなく `/review` の再実行が担当する
7. `modules/l0-surfaces.md` の `## Machine-Readable Event Marker` 節に `**type=pre-merge-ac-gate**` の小節を追加する (4 と並行可)
   - 記述内容: `/merge` Step 1 のゲートが投稿すること / 属性 `decision=blocked|override`、`ac=<カンマ区切りの 1-based index>` (index の基準は Issue 本文の全 AC 列挙 = `gh-issue-edit.sh --checkbox` と同一)、`reason="<1 行の理由>"` / Issue コメントは append-only のため **最新 1 件のみを解決する (latest-wins)** こと、`decision=override` の `ac=` 集合が現在の未チェック集合を包含する場合にのみゲートを通過させること / 例を 2 つ (blocked / override)
   - `## Trust Boundary` の bot 例外 (`<!-- wholework-event:` を含むコメントは consume する) にそのまま乗るため、Trust Boundary 表の変更は不要
   - Step 2 の「Cross-phase marker exception」への追加は不要 (このマーカーは `/merge` が同一フェーズ内で `gh issue view` により直接解決するため、コメント consume 経路を通らない)
8. `docs/workflow.md` の `### 5. /merge — Merge` に 1 文を追加し、`docs/ja/workflow.md` の対応箇所を同期する (4 の後)
   - 追加内容: squash merge の前に対象 Issue の pre-merge acceptance criteria が全てチェック済みかを検証し、未チェックがある場合は提示して merge をブロックする (記録済み override がある場合を除く)
   - `docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/workflow.md` にコードフェンス数の一致を含めて反映する
9. `docs/structure.md` の Scripts 節 (`**Project utilities:**`) に `check-pre-merge-ac.sh` の行を追加し、Directory Layout の `scripts/` 行を `(68 files)` → `(69 files)` に変更する。`docs/ja/structure.md` も同様に同期する (1 の後)

## Alternatives Considered

| 案 | 内容 | 判断 |
|---|---|---|
| `gh-pr-merge-status.sh` に AC フィールドを追加 (Issue 本文の案) | 既存スクリプトの JSON に `pre_merge_ac_*` を足す | **不採用**。同スクリプトは `scripts/run-code.sh:335` と `modules/orchestration-fallbacks.md` からも消費される PR スコープの共有契約であり、Issue 本文パースを混ぜると無関係な consumer に影響する。また `mergeable:false` に相乗りさせると `/merge` Step 1 の既存分岐 (非対話時は「そのまま merge を試行」に自動解決) に吸収され、ゲートとして機能しない |
| `/merge` ゲート内で verify command を再実行 (B-1 の字義通りの解釈) | 未チェック AC の verify command をその場で再実行 | **不採用**。worktree で PR head を checkout したうえで verify-executor を回す必要があり、`docs/tech.md` が SSoT として定める「merge は機械的操作、`model: sonnet` + `effort: low` で足りる」という決定と衝突する。検出の単一箇所化 (B-1 の意図) はゲートで達成し、再検証の実行は `/review` 再実行に委ねる |
| UNCERTAIN を MUST 扱いにして `REQUEST_CHANGES` (B-3) | `/review` 側でブロック | **不採用**。環境要因の UNCERTAIN で常時ブロックされる懸念が Issue 本文に明記済み |
| `.wholework.yml` にゲート有効/無効の設定キーを追加 | `pre-merge-ac-gate: true/false` | **不採用**。Issue が要求していない。`### Pre-merge` 見出しを持たない Issue 本文では自動的に no-op になり、override マーカーが escape hatch として機能するため、設定キー無しでも過剰ブロックにはならない |

## Verification

### Pre-merge

- <!-- verify: rubric "skills/merge/SKILL.md に、対象 Issue の pre-merge AC が全てチェック済みかを確認するステップが追加され、未チェックがある場合の挙動 (提示・確認・警告のいずれか) が定義されている" --> `/merge` に pre-merge AC ゲートが追加されている
- <!-- verify: section_contains "skills/merge/SKILL.md" "Step 1" "pre-merge AC" --> `/merge` Step 1 に pre-merge AC ゲート関連の記述がある (上記 rubric AC の補助検証)
- <!-- verify: rubric "/review 完了後に UNCERTAIN が残った pre-merge AC を誰がどのフェーズで再検証・チェックするかが明文化されている" --> review 完了後の再検証責務が明確になっている
- <!-- verify: grep "Acceptance" "skills/merge/SKILL.md" --> `skills/merge/SKILL.md` に acceptance criteria への言及がある

### Post-merge

- pre-merge AC を意図的に 1 件未チェックのまま `/merge` を実行し、ゲートが機能することを確認する (verify-type: manual)

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/check-pre-merge-ac.sh:*`: pre-merge AC のチェック状態取得 — `skills/merge/SKILL.md` の `allowed-tools` に **未登録のため追加が必要**
- `gh issue view:*`: override マーカーの解決 — 登録済み
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*`: ゲートマーカーの投稿 — 登録済み

### Built-in Tools

- `Write`: マーカーコメント本文を `.tmp/` に書き出す — `skills/merge/SKILL.md` の `allowed-tools` に **未登録のため追加が必要**
- `AskUserQuestion`: 対話モードでの承認確認 — `validate-skill-syntax.py` の `FORBIDDEN_ALLOWED_TOOLS` に含まれるため `allowed-tools` には **追加しない** (既存の Step 1・Step 3 も同様に未宣言で使用している)

### MCP Tools

- なし

## Uncertainty

- **グローバル AC index の整合性**: ゲートが返す index が `gh-issue-edit.sh --checkbox` および `modules/l0-surfaces.md` の `ac=` 属性と一致するか
  - **検証方法**: `scripts/gh-issue-edit.sh` の awk パターン (`/^- \[[ xX]\]/`、本文全体を対象、行頭一致のみ) を読み取り、新スクリプトで同一パターンを使うことで構成上一致させる。`tests/check-pre-merge-ac.bats` のケース (f) で Acceptance Criteria の外側にチェックボックスがある本文を用いて回帰を防ぐ
  - **影響範囲**: Implementation Steps 1, 2, 4
  - **解決状況**: 解決済み (同一パターン採用で構成上保証)
- **非ゼロ終了が `/auto` に与える影響**: ゲートによる merge 中断が `/auto` の復旧ループを誘発しないか
  - **検証方法**: `skills/auto/SKILL.md` の merge 失敗ハンドリングを確認
  - **影響範囲**: Implementation Steps 4
  - **解決状況**: 解決済み。`skills/auto/SKILL.md` Step 4 の項目 11 は merge 失敗時に completion check (`reconcile-phase-state.sh merge --check-completion`) を行い、`matches_expected` が false なら Step 6 (失敗ハンドリング) へ遷移する。PR が未 merge のままなら completion check も false になるため、ゲートによる中断は既存の「merge phase failure」経路にそのまま乗る (同 SKILL.md の失敗要因リストにも invalid PR state / CI failure が列挙済み)

## Notes

- **AC2 の verify command を修正した**: Issue 本文の元の記述は `section_contains "skills/merge/SKILL.md" "### Step 1" "pre-merge AC"` だったが、`modules/verify-executor.md` の `section_contains` 仕様は「見出し行から先頭の `#` 記号と空白を除去したうえで部分一致」であるため、引数側に `###` を含めると `Step 1: Check PR State` に一致せず恒久的に UNCERTAIN になる。`"Step 1"` に修正し、Issue 本文と Spec の両方を同じ内容に更新した (`modules/verify-patterns.md` §18 「Issue Body Is SSoT」を維持するため、Spec 側だけの書き換えにはしていない)。
- **既存実装との整合確認 (conflict なし)**: Issue 本文 Background の 3 つの事実主張 (`/review` の UNCERTAIN 非ブロック、`skills/merge/SKILL.md` に acceptance criteria への言及が無い、`gh-pr-merge-status.sh` が AC 状態を返さない) を実装と照合し、いずれも一致することを確認した。
- **fail-open 方針**: `check-pre-merge-ac.sh` が Issue 本文を取得できない場合は `resolved:false` を返し、ゲートは警告のみで通過させる。これは `run-merge.sh` が `pre-merge-check.sh` の非ゼロ終了を fail-open で扱っている既存方針と揃えたもの。ゲートの目的は「未検証のまま静かに merge されること」の防止であり、GitHub API 障害で merge 全体を止めることではない。
- **`### Pre-merge` 見出しを持たない Issue 本文**: `pre_merge_total:0` となりゲートは no-op になる。セクション分割していないプロジェクトへの後方互換性を意図した設計であり、`skills/verify/SKILL.md` Step 4 の「セクション分割が無い場合は全条件を pre-merge 扱い」とは意図的に異なる扱いにしている (ゲートは merge をブロックする副作用を持つため、判定できない場合は通す)。
- **`verify-type: manual` な pre-merge AC も対象**: Issue 本文の指示どおり、`ac-tier: preview` / `verify-type: manual` を含む全ての pre-merge チェックボックスをゲートの対象にする。特別扱いはしない。
- **Adapter pattern survey**: 本 Issue の verify command は `rubric` / `section_contains` / `grep` のみで、`modules/verify-executor.md` の組み込み変換表に既に存在する。`docs/environment-adaptation.md` の Extension Guide Step 0 は適用不要。
- **新規外部依存パッケージ**: なし (`awk` / `jq` / `gh` はいずれも `docs/tech.md` の Key Dependencies に既出)。
- **ツール検出パターン**: 本 Issue の Implementation Steps にツール検出 (バージョン確認・MCP ToolSearch・CLI 検出) は含まれない。
- **`.claude/` 配下のファイル変更**: なし (`git add -f` の注意書きは不要)。
- **Mermaid 図の更新**: なし。
- **`docs/structure.md` の tests 件数**: Directory Layout の `tests/` 行は `(95 files)` だが実際は 103 件で、既にドリフトしている。ただし structure.md の維持ルールが件数更新を求めているのは `modules/` と `scripts/` のみのため、本 Issue では `scripts/` の件数のみを更新し tests 件数には触れない。
- **セキュリティ/クレデンシャル**: 本 Issue はクレデンシャル保管・シークレット管理・アクセス制御を扱わないため、`SECURITY.md` / `docs/` のポリシー整合チェックは適用外。

## Consumed Comments

- `saito` / `MEMBER` / first-class / `/issue 1060 --non-interactive` の Issue Retrospective。Triage 結果 (Type=Feature, Size=M→L, Value=4)、Background 事実確認 (3 主張とも codebase と一致)、AC verify command の監査結果、あいまいさの自動解決 3 件 (ゲート挙動は「提示 + 明示的承認がなければ中断」、対応方針は B-1 軸 + B-2 補助、UNCERTAIN のまま merge する場合はコメントに理由を記録) を報告。本 Spec の設計はこの 3 件の自動解決方針を前提として引き継いでいる。 / https://github.com/saitoco/wholework/issues/1060#issuecomment-5112496825
