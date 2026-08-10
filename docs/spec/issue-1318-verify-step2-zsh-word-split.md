# Issue #1318: verify: Step 2 の PR 候補ループが zsh の単語分割仕様で機能せず pr route を patch route と誤判定

## Overview

`skills/verify/SKILL.md` Step 2 の PR 候補検証ループ (`for candidate in $CANDIDATE_PRS; do ... done`) が、実行シェルが zsh のときに機能しない。zsh は非引用符スカラー変数展開で単語分割を行わないため (bash との既知の非互換)、`$CANDIDATE_PRS` が複数行のとき for ループは 1 回だけ実行され、全候補を連結した文字列が `gh-extract-issue-from-pr.sh` に渡ってしまう。結果として `PR_NUMBER` が空のまま残り、pr route の Issue が patch route として誤判定される。ループを `while IFS= read -r` + here-string 形式へ書き換え、同型の再発を `scripts/validate-skill-syntax.py` の機械検査で防止する。

## Reproduction Steps

1. zsh 環境 (`$0=/bin/zsh`, `ZSH_VERSION=5.9`, `BASH_VERSION` 未設定) で `/verify 1285` を実行する。
2. `gh pr list --search "closes #1285" --state merged --json number --jq '.[].number' | head -10` が候補 2 件 (`1111`, `1306`, 改行区切り) を返す。
3. `CANDIDATE_PRS` は非引用符のまま `for candidate in $CANDIDATE_PRS; do ... done` に渡される。
4. zsh は非引用符スカラー展開で単語分割を行わないため、ループは 1 回だけ実行され `candidate` に `"1111\n1306"` (2 行連結) が入る。
5. `${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh "1111\n1306"` の引数検証 (`[[ "$PR_NUMBER" =~ ^[0-9]+$ ]]`) が失敗し、`Error: PR number must be a positive integer: 1111\n1306` を出力する。
6. ループ内の `if` 分岐に到達しないため `break` が実行されず、`PR_NUMBER` は空のまま残る。実際は #1306 が `closes #1285` を持つ正しい PR だった。
7. 後続処理で `/verify` が patch route と誤判定し、`github_check "gh pr checks"` 系 AC が誤って UNCERTAIN になる、`reconcile-phase-state.sh review --pr "$PR_NUMBER"` に空値が渡る、`BASE_BRANCH` が実際の base ではなく既定の `main` にフォールバックする、という 3 つの影響が連鎖する。

## Root Cause

zsh は既定で非引用符スカラー変数展開に対して単語分割を行わない (bash との既知の非互換。zsh のネイティブモードでは `SH_WORD_SPLIT` が既定で off)。`for candidate in $CANDIDATE_PRS` は `$CANDIDATE_PRS` の値が改行 (IFS に含まれる) で単語分割されて 1 候補ずつループすることに依存した実装だった。bash ではこの前提が成立するが、zsh では非引用符展開が改行を含んでいても 1 語として扱われるため、`gh pr list` が返す merged PR 候補が 2 件以上のとき for ループは常に 1 回しか回らず、`candidate` に全候補が連結された文字列が入る。これは Wholework の SKILL.md に潜む「bash 前提スニペットが zsh で機能しない」失敗モードの 3 例目であり、先行 2 例 (#891、および `docs/sessions/46196-1785292524-2026-07-31/session.md` に記録された対応) はいずれもその場限りの修正に留まり、再発防止の構造的対策が入っていなかった。

## Changed Files

- `skills/verify/SKILL.md`: change — Step 2 の PR 候補検証ループを `for candidate in $CANDIDATE_PRS; do ... done` 形式から、`if [ -n "$CANDIDATE_PRS" ]; then` で候補ゼロ件時の安全性を保ったうえで `while IFS= read -r candidate; do ... done <<< "$CANDIDATE_PRS"` 形式へ書き換える
- `scripts/validate-skill-syntax.py`: change — `UNQUOTED_WORD_SPLIT_FOR_PATTERN` 正規表現と `validate_unquoted_word_split_loops()` 関数を追加。bash コードフェンス内の `for VAR in $SCALAR` / `for VAR in ${SCALAR}` 形式 (非引用符スカラー展開のみ、配列展開・引用符付き形式は構造的に対象外) を検出する。`validate_skill()` から呼び出して `skills/*/SKILL.md` を対象にする (現行 CI 呼び出しと同じ範囲) ほか、`main()` の既存 `modules_dir` 解決を再利用して `modules/*.md` も対象にする (`.github/workflows/test.yml` の変更は不要)
- `tests/validate-skill-syntax.bats`: change — 新規検査に対する bats テストを追加する (エラーケース: `for candidate in $CANDIDATE_PRS` 形式のフィクスチャが `unquoted_word_split` を含むエラーで拒否される、成功ケース: 書き換え後の `while IFS= read -r` 形式が PASS する、modules ケース: `modules/*.md` フィクスチャも同様に拒否される)

## Implementation Steps

1. `skills/verify/SKILL.md` Step 2 の PR 候補検証ループ (2 つ並んだ bash ブロックのうち後者、`PR_NUMBER=""` / `BASE_BRANCH=""` から始まり、直後の "If no candidate's issue_number matches ..." 段落の直前まで) を以下の形式へ書き換える。直前の `CANDIDATE_PRS=$(gh pr list ...)` ブロックは変更しない。(→ 受入条件 1)

   ```bash
   PR_NUMBER=""
   BASE_BRANCH=""
   if [ -n "$CANDIDATE_PRS" ]; then
     while IFS= read -r candidate; do
       EXTRACT_RESULT=$(${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh "$candidate")
       CANDIDATE_ISSUE=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('issue_number',''))")
       if [ "$CANDIDATE_ISSUE" = "$ISSUE_NUMBER" ]; then
         PR_NUMBER="$candidate"
         BASE_BRANCH=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('base_ref','main'))")
         break
       fi
     done <<< "$CANDIDATE_PRS"
   fi
   ```

2. `scripts/validate-skill-syntax.py` に検査ロジックを追加する (after 1) (→ 受入条件 2): 既存の `BASH_CODEBLOCK_PATTERN` 付近に `UNQUOTED_WORD_SPLIT_FOR_PATTERN = re.compile(r'\bfor\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?(?![A-Za-z0-9_])')` を定義する。既存 `validate_bash_safety()` と同じ構造 (bash ブロックを走査、`#` 始まり行はスキップ、同じ行番号計算) で `validate_unquoted_word_split_loops(content: str) -> List[str]` を実装し、マッチごとに文字列 `unquoted_word_split` を含むエラーメッセージ (該当するループ変数・元変数名を明示し、`while IFS= read -r VAR; do ... done <<< "$SOURCE"` への書き換えを推奨) を返す。`validate_skill()` から呼び出して `skills/*/SKILL.md` を対象にする (既存 `validate_bash_safety(content)` 呼び出しの近く)。加えて `main()` の既存 `validate_modules_scripts_in_allowed_tools()` クロスファイル検証ブロック直後で `modules_dir.glob('*.md')` を走査して同じ検査を直接呼び出す (frontmatter を前提とする `validate_skill()` のパイプラインは経由しない) — 出力は既存の `📄 {path}` / `❌ Error: {message}` 形式に合わせ、`total_errors` に加算する。

3. `tests/validate-skill-syntax.bats` に bats テストを追加する (after 2) (→ 受入条件 2, 3): (a) bash ブロック内に `for candidate in $CANDIDATE_PRS` を含むフィクスチャが `unquoted_word_split` を含む出力で拒否されることを確認するエラーケース、(b) 書き換え後の `while IFS= read -r candidate; do ... done <<< "$CANDIDATE_PRS"` 形式が `0 error` で通過することを確認する成功ケース、(c) 既存の `create_include` ヘルパーで `modules/*.md` に同型のパターンを含むフィクスチャを作成し、`skills/` パス引数で実行した際に `main()` の modules 走査で拒否されることを確認するケース。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md Step 2 の PR 候補検証ループが、zsh でも各候補を 1 件ずつ処理する形式 (例: while IFS= read -r candidate; do ... done <<< \"$CANDIDATE_PRS\"、または gh pr list の出力を直接 pipe して read する形式) になっており、for ループへの非引用符スカラー展開による単語分割に依存していない" --> skills/verify/SKILL.md Step 2 の PR 候補検証ループが、非引用符スカラー変数の単語分割に依存しない形式へ書き換えられている
- <!-- verify: grep "unquoted_word_split" "scripts/validate-skill-syntax.py" --> scripts/validate-skill-syntax.py が SKILL.md / modules 内の単語分割依存 for ループを検出する検査を持つ
- <!-- verify: grep "unquoted_word_split" "tests/validate-skill-syntax.bats" --> 上記検査の bats テストが追加されている

### Post-merge

- merged PR 候補が 2 件以上返る Issue の `/verify` 実行で、`closes #N` を実際に持つ PR が正しく `PR_NUMBER` に解決されることを確認する

## Notes

### 検査の適用範囲について (Issue Notes から本 Spec に委譲された決定)

Issue 本文の Notes セクションが本 Spec に委譲した 2 つの粒度判断:

1. **非引用符スカラー変数のみを対象とする**: 検査対象は `for IDENT in ` 直後の非引用符スカラー展開 (`$VAR` / `${VAR}`) のみ。コマンド置換 (`for x in $(cmd)`)、引用符付き形式 (`for x in "$VAR"`)、配列展開 (`for x in "${arr[@]}"`) は正規表現の構造上 (`$`/`${` の直後に識別子開始文字を要求するため、引用符や `(` はマッチしない) 除外される。これは Issue 本文が問題を「非引用符変数の単語分割依存」と定義していることと整合し、誤検出リスクを抑える。
2. **bash コードブロック内に限定する**: 検査は bash フェンス内のみを走査する。既存の `validate_bash_safety()` と同じスコープ設計であり、シェル動作を説明する地の文 (本 Spec ファイル自身や、SKILL.md 中で "for X in $Y" 的な語句に言及する段落など) を誤検出しない。

`rg -P` で同等の PCRE パターンを `skills/`・`modules/`・`agents/` に対して実測し、現状の唯一の該当箇所 (`skills/verify/SKILL.md:104`) のみにマッチし誤検出がないことを確認済み。

### CI 引数変更なしで modules/ をカバーする

AC2 は「SKILL.md / modules 内の」検査を要求している。`scripts/validate-skill-syntax.py` の `main()` は `skills/` を引数に呼ばれた場合 (現行の `.github/workflows/test.yml` の呼び出し方) に既に `modules_dir` を解決しており、既存の `validate_modules_scripts_in_allowed_tools()` クロスファイル検証で使用している。新規検査もこの同じ `modules_dir` を再利用するため、AC2 の modules カバレッジを満たすのに CI ワークフローの変更は不要。

### agents/ はスコープ外

Issue 本文自身の調査用 grep (`grep -rnE 'for [a-zA-Z_]+ in [$]' skills/ modules/ agents/`) は `agents/` も走査対象に含めていたが、AC の文言は「SKILL.md / modules」のみをスコープとしている。同 grep の結果が示す通り `agents/` に現状該当箇所はなく、本 Issue では意図的に対象外とする。再発が見つかった場合はフォローアップで対応する。

### 再発防止としての位置づけ

本件は同一失敗モード (zsh 非互換な bash 前提スニペット) の 3 例目である (Issue 本文の一覧表参照)。先行 2 例 (#891 はその場修正のみ、`docs/sessions/46196-1785292524-2026-07-31/session.md` に記録された 2 例目も同様) と異なり、本 Issue では CI で機械的に強制される検査を追加するため、4 例目が発生した場合は発見・修正サイクルを人手に頼らず自動的に捕捉できる。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 追加確認不要と判断 (検査範囲は Issue 本文 Notes で既に /spec へ委譲済み)、Type=Bug/Size=M/Value=3 設定、post-merge AC に session=next 追加 / https://github.com/saitoco/wholework/issues/1318#issuecomment-5235678768
