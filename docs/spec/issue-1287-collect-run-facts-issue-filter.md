# Issue #1287: collect-run-facts: Issue 列挙を処理実績イベントに限定 (#1279 follow-up)

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1287 --non-interactive` の Issue Retrospective — Auto-Resolve Log 3 点 (イベントフィルタは #1279 の `get-auto-session-report.sh` 修正パターン `.event == "sub_start" or (.event | startswith("phase_"))` をそのまま踏襲、bats テスト追加先は新規ファイルではなく既存 `tests/run-fact-matching.bats`、許可リスト方式採用により「等」の個別列挙が不要になる)。Acceptance Criteria は既にこの方針で確定済み (AC1: rubric+file_not_contains 併記、AC2: 対象ファイル明記、AC3: patch route 形式の CI green 確認)。本 Spec はこの方針をそのまま踏襲する。 / URL: https://github.com/saitoco/wholework/issues/1287#issuecomment-5227714891

## Overview

`scripts/collect-run-facts.sh` の Issue 列挙ロジック (`ISSUE_NUMBERS`, 140 行目) が、セッション内イベントの `.issue` フィールドをイベント種別を問わず無差別に集計しているため、`opportunistic_verify_result` イベント (判定対象の候補 Issue 番号を記録するだけで、このセッションが実際に処理した Issue を意味しない) が「処理済み Issue」として `issues[]` 配列に混入する。#1279 で `scripts/get-auto-session-report.sh` に適用した許可リスト方式 (`sub_start` イベントまたは `phase_` プレフィックスを持つイベントのみを処理実績とみなす) と同型のパターンを `collect-run-facts.sh` にも適用し、この汚染を解消する。

## Reproduction Steps

1. `/auto` セッション中に Opportunistic Verification (`modules/opportunistic-verify.md`) が複数の候補 Issue の pending AC を判定する
2. 判定 1 件ごとに `opportunistic_verify_result` イベントが emit され、`issue` フィールドに判定対象の候補 Issue 番号 (このセッションが処理した Issue ではない) が記録される (`modules/event-emission.md` で定義済みの意味論)
3. `scripts/collect-run-facts.sh --session <id>` を実行すると、140 行目の `ISSUE_NUMBERS=$(... | jq -r '.issue' ... | sort -n -u)` がイベント種別を区別せず、候補 Issue 番号も `issues[]` 配列に含めてしまう
4. 実測: session `91762-1786112233` (2026-08-08) の retrospective で「Issues processed: 58」(実処理 3 件) という同種の汚染が観測されている (`docs/sessions/91762-1786112233-2026-08-08/session.md` 参照)

## Root Cause

`scripts/collect-run-facts.sh:140` の `ISSUE_NUMBERS` が `jq -r '.issue' 2>/dev/null | sort -n -u` という、イベント種別を問わずセッション内の全 distinct `.issue` を対象とするパターンを使用している。`opportunistic_verify_result` イベントの `issue` フィールド自体の値は仕様通り正しい (`EMIT_ISSUE_NUMBER` が候補 Issue 番号を記録するという意味論通り) ため、#1279 の Root Cause 分析と同じく、修正すべきは emit 側ではなく集計側 (本スクリプトの列挙フィルタ) である。

## Changed Files

- `scripts/collect-run-facts.sh`: 140 行目の `ISSUE_NUMBERS` 算出を、処理実績を示すイベント (`sub_start` または `phase_` プレフィックスを持つイベント) のみを対象とするフィルタに変更 (#1279 の `get-auto-session-report.sh` `PROCESSED_ISSUES_JSON` パターンと同型のフィルタ条件) — bash 3.2+ compatible
- `tests/run-fact-matching.bats`: 新規テスト 1 件追加 (`opportunistic_verify_result` のみを持つ候補 Issue が `issues[]` から除外されることを検証)

## Implementation Steps

1. `scripts/collect-run-facts.sh` の 140 行目 (現在 `ISSUE_NUMBERS=$(printf '%s\n' "$SESSION_EVENTS" | jq -r '.issue' 2>/dev/null | sort -n -u) || { ... }`) を次の形に置き換える。`$SESSION_EVENTS` は `jq -s` を使わない改行区切り JSON ストリームであるため (該当ファイル全体がこの形式で統一されている)、#1279 の配列内包表記 (`[.[] | select(...) | .issue] | unique`) とは異なり、単一オブジェクトへの直接 `select()` 適用形式で書く:
   ```bash
   # Issues counted here must show an event that indicates actual phase execution
   # (sub_start = batch/XL dispatch start, phase_start/phase_complete = phase ran).
   # opportunistic_verify_result's `issue` field records a *candidate* Issue being
   # judged for pending AC, not one this session processed — excluded by this filter.
   ISSUE_NUMBERS=$(printf '%s\n' "$SESSION_EVENTS" | jq -r 'select(.issue != null and .issue > 0 and (.event == "sub_start" or (.event | startswith("phase_")))) | .issue' 2>/dev/null | sort -n -u) || {
     echo "Error: failed to enumerate issue numbers from session events" >&2
     exit 1
   }
   ```
   (→ acceptance criteria 1)
2. (after 1) `tests/run-fact-matching.bats` に新規テストを追加する。既存テスト群と同じ setup (`$BATS_TEST_TMPDIR/events.jsonl` に 1 行 1 JSON でイベントを書き込み、`AUTO_EVENTS_LOG` にエクスポート、`--no-github` で実行) を使い、同一 `session_id` 内に以下を混在させたフィクスチャを用意する: (a) 処理済み Issue #100 — `sub_start` (`size` フィールド付き) + `phase_start`/`phase_complete` (`phase: code-patch`) を持つ、(b) 候補 Issue #501 — `opportunistic_verify_result` イベント (`skill`/`result`/`ac_index` フィールド付き) のみを持ち `sub_start`/`phase_*` を一切持たない。`--session sess1 --no-github` の出力で `.issues | length` が `1`、`.issues[0].number` が `100` であることを検証する (→ acceptance criteria 2)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/collect-run-facts.sh の Issue 列挙 (ISSUE_NUMBERS) が、sub_start イベントまたは phase_ プレフィックスを持つイベントなど処理実績を示すイベント種別のみを対象とするフィルタに変更されている (#1279 の get-auto-session-report.sh 修正と同型の許可リスト方式パターン)" --> <!-- verify: file_not_contains "scripts/collect-run-facts.sh" "jq -r '.issue' 2>/dev/null | sort -n -u" --> `scripts/collect-run-facts.sh` の Issue 列挙 (`ISSUE_NUMBERS`) が、処理実績を示すイベント種別 (`sub_start` / `phase_*` 等) のみを対象としている (#1279 と同型の許可リスト方式)
- <!-- verify: command "bats tests/run-fact-matching.bats" --> `opportunistic_verify_result` 等の候補 Issue 番号のみを持つイベントが Issue 列挙から除外されることを検証する bats テストが `tests/run-fact-matching.bats` (既存ファイル) に追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) の bats テストが green (patch route)

### Post-merge

なし (Issue 本文に Post-merge Acceptance Criteria の記載なし。Issue Retrospective — Consumed Comments 参照 — の通り、方式選定自体の再検証は #1279 側で完了済みのためスコープを Pre-merge の 3 条件に絞ったと明記されている)

## Notes

- **許可リスト方式・パターン踏襲の理由**: #1279 が `get-auto-session-report.sh` で確立した修正パターン (`.event == "sub_start" or (.event | startswith("phase_"))`) をそのまま踏襲した。Root cause に最も忠実であり、既存コードベースパターンとの一貫性を保てるため (詳細は Consumed Comments の Issue Retrospective コメント参照)。許可リスト方式の採用自体の妥当性 (除外リスト方式より将来の同型汚染に強い等) の再検証は #1279 側 (`docs/spec/issue-1279-fix-issue-enum-contamination.md` Notes) で完了・記録済みであり、本 Issue はその適用のみを扱う。
- **JSONL ストリーム vs 配列の実装差分**: #1279 の `get-auto-session-report.sh` は `EVENTS_JSON` を `jq -s` でスラープした配列として扱うため `[.[] | select(...) | .issue] | unique` という配列内包表記を使う。一方 `collect-run-facts.sh` の `$SESSION_EVENTS` は `jq -s` を使わないストリーム形式 (同ファイル内の他の処理と統一されている) であるため、本 Issue の実装は `select(...) | .issue` という単一オブジェクトへの直接適用形式を採る。フィルタ条件の意味論 (許可リストの中身: `sub_start` ∪ `phase_*` プレフィックス) は #1279 と完全に同一。
- **`.issue` の型**: `scripts/emit-event.sh` が `"issue":${_issue}` という unquoted 数値として emit するため (`emit_event()` 実装、124 行目)、`.issue > 0` の数値比較は #1279 のパターンと同様に安全に成立する。
- **スコープ確認 (Steering Docs sync candidate check)**: `grep -rn "jq -r '\.issue'" scripts/ modules/` で確認した結果、同型の未フィルタ `.issue` 列挙パターンは本 Issue が対象とする `scripts/collect-run-facts.sh:140` の 1 箇所のみで、他に対応漏れは存在しない。また `collect-run-facts.sh` を参照する現行ドキュメント (`docs/structure.md` / `docs/ja/structure.md` の役割説明行、`modules/run-fact-matching.md` / `modules/opportunistic-verify.md` / `modules/observation-trigger.md` / `modules/phase-state.md` の呼び出し規約説明) はいずれも `--session`/`--no-github` 等の I/O 契約や出力 JSON スキーマを記述するのみで、`issues[]` に含まれる Issue 番号の内部フィルタ条件には言及していないため、変更不要と判断した。
- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** Issue 本文の Auto-Resolved Ambiguity Points (`/issue` フェーズで非対話モードにより自動解決済み) を実装方針として採用した (詳細は Consumed Comments の Issue Retrospective コメント参照)。

## Code Retrospective

### Deviations from Design

- なし。Implementation Steps 1・2 とも Spec 記載の置換内容・フィクスチャ設計をそのまま適用した。

### Design Gaps/Ambiguities

- なし。

### Rework

- `tests/run-fact-matching.bats` の既存テスト「recovery_tiers captures tier values with tier N fact_tokens」(旧: 900 番 Issue に `recovery` イベントのみを与えるフィクスチャ) が、フィルタ変更後に FAIL した。原因は当該フィクスチャが `sub_start`/`phase_*` を一切含まず、新しい許可リストフィルタで Issue #900 自体が `ISSUE_NUMBERS` から除外されたため。実運用では `recovery` イベントは必ず稼働中の phase 内で発生する (`phase_start` を伴わない `recovery` 単体は起こらない) ため、フィクスチャが非現実的な形だったと判断し、`phase_start` イベントを 1 件追加してフィクスチャを実態に合わせた (テストが検証する内容自体は変更していない)。Tier 0 分類は `logic` (fixture 個別ケースとして機械分類されなかった) だったため、Step 9 通常の 1 回リペア枠内で対応した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Step 1 の jq フィルタをそのまま採用 (`select(.issue != null and .issue > 0 and (.event == "sub_start" or (.event | startswith("phase_")))) | .issue`) — #1279 の `get-auto-session-report.sh` と完全に同一の許可リスト条件。
- AC3 (`github_check "gh run list" ...`) は patch route branch-scoped CI AC exclusion ルールに従い未チェックのまま残した。post-merge の `/verify` で評価される。

### Deferred Items
- AC3 の CI green 確認は `/verify` 実行時まで持ち越し。

### Notes for Next Phase
- `/verify` 実行時、`gh run list --branch=main --limit=1` がこの Issue の実装コミット (または合わせて push される retrospective コミット) の run を指していることを確認すること。
- `tests/run-fact-matching.bats` の「recovery_tiers」テストフィクスチャを変更済み (`phase_start` 追加) — 今後同ファイルに新規テストを追加する際は、`ISSUE_NUMBERS` の許可リストフィルタ (`sub_start` / `phase_*` のみ) を満たすイベントを含めること。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- `/code` が起票した Issue を triage auto-chain 経由で正規化し、Size S・Type Bug・Value 4 を設定。CI 検証 AC に patch route 用の `gh run list` 形式を選んでおり、同一 batch の #1256 で顕在化した route 依存の教訓が正しく適用されている
- 一方 **AC2 の verify command `command "bats tests/run-fact-matching.bats"` は常時 PASS だった**。同ファイルは変更前から存在し (実装コミット `757c1934` の差分は 19 追加 1 削除の modification)、実装前の main で CI が green だったため、新規テストケースを 1 件も追加しなくても exit 0 になる。Step 15 の監査は「問題なし」と報告した

#### spec

- Root Cause を #1279 と同型と特定し、許可リスト方式をそのまま踏襲。Changed Files 2 件で範囲が明確

#### code

- Implementation Steps を逸脱なく実施、rework ゼロ。`scripts/collect-run-facts.sh` 6 行・`tests/run-fact-matching.bats` 20 行の変更で完結

#### review

- patch route のため `/review` フェーズは実行されていない

#### merge

- patch route の直コミット。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 2 件は既チェックのため skip、CI の 1 件は実測して PASS (run `31275255719` / headSha `8c07c056` = 本 Issue 自身の commit)。post-merge 条件なし。全 AC チェック済みのため `phase/done` へ遷移
- **修正の効果を実データで確認した**: 本 Issue が扱う汚染は、まさにこの `/auto --batch` セッション (`23043-1786197225`) の実行中に観測されていたもので、`/verify 1256` 時点の `collect-run-facts.sh` 出力には `phases` が空配列の #783 / #1064 / #1108 が混入していた (いずれも本セッションの opportunistic verification で候補判定されただけの Issue)。修正後の列挙は `476 1256 1257 1266 1279 1287` で、`sub_start` ∪ `phase_*` を持つ Issue 集合と完全一致し、3 件が除外されたことを個別にも確認した
- `#476` は `phase_*` のみを持つ Issue (#1257 の review フェーズ中に in-session `/verify` として dispatch された) であり、#1279 の Spec が記録した設計判断 (`phase_*` のみを持つ Issue も計上する) と一致する挙動

### Improvement Proposals

- **`skill-dev-verify-audit.md` Pattern 2 に「既存のグリーンなテストスイートを走らせるだけの `command` 型 AC」のサブパターンが欠けている (Tier 1 — 起票)**: 現行 Pattern 2 の `command` 型サブパターンは「対象スクリプトが informational 専用で失敗条件フラグなしに常に exit 0 を返す設計」というケースのみを扱う (`:66-78`)。しかし `command "bats <既存ファイル>"` のように、AC 本文が「新規テストケースが追加されている」ことを主張しているのに verify command は変更前から green な既存スイートを走らせるだけ、という形は被覆されていない。本セッション内で 3 件観測した — #1273 (`ls tests/`)、#1279 (`command "bats tests/get-auto-session-report.bats"`)、#1287 (`command "bats tests/run-fact-matching.bats"`)。うち #1279 は `/issue` が独立に気づいて指摘したが、これはパターン文書の要求を超えた判断であり再現性がない。検出は機械的に可能: `command` 型 AC を実装前の main に対して実行し、既に exit 0 かつ AC 本文が新規カバレッジの追加を主張している場合に flag する。Tier 1 の根拠は positive-evidence gate の (b) と (c) — (b) 同型が本セッションだけで 3 件、(c) `skills/triage/skill-dev-verify-audit.md` は `/triage` Step 7 と `/issue` Step 15 の 2 skill が読む共有面

- **#1279 に記録した Tier 2 提案「AC 常時 PASS を検出した `/issue` の処置が Issue 間で一貫しない」は把握が不正確だった (訂正)**: #1287 の調査により、#1279 と #1287 の差は `/issue` の実行のばらつきではなく、監査パターン文書の被覆範囲の問題であることが判明した。#1287 で `/issue` が「問題なし」と報告したのは、当該形が Pattern 2 のどのサブパターンにも該当しないためで、実行ミスではない。上記の Tier 1 提案がこの系統の正しい対処にあたる
