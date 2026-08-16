# Issue #1363: run-fact-matching: fact_tokens過剰マッチ・空フィルタ全件返却・checkbox失敗時のコメント孤立を修正

## Overview

run-fact AC reconciliation パイプライン (`modules/run-fact-matching.md`) を構成する3スクリプトに、Issue #1157 の refinement 作業 (ローカル stale worktree に未コミットのまま埋もれていた) 由来の独立した3件のバグが残っている。本 Issue はこれらを修正し、トークンフィルタ精度と L0 write (checkbox/comment) の整合性不変条件を回復する。

- **Bug 1**: `scripts/collect-run-facts.sh` — `.issue` キーが欠落したイベントが文字列 `"null"` として `ISSUE_NUMBERS` に混入し、存在しない issue の fact エントリが生成される
- **Bug 2**: `scripts/scan-pending-ac.sh` — `--facts` に空の `fact_tokens` 集合が渡されると、フィルタガードが無効化され候補が無フィルタで全件返却される
- **Bug 3**: `scripts/apply-run-fact-match.sh` — checkbox 書き込み (`gh-issue-edit.sh --checkbox --check`) が失敗しても audit-trail コメントが無条件に投稿され、「チェック済み」を主張する孤立コメントが残る

`/spec` 実行時点のコードベース実測により、Issue 本文が参考として添付した diff の一部が現状の `main` と乖離していることを確認した (詳細は `## Notes`)。Issue 本文の Pre-merge AC1〜3 には、Triage AC audit コメント (MEMBER, first-class) の指摘を受け、新規回帰テストの存在を個別に確認する `grep` verify command を追加済み (本 Spec 作成と同一セッション内、`gh-issue-edit.sh` 経由)。

## Reproduction Steps

3件とも `/spec` 実行時に現行 `main` に対して fixture を用いて実機確認済み。

1. **Bug 1**: `AUTO_EVENTS_LOG` に `{"issue":"null",...,"event":"phase_start",...}` と正常な issue イベントを含む JSONL を用意し、`collect-run-facts.sh --session <id> --no-github` を実行すると、`issues[]` に `{"number":null,...}` という不正エントリが混入する。
2. **Bug 2**: `{"session_id":"s1","issues":[]}` (fact_tokens が空集合になる facts ファイル) を用意し、`scan-pending-ac.sh --facts <path>` を実行すると、フィルタが機能せず `phase/verify` Issue の未チェック post-merge 候補が無条件に全件返る。
3. **Bug 3**: `gh-issue-edit.sh` が失敗する mock を `WHOLEWORK_SCRIPT_DIR` 経由で差し込み、`apply-run-fact-match.sh --issue 42 --ac 3 --verdict satisfied` (`--dry-run` なし) を実行すると、`Warning: failed to check AC ...` が出力されるにもかかわらず `gh-issue-comment.sh` が呼ばれ、audit-trail コメントが投稿される。

## Root Cause

1. **Bug 1**: `ISSUE_NUMBERS` の抽出は `jq -r 'select(.issue != null and .issue > 0 and ...) | .issue'` (collect-run-facts.sh:144)。jq の型順序ではあらゆる文字列があらゆる数値より大きいと定義されるため、`.issue` が JSON 文字列 `"null"` (JSON リテラル `null` ではない) の場合 `.issue != null` (型が異なるため真) と `.issue > 0` (文字列 > 数値で真) の両方を満たしてしまい、フィルタを通過する。後続の `for N in $ISSUE_NUMBERS` ループ (collect-run-facts.sh:234) には `"0"` の sentinel チェックはあるが `"null"` 文字列のチェックが無く、`--argjson n "null"` が JSON リテラル `null` として解釈されるため `ISSUE_FACT` の `number` フィールドに `null` がそのまま代入される。なお、Issue 本文が記載する「バレの phase 名 (`issue`/`spec`/`review` 等) が `fact_tokens` に混入する」問題は、`JQ_PASS2` の `fact_tokens` 生成が既に `$names | map(wrapper_for(.)) | map(select(. != null))` (バレの phase 名を含まない形) になっており、**#1238 で main に反映済み**。今回対応が必要なのは `.issue` 文字列 `"null"` の混入のみ。
2. **Bug 2**: `if [ -n "$FACT_TOKENS_LOWER" ]; then` (scan-pending-ac.sh:202) は `--facts` 自体が指定されているかどうかではなく、パース結果の `$FACT_TOKENS_LOWER` が空文字列かどうかで分岐している。`--facts` ファイルの `issues[]` が空、または全 issue の `fact_tokens` が空の場合、このガードが false になり、トークン一致チェックのループ全体がスキップされて `MATCHED` が未定義のまま次のフィルタ (Rule 1/Rule 2) に進み、結局候補として採用される。「マッチするトークンが無ければ空を返す」という意図と逆の動作になっている。
3. **Bug 3**: `if [ "$ACTION" = "auto-check" ] && [ "$DRY_RUN" = false ]; then` ブロック (apply-run-fact-match.sh:153-170) 内で、checkbox 書き込み (`gh-issue-edit.sh`, 154行目) の失敗は `Warning:` を出力するのみで後続処理を止めない。`COMMENT_FILE` 作成・`gh-issue-comment.sh` 呼び出しは checkbox 書き込みの成否と無関係に実行される。`modules/run-fact-matching.md` の「`auto-check` はチェックボックス更新と同じ呼び出しで audit-trail コメントを投稿するため、次の `scan-pending-ac.sh` 実行時に同じ候補が再度候補化されることはない」という設計上の不変条件が、checkbox 書き込み失敗時には成立しなくなる。合わせて `TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1)` (121行目) には `get-config-value.sh` 自体の失敗に対するフォールバックが無く、`set -euo pipefail` により本スクリプト自体が異常終了しうる。

## Changed Files

- `scripts/collect-run-facts.sh`: `for N in $ISSUE_NUMBERS` ループの `[ "$N" = "0" ] && continue` の直後に `[ "$N" = "null" ] && continue` を追加 (bash 3.2+ 互換、既存の sentinel チェックと同型)
- `scripts/scan-pending-ac.sh`: `if [ -n "$FACTS_PATH" ]; then ... fi` ブロック内、`FACT_TOKENS_LOWER` パース直後に空チェックを追加し、空の場合は stderr 警告 + `[]` 出力 + `exit 0` (bash 3.2+ 互換)
- `scripts/apply-run-fact-match.sh`: `auto-check` 処理を「checkbox 書き込み成功時のみ audit-trail コメントを投稿する」構造に再編し、`get-config-value.sh` 呼び出しに `2>/dev/null || echo L1` フォールバックを追加 (bash 3.2+ 互換)
- `tests/run-fact-matching.bats`: 上記3バグに1:1対応する回帰テストを3件追加 (既存35ケースは変更なし)

## Implementation Steps

1. `scripts/collect-run-facts.sh` の `for N in $ISSUE_NUMBERS` ループに `.issue` 文字列 `"null"` 除外ガードを追加する (→ acceptance criteria AC1)
2. `scripts/scan-pending-ac.sh` の `--facts` 処理に、パース後の `FACT_TOKENS_LOWER` が空の場合の早期 `[]` 返却を追加する (→ acceptance criteria AC2)
3. `scripts/apply-run-fact-match.sh` の `auto-check` ブロックを、checkbox 書き込み成功時のみ audit-trail コメントを投稿する構造に再編し、`get-config-value.sh` 呼び出しに fail-open フォールバック (`2>/dev/null || echo L1`) を追加する (→ acceptance criteria AC3)。フォールバックの動作方針: `get-config-value.sh` 自体が失敗した場合は `modules/detect-config-markers.md` の既存の autonomy tier フォールバック規則 (不正値は最も安全な `L1` にフォールバック) と揃え、`L1` を採用する。この fail-open フォールバックは既存の3回帰テストの対象外 (Issue 本文 Notes に明記の通り、回帰テストは3バグに1:1対応)
4. `tests/run-fact-matching.bats` に回帰テストを3件追加する (→ acceptance criteria AC1, AC2, AC3, AC4)。テスト名 (既存の `"<script-prefix>: <description>"` 命名規則を踏襲):
   - `collect-run-facts: issue field serialized as the string null is excluded from issues[]`
   - `scan-pending-ac: --facts with empty fact_tokens set returns empty array`
   - `apply-run-fact-match: checkbox write failure prevents audit-trail comment`
5. (after 1, 2, 3, 4) `bats tests/run-fact-matching.bats` をローカル実行し、既存35件 + 新規3件の計38件が全て PASS することを確認する (→ acceptance criteria AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/collect-run-facts.sh の fact_tokens 生成が、バレの phase 名 (issue/spec/review 等) を含まず、ラッパースクリプト名 (run-review.sh 等) のみを含むようになっている。また .issue キー欠落によるイベントの文字列 null は issue 番号として扱われない" --> <!-- verify: grep "issue field serialized as the string null" "tests/run-fact-matching.bats" --> collect-run-facts.sh の fact_tokens 精度が改善されている
- <!-- verify: grep "contains no fact tokens" "scripts/scan-pending-ac.sh" --> <!-- verify: grep "facts with empty fact_tokens set" "tests/run-fact-matching.bats" --> scan-pending-ac.sh が --facts の fact_tokens が空の場合に空配列を返し全件フォールバックしないようになっている
- <!-- verify: rubric "scripts/apply-run-fact-match.sh の action=auto-check 処理が、checkbox 書き込み (gh-issue-edit.sh --checkbox --check) が成功した場合のみ audit-trail コメントを投稿するようになっている" --> <!-- verify: grep "checkbox write failure prevents audit-trail comment" "tests/run-fact-matching.bats" --> checkbox 書き込み失敗時に孤立した audit-trail コメントが投稿されない
- <!-- verify: command "bats tests/run-fact-matching.bats" --> 上記3件それぞれの回帰テストを含め、bats テストスイート全体が PASS する

### Post-merge

なし

## Notes

### Issue本文添付 diff との乖離 (`/spec` codebase 実測、Notes 記載)

Issue 本文に添付された diff は #1157 直後の stale worktree 由来で、現在の `main` から一部乖離している。実装は本 Spec が実測した現状のソースを基準とする:

- バグ1のうち「バレの phase 名除外」部分 (`JQ_PASS1`/`JQ_PASS2` の `wrapper_for` 関連 hunk) は **#1238 で既に `main` に反映済み**。添付 diff のその部分は適用不要。未対応は `.issue` キー欠落によるイベントが文字列 `"null"` として `ISSUE_NUMBERS` に混入する経路のみ。
- `scripts/scan-pending-ac.sh` の `gh issue list --label "phase/verify" --state closed ...` は **#1242 で `--state all` に変更済み**。添付 diff のコンテキスト行 (`--state closed`) は現状と異なるため、実装は現状の `--state all` 行に対して適用する。
- truncation note の文言変更 hunk (`deferred to the next run.` → `... this list order is stable ...`) はどの AC にも対応しないためスコープ外とし、適用しない。

### verify command の常時 PASS リスク対応 (Auto-Resolve)

Triage AC audit コメント (Consumed Comments 参照、MEMBER・first-class) が、元の AC4 (`command "bats tests/run-fact-matching.bats"` 単体) は新規テストを1件も追加しなくても既存35ケースの PASS だけで常時成功する (Pattern 2) と指摘し、`bats --filter '<新規テスト名>' ...` への絞り込みを提案した。

`/spec` で `bats --filter` を実機検証 (Bats 1.13.0) したところ、フィルタに一致するテストが0件でも `1..0` を出力して exit 0 (成功) を返すことを確認した。これは指摘対象の問題を形を変えて再導入するリスクがあるため、`--filter` 単体は不採用とした。代わりに、本リポジトリの直近の precedent (#1279, #1334) が確立した「`grep` による新規テスト文字列の存在確認 (実装前は不一致) + `command "bats tests/<file>.bats"` による全件 PASS 確認」の2段構えパターンを踏襲し、AC1〜3 それぞれに対応する新規テスト名の `grep` verify command を追加した (AC4 の `command` はそのまま全件確認用として維持)。Issue 本文にも同内容を反映済み。

### Fail-safe critical script の edge case (`scripts/apply-run-fact-match.sh`)

`apply-run-fact-match.sh` は checkbox 自動チェックの可否を決めるゲートスクリプトであるため、依存コマンド失敗時の挙動を明記する: `get-config-value.sh` 呼び出し失敗時は `L1` (最も安全な tier) にフォールバックする (fail-open)。checkbox 書き込み失敗時は audit-trail コメントを投稿しない (Bug 3 の修正そのもの)。`gh-issue-comment.sh` 自体の失敗は既存どおり stderr 警告のみで `exit 0` (fail-open、`/auto` を止めない)。

## Consumed Comments

- saito (MEMBER, first-class, 2026-08-15T12:21:30Z): Triage AC audit — (1) Pre-merge AC4 の verify command (`command "bats tests/run-fact-matching.bats"`) が新規テスト追加なしでも常時 PASS するリスクを指摘、`bats --filter` への絞り込みを提案。(2) AC1 の rubric が要求する fact_tokens 改善のうち「バレの phase 名除外」部分は #1238 で既に main に反映済みであり、Notes 添付の diff は現状の実装と乖離しているため、実装時は現状のソースを実測すべきと助言。両指摘とも本 Spec に反映済み (前者は #1279/#1334 の precedent パターンへ発展させて採用、後者は `## Root Cause` および `## Notes` に反映)。https://github.com/saitoco/wholework/issues/1363#issuecomment-5302197700

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 をそのまま実施した。Spec の `## Notes` が指摘した通り、Issue 本文添付の参考 diff のうち「バレの phase 名除外」部分 (#1238 で反映済み) は適用せず、`.issue` 文字列 `"null"` 除外ガードのみを `collect-run-facts.sh` に追加した。

### Design Gaps/Ambiguities

N/A — Spec の Root Cause / Notes が現状ソースとの乖離点を明記していたため、実装中に新たな曖昧点は発生しなかった。

### Rework

N/A

### Smoke Test

Spec に `## Smoke Test` セクションなし — スキップ (no-op)。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Root Cause/Notes の指示通り、Issue 本文添付の参考 diff のうち #1238 で main に反映済みの「バレの phase 名除外」部分は適用せず、`.issue` 文字列 `"null"` 除外ガードのみを追加した。
- 3スクリプトの修正は Spec Changed Files の記述通りの最小差分で実施 (`collect-run-facts.sh` は1行、`scan-pending-ac.sh` は5行、`apply-run-fact-match.sh` は auto-check ブロックの構造変更 + fail-open フォールバック1行)。
- `scripts/scan-pending-ac.sh` が Spec に記載のない `tests/scan-pending-ac.bats` からも参照されていることを Step 9 の behavioral change detection で検出したため、全 bats スイート (1790件) を並列実行して回帰がないことを確認した。

### Deferred Items
- None

### Notes for Next Phase
- Pre-merge AC1〜4 は全て verify-executor 相当の手動実行で PASS 済み、Issue チェックボックスも更新済み。`/review` では追加の rubric/grep 再実行で同じ結果になるはず。
- Post-merge AC は「なし」。`/verify` は実質何もすることがない想定。
