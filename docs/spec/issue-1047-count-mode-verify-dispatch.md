# Issue #1047: auto: Count mode に verify orchestration を追加し stop-at 判定を共通ヘルパー化

## Overview

`/auto --batch N` (Count mode) の `#### Process Each Issue` には verify orchestration ステップが存在しない。List mode (`--batch N1 N2 ...`) は step 7 に verify dispatch と `AUTO_STOP_AT` / `--non-interactive` gate を持つため、同じ `--batch` でもモードによって Issue の到達フェーズが変わる。

本 Issue では (1) Count mode に step 6 として List mode step 7 と同型の verify orchestration ブロックを追加し、(2) `scripts/run-auto-sub.sh` に分散した stop-at 判定 6 箇所を新規共通ヘルパー `scripts/should-stop-at-phase.sh` に集約する。

## Reproduction Steps

1. `.wholework.yml` を持つ repo で `phase/ready` の XS/S Issue を 1 件以上用意する。
2. `/auto --batch 1` を実行する (Count mode)。
3. `run-auto-sub.sh` が merge まで完走し、Issue に `phase/verify` が付与される。
4. 親セッションはそのまま次の Issue 処理へ進み、`/verify` は一度も dispatch されない。Issue は `phase/verify` のまま放置される。
5. 同じ Issue を `/auto --batch <N1> <N2>` (List mode) で処理すると、step 7 の verify orchestration により `/verify` が dispatch され `phase/done` まで到達する。

## Root Cause

`skills/auto/SKILL.md` の `#### Process Each Issue` (Count mode, L1130-L1141) は step 1-5 (labels check → run-issue → get-size → run-auto-sub → XS retro transcription) で終わっており、verify dispatch ステップが最初から書かれていない。

`scripts/run-auto-sub.sh` は Size に関わらず verify を呼ばない設計 (`# verify is deferred to the parent /auto session` — Issue #485) なので、親セッション側にステップが無い限り verify は永久に走らない。List mode は #615 で verify orchestration を得て #1044 で `AUTO_STOP_AT` gate を得たが、Count mode には同じ追加が波及していない。

修正方針の妥当性: Count mode に step 6 を追加するだけで両モードの verify 挙動が一致する。`run-auto-sub.sh` 側を変更して verify を呼ばせる案は Issue #485 の設計 (verify は親セッションで AskUserQuestion を使えるコンテキストで実行する) を覆すため採らない。

## Changed Files

- `scripts/should-stop-at-phase.sh`: 新規。phase 順序に基づく stop-at 判定を単一の決定点に集約する predicate script — bash 3.2+ 互換 (連想配列・`mapfile` 不使用)
- `scripts/run-auto-sub.sh`: `AUTO_STOP_AT` 直接比較 6 箇所 (L976 / L978 / L1059 / L1065 / L1138 / L1144) を helper 呼び出しに置換 — bash 3.2+ 互換
- `skills/auto/SKILL.md`: `#### Process Each Issue` (Count mode) に stop-at 設定の読み込みブロックと step 6 (verify orchestration) を追加
- `tests/should-stop-at-phase.bats`: 新規。helper の phase 順序判定・fallback・usage error を検証
- `tests/run-auto-sub.bats`: `setup()` の `$MOCK_DIR` に実物の `should-stop-at-phase.sh` を copy (既存の `get-config-value.sh` と同じ扱い)
- `tests/auto-batch.bats`: Count mode section 用の構造テスト 5 件を追加
- `docs/structure.md`: `**Process management:**` に helper のエントリを追加、Directory Layout の `(92 files)` を `(93 files)` に更新
- `docs/ja/structure.md`: 同上 (`**プロセス管理:**` / `(92 ファイル)` → `(93 ファイル)`)
- `docs/workflow.md`: `**`--batch N`**` 段落を、verify orchestration が Count/List 両モードで走ること・`auto-stop-at` gate の存在・blocked-by gate が List mode 限定であることを明示するよう更新
- `docs/ja/workflow.md`: 同上 (日本語ミラー、`docs/translation-workflow.md` の同期義務対象)
- [Steering Docs sync candidate] `modules/detect-config-markers.md`: keyword `AUTO_STOP_AT` の grep で 7 files 一致 (うち 4 件は `docs/spec/` の過去 Spec で除外)。本ファイルは `auto-stop-at` の有効値と fallback (`verify`) を定義する SSoT。helper はこの fallback 規則をそのまま実装するため記述変更は不要の見込みだが、`/code` 側で fallback 文言が現状と整合しているか確認すること
- [Steering Docs sync candidate] keyword `auto-stop-at` skipped: matched 30 files (no discriminating power)
- [Steering Docs sync candidate] keyword `run-auto-sub.sh` skipped: matched 38 files (no discriminating power)
- [Steering Docs sync candidate] keyword `auto` (bare skill name) skipped: 弁別力なし

## Implementation Steps

1. `scripts/should-stop-at-phase.sh` を新規作成する (→ 受入基準 4, 5)。インターフェースと分岐挙動は下記「helper 分岐仕様 (exhaustive)」の通り。
2. `scripts/run-auto-sub.sh` の `AUTO_STOP_AT` 直接比較 6 箇所を helper 呼び出しに置換する (after 1) (→ 受入基準 4, 5)。置換対象と等価性は下記「run-auto-sub.sh 置換対応表 (exhaustive)」の通り。`AUTO_STOP_AT` の代入行 (`AUTO_STOP_AT=$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify ...)`) は残し、helper には第 2 引数として解決済みの値を渡す (config 再読み込みを 6 回発生させないため)。
3. `skills/auto/SKILL.md` の `#### Process Each Issue` (Count mode) に、見出し直後・`Process the selected N Issues **sequentially** (serially):` の直前へ stop-at 設定の読み込みブロックを挿入し、既存 step 5 の直後に step 6 (verify orchestration) を追加する (parallel with 1, 2) (→ 受入基準 1, 2)。挿入内容は下記「Count mode 追加ブロック仕様」の通り。半角感嘆符と 3 連バッククォートを本文に含めないこと (`validate-skill-syntax.py` の MUST 制約)。
4. `tests/should-stop-at-phase.bats` を新規作成する (after 1) (→ 受入基準 6)。テストケースは下記「新規テストケース一覧 (exhaustive)」の通り。
5. `tests/run-auto-sub.bats` の `setup()` 内、`get-config-value.sh` を copy している行の直後に、実物の `scripts/should-stop-at-phase.sh` を `$MOCK_DIR` へ copy する行と `chmod +x` を追加する (after 1) (→ 受入基準 6)。同ファイルは `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているため、copy を怠ると既存の `auto-stop-at` 系テスト 3 件が helper 不在で失敗する。
6. `tests/auto-batch.bats` に Count mode section 用の `@test` を 5 件追加する (after 3) (→ 受入基準 3, 6)。テスト名とアサーションは下記「新規テストケース一覧 (exhaustive)」の通り。既存の `count_mode_section()` と同じ awk パターンを `run bash -c` 内で用いる。
7. `docs/structure.md` を更新する (after 1) (→ 受入基準 7, 8): `**Process management:**` の `scripts/resolve-batch-query.sh` 行の直後に helper のエントリを 1 行追加し、Directory Layout の `├── scripts/             # Utility scripts used by skills and agents (92 files)` を `(93 files)` に更新する。件数は `find scripts -maxdepth 1 -type f | wc -l` の値 (サブディレクトリ `scripts/git-hooks/` を除く top-level のみ) に一致させる。
8. `docs/ja/structure.md` を同様に更新する (after 7) (→ 受入基準 9, 10): `**プロセス管理:**` の `scripts/resolve-batch-query.sh` 行の直後に日本語エントリを追加し、`(92 ファイル)` を `(93 ファイル)` に更新する。
9. `docs/workflow.md` および `docs/ja/workflow.md` の `--batch N` 段落を更新する (after 3) (→ 受入基準 10)。(a) verify orchestration が Count mode と List mode の両方で走ることを明示、(b) `auto-stop-at: merge` 設定時は verify を skip し `phase/verify` を残すことを追記、(c) 現状「各 Issue の処理開始前に blocked-by 関係を確認」と両モード共通のように読める記述を List mode 限定であると明示。日本語ミラーは `docs/translation-workflow.md` の同期手順に従い、code fence 数の一致を確認する。

### helper 分岐仕様 (exhaustive)

インターフェース:

- 実行形式: `scripts/should-stop-at-phase.sh <completed-phase> [stop-at-value]`
- `<completed-phase>`: 直前に完了したフェーズ名 (`spec` / `code` / `review` / `merge` / `verify`)
- `[stop-at-value]`: 任意。省略時は `"$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify` で `.wholework.yml` から解決する (`SCRIPT_DIR` は `${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}`、`run-auto-sub.sh` と同じ解決方式)
- 標準出力: なし (呼び出し元のログを汚さないため)
- 判定式: phase 順序を `spec=1 / code=2 / review=3 / merge=4 / verify=5` とし、`order(stop-at) <= order(completed-phase)` のとき stop

分岐 (exhaustive):

| # | 条件 | 終了コード | stdout / stderr | 意味 |
|---|------|-----------|-----------------|------|
| 1 | `order(stop-at) <= order(completed-phase)` | 0 | なし | stop — `<completed-phase>` より先へ進まない |
| 2 | `order(stop-at) > order(completed-phase)` | 1 | なし | continue — 次フェーズへ進む |
| 3 | `<completed-phase>` が未指定または未知の値 | 2 | stderr に `should-stop-at-phase.sh: unknown completed phase: '<value>'` | usage error。呼び出し元が `if` 条件で使う限り分岐 2 と同じ「continue」側に落ちる (fail-open) |
| 4 | `[stop-at-value]` が空文字・未知の値 | 分岐 1 または 2 に従う | なし | `verify` (= フルパイプライン) に fallback。`modules/detect-config-markers.md` の documented fallback と一致し、既存の直接比較が未知値で false になる挙動と等価 |
| 5 | `[stop-at-value]` 省略時に `get-config-value.sh` が失敗 | 分岐 1 または 2 に従う | なし | `|| echo verify` により `verify` へ fallback。`run-auto-sub.sh` L955 の既存 fallback と同一 (fail-open) |

fail-safe 設計の根拠 (本 helper は `modules/*` の gate に相当するため明記): 未知入力・依存コマンド失敗のいずれも **fail-open (continue)** を選ぶ。既存の直接比較 (`[[ "$AUTO_STOP_AT" == "review" ]]`) は未知値に対して false = continue であり、fail-open が唯一の挙動保存的な選択である。fail-closed (stop) にすると設定ミスやタイポでパイプラインが無言で停止し、Issue が中間フェーズに滞留する work loss を生む。

その他の入力エッジケース:

- 空入力 (`$1` が空文字): 分岐 3 (exit 2)。`"${1:-}"` で `set -u` 由来の異常終了を避ける
- 巨大入力・特殊文字 (`>` / `"` / 改行 / CRLF / マルチバイト): 判定は `case "$value" in spec) ...` のリテラルパターン照合で行う。パターン側にメタ文字を含めないため、word 側のメタ文字は特別扱いされない。いずれも「未知の値」として分岐 3 (`<completed-phase>`) または分岐 4 (`[stop-at-value]`) に落ちる
- timeout / kill 条件: 本 helper は外部通信もループも持たない短命プロセスであり、timeout 監視・kill ハンドリング・監視継続の概念は持たない (該当なし)
- error path: 分岐 3 のみ。retry / restart は行わない

bash 3.2 互換: 連想配列・`mapfile` を使わず `case` による順序解決のみを用いる。`set -euo pipefail` は使わず `set -uo pipefail` とする (`exit 1` が正常な判定結果であるため)。

### run-auto-sub.sh 置換対応表 (exhaustive)

| # | 現在の行 (近傍コンテキスト) | 現在の条件式 | 置換後 | 等価性 |
|---|------------------------------|--------------|--------|--------|
| 1 | tier3 skip 分岐、`_SKIP_PR_NUMBER` が非空のとき最初の `if` | `[[ "$AUTO_STOP_AT" == "code" \|\| "$AUTO_STOP_AT" == "spec" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" code "$AUTO_STOP_AT"` | stop 集合 `{spec, code}` で一致 |
| 2 | 同 `elif` | `[[ "$AUTO_STOP_AT" == "review" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" review "$AUTO_STOP_AT"` | 直前の `if` で `{spec, code}` が除かれるため実効集合は `{review}` で一致 |
| 3 | `M)` ケース、`echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"` の直後の `if` | `[[ "$AUTO_STOP_AT" == "spec" \|\| "$AUTO_STOP_AT" == "code" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" code "$AUTO_STOP_AT"` | stop 集合 `{spec, code}` で一致 |
| 4 | `M)` ケース、review phase 実行直後のネストされた `if` | `[[ "$AUTO_STOP_AT" == "review" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" review "$AUTO_STOP_AT"` | 外側 `else` により `{spec, code}` が除かれるため実効集合は `{review}` で一致 |
| 5 | `L)` ケース、`echo "${LOG_PREFIX} PR number: ${PR_NUMBER}"` の直後の `if` | `[[ "$AUTO_STOP_AT" == "spec" \|\| "$AUTO_STOP_AT" == "code" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" code "$AUTO_STOP_AT"` | # 3 と同じ |
| 6 | `L)` ケース、review phase 実行直後のネストされた `if` | `[[ "$AUTO_STOP_AT" == "review" ]]` | `"$SCRIPT_DIR/should-stop-at-phase.sh" review "$AUTO_STOP_AT"` | # 4 と同じ |

`run-auto-sub.sh` は `set -euo pipefail` 下で動作するが、`if <command>; then` の条件位置に置かれたコマンドの非ゼロ終了は `set -e` の対象外であるため、helper が exit 1 を返しても script は停止しない。同ファイル内の既存 predicate `_spec_is_diffless()` (`if _spec_is_diffless "$SUB_NUMBER"; then`) が同じ 0/1 規約を採っており、本 helper はその慣行に揃える。

未知値・`merge`・`verify` の扱い: いずれの分岐でも helper は continue (exit 1) を返し、merge phase まで実行される。これは置換前の挙動と同一。

### Count mode 追加ブロック仕様

`#### Process Each Issue` の見出し直後に挿入する読み込みブロック:

- 太字見出し `**Load stop-at setting (Count mode only):**` と、`${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` を Read して "Processing Steps" セクションに従い `AUTO_STOP_AT` を retain する旨の 1 段落。List mode は同等ブロックを numbered steps の外に置いた結果、Until mode step 1 で「steps 1-7 の再利用では拾えない」という補足を要したため、Count mode では `#### Process Each Issue` セクション内に置いて自己完結させる

既存 step 5 の直後に追加する step 6:

- 見出し: `6. **Verify orchestration** (after run-auto-sub.sh success):`
- `gh issue view $NUMBER --json labels -q '.labels[].name'` で labels を再取得
- `phase/verify` が labels に含まれる場合:
  - `AUTO_STOP_AT == "merge"` のとき: `Skipping verify for #$NUMBER (auto-stop-at=merge); phase/verify remains` を出力して次の Issue へ
  - そうでなく `--non-interactive` が ARGUMENTS に **無い** とき: `Skill(skill="wholework:verify", args="$NUMBER --session-id=<literal SESSION_ID value from step 1>")` を親セッションで invoke。失敗時または出力に `MAX_ITERATIONS_REACHED` を含む場合は警告を出して次の Issue へ (batch 全体は中断しない)
  - そうでない (`--non-interactive` が有る) とき: `Skipping verify for #$NUMBER (non-interactive mode); phase/verify remains` を出力して次の Issue へ
- `phase/verify` が labels に無い場合: 何もせず次の Issue へ
- ブロック末尾に注記を 1 行置く: Count mode は `BATCH_ID` を持たない (`write_batch` を一度も呼ばない) ため、List mode step 7 と異なり `auto-checkpoint.sh update_batch` は呼ばない

gate は List mode step 7 と同じリテラル比較 (`AUTO_STOP_AT == "merge"`) を使い、helper の phase 順序判定は用いない。順序判定に広げると `auto-stop-at: review` などで List mode と挙動が分かれ、本 Issue の目的である挙動統一に反するため。

### 新規テストケース一覧 (exhaustive)

`tests/should-stop-at-phase.bats` (新規):

| `@test` 名 | 入力 | 期待 |
|-----------|------|------|
| `should-stop-at-phase: stop-at=code, completed=code -> stop` | `code code` | exit 0 |
| `should-stop-at-phase: stop-at=spec, completed=code -> stop` | `code spec` | exit 0 |
| `should-stop-at-phase: stop-at=review, completed=code -> continue` | `code review` | exit 1 |
| `should-stop-at-phase: stop-at=review, completed=review -> stop` | `review review` | exit 0 |
| `should-stop-at-phase: stop-at=merge, completed=review -> continue` | `review merge` | exit 1 |
| `should-stop-at-phase: stop-at=verify, completed=merge -> continue` | `merge verify` | exit 1 |
| `should-stop-at-phase: unknown stop-at value falls back to verify` | `review bogus` | exit 1 |
| `should-stop-at-phase: empty stop-at value falls back to verify` | `review ""` | exit 1 |
| `should-stop-at-phase: stop-at read from .wholework.yml when omitted` | `review` + `WHOLEWORK_CONFIG_PATH` に `auto-stop-at: review` | exit 0 |
| `should-stop-at-phase: missing config falls back to verify` | `review` + `WHOLEWORK_CONFIG_PATH=/dev/null` | exit 1 |
| `should-stop-at-phase: unknown completed phase exits 2` | `bogus verify` | exit 2、stderr に `unknown completed phase` |
| `should-stop-at-phase: no arguments exits 2` | 引数なし | exit 2 |

テスト入力データ形式: 第 1 引数・第 2 引数はいずれもプレーン文字列。config 読み込み経路の 2 件は `export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/.wholework.yml"` を設定し、その YAML に `auto-stop-at: <value>` を 1 行だけ書いた flat key 形式を用いる (`scripts/get-config-value.sh` header の Supported Input Shapes 表 #1 に該当)。`get-config-value.sh` を呼ぶ 2 件のみ `export WHOLEWORK_SCRIPT_DIR` を helper と同じ `scripts/` に向ける。

`tests/auto-batch.bats` に追加する `@test` (すべて `count_mode_section()` と同じ awk 抽出結果に対する `grep -q`):

| `@test` 名 | 検索文字列 |
|-----------|-----------|
| `Count mode section: wholework:verify Skill invocation present` | `wholework:verify` |
| `Count mode section: phase/verify label check present` | `phase/verify` |
| `Count mode section: AUTO_STOP_AT retained for verify gate` | `AUTO_STOP_AT` |
| `Count mode section: auto-stop-at merge skip behavior present` | `auto-stop-at=merge` |
| `Count mode section: non-interactive skip behavior present` | `non-interactive` |

## Alternatives Considered

**共通ヘルパーを `skills/auto/SKILL.md` の LLM prose 8 箇所にも適用する案 (不採用)**: prose 側の判定は `EFFECTIVE_STOP_AT == "spec"` のような 1 行の等価比較であり、`--stop-at` フラグ override を織り込んだ `EFFECTIVE_STOP_AT` を使う。subprocess 呼び出しに置き換えても各 prose 箇所の記述行は残るため編集箇所数は減らず、実行コストと失敗面のみ増える。AC 4 の rubric が `tests/run-auto-sub.bats` を名指ししていること、共通ヘルパー化トリガーの系譜 (#980 / #1042) がいずれも `run-auto-sub.sh` であることからも、bash 側 6 箇所が本来の対象と判断した。

**Count mode の gate を helper の phase 順序判定に広げる案 (不採用)**: `auto-stop-at: review` などでも verify を skip できるようになるが、List mode step 7 のリテラル比較との非対称が新たに生まれる。本 Issue の目的は両モードの挙動統一であり、List mode 側の gate 変更は Issue 本文で明示的に対象外とされている。

**`run-auto-sub.sh` 側で verify を呼ぶ案 (不採用)**: Issue #485 が verify を親セッションに委譲した設計 (AskUserQuestion を使えるコンテキストで manual AC を確認する) を覆すことになる。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の Count mode Process Each Issue に、Issue ごとの verify dispatch (phase/verify チェックと AUTO_STOP_AT gate と --non-interactive gate を含む) が追加されている" --> `skills/auto/SKILL.md` Count mode の Process Each Issue に List mode Step 7 相当の verify orchestration ブロックが追加されている
- <!-- verify: section_contains "skills/auto/SKILL.md" "Process Each Issue" "AUTO_STOP_AT" --> `Process Each Issue` (Count mode) セクション内に `AUTO_STOP_AT` gate が実装されている
- <!-- verify: file_contains "tests/auto-batch.bats" "Count mode section: auto-stop-at merge skip behavior present" --> Count mode の verify orchestration ブロックの挙動を検証する bats テストが `tests/auto-batch.bats` に追加されている
- <!-- verify: rubric "scripts/should-stop-at-phase.sh が phase 順序 (spec<code<review<merge<verify) に基づく stop 判定を行い、scripts/run-auto-sub.sh 内の AUTO_STOP_AT 直接比較が全て helper 呼び出しに置き換わっており、置換前後で分岐条件が等価である" --> 共通ヘルパーが実装され、`run-auto-sub.sh` の `AUTO_STOP_AT` 直接比較 6 箇所が helper 呼び出しに置き換えられている
- <!-- verify: file_contains "scripts/run-auto-sub.sh" "should-stop-at-phase.sh" --> `scripts/run-auto-sub.sh` が helper を参照している
- <!-- verify: command "bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/should-stop-at-phase.bats tests/run-auto-sub.bats tests/auto-batch.bats" --> helper の新規テストと既存スイートが PASS する (新規ロジックを検証する新規テストケースを追加したうえでスイート全体が PASS すること)
- <!-- verify: file_contains "docs/structure.md" "should-stop-at-phase.sh" --> `docs/structure.md` の Scripts セクションに新スクリプトのエントリが追加されている
- <!-- verify: file_contains "docs/structure.md" "(93 files)" --> `docs/structure.md` の Directory Layout のスクリプト件数コメントが更新されている
- <!-- verify: file_contains "docs/ja/structure.md" "(93 ファイル)" --> `docs/ja/structure.md` の Directory Layout のスクリプト件数コメントが更新されている
- <!-- verify: rubric "docs/workflow.md と docs/ja/workflow.md の --batch 記述が Count mode でも verify orchestration が走ることと auto-stop-at gate の存在を記載しており、docs/ja/structure.md に should-stop-at-phase.sh のエントリがある" --> `docs/workflow.md` / `docs/ja/workflow.md` の `--batch N` 記述が更新され、`docs/ja/structure.md` にも新スクリプトのエントリが追加されている

### Post-merge

- tofas repo (または他の `.wholework.yml` を持つ repo) で Count mode (`/auto --batch N`) を実行し、verify phase まで自動進行することを確認
- tofas repo で Count mode + `auto-stop-at: merge` 設定下で `/auto --batch N` を実行し、verify phase が skip されることを確認

## Tool Dependencies

### Bash Command Patterns

- なし (`skills/auto/SKILL.md` の `allowed-tools` には `gh issue view:*` が既に登録済み。新規 `${CLAUDE_PLUGIN_ROOT}/scripts/` 参照を SKILL.md 本文に追加しないため、`allowed-tools` の変更は不要)

### Built-in Tools

- なし (`Skill` は `skills/auto/SKILL.md` の `allowed-tools` に登録済み)

### MCP Tools

- なし

## Uncertainty

- **`section_contains` の heading 引数の照合規則**: 解決済み。`modules/verify-executor.md` L70 により、heading 引数は対象見出し行から先頭の `#` と空白を除去したうえで部分一致する。Issue 本文にあった `"#### Process Each Issue"` は恒久的に UNCERTAIN になるため `"Process Each Issue"` に修正した (triage AC audit コメントの指摘と一致)。`#### Process Each Issue` は `skills/auto/SKILL.md` 内で一意であり、次の同レベル以上の見出しは `### List mode (--batch N1 N2 ...)` であるため、抽出範囲は Count mode の Process Each Issue ブロックのみになる。
  - **検証方法**: `modules/verify-executor.md` の翻訳表を読み、`grep -n "#### Process Each Issue" skills/auto/SKILL.md` で一意性を確認済み
  - **影響範囲**: Implementation Steps 3、受入基準 2
- **`set -e` 下での exit 1 の扱い**: 解決済み。`if <command>; then` の条件位置に置かれたコマンドの非ゼロ終了は `set -e` の対象外。同じ `scripts/run-auto-sub.sh` 内の既存 predicate `_spec_is_diffless()` が同じ 0/1 規約で `if` 条件に使われていることを確認した。
  - **検証方法**: `scripts/run-auto-sub.sh` L627-L654 (`_spec_is_diffless()` 定義) と L948 (`if _spec_is_diffless ...`) を Read
  - **影響範囲**: Implementation Steps 1, 2
- **`tests/run-auto-sub.bats` の `WHOLEWORK_SCRIPT_DIR` mock**: 解決済み。同ファイルは `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しており、`run-auto-sub.sh` の `$SCRIPT_DIR/should-stop-at-phase.sh` は `$MOCK_DIR` を指す。`get-config-value.sh` / `retry-on-kill.sh` と同様に実物を copy する必要がある。
  - **検証方法**: `tests/run-auto-sub.bats` L21-L125 を Read
  - **影響範囲**: Implementation Steps 5

## Notes

- **Issue 本文の事実主張と実装の突き合わせ (`8 箇所`)**: Issue 本文の「stop-at 判定箇所が合計 8 箇所に到達する」は、`grep -c 'EFFECTIVE_STOP_AT ==' skills/auto/SKILL.md` = 6 と `grep -c 'AUTO_STOP_AT ==' skills/auto/SKILL.md` = 1 の合計 7 に、本 Issue の Count mode 追加分 1 を足した数 (= SKILL.md の LLM prose のみ) と一致する。一方 `grep -c 'AUTO_STOP_AT" ==' scripts/run-auto-sub.sh` = 6 の bash 条件式は含まれていない。共通ヘルパーは bash script であり、実際の置換対象は後者の 6 箇所である。この不一致を解消するため Issue 本文の該当記述と AC 4 を更新した (詳細は Auto-Resolve Log を参照)。
- **audit/investigation 型 Issue 判定**: 該当しない。本 Issue は既存項目の分類・監査ではなく、`skills/auto/SKILL.md` と `scripts/run-auto-sub.sh` への機能追加/リファクタである。よって「判断根拠として書く識別子の grep 事前検証」ステップは追加していない (ただし本 Spec 内で引用した行番号・関数名はすべて grep/Read で確認済み)。
- **fail-safe critical script 判定**: 該当する。`scripts/should-stop-at-phase.sh` は「先へ進むか止めるかを決める gate」(判定基準 a) であるため、空入力・特殊文字・依存コマンド失敗時の挙動を Implementation Steps の「helper 分岐仕様 (exhaustive)」に明記した。すべて fail-open (continue) を採用し、その根拠 (既存の直接比較が未知値で false = continue であること、fail-closed だと設定ミスで Issue が中間フェーズに滞留すること) を同節に記載した。
- **新規分岐ロジックに対する新規テストケース要件**: Implementation Steps 1 (helper の 5 分岐) と 3 (Count mode step 6 の 3 分岐) はいずれも新規分岐ロジックであるため、受入基準 6 の `command "bats ..."` は既存スイートの PASS だけでなく、`tests/should-stop-at-phase.bats` の 12 ケースと `tests/auto-batch.bats` の Count mode 5 ケースを追加したうえでのスイート PASS を要求する。
- **Uncertainty と Implementation Steps の整合**: Uncertainty の 3 項目はいずれも Implementation Steps に転記済み ( `section_contains` 修正 → Step 3 と受入基準 2、`set -e` 規約 → Step 1/2 と「run-auto-sub.sh 置換対応表」末尾の注記、mock copy → Step 5)。転記漏れを埋める方向 (a) で解消した。
- **allowed-tools impact chain check**: 新規 `scripts/*.sh` を追加するが、呼び出し元は `scripts/run-auto-sub.sh` (bash subprocess) のみで、いずれの `skills/*/SKILL.md` 本文からも参照しない。したがって `allowed-tools` への `${CLAUDE_PLUGIN_ROOT}/scripts/should-stop-at-phase.sh:*` 追加は不要。`modules/*.md` の変更も含まないため Case 2 も非該当。
- **`.claude/` ファイルの変更なし**: `git add -f` の考慮は不要。
- **CI 制約**: `scripts/` と `skills/` の追加行は英語であること (`scripts/check-language-convention.py` が diff に対して CJK を検出する。日本語は二重引用符内の文字列とインラインコードスパンのみ許容)。`skills/auto/SKILL.md` 本文には半角感嘆符と 3 連バッククォートを含めないこと (`scripts/validate-skill-syntax.py` の MUST 制約)。`scripts/*.sh` は macOS の bash 3.2 で `bash -n` が通ること。
- **Smoke Test 非該当**: 外部/MCP ツール呼び出しを含まないため `## Smoke Test` セクションは設けない。
- **UI Design 非該当**: UI 変更を含まない。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective。Background の事実主張をコードベース照合済みであること、条件付き共通ヘルパー化 AC を #1044 の先例に合わせて維持したこと、blocked-by なし・タイトルドリフトなしを報告 / https://github.com/saitoco/wholework/issues/1047#issuecomment-5378149523
- saito / MEMBER / first-class / Triage AC audit の警告。`section_contains` の heading 引数に先頭の `####` を含めており恒久 UNCERTAIN になるため `"Process Each Issue"` へ修正するよう指摘 (本フェーズで Issue 本文と Spec の両方に反映済み) / https://github.com/saitoco/wholework/issues/1047#issuecomment-5378164415

- saito / MEMBER / first-class / ## Change Tracking (by /code) / https://github.com/saitoco/wholework/issues/1047#issuecomment-5378393718
## issue retrospective

- Background に記載された事実主張 (Count mode に verify orchestration ステップが存在しないこと、List mode Step 7 との対比、stop-at 判定箇所が本 Issue の実装で合計 8 箇所に到達する見込み) をコードベース照合し、いずれも `skills/auto/SKILL.md` / `scripts/run-auto-sub.sh` の現状実装と整合していることを確認した (Step 5 advisory check)。
- Acceptance Criteria: Pre-merge AC の1件目 (`rubric` で verify orchestration ブロック追加を判定) に対し、`modules/verify-patterns.md` §9 のガイドライン (rubric + supplementary file_contains/section_contains) に従い、対象ファイルとセクション見出し (`skills/auto/SKILL.md` の `#### Process Each Issue` 見出し、Count mode 配下で一意) が事前に特定可能なため、`section_contains "skills/auto/SKILL.md" "#### Process Each Issue" "AUTO_STOP_AT"` を機械的な補完チェックとして追加した。2件目の AC (bats テスト追加を判定する rubric) は追加されるテストケース名が実装依存 (developer-determined) であり、`modules/verify-patterns.md` §9 の "When NOT to apply" (実装箇所が developer-determined) に該当するため、補完チェックは付与しなかった。
- 共通ヘルパー化 AC (`should-stop-at-phase.sh` 相当) は本文で既に「実装した場合」という条件付き AC として記載されている。過去の Issue #1044 の Spec (`docs/spec/issue-1044-batch-verify-stop-at-merge.md`) では、同種の共通ヘルパー化を「既存パターンとの差分最小化を優先し見送り、分散箇所が閾値を超過した時点で別 Issue にて再検討する」方針が明示的に記録されており、本 Issue はまさにその「別 Issue」に相当するスコープを含む。この過去判断と整合するため、AC を必須化せず条件付きのまま維持した (auto-resolve — 過去の同種判断からの一意な推論)。
- Blocked-by: `gh-check-blocking.sh` は exit 0 (オープンなブロッカーなし)。
- タイトルドリフト: なし (現在のタイトルは更新後の本文スコープと一致)。
- Sub-issue 分割評価: non-interactive モードのため High-Stakes Decision としてスキップ。Size L だが `skills/auto/SKILL.md` への同型ブロック追加 + テスト追加という単一スコープの変更であり、参考情報としても分割の必要性は低いと判断した。

## spec retrospective

### Minor observations

- `/issue` フェーズが補完チェックとして追加した `section_contains` の heading 引数に `####` プレフィックスが含まれており、`modules/verify-executor.md` の heading 部分一致規則 (先頭の `#` と空白を除去してから部分一致) の下では恒久 UNCERTAIN になる形だった。同一セッション内の Triage AC audit が検出し、本フェーズで修正した。`section_contains` の補完チェックを新規に書く際は、見出しレベル記号を引数に含めないことを毎回確認する必要がある。
- `docs/structure.md` のスクリプト件数コメント `(92 files)` は `find scripts -maxdepth 1 -type f | wc -l` (= 92) と一致するが、`ls scripts/ | wc -l` (= 93) とは一致しない。`scripts/git-hooks/` サブディレクトリが `ls` では 1 件として数えられるため。件数更新時は必ず `-maxdepth 1 -type f` の値を使う。

### Judgment rationale

- Issue 本文の「stop-at 判定箇所が合計 8 箇所」は SKILL.md の LLM prose のみの数であり、共通ヘルパー (bash script) の実際の置換対象である `scripts/run-auto-sub.sh` の bash 条件式 6 箇所を含んでいなかった。両者は実行サーフェスが異なる (prose は LLM 実行、bash は subprocess) ため単純合算できない。AC 4 の rubric が `tests/run-auto-sub.bats` を名指ししていたこと、共通ヘルパー化トリガーの系譜 (#980 / #1042) がいずれも `run-auto-sub.sh` であったことを根拠に、置換対象を bash 側 6 箇所に確定した。
- Count mode の gate をリテラル比較 (`AUTO_STOP_AT == "merge"`) に留め、helper の phase 順序判定に広げなかった。本 Issue の目的が両モードの挙動統一である以上、Count mode だけ広い gate を持たせると新たな非対称を作ることになるため。List mode 側の gate 拡張は独立した判断であり、必要なら別 Issue とする。
- Count mode は `write_batch` を一度も呼ばないため、List mode step 7 から `auto-checkpoint.sh update_batch` 呼び出しを除いた形で移植した。将来の読者が List mode との対称性から checkpoint 呼び出しを「復元」しないよう、その旨の注記を追加ブロック内に置く仕様とした。
- helper の exit code 規約 (0=stop / 1=continue / 2=usage error) は、同じ `scripts/run-auto-sub.sh` 内の既存 predicate `_spec_is_diffless()` と同一の 0/1 規約に揃えた。stdout に判定語を出す案は、呼び出し元 (`if` 条件) の記述が `grep -q` 経由になり読みにくくなるため採らなかった。

### Uncertainty resolution

- `section_contains` の heading 引数照合規則: `modules/verify-executor.md` の翻訳表を読んで解決 (先頭 `#` 除去後の部分一致)。Issue 本文の AC と Spec の両方を修正済み。
- `set -euo pipefail` 下で helper の exit 1 が script を止めないか: `if <command>; then` の条件位置は `set -e` の対象外であること、および同ファイル内の `_spec_is_diffless()` が同じ規約で使われていることを確認して解決。
- `tests/run-auto-sub.bats` の `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` により新規 helper が mock ディレクトリ側に解決される点: `setup()` を読んで確認し、`get-config-value.sh` と同じ「実物を copy」方式を Implementation Steps 5 に明記して解決。

### 新規テストケース要件のサマリ

- Implementation Steps 1 (helper の 5 分岐) と 3 (Count mode step 6 の 3 分岐) がいずれも新規分岐ロジックのため、`tests/should-stop-at-phase.bats` に 12 ケース、`tests/auto-batch.bats` の Count mode section に 5 ケースの新規テストを追加したうえでスイート全体が PASS することを受入基準 6 に要求した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の Implementation Steps 1-9 を記載順にそのまま実装した。逸脱なし。
- 受入基準 6 の verify command が直列実行で 60 秒 timeout を超過することを Step 10 で検出し、`--jobs $(nproc || sysctl -n hw.logicalcpu)` を追加する形で Issue 本文と Spec の両方を修正した (詳細は Code Retrospective 参照)。
- Phase Handoff (spec) の Deferred Items のうち `modules/detect-config-markers.md` の fallback 文言整合性を確認し、変更不要と確定した。

### Deferred Items

- `skills/auto/SKILL.md` の `EFFECTIVE_STOP_AT` prose 判定 8 箇所の共通化は本 Issue のスコープ外 (spec phase から引き継ぎ、未着手のまま)。将来 stop-at 値を追加する際に再評価する。
- List mode step 7 の gate を phase 順序判定へ広げる案は本 Issue の対象外 (spec phase から引き継ぎ、Issue 本文で明示)。必要なら別 Issue とする。

### Notes for Next Phase

- 受入基準 6 の verify command は `--jobs` 付きの並列形に修正済み (実測 37 秒、60 秒 timeout 内)。`/review`/`/verify` で再確認する際は修正後の Issue 本文記載のコマンドを使うこと。
- full suite (`bats --jobs 18 tests/`) は 1939 件全て PASS。`should-stop-at-phase.bats` 12 件、`auto-batch.bats` の Count mode 5 件を含む。
- `docs/structure.md`/`docs/ja/structure.md`/`docs/workflow.md`/`docs/ja/workflow.md` は本フェーズで更新済み。`docs/guide/xl-decomposition.md` の翻訳同期ギャップ (`docs/ja/guide/xl-decomposition.md` 未更新) は本 Issue と無関係の既存差分のため未対応。

## Code Retrospective

### Deviations from Design

- N/A。Implementation Steps 1-9 は Spec の仕様通りに実装した (helper 分岐仕様、run-auto-sub.sh 置換対応表、Count mode 追加ブロック仕様、新規テストケース一覧のいずれも記載通り)。

### Design Gaps/Ambiguities

- 受入基準 6 の verify command (`command "bats tests/should-stop-at-phase.bats tests/run-auto-sub.bats tests/auto-batch.bats"`) は直列実行で実測 65 秒かかり、`command` verify type の 60 秒 timeout を超過することを Step 10 で発見した (`modules/verify-executor.md` の Timeout Coverage Audit が明記する「`command` は full suite 実行に不向き」と同型の事例)。`--jobs $(nproc || sysctl -n hw.logicalcpu)` を追加した並列形なら実測 37 秒で収まることを確認し、Issue 本文と Spec の両方の verify command を修正した (Step 10 miscalibrated hint 扱い)。Spec 記述時点では対象テストファイルが 3 件・合計テスト数が確定していなかったため、この所要時間は実装完了まで具体的に見積もれなかった。

### Rework

- N/A。

### Deferred Items 引き継ぎの解決

- Phase Handoff (spec) の Deferred Items 3 件目「`modules/detect-config-markers.md` の fallback 文言が現状と整合しているか `/code` で最終判断」: 整合を確認した。`detect-config-markers.md` は `auto-stop-at` の fallback を `"verify"` (フルパイプライン) と明記しており、`scripts/should-stop-at-phase.sh` の fallback 実装 (未知値・取得失敗いずれも `verify` 相当の順序 5 にフォールバック) と一致する。記述変更は不要と確定した。
