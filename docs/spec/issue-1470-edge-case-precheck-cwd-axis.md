# Issue #1470: review: Edge Case Pre-check が実行コンテキスト (CWD) の軸を持たず CWD 依存バグを検出できない

## Overview

`skills/review/SKILL.md` の Parser/Validator Edge Case Pre-check は、パーサ・バリデータ系の新規/変更コードに実際に fixture を流して挙動を測定する仕組みだが、現行の 5 軸 (空入力 / 予期しない入れ子や階層深度 / メタ文字を含む入力 / コメント等の付随構文 / 想定より浅いまたは深い構造) はいずれも入力文字列の**形状**を変える軸であり、**実行位置** (CWD) は手順 3(3) により repository root に固定されている。このため #1463 で実際に発生した `scripts/detect-pr-ci-workflows.sh` の CWD 依存バグ (呼び出し元によって評価対象が変わる) を、この Pre-check の実行 sub-agent は原理的に再現できなかった (review-bug の diff 読解側が代わりに発見した)。

本 Issue は、firing condition (c) (外部由来の文字列を引数に取り解釈・検証するスクリプト) が発火したケースに限り、同じ fixture を repository root 以外の CWD からも実行して結果を比較する「実行コンテキスト軸」を追加する。(a)/(b) は正規表現・入力形状の分岐であり、ファイルシステムに触れないため CWD の影響を受けず、対象外とする。

Workflow path (`skills/review/workflow-guidance.md`) 側は、`.tmp/edge-case-context-$NUMBER.md` の内容を `edgeCaseContext` としてそのまま転記するだけの content-agnostic な設計であるため、軸の追加そのものによる内容変更は不要であることをコードベース調査で確認した (詳細は Notes 参照)。

## Changed Files

- `skills/review/SKILL.md`: Parser/Validator Edge Case Pre-check セクションに実行コンテキスト (CWD) 軸を追加 (内容追加)
- `skills/review/workflow-guidance.md`: Processing Steps (Workflow Path) の手順 4 に、新規軸追加時も本ファイルの内容変更が不要である旨の 1 文を追加 (内容追加)
- `tests/workflow-guidance.bats`: 上記 workflow-guidance.md の追記を検証する `@test` を 1 件追加
- `tests/edge-case-execution-context.bats`: 新規ファイル。SKILL.md 側の実行コンテキスト軸追加を検証する `@test` を 2 件追加

[Steering Docs sync candidate] keyword "review" skipped: matched 1099 files (no discriminating power)

## Implementation Steps

1. `skills/review/SKILL.md` の `### Parser/Validator Edge Case Pre-check` セクションを変更する (→ 受入条件 AC1, AC2)。
   - 挿入位置 A: `**Minimum input axes to cover** (same 5 axes as the Issue body; exhaustive): ...` の行の直後、`**Trust gating (execution safety)**:` 段落の直前に、以下の段落を新規挿入する:
     > **Execution context axis (firing condition (c) only)**: the 5 input axes above vary input *content*; none of them can surface a bug that depends on *where the code runs* instead — e.g., a script that resolves a path relative to CWD, or silently defaults to the caller's CWD when a repository-root argument is omitted. This axis targets exactly that gap: for a file matched via firing condition (c), additionally re-run the same fixture and arguments from a CWD other than the repository root, and compare the result against the repository-root execution in step 3 below. Scope is (c) only — (a) regex matching and (b) shape-branching both operate purely on an in-memory string with no filesystem access, so execution location cannot affect their result.
   - 挿入位置 B: 手順 3 のサブエージェント指示リスト末尾、`(6) output findings in the same **[Edge Case Execution] path:line** format as review-bug.` の直後に、句点の前で以下を追記する:
     > , (7) if this file was matched via firing condition (c), additionally repeat the execution in (3) from a CWD other than the repository root (e.g. a subdirectory under `.tmp/`) using identical arguments and fixtures, and compare the result against the repository-root execution — report any mismatch as a finding in the same format, noting both CWD values used.
2. (after 1) `skills/review/workflow-guidance.md` の `## Processing Steps (Workflow Path)` 手順 4 (`**Run Workflow pipeline** using the inline script below. ...`) の末尾、`edgeCaseContext carries the same Parser/Validator Edge Case Pre-check output consumed by the static path's 10.2 step 3.` の直後に、以下の 1 文を追記する (→ AC3):
   > Any additional axis introduced in that Pre-check (including an execution-context/CWD axis) is carried through automatically — this transcription is content-agnostic, so no change to this file is required when the Pre-check's own axis set changes.
3. (after 2) `tests/workflow-guidance.bats` に以下の `@test` を追加する (→ AC3, AC4):
   ```bash
   @test "workflow-guidance: new Pre-check axes require no content change to this file" {
       grep -q "no change to this file is required" "$GUIDANCE_FILE"
   }
   ```
4. (after 1) 新規ファイル `tests/edge-case-execution-context.bats` を作成する (→ AC1, AC2, AC4):
   ```bash
   #!/usr/bin/env bats

   # Structural regression tests for the Parser/Validator Edge Case Pre-check's
   # execution-context (CWD) axis, added in Issue #1470 to close the detection
   # gap that let scripts/detect-pr-ci-workflows.sh's CWD-dependent bug (#1463)
   # pass the pre-check's fixture-execution sub-agent unnoticed.

   SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/review/SKILL.md"

   @test "review SKILL.md: Parser/Validator Edge Case Pre-check documents the execution context axis" {
       grep -q "Execution context axis" "$SKILL_FILE"
   }

   @test "review SKILL.md: Edge Case Pre-check re-executes fixtures from a non-repository-root CWD" {
       grep -q "CWD other than the repository root" "$SKILL_FILE"
   }
   ```
   実装後、`bats tests/` を実行し全件 PASS することを確認する (→ AC4)。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md の Parser/Validator Edge Case Pre-check に、入力内容の 5 軸に加えて実行位置 (CWD / repository root 以外からの実行) を変えて結果を比較する軸が追加されており、CWD 依存バグを検出できる手順になっている" --> Edge Case Pre-check に実行コンテキスト (CWD / root) の軸が追加されている
- <!-- verify: section_contains "skills/review/SKILL.md" "Parser/Validator Edge Case Pre-check" "CWD" --> 当該節が repository root 固定でない実行を規定している
- <!-- verify: file_contains "skills/review/workflow-guidance.md" "no change to this file is required" --> Workflow path 側の対応方針 (workflow-guidance.md の変更要否) が明示され、実際の `edgeCaseContext` 転記ロジックと整合している
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 次に firing condition (c) に該当する新規スクリプトを含む PR で `/review` を実行した際、実行コンテキスト軸が実際に測定されることを観察する
  - Expected output structure:
    - `.tmp/edge-case-context-$NUMBER.md` またはレビュー本体の出力に、repository root 以外の CWD からの実行結果への言及があること
    - 該当スクリプトが CWD 非依存であれば「一致」と記録され、依存があれば `**[Edge Case Execution] path:line**` 形式の finding として報告されること

## Notes

### Consumed Comments からの反映

triage AC audit コメント (MEMBER, saito, 2026-09-13T08:22:25Z, first-class) が、当初の AC3 rubric (`skills/review/workflow-guidance.md の edge case pipeline が...SKILL.md 側を参照する形になっている`) について「`workflow-guidance.md` は実装前の現状 (main ブランチ) の時点で既に `edgeCaseContext` を汎用転記するだけの設計になっており、rubric の当該選択肢が実装の正誤に関わらず常時 PASS しうる」と指摘した。`skills/review/workflow-guidance.md` の実際の内容 (Processing Steps (Workflow Path) 手順 4、および Inline Workflow Script の `EDGE_CASE_SUFFIX` 構築ロジック) を読み、この指摘が正しいことを確認した。

対応として、コメントが提示した 2 案のうち「(b) `/spec` で workflow-guidance.md への変更が不要であることを確定させ、AC を section_contains/grep 型のコード具体物に紐づく補助チェックに置き換える」を採用した。理由: 実際に調査した結果、`edgeCaseContext` の転記ロジックは content-agnostic であり、SKILL.md 側の軸追加だけで Workflow path 側は自動的に新軸をカバーする設計として正しく機能している (workflow-guidance.md 自体を変更する必然性がない) ため。ただし「変更不要」を暗黙のままにすると今回のような誤解 (Issue Scope 自身も「Workflow path 側にも同じ軸を反映する」と変更が必要であるかのように記述していた) が再発するため、その設計意図を明文化する 1 文を workflow-guidance.md に追加し (Implementation Step 2)、AC3 の verify command を rubric から `file_contains` (その 1 文の存在確認) に変更した。Issue 本文の AC3 も `/spec` フェーズで同内容に更新済み。

### Issue body vs. 実装の齟齬 (Step 6 conflict detection)

Issue Scope 節は "`skills/review/workflow-guidance.md` にも同じ軸を反映する" と記述しており、同ファイルへの内容変更を前提としていたが、実装調査の結果、同ファイルの `edgeCaseContext` 転記は汎用的 (content-agnostic) であり、軸の種類によらず変更不要であることが判明した。上記の Consumed Comments 対応と合わせて、AC3 を「変更不要という設計判断が明文化されていること」を検証する形に補正した。

### Auto-Resolve Log (non-interactive mode)

- **論点**: 実行コンテキスト軸を firing condition (c) 限定にするか、(a)/(b) も含めるか (Issue Scope が `/spec` 判断に委ねていた点)。
- **解決**: (c) 限定を採用。(a) 正規表現マッチ・(b) 入力形状分岐は、いずれもメモリ上の文字列のみを対象とした純粋な分岐/マッチングでありファイルシステムアクセスを伴わないため、実行位置 (CWD) を変えても結果は原理的に変わらない。#1463 の実例 (`detect-pr-ci-workflows.sh`) も外部由来の文字列を引数に取り解釈するスクリプトであり (c) に該当する。(c) 限定とすることで、既存 fixture の再利用のみで追加コストを抑えるという Issue の設計意図とも整合する。

### 新規テストケース (Step 13 相当、SPEC_DEPTH=light のため本節に記録)

本 Issue は `skills/review/SKILL.md` に新規の分岐ロジック (firing condition (c) 限定での追加実行) を導入するが、対象は LLM が解釈する prose 手順であり既存の対応する bats カバレッジは存在しなかった (`tests/review.bats` は同じ SKILL.md の別セクション `## Opportunistic Verification` のみを対象としている)。既存コンベンション (`tests/workflow-guidance.bats` の grep-guard 方式) に倣い、新規ファイル `tests/edge-case-execution-context.bats` (2 `@test`) と `tests/workflow-guidance.bats` への追加 (1 `@test`) で新規ロジックを検証する (Implementation Steps 3, 4)。

### Steering Docs sync candidate check

キーワード "review" (bare skill name) は `docs/`, `tests/`, `scripts/`, `modules/` 配下で 1099 ファイルにマッチし判別力なしのためスキップした。"Edge Case Pre-check" というより具体的な語での追加 grep も実施したが、ヒットはすべて `docs/spec/issue-*.md` の disposable な過去レトロスペクティブ記録 (Spec は完了後保守されないため対象外) と、`modules/observation-trigger.md:238` の 1 件のみだった。後者は過去に Pre-check が検出したバグの引用 (historical anecdote) であり、Pre-check の現在の軸構成を規定する記述ではないため更新不要と判断した。`docs/workflow.md` / `README.md` / `docs/guide/*.md` にも "Edge Case" 系の記述はなく、同期対象なし。`docs/ja/` は `docs/*.md` (steering/project doc) のみを対象としており `skills/*/SKILL.md` は翻訳対象外のため対象外。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / summary: triage AC audit — AC3 の rubric verify command が実装前から常時 PASS しうる懸念を指摘 (対応内容は Notes > Consumed Comments からの反映を参照) / URL: https://github.com/saitoco/wholework/issues/1470#issuecomment-5652189343

No new comments since last phase.

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜4 をそのままの順序・内容で実装した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A — 新規テスト 3 件 (`tests/edge-case-execution-context.bats` 2 件、`tests/workflow-guidance.bats` 1 件) について、対象ファイル (`skills/review/SKILL.md`, `skills/review/workflow-guidance.md`) を `git stash push -u` で実装前の状態に一時退避したうえで実行し、全件 FAIL することを確認した (New Verification-Test Pre-implementation FAIL Check)。その後 stash を復元し、`bats --jobs 18 tests/` で全 2077 件 PASS を確認した。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Pre-merge AC 4 件を verify-executor で再検証し、全件 PASS (rubric 1件、section_contains 1件、file_contains 1件、command 1件は CI reference fallback 経由) を確認した。Issue チェックボックスは code フェーズで既に `[x]` 済みのため変更なし。
- REVIEW_DEPTH=light (Size M) のため review-light 1エージェント統合レビューを実行。SHOULD 指摘1件 (Parser/Validator Edge Case Pre-check の新規手順 (7) が生成する代替 CWD ディレクトリが 14.2 のクリーンアップ backstop リストに含まれていない) を採用し修正した。
- 修正方針は、代替 CWD を `.tmp/edge-case-fixtures-$NUMBER/` 配下にネストする案 (既存クリーンアップの対象に自動的に含まれる) を採用し、14.2 のリスト自体への追加は不要とした。
- CI (全8ジョブ SUCCESS)・Base Branch Conflict Pre-check (競合なし)・Parser/Validator Edge Case Pre-check (本PRはプロース/テストのみでゼロマッチ) はいずれも通常経路で完了。

### Deferred Items
- Post-merge AC (firing condition (c) 該当の新規 PR での `/review` 実行時に実行コンテキスト軸が実際に測定されることの観察) は `/verify` で次回該当 PR 発生時に確認する (未変更、code フェーズからの引き継ぎを維持)。

### Notes for Next Phase
- レビューで1件 SHOULD 修正済み・push済み (commit 350152ea)。追加の MUST/SHOULD/CONSIDER 指摘なし。
- Lightweight re-check: `validate-skill-syntax.py` PASS、対象テスト7件 PASS、`bats --jobs 18 tests/` 全2077件 PASS。
- 本 phase 中に GitHub 側の一時的な Partial System Outage (2026-09-13T09:16 UTC) が発生し、ラベル遷移・レビュー投稿 API が一時的に失敗したが、再試行で解消済み。`/merge` 実行時に同種の一時エラーが再発する可能性はあるが、本 Issue のスコープとは無関係。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — review-light (Perspective 1) が Spec の Implementation Steps 1〜4 と実装差分を突き合わせ、挿入位置 A/B・workflow-guidance.md の追記・新規テスト2件とも Spec 記載どおりであることを確認した。`EDGE_CASE_SUFFIX` の content-agnostic な転記ロジックについても独自に再検証しており、Spec の Notes が主張する設計判断の裏付けが取れている。

### Recurring issues

review-bug 2 エージェントの fan-out は `SKIP_REVIEW_BUG=false` かつ `REVIEW_DEPTH=full` の場合のみ動く経路であり、本 PR は `REVIEW_DEPTH=light` (Size M) のため review-light 1 エージェントによる統合レビューのみで完結した。指摘は 1 件 (SHOULD): Parser/Validator Edge Case Pre-check の新規手順 (7) が使う「repository root 以外の CWD」ディレクトリが、既存のクリーンアップ対象 (`.tmp/edge-case-fixtures-$NUMBER/` および 14.2 の backstop リスト) に明示的に含まれていなかった。本 Issue 自身が「Pre-check の実行結果の取りこぼし (CWD 依存バグ)」を主題としており、その対策コード自身が新たな一時ディレクトリを生成する副作用を持つ点は Spec 側で想定されていなかった。修正は該当ディレクトリを `.tmp/edge-case-fixtures-$NUMBER/` 配下にネストする 1 行の文言修正で完了し、既存テスト (grep ベースの文字列一致) にも影響しなかった。この種の「新規手順が生成する副産物のクリーンアップ漏れ」は Edge Case Pre-check 拡張時に繰り返しやすいパターンとして留意する。

### Acceptance criteria verification difficulty

Nothing to note — 4件の Pre-merge AC (rubric 1件、section_contains 1件、file_contains 1件、command 1件) はいずれも UNCERTAIN なく PASS 判定できた。`command "bats tests/"` は safe mode のため CI reference fallback (exact job name match: `Run bats tests`) で PASS 判定。rubric AC は Consumed Comments 記録済みの triage 指摘 (常時 PASS しうる懸念) を `/spec` 側で既に file_contains に置き換え済みだったため、本 phase では健全な形で検証できた。

なお本 phase 中、GitHub 側で API リクエスト全般に影響する Partial System Outage (2026-09-13T09:16 UTC 発生、githubstatus.com で確認) が発生し、`gh-label-transition.sh` および `gh-pr-review.sh` のレビュー投稿 API 呼び出しが一時的に 500 エラーで失敗した。いずれも再試行で成功しており、本 Issue のスコープ (Edge Case Pre-check の CWD 軸追加) とは無関係な GitHub 側の一時的な障害であることを githubstatus.com で確認済み。
