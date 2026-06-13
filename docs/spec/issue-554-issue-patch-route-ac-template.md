# Issue #554: issue-skill: github_check AC テンプレートへの patch route 雛形追加

## Overview

`/issue` skill の AC 生成参照ドキュメント (`skills/issue/SKILL.md` AC Writing Guide および `skills/issue/spec-test-guidelines.md`) に patch route 用 `github_check` 雛形を追加し、各例示に route 区分注記 (PR route / patch route) を付ける。

Issue #551 の verify 実行で判明した問題: patch route Issue では `gh pr checks` 形式が使えないが、`/issue` の AC 雛形に patch route 向けのテンプレートが存在せず、誤った形式が選ばれるリスクがある。

## Changed Files

- `skills/issue/spec-test-guidelines.md`: patch route 用 `github_check` 雛形を追加し、route 区分注記を付与
- `skills/issue/SKILL.md`: AC Writing Guide の "Do not include test counts" 例示に patch route 雛形と route 区分注記を追加

## Implementation Steps

1. `skills/issue/spec-test-guidelines.md` "Using `github_check` for CI-based bats verification" セクションを更新 (→ AC 1, 2, 3, 6, 7)
   - "**Recommended pattern:**" を "**Recommended patterns:**" に変更し、PR route と patch route の両形式を例示
   - 既存の `gh pr checks` 行に `(PR route)` 注記を追加
   - `gh run list` 形式の patch route 例を追加: `github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` に `(patch route)` 注記
   - route 選択方針段落を追記: 「Size XS/S → patch route → `gh run list` form、Size M/L → PR route → `gh pr checks` form。詳細判定ロジックは `modules/verify-classifier.md` § Patch Route CI Verification Note を参照」
   - "**Example acceptance criteria entry:**" の既存例にも `(PR route)` 注記を追加し、patch route 例を併記

2. `skills/issue/SKILL.md` AC Writing Guide "Do not include test counts" 例示を更新 (→ AC 4, 5, 7)
   - "Good:" 例の `gh pr checks` 行に `(PR route)` 注記を追加
   - `gh run list` 形式の patch route 例を追加
   - route 選択方針の note を 1 文追加: 「Note: Size XS/S → patch route → `gh run list` form、M/L → PR route → `gh pr checks` form (詳細: `modules/verify-classifier.md`)」

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "gh run list" --> `skills/issue/spec-test-guidelines.md` に `gh run list` form の github_check テンプレートが追加されている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "patch route" --> `skills/issue/spec-test-guidelines.md` の例示に patch route 注記が含まれている
- <!-- verify: file_contains "skills/issue/spec-test-guidelines.md" "PR route" --> `skills/issue/spec-test-guidelines.md` の例示に PR route 注記が含まれている
- <!-- verify: file_contains "skills/issue/SKILL.md" "gh run list" --> `skills/issue/SKILL.md` AC Writing Guide に patch route 用 github_check 雛形が追加されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "patch route" --> `skills/issue/SKILL.md` AC Writing Guide に patch route 注記が含まれている
- <!-- verify: grep "XS/S.*patch\|patch.*XS/S\|Size XS/S" "skills/issue/spec-test-guidelines.md" --> Size XS/S → patch route の使い分け方針が記載されている
- <!-- verify: rubric "skills/issue/spec-test-guidelines.md and skills/issue/SKILL.md AC Writing Guide both present patch-route (gh run list + expected 'success') and PR-route (gh pr checks) github_check templates with explicit route annotations, and reference modules/verify-classifier.md as the SSoT for detailed routing logic" --> 両ファイルが両形式の雛形 + route 注記 + verify-classifier.md SSoT 参照を含むことが rubric 基準を満たす
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) all jobs pass (patch route 形式の dogfooding)

### Post-merge

- 次に XS/S Issue で `/issue` を実行した際、生成される AC に patch route 用 `gh run list` form の github_check が含まれることを目視確認 <!-- verify-type: opportunistic -->

## Notes

- 変更は追記のみ。既存 PR route テンプレートは温存する
- workflow ファイル名は `test.yml` を代表例として記載 (verify-classifier.md line 77 と整合)
- route 判定ロジックの詳細は `modules/verify-classifier.md` § Patch Route CI Verification Note に委譲し、`/issue` 側では雛形と route 判定の入り口のみ提供する
- `spec-test-guidelines.md` は SCAN_DIRS 対象 (`skills/`) に含まれるため、追加する patch route 例内の `jq` 式 `.[0].conclusion` が半角 `!` を含まないことを確認済み (問題なし)

## review retrospective

### Spec vs. 実装の乖離パターン

特記なし。実装は Spec の各ステップと 1:1 で対応しており、構造的な乖離は検出されなかった。

### 繰り返し発生する問題

特記なし。CONSIDERが1件（SKILL.mdのGoodセクションにサブヘッダーがなく spec-test-guidelines.md と非対称）のみ。同種の問題の繰り返しはない。

### 受け入れ条件の検証難度

8件中7件が自動PASS。残り1件（`github_check "gh run list..."` による CI pass 確認）は safe モードでアローリスト外のため UNCERTAIN となった。これは verify-executor の仕様上の想定動作であり、`/verify` の full モードまたは CI ステータス参照で補完可能。今後 XS/S patch route Issue の AC に `github_check "gh run list..."` 形式を使う場合、safe モードでは常に UNCERTAIN になることを認識しておくとよい。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- MUST issueなし、SHOULD issueなし — CONSIDERが1件（SKILL.md Goodセクションのサブヘッダー非対称性）のみ → スキップ判断（機能的問題なし）
- すべてのpre-merge AC自動検証完了（7/8 PASS、1 UNCERTAIN）
- UNCERTAIN ACは github_check safe mode 制約によるもの（CI自体はSUCCESS確認済み）

### Deferred Items

- Post-merge AC: 次回 XS/S Issue で `/issue` を実行した際の目視確認（opportunistic verify で追跡）
- SKILL.md Good セクションのサブヘッダー非対称性（CONSIDER）: 将来の改善候補

### Notes for Next Phase

- CI全ジョブSUCCESS（DCO/bats/validate-skill-syntax/forbidden-expressions/macOS-compat）
- レビューコメント（CONSIDER）を投稿済み — マージ前の修正不要
- `/merge 606` で直接マージ可能
