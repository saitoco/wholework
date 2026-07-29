# Issue #1069: verify: html_check で CSS combinator (隣接兄弟・子・子孫) を扱えるように

## Overview

`html_check` verify command が依存する `scripts/html-selector-match.py` は、compound selector (tag / `#id` / `.class` / `[attr]` / `[attr='value']`) の単一要素照合しかできず、combinator (子孫の半角スペース / 子 `>` / 隣接兄弟 `+` / 一般兄弟 `~`) を解釈できない。このため DOM の順序・階層関係を受け入れ条件にした AC が書けず、combinator を含むセレクタを渡すと `selector parse error` で exit 2 → UNCERTAIN 確定となる。

本 Issue では **案 A (内製実装の拡張)** を採用し、`scripts/html-selector-match.py` を「start tag を逐次照合する」設計から「要素ツリーを構築して combinator チェーンを照合する」設計に変更する。外部バイナリ依存はゼロのまま維持し、CLI 契約 (引数 1 個 / stdin から HTML / stdout にマッチ数 / 解析失敗時 exit 2) と `modules/verify-executor.md` の 2 段階判定ロジックは変更しない。

案 B (htmlq 委譲 + 内製フォールバック) を採らない理由は「Alternatives Considered」に記載する。`/spec` フェーズで htmlq 0.4.0 を実機検証した結果 (`--count=N` を表現できない・exit code 意味論が非互換) が判断の主根拠。

## Changed Files

- `scripts/html-selector-match.py`: change — combinator 対応 (セレクタ分割 + 要素ツリー構築 + チェーン照合)。Python 3 標準ライブラリのみ (`re` / `sys` / `html.parser`)、サードパーティ import 禁止 (#1056 の制約を維持)。CLI 契約は不変
- `modules/verify-executor.md`: change — `html_check` 翻訳テーブル行と「Differentiation Between `http_status` / `html_check` / ... と `command`」節の `html_check` 説明に、combinator サポート・採用方式 (内製拡張、外部バイナリ不要)・既知の制約を追記
- `tests/html-selector-match.bats`: change — combinator テストケースを追加 (既存 7 ケースは維持)
- `tests/verify-executor.bats`: change — `combinator` 記述の回帰ガード assertion を 1 件追加
- `skills/issue/SKILL.md`: change — verify command テーブルの `html_check` 行に combinator 対応を 1 文追記 [Steering Docs sync candidate]

**変更不要と判断したファイル (いずれも grep / 実測で確認済み):**

- `scripts/validate-skill-syntax.py`: `_parse_verify_args()` を実際に import して実測し、`html_check "URL" "input[name='last_name'] + input[name='first_name']" "--exists"` が引数 3 個 (`KNOWN_VERIFY_COMMAND_TYPES['html_check'] = (3, 3)` と一致) に分解されることを確認した。二重引用符で囲まれたセレクタ内の空白・`>` `+` `~` は引数区切りとして扱われないため、arg count 定義もパーサも変更不要
- `docs/structure.md`: 新規ファイルの追加・削除がないため `modules/` (41 files) / `scripts/` (68 files) / `tests/` (95 files) のファイル数記述は不変。Key Files の Scripts 節にも `html-selector-match.py` の項目は存在しない (`grep -rn "html-selector-match" docs/` で 0 件)
- `docs/environment-adaptation.md` / `docs/ja/environment-adaptation.md`: `html_check` 行 (Command-by-Environment Table) は safe/full モードの実行可否のみを記述しており、セレクタ文法に言及していない
- `docs/guide/customization.md` / `docs/ja/guide/customization.md`: `html_check` は pre-merge-preview tier の verify command 集合の一員として列挙されるのみで、セレクタ文法に言及していない
- `modules/verify-patterns.md`: L391 は manual→auto 置換のクイックリファレンス表で `html_check` をコマンド型として挙げるのみ。combinator ガイダンスをここに追記すると eager-load コスト (`docs/environment-adaptation.md` の Eager-load vs Lazy-load 分類表で ~1500 tokens/section と明記) が全プロジェクトに波及するため、記述先は `modules/verify-executor.md` の既存行 (~30 tokens/row) に限定する

## Implementation Steps

1. `scripts/html-selector-match.py` のセレクタ解析を combinator 対応に拡張する (→ 受入条件 AC1, AC2)
   - 既存 `parse_selector()` の本体をそのまま `parse_compound()` にリネームする。compound 文法 (tag / `#id` / `.class` / `[attr]` / `[attr='value']`) と既存の正規表現 (`TAG_RE` / `ID_RE` / `CLASS_RE` / `ATTR_RE`) は変更しない
   - 新規 `split_selector(selector)` を追加する。セレクタ文字列を `[(combinator, compound_text), ...]` の順序付きリストに分割し、先頭要素の combinator は `None`、以降は `'>'` / `'+'` / `'~'` / `' '` (子孫) のいずれかとする。`[` `]` の入れ子深さと引用符状態 (`'` / `"`) を追跡し、**角括弧内・引用符内の空白と `>` `+` `~` は combinator として扱わない** (例: `div[data-x='a b'] > span` は 2 compound に分割される)
   - `parse_selector()` は `[(combinator, compound_dict), ...]` を返すよう変更する
   - `ValueError` を送出する不正入力 (exhaustive): 空セレクタ / 先頭が combinator (`> div`) / 末尾が combinator (`div >`) / 連続 combinator (`div>>bad`) / `[` `]` の不均衡 / 引用符の未終端

2. (after 1) 要素ツリーを構築するパーサに置き換える (→ 受入条件 AC1)
   - `SelectorMatcher(HTMLParser)` を `TreeBuilder(HTMLParser)` に置き換える。`Node` クラス (`__slots__`: `tag` / `attr_dict` / `class_set` / `id_value` / `parent` / `children` / `sibling_index`) を導入し、`#document` を根とする木を構築する
   - `handle_starttag`: `Node` を生成して親の `children` に追加し、文書順リスト `self.nodes` にも追加する。**void element** (`area` `base` `br` `col` `embed` `hr` `img` `input` `link` `meta` `param` `source` `track` `wbr` — exhaustive) の場合は開き要素スタックに push しない (`html.parser` は void element に対して `handle_endtag` を呼ばないため、push するとスタックが閉じられず以降の階層判定がすべて崩れる)
   - `handle_startendtag`: 生成・追加のみ行い push しない
   - `handle_endtag`: スタックを末尾から走査して同名タグを探し、見つかった位置以降を切り詰める。見つからない場合 (孤立した終了タグ) は無視して処理を継続する
   - `sibling_index` は `Node` 生成時に `len(parent.children)` を代入する。前方兄弟参照を O(1) にして、兄弟数の多い文書で `~` 照合が O(n^2) になるのを防ぐ (`list.index()` による線形走査は使わない)

3. (after 2) combinator チェーン照合を実装する (→ 受入条件 AC1)
   - `matches_compound(node, compound)`: 既存 `handle_starttag` 内の照合条件 (tag は小文字比較 / `id` 完全一致 / `class` は部分集合 / 属性は存在チェック + 値一致) をそのまま関数として切り出す
   - `matches_chain(node, chain)`: `chain` 末尾の compound を `node` に照合し、一致したら直前の combinator に応じて残りを再帰照合する (分岐は exhaustive)
     - `'>'`: `node.parent` が `#document` 以外なら親に対して残りを照合し、その結果を返す
     - `' '`: `node.parent` から `#document` の手前まで祖先を遡り、いずれかが残りに一致すれば真、最後まで一致しなければ偽
     - `'+'`: 直前の兄弟要素 1 個のみに対して残りを照合する。直前の兄弟が存在しなければ偽
     - `'~'`: 直前の兄弟要素を先頭方向へ順に辿り、いずれかが残りに一致すれば真、先頭まで一致しなければ偽
   - マッチ数は `self.nodes` (文書順) を走査して `matches_chain` が真になる要素を数える。`--exists` / `--count=N` の意味論 (`verify-executor` 側の判定) は変更しない

4. (after 3) CLI 契約が不変であることを保証し、docstring を更新する (→ 受入条件 AC1, AC2)
   - 引数 1 個 (CSS セレクタ) / stdin から HTML / stdout にマッチ数 / セレクタ解析失敗時は stderr にメッセージ + exit 2 / 空 stdin は `0` を出力して exit 0 — いずれも現行どおり維持する
   - モジュール docstring に、対応する combinator 4 種と**既知の制約**を記載する。制約: HTML5 の implied end tag 規則 (`<p>` の自動クローズ等) は解釈せず、明示的な終了タグのみで入れ子を決定する。したがって `<div><p>a<p>b</div>` に対する `div > p` はブラウザ準拠の 2 ではなく 1 を返す
   - サードパーティ import を追加しない (`re` / `sys` / `html.parser` のみ)

5. (parallel with 2, 3) `modules/verify-executor.md` を更新する (→ 受入条件 AC2, AC3, AC4)
   - `html_check "URL" "selector" "--exists"` で始まる翻訳テーブル行に、**`combinator` という語を含む形で**「compound selector に加えて combinator (子孫の半角スペース / 子 `>` / 隣接兄弟 `+` / 一般兄弟 `~`) を解釈する」旨を追記する
   - 「### Differentiation Between `http_status` / `html_check` / `api_check` / `build_success` / `github_check` and `command`」節の `html_check` 箇条書きに、以下 3 点を明記する
     - 採用方式は**内製実装 (`scripts/html-selector-match.py`) の拡張であり、外部バイナリを一切必要としない**。したがって「外部ツール未インストール時の UNCERTAIN + 導入案内」という分岐は存在しない
     - UNCERTAIN が残るのはセレクタ構文を解析できない場合 (スクリプトが exit 2 を返す場合) のみ
     - 既知の制約として、入れ子は明示的な終了タグのみで決定し implied end tag 規則は解釈しない旨を 1 文添える
   - 判定ロジック (exit code 非 0 → UNCERTAIN、exit 0 → マッチ数で `--exists` / `--count=N` を判定) は変更しない。既存の記述をそのまま残す

6. (after 4) `tests/html-selector-match.bats` に combinator テストケースを追加する (→ 受入条件 AC5, AC6)
   - 既存 7 ケースは削除・改変しない (後方互換の回帰ガード)
   - 追加ケース (exhaustive): (a) 隣接兄弟 `+` が void element (`<input>`) 間で正順にマッチする / (b) 同じ隣接兄弟セレクタを逆順にすると 0 件になる (DOM 順序判定が成立していることの確認) / (c) 子 `>` が直接の子のみに一致し孫には一致しない / (d) 子孫 (半角スペース) が孫にも一致する / (e) 一般兄弟 `~` が後続の全兄弟に一致し、逆向きには一致しない / (f) 引用符内に空白を含む属性値と combinator の併用 (`div[data-x='a b'] > span`) が 1 件に一致する / (g) 不正な combinator セレクタ (`> div` / `div >` / `div>>bad`) が exit 2 かつ stdout 空になる / (h) 孤立した終了タグを含む不正な入れ子でも例外を送出せず数え上げが完了する
   - 追加する `@test` 名には `combinator` の語を含める (AC5 の `grep "combinator" "tests/html-selector-match.bats"` を満たすため)
   - 入力形式は既存ケースに合わせる: `run bash -c "printf '<html>' | python3 '$REAL_SCRIPT' 'selector'"` の形で HTML を stdin に渡し、`$status` と `$output` (印字されたマッチ数の文字列) を比較する。`WHOLEWORK_SCRIPT_DIR` モック機構は使用しない (#1056 Spec の判断を踏襲)

7. (after 5) `tests/verify-executor.bats` に回帰ガードを 1 件追加する (→ 受入条件 AC4, AC6)
   - `@test "verify-executor: html_check documents combinator support"` を追加し、`grep -q "combinator" "$VERIFY_EXECUTOR"` を assertion とする
   - 既存 2 件 (`html_check uses html-selector-match.py` / `html_check no longer gates on which pup`) は維持する

8. (parallel with 5) `skills/issue/SKILL.md` の verify command テーブルの `html_check` 行を更新する (→ 受入条件 AC1)
   - 「HTML structure verification using CSS selectors.」に続けて、combinator (子孫の半角スペース / `>` / `+` / `~`) が使えるため DOM の順序・階層を検証する AC を書ける旨を 1 文追記する
   - SKILL.md 本文なので半角 `!` を使わない (`validate-skill-syntax.py` の MUST 制約)

## Alternatives Considered

### 案 B: htmlq 委譲 + 内製実装フォールバック (不採用)

Issue 本文および `/issue` フェーズの Auto-Resolve Log が推奨していた案。`/spec` フェーズで htmlq 0.4.0 (`/opt/homebrew/bin/htmlq`) を実機検証したうえで不採用とした。不採用理由は以下 4 点。

1. **`--count=N` を表現できない (機能後退)** — htmlq に件数出力オプションは存在しない (`htmlq --help` で確認)。Issue 本文が代替案として挙げた「`--attribute` 指定時の出力行数で代用」も成立しない。実測では (a) 単一マッチでも要素が複数行にまたがると 4 行出力される (`form div.row` で 1 マッチ / 4 行)、(b) `--attribute name` を指定した要素がその属性を持たない場合は空行ではなく**出力そのものが 0 バイト**になる (`form p --attribute name` で確認)。つまり行数は件数の代理指標として機能しない。combinator を含む AC で `--count=N` が使えなくなるのは、compound selector で既に提供している機能の後退にあたる
2. **判定エンジンの二重化による非一貫性** — compound は Python、combinator は Rust (`scraper` / `selectors` クレート) という分岐は、同一文書・同一 compound 部分に対して属性照合や class 照合の微妙な差異が出うる。単一エンジンなら生じない不一致を構造的に持ち込む
3. **#1056 が解消した失敗モードの再導入** — 「外部バイナリ未インストール → 恒久的に UNCERTAIN」は #1056 の主題そのもの。combinator AC を書けるようにするのが本 Issue の目的なのに、その AC だけが環境依存で UNCERTAIN になるのでは目的を達しない。`docs/product.md` の「optional dependency はグレースフルにフォールバックする」方針も、ここでは**フォールバック先が存在しない** (compound selector では原理的に DOM 順序を判定できない) ため適用できない
4. **Adapter パターンの適用要件を満たさない** — `docs/environment-adaptation.md` § "Adapter Pattern Application Requirements" は「複数の実装選択肢を抽象化する必要がある場合にアダプタは価値を持つ」と定めている。CSS セレクタ判定の実装選択肢は内製 1 つ + htmlq 1 つで、`browser` (browser-use CLI vs Playwright MCP) のような選択肢の広がりがない。`mcp_call` がアダプタ層を持たない理由 (同 § "Why `mcp_call` Does Not Use an Adapter") と同じ論理が当てはまる

なお htmlq の exit code 意味論の非互換 (不正セレクタで exit **101** panic、マッチ 0 件と matched を exit code で区別できず stdout の空判定が必要) も実測で確認した。これは委譲層で吸収可能だが、上記 1 と 2 を打ち消すほどの利点は認められなかった。

### 案 C: htmlq を必須依存化 (不採用)

Issue 本文が既に非推奨としている。#1056 の目的 (外部バイナリを必須にしない) に正面から反するため検討を打ち切った。

### 内製拡張の実装コスト再評価

Issue 本文は案 A のコストとして「実装量の膨張、void element / 不正な入れ子 / `<template>` への耐性」を挙げていた。`/spec` フェーズでプロトタイプを実装し、以下を実測で確認した。

- 追加実装量は約 120 行 (現行 127 行 → 約 250 行)。すべて標準ライブラリで完結する
- void element は「開き要素スタックに push しない」という 1 箇所の判定で解決する。実測で `input[name='first_name'] + input[name='last_name']` = 1、逆順 = 0 を確認済み
- 不正な入れ子 (孤立した終了タグ `</i>`) は `handle_endtag` のスタック走査でスキップされ、例外なく処理が継続することを確認済み
- `<script>` / `<style>` の内容は `html.parser` が CDATA モードで扱うため、タグとして誤カウントされない (現行実装と同じ)
- 唯一の残存制約は implied end tag 非対応 (Uncertainty U1 参照)

## Verification

### Pre-merge

- <!-- verify: rubric "html_check が combinator (隣接兄弟 + / 子 > / 一般兄弟 ~ / 子孫の半角スペース) を含む CSS セレクタを解釈できるようになっている" --> `html_check` が combinator を含むセレクタを扱える
- <!-- verify: rubric "combinator 対応の実装方式 (内製拡張 / htmlq 委譲 / 併用) が決定され、外部バイナリが必要な場合は未インストール時の挙動 (UNCERTAIN + 導入案内) が定義されている" --> 実装方式と未インストール時の挙動が定義されている
- <!-- verify: rubric "modules/verify-executor.md の html_check 行が、採用した実装方式に合わせて更新されている (判定ロジック・exit code の扱いを含む)" --> `verify-executor.md` の記述が更新されている
- <!-- verify: grep "combinator" "modules/verify-executor.md" --> `verify-executor.md` が combinator に言及している
- <!-- verify: grep "combinator" "tests/html-selector-match.bats" --> `tests/html-selector-match.bats` に combinator 用のテストケースが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイート (combinator ケース含む) が CI で pass する

### Post-merge

- 隣接兄弟セレクタ (`a + b`) を含む AC を実際の URL に対して実行し、要素順序が期待どおりのときに PASS、逆順のときに FAIL することを確認する <!-- verify-type: manual -->
- 不正なセレクタを渡した際に UNCERTAIN として扱われ、エラー理由が記録されることを確認する <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

none (新規の Bash コマンドパターンは追加しない)

### Built-in Tools

none (既存の Read / Write / Edit / Bash / Grep / Glob で足りる)

### MCP Tools

none

## Uncertainty

- **[U1] implied end tag 規則の非対応**: `html.parser` は HTML5 の暗黙終了タグ規則 (例: `<p>` の直後に `<p>` が来ると前者が自動的に閉じる) を実装していないため、明示的な終了タグのない文書ではブラウザと入れ子解釈が食い違う
  - **検証方法**: プロトタイプ実測済み。`<div><p>unclosed<p>second</div>` に対し `div > p` は 1 を返す (ブラウザ準拠なら 2)
  - **影響範囲**: Implementation Steps 2, 4, 5
  - **対応 (解決済み)**: 仕様として受け入れ、docstring (Step 4) と `modules/verify-executor.md` (Step 5) に既知の制約として明記する。実務上の影響は限定的 — `html_check` の対象は主にフレームワークが生成した well-formed HTML であり、Issue 本文の動機ケース (`<input>` 兄弟の順序判定) は void element なので implied end tag と無関係

- **[U2] 兄弟数の多い文書での照合コスト**: `~` (一般兄弟) 照合で前方兄弟を辿る際、親の `children` リストを毎回 `list.index()` で線形走査すると全体が O(n^2) になる
  - **検証方法**: 実装設計上の静的分析
  - **影響範囲**: Implementation Steps 2, 3
  - **対応 (解決済み)**: `Node` に `sibling_index` を持たせて前方兄弟参照を O(1) にする (Step 2 に明記済み)

## Consumed Comments

- saito (MEMBER / first-class): `/issue 1069 --non-interactive` の Issue Retrospective。(1) Size L 判定の根拠 (`html-selector-match.py` のパーサ設計変更 + `verify-executor.md` 更新 + テスト追加)、(2) 案 B 推奨は `/issue` フェーズの暫定判断であり最終決定は `/spec` に委ねる旨、(3) AC は rubric ベースでどの実装方式でも検証可能な文言にしてあるため AC 自体は変更していない旨、(4) Pre-merge に bats テスト追加の `grep` 検証と CI 通過確認の 2 件を追加した経緯。本 Spec ではこれを受け、htmlq の実機検証を行ったうえで案 A を最終決定した (https://github.com/saitoco/wholework/issues/1069#issuecomment-5112370359)
- code phase (2026-07-29): No new comments since last phase (cutoff: most recent `phase/*` label assignment, 2026-07-29T03:29:33Z).

## Notes

### 実装方式の最終決定 (Auto-Resolve Log 参照)

`/issue` フェーズの Auto-Resolve Log は案 B を推奨していたが、`/spec` フェーズの実機検証を経て**案 A (内製拡張) を最終決定**とした。Issue 本文の「Auto-Resolved Ambiguity Points」も同内容に更新済み。根拠は「Alternatives Considered」を参照。

### AC2 の条件節について

AC2 の rubric 文言「**外部バイナリが必要な場合は**未インストール時の挙動 (UNCERTAIN + 導入案内) が定義されている」は条件節であり、案 A では前件が偽になるため空虚に真となる。ただし adversarial な grader が無条件要件と解釈するリスクがあるため、Implementation Step 5 で `modules/verify-executor.md` に「外部バイナリを一切必要としないため、未インストール時の分岐は存在しない」旨を**明示的に書く**ことで前件が偽であることを可読にする。

### rubric 文言中の `/` 記法について

AC1 / AC2 の rubric 文言には `/` 区切りが含まれるが、いずれも括弧内の列挙 (`(隣接兄弟 + / 子 > / 一般兄弟 ~ / 子孫の半角スペース)`、`(内製拡張 / htmlq 委譲 / 併用)`) であり、`modules/verify-executor.md` § "Slash (`/`) notation in rubric condition text" が容認する「単一条件配下のサブケース列挙を括弧で示す形式」に該当する。独立トリガの OR ではないため `OR:` プレフィクスへの書き換えは不要と判断し、AC 文言は変更していない。

### htmlq 実機検証の生データ (`/spec` フェーズ実施)

| 検証項目 | 結果 |
|---|---|
| 隣接兄弟セレクタ (正順) | `htmlq "input[name='first_name'] + input[name='last_name']" --attribute name` → `last_name` / exit 0 |
| 隣接兄弟セレクタ (逆順) | 出力なし / exit 0 |
| 不正セレクタ (`div>>bad`) | `thread 'main' panicked at src/main.rs:248:10: Failed to parse CSS selector: ()` / exit **101** |
| 件数出力オプション | 存在しない (`htmlq --help` の FLAGS / OPTIONS に該当項目なし) |
| 単一マッチの出力行数 | `form div.row` → 1 マッチだが 4 行出力 (要素が複数行にまたがるため) |
| `--attribute` 未保持要素 | `form p --attribute name` → 0 バイト出力 (空行ですらない) |

測定スコープ: htmlq 0.4.0 (Homebrew, `/opt/homebrew/bin/htmlq`)、macOS 25.4.0、`.tmp/page.html` (form / div.row / input×2 / p / br / span を含む 12 行の fixture)。

### プロトタイプ検証の生データ (`/spec` フェーズ実施)

`.tmp/proto.py` (実装ステップ 1-4 相当) で以下を実測。すべて期待どおり。

| セレクタ | 期待 | 実測 |
|---|---|---|
| `input[name='first_name'] + input[name='last_name']` | 1 | 1 |
| `input[name='last_name'] + input[name='first_name']` | 0 | 0 |
| `form > div.row` | 1 | 1 |
| `form > input` (孫なので不一致) | 0 | 0 |
| `form input` (子孫) | 2 | 2 |
| `div.row ~ span` | 1 | 1 |
| `span ~ div.row` (逆向き) | 0 | 0 |
| `div[data-x='a b'] > span` | 1 | 1 |
| `div` (後方互換) | 2 | 2 |
| `.a` (後方互換) | 1 | 1 |
| `form.kf-form[data-kw-lang='ja']` (後方互換) | 1 | 1 |
| `div>>bad` / `> div` / `div >` / `div[unclosed` | exit 2 + stdout 空 | すべて exit 2 + stdout 空 |
| 空 stdin | `0` + exit 0 | `0` + exit 0 |

測定スコープ: Python 3.14.6 (macOS)、プロトタイプ約 250 行。CI (ubuntu-latest の system python3) では未実測 — 標準ライブラリのみのため差異は想定しないが、`/code` フェーズで bats 経由の CI 実行により確認される (AC6)。

### 既存パターンとの整合

- **ツール検出パターンの一貫性**: 案 A ではツール検出 (`command -v` / ToolSearch / バージョンチェック) を一切導入しないため、既存の検出パターン (`browser-adapter` の `command -v browser-use`、`lighthouse-adapter` の CLI 検出) との分岐は発生しない
- **依存パッケージの追加なし**: 外部レジストリからの新規依存追加がないため、バージョン事前確認は不要
- **Adapter パターン事前調査 (`docs/environment-adaptation.md` Extension Guide Step 0)**: `modules/verify-executor.md` で `adapter-resolver.md` に委譲している行は `lighthouse_check` / `browser_check` / `browser_screenshot` / `visual_diff` の 4 件、バンドル済みアダプタは `browser-adapter.md` / `lighthouse-adapter.md` / `visual-diff-adapter.md` の 3 件。いずれも「複数の実装選択肢の抽象化」を必要とするケースであり、本件 (実装選択肢が実質 1 つ) は該当しない

### skill-dev SHOULD 制約への対応

- **#825 (既存パーサ挙動の検証)**: `scripts/validate-skill-syntax.py` の `_parse_verify_args()` を実際に import して combinator セレクタの引数分解を実測確認した (Changed Files の「変更不要」節に記載)
- **#672 (引数パーサのエッジケース)**: 未終端の引用符 / 空セレクタ / 不正文字 (連続 combinator) / 括弧の不均衡を Implementation Step 1 の exhaustive リストとテストケース (g) に含めた
- **#526 (テスト置換のシナリオ網羅)**: 既存 7 ケースを削除・改変しない方針を Step 6 に明記した

## issue retrospective

`/issue 1069 --non-interactive` によるリファインを実施。

### Triage
- Title を noun-ending 規則に合わせて正規化: `...を扱えるようにする` → `...を扱えるように`
- Type: Feature (Issue Types API)
- Size: L (`scripts/html-selector-match.py` のパーサ設計変更 + `modules/verify-executor.md` 更新 + テスト追加、という複数ファイル・実装ロジック変更を伴うため Axis 1 = M から Complexity adjustment で +1)
- Value: 3 (Impact=2: `modules/verify-executor.md` は多数の Skill から参照される共有コンポーネント。Alignment=4: `docs/product.md` の検証ハーネスとしての Vision に直結。raw=6 → Value 3)
- 重複候補: なし

### Auto-Resolve Log (non-interactive mode)

- **実装方式は 案 B (htmlq 委譲 + 内製実装フォールバック) を推奨** — reason: Issue 本文中の実測データ (htmlq 0.4.0 の combinator 完全サポート、Homebrew 導入容易性) に加え、`docs/product.md` の「オプショナル依存はグレースフルフォールバック」という既存方針、および `Adapter` 概念 (detect → translate → delegate) と設計思想が一致するため。ただし AC (Pre-merge 2/3 件目) は rubric ベースでどの実装方式でも検証可能な文言のため、AC 自体は変更せず Issue 本文に推奨と根拠のみ追記した。最終決定は `/spec` に委ねる。
  - Other candidates: 案 A (内製実装のみ拡張)、案 C (htmlq 必須化 — #1056 の目的に反するため非推奨)
  - **`/spec` フェーズでの結末**: 実機検証の結果、この推奨は覆り 案 A を採用した (本 Spec の「Alternatives Considered」参照)

### Acceptance Criteria の変更

- Pre-merge に 2 件追加:
  - `tests/html-selector-match.bats` に combinator 用テストケースが追加されていることの `grep` 検証 (既存 4 件の rubric/grep は「実装方針が決定された」ことしか検証しておらず、実際の動作を検証する項目が欠けていたため)
  - `github_check "gh pr checks" "Run bats tests"` — Size L (PR route) に合わせた CI テスト pass 確認。`.github/workflows/test.yml` の `Run bats tests` ジョブ名と一致することを確認済み

### スキップした操作

- Step 12 (Scope Assessment / sub-issue splitting): non-interactive mode のため High-Stakes Decision としてスキップ。Size L は分割不要な規模と判断し XL への変更は行っていない

## spec retrospective

### Minor observations

- `/issue` の Auto-Resolve Log が「この推奨は暫定であり `/spec` で実機再確認したうえで最終決定すること」という引き継ぎ指示を明示していたため、`/spec` 側が推奨を無批判に踏襲せず検証を実行できた。非対話モードの auto-resolve は「暫定判断 + 下流への検証指示」の形で渡すと、誤った早期確定を防げる。
- Issue 本文が案 B の根拠として引用していた downstream 実測 (「`--attribute` 指定時は 1 マッチ 1 行になるため行数で代用できる」) は、`/spec` の追試で成立しないことが判明した。属性を持たない要素は空行ではなく 0 バイト出力になり、要素が複数行にまたがると 1 マッチで 4 行出力される。**Issue 本文に記載された実測データであっても、設計判断の主軸になる場合は `/spec` で追試する価値がある**。
- 設計判断が「実装コストの見積」に依存する場合 (本件では「内製拡張は実装量が膨らむ」という Issue 本文の懸念)、`/spec` 段階でプロトタイプを書いて実測すると見積の不確実性を除去できた。約 30 分のプロトタイプ実装で「追加約 120 行・void element 対応は 1 箇所の判定・不正入れ子は例外なし」まで確定した。

### Judgment rationale

- `docs/product.md` の「Everything else is optional; each Skill falls back gracefully when optional dependencies are absent」を外部依存導入の根拠にできるのは、**フォールバック先が機能的に劣化版でも成立する場合に限る**と判断した。本件は compound selector では DOM 順序を原理的に判定できず、フォールバック先が存在しない (UNCERTAIN = 機能なし) ため、同方針は適用条件を満たさない。`/issue` の Auto-Resolve Log はこの適用条件を検証せずに「方針と整合する」と読んでいた。
- Adapter パターンの適用可否は `docs/environment-adaptation.md` § "Adapter Pattern Application Requirements" (複数の実装選択肢の抽象化が必要か) を判定基準とした。CSS セレクタ判定は実装選択肢が実質 1 つであり、`mcp_call` がアダプタ層を持たない理由と同じ論理が当てはまる。Issue 本文の `Adapter` 用語定義 (detect → translate → delegate) との「設計思想の一致」は、適用要件そのものではない。
- AC2 の rubric 文言が条件節 (「外部バイナリが必要な場合は」) であるため案 A では空虚に真になるが、adversarial な grader が無条件要件と誤読するリスクを見込み、`modules/verify-executor.md` に「外部バイナリを一切必要としないため未インストール時の分岐は存在しない」旨を明示的に書く指示を Implementation Step 5 に入れた。**条件付き AC は、前件が偽であることを成果物側で可読にしておく**のが grader 対策として有効。
- AC 文言自体は 1 件も変更しなかった。`modules/verify-patterns.md` §18 (Issue Body Is SSoT for Verify Commands) に従い、実装方式の決定 (HOW) は Spec と Issue 本文の Auto-Resolved Ambiguity Points に記録するに留めた。

### Uncertainty resolution

- **U1 (implied end tag 非対応)**: プロトタイプ実測で `<div><p>a<p>b</div>` に対する `div > p` が 1 (ブラウザ準拠なら 2) と確定。仕様として受け入れ、docstring と `modules/verify-executor.md` に既知の制約として明記する方針とした。本 Issue の動機ケース (`<input>` 兄弟の順序判定) は void element のため implied end tag と無関係であることを確認した。
- **U2 (兄弟走査の計算量)**: `list.index()` による前方兄弟参照は兄弟数が多い文書で `~` 照合を O(n^2) にする。`Node.sibling_index` を持たせて O(1) 化する方針を Implementation Step 2 に明記して解消した。
- **htmlq の exit code 意味論**: Issue 本文の記載 (不正セレクタで exit 101 panic、マッチ 0 件と matched を exit code で区別不能) を実機で再現確認し、Notes の生データ表に記録した。案 A 採用により実装には影響しないが、将来 htmlq 採用が再検討された場合の一次情報として残す。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1-4 の記述どおりに `split_selector` / `parse_compound` / `TreeBuilder` / `Node` / `matches_compound` / `matches_chain` を実装した。プロトタイプ検証の生データ表 (Notes) に記載された全パターン (12 セレクタケース + 不正セレクタ 4 種 + 空 stdin) を実装後に再実測し、全て一致することを確認した。

### Design Gaps/Ambiguities

- `matches_chain` の `chain` 内で「どの要素とどの combinator が対応するか」のインデックス規約が Implementation Step 3 の文章だけでは一意に確定しなかった。`split_selector` (Step 1) の出力形式 (「先頭要素の combinator は `None`、以降は前の compound とを結ぶ combinator」) から逆算し、`chain[i][0]` を「`chain[i-1]` と `chain[i]` を結ぶ combinator」と定義して実装した。この対応関係は自明ではあるが、Step 3 に明記されていれば再確認の手間が省けた。
- `/code` スキル自身の Step 順序に起因する問題を発見した: Step 1 (Consumed Comments を Spec に記録) はメインリポジトリのワーキングツリーに対して行われるが、直後の Step 2 (Worktree Entry) はデフォルト `baseRef: fresh` (= `origin/<default-branch>` から分岐) で worktree を作成するため、Step 1 の未コミット変更が worktree 側に一切引き継がれない。本セッションで実際にこの状態を踏み、worktree 側で同内容を再記録し、メインリポジトリ側の孤立した diff を `git checkout --` で破棄して回避した。本 Issue の実装スコープ外 (`/code` スキル自体の構造的な穴) のため、follow-up Issue #1078 (`retro/code`) として起票した。

### Rework

- Rework 自体は発生していない (実装ロジックは Spec のプロトタイプ検証を踏襲し一度で全ケース一致)。上記の Consumed Comments 孤立 diff の復旧作業のみ、本来不要だったやり直しに当たる。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Implementation Steps 1-4 の記述どおりに `split_selector` / `parse_compound` / `TreeBuilder` / `Node` / `matches_compound` / `matches_chain` を実装。Spec Notes のプロトタイプ検証表 (12 セレクタ + 不正セレクタ 4 種 + 空 stdin) を実装後に再実測し、全一致を確認した
- `matches_chain` の chain インデックス規約 (`chain[i][0]` は `chain[i-1]` と `chain[i]` を結ぶ combinator) は `split_selector` の出力形式から一意に決定し、そのまま再帰実装した
- 既存 7 bats ケース + 新規 combinator ケース 8 件、および `modules/verify-executor.md` / `skills/issue/SKILL.md` の関連ドキュメント更新をすべて含め、フルスイート (1258 件) が PASS することを確認した (`html-selector-match.py` は複数の bats ファイルから参照されるため behavioral change 扱いとしてフルスイートを実行)
- Pre-merge AC 6 件中、rubric/grep の 4 件は本フェーズ内で PASS 確認済み。`github_check "gh pr checks" "Run bats tests"` は PR/CI が本フェーズ完了時点でまだ存在しないため UNCERTAIN のまま — CI 完了後に確認される

### Deferred Items

- implied end tag 規則への非対応は Spec 記載どおり既知の制約として docstring と `modules/verify-executor.md` に明記した (U1 の対応方針を踏襲、追加対応なし)
- Post-merge AC 2 件はいずれも `verify-type: manual`。`/verify` フェーズで人間が実施する
- `github_check "gh pr checks" "Run bats tests"` (Pre-merge AC6) の PASS 確認は CI 完了後 (`/review` または `/verify`) に持ち越し

### Notes for Next Phase

- `/code` スキル自身の Step 1 (Consumed Comments 記録) と Step 2 (worktree fresh 作成) の順序矛盾により、メインリポジトリ側に孤立した diff が発生する事象を本セッションで確認・復旧した。follow-up Issue #1078 (`retro/code`) を起票済み — `/review` 側で特別な対応は不要
- 実装は CLI 契約 (引数1個/stdin/stdout/exit code) を変更していないため、`html_check` を呼び出す既存の Issue AC には影響しない
- `docs/structure.md` / `scripts/validate-skill-syntax.py` は Spec の判断どおり変更不要のまま (`/spec` フェーズの実測確認を踏襲、`/code` 側での再確認でも変更不要と再確認)
