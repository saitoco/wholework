# Issue #1127: audit: Issue 本文に書かれた前提条件の失効検出

## Overview

Issue 本文に書かれた「現時点で実害はない」「該当箇所は 0 件」「呼び出し元は 1 箇所のみ」といった**コードベース状態依存の前提**は、後続の変更で無言に失効する。#1055 はまさにこれで、前提が #1088 (2026-07-30 close) の実装で崩れてから約 1 か月のあいだ「実害なし」の Issue として滞留した。

本 Issue は、その失効を検出する仕組みを実装する。Issue 本文の対応方針 A (検出) / B (機械可読マーカー) / C (予防) の採否は `/spec` に委ねられていたため、本 Spec で **B + A + C を採用**する (採否の根拠は下記 `## Alternatives Considered` と `## Notes` を参照)。

- **B (基盤)**: Issue 本文に `<!-- premise: <式> -->` マーカーを書けるようにし、決定的な bash スクリプト `scripts/check-premise-expiry.sh` が現在のコードベースに対して再評価する
- **A (検出面)**: `/audit premise` サブコマンドが open Issue 全件を走査し、失効した前提を該当 Issue にコメント投稿する (autonomy tier ゲート: L1 は advisory、L2/L3 は自動投稿)
- **C (予防)**: `/issue` Step 4 に、コードベース状態依存の記述に `premise:` マーカーを付与するガイダンスを追加する

## Changed Files

- `scripts/check-premise-expiry.sh`: new file。Issue body ファイルから `<!-- premise: ... -->` マーカーを抽出し、`grep_count` / `file_exists` / `file_not_exists` の 3 式型を現在の作業ツリーに対して評価する。失効を検出したら exit 2 + stdout に `EXPIRED:` 行、評価不能は stderr に `UNEVALUABLE:` 行 (exit code に影響させない)。**ヘッダコメントが「検出対象の前提の種類」と「検出できない前提の扱い」の SSoT** (`scripts/get-config-value.sh` の "Supported/Unsupported Input Shapes" が `modules/detect-config-markers.md` から SSoT として参照されている先例と同型)。bash 3.2+ 互換 (`mapfile` / `${VAR,,}` 不使用)
- `tests/check-premise-expiry.bats`: new file。前提成立時に検出されない negative case と、失効時に検出される positive case の両方を検証する。`$BATS_TEST_TMPDIR` に `git init` + `git add` した使い捨てリポジトリを作り hermetic に実行する
- `skills/audit/SKILL.md`: `premise` サブコマンドのセクションを新規追加 (Step 1 Context Collection / Step 2 Premise Evaluation / Step 3 Results Output / Step 4 Comment Posting)。**方式選定の根拠 (A/B/C の採否と他案を採らなかった理由) を同セクション冒頭の Design Rationale ブロックに記載**。あわせて Command Routing に `premise` 分岐を追加、usage 文字列に `premise` を追加、frontmatter `description` に `premise` サブコマンドの説明を追加、frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh:*` を追加
- `skills/issue/SKILL.md`: Step 4 に「Premise marker for codebase-state-dependent statements」サブステップを追加。スクリプト呼び出しは行わない LLM 判断のみのガイダンスのため `allowed-tools` の変更は不要
- `docs/structure.md`: Directory Layout の `scripts/` ファイル数コメントを 84 files→85 files、`tests/` を 120 files→121 files に更新。Key Files > Scripts > Tooling セクションに `scripts/check-premise-expiry.sh` のエントリを追加
- `docs/ja/structure.md`: [translation sync] `docs/structure.md` と同じ変更内容を日本語で反映
- `docs/workflow.md`: `/audit` 説明段落 (line 180 付近) に `/audit premise` の 1 文を追加
- `docs/ja/workflow.md`: [translation sync] 同上
- `docs/product.md`: Terms テーブルの `/audit` 行のサブコマンド列挙に `premise` を追加。あわせて `Premise marker` 用語行を追加
- `docs/ja/product.md`: [translation sync] 同上
- `docs/guide/workflow.md`: `### /audit` のコードフェンスに `/audit premise` の 1 行を追加
- `docs/ja/guide/workflow.md`: [translation sync] 同上

**Steering Docs sync candidate (調査済み・変更不要と判断)**:
- `.claude/settings.json.template`: 変更不要。`/audit` の `allowed-tools` に登録済みの `compute-escalation-level.sh` / `collect-recovery-candidates.sh` / `collect-opportunistic-retire-candidates.sh` はいずれも settings.json.template に不在であることを grep で確認済み。`${CLAUDE_PLUGIN_ROOT}` 形式の SKILL.md frontmatter エントリのみで足りる
- `scripts/validate-skill-syntax.py`: 変更不要。`KNOWN_TOOLS` の更新が必要なのは base tool 名 (Read/Write 等) を `allowed-tools` に追加する場合のみで、本 Issue は `Bash(...)` パターンの追加のみ
- `modules/l0-surfaces.md`: 変更不要。新規コメントは `wholework-event:` 名前空間ではなく `<!-- premise-expired: ... -->` 単独マーカーを使う (根拠は `## Notes`)。L0 Surface SSoT テーブルの "Issue comments" 行は既存で、新しい L0 surface は増えない

## Implementation Steps

1. `scripts/check-premise-expiry.sh` を新規作成する (→ 受入条件 1, 2)。

   **インターフェース**: `scripts/check-premise-expiry.sh <issue-body-md-path>` (引数 1 つ、リポジトリルートを CWD として実行)

   **対応する前提式 (exhaustive、3 種)**:
   | 式 | 意味 | 評価方法 |
   |---|---|---|
   | `grep_count "<pattern>" "<paths>" <op> <N>` | `<paths>` 配下の追跡ファイル内で `<pattern>` に**固定文字列**一致する**行数**が `<op> <N>` を満たす | `git grep -F -- "<pattern>" -- <paths>` の出力行数を `wc -l` で数え `[ "$COUNT" <op> "$N" ]` で比較 |
   | `file_exists "<path>"` | `<path>` が存在する | `test -e "<path>"` |
   | `file_not_exists "<path>"` | `<path>` が存在しない | `test ! -e "<path>"` |

   `<op>` は `-eq` / `-ne` / `-lt` / `-le` / `-gt` / `-ge` の 6 種 (exhaustive)。`<N>` は非負整数。`<paths>` は半角スペース区切りの複数パス可。

   **分岐の挙動全列挙 (exhaustive)**:
   - **正常終了条件**: exit 0 — (a) marker が 0 件、(b) 全 premise が成立、(c) UNEVALUABLE のみ、のいずれか。stdout は空
   - **検出条件**: exit 2 — 1 件以上の premise が失効。stdout に `EXPIRED: <式> (actual: <実測値>)` を 1 行ずつ出力。`<実測値>` は `grep_count` なら行数、`file_exists` なら `not found`、`file_not_exists` なら `exists`
   - **usage error**: exit 1 — 引数欠落 / ファイル不在 / 読取不可。stderr に `Usage: check-premise-expiry.sh <issue-body-md-path>`。stdout は空
   - **fail-open 条件 (exit code に影響しない)**: 以下は stderr に `UNEVALUABLE: <式> (reason: <理由>)` を出力して次の marker の処理を続ける。EXPIRED としては扱わない (誤検出防止)
     - git work tree 外 (`git rev-parse --is-inside-work-tree` が非ゼロ) → reason: `not inside a git work tree`
     - `grep_count` の `<paths>` に `test -e` が偽となるパスがある → reason: `path not found: <p>`。**この検証は必須** — `git grep` は存在しないパススペックでもエラーを出さず exit 1 (ゼロマッチと同一) を返すため、検証を省くとタイプミスしたパスが「マッチ 0 件」として前提成立と誤判定される
     - 未対応の式型 / 構文不正 (演算子が 6 種以外、`<N>` が非負整数でない、引用符の対応が取れない等) → reason: `unsupported expression` / `malformed expression`
   - **timeout 条件**: なし。外部 I/O を持たずローカルの `git grep` / `test` のみで完結するため、呼び出し側 (Bash tool / verify-executor の `command` 60 秒) の timeout に従う
   - **kill 条件**: なし。長時間実行ループを持たない
   - **監視継続**: 該当なし (watchdog ではない)

   **ヘッダコメント (AC2 の SSoT)**: 上表の「対応する前提式」に加えて、以下の**検出できない前提の扱い**を明記する。
   - 追跡外ファイル (`.gitignore` 対象・未 `git add`) は `grep_count` の対象外。`modules/filesystem-scope.md` § Approved Patterns が bash スクリプトの検索に `git grep` を指定しているため、この制約は意図的なもの
   - 正規表現は非対応 (`git grep -F` の固定文字列のみ)。`modules/verify-executor.md` が記録する ERE/BRE の取り違え問題を式レベルで排除するため
   - 3 式型で表現できない前提 (「この設計判断は将来の X 次第」等の意味論的前提) は機械検出の対象外。`/audit premise` の Layer 2 が marker 化候補として提示するにとどまり、失効判定はできない
   - marker は `## Background` / `## Purpose` 等の散文セクションに置く。AC の checkbox 行 (`- [ ] ...`) には置かない — `scripts/check-pre-merge-ac.sh` / `scripts/scan-pending-ac.sh` 等の AC パーサと同一行に同居させない運用上の制約

   bash 3.2+ 互換 (`mapfile` / `${VAR,,}` 不使用、配列は `IFS` + `read -r -a` のみ)。

2. `tests/check-premise-expiry.bats` を新規作成する (after 1) (→ 受入条件 3, 4)。

   `setup()` で `$BATS_TEST_TMPDIR` 配下に使い捨て git リポジトリを作る (`git init -q` + fixture 配置 + `git add`)。commit は不要 — `git grep` は index に載った作業ツリーのファイルを検索することを実測で確認済み (`## Uncertainty` 参照)。各テストは `cd` した使い捨てリポジトリを CWD としてスクリプトを実行する。

   最低限カバーするケース (exhaustive):
   - negative case: `grep_count "<存在しない語>" "sub/" -eq 0` が成立 → exit 0、stdout 空
   - positive case: `grep_count "<存在する語>" "sub/" -eq 0` が失効 → exit 2、stdout に `EXPIRED:` と実測件数
   - `file_exists` / `file_not_exists` の成立・失効各 1 件
   - marker 0 件の body → exit 0、stdout 空
   - usage error (引数欠落 / ファイル不在) → exit 1
   - fail-open: 存在しないパスを含む `grep_count` → exit 0、stderr に `UNEVALUABLE:` (EXPIRED ではないこと)
   - fail-open: 未対応式型 → exit 0、stderr に `UNEVALUABLE:`
   - 複数 marker が混在し 1 件のみ失効 → exit 2、stdout は失効した 1 行のみ

3. `skills/audit/SKILL.md` に `premise` サブコマンドのセクションを追加する (after 1) (→ 受入条件 1, 2)。

   `## fragility Subcommand` と `## progress Subcommand` のあいだに `## premise Subcommand` (h2) を挿入し、既存 subcommand と同じ `### Option Parsing` → `### Step N:` (h3) 構成にそろえる。

   - **Design Rationale ブロック** (セクション冒頭、`### Option Parsing` の直前): 採用方式 (B + A + C) と、A 単独 / B 単独を採らなかった理由、`drift` サブ観点ではなく独立サブコマンドとした理由を記載する。**Spec ではなくここに書くことが必須** — AC1 の `rubric` grader には Issue body と git diff と本文中で明示的に名指しされたファイルのみが渡され、Spec ファイルは渡されない (`modules/verify-executor.md` の `rubric` 行) 。`/spec` が main に直接コミットする Spec は PR diff にも含まれないため、Spec だけに書くと grader から不可視になる
   - **Option Parsing**: `--dry-run` (レポート表示のみ、コメント投稿しない) / `--limit N` (コメント投稿を N 件に制限)
   - **Step 1 Context Collection**: `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` を Read して `AUTONOMY_TIER` を取得 (Read 指示は見出し直後の第 1 段落に置く)。`gh issue list --state open --json number,title,body --limit 100` で open Issue を取得
   - **Step 2 Premise Evaluation (2 層、exhaustive)**:
     - Layer 1 (決定的): body に `<!-- premise:` を含む Issue について、Write ツールで `.tmp/premise-body-<N>.md` に body を書き出し `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh .tmp/premise-body-<N>.md` を実行する。exit 2 → stdout 各行を失効として記録、exit 0 → 成立、exit 1 → 警告を出して当該 Issue をスキップ。処理後に `rm -f` で一時ファイルを削除する
     - Layer 2 (発見的、LLM 判断): `premise:` マーカーを持たない Issue の body を読み、コードベース状態に依存する前提が書かれているかを判断する (例: 「現時点で実害はない」「該当箇所は 0 件」「呼び出し元は 1 箇所のみ」「将来 X が入った場合」)。**固定フレーズの grep ではなく LLM 判断で行う** — Wholework は Issue 本文の言語をプロジェクト側で決める設計 (`CLAUDE.md` § Language Conventions) であり、特定言語のフレーズ表をスクリプトに埋め込むと配布先プロジェクトで機能しないため。結果は marker 化候補として報告し、**失効判定はしない** (機械可読な形がない前提の失効可否は判定できない)
   - **Step 3 Results Output**: `| No | Issue | Layer | Premise | Result | Detail |` のテーブルで表示する。`Result` は `EXPIRED` / `HOLDS` / `UNEVALUABLE` / `MARKER CANDIDATE`。`--dry-run` の場合はここで終了する
   - **Step 4 Comment Posting (autonomy tier ゲート)**:
     - `AUTONOMY_TIER=L1`: L0 write を行わず advisory 出力のみ (`Recommend: comment on #N — premise expired: <式> (actual: <実測値>)`)
     - `AUTONOMY_TIER=L2` または `L3`: `EXPIRED` 行を持つ Issue ごとに `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh` でコメントを投稿する
     - 重複防止: 投稿前に `gh issue view <N> --json comments` を取得し、`<!-- premise-expired: <式> -->` を含むコメントが既にあれば当該式の投稿をスキップする (`/audit stats --retention` の `<!-- escalation-level: N -->` 重複防止と同型)
     - コメント本文は `<!-- premise-expired: {式} -->` を先頭行に置き、`## Premise Expired` 見出しと失効内容 (式 / 実測値 / 前提を再検討すべき旨) を続ける
     - `MARKER CANDIDATE` 行にはコメントを投稿しない (Step 3 の表示のみ)
     - `--limit N` で打ち切った場合は、投稿しなかった件数を明示的に出力する (silent truncation を避ける)
   - 本サブコマンドは引数なし `/audit` の統合実行 (drift + fragility) には**含めない** (理由は Design Rationale ブロックに記載)

4. `skills/audit/SKILL.md` の Command Routing / usage / frontmatter を更新する (after 3) (→ 受入条件 1)。

   - Command Routing に `premise` 分岐を追加する。挿入位置は `auto-session` の分岐の直後、「If ARGUMENTS is empty」の分岐の直前 (統合実行の分岐より前に置く)
   - usage 文字列に `premise` を追加する: `Usage: /audit [drift|fragility|stats|progress <XL-parent>|auto-session <session-id>|premise] [--dry-run] ...`
   - frontmatter `description` に `/audit premise` の説明を 1 文追加する (YAML block scalar は使えないため 1 行で書く)
   - frontmatter `allowed-tools` の Bash パターン列挙に `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh:*` を追加する

5. `skills/issue/SKILL.md` Step 4 に premise marker ガイダンスのサブステップを追加する (after 1) (→ 受入条件 1)。

   挿入位置: Step 4 の「Checkbox format for Pre-merge / Post-merge condition lines」サブステップの直後 (Step 4 の末尾)。見出しは `**Premise marker for codebase-state-dependent statements:**`。

   内容: Issue 本文にコードベース状態依存の前提 (「現時点で実害はない」「該当箇所は 0 件」「呼び出し元は 1 箇所のみ」) を書く場合、その行に `<!-- premise: ... -->` マーカーを付与して `/audit premise` が後から再評価できるようにする。対応する式文法と限界の SSoT は `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh` のヘッダコメントである旨を明記する。マーカー例を 1 つ示す。3 式型で表現できない前提の場合は、代わりに「どの実装が入ったら失効するか」を散文で併記する (マーカーなしの前提は `/audit premise` の Layer 2 で marker 化候補として提示されるだけで、失効判定はされない)。マーカーは散文セクションに置き AC の checkbox 行には置かない旨も記載する。

   スクリプト呼び出しを伴わない LLM 判断のみのガイダンスであるため、`/issue` の `allowed-tools` は変更しない。

6. `docs/structure.md` と `docs/ja/structure.md` を更新する (after 1, 2) (→ 受入条件 1)。

   Directory Layout の `scripts/` ファイル数コメントを `(84 files)`→`(85 files)`、`tests/` を `(120 files)`→`(121 files)` に更新する。Key Files > Scripts > **Tooling** セクションに `scripts/check-premise-expiry.sh` のエントリを追加する。`docs/ja/structure.md` に同じ変更内容を日本語で反映する (`docs/translation-workflow.md` の Sync Procedure に従い、見出し・構成を保ったままコードフェンス数の整合を確認する)。

7. `docs/workflow.md` と `docs/ja/workflow.md` を更新する (after 3) (→ 受入条件 1)。

   `/audit` の説明段落 (`/audit auto-session` の説明の後) に `/audit premise` の説明を 1 文追加する: Issue 本文に書かれた `premise:` マーカーを現在のコードベースに対して再評価し、失効したものを該当 Issue にコメントで通知する (autonomy tier に応じて L1 は advisory、L2/L3 は自動投稿)。`docs/ja/workflow.md` に同じ内容を日本語で反映する。

8. `docs/product.md` と `docs/ja/product.md` を更新する (after 3) (→ 受入条件 1)。

   Terms テーブルの `/audit` 行のサブコマンド列挙に `premise` を追加する。あわせて `Premise marker` の用語行を追加する (Definition: Issue 本文の記述がコードベースの現在状態に依存することを宣言する `<!-- premise: ... -->` 形式の HTML コメントマーカー。`/audit premise` が再評価して失効を検出する / Context: /issue, /audit / 日本語訳: 前提マーカー)。`docs/ja/product.md` に同じ内容を日本語で反映する。

9. `docs/guide/workflow.md` と `docs/ja/guide/workflow.md` を更新する (after 3) (→ 受入条件 1)。

   `### /audit — Drift and Fragility Detection` のコードフェンス内に `/audit premise` の 1 行 (`# re-evaluate premise markers in open issues`) を追加する。`docs/ja/guide/workflow.md` に同じ内容を日本語で反映する。

## Alternatives Considered

| 案 | 内容 | 採否 | 理由 |
|---|---|---|---|
| **A 単独** | `/audit` に前提失効の観点を追加し、Issue 本文の散文を LLM が読んで失効を判断する | 不採用 | AC3 が要求する「前提成立時に検出されないこと (negative case) と失効時に検出されること」の**両方を bats で検証する**テストが書けない。LLM 判断は非決定的で bats の assert 対象にならない。`modules/skill-dev-constraints.md` § LLM-assisted Skill Phase Test Strategy の 2 層分割 (script 層 = 決定的 / LLM 層 = observation AC) に照らしても、AC3 は script 層の存在を前提としている |
| **B 単独** | `<!-- premise: ... -->` マーカーとその評価スクリプトのみを追加する | 不採用 | マーカーを評価する実行主体がなく、検出ループが閉じない。post-merge AC 「既存の open Issue 全件に対して実行し確認する」の実行手段も存在しないことになる |
| **C 単独** | `/issue` 側で「実害なし」型の記述に失効条件の併記を促すだけ | 不採用 | 予防のみで、既に書かれている前提 (#1055 を含む既存 open Issue) の失効を検出できない。AC1 の「検出手段が実装されている」を満たさない |
| **A + B (C なし)** | 検出と基盤のみ | 不採用 | 新規 Issue にマーカーが付く動機付けがなく、機構が使われないまま風化する。C は `/issue` Step 4 に既存の warn-only サブステップ群と同型のガイダンスを 1 つ足すだけで、追加コストが小さい |
| **`drift` のサブ観点として実装** | drift の Step 2 検出カテゴリ表に行を追加する | 不採用 | **出力アクションが異なる**。drift は Step 5 で「新規 Issue を起票する」が、前提失効の正しい応答は「前提を書いた既存 Issue にコメントする」。drift の Step 4 は "Generate all / Select / Cancel" という単一の起票判断に収束する設計で、コメント投稿レンズを同居させると判断軸が二重化する。なお drift の Step 1 が duplicate check 用に open Issue を既に取得している点は独立サブコマンド化の反証になりうるが、取得コスト (`gh issue list` 1 回) より判断軸の分離を優先した |
| **引数なし `/audit` の統合実行に含める** | `/audit` (drift + fragility) に premise を加えて 3 観点統合にする | 不採用 | 同上。統合実行の Step 3/4 は全観点の結果を 1 つの起票判断にまとめる構造で、L0 write の種類が異なる premise を混ぜると tier ゲートの適用範囲が不明瞭になる |
| **`wholework-event:` 名前空間のコメントマーカー** | `<!-- wholework-event: type=premise-expired ... -->` で重複防止する | 不採用 | `modules/l0-surfaces.md` § Machine-Readable Event Marker への型定義追加が必要になる。最も近い先例 (`/audit stats --retention` の retire-proposal コメント) は `<!-- escalation-level: N -->` という単独マーカーを使っており、`/audit` 内のコメントマーカー規約としてはそちらに合わせるほうが一貫する |
| **`grep -rF` / ripgrep を使う** | 追跡外ファイルも含めて検索する | 不採用 | `modules/filesystem-scope.md` § Prohibited Patterns が `grep -rn '<pat>' .` 形式を禁じ、Approved Patterns で bash スクリプトの検索に `git grep` を指定している。ripgrep は ERE 既定で `modules/verify-executor.md` が記録する BRE/ERE 取り違えの温床になる。追跡外ファイルが対象外になる制約はヘッダコメントに限界として明記する |
| **`==` / `<` / `>` 演算子** | Issue 本文の例 (`== 0`) に合わせる | 不採用 | `>` は HTML コメント内に現れると、コードベース既存の属性抽出パターン `grep -oE 'config=[^ >]+'` (`scripts/opportunistic-search.sh`) と同型の `[^ >]+` 系抽出が将来 premise マーカーに適用された際に破綻する。shell test 形式 (`-eq` / `-lt` 等) は `>` を一切含まず、bash の整数比較に 1:1 対応する。Issue 本文の例は「のような形で」という提案であり固定の契約ではないため、文法確定は `/spec` の裁量に属する |

## Verification

### Pre-merge

- <!-- verify: rubric "Issue 本文に書かれた前提条件の失効を検出する仕組みが実装されている。/audit の新しい観点、既存観点への追加、または前提を宣言するマーカーとその再評価処理のいずれでもよいが、採用方式と他案を採らなかった判断根拠が記録されている" --> 前提失効の検出手段が実装され、方式選定の根拠が記録されている
- <!-- verify: rubric "検出対象とする前提の種類 (grep 件数、呼び出し元の有無、ファイル存在など) と、検出できない前提の扱いが明記されている" --> 検出対象の範囲と限界が明記されている
- <!-- verify: rubric "tests/ 配下に、前提が成立している場合に検出されないこと (negative case) と、失効している場合に検出されることの両方を検証するテストが存在する" --> 両ケースを検証するテストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge

- 実装後に既存の open Issue 全件に対して実行し、#1055 と同型の前提失効が他にも存在するかを確認する <!-- verify-type: manual -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh:*`: `/audit premise` Step 2 Layer 1 から呼び出す。`skills/audit/SKILL.md` の `allowed-tools` に追加が必要 (実装ステップ 4 に含む)
- `gh issue list:*` / `gh issue view:*` / `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*`: いずれも `skills/audit/SKILL.md` の `allowed-tools` に登録済み。追加不要

### Built-in Tools

- `Read`: `.wholework.yml` / `modules/detect-config-markers.md` の読み取り。登録済み
- `Write`: `.tmp/premise-body-<N>.md` への Issue body 書き出し。登録済み
- `Bash(rm:*)`: 一時ファイル削除。登録済み

### MCP Tools

- なし

## Uncertainty

- **`git grep` の未追跡・未存在パススペック時の挙動**: 検証済み。`git grep -F -- "<pat>" -- nosuchdir/` は**エラーを出さず exit 1** (ゼロマッチと同一) を返すことを実測で確認した。したがってパスのタイプミスが「マッチ 0 件」= 前提成立として誤判定されうる。**対応**: 実装ステップ 1 の fail-open 条件として、`grep_count` 評価前に全パスの `test -e` 検証を必須化した。影響範囲: 実装ステップ 1, 2
- **`git init` + `git add` (commit なし) で `git grep` が動作するか**: 検証済み。一時ディレクトリで `git init -q` + `git add` のみを行い `git grep -F -- "token" -- sub/` が期待どおり 2 行を返すことを実測で確認した。bats テストで commit 用の `git config user.*` 設定は不要。影響範囲: 実装ステップ 2
- **CI ジョブ名 `Run bats tests`**: 検証済み。`.github/workflows/test.yml` line 9 に `name: Run bats tests` が存在することを確認した。受入条件 4 の `github_check` はそのまま有効。影響範囲: 受入条件 4
- **`/audit premise` Layer 2 (LLM 判断) が既存 open Issue に対して有用な marker 化候補を返すか**: **未検証**。マージ前に確認する手段がない (実際の open Issue 群に対する LLM 判断の質は実行してみないと分からない)。post-merge AC がまさにこの確認を担う。影響範囲: post-merge 受入条件。Layer 1 (決定的) はこの不確実性から独立しており、Layer 2 が期待どおりでなくても pre-merge 受入条件 1-4 は満たされる

## Notes

### 方式選定の根拠の記録先を Spec から実装ファイルへ変更した

Issue の `## Auto-Resolved Ambiguity Points` および Issue Retrospective は、AC1 の rubric が要求する「採用方式と他案を採らなかった判断根拠」の記録先を「`/spec` が作成する Spec の Retrospective/Design セクション」と想定していた。**この想定は誤りである**ため、本 Spec で修正した。

理由: `modules/verify-executor.md` の `rubric` 行は grader への入力を「Issue body、git diff、text 中で明示的に名指しされたファイル」と定め、**Spec ファイルは grader に渡さない**と明記している。加えて `/spec` は Spec を worktree 経由で base ブランチに直接マージする (`modules/worktree-lifecycle.md` § Spec file write destination) ため、Spec は PR の diff にも含まれない。したがって根拠を Spec だけに書くと、AC1 の rubric grader からは構造的に不可視になる。

対応: 方式選定の根拠は `skills/audit/SKILL.md` の premise サブコマンド冒頭の **Design Rationale ブロック**に、検出範囲と限界は `scripts/check-premise-expiry.sh` の**ヘッダコメント**に記載する (いずれも PR diff に含まれる)。本 Spec の `## Alternatives Considered` はその人間向け・`/code` 向けの控えであり、AC の判定根拠そのものではない。

### 前提式の SSoT をモジュールではなくスクリプトヘッダに置いた

`modules/premise-marker.md` を新設する案も検討したが、採らなかった。消費者は `/audit` と `/issue` の 2 スキルで、`modules/` 抽出の推奨基準 (`modules/skill-dev-checks.md` § Shared Module Check: 同一のルール/ロジックが 2 箇所以上で使われる場合に推奨) の境界上にある。決め手は `scripts/get-config-value.sh` の先例で、同スクリプトのヘッダコメント内 "Supported/Unsupported Input Shapes" テーブルが `modules/detect-config-markers.md` から「bash 側が対応する入力形状の exhaustive な single-source」として明示的に参照されている。文法の実装体とその仕様記述を同一ファイルに置くほうが乖離しにくく、`modules/` を 45→46 に増やして `docs/structure.md` の Modules 一覧とファイル数コメントを二重更新するコストも避けられる。

### post-merge AC のゼロ件判定

post-merge 受入条件 (「既存の open Issue 全件に対して実行し、#1055 と同型の前提失効が他にも存在するかを確認する」) は、マージ直後の時点ではマーカーを持つ Issue が 0 件であるため、Layer 1 の結果は必然的にゼロ件になる。`modules/verify-patterns.md` §28 (Count-Dependent Conditional Acceptance Criteria) の既定判定に従い、**実行結果にゼロ件である旨が明示されていれば PASS** と判定する。Layer 2 の marker 化候補が 0 件か 1 件以上かは PASS/FAIL を左右しない (Issue Retrospective が確定させたとおり、本条件は investigation-only スコープであり起票要否は発見時の個別判断)。

`modules/verify-patterns.md` §11 の quick reference に照らして自動化可能な verify command への置換も検討したが、「実行」部分は `/audit premise` の呼び出しで自動化できる一方、「#1055 と同型の前提失効が他にも存在するかを確認する」の判断部分は出力の読解を要するため、`verify-type: manual` のまま据え置いた。Issue 本文の AC も変更しない (要件の追加・変更は `/issue` の責務であり `/spec` では行わない)。

### premise マーカーの配置制約

`<!-- premise: ... -->` は `## Background` / `## Purpose` 等の散文セクションに置き、`### Pre-merge` / `### Post-merge` の checkbox 行には置かない。既存の AC パーサ (`scripts/check-pre-merge-ac.sh` / `scripts/scan-pending-ac.sh` / `scripts/check-ac-checkbox-format.sh`) はいずれも `^- \[[ xX]\]` 行を対象とし `verify:` / `verify-type:` 属性を読むため、同一行に別種のマーカーを同居させる必然性がなく、将来の属性抽出との干渉リスクだけが残る。この制約はスクリプトヘッダと `/issue` のガイダンス双方に明記する。

### Issue 本文の事実主張の検証結果 (conflict なし)

Issue 本文 Background の技術的主張をコードベースに対して照合し、いずれも現状と一致することを確認した。conflict は検出されなかった。

- 「`scripts/opportunistic-search.sh` の `config=` ゲートが Issue 本文の `config=<key>` をそのまま `get-config-value.sh` に渡す」 → `scripts/opportunistic-search.sh` line 398-406 で実装を確認
- 「既存の `/audit drift` はドキュメントと実装の乖離を検出するが、Issue 本文に書かれた前提と実装の乖離は見ていない」 → `skills/audit/SKILL.md` drift Step 2 の検出カテゴリ表は全て Steering/Project Documents 起点で、open Issue は Step 3 の duplicate check にのみ使われることを確認
- 参考実測: `git grep -F -- "get-config-value.sh" -- scripts/ skills/ modules/` は現時点で 40 行にマッチする。#1055 が書いた「0 件」という前提は実際に失効している

### 観測事項: translation-workflow.md の対象範囲記述

`docs/translation-workflow.md` § When to Sync は同期義務を「top-level `docs/*.md`」と記述しているが、実装側の `scripts/check-translation-sync.sh` は `docs/*.md` に加えて `docs/guide/*.md` も対象にしている (line 23-24)。本 Spec は実装側に合わせて `docs/guide/workflow.md` の ja ミラーも Changed Files に含めた。ドキュメント側の記述更新は本 Issue のスコープ外 (`/audit drift` が拾うべき性質のもの) として、ここに記録するに留める。

## Consumed Comments

- `saito` / `MEMBER` / first-class — `/issue` フェーズの Issue Retrospective。Background の技術的主張がコードベース grep で裏付けられたこと、非対話モードで自動解決した 2 点 (判断根拠の記録場所、post-merge AC のスコープ解釈)、および方式選定 A/B/C の採否を意図的に `/spec` に委ねたことを伝達している。本 Spec は方式選定を `## Alternatives Considered` で確定させ、判断根拠の記録先については `## Notes` 第 1 節のとおり Spec ではなく実装ファイルへ修正した — https://github.com/saitoco/wholework/issues/1127#issuecomment-5245146709

## issue retrospective

### Background 事実確認 (advisory)

Background 内の技術的主張 (`scripts/get-config-value.sh` の存在、`scripts/opportunistic-search.sh` の `config=` ゲートが `get-config-value.sh` を呼び出す実装) はコードベース grep で裏付けが取れた。両スクリプトとも実在し、`opportunistic-search.sh:403` で `get-config-value.sh` を呼び出している。Background の記述は正確。

### 曖昧性の自動解決 (Non-Interactive Mode)

非対話モード (`--non-interactive`) のため、以下 2 点を自動解決した (Issue 本文 `## Auto-Resolved Ambiguity Points` に転記済み)。

1. **判断根拠の記録場所** — AC1 の rubric が要求する「採用方式と他案を採らなかった判断根拠」の記録先は本文で未指定だった。既存パターン (Spec-first: 判断根拠は Spec の Retrospective に蓄積、例: #921/#922/#923) から一意に推測可能であり、AC テキスト自体は記録先に依存せず判定可能なため、`/spec` が作成する Spec の Retrospective/Design セクションに記録される前提とし、本文は変更しなかった。
   - 他候補: 専用の `docs/reports/*.md` レポートを新規作成する案も検討したが、本 Issue は「機能実装」であり `docs/reports/` は主に測定・影響分析レポート向けの慣習であるため採用しなかった。
2. **Post-merge AC の実行結果の扱い** — 「#1055 と同型の前提失効が他にも存在するかを確認する」は「確認する (investigate)」であり「起票する (file)」ではないと解釈した。設計案・調査結果は起票より Issue 追記/コメントを優先する既存の運用方針と整合させた。新規の前提失効を発見した場合の追加起票要否は、発見時に個別判断する運用とする。

### 方式選定 (A/B/C) について

Background に記載の対応方針 A (`/audit` への観点追加) / B (機械可読マーカー) / C (`/issue` 側予防) の採否は、Issue/Spec の責務境界 (`docs/product.md` § `/issue` (What) vs `/spec` (How)) に従い意図的に `/spec` の判断に委ねた。`/issue` フェーズでの解決対象ではないため、自動解決の対象外とした。

### 機械チェック結果

- `check-skill-change-observation-ac.sh`: exit 0 (session=next 欠落なし)
- `check-ac-checkbox-format.sh`: exit 0 (チェックボックス形式違反なし)
- `gh-check-blocking.sh`: exit 0 (オープンなブロッカーなし)

## spec retrospective

### Minor observations

- `docs/translation-workflow.md` § When to Sync は同期義務を「top-level `docs/*.md`」と記述しているが、実装の `scripts/check-translation-sync.sh` は `docs/guide/*.md` も対象にしている。本 Spec は実装側に合わせたが、ドキュメント記述の更新は別 Issue 相当 (本 Spec `## Notes` 末尾に記録済み)。
- `docs/structure.md` の `scripts/` ファイル数コメント `(84 files)` は `scripts/` 直下のファイル数を数えており、`scripts/git-hooks/` 配下は含まない。実測 (`ls -1 scripts/ | grep -v git-hooks | wc -l` = 84、`scripts/git-hooks/` = 1) で確認した。`find scripts -type f` の 85 と取り違えると数え方の drift を生む。
- `/audit` の `allowed-tools` に登録されている `compute-escalation-level.sh` / `collect-recovery-candidates.sh` / `collect-opportunistic-retire-candidates.sh` は `.claude/settings.json.template` に不在。新規スクリプト追加時に settings.json.template を触る必要はないことの根拠として記録する。

### Judgment rationale

- **AC1 の判断根拠の記録先を Issue Retrospective の想定から変更した**。Issue Retrospective は「Spec の Retrospective に蓄積」という既存パターンから記録先を推測していたが、`modules/verify-executor.md` の `rubric` 行が grader 入力を「Issue body / git diff / text 中で名指しされたファイル」と定めており Spec は渡らない。さらに `/spec` の Spec は base ブランチへ直接マージされ PR diff にも含まれない。この 2 つを突き合わせると、Spec 単独の記録は rubric AC からは構造的に不可視になる。実装ファイル (`skills/audit/SKILL.md` の Design Rationale ブロック、`scripts/check-premise-expiry.sh` のヘッダコメント) を authoritative な記録先とし、Spec はその控えとした。
- **A 単独案を AC3 で棄却した**。AC3 が「negative case と positive case の両方を bats で検証する」ことを要求しているため、非決定的な LLM 判断だけでは AC を満たせない。逆に言えば AC3 の存在自体が「決定的なスクリプト層が必要」という設計制約を Issue 側から与えていた。AC の文面から実装アーキテクチャの下限が決まる例として記録する。
- **`drift` サブ観点ではなく独立サブコマンドを選んだ決め手は出力アクションの差**。入力 (open Issue 本文) は drift の Step 1 が duplicate check 用に既に取得しており、その意味では drift への統合のほうが安価だった。しかし drift の Step 4/5 は「新規 Issue を起票するか」という単一判断に収束する構造で、「前提を書いた既存 Issue にコメントする」という別種の L0 write を同居させると tier ゲートの適用範囲が不明瞭になる。入力の共有よりも判断軸の分離を優先した。
- **前提式の演算子に shell test 形式 (`-eq` 等) を選んだ**。Issue 本文の例は `== 0` だったが、`>` を含む演算子は HTML コメント内の属性抽出パターン (`grep -oE 'config=[^ >]+'`、`scripts/opportunistic-search.sh`) と将来衝突する。Issue 本文の例示は「のような形で」という提案であり文法の固定契約ではないため、`/spec` の裁量で変更した。
- **前提式の SSoT をモジュールではなくスクリプトヘッダに置いた**。消費者が 2 スキル (`/audit`, `/issue`) で `modules/` 抽出基準の境界上にあったため、`scripts/get-config-value.sh` のヘッダ内 "Supported/Unsupported Input Shapes" が `modules/detect-config-markers.md` から SSoT として参照されている先例に倣った。文法の実装体と仕様記述を同一ファイルに置くと乖離しにくい。

### Uncertainty resolution

- **`git grep` は存在しないパススペックでもエラーを出さず exit 1 (ゼロマッチと同一) を返す**。実測で確認した。この挙動は「パスのタイプミス → マッチ 0 件 → 前提成立」という silent false negative を生む。#1055 が「0 件だから実害なし」で滞留したのと構造的に同じ失敗モードを、検出機構自身が再生産しかねなかった。対策として `grep_count` 評価前の全パス `test -e` 検証を必須の fail-open 分岐として Spec に明記した。
- **`git init` + `git add` のみ (commit なし) で `git grep` が動作する**ことを一時ディレクトリで実測確認した。bats テストで `git config user.name` / `user.email` の設定が不要になり、hermetic なフィクスチャ構築が単純化する。
- **CI ジョブ名 `Run bats tests`** が `.github/workflows/test.yml` line 9 に実在することを確認した。受入条件 4 の `github_check` はそのまま有効。
- **未解決のまま残した不確実性**: `/audit premise` Layer 2 (LLM 判断による marker 化候補抽出) が実際の open Issue 群に対して有用な結果を返すかは、マージ前に検証する手段がない。post-merge 受入条件がこの確認を担う。Layer 1 (決定的) はこの不確実性から独立しているため、pre-merge 受入条件 1-4 の成否には影響しない。

## Code Retrospective

### Deviations from Design

- N/A — 実装ステップ 1〜9 は Spec の記述通りに実施した。順序・内容ともに変更なし。

### Design Gaps/Ambiguities

- **`skills/issue/SKILL.md` への premise マーカーガイダンス追加が `validate-skill-syntax.py` の allowed-tools 一貫性チェックに抵触することを Spec は想定していなかった**。Spec 実装ステップ 5 は「スクリプト呼び出しを伴わない LLM 判断のみのガイダンスであるため allowed-tools は変更しない」としていたが、ガイダンス文中で `${CLAUDE_PLUGIN_ROOT}/scripts/check-premise-expiry.sh` という完全参照形式を書いた時点で、validator の `validate_body_scripts_in_allowed_tools()` (本文中の `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` パターンを機械的に検出し allowed-tools 登録の有無を問う静的チェック、呼び出しか単なる参照かを区別しない) がエラーを出した。対応: ガイダンス文中の参照を `${CLAUDE_PLUGIN_ROOT}/` プレフィックスなしの `scripts/check-premise-expiry.sh` 表記に変更し、allowed-tools は Spec の判断通り無変更のまま validator を通過させた。他の Skill が同種の「呼び出しを伴わない SSoT 参照」を本文に書く際も、`${CLAUDE_PLUGIN_ROOT}/scripts/` の完全形は避けるべき一般的な注意点として記録する。

### Rework

- N/A — 上記のガイダンス文言修正以外に手戻りは発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- pre-merge AC ゲート (4件全 PASS) と review-incomplete-fallback チェック (fallback なし、通常の Review Response Summary 経路) を確認したうえで、conflicts なしの clean マージとして squash merge を実行した。
- BASE_BRANCH は `main` のため、`closes #1127` による Issue 自動クローズが有効。ラベル遷移・Issue クローズ確認のフォールバック手順が Step 6 として組み込まれている。

### Deferred Items

- `/audit premise` Layer 2 (LLM 判断) の実効性検証は post-merge 受入条件に委ねた。マージ前に検証する手段がない (spec/review retrospective から継続)。
- `docs/translation-workflow.md` の同期対象範囲の記述の是正は本 Issue のスコープ外 (spec/review retrospective から継続)。
- 既存 open Issue への premise マーカーの遡及付与は行わない。post-merge の調査で marker 化候補が挙がった場合の起票要否は発見時の個別判断 (spec/review retrospective から継続)。
- 棄却した review finding のうち `scripts/check-premise-expiry.sh:161` (git grep exit status 未検査、out-of-repo path で fatal collapse) は将来別の呼び出しパターンで顕在化しうる。再発した場合は個別 Issue で再検討する (review retrospective から継続)。

### Notes for Next Phase

- `/verify` 前提: post-merge AC は「CI (`Run bats tests`) が merge commit で pass すること」および「`/audit premise` を既存 open Issue に対して実行し、他に #1055 のような失効前提が存在しないかを investigation-only で確認すること」の2点。
- Full bats suite は review フェーズ完了時点で 1728/1728 全 pass。マージ commit 上での再実行結果が post-merge AC の1つ目。

## review retrospective

### Spec vs. implementation divergence patterns

Spec (`## Changed Files` 列挙) と PR diff の構造的な乖離はなかった — 13ファイル全件が Spec 記載と一致していた。一方で、Spec 記載の Changed Files には含まれていなかったが本来同期対象だった `docs/tech.md` の model-effort-matrix 列挙漏れを review フェーズで検出・修正した。原因は Spec 作成時の Steering Docs sync 調査が `docs/product.md`/`docs/workflow.md`/`docs/guide/workflow.md` の3系統列挙のみを対象とし、`docs/tech.md` の model-effort-matrix という4つ目の同種列挙サイトを見落としたこと。`/audit` サブコマンドのような「複数箇所に列挙が重複する」パターンを Spec 段階で洗い出す際は、grep で `audit (skill)` や `/audit ` のような列挙キーワードをリポジトリ全体から探索し、同種列挙サイトを網羅的に確認するべきだった。

より構造的な観点では、`skills/audit/SKILL.md` Step 2 (Premise Evaluation) の exit-0 処理が Step 3 (Results Output) の `HOLDS`/`UNEVALUABLE` を生成できないという MUST 級の欠落は、Spec の実装ステップ記述自体には現れていなかった (Spec は「Layer 1 (deterministic)... 現在のコードベースに対して再評価する」という抽象度で記述しており、exit code ごとの Step 3 テーブルへの反映指示までは踏み込んでいなかった)。SKILL.md という「LLM 実行主体の prose」を新規作成する Issue では、スクリプトの exit code / stderr 出力と、それを消費する後続 Step の出力フォーマット (今回は Result enum 4値) との対応関係を Spec 段階で明示的に対応表化しておくと、この種のギャップを実装フェーズより前に検出できた可能性がある。

### Recurring issues

review-bug の diff-scan・security-scan の2エージェントが独立に、`scripts/check-premise-expiry.sh` の同じ2つの根本原因 (空 `<paths>` の受理、マーカー抽出正規表現の近似マッチ消失) にたどり着いた。これは「fail-open を謳うスクリプトが、fail-open 経路自体に到達する前に入力を静かに取りこぼす」という同型のバグパターンで、ヘッダコメントが明記する設計意図 (「UNEVALUABLE で silent false negative を防ぐ」) の実装漏れが2箇所で再発した形。fail-open メカニズムを持つスクリプトを実装する際は、「fail-open 分岐に到達する前の入力検証・正規表現マッチ自体が意図せず入力を弾いていないか」を単体で確認する observation は、今後同種のスクリプト (`<!-- verify: ... -->` のような他のマーカーパーサ) を実装する際にも再利用できる。

2段階検証で8/10件が棄却された内訳を見ると、「唯一の呼び出し元がパスを自身で生成するため到達不能」(2件)・「手前のガードが同じ fail-open 結果に先に到達」(1件)・「既存コードの慣行と同型で本 PR が新規に持ち込んだものではない」(3件)・「CI で検査されない静的解析ツールの所感」(1件)・「LLM 実行主体の prose では失敗が可視化されるため杞憂」(1件) という5パターンに分かれた。特に「既存慣行と同型」の3件 (`--limit 100`、コメント本文の tmp パス省略、ja ミラーの全角括弧) は、review-bug が新規追加コードの周辺だけを見て「本 PR が持ち込んだ欠陥」と誤認した false positive であり、検証エージェントが `git show main:<path>` で既存コードとの diff を確認して初めて棄却できた。この種の false positive は、review-bug のプロンプトに「変更箇所が既存コードの慣行を踏襲しているだけでないか、`git show main:<path>` で確認する」という明示的な指示を追加すれば一次生成の段階で減らせる可能性がある。

### Acceptance criteria verification difficulty

4件の Pre-merge AC (rubric×3、github_check×1) はいずれも UNCERTAIN なく PASS 判定できた。rubric 対象ファイル (`scripts/check-premise-expiry.sh` ヘッダコメント、`skills/audit/SKILL.md` Design Rationale ブロック) が rubric 条件文が要求する内容をそのまま指し示せる場所に集約されていたため、grader の判定が容易だった — rubric 文を書く際に「判断根拠は `/spec` が作成する Spec に記録される」という Auto-Resolved Ambiguity Points の想定に反し、実際には `skills/audit/SKILL.md` 本体に Design Rationale ブロックとして記録された点は、AC のテキスト自体が記録先を問わない書き方だったため実害はなかった。verify command / rubric の記述に特筆すべき問題はなかった。
