# Issue #1435: verify-patterns: 複数ファイル対象 command verify command の early detection を追加

## Overview

`modules/verify-patterns.md` に新規パターン `### 32.` を追加し、AC 作成時点 (`/issue` Step 4/7、`/spec` 自身の AC 作成ステップ = 本 Step 10 — いずれも既に `modules/verify-patterns.md` を Read している) で `command` verify command の引数が複数ファイルパス (スペース区切りの複数ファイル指定、または 2 件以上にマッチする glob) を対象にしているケースを検出し、`modules/verify-executor.md` の Timeout Coverage Audit を参照した警告と `github_check` への言い換えを促す。

既存の `modules/verify-patterns.md` §24 (Behavioral Changes — Prefer Full Test Suite for Verify Commands) は「既存ファイルの修正 + 他テストからの参照」という意味的トリガーであり、本 Issue が意図する「`command` 引数自体が複数ファイルパスを含むかどうか」という構文的トリガーとは独立している (新規追加ファイルのみを対象とする `command` は §24 の対象外だが、本チェックの対象にはなる)。この独立性は §32 の本文で明記し、rubric grader が §24 の既存記述だけで満たされていると誤判定しないようにする。

## Changed Files

- `modules/verify-patterns.md`: `## Output` の直前 (§31 "Literal Numeric Pinning ACs — Concurrent PR Resilience" の末尾の後) に `### 32. Multi-File \`command\` Verify Commands — Early Timeout-Risk Detection` セクションを追加
- [Steering Docs sync candidate] keyword "verify-patterns.md" skipped: matched 149 files (no discriminating power) — 全キーワードがフィルタでスキップされたため、これ以上の enumeration は行わない

## Implementation Steps

1. `modules/verify-patterns.md` の `## Output` 見出し直前に `### 32. Multi-File \`command\` Verify Commands — Early Timeout-Risk Detection` を新規追加する (→ acceptance criteria A, B)
   - **検出ヒューリスティック (いずれかで発火)**: (a) `command` の引数が単一のテストランナー呼び出しに対しスペース区切りで 2 件以上のファイル/パスを渡している (例: `command "bats tests/foo.bats tests/bar.bats"`)、(b) 引数中の shell glob (`*`, `?`, `[...]`) が 2 件以上にマッチしうるパスセグメントを含む (例: `command "pytest tests/test_*.py"`)
   - **検出時のアクション**: `modules/verify-executor.md` § Timeout Coverage Audit を参照し、multi-file `command` 呼び出しはマッチするファイル/テスト数が増えるほど実行時間が読めなくなるタイムアウトリスクパターンであると警告し、§24 のフレームワーク別 `github_check` (CI reference) 形への言い換えを推奨する
   - **§24 との関係を明記する独立したパラグラフ**: 本チェックは構文的 (`command` 引数のテキストのみを見る) であり、§24 は意味的 (既存ファイル修正 + 他テストからの参照を見る) — 両トリガーは独立でどちらか一方のみが発火しうる (新規ファイルのみの追加は §24 対象外だが本チェックには該当し得る、逆に単一ファイルを対象とする `command` の §24 該当ケースは本チェックには該当しない) ことを明記し、rubric grader が一方の記述のみで他方を「既に満たされている」と誤判定しないよう注意書きを添える
   - ❌/✅ 例を 1 件含める: `command "bats tests/new-foo.bats tests/new-bar.bats"` (新規追加ファイルのみ — §24 の purely-additive 除外には該当するが本チェックの構文的トリガーには該当する) → `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md のパターンテーブル (または skills/issue/spec-test-guidelines.md、skills/spec/SKILL.md のいずれか、もしくは複数) に、複数ファイルパスを対象とする command verify command を AC 作成時点で検出し github_check への言い換えを促す軽量チェックが追加されている" --> 複数ファイルパスを対象とする `command` verify command を AC 作成時点 (`/issue` の AC 作成ステップまたは `/spec` の AC 作成ステップ) で検出し、`github_check` への言い換えを促す警告チェックが追加されている
- <!-- verify: rubric "追加された検出チェックの警告文言が modules/verify-executor.md の Timeout Coverage Audit の推奨 (github_check への切替) と矛盾しない" --> 追加したチェックが `modules/verify-executor.md` の Timeout Coverage Audit の記述と整合している

### Post-merge

なし

## Notes

- **Consumed Comments を反映した設計判断**: `/triage` (Step 15 AC Verify Command Integrity Audit) が投稿した audit コメントで、AC1 の rubric が「§24 の既存記述だけで満たされている」と誤判定されるリスク (Pattern 2: rubric 型に起因する常時 PASS リスク) が指摘された。§24 のトリガーは意味的 (既存ファイル修正 + cross-file test coupling)、本 Issue が意図するのは構文的 (`command` 引数が複数ファイルパスを含むか) であり両者は独立。この指摘を受け、実装は §24 を書き換えるのではなく独立した新規 `### 32.` セクションとして追加し、セクション本文中に §24 との関係 (独立したトリガー条件) を明記するパラグラフを含めることとした。
- **`docs/environment-adaptation.md` の capability extraction ガイドとの非該当確認**: 同ファイル 470 行目・486 行目に「新規 capability のガイダンスは `modules/verify-patterns.md` のような eager-load 共有モジュールに直接セクション追加せず、`load_when: capability: {name}` で gate した Domain file に分離すること」という記述がある。この規則は「Adding a new capability」という拡張ガイドの一部であり、`capabilities.{name}` ゲート付きの新機能固有のガイダンス (例: Figma, visual-diff) を対象にしたものである。本 Issue が追加する内容は特定の capability に紐づかない汎用的な AC 品質ガイドライン (既存の §1, §24, §31 等と同種) であり、この規則の対象外と判断した。
- **§32 という番号付け (既存セクションのリナンバーなし)**: §25-31 を繰り下げて §24 の直後に挿入する案も検討したが、`modules/verify-executor.md` 側に `modules/verify-patterns.md` §24 への相互参照が既に存在し (Timeout Coverage Audit 内)、リナンバーはこの参照および将来のリナンバー対象範囲拡大のリスクを伴う。末尾追記 (§32) はこのリスクを避けつつ、`## Output` 直前という既存の一貫した挿入位置規約に従う。
- **新規テストケース要否の判断**: `modules/verify-patterns.md` は LLM が Read して従うプレーンテキストのガイドラインであり、スクリプト/モジュールへの新規分岐ロジック追加ではないため、「新規ブランチロジックに対する新規テストケース要件」チェックの対象外と判断した (既存の `tests/verify-heuristics.bats` 等は `grep -q` による存在確認のみで、セクション数を数えるものではなく、本追加によって既存テストが失敗することはない)。

## Consumed Comments
No new comments since last phase.
