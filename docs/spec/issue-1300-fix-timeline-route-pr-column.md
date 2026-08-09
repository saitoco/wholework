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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `_route` 導出は `ROUTE_MIX` (#1289) と同じ `has_pr`/`has_patch` 判定パターンを Timeline 行生成ループ内に直接インライン展開した (共通関数への抽出はスコープ外、Spec Implementation Step 1 の指示通り)。
- `PR` 列は `skills/verify/SKILL.md` Step 2 と同じ「候補を最大10件取得 → `gh-extract-issue-from-pr.sh` で実 `closes` 参照を検証 → 一致した最初の候補を採用」方式を採用し、JSON パースは python3 ではなく既存の jq 依存に揃えた。
- `_size` 表示列 (Timeline 行の `M/`, `S/` 部分) は Spec の判断通り `sub_start.size` のまま変更していない (post-spec 確定値への統一はスコープ外)。

### Deferred Items
- `_size` 表示自体を post-spec の確定 Size に揃える対応 (Spec Notes に明記のスコープ外事項)。
- 全 bats スイート並列実行時の `tests/post_merge_check.bats` フレーク — 既存 Issue #1308 で追跡済み、本 Issue からの追加対応なし。

### Notes for Next Phase
- Post-merge AC は `verify-type: observation event=auto-run session=next` — 次回 `/auto --batch` 完走後の L3 retrospective で Timeline 表と Route mix の整合、PR 列の正確性を確認する。
- `tests/get-auto-session-report.bats` の新規2テストは `NO_GITHUB` の有無を使い分けている (PR列テストは `gh` PATH モックが必要なため `--no-github` なし、route テストは `--no-github` で十分)。
