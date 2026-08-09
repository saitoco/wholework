# Issue #1300: get-auto-session-report: Timeline 表の Size/Route 陳腐化と PR 列の無検証全文検索を修正

## Overview

`scripts/get-auto-session-report.sh` の Sub-Issue Completion Timeline 表に独立した 2 つの不正確性がある。

- **欠陥 1**: `Size/Route` 列の `_route` が `sub_start` イベントの `size` (dispatch 時点のスナップショット) を `case` 文で直接マッピングしており、post-spec の Size 再評価 (`/spec` の Post-Spec Size Refresh) を反映しない。同スクリプトの `ROUTE_MIX` 集計は #1289 で実行フェーズ (`code-pr`/`code-patch`) 由来の導出へ既に修正済みだが、Timeline 表側は修正漏れとして残っている。実測で降格 (#1256 M→XS, #1251 M→S) ・昇格 (#1292 S→M) の両方向で route 誤りが確認されている。
- **欠陥 2**: `PR` 列が `gh pr list --search "closes #N"` (GitHub の全文検索) の先頭ヒットを実 `closes` 参照の検証なしに採用しており、無関係な PR が先頭に来ると誤った番号を報告する。`skills/verify/SKILL.md` Step 2 (#1202) に同種の問題への参照実装 (候補を複数取得し `gh-extract-issue-from-pr.sh` で実 `closes` 参照を検証) が既にある。

両欠陥とも根本原因は異なるが同一の表・同一のスクリプトに存在し、「Timeline 行が実態と一致しない」という同一の症状として現れるため 1 Issue にまとめられている。

## Reproduction Steps

1. `/auto --batch` を、Size が post-spec で再評価される (昇格または降格) Issue を含めて実行する — 例: `sub_start` 時点で Size M と記録された Issue を `/spec` の Post-Spec Size Refresh が XS/S へ降格し、`code-patch` フェーズで実行される。
2. セッション完了後、`scripts/get-auto-session-report.sh <session-id> --metrics-only` で L3 Metrics セクションを生成する。
3. Sub-Issue Completion Timeline 表を確認する: `Size/Route` 列が `M/pr` のように `sub_start` の陳腐化した size を表示し、同じ行の Phase breakdown 列 (`code-patch ...`) や、レポート内の `Route mix` 集計行 (`patch: N, pr: M, ...`) と矛盾する。
4. 別途、merge 済み PR を持たない (patch route の) Issue について、`PR` 列に無関係な PR 番号 (例: `#1090`) が表示されることがある — `gh pr list --search "closes #N"` の全文検索が無関係な PR を先頭に返し、無検証で採用されるため。

## Root Cause

- **欠陥 1** (`scripts/get-auto-session-report.sh:341-346`): `_size` を `sub_start` イベントの `size` から取得した直後、`case "$_size" in XS|S) _route="patch" ;; M|L) _route="pr" ;; *) _route="?" ;; esac` で `_route` を直接マッピングしている。これは post-spec の Size 再評価を一切反映しない dispatch 時点のスナップショットである。同スクリプトの `ROUTE_MIX` (`:170-191`, #1289 で修正済み) は既に `code-pr`/`code-patch` phase イベントの有無から per-issue に route を導出する方式へ切り替わっているが、Timeline 表側の `_route` 導出は同じ修正が適用されずに残っている — 同一の陳腐化した導出元を持つ 2 箇所のうち 1 箇所だけが修正された状態。
- **欠陥 2** (`scripts/get-auto-session-report.sh:368`): `_pr_num=$(gh pr list --search "closes #${_num}" --state all --json number --jq '.[0].number // empty' ...)` が `gh pr list --search` (全文検索、構造化フィルタではない) の先頭ヒットを無検証で採用している。`skills/verify/SKILL.md` Step 2 (#1202 で導入) は同じ問題に対し、候補を最大 10 件取得し `scripts/gh-extract-issue-from-pr.sh` で各候補の実 `closes` 参照を検証してから採用する方式を既に実装しているが、この方式は Timeline 表側には適用されていない。

## Changed Files

- `scripts/get-auto-session-report.sh`: Sub-Issue Completion Timeline 行生成部分を修正 — (1) `_route` 導出を `sub_start.size` の `case` マッピングから、`ROUTE_MIX` (#1289) と同じ実行フェーズ (`code-pr`/`code-patch` イベント) 由来の per-issue 導出へ変更 (`_size` 表示自体は `sub_start.size` のまま据え置き — 対応方針参照)。(2) `PR` 列の解決を、候補 PR の実 `closes` 参照を `gh-extract-issue-from-pr.sh` で検証してから採用する方式へ変更 (`skills/verify/SKILL.md` Step 2 / #1202 と同じ方式)。bash 3.2+ compatible を維持。
- `tests/get-auto-session-report.bats`: 2 件の bats テストを追加 — (1) 全文検索の誤ヒット候補が実 `closes` 参照で不一致の場合に `PR` 列が `—` になることを検証。(2) Size 昇格・降格の両方向のフィクスチャで Timeline 行の route が実行フェーズ側を報告することを検証。

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `_route` 導出を修正する (→ 欠陥 1 / AC1, AC2)
   - `_size=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "sub_start") | .size] | first // "?"' ...)` の直後にある `case "$_size" in XS|S) _route="patch" ;; M|L) _route="pr" ;; *) _route="?" ;; esac` ブロックを除去する。
   - 代わりに、同じループ内で既に計算済みの `$_issue_events` (issue でフィルタ済みの EVENTS_JSON) を使い、`ROUTE_MIX` (`:181-182`) の `has_pr`/`has_patch` 判定と同じ考え方で per-issue に `_route` を導出する:
     ```bash
     _has_pr=$(echo "$_issue_events" | jq -r '[.[] | select(.phase == "code-pr")] | length > 0')
     _has_patch=$(echo "$_issue_events" | jq -r '[.[] | select(.phase == "code-patch")] | length > 0')
     if [[ "$_has_pr" == "true" ]]; then
       _route="pr"
     elif [[ "$_has_patch" == "true" ]]; then
       _route="patch"
     else
       _route="?"
     fi
     ```
   - `_size` 自体 (表示値) は `sub_start.size` のまま変更しない — Issue の Auto-Resolve Log で既に「Size 表示列は `sub_start` の `size` を使い続ける可能性が高い」と判断されている前提を踏襲する。
2. (after 1) `scripts/get-auto-session-report.sh` の `PR` 列解決を修正する (→ 欠陥 2 / AC3)
   - `_pr_num=$(gh pr list --search "closes #${_num}" --state all --json number --jq '.[0].number // empty' 2>/dev/null || true)` を、`skills/verify/SKILL.md` Step 2 の `CANDIDATE_PRS` ループと同じ方式に置き換える:
     ```bash
     _candidate_prs=$(gh pr list --search "closes #${_num}" --state all --json number --jq '.[].number' 2>/dev/null | head -10 || true)
     for _candidate in $_candidate_prs; do
       _candidate_issue=$("$SCRIPT_DIR/gh-extract-issue-from-pr.sh" "$_candidate" 2>/dev/null | jq -r '.issue_number // empty' 2>/dev/null || true)
       if [[ "$_candidate_issue" == "$_num" ]]; then
         _pr_col="#${_candidate}"
         break
       fi
     done
     ```
   - JSON パースは (`skills/verify/SKILL.md` の python3 と異なり) `jq` を使う — このスクリプトは既に jq に全面依存しており python3 への新規依存を避けるため。
   - `_pr_col` の初期値 `—` (既存のデフォルト、`:366`) は変更しない。候補が 0 件、または全候補が不一致の場合はデフォルトのまま `—` を維持する。
3. `tests/get-auto-session-report.bats` に PR 列の誤ヒット防止テストを追加する (after 2) (→ AC4)
   - 既存の「Verify Phase Residuals: issue carrying live phase/verify label is detected」テストと同じ `gh` PATH モック方式を使う。
   - `gh pr list --search "closes #<N>"` が無関係な候補 PR 番号 (例: `1090`) を返し、`gh pr view 1090 --json body,title,baseRefName` がそれとは別の Issue を参照する本文 (例: `closes #1061`) を返すようモックする — Issue 本文に記載された実測 (`/verify 1266` で PR #1090 が誤って返された事例) を再現する。
   - Timeline 行の `PR` 列が `—` になることを assert する。
4. (parallel with 3) `tests/get-auto-session-report.bats` に Size 昇格・降格双方向のフィクスチャテストを追加する (→ AC5)
   - 既存の「Route mix: reports the executed code-patch/code-pr phase route...」テストと同様のフィクスチャ形式で、`--no-github` を使う。
   - 1 Issue は `sub_start` size=M で `code-patch` を実行 (降格、#1251 を参考にした番号を使用)、もう 1 Issue は `sub_start` size=S で `code-pr` を実行 (昇格、#1292 を参考にした番号を使用)。
   - Timeline 行がそれぞれ `/patch` と `/pr` を報告することを assert する (`_size` 表示部分はそれぞれ `M`, `S` のまま)。
5. (after 1, 2, 3, 4) `bats tests/get-auto-session-report.bats` を実行し全件 PASS を確認する (→ AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "get-auto-session-report.sh の Sub-Issue Completion Timeline 行生成において、route が sub_start イベントの size フィールドではなく実際に実行されたフェーズを根拠に導出されている" --> Timeline 表の `Size/Route` 列が、`sub_start` イベントの `size` ではなく実行フェーズ (`code-pr` / `code-patch`) に基づく route を報告している
- <!-- verify: file_not_contains "scripts/get-auto-session-report.sh" "XS|S) _route=\"patch\"" --> `sub_start` の `size` を route 判定に直接用いている `case "$_size" in ... esac` 形式のマッピングが Timeline 行生成から除去されている
- <!-- verify: grep "gh-extract-issue-from-pr" "scripts/get-auto-session-report.sh" --> `PR` 列が、候補 PR の実 `closes` 参照を検証してから採用する方式になっている
- <!-- verify: rubric "tests/get-auto-session-report.bats に、closes 参照が一致する PR を持たない Issue の Timeline 行で PR 列が — になることを検証するテストが追加されている" --> patch route の Issue (`closes` 参照を持つ PR が存在しない) で `PR` 列が `—` になることを検証する bats テストが追加されている
- <!-- verify: rubric "tests/get-auto-session-report.bats に、sub_start の size と実行 route が食い違うフィクスチャについて、Size 昇格方向・降格方向の双方で Timeline 行が実行 route 側を報告することを検証するテストが追加されている" --> post-spec で Size が再評価された Issue のフィクスチャで、Timeline 行の route が実行 route を報告することを昇格・降格の両方向について検証する bats テストが追加されている (実測: #1251 の M→S 降格、#1292 の S→M 昇格のいずれも Timeline 行が誤った route を報告した — session `97764-1786198856`)
- <!-- verify: command "bats tests/get-auto-session-report.bats" --> `bats tests/get-auto-session-report.bats` 全件が PASS する (回帰保護 — 単独では常時 PASS のため上記 2 件の新規テスト追加 AC と組で機能する)

### Post-merge

- 次回 `/auto --batch` の完走後、L3 retrospective の Timeline 表の `Size/Route` 列と `Route mix` の集計が矛盾せず、`PR` 列が各 Issue の実 PR (patch route なら `—`) と一致することを観察する
  - 期待する出力構造:
    - Timeline 表の `Size/Route` 列が、同一行の Phase breakdown 列 (実行された `code-pr`/`code-patch`) と矛盾しない
    - `Route mix` 集計行 (patch/pr 件数) と、Timeline 表の各行の route 表示が整合する
    - `PR` 列が各 Issue の実際の PR 番号と一致し、patch route (PR が存在しない) の Issue では `—` になっている
  <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **Steering Docs sync candidate check 実施済み・変更不要**: `grep -rn "get-auto-session-report.sh" docs/ tests/ scripts/` で横断検索した。`docs/structure.md` (`:66, :201`) と `docs/tech.md` (`:248`, `WHOLEWORK_ISSUE_BODY_DIR` の説明) にヒットがあるが、いずれも本修正が変更しない一般的なスクリプト説明 (`--metrics-only` の出力先、無関係な環境変数) であり、Timeline 行の Size/Route/PR 導出ロジックには触れていないため更新不要と判断した。
- **`tests/audit-auto-session.bats` は変更不要**: 同スクリプトを対象とする別テストファイルだが (`grep -n "route\|_pr_col\|pr list" tests/audit-auto-session.bats` で確認)、唯一の route 関連 assertion (`patch:.*pr:`, `:44`) は `Route mix` 集計行 (#1289 で既に修正済み) を対象としており、フィクスチャも Size と実行フェーズが一致するケース (S/code-patch, M/code-pr) のみで新旧いずれの route 導出方式でも同じ結果になるため、本修正による影響はない。
- **`_size` 表示は意図的に現状維持**: Issue 本文の Auto-Resolve Log に既に「Size 表示列 (`M/`, `S/` の部分) は `sub_start` の `size` を使い続ける可能性が高い」との判断が記録されている。本 Spec もこれを踏襲し、`_route` の導出方式のみを変更する。`_size` 表示自体を post-spec の確定値に揃える対応は本 Issue のスコープ外 (必要になった場合は別 Issue で検討)。
- **AC2 の `file_not_contains` パターンの安全性確認**: `grep -n "XS" scripts/get-auto-session-report.sh` で確認したところ、`"XS"` という文字列は除去対象の `case` 文の行 (`:343`) にのみ出現する。Implementation Step 1 の置き換えコードは `"XS"` を含まないため、`file_not_contains` の判定方式 (Grep ベースの部分一致、ERE 解釈の可能性あり) に関わらず修正後は誤検出なく PASS する。
- **PR 列 JSON パースに python3 ではなく jq を採用**: `skills/verify/SKILL.md` Step 2 の参照実装は python3 で `gh-extract-issue-from-pr.sh` の JSON 出力をパースしているが、`get-auto-session-report.sh` は現状 python3 に依存しておらず jq に全面依存しているため、一貫性を優先して `jq -r '.issue_number // empty'` を使う。
- **Post-merge observation AC のフォーマット**: `verify-classifier.md` の observation-tag ガイドラインに沿い、Option A (観測イベントと期待される出力構造の分離) の形で整形した。Issue 本文側の元の 1 文プローズは既に 3 つの期待基準 (Size/Route と Phase breakdown の整合、Route mix との整合、PR 列の正確性) を暗に含んでいたため、Issue 本文自体の書き換えは行わず、Spec 側の記述のみを構造化した。
- 欠陥 1 と欠陥 2 は根本原因が異なる (前者は値のスナップショット時点の取り違え、後者は全文検索結果の無検証採用) が、同一の表・同一のスクリプトに存在するため 1 Issue にまとめられている (Issue 本文 Notes 参照)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1300` (non-interactive) 実行時の Autonomous Auto-Resolve Log — AC5 のテスト範囲を降格方向のみから昇格・降格の両方向へ拡張、AC2 の verify command を `case` 文の直接マッピング検出へ変更、Post-merge observation AC に `session=next` を追加。いずれも現在の Issue 本文に既に反映済みであり、本 Spec 作成時点で追加対応は不要と判断した。 / URL: https://github.com/saitoco/wholework/issues/1300#issuecomment-5230385022

## Code Retrospective

### Deviations from Design
N/A — Implementation Steps 1〜5 を Spec の記述通りに実装した。

### Design Gaps/Ambiguities
- 全 bats スイート (`bats --jobs 18 tests/`) の1回目実行で `tests/post_merge_check.bats` の `fail: gh issue reopen called when FAIL input given` が1件 FAIL したが、単体実行および2回目の並列実行では PASS した。本 Issue の変更対象 (`scripts/get-auto-session-report.sh` / `tests/get-auto-session-report.bats`) とは無関係な並列実行時フレークであり、既存 Issue #1308 (`tests/post_merge_check.bats: bats --jobs 並列実行時に 2 件 FAIL するフレークを解消`) で追跡済みのため、本 Issue では追加の Follow-up Issue 起票は行わなかった。

### Rework
N/A — 手戻りなし。

## review retrospective

### Spec vs. implementation divergence patterns
N/A — review-light (spec deviation 観点) で乖離なし。`_route` 導出 (`ROUTE_MIX` と同じ `has_pr`/`has_patch` パターン) と `PR` 列の検証付き解決 (`skills/verify/SKILL.md` Step 2 と同方式) はいずれも Spec Implementation Steps の記述通りに実装されていた。

### Recurring issues
N/A — 同種の issue の複数発生はなし。MUST/SHOULD issue はゼロ、CONSIDER 2件 (コメント欠如・API呼び出し量) はいずれも軽微な提案であり修正は見送った。

### Acceptance criteria verification difficulty
N/A — 6件の Pre-merge AC (rubric ×3, file_not_contains ×1, grep ×1, command ×1) は全て UNCERTAIN なく機械的に PASS 判定できた。`bats --jobs 18 tests/get-auto-session-report.bats` は 17/17 PASS。verify command の記述と実装の対応も明確だった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 6件は全て checked 済み、review-incomplete-fallback も該当なしのため、pre-merge AC ゲートは通常経路 (override 不要) で通過した。
- `gh pr merge --squash --delete-branch` で squash merge を実行し、`closes #1300` により Issue を自動クローズさせた (BASE_BRANCH=main のため手動 close 不要)。

### Deferred Items
- CONSIDER 2件 (コメント欠如の可読性提案、候補PR検証ループのAPI呼び出し量) は review フェーズで修正見送り済み — 再掲不要。

### Notes for Next Phase
- Post-merge AC (`verify-type: observation event=auto-run session=next`) は次回 `/auto --batch` 完走後に `/verify 1300` で確認する。Timeline 表の `Size/Route` 列と `Route mix` の集計、`PR` 列と実 PR の一致を観察すること。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- **同一 batch で直前に着地した #1294 の Pattern 2 サブパターンが実際に機能した**: Step 15 の監査が「全 6 件の Pre-merge AC が意図通り機能することを main ブランチに対する空撃ちで確認」と報告している。これは #1294 が追加した検出手順 (b) そのもので、かつ回帰保護と明示した `command "bats tests/get-auto-session-report.bats"` AC は除外条件 (d) により正しく指摘されていない (コメント投稿なし)。追加したパターンが誤検出も検出漏れも起こさずに動作した最初の実例
- **起票側 (`/verify 1289` の L3 retrospective) の想定漏れを 1 件補正した**: 起票時の AC5 は「post-spec で Size が**降格**した Issue」のフィクスチャのみを要求していたが、フォローアップの実測で #1251 (M→S 降格) と **#1292 (S→M 昇格)** の双方で Timeline 行が誤 route を報告することが判明し、AC5 を「昇格・降格の両方向」へ拡張した。私が観測した実例 (#1256 の M→XS 降格) が降格側だけだったため、起票時のスコープが片側に偏っていた
- AC2 の verify command を jq クエリ文字列マッチから、実際に route 判定を行っている `case "$_size" in ... esac` ブロックの検出へ精緻化 (偽陰性リスクの低減)

#### spec

- 根本原因の異なる 2 欠陥 (値のスナップショット時点の取り違え / 全文検索結果の無検証採用) を 1 Issue で扱う構成を維持しつつ、それぞれに独立した AC とテストを設計した

#### code

- `scripts/get-auto-session-report.sh` 24 行・`tests/get-auto-session-report.bats` 62 行の変更。rework ゼロ

#### review

- review-light の 4 観点すべてで指摘 0 件 (MUST: 0 / SHOULD: 0)。MUST 指摘がなかったため `REQUEST_CHANGES` は試行されず、#1256 の自己 PR 422 フォールバックは本 PR では発火していない

#### merge

- PR #1311 を squash merge。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 6 件は既チェックのため skip、post-merge の observation 1 件は `auto-run` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- **修正の効果を実データで確認した**: 本セッションの Timeline 表は #1294 = `S/patch` / PR `—`、#1300 = `M/pr` / PR `#1311`、#1301 = `S/patch` / PR `—` を報告し、3 行すべてが実態と一致した。前セッション (`23043-1786197225`) では 7 行中 3 行の PR 列が誤りだった
- **同表で別系統の欠陥を発見した** (下記 Improvement Proposals)

### Improvement Proposals

- **レポートの silent-window 警告閾値が `.wholework.yml` の phase timeout override を読まない (Tier 1 — 起票)**: `scripts/get-auto-session-report.sh:26` は `SILENT_THRESHOLD_SPEC=$(( ${WATCHDOG_TIMEOUT_SPEC_DEFAULT:-1800} - SILENT_MARGIN ))` のように `scripts/watchdog-defaults.sh` のグローバル既定値から警告閾値を計算しており、`.wholework.yml` の project override を解決していない。実際の watchdog は `run-*.sh` が `load_watchdog_timeout()` 経由で config を読むため、**警告基準と実 kill 基準が乖離する**。本セッションの Timeline は #1301 の spec 行に `Silent 1310s phase=spec (within 600s of watchdog limit)` を出したが、#1301 が設定した `watchdog-timeout-spec-seconds: 2340` に対する余裕は 1030s ある。この repo は code (7200s / 既定 4680s) も override しており同じ乖離が生じる。Tier 1 の根拠は (b) 本セッション内で同一スクリプトの測定精度欠陥として #1279 / #1289 / #1300 に続く 4 件目であること、(c) 同スクリプトが `skills/auto/SKILL.md` Step 5 と `skills/audit/SKILL.md` の 2 skill が消費する測定 SSoT であること。加えて **#1301 の post-merge AC (「`within 600s of watchdog limit` の警告が spec 行に出ない」ことの観察) は本修正なしには恒久的に達成不能**であり、既存 Issue の検証可能性を直接ブロックしている
