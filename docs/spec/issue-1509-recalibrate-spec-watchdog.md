# Issue #1509: auto: spec フェーズの watchdog 上限を最新の実測に合わせて再較正する

## Overview

`/auto --batch` の spec フェーズで、最大無出力時間 (max silent window) が #1301 の project override (2340s) の 88–97% に 3 セッション連続で達した (2280s / 2060s / 2190s。いずれも Size M の dispatch で、kill は 0 件)。#1301 が自ら予告した「再発が続けば別 Issue で global default への昇格を検討する」条件に該当するため、#1301 / #939 の先例を当てはめて判断した結果、project override に留めず **global default へ昇格する** (根拠は Notes 参照)。

- `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_SPEC_DEFAULT` を 1800 → **2964** に引き上げる。2964 = 実測最大 2280s × 1.3 (#903 / #1301 と同じ係数)。2280 / 2964 = 76.9% で、80% 再較正トリガー未満
- `.wholework.yml` の spec override (2340s) を削除し、実効上限を global default に一本化する
- 既定値 1800 に依存する bats 3 本と、既定値を記載したドキュメント (customization ガイド、`docs/tech.md` の再較正履歴、それぞれの `docs/ja/` ミラー) を同期する
- 受入条件は Issue 本文を更新して 4 → 5 件にした (元の AC2 が worktree 隔離ガードに拒否される形だったため。Notes 参照)

## Changed Files

- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` → `WATCHDOG_TIMEOUT_SPEC_DEFAULT=2964`。"Recalibration guidance" コメントブロック末尾に SPEC_DEFAULT の bullet を追加 — 定数値とコメントのみの変更で、bash 3.2+ 互換
- `.wholework.yml`: spec override (コメントブロックと `watchdog-timeout-spec-seconds: 2340` の行、12–20 行目) を削除し、昇格した旨の短いコメントに置換
- `tests/watchdog-defaults.bats`: `load_watchdog_timeout uses phase-specific default when phase is spec` の期待値 `1800` → `2964`
- `tests/get-auto-session-report.bats`: `at-risk threshold falls back to phase default when no override is configured` と `at-risk threshold honors .wholework.yml phase override: no false positive within headroom` のフィクスチャとコメントを新既定値に合わせて更新
- `tests/audit-auto-session.bats`: `success: phase silent window threshold violation appears in Summary and Notes` のフィクスチャとコメントを新既定値に合わせて更新
- `docs/tech.md`: "Watchdog timeout calibration" bullet 末尾に `**Follow-up (#1509)**` を追記 (実測最大 2280s、係数 ×1.3、昇格の判断理由を含む)
- `docs/ja/tech.md`: 上記の日本語ミラー (`**フォローアップ (#1509)**`)
- `docs/guide/customization.md`: spec フェーズの既定値 `1800` を `2964` に更新 (per-phase override のサンプルコメントと、Available Keys 表の `watchdog-timeout-spec-seconds` 行)
- `docs/ja/guide/customization.md`: 上記の日本語ミラー
- [Steering Docs sync candidate] keyword "WATCHDOG_TIMEOUT_SPEC_DEFAULT" skipped: matched 20 files (no discriminating power)
- [Steering Docs sync candidate] keyword "watchdog-timeout-spec-seconds" skipped: matched 14 files (no discriminating power)
- [Steering Docs sync candidate] keyword "watchdog-defaults.sh" skipped: matched 51 files (no discriminating power)
- [Steering Docs sync candidate] 抽出した全キーワードが弁別力フィルタでスキップされたため、この確認はここで終了。上記の Changed Files は、既定値のリテラル (`1800` / `2340`) に依存するテストとドキュメントを直接調査して特定した (調査範囲は Notes の「既定値依存の調査」)

## Implementation Steps

1. `scripts/watchdog-defaults.sh` を編集する (→ 受入条件 1, 2, 4)
   - `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` を `WATCHDOG_TIMEOUT_SPEC_DEFAULT=2964` に置換する。受入条件 2 の `file_contains` が文字列 `WATCHDOG_TIMEOUT_SPEC_DEFAULT=2964` の存在を要求するため、`=` の前後に空白を入れない
   - "Recalibration guidance" コメントブロックの末尾 (`REVIEW_DEFAULT raised again 2600->5400` の bullet の直後、`WATCHDOG_TIMEOUT_SPEC_DEFAULT=` 行の直前) に、既存 bullet と同じ形式 (`#   - ` で開始し、継続行は `#     `) で SPEC_DEFAULT の bullet を追加する。含める内容は次の通り
     - 1800→2964 に引き上げた旨 (#1509, 2026-10)
     - #1301 の override (2340s) が 3 セッション連続で 88–97% に達した実測 (`max_silent_window` 2280s / 2060s / 2190s、kill なし)
     - override 期間の spec 実測 (N=95) の p95 1770s / max 2280s
     - max 2280s に #903 と同じ ×1.3 係数を適用して 2964s (2280/2964 = 76.9%、80% トリガー未満)
     - override を global default へ昇格した旨と、`docs/tech.md` § Watchdog timeout calibration への参照
   - リテラル `2280` を必ず含める (受入条件 4 の `grep -q 2280` が参照する)
2. `.wholework.yml` を編集する (parallel with 1) (→ 受入条件 1, 3)
   - spec override のコメントブロック (`# 2 セッション連続 (2026-08-08, 2026-08-09) の実測で ...` から `# 再発が続けば別 Issue で global default への昇格を検討する (詳細: docs/tech.md #939 段落)。` まで) と、直後の `watchdog-timeout-spec-seconds: 2340` の行を削除する。同じ位置に、昇格済みである旨の日本語コメントを 3〜4 行置く。例: `# spec フェーズの watchdog 上限は、#1301 の project override (2340s) が 3 セッション連続で余裕 60–280s まで詰まったため、#1509 で global default (scripts/watchdog-defaults.sh の WATCHDOG_TIMEOUT_SPEC_DEFAULT = 2964s) へ昇格した。この repo では override を置かない。根拠と実測は docs/tech.md の Watchdog timeout calibration を参照。` (実際は 1 行 80〜100 字前後で折り返す)
   - 置換コメントに override のキー名 `watchdog-timeout-spec-seconds` を書かない。受入条件 3 の `file_not_contains` は 0 件一致を要求し、コメント内の言及も不合格になる
   - 直前の code / review の override エントリ (`watchdog-timeout-review-seconds: 5400`) と、直後の `auto-retry-on-fail:` ブロックは変更しない
3. 既定値依存のテストを更新し、全件 PASS を確認する (after 1) (→ 受入条件 5)
   - `tests/watchdog-defaults.bats`: `@test "load_watchdog_timeout uses phase-specific default when phase is spec"` の `[ "$output" = "1800" ]` を `"2964"` に変更する (テスト名は変えない)
   - `tests/get-auto-session-report.bats` の `at-risk threshold falls back to phase default when no override is configured`: フィクスチャの `max_silent_window` を `"max_sec":"2400"` に、そのイベントの `ts` を `10:22:50Z` → `10:41:00Z` に、続く `phase_complete` / `sub_complete` を `10:41:01Z` / `10:41:02Z` に変更する (`phase_start` の `10:01:00Z` からの経過が 2400s になり、`max_sec` と矛盾しない)。コメント `# default threshold = 1800 - 600 = 1200s; observed 1310s exceeds it` を `# default threshold = 2964 - 600 = 2364s; observed 2400s exceeds it` に変更する。アサーション (`within 600s of watchdog limit`、`Phase silent windows > threshold | 1 (spec:1)`) は変更しない
   - `tests/get-auto-session-report.bats` の `at-risk threshold honors .wholework.yml phase override: no false positive within headroom`: `CONFIG_FIXTURE` の `watchdog-timeout-spec-seconds: 2340` を `watchdog-timeout-spec-seconds: 3600` に変更し、イベントは上の default テストと同じ値 (`max_sec` 2400、`ts` 10:41:00Z / 10:41:01Z / 10:41:02Z) に変更する。コメント `# override threshold = 2340 - 600 = 1740s; observed 1310s stays under it` を `# override threshold = 3600 - 600 = 3000s; observed 2400s stays under it (the default threshold, 2964 - 600 = 2364s, would flag it)` に変更する。override 値を新既定値より大きくするのは、「override が効いているか」を判別できる状態を保つため (Notes 参照)
   - `tests/audit-auto-session.bats` の `success: phase silent window threshold violation appears in Summary and Notes`: コメント 2 行 (`# spec phase: WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800, SILENT_MARGIN=600, threshold=1200` / `# max_sec=1500 > 1200 => violation`) を `=2964 ... threshold=2364` / `# max_sec=2400 > 2364 => violation` に変更し、`max_silent_window` を `"max_sec":2400` (数値のまま)、その `ts` を `10:25:00Z` → `10:40:01Z`、続く `phase_complete` / `sub_complete` を `10:40:02Z` / `10:40:03Z` に変更する (`phase_start` の `10:00:01Z` から 2400s)
   - 3 本を単体実行して PASS を確認した後、`bats tests/` 全件 PASS を確認する
4. ドキュメントを同期する (parallel with 1) (→ 受入条件 1, 4)
   - `docs/tech.md`: "Watchdog timeout calibration" bullet の末尾 (`**Follow-up (#1301)**:` の文の直後) に `**Follow-up (#1509)**:` の文を追加する。既存の `Follow-up (#1301)` 文と同じ密度の英語で、次の事実を含める
     - #1301 の override が 3 セッション連続で 88–97% に達したこと (2280s / 2060s / 2190s、kill なし)
     - override 期間の spec 実測 (N=95、26 セッション、`ts >= 2026-08-10`): median 1210s / p95 1770s / max 2280s、spec の `watchdog_kill` 0 件。80% (1872s) 以上は上記 3 件のみ
     - 判断: #1301 が override に留めた理由 (サンプル数が #903 の n=10 / n=9 に対して 2 セッション分のみ) が解消し、revisit trigger (再発) が発火したため global default へ昇格
     - `WATCHDOG_TIMEOUT_SPEC_DEFAULT` 1800→**2964** (2280 × 1.3、76.9%)。`.wholework.yml` の override を削除。リテラル `2280` を含める (受入条件 4)
     - 昇格のコスト (ハング検出が最大 +1164s 遅れる) と、それを許容した理由 (override 期間の spec ハング kill 0 件)
   - `docs/ja/tech.md`: 同じ bullet の末尾 (`**フォローアップ (#1301)**:` の文の直後) に、上の内容の日本語版 `**フォローアップ (#1509)**:` を追加する。括弧は半角で前後に半角スペースを入れる
   - `docs/guide/customization.md`: 51 行目のサンプルコメント `# watchdog-timeout-spec-seconds: 1800` を `2964` に変更し、143 行目の表の行の `` (falls back to `1800`) `` と `` > `1800`. `` を `2964` に変更する
   - `docs/ja/guide/customization.md`: 45 行目のサンプルコメントと、132 行目の表の行 (`` (フォールバック: `1800`) `` と `` > `1800`。 ``) を同様に `2964` に変更する

## Verification

### Pre-merge

- <!-- verify: rubric "spec フェーズの watchdog 上限 (.wholework.yml の watchdog-timeout-spec-seconds、または scripts/watchdog-defaults.sh の WATCHDOG_TIMEOUT_SPEC_DEFAULT) が、本 Issue の 3 件の実測 (最大 2280s) に対して 80% 再較正トリガー閾値を下回る余裕を持つ値 (2280 / 0.8 = 2850s を超える値) に更新されており、採用値の根拠 (実測値と係数) がコメントまたは docs/tech.md に記録されている" --> spec の watchdog 上限が最新の実測に合わせて再較正され、根拠が記録されている
- <!-- verify: file_contains "scripts/watchdog-defaults.sh" "WATCHDOG_TIMEOUT_SPEC_DEFAULT=2964" --> spec フェーズの global default (`WATCHDOG_TIMEOUT_SPEC_DEFAULT`) が、実測最大 2280s に #903 / #1301 と同じ ×1.3 係数を適用した 2964s (2850s 超) に更新されている
- <!-- verify: file_not_contains ".wholework.yml" "watchdog-timeout-spec-seconds" --> #1301 の project override (2340s) が `.wholework.yml` から削除され、spec フェーズの実効 watchdog 上限が global default に一本化されている
- <!-- verify: command "grep -q 2280 .wholework.yml docs/tech.md scripts/watchdog-defaults.sh" --> 採用値の根拠として実測最大値 2280s が `.wholework.yml` / `docs/tech.md` / `scripts/watchdog-defaults.sh` のいずれかに記録されている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 再較正後の `/auto --batch` で Size M 以上の Issue の spec フェーズを 3 件以上観測し、最大無出力時間が新しい上限の 80% を超えないこと、spec の watchdog kill が発生しないことを確認する。ベースライン: 再較正前の 3 件 (2280s / 2060s / 2190s、上限 2340s の 88–97%)。最小サンプル: Size M 以上の spec 3 件。3 件に満たない間は SKIPPED (サンプル待ち) として判定しない <!-- verify-type: observation event=auto-run when=mode:batch -->

## Notes

### 判断: project override ではなく global default へ昇格する

Issue 本文は「project override に留めるか global default へ昇格するかは、#1301 / #939 の先例に沿って `/spec` で判断する」としている。#1301 の Spec Notes が override に留めた理由として挙げた 3 点を、今回の実測に当てはめた。

| #1301 が override に留めた理由 | 今回 |
|---|---|
| 1. 実測が本 repo の 2 セッション分のみで、#903 の再較正パス (code: n=10 / review: n=9) よりサンプル数が少ない | 解消。override 期間の spec 実測は N=95 (26 セッション、94 Issue) で、#903 の約 9–10 倍 |
| 2. review フェーズの先例 (PR #1201 の override → #939 で global default 昇格) と同じ段階を踏む。#1301 は「即時 override」の段階 | 今回が 2 段目 (昇格) に相当する |
| 3. 再発が続く場合は、別 Issue で global default への昇格を検討する | 発火済み。3 セッション連続で override の 88–97% に達した (本 Issue 自体がその別 Issue) |

加えて次の 2 点を昇格の根拠とした。

- **Distributable-first improvement principle** (`docs/tech.md`): `.wholework.yml` はこの repo 固有の設定で、他の Wholework ユーザーに届かない。`run-spec.sh` は全ユーザーで同じ skill 手順・同じ effort (`max`) の spec を走らせるため、モデル由来の無出力時間の伸びは配布対象の `scripts/watchdog-defaults.sh` に反映するのが筋
- **モデル世代の交代**: `docs/tech.md` は「親モデルが変わったら再較正する」としており、default parent は 2026-09-28 に Sonnet 5.5 へ替わった。実測でも 2026-10-01 以降の N=17 は median 1360s / p95 2280s で、それ以前の N=78 (median 1200s / p95 1670s / max 1800s) より重い。ただし 2026-10-04 の 3 件が Size M→L に昇格した重い Issue だったため、モデル由来の伸びと Issue の構成の違いは分離できない (「整合するが分離不能」として記録する)

**昇格のコスト**: 真にハングした spec の検出が、既定 1800s 比で最大 +1164s、override 2340s 比で最大 +624s 遅れる (Icebox #596 の timeout 膨張 対 ハング検出のトレードオフ)。override 期間の 95 サンプルで spec の `watchdog_kill` は 0 件で、spec のハング kill 自体が観測されていないため、期待コストは小さいと判断した。

**不採用案**: project override のみを 2964 に更新する案 (変更 3 ファイル、Size S のまま)。#1301 が自ら予告した昇格条件を満たしており、他ユーザーに届かないため見送った。この案を望む場合は、Step 1 を `.wholework.yml` の override 値 2964 への更新に置き換え、Step 3 (テスト) と customization ガイドの更新を省けばよい。

### 採用値 2964s の根拠

- 実測最大 2280s (#1491、Size M の dispatch) に、`docs/tech.md` で確立済みの ×1.3 係数 (#903: code 3600→4680 / review 2000→2600、#1301: spec 1800→2340) を適用した: 2280 × 1.3 = 2964。2280 / 2964 = 76.9% で、80% 再較正トリガー (= 2371s) 未満
- 丸めて 3000 にする案もあるが、「実測値 × 係数」の追跡性 (受入条件 1 の根拠記録要件) を優先して端数のまま採用した。受入条件 2 の `file_contains` は 2964 を固定する
- `scripts/get-auto-session-report.sh` の at-risk 閾値は `実効上限 - 600s` なので 2364s (= 上限の 79.8%) になり、「80% 超過」の判定とほぼ一致する。Post-merge の観察では、`/audit auto-session` の Metrics に spec の `within 600s of watchdog limit` が出ないこと (閾値 2364s、判定値は 2371s) を代理指標にできる

### 計測スコープ (measurement-scope)

- **対象**: spec フェーズの `max_silent_window` イベント (`phase=="spec"`)。`docs/sessions/*/events.jsonl` (コミット済みの 77 ファイル)
- **期間**: `ts >= 2026-08-10T00:00:00Z`。#1301 の override コミット `7bf053e8` は 2026-08-09T06:14:24Z に着地した。当日に開始済みの spec フェーズが旧既定 1800s で走っている可能性を避け、翌 UTC 日で区切った (除外された 5 件は 910–1230s で、結論に影響しない)
- **重複排除**: `session_id|issue|ts` で unique。結果は 95 サンプル / 26 セッション / 94 Issue (2026-08-10T02:24:43Z – 2026-10-04T15:42:25Z)
- **パーセンタイル**: nearest-rank。ソート済み配列の index `ceil(N × p) - 1` (median は index `floor(N / 2)`)
- **Size**: `sub_start` イベントの dispatch 時点の `size` を `session_id` + `issue` で結合 (`/spec` 内の Size 昇格後の値ではない)
- **出所**: コミット `bf90cf9e` 時点のワークツリー、取得日時 2026-10-05T02:56Z。セッションを追加すると N は増える。再計測の際は N と期間を併記すること

| 母集団 | N | median | p95 | max |
|---|---|---|---|---|
| override 期間 (`ts >= 2026-08-10`) | 95 | 1210s | 1770s | 2280s |
| 2026-10-01 より前 (2026-08-10 – 2026-09-13) | 78 | 1200s | 1670s | 1800s |
| 2026-10-01 以降 (2026-10-02 – 2026-10-04) | 17 | 1360s | 2280s | 2280s |
| dispatch 時点 Size S / XS | 44 | 1160s | 1670s | 1770s |
| dispatch 時点 Size M | 41 | 1280s | 2060s | 2280s |
| dispatch 時点 Size L (`--opus` 経路) | 10 | 1240s | 1520s | 1520s |

override 期間 (N=95) の補足: min 730s / mean 1244s / p90 1600s。1872s (override 2340s の 80%) 以上は 3 件 (2280s / 2190s / 2060s で、本 Issue の 3 件と一致)、1740s (現行の at-risk 閾値) 以上は 6 件。spec の `watchdog_kill` は 0 件 (データセット中の spec kill は override 以前の 2026-07-09 #962 と 2026-08-07 #1213 / #1238 の計 3 件で、いずれも 1800s)。

再現コマンド (リポジトリルートで実行):

```bash
jq -s -r '[.[] | select(.event=="max_silent_window" and .phase=="spec" and .ts >= "2026-08-10") | {k: "\(.session_id)|\(.issue)|\(.ts)", v: (.max_sec|tonumber)}] | unique_by(.k) | map(.v) | sort as $v | ($v|length) as $n | {n: $n, min: $v[0], median: $v[($n/2|floor)], p90: $v[(($n*0.9)|ceil)-1], p95: $v[(($n*0.95)|ceil)-1], max: $v[-1], over_1872: ($v|map(select(.>=1872))|length), over_1740: ($v|map(select(.>=1740))|length), mean: (($v|add)/$n|floor)}' docs/sessions/*/events.jsonl
```

era / Size 別は、同じ式に `($sizes["\(.session_id)|\(.issue)"])` (`sub_start` の `size` を `session_id|issue` で引いた map) と `ts < "2026-10-01"` の絞り込みを加えたもの。

### 受入条件の修正 (Issue 本文も更新済み)

- **元の AC2 を置換した**: 元の `command "bash -c 'source scripts/watchdog-defaults.sh && load_watchdog_timeout scripts spec && [ ${WATCHDOG_TIMEOUT} -gt 2850 ]'"` を、本 `/spec` セッションの worktree で同形のコマンドを実行したところ、隔離ガードに「`source` を plain command で実行する」として拒否された。`/code`・`/review`・`/verify` はいずれも worktree 内で verify command を実行する (`modules/verify-executor.md` の `command` 行、`modules/verify-patterns.md` §34、`modules/worktree-lifecycle.md` の `source` の節も同旨) ため、そのままでは各フェーズで実行不能になり、`/merge` の pre-merge AC ゲートを塞ぐ恐れがある
- **置換後**: dedicated verify command 2 件 (default 定数が `2964` であること / `.wholework.yml` に spec override が残っていないこと)。昇格を採用したので、この 2 件で「実効上限 > 2850s」が決定的に判定できる。dedicated type は `/review` の safe mode でも `PR_BRANCH` 経由で読めるため UNCERTAIN にならない。`modules/verify-patterns.md` §9 の「rubric が数値リテラルを含む場合は `file_contains` を併記する」にも沿う
- **Pre-merge 件数**: 4 → 5 (light の上限 5 以内)。Issue 本文の Auto-Resolved Ambiguity Points にも置換の経緯を追記した
- **基準時点の確認**: 置換後の AC2 / AC3 は現状 (1800 / 2340 のまま) で FAIL する (`WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800`、`.wholework.yml:20` にキーが存在)。AC4 も現状で 0 件一致 (終了コード 1) のため、どれも空振りしない
- **AC4 (`command "bats tests/"`) は Issue のまま維持した**: `modules/verify-executor.md` § Timeout Coverage Audit は `command` でのフルスイート実行を避けるよう定めるが、`/code` (Step 9 の全件実行と Step 10 の bats AC の扱い) と `/review` (pr route の CI Reference Fallback) に、この形の AC を処理する既存の経路がある。本 Issue で AC4 を書き換える必要はない
- **Post-merge の observation AC は変更しない**: 観察イベント (`auto-run`、`when=mode:batch`)、ベースライン、最小サンプル、SKIPPED の扱いが揃っており、`modules/verify-classifier.md` の定義を満たす。判定値は「新しい上限 2964s の 80% = 2371s」

### 既定値依存の調査

- **範囲**: `scripts/ tests/ modules/ skills/ agents/ hooks/ docs/ README*.md CONTRIBUTING.md SECURITY.md examples/ install.sh .github/` を対象に `grep -rn -E "\b(1800|2340)\b"` と `grep -rn "WATCHDOG_TIMEOUT_SPEC_DEFAULT\|watchdog-timeout-spec-seconds"` を実行。履歴として更新しない `docs/spec/`、`docs/sessions/`、`docs/reports/`、`docs/ja/reports/` は除外した
- **`WATCHDOG_TIMEOUT_SPEC_DEFAULT` の利用箇所 (網羅)**: 定義 `scripts/watchdog-defaults.sh:29`。`load_watchdog_timeout` が `eval` で `WATCHDOG_TIMEOUT_${PHASE}_DEFAULT` を引いて解決し、呼び出し元は `scripts/run-spec.sh:277` と `scripts/get-auto-session-report.sh:27` (at-risk 閾値 = 上限 - 600s)
- **影響を受けるテスト 3 本**: `tests/watchdog-defaults.bats:74` (`1800` を直接 assert)、`tests/get-auto-session-report.bats` の default フォールバックのテスト (`max_sec` 1310 > 閾値 1200 を期待)、`tests/audit-auto-session.bats:118` 以降 (`max_sec` 1500 > 閾値 1200 を期待、`WHOLEWORK_CONFIG_PATH=/dev/null`)。Issue 本文の Issue Retrospective は `tests/watchdog-defaults.bats` のみを挙げていたが、後 2 本も新既定値 (閾値 2364s) では `max_sec` が閾値を下回り、アサーションが失敗する (`get-auto-session-report.sh` の比較は厳密な `>`)
- **override 側のテストの判別力**: `tests/get-auto-session-report.bats` の `honors .wholework.yml phase override` は、override 2340s・観測 1310s で「override が効いているか」を見ている。旧既定では閾値 1200 < 1310 < 1740 のため、override を無視すると失敗した。新既定 (閾値 2364) では 1310 は両方の閾値より小さいので、override を無視しても通ってしまい判別力を失う。override 値を既定より大きい 3600 (閾値 3000) にし、観測値を 2364 < 2400 < 3000 の 2400 にすれば、override を無視すると (2400 > 2364 で) 失敗する状態に戻る
- **bats の入力形式**: `scripts/get-auto-session-report.sh` が読む `AUTO_EVENTS_LOG` の JSONL。1 行 1 イベントで `{"ts":"<ISO 8601 UTC>","issue":<N>,"event":"max_silent_window","session_id":"<id>","phase":"spec","max_sec":<数値または数値文字列>}`。`max_sec` は jq の `tonumber` で数値化して `実効上限 - 600` と厳密な `>` で比較される。設定の解決元は `WHOLEWORK_CONFIG_PATH` (`/dev/null` で既定値を強制、ファイルを渡すとその内容を使う)。`tests/watchdog-defaults.bats` は `$MOCK_DIR/get-config-value.sh` が空文字を返すモックで既定値を引く
- **影響なしと確認した箇所**: `tests/run-{spec,code,review,merge,issue}.bats`・`tests/auto-recovery.bats`・`tests/spawn-recovery-subagent.bats`・`tests/run-code-mergeability.bats` は `load_watchdog_timeout` を固定値 1800 のスタブで置き換えており、実際の既定値を読まない。`scripts/claude-watchdog.sh` の `WATCHDOG_TIMEOUT:-1800` は `run-*.sh` が `load_watchdog_timeout` の結果を環境変数で渡すため spec フェーズの既定値と無関係。`skills/auto/SKILL.md:338` と `skills/spec/skill-dev-constraints.md:112` の「default 1800s」は `claude-watchdog.sh` 自体の一般的な記述で、今回の変更で新たに誤りになるものではない (既存の記述の古さは本 Issue の範囲外)。`modules/detect-config-markers.md` の spec 行は数値の既定値を持たない。`docs/structure.md`・`docs/product.md`・`README.md`・`README.ja.md`・`docs/workflow.md`・`CLAUDE.md` に phase 既定値の記述はない
- **`docs/reports/watchdog-recovery-strategy.md` への追記は行わない**: レポートは時点記録で翻訳対象外。#1301 の追従も `docs/tech.md` のみだった。数値と再現手順は `docs/tech.md` (要約) と本 Spec (再現コマンド) に残る

### その他の判定

- **fail-safe critical**: `scripts/watchdog-defaults.sh` は `2>/dev/null || echo ...` による既定値フォールバックを持つため、字面では基準 (c) に該当する。ただし本 Issue が変えるのは定数値のみで `load_watchdog_timeout` のロジックには触れない。空・非数値・負値は警告付きで phase 既定値にフォールバックし、`get-config-value.sh` の失敗時も phase 既定値にフォールバックする挙動は不変で、既存の `tests/watchdog-defaults.bats` (非数値・負値・警告出力のテスト) がカバーしている。追加のエッジケース記述は不要と判断した
- **audit / investigation-type**: no。実測に基づく設定値の再較正であり、既存項目の分類を永続成果物に記録する Issue ではない
- **外部仕様の確認**: 不要 (外部 API やコマンドの挙動に依存しない)
- **新規ブランチロジックのテスト**: 該当なし (定数値の変更のみで、新しい分岐を追加しない)
- **Listing-side sub-check (Steering Docs)**: 発火しない (サブコマンド・ファイルの追加/削除/改名・ディレクトリ構造の変更のいずれもない)
- **Outbound pointer sync**: 追加候補なし。`scripts/watchdog-defaults.sh` と `docs/tech.md` が指す `docs/reports/` は時点記録で更新対象外。`docs/guide/customization.md` が指す `modules/detect-config-markers.md` の spec 行は数値の既定値を持たない
- **Issue 本文との矛盾検出**: なし。Background の 3 セッションの数値 (2280s / 2060s / 2190s、上限 2340s に対する 97.4% / 88.0% / 93.6%) は各セッションの `docs/sessions/*/session.md` の Metrics と一致し、`docs/sessions/*/events.jsonl` の `max_silent_window` とも一致した
- **コスト・不可逆な Step**: なし (本番副作用や高コストの実行を含まない)
- **Size の見込み**: Changed Files は 9 件 (Axis 1: L)。既存の再較正パスの水平展開 (Axis 2: -1) で M (pr route) になる見込み。triage 時点の S からの引き上げは Step 18 で確定する

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 曖昧点の自動解決 (2850s 下限と実効値判定) と AC 変更理由の記録。global default 昇格時は tests/watchdog-defaults.bats の更新が必要との注記 / https://github.com/saitoco/wholework/issues/1509#issuecomment-5987169878

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1–4 を Spec どおりに実施)

### Design Gaps/Ambiguities
- 実行環境に bats が無く、`bats tests/` (Pre-merge AC 5) と更新した 3 本の bats をローカルで実行できなかった。代わりに `scripts/get-auto-session-report.sh` を同じフィクスチャ (`max_sec` 2400、`WHOLEWORK_CONFIG_PATH=/dev/null` と 3600 の override) で直接実行し、既定値では `within 600s of watchdog limit` が出て override では出ないことを確認した (近似確認であり AC の根拠ではない)。AC 5 は未チェックのまま、PR の CI で確認する
- `scripts/check-bare-bracket-assertions.sh` は既存テスト全体に 1016 件の警告を出す。本変更とは無関係の既存事象
- `scripts/check-translation-sync.sh` は `docs/guide/xl-decomposition.md` を OUTDATED と報告する。本変更とは無関係の既存事象 (`tech.md` と `customization.md` は IN_SYNC)
- PR 本文の末尾に付けるべき attribution 行を `gh pr create` 時に入れ忘れ、後から `gh pr edit` で追加しようとしたが権限分類器に拒否された。PR は有効なので、追加は行っていない

### Rework
- N/A

## review retrospective

### Spec vs. 実装の乖離パターン
Nothing to note (Spec の Changed Files 9 件がすべて変更され、スコープ外の変更もなかった)

### 繰り返し発生した指摘
Nothing to note (指摘は `docs/ja/tech.md` の `。` 直後の余分な半角スペース 1 件 (CONSIDER) のみで、修正済み)

### 受入条件検証の難しさ
- AC 5 (`bats tests/`) は実行環境に bats がなくローカル検証できず、CI の `Run bats tests` ジョブ結果 (SUCCESS) を根拠に PASS とした。`command` 型の AC は safe mode では CI 参照が前提になる
- 検証コマンド付きの AC 1〜4 はすべて決定的に判定でき、UNCERTAIN は発生しなかった

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- マージ戦略は `resolve-merge-strategy.sh` の結果 (squash) を使用し、競合なし・CI 成功のため rebase は不要だった

### Deferred Items
- Post-merge の observation AC (再較正後の Size M 以上の spec 3 件の観測) は `/verify` では SKIPPED になる想定

### Notes for Next Phase
- `closes #1509` による自動クローズと `phase/verify` ラベルを確認すること
