# Issue #1514: tests: bats の Markdown 節抽出をコードフェンス対応の共通ヘルパーに統一

## Overview

bats テストが SKILL.md などの Markdown から見出しを起点に節を切り出す処理は、テストごとにインラインの awk で個別実装されており、コードフェンス内の `## ...` 行を見出しと誤認して節を途中で打ち切る。PR #1513 (Issue #1512) の CI FAIL はこの誤認が原因だった。

`tests/helpers/markdown-section.bash` に、フェンス内の見出し風の行を見出しとして扱わない共通ヘルパー `md_section` を 1 つ置き、`.bats` から `load` で読み込む。既存の見出しベースの節抽出 (Background の 8 ファイル・63 箇所、`tests/worktree-lifecycle.bats` の `section()`、`/spec` 時の追加調査で見つけた `tests/orchestration-fallbacks.bats` の 1 箇所) をすべてこのヘルパー経由に置き換え、ヘルパー自体のテストで #1513 と同じ形の入力 (フェンス内の `## ` 行) を検証する。

## Changed Files

- `tests/helpers/markdown-section.bash`: new file — 共通ヘルパー `md_section FILE HEADING_PREFIX [END_LEVEL]` を定義する (bash 3.2+ compatible、awk は POSIX 機能のみで mawk / BWK awk / gawk 互換)
- `tests/markdown-section.bats`: new file — `md_section` 自体のテスト (フェンス内の `## ` / `### ` 行で節が打ち切られないケースを含む)
- `tests/worktree-lifecycle.bats`: ファイル内の `section()` 定義を削除し、`load 'helpers/markdown-section'` を追加して 10 箇所の `section` 呼び出しと `failure_section()` を `md_section` 経由にする
- `tests/auto-batch.bats`: 3 つのラッパー関数 (`list_mode_section` / `count_mode_section` / `until_mode_section`) の本体を `md_section` 呼び出しに置き換え、27 箇所のインライン `run bash -c "awk ... | grep ..."` をラッパー関数経由に書き換える
- `tests/auto-completion-report.bats`: `batch_completion_section()` の本体を `md_section "$SKILL_FILE" "### Batch Completion Report" 2` に置き換える
- `tests/auto.bats`: 5 つの `step*_section()` (`### Step 3a:` / `### Step 3:` / `### Step 2a:` / `### Step 2:` / `### Step 5:`) の本体を置き換える
- `tests/code.bats`: 10 箇所 (9 関数、`step10_section()` は 2 回定義) の本体を置き換える
- `tests/review.bats`: 6 つのラッパー関数の本体を置き換える
- `tests/verify.bats`: 8 つのラッパー関数の本体を置き換える
- `tests/audit-manual-waiting-count.bats`: `manual_waiting_count_section()` の本体を置き換える
- `tests/review-rubric-safe.bats`: 2 箇所のインライン awk (`Rubric Command Semantics` 節、`### 9. When to Use` 節) を `md_section` に置き換える
- `tests/orchestration-fallbacks.bats`: archive の `## <anchor>` 節を切り出す複数行 awk (1 箇所) を `md_section` に置き換える
- `docs/tech.md`: `## Testing Strategy` の `### BATS Mocking Convention` の直後に `### BATS Markdown Section Extraction` (h3) を追加し、見出しベースの節抽出は共通ヘルパーを使う規約と `md_section` の振る舞いを記載する
- `docs/ja/tech.md`: 上記の和訳ミラー。`### BATS モッキング規約` の直後に `### BATS の Markdown 節抽出` (h3) を追加する (`docs/translation-workflow.md` の同期手順)
- `docs/structure.md`: [Steering Docs sync candidate (listing-side)] Directory Layout の `tests/` ツリーに `helpers/` (bats `load` で読み込む共有ヘルパー) の行を追加する
- `docs/ja/structure.md`: 上記の和訳ミラー (`tests/` ツリーに `helpers/` の行を追加)
- `README.md`: [Steering Docs sync candidate (listing-side)] `tests/` の列挙は現状なし (`grep -n "tests/" README.md` は e615db88 時点で 0 件)。変更不要の見込みで、`/code` が最終確認する
- [Steering Docs sync candidate] inbound の keyword check はスキップ: Changed Files に SKILL.md・`modules/`・`scripts/` を含まないため

## Implementation Steps

1. `tests/helpers/markdown-section.bash` を新規作成し、`md_section` を定義する (→ 受入条件 1)
   - シグネチャ: `md_section FILE HEADING_PREFIX [END_LEVEL]`。出力は stdout
   - 開始: コードフェンス外で、行頭が `HEADING_PREFIX` に **リテラルで** 一致する最初の行 (正規表現ではない。`index($0, prefix) == 1`)。その見出し行を出力の 1 行目に含める
   - 終了: 開始後、コードフェンス外で最初に現れる「`#` が 1 個以上続き直後が半角スペースの行」のうち、`#` の個数が `END_LEVEL` 以下の行の直前まで。見つからなければファイル末尾まで
   - `END_LEVEL` 省略時は `HEADING_PREFIX` 先頭の `#` の個数 (例: `### Step 0:` → 3)
   - コードフェンス: 行頭の空白 (スペース・タブ) に続けて ``` で始まる行 (`/^[ \t]*```/`) でフェンス内外を切り替える (`modules/l0-surfaces.md` § AC Enumeration Convention (b) と同じ判定)。フェンスはファイル先頭から追跡し、開始前のフェンス内に見出しと同じ文字列があっても節を開始しない。節の中のフェンス行・フェンス内の行はそのまま出力する。`~~~` フェンスとインデントコードブロックは対象外 (l0-surfaces と同じ)
   - 終了ステータス: 0 = 見出しが見つかった。1 = 見出しが見つからない (出力は空)。2 = `END_LEVEL` 省略かつ `HEADING_PREFIX` が `#` で始まらない (stderr に使い方を出す)。見出しの改名でテストが空の節に対して素通りするのを、`s="$(md_section ...)"` 形式の呼び出しで検出できるようにするため
   - 互換性: bash 3.2+ (`mapfile`・連想配列・`${var,,}` を使わない)。awk は `index` / `match` + `RLENGTH` のみを使い、区間表現 (`{1,4}`) を使わない (mawk 1.3.3 / BWK awk 互換)
   - 先頭コメントに用途・引数・終了ステータス・読み込み方 (`load 'helpers/markdown-section'`) を英語で書く
   - 参照実装 (`/spec` のプロトタイプ。mawk で動作確認済み):
     ```bash
     md_section() {
         local file="$1" prefix="$2" level="${3:-}"
         if [ -z "$level" ]; then
             level="${prefix%%[!#]*}"
             level="${#level}"
         fi
         if [ "$level" -lt 1 ]; then
             echo "md_section: HEADING_PREFIX must start with '#', or pass END_LEVEL" >&2
             return 2
         fi
         awk -v prefix="$prefix" -v level="$level" '
             /^[ \t]*```/ { infence = !infence; if (found) print; next }
             infence { if (found) print; next }
             !found && index($0, prefix) == 1 { found = 1; print; next }
             found {
                 if (match($0, /^#+ /) && RLENGTH - 1 <= level) exit
                 print
             }
             END { if (!found) exit 1 }
         ' "$file"
     }
     ```
2. `tests/markdown-section.bats` を新規作成する (after 1) (→ 受入条件 3, 4)
   - 先頭で `load 'helpers/markdown-section'` を実行する。フィクスチャは各テスト内 (または `setup()`) で `$BATS_TEST_TMPDIR` に heredoc (`<<'EOF'`) で書き出す (既存テストの大半と同じ方式。`tests/fixtures/` は使わない)
   - 必須ケース (`@test` 名は英語、`md_section:` で始める):
     - (a) フェンス内の `## ` / `### ` 行で節が打ち切られず、フェンスの後の本文と次の本物の見出しの直前まで切り出される (#1513 の再現入力。受入条件 3 の中心)
     - (b) 開始見出しより前のフェンス内にある同じ文字列の行では節を開始しない
     - (c) インデントされたフェンス (例: `   ```bash`) 内の `## ` 行でも打ち切られない
     - (d) `END_LEVEL` を渡すと既定の終了レベルを上書きする (例: `## Target` に 3 を渡すと子の `### ` 見出しで止まる / `### X` に 2 を渡すと `## ` まで続く)
     - (e) 既定の終了レベルは開始見出しのレベル (`#### X` は `### ` / `#### ` で止まり、`##### ` では止まらない)
     - (f) 後続の見出しがなければファイル末尾まで切り出す
     - (g) 見出しが見つからないと終了ステータス 1 で出力が空
     - (h) `END_LEVEL` 省略で `#` で始まらない `HEADING_PREFIX` を渡すと終了ステータス 2
     - (i) `HEADING_PREFIX` はリテラル一致 (例: `### 12.3` は先に現れる `### 1243 Other` に一致しない)
   - アサーションは `[ ... ]`、`grep -q`、または `[[ ... ]] || false` で書く (`scripts/check-bare-bracket-assertions.sh` の検出対象を増やさない)
3. `tests/worktree-lifecycle.bats` を置き換える (after 1) (→ 受入条件 2)
   - ファイル内の `section()` 定義とその説明コメントを削除し、`MODULE` などのパス変数定義の近くに `load 'helpers/markdown-section'` を置く
   - `failure_section()` と 10 箇所の `section "$X" "<heading>" <level>` を `md_section` に置き換える。第 3 引数は見出しのレベルと同じなので省略してよい
4. `tests/auto-batch.bats`・`tests/auto-completion-report.bats`・`tests/auto.bats` を置き換える (after 1) (→ 受入条件 2)
   - 各ファイルの先頭 (パス変数定義の直後) に `load 'helpers/markdown-section'` を追加し、ラッパー関数の本体を Notes の対応表のとおり `md_section` 呼び出しにする。ラッパー関数名と引数 (`"$1"` を受ける関数はそのまま) は変えない
   - `tests/auto-batch.bats` の 27 箇所のインライン `run bash -c "awk ... '$SKILL_FILE' | grep ..."` はラッパー関数を使う形に書き換える (`bash -c` の中ではシェル関数を呼べないため)。推奨形: `run grep -q 'X' <<< "$(list_mode_section)"` の後に既存の `[ "$status" -eq 0 ]` を残す。`grep -n` で行番号を比較する 2 テストも同じ形にし、行番号が節内の相対行番号であることを保つ
   - ラッパー関数の説明コメント (「ends at the next level-3 (### Step ) heading」など) を新しい終了条件に合わせて直す
5. `tests/code.bats`・`tests/review.bats`・`tests/verify.bats`・`tests/audit-manual-waiting-count.bats`・`tests/review-rubric-safe.bats`・`tests/orchestration-fallbacks.bats` を置き換える (after 1) (→ 受入条件 2)
   - 手順 4 と同じく `load 'helpers/markdown-section'` を追加し、Notes の対応表のとおり置き換える。`tests/code.bats` の `step10_section()` は 2 回定義されているので両方置き換える (後者の重複定義を削除してもよい)
   - `tests/review-rubric-safe.bats` の 2 箇所は `md_section "$VERIFY_EXECUTOR" "### Rubric Command Semantics" | grep -q "always_allow"` と `md_section "$VERIFY_PATTERNS" "### 9. When to Use" | grep -q "/review"` にする
   - `tests/orchestration-fallbacks.bats` の archive 節抽出は `block=$(md_section "$ARCHIVE" "## $anchor")` にする (見出し行が出力に含まれるようになるが、後続の `grep -q '^### Symptom'` などには影響しない)
6. 置き換えの検証 (after 2, 3, 4, 5) (→ 受入条件 2, 4)
   - 残存チェック: `grep -nE "awk .*(\^##|/\^#)" tests/*.bats` が 0 件、`grep -n "^section()" tests/worktree-lifecycle.bats` が 0 件、`grep -n 'anchor="## ' tests/orchestration-fallbacks.bats` が 0 件
   - 同値性チェック: bats がない環境でも確認できるよう、`.tmp/` に plain bash のハーネスを作り、**`tests/helpers/markdown-section.bash` 自体を `source` して** (関数本体を写さない。#1512 の再現ハーネスがヘルパーの不具合を見逃した教訓)、Notes の対応表の各呼び出しの出力を置き換え前の awk (`git show HEAD:tests/<file>` の定義) の出力と比較する。差分は Notes の「既知の差分」3 件だけであることを確認し、3 件については各テストのアサーション (否定形を含む) が新しい範囲でも成り立つことを確認する
   - bats が使える環境なら `bats tests/markdown-section.bats` と置き換えた 10 ファイルを実行する。使えない場合は PR の CI (`Run bats tests`) で確認する
7. ドキュメントを更新する (parallel with 2–6) (→ ドキュメント整合)
   - `docs/tech.md`: `### BATS Mocking Convention` の直後に `### BATS Markdown Section Extraction` (h3) を追加する。内容: 見出しを起点に Markdown の節を切り出すテストは個別の awk を書かず `tests/helpers/markdown-section.bash` の `md_section` を `load 'helpers/markdown-section'` で読み込んで使うこと、フェンス内の見出し風の行を見出しとして扱わないこと、終了条件 (開始見出しのレベル以下の次の見出し、`END_LEVEL` で上書き可)、見出しが見つからないと終了ステータス 1、導入の経緯 (#1512 / PR #1513 の CI FAIL)
   - `docs/ja/tech.md`: `### BATS モッキング規約` の直後に `### BATS の Markdown 節抽出` (h3) として和訳を追加する。コードフェンス数を英語版と一致させる
   - `docs/structure.md` / `docs/ja/structure.md`: Directory Layout の `tests/` ツリーで `<script-name>.bats` と `fixtures/` の間に `helpers/` の行を追加する (英語版例: `│   ├── helpers/         # Shared bats helpers loaded with load (markdown-section.bash)`)
   - `README.md`: `tests/` の列挙がないことを確認し、変更しない

## Verification

### Pre-merge

- <!-- verify: rubric "tests/ 配下に、Markdown ファイルから見出しを起点に節を切り出す共通ヘルパーが 1 つ置かれ、.bats ファイルから読み込んで使える。このヘルパーはコードフェンス (``` で始まる行で囲まれた範囲) 内の見出し風の行を見出しとして扱わず、節の開始・終了の判定に使わない" --> フェンス対応の節抽出ヘルパーが `tests/` に共通化されている
- <!-- verify: rubric "Background に列挙した 8 ファイル (auto-batch.bats、code.bats、verify.bats、review.bats、auto.bats、review-rubric-safe.bats、audit-manual-waiting-count.bats、auto-completion-report.bats) と tests/worktree-lifecycle.bats の見出しベースの節抽出が、すべて共通ヘルパー経由になっている。見出しの先頭一致で節を切り出すインラインの awk がこれらのファイルに残っていない" --> 既存の節抽出がすべて共通ヘルパーに置き換わっている
- <!-- verify: rubric "共通ヘルパー自体のテストがあり、コードフェンス内に見出し風の行 (## や ### で始まる行) を含む入力で、節がその行で打ち切られず次の本物の見出しまで切り出されることを検証している" --> 共通ヘルパーのテストでフェンス内の見出し風の行を扱うケースを検証している
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)

### Post-merge

なし

## Notes

### 置き換え対応表 (e615db88 時点)

計測範囲: `tests/*.bats` (サブディレクトリなし)。インライン awk の件数は Issue Background と同じ `grep -nE "awk .*(\^##|/\^#)" tests/*.bats` で 8 ファイル 63 箇所 (auto-batch 30 = ラッパー 3 + インライン 27、code 10、verify 8、review 6、auto 5、review-rubric-safe 2、audit-manual-waiting-count 1、auto-completion-report 1)。これに `tests/worktree-lifecycle.bats` の `section()` (定義 1、呼び出し 10) と、上の grep に掛からない複数行 awk 1 箇所 (`tests/orchestration-fallbacks.bats`) を加える。

| ファイル | 置き換え箇所 | 新しい呼び出し (第 3 引数省略 = 見出しのレベル) |
|---------|-------------|------------------------------------------|
| `audit-manual-waiting-count.bats` | `manual_waiting_count_section` | `md_section "$SKILL_FILE" "#### Manual Waiting Count"` |
| `auto-batch.bats` | `list_mode_section` / `count_mode_section` / `until_mode_section` + インライン 27 | `md_section "$SKILL_FILE" "### List mode"` / `"### Count mode"` / `"### Until mode"` |
| `auto-completion-report.bats` | `batch_completion_section` | `md_section "$SKILL_FILE" "### Batch Completion Report" 2` (旧実装は `## ` でのみ終了するため 2 を渡す) |
| `auto.bats` | `step3a` / `step3` / `step2a` / `step2` / `step5` `_section` | `md_section "$1" "### Step 3a:"` / `"### Step 3:"` / `"### Step 2a:"` / `"### Step 2:"` / `"### Step 5:"` |
| `code.bats` | `step0` / `step8` / `step9` / `step10` (×2) / `step11` / `step14` `_section` | `md_section "$1" "### Step N:"` |
| `code.bats` | `followup_issue_section` / `behavioral_change_detection_section` / `new_verification_test_fail_check_section` | `md_section "$1" "#### Follow-up Issue Creation"` / `"#### Behavioral Change Detection"` / `"#### New Verification-Test Pre-implementation FAIL Check"` |
| `review.bats` | 6 関数 | `"## Opportunistic Verification"` / `"## Step 8: Static Acceptance Criteria Verification"` / `"## Step 9: CI Status Check"` / `"## Non-Interactive Mode Behavior"` / `"### 12.3. Lightweight Re-check"` / `"### 12.2. Fix Work"` |
| `verify.bats` | 8 関数 | `"### Step 2: Detect and Update Base Branch"` / `"### Step 5: "` / `"#### Step 8c: "` / `"### Step 6: "` / `"#### Step 8a: "` / `"#### Step 8b: "` / `"### Step 9: "` / `"### Step 1: "` |
| `review-rubric-safe.bats` | インライン 2 | `md_section "$VERIFY_EXECUTOR" "### Rubric Command Semantics"` / `md_section "$VERIFY_PATTERNS" "### 9. When to Use"` |
| `worktree-lifecycle.bats` | `section()` 定義 + 呼び出し 10 | 定義を削除し、同じ引数で `md_section` を呼ぶ |
| `orchestration-fallbacks.bats` | archive 節抽出 (複数行 awk) | `md_section "$ARCHIVE" "## $anchor"` |

### 同値性の事前確認 (プロトタイプ)

`/spec` で参照実装と同じ `md_section` を `.tmp/` に置き、上表の全呼び出し (worktree-lifecycle の 10 呼び出しと archive の 2 アンカーを含む) について、旧 awk の出力と比較した (出所: main e615db88 の作業ツリー、awk は mawk、2026-10-09 実施。ハーネスはコミットしていない)。旧実装で見出し行を除外していた 4 箇所 (`code.bats` の `####` 系 3 関数、`Rubric Command Semantics`) と archive 節は見出し行を含めて比較した。

- 同一: 上記以外のすべて (終了条件の書き方が違う `review.bats` の明示終了見出し、`verify.bats` の `### Step ` 終了、`audit` の `### ` / `#### ` 終了も、現状の SKILL.md では出力が一致した)
- **既知の差分 (3 件)**:
  - `code.bats` Step 11 (155 → 177 行): フェンス内の `### Changes Made` で途中打ち切りになっていたのが直り、節末まで伸びる。アサーションはすべて肯定形 (含むこと) なので影響なし
  - `code.bats` Step 14 (81 → 108 行): フェンス内の `### Changes` で途中打ち切りになっていたのが直る (#1512 の review retrospective で指摘された箇所)。否定形アサーション `$(git rev-parse` を含まないこと (`tests/code.bats` の "Step 14 CI confirmation resolves the pushed head SHA as a separate literal step") は、伸びた範囲にも該当文字列がないことを確認済み。`CI-based bats AC confirmation` と `Implementation Complete comment (patch route, before label transition)` の行順も変わらない
  - `review-rubric-safe.bats` の `### 9. When to Use` (420 → 79 行): 旧実装は awk の範囲指定で次の `## ` (`## Verify Prerequisites`) まで切り出していたが、新実装は節本来の終わり (`### 10.`) で止まる。テスト名どおり「section 9」の範囲になり、`/review` は範囲内に 1 件あるので PASS のまま
- `/code` 実行時点で SKILL.md が変わっている可能性があるため、Implementation Step 6 の同値性チェックで再確認する

### Exclusions (見出しベースの単一節抽出ではないため置き換え対象外)

- `tests/auto.bats` の `notable_judgment_section` / `notable_judgment_jq_command`: 番号付きリスト項目 (`3. **Notable judgment**` 〜 `4. **`) の切り出し
- `tests/spec.bats` (2 箇所)・`tests/auto-xl-concurrency.bats`: 太字ラベル (`**...**`) や `---` を区切りにする切り出し
- `tests/worktree-lifecycle.bats` の Step A〜D 切り出し: 切り出し済みの節テキストを太字ラベルで分割する処理
- `tests/orchestration-fallbacks.bats` の Rationale 検査 (`# Extract each block from ## heading ...` の awk): 全エントリを状態付きで走査する構造検査で、単一節の切り出しではない
- `tests/get-auto-session-report.bats` (4 箇所)・`tests/append-consumed-comments-section.bats` (1 箇所): スクリプトの出力や生成した Spec に対する `sed -n '/A/,/B/p'` / `'/A/,$p'` の範囲抽出。終了位置を明示した見出しや EOF で決めており、「開始見出しのレベル以下の次の見出し」という意味に対応しない
- `tests/auto-batch.bats` の見出し順序検査 (`grep -n '^### List mode\|^### Until mode\|^### Resume mode'`): 節抽出ではない

### Issue 本文との相違 (Conflict with implementation)

- Issue Background は「見出しで節を切り出すインラインの awk が `tests/` の 8 ファイルに約 63 箇所」とする。計測コマンドの結果としては正しいが、1 行の grep に掛からない複数行 awk の単一節抽出が `tests/orchestration-fallbacks.bats` に 1 箇所ある。目的 (個別実装をなくす) と Issue Retrospective の判断 (既存の全箇所を置き換える) に合わせ、置き換え対象に含めた。受入条件 2 の rubric はファイルを列挙しているため変更していない (このファイルには置き換え対象外の構造検査 awk も残るので、受入条件に加えると判定が曖昧になる)
- 「`tests/worktree-lifecycle.bats` の `section()` だけがフェンス対応済み」について: `section()` はフェンスの追跡を節の開始後にしか行わないため、開始見出しより前のフェンス内に同じ文字列があると誤って開始しうる。共通ヘルパーはファイル先頭から追跡する (テストケース (b))

### 設計判断 (Auto-resolved)

- **置き場所と名前**: `tests/helpers/markdown-section.bash` の `md_section`。`bats tests/` は `.bats` だけを再帰なしで実行するので、`tests/helpers/*.bash` はテストとして実行されない。関数名は既存の `section` / `*_section` ラッパーと衝突しないよう `md_section` とした (他候補: bats-core の慣例の `tests/test_helper/`、`tests/lib/`)
- **読み込み方**: `load 'helpers/markdown-section'` (拡張子なし)。bats-core の `load` はテストファイルのディレクトリ (`BATS_TEST_DIRNAME`) からの相対パスで解決し、互換性のため最初に `.bash` を付けた名前を探す (出所: https://bats-core.readthedocs.io/en/stable/writing-tests.html 、2026-10-09 取得)。拡張子付きの指定は古い bats (`.bash` を常に付ける版) で `markdown-section.bash.bash` を探して失敗するため、拡張子なしにした。CI は `ubuntu-latest` の apt 版 bats
- **終了条件の統一**: 旧実装は「同じレベルの見出しだけで終了」「`### Step ` だけで終了」「明示した次の見出しで終了」など箇所ごとに違っていた。新実装は「開始見出しのレベル以下の次の見出し」に統一し、例外は `END_LEVEL` で表す (現状は `auto-completion-report.bats` の 1 箇所だけ 2 を渡す)。プロトタイプで現状の出力が一致することを確認した
- **見出し行は常に出力に含める**: 旧実装の一部は見出し行を除外していたが、該当テストのアサーションは見出し行の有無に依存しないことを確認した (`code.bats` の否定形アサーション `run_in_background` を含まないこと も見出し行に該当文字列はない)
- **見出しが見つからない場合は終了ステータス 1**: 現状の呼び出しで見出しが見つからない箇所はない (プロトタイプで全呼び出しの出力が空でないことを確認)
- **ドキュメント**: テストの規約の SSoT である `docs/tech.md` § Testing Strategy に節を追加し、今後のテストが個別の awk を書かないようにする。`tests/helpers/` は新しいディレクトリなので `docs/structure.md` の Directory Layout に追加する

### その他

- bats テストの入力形式: ヘルパーのテストのフィクスチャは Markdown テキスト。例 (4 連バッククォートは Spec 上の表示用):
  ````markdown
  # Doc

  ```markdown
  ## Target
  fenced copy of the heading (must not start the section)
  ```

  ## Target

  intro line

  ```markdown
  ## Fenced heading
  ### Fenced sub heading
  ```

     ```bash
     ## indented fenced comment
     ```

  ### Child heading
  child body

  ## Next
  after
  ````
  この入力で `md_section "$F" "## Target"` は `## Target` から `child body` の後の空行までを返し、`fenced copy` と `after` を含まない (プロトタイプで確認済み)
- 新規ロジックのテスト要件: 既存ファイルへの分岐追加ではなく新規ヘルパーの追加だが、受入条件 3 のとおり `tests/markdown-section.bats` に (a)〜(i) のケースを追加し、スイートが PASS することを求める。置き換え前の個別 awk に (a) の入力を与えると節が `## Fenced heading` で打ち切られるので、(a) は欠陥の再現入力として検出力を持つ
- ローカルに bats がない環境での確認方法は本 Issue の対象外 (Issue Notes)。Implementation Step 6 の plain bash ハーネスは置き換えの同値性確認のためのもので、bats の代替ではない
- 本 Spec は skills/ や modules/ を変更しないため、`allowed-tools` の追加は不要

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (置き換え対象を既存の全箇所とする判断、ヘルパーのファイル名・置き場所・読み込み方は `/spec` に委ねる判断、ヘルパー自体のテストに欠陥の再現入力を含める判断、Size L と PR ルートの根拠、bats がない環境の確認方法を対象外とする判断の記録。`/spec` への追加要求はなし) / https://github.com/saitoco/wholework/issues/1514#issuecomment-6075277926

## issue retrospective

### 判断の記録

- **置き換え対象は既存の全箇所とした (`tests/worktree-lifecycle.bats` の `section()` を含む 9 ファイル)** — 理由: 目的が「個別実装による同種の失敗を防ぐ」ことなので、一部だけ共通化すると個別実装が残り、目的を満たさない。2026-10-09 時点の計測値 (8 ファイル・約 63 箇所) を Background に残し、AC はそのファイル一覧で判定できるようにした
- **共通ヘルパーのファイル名・置き場所・読み込み方は AC で固定しなかった** — 理由: 実装方式は `/spec` が決める。AC は「`tests/` 配下に 1 つ」「`.bats` から読み込める」「フェンス内の見出し風の行を見出しとして扱わない」という振る舞いだけを `rubric` で問う
- **共通ヘルパー自体のテストの AC に、欠陥を再現する入力 (フェンス内の `## ` 行) を明記した** — 理由: 再現入力のないテストは検出力を持たない (#1130 の前例)。今回の CI 失敗と同じ形の入力で節が打ち切られないことを問う
- **Size は L とした** — 変更ファイルは 9 + 共通ヘルパー + そのテストで約 11。機械的な置き換えなので複雑度で 1 段下げた。テストの共有構造の変更にあたるため、PR ルート (M 以上) は必須
- **Post-merge の AC は置かなかった** — 結果は CI の bats テストと Pre-merge の `rubric` で判定できる
- ローカルに bats がない環境での確認方法は対象外とし、Notes に明記した (必要なら別 Issue)

## spec retrospective

### Minor observations

- Issue Background の計測コマンド (`grep -nE "awk .*(\^##|/\^#)"`) は 1 行の awk しか拾わず、`awk -v anchor=... '` で始まる複数行 awk (`tests/orchestration-fallbacks.bats`) を取りこぼした。件数の計測を grep 1 本に頼ると、書き方の違う同種実装が漏れる
- 旧実装の終了条件は箇所ごとにばらばらで (同じレベルのみ / `### Step ` のみ / 明示した次の見出し / `## ` のみ)、文面だけでは統一後の挙動差を判断できなかった。プロトタイプで全呼び出しの出力を新旧比較したことで、差分が 3 件に限られ、すべてアサーションに影響しないことを Spec 段階で確定できた
- 作業環境の awk は mawk。プロトタイプを mawk で動かしたので、区間表現を使わない設計の互換性もあわせて確認できた

### Judgment rationale

- `tests/orchestration-fallbacks.bats` の 1 箇所は置き換え対象に含めたが、受入条件 2 の rubric には加えなかった。同じファイルに置き換え対象外の構造検査 awk (全エントリ走査) が残るため、ファイルを列挙に加えると「インラインの awk が残っていない」の判定が曖昧になる
- ヘルパーは見出しが見つからないとき終了ステータス 1 を返す設計にした。見出しの改名でテストが空の節に対して素通りする (否定形アサーションが常に PASS する) 弱点を、`s="$(md_section ...)"` 形式の呼び出しで検出できる。現状の全呼び出しで見出しが見つかることを確認したので、既存テストは壊れない
- `load` は拡張子なしの形を選んだ。bats-core の文書は拡張子付きの指定を推奨するが、古い bats は `.bash` を常に付けるため、拡張子付きだと読み込みに失敗する
- `### 9. When to Use` の節は旧実装より狭くなる (次の `## ` → 次の `### `) が、テスト名の意図 (section 9) に合うので `END_LEVEL` で旧範囲を再現しなかった

### Uncertainty resolution

- bats `load` のパス解決と拡張子の扱い: 公式文書で確認した (テストファイルのディレクトリ基準、`.bash` 付きの名前を先に探す)。`bats tests/` が `.bats` だけを再帰なしで実行するため、`tests/helpers/*.bash` はテストとして実行されない
- 置き換えによる判定の変化: プロトタイプの新旧比較で解消 (Notes「同値性の事前確認」)。`/code` 時点で SKILL.md が変わっている可能性に備え、Implementation Step 6 で同じ比較を実ヘルパーを `source` するハーネスで再実行する
- 新規ロジックのテスト要件: `tests/markdown-section.bats` に (a)〜(i) の 9 ケース (フェンス内の `## ` / `### ` で打ち切られない、開始前のフェンス内の同名行で開始しない、インデントされたフェンス、`END_LEVEL` 上書き、既定の終了レベル、EOF まで、見出しなしで 1、`#` なし prefix で 2、リテラル一致) を追加し、スイートが PASS すること

## Code Retrospective

### Deviations from Design

- `tests/markdown-section.bats` の否定アサーションは、Spec の想定にあった `! echo ... | grep -q` ではなく、ファイル内の補助関数 `refute_output_has` で書いた。bats は否定パイプラインを失敗として扱わないため、`!` 形式だと「含まないこと」の検証が常に PASS してしまう
- `tests/auto-completion-report.bats` を含め、旧実装のコメントにあった終了条件の説明を新しい終了条件 (開始見出しのレベル以下の次の見出し) に合わせて直した。Spec の対応表にはコメント修正の記載がなかったが、手順 4 の「説明コメントを直す」を全ファイルに適用した
- `tests/code.bats` の重複定義 `step10_section()` は、後者を削除して前者を共有した (手順 5 が許容していた対応)

### Design Gaps/Ambiguities

- Spec のテストケース (c) 「インデントされたフェンス内の `## ` 行」は、フィクスチャの `## ` 行までインデントしていると、フェンス処理がなくても見出しとして扱われないため検出力がなかった。フェンス内の行を行頭から書く形に直し、フェンス判定を外した変異版で 3 件 (a / b / c) が FAIL することを確認した
- 作業環境に bats も GNU parallel もなかった。bats-core v1.11.1 を `/tmp` に取得して実行し、`--jobs` が使えないため全 135 ファイルを 4 つに分けた直列実行で全件 PASS を確認した (`modules/test-runner.md` の `--jobs` 不可時の分割実行に従った)
- ワークツリーの隔離ガード (`worktree isolation guard`) が、glob を含む `bats` の引数や `&` による並列起動を「git でないと示せない」として拒否した。リテラルのファイル名を並べた単純なコマンドに分けて回避した

### Rework

- 変異テストでテストケース (c) の検出力不足に気づき、フィクスチャを 1 回直した。それ以外のやり直しはない
- 置き換え前後の同値性チェック (plain bash ハーネスが実ヘルパーを `source`) の結果は、33 呼び出し中 31 件が同一、差分は Spec の想定どおり 3 件 (code Step 11 / Step 14、`review-rubric-safe` の section 9。ハーネスの対象外だった `review-rubric-safe` と `worktree-lifecycle` は bats の実行結果で確認)。bats が使えたため、各テストのアサーションが新しい範囲でも PASS することを実行で確認できた

## review retrospective

### Spec vs. 実装の乖離パターン

- 構造的な乖離はなかった。変更ファイル 17 件は Spec の Changed Files と一致し、残存チェック (インライン awk と `section()` の残り) も 0 件だった
- 唯一の SHOULD は Spec のテストケース (d) の後半。`### Child` に END_LEVEL 2 を渡すケースが、同レベルの兄弟見出しのないフィクスチャだったため既定値と区別できなかった。兄弟見出しを足して修正済み

### 繰り返し出た指摘

- 否定アサーションだけのテストで、見出しの改名が空の節に対して素通りする点を review-spec と review-bug の両方が指摘した。ヘルパーの狙い (見出し未検出で exit 1) が、`run xxx_section` + `[[ "$output" != ... ]]` や `<<< "$(...)"` の呼び出し形では活きない。旧実装も素通りで退行ではないため本 PR では直さず、`s="$(md_section ...)"` で受ける形への統一を follow-up の候補とする

### 受け入れ条件の検証の難しさ

- UNCERTAIN は 0 件。AC 1〜3 は rubric、AC 4 は `github_check` で、CI が両トリガーで pass していたため判定に迷いはなかった
- review-bug 系のサブエージェントは、ワークツリーの隔離ガードが `source` と `bash -c` を拒否したため、ヘルパーの awk 本体を直接渡して同値性を比較した。実ヘルパーを `source` する計測はオーケストレーター側のスクリプトファイル経由でのみ可能だった

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- SHOULD 1 件 (END_LEVEL 上書きテストの検出力) は修正し、CONSIDER 5 件は本 PR の範囲外としてスキップした (ヘルパーの誤用耐性と、否定アサーションの素通り)
- Workflow 経路は再起動保証のない実行面のため使わず、静的な Task fan-out を前景で実行した

### Deferred Items

- 数値でない END_LEVEL の検証、FILE 不在時の終了ステータス (awk の exit 2 と文書上の exit 2 の衝突)、`awk -v` のバックスラッシュ解釈は、ヘルパーの堅牢化として別 Issue 候補
- 否定アサーションのテストを `s="$(md_section ...)"` で受ける形に統一する案も別 Issue 候補

### Notes for Next Phase

- 検出された MUST はなく、CI も全件 SUCCESS。`/merge 1515` に進める
- Issue #1514 の AC はすべて `[x]` (AC 4 は本レビューで更新)。Post-merge 条件はなし
