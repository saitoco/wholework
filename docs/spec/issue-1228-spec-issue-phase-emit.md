# Issue #1228: auto: spec / issue phase の wrapper_exit と token_usage の emit 欠落を解消

## Overview

`spec` / `issue` phase は正常終了時も `wrapper_exit` / `token_usage` イベントを一切 emit しない。`phase_start` / `phase_complete` / `max_silent_window` は emit されているため、フェーズが走っていないのではなく終了時の 2 イベントだけが欠落している。

この欠落により #1064 (spec effort 再校正)、#939 (spec コスト側実測)、#1146 (issue phase の external kill 判定) の 3 件がブロックされている。

**採用方針: 案 ii (wrapper 側で直接 emit)。** 案 i (`run_phase_with_recovery()` 経由への統一) は issue phase を原理的にカバーできない (Root Cause 参照)。

## Reproduction Steps

1. `/auto --batch` を実行し、`spec` phase と `issue` phase を含む Issue を処理する
2. `.tmp/auto-events.jsonl` を集計する:
   ```bash
   jq -rs '[.[]|select(.event=="wrapper_exit")]|group_by(.phase)|map({phase:.[0].phase,n:length})' .tmp/auto-events.jsonl
   jq -rs '[.[]|select(.event=="token_usage")]|group_by(.phase)|map({phase:.[0].phase,n:length})' .tmp/auto-events.jsonl
   ```
3. どちらの内訳にも `spec` / `issue` が現れない

実測 (計測範囲: `.tmp/auto-events.jsonl` 全期間、2026-08-07 時点、フィルタなし):

| event | phase 内訳 |
|---|---|
| `token_usage` | `code-patch`:125 / `code-pr`:109 / `review`:112 / `merge`:108 (`spec`:0, `issue`:0) |
| `wrapper_exit` | `code`:3 / `code-patch`:158 / `code-pr`:119 / `review`:117 / `merge`:112 (`spec`:0, `issue`:0) |

## Root Cause

**2 系統の独立した原因がある。**

### 原因 1 — `wrapper_exit` / `token_usage` の emit 箇所が `run_phase_with_recovery()` の中だけ

`emit_event "wrapper_exit"` (`scripts/run-auto-sub.sh:639`) と `emit_event "token_usage"` (同 L650) は `run_phase_with_recovery()` (L600-) の中にしか存在しない。同関数を経由するのは `code-patch` / `code-pr` / `review` / `merge` のみで、

- **spec** — `scripts/run-auto-sub.sh:841-849` が `run-spec.sh` を直接呼ぶ (`run_phase_with_recovery()` をバイパス)
- **issue** — `skills/auto/SKILL.md` L246 / L1095 / L1126 が `run-issue.sh` を Bash で直接起動する

### 原因 2 — `run-spec.sh` / `run-issue.sh` は token-usage JSON ファイル自体を生成していない

`.tmp/token-usage-<issue>.json` を書き出しているのは `run-code.sh:257-269` / `run-review.sh:245-256` / `run-merge.sh:146-157` の 3 本のみ。いずれも `AUTO_EVENTS_LOG` 設定時に `--output-format json` + `OUTPUT_FORMAT_JSON=1` でキャプチャする分岐を持つ。`run-spec.sh` / `run-issue.sh` にはこの分岐がなく、`--output-format json` を使っていない。

したがって emit を追加するだけでは `token_usage` は永久に発火しない。JSON キャプチャ分岐の追加が前提条件になる。

### 案 i を採らない根拠 (修正アプローチの妥当性)

`run_phase_with_recovery()` は `scripts/run-auto-sub.sh` 内のローカル関数である。`run-issue.sh` は `run-auto-sub.sh` から一度も呼ばれていない (計測範囲: `scripts/` `skills/` `modules/` `docs/` `tests/` を `grep -rn "run-issue.sh"`。`scripts/` 内のヒットは `run-issue.sh` 自身と `collect-run-facts.sh:163,196` の phase→runner 名マッピング文字列のみで、呼び出しは 0 件)。

よって案 i を採っても spec phase しか救えず、AC1 / AC2 の「issue phase でも emit される」を満たせない。案 ii が唯一 2 phase 同時に満たせる方針。

補足: `run-spec.sh` / `run-issue.sh` は既に `run_with_retry_on_kill` でラップ済み (`run-spec.sh:173`, `run-issue.sh:114`) のため、Issue 本文が案 ii のトレードオフに挙げた「retry ラップが引き続き欠落」は実際には当てはまらない。欠落するのは `_write_wrapper_retry_recovery` と `concurrent_commit_detected` のみで、本 Issue の Purpose には不要。

## Changed Files

- `scripts/run-spec.sh`: `AUTO_EVENTS_LOG` 設定時の JSON キャプチャ分岐を追加 (`run-code.sh:256-282` と同型) + reconcile 調整後・`phase_complete` 直前に `wrapper_exit` / `token_usage` emit を追加 — bash 3.2+ 互換
- `scripts/run-issue.sh`: 同上 — bash 3.2+ 互換
- `tests/run-spec.bats`: `wrapper_exit` / `token_usage` emit を保護するテストケース追加
- `tests/run-issue.bats`: 同上
- `modules/event-emission.md`: `### wrapper_exit` / `### token_usage` 節の emit 元・emit 条件・対象 phase・フィールド一覧を実装に合わせて修正 + Wrapper Coverage Table の `run-issue.sh` / `run-spec.sh` 行を更新
- `docs/structure.md`: L224 `detect-external-kill.sh` 説明の前提を修正 (`wrapper_exit` 不在条件が issue / spec phase でも判別力を持つようになった旨)
- `docs/ja/structure.md`: 上記の対訳同期 (`docs/translation-workflow.md` の Sync Procedure に従う。verify command の対象外 — 翻訳出力物のため)
- `docs/reports/event-log-schema.md`: `### 1. token_usage` の `phase` フィールド説明 (L47)、**Emission point** (L56)、**Scope** (L58 「`spec` phase is excluded as it is called directly」) を修正 — [Steering Docs sync candidate] AC8 の rubric 対象外だが同じ主張が実装と食い違うため同時更新

**変更不要 (grep で確認済み):**

- `scripts/run-auto-sub.sh` — 案 ii は spec dispatch チェーン (L837-850) に触れないため、#1108 が追加した XS ゲート・skip ログ文言・`--opus` 受け渡しはいずれも影響を受けない
- `docs/structure.md:215` (`retry-on-kill.sh` の使用元一覧)、`docs/structure.md:235,238` (`run-issue.sh` / `run-spec.sh` の 1 行説明) — 記述内容が本変更の影響を受けない
- `docs/tech.md:41,92` — model / effort matrix の記述であり、出力フォーマットには言及していない
- `tests/run-auto-sub.bats:319,436` — `run-spec.sh` dispatch の有無を検証するテストで、dispatch 自体は不変
- `docs/migration-notes.md:536` — 移行時の履歴記録 (Exclusions に該当)

## Implementation Steps

1. `scripts/run-spec.sh`: `claude` 呼び出し (L170-181) を `run-code.sh:256-282` と同型の 2 分岐に変更する。`AUTO_EVENTS_LOG` が非空のとき `TOKEN_USAGE_FILE=".tmp/token-usage-${ISSUE_NUMBER}.json"` を設定し `mkdir -p .tmp` した上で、`env` 引数に `OUTPUT_FORMAT_JSON=1` を追加し `claude` 引数に `--output-format json` を追加して標準出力を `> "$TOKEN_USAGE_FILE"` へリダイレクトする。直後に `jq -r '.result // empty' "$TOKEN_USAGE_FILE" 2>/dev/null || true` でテキストを標準出力へ補完する。続けて、reconcile 調整ブロック (L184-194) の直後・`phase_complete` emit ブロック (L196-198) の直前に、`_EMIT_PHASE_OWNED` が非空のときのみ `emit_event "wrapper_exit" "phase=${EMIT_PHASE_NAME}" "exit_code=${EXIT_CODE}"` を無条件 (exit code に関わらず) で emit し、その直後に `token_usage` emit を置く。`token_usage` は `run-auto-sub.sh:641-657` の抽出ロジック (`modelUsage` の `inputTokens + outputTokens` 最大キーを `model` に採用、`usage.input_tokens` が空なら emit をスキップ) を逐語移植し、ファイル非存在時はスキップする挙動を維持する。emit 後に `rm -f "$TOKEN_USAGE_FILE"` する。top-level スコープのため `local` は使わず、変数名は `_` 接頭辞で衝突を避ける。bash 3.2+ 互換 (→ 受入条件 AC1, AC2)
2. `scripts/run-issue.sh`: Step 1 と同じ変更を適用する。対象は `claude` 呼び出し (L111-122)、reconcile 調整ブロック (L125-135)、`phase_complete` emit ブロック (L137-139)。`EMIT_PHASE_NAME` は `issue`。`run-issue.sh` は `--effort high` / `--model sonnet` 固定のため、追加する引数は `--output-format json` のみ (parallel with 1) (→ 受入条件 AC1, AC2)
3. `tests/run-spec.bats`: emit 捕捉パターン (既存の L373-405 と同じく `emit-event.sh` mock を `emit_event() { echo "\$@" >> "${EMIT_LOG}"; }` で上書きする形式) で 3 ケース追加 — (a) `wrapper_exit` が `phase=spec` と `exit_code=0` 付きで emit される、(b) `EMIT_PHASE_NAME` 事前設定時は `wrapper_exit` が emit されない (二重 emit 防止)、(c) mock `claude` に token-usage JSON を書かせた上で `token_usage` が `phase=spec` と `model=` 付きで emit される。(c) の mock は `run-auto-sub.bats:1080-1082` のフィクスチャ形状 (`{"model":null,"usage":{"input_tokens":...,"output_tokens":...,"cache_read_input_tokens":...},"modelUsage":{"<model-id>":{"inputTokens":...,"outputTokens":...}}}`) をそのまま使う (after 1) (→ 受入条件 AC3)
4. `tests/run-issue.bats`: Step 3 と同じ 3 ケースを `phase=issue` で追加する。既存の emit テストは L286-317 (after 2) (→ 受入条件 AC3)
5. `modules/event-emission.md`: `### wrapper_exit` (L82-84) を「`run-auto-sub.sh` の `run_phase_with_recovery()` が `code-patch` / `code-pr` / `review` / `merge` について、`run-spec.sh` / `run-issue.sh` が自フェーズについて、いずれも exit code に関わらず毎回 emit する」に修正する (現行の「`claude-watchdog.sh` が abnormal exit 時に emit」は 2 点とも誤り)。`### token_usage` (L86-89) はフィールド一覧から実装に存在しない `cache_write_tokens` を削除し `model` を追加、emit 元と対象 phase を明記する。Wrapper Coverage Table (L144-151) の `run-issue.sh` / `run-spec.sh` 行の「Phase value(s) emitted」欄に `wrapper_exit` / `token_usage` を追記する (→ 受入条件 AC8)
6. `docs/structure.md` L224 の `detect-external-kill.sh` 説明を修正し、`wrapper_exit` 不在条件が全 phase で判別力を持つようになった旨を反映する。あわせて `docs/ja/structure.md` L216 相当の対訳を同期する (`docs/translation-workflow.md` Sync Procedure の 5 手順に従い、code fence 数の一致も確認する) (→ 受入条件 AC8)
7. `docs/reports/event-log-schema.md` の `### 1. token_usage` を修正する: 冒頭文の「parsed from `TOKEN_USAGE_FILE` written by `run-code.sh` / `run-review.sh` / `run-merge.sh`」に `run-spec.sh` / `run-issue.sh` を追加、`phase` フィールド説明 (L47) の値列挙に `spec` / `issue` を追加、**Emission point** (L56) と **Scope** (L58) の「`spec` phase is excluded as it is called directly」を実装後の実挙動に合わせて書き換える (parallel with 5, 6)
8. 4 スイートを実行して回帰がないことを確認する: `bats tests/run-spec.bats tests/run-issue.bats tests/run-auto-sub.bats tests/auto-sub-observability.bats` (after 3, 4) (→ 受入条件 AC4, AC5, AC6, AC7)

## Verification

### Pre-merge

- <!-- verify: rubric "spec フェーズと issue フェーズの終了時に wrapper_exit イベントが phase=spec / phase=issue および exit_code 付きで emit される実装になっている" --> spec / issue phase で `wrapper_exit` が emit される
- <!-- verify: rubric "spec フェーズと issue フェーズについて、.tmp/token-usage-<issue>.json が存在する場合に token_usage イベントが phase 名付きで emit される実装になっている。ファイルが存在しない場合に emit をスキップする既存の挙動 (run-auto-sub.sh:641-657) は維持されている" --> spec / issue phase で `token_usage` が emit される
- <!-- verify: rubric "tests/auto-sub-observability.bats または tests/run-spec.bats / tests/run-issue.bats に、spec / issue フェーズの wrapper_exit と token_usage の emit を保護する検証ケースが追加されており、実装前には FAIL する assert になっている" --> emit がテストで保護されている
- <!-- verify: command "bats tests/auto-sub-observability.bats" --> `tests/auto-sub-observability.bats` が PASS する
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が PASS する
- <!-- verify: command "bats tests/run-spec.bats" --> `tests/run-spec.bats` が PASS する (AC3 の新規テストケースを spec 側 (案 ii) に追加した場合の保護)
- <!-- verify: command "bats tests/run-issue.bats" --> `tests/run-issue.bats` が PASS する (AC3 の新規テストケースを issue 側 (案 ii) に追加した場合の保護)
- <!-- verify: rubric "modules/event-emission.md の wrapper_exit / token_usage セクションの emit 元・emit 条件・対象 phase の記述、および docs/structure.md の detect-external-kill.sh 説明の前提が、spec / issue phase を含めた実装後の実挙動と一致している" --> ドキュメントが実挙動と一致している (`modules/event-emission.md`, `docs/structure.md`)

### Post-merge

- 次の `/auto` 実行後に `.tmp/auto-events.jsonl` を集計し、`wrapper_exit` と `token_usage` の phase 内訳に `spec` と `issue` が現れることを確認する <!-- verify-type: observation event=auto-run session=next -->

## Tool Dependencies

### Bash Command Patterns

- なし (既存の `allowed-tools` で充足。新規 `scripts/*.sh` の追加はないため allowed-tools impact chain check は該当なし)

### Built-in Tools

- なし (`Read` / `Edit` / `Grep` / `Bash` はいずれも登録済み)

### MCP Tools

- なし

## Uncertainty

- **JSON モード切替による `max_silent_window` の意味変化と watchdog kill 条件の変化**: `claude-watchdog.sh:67-84` の `OUTPUT_FORMAT_JSON=1` 分岐はファイルサイズ検査をスキップし `unchanged_time` をリセットしないため、`max_silent_window.max_sec` が「真の無出力ウィンドウ」から「実行時間総量」に変わり、watchdog kill も実質的に total-duration timeout になる (`docs/spec/issue-630-auto-event-log-metrics.md` L130 に既知として記録済み)。#939 が必要とする spec の silent window 実測を壊す懸念があった。
  - **検証方法**: `.tmp/auto-events.jsonl` から `phase_start` → `phase_complete` の実所要時間と `max_silent_window.max_sec` を phase 別に突き合わせる (計測範囲: 全期間、`.tmp/auto-events.jsonl` のみ、session_id / issue / phase の 3 つ組でペアリング、0〜20000 秒の範囲外は除外)
  - **検証結果 (実施済み)**:

    | phase | 実所要時間 p50 / p95 / max (n) | `max_silent_window.max_sec` p50 / max (n) |
    |---|---|---|
    | spec | 914s / 1464s / 1806s (n=229) | 900s / 1800s (n=220) |
    | issue | 433s / 614s / 1025s (n=244) | 420s / 1010s (n=236) |

    差分は p50 で 1〜3% にとどまる。すなわち `spec` / `issue` の `claude -p` は非 JSON モードでも中間出力をほぼ出しておらず、`max_silent_window` は**現状すでに実行時間総量とほぼ同義**である。よって JSON モード化による意味変化・kill リスク増はいずれも実質的に発生しない。#939 の実測の解釈も変わらない。
  - **残存リスク**: spec の実所要時間 max 1806s は `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` (`scripts/watchdog-defaults.sh`) を既に超えており境界にある (`spec` phase の `watchdog_kill` は 2 件)。これは本 Issue 以前から存在する状態で、再校正は #939 のスコープ。実装後に spec の kill 頻度が上がるようなら `.wholework.yml` の `watchdog-timeout-spec-seconds` で調整する
  - **影響範囲**: Implementation Steps 1, 2

## Notes

### `.tmp/token-usage-<issue>.json` の phase 間共有と `rm -f` の理由

`run-spec.sh` が書く token-usage ファイルのパスは `run-code.sh` が書くものと同一 (`.tmp/token-usage-<issue>.json`) である。通常は `run-code.sh` がリダイレクト時点でファイルを truncate するため混同は起きないが、`run-code.sh` がリダイレクトに到達する前に早期 abort した場合、`run_phase_with_recovery()` が spec 由来の古い JSON を読んで `phase=code-patch` の `token_usage` として emit してしまう。これは本 Issue が取得しようとしている実測 (#1064) を汚染する。

Implementation Step 1 / 2 で emit 直後に `rm -f "$TOKEN_USAGE_FILE"` するのはこの混同を断つため。AC2 が求める「ファイル非存在時は emit をスキップ」の挙動は維持される (むしろファイルを一時的な存在にすることで整合する)。

phase-scoped なファイル名 (`.tmp/token-usage-<issue>-spec.json` 等) も検討したが、AC2 の rubric 文言が `.tmp/token-usage-<issue>.json` を名指ししており、既存 3 wrapper の慣行とも揃わないため採用しなかった。

### 案 ii による emit ロジックの複製について

`wrapper_exit` / `token_usage` の emit ロジックが `run-auto-sub.sh` / `run-spec.sh` / `run-issue.sh` の 3 ファイルに複製される。`scripts/emit-event.sh` に共有ヘルパ (`emit_token_usage_from_file` 等) として抽出する案も検討したが、以下の理由で見送った:

- `tests/*.bats` は `emit-event.sh` を heredoc mock で置き換えており、その定義は 8 ファイル計 54 箇所ある (計測範囲: `tests/*.bats` を `grep -rn 'emit-event.sh" <<'`)。うち本ヘルパの呼び出し経路に乗るのは `run-auto-sub.bats` (15)、`auto-sub-observability.bats` (3)、`run-spec.bats` (6)、`run-issue.bats` (4) の計 28 箇所。全 wrapper が `set -e` のため、mock にヘルパを追加し忘れた 1 箇所が即座にテスト abort になる
- 既に `_maybe_emit_phase_complete()` が `run-spec.sh:81-98` / `run-issue.sh:31-48` / `run-code.sh` に逐語的に複製されており、小さな emit ヘルパの wrapper 間複製は本リポジトリの既存慣行である

共有ヘルパ化は follow-up 候補として記録する (本 Issue では起票しない — 改善提案は `/verify` フェーズで集約する)。

### `--output-format json` 化による `/auto` ログの見え方の変化

`spec` / `issue` phase の標準出力が JSON リダイレクトに吸われるため、`/auto` のログ上でリアルタイムに流れていた内容が最終 `jq -r '.result'` の 1 回出力に変わる。`run-code.sh` / `run-review.sh` / `run-merge.sh` が既にこの形式であり、`run-spec.sh` の `print_end_banner` / `Exit code: ` トレーラ出力は JSON リダイレクトの外側にあるため `detect-external-kill.sh` の「`Exit code: ` トレーラ不在」判定には影響しない。

### `wrapper_exit` の `exit_code` に reconcile 調整後の値を使う理由

`run-spec.sh` / `run-issue.sh` は `claude` の raw exit code を reconcile 結果で補正する (143 → 0、0 → 1)。`run_phase_with_recovery()` が `code-patch` について emit する `exit_code` は `run-code.sh` が同じ補正を済ませた**後**の最終 exit code なので、パリティを取るには spec / issue でも補正後の `EXIT_CODE` を使うのが正しい。

外部 kill 時は wrapper 自体が emit 到達前に落ちるため `wrapper_exit` は不在のままとなり、`detect-external-kill.sh` のシグネチャは意図通り機能する。

### `_EMIT_PHASE_OWNED` ガードを付ける理由

`phase_start` / `phase_complete` と同じガードを `wrapper_exit` / `token_usage` にも適用する。現状 `EMIT_PHASE_NAME` は spec / issue dispatch のいずれでも未設定なので実挙動は変わらないが、将来 spec が `run_phase_with_recovery()` 経由に変わった場合 (#1108 系の再構成) に二重 emit を自動的に防げる。

### ツール検出パターン整合性 / 外部仕様依存 / 依存バージョン

- 新規のツール検出は含まないため、tool detection pattern consistency check は該当なし
- 外部パッケージレジストリからの新規依存追加はないため、dependency version pre-check は該当なし
- `--output-format json` は既に本リポジトリ内 3 wrapper で使用中の Claude Code CLI オプションであり、外部仕様の新規調査は不要

### verify command の adapter 調査

Issue 本文の verify command は `rubric` (5 件) と `command "bats ..."` (4 件) のみで、いずれも `modules/verify-executor.md` の built-in translation table に存在する command type。よって `docs/environment-adaptation.md` Extension Guide Step 0 の adapter 調査は該当なし。

## Consumed Comments

cutoff: `2026-08-07T07:29:33Z` (直近の `phase/*` label 付与時刻、Issue timeline より取得)

| login | authorAssociation | trust tier | 意図 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue 1228 --non-interactive` の Issue Retrospective。AC4/AC5 のテストファイル検証範囲拡張と AC6 の対象ファイル明示という 2 件の自動解決を報告し、案 i / 案 ii の方針選択は `/spec` に委ねたことを明記 | [#issuecomment-5213951164](https://github.com/saitoco/wholework/issues/1228#issuecomment-5213951164) |

cutoff 以前のコメント 2 件 (`#issuecomment-5212048140` — AC6 対象範囲となるドキュメント不正確さの特定、`#issuecomment-5213033677` — #1108 着地後の案 i 制約 3 件の申し送り) は消費対象外だが、いずれも設計判断に直結するため参照した。前者は Changed Files の `modules/event-emission.md` / `docs/structure.md` に、後者は Root Cause の「案 i を採らない根拠」に反映済み。
