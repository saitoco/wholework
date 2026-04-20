# Issue #281: test: core module shallow bats テスト追加 (adapter-resolver / size-workflow-table / domain-loader / doc-checker)

## Overview

複数 skill から参照される 4 つの prompt-based core module (`adapter-resolver`, `size-workflow-table`, `domain-loader`, `doc-checker`) に shallow bats テストを追加し、key heading / 契約文言 / section 構造の欠落を CI で smoke 検知する。実装は `tests/verify-rubric.bats` (#271) / `tests/review-rubric-safe.bats` (#275) と同じ grep / awk ベースの shallow 方針で、LLM 応答自体は mock せず assertion しない。

## Changed Files

- `tests/adapter-resolver.bats`: new file — 4 section 存在 + "capability" / "3-layer" 文言検証。bash 3.2+ 互換(grep/awk のみ)
- `tests/size-workflow-table.bats`: new file — "2 axes" 文言 + XS/S/M/L/XL 5 段階 table 行 + workflow route (patch/pr) 文言検証
- `tests/domain-loader.bats`: new file — `.wholework/domains/` path + Markdown load 契約文言検証
- `tests/doc-checker.bats`: new file — README.md/CLAUDE.md/workflow.md 参照 + "missed updates" / "command example" 文言検証

## Implementation Steps

1. `tests/adapter-resolver.bats` 作成 — `PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"` で module path を解決し、(i) `## Purpose` / `## Input` / `## Processing Steps` / `## Output` の 4 section 見出し存在、(ii) "capability" 文言、(iii) "3-layer" または "resolution order" 文言、の 3 テスト (→ AC 1)

2. `tests/size-workflow-table.bats` 作成 — (i) "2 axes" 文言、(ii) XS/S/M/L/XL 5 行の table 行存在(`| XS` / `| S` / `| M` / `| L` / `| XL` の 5 パターン存在)、(iii) "patch" および "pr" workflow route 文言、の 3 テスト (→ AC 2)

3. `tests/domain-loader.bats` 作成 — (i) `.wholework/domains/` path 記述、(ii) "Markdown" 文言、(iii) "Glob" または "Discover" または "load" のいずれか(discovery 契約)、の 3 テスト (→ AC 3)

4. `tests/doc-checker.bats` 作成 — (i) "README.md" と "CLAUDE.md" と "workflow.md" の 3 参照存在(1 テストで 3 grep の連続 assertion)、(ii) "missed updates" 文言、(iii) "command example" 文言、の 3 テスト (→ AC 4)

5. ローカルで `bats tests/adapter-resolver.bats tests/size-workflow-table.bats tests/domain-loader.bats tests/doc-checker.bats` 実行し 4 ファイル全 PASS を確認 (→ AC 5)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/adapter-resolver.bats" --> `tests/adapter-resolver.bats` が新規作成されている
- <!-- verify: file_exists "tests/size-workflow-table.bats" --> `tests/size-workflow-table.bats` が新規作成されている
- <!-- verify: file_exists "tests/domain-loader.bats" --> `tests/domain-loader.bats` が新規作成されている
- <!-- verify: file_exists "tests/doc-checker.bats" --> `tests/doc-checker.bats` が新規作成されている
- <!-- verify: command "bats tests/adapter-resolver.bats tests/size-workflow-table.bats tests/domain-loader.bats tests/doc-checker.bats" --> 追加 4 テストがローカルで PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 追加テストを含む全 bats テストが CI で PASS する
- <!-- verify: rubric "各 bats は実装(LLM応答)を mock していない — 文書存在 + 文言 grep + section 構造の shallow 検証に留まっている" --> shallow test 方針が維持されている

### Post-merge

- (なし)

## Notes

- **shallow test 方針の前例**: `tests/verify-rubric.bats` (#271)、`tests/review-rubric-safe.bats` (#275)。`PROJECT_ROOT` 解決パターン、grep/awk による文言確認、LLM 応答 mock 禁止の 3 点を踏襲
- **bash 3.2+ 互換**: `mapfile`(bash 4+)や `readarray` は使わない。`awk /pattern/,/^### /` の range pattern は macOS BSD awk で start 行を二重出力するので、範囲 body 内で `{f=1; next}` を使う形(#275 Code Retrospective 参照)
- **section 見出し検証**: markdown heading は `grep -q "^## Purpose"` のように `^` 付き完全一致ではなく、`grep -q "## Purpose"` の行内部分一致にする(他 section 先頭との衝突回避は現状不要)
- **table 行検証 (size-workflow-table)**: `| XS` / `| S ` / `| M ` / `| L ` / `| XL` で検出(ただし `| S ` は `| XS` の右側にもマッチする可能性があるため、table cell の完全一致 `^\| XS ` のように `^` 付きで区別。`| S ` と `| XS` 衝突回避のため `grep -qE "^\| XS\|"` などで cell 境界を取る)
- **doc-checker の "command example"**: doc-checker.md L47 の "command examples" に部分一致する。"command example" で十分
- **CI 反映**: 既存 CI 設定は `tests/*.bats` を glob で全実行する形と想定(bats 呼出の shell 展開頻度は review-rubric-safe.bats 追加時と同じパターンが動作した実績あり)
- **`command` hint の UNCERTAIN 扱い**: AC 5 の `command "bats ..."` は safe モード(`/review`)で UNCERTAIN を返すが、CI 反映(AC 6 の `github_check`)で担保される
- **Issue との整合**: Issue 本文の AC 7 項目と本 Spec Verification > Pre-merge の 7 項目は 1:1 対応

## Code Retrospective

### Deviations from Design
- N/A（設計通り実装）

### Design Gaps/Ambiguities
- `domain-loader.bats` の discovery 契約テストで `-i` フラグを追加（`grep -qiE`）。"Glob" は大文字、"Discover" は大文字、"load" は小文字と混在するため、case-insensitive にした方が将来変更に頑健と判断。Spec では `grep -qiE "Glob|Discover|load"` という形は明示されていなかったが意図に合致。

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の AC は 7 件すべてに verify command 付き。rubric (AC 7) による semantic validation の組み込みも適切。Post-merge 条件なし。

#### design
- Spec の実装ステップは各 bats ファイルの test 内容と 1:1 対応しており設計の明確さは高い。
- Code Retrospective（PR #282 diff より）: `domain-loader.bats` で `-i` フラグを追加（`grep -qiE`）。モジュール内テキストの大文字混在への対処で意図に合致した小修正。

#### code
- Code Retrospective より: N/A 設計通り実装。Rework なし。

#### review
- Review Retrospective より: MUST/SHOULD/CONSIDER 0件。実装と Spec が完全一致。AC 5 (`command "bats..."`) safe モードで UNCERTAIN → AC 6 CI fallback で代替 PASS という 2 条件の組み合わせ設計は妥当。

#### merge
- 本 verify 実行時点では PR #282 は未マージ（OPEN）。通常フロー（merge → verify）が守られなかった。

#### verify
- `/verify 281` が PR マージ前に実行されたため、条件 1〜5 が「ファイル未存在」で FAIL。これは実装コードの問題ではなく verify のタイミング起因。
- 条件 7 (rubric) は PR #282 diff を proxy として評価し PASS 判定。

### Improvement Proposals
- `/verify` スキルが OPEN PR 存在・未マージ状態で呼び出された場合、"PR #N is open but not merged — run `/verify` after merging" という早期警告を Step 2 に追加することで、タイミング起因のフォールス FAIL を防げる。
