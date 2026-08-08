# Issue #1279: get-auto-session-report: Issue 列挙を処理実績イベントに限定し opportunistic_verify_result による汚染を解消

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1279 --non-interactive` の Issue Retrospective — Auto-Resolve Log (post-merge observation AC への `session=next` 付与理由、許可リスト方式・in-session `/verify` dispatch の扱いは AC テキストが選択肢に依存しないため Issue 本文の追加変更なしと判定した根拠)。本 Spec の設計方針 (許可リスト方式・`sub_start`/`phase_*` の union 採用) は同ログの判断を踏襲する。 / URL: https://github.com/saitoco/wholework/issues/1279#issuecomment-5226906958
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Triage AC audit — Pre-merge AC4 の `<!-- verify: command "bats tests/get-auto-session-report.bats" -->` が常時 PASS リスクを持つ (新規テスト追加前の main ブランチで既に exit 0) との指摘。`--filter` によるテスト名の具体化を推奨。本 Spec でテスト名確定後に反映する (Implementation Step 4 で Issue 本文 AC4 も同期更新)。 / URL: https://github.com/saitoco/wholework/issues/1279#issuecomment-5226918680

## Overview

`scripts/get-auto-session-report.sh` は `.tmp/auto-events.jsonl` から `/auto` セッションの Metrics を生成する際、「セッション内で登場した distinct `.issue`」を無差別に「処理済み Issue」として集計している。#1236 で `modules/opportunistic-verify.md` Step 3 に `opportunistic_verify_result` イベントの emit が追加され、その `issue` フィールドには「判定対象の候補 Issue 番号」(`EMIT_ISSUE_NUMBER`、実際にこのセッションが処理した Issue ではない) が入るようになったため、候補 Issue が処理済み Issue として混入するようになった。本 Issue は Issue 列挙の母集団を「処理を示すイベント種別 (`sub_start` / `phase_*`)」に限定し、この混入を解消する。

## Reproduction Steps

1. `/auto --batch` 等のセッション中に、Opportunistic Verification (`modules/opportunistic-verify.md`) が複数の候補 Issue の pending AC を判定する。
2. 判定 1 件ごとに `opportunistic_verify_result` イベントが emit され、`issue` フィールドに判定対象の候補 Issue 番号 (このセッションが処理した Issue ではない) が記録される (`modules/event-emission.md` で定義済みの意味論)。
3. セッション終了時に `get-auto-session-report.sh <session-id> --metrics-only` を実行すると、`ISSUES_PROCESSED` / `ISSUE_NUMS_FOR_TABLE` / `ISSUE_NUMS` (いずれも「イベント全体の distinct `.issue`」を数える同一パターン) が候補 Issue 番号を「処理済み Issue」として計上する。
4. 実測 (session `83694-1786088052`, 2026-08-08): `/auto --batch 1236 1239 1238 1242` で実処理 4 Issue (+ in-session `/verify` dispatch の #575) に対し「Issues processed: 48」と報告され、Sub-Issue Completion Timeline に全フィールド `?` の行が 43 行生成された。

## Root Cause

`scripts/get-auto-session-report.sh` の 3 箇所 — `ISSUES_PROCESSED` (174-176 行目)、`ISSUE_NUMS_FOR_TABLE` (310 行目)、GitHub state lookups の `ISSUE_NUMS` (503 行目) — がいずれも `[.[] | select(.issue != null and .issue > 0) | .issue] | unique` という同一の jq パターンで、イベント種別を問わずセッション内の全 distinct `.issue` を「処理済み Issue」とみなしている。

`opportunistic_verify_result` の `issue` フィールド自体の値は意図通り正しい (候補 Issue 番号を記録するという `EMIT_ISSUE_NUMBER` の仕様通り)。したがって本件は emit 側の値が誤っている #1007 (PR 番号が `EMIT_ISSUE_NUMBER` にそのまま入り、`issue` フィールドの値自体が誤っていたケース) とは性質が異なり、集計側 (`get-auto-session-report.sh`) がイベント種別による意味論の違いを区別していないことが根本原因である。修正は集計側のフィルタ条件に限定するのが妥当 (詳細は Notes 参照)。

## Changed Files

- `scripts/get-auto-session-report.sh`: `ISSUES_PROCESSED` (174-176 行目) / `ISSUE_NUMS_FOR_TABLE` (310 行目) / `ISSUE_NUMS` (503 行目) の 3 箇所が使う「全 distinct `.issue`」列挙を、`sub_start` または `phase_*` イベントを持つ Issue のみに限定した共通変数 `PROCESSED_ISSUES_JSON` から導出する形に置き換える — bash 3.2+ compatible
- `tests/get-auto-session-report.bats`: 新規テスト 1 件追加 (`opportunistic_verify_result` の候補 Issue が Issues processed / Sub-Issue Completion Timeline から除外されることを検証)
- `docs/workflow.md`: `/audit auto-session` の「Issues processed」定義文に、候補 Issue のみを記録する他イベント (`opportunistic_verify_result` 等) は集計から除外される旨を追記
- `docs/ja/workflow.md`: 上記の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

**Steering Docs sync candidate として検出したが変更不要と判断したファイル (grep 実施済み):**

- `docs/structure.md` / `docs/ja/structure.md`: `get-auto-session-report.sh` への言及は Scripts 一覧の 1 行役割説明のみで、集計ロジックの内部修正は記述に影響しない
- `docs/tech.md` / `docs/ja/tech.md`: `WHOLEWORK_ISSUE_BODY_DIR` の説明行は verify-type breakdown 用の既存挙動であり、本修正の対象外

## Implementation Steps

1. `scripts/get-auto-session-report.sh` を修正する。`EVENT_COUNT` の計算 (現在の 139 行目) の直後に、処理を示すイベント (`sub_start`、または `phase_` で始まるイベント種別) を持つ Issue 番号の一意集合を計算する変数を追加する:
   ```bash
   # Issues counted here must show an event that indicates actual phase execution
   # (sub_start = batch/XL dispatch start, phase_start/phase_complete = phase ran).
   # opportunistic_verify_result's `issue` field records a *candidate* Issue being
   # judged for pending AC, not one this session processed — excluded by this filter.
   PROCESSED_ISSUES_JSON=$(echo "$EVENTS_JSON" | jq -c '
     [.[] | select(.issue != null and .issue > 0 and (.event == "sub_start" or (.event | startswith("phase_")))) | .issue] | unique
   ' 2>/dev/null || echo "[]")
   ```
   続けて、`ISSUES_PROCESSED` の計算 (現在の 174-176 行目) を次の形に置き換える:
   ```bash
   ISSUES_PROCESSED=$(echo "$PROCESSED_ISSUES_JSON" | jq 'length' 2>/dev/null || echo 0)
   ```
   `ISSUE_NUMS_FOR_TABLE` の計算 (現在の 310 行目) を次の形に置き換える:
   ```bash
   ISSUE_NUMS_FOR_TABLE=$(echo "$PROCESSED_ISSUES_JSON" | jq -r '.[]' 2>/dev/null || true)
   ```
   GitHub state lookups ブロックの `ISSUE_NUMS` の計算 (現在の 503 行目) を次の形に置き換える (これにより `FULLY_CLOSED` / `VERIFY_REMAINING` の live `gh issue view` 呼び出しも候補 Issue に対して発行されなくなる — 副次的な API 呼び出し削減):
   ```bash
   ISSUE_NUMS=$(echo "$PROCESSED_ISSUES_JSON" | jq -r '.[]' 2>/dev/null || true)
   ```
   (→ acceptance criteria 1, 2, 3)
2. (after 1) `tests/get-auto-session-report.bats` に新規テスト `"Issues processed: opportunistic_verify_result candidate Issues are excluded from enumeration"` を追加する。フィクスチャは既存の `session_id filter` テストと同じ 1 行 1 JSON 形式で、同一 `session_id` 内に次の 2 種類の Issue を混在させる: (a) 処理済み Issue #100 — `sub_start` (size 付き) + `phase_start`/`phase_complete` (`phase` は `code-patch`) + `sub_complete` を持つ、(b) 候補 Issue #501・#502 — `opportunistic_verify_result` イベント (`skill`/`result`/`ac_index` フィールド付き、`result` はそれぞれ `PASS`/`SKIP`) のみを持ち `sub_start`/`phase_*` を一切持たない。`--metrics-only --no-github` の出力に `Issues processed | 1` のみが現れ、`| #501 |` および `| #502 |` の行が Sub-Issue Completion Timeline に出現しないことを検証する (→ acceptance criteria 4)
3. (parallel with 1, 2) `docs/workflow.md` の「Issues processed」定義文 (`... an Issue's presence or absence of a` `` `sub_start` `` `event lets you tell them apart when needed.` の直後、`Details: ...` の直前) に、候補 Issue のみを記録する他イベント (`opportunistic_verify_result` 等) は集計から除外される旨の一文を追記する。`docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/workflow.md` の対応箇所 (「両者を判別したい場合は、`sub_start` イベントの有無で確認できます。」の直後、「詳細: ...」の直前) に日本語ミラーを同期する (→ acceptance criteria 1, 2)
4. (after 2) Issue #1279 本文の Pre-merge AC4 の verify command を、Step 2 で確定したテスト名に基づき `command "bats --filter 'candidate Issues are excluded' tests/get-auto-session-report.bats"` に更新する (`gh-issue-edit.sh` 経由。理由: 既存の `command "bats tests/get-auto-session-report.bats"` は新規テスト追加前の main ブランチで既に exit 0 のため、テスト未追加でも常時 PASS してしまう — Triage AC audit コメントで指摘済み)。同じ verify command を本 Spec の Verification 節にも反映する (→ acceptance criteria 4)

## Verification

### Pre-merge

- <!-- verify: rubric "get-auto-session-report.sh の Issue 列挙ロジックが、イベントの issue フィールドを無差別に集めるのではなく、処理実績を示すイベント種別に限定して母集団を構成している" -->
- <!-- verify: rubric "許可リスト方式 (処理を示すイベントを正とする) か除外リスト方式かの選択と理由が Spec に記録されている" -->
- <!-- verify: rubric "phase_* イベントのみを持つ Issue の扱いについての判断が Spec または実装コメントに記載されている" -->
- <!-- verify: command "bats --filter 'candidate Issues are excluded' tests/get-auto-session-report.bats" -->
- <!-- verify: github_check "gh pr checks" "Run bats tests" -->

### Post-merge

- 次回 `/auto --batch` 完走後の L3 retrospective で、Metrics の `Issues processed` が実際の処理件数と一致することを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **許可リスト方式の採用理由 (AC2)**: Issue 本文の「対応方針 (案)」で既に許可リスト方式が推奨されており、「今後 `opportunistic_verify_result` 以外にも候補 Issue 番号を持つイベントが追加されうるため、『処理を示すイベント』を正とする方が将来の同型汚染に強い」という理由に同意し採用した。除外リスト方式 (`opportunistic_verify_result` を個別に除外) は、将来同種の「候補 Issue 番号を持つが処理を意味しない」イベントが追加されるたびに個別対応が必要になり、構造的に脆い。
- **`sub_start` ∪ `phase_*` の union を採用した理由、および #575 (in-session `/verify` dispatch) の扱い (AC3)**: Issue 本文の実測では `sub_start` のみ (方式 1) だと 4 件、`phase_*` を含む union (方式 2/3) だと 5 件 (#575 を含む) に収束するとされている。本 Spec は union を採用し、`phase_*` イベントのみを持つ Issue (in-session `/verify` dispatch によるもの、例: #575) も「処理された Issue」として計上する。理由: `phase_start`/`phase_complete` は実際にフェーズの実行 (この場合は `/verify`) が行われたことを示す一次イベントであり、`docs/workflow.md` の既存の「Issues processed」定義 (#1007 で追記済み) も「observation dispatch による `/verify` 単体再実行のみを受けた Issue」を計上対象として明記している。`opportunistic_verify_result` は判定 (judgment) を記録するイベントであり実行 (execution) を記録しないため、この 2 つは意味論的に異なる。
- **#1007 との判断の相違点**: #1007 (PR 番号混入) は emit 側の値そのものが誤っていた (PR 番号が Issue 番号として記録された) ため emit 側で修正した。本 Issue は emit されている値自体は正しく (候補 Issue 番号として意図通り)、集計側がイベント種別の意味論を区別していないことが原因のため、集計側 (`get-auto-session-report.sh`) での修正が妥当と判断した。同じスクリプト・同じ「Issues processed 水増し」という症状でも、修正すべきレイヤーが異なる点に注意 (Root Cause 参照)。
- **Pre-merge AC4 の verify command 具体化**: Triage AC audit コメント (Consumed Comments 参照) の指摘通り、既存の `command "bats tests/get-auto-session-report.bats"` は新規テスト追加前の main で既に exit 0 のため、実装を忘れても PASS してしまう常時 PASS リスクがある。Implementation Step 2 で確定したテスト名から一意な部分文字列 `candidate Issues are excluded` を抽出し、`bats --filter` で新規テストのみを対象にした verify command に置き換えた。CI 側の全件実行は Pre-merge AC5 (`github_check "gh pr checks" "Run bats tests"`) が別途担保する。
- **Out of Scope — `scripts/collect-run-facts.sh` の同型汚染 (follow-up 推奨)**: `scripts/collect-run-facts.sh` 140 行目の `ISSUE_NUMBERS=$(... | jq -r '.issue' ...)` にも本 Issue と同型の「全 distinct `.issue` を無差別に集計する」パターンが存在する。session `91762-1786112233` (2026-08-08) の retrospective で「Issues processed: 58」(実処理 3 件) という同種の汚染が実際に観測されている (`docs/sessions/91762-1786112233-2026-08-08/session.md` 参照)。本 Issue の Title/Background/Purpose はいずれも `get-auto-session-report.sh` のみを対象としており、`collect-run-facts.sh` への対応は `/issue` フェーズで確定した要件の範囲外 (`/spec` は要件を追加・変更しない — `docs/product.md` § `/issue` (What) vs `/spec` (How) Responsibility Boundary) と判断し、本 Spec では変更しない。別 Issue での対応を推奨する。
- **SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文の Auto-Resolved Ambiguity Points (`/issue` フェーズで非対話モードにより自動解決済み) を実装方針として採用した (詳細は Consumed Comments の Issue Retrospective コメント参照)。

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜4 を設計通りに実施した。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

### Follow-up

- Notes の「Out of Scope — `scripts/collect-run-facts.sh` の同型汚染」を受け、follow-up Issue #1287 を起票した (重複なしを `gh issue list` で確認済み)。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate 確認で unchecked_count=0 (Pre-merge AC1〜5 全てチェック済み) を確認し、追加のユーザー確認なしでマージを進行した。
- review-incomplete-fallback チェックでは organic completion (fallback 経由ではない) を確認した。
- `gh pr merge 1286 --squash --delete-branch` で Squash Merge を実行し、リモートブランチを削除した。

### Deferred Items
- `scripts/collect-run-facts.sh` の同型汚染 follow-up Issue #1287 は本 PR のスコープ外のまま (review phase から引き継ぎ、変更なし)。
- Post-merge AC (`session=next` の観察 AC) は次回 `/auto --batch` 完走後の L3 retrospective で確認される (変更なし)。

### Notes for Next Phase
- `/verify` は Post-merge AC (observation, `session=next`) を次回の `/auto --batch` 実行後に確認すること。現時点では確認不能なため保留のままで良い。
- Issue #1279 はマージにより auto-close 見込み (base branch は main)。

## review retrospective

### Spec vs. implementation divergence patterns

- Nothing to note — Implementation Steps 1〜4 は Spec の記述通りに実施されており、`PROCESSED_ISSUES_JSON` 共通変数の導入方法・3箇所の置き換え箇所とも Spec と実装で乖離はなかった。

### Recurring issues

- Nothing to note — review-light エージェントによる4観点 (Spec 逸脱・エッジケース堅牢性・セキュリティ・ドキュメント整合性) チェックで指摘は0件だった。

### Acceptance criteria verification difficulty

- Pre-merge AC5 (`github_check "gh pr checks" "Run bats tests"`) は `/code` フェーズ完了時点では PR 未作成のため判定不能で未チェックのまま引き継がれていたが、本フェーズで CI 全9件 SUCCESS を確認しチェック済みに更新した。これは Phase Handoff の想定通りの引き継ぎであり、AC 記述自体に問題はなかった。
- rubric 系 AC (AC1〜3) は Spec Notes 節の記述と実装コメントを直接参照するだけで PASS 判定でき、UNCERTAIN や verify command の構文エラーは発生しなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- Background の事実主張がすべてコードベース照合で裏付けられており、`/spec` 以降で前提の訂正が発生しなかった
- AC 監査で `command "bats tests/get-auto-session-report.bats"` の常時 PASS リスクを検出したが、**コメント投稿のみで本文は修正しなかった**。同一セッションの #1266 では `/issue` Step 7 が AC を実際に書き換えており、同じ検出に対する処置が Issue 間で分かれている。今回は `/spec` が Notes に記録したうえで本文も同期修正したため実害はなかったが、`/issue` が修正まで行うか指摘に留めるかの基準は明文化されていない

#### spec

- 許可リスト方式の採用理由、`sub_start` ∪ `phase_*` の union 採用と #575 の扱い、#1007 との修正レイヤーの違いを、いずれも AC が要求する形で Notes に記録した。判断の追跡可能性が高い
- triage / `/issue` 双方が指摘した AC4 の常時 PASS を、実装確定後のテスト名から一意な部分文字列を抽出して `bats --filter` 形式へ具体化した。指摘 → 修正の連鎖が Issue 本文まで届いている
- `scripts/collect-run-facts.sh` の同型汚染を副次的に発見し、`/issue` フェーズで確定した要件の範囲外として Notes に記録するに留めた。`/spec` が要件を追加しない責務境界を守った判断

#### code

- Implementation Steps 1〜4 を逸脱なく実施、rework ゼロ
- Notes の Out of Scope を受けて follow-up Issue #1287 を起票し、重複がないことを `gh issue list` で確認している

#### review

- review-light の 4 観点すべてで指摘 0 件 (MUST: 0 / SHOULD: 0 / CONSIDER: 0)。指摘がなかったため `REQUEST_CHANGES` 自体が試行されず、#1256 で修正した自己 PR 422 フォールバックは本 PR でも発火していない。#1256 の post-merge observation 条件は引き続き未検証

#### merge

- Pre-merge AC gate で unchecked_count=0 を確認、review-incomplete-fallback チェックで organic completion を確認したうえで squash merge。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 5 件は既チェックのため既定どおり skip、post-merge の observation 1 件は `auto-run` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- triage で AC4 の常時 PASS を指摘した経緯があるため、skip では効果を確認できない点を補うべく実データで検証した。本セッション (`23043-1786197225`) の生 distinct issue は 6 件 (`783 1064 1108 1256 1266 1279`)、うち処理実績イベントを持つのは 3 件 (`1256 1266 1279`) で、修正後のレポートは `Issues processed: 3` を返した。**修正が実データで機能していることを確認**した。#783 / #1064 / #1108 は本セッションの opportunistic verification で候補判定された Issue であり、汚染の再現でもある
- **同スクリプトに同系統の未修正欠陥を発見した** (下記 Improvement Proposals)

### Improvement Proposals

- **`get-auto-session-report.sh` の `Route mix` が post-spec の Size 再評価を反映しない (Tier 1 — 起票)**: `:170-179` は route を `sub_start` イベントの `size` フィールドから導出しているが、`sub_start` は sub-issue 開始時点の記録であり `/spec` の post-spec Size 再評価より前の値である。本セッションの実測では #1256 が `sub_start` で `size: "M"` のまま記録され、`/spec` が M → XS へ降格して patch route で着地したにもかかわらず pr として集計された (報告値 `patch: 1, pr: 2` / 実態 `patch: 2, pr: 1`)。`scripts/collect-run-facts.sh:185` は同じ route を `code-pr` / `code-patch` phase イベントの有無から導出しており (実際 #1256 を `route: "patch"` と報告)、参照実装が同一リポジトリ内に存在する。Tier 1 の根拠は positive-evidence gate (c): `get-auto-session-report.sh` は `skills/auto/SKILL.md` Step 5 の L3 retrospective と `skills/audit/SKILL.md` の `/audit auto-session` という 2 つの skill が消費する測定 SSoT であり、本 Issue 自身の Background がその二重消費経路を明記している。既存 open Issue に該当なし (#1240 は route *選択*側で別系統、#875 は CLOSED) を確認済み

- **AC 常時 PASS を検出した `/issue` の処置が Issue 間で一貫しない (Tier 2 — 記録のみ)**: 同一セッション内で、#1266 では `/issue` Step 7 が AC を実際に書き換えたのに対し、本 Issue では指摘コメントの投稿のみで本文は変更されなかった。本 Issue では `/spec` が後段で修正したため実害ゼロだが、`/spec` を持たない経路 (XS patch route 等) では指摘が消化されないまま verify に到達しうる。単独の起票は見送るが、同型が再発した場合は `/issue` の AC 監査の処置基準として Tier 1 を検討する
