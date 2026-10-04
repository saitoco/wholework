# Issue #1495: check-forbidden-expressions: scripts/ を走査対象に追加する

## Overview

`docs/tech.md` § Forbidden Expressions は、`docs/product.md` § Terms で "Formerly called" とされた廃止語を、code comments を含む新規コンテンツで使うことを禁じている。一方 `scripts/check-forbidden-expressions.sh` の走査対象 `SCAN_DIRS` は `skills/ modules/ agents/ tests/ docs/` で、`scripts/` を含まない。このため、スクリプトのコメントに入った廃止語は CI で検出されない。本 Spec は `SCAN_DIRS` に `scripts/` を加え、ポリシーの範囲と検査の範囲を一致させる。

`scripts/` を走査対象に加えると、現状 (main `51c3b86f`) では次の 3 種類が検出される (計 15 行)。追加後も違反 0 件で終了させるため、種類ごとに対処する。なお、本 Spec 自身も `docs/spec/` 配下で CI の走査対象になるため、旧称の語を書く行には `旧称` を併記している (`docs/tech.md` § Forbidden Expressions の規定)。

| 検出 | 原因 | 対処 |
|------|------|------|
| `scripts/check-forbidden-expressions.sh` 自身の定義行 (13 行) | `DEPRECATED_TERMS` 配列と `case` 分岐に全廃止語がリテラルで現れる | `check_term` のパイプラインに自己参照の除外を追加する (既存の bats 自己除外と同じ方式) |
| `scripts/observation-trigger.sh:3` | 文頭の動詞 (旧称 Dispatch。大文字小文字を区別した一致) | コメントを言い換える (旧称 Dispatch → Trigger) |
| `scripts/reconcile-phase-state.sh:617` の見出しコメント | 旧称 Dispatch の部分文字列一致 (Dispatcher)。別語であり、動詞用法でもない | チェッカーに単語境界を導入し、別語を検出しない (コメントは変更しない) |

回帰テストとして、`tests/check-forbidden-expressions.bats` に `scripts/` 配下の検出を保護するテストを追加する (旧実装では FAIL する入力を使う)。`docs/*.md` は変更しない (実装がポリシーに追いつく側であり、既存の記述は変更後も正確。Notes「翻訳同期・他文書の確認」を参照)。

## Changed Files

- `scripts/check-forbidden-expressions.sh`: (a) `SCAN_DIRS` の末尾に `scripts/` を追加、(b) `check_term` のパイプラインに自己参照の除外 (行頭アンカー付きの `grep -v`) を追加、(c) 旧称 Dispatch のケースを部分文字列一致から単語境界付きの ERE に変更 — bash 3.2+ 互換 (新しい構文は使わず、既存形式の `grep -v` 行の追加とパターン変更のみ)
- `scripts/observation-trigger.sh`: 3 行目のコメントの文頭の動詞 (旧称 Dispatch) を Trigger に言い換える (コメントのみ。bash 3.2+ 互換性・挙動への影響なし)
- `tests/check-forbidden-expressions.bats`: `setup()` に `scripts/` ディレクトリの作成を追加し、新規テスト 4 件を追加 (Implementation Steps 3)
- [Steering Docs sync candidate] keyword "SCAN_DIRS" skipped: matched 12 files (no discriminating power)
- [Steering Docs sync candidate] keyword "check-forbidden-expressions.sh" skipped: matched 78 files (no discriminating power)
- [Steering Docs sync candidate] keyword "observation-trigger.sh" skipped: matched 77 files (no discriminating power)
- [Steering Docs sync candidate] keyword "check_term" (関数名): matched 4 files — `grep -rn` で確認した結果、本体と過去 Spec 3 件 (`docs/spec/issue-270|373|765-*.md`、disposable) のみで、同期候補なし
- 上の 4 件の測定: `grep -rl "<keyword>" docs/ tests/ scripts/ modules/ | wc -l` (全ファイル、`docs/spec/` の disposable な過去 Spec を含む)

## Implementation Steps

1. `scripts/observation-trigger.sh` の 3 行目のコメントを言い換える (→ Pre-merge AC2)
   - 文頭の動詞 (旧称 Dispatch) を Trigger に置き換え、`# Trigger observation-type ACs when a named event fires.` とする。ほかの行は変更しない (スクリプト名の語幹 `trigger` と `modules/observation-trigger.md` の語彙に揃えた)
2. (parallel with 1) `scripts/check-forbidden-expressions.sh` を変更する (→ Pre-merge AC1, AC2)
   - (a) `SCAN_DIRS` を `"skills/ modules/ agents/ tests/ docs/ scripts/"` にする。1 行のまま、`^SCAN_DIRS=` で始まる形を保つ (Pre-merge AC1 の `grep` が一致する)
   - (b) `check_term` のパイプラインで、`grep -v 'tests/check-forbidden-expressions.bats' \` の直後に `| grep -v '^scripts/check-forbidden-expressions.sh:' \` を追加する。`grep -r` の出力は `path:content` 形式なので、行頭の `scripts/check-forbidden-expressions.sh:` だけに一致する。本文がこのパスに言及しているだけの他ファイルの行は除外しない (Notes「自己除外を行頭アンカーにする理由」)。自己参照の除外が 2 つになるので、`check_term()` の直前に英語のコメントを 1〜2 行置く (例: `# Self-reference exclusions: this script and its bats file hold every deprecated term as literals.`)。バックスラッシュ継続のパイプラインの途中にはコメント行を挟まない (継続が切れて構文エラーになる)
   - (c) 旧称 Dispatch のケースの `check_term` 呼び出しを、第 2 引数 `"-r"` → `"-rE"`、第 3 引数 `"$TERM"` → 語を `\b` で前後から挟んだ ERE に変更する (同じ `case` 内の旧称 Design file / 旧称 Issue Spec のケースと同じ形式)。ケース直上のコメントは、大文字小文字を区別し単語境界を使うこと、散文中の小文字 (`command dispatch`) と、語の後ろに英字が続く別語 (名詞形・複数形) を誤検出しないことを述べる英語に更新する
   - (d) fail-safe critical の扱い: 上記の変更で `|| true` / `|| VIOLATIONS=1` の構造と終了コード (違反あり = 1、なし = 0) は変えない。edge case の期待挙動は Notes「Fail-safe critical」を参照
3. (after 2) `tests/check-forbidden-expressions.bats` を変更する (→ Pre-merge AC3, AC4)
   - `setup()` の `mkdir -p` 群に `mkdir -p "$BATS_TEST_TMPDIR/scripts"` を追加する (`scripts/` を空でも存在させ、`grep` の "No such file or directory" が既存テストの `$output` に混ざらないようにする)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する新規テストケース (`tests/check-forbidden-expressions.bats` に下表の 4 件) を追加したうえでスイートが PASS すること。命名は既存の接頭辞 (`detection:` / `exclusion:` / `false positive:`) に揃え、関連する既存テストの近くか末尾にまとめて置く

   | # | `@test` 名 | フィクスチャ (CWD = `$BATS_TEST_TMPDIR`) | 期待 | 守るもの |
   |---|-----------|------------------------------------------|------|----------|
   | T1 | `detection: deprecated term in scripts dir exits 1` | `scripts/bad.sh` に `# use verification hint here` を 1 行 (旧称 verification hint を含む) | status 1、`$output` に `verification hint` を含む | `scripts/` の走査 (Pre-merge AC4。旧実装は `scripts/` を走査せず status 0 になり FAIL する) |
   | T2 | `exclusion: own definition file scripts/check-forbidden-expressions.sh is not flagged` | `scripts/check-forbidden-expressions.sh` に `  "verification hint"` を 1 行 (旧称 verification hint を含む) | status 0 | 自己除外 (除外行を消すと FAIL) |
   | T3 | `false positive: Dispatcher and Dispatches word forms are not flagged` | `scripts/router.sh` に `# --- Dispatcher ---` と `# Dispatches to the phase handler` の 2 行 (旧称 Dispatch の派生語) | status 0 | 単語境界 (部分文字列一致に戻すと FAIL) |
   | T4 | `detection: other file mentioning the checker path is still flagged` | `docs/guide.md` に `see scripts/check-forbidden-expressions.sh for verification hint` を 1 行 (旧称 verification hint を含む) | status 1 | 自己除外の行頭アンカー (アンカーを外すと FAIL) |

4. (after 2, 3) 検証する (→ Pre-merge AC1〜AC4)
   - (a) `bash scripts/check-forbidden-expressions.sh` が exit 0 で終わる
   - (b) `command -v bats` で導入を確認する。導入済みなら `bats tests/check-forbidden-expressions.bats` (既存 19 件 + 新規 4 件) が PASS する。未導入なら、push 後の CI `Run bats tests` ジョブの結果で確認する (Spec 作成時のこの環境は未導入だった)
   - (c) 新規テスト T1 が旧実装で FAIL することを確認する (Pre-merge AC4)。`bats` が使えるなら、`SCAN_DIRS` から ` scripts/` を一時的に外して T1 だけを実行し、FAIL を見てから元に戻す。`bats` がない場合は、T1 と同じ入力 (`scripts/bad.sh` に旧称 verification hint を含む 1 行) を `.tmp/` 配下の空のフィクスチャ構造に Write ツールで作り、変更前のチェッカーが exit 0、変更後が exit 1 になることを確認する (Spec 作成時に同じ方法で実測済み。Notes「事前検証」)
   - (d) 1 つのコミットにまとめる (`SCAN_DIRS` の拡張だけを先にコミットすると CI の `check-forbidden-expressions` ジョブが失敗する)

## Verification

### Pre-merge

- <!-- verify: grep "^SCAN_DIRS=.*scripts/" "scripts/check-forbidden-expressions.sh" --> `scripts/` が走査対象に含まれている
- <!-- verify: command "bash scripts/check-forbidden-expressions.sh" --> 走査対象を広げた後も違反 0 件で終了する (チェッカー自身の定義行、`observation-trigger.sh` の動詞用法、`reconcile-phase-state.sh` の別語 (旧称 Dispatch の派生語) への対処を含む)
- <!-- verify: command "bats tests/check-forbidden-expressions.bats" --> チェッカーの bats が PASS する
- <!-- verify: rubric "tests/check-forbidden-expressions.bats に、scripts/ 配下のファイルに禁止表現が含まれる場合に exit 1 となることを検証するテストケースが追加されている。そのテストは scripts/ を走査対象に含めない旧実装 (SCAN_DIRS に scripts/ がない状態) に対して FAIL する入力を使っている" --> `scripts/` 配下の禁止表現を検出することを bats が回帰テストとして保護している (旧実装では FAIL する入力を使う)

### Post-merge

なし

## Notes

### 採用方針の判断 (non-interactive auto-resolve)

Issue の Retrospective は、3 種類の検出への対処 (語の言い換え、除外、単語境界の導入など) を `/spec` の判断に委ねている。いずれも既存パターンから一意に推論でき、選択肢によって Spec の記述が変わる曖昧さではないため、auto-resolve の条件「既存パターンから一意に推論できる」に基づいて次のとおり決めた。

- **チェッカー自身の定義行 → 自己除外 (採用)**: 既存の `grep -v 'tests/check-forbidden-expressions.bats'` と同じ方式で、出力側のフィルタを 1 行足す。不採用: 定義を文字列連結で書いてリテラルを消す (可読性と検索性が落ちる)、`grep --exclude` を使う (除外の仕組みが bats 用のパイプラインと二重になる)
- **動詞用法 → 言い換え (採用)**: 文頭の大文字は、動詞用法と旧称を機械的に区別できない。不採用: 該当行だけを許容する除外 (将来、旧称が同じ形で混入しても見逃す)。言い換えの語は、スクリプト名の語幹と `modules/observation-trigger.md` の語彙 (trigger) に合わせて Trigger を選んだ
- **別語 → 単語境界の導入 (採用)**: 原因はチェッカーの部分文字列一致で、別語を書くたびに再発する。`scripts/` のコメントは文頭が大文字になるため、名詞形・複数形が自然に現れる (旧称 Dispatch の複数形は `docs/reports/external-kill-investigation.md` の 5 行に既に存在し、`^docs/reports/` のパス除外で見えていないだけ)。同じスクリプト内の旧称 Design file / 旧称 Issue Spec のケースが、同種の誤検出を単語境界で避けている先例でもある。不採用: コメントの言い換え (再発する)、`extra_grep_v` で別語を例外にする (同じ行に語単体があっても見逃す抜け穴になる)
- **影響範囲**: 単語境界は `scripts/` 以外のディレクトリの判定も緩める (語の後ろに英字が続く語を検出しなくなる)。現状の違反は 0 件で、緩める方向の変更のため新たな違反は生じない。語単体 (後ろが空白・記号・行末) は引き続き検出する (事前検証の語単体 + 記号の入力)。`\b` 付きの `-E` は既存の 2 ケースが既に使っており、macOS の `grep` に関する新しい依存は増えない

### 自己除外を行頭アンカーにする理由

既存の `tests/check-forbidden-expressions.bats` の除外は行頭アンカーなしの `grep -v` である。同じ形で `scripts/check-forbidden-expressions.sh` を除外すると、他ファイル (たとえば `docs/spec/` の Spec) の本文がこのパスに言及し、かつ廃止語も含む行まで検出から外れる抜け穴になる。`grep -r` の出力は `path:content` なので、行頭の `scripts/check-forbidden-expressions.sh:` に一致させればチェッカー自身の行だけを除外できる。この抜け穴の有無を T4 で保護する。既存の bats 除外は本 Issue の範囲外のため変更しない。

### 事前検証 (Spec 作成時に実測)

- 測定: main `51c3b86f` の作業ツリー。`scripts/` の全ファイルを対象に、`check_term` と同じ除外フィルタを通して禁止語 9 種を検索した。検出は Overview の 3 種類のみ (チェッカー自身の定義行 13 行、`scripts/observation-trigger.sh:3`、`scripts/reconcile-phase-state.sh:617`)。自己定義行 13 行の内訳は、配列の 9 行、`case` 分岐の 3 行、旧称 Issue Spec のケースの `check_term` 呼び出し 1 行
- 計画した実装 (`SCAN_DIRS` の拡張、行頭アンカー付きの自己除外、単語境界) を `.tmp/` に試作し、同じ作業ツリーで実行した。残る検出は `scripts/observation-trigger.sh` の 1 行だけで (Implementation Steps 1 の言い換えで 0 件になる)、チェッカー自身の定義行と `reconcile-phase-state.sh` の別語 (旧称 Dispatch の派生語) は検出されない。同じ作業ツリーで現行のチェッカーは exit 0 (ベースライン)
- 複数形の実在: リポジトリ全体 (`.git/` と `.claude/` を除く) で、旧称 Dispatch に語尾 es / ed / ing が付いた形を ERE の単語境界つきで検索すると 5 行がヒットし、すべて `docs/reports/external-kill-investigation.md` にある (旧称 Dispatch の複数形)
- 新規テスト 4 件の入力を、空のフィクスチャ構造 (`skills modules agents tests docs/spec scripts`) に Write ツールで作って試作チェッカーに与えた: T1 = exit 1 (現行のチェッカーは同じ入力で exit 0)、T2 = exit 0、T3 = exit 0、T4 = exit 1。語単体に記号が続く入力 (`# <語>: run observation ACs`) は exit 1 のままで、語単体の検出は維持される

### Issue 本文と既存実装の整合

Background の事実主張 (`SCAN_DIRS` の値、検出される 3 種類とその行番号、`docs/tech.md` が code comments を含めて禁じていること) をすべて実装と照合し、一致した。乖離なし。Issue 本文の premise marker (`grep_count ... -ge 1`) は `scripts/observation-trigger.sh` の言い換え後に成立しなくなるが、Background が述べる「修正前の状態」の記録であり、想定内である。

Pre-merge AC2 の説明文は、CI の走査を避けるため、Issue 本文の語 (旧称 Dispatch の派生語 Dispatcher) を「別語」と言い換えた。verify command は Issue 本文と一致している。

### Fail-safe critical

`scripts/check-forbidden-expressions.sh` は CI ゲート (`.github/workflows/test.yml` の `check-forbidden-expressions` ジョブ、`/code` のローカル確認、`scripts/pre-merge-check.sh` のベースライン比較) で、`|| true` を含む (`grep -nF -e '|| true'` で `check_term` の 2 箇所を確認) ため、fail-safe critical に該当する。変更後の期待挙動:

- 空・巨大な入力: 空のファイルも巨大なファイルも、`grep` は行単位で処理し、一致なしなら exit 0 (変更なし)。`scripts/` が存在しない場合、`grep` はそのディレクトリについて標準エラーに出力するだけで、ほかのディレクトリの走査は続く (fail-open。既存挙動を踏襲する。bats の `setup()` で `scripts/` を作るのはこの出力を避けるため)
- 特殊文字: `>`・`"`・改行・CRLF・マルチバイトを含む行も、パイプラインは行単位のテキストとして扱う。マルチバイトの語 (日本語表記の 2 語) の一致は既存のロケール依存のまま。新規の自己除外は `path:` 接頭辞に対する行頭アンカーなので、本文側の文字には影響されない
- 依存コマンドの失敗: `grep` が終了コード 2 (権限エラーなど) を返しても `|| true` で握りつぶされ、そのファイルが未走査のまま exit 0 になり得る (fail-open)。CI では全ファイルが読めるため実害は小さい。エラーと「一致なし」を区別するには `check_term` の再設計が必要で、本 Issue の範囲外のため挙動は変えない

### audit/investigation-type の判定と識別子の実在確認

audit/investigation-type: no — 本 Issue の目的はチェッカーの走査範囲の拡張であり、項目ごとの分類を後続プロセスが判断根拠として読む成果物ではない。ただし、本 Spec が引用する識別子 (`SCAN_DIRS`、`check_term`、`tests/check-forbidden-expressions.bats` の除外行、`scripts/observation-trigger.sh:3`、`scripts/reconcile-phase-state.sh:617`、`docs/reports/external-kill-investigation.md` の複数形、`tests/pre-merge-check.bats` のスタブ) は、いずれも `grep` で現在のコードベースに実在することを確認した。

### bats テストの入力形式と自己参照除外

- 入力形式: テストは `$BATS_TEST_TMPDIR` を CWD にして、`skills/ modules/ agents/ tests/ docs/ scripts/` 配下に `echo "..." > <dir>/<file>` でテキストファイルを作る (`setup()` が 6 ディレクトリと `docs/spec` を作る)。チェッカーは `grep -r` の出力 (`path:content`) を行単位で処理し、違反ありなら exit 1 で標準出力に `Forbidden expression '<term>' detected:` と該当行を出し、なしなら exit 0
- 新規の自己除外は行頭の `scripts/check-forbidden-expressions.sh:` に一致させるため、T2 と T4 のフィクスチャのパスは CWD 相対でちょうどこのパスにする
- 自己参照の除外: bats ファイル側は既存の `tests/check-forbidden-expressions.bats` 除外で足りる (新規テストのフィクスチャ文字列は bats ファイルに書かれる)。チェッカー本体は本 Issue の自己除外が担う

### テスト

- 新規分岐ロジック (自己除外フィルタ、単語境界、`scripts/` の走査) に対し、新規テスト 4 件 (T1〜T4) を追加する。Pre-merge AC3 は、既存スイートの PASS だけでなく、これらを追加した状態での PASS を要求する (Implementation Steps 3)
- 各テストの識別力: T1 は旧実装で FAIL (実測)、T2 は自己除外の行を消すと FAIL、T3 は部分文字列一致に戻すと FAIL、T4 は行頭アンカーを外すと FAIL (T2〜T4 は各フィルタの構造から導ける)
- 他のテストとの結合: `grep -rln "check-forbidden-expressions" tests/` は 2 件 (本体の bats と `tests/pre-merge-check.bats`)。後者はスタブのチェッカー (`<<'STUB'`) を使い、実スクリプトの挙動に依存しないため、Pre-merge AC3 は単一の bats で足りる (`modules/verify-patterns.md` §24 の full suite 要件には該当しない)
- この環境には `bats` が未導入 (`command -v bats` の出力が空)。CI は `apt-get install bats` で導入する。`bats` が使えない環境では、Pre-merge AC3 は CI の `Run bats tests` の結果を参照して判定する

### 翻訳同期・他文書の確認

- `docs/*.md` は変更しないため、`docs/translation-workflow.md` に基づく `docs/ja/` の同期は不要
- 変更不要と判断 (`grep` で確認済み): `docs/tech.md:234` (code comments を含めて禁じる規定。実装が追いつく側)、`docs/tech.md:237` と `docs/ja/tech.md:228` (`SCAN_DIRS` に `docs/spec/` が含まれる旨。追加後も正確)、`docs/structure.md:272` (チェッカーの説明に走査ディレクトリの列挙なし)、`skills/code/forbidden-expressions-check.md` と `skills/review/skill-dev-recheck.md` (走査範囲の記述なし)
- Outbound pointer sync candidate: `scripts/check-forbidden-expressions.sh` のヘッダーが指す `docs/product.md` § Terms は、Terms 表の内容が変わらないため対象外。`scripts/observation-trigger.sh` が指す `modules/observation-trigger.md` も、言い換える 1 行と同じ文が存在しない (`grep` で確認) ため対象外
- Listing-side sub-check: サブコマンド・ファイルの追加/削除/改名・ディレクトリ構造の変更を伴わないためスキップ。Tag/enum の意味拡張、リネーム、機能削除、`allowed-tools` (新規 `scripts/*.sh` と `modules/*.md` の変更なし) にも該当しない

### Size 再評価

triage 時の Size は S。Changed Files は 3 件だが、`scripts/observation-trigger.sh` は 1 行のコメント言い換えで、実質は 2 ファイル規模 (Axis 1: S)。Axis 2 は「スクリプトのロジック変更 (+1)」と「既存パターンの横展開 (−1。`grep -v` 行の追加と単語境界は同じスクリプト内に先例あり)」が相殺する。CI Dependency Minimum Override の対象なし (CI workflow の変更なし。bats は per-test の `setup()` にディレクトリ作成を足すだけで、共有 fixture の構造は変えない)。S のままで route は patch。同じスクリプトの先例 (#270, #765) も、PR 番号の付かない `closes #N` のコミットで入っており、patch route と整合する。

### `/code` へのメモ

- 1 つのコミットにまとめる (`SCAN_DIRS` の拡張だけが先に push されると CI の `check-forbidden-expressions` ジョブが失敗する)
- Changed Files に `.claude/` 配下はなく、`git add -f` は不要
- 実装の前後で `bash scripts/check-forbidden-expressions.sh` を実行する。Code Retrospective を Spec に書く前にも再実行する (Spec も走査対象。旧称の語は `旧称:` を併記して書く。`skills/code/forbidden-expressions-check.md` の Retrospective Guard)
- 新規のコメントとテスト名は英語 (ソースコードの言語規約)。Spec の記述は日本語

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (回帰テスト用 AC の追加判断と、Background の検出 3 種類への訂正) / https://github.com/saitoco/wholework/issues/1495#issuecomment-5977709784

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1〜4 を Spec どおりに実装し、1 コミットにまとめた (`SCAN_DIRS` の拡張だけを先にコミットしていない)

### Design Gaps/Ambiguities
- この環境には `bats` が未導入だったため、Pre-merge AC3 (`bats tests/check-forbidden-expressions.bats`) はローカルで評価できない。AC3 はチェックを付けず、push 後の CI `Run bats tests` ジョブの結果で確認する (Step 14 の CI-based bats AC confirmation 対象)
- 新規テスト T2〜T4 は、`.tmp/fx/` の空フィクスチャ構造にテストと同じ入力を作ってチェッカーを直接実行し、期待どおりの終了コード (T2 = 0、T3 = 0、T4 = 1) を確認した。bats の `run` 経由の実行そのものは未確認

### Rework
- なし

### Pre-implementation FAIL Check
- Confirmed pre-implementation FAIL for 1 new test(s): T1 (`scripts/` 配下の検出) は、`SCAN_DIRS` から `scripts/` を外した旧実装のコピーで exit 0 (テストの期待は exit 1 なので FAIL)、新実装で exit 1 になることを確認した。T2〜T4 は各フィルタ (自己除外、単語境界、行頭アンカー) の構造から識別力を導いた (Spec Notes「テスト」のとおり)

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `check_term` の自己参照の除外は、行頭アンカー付き (`^scripts/check-forbidden-expressions.sh:`) にした。他ファイルがこのパスに言及しつつ廃止語も含む行を見逃さないため (T4 で保護)
- 旧称 Dispatch のケースは単語境界付きの ERE に変更し、`reconcile-phase-state.sh` の見出しコメントは変更しなかった

### Deferred Items
- Pre-merge AC3 (bats) は、ローカルに `bats` がないため、push 後の CI 結果で確認する (チェックなしのまま残している)

### Notes for Next Phase
- `/verify` は AC3 を CI の `Run bats tests` ジョブの結果で判定すること。CI が FAIL なら新規テスト 4 件 (T1〜T4) を最初に疑う
