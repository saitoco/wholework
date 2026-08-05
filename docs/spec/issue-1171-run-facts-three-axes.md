# Issue #1171: collect-run-facts: operate route / recovery tier / mode を実行事実 JSON に追加

## Overview

`scripts/collect-run-facts.sh` が出力する実行事実 JSON に、`/auto` 実行時に確定しているのに欠落・潰されている 3 軸 (operate route / recovery tier / mode) を追加する。#1118 の `when=` 実行文脈ゲートと #1157 の run-fact 照合が同じ SSoT を参照できる状態にすることが目的。

3 軸それぞれの現状と採用方針:

| 軸 | 現状 | 採用する表現 |
|---|---|---|
| operate route | `route` が `pr` / `patch` / `unknown` の 3 値。operate route も `run-code.sh --patch` 経由で `code-patch` phase を emit するため phase 名で判別できない | `route` に 4 値目 `operate` を追加。判別は `modules/phase-state.md` § "Operate Route Completion Signature" が既に定義済みの marker コメント (execution-log / execution-plan) を使う |
| recovery tier | `recovery` イベントは `tier=1\|2\|3` を emit しているが `anomalies.recovery` が件数に潰している | issue ごとに `recovery_tiers` 配列 (整数の昇順ユニーク) を追加。`anomalies.recovery` の件数は後方互換のため維持 |
| mode | JSON にフィールドが存在しない | top-level に `mode` (`batch` / `single` / `unknown`) を追加。`/auto` が session metadata に宣言した値を第一優先、イベント由来の推定をフォールバックとする |

## Changed Files

- `scripts/collect-run-facts.sh`: JQ_PASS1 に `first_ts` / `recovery_tiers` を追加、operate marker probe と freshness gate を per-issue ループに追加、session-level `mode` 解決ラダーを追加、`fact_tokens` を拡張、ヘッダコメントの `Per-issue fields` 節を更新 — bash 3.2+ 互換 (`mapfile` / `${VAR,,}` 不使用)
- `modules/run-fact-matching.md`: fact JSON のフィールド SSoT に `mode` / `route: operate` / `recovery_tiers` を追記し、Processing Steps step 3 の fail-safe 判定基準を新フィールド分だけ緩和
- `skills/auto/SKILL.md`: Step 1 の `.tmp/auto-session-${SESSION_ID}.json` 書き込みに `"mode"` キーを追加 (ARGUMENTS に `--batch` を含めば `batch`、含まなければ `single`)
- `tests/run-fact-matching.bats`: `missing events log` の完全一致アサーションを `mode` 追加に合わせて更新し、3 軸それぞれの positive / negative テストを追加
- `docs/structure.md`: [Steering Docs sync candidate] L205 の `scripts/collect-run-facts.sh` 一行説明に operate route 判別 / recovery tier / mode を反映
- `docs/ja/structure.md`: [Steering Docs sync candidate] L197 の同一行を日本語ミラーとして同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

「変更不要」と判断したファイル (grep 確認済み):

- `scripts/scan-pending-ac.sh`: fact JSON の消費は `jq -r '[.issues[].fact_tokens[]?] | unique | .[]'` のみ (L100)。top-level / per-issue のフィールド追加では壊れない
- `scripts/apply-run-fact-match.sh`: fact JSON を読まない (`--issue` / `--ac` / `--verdict` / `--evidence` の引数のみ)
- `docs/structure.md` L206 / `docs/ja/structure.md` L198 の `scan-pending-ac.sh` 行: 記述内容 (fact token による事前絞り込み) は変わらない

## Implementation Steps

1. `scripts/collect-run-facts.sh` の `JQ_PASS1` に 2 フィールドを追加する (→ acceptance criteria 2)
   - `first_ts: ($events | map(.ts) | min)` — operate marker の freshness gate で使う、この run における当該 Issue の最初のイベント時刻
   - `recovery_tiers: ([$events[] | select(.event == "recovery") | .tier // empty | tonumber?] | unique)` — `emit_event()` は全 kv 値を文字列で書くため `tonumber?` で整数化する。`tonumber?` は非数値を静かに落とすので `tier` 欠落や破損値でも失敗しない。`unique` は jq の仕様で昇順ソートも兼ねる。該当イベントがなければ `[]`
   - `anomalies.recovery` の件数計算は既存のまま変更しない (後方互換)

2. `scripts/collect-run-facts.sh` の per-issue ループに operate route probe を追加する (after 1) (→ acceptance criteria 1)
   - `FACTS_PARTIAL` から `route` と `first_ts` を取り出し、`route` が `patch` かつ `NO_GITHUB=false` のときだけ以下を実行する (`pr` / `unknown` のときは probe しない — operate route は必ず `run-code.sh --patch` 経由で `code-patch` を emit するため)
   - `gh issue view "$N" --json comments --jq "[.comments[] | select(.body | contains(\"<!-- wholework-event: type=execution-log phase=code issue=${N}\") or contains(\"<!-- wholework-event: type=execution-plan phase=code issue=${N}\")) | .createdAt] | sort | last // empty"` で marker コメントの最新 `createdAt` を取る (`scripts/reconcile-phase-state.sh` の `_operate_signal_ts()` と同一クエリ)
   - ISO8601 形状 (`[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*`) の `case` マッチでガードし、形状不一致なら空文字に落とす (degraded な `gh` 出力を marker と誤認しない)
   - freshness gate: marker の `createdAt` が `first_ts` より後 (`[ "$OPERATE_TS" \> "$FIRST_TS" ]` による文字列比較 — 双方 ISO8601 UTC なので辞書順比較で正しい) のときだけ `ROUTE="operate"` にする。過去の operate cycle が残した stale marker が後続の patch run を誤ラベルするのを防ぐ
   - `JQ_PASS2` は `$partial.route` ではなく `--arg route "$ROUTE"` で解決済みの値を受け取るよう変更する

3. `scripts/collect-run-facts.sh` に session-level `mode` 解決ラダーを追加する (parallel with 1, 2) (→ acceptance criteria 3)
   - 優先順 (exhaustive): (a) `.tmp/auto-session-${SESSION_ID}.json` の `.mode` が `batch` または `single` ならその値、(b) イベント由来フォールバック — session 内で `sub_start` イベントを持つ非ゼロ Issue 番号が 2 件以上なら `batch`、session にイベントが 1 件以上あってこの条件を満たさなければ `single`、(c) session イベントが 0 件なら `unknown`
   - **`--issue` フィルタ適用前の全 session イベントに対して判定する**。`ISSUE_NUMBERS` を絞り込んだ後の集合で数えると `--issue` の有無に mode が依存してしまい、受け入れ条件を満たさない
   - 出力の 3 経路すべて (イベントログ不在 / session イベント 0 件 / 通常経路) に `mode` を含め、フィールド順は `{session_id, mode, issues}` で固定する。前 2 経路は `unknown`

4. `scripts/collect-run-facts.sh` の `fact_tokens` を拡張し、ヘッダコメントを更新する (after 1, 2, 3) (→ acceptance criteria 1, 2, 3, 4)
   - tier token: `(.recovery_tiers | map("tier " + tostring))` — `scan-pending-ac.sh` の事前絞り込みは token を小文字化して AC 条件文への部分一致で判定するため、`tier 2` が「Tier 2/3 recovery の発火」に一致する
   - mode token: top-level `mode` が `batch` のときのみ、各 issue の `fact_tokens` に `"batch"` を追加する。`single` のときは token を追加しない (`single` は汎用語すぎて事前絞り込みが no-op 化する — `/auto` token を除外した #1157 と同じ理由)
   - operate token は既存の `(.route + " route")` 式が `"operate route"` を自動生成するので追加実装不要
   - ヘッダコメントの `Per-issue fields` 節に `recovery_tiers` を追記し、`route` の値域を `pr | patch | operate | unknown` に更新、top-level `mode` の説明と `--no-github` 時に operate 判別がスキップされる旨を追記する

5. `modules/run-fact-matching.md` を fact JSON の SSoT として更新する (after 4) (→ acceptance criteria 4)
   - fact JSON のフィールド一覧に `mode` (top-level, `batch` / `single` / `unknown`)、`route` の `operate` 値、per-issue `recovery_tiers` を追記する
   - Processing Steps step 3 の fail-safe 判定基準を、新たに表現可能になった 3 軸の分だけ緩和する: route / recovery tier / mode に言及する条件文は「facts JSON に表現がない」を理由に自動的に `ambiguous` とはしない。ただし `--no-github` 実行時は operate 判別がスキップされ `route` が `patch` に留まる点は明記し、この場合は引き続き `ambiguous` とする
   - 「否定形の主張」の判定基準に `recovery_tiers` を追加する: 「Tier N recovery が発火していない」は `recovery_tiers` に N が含まれないことで判定できる

6. `skills/auto/SKILL.md` Step 1 の session metadata 書き込みに `mode` を追加する (parallel with 5) (→ acceptance criteria 3)
   - `.tmp/auto-session-${SESSION_ID}.json` の JSON テンプレート (`session_id` / `session_start` / `skill_versions` を持つコードフェンス) に `"mode": "<batch|single>"` を追加する
   - 挿入位置は `"session_start"` の直後 (`"skill_versions"` の直前)
   - 値の決め方をテンプレート直後の説明文に追記する: ARGUMENTS に `--batch` が含まれるなら `batch`、含まなければ `single`。XL の sub-issue fan-out は `--batch` ではないので `single` になる
   - 半角感嘆符・triple backtick を本文に入れない (`scripts/validate-skill-syntax.py` の制約)

7. `tests/run-fact-matching.bats` に 3 軸のテストを positive / negative 込みで追加する (after 1, 2, 3, 4) (→ acceptance criteria 5, 6)
   - 既存 `collect-run-facts: missing events log yields empty issues array` の完全一致アサーションを `{"session_id":"sess1","mode":"unknown","issues":[]}` に更新する
   - operate: positive — `code-patch` の fixture + `$MOCK_DIR/gh` mock が `first_ts` より後の `createdAt` を持つ execution-log marker コメントを返す → `route == "operate"` かつ `fact_tokens` に `operate route` を含む。negative — 同じ fixture で marker を返さない mock → `route == "patch"` かつ `fact_tokens` に `operate route` を含まない
   - recovery tier: positive — `tier=2` / `tier=3` の `recovery` イベント → `recovery_tiers == [2,3]`、`anomalies.recovery == 2`、`fact_tokens` に `tier 2` / `tier 3`。negative — `recovery` イベントなし → `recovery_tiers == []` かつ `tier ` 始まりの token なし
   - mode: positive — `.tmp/auto-session-sess1.json` に `{"mode":"batch"}` を置く → `mode == "batch"` かつ `fact_tokens` に `batch`。positive (フォールバック) — 2 Issue が `sub_start` を持つ fixture で metadata なし → `mode == "batch"`。negative — 単一 Issue で metadata なし → `mode == "single"` かつ `batch` token なし。さらに `--issue` を付けた実行でも `mode == "batch"` が変わらないことを確認する
   - mock 追加: operate テストは `--no-github` を外して実行するため、`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` 配下に `get-issue-size.sh` mock を追加し、`gh` mock は `issue view --json comments` と `pr view` の両方を扱えるようにする

8. `docs/structure.md` と `docs/ja/structure.md` の `collect-run-facts.sh` 一行説明を同期更新する (after 4) (→ acceptance criteria 4)
   - 英語版 L205: `(route, Size, phase outcomes, PR state, anomaly counts, fact tokens)` を `(route including the diff-less operate value, run mode, Size, phase outcomes, PR state, anomaly counts, recovery tiers, fact tokens)` 相当に更新
   - 日本語版 L197: `(route・Size・各 phase の結果・PR 状態・anomaly 件数・fact token)` を対応する日本語表現に同期

## Alternatives Considered

| 軸 | 不採用案 | 不採用の理由 |
|---|---|---|
| operate route | `/code` の operate 分岐から専用イベントを emit する | operate 判別は `skills/code/SKILL.md` Step 0 の LLM 判定で、emit も LLM 駆動になる。`modules/l0-surfaces.md` が LLM 駆動 emit の取りこぼしを明記しており信頼性が落ちる。marker コメントは `/code` Step 11 が必ず投稿し `reconcile-phase-state.sh` が既に完了シグネチャとして採用済みのため、新規シグナルを増やさずに済む |
| operate route | PR 不在 + Spec の `## Changed Files` 空を読む | Spec ファイルの再パースが必要で、`/spec` が operate と判定した時点の内容と `/code` 実行時の内容が一致する保証がない。marker はイベントそのもの |
| recovery tier | `anomalies.recovery` を件数から `{tier: count}` オブジェクトに変更する | 破壊的変更。`fact_tokens` の `(.anomalies \| to_entries \| map(select(.value >= 1) \| .key))` が壊れ、受け入れ条件 4 (後方互換) に反する |
| mode | 新規イベント `batch_start` を `/auto` batch 経路から emit する | Count mode は `BATCH_ID` を持たず `auto-checkpoint.sh write_batch` も呼ばないため、bash 側の決定的なフックがない。SKILL.md prose への emit 追加は session metadata への 1 キー追加と信頼性が同等で、touch point が多い |
| mode | 相異なる Issue 番号の件数だけで判定する | batch 1 件のケースと単一 Issue が区別できず、XL の sub-issue fan-out も batch と誤判定する。宣言を第一優先にすることでこの 2 つを解消し、宣言が無い場合のフォールバックとしてのみ残す |

## Verification

### Pre-merge

- <!-- verify: rubric "collect-run-facts.sh が operate route を patch route と区別して表現できる。run-code.sh が operate route でも code-patch phase を emit するため phase 名だけでは判別できない点が実装で考慮され、代替シグナルを用いていること" --> operate route が fact JSON で表現できる
- <!-- verify: rubric "collect-run-facts.sh が recovery の tier (1/2/3) を保持する。recovery イベントは tier=N を emit しているが現行の anomalies は件数に潰しているため、tier 依存の照合ができない状態が解消されていること" --> recovery tier が fact JSON に保持される
- <!-- verify: rubric "collect-run-facts.sh の出力が batch mode と single-issue mode を区別できる。--issue フィルタの有無に依存しない形で、収集結果自体から mode が読み取れること" --> mode が fact JSON で表現できる
- <!-- verify: rubric "既存の fact JSON の消費側 (scripts/scan-pending-ac.sh の fact_tokens 事前絞り込み、modules/run-fact-matching.md の rubric 判定手順) が、追加フィールドによって壊れていない。後方互換が保たれているか、破壊的変更である場合は消費側も併せて更新されていること" --> 既存の消費側との互換が保たれている
- <!-- verify: rubric "tests/run-fact-matching.bats に、operate route の判別・recovery tier の保持・mode の区別をそれぞれ検証するテストが追加されている。いずれも該当しない場合の negative case を含むこと" --> 3 軸それぞれのテストが negative case 込みで存在する
- <!-- verify: command "bats tests/run-fact-matching.bats" --> `tests/run-fact-matching.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト全件が CI で PASS する (pr route)

### Post-merge

- operate route の `/auto` を完走させ、`scripts/collect-run-facts.sh` の出力で当該 Issue の route が patch と区別されていることを確認する

## Tool Dependencies

### Bash Command Patterns

- なし (`collect-run-facts.sh` は `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*` として既に `skills/auto/SKILL.md` の `allowed-tools` に登録済み。新規 `scripts/*.sh` の追加はないため allowed-tools impact chain check は該当なし)

### Built-in Tools

- なし (既存の Read / Edit / Write で足りる)

### MCP Tools

- なし

## Uncertainty

- **`--no-github` 実行時に operate route を判別できない**: `gh issue view` を呼べないため `route` は `patch` に留まる。
  - **検証方法**: bats テスト (hermetic 実行はすべて `--no-github`) と、`modules/run-fact-matching.md` の fail-safe 記述で明示的に扱う
  - **影響範囲**: Implementation Steps 2, 4, 5。`/auto` の本番経路は `--no-github` を渡さないため実運用の判別能力には影響しない
- **イベント由来フォールバックが XL の sub-issue fan-out を `batch` と誤判定する**: `sub_start` は batch 経路と XL 経路の双方で `run-auto-sub.sh` から emit されるため、両者をイベントだけで区別する信号がない。
  - **検証方法**: `/auto` Step 1 の宣言 (`mode: single`) が第一優先で解決するため、宣言が書かれた session では誤判定しない。宣言が無い過去 session に対してのみ発生する既知の劣化として `modules/run-fact-matching.md` に明記する
  - **影響範囲**: Implementation Steps 3, 5, 6

## Notes

### 非対話モードの Auto-Resolve Log

`--non-interactive` のため、以下 3 点をモデル判断で自動解決した (Issue 側にも retrospective コメントとして記録)。

1. **operate route の代替シグナル選定** → marker コメント (execution-log / execution-plan) 方式を採用。根拠: `modules/phase-state.md` § "Operate Route Completion Signature" が既に SSoT としてこのシグネチャを定義し、`scripts/reconcile-phase-state.sh` の `_operate_signal_ts()` が同一クエリを実装済み。新しい検出方式を持ち込むと Spec 段階のツール検出パターン整合性チェックに反する
2. **mode の決定ソース** → session metadata 宣言を第一優先、イベント由来推定をフォールバックとする 2 段ラダーを採用。根拠: 宣言のみだと過去 session や書き込み漏れで解決不能、推定のみだと batch 1 件と XL fan-out を誤判定する。両者の弱点が相補的
3. **recovery tier の表現形** → `anomalies.recovery` の件数を維持したまま `recovery_tiers` 配列を追加する加算的変更を採用。根拠: 受け入れ条件 4 が後方互換を要求しており、`fact_tokens` の `anomalies` 走査式を壊さない

### 実装上の注意

- `emit_event()` は kv 値をすべて文字列として書き出すため、`recovery` イベントの `tier` は `"1"` / `"2"` / `"3"` の文字列である。`recovery_tiers` を整数配列にするには `tonumber?` による変換が必須
- `first_ts` と marker の `createdAt` はどちらも ISO8601 UTC (`%Y-%m-%dT%H:%M:%SZ`) なので、`date` 変換なしの辞書順比較で正しく前後判定できる (`modules/l0-surfaces.md` の cutoff 比較と同じ前提)
- `scan-pending-ac.sh` の token 判定は token を小文字化したうえで AC 条件文への部分一致 (`case "$TEXT_LOWER" in *"$tok"*`) なので、token は短いほど広く当たる。`single` を token 化しない判断はこの性質による
- `docs/structure.md` は top-level `docs/*.md` なので `docs/translation-workflow.md` の Sync Procedure 対象。`docs/ja/structure.md` を同一 PR で同期する
- bash 3.2 互換 (macOS system bash) を維持する。`mapfile` / `${VAR,,}` / 連想配列は使わない
- Issue body の post-merge observation AC には、Step 10 の verify-type タグチェックに従い「期待する出力構造」のサブ項目を追記した (Option A の 2 部構成)

## Consumed Comments

No new comments since last phase.

## spec retrospective

### Minor observations

- Issue 本文の「軸」表が既に `run-code.sh` の該当行番号 (L112-116) や `run-auto-sub.sh` の emit 行 (L1054 / L1071 / L1094) まで特定していたため、codebase investigation は事実確認だけで済んだ。三軸それぞれの「現状の潰れ方」を Issue 段階で行番号付きで書いておくと spec phase の探索コストがほぼゼロになる好例
- `modules/phase-state.md` § "Operate Route Completion Signature" は `reconcile-phase-state.sh` 専用の記述として書かれているが、実質は「operate route を外形から判別する唯一の SSoT シグネチャ」である。本 Issue で 2 つ目の消費側 (`collect-run-facts.sh`) ができるため、将来 3 つ目が現れたら shared helper への切り出しを検討する余地がある

### Judgment rationale

- **operate 判別を `route == "patch"` のときだけ probe する設計にした理由**: `skills/auto/SKILL.md` L399 と `skills/code/SKILL.md` L84 の双方が「operate route は必ず `run-code.sh --patch` 経由」と明記している。`pr` / `unknown` のときに probe しても marker は原理的に見つからず、`gh` 呼び出しが純粋な無駄になる
- **freshness gate に reopen timestamp ではなく「この run の最初のイベント時刻」を使った理由**: `reconcile-phase-state.sh` は「phase が完了したか」を判定するので reopen 基準が正しいが、`collect-run-facts.sh` は「この session の run で何が起きたか」を構造化する。session スコープに合わせるほうが意味論的に正しく、`get-last-reopen` の追加呼び出しも不要になる
- **`single` を fact token 化しなかった理由**: #1157 が `/auto` token を除外した実測根拠 (414 件中 84 件にマッチして事前絞り込みが no-op 化) と同型の判断。`single` は汎用語すぎる。`batch` は語として十分に稀

### Uncertainty resolution

- **設計時の不確実性「mode を決定的に取れるか」**: `emit_event` の全 kv を洗い出した結果、batch/single を区別する既存イベントは存在しないことを確認した。`auto-checkpoint.sh write_batch` は List mode 専用で Count mode が通らないため bash 側の決定的フックにならない、という点まで確認したうえで session metadata 宣言方式を採った
- **未解決のまま残した点**: イベント由来フォールバックが XL sub-issue fan-out を `batch` と誤判定する。`sub_start` は batch 経路と XL 経路の双方で `run-auto-sub.sh` から emit されるため、イベントだけでは区別する信号がない。宣言が第一優先なので新規 session では発生せず、宣言の無い過去 session に限る既知の劣化として Uncertainty 節に記録した

## Code Retrospective

### Deviations from Design

- N/A — 実装は Spec の Implementation Steps 1-8 をそのままの順序・内容で実装した

### Design Gaps/Ambiguities

- N/A — Spec の設計判断 (marker コメント方式、加算的フィールド追加、2段ラダー) はいずれも実装時に迷いなく適用できた

### Rework

- N/A

### Verification notes

- 実装後 `bats tests/run-fact-matching.bats` を単体実行して 26/26 PASS を確認し、続けて `skills/auto/SKILL.md` の変更が behavioral change 検出 (テスト参照チェック) に該当したためフルスイート `bats tests/` を実行し 1402/1402 PASS を確認した
- `scripts/validate-skill-syntax.py` と `scripts/check-forbidden-expressions.sh` はいずれも新規エラーなし (`skills/auto/SKILL.md` の既存 warning `unknown field: 'loop-paths-fallback'` は本 Issue の変更と無関係の既存項目)
- `scripts/check-translation-sync.sh` で `docs/structure.md` / `docs/ja/structure.md` が IN_SYNC であることを確認した (他ファイルの MISSING_JA/OUTDATED は本 Issue のスコープ外の既存項目)

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の Implementation Steps 1-8 を設計どおりの順序で実装。逸脱・設計判断の再検討は発生しなかった (`## Code Retrospective` 参照)
- Pre-merge AC のうち rubric 系 5 件と `bats tests/run-fact-matching.bats` の command 系 1 件はこの phase 内でチェック済み。`github_check "gh pr checks" "Run bats tests"` は CI 実行後でないと確認できないため未チェックのまま残した
- `skills/auto/SKILL.md` の変更が既存の behavioral change 検出条件 (直接対応テスト以外からの参照) に該当したため、`bats tests/run-fact-matching.bats` の単体実行に加えてフルスイート `bats tests/` (1402件) を実行して回帰がないことを確認した

### Deferred Items

- `--no-github` 実行時は operate 判別をスキップし `route` は `patch` に留まる (spec Uncertainty 記載どおり、設計上の既知の制約であり本 Issue では対応しない)
- イベント由来フォールバックによる XL fan-out の `batch` 誤判定は修正しない (spec Uncertainty 記載どおり)
- Post-merge AC (operate route での `/auto` 完走確認) は `/verify` で検証する

### Notes for Next Phase

- `github_check "gh pr checks" "Run bats tests"` の Pre-merge AC は CI 結果待ちのため未チェック。`/review` で CI green を確認したうえでチェックすること
- Post-merge AC は operate route の `/auto` を実際に完走させ、`route: operate` と `fact_tokens` の `operate route` トークンが出力されることを確認する必要がある (hermetic テストでは `--no-github` のため代替不可)
- `docs/guide/index.md` (OUTDATED) と `docs/guide/autonomy.md` (MISSING_JA) の翻訳ギャップは `scripts/check-translation-sync.sh` で検出済みだが、本 Issue のスコープ外の既存項目 (本 Issue が変更した `docs/structure.md` とは無関係)
