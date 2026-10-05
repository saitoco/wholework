# Issue #1510: docs: structure.md のファイル数コメントのずれを機械的に検出する

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (方針 a/b の選択と件数の数え方を /spec に委ねる旨の記録。新規の指示なし) / https://github.com/saitoco/wholework/issues/1510#issuecomment-5987625945

## Overview

`docs/structure.md` の Directory Layout は、`modules/` `agents/` `scripts/` `tests/` の 4 ディレクトリについてファイル数を静的なコメントで持っている。ファイルを追加・削除するたびに手で直す必要があり、直し忘れによるずれが繰り返し起きている (#1280、#1403、2026-10-03 の `/doc sync --deep`、#1504)。Issue は、方針 a (実ファイル数との照合チェックを CI と `/code` の事前チェックに追加する) と方針 b (件数コメント自体を廃止する) のどちらを採るかを `/spec` に委ねている。

**採用方針: b (件数コメントを廃止する)。** 件数は実ディレクトリから導ける派生情報であり、共有ファイルの 1 行に静的に書く限り、手作業の規定を守っても並行 PR で黙って失われる。ずれを「早く見つける」(a) より、ずれうる情報を持たない (b) ほうが、Purpose の「手作業の規定に頼らずに防ぐ」を満たす。根拠と不採用理由の詳細は Notes の「方針判断」を参照。

変更内容:

- `docs/structure.md` の Directory Layout から 4 箇所の件数コメントを削除する
- Key Files の Maintenance rule のうち、件数コメントの更新を求める段落を、件数コメントを置かない方針と理由の記述に置き換える
- 件数コメントを前提にした周辺記述 (`docs/versioning.md` の Gate 4 チェック、`modules/verify-patterns.md` の例示) と、対応する JA ミラーを整合させる

## Changed Files

- `docs/structure.md`: Directory Layout の 4 行 (`modules/` `agents/` `scripts/` `tests/`) から件数コメントを削除する。Key Files の Maintenance rule の第 2 段落 (件数コメントの更新指示) を、件数コメントを置かない方針と理由を述べる記述に置き換える
- `docs/ja/structure.md`: 上記の日本語ミラー (`docs/translation-workflow.md` の Sync Procedure に従う。SHOULD レベルで、Issue の受入条件の対象外)
- `docs/versioning.md`: Gate 4 のチェック (a) (structure.md の件数が実数と一致) を削除し、残るチェックの記号と件数表記 ("four checks") を振り直す
- `docs/ja/versioning.md`: 上記の日本語ミラー (SHOULD レベル)
- `modules/verify-patterns.md`: § "Literal Numeric Pinning ACs — Concurrent PR Resilience" の例示と Scope が、廃止済みの件数コメントを指すことを追記して整合させる (SHOULD レベル。英語のみで、日本語を含めない)
- [Steering Docs sync candidate] keyword "verify-patterns.md" skipped: matched 165 files (no discriminating power)
- [Steering Docs sync candidate] keyword "Literal Numeric Pinning" (編集する § の見出し): `docs/` `tests/` `scripts/` `modules/` で Spec 以外のヒットは 3 件 (`docs/structure.md`、`docs/ja/structure.md`、`modules/verify-patterns.md`) で、いずれも上記 Changed Files に含まれる

## Implementation Steps

1. `docs/structure.md` を編集する (→ AC1, AC2)
   - Directory Layout の次の 4 行から件数コメントを削除する (行内の他の説明文は変えない):
     - `modules/` 行: 末尾の ` (46 files)` を削除する
     - `agents/` 行: 末尾の ` (8 files)` を削除する
     - `scripts/` 行: 末尾の ` (97 files)` を削除する
     - `tests/` 行: 末尾の ` (133 files)` を削除する
   - Key Files の Maintenance rule のうち、`> When adding or removing a file in` で始まる第 2 段落の全体を、次の文面に置き換える (第 1 段落は変更しない)。`(N files)` 形式の文字列は例示としても残さない (AC2 の確認で、規定文中の例示が件数コメントと誤認されないようにするため):

     > The Directory Layout section deliberately carries no file-count comments. A count is derived information: it drifts each time a file is added or removed (recurring drift: #1280, #1403, #1504), and a literal count on a shared line is lost silently when concurrent PRs each bump it (see `modules/verify-patterns.md` § "Literal Numeric Pinning ACs — Concurrent PR Resilience"). Do not add counts back — describe each directory by its role. When a verify command needs a file count, compare against the live directory (for example `find <dir> -maxdepth 1 -type f | wc -l`) rather than a number written in a document.

2. `docs/ja/structure.md` を 1 に合わせて更新する (after 1) (→ 翻訳同期。SHOULD レベル)
   - Directory Layout の 4 行 (`modules/` `agents/` `scripts/` `tests/`) から ` (N ファイル)` を削除する
   - 主要ファイルセクションの「メンテナンスルール」のうち、`> \`modules/\` または \`scripts/\` にファイルを追加・削除する場合は` で始まる第 2 段落の全体を、次の文面に置き換える (第 1 段落は変更しない):

     > Directory Layout セクションには、意図的にファイル数コメントを置かない。件数は派生情報であり、ファイルを追加・削除するたびにずれる (繰り返し発生したずれ: #1280, #1403, #1504)。また、共有行に書かれた件数リテラルは、並行 PR がそれぞれ加算すると黙って失われる (`modules/verify-patterns.md` § "Literal Numeric Pinning ACs — Concurrent PR Resilience" を参照)。件数を書き戻さず、各ディレクトリは役割で説明すること。verify command でファイル数が必要な場合は、文書に書かれた数値ではなく実ディレクトリとの比較 (例: `find <dir> -maxdepth 1 -type f | wc -l`) を使うこと。

3. `docs/versioning.md` と `docs/ja/versioning.md` の Gate 4 を更新する (parallel with 1) (→ 件数コメント廃止に伴う整合。SHOULD レベル)
   - `docs/versioning.md`: Gate 表の行 4 の `See the four checks below` を `See the three checks below` に変える。`**Gate 4 — documentation drift checks:**` 直下のコードブロックから、`# a. structure.md file counts match reality (EN and JA)` で始まる 3 行 (コメント、`ls scripts/ | wc -l ; ...`、`grep -E '\([0-9]+ files\)' docs/structure.md`) と直後の空行を削除し、残るチェックの記号を `# b.` → `# a.`、`# c.` → `# b.`、`# d.` → `# c.` に振り直す
   - `docs/ja/versioning.md`: Gate 表の行 4 の `下記 4 項目を参照` を `下記 3 項目を参照` に変える。コードブロックから `# a. structure.md のファイルカウントが実数と一致 (英日とも)` で始まる 3 行と直後の空行を削除し、同様に記号を a-c に振り直す
   - コードフェンスの数 (開き・閉じ) は EN と JA で一致したまま変えない (`docs/translation-workflow.md` の Sync Procedure 5)

4. `modules/verify-patterns.md` の § "Literal Numeric Pinning ACs — Concurrent PR Resilience" を整合させる (parallel with 1) (→ 件数コメント廃止に伴う整合。SHOULD レベル)
   - 「Recommended pattern」のコードブロックの直後 (`Use \`-E\`/\`-o\` for extraction` で始まる段落の直前) に、次の 1 文を段落として追加する:

     The example above names the `docs/structure.md` script-count comment as it existed when this section was written; that comment was removed in #1510, so substitute the document and anchor text of whichever hand-maintained count the acceptance condition actually pins.

   - `**Scope**:` 段落の `this pattern generalizes beyond \`docs/structure.md\`'s \`(N files)\` comment to` を `this pattern generalizes beyond the former \`docs/structure.md\` \`(N files)\` comment (removed in #1510) to` に変える
   - 追記は英語のみにする (`scripts/check-language-convention.py` の対象は `modules/` を含むため、CJK 文字を入れない)

5. 確認する (after 1-4) (→ AC1, AC2, AC3)
   - `grep -nE '\([0-9]+ files?\)' docs/structure.md` の出力が空であること
   - `grep -nE '\([0-9]+ ファイル\)|（[0-9]+ ファイル）' docs/ja/structure.md` の出力が空であること
   - `grep -n "file counts match" docs/versioning.md` と `grep -n "ファイルカウントが実数と一致" docs/ja/versioning.md` の出力が空であること
   - `bash scripts/check-forbidden-expressions.sh` が成功すること (Spec ファイルも走査対象)
   - 既存の bats スイートはスクリプトもテストも変更しないため、結果は変わらない。CI の `Test` workflow の成功は AC3 で確認する

## Verification

### Pre-merge

- <!-- verify: rubric "docs/structure.md の Directory Layout のファイル数コメントについて、(a) 実ファイル数との照合を CI で機械的に検出する仕組みが追加されている、または (b) ずれうる静的な件数コメントが廃止されている、のいずれかが実装されており、docs/structure.md の『ファイル追加・削除時は件数コメントも更新する』旨の手作業規定が実装に合わせて更新されている" --> 件数コメントのずれが機械的に検出されるか、件数コメント自体が廃止されている
- <!-- verify: rubric "方針 a を採った場合、件数がずれた docs/structure.md に対してチェックが非ゼロで終了することを検証する bats テストがある。方針 b を採った場合、docs/structure.md の Directory Layout に (N files) 形式の件数コメントが残っていない" --> 採用した方針が検証されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> 全 bats テストが PASS する (CI の `Run bats tests` ジョブ)

### Post-merge

なし

## Notes

### 方針判断 (a / b の選択。非対話モードの自動解決として記録)

**採用: b (件数コメントを廃止する)**。

- **並行 PR で構造的に衝突する**: `modules/verify-patterns.md` § "Literal Numeric Pinning ACs — Concurrent PR Resilience" が、共有行の件数リテラルは並行 PR が独立に +1 すると git が非競合マージして片方の加算を黙って失うことを文書化している (#1047 と #1119 の 2 件)。同節は「並行 PR が開いている間は、`/review` (safe mode) から兄弟 PR の未マージ変更を観測できないため、PR 時点では検出できない」と述べている。方針 a の CI チェックも `/code` の事前チェックも PR ブランチ上で動くため同じ制約を受け、衝突は merge 後の main でしか見えない。a は「ずれを早く見つける」ことはできても、「防ぐ」ことにはならず、main の CI が赤くなって件数だけを直す追従コミットが発生する
- **手作業の総量**: `docs/spec` 配下で件数コメントの運用 (`ファイル数コメント|件数コメント|file count comment|file-count comment|ファイルカウント` で grep) に言及する Spec が 47 件ある。件数の更新は EN と JA の両方に及ぶ。b は、この更新作業と、`/spec` Step 10 の Steering Docs sync candidate 判定での「件数コメントの再確認」を不要にする
- **情報価値が低い**: 件数は規模感を示すだけで、Key Files が実在ファイルを列挙しているため、読み手の判断に必要な情報ではない

**不採用: a (照合チェックスクリプト + CI + `/code` 事前チェック)**。

- 追加物が多い: 新規スクリプト、bats テスト、`test.yml` の CI ジョブ、`/code` の事前チェック手順 (SKILL.md 本文と `allowed-tools` の追記)、Key Files / CI 概要の追従
- 件数の手更新自体は残る (検出されるだけで、直す作業は変わらない)
- 数え方 (直下のみ / 再帰) の決め直しが要る
- 先行事例 #1434 が退けた「件数コメントの廃止 + CI 自動生成」とは別物。#1434 の却下理由は新規 CI ジョブの追加が Size S に対して過大だったことで、CI 自動生成を伴わない単純な廃止である b には当てはまらない

**回帰防止**: 件数コメントの再導入を検出する機械的ガードは追加しない。ガード自体が新たな保守対象になるうえ、`skills/doc/structure-template.md` に件数コメントの生成指示がなく、再導入の経路は人手のみである。再導入を禁じる記述を Maintenance rule に明記することで足りると判断した。必要になれば別 Issue で扱う。

### 件数の数え方 (参考。方針 b では決め直さない)

Issue が `/spec` に委ねた「件数の数え方」は、方針 b では件数コメントが存在しなくなるため決め直さない。参考として 2026-10-05 時点の実測値を記録する。測定は `find <dir> -maxdepth 1 -type f | wc -l` (対象は各ディレクトリ直下の通常ファイルのみ):

- `modules/` 46 件、`agents/` 8 件、`scripts/` 97 件 (`.sh` 94 + `.py` 3)、`tests/` 133 件 (すべて `.bats`)
- 数えていないサブディレクトリ: `scripts/git-hooks/`、`tests/fixtures/`
- ドット始まりのファイルとシンボリックリンクは、これら 4 ディレクトリの直下に存在しない
- 上記はいずれも、変更前の `docs/structure.md` の件数コメントと一致していた

### Size 再評価と patch route 化

- Changed Files は 5 件。Axis 1 は M (3-5 件)
- 変更は docs と説明文のみ (`modules/verify-patterns.md` は説明の追記で、挙動は変わらない) のため、Axis 2 で 1 段階下げて S
- CI Dependency Minimum Override に該当するファイル (CI workflow、tests、CI 環境依存の検証) は含まれない
- 結果、triage 時点の M から S (patch route) に変わる。Step 18 で Size を更新する
- patch route では PR が存在しないため、AC3 の `github_check "gh pr checks" "Run bats tests"` を `gh run list` 形式 (`expected_value` は job 名から `success` へ) に変換し、Issue 本文にも反映した (`/spec` Step 10 の Patch route verify command check)。`.github/workflows/` には複数の workflow ファイルがあるため `--workflow=test.yml` を付け、main の push 後の run を見るため `--branch=main` を付けた (`modules/verify-classifier.md` § "Patch Route CI Verification Note" の形式)

### 変更不要と判断したファイル (grep で確認済み)

- `skills/spec/SKILL.md` (Listing-side sub-check の説明と例): 件数コメントを「列挙する文書の一例」として挙げる汎用ガイダンスで、件数コメントを持つ下流リポジトリにも適用される。この repo の件数コメント廃止では無効にならないため変更しない (配布物の汎用文面を repo 固有の事情で変えない)
- `README.md`、`README.ja.md`、`docs/guide/*`、`docs/tech.md`、`docs/workflow.md`: 件数記述なし。`grep -rnE '\([0-9]+ files?\)'` の Spec 以外のヒットは `docs/structure.md` と `docs/reports/external-kill-investigation.md` (無関係な件数) のみ
- `skills/doc/structure-template.md`: 件数コメントを生成する指示なし (`/doc sync structure` が再導入しない)
- `tests/*.bats`、`scripts/*.sh`、`.github/workflows/*.yml`: `docs/structure.md` の件数記述や `Literal Numeric Pinning` の文面を参照する箇所なし (`grep -rnE '94 files|Literal Numeric|Utility scripts used' tests` が 0 件。`docs/versioning.md` を参照するテスト・スクリプトもなし)
- `docs/translation-workflow.md` が `docs/{lang}/` を実装対象外とする `modules/doc-checker.md` と食い違って見える点は、前者が JA ミラーの同期義務を定め、後者が影響範囲の判定から翻訳出力を除外しているだけで、両立する。本 Spec は前者に従い JA ミラーを Changed Files に入れた

### 実施した調査チェックの結果

- Steering Docs sync candidate check (inbound): `modules/verify-patterns.md` が Changed Files に入るため実施。キーワード `verify-patterns.md` は 165 件ヒットで識別力なしのためスキップ。見出し `Literal Numeric Pinning` は Spec 以外で 3 件、すべて Changed Files 済み
- Listing-side sub-check: スキップ。サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構成の変更のいずれも行わない (件数コメントを消すだけで、ツリーの構造は変えない)
- Outbound pointer sync candidate check: `docs/structure.md` の Maintenance rule が指す `modules/verify-patterns.md` § は Changed Files 済み。`docs/versioning.md` Gate 4 のチェック b が指す `docs/guide/customization.md` と `modules/detect-config-markers.md` は本変更と無関係。追加の候補なし
- `docs/ja/` translation sync check: `docs/translation-workflow.md` の Sync Procedure に従い、JA ミラー 2 件を Changed Files に入れた。Issue の Auto-Resolved Ambiguity Points は JA を受入条件から除外している (翻訳フローに任せる) ため、JA の更新は受入条件ではなく SHOULD レベル
- allowed-tools impact chain check (Case 2): `modules/verify-patterns.md` への追記に `scripts/*.sh` のパスが含まれないためスキップ
- 新規分岐ロジックの追加なし (docs のみ) のため、新規テストケースは不要
- 監査/調査型 Issue か: no (新機能の改修でも、複数項目の分類調査でもない)。Fail-safe critical か: no (スクリプトの変更なし)
- 外部仕様への依存: なし (`find` の `-maxdepth` / `-type f` は POSIX 標準。説明文中の例示のみ)

### 受入条件についての観察

- AC1 / AC2 の rubric は、方針 a・b のどちらでも成り立つ書き方になっている。本設計は AC1 の (b) と AC2 の「方針 b を採った場合」の条件に直接対応する
- AC2 の件数コメント残存確認が規定文中の例示を誤検出しないよう、Maintenance rule に `(N files)` 形式の文字列を残さない (Implementation Steps の 1)
- #1280 の Post-merge 観察条件 (次回 `/audit drift` で件数ドリフトが検出されない) は、本変更で検出対象の件数自体がなくなる。判定は別 Issue (#1280) の `/verify` で扱い、本 Issue のスコープ外とする
