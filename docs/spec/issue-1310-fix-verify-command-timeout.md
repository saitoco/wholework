# Issue #1310: verify-executor: command の 60 秒タイムアウトで全件テストスイート検証が不能な状態を解消

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Issue Retrospective — 対象 AC (「上記いずれかの対応方針が設計され...検証可能になっている」) を Pre-merge から Post-merge (`verify-type: manual`) へ再分類済みであることを確認。`/issue`/`/spec` 責務境界 (`docs/product.md` § Responsibility Boundary) により、対応方針 (案1/2/3) の選定と「妥当な形で」の判定基準は `/spec` の裁量に委ねる設計を維持 (Auto-Resolve: 現状維持)。機械チェック (`check-ac-checkbox-format.sh` / `check-skill-change-observation-ac.sh`) は exit 0、本 Issue に BRE メタ文字を含む `grep` verify command なし。 / URL: https://github.com/saitoco/wholework/issues/1310#issuecomment-5235047373

## Overview

`modules/verify-executor.md` の `command "cmd"` verify type は実行タイムアウトが固定 60 秒であり (§ Timeout Coverage Audit)、`bats tests/` のような全件テストスイート実行を要求する verify command は構造的に検証不能 (恒常的 UNCERTAIN) になる。Issue 本文が提示する 3 案 (新 verify type 新設 / タイムアウト設定可能化 / 起票ガイドライン是正) のうち、**案 3 (起票ガイドラインの是正) のみ**を採用する。既存の `github_check` (Job-Level Conclusion Sub-Form 含む) が CI 参照によるタイムアウト非依存の検証経路を既に提供しており、新規メカニズムの追加は不要と判断した (判断根拠は Notes を参照)。

あわせて、案 3 に付随する追加スコープ (件数依存 AC の該当 0 件時の判定規約。#1251 / #1294 からの繰越分) を `modules/verify-patterns.md` に追加し、繰越スコープの行き場を本 Issue 内で確定させる。

## Reproduction Steps

1. `/code 1304` の Step 10 (verify command consistency check) で、Issue #1304 の AC5 `<!-- verify: command "bats tests/" --> 既存テストスイートが PASS する` を `modules/verify-executor.md` の Processing Steps に従って実行する。
2. `bats --jobs 18 tests/` (並列実行) は完了する (1640/1642 PASS) が、`command` type 固定 60 秒 (§ Timeout Coverage Audit) を超過する。
3. `bats tests/` (serial 実行、AC5 が指定する厳密な形) は Bash tool の 600 秒上限を超過してもなお完了せず、バックグラウンドへ自動移行する。

## Root Cause

`modules/verify-patterns.md` §24 (Behavioral Changes — Prefer Full Test Suite for Verify Commands) が、全件スイート実行を要求する behavioral-change AC の「正しい verify command」として `command "bats tests/"` (および同型の `pytest` / `pnpm test` / `npm test`) を直接推奨している。一方 `modules/verify-executor.md` § Timeout Coverage Audit は `command` type の実行タイムアウトを固定 60 秒と定めている。両者は互いに矛盾しており、Wholework 自身のテストスイート規模 (1642 件、2026-08-10 時点) では §24 の推奨形が常に UNCERTAIN に終わる。Issue #1304 の AC5 はこの矛盾したガイドラインに従って `/issue` フェーズで生成された典型例である。

なお §24 の「Definition of behavioral changes」「Detection heuristic (2 checks)」自体 (behavioral change の判定基準) は `skills/code/SKILL.md:333` から直接参照される SSoT であり、本 Issue の修正対象ではない — 修正対象は同セクション内の「検出後にどの verify command 形式を使うか」の推奨部分のみ。

## Changed Files

- `modules/verify-patterns.md`: §24 (Behavioral Changes — Prefer Full Test Suite for Verify Commands) の「Scope trade-off」「Recommended scope by test framework」表・「Decision procedure」・Issue #819 実例の結論行を、全件スイート検証時は `github_check` CI 参照形を使う形へ修正 (直接 `command "<full-suite-cmd>"` 実行の推奨を撤回)。「Definition of behavioral changes」「Detection heuristic」は変更しない。あわせて末尾 (`## Output` 直前、§27 の直後) に新設 §28 "Count-Dependent Conditional Acceptance Criteria — Default Judgment for Zero-Count Case" を追加。
- `modules/verify-executor.md`: § Timeout Coverage Audit の表の直後・「Out of scope」段落の直前に、全件複数ファイルテストスイート実行に `command` type を使わないよう警告する注記を追加 (`modules/verify-patterns.md` §24 と「github_check: Job-Level Conclusion Sub-Form」への相互参照)。

## Implementation Steps

1. `modules/verify-patterns.md` §24 を修正する (→ Post-merge AC)。「Scope trade-off」表のヘッダーを「Command example」→「Logical test scope」に変更する (verify command の実際の形式と混同しないため)。「Recommended scope by test framework」表を、narrow scope (直接 `command`) と full suite (CI 参照 `github_check`) の 2 列構成に置き換える。full suite 列は本リポジトリの `.github/workflows/test.yml` の `bats` job (`name: Run bats tests`) を対象にした job-level conclusion sub-form を bats の具体例として明記する:
   ```
   github_check "gh run view $(gh run list --workflow=test.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\").conclusion'" "success"
   ```
   `command` type の 60 秒固定タイムアウト (`modules/verify-executor.md` § Timeout Coverage Audit) が全件スイート実行では構造的に超過することを説明する注記を追加し、patch route (`--branch=main` 形、`modules/verify-classifier.md` § Patch Route CI Verification Note 参照) と PR route (job-level sub-form、`--branch=main` を付けない) の使い分けを明記する。「Decision procedure」に「full suite の場合は CI 参照形を使う。直接 `command "<full-suite-cmd>"` は書かない」ステップを追加する (3 ステップ→4 ステップ)。「Real example (Issue #819)」の結論行 (`Correct verify command: bats tests/ (full suite)`) を上記 CI 参照形に更新する。
2. `modules/verify-executor.md` の § Timeout Coverage Audit 表の直後・「Out of scope」段落の直前 (after 1, parallel with 3) に、全件複数ファイルテストスイート実行を `command` で書かないよう警告する段落を追加する。`modules/verify-patterns.md` §24 と本ファイル内の「github_check: Job-Level Conclusion Sub-Form」への相互参照を含める (→ Post-merge AC)。
3. `modules/verify-patterns.md` の §27 の直後・`## Output` の直前 (parallel with 1, 2) に新設 §28 "Count-Dependent Conditional Acceptance Criteria — Default Judgment for Zero-Count Case" を追加する。含める内容: (a) 既定判定「該当件数が 0 であることが成果物に明記されていれば PASS」、(b) 条件文で既定を上書きしたい場合は条件文自身に明記する旨、(c) 既存 §26 (Absence-Verifying Acceptance Conditions) との関係 (§26 は「0 という結果自体が vacuous scan による偽陽性でないか」を確認する authoring-time の規約、本節は「confirmed genuine な 0 件をどう判定するか」という judgment-time の既定ルールで、両者は補完関係にある)、(d) 実例として Issue #1275 Pre-merge AC 4/5 (分類 D=0 により両 AC が vacuously satisfied となった事例) を引用する (→ Pre-merge AC1, AC2)。

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-classifier.md (または採用案に応じた規約ファイル) に、件数に依存する AC の該当 0 件時の判定ルールが記述されている。案 3 を採らない場合は、本項目を引き継ぐ Issue 番号が Spec に記録されていること" --> 件数に依存する AC について、該当件数が 0 の場合の判定ルールが記述規約に追加されている
- <!-- verify: rubric "採用案に応じた規約ファイルに、件数依存 AC の該当 0 件時の既定判定 (成果物に 0 件と明記されていれば PASS) が読み取れる形で記述されている" --> 追加された規約に該当 0 件時の判定に関する記述が含まれている

### Post-merge

- 上記いずれかの対応方針が設計され、`command "bats tests/"` 相当の AC が UNCERTAIN に終わらず妥当な形で検証可能になっている <!-- verify-type: manual -->

## Notes

- **採用案の判断根拠**: Issue 本文の 3 案のうち案 3 のみを採用した。理由: `github_check` (Job-Level Conclusion Sub-Form 含む、`modules/verify-executor.md` に既存) は既に CI 参照によるタイムアウト非依存の検証経路を提供しており、CI (`.github/workflows/test.yml` の `bats` job) は既に全件スイートを並列実行し、パラレル限定 flake を serial 再実行で切り分ける仕組み (`docs/tech.md` § CI bats Parallel/Serial Split) まで備えている。案 1 (新 verify type 新設) はこの既存経路の重複実装になる。案 2 (`command` タイムアウトの設定可能化) は、`command` が呼び出し元セッションの Bash tool 内で実行される制約自体は変わらないため、タイムアウト値を伸ばしても Issue 本文が実測した「serial 実行が 600 秒の Bash tool 上限を超過する」問題を解消しない (parallel 実行を強制しない限り再現しうる)。`/issue` フェーズの Issue Retrospective (Consumed Comments 参照) は「対応方針の選定は `/spec` の責務」として明示的にこの判断を委ねている。
- **`docs/environment-adaptation.md` の Eager-load 制約との整合確認**: 同ドキュメント § Extension Guide は「新規 capability の usage guidance は `modules/verify-patterns.md` への直接追加を避け Domain file 化する」と定めているが (Eager-load vs Lazy-load 表の該当行)、これは `.wholework.yml` の `capabilities.*` で有効化される新規 capability 固有のガイドラインに限定される規約であり、`docs/environment-adaptation.md` § Extension Guide の対象は「新規 capability の追加」手順である。本 Issue の変更 (§24 修正・§28 新設) はいずれも capability 非依存の汎用 AC 記述ガイドラインであり (既存 §1-27 も同様に capability 非依存の内容で、いずれも Domain file 化されていない)、この制約の対象外と判断した。
- **0 件判定規約の格納先**: Issue 本文は `modules/verify-classifier.md` を例示先として挙げているが、同ファイルの Purpose は「post-merge 条件の verify-type 分類基準」に限定されており、この規約が実際に問題化した #1275 の実例は Pre-merge の rubric AC だった。`modules/verify-patterns.md` は `/issue` `/spec` 双方が参照する pre/post-merge 共通の AC 記述ガイドライン集であり、既存 §26 (Absence-Verifying Acceptance Conditions) と主題的に連続するため、そちらへ §28 として追加する。Pre-merge AC の rubric 文言は「(または採用案に応じた規約ファイル)」を許容しており、この選択と矛盾しない。
- **#1251 / #1294 からの繰越の解消**: 「件数 0 の AC の判定ルール」は元々 #1251 への追記として提案されたが、コメント投稿タイミングが #1251 の L0 消費カットオフ (`phase/issue` 付与時刻: 2026-08-08T23:29:13Z) より前だったため未反映のまま #1251 が `phase/done` でクローズされた (2026-08-09T00:17:09Z)。本 Issue が案 3 を採用したことで、この繰越スコープは本 Issue 内で解消され、新たな follow-up Issue の起票は不要である。
- Issue #1304 の AC5 (`command "bats tests/"`) 自体の書き換えは本 Issue のスコープ外 (Issue 本文 Notes に明記されている)。`/verify 1304` 実行時に同じ UNCERTAIN 判定を受ける見込みだが、これは Issue #1304 側の解決事項として残す。
