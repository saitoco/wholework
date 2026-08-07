# Issue #1167: verify: manual AC 区分 C (故障注入 2 件) を bats テスト化し D1 (UI 目視 5 件) の manual 維持を記録

## Overview

親 Issue #1158 (`phase/verify` に滞留する `verify-type: manual` の post-merge AC 79 件の再型付け・retire) の分割 sub-issue。`docs/stats/2026-08-05.md` Section 10 の分類 6 区分のうち、区分 **C (故障注入、2 件: #1066 #1060)** と区分 **D1 (UI 目視、5 件: #1059 #709 #548 #442 #441)** を担当する。

- **C**: 各 Issue の post-merge manual AC が要求する「意図的に X を失敗させて確認する」シナリオの、機械的に決定可能な核 (deterministic core) を bats テストとして追加し、AC を `verify-type: auto` (verify command 付き) へ変更する。
- **D1**: FleetView 表示・preview 実送信・視覚的差分確認など真に人間の目 (または実環境) を要する 5 件について、`manual` のまま維持する判断根拠を Issue 単位で記録する。

`Blocked by #1157` は解消済み (#1157 は 2026-08-04 に CLOSED、`gh-check-blocking.sh` / `get-blocked-by.sh` の両方が「オープンなブロッカーなし」を返す)。

## Consumed Comments

### code phase

cutoff: 2026-08-07T03:25:23Z (`phase/code` ラベル付与の timeline イベント)。

新規コメントなし (cutoff 以前の 1 件のみ存在)。Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャン結果も該当なし。

### spec phase

cutoff: 未確定 (`phase/*` ラベル付与の timeline イベントが存在せず、`.tmp/auto-events.jsonl` にも本 Issue の `phase_start` イベントが見つからなかったため、フォールバック B によりベストエフォートで全コメントを対象としたが、該当コメント自体が 0 件だった)。

新規コメントなし (`gh issue view 1167 --json comments` の結果が空)。Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャン結果も該当なし。

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1167#issuecomment-5213587282
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1167#issuecomment-5213692052
## Changed Files

- `tests/wait-ci-checks.bats`: 変更 — `bucket: "fail"` の check 1 件 (`pending` なし) をモックし、(a) ポーリングループが 1 回目の poll で即座に break すること (`sleep 60` に到達しない)、(b) `ci_result:` 行が `failed=1` を正しく報告することを検証するテストを追加。`skills/code/SKILL.md` Step 13 の fix loop Row 1 (`failed>0` → fix loop へ進む) が依存する決定的シグナルの回帰テスト (#1066 の故障注入シナリオの機械的な核)
- `tests/check-pre-merge-ac.bats`: 変更 — Pre-merge チェックボックスが 3 件中ちょうど 1 件未チェック (Post-merge の未チェックは含まない) のケースをモックし、`unchecked_count=1` と正しい 1-based index を検証するテストを追加。`skills/merge/SKILL.md` Step 1 の pre-merge AC ゲートが依存する決定的シグナルの回帰テスト (#1060 の故障注入シナリオの機械的な核)
- `docs/reports/manual-ac-retype-c-d1.md`: 新規作成 — 区分 C 2 件のマッピング表 (Issue / 条件文要約 / 追加したテスト / 選定根拠) と区分 D1 5 件の維持根拠表 (Issue / 条件文要約 / manual 維持の理由)。Pre-merge AC1/AC3 が `rubric` タイプであり、`modules/verify-executor.md` の定義上 grader は Issue 本文・git diff・rubric 本文で名指ししたファイルしか見えない (Spec ファイルも Issue コメントも見えない) ため、この記録ファイルがないと AC1/AC3 が原理的に評価不能になる (#1163 の同型判断を踏襲。詳細は Notes 参照)
- リポジトリ外 (GitHub Issue 本文、非追跡):
  - `#1066`: post-merge manual AC 行の `<!-- verify-type: manual -->` を `<!-- verify: command "bats tests/wait-ci-checks.bats" -->` 付与 + `<!-- verify-type: auto -->` へ変更 (人間可読テキストは変更しない)
  - `#1060`: post-merge manual AC 行の `<!-- verify-type: manual -->` を `<!-- verify: command "bats tests/check-pre-merge-ac.bats" -->` 付与 + `<!-- verify-type: auto -->` へ変更 (人間可読テキストは変更しない)
  - `#1167` (本 Issue 自身): post-merge AC の文言を「7 件減少」から実態に合わせて修正 (Notes 参照)
- `docs/structure.md`: 変更不要 — Directory Layout に `docs/reports/` は既出 (62行目)。Key Files は「スクリプトが消費する report ファイル」のみ列挙する方針で、本記録ファイルは消費側スクリプトを持たないため対象外 (`grep -n "reports/" docs/structure.md` で確認済み)
- `docs/translation-workflow.md`: 変更不要 — `docs/reports/` は § Exclusions で明示的に翻訳対象外 (確認済み)

## Implementation Steps

1. `tests/wait-ci-checks.bats` に、`gh pr checks` モックが `[{"name":"Deploy preview","state":"FAILURE","bucket":"fail"}]` (check 1 件、`pending` バケットなし) を返すテストケースを追加する。`scripts/wait-ci-checks.sh:71-73` の `_pending -eq 0` 早期 break パスが 1 回目の poll で発火し、`sleep 60` に到達せず完了することと、`ci_result: total=1 passed=0 failed=1 pending=0 cancelled=0 zero_checks=false` が出力されることを確認する (→ 受入条件1)
2. (parallel with 1) `tests/check-pre-merge-ac.bats` に、既存の `make_gh_mock_body` ヘルパを使い Pre-merge 3 件中 1 件のみ未チェック (Post-merge 側の未チェックは含めない) の Issue 本文をモックするテストケースを追加する。`unchecked_count` が `"1"`、`unchecked_indices` が未チェック項目の 1-based index と一致することを確認する (→ 受入条件1)
3. (after 1, 2) `bats tests/` を実行し、新規 2 件を含む全件が PASS することを確認する (→ 受入条件4)
4. (after 3) `docs/reports/manual-ac-retype-c-d1.md` を新規作成する。「区分 C: bats テスト化マッピング」節に #1066 / #1060 の条件文要約・追加したテスト名・選定根拠を記録し、「区分 D1: manual 維持根拠」節に #1059 / #709 / #548 / #442 / #441 の条件文要約と manual を維持する理由 (下記 Notes の各理由を転記) を Issue 単位で記録する (→ 受入条件1, 受入条件3)
5. (after 3, parallel with 4) `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh` を使い Issue 本文を更新する:
   - `#1066`: post-merge manual AC 行に `<!-- verify: command "bats tests/wait-ci-checks.bats" -->` を先頭付与し、末尾の `<!-- verify-type: manual -->` を `<!-- verify-type: auto -->` へ置換
   - `#1060`: post-merge manual AC 行に `<!-- verify: command "bats tests/check-pre-merge-ac.bats" -->` を先頭付与し、末尾の `<!-- verify-type: manual -->` を `<!-- verify-type: auto -->` へ置換
   - `#1167` (本 Issue 自身): post-merge AC の文言を Notes 記載の修正後テキストへ置換
   (→ 受入条件2)

## Verification

### Pre-merge

- <!-- verify: rubric "区分 C の 2 件 (#1066 / #1060) について、条件が要求する故障注入シナリオを検証する bats テストが tests/ 配下に追加されている" --> C の 2 件が bats テスト化されている
- <!-- verify: rubric "bats テスト化した 2 件の post-merge AC が、テストによる担保を根拠に retire (phase/done 遷移) されているか、または verify command 付きの自動判定 AC へ変更されている" --> C の 2 件の AC が処理されている
- <!-- verify: rubric "区分 D1 の 5 件 (#1059 / #709 / #548 / #442 / #441) について、manual のまま維持する判断根拠が Issue 単位で記録されている" --> D1 の 5 件の manual 維持根拠が記録されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- 移行完了後の `/audit stats --retention` で、`#1066` と `#1060` (区分 C の 2 件) が Manual waiting の集計対象 (`phase/verify` かつ未チェックの `verify-type: manual` 行) から外れていることを個別に確認する。区分 D1 の 5 件 (`#1059` `#709` `#548` `#442` `#441`) は意図して `manual` のまま維持するため Manual waiting 件数に残り続けるのが正しい挙動であり、減少数には含めない <!-- verify-type: observation event=auto-run -->

## Notes

### 追加する bats テストの入力データ形式

- `tests/wait-ci-checks.bats` (新規テスト、Implementation Step 1): 既存テストと同じ `$MOCK_DIR/gh` 差し替え方式。`gh pr checks` 呼び出しに対し `echo '[{"name":"Deploy preview","state":"FAILURE","bucket":"fail"}]'` を返す (check 1 件、`bucket` は `"fail"` のみで `"pending"` を含まない JSON 配列)
- `tests/check-pre-merge-ac.bats` (新規テスト、Implementation Step 2): 既存の `make_gh_mock_body` ヘルパ (heredoc で Issue 本文を渡す) を使用。`### Pre-merge (auto-verified)` 配下に `- [x]` 2 件 + `- [ ]` 1 件、`### Post-merge` 配下は `- [ ]` を含めない (Post-merge 側の未チェックが index に混入しないことを確認済みの (b) との差分を明確にするため)

### post-merge AC の文言修正 (「7 件減少」→ 実態に合わせた表現)

Issue 本文の post-merge AC は「phase/verify の Manual waiting 件数が移行前 (79 件) から**7 件減少**していることを確認する」と記載されているが、`skills/audit/SKILL.md` の Manual Waiting Count 定義 (「`phase/verify` ラベルの Issue のうち、未チェックかつ `verify-type: manual` を含む行を持つ Issue 数」) に照らすと、本 Issue で実際に Manual waiting から外れるのは区分 C の 2 件 (#1066 / #1060、`auto` へ retype) のみである。区分 D1 の 5 件は Purpose 自体が「manual のまま維持」と明記しており、`docs/stats/2026-08-05.md` の棚卸し方針表も D1 を「manual のまま維持 (正当)」としている — 維持根拠を記録しても Issue 本文の未チェック `manual` 行はそのまま残るため、Manual waiting のスキャン条件 (unchecked + `verify-type: manual`) には引き続きヒットし続けるのが意図した挙動である。

この種の「Issue 単位の件数と実際に変動する件数のずれ」は姉妹 sub-issue #1163 (区分 A) が既に遭遇し是正済み — `docs/spec/issue-1163-manual-ac-retype-a.md` の spec retrospective は「Post-merge AC の文言を『34 件減少』→『再型付けした AC 行数分だけ減少』へ修正した。対象外分は減少しないため、旧文言のままなら確実に FAIL していた」と記録している。本 Issue でも同じ理由により、Implementation Step 5 で Issue 本文の post-merge AC 文言を実態 (2 件のみ Manual waiting から外れる) に合わせて修正する。#1163 が個別 Issue 番号の含有確認を件数差分より優先する設計を採用した教訓 (「件数差分だけで判定する設計は将来的に誤検知の余地がある」) も踏襲し、本 Issue の Post-merge Verification は #1066 / #1060 の個別状態確認を一次情報とする。

### なぜ Issue 本文編集のみ (operate route) ではなく記録ファイルを追加するか

Pre-merge AC1・AC3 は `rubric` タイプであり、`modules/verify-executor.md` の定義上 grader が参照できるのは Issue 本文・git diff・rubric 本文で名指ししたファイルのみ (Spec ファイルも Issue コメントも渡らない)。Issue 本文の編集のみでは C・D1 それぞれの詳細なマッピング・根拠を記録する場所がなく、rubric AC が原理的に評価不能になる。姉妹 sub-issue #1163 が同型の制約から operate route を採らず記録ファイル 1 本を追加した前例 (`docs/spec/issue-1163-manual-ac-retype-a.md` Notes 「operate route を採らなかった理由」) に倣い、本 Issue でも `docs/reports/manual-ac-retype-c-d1.md` を Changed Files に含めた。この結果、Changed Files は非空でリポジトリ内ファイルを含むため `modules/size-workflow-table.md` の Diff-less Axis (operate route) 判定基準を満たさず、Size=M の通常マッピングどおり pr route となる。

### 区分 D1 5 件の manual 維持根拠 (`docs/reports/manual-ac-retype-c-d1.md` へ転記する内容)

- **#1059**: 「preview 環境で人間が確認する AC を含む Issue を 1 件通しで実行し、AC が pre-merge セクションに配置され merge 前に確認される流れになることを確認する」— `/issue`→`/spec`→`/code`→`/review` の複数スキルにまたがる実オーケストレーションと実 preview 環境が前提。単一の決定的スクリプトで模擬しようとすると `/issue` の分類判断・実 preview URL・`/review` の提示挙動を同時にモックする必要があり、統合確認としての意味を失う
- **#709**: 「GitHub UI から bug_report テンプレートで Issue を新規起票し、AC セクションが入力欄として表示されることを目視確認」— GitHub の Issue Forms レンダリングは GitHub 側プラットフォームの責務であり、本リポジトリのテスト可能範囲外。ブラウザでの見た目確認が必須
- **#548**: 「koganezawa-com#58 を fullPage で再走し、ページ全体の 3-panel が寸法 throw なく生成される」— 実 downstream リポジトリの実 Web ページに対するブラウザ自動化と実スクリーンショット取得が前提。bats はネットワークアクセスを避けるヘルメティックなテストを原則とし、生成された合成画像自体の品質確認 (throw の有無だけでなく見た目) には目視が必要
- **#442**: 「`/spec` を実行したとき、インタラクティブな UI コンポーネントを含む Issue の Spec に `aria-*` 属性の動的更新 AC が含まれることを確認する」— 任意の将来 Issue に対する LLM の Spec 生成品質 (ガイドラインの適切な反映) という主観的判断が対象。固定 fixture を用いた bats アサーションでは表現できず、rubric も対象となる将来の Spec ファイルを事前に名指しできないため grader の可視範囲制約に抵触する
- **#441**: 「サンプル UI 再現プロジェクトで `visual_diff` を実装し、検出結果が期待通り (差分あり→FAIL、なし→PASS)」— D1 区分の典型例。実ブラウザによる実ページのレンダリング・スクリーンショット取得・pixel-diff 判定の一連の流れが前提で、`pixelmatch` の数値計算のみを固定 fixture でテストしても「実環境で正しく検出できるか」という AC の主旨を代替できない

### #708 / #719 に残る故障注入型 manual AC (本 Issue のスコープ外、要フォローアップ)

姉妹 sub-issue #1163 (区分 A、34 Issue) の全件精査で、#708 (条件1・2) と #719 (条件1) の計 3 AC 行が「故障注入型」に該当し区分 A (observation 再型付け) の対象外と判定された (`docs/reports/manual-ac-retype-a.md` § 対象外)。#1163 の Spec (`docs/spec/issue-1163-manual-ac-retype-a.md`) の Phase Handoff は明示的に「#708 の 2 条件・#719 条件1 の bats テスト化 — 区分 C 相当として #1167 の領域」と記録しているが、**本 Issue (#1167) 自身の Issue 本文は区分 C として #1066 / #1060 のみを挙げており、#708 / #719 には触れていない**。

調査の結果、この 3 条件は技術的には本 Issue の #1066 / #1060 と同型の対応が可能と見られる:
- `#708` 条件1・2: `reconcile-phase-state.sh --check-precondition code-pr/code-patch` の precondition 判定 (Spec 無し M/XS Issue に対する `matches_expected` の真偽) を検証するもの。`tests/reconcile-phase-state.bats` が既存の決定的テスト対象
- `#719` 条件1: `pre-merge-check.sh` の新規 FAILURE 判定 (`NEW_FAILURE: base PASS / head FAIL exits 2`) を検証するもので、**`tests/pre-merge-check.bats` に既に同一シナリオのテストが存在する** (`grep -n "NEW_FAILURE" tests/pre-merge-check.bats`で確認済み) — 追加実装なしで AC を `auto` へ retype できる可能性が高い

ただし、この 3 件は #1158 の sub-issue 分割時点の Issue 番号割り当て (#1163 に含まれる 34 件、#1167 に割り当てられた 7 件) のいずれにも本 Issue の Acceptance Criteria として明記されておらず、非対話モード・light depth での conflict detection ポリシー (`skills/spec/SKILL.md` Step 6: 「note in Spec's Notes section only」) に従い、本 Spec の Implementation Steps・Changed Files には含めない。対応が必要な場合は別途 Issue 起票または #1167 の追加スコープとして扱うことを推奨する。

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜5 は Spec 記載どおりに実施した。

### Design Gaps/Ambiguities

- 実行開始時点で本 Issue のラベルが既に `phase/ready` を経由せず `phase/code` になっており、`reconcile-phase-state.sh --check-precondition code-pr` が `phase/ready` 欠如を警告した。GitHub Timeline を確認したところ、Implementation Step 5 の Issue 本文編集 (`#1066` / `#1060` の verify-type 再型付けと `#1167` 自身の post-merge AC 文言修正) は既にリモートへ適用済みだった一方、bats テスト追加・レポートファイル作成・commit/push/PR はまだ行われていない状態だった — 中断された前回試行 (watchdog kill 等) の痕跡と判断し、Issue 編集を再実行せず Implementation Step 1〜4 のみを完了させる形で処理を継続した。GitHub Issue 編集はローカル worktree のコミット状態と独立して永続化されるため、再開時にどこまで完了しているかを個別に確認する必要がある。
- Worktree 作成時のベース (`origin/main` の session 開始時点スナップショット) が、実装完了時には origin/main から 10 commit 遅れていた (並行セッションによる別 Issue のマージが session 中に進行したため)。`git diff origin/main HEAD` で無関係な削除差分 (他 Issue の Spec/レポートファイル) が大量に出たため、push 前に `git rebase origin/main` を実施して解消した。長時間の non-interactive 実行では、PR 作成直前に origin/main との乖離を確認する一手間が有効。

### Rework

- N/A — 上記のベースドリフトは rebase 1 回で解消し、実装内容 (bats テスト・レポートファイル) への手戻りはなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC ゲート (4件全チェック済み) と review-incomplete-fallback チェック (該当なし) の両方をクリアしたため、確認なしでスカッシュマージを実行した
- `gh-pr-merge-status.sh` が `mergeable=true, reason=clean` を返したため、コンフリクト解消手順 (Step 3) はスキップした

### Deferred Items
- #708 (条件1・2) と #719 (条件1) の計 3 AC 行は、姉妹 sub-issue #1163 の Phase Handoff が「区分 C 相当」と指摘しているが、本 Issue のスコープ外として対応していない (Spec Notes 「#708 / #719 に残る故障注入型 manual AC」参照)。対応候補: `#708` は `tests/reconcile-phase-state.bats` の既存対象、`#719` 条件1 は `tests/pre-merge-check.bats` に既に同一シナリオのテストが存在するため追加実装なしで retype できる可能性が高い
- Post-merge AC (`/audit stats --retention` での #1066 / #1060 個別確認) は本 PR merge 後の観測が前提であり、本フェーズでは未実施

### Notes for Next Phase
- `/verify` は post-merge AC の observation event (`event=auto-run`) に従い、次回 `/auto` 実行時の `/audit stats --retention` 結果を待って判定すること
- BASE_BRANCH=main のため、squash merge により `closes #1167` が Issue を自動クローズする見込み — Step 6 のフォールバック確認で state=CLOSED を検証すること

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — Implementation Steps 1〜5 と PR diff (bats テスト2件・レポートファイル・Spec 追記) は完全に一致していた。review-light agent (Spec 乖離・エッジケース/堅牢性・セキュリティ・ドキュメント整合性の4観点) が指摘なしで完了。

### Recurring issues

Nothing to note — 同種の問題の再発は見られなかった。

### Acceptance criteria verification difficulty

Pre-merge AC1・AC3 は rubric タイプで `docs/reports/manual-ac-retype-c-d1.md` を根拠資料として評価する構成だったが、Phase Handoff の「Notes for Next Phase」に評価対象ファイルの案内が明記されていたため判定に迷いはなかった。AC4 (`bats tests/`) はローカル実行で exit code 0・最終テスト `ok 1510`・`not ok` なしを確認、CI の `Run bats tests` ジョブ SUCCESS とも整合。PR 本文が「1509件」と記載しているのに対し実際のフルスイートは 1510 件だったが、この差は本 PR が新規に bats テストを2件追加したことによる数値の陳腐化であり、AC 判定への影響はない (verify command は件数を固定しない `bats tests/` のみを要求するため)。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC を rubric 3 + `command "bats tests/"` 1 で構成した判断が有効だった。区分 C の本質 (故障注入シナリオのテスト化) は `bats tests/` の実行で機械判定でき、区分 D1 の「manual 維持の判断根拠」という意味論部分だけを rubric に委ねる分担になっていた。
- Spec Notes で **#708 / #719 の 3 AC 行が区分 C 相当でありながら本 Issue のスコープ外である**ことを明示し、対応候補まで調査した上で「別途起票または追加スコープ」を推奨した。非対話モード・light depth の conflict detection ポリシー (Notes 記録のみ) に忠実で、かつ後続が拾えるだけの情報量を残した点が良い。

#### design
- 区分 D1 の 5 件を「manual のまま維持する」判断根拠を Issue 単位で書き下ろした設計により、rubric grader が `docs/reports/manual-ac-retype-c-d1.md` だけを読めば判定できる構造になっていた。

#### code
- レジューム状態 (前回試行が Issue 本文編集まで完了・bats テスト追加以降が未完了) を GitHub Timeline から特定し、Issue 編集を再実行せず残りの Step だけを完了させた判断は正しい。#1163 / #1164 / #1165 と同型のパターンが 4 本目の sub-issue でも再現している。
- worktree のベースが実装完了時点で origin/main から 10 commit 遅れており、`git rebase origin/main` で解消した。並行セッションが多い環境での長時間 non-interactive 実行では、PR 作成直前に origin/main との乖離を確認する一手間が有効という知見が得られた。

#### review
- review-light agent (4 観点) が指摘なしで完了し、Spec と PR diff の乖離もゼロだった。`code-pr` フェーズで Tier 2 fallback catalog による自動 recovery が発生したが、`docs/reports/orchestration-recoveries.md` に記録済みで review 品質には影響していない。

#### merge
- pre-merge AC ゲート (4/4 チェック済み) と review-incomplete-fallback チェックの両方をクリアし、`mergeable=true, reason=clean` で確認なしのスカッシュマージ。`closes #1167` により Issue は自動 CLOSE 済み。

#### verify
- Pre-merge 4 件はすべて `/review` 時点で PASS 済みのため already-checked skip rule により SKIPPED。post-merge の observation AC (`event=auto-run`) は 1 回目の verify では未発火で SKIPPED だったが、同一 `/auto 1158` セッション内で `observation-trigger.sh --event auto-run` を実行して発火させた後、2 回目の verify で PASS 判定に到達し `phase/done` へ遷移した。FAIL / UNCERTAIN は 0 件。
- **post-merge AC を Issue 単位の個別確認として書いた設計が、実際の評価局面で他の sub-issue より明確に優位だった**。#1164 / #1165 / #1166 は「Manual waiting 件数が移行前 (79 件) から N 件減少」という集計値ベースだったため、評価時に baseline 79 の母集団定義 (90 日窓・created ≥ 2026-05-07) を `docs/stats/2026-08-05.md` § 訂正 1 から掘り起こして再現する必要があった (全期間スキャンでは 123 件となり誤判定しうる)。一方本 AC は `#1066` / `#1060` の本文を直接照合するだけで判定でき、母集団定義に依存しない。さらに「D1 の 5 件は意図して manual のまま維持するため減少数には含めない」と除外対象まで明記していたため、残存が正常か異常かの判断も一意だった。**observation AC は集計値の増減ではなく、対象エンティティの個別状態で書くほうが評価可能性が高い**。

### Improvement Proposals

- **#708 (条件1・2) と #719 (条件1) の計 3 AC 行が #1158 の sub-issue 分割からこぼれ落ちている** — 姉妹 sub-issue #1163 (区分 A) の全件精査でこの 3 行が「故障注入型」= 区分 C 相当と判定され、#1163 の Phase Handoff が明示的に「#1167 の領域」と記録した。しかし #1167 自身の Issue 本文は区分 C として #1066 / #1060 のみを挙げており、この 3 行はどちらの sub-issue の Acceptance Criteria にも入っていない。結果として `phase/verify` に滞留し続ける — 親 #1158 が解消しようとしている状態そのものが、分割作業自体の副産物として新たに 3 行残る。`grep -rl "#708" docs/spec/` は 4 ファイルにヒットし、#1163 と #1167 の 2 つの独立した Spec retrospective が同じ欠落を記録している (再発性の機械的確認)。調査済みの対応候補: `#708` 条件1・2 は `tests/reconcile-phase-state.bats` が既存の決定的テスト対象、`#719` 条件1 は `tests/pre-merge-check.bats` に既に同一シナリオのテストが存在するため**追加実装なしで `auto` へ retype できる可能性が高い**。低コストで確実に滞留 3 件を減らせる。
