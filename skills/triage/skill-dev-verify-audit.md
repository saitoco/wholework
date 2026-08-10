---
type: domain
skill: triage
---

# AC Verify Command Integrity Audit

This Domain file defines the verify command audit patterns for the `/triage` skill.
Used in: Step 7 (Single Issue Execution), Bulk Execution Step 3 substep 7, and `/issue` Existing Issue Refinement Step 15 (regardless of `triaged` label state).

## Purpose

Detect defective `<!-- verify: ... -->` patterns in Issue AC sections before they
propagate to the `/verify` phase and produce false PASSes or false FAILs.

Proven value: In the 2026-06-13 `/auto` session, triage caught verify command defects
in 3 of 14 Issues (21%) — preventing downstream quality failures.

## Processing Steps

1. Extract all `<!-- verify: ... -->` comments from the issue body
2. For each extracted verify command, check against the patterns below
3. Collect all findings
4. If any findings exist, post a single audit comment to the Issue (see ## Non-Destructive Audit Behavior)
5. If no findings, skip silently — do not post an empty comment

## Patterns

### Pattern 1: grep 引数順誤り (Reversed grep Arguments)

Detect: `grep "path/to/file" "pattern"` — a path appears as the first argument
instead of the search pattern. This is the 引数順（引数の順序）誤り anti-pattern.

Indicators that the first argument is a path (not a pattern):
- Ends with a recognized file extension: `.md`, `.sh`, `.py`, `.yml`, `.yaml`, `.json`, `.txt`
- Contains `/` (path separator) — path-like string

Example of incorrect grep 引数順:
```
<!-- verify: grep "skills/triage/SKILL.md" "some pattern" -->
```

Correct form (pattern first, path second):
```
<!-- verify: grep "some pattern" "skills/triage/SKILL.md" -->
```

Fix: swap the two arguments so the search pattern comes first.

### Pattern 2: 常時 PASS な verify command (Always-PASS Command)

Detect: A `file_contains` or `grep` verify command whose search string already
exists in the target file on the `main` branch — before this PR lands.

If the string is already present, the command always returns PASS regardless of
whether the PR's change is correct. It provides no verification signal.

Detection approach:
- Run the grep/file_contains check against the current `main` branch
- If the result is already PASS, flag as 常時 PASS (always-PASS)

Fix options:
- Choose a string that will appear only after the change lands
- Switch to `section_not_contains` or `file_not_contains` to assert removal instead

**exit code 設計に起因する常時 PASS (`command` 型 AC)**:

`command` 型の verify command は、対象スクリプトが明示的な失敗条件フラグ（例: `--fail-if-outdated`）を渡さない限り常に exit 0 を返す informational 専用の設計になっている場合、実装の正誤に関わらず常時 PASS になる。

例: `<!-- verify: command "bash scripts/check-translation-sync.sh" --> ` — `check-translation-sync.sh` は `--fail-if-outdated` を渡さない限り常に exit 0 を返す (スクリプト冒頭に "Always exits 0 (informational only)" と明記されている)。

Detection approach:
- `command` 型 AC の対象スクリプトのソースを確認し、失敗時に非ゼロの exit code を返す設計かどうかを検証する
- フラグなしでは常に exit 0 を返す設計の場合、常時 PASS として検出する

Fix options:
- スクリプトに失敗条件フラグ（`--fail-if-outdated` 等）を明示的に渡す
- スクリプトの exit code 設計自体を、失敗時に非ゼロを返すよう修正する

**既存テストファイルの実行に起因する常時 PASS (`command` 型 AC)**:

`command` 型の verify command の対象が既存テストファイル/スイートであり、かつ AC 本文が新規テストケース・新規カバレッジの追加を主張している場合、実装前の `main` で対象コマンドが既に exit 0 を返すなら、新規テストを 1 件も追加しなくても常時 PASS になる。

例: `#1279` (`command "bats tests/get-auto-session-report.bats"` が「新規テストケース追加」を主張していたが、実装前の main でも既存 12 ケースが全 PASS していたため常時 PASS だった。`/issue` Step 15 が検出し、`bats --filter '<新規テスト名>' <file>` へ絞り込むことで解消した) と `#1287` (同型の常時 PASS を `/issue` Step 15 が「問題なし」と誤判定し、検出漏れとなった) を参照。

Detection approach:
- (a) `command` 型 AC の対象が新規追加ファイルではなく既存テストファイル/スイートか確認する
- (b) 実装前の `main` ブランチの状態で対象コマンドを空撃ちする
- (c) 空撃ちが既に exit 0 を返し、かつ AC 本文が新規テストケース・新規カバレッジの追加を主張している場合、常時 PASS として検出する
- (d) AC 本文が回帰保護のみを主張しており新規カバレッジの追加を主張していない場合は、検出対象外とする (既存スイート全体を走らせる回帰保護 AC 自体は正当であり禁止しない)

Fix options:
- `bats --filter '<新規テスト名の一意な部分文字列>' <file>` の形へ絞り込む (`#1279` で採用)
- 新規テストのフィクスチャや識別子を対象とした `grep` 型 AC を別途併記し、既存スイート実行は回帰保護 AC として役割を分ける
- テストファイル自体が新規追加なら `command "bats <新規ファイル>"` は判別可能なため変更不要

**`section_contains`/`section_not_contains` 型に起因する常時 PASS**:

`section_contains` 型の verify command は、対象ファイルの main ブランチ時点で、指定 heading セクション内に検索文字列が既に存在する場合、実装前から常時 PASS になる。`section_not_contains` は逆に、対象文字列が既に不在の場合に常時 PASS になる。

例: `<!-- verify: section_contains "modules/worktree-lifecycle.md" "Consumed Comments" "Comment Consumption" -->` — 先行 Issue の着地により "Comment Consumption" という語が既に該当セクションに存在していると、本 Issue の実装を待たず常時 PASS になる (実測: #1078)。

Detection approach:
- 対象ファイルを Read し、`modules/verify-executor.md` の `section_contains` 仕様通り (heading 行から次の同格以上見出しの直前まで、または EOF まで) にセクションを切り出す
- 切り出したセクション本文に対して現状の `main` ブランチの内容のまま検索文字列を空撃ちする (grep 相当)。既に一致していれば `section_contains` の常時 PASS として検出する。`section_not_contains` は不一致 (文字列が既に不在) であれば常時 PASS として検出する

Fix options:
- main ブランチにまだ存在しない文字列を選ぶ、または実装後にのみ真になる heading/検索文字列へ変更する
- `section_contains` ⇄ `section_not_contains` を実装意図と逆に選んでいないか確認し、必要なら切り替える

**`github_check` 型に起因する常時 PASS**:

`github_check` 型の verify command は、`gh_command` を現状の repository 状態に対して実行した結果が既に `expected_value` を含む場合、実装前から常時 PASS になる。特に `gh issue view`/`gh pr view` で Issue/PR の既存ラベルやタイトルの一部を検証している場合に起こりやすい。

例: `<!-- verify: github_check "gh issue view $NUMBER --json labels" "triaged" -->` — Issue に triage 実行時点で既に `triaged` ラベルが付与されていれば、実装 0 行で常時 PASS になる。

Detection approach:
- safe mode の allowlist 対象コマンド (`gh issue view`/`gh pr view`/`gh pr checks`/`gh api` GET/`gh run view`) であれば、現状の repository 状態に対してそのまま `gh_command` を空撃ちで実行し、出力に `expected_value` が既に含まれるか確認する。既に含まれていれば常時 PASS として検出する
- allowlist 外のコマンド (full mode 限定) は空撃ちせず、`gh_command` が参照する対象 (issue/PR 番号・フィールド) が実装前から存在しうるものかをレビューで判定する

Fix options:
- 実装後にのみ真になる状態を参照する `gh_command`/`expected_value` に変更する
- post-merge の observation 型 AC へ移す

**`rubric` 型に起因する常時 PASS**:

`rubric` 型の verify command は、grader が現状の (実装前の) 状態を rubric text の条件に照らして既に満たしていると判定する場合、実装前から常時 PASS になる。既存の類似実装の説明文をそのまま rubric text に再利用すると特に起こりやすい (実測: 本 Issue 自身の起票時点の AC1 が、Pattern 6 の説明文を流用した結果、既存の Pattern 2 が該当すると解釈されかけた)。

例: `<!-- verify: rubric "Pattern 6 と同じ構造で新規 Pattern が追加されている" -->` — Pattern 2 が既に同じ構造 (症状・検出手順・修復案) を備えているため、grader が Pattern 2 を該当と解釈すると常時 PASS になりうる。

Detection approach:
- audit を実行している LLM 自身が、rubric text の主張を現状のリポジトリ内容 (Grep/Read) に照らして空撃ちする — 「rubric text が要求する条件を、実装前の現状が既に満たしていないか」を判定する
- 既存の類似実装が rubric text の主張範囲に含まれてしまわないか、Grep で類似の見出し・キーワードを検索して確認する

Fix options:
- 現状のリポジトリ内容 (diff で変更される具体的な範囲) を rubric text に明示的に含める
- 既存の類似実装を rubric text 内で明示的に除外する文言を追加する

**定義が構造的に充足不能な AC (複数量の同時成立不能)**:

AC が複数の量 (分母・分子、件数と割合など) を同時に要求している場合、それらが同一の実行単位で同時に取得できないと、実装をどう進めても AC 自体が構造的に充足不能になる。実装側の不足ではなく AC の定義自体の矛盾であるため、grader は UNCERTAIN と判定する。

例: #1270 の Pre-merge AC1 は「observation dispatch における SKIPPED 率 (分母: 1 回の dispatch で候補に挙がった observation AC 行数、分子: そのうち SKIPPED を返した行数)」を要求していたが、`skills/auto/SKILL.md` Step 5 の dispatch は `observation-dispatch-threshold` (既定 5) 件を上限とするため、分母 85 に対し分子は構造上 5 が上限となり、率として意味をなさない。`/verify 1270` はこの AC を UNCERTAIN と判定した。

Detection approach:
- (a) AC が複数の量を同時に要求しているか確認する
- (b) 一方の取得が設定値やスクリプトの構造的上限で制約されるか確認する
- (c) 判定が難しい場合は検出せず素通しする (偽陽性を避ける — この監査は非破壊コメントであり、過剰指摘は起票者の負担になる)

Fix options:
- 両方の量を同一実行単位で取得できる形へ AC を書き換える
- 一方の量のみを baseline として記録する形へ単位を揃える (#1270 が採った方法 — 率を諦めて母集団の実数に統一)
- 比較対象となる post-merge AC も同じ単位へ揃える (片方だけ直すと baseline と post-merge が別の量を測ることになる)

### Pattern 3: 常時 FAIL な verify command (Always-FAIL Command)

Detect: A `file_contains` or `grep` verify command whose search string has already
been removed from the target file on `main` — before this PR lands.

If the string is already absent, the command always returns FAIL regardless of
the PR's content. It will block the PR unnecessarily.

Detection approach:
- Run the grep/file_contains check against the current `main` branch
- If the result is already FAIL, flag as 常時 FAIL (always-FAIL)

Fix: Update the expected string to match what the implementation will actually produce.

### Pattern 4: patch route × `gh pr checks` 不整合

Detect: Issues with Size XS or S and `ALWAYS_PR=false` (patch route) whose AC uses
`github_check "gh pr checks"`.

The patch route commits directly to `main` without creating a PR. Therefore,
`gh pr checks` will never find a matching pull request and the check always FAILs.

Detection approach:
- In Single Issue Execution: read the Size assigned in Step 6 (Size Assignment)
- In Bulk Execution (Step 3 substep 7): read the `size` field from the Step 2 classification
  JSON for the current issue
- In `/issue` Existing Issue Refinement (Step 15): read Size via `get-issue-size.sh $NUMBER`
  (same call as `/issue`'s own Step 6); `ALWAYS_PR` is retained from `/issue`'s Step 4
  (Reference Steering Documents).
- `ALWAYS_PR` is retained from `skills/triage/SKILL.md`'s "Configuration Detection" section
  (a common section that precedes both Single Issue Execution and Bulk Execution). When
  `ALWAYS_PR=true`, skip Pattern 4 entirely — `always-pr: true` promotes Size XS/S to pr route,
  so `github_check "gh pr checks"` is the correct form (see `modules/size-workflow-table.md`
  § "ALWAYS_PR Override")

Fix: Replace `github_check "gh pr checks"` with a `github_check "gh run list"` form,
for example:
```
github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

If multiple workflow files exist under `.github/workflows/`, add `--workflow=<filename>`
to target the specific workflow.

### Pattern 5: Destructive Command Safety Check

Detect: verify commands that contain destructive operations, such as:
- `rm`, `mv`, `cp` (filesystem mutations)
- `gh issue close`, `gh issue delete`, `gh issue edit`
- `gh pr merge`, `gh pr close`
- Any command that modifies external state as a side effect

Verify commands are executed by the `/verify` skill as acceptance tests. They should
be read-only. Destructive commands in verify context can cause irreversible side
effects on Issues, PRs, or the filesystem.

Fix: Remove the destructive command from the verify context and mark the AC line as
`verify-type: manual` so a human performs the check instead.

### Pattern 6: 常時 UNCERTAIN な verify command (Always-UNCERTAIN Command)

Detect: 以下 5 つのサブパターンのいずれかに該当する verify command は、実装が正しくても
判定不能 (UNCERTAIN) になる。

1. **heading 引数に先頭の `#` を含める**: `section_contains`/`section_not_contains` の
   heading 引数（第 2 引数）に見出し記号 `#`/`##`/`###` を含めている。
   `modules/verify-executor.md` の `section_contains` 仕様は、見出し行から先頭の `#` と
   空白を除去したうえで部分一致するため、`"### Step 1"` は `## Step 1` にも `### Step 1`
   にもマッチせず「No heading matched」で恒久的に UNCERTAIN になる。
   例: `<!-- verify: section_contains "path/to/file.md" "### Step 1" "text" -->`
   修復案: heading 引数から先頭の `#` を除去する —
   `<!-- verify: section_contains "path/to/file.md" "Step 1" "text" -->`

2. **存在しないファイルパスを参照**: verify command が参照するファイルパスがリポジトリに
   存在しない。
   例: `<!-- verify: section_contains "modules/nonexistent.md" "Step 1" "text" -->`
   修復案: 実装が生成する実際のファイルパスに修正する。

3. **引数個数不足**: verify command 種別が要求する引数の個数が不足しており、構文エラーに
   なる。
   例: `<!-- verify: file_contains "path/to/file" -->` (text 引数欠落)
   修復案: 欠落している引数を補う。

4. **未定義のコマンド名**: `modules/verify-executor.md` が定義していない verify command
   種別を使用している。
   例: `<!-- verify: file_has "path" "text" -->`
   修復案: `modules/verify-executor.md` が定義する既存の verify command 種別
   (`grep`, `file_contains`, `section_contains`, `command`, `github_check`, `rubric` 等)
   に置き換える。

5. **対応する CI job のない safe mode 限定コマンドを Pre-merge に置く**: `command` 型
   verify command を Pre-merge AC に配置しているが、`/review` の safe mode では任意コマ
   ンド実行が許可されないため、対応する CI job の結果を参照する CI reference fallback に
   頼ることになる。対応する CI job が存在しない場合、恒久的に UNCERTAIN になる。
   例: `<!-- verify: command "bash scripts/some-custom-check.sh" -->` を Pre-merge に置く
   が、`.github/workflows/` に対応する CI job がない。

   `command` 型 AC を Pre-merge に置いてよい判定基準:
   - (a) 対応する CI job が存在し、`/review` の CI reference fallback が解決できる
   - (b) スクリプトが失敗時に非ゼロの exit code を返す設計である

   どちらも満たさない場合は、Post-merge へ移すか `verify-type: manual` を付与する。

Fix: 該当する verify command を上記の修復案に従って修正する。UNCERTAIN が解消できない
場合は Post-merge へ移すか `verify-type: manual` を付与する。

## Non-Destructive Audit Behavior

This audit is **non-destructive**: triage does NOT auto-edit the Issue body.

When problems are detected, triage posts a comment to the Issue with the findings and
suggested fixes. The user then decides whether and how to update the Issue body.
This avoids destructive behavior in cases where `/issue` may regenerate the AC.

**Self-generated AC (自己生成 AC)**: this non-destructive policy applies unconditionally
even when the audited AC was authored within the same execution that runs this audit —
e.g. AC produced by `/issue` Existing Issue Refinement's own Step 7 classification,
Step 9 Issue body reflection, or Step 12 sub-issue redistribution. The audit does not
distinguish 自己生成 AC from externally-authored AC and does not auto-edit the Issue body
for either. This determinism is deliberate: defining a boundary for "authored within the
same execution" is ambiguous when `/triage` Step 2's auto-chain invokes `/issue` — from a
user's perspective this is a single continuous operation, but from the skill's perspective
it spans two separate invocations. Making the audit's judgment depend on that ambiguous
boundary would reintroduce non-deterministic behavior into the very check this rule exists
to prevent. Observed divergence before this rule was made explicit: Issue #1220 followed
the non-destructive default (comment-only), while Issue #1221 deviated by auto-editing the
Issue body — both audited AC self-generated within the same `/issue` execution.

**Repair handoff for self-generated AC**: because the Issue body is never auto-edited, a
defective 自己生成 AC is fixed only once a downstream phase picks up the audit comment.
This works without any new mechanism: the Comment Consumption Procedure
(`modules/l0-surfaces.md`) already treats Issue comments as first-class context for
whichever phase runs next — `/spec` for Size S/M/L/XL, or `/code` directly for Size XS
(whose patch route skips `/spec`). Either phase reads the comment as prompt-equivalent
input and applies the suggested fix as part of its own work.

**Post the audit comment** only when at least one pattern match is found.
If no patterns match, skip without posting.

### Comment Format Template

```
⚠️ Triage AC audit: verify command に問題があります

- AC: `<!-- verify: grep "skills/triage/SKILL.md" "some pattern" -->`
  - Pattern: grep の引数順誤り（第 1 引数がパス様文字列）
  - 修復案: `<!-- verify: grep "some pattern" "skills/triage/SKILL.md" -->`

- AC: `<!-- verify: github_check "gh pr checks" "Run bats tests" -->`
  - Pattern: patch route（Size S）× `gh pr checks` 不整合
  - 修復案: `<!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->`
```

### Posting the Comment

`$NUMBER` refers to the current Issue number (in Bulk Execution, the per-loop issue number).

```bash
mkdir -p .tmp
# Write comment body to .tmp/triage-audit-comment-$NUMBER.md using the Write tool
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/triage-audit-comment-$NUMBER.md
rm -f .tmp/triage-audit-comment-$NUMBER.md
```
