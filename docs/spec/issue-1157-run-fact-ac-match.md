# Issue #1157: auto/verify: /auto 実行の事実から充足済み AC を検出し phase/verify 滞留を解消

## Overview

`/auto` 完走時に、その実行の**事実** (route / Size / 各 phase の結果 / PR 番号と状態 / `.tmp/auto-events.jsonl` のイベント列) を構造化して収集し、`phase/verify` に滞留する Issue の pending post-merge AC と照合して、充足された AC を検出する。検出結果は autonomy tier でゲートし、L1 は候補提示のみ、L2/L3 は自動チェックする。照合が曖昧な場合は tier を問わず候補提示に倒す (fail-safe)。

**対応方針の確定: 案 B (実行事実の構造化を独立スクリプトに切り出す) を採用。** 根拠は「Alternatives Considered」参照。

パイプラインは 3 スクリプト + 1 module + `/auto` からの呼び出しで構成する:

```
/auto 完走
  → (既存) Event-based observation scan
  → (新規) Run-fact AC reconciliation
       1. collect-run-facts.sh    … 実行事実を JSON 化 (決定的)
       2. scan-pending-ac.sh      … pending post-merge AC を列挙し fact token で事前絞り込み (決定的)
       3. LLM rubric 判定          … 条件文 × 実行事実 → verdict (satisfied / not_satisfied / ambiguous)
       4. apply-run-fact-match.sh … tier ゲート + fail-safe + 自動チェック/候補提示 (決定的)
```

LLM 判定を中央の 1 段のみに閉じ込め、その前後を決定的スクリプトで挟むことで、AC5 が要求する 3 経路 (検出 / 非検出 / 曖昧時フォールバック) を bats で検証可能にする。

### 母集団の実測 (2026-08-05 時点)

| 指標 | 実測値 |
|---|---|
| `phase/verify` かつ closed の Issue 数 | 312 |
| うち未チェック post-merge AC を持つ Issue 数 | 306 |
| 未チェック post-merge AC 総数 | 414 |
| verify-type 内訳 | manual 244 / opportunistic 132 / observation 34 / auto 4 |
| fact token 事前絞り込み後の候補数 (route=pr / Size L / PR #1151 の実行を想定) | **17** |

- **計測スコープ**: `gh issue list --label "phase/verify" --state closed --json number,body --limit 400` の全件。各 Issue body の `### Post-merge` または `## Post-merge` 見出し以降 (次の `##`/`###` 見出しまで) の `- [ ]` 行のみ。`verify-type` タグなしの行は `manual` として計上 (`/verify` Step 8b の扱いに合わせた)
- **計測コマンド**: 上記 `gh issue list` の出力を Python で節スキャンして集計
- **事前絞り込みの token 集合** (計測時): `pr route` / `patch route` / `size l` / `run-review.sh` / `run-code.sh` / `run-merge.sh` / `run-spec.sh` / `#1151`。汎用トークン `/auto` は**意図的に除外**した (単独で 414 件中 84 件にヒットし、絞り込みとして機能しないため)

414 件を毎回 LLM に投げるのは非現実的だが、17 件なら 1 回の rubric 判定で扱える。この事前絞り込みが設計の要である。

## Changed Files

- `scripts/collect-run-facts.sh`: 新規。`/auto` 実行事実を単一行 JSON で stdout 出力 — bash 3.2+ 互換 (`mapfile` / `${VAR,,}` を使わず `tr` を使用)
- `scripts/scan-pending-ac.sh`: 新規。`phase/verify` closed Issue の未チェック post-merge AC を列挙し、`--facts` で fact token 事前絞り込みを行う — bash 3.2+ 互換
- `scripts/apply-run-fact-match.sh`: 新規。verdict × autonomy tier の決定的ゲートと反映 (自動チェック / 候補提示 / 何もしない) — bash 3.2+ 互換
- `modules/run-fact-matching.md`: 新規。照合手順の SSoT (Purpose / Input / Processing Steps / Output の 4 節構造)。verdict 契約・fail-safe 判定基準・marker 形式を定義
- `modules/autonomy-tier.md`: `### Tier × External System Write (operate route)` 節の直後に `### Tier × Run-Fact AC Match` 節を追加
- `skills/auto/SKILL.md`: 2 箇所 (single-issue route の "Event-based observation scan (auto-run event, ...)" 直後、batch route の "Event-based observation scan (batch, best-effort)" 直後) に Run-fact AC reconciliation ブロックを追加。frontmatter `allowed-tools` に 3 スクリプトの literal エントリを追加
- `tests/run-fact-matching.bats`: 新規。3 スクリプトを feature 単位でカバー。AC5 の 3 経路を `apply-run-fact-match.sh --dry-run` で検証
- `docs/structure.md`: Modules 一覧に `modules/run-fact-matching.md`、Scripts 一覧 (`observation-trigger.sh` 近傍) に新規 3 スクリプトの行を追加
- `docs/ja/structure.md`: `docs/structure.md` の対応箇所を日本語でミラー (`docs/translation-workflow.md` の同期手順に従う)

**Steering Docs sync candidate** (`/code` フェーズで各ファイルを読んで最終判断すること):

- `docs/workflow.md`: `/auto` 完走時の挙動が増えるため、`phase/verify` 残留の説明 (L223 / L262 付近の "All auto-verify PASS + opportunistic/observation/manual unchecked → phase/verify") に本機構への言及が必要か確認。追記した場合は `docs/ja/workflow.md` も同期 (translation-workflow.md の対象)
- `docs/guide/autonomy.md`: L1/L2/L3 のユーザ向け説明に run-fact AC match のゲートを追記すべきか確認 (`docs/ja/guide/autonomy.md` は存在しないためミラー義務なし)
- `docs/guide/customization.md` / `docs/ja/guide/customization.md`: 本 Spec では `.wholework.yml` に新規キーを追加しない方針のため原則変更不要。上限値を config 化する判断に変えた場合のみ Available Keys テーブルへの行追加が必要
- `modules/observation-trigger.md`: 「event 名マッチのみ」という現行スコープの記述が本機構の追加後も正確か確認 (相補関係への相互参照 1 行の追加が候補)
- `modules/l0-surfaces.md`: 新規 marker `type=run-fact-ac-match` を Machine-Readable Event Marker 節に追記するか確認。`type=observation-trigger` が `modules/observation-trigger.md` 側に記載されている前例に倣い、本 Spec では `modules/run-fact-matching.md` 側に記載する方針とした
- `docs/tech.md`: 環境変数テーブルに新規変数を追加しない方針 (既存の `AUTO_EVENTS_LOG` / `AUTO_SESSION_ID` / `WHOLEWORK_SCRIPT_DIR` / `WHOLEWORK_CONFIG_PATH` のみ使用) のため原則変更不要

「変更不要」と記載した項目はいずれも grep で参照箇所を確認済みだが、実装内容が Spec からずれた場合は判断が変わるため `/code` で再確認すること。

## Implementation Steps

1. `scripts/collect-run-facts.sh` を新規作成する (→ acceptance criteria AC1)

   - Usage: `collect-run-facts.sh [--session <session-id>] [--issue <N>] [--no-github]`
   - session 解決順: `--session` 引数 → `AUTO_SESSION_ID` 環境変数 → `.tmp/auto-session-current` ポインタ。いずれも解決できなければ exit 1
   - `${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}` を `session_id` で絞り込む。ファイルが存在しない場合は `{"session_id":"<id>","issues":[]}` を出力して exit 0 (fail-open)
   - Issue ごとに以下を組み立て、単一行 JSON として stdout に出力する:
     - `number` — `.issue` フィールド
     - `size` — イベント列中の `sub_start.size` (存在すれば最新の `size_refresh` を優先)。イベントに無い場合は `get-issue-size.sh <N>` にフォールバック。`--no-github` 指定時および解決不能時は空文字列
     - `route` — `code-pr` phase があれば `pr`、`code-patch` phase があれば `patch`、いずれも無ければ `unknown`
     - `pr` — 当該 Issue のイベントに現れる `pr` フィールドの値 (無ければ `null`)
     - `pr_state` — `gh pr view <pr> --json state -q .state` の結果。`--no-github` 指定時・PR 番号なし・取得失敗時は空文字列
     - `phases` — `[{"name":..., "status":"complete"|"started", "backfilled":true|false}]`。`phase_complete` があれば `complete`、`phase_start` のみなら `started`
     - `anomalies` — `recovery` / `watchdog_kill` / `manual_intervention` / `concurrent_commit_detected` / `code_retry_fire` の各イベント件数 (exhaustive)
     - `fact_tokens` — 後段の事前絞り込み用トークン配列。生成規則は Step 2 と共有するため本スクリプト側で確定させる (下記)
   - `fact_tokens` の生成規則 (exhaustive):
     - `route` が `unknown` 以外のとき `"<route> route"` (例 `pr route`)
     - `size` が空でないとき `"Size <SIZE>"` (例 `Size L`)
     - 実行された各 phase 名 (`issue` / `spec` / `code-pr` / `code-patch` / `review` / `merge` / `verify`) と、その wrapper スクリプト名 (`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh`)。`verify` は wrapper が存在しないため phase 名のみ
     - `pr` が非 null のとき `"#<pr>"`
     - `anomalies` のうち件数が 1 以上のイベント名
     - 汎用トークン `/auto` は**含めない** (Overview の実測どおり絞り込みが機能しなくなるため)。この除外理由をスクリプトのヘッダコメントに明記する
   - `--no-github` 指定時は `gh` および `get-issue-size.sh` を一切呼ばない (bats のヘルメティック実行用)
   - jq パイプラインは失敗時に `|| { echo "Error: ..." >&2; exit 1; }` でガードする

2. `scripts/scan-pending-ac.sh` を新規作成する (parallel with 1) (→ acceptance criteria AC2)

   - Usage: `scan-pending-ac.sh [--facts <path>] [--limit <N>] [--max-candidates <N>]`
   - Issue 取得は `gh issue list --label "phase/verify" --state closed --json number,body --limit ${LIMIT:-400}` の **1 回の API 呼び出し**で行う (Issue ごとの `gh issue view` ループは使わない。312 件で実測 4.1 秒)
   - 各 Issue body について:
     - グローバル 1-based チェックボックス index を body 全体の `^- \[[ xX]\]` 行で数える (`scripts/gh-issue-edit.sh` および `scripts/check-pre-merge-ac.sh` と同一規約。`gh-issue-edit.sh --checkbox` にそのまま渡せる値であること)
     - `^### Post-merge` または `^## Post-merge` 見出しの次行から、次の `^##` / `^### ` 見出しまでを post-merge 節とする (`check-pre-merge-ac.sh` の Pre-merge 節範囲定義と同型)
     - post-merge 節内の `^- \[ \]` 行を候補として抽出する
     - `verify_type` は行内の `verify-type: <t>` から取得し、**タグが無い行は `manual` とする** (`skills/verify/SKILL.md` Step 8b の「verify command も verify-type も無い条件は manual として扱う」規約に一致)。`manual` / `observation` / `opportunistic` / `auto` のいずれも除外しない — AC2 が要求する「manual AC も照合対象に含まれる」はここで実現される
     - `condition` はチェックボックス記法と `<!-- ... -->` を除去したテキスト
   - `--facts <path>` が指定されたとき: `fact_tokens` 配列を読み、いずれか 1 つ以上が `condition` に大小文字を無視した部分一致でヒットする行のみを残す。`--facts` 未指定時は全件通過 (後方互換・デバッグ用)
   - `--max-candidates` (デフォルト 30) で件数を打ち切る。打ち切った場合は stderr に `Note: truncated N candidate AC(s) to <max>; deferred to the next run.` を出力する (silent cap を作らない)
   - `gh issue list` の返却件数が `--limit` と一致した場合は stderr に `Warning: issue list hit the --limit <N> cap; some phase/verify Issues were not scanned.` を出力する
   - 出力は JSON 配列 `[{"number":N,"ac_index":I,"verify_type":"manual","condition":"..."}]`。該当なしは `[]`
   - `gh` 呼び出し失敗時は `[]` を出力して exit 0 (fail-open — `/auto` を止めない)

3. `scripts/apply-run-fact-match.sh` を新規作成する (after 1, 2) (→ acceptance criteria AC3, AC4)

   - Usage: `apply-run-fact-match.sh --issue <N> --ac <index> --verdict satisfied|not_satisfied|ambiguous [--evidence <text>] [--dry-run]`
   - tier 解決: `AUTONOMY_TIER` 環境変数 → `"${SCRIPT_DIR}/get-config-value.sh" autonomy L1`。`L1` / `L2` / `L3` 以外は `L1` にフォールバック (`modules/detect-config-markers.md` の既存規約と一致)
   - verdict × tier ゲート表 (exhaustive):

     | verdict | L1 | L2 | L3 |
     |---|---|---|---|
     | `satisfied` | `advisory` | `auto-check` | `auto-check` |
     | `ambiguous` | `advisory` | `advisory` | `advisory` |
     | `not_satisfied` | `none` | `none` | `none` |

   - **fail-safe**: `--verdict` が未指定・空・上記 3 値以外の場合は `ambiguous` として扱い、stderr に `Warning: unknown verdict '<v>', treating as ambiguous (fail-safe).` を出力する。曖昧側は tier を問わず `auto-check` に到達しない
   - stdout の 1 行目は常に `action=<auto-check|advisory|none>`
   - `advisory` のとき 2 行目に `Recommend: /verify <N> — post-merge AC #<index> may be satisfied by this run (<evidence>)` を出力する (`modules/autonomy-tier.md` path A の `Recommend:` プレフィックス慣行に従う。Issue コメント化はしない)
   - `auto-check` かつ `--dry-run` 無指定のとき、この順で実行する:
     1. `"${SCRIPT_DIR}/gh-issue-edit.sh" <N> --checkbox <index> --check`
     2. `"${SCRIPT_DIR}/gh-issue-comment.sh"` で監査証跡コメントを投稿。1 行目に marker `<!-- wholework-event: type=run-fact-ac-match phase=run-fact-match issue=<N> ac=<index> verdict=satisfied -->` を置き、2 行目以降に evidence を人間可読で書く
     - いずれかが失敗した場合は stderr に警告を出して exit 0 (fail-open — `/auto` を中断させない)
   - `--dry-run` のときは L0 書き込みを一切行わず、解決した `action=` 行 (および advisory 行) のみ出力する
   - 引数不正は exit 1、それ以外は exit 0

4. `modules/run-fact-matching.md` を新規作成する (after 3) (→ acceptance criteria AC2, AC3, AC4)

   - CLAUDE.md の "Standard Structure Template for Shared Modules" に従い Purpose / Input / Processing Steps / Output の 4 節構造とする
   - **Input**: `AUTO_SESSION_ID` (呼び出し元 `/auto` が保持)、`AUTONOMY_TIER`
   - **Processing Steps**:
     1. `collect-run-facts.sh` を実行し `.tmp/run-facts-${AUTO_SESSION_ID}.json` に保存する
     2. `scan-pending-ac.sh --facts .tmp/run-facts-${AUTO_SESSION_ID}.json` を実行し候補 AC 配列を得る。空配列なら以降をスキップし `Run-fact AC reconciliation: no candidates.` を出力して終了
     3. **rubric 判定 (LLM、1 回のバッチ判定)**: 実行事実 JSON と候補 AC 配列を突き合わせ、各 AC に `satisfied` / `not_satisfied` / `ambiguous` を割り当てる
     4. 各 AC について `apply-run-fact-match.sh` を呼び、返された `action=` に従って処理する
     5. 集計行を出力する: `Run-fact AC reconciliation: <auto-checked> auto-checked, <advisory> advisory, <skipped> not satisfied (candidates: <N>).`
   - **fail-safe 判定基準 (`ambiguous` を返さなければならないケース、exhaustive)**:
     - 条件文が参照する事実が実行事実 JSON に存在しない (代表例: `/review` の depth `--full` / `--light`。`.tmp/auto-events.jsonl` の `phase` 値は `review` のみで depth を記録しない — 「Uncertainty」参照)
     - 条件文が「〜が起きなかった」という不在主張であり、対応するシグナルが `anomalies` の観測対象イベント名 (exhaustive な 5 種) に含まれていない
     - 条件文が複数の下位条件の連言であり、そのうち一部しか実行事実で裏付けられない
     - 上記に当てはまらなくても判断に迷う場合は `ambiguous` を選ぶ (既定値)
   - `satisfied` を返してよいのは、条件文の全下位条件が実行事実 JSON の値から直接読み取れる場合に限る
   - marker 形式 `<!-- wholework-event: type=run-fact-ac-match phase=run-fact-match issue=<N> ac=<index> verdict=satisfied -->` を定義する。`phase=` が固定リテラルであること (workflow phase 名ではないこと) と、その理由が `modules/observation-trigger.md` の `phase=observation-trigger` と同じであることを明記する
   - コメント蓄積が起きない理由を明記する: `auto-check` は同時にチェックボックスを立てるため当該 AC は次回スキャンで候補にならない。`advisory` はターミナル出力のみで L0 に書き込まない (#1026 で観測されたコメント蓄積の再発を構造的に防ぐ)

5. `modules/autonomy-tier.md` に `### Tier × Run-Fact AC Match` 節を追加する (after 4) (→ acceptance criteria AC3)

   - 挿入位置: `### Tier × External System Write (operate route)` 節の直後、`## \`.wholework.yml\` Schema` 節の直前
   - Step 3 のゲート表と同じ内容を掲載し、L1 が path A (Advisory) セマンティクスの再利用であることを明記する
   - `modules/run-fact-matching.md` への相互参照を張る
   - 誤検出リスクを根拠として「曖昧時は tier を問わず advisory」を明記する (AC4 が要求する「ドキュメント側の明記」の一方)

6. `skills/auto/SKILL.md` に呼び出しを配線する (after 4) (→ acceptance criteria AC1, AC2, AC3, AC4)

   - frontmatter `allowed-tools` の `Bash(...)` リストに以下 3 つの literal エントリを追加する (ワイルドカードでは `scripts/validate-skill-syntax.py` の allowed-tools 突合を通らない):
     - `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*`
     - `${CLAUDE_PLUGIN_ROOT}/scripts/scan-pending-ac.sh:*`
     - `${CLAUDE_PLUGIN_ROOT}/scripts/apply-run-fact-match.sh:*`
   - 挿入位置 1 (single-issue route): "Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure):" ブロックの L2/L3 dispatch 段落の直後、"L3 auto-retrospective (batch/XL routes only, ...)" ブロックの直前
   - 挿入位置 2 (batch route): "Event-based observation scan (batch, best-effort):" ブロックの L2/L3 dispatch 段落の直後
   - 追加する内容 (両箇所とも同一):
     - 見出し行 `**Run-fact AC reconciliation (runs after the observation scan, best-effort):**`
     - 直後の最初の段落で `Read \`${CLAUDE_PLUGIN_ROOT}/modules/run-fact-matching.md\` and follow the "Processing Steps" section.` と指示する (`modules/skill-dev-checks.md` の Read Instruction Placement Rule — Read 指示は見出し直後の最初の段落に置き、番号付きリストや表の内部に埋めない)
     - スクリプト失敗時は警告のみ出して `/auto` を継続する旨を明記する
   - `modules/run-fact-matching.md` には caller 条件分岐 (SPEC_DEPTH 等) を持たせないため、Caller Condition Propagation の追加記述は不要

7. `tests/run-fact-matching.bats` を新規作成する (after 3, 6) (→ acceptance criteria AC5, AC6)

   - **AC5 が要求する 3 経路**を `apply-run-fact-match.sh --dry-run` で検証する:
     - 検出経路: `--verdict satisfied` かつ `AUTONOMY_TIER=L3` → stdout に `action=auto-check`
     - 非検出経路 (negative case): `--verdict not_satisfied` かつ `AUTONOMY_TIER=L3` → stdout に `action=none`、`Recommend:` 行が出ないこと
     - 候補提示フォールバック経路: `--verdict ambiguous` かつ `AUTONOMY_TIER=L3` → stdout に `action=advisory` と `Recommend:` 行
   - 追加ケース: `--verdict satisfied` かつ `AUTONOMY_TIER=L1` → `action=advisory` (tier ゲート)、`--verdict` 不正値 → `action=advisory` かつ stderr に fail-safe 警告
   - `collect-run-facts.sh`: `AUTO_EVENTS_LOG` に fixture JSONL を指す `--no-github` 実行で、`route` / `size` / `pr` / `phases` / `anomalies` / `fact_tokens` が期待どおりに出ること。イベントログ不在時に `issues: []` で exit 0 すること
   - `scan-pending-ac.sh`: `gh` を PATH prepend でモックし、post-merge 節の `- [ ]` 行のみが拾われること、`verify-type` タグなしの行が `manual` になること、グローバル 1-based index が pre-merge 節のチェックボックスを含めて数えられていること、`--facts` 指定時に token 不一致の行が除外されること
   - モック方針は `tests/resolve-preview-ac-fallback.bats` の PATH prepend パターンに従う。sibling スクリプト呼び出し (`get-config-value.sh` / `gh-issue-edit.sh` / `gh-issue-comment.sh`) は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` でモックディレクトリへ差し替え、`$MOCK_DIR` に 3 つのモックファイルを配置する
   - `WHOLEWORK_CONFIG_PATH=/dev/null` を設定して `.wholework.yml` 依存を排除する

8. `docs/structure.md` と `docs/ja/structure.md` を更新する (after 1, 2, 3, 4) (→ acceptance criteria AC1, AC2, AC3)

   - `docs/structure.md` の `### Modules` の "Key modules" 箇条書きに `modules/run-fact-matching.md` の 1 行を追加する
   - `docs/structure.md` の Scripts 一覧 (`scripts/observation-trigger.sh` / `scripts/opportunistic-search.sh` の近傍) に新規 3 スクリプトの 1 行説明を追加する
   - `docs/ja/structure.md` の対応箇所 (L193-194 近傍および Modules 相当節) を日本語でミラーする (`docs/translation-workflow.md` の Sync Procedure に従い、code fence 数の一致も確認する)

## Alternatives Considered

Issue 本文に列挙された 3 案について、以下の理由で **案 B** を採用した。

| 案 | 内容 | 判定 | 理由 |
|---|---|---|---|
| **A** | `/auto` Step 5 の observation scan を拡張し、`observation-trigger.sh` に `--context` 等で実行事実を渡して条件照合させる | 不採用 | (1) `observation-trigger.sh` は `opportunistic-search.sh` への純粋な pass-through + コメント投稿であり、条件照合ロジックを持たない (#1026 の Spec でも同じ理由で変更対象から外されている)。(2) `opportunistic-search.sh` の event モードは `verify-type: observation` で grep するため、manual AC 244 件を拾うには grep 条件そのものを書き換える必要があり、既存の `keyword=` / `config=` ゲートの意味論と衝突する。(3) event 名マッチ (false-positive 抑制) と実行事実照合 (false-negative 解消) は目的が相補的で、同一スクリプトに同居させると `/verify` dispatch の判断基準が二重化する |
| **B** | 実行事実の構造化を独立スクリプトに切り出し、別スクリプトが pending AC と照合する | **採用** | (1) `scripts/resolve-preview-ac-fallback.sh` (#1035) / `scripts/check-pre-merge-ac.sh` の「決定論的判定をスクリプト化して bats で検証可能にする」前例に沿う。(2) AC5 が「検出 / 非検出 / 曖昧時フォールバックの 3 経路」のテストを要求しており、LLM 判定を挟む設計では判定前後を決定的スクリプトで挟まないと bats で検証できない。(3) `observation-trigger.sh` の責務を変えないため、#1118 (false-positive 側) と本 Issue (false-negative 側) を独立に進められる |
| **C** | `/verify` Step 8b の manual 判定を実行事実ベースに拡張する | 不採用 | Issue 本文が自認するとおり manual AC はそもそも dispatch されないため、dispatch 契機を別途作る必要がある。契機を作る部分が結局案 B と同じ実装になり、`/verify` 側の拡張が上積みになるだけで正味の複雑度が増す。ただし将来 `/verify` が単体起動されたときにも実行事実を参照したくなった場合は、`modules/run-fact-matching.md` を `/verify` からも Read する形で後付けできる (module 化しておく利点) |

**LLM 判定を挟まない全決定論的照合も検討したが不採用**とした。条件文は自然言語であり、Issue 本文も「機械的な完全一致は期待できない」と明記している。決定論的にできる部分 (事実収集・候補絞り込み・tier ゲート・反映) と、できない部分 (意味レベルの照合) を分離し、後者だけを LLM に委ねる構成とした。

## Verification

### Pre-merge

- <!-- verify: rubric "/auto 実行の事実 (route / Size / 各 phase の結果 / PR 番号と状態 / events.jsonl のイベント列) を構造化データとして収集する仕組みが実装されている" --> 実行事実の構造化収集が実装されている
- <!-- verify: rubric "phase/verify に滞留する Issue の pending AC (verify-type: manual / observation / opportunistic のいずれも対象) と実行事実を照合し、充足された AC を検出する仕組みが実装されている。manual AC が照合対象に含まれることが実装から確認できる" --> pending AC との照合機構が実装され、manual AC も対象に含まれる
- <!-- verify: rubric "検出結果の反映が autonomy tier でゲートされている (L1 は候補提示のみ、L2/L3 で自動チェック)。modules/autonomy-tier.md に該当節が追加されているか既存節から参照されている" --> autonomy tier ゲートが実装されている
- <!-- verify: rubric "誤検出を避けるための判定基準 (照合が曖昧な場合は自動チェックせず候補提示に倒す) が実装とドキュメントの双方に明記されている" --> 曖昧時は候補提示に倒す fail-safe が実装されている
- <!-- verify: rubric "tests/ 配下に、実行事実が条件を満たす場合の検出・満たさない場合の非検出 (negative case)・照合が曖昧な場合の候補提示フォールバックの 3 経路を検証するテストが存在する" --> 3 経路を検証するテストが追加されている
- <!-- verify: command "bats tests/" --> テストスイート全件が PASS する

### Post-merge

- `/auto` を 1 回完走させ、`phase/verify` 滞留 Issue のうち当該実行で充足された AC が検出される (自動チェックまたは候補提示) ことを観察する <!-- verify-type: observation event=auto-run -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*` — 実行事実の収集 (`skills/auto/SKILL.md` の `allowed-tools` に追加が必要)
- `${CLAUDE_PLUGIN_ROOT}/scripts/scan-pending-ac.sh:*` — pending AC の列挙と事前絞り込み (同上)
- `${CLAUDE_PLUGIN_ROOT}/scripts/apply-run-fact-match.sh:*` — tier ゲートと反映 (同上)
- `gh issue list:*` / `gh pr view:*` — 既に `skills/auto/SKILL.md` の `allowed-tools` に登録済み。新規スクリプト内部からの呼び出しであり追加不要
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*` / `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*` / `${CLAUDE_PLUGIN_ROOT}/scripts/get-config-value.sh:*` / `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*` — 新規スクリプトが `$SCRIPT_DIR` 経由で内部的に呼ぶのみで、`/auto` の SKILL.md 本文からは直接呼ばないため `allowed-tools` への追加は不要

### Built-in Tools

- `Read` — `modules/run-fact-matching.md` の読み込み (登録済み)
- `Bash` — 新規スクリプトの実行 (登録済み)

### MCP Tools

- none

## Uncertainty

- **`/review` の depth (`--full` / `--light`) が `.tmp/auto-events.jsonl` に記録されていない**: `scripts/run-review.sh` は `EMIT_PHASE_NAME="review"` を固定で設定し (L87)、depth をイベントに載せない。`modules/event-emission.md` の Wrapper Coverage Table でも `run-review.sh` の phase 値は `review` のみ
  - **検証方法**: `grep -n "EMIT_PHASE_NAME" scripts/run-review.sh` および `jq -r 'select(.issue==1150) | .phase' .tmp/auto-events.jsonl` で確認済み (実測: `review` のみ、depth なし)
  - **影響範囲**: Implementation Steps 4 の fail-safe 判定基準。#1097 型の条件 (「Size L の PR に `run-review.sh <PR> --full` を実行し…」) は `--full` を実行事実から確認できないため `ambiguous` に落ち、L3 でも自動チェックされず候補提示になる。これは fail-safe が意図どおり働いた結果であり、本 Issue のスコープでは仕様として受け入れる。depth をイベントに載せる拡張は `modules/event-emission.md` の変更を伴うため別 Issue とする

- **`sub_start` イベントは single-issue route では発行されない**: Issue #1150 のイベント列を実測したところ `sub_start` が無く、`size` フィールドが取得できない (`sub_start` は `run-auto-sub.sh` 経由の batch / XL sub-issue 経路でのみ発行される)
  - **検証方法**: `jq -r 'select(.issue==1150) | [.ts,.event,.phase//"",.pr//"",.size//""] | @tsv' .tmp/auto-events.jsonl` で確認済み
  - **影響範囲**: Implementation Steps 1 の `size` 解決。`get-issue-size.sh <N>` へのフォールバックを必須とする (`--no-github` 時のみ空文字列を許容)。フォールバックが無いと single-issue route で `Size <SIZE>` トークンが常に欠落し、事前絞り込みの精度が落ちる

- **`opportunistic-search.sh` の `--limit 50` が本機構の母集団に対して不足していること**: `phase/verify` かつ closed の Issue は実測 312 件で、既存の `opportunistic-search.sh` は先頭 50 件しか走査しない。本 Spec の `scan-pending-ac.sh` は自前の `--limit` (デフォルト 400) と上限到達時の stderr 警告を持つため本機構としては解消済みだが、既存の `opportunistic-search.sh` 側の silent cap は本 Issue のスコープ外として残る
  - **検証方法**: `gh issue list --label "phase/verify" --state closed --json number --limit 300 --jq 'length'` → 300 (上限到達)、`--limit 400` → 312
  - **影響範囲**: なし (本 Spec の実装には影響しない)。observation AC の取りこぼしという別の欠陥として `/verify` の Improvement Proposal 候補に記録する

## Notes

### Issue 本文と既存実装の食い違い

- **内容**: Issue 本文の「何が欠けているか」節に「`observation-trigger.sh --event <name>` が Issue コメントを走査し、`verify-type: observation event=<name>` を持つ Issue を拾う」とあるが、実際に走査しているのは **Issue コメントではなく Issue body** である
- **Issue 本文の引用**: 「`observation-trigger.sh --event <name>` が Issue コメントを走査し、`verify-type: observation event=<name>` を持つ Issue を拾う」
- **実際の実装**: `scripts/opportunistic-search.sh` L135 が `gh issue view "$N" --json body -q .body` で **body** を取得し、L139 で `grep -E '^- \[ \]' | grep "verify-type: observation"` している。`observation-trigger.sh` が Issue **コメント**を読むのは冪等性ガードのマーカー確認 (L87-89) のみ
- **自動解決 (非対話モード)**: 実装側を正とし、本 Spec は「Issue body の post-merge 節を走査する」設計とした。Issue 本文の記述は背景説明であり要件そのものではないため、Issue 本文の修正は行わない。ただしこの前提は設計の中核 (どこから AC を読むか) なので、`/code` 実装時に body 走査であることを再確認すること

### 自動解決した曖昧点 (非対話モード)

1. **対応方針 A / B / C の選択** → **案 B を採用**
   - 根拠: 「Alternatives Considered」節に詳述。`resolve-preview-ac-fallback.sh` / `check-pre-merge-ac.sh` の前例、AC5 のテスト要件、`observation-trigger.sh` の責務保全の 3 点

2. **照合対象 AC の母集団と絞り込み方法** → **fact token による決定的事前絞り込み + 上限 30 件**
   - 根拠: 未チェック post-merge AC は実測 414 件あり、毎回の `/auto` 完走時に全件を rubric 判定するのは非現実的。`opportunistic-search.sh` の `keyword=` ゲート (#934) と同型の「決定的な事前フィルタ → LLM 判定」の 2 段構成を踏襲した。実測で 414 件 → 17 件まで絞れることを確認済み
   - 汎用トークン `/auto` の除外も同じ実測に基づく (単独で 84 件ヒットし絞り込みが機能しない)
   - 上限 30 は `.wholework.yml` のキーにせずスクリプト内定数とした。実測候補数が 17 件で上限に達しておらず、config キーを増やすと `modules/detect-config-markers.md` / `docs/guide/customization.md` / `docs/ja/guide/customization.md` の 3 ファイル同期義務が発生するため。上限到達が実際に観測された時点で config 化を起票する

3. **`auto-check` 時の監査証跡の形式** → **`type=run-fact-ac-match` marker 付きコメントを 1 件投稿**
   - 根拠: `modules/l0-surfaces.md` の Machine-Readable Event Marker 規約に沿う。チェックボックスを立てるため当該 AC は次回スキャンで候補にならず、#1026 で観測されたコメント無限蓄積は構造的に起きない
   - Issue 本文の Auto-Resolved Ambiguity Points が禁じているのは **候補提示 (L1 tier) の Issue コメント化**であり、自動チェック時の監査証跡はこれに該当しない。候補提示側は `Recommend:` プレフィックス付きターミナル出力のみとする方針を維持する

### 既存の類似ツールとの関係

- `scripts/post_merge_check.sh` は manual AC を人間に P/F/S で対話的に問う **人間ループ**のツールであり、Issue 番号を明示的に受け取り、チェックボックス index も計算しない。本 Spec の自動検出経路とは目的が異なるため再利用せず、両者は併存させる

### 実装上の注意

- 3 スクリプトはいずれも bash 3.2+ 互換で書くこと (macOS system bash)。`mapfile` (bash 4+)、`${VAR,,}` (bash 4+) を使わず、小文字化は `tr '[:upper:]' '[:lower:]'` を使う
- `scan-pending-ac.sh` / `apply-run-fact-match.sh` は `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` の既存イディオムを使い、sibling スクリプトを `$SCRIPT_DIR` 経由で呼ぶこと (bats のモック差し替えが効くようにするため)
- 3 スクリプトいずれも `/auto` を中断させてはならない。`gh` の失敗・イベントログ不在・jq パースエラーはすべて fail-open (空結果 + exit 0) とし、引数不正のみ exit 1 とする
- `modules/run-fact-matching.md` の列挙には `modules/skill-dev-checks.md` の Exhaustive/Example マーカー規約に従い `(exhaustive)` / `(examples)` を付けること
- `skills/auto/SKILL.md` は `scripts/validate-skill-syntax.py` の制約を受ける。本文に半角感嘆符とトリプルバッククォートを含めないこと

## issue retrospective

`/issue 1157 --non-interactive` によるリファインメントを実施しました。

### Triage (自動連鎖)

- Title: 「解消する」→「解消」(noun-ending rule)
- Type: Feature
- Size: L (実行事実の構造化収集 + pending AC 照合 + autonomy tier ゲート + fail-safe + テスト3経路。複数モジュール/スキルに跨る新規アーキテクチャパターンのため Axis 2 で +1 調整)
- Value: 5 (Impact=10: blocking=1 (#1158 が本 Issue に blocked-by)、mentions=9、shared_flag=+2 / Alignment=5: Vision の中核である post-merge 検証機構に直接該当。Level 1 精度 (`docs/product.md` Steering Documents 利用)
- 重複候補: なし (#1158 / #1118 / #1156 は関連 Issue だが目的が異なると判定)
- AC verify command 監査: 該当パターンなし (rubric ベースの AC のみ、grep 引数順・常時 PASS/FAIL・patch route 不整合・破壊的コマンドのいずれにも該当せず)

### 曖昧性検出と自動解決

Size L につき上限5件のうち、2件を自動解決 (残りは AC 文言自体が既に十分具体的で曖昧性なしと判定):

1. **候補提示 (L1 tier) の掲示形式**: `modules/autonomy-tier.md` Path A および `triage`/`verify`/`auto` 各スキルで一貫する「`Recommend:` プレフィックス付きターミナル出力」慣行を踏襲する方針とした。既存パターンが複数箇所で反復されており、一意に推論可能なため自動解決 (Issue コメント化などの新形式は導入しない)。AC 文言は変更不要。
2. **遡及適用範囲**: 本 Issue は前向き (prospective) 検知メカニズムに限定し、既存滞留 167 件への遡及バックフィルは #1158 が別途担う方針を明記。Post-merge AC の「1 回完走」要件および #1158 の Related 記載と整合することを確認済み。

いずれも Issue body に `## Auto-Resolved Ambiguity Points` セクションとして記録した。

### AC 分類・verify command 割当

新規 Issue 作成時点 (retro/verify から自動起票) で既に Pre-merge/Post-merge の分類と rubric ベースの verify command が適切に割り当てられていたため、変更なし。`対応方針の候補 A/B/C` は `/issue` (What) と `/spec` (How) の責務境界に従い、意図的に `/spec` へ確定を委譲する設計のまま維持した (`docs/product.md` § spec-design-boundary 参照)。

### Background 事実主張検証

`observation-trigger.sh` / `reconcile-phase-state.sh` / `run-review.sh` / `/verify Step 8c` の実在をいずれも確認済み (advisory scan、ブロッキングなし)。

### 依存関係

明示的な `Blocked by #N` 記載なし。`gh-check-blocking.sh` の結果、設定すべき依存関係なし (exit 0)。

### スキップした処理

非対話モードのため sub-issue 分割評価 (Step 12) は High-Stakes Decision としてスキップ。分割が必要と判断される場合は `/issue 1157` を対話モードで再実行してください。

## spec retrospective

### Minor observations

- `/issue` の Background 事実主張検証は「実在確認」(ファイル・関数が存在するか) までで、**主張内容の正確性**までは検証していなかった。実際 Issue 本文の「`observation-trigger.sh` が Issue コメントを走査し」は誤りで、走査対象は `opportunistic-search.sh` が読む Issue **body** だった。`/spec` Step 6 の conflict detection で初めて捕捉できた。advisory scan と conflict detection の粒度差が意図どおりに機能した事例として記録する
- 既存の `scripts/opportunistic-search.sh` は `gh issue list --limit 50` で走査対象を打ち切っているが、`phase/verify` かつ closed の Issue は実測 312 件ある。observation AC の取りこぼしが構造的に発生している可能性があり、本 Issue のスコープ外だが独立した欠陥として `/verify` の Improvement Proposal 候補に相当する
- `scripts/post_merge_check.sh` が manual AC の人間ループ処理として既に存在していた。`docs/stats/2026-08-05.md` の「manual 79 件が median 39 日滞留」という分析は、このツールの存在を踏まえると「ツールが無い」ではなく「起動する契機が無い」問題だったと読み直せる。本 Issue が作ろうとしているのはまさにその契機である

### Judgment rationale

- **案 B 採用の決め手は AC5 のテスト要件だった**。「検出 / 非検出 / 曖昧時フォールバックの 3 経路を bats で検証する」を満たすには、LLM 判定の前後を決定的スクリプトで挟む構造が必要になる。案 A (`observation-trigger.sh` 拡張) では判定ロジックが LLM プロンプト側に寄り、bats で経路を固定できない。AC が実装アーキテクチャを一意に決めた珍しいケース
- **上限値を `.wholework.yml` の config キーにせずスクリプト内定数にした**。config キーを 1 つ増やすと `modules/detect-config-markers.md` / `docs/guide/customization.md` / `docs/ja/guide/customization.md` の 3 ファイル同期義務が発生する。実測候補数 17 件に対して上限 30 は余裕があり、到達実績が出てから起票する方が総コストが低いと判断した。`observation-dispatch-threshold` (#952) は実際に 17 件の dispatch が発生してから config 化された前例であり、同じ順序に従う
- **fact token から汎用トークン `/auto` を除外する判断は実測に基づく**。414 件中 84 件が `/auto` を含み、含めると絞り込みが機能しない。設計判断を推測ではなく計測で決められたのは、`gh issue list --json number,body` が 1 回の API 呼び出しで全 body を取れると分かったため。当初は Issue ごとに `gh issue view` を回す前提で「重すぎる」と考えていたが、既存 `opportunistic-search.sh` の実装 (Issue ごとの `gh issue view` ループ) をそのまま踏襲しかけていた

### Uncertainty resolution

- **`/review` の depth が events.jsonl に記録されているか** → 記録されていない。`scripts/run-review.sh` L87 が `EMIT_PHASE_NAME="review"` を固定設定しており、`--full`/`--light` はイベントに載らない。実測 (`jq 'select(.issue==1150) | .phase'`) でも `review` のみ。結果として #1097 型の条件は `ambiguous` に落ちるが、これは fail-safe が意図どおり働いた状態であり、仕様として受け入れた。depth 記録の追加は `modules/event-emission.md` の契約変更を伴うため別 Issue とする
- **`sub_start` イベントが single-issue route でも発行されるか** → 発行されない。#1150 のイベント列に `sub_start` が無く、`size` フィールドが取れない。`get-issue-size.sh` へのフォールバックを必須とする設計に修正した。これを見落とすと single-issue route で `Size <SIZE>` トークンが常に欠落し、事前絞り込みの精度が静かに劣化する類のバグになっていた
- **全 pending AC を LLM に投げる負荷が現実的か** → 非現実的 (414 件)。決定的な事前絞り込みを挟むことで 17 件まで落ちることを実測で確認し、設計の要とした。`opportunistic-search.sh` の `keyword=` ゲート (#934) と `config=` ゲート (#1026) が同じ「決定的な事前フィルタ → LLM 判定」の 2 段構成であり、既存パターンの横展開として位置づけられる

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1–8 were followed as written; no reordering or omission occurred.

### Design Gaps/Ambiguities

- **Steering Docs sync candidates were resolved by precedent, not by new judgment**: for `docs/guide/autonomy.md` and `docs/workflow.md`, I checked whether the existing "operate route" external-system-write gate (`modules/autonomy-tier.md` § Tier × External System Write, added for #995) — a structurally identical independent-axis tier gate — is surfaced in either user-facing doc. It is not, in either file. I followed that precedent and left both files unchanged for the new Tier × Run-Fact AC Match gate as well, rather than introducing a new documentation-surfacing convention this Issue did not ask for.
- **`modules/observation-trigger.md` cross-reference**: the Spec listed this as a sync candidate ("相補関係への相互参照 1 行の追加が候補"). I added one Notes-section line pointing to `modules/run-fact-matching.md`, since a reader of `observation-trigger.md` alone would otherwise have no way to discover that manual-tagged post-merge AC are handled by a different mechanism entirely.
- **`apply-run-fact-match.sh --evidence` default value**: the Spec's Step 3 defines the `Recommend:` and audit-trail-comment formats but not what to print when `--evidence` is omitted. I chose the literal string `"no evidence provided"` — a judgment call not specified by the Spec, recorded here in case a future caller needs a different default (e.g. empty string, or omitting the parenthetical entirely).

### Rework

- **jq filter-argument re-evaluation bug in `collect-run-facts.sh`**: the first draft of the `phase_entry(events; p)` jq function used bare (non-`$`) parameters. jq evaluates a bare filter parameter's argument expression against whatever `.` is *at the point of reference inside the function body*, not against `.` at the call site — so `p` inside `map(select(.phase == p))` silently evaluated against each element of the mapped array instead of the phase name passed in, and every phase's `status` resolved to `"started"` regardless of whether a `phase_complete` event existed. Caught by the manual smoke test in Task #1 (expected `"complete"` for issue 1150's `code-pr`/`review`/`merge` phases, got `"started"` for all three). Fixed by switching to `$`-prefixed (bound-value) parameters throughout the module's jq functions. This is a general jq pitfall, not specific to this script — worth remembering for any future jq `def` with a filter-typed parameter referenced inside a nested `map`/`select`.
- **`scan-pending-ac.sh` output line-wrapping**: the accumulator variable for the candidate array was built via repeated `jq '. += [...]'` calls without `-c`, so the final output was pretty-printed across multiple lines instead of the single-line JSON the module header documents. Caught by `tests/run-fact-matching.bats`'s truncation test (a naive `grep '^\['` line-extraction failed). Fixed by adding `-c` to the accumulator's jq call.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Pre-merge AC gate (`check-pre-merge-ac.sh`) resolved cleanly: all 6 pre-merge acceptance conditions were already checked, so the merge proceeded without an override marker.
- `gh-pr-merge-status.sh` reported `mergeable=true reason=clean`, so no rebase/conflict-resolution path was taken; squash-merged directly via `gh pr merge --squash --delete-branch`.
- Local branch deletion for `worktree-code+issue-1157` failed because another pre-existing worktree (`review+pr-1160`, unrelated to this merge) still has it checked out; the remote branch was deleted successfully by `gh pr merge`. Left that worktree untouched rather than force-removing it, since it predates this task and is out of scope.

### Deferred Items

- 未チェックの Deferred Items は変更なし (code フェーズの記載を継続): `/review` depth のイベントログ記録拡張、`opportunistic-search.sh --limit 50` の silent cap、既存滞留 167 件への遡及バックフィル (#1158 が担当) — いずれも本 Issue のスコープ外
- Post-merge AC (observation, event=auto-run) は引き続き未チェック — `/verify` フェーズでの観察対象

### Notes for Next Phase

- `/verify` はこの Issue の Post-merge AC (observation, event=auto-run) を、次回いずれかの `/auto` 完走で本機構自身が発火するかどうかで判定することになる。本 PR のマージそのものが `/auto` 経由でない場合、post-merge AC の充足には別途 `/auto` 実行が必要な点に注意 (code フェーズからの引き継ぎを維持)
- ローカルの `worktree-code+issue-1157` ブランチは `review+pr-1160` worktree 内に残存しているため、そちらの worktree が不要になった時点で削除すること (この merge 実行では対象外)
- 3 スクリプトはすべて fail-open、bats テスト 18 件で検証済み — 変更なし

## Consumed Comments

- login: `saito` / authorAssociation: `MEMBER` / trust tier: first-class / 要旨: `/issue 1157 --non-interactive` の Issue Retrospective。Triage 判定 (Type Feature / Size L / Value 5) の根拠、自動解決した曖昧点 2 件 (候補提示の掲示形式は `Recommend:` ターミナル出力慣行を踏襲 / 遡及適用は #1158 が担当し本 Issue は前向き検知に限定)、対応方針 A/B/C の確定を意図的に `/spec` へ委譲した設計判断、Background の事実主張検証済みの記録。sub-issue 分割評価は非対話モードのためスキップ済み / URL: https://github.com/saitoco/wholework/issues/1157#issuecomment-5183192598

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1157#issuecomment-5184331273
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1157#issuecomment-5185271809
- saito / MEMBER / first-class / ## Acceptance Test Results (再検証: observation 発火後) / https://github.com/saitoco/wholework/issues/1157#issuecomment-5186317121
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1157#issuecomment-5195223616
- saito / MEMBER / first-class / ## Acceptance Test Results (再検証 2: observation 再発火後) / https://github.com/saitoco/wholework/issues/1157#issuecomment-5199403005
## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC 6 件はいずれも明確に判定できた。特に AC 2 が「manual AC が照合対象に含まれることが**実装から確認できる**」と検証手段まで指定していたため、実装側がヘッダコメント L32-38 に「manual / observation / opportunistic / auto をすべて候補に含め、除外しない (これが AC2 の要求を満たす方法である)」と明記する形で応答しており、rubric 判定が一意に定まった
- 対応方針 A/B/C の確定を `/issue` から `/spec` へ意図的に委譲した判断が機能した。B (独立スクリプトへの切り出し) が採用され、`resolve-preview-ac-fallback.sh` (#1035) の「決定論的判定をスクリプト化して bats で検証可能にする」前例に沿った構成になっている

#### design
- Steering Docs sync を**先例に照らして「変更しない」と判断**した記録 (Code Retrospective の Design Gaps) が有用。構造的に同型の operate-route tier gate (#995) が `docs/guide/autonomy.md` / `docs/workflow.md` に露出していないことを確認したうえで、本 Issue でも露出させない選択をしている。「新しいドキュメント露出慣行を本 Issue が勝手に作らない」というスコープ規律

#### code
- 手戻り 2 件。いずれも**テストではなく手動 smoke test / 既存テストが捕捉**した:
  - **jq のフィルタ引数再評価バグ**: `def phase_entry(events; p)` で bare パラメータを使うと、`p` は関数本体の参照地点の `.` に対して評価される。`map(select(.phase == p))` の中では配列の各要素に対して評価されてしまい、全 phase の status が `"started"` に潰れていた。`$` 付き (bound-value) パラメータへ切り替えて解消。**jq 一般の落とし穴であり本スクリプト固有ではない**
  - **`scan-pending-ac.sh` の出力改行**: 累積変数を `jq '. += [...]'` で組み立てる際に `-c` を付け忘れ、module ヘッダが規定する単一行 JSON にならなかった。truncation テストの `grep '^\['` が失敗して発覚

#### review
- 特記事項なし。Pre-merge AC 6 件が全チェック済みだったため `check-pre-merge-ac.sh` の gate は override marker なしで通過、`mergeable=true reason=clean` で conflict 解消も不要だった

#### merge
- `worktree-code+issue-1157` のローカルブランチ削除が、無関係の既存 worktree (`review+pr-1160`) がチェックアウト中のため失敗。remote branch は削除成功。既存 worktree は本タスク以前から存在しスコープ外のため force 削除せず放置した判断は妥当

#### verify
- Post-merge の observation AC は未発火のため SKIPPED。本 Issue は `--batch 1157 1158 1159` の 1 件目として処理されており、`observation-trigger.sh --event auto-run` は Batch Completion Report 時点で走るため、発火は本 verify の直後になる
- `scripts/apply-run-fact-match.sh` は本 verify 内で実行していない。`autonomy: L3` 下で `satisfied` verdict に対し**他 Issue のチェックボックスを自動更新する**ため、別 Issue の verify 実行中に副作用を出さない判断。パイプラインの前段 2 スクリプトは個別に実動作を確認済み
- **残存 worktree 40 件を観測** (うち review/verify 系 9 件、`code+issue-385` など古いものを含む)。merge フェーズで顕在化した `review+pr-1160` はその 1 件にすぎない。`modules/worktree-lifecycle.md` の stale 判定指針 (「所有プロセスの終了を積極的に確認できない限り live conflict として扱い、迷ったら自動処理せず衝突を表面化させる」) に従い本 verify では削除していない。#1119 (異常終了フェーズの stale worktree 回収) の実証データ

#### verify (再検証、2026-08-04 発火後)

`auto-run` イベント発火 (2026-08-04T22:21:39Z) を受けて条件 7 を初評価した結果、**UNCERTAIN**。

- **機構単体は 4 経路すべて動作確認できた**。Stage 1 (`collect-run-facts.sh`) が batch 3 件の実行事実を正しく構造化 (#1158 が Size XL でスキップされた事実も `route: unknown` / `pr: null` として反映)、Stage 2 (`scan-pending-ac.sh`) が 386 件の候補 AC を検出、Stage 3 (`apply-run-fact-match.sh --dry-run`) が `not_satisfied`→`none` / `ambiguous`→`advisory` / `satisfied`+L3→`auto-check` / `satisfied`+L1→`advisory` の全経路を設計どおりに返した
- **しかし `/auto` 統合経路は一度も実行されていない**。`skills/auto/SKILL.md` の L751 (単一 Issue 経路) と L1205 (batch 経路) に Run-fact AC reconciliation ステップが追加されているが、**本 batch は #1157 着地前の SKILL.md (`37b13320`) を読み込んで開始しており**、`dbaff5c8` への更新は batch 実行中に起きた
- **PASS にしなかった判断根拠**: 条件 7 の観察対象は**統合された挙動**であり、手動でパイプラインを走らせた結果はその代替にならない。本 Issue 自身が `modules/autonomy-tier.md` に記した設計原則「false-positive auto-check は advisory の見逃しより取り消しが難しいため、不明確な match は如何なる tier でも auto-check に到達してはならない」を、本 Issue 自身の AC 判定にも適用した
- **構造的な発見**: 自己ホスト型リポジトリでは、**skill を変更する Issue の統合経路を同一セッション内で検証できない**。skill 自己更新の非伝播 (`docs/sessions/73536-1785868487-2026-08-04/session.md` § Skill Self-Update Propagation Note) により、変更後の skill が作用するのは次 session 以降になるため。これは #1157 に固有の問題ではなく、`skills/*/SKILL.md` を変更するすべての Issue の post-merge observation AC に共通する制約

#### verify (再々検証、2026-08-05 発火後)

`auto-run` イベントの再発火 (2026-08-05T17:41:20Z) を受けた条件 7 の 2 回目の評価。結果は再び **UNCERTAIN**、ただし理由が前回と入れ替わった。

- **前回の UNCERTAIN 理由は解消済み**。2026-08-05 以降、#1157 着地 (08-04T20:22Z) より後に開始した `/auto` セッションが 5 件以上完走している (`6722-1785907145` / `56516-1785934632` / `65022-1785935372` / `38916-1785974328`)。いずれも更新後の `skills/auto/SKILL.md` (`dbaff5c8` 以降) を読み込んでいるはずで、skill 自己更新の非伝播はもはや障害ではない
- **それでも統合経路の実行痕跡が 4 系統すべてでゼロ**。`.tmp/run-facts-<session>.json` (Processing Steps 1 の必須出力、`no candidates` 終了でも生成される) が 0 件、`type=run-fact-ac-match` marker コメントが 0 件、`.tmp/permission-log.txt` の `collect-run-facts.sh` / `scan-pending-ac.sh` 実行記録が 0 件、`docs/sessions/*/session.md` の `Run-fact AC reconciliation:` サマリー行が 0 件
- **配線側の欠落ではない**。現行 main の `skills/auto/SKILL.md` は L752 (単一 Issue 経路) と L1206 (batch 経路) の双方に `modules/run-fact-matching.md` の読み込み指示を保持し、`allowed-tools` にも 3 スクリプトの literal エントリが登録されている
- **UNCERTAIN とした判断根拠**: 「実行されたが候補ゼロだった」と「そもそも実行されなかった」を弁別する証拠がない。前者なら機構は設計どおりで条件 7 は次の機会に評価できるが、後者なら best-effort ステップの実行漏れという別問題になる。`modules/run-fact-matching.md` 自身の fail-safe 思想 (曖昧なら `satisfied` に倒さない) を AC 判定にも適用した
- **観測手段そのものの欠落が二次的な問題**: `action=advisory` は `Recommend:` のターミナル出力のみ、`no candidates` も同様にターミナル出力のみで、いずれも L0 にも `.tmp/` にも痕跡を残さない。唯一の永続的痕跡は Step 1 が保存する `run-facts-<session>.json` だが、これも `/auto` が実際にステップへ到達した場合にしか生まれない。**「ステップが走って何も検出しなかった」と「ステップに到達しなかった」が事後に区別できない設計**であり、条件 7 のような observation AC を評価する側から見ると観測不能な構造になっている

### Improvement Proposals

**追記 (2026-08-05 再々検証)**:

- **Tier 1 (Issue 起票、ユーザー指摘)**: **チェック済み pre-merge AC の再検証が既定になっており、コストに見合っていない**。`skills/verify/SKILL.md` Step 6 の「Re-runs: re-verify all conditions (idempotent). Re-verify even if already checked」に従い、本再々検証では条件 1〜6 をすべて再実行した。うち条件 6 は `bats tests/` 1405 件で、実行に相応の時間とトークンを要したが、結果は merge 前の検証と同一で新規情報はゼロだった。pre-merge AC は (a) `/review` の pre-merge AC gate (`check-pre-merge-ac.sh`) を通過し、(b) merge 時点で `[x]` になっている以上、`/verify` の再実行は二重検証にあたる。`/verify` の責務を post-merge AC の評価に絞り、checked な pre-merge AC は既定でスキップ (再検証したい場合のみ明示フラグ) とするのが妥当。特に `command` 系 (テストスイート実行) は rubric 系と比べてコスト差が大きく、既定スキップの効果が大きい
  - **判断根拠**: 影響範囲がすべての `/verify` 実行に及び (Tier 1 criterion「影響範囲が広い」)、`/auto` パイプラインでは Issue ごとに毎回発生するため再発性も構造的。ユーザーからの明示的な指摘でもある
- **Tier 1 候補 (Step 16 で既存 Issue への追記可否を判定)**: `modules/*.md` を「Read して Processing Steps に従う」形で呼び出す **best-effort ステップは、配線が正しくても実行されないことがあり、しかも実行の有無が事後に判別できない**。本 Issue の Run-fact AC reconciliation は 5 セッション以上の `/auto` 完走を経て痕跡ゼロだったが、これが「未到達」なのか「到達して候補ゼロ」なのかを区別する手段が存在しない。少なくとも到達を記録する何か (event emission、あるいは `no candidates` 時も含めた `run-facts-<session>.json` の無条件生成) があれば、observation AC 側から評価可能になる
  - **本 Issue のスコープ外とする根拠**: #1157 が実装したのは検出機構そのものであり、その機構が `/auto` から確実に呼ばれることの保証は `/auto` 側の実行保証の問題。#1117 (issue/spec フェーズの completion check による silent no-op 検出) と同型の課題であり、同 Issue への追記で扱える可能性が高い

**追記 (2026-08-04 再検証)**:

- **Tier 1 (Issue 起票)**: 自己ホスト型リポジトリでは、`skills/*/SKILL.md` を変更する Issue の**統合経路を同一セッション内で検証できない**。skill 自己更新は次 session 以降にしか作用しないため、post-merge の observation AC が「変更後の skill が実際に動くこと」を要求している場合、その Issue を処理したセッションでは必ず評価不能になる。本 Issue の条件 7 がこの制約に直面した最初の明示的な事例。`/issue` が SKILL.md 変更を伴う Issue の post-merge AC を生成する際に、この制約を条件文へ織り込むか警告する仕組みが要る。**→ #1168 として起票済み**
  - **Tier 1 とした判断根拠**: 影響範囲が `skills/*/SKILL.md` を変更するすべての Issue に及び (Tier 1 criterion「影響範囲が広い」)、かつ skill 自己更新の非伝播という**構造に起因するため再発が保証される** (同「再発性」)。#1159 で導入した新デフォルト (迷ったら Tier 2) は判断が困難な場合の fallback であり、本件は criterion に明確に該当するため適用外

---

以下は初回検証時 (2026-08-04、発火前) の分類。`modules/retro-proposals.md` の三層判定を適用した結果、**Tier 1 (Issue 起票) に該当するものはなかった**。内訳:

- **Tier 2 (convention — memory 提案)**: jq の `def` でフィルタ型パラメータを nested `map`/`select` 内から参照する場合は `$` 付きの bound-value パラメータを使う。bare パラメータは参照地点の `.` に対して再評価されるため、silent に誤った値で評価される。本 Issue で 1 件発生し、bats テストではなく手動 smoke test でのみ捕捉された類のバグ
- **Tier 3 (one-time memo)**: `scan-pending-ac.sh` の jq 累積時の `-c` 付け忘れ。既存テストが捕捉済みで再発性は低い
- **No action (既存 Issue が対象)**: 残存 worktree 40 件は #1119 のスコープ。本 verify の観測データは同 Issue の優先度判断材料として有効だが、新規起票は不要

なお本セッションで起票した #1159 は「Tier 2/3 判定が実運用でゼロ件であり、判定結果も記録されない」ことを問題として扱っている。本 retrospective はその指摘を受けて意識的に Tier 2/3 を適用した最初の事例にあたる — ただし現状の実装では**この分類結果は terminal 出力にも残らず、本 Spec への手書き記録が唯一の痕跡**である点が、#1159 の主張 (判定の永続化が測定の前提) を裏付けている

---

## Verify Retrospective (再々々検証、2026-08-06 — 条件 7 PASS)

### 結果

`/auto 1186` (session `63702-1785981144`) の完走により Run-fact AC reconciliation が実際に実行され、**条件 7 が PASS**。本 Issue は `phase/done` へ遷移し完了した。3 回の `/verify` を要した。

| 回 | 日時 | 条件 7 | 判定理由 |
|---|---|---|---|
| 1 | 2026-08-05T01:01Z | UNCERTAIN | skill 自己更新の非伝播により、本 Issue 着地前の `skills/auto/SKILL.md` (`37b13320`) を読み込んだ batch では統合経路が構造的に実行され得なかった |
| 2 | 2026-08-06T02:0xZ | UNCERTAIN | 非伝播は解消したが、5 セッション以上の `/auto` 完走を経ても統合経路の実行痕跡が 4 系統すべてでゼロ。「実行されて候補ゼロ」と「未到達」を弁別できず |
| 3 | 2026-08-06T04:1xZ | **PASS** | `/auto 1186` で統合経路が実行され、`run-facts-<session>.json` 生成・225→30 件の候補抽出・3 経路の verdict 処理・`Recommend:` 行出力がすべて実測された |

### Phase-by-Phase Review (3 回目の verify で得られた知見)

#### verify
- **前回の「4 系統すべてゼロ」という観察の意味が確定した**。今回、統合経路が実行された結果 `.tmp/run-facts-63702-1785981144.json` が生成された。すなわち **Processing Steps が走れば痕跡は必ず残る**。前回の痕跡ゼロは「実行されて候補ゼロだった」ではなく「**そもそも到達していなかった**」ことを示していたと事後的に確定できる。前回 Improvement Proposals に「Tier 1 候補」として記録した「実行されたか未実行かが事後に区別できない」という指摘は、**run-facts JSON の有無という形で既に区別可能だった** — 提案の前提が誤っていたため取り下げる
  - ただし `action=advisory` の `Recommend:` 行と `no candidates.` は依然ターミナル出力のみで永続化されない。「実行された上で候補ゼロ / 全件 advisory だった」ケースの詳細は run-facts JSON の存在からしか逆算できず、粒度は粗いままである。実害が観測されるまでは起票しない
- **なぜ 2 回目で走らなかったのかは未解明のまま**。8/5 の 5 セッション以上の `/auto` 完走で一度も到達していない一方、本 session では到達した。差分として考えられるのは、本 session が `/auto` を対話セッション内で直接実行し、Completion Report 以降のステップを明示的に辿ったのに対し、8/5 の各セッションがどこで停止したかを事後に確認する手段がないこと。**LLM-native prose の best-effort ステップは、到達したことは run-facts JSON で確認できるが、到達しなかった場合にどこで止まったかは追跡できない**
- **#1186 の already-checked AC skip rule が本 verify で効いた**。pre-merge 6 件がすべて SKIPPED となり、2 回目の verify で実行した `bats tests/` 1405 件が今回は走っていない。同一 Issue の連続する 2 回の verify で、旧ルール (全件再実行・新規情報ゼロ) と新ルール (全件スキップ) を直接比較できた形になっている
- **fail-safe が実運用で 1 件の誤検出を防いだ**。#1123 ac7 は run facts の `manual_intervention=0` だけを見れば `satisfied` に見えたが、実際には「manual recovery が発生する機会がなかった」だけであり「#1123 の修正が効いた証拠」ではない。`modules/run-fact-matching.md` の「判断が不明確なら `ambiguous`、決して `satisfied` にしない」に従って `ambiguous` に倒した。**本 Issue が設計した fail-safe が、本 Issue 自身の完了判定を行う実行で実際に誤 auto-check を防いだ**

### Improvement Proposals

- **取り下げ**: 前回記録した「Tier 1 候補 — best-effort ステップの実行有無が事後判別できない」は、run-facts JSON の有無で区別可能であることが本検証で判明したため取り下げる (上記 verify 節参照)
- **N/A (新規なし)**: 本検証で得られた他の観察 (merge フェーズの watchdog kill と `Exit code: 0` の併存) は `docs/spec/issue-1186-skip-checked-ac-reverify.md` の `## Auto Retrospective` に記録済みで、#1140 / #939 が追跡中
