# Issue #1449: verify-patterns: 残存する gh run list in_progress 検出漏れパターンの例示を更新

## Overview

#1444 で `modules/verify-executor.md` に `gh run list`/`gh run view` 系 `github_check` verify command の in_progress 検出制約を明記し、canonical テンプレート (`modules/verify-classifier.md` § "Patch Route CI Verification Note") と、実際に verify command を生成する auto-fix ロジック 2 箇所 (`skills/verify/SKILL.md`, `skills/spec/SKILL.md`) を `--json conclusion,status --jq 'if .[0].status != "completed" then "in_progress" else .[0].conclusion end'` 形式に更新済み。

本 Issue はその残りの例示/ガイダンス箇所 (`docs/versioning.md` / `docs/ja/versioning.md` / `skills/triage/skill-dev-verify-audit.md` / `skills/issue/spec-test-guidelines.md` / `skills/issue/SKILL.md` / `modules/verify-patterns.md`) を、status を合成する推奨パターンに揃える。`docs/spec/issue-*.md` 配下の使い捨て Spec ファイルおよび `docs/reports/` 系の過去レポートは対象外 (Issue 本文で明示)。

調査の結果、対象ファイル内には workflow レベル (`--json conclusion --jq '.[0].conclusion'`) だけでなく job レベル (`--json jobs --jq '.jobs[] | select(...).conclusion'`) の同種パターンも残存していることが判明した。また `modules/verify-executor.md` 自身の "github_check: Job-Level Conclusion Sub-Form"節の使用例 (Issue 本文の対象ファイル一覧には含まれない) も未更新だったため、追加スコープとして本 Spec に含める (詳細は `## Notes`)。

## Changed Files

- `docs/versioning.md`: リリースゲート表の「Base branch CI is green」行に `status` を追加し、in_progress を green と誤認しないことを明記 (単発 verify command テンプレートとは形が異なるための適応的修正、詳細は Notes)
- `docs/ja/versioning.md`: 上記の日本語ミラー更新 (`docs/translation-workflow.md` の同期対象)
- `skills/triage/skill-dev-verify-audit.md`: Pattern 4 の "Fix:" 例示および修復案サンプル (計 2 箇所) を canonical パターンに更新
- `skills/issue/spec-test-guidelines.md`: patch route AC 例示 (計 2 箇所) を canonical パターンに更新
- `skills/issue/SKILL.md`: patch route AC 例示 (1 箇所) を canonical パターンに更新
- `modules/verify-patterns.md`: workflow レベル・job レベル双方の残存例示 (計 11 箇所) を canonical パターンに更新
- `modules/verify-executor.md`: "Job-Level Conclusion Sub-Form" の使用例テンプレートと具体例 (計 2 箇所) を job レベル canonical パターンに更新 (Issue 本文の対象ファイル一覧外の追加スコープ、Notes 参照)
- [Steering Docs sync candidate] keyword "verify-patterns.md" skipped: matched 150 files (no discriminating power)
- [Steering Docs sync candidate] keyword "issue" (bare skill name, from `skills/issue/SKILL.md`) skipped: matched 1096 files (no discriminating power)

## Implementation Steps

置換規則 (共通):
- workflow レベル: `--json conclusion --jq '.[0].conclusion'` → `--json conclusion,status --jq 'if .[0].status != "completed" then "in_progress" else .[0].conclusion end'`
- job レベル: `--json jobs --jq '.jobs[] | select(.name=="<job>").conclusion'` → `--json jobs --jq '.jobs[] | select(.name=="<job>") | if .status != "completed" then "in_progress" else .conclusion end'` (`modules/verify-executor.md` § "github_check: `gh run list` In-Progress Detection Constraint" が既に明記している式そのもの)
- `--workflow=`/`--branch=`/`--commit=` 等の既存オプションはそのまま保持し、`--json`/`--jq` 部分のみを置換する

1. (→ acceptance criteria A) `docs/versioning.md` と `docs/ja/versioning.md` の「Base branch CI is green」表行を更新する。
   - `docs/versioning.md`:
     - 旧: `` `gh run list --branch main --workflow Test --limit 10 --json conclusion` — no `failure` ``
     - 新: `` `gh run list --branch main --workflow Test --limit 10 --json conclusion,status` — no `failure`, and no `status` other than `completed` (an in-progress run must not be read as green) ``
   - `docs/ja/versioning.md`:
     - 旧: `` `gh run list --branch main --workflow Test --limit 10 --json conclusion` — `failure` がないこと ``
     - 新: `` `gh run list --branch main --workflow Test --limit 10 --json conclusion,status` — `failure` がなく、`status` がすべて `completed` であること (実行中の run を緑と誤認しないため) ``

2. (parallel with 1, 3, 4, 5) (→ acceptance criteria A) `skills/triage/skill-dev-verify-audit.md` の 2 箇所を更新する。
   - Pattern 4 "Fix:" のフェンスコード例 (`github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`) を上記 workflow レベル置換規則で更新
   - Pattern 4 サンプル出力内の「修復案」行 (同一パターン) を同様に更新

3. (parallel with 1, 2, 4, 5) (→ acceptance criteria A) `skills/issue/spec-test-guidelines.md` (2 箇所) と `skills/issue/SKILL.md` (1 箇所) を更新する。3 箇所とも同一の patch route AC 例示行:
   - 旧: `- [ ] <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) all jobs pass (patch route)`
   - 新: `- [ ] <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion,status --jq 'if .[0].status != \"completed\" then \"in_progress\" else .[0].conclusion end'" "success" --> CI (test.yml) all jobs pass (patch route)`
   - (`modules/verify-classifier.md` の canonical テンプレートと同一の `--branch=main` 付き形式)

4. (parallel with 1, 2, 3, 5) (→ acceptance criteria A) `modules/verify-patterns.md` の 11 箇所を更新する。
   - workflow レベル (計 7 箇所): L39 (`node_modules` pitfall 行, `--workflow=ci.yml`)、L177 (DCO recommended pattern, `--workflow=dco.yml`)、L200 (Preferred pattern 1, `--workflow=<specific>.yml`)、L908-910 (pytest/pnpm/npm 行, `--workflow=<file>.yml` — 3 行とも バイト同一のため `replace_all` で一括置換可)、L1148 (§25 例示, `--workflow=test.yml`)
   - job レベル (計 4 箇所): L217 (比較表内の job レベル行)、L227 (multi-job workflow 例, `--workflow=ci.yml`)、L907 (test-framework 表の bats 行, `--workflow=test.yml`, テーブルセル内のためパイプは `\|` エスケープ)、L927 (§ 該当箇所の "Correct verify command" 例, `--workflow=test.yml`) — いずれも上記 job レベル置換規則を適用

5. (parallel with 1, 2, 3, 4) (→ acceptance criteria A) `modules/verify-executor.md` の "github_check: Job-Level Conclusion Sub-Form" 節を更新する (追加スコープ、Notes 参照)。
   - L94 (Usage form テンプレート, プレースホルダ `<file>.yml`/`<job_name>`) と L100 (具体例, `--workflow=ci.yml`, job=`Run bats tests`) の 2 箇所に job レベル置換規則を適用
   - L125 (制約節の説明文中の式) は既に修正後の形を正しく記述しているため変更不要

## Verification

### Pre-merge

- <!-- verify: rubric "docs/versioning.md, skills/triage/skill-dev-verify-audit.md, skills/issue/spec-test-guidelines.md, skills/issue/SKILL.md, modules/verify-patterns.md に残る `gh run list --json conclusion --jq '.[0].conclusion'` 形式の例示が、status を合成する推奨パターンに更新されている、またはその適用対象外である理由が明記されている" --> 残存する旧パターンの例示が更新または対象外理由が明記されている

### Post-merge

なし

## Notes

- **docs/versioning.md / docs/ja/versioning.md の適応的修正**: このゲートチェック行は単発の `<!-- verify: -->` AC テンプレートではなく、直近 10 件の run を対象に「`failure` が無いこと」を確認する人間/AI 向けの手順記述。in_progress 中の run は `conclusion` が空 (≠ `failure`) のため、素の「`failure` なし」判定では in_progress を green と誤認しうる — 単発 run の `expected_value` 不一致で FAIL 誤判定する canonical パターンの問題とは発生方向が逆だが、同じ「status 未参照」に起因する検出漏れであるため、`--json` に `status` を追加し「`status` が全て `completed`」条件を明記する適応的修正を行った (jq 式をそのまま移植するのではなく、この行の「直近 N 件・no failure」という形に合わせた)。
- **modules/verify-executor.md を追加スコープに含めた判断**: Issue 本文が明示する対象ファイル一覧 (`docs/versioning.md`, `skills/triage/skill-dev-verify-audit.md`, `skills/issue/spec-test-guidelines.md`, `skills/issue/SKILL.md`, `modules/verify-patterns.md`) に `modules/verify-executor.md` は含まれない。しかし grep 調査で、この制約自体を明文化した張本人であるこのファイルの "Job-Level Conclusion Sub-Form" 使用例 (L94 テンプレート・L100 具体例) が #1444 で更新されないまま残っていたことが判明した。同一制約の SSoT ファイル自身が古い例を残していると、将来この例をコピーした際に同じ検出漏れを再発させるリスクが最も高い箇所と判断し、低リスクな同一パターンの機械的修正として本 Spec に含めた。Pre-merge AC の rubric 文言は Issue 本文の記載を逐語的に引き継ぐ (Verify command sync rule) ため書き換えていないが、rubric が名指す 5 ファイルは Implementation Steps で全てカバーしており、この追加修正が AC 判定に悪影響を与えることはない。
- **modules/verify-patterns.md の job レベル箇所の扱い**: rubric 文言が引用する `gh run list --json conclusion --jq '.[0].conclusion'` は workflow レベルの記法だが、rubric はこの文字列の完全一致ではなく「status 未合成の `.conclusion` 抽出パターン」全般を趣旨としていると判断し (Issue 本文 Background の「`--json conclusion --jq '.[0].conclusion'`、status 合成なし」という記述も特性の説明であり厳密な引用ではない)、`modules/verify-patterns.md` 内の job レベル箇所 (L217, L227, L907, L927) も同一ファイル内の残存旧パターンとして更新対象に含めた。
- **対象外ファイル**: `docs/spec/*.md` (使い捨て Spec、Issue 本文で明示的に対象外) および `docs/reports/*.md` / `docs/ja/reports/*.md` (過去の実行記録・レポート — 当時の事実の記録であり「将来コピーされる例示/ガイダンス」ではないため、Issue の Purpose の範囲外と判断)。`modules/verify-classifier.md` と `modules/verify-executor.md` L125 の制約説明文、`skills/verify/SKILL.md` L248、`skills/spec/SKILL.md` L690 は #1444 で既に canonical パターンに更新済みのため変更不要。
- **新規テストケース要否**: 本 Issue はドキュメント/Skill 本文中の例示文字列の修正のみであり、スクリプトへの新規分岐ロジック追加を伴わないため、bats 新規テストケースの追加要件は非該当 (`tests/` 配下に旧パターン文字列を assert するテストは無いことを grep で確認済み)。

## Consumed Comments

No new comments since last phase.
