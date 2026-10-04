# Issue #1492: scripts: 引数なしの mktemp による /tmp 利用を一時ファイル方針に合わせる

## Overview

`docs/product.md` の Non-Goals は「`/tmp/` 配下への一時ファイル作成 (プロジェクト内の `.tmp/` を使用すること)」と定めている。一方、`scripts/` の 8 スクリプト (13 箇所) は引数なしの `mktemp` / `mktemp -d` で `$TMPDIR` (既定 `/tmp`) に一時ファイルを作っており、新しいコード (`scripts/resolve-preview-env.sh`、`modules/verify-executor.md` など) の `.tmp/` 利用と方針が混在している。Issue は「`.tmp/` への置換」と「適用範囲の明記」のどちらでも解決とみなし、どちらに倒すかを `/spec` の判断に委ねている。

本 Spec は **適用範囲の明記** で解決する (根拠は Notes「採用方針の判断」)。

- Non-Goal の対象を「Skill / module の手順が作る一時ファイル、および呼び出し元や後続の tool call にパスを引き渡す一時ファイル」と定める
- 同梱スクリプトが 1 回の実行内で完結させる private scratch (テンプレートなしの `mktemp` / `mktemp -d`) は対象外と明記する
- 詳細規則は配布対象の `modules/filesystem-scope.md` (§ Temporary Files) に置き、`docs/product.md` の Non-Goal には Scope 1 項目とポインタだけを追加する
- ユーザー向けのフットプリント宣言である `SECURITY.md` と、スクリプトヘッダーの `/tmp/` 使用例を同期する

スクリプト本体のロジックは変更しない。

## Changed Files

- `modules/filesystem-scope.md`: 一時ファイルの配置規則を追加 — `### Allowed Base Paths` 表に 1 行、`### Prohibited Patterns` の直後に `### Temporary Files` (h3) を新設、`## Approved Patterns` に `### Bash scripts — temporary files` (h3) を追加、`## Implementation Reference` に bullet 2 件を追加
- `docs/product.md`: `## Non-Goals` の `/tmp/` 項目の直下に入れ子 bullet `Scope:` を追加 (既存の 1 行は無変更)
- `docs/ja/product.md`: 上記の日本語ミラー (`## 非ゴール` の対応項目)。`docs/product.md` と同一コミットで更新する
- `SECURITY.md`: `### Local File Writes` の `.tmp/` bullet の対象を明確化し、`$TMPDIR` bullet を 1 件追加 (翻訳ミラーなし)
- `scripts/opportunistic-search.sh`: ヘッダーコメント line 15 の使用例 `--context-file /tmp/spec.md` を `--context-file .tmp/spec.md` に変更 (コメントのみ。bash 3.2+ 互換性・挙動への影響なし。同ヘッダー内の他の例 `.tmp/facts-session1.json` と揃える)
- [Steering Docs sync candidate] keyword "filesystem-scope.md" skipped: matched 11 files (no discriminating power) — 測定: `grep -rl "filesystem-scope.md" docs/ tests/ scripts/ modules/` (disposable な `docs/spec/` 6 件と `docs/reports/` 2 件を含む)

## Implementation Steps

1. `modules/filesystem-scope.md` に一時ファイルの配置規則を追加する (→ Pre-merge AC1)
   - (a) `### Allowed Base Paths` 表 (列は `Base | Example`) の末尾に次の行を追加する。表の冒頭文「All file I/O during skill execution MUST originate from one of:」と矛盾させないための行である:
     `| Script-private scratch under `$TMPDIR` | bare `mktemp` / `mktemp -d` inside a bundled script — see Temporary Files below |`
   - (b) `### Prohibited Patterns` 表の直後 (`## Approved Patterns` の直前) に `### Temporary Files` (h3) を新設し、次の本文を置く:

     ```markdown
     ### Temporary Files

     Where a temporary file lives depends on who creates it and whether its path leaves the creating process (examples, not exhaustive):

     | Creator | Placement | Rule |
     |---------|-----------|------|
     | Skill / module procedure (an LLM-executed step) | `.tmp/` in the project (gitignored) | Create with the Write tool after `mkdir -p .tmp`, or `mktemp .tmp/<name>-XXXXXX` when a shell snippet must create it. Never `/tmp/` — this is the Non-Goal in `docs/product.md` |
     | Bundled script — path handed back to the caller, or file read/removed by a later tool call | `.tmp/` (absolute `$PWD/.tmp/` path) | The path outlives the script, so it stays inside the project like any LLM-created file. Put the `X` run at the very end of the template (BSD `mktemp` does not randomize it otherwise) |
     | Bundled script — credential-bearing scratch file | `.tmp/` | Project-local and owner-only (`mktemp` creates mode 600); remove it right after use so secrets stay out of the shared `$TMPDIR` |
     | Bundled script — private scratch file | `$TMPDIR` via bare `mktemp` / `mktemp -d` (no template; default `/tmp`) | Out of scope of the Non-Goal. Created, consumed, and removed within one script invocation, and never exposed to an LLM tool call. Remove it before exit (`trap ... EXIT` or an explicit `rm`). Use `mktemp -d` when the scratch space must stay outside the working tree (e.g. the ephemeral detached git worktree in `scripts/pre-merge-check.sh`) |

     Why private scratch is out of scope: the Non-Goal keeps files that Claude creates, or hands from one tool call to the next, inside the project (gitignored, inspectable, covered by worktree isolation). A bundled script's private scratch file never crosses a tool-call boundary, and a uniquely named `mktemp` file avoids the collisions that fixed `/tmp/` names cause between concurrent sessions. A hard kill (SIGKILL) skips every cleanup path: a leftover in `$TMPDIR` can be reclaimed by the OS, whereas a leftover in `.tmp/` would persist in the project.
     ```

   - (c) `## Approved Patterns` の `### Bash scripts — use explicit paths with `find`` の後 (`### LLM skills — use scoped Glob and Grep calls` の前) に `### Bash scripts — temporary files` (h3) を追加し、次の snippet を置く:

     ```bash
     # Private scratch file: bare mktemp (default $TMPDIR), removed by the script itself
     scratch="$(mktemp)"
     trap 'rm -f "$scratch"' EXIT

     # Path handed back to the caller: project-local, absolute, X run at the very end
     mkdir -p .tmp
     out_file="$(mktemp "$PWD/.tmp/<name>-XXXXXX")"
     echo "$out_file"
     ```

   - (d) `## Implementation Reference` の末尾に次の 2 bullet を追加する (既存 bullet と同じ `` - `path` — description `` 形式):
     - `scripts/resolve-preview-env.sh` — creates credential-bearing temp files under an absolute `$PWD/.tmp/` template and hands the path back to its caller (compliant with Temporary Files)
     - `scripts/pre-merge-check.sh` — `mktemp -d` host directory for an ephemeral detached git worktree, kept outside the repository working tree; the other bare-`mktemp` scratch files in `scripts/` (enumerate with `git grep -nE '\$\(mktemp( -d)?\)' -- scripts/`) follow the same private-scratch rule (examples)
2. (parallel with 1) `docs/product.md` と `docs/ja/product.md` の Non-Goal に適用範囲を追加する。2 ファイルは同一コミットで更新する (→ Pre-merge AC1)
   - `docs/product.md` の `## Non-Goals` で、既存行 `- Creating temporary files under `/tmp/` (use `.tmp/` within the project instead)` はそのまま残し、直下に入れ子 bullet (2 スペースインデント) を追加する:
     `  - Scope: temporary files that Skill and module procedures create, or whose path is handed back to a caller or a later tool call. A bundled script's own scratch file (bare `mktemp` / `mktemp -d`, created and removed within one script invocation) is out of scope. Details: `modules/filesystem-scope.md` § Temporary Files`
   - `docs/ja/product.md` の `## 非ゴール` で、既存行 `- `/tmp/` 配下への一時ファイル作成 (プロジェクト内の `.tmp/` を使用すること)` の直下に対応する入れ子 bullet を追加する (括弧は半角 + 前後に半角スペース):
     `  - 適用範囲: Skill・module の手順が作成する一時ファイル、および呼び出し元や後続の tool call にパスを引き渡す一時ファイルが対象。同梱スクリプト自身の scratch ファイル (引数なしの `mktemp` / `mktemp -d` で作成し、1 回のスクリプト実行内で削除するもの) は対象外。詳細は `modules/filesystem-scope.md` § Temporary Files を参照`
3. (parallel with 1) `SECURITY.md` の `### Local File Writes` を更新する (→ Pre-merge AC1)
   - `.tmp/` bullet を `- **`.tmp/`** — temporary files that skill and module procedures create, or whose paths are handed between tool calls (auto-cleaned after use)` に置き換える
   - 直後に `- **`$TMPDIR`** (default `/tmp`) — short-lived scratch files that bundled scripts create with `mktemp` / `mktemp -d` (owner-only permissions) and remove before they exit` を追加する
4. (parallel with 1) `scripts/opportunistic-search.sh` のヘッダーコメント line 15 の `/tmp/spec.md` を `.tmp/spec.md` に変更する。コメント以外は触らない (→ Pre-merge AC1)
5. (after 1, 2, 3, 4) 検証する (→ Pre-merge AC2)
   - (a) 引用した識別子の実在を再確認する: `grep -n 'mktemp' scripts/resolve-preview-env.sh scripts/pre-merge-check.sh modules/verify-executor.md modules/lighthouse-adapter.md modules/browser-adapter.md`
   - (b) `bash scripts/check-translation-sync.sh` で `docs/product.md` が `IN_SYNC` であることを確認する
   - (c) Pre-merge AC2 の `bats` 8 本を実行する (bats が使えない環境では CI の `Run bats tests` の結果を参照する)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/*.sh の引数なし mktemp / mktemp -d が .tmp/ 配下を使う形に置き換えられている、または docs/product.md もしくは modules/filesystem-scope.md に『/tmp を使わない』方針の適用範囲 (スクリプト内部の mktemp を対象外とするか) が明記され、実装と矛盾しない状態になっている" --> 一時ファイルの方針と実装が一致している
- <!-- verify: command "bats tests/gh-issue-edit.bats tests/post_merge_check.bats tests/pre-merge-check.bats tests/wait-ci-checks.bats tests/claude-watchdog.bats tests/gh-pr-review.bats tests/audit-retention.bats tests/run-fact-matching.bats" --> 影響するスクリプトの bats が PASS する

### Post-merge

- 次回 `/auto` の実行後、`/tmp` にこのリポジトリのスクリプト由来の一時ファイルが残っていないことを確認する (スクリプト内部の `mktemp` を Non-Goal の対象外とする方針で解決した場合は N/A として扱う) <!-- verify-type: opportunistic -->
  - 本 Spec は適用範囲の明記で解決するため **N/A** (Notes「Post-merge の N/A の扱い」を参照)

## Notes

### 採用方針の判断 (non-interactive auto-resolve)

- **採用: 適用範囲の明記** (Non-Goal の対象を LLM 実行手順とパスの引き渡しに限定し、スクリプト private scratch は対象外とする)。auto-resolve の条件「既存パターンから一意に推論できる」に該当する
- 根拠 1 — 既存規約との一貫性: #1308 (`scripts/post_merge_check.sh`) は `/tmp/<template>` を run-scoped な bare `mktemp -d` に置換し、`scripts/pre-merge-check.sh` の同形式を「既存の形式」として採用した。`.tmp/` + テンプレートを使うのは、LLM が実行する module 手順 (`modules/verify-executor.md:344` の curl config、`modules/lighthouse-adapter.md:40` のヘッダーファイル、`modules/browser-adapter.md:84` の screenshot) と、資格情報を扱う / 呼び出し元にパスを返すファイル (`scripts/resolve-preview-env.sh`、#1417・#1429) に限られる。この線引きをそのまま明文化できる
- 根拠 2 — 置換案のリスク (いずれもコード / テストで確認済み):
  - `scripts/pre-merge-check.sh:86` の `mktemp -d` は ephemeral な detached git worktree (`git worktree add --detach`) の親ディレクトリで、`.tmp/` 配下に移すとリポジトリ作業ツリー内に入れ子の checkout を作る
  - EXIT trap は SIGKILL では走らない。`scripts/claude-watchdog.sh` と `scripts/pre-merge-check.sh` は trap ではなく明示的な `rm` で後始末しており、外部 kill はこのリポジトリで繰り返し観測されている失敗モードである (`docs/tech.md` § Two-tier orchestration)。`$TMPDIR` の残骸は OS の定期クリーンアップや再起動で回収されうるが、`.tmp/` の残骸はプロジェクト内に残り続ける
  - 相対 `.tmp/` は CWD 依存である。`scripts/resolve-preview-env.sh:249-256` のコメントが記録している通り、呼び出し元の CWD が worktree だとパスが解決できない問題が実在した。`mkdir -p .tmp` の失敗経路も増え、fail-open 設計のスクリプト (`scripts/apply-run-fact-match.sh` は「`/auto` を abort しない」) に新しい失敗モードを足す
  - `tests/wait-ci-checks.bats` の restricted-PATH テストは、依存コマンドごとにラッパー (`jq` / `date` / `mktemp` / `grep`) を用意している (setup の 51-89 行)。`mkdir` の追加はこのテスト基盤の変更を伴う
  - 8 スクリプトはいずれも終了前に一時ファイルを削除しており (Issue Retrospective の確認と一致)、`/tmp` 残留は通常発生しない。13 箇所 + bats 8 本の変更に見合う実益がない
- 根拠 3 — Non-Goal の趣旨: Claude が作る、または tool call 間で受け渡すファイルをプロジェクト内 (gitignore 済み・worktree 分離の対象) に留めること。スクリプト private scratch は tool call に露出しないため当てはまらない
- 不採用: (a) 8 スクリプト・13 箇所を `.tmp/` ベースに置換 (根拠 2 のリスク)、(b) 一部のみ置換するハイブリッド (規則の境界が暗黙になり、説明が二重化する)
- 追加の判断: `SECURITY.md` を同期対象に含めた。`### Local File Writes` はユーザー向けのフットプリント宣言で、一時ファイルの置き場所を `.tmp/` のみとして記述しているため、方針の明記だけでは別の場所に不一致が残る (不採用: `docs/product.md` / `modules/filesystem-scope.md` のみ更新)

### Issue 本文と既存実装の整合

Background の事実主張 (Non-Goal の文言、8 スクリプトとその行番号、新しいコードの `.tmp/` 利用) をすべて実装と照合し、一致した。乖離なし。

### 測定スコープ

- 引数なし `mktemp`: 8 ファイル・13 箇所 (scope: `scripts/` の git 管理ファイル、パターン `$(mktemp)` / `$(mktemp -d)`、コマンド: `git grep -nE '\$\(mktemp( -d)?\)' -- scripts/`)。内訳は `apply-verify-retire.sh` が 6、他 7 ファイルが各 1
- テンプレート付き `.tmp/` の `mktemp`: `scripts/resolve-preview-env.sh` の 3 箇所 (scope: 同上、コマンド: `git grep -nE 'mktemp[^)]*\.tmp/|mktemp "\$PWD/\.tmp' -- scripts/`)
- `scripts/` 外: `install.sh`・`examples/`・`.github/`・`.claude/`・`tests/helpers` に `mktemp` / `/tmp` の使用なし (`git grep -nE 'mktemp|/tmp' -- install.sh examples .github .claude tests/helpers`)
- `.tmp/` を含まない `/tmp` の直接参照 9 行 (scope: `scripts/ modules/ skills/ agents/ hooks/ docs/` の git 管理ファイル、`docs/spec/` `docs/sessions/` `docs/reports/` を除く、コマンド: `git grep -n '/tmp' -- scripts/ modules/ skills/ agents/ hooks/ docs/ ':!docs/spec/' ':!docs/sessions/' ':!docs/reports/' | grep -v '\.tmp/'`): `scripts/opportunistic-search.sh:15` (使用例 — Step 4 で修正)、`scripts/validate-skill-syntax.py:52` (禁止パターンの正規表現 — 無関係)、`modules/verify-executor.md:397` (`cd /tmp` のアンチパターン解説 — 無関係)、`docs/versioning.md:149-151` と `docs/ja/versioning.md:140-142` (範囲外 — 下記)

### Fail-safe critical / 識別子検証

- fail-safe critical: スクリプトを変更しないため edge case の規定は不要。置換案 (不採用) で最も影響が大きい `scripts/apply-run-fact-match.sh` は fail-open 設計で、この点も不採用の根拠の 1 つ
- audit/investigation-type: no — 目的は方針と実装の整合であり、項目ごとの分類を後続プロセスが判断根拠として読む成果物ではない。ただし追加する文書が引用する識別子 (`scripts/resolve-preview-env.sh` の `.tmp/` テンプレート、`scripts/pre-merge-check.sh` の `mktemp -d` と `git worktree add --detach`、上記 3 つの module の `.tmp/` 使用) は実在を grep で確認済み。Step 5 (a) で再確認する

### allowed-tools impact chain

`modules/*.md` 変更の Case 2 ゲート (追記内容が `scripts/*.sh` パスを含む) に該当する。reader の列挙 (`grep -rl "modules/filesystem-scope\.md" skills/*/SKILL.md`) は `skills/spec/SKILL.md` のみで、L417 は参照ポインタであり "Read and follow" ではない。追記内容は既存スクリプトの引用のみで新しいスクリプト呼び出しを導入しないため、`allowed-tools` の追加は不要。

### テスト

- スクリプト無変更のため、Pre-merge AC2 の bats 8 本は回帰ガードとして機能する。新規ロジックは追加しないので新規テストケースは不要 (New test case requirement の対象外)
- この環境には `bats` が未導入 (CI は `apt-get install bats`) で、ベースラインを実測できなかった。代わりに main HEAD `9e1ce776` の CI `Test` workflow が success (2026-10-04T06:53:10Z) であることを確認した。`bats` が使えない環境では `command` AC は CI の `Run bats tests` の結果を参照して判定する
- 追記先の文書を参照する bats はない (`grep -rln -E 'product\.md|filesystem-scope|Non-Goals' tests/` が 0 件)

### 翻訳同期・他文書の確認

- `docs/product.md` は top-level `docs/*.md` のため `docs/translation-workflow.md` の同期対象。`scripts/check-translation-sync.sh` は git タイムスタンプで OUTDATED を判定するので、`docs/ja/product.md` を同一コミットで更新する。追記にコードフェンスはなく、フェンス数の一致確認は自明。`SECURITY.md` に翻訳ミラーはない (`ls SECURITY*.md docs/ja/SECURITY*` で確認)
- 変更不要と判断 (確認済み): `docs/structure.md:150` / `docs/ja/structure.md:143` の `modules/filesystem-scope.md` Key Files 説明 (「filesystem access scope constraints and approved patterns for skills/scripts」) は追記後も正確。`docs/tech.md` に `/tmp` / `.tmp/` の方針記述はない
- Outbound pointer sync candidate: なし。Listing-side sub-check: サブコマンド・ファイルの追加/削除/改名・ディレクトリ構造の変更を伴わないためスキップ
- Size 再評価: Changed Files 5 件 (Axis 1: M) だがドキュメント中心 (スクリプトはコメントのみ、Axis 2: −1) で S のまま。CI Dependency Minimum Override の対象なし。route は patch

### 範囲外の観察

`docs/versioning.md:149-151` (および `docs/ja/versioning.md:140-142`) の Gate 4 チェック (c) が `> /tmp/en.txt` / `> /tmp/ja.txt` のリダイレクトを使う。リリースゲートの手順であり、Skill / module / script が作る一時ファイルではないため本 Issue の範囲外とし、変更しない。Claude がこの手順を実行する場合は Bash リダイレクトと `/tmp` の両方に当たるので、必要ならフォローアップ Issue で扱う (候補: プロセス置換で一時ファイルを不要にする)。

### Post-merge の N/A の扱い

Issue 本文の Post-merge 条件は「スクリプト内部の `mktemp` を Non-Goal の対象外とする方針で解決した場合は N/A として扱う」と自ら定めている。本 Spec はこの方針で解決するため N/A である。`/verify` は opportunistic 条件が未チェックで残ると `phase/verify` を維持するので (`skills/verify/SKILL.md`)、N/A として明示的にチェックして閉じること。

### `/code` へのメモ

- 追記文の言語: `modules/filesystem-scope.md` / `docs/product.md` / `SECURITY.md` は英語、`docs/ja/product.md` は日本語 (括弧は半角 + 前後に半角スペース)
- Changed Files に `.claude/` 配下はなく、`git add -f` は不要
- Pre-merge AC1 の rubric は 2 つの解決方法のうち「適用範囲の明記」側で PASS する。文書に「スクリプト内部の `mktemp` は対象外」と読める記述 (`docs/product.md` の Scope と `modules/filesystem-scope.md` の Temporary Files) が残っていること

## Code Retrospective

### Deviations from Design
- なし。Implementation Steps 1-4 を Spec どおりに実装した (テキストは Spec の記載をそのまま使用)。

### Design Gaps/Ambiguities
- Pre-merge AC2 (`bats` 8 本) はこの実行環境に bats が未導入のためローカルで評価できなかった。スクリプト本体は無変更 (`scripts/opportunistic-search.sh` のコメント 1 行のみ) で、`bash -n` による構文確認のみ実施。AC2 は未チェックのまま残し、push 後の CI `Run bats tests` の結果で確認する (Step 14)。
- `filesystem-scope.md` の `### Prohibited Patterns` 表の最終行の Fix 列は Spec 想定の文言と異なっていた (`Always pass ...` で始まる行) が、挿入位置 (表の直後・`## Approved Patterns` の直前) に影響はなかった。

### Rework
- なし (`### Temporary Files` 挿入の Edit が 1 回アンカー不一致で失敗し、行末の文言を合わせて再実行した程度)。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の方針どおり「適用範囲の明記」で解決した。スクリプト本体の `mktemp` は変更していない。
- `docs/product.md` と `docs/ja/product.md` は同一コミットで更新し、`check-translation-sync.sh` で `IN_SYNC` を確認した。

### Deferred Items
- Pre-merge AC2 (`bats` 8 本の PASS): bats 未導入のため pending post-push CI confirmation (Step 14)。
- Post-merge の `/tmp` 残留確認 (opportunistic) は Spec 方針により N/A。`/verify` で N/A として明示的にチェックして閉じること。

### Notes for Next Phase
- Pre-merge AC1 (rubric) は `/code` で PASS 判定してチェック済み。
- `docs/versioning.md` の Gate 4 `/tmp/en.txt` リダイレクトは範囲外のまま (Spec Notes「範囲外の観察」参照)。

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective (曖昧点の自動解決と、8 スクリプトとも EXIT trap 等で後始末済みのため適用範囲明記が有力候補という所見) / https://github.com/saitoco/wholework/issues/1492#issuecomment-5977500709
