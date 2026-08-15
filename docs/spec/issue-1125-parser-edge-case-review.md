# Issue #1125: review: パーサ系変更への negative/edge case 実測ステップの定型化

## Overview

PR #1120 (Issue #1055) の `/review --light` で、追加コードに silent failure (エラーにならず無言で誤った値や default が返る) が 3 件見つかった。3 件とも静的な差分読解では検出されず、一時的な `.wholework.yml` を実際に構成して実行することでのみ発見された。本 Issue は、入力を解釈・検証・正規化する処理を含む変更に対し「negative / edge case 入力を実際に構成して実行し、境界値・異常系の挙動を実測する」手順を `/review` の観点定義に定型化し、検出を実行者依存でなくすることが目的。`--light` / `--full` のどちらで発火させるかの判断は本 Spec に委譲されている。

## Changed Files

- `skills/review/SKILL.md`: Step 10 の "Base Branch Conflict Pre-check" の直後に新規 "Parser/Validator Edge Case Pre-check" サブセクションを追加。発火条件 (3 ヒューリスティック)・最低限カバーする入力軸 (5 軸)・2 ファイル cap・`general-purpose` Task 起動による実測実行・`.tmp/edge-case-context-$NUMBER.md` の書き込み・`--light`/`--full`/Workflow 経路すべてで発火する理由を記述する。10.0 (light mode) の 4. と 10.2 (full mode) の 3. のプロンプト注入箇所に context ファイルの追加注入を挿入し、14.2 の `rm -f` クリーンアップ対象に追加する
- `skills/review/workflow-guidance.md`: `capabilities.workflow: true` 時の Workflow 経路にも同じ edge case context を注入する (`args.edgeCaseContext` を追加し、Inline Workflow Script の `finderPrompts` に `CONFLICT_SUFFIX` と同様の `EDGE_CASE_SUFFIX` を追加)。`tests/workflow-guidance.bats` が grep 検証する既存の `return parallel(finderResult.findings.map(finding =>` 行は変更しない
- `agents/review-light.md`: "Perspective 2: Edge Cases and Robustness" に、プロンプトに事前実測済み edge case 実行結果が含まれる場合はそれを再導出せず直接所見に取り込む旨のガイダンスを追加する
- `agents/review-bug.md`: "1. Bug/Logic Error Detection" 内の既存 "Date/File-Naming Semantics Cross-Check" ブロックと同じパターンで "Pre-measured Edge Case Execution Results" ブロックを追加する
- `tests/workflow-guidance.bats`: `EDGE_CASE_SUFFIX` が finder prompt に適用されていることを確認する `grep -q` 回帰テストを、既存 2 テストと同じ構造規約で 1 件追加する

## Implementation Steps

1. `skills/review/SKILL.md` の Step 10、"### Base Branch Conflict Pre-check" サブセクション末尾 (「6. Add `.tmp/base-conflict-context-$NUMBER.md` to the `rm -f` cleanup list in 14.2.」の直後、「**Workflow path (opt-in)**:」段落の直前) に新規 "### Parser/Validator Edge Case Pre-check" サブセクションを挿入する。内容:
   - **発火条件** (diff の `+` 行のいずれかに合致すれば発火。exhaustive): (a) 入力文字列に対する照合・検証・抽出用の正規表現の追加/変更、(b) 入力値の形式によって分岐する `case`/`if` 連鎖の追加/変更 (固定 enum 判定ではなく形式判定目的のもの)、(c) プロセス外部から与えられる文字列 (設定ファイル内容・CLI 引数・環境変数・ユーザー入力等) を引数に取り、それを解釈・検証・正規化する関数/スクリプトの追加/変更
   - **最低限カバーする入力軸** (Issue 本文と同一の 5 軸。exhaustive): 空入力 / 想定外の階層・ネスト / メタ文字を含む入力 / コメント等の付随構文 / 想定より深い or 浅い構造
   - 発火条件に合致したファイルが 0 件なら以降をスキップする (context ファイルを書かない)。2 件を超える場合は diff hunk が大きい上位 2 件のみ処理し、対象外ファイルを context ファイルのヘッダーに記録する (cap の理由: この実測 sub-agent は Step 10.3 の検証 sub-agent より重い処理を伴うため、より保守的な上限とする)
   - 発火条件に合致したファイルごとに `subagent_type="general-purpose"` の Task sub-agent を並列起動する。プロンプトには対象ファイルパス・diff hunk・Spec パスを渡し、(1) 変更対象の関数/スクリプトを特定する、(2) 上記 5 軸をカバーする fixture 入力を構成する、(3) sub-agent 自身が持つ Bash/Write 権限を使いリポジトリルート (worktree、PR HEAD 相当) から対象コードを実際に実行する (シミュレーションでなく実行必須)、(4) 実測結果と期待動作を比較する、(5)「エラーにならず誤った値や default が無言で返る」経路を見つけた場合、Spec に意図的な fail-open として明記されているかを確認したうえで未文書化なら finding として報告する、(6) review-bug と同じ `**[Edge Case Execution] path:line**` 形式で出力する、よう指示する
   - 所見が 1 件以上ある sub-agent 結果を `.tmp/edge-case-context-$NUMBER.md` に書き込む (全 sub-agent が所見なし、または 0 件マッチなら書き込まない)。当該ファイルを 14.2 の `rm -f` クリーンアップ対象に追加する
   - **発火する review 深度と理由**: `--light` / `--full` / Workflow 経路のいずれでも発火する (`REVIEW_DEPTH` に依存しない)。理由: 発端の欠陥 (#1055 / PR #1120) は `--light` で発見されており、`--full` 限定にすると本 Issue が埋めようとしている検出漏れが再発する。コストは発火条件によるゲーティング (パーサ/バリデータ/正規化処理に触れない大多数の PR では 0 件マッチになる) と 2 ファイル cap で抑制する
   (→ Pre-merge AC1, AC2)
2. 同じく `skills/review/SKILL.md` の Step 10、10.0 (light mode) の 4. 内 (`.tmp/base-conflict-context-$NUMBER.md` 注入の直後) と 10.2 (full mode) の 3. 内 (同注入の直後) に、`.tmp/edge-case-context-$NUMBER.md` が存在する場合はその内容を同じプロンプトへ追加注入する処理を挿入する。注入時の指示文の要旨:「以下は本 diff のパーサ/バリデータ/正規化処理変更に対して事前に実測済みの edge case 実行結果である。再導出せず、[review-light: Perspective 2 / review-bug: Detected Issues] に直接反映すること」(after 1) (→ Pre-merge AC1)
3. `skills/review/workflow-guidance.md` の Inline Workflow Script に、Workflow 呼び出し時の `args` へ `edgeCaseContext` (`.tmp/edge-case-context-$NUMBER.md` の内容。なければ空文字列) を追加し、`CONFLICT_SUFFIX` と同じパターンで `EDGE_CASE_SUFFIX` を定義して `finderPrompts` の各テンプレート文字列に追加する (`return parallel(finderResult.findings.map(finding =>` の行は変更しない — `tests/workflow-guidance.bats` の既存 grep アサーション対象のため)。「Processing Steps (Workflow Path)」側の `args` 説明にも `edgeCaseContext` の追加を明記する。`tests/workflow-guidance.bats` に `EDGE_CASE_SUFFIX` が `finderPrompts` に適用されていることを確認する `grep -q` テストを 1 件追加する (after 1, parallel with 2) (→ Pre-merge AC1, AC3)
4. `agents/review-light.md` の "Perspective 2: Edge Cases and Robustness" セクション (既存の boundary values / external command failure / temp file cleanup の箇条書きの後) に、プロンプトに edge case 実行結果 (`skills/review/SKILL.md` § Parser/Validator Edge Case Pre-check 由来) が含まれる場合はそれを直接この perspective の出力に取り込み再導出しない旨の 1 文を追加する (parallel with 1-3) (→ Pre-merge AC1)
5. `agents/review-bug.md` の "1. Bug/Logic Error Detection" 内、既存の "Date/File-Naming Semantics Cross-Check" ブロックの直後に、同じ構造 (見出し + "When ... " 条件文) で "Pre-measured Edge Case Execution Results" ブロックを追加し、プロンプトに事前実測済み edge case 実行結果が含まれる場合は Detected Issues に直接反映し再導出しない旨を記述する (parallel with 1-4) (→ Pre-merge AC1)

## Verification

### Pre-merge
- <!-- verify: rubric "review の観点定義 (agents/ 配下の review-light または review-bug、あるいは skills/review/SKILL.md) に、入力を解釈・検証・正規化する処理を含む変更に対して negative/edge case 入力を実際に構成して実行する手順が追加されている。発火条件と、最低限カバーする入力の軸が示されている" --> edge case 実測の手順と発火条件が定義されている
- <!-- verify: rubric "手順が --light / --full のどちらで発火するかが明記され、その選択理由が記録されている" --> 発火する review 深度と選択理由が明記されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge
- パーサ系の変更を含む PR の `/review` で、edge case 実測ステップが実行されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **実装検討時に発見した既存実装との抵触 (Step 6 conflict detection。non-interactive につき model judgment で auto-resolve)**: `agents/review-light.md` / `agents/review-bug.md` の `tools:` frontmatter は `Read, Glob, Grep, Bash(git log:*, git diff:*, git show:*)` のみで、任意スクリプトの実行や一時 fixture ファイルの書き込みができない。Issue 本文が想定する「実際に構成して実行する」を文字どおり実装するには、この 2 agent 自体に Bash 実行権限を追加する方法も考えられるが、`skills/spec/SKILL.md` 自身の "allowed-tools impact chain check" が明記するとおり `scripts/*.sh` へのワイルドカード許可はこのリポジトリの既存 allowed-tools パターンに前例がなく (`grep -rn "scripts/\*\." agents/ skills/ modules/ docs/` を実行して確認。ヒットはすべてこのルール自体を説明する prose であり、実際の `allowed-tools:` 値には出現しない)、対象スクリプトは PR ごとに異なるため個別スクリプト名の列挙による許可もできない。加えて `/review` は pre-merge の safe mode 原則 (`docs/product.md` § Terms "safe mode": 外部コマンド実行や副作用のある verify command を制限し CI 参照にフォールバックする) のもとで動作しており、review-light/review-bug という主要 2 レビュー sub-agent 自体に汎用シェル実行権限を恒常的に付与するのは least privilege の観点からも不釣り合いに広い。そこで、Step 10.3 の検証 sub-agent (`subagent_type="general-purpose"`) と同じ既存パターンを再利用し、発火条件に合致したときだけ `general-purpose` (フルツールアクセス) sub-agent を都度起動して実測を行い、結果を `.tmp/base-conflict-context-$NUMBER.md` と同型の context ファイル経由で review-light/review-bug のプロンプトに注入する設計とした。review-light/review-bug 自体の `tools:` frontmatter は変更しない (新規 `scripts/*.sh` も `modules/*.md` も追加しないため、allowed-tools impact chain check の対象外)
- **`workflow-guidance.md` も対象に含めた理由**: 本リポジトリ自身の `.wholework.yml` は `capabilities: workflow: true` を設定済みであり、`--full` レビューは既定で `skills/review/workflow-guidance.md` の Workflow 経路を通る。Step 10.1-10.3 の static fan-out のみに実装すると、本リポジトリ自身の `/review --full` では edge case pre-check が実質発火しない (light mode の 10.0 経由でのみ発火する) ため、Post-merge の観察 AC が長期間観測されないおそれがある。両経路に実装することで機能的な等価性を確保した
- **`docs/structure.md` / `docs/tech.md` の Agent 一覧・Architecture Decisions は更新対象外と判断**: `modules/skill-dev-doc-impact.md` の Change Type 表は agent の追加/変更/削除で `docs/workflow.md` (modules/agents 一覧表) の更新を要求するが、これは agent ファイル自体の追加・削除や役割変更を指すものである。`docs/workflow.md` に review-light/review-bug 個別の観点詳細を記述した一覧表は存在せず (`grep -n "review-light\|review-bug\|review-spec" docs/workflow.md README.md CLAUDE.md` で確認、ヒットは `review-bug: false` という設定例 1 件のみ)、既存の 1 行ロール要約 ("Lightweight Integrated review" / "Bug/Logic Error Detection") は本変更後も引き続き正確なため、更新は不要と判断した
- cap=2 の根拠: Step 10.3 の検証 sub-agent は所見 10 件までを上限とするが、実測 sub-agent は Bash/Write を伴う重い処理のため、それより保守的な 2 ファイルを cap とした
- 用語は `docs/product.md` § Terms の "verify command" / "safe mode" / "full mode" と整合させた (deprecated 用語の使用なし)

## Consumed Comments

| Login | Association | Trust tier | Summary | URL |
|-------|-------------|-----------|---------|-----|
| saito | MEMBER | first-class | `/issue` フェーズの Issue Retrospective。`triaged` 済みのため triage auto-chain はスキップ、steering docs との用語抵触なし、曖昧ポイント検出なし。Post-merge AC の `verify-type: observation event=auto-run` に `session=next` が欠落していたため追加済み (本 Spec 作成時点の Issue body で反映済みを確認)。手順順序の補正メモ (comment consumption を label transition より先に実行すべきところ誤って逆順で実行、実害なし) | https://github.com/saitoco/wholework/issues/1125#issuecomment-5302569064 |

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1-5 を Spec の記述どおりに実装した)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 3件全 PASS・CI SUCCESS・review 承認済みの状態を確認したうえで squash merge を実行した (conflict なし、追加の conflict 解決手順は不要だった)

### Deferred Items
- Post-merge AC (`verify-type: observation event=auto-run session=next`): パーサ系変更を含む次回 PR の `/review` で edge case pre-check が実際に発火するかは post-merge の観察待ち (未変更で継続)

### Notes for Next Phase
- `/verify` では Post-merge AC (observation event=auto-run) の発火有無に加え、本 PR で追加した Trust gating (信頼境界判定) と fixture cleanup が実際のパーサ系 PR で機能するかを次回発火時に確認すること

## review retrospective

### Spec vs. implementation divergence patterns

実装は Spec の Implementation Steps 1-5 におおむね忠実で、Code Retrospective も「Deviations from Design: N/A」としている。今回 `--light` review で検出された5件の指摘 (MUST 1件・SHOULD 3件・CONSIDER 1件) はいずれも Spec が明記していなかった論点に関するものだった。特に、PR diff 由来コードを実際に実行するという設計そのものが持つセキュリティ含意 (実行対象の信頼境界・サンドボックス化) を Spec の Notes セクションは議論していなかった (Notes は allowed-tools 権限設計の議論はあったが、「誰の PR に対して実行するか」という信頼境界の論点はなかった)。今後、diff 由来コードを実際に実行する設計を Spec 化する際は、実行対象の信頼境界を明示的な論点として立てることが望ましい。

### Recurring issues

単一のサブセクション追加でありながら、下流ステップへの伝播漏れ (10.3 検証・Workflow adversarial-refute が事前実測済み finding を認識しない)・cap 発動時の記録欠落・fixture cleanup 未定義・illustrative example の非対称、という複数の統合ギャップが同時に見つかった。「新しい実行系ステップを追加する際、既存の後続ステップ (検証 sub-agent・Workflow 経路・14.2 クリーンアップ・illustrative 例) すべてに一貫して伝播しているか」を横断チェックする観点は、review-light の4観点定義に明示的には存在しない。今回は `--light` review でも機能したため検出できたが、経験1件のみで一般化根拠が薄く、別 Issue 化は見送る。

### Acceptance criteria verification difficulty

3件の Pre-merge AC (rubric×2, github_check×1) はいずれも UNCERTAIN なく明確に判定できた。rubric の文言が「発火条件と入力軸が示されている」「review 深度と選択理由が明記されている」という検証可能な具体的表現になっていたため、grader 判定は容易だった。verify command の記述に問題は見つからなかった。
