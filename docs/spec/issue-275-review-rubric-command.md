# Issue #275: review: rubric による意味レベルのレビュー観点 opt-in を導入

## Overview

`/review` に意味レベルのレビュー観点を opt-in で宣言できる経路を追加する。#271 で導入した `<!-- verify: rubric "text" -->`(AC の意味判定)と対称の設計で、PR レビュー観点の意味判定経路を pre-merge 側にも拡張する。

Issue 本文に新規 `## Review Criteria` セクションを導入し、`<!-- review: rubric "text" -->` marker で観点を宣言する。`/review` は既存 Step 10.3 の直後に新しいサブステップ `10.4. Review Rubric Grading` を追加して、marker を抽出し grader を呼び出し、結果を PR コメントに integrate する。grader の設計(adversarial スタンス、入力範囲、戻り値契約)は `modules/verify-executor.md` の Rubric Command Semantics を参照する形で、重複実装を避ける。

`/review` は PR diff と Issue 本文の読取が責務で副作用なし(`always_allow` 相当)のため、review rubric は `/review` 実行中は常に grader を呼ぶ(#271 の verify: rubric が safe-mode で UNCERTAIN を返すのとは挙動が異なる)。Spec は grader に入力しない(Issue=WHAT / Spec=HOW 原則の維持)。

## Changed Files

- `skills/review/SKILL.md`: Step 10 配下に `### 10.4. Review Rubric Grading` サブセクションを追加(Issue 本文の `## Review Criteria` セクションから `<!-- review: rubric "text" -->` marker を抽出して review-rubric-phase.md に従い grader を呼び、結果を Review body(Step 11 の出力)に "Review Rubric Results" 表として integrate)
- `skills/review/review-rubric-phase.md`: 新規作成。grader 呼び出し契約(adversarial スタンス、入力範囲 = Issue 本文 + PR diff + rubric text 内で明示言及されたファイル、`Spec files are not passed to the grader` の明記、戻り値 PASS / FAIL / UNCERTAIN と FAIL 時の gap 記述、Managed Agents `permission_policy: always_allow` portability)を記述。shared semantics は `modules/verify-executor.md` の Rubric Command Semantics への参照で重複実装を避ける
- `skills/issue/SKILL.md`: Step 4(Classify Acceptance Criteria and Assign Verify Commands)の末尾付近に Review Criteria 宣言ガイダンスセクションを追加(新規セクション `## Review Criteria`、marker syntax `<!-- review: rubric "text" -->`、AC との役割分担)。併せて "Standard Format" に `## Review Criteria` のサンプル行を追加
- `modules/verify-patterns.md`: 既存 §9 の後に `### 10. When to Use \`review: rubric\` vs \`verify: rubric\`` セクションを追加(verify: AC の post-merge 充足判定、review: PR 品質の pre-merge 観点判定 の違いと使い分け)
- `tests/review-rubric.bats`: 新規作成。Issue 本文からの `## Review Criteria` セクション抽出、`<!-- review: rubric "text" -->` marker パース、`skills/review/review-rubric-phase.md` の存在と必要文言の shallow 検証 — bash 3.2+ 互換(grep / awk のみ使用、mapfile 等 bash 4+ 機能は使わない)

## Implementation Steps

1. `skills/review/review-rubric-phase.md` を新規作成(module standard 4-section structure: Purpose / Input / Processing Steps / Output)。内容: (a) grader input scope — Issue body (Background, Purpose, Acceptance Criteria, Review Criteria sections) と `gh pr diff $NUMBER` と rubric text 内で明示言及されたファイル。Spec files are not passed to the grader。(b) adversarial system prompt 指定。(c) 戻り値 PASS / FAIL / UNCERTAIN、FAIL 時は gap の自然言語記述。(d) shared design は `modules/verify-executor.md` の "Rubric Command Semantics" セクションを参照。(e) Managed Agents `permission_policy: always_allow` への portability を注記 (→ AC 2, 3, 4, 5, 6)

2. `skills/review/SKILL.md` の Step 10.3 直後に `### 10.4. Review Rubric Grading` サブセクションを追加。処理: (i) Issue 本文から `## Review Criteria` セクションを抽出(存在しなければ skip)、(ii) セクション内の `<!-- review: rubric "text" -->` marker を列挙、(iii) 各 marker について `skills/review/review-rubric-phase.md` を Read して "Processing Steps" に従い grader を呼ぶ、(iv) 結果の PASS / FAIL / UNCERTAIN + gap を収集、(v) Step 11 の Review body 生成直前に "## Review Rubric Results" 表として追加 (→ AC 1)

3. `skills/issue/SKILL.md` Step 4 の "Custom verify command handlers" セクション直前付近に新規サブセクション "Review Criteria section (optional)" を追加。内容: (a) `## Review Criteria` は optional、意味レベルのレビュー観点宣言用、(b) marker syntax `<!-- review: rubric "text" -->` は `verify:` と対称、(c) AC(post-merge 充足)と Review Criteria(pre-merge 品質)の役割分担、(d) Issue = WHAT を崩さない(Spec ではなく Issue 側に置く)。併せて "Standard Format" コードブロック内に `## Review Criteria` サンプル行を 1 例追加 (→ AC 7, 8)

4. `modules/verify-patterns.md` の §9(既存の `rubric` 使い所ガイド)の後に `### 10. When to Use \`review: rubric\` vs \`verify: rubric\`` セクションを追加。内容: (a) `verify: rubric` は post-merge、AC 項目として実装成果物 vs 要件の充足を判定。(b) `review: rubric` は pre-merge、PR diff vs レビュー観点(アーキテクチャ整合、命名一貫性、エラーハンドリング方針等)の適合を判定。(c) 評価タイミングと対象が異なるため Issue 内でセクションを分ける (→ AC 9)

5. `tests/review-rubric.bats` を新規作成。bats テストで (i) サンプル Issue 本文テキストから `## Review Criteria` セクションが抽出できること、(ii) セクション内の `<!-- review: rubric "text" -->` marker 数が期待通り parse できること、(iii) `skills/review/review-rubric-phase.md` が存在し `Spec files are not passed to the grader` と `adversarial` を含むこと、(iv) `skills/review/SKILL.md` に `review: rubric` および "10.4" 相当のセクション見出しが存在することを shallow に検証(LLM 応答そのものは mock せず assertion しない)。bash 3.2+ 互換(mapfile など bash 4+ 機能は避ける) (→ AC 10, 11)

## Verification

### Pre-merge
- <!-- verify: file_contains "skills/review/SKILL.md" "review: rubric" --> `skills/review/SKILL.md` に `<!-- review: rubric "text" -->` marker 処理フロー(Step 10.4 相当)が追加されている
- <!-- verify: file_exists "skills/review/review-rubric-phase.md" --> `skills/review/review-rubric-phase.md` が新規作成されている
- <!-- verify: file_contains "skills/review/review-rubric-phase.md" "adversarial" --> 新規モジュールに adversarial スタンスの指定が明記されている
- <!-- verify: file_contains "skills/review/review-rubric-phase.md" "Spec files are not passed to the grader" --> 新規モジュールに Spec を grader に渡さない旨が明記されている
- <!-- verify: grep "PASS.*FAIL.*UNCERTAIN\|FAIL.*gap" "skills/review/review-rubric-phase.md" --> 戻り値 PASS / FAIL / UNCERTAIN と FAIL 時の gap 記述が記述されている
- <!-- verify: file_contains "skills/review/review-rubric-phase.md" "verify-executor.md" --> 新規モジュールから `modules/verify-executor.md` の Rubric Command Semantics への参照(重複実装回避)が記述されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "Review Criteria" --> `skills/issue/SKILL.md` に `## Review Criteria` セクションのガイダンスが追加されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "review: rubric" --> `skills/issue/SKILL.md` に `<!-- review: rubric "text" -->` marker の記述ガイダンスが追加されている
- <!-- verify: file_contains "modules/verify-patterns.md" "review: rubric" --> `modules/verify-patterns.md` に review rubric と verify rubric の使い分けガイドラインが追加されている
- <!-- verify: command "find tests -name '*review-rubric*.bats' -o -name '*review_rubric*.bats' -type f | grep -q ." --> review rubric の marker 抽出・dispatch を検証する bats テストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 追加されたテストを含む全 bats テストが CI で PASS する

### Post-merge
- 実 PR で `## Review Criteria` セクションに `<!-- review: rubric "text" -->` を宣言し、`/review` 経由で観点ごとに PASS / FAIL / UNCERTAIN と gap を含むコメントが投稿されることを確認(verify-type: opportunistic)

## Notes

- **#271 実装を前提**: `modules/verify-executor.md` の "Rubric Command Semantics" セクションが merge 済みで、adversarial スタンス / grader 入力範囲 / 戻り値契約が定義されている。本 Issue の `review-rubric-phase.md` はこれを参照する形で重複実装を避ける
- **Step 10.4 の命名**: 既存 `### 10.0`〜`### 10.3` と同じパターンで `### 10.4. Review Rubric Grading` を使う(`### Step 10.4` は validator の `validate_decimal_steps` で弾かれる — `### Step N.M` 形式のみ検出対象で、`### N.M.` 形式は許可されている)
- **safe / full モード扱い**: `/review` は基本 safe-mode で動き verify-executor 経由で AC 側の `<!-- verify: rubric -->` を UNCERTAIN として扱うが、review rubric は `/review` phase の中核機能で常に grader を呼ぶ(別レイヤ)。この挙動差は `review-rubric-phase.md` で明記する
- **Issue=WHAT 原則の維持**: AC(post-merge, 実装成果物評価)と Review Criteria(pre-merge, PR diff 評価)は同じ Issue に共存するが、評価タイミング・対象・用途が異なる。両方とも Issue 側にあり、Spec(HOW)には依存しない
- **Multi-perspective Code Review との共存**: Step 10.0–10.3 の既存レビューパスは残し、10.4 は opt-in 追加として作用する(Issue 本文に `## Review Criteria` が無ければ no-op)。既存挙動への影響ゼロ
- **bats テストの粒度**: `review: rubric` は LLM grader を呼ぶが、#271 `tests/verify-rubric.bats` と同じ方針で shallow test に留める — 文書存在・必要文言・セクション構造の検証のみで、LLM 応答自体の assertion は行わない
- **Managed Agents portability**: 将来 `/review` phase を Managed Agents Outcome に移植する際、review rubric は `permission_policy: always_allow` で 1:1 マップされる(verify rubric と同じ)
