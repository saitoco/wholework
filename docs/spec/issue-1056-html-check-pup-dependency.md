# Issue #1056: verify: html_check の pup 依存を緩和し同名別ツールによる誤判定を防ぐ

## Overview

`modules/verify-executor.md` の `html_check` verify command (full mode) は、CSS セレクタ判定を外部バイナリ `pup` (ericchiang/pup) に依存している。存在チェックが `which pup` の成否のみであるため、Homebrew core の同名別ツール (Datadog API CLI) を誤って認識し、構造的に UNCERTAIN / false PASS / false FAIL を生む。本 Issue では `pup` への依存を撤廃し、Python 標準ライブラリ (`html.parser`) による内製 CSS セレクタ判定に置き換える (Issue 本文の検討候補 B 相当。ダウンストリームプロジェクトで実運用検証済み)。

## Reproduction Steps

1. `brew install pup` を実行する (Homebrew core の `pup` formula は ericchiang/pup ではなく Datadog API CLI `pup 1.9.1` を指す)
2. `html_check` を含む verify command を full mode (`/verify`) で実行する
3. `which pup` が成功するため、未インストール時の UNCERTAIN 判定をすり抜ける
4. `curl ... | pup "selector"` は実行されるが、Datadog CLI は CSS セレクタ構文を解釈できず空出力または `error: unrecognized subcommand` を返す。`--exists` 判定は空出力を FAIL とみなすため false FAIL となる。検証コード側で `2>&1` によりエラー出力を巻き込むと非空になり false PASS にもなり得る (実際に発生)

## Root Cause

`modules/verify-executor.md` の `html_check` full mode 処理 (L74) が `which pup` の終了コードのみで「ericchiang/pup が使用可能」と判断している。Homebrew core の `pup` formula は無関係な別ツール (Datadog API CLI) であるため `which pup` は成功するが、CSS セレクタ判定機能を持たない。加えて本来の ericchiang/pup は 2019 年以降未更新で Homebrew に存在せず、Go toolchain でのソースビルドが必要なため正しい導入自体が困難な環境が多い。結果として `html_check` を含む Acceptance Criteria が環境依存で恒久的に UNCERTAIN 化する (`pup` の出現箇所: repo 全体で 2 件、いずれも `modules/verify-executor.md` 内 — L74 テーブル行と L266 差別化説明。スコープ: repo 全体の `.md`/`.sh`/`.py` ファイル、`.git/` 除く、`grep -rn '\bpup\b' . --include="*.md" --include="*.sh" --include="*.py"` で確認)。

## Changed Files

- `scripts/html-selector-match.py`: 新規ファイル — Python 標準ライブラリのみで CSS セレクタ判定を行うスクリプト (外部バイナリ非依存)
- `modules/verify-executor.md`: change — `html_check` の翻訳テーブル行 (L74) と「Differentiation Between ... と `command`」節の `html_check` 説明 (L266) を、`pup` 依存の記述から `scripts/html-selector-match.py` 呼び出しの記述に変更
- `tests/html-selector-match.bats`: 新規ファイル — `scripts/html-selector-match.py` の bats テスト (`tests/validate-skill-syntax.bats` の構成に準拠)
- `tests/verify-executor.bats`: change — `html_check` の新実装を保証する assertion を追加 (CI レベルの回帰ガード)
- `docs/structure.md`: change — Directory Layout の `scripts/` ファイル数コメントを `(66 files)` → `(68 files)` に更新 (SHOULD レベル。既存実ファイル数 67 との 1 件ズレ [本 Issue と無関係な既存 drift] の修正も含めた最終値)
- `docs/ja/structure.md`: change — 上記の日本語ミラー (`66 ファイル` → `68 ファイル`) を同期 (`docs/translation-workflow.md` Sync Procedure 準拠。`docs/spec/` 配下ではないため sync 対象)

## Implementation Steps

1. `scripts/html-selector-match.py` を新規作成する (`#!/usr/bin/env python3`、標準ライブラリのみ、サードパーティ import 禁止)。stdin から HTML を読み込み、CLI 引数 1 個 (CSS セレクタ文字列) を受け取り、マッチした要素数を標準出力に出力する。
   - **セレクタ文法**: 先頭の tag 名 (省略可、`^[a-zA-Z][\w-]*`、省略時は任意タグ) + `#id` (省略可、`id` 属性の完全一致) + `.class` (0 個以上、AND 一致、要素の `class` 属性を空白分割した集合に対する部分集合判定) + `[attr]` / `[attr='value']` / `[attr="value"]` (0 個以上、AND 一致、属性の存在 or 属性値の完全一致)。子孫結合子・隣接結合子・疑似クラスは非対応 (Issue 本文の検討候補 B の想定スコープに準拠)。
   - **マッチング実装**: `html.parser.HTMLParser` を継承し `handle_starttag` をオーバーライドする (`handle_starttag` は自己終了/void 要素でも呼び出されるため `<input>` 等も判定可能)。開始タグを 1 つずつ解析済みセレクタと照合し、一致するたびにカウンタを加算する。
   - **エラー時の挙動**: セレクタのパースに失敗した場合 (未対応の構文・不正なセレクタ) は、**stdout に何も出力せず、stderr にエラー内容を出力して exit code 2 で終了する**。Python の traceback をそのまま送出することはしない (verify-executor 側の判定が traceback で壊れないようにするため)。stdin が空の場合は正常な「マッチ 0 件」として exit code 0 + `0` を出力する。
     - この分岐により「セレクタの書き方が誤っている」ケースと「本当に要素が存在しない」ケースが verify-executor 側で区別可能になる。前者を `0` (= FAIL) に倒すと、本 Issue が解消しようとしている false FAIL を別の形で作り込むことになるため、非 0 exit → UNCERTAIN に倒す設計を採る。
   (→ Pre-merge AC1, AC2)

2. (after 1) `modules/verify-executor.md` の `html_check` 翻訳テーブル行 (`html_check "URL" "selector" "--exists"` で始まる行, L74) の full mode 処理を変更する。「first check `which pup` (UNCERTAIN if not installed). If pup exists, run `curl -s --connect-timeout 5 --max-time 10 "URL" \| pup "selector"`」の記述を、「run `curl -s --connect-timeout 5 --max-time 10 "URL" \| python3 ${CLAUDE_PLUGIN_ROOT}/scripts/html-selector-match.py "selector"`」に置き換える。判定は次の 2 段階で記述する: (a) スクリプトの exit code が非 0 の場合は **UNCERTAIN** (セレクタ構文が不正で判定不能。stderr の内容を判定理由として付記する)、(b) exit code 0 の場合は標準出力 (マッチ数) を用いて `--exists` は「0 より大きいか」、`--count=N` は「N と一致するか」で判定する。safe mode の URL セキュリティチェック (`browser-verify-security.md` 参照) と `--allow-localhost` の扱いは変更しない。
   (→ Pre-merge AC1, AC2, AC3)

3. (after 2) `modules/verify-executor.md` の「### Differentiation Between `http_status` / `html_check` / `api_check` / `build_success` / `github_check` と `command`」節にある `html_check` の説明箇条書き (L266 付近) を更新する。「curl + pup with CSS selector evaluation... UNCERTAIN if `pup` is not installed」という記述を、curl + 内製 Python セレクタ判定 (`scripts/html-selector-match.py`、外部バイナリ非依存、外部ツール未インストール起因の UNCERTAIN 分岐なし) の説明に置き換える。あわせて、UNCERTAIN が残るのはセレクタ構文が不正な場合 (スクリプトが非 0 exit を返す場合) のみである旨を明記する。
   (→ Pre-merge AC1)

4. (parallel with 2, 3) テストを追加する。
   - `tests/html-selector-match.bats` を新規作成し、`tests/validate-skill-syntax.bats` と同様に `scripts/html-selector-match.py` を `run` ヘルパーで直接サブプロセス実行する構成にする。カバーするケース: (a) 単純な tag セレクタ、(b) `.class` セレクタ、(c) `[attr='value']` セレクタ、(d) ダウンストリーム実事例に近い `tag.class[attr='value']` の複合セレクタ (例: `<form class="kf-form" data-testid="signup">` を含む HTML フィクスチャ)、(e) マッチ数 0 になるセレクタ (exit code 0 かつ出力 `0`)、(f) 不正なセレクタ構文で exit code が非 0 になり stdout が空であること (「マッチ 0 件」との区別が成立していることの確認)、(g) 空の stdin で exit code 0 かつ出力 `0` になること。
   - `tests/verify-executor.bats` に assertion を 2 件追加する: `grep -q "html-selector-match.py" modules/verify-executor.md` (新実装が組み込まれていることの確認) と、`which pup` / `If pup exists, run` に相当する記述が存在しないことを確認する assertion (AC3 と同じ意図を CI レベルでも保証する回帰ガード)。
   (→ Pre-merge AC1, AC2)

5. (parallel with 1-4, SHOULD レベル) `docs/structure.md` の Directory Layout コメント `scripts/ ... (66 files)` を `(68 files)` に更新し (新規ファイル追加分 +1、および本 Issue と無関係な既存 1 件ズレの修正分 +1)、`docs/ja/structure.md` の対応する日本語ミラー (`66 ファイル` → `68 ファイル`) も同期する。

## Verification

### Pre-merge

- <!-- verify: rubric "html_check が ericchiang/pup 単独への依存を脱し、代替手段 (htmlq 許容 / 内製セレクタ判定 / 同等の方式) で CSS セレクタ判定を実行できるようになっている" --> `html_check` が単一の未メンテナンス外部バイナリに依存しなくなっている
- <!-- verify: rubric "pup という名前のバイナリが存在しても期待する HTML パーサでない場合に false PASS / false FAIL を返さない設計になっている" --> 同名別ツールによる誤判定を防ぐ仕組みがある
- <!-- verify: file_not_contains "modules/verify-executor.md" "If pup exists, run" --> `modules/verify-executor.md` の `html_check` 実装が `which pup` の成否のみで実行可否を決める記述から更新されている

### Post-merge

- 実装者が `pup` 未インストールの環境 (CI やクリーンな sandbox 等) で `html_check` を含む AC を実行し、UNCERTAIN ではなく PASS/FAIL が返ることを確認する

## Notes

- **設計判断 (Option B 採用)**: Issue 本文の検討候補 A (`htmlq` 許容) / B (内製セレクタ判定) / C (検出厳密化のみ) のうち、B を採用した。理由: (1) AC1 (単一外部バイナリ依存の脱却) と AC2 (同名別ツールによる誤判定防止) を同時に、かつ構造的に満たすのは B のみ — A は `htmlq` という別の外部バイナリへ依存が移るだけで「単一の未メンテナンス外部バイナリ」問題の形を変えているに過ぎず、`pup` の名前衝突対策も別途必要になる。C は誤判定は防げても UNCERTAIN 自体は解消しない (AC1 を満たさない)。(2) Issue 本文で B 相当の実装がダウンストリームで実運用検証済みと報告されている。(3) Python3 は本プロジェクトの既存必須依存 (`docs/tech.md` — `scripts/validate-skill-syntax.py` が使用) であり、新規の環境要件を追加しない。代替案の採否自体は `docs/product.md` § `/issue` (What) vs `/spec` (How) Responsibility Boundary に基づき `/spec` の責務として判断した。
- **設計判断 (パース失敗時は UNCERTAIN)**: 初版の Spec ではセレクタのパース失敗時も `0` を出力する (= `--exists` では FAIL) 設計としていたが、ユーザー確認により **非 0 exit → UNCERTAIN** に変更した。理由: パース失敗を `0` に丸めると「セレクタの書き方が誤っている」と「本当に要素が存在しない」が判別できず、本 Issue が解消対象としている false FAIL を別の形で作り込むことになるため。traceback をそのまま出さない (判定を壊さない) という初版の意図は、stderr へのエラーメッセージ出力 + 固定 exit code 2 で維持する。なお **stdin が空の場合は従来どおり `0` (マッチなし、exit 0)** とし、UNCERTAIN には倒さない — 空レスポンスの原因切り分け (curl 失敗 vs 実際に空の HTML) は curl 側の exit code の責務であり、本スクリプトのスコープ外と判断した。
- **セレクタ対応範囲**: `tag` / `.class` (複数可、AND) / `#id` / `[attr]` / `[attr='value']` の単純セレクタ (compound selector) のみサポートし、子孫結合子・疑似クラス等は非対応。Issue 本文の検討候補 B の記述 (「複雑なセレクタは非対応でよい。実用上は `tag.class[attr]` / `[attr='val']` で足りる」) に準拠。
- **bats テストの入力形式**: `tests/html-selector-match.bats` は `scripts/html-selector-match.py` を `run` ヘルパーでサブプロセス実行し、HTML フィクスチャを heredoc または `<<<` で標準入力に渡し、`$output` (印字されたマッチ数の文字列) を期待値と比較する形式とする。他スクリプトの `WHOLEWORK_SCRIPT_DIR` モック機構は使用しない — `html-selector-match.py` は他スクリプトから `SCRIPT_DIR` 経由で呼ばれる兄弟スクリプトではなく、`verify-executor.md` 自身の Bash 実行から直接呼ばれるスクリプトのため (`WHOLEWORK_SCRIPT_DIR` をモックしている既存 bats テスト 28 ファイルを確認したが、いずれも `run-*.sh` 系オーケストレーションスクリプトのモックであり、本スクリプトを `SCRIPT_DIR` 経由で呼び出すものは存在しないことを確認済み)。
- **`docs/structure.md`/`docs/ja/structure.md` の同期を Pre-merge Verification に含めない理由**: Verify command sync rule (Issue 本文の Pre-merge Acceptance Criteria との件数一致を優先) に従い、Changed Files と Implementation Steps には記載するが Pre-merge Verification の追加項目としては数えない (Issue #930 の precedent と同じ扱い)。
- **他ファイルへの影響なし (確認済み)**: `grep -rn '\bpup\b' . --include="*.md" --include="*.sh" --include="*.py"` (`.git/` 除く) で `pup` の出現箇所は repo 全体で 2 件、いずれも `modules/verify-executor.md` 内 (L74, L266) のみと確認した。`html_check` の CLI 引数構文を参照する他ファイル (`skills/issue/SKILL.md`, `modules/verify-patterns.md`, `docs/environment-adaptation.md`, `docs/guide/customization.md`) はいずれも `pup` に言及しておらず、引数構文自体は変更しないため更新不要と判断した (grep で確認済み)。新規ファイル `scripts/html-selector-match.py` を参照する既存ファイルも存在しない (`grep -rn "html-selector-match" docs/ tests/ scripts/` で 0 件、新規ファイルのため妥当)。
- **allowed-tools 変更不要 (確認済み)**: `html_check` の full mode 実行は現状も `curl`/`pup` が `/verify` の `allowed-tools` に明示エントリなしで動作しており (既存の許可特性)、`curl`/`python3` への置き換えで許可要件が悪化するわけではない。`/review` の `allowed-tools` には `python3:*` が既に含まれている。
- **Issue 本文と実装の整合性チェック**: Issue 本文が主張する現行実装 (`which pup` による存在チェックのみ、`curl | pup` の実行) は `modules/verify-executor.md` L74 の記述と完全に一致することを確認した。矛盾なし。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective コメント。AC3 の verify command を `grep "html_check" ...` から `file_not_contains ... "If pup exists, run"` に変更した理由 (main 時点で `html_check` という文字列自体は 5 箇所存在し常時 PASS するパターンだったため) と、代替案 A/B/C の選定が `/spec` の責務である旨を確認。post-merge AC の主語明示についても言及。 (https://github.com/saitoco/wholework/issues/1056#issuecomment-5111434384)

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 を Spec の記述どおりの順序・内容で実装した。

### Design Gaps/Ambiguities

N/A — セレクタ文法・マッチング実装・エラー時挙動 (非 0 exit → UNCERTAIN、空 stdin → 0 件扱い) が Spec に具体的に規定されていたため、実装判断で迷う箇所はなかった。

### Rework

N/A — 手戻りは発生しなかった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1〜5 をそのままの順序で実装。`scripts/html-selector-match.py` は Option B (内製 Python パース) として `html.parser.HTMLParser` の `handle_starttag` オーバーライドで実装し、compound selector (`tag`/`#id`/`.class`/`[attr]`/`[attr='value']`) をサポート。
- セレクタパース中の正規表現マッチは `pos` オフセット付き `.match(selector, pos)` を使用し、パターン先頭の `^` アンカーは意図的に外した (`^` は絶対文字列先頭のみを指し `pos` 相対にならないため、含めると 2 トークン目以降が常にマッチ失敗する)。
- `modules/verify-executor.md` の `html_check` (L74 翻訳テーブル行 + L266 Differentiation 節) を pup 依存の記述から `html-selector-match.py` 呼び出しに置換。判定は script exit code 非 0 → UNCERTAIN、0 → 出力マッチ数で `--exists`/`--count=N` 判定という 2 段階を明記。

### Deferred Items
- Post-merge AC (「実装者が `pup` 未インストールの環境で `html_check` を含む AC を実行し PASS/FAIL が返ることを確認する」) は manual verify-type のため merge 後に別途実施が必要。
- None

### Notes for Next Phase
- Behavioral Change Detection により `modules/verify-executor.md` を参照する既存テスト (`tests/verify-rubric.bats`, `tests/review-rubric-safe.bats`, `tests/check-eager-load-capability.bats`) が検出されたため、`bats tests/` フルスイートを実行済み (1246 件 PASS、FAIL 0)。/review でも同様の full suite 実行が妥当。
- Pre-merge AC 3 件 (rubric x2, file_not_contains x1) は自己評価で PASS 済み・Issue チェックボックス反映済み。/review での再検証時も同じ判定になるはず (実装内容に変更なし)。
