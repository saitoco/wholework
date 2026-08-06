# Issue #1200: blocked-by: 判定の SSoT を Issue body テキストから GraphQL 関係に移す

## Consumed Comments

No new comments since last phase.

## Overview

blocked-by 関係の判定 (gate・依存チェック・依存グラフ構築) を Issue body の `Blocked by #N` テキスト grep から GitHub native の GraphQL `blockedBy` 関係へ移す。body テキストは廃止せず、**書き込みトリガー (入力ショートカット)** として存続させる (Issue 本文の候補 1 を採用)。

判定側の単一の読み取り窓口として `scripts/get-blocked-by.sh` を新設する。単一 Issue モード (`get-blocked-by.sh <N>`) と一括モード (`get-blocked-by.sh --all`) を持ち、後者は open Issue 全体の blocked-by グラフを 1 回の GraphQL クエリ (必要に応じてページング) で取得して `/triage --backlog dependency` のグラフ構築コストを O(1) 回の API 呼び出しに抑える。

`docs/workflow.md` § Blocked-by relationships は既に「GraphQL が SSoT」と宣言済みであり、本 Issue はその宣言に実装を合わせる drift 解消でもある。ドキュメント側は body テキストの位置づけを「人間向け補足」から「入力ショートカット」へ言い換え、読み取り経路を明記する。

## Changed Files

- `scripts/gh-graphql.sh`: named query `get-open-issues-blocked-by` を追加 (open Issue 一覧 + `blockedBy` + `pageInfo` の 1 クエリ取得)。bash 3.2+ 互換
- `scripts/get-blocked-by.sh`: 新規作成。GraphQL から blocked-by 関係を読み取る単一窓口。単一 Issue モード / `--all` 一括モード。bash 3.2+ 互換 (`mapfile` 不使用)
- `tests/get-blocked-by.bats`: 新規作成。`WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` で `gh-graphql.sh` をモックする (`tests/set-blocked-by.bats` と同じパターン)
- `tests/auto-batch.bats`: List mode gate が `get-blocked-by.sh` を参照し body grep を残していないことを検証する `@test` を 2 件追加
- `skills/auto/SKILL.md`: List mode step 4 の blocked-by gate を「`gh-check-blocking.sh` で body ショートカットを materialize → `get-blocked-by.sh` で GraphQL から判定」に変更; frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` と `${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh:*` を追加
- `skills/triage/SKILL.md`: Step 9 の「Dependency blocked-by check」と Step 2b の依存グラフ構築・異常検出・レポート書式を GraphQL 基点に変更; frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` を追加
- `skills/spec/SKILL.md`: Step 4 の `gh-check-blocking.sh $NUMBER --dry-run` を `get-blocked-by.sh $NUMBER` に変更 (exit code 契約は 0/1/2 のまま); frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` を追加
- `modules/l0-surfaces.md`: L0 Surface SSoT 表の「Issue blocked-by relationships」行の Operations を `add, remove` → `add, remove, read` に変更し、Primary callers に `get-blocked-by.sh` を追加
- `docs/workflow.md`: § Blocked-by relationships を改訂 — body テキストを「人間向け補足」→「入力ショートカット (書き込みトリガー)」に言い換え、「### 読み取り経路」小節を新設、Scripts 一覧に `get-blocked-by.sh` を追加
- `docs/ja/workflow.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` 準拠)
- `docs/structure.md`: GitHub API utilities 一覧に `scripts/get-blocked-by.sh` を追加
- `docs/ja/structure.md`: 上記の日本語ミラー同期
- `.claude/settings.json.template`: `permissions.allow` に `"Bash(scripts/get-blocked-by.sh *)"` を追加 (`gh-check-blocking.sh` と同じ扱い)。**Edit/Write ツールは `.claude/` を拒否するため `sed` または `python3` で編集し、`git add` する** (`.gitignore` に `!.claude/settings.json.template` の un-ignore があるため `-f` は不要)
- `tests/gh-graphql.bats`: [Steering Docs sync candidate] named query の解決テスト群 (L101-113) に `get-open-issues-blocked-by` の行を追加すべきか確認する
- `modules/retro-proposals.md`: 変更不要 — Step 11 は `set-blocked-by.sh` を呼ぶ**書き込み**経路であり、候補 1 では維持される (`grep -n "set-blocked-by" modules/retro-proposals.md` で L160 の 1 箇所のみ、判定用の読み取りは存在しないことを確認済み)
- `skills/issue/SKILL.md`: 変更不要 — Step 7 / Step 11 の `gh-check-blocking.sh` 呼び出しは body → GraphQL の**書き込み**経路であり、候補 1 では維持される (`grep -n "gh-check-blocking" skills/issue/SKILL.md` で L329 / L527 の 2 箇所とも書き込み用途であることを確認済み)
- `scripts/gh-check-blocking.sh`: 変更不要 — 役割は body → GraphQL の書き込みのまま。exit code 契約 (0/1/2) も変更しない

## Implementation Steps

1. `scripts/gh-graphql.sh` の `get_named_query()` に `get-open-issues-blocked-by` を追加する (`get-blocked-by)` の直後に配置)。クエリ本体は 1 行の `printf '%s'` で、変数は `$owner:String!,$repo:String!,$first:Int!,$cursor:String`、本体は `repository(owner:$owner,name:$repo){issues(states:OPEN,first:$first,after:$cursor,orderBy:{field:CREATED_AT,direction:DESC}){pageInfo{hasNextPage endCursor}nodes{number blockedBy(first:50){nodes{number state}}}}}`。`$cursor` は nullable なので 1 ページ目は `-F cursor=...` を渡さない (`gh api graphql` は未指定の nullable 変数を null として送る) (→ 受け入れ条件 5)

2. `scripts/get-blocked-by.sh` を新規作成する (1 の後)。`set -euo pipefail`、`SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` で `"$SCRIPT_DIR/gh-graphql.sh"` を呼ぶ (`set-blocked-by.sh` と同じ解決方式。PATH 先行方式は採らない)。bash 3.2+ 互換 — `mapfile` / 連想配列を使わず `while IFS= read -r` で読む。分岐の挙動は下記「分岐の挙動 (exhaustive)」表のとおり (→ 受け入れ条件 5)

3. `tests/get-blocked-by.bats` を新規作成する (2 の後)。`tests/set-blocked-by.bats` と同じ MOCK_DIR パターン (`export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` + `$MOCK_DIR/gh-graphql.sh` モック) を使う。カバーするケース: `--help` (exit 0 + `Usage`)、引数なし (exit 1)、非数値引数 (exit 1)、未知オプション (exit 1)、`--limit` 非数値 (exit 1)、blocker なし (exit 0 + 出力空)、全 blocker CLOSED (exit 0 + `<num>\tCLOSED` 行)、OPEN blocker あり (exit 2)、`--all` の TSV 3 列出力、`--all` の `hasNextPage: true` ページング (2 ページ目まで読む)、`--all` は OPEN blocker があっても exit 0 (→ 受け入れ条件 5)

4. `skills/auto/SKILL.md` List mode の step 4「Blocked-by check」を書き換える (2 の後、5・6 と並行可)。`gh issue view $NUMBER --json body -q '.body' | grep -ioE ...` のコードブロックを削除し、(a) `${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER` で body ショートカットを GraphQL へ materialize (exit code 2 は正常であることを明記)、(b) `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh $NUMBER` で権威ある blocker 一覧を取得、の 2 段に置き換える。各 blocker 行は `<number><TAB><state>`。`state` が `CLOSED` なら追加 API 呼び出しなしで gate 解放、`OPEN` の場合のみ `gh issue view $BLOCKER --json labels -q '[.labels[].name | select(startswith("phase/"))]'` で `phase/done` を判定する。警告文言と「`update_batch` を呼ばない」挙動は現行のまま維持する。あわせて frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` と `${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh:*` を追加する (→ 受け入れ条件 1)

5. `skills/triage/SKILL.md` Step 9 の「Dependency blocked-by check」を書き換える (2 の後、4・6 と並行可)。(a) `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh $NUMBER` を権威ソースとして blocker 一覧を取得、(b) `state` が `CLOSED` の blocker は「resolved dependency (#N is CLOSED)」として report のみ (自動修正なし — 現行踏襲)、(c) `state` が `OPEN` の blocker は「open dependency (#N is OPEN)」として report、(d) body の `Blocked by #N` テキストのうち (a) の一覧に無い N を「未設定 relationship」として tier-aware アクション (L1: advisory print / L2・L3: `set-blocked-by.sh $NUMBER $N`) の対象とする。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` を追加する (→ 受け入れ条件 2)

6. `skills/triage/SKILL.md` Step 2b「Dependency Analysis」を書き換える (5 の後)。グラフ構築を `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh --all --limit $LIMIT` の TSV 出力 (`<issue><TAB><blocker><TAB><blocker_state>`) 基点に変更し、異常検出 3 種の定義を更新する — **循環依存**: GraphQL グラフ上の DFS (検出ロジック自体は現行のまま、入力ソースのみ変更)、**解決済み blocked-by**: `blocker_state` が `CLOSED` の行 (= 陳腐化した GraphQL 関係。`gh-graphql.sh --query remove-blocked-by` での削除を推奨、自動修正なし)、**孤児依存**: GraphQL 関係では構造的に発生しえないため body テキストの衛生チェックとして再定義する (body に `Blocked by #N` があり `gh issue view N` がエラーになるケース)。「未設定 relationship の tier-aware backfill」は現行どおり維持する。あわせて Step 3 の dependency レポート書式 (`### Resolved Blocked-by` / `### Orphan Dependency`) と Step 4 の dependency コメント書式を、上記の再定義に合わせて更新する (→ 受け入れ条件 2)

7. `skills/spec/SKILL.md` Step 4「Blocked-by Detection」のコードブロックを `${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER --dry-run` から `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh $NUMBER` に差し替える (2 の後、4・5 と並行可)。exit code 0/1/2 と `HAS_OPEN_BLOCKING` の対応表はそのまま維持する。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*` を追加する (`gh-check-blocking.sh:*` は他ステップで使わないが既存エントリなのでそのまま残す) (→ 受け入れ条件 3)

8. `modules/l0-surfaces.md` の L0 Surface SSoT 表「Issue blocked-by relationships」行を更新する (4・5・6・7 と並行可)。Operations を `add, remove, read` に、Primary callers に `get-blocked-by.sh` (read) を追加する (→ 受け入れ条件 3)

9. `docs/workflow.md` § Blocked-by relationships を改訂する (8 の後)。冒頭文の「Body text such as `Blocked by #N` is a human-readable supplement only」を「入力ショートカット (書き込みトリガー) であり、判定には使われない」旨に書き換え、`### 自動設定経路` の後に `### Reading relationships` 小節 (読み取りは `get-blocked-by.sh` に一本化、`/auto` batch gate・`/triage` Step 9・Step 2b・`/spec` Step 4 が消費) を追加し、`### Scripts` 一覧に `scripts/get-blocked-by.sh` と `gh-graphql.sh --query get-open-issues-blocked-by` を追加する。`docs/translation-workflow.md` の Sync Procedure に従い `docs/ja/workflow.md` を同期する (body テキストの位置づけは日本語で「入力ショートカット」と表記) (→ 受け入れ条件 3, 6)

10. `docs/structure.md` の GitHub API utilities 一覧に `scripts/get-blocked-by.sh` の 1 行を追加し (`set-blocked-by.sh` の直後)、`docs/ja/structure.md` に同じ位置で日本語ミラーを追加する。あわせて `.claude/settings.json.template` の `permissions.allow` に `"Bash(scripts/get-blocked-by.sh *)"` を `"Bash(scripts/gh-check-blocking.sh *)"` の直後に追加し (Edit/Write ツールは `.claude/` を拒否するため `sed` か `python3` で編集)、`tests/auto-batch.bats` に List mode gate の 2 件の `@test` を追加する (9 の後) (→ 受け入れ条件 4)

### `scripts/get-blocked-by.sh` の分岐の挙動 (exhaustive)

| 分岐 | 正常終了条件 / 出力 | error path | exit code |
|---|---|---|---|
| `--help` / `-h` | usage を stdout に出力 | — | 0 |
| 引数なし | — | `Error: issue number or --all is required` を stderr + usage | 1 |
| 非数値の issue 番号 | — | `Error: issue-number must be a positive integer: <arg>` を stderr | 1 |
| 未知のオプション | — | `Error: unknown argument: <arg>` を stderr + usage | 1 |
| `--limit` が非数値または 0 以下 | — | `Error: --limit must be a positive integer: <val>` を stderr | 1 |
| 単一 Issue、blocker 0 件 | stdout に出力なし | — | 0 |
| 単一 Issue、blocker が全て CLOSED | 各 blocker につき `<number><TAB>CLOSED` を 1 行 | — | 0 |
| 単一 Issue、OPEN blocker が 1 件以上 | 各 blocker につき `<number><TAB><state>` を 1 行 (CLOSED も含め全件出力) | — | 2 |
| 単一 Issue、GraphQL 呼び出し失敗 | — | `Error: failed to fetch blocked-by for issue #<N>` を stderr | 1 |
| `--all`、blocker を持つ Issue が 1 件以上 | 各関係につき `<issue><TAB><blocker><TAB><blocker_state>` を 1 行 (blocker を持たない Issue は行を出さない) | — | 0 |
| `--all`、blocker を持つ Issue が 0 件 | stdout に出力なし | — | 0 |
| `--all`、`hasNextPage: true` | `endCursor` を `-F cursor=` に渡して次ページを取得。`hasNextPage: false` または累計取得件数が `--limit` に達したら停止 | — | 0 |
| `--all`、GraphQL 呼び出し失敗 | — | `Error: failed to fetch open-issue blocked-by graph` を stderr | 1 |

exit code 2 (OPEN blocker あり) は**単一 Issue モードのみ**のシグナルであり、`--all` は成功時つねに 0 を返す。監視ループは持たない (単発実行、全分岐で即終了)。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md の batch mode における blocked-by gate が、Issue body の grep ではなく GraphQL 経由 (gh-graphql.sh --query get-blocked-by または set-blocked-by.sh 等のスクリプト) で blocker を取得する実装になっている" --> `/auto` の batch gate が GraphQL を参照する
- <!-- verify: rubric "skills/triage/SKILL.md の依存チェック (Single Issue Execution) と Backlog Analysis の依存グラフ構築が、Issue body の Blocked by テキスト抽出ではなく GraphQL 経由で blocker を取得する実装になっている。方針 1 を採る場合、body テキストが書き込みトリガーとして残ることは許容される" --> `/triage` の依存判定が GraphQL を参照する
- <!-- verify: rubric "blocked-by 関係の SSoT が GraphQL である旨と、body テキストの位置づけ (入力ショートカットか廃止か) が docs 配下のいずれかに明記されている" --> SSoT の所在がドキュメントに明記されている
- <!-- verify: command "bats tests/auto-batch.bats" --> `tests/auto-batch.bats` が PASS する
- <!-- verify: command "bats tests/get-blocked-by.bats" --> 読み取り窓口スクリプト `scripts/get-blocked-by.sh` の bats テストが PASS する
- <!-- verify: file_contains "docs/ja/workflow.md" "入力ショートカット" --> `docs/ja/workflow.md` ミラーが body テキストの位置づけ変更に追従している

### Post-merge

- GraphQL で blocked-by を設定し body にはテキストを書かない Issue を `/auto --batch` に含め、blocker が未完了の間 skip されることを観察する (`verify-type: observation event=auto-run session=next`)

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/get-blocked-by.sh:*`: 新規スクリプト。`skills/auto/SKILL.md`・`skills/triage/SKILL.md`・`skills/spec/SKILL.md` の `allowed-tools` に追加が必要 (3 スキルとも現時点で未登録。ワイルドカードで `scripts/*.sh` を覆う既存エントリは存在しない)
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh:*`: `skills/auto/SKILL.md` の `allowed-tools` に追加が必要 (`skills/spec/SKILL.md`・`skills/issue/SKILL.md` には既に登録済み)

### Built-in Tools

- `Read` / `Edit` / `Write` / `Grep` / `Glob`: 既存の `allowed-tools` で充足。追加不要

### MCP Tools

- none

## Notes

### 方針決定 (非対話モードでの自動決定)

Issue 本文の候補 1 (読み取りを GraphQL に統一、body は入力ショートカットとして存続) を採用した。Issue 本文自身が「候補 1 が既存運用への影響が最小」と推奨しており、かつ `docs/workflow.md` の既存宣言 (body = 補足) とも整合するため。候補 2 (body 完全廃止) は既存 Issue の body に残るテキストの扱いと起票時 UX の代替設計を要し、本 Issue のスコープを超える。

### Issue 本文と既存実装の乖離 (Conflict with implementation)

- **Issue 本文の記述**: 「GitHub をワークフローの L0 SSoT とする設計思想と矛盾する」— あたかも SSoT の所在が未宣言であるかのように読める
- **実際の実装**: `docs/workflow.md` L292 は既に "GitHub native blocked-by relationships ... are the **SSoT** for Issue dependency state. Body text such as `Blocked by #N` is a human-readable supplement only" と宣言済み。`docs/ja/workflow.md` L285 にもミラーがある
- **解決**: 本 Issue を「新しい方針決定」ではなく「宣言済みドキュメントへの実装追従 (drift 解消)」と位置づけ直した。受け入れ条件 3 は既存記述の存在だけで PASS しうるため、body テキストの位置づけを「人間向け補足」→「入力ショートカット (書き込みトリガー)」に言い換え、読み取り経路を明記する変更を実装ステップ 9 に明示した。Issue 本文にもこの乖離を追記済み

### 孤児依存 (orphan dependency) の再定義

GitHub の `addBlockedBy` mutation は存在する Issue の node ID を要求するため、**GraphQL 関係が孤児になることは構造的にありえない**。したがって `/triage` の孤児検出は「GraphQL 依存グラフの異常」ではなく「body テキストの衛生チェック」として再定義した (実装ステップ 6)。この再定義により、Issue 本文の「`/triage` の孤児検出は body 側の掃除しか提案しない」という指摘は、body 側の掃除こそが孤児検出の正しい役割である、という結論に落ち着く。

### `/auto` gate での materialize 呼び出し (L0 書き込み)

判定を GraphQL のみにすると、「body に `Blocked by #N` があるが GraphQL 関係が未設定」の Issue で gate が現行より**弱く**なる。これを避けるため、List mode step 4 の判定直前に `gh-check-blocking.sh $NUMBER` (非 `--dry-run`) を実行して body ショートカットを GraphQL へ materialize する設計とした。これは L0 書き込み (`modules/l0-surfaces.md` の Issue blocked-by relationships 行) にあたるが、同じ書き込みは `/issue` Step 7 / Step 11 と `/triage` Step 9 で既に行われており、`/auto --batch` は元来 autonomous モードであるため許容範囲と判断した。

### `/spec` Step 4 は読み取りのみ (materialize しない)

`/spec` Step 4 は現行が `--dry-run` (書き込みなし) であるため、materialize を追加せず読み取り専用のまま `get-blocked-by.sh` に差し替える。`/spec` に到達する Issue は `/issue` または `/triage` を通過済みで materialize が完了している前提。`/auto` 経由では List mode step 2 の `run-issue.sh` および step 4 の materialize が先行するため、この前提はさらに強く保たれる。

### ツール検出方式の一貫性

新規スクリプトの sibling script 解決は `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` の 1 方式に統一する (`set-blocked-by.sh` / `get-sub-issue-graph.sh` と同じ)。`gh-check-blocking.sh` が採る「PATH 先行 + SCRIPT_DIR フォールバック」方式は採らない — 当該方式は `tests/gh-check-blocking.bats` が PATH 経由でモックしていた歴史的経緯 (#7) によるもので、新規テストは MOCK_DIR パターンを使うため不要。

### `.claude/settings.json.template` の編集方法

Edit / Write ツールは `.claude/` 配下を sensitive file として拒否するため、`sed` または `python3` で編集する (`modules/worktree-lifecycle.md` § "Editing `.claude/` files inside worktrees")。`.gitignore` には `!.claude/settings.json.template` の un-ignore があるため `git add` は通常どおり動作し、`git add -f` は不要。

### verify command のパターン事前確認

- `file_contains "docs/ja/workflow.md" "入力ショートカット"`: 現時点で当該文字列は存在しない。実装ステップ 9 で導入される文字列であり、日本語ミラーに英語パターンを持ち込まないよう日本語表記を選んだ
- `command "bats tests/get-blocked-by.bats"`: 実装ステップ 3 で新規作成されるテストファイル
- `command "bats tests/auto-batch.bats"`: 既存ファイル。実装ステップ 10 の `@test` 追加後も既存 10 件は PASS する必要がある。特に `blocked-by check present` (grep `blocked`) と `phase/done gate condition present` (grep `phase/done`) は List mode 書き換え後も維持されること

### 計測メモ

`grep -rn "blocked-by\|Blocked by\|blockedBy" --include="*.md" --include="*.sh" --include="*.bats" .` (リポジトリルート、`docs/sessions/` と `docs/spec/` を除外) のヒットのうち、**判定 (読み取り) に使われている箇所は 5 箇所** (`skills/auto/SKILL.md` L1117-1119、`skills/triage/SKILL.md` L233-244 / L580-601 / L750-758 / L823-824、`skills/spec/SKILL.md` L90)。残りは書き込み経路 (`gh-check-blocking.sh`、`set-blocked-by.sh`、`modules/retro-proposals.md`)、sub-issue グラフ用途 (`get-sub-issue-graph.sh`、`get-sub-issue-progress.sh` — 本 Issue のスコープ外。既に GraphQL 基点)、およびドキュメント/テスト記述。

### スコープ外

- `scripts/get-sub-issue-graph.sh` / `scripts/get-sub-issue-progress.sh` の `blockedBy` 利用: 既に GraphQL 基点であり変更不要
- `docs/guide/xl-decomposition.md` の `blocked_by` YAML キー: decomposition ファイルの入力書式であり、判定経路ではない
- `docs/ja/structure.md` に `get-sub-issue-progress.sh` の行が欠けている既存 drift: 本 Issue の変更対象外
