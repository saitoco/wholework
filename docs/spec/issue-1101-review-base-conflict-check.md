# Issue #1101: review: ベースブランチとの conflict 事前検査ステップの追加

## Overview

Issue #1069 / PR #1077 のレビューで、ベースブランチ (main) 側の並行変更 (#1074) と `modules/verify-executor.md:74` が同一行で衝突していたにもかかわらず、`/review` の既存ステップ (受入条件検証・CI 確認・多観点コードレビュー) では検知できず、`git merge-tree $(git merge-base HEAD origin/main) HEAD origin/main` を手動実行して初めて発覚した。CI はブランチ単体で走るため SUCCESS のままであり、GitHub の `mergeable` 判定もテキストレベルの自動マージ可否のみを見る。`modules/verify-executor.md` のような SSoT 文書は複数 Issue が同一行を繰り返し編集するため (#424 / #1056 / #1074 / #1069)、再発は確実。

本 Issue では `/review` のコードレビュー (Step 10) 前に `git merge-tree` によるベースブランチとの conflict 事前検査を追加し、`changed in both` として検出されたファイル (特に SSoT 文書) について、ベース側の変更内容をレビュー入力として明示的に渡し、両方の変更が保持される解決になっているかをレビュー対象に含める。

## Changed Files

- `skills/review/SKILL.md`:
  - frontmatter `allowed-tools`: `git merge-tree:*`, `git merge-base:*` を追加 (既存の git サブコマンド個別列挙 `git log:*, git diff:*, git show:*, git add:*, git commit:*, git push:*, git fetch:*, git checkout:*, git worktree:*, git branch:*` に含まれていない — 未追加のままだと非対話モードでパーミッションエラーになる)
  - `## Step 10: Multi-perspective Code Review (parallel execution)`: Base Branch Conflict Pre-check サブセクションを追加。`10.0`/`10.2` の Task プロンプトを拡張。`14.2` のクリーンアップ対象に一時ファイルを追加
- `skills/review/workflow-guidance.md`: Workflow パス (`capabilities.workflow: true` 時の finder → adversarial verify pipeline) にも conflict context を伝搬 — Issue 本文の verify command が直接カバーする対象ではない completeness 拡張。理由は Notes 参照

## Implementation Steps

1. (→ AC1, AC2) `skills/review/SKILL.md` frontmatter の `allowed-tools` に `git merge-tree:*`, `git merge-base:*` を追加する。

2. (→ AC1, AC2, AC3) `skills/review/SKILL.md` の `## Step 10: Multi-perspective Code Review (parallel execution)` 内、既存の `**In light mode**: if `REVIEW_DEPTH=light` and Issue number was extracted...` 段落の直後、`### 10.0. Lightweight Integrated Review (REVIEW_DEPTH=light only)` 見出しの直前に、無番号の新規サブセクション「Base Branch Conflict Pre-check」を挿入する。light/full/Workflow の分岐点より前に位置するため、以降のどの経路でも共通して実行される。処理内容:
   - `git fetch origin "$BASE_REF"` を実行し `origin/$BASE_REF` を最新化する
   - `MERGE_BASE_SHA=$(git merge-base HEAD "origin/$BASE_REF")` を計算する
   - `git merge-tree "$MERGE_BASE_SHA" HEAD "origin/$BASE_REF"` を実行する。**この非推奨 3 引数 `--trivial-merge` 形式を厳密にそのまま使うこと** (git 2.55.0 で実機検証済み — 同一行を双方が変更した衝突で `changed in both` ヘッダーを出力することを確認済み)。現行推奨の `--write-tree` 2 引数形式に置き換えないこと — そちらは同じ衝突を `CONFLICT (content): Merge conflict in <path>` として報告し、`changed in both` という文字列を一切含まない (詳細は Notes)
   - 出力を `changed in both` ブロック単位でパースし、各ブロックの `their` 行に続くファイルパスを抽出する
   - 抽出した各パスについて `git diff "$MERGE_BASE_SHA" "origin/$BASE_REF" -- "<path>"` でベース側の変更内容 (Issue 本文「対応方針」項目2の「ベース側の変更内容」) を取得し、パスが `modules/*.md` または `docs/*.md` に一致する場合は `[SSoT]` フラグを付与する
   - 該当ファイルが1件以上あれば `.tmp/base-conflict-context-$NUMBER.md` に (パス / `[SSoT]` フラグ / ベース側 diff) を書き出す。0件なら書き出さず後続に追加コンテキストを渡さない
   - `.tmp/base-conflict-context-$NUMBER.md` を `14.2` の既存 `rm -f` クリーンアップ対象リストに追加する

3. (→ AC1, AC3) `skills/review/SKILL.md` の `### 10.0` step 4 (`review-light` の Task プロンプト) と `### 10.2` step 3 (`review-spec` / `review-bug`×2 の Task プロンプト) を拡張する。`.tmp/base-conflict-context-$NUMBER.md` が存在する場合、その内容を各プロンプト文字列に追記し、次の指示を明記する: (a) 列挙されたファイルで PR の現在の解決がどちらか一方の変更を失っている場合は MUST として報告する、(b) `[SSoT]` が付いたファイル (`modules/*.md` / `docs/*.md` に一致) は複数 Skill から参照される SSoT 文書のため優先的に確認する

4. (→ AC1, AC3) `skills/review/workflow-guidance.md` にも同じ conflict context を伝搬させる。本プロジェクト自身の `.wholework.yml` で `capabilities.workflow: true` が設定されており、L/XL の full mode レビュー (`REVIEW_DEPTH=full`) は `skills/review/SKILL.md` の静的 `10.1`–`10.3` ではなくこのファイルの Processing Steps (Workflow パス) を経由する (理由は Notes)。`Processing Steps (Workflow Path)` step 4 で Workflow ツールに渡す `args` オブジェクトに `conflictContext` フィールド (`.tmp/base-conflict-context-$NUMBER.md` の内容、存在しない場合は空文字列) を追加し、Inline Workflow Script 内の 3 つの `finderPrompts` テンプレート文字列それぞれに、step 3 と同じ conflict context + MUST/SSoT 指示を追記する

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md に、ベースブランチとの conflict 事前検査ステップ (git merge-tree による changed in both の検出、両方の変更が保持されるかの確認、および対象ファイルが modules/*.md や docs/*.md 等の SSoT 文書である場合の重点的な扱い) が追加されている" --> `/review` にベースブランチとの conflict 事前検査ステップが追加されている
- <!-- verify: grep "merge-tree" "skills/review/SKILL.md" --> `skills/review/SKILL.md` が `merge-tree` に言及している
- <!-- verify: grep "SSoT" "skills/review/SKILL.md" --> `skills/review/SKILL.md` が SSoT 文書の重点的な扱いに言及している
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストスイートが CI で pass する

### Post-merge

- ベースブランチ側と同一行を変更する PR を実際にレビューし、conflict が MUST 指摘として検出されることを確認する <!-- verify-type: manual -->

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: `/issue` フェーズの Issue Retrospective。非対話モードでの Auto-Resolve Log 2 件 (Domain Classification=Core 確定、AC1 rubric への SSoT 明記追加) を記録しているが、いずれも Issue 本文に既に反映済みであり本 Spec への追加アクションは不要と判断した。 / URL: https://github.com/saitoco/wholework/issues/1101#issuecomment-5161713038

## Notes

### `git merge-tree` の形式選定 (external spec 検証済み)

Git 2.55.0 (`git --version` で確認) で `git merge-tree --help` を確認したところ、Issue 本文が指定する 3 引数の `<base-tree> <branch1> <branch2>` 形式は **`--trivial-merge` として deprecated** と明記されており、現行推奨は `--write-tree` を伴う 2 引数形式である。この違いが出力フォーマットに直接影響するため、このリポジトリ内で一時ブランチを使って両形式を実機比較した (作業後に削除済み、コミット・push なし):

- **非推奨 3 引数形式** (`git merge-tree "$MERGE_BASE_SHA" HEAD "origin/$BASE_REF"`): 同一行を双方が変更した衝突で `changed in both` ヘッダーを出力することを確認 (Issue 本文の前提と一致)
- **現行推奨 `--write-tree` 形式**: 同じ衝突を `CONFLICT (content): Merge conflict in <path>` として出力し、`changed in both` という文字列は一切含まれない

AC1 の rubric と AC2 の `grep "merge-tree"` はいずれも `changed in both` という具体的な文字列検出を前提にしているため、実装は **意図的に非推奨の 3 引数形式を使用すること**。`git help` 上は deprecated と明記されているが撤去予定の記載はなく、現時点でオプション自体は存続している。

### `allowed-tools` 未登録の検出

`skills/review/SKILL.md` の既存 `allowed-tools` は git サブコマンドを個別列挙するパターン (`git log:*, git diff:*, git show:*, ...`) を採っており、ワイルドカードでの包括カバーはない。`git merge-tree` と `git merge-base` は現在未登録であることを frontmatter を直接確認して検出した。Changed Files に追加済み。実装後は `scripts/check-allowed-tools.sh` (`/code` Step 8 で自動実行) でも整合性が再確認される。

### Workflow パス (`skills/review/workflow-guidance.md`) を Changed Files に含めた理由

`.wholework.yml` に `capabilities.workflow: true` が設定されているため、本プロジェクト自身の `/review --full` (Size L/XL) は `skills/review/SKILL.md` の静的 Task fan-out (`10.1`–`10.3`) ではなく `skills/review/workflow-guidance.md` の Processing Steps (finder → adversarial verify pipeline) を経由する。実際、本 Issue の発端となった #1069 は Size L (`get-issue-size.sh 1069` で確認) であり、review retrospective には「`capabilities.workflow: true` を設定していても Workflow パスに入れなかった (Workflow ツール自体がセッションに存在しなかったため静的 Task fan-out にフォールバックした)」と記録されている — つまり #1069 は本来 Workflow パスに入るはずが、ツール不在という別要因でたまたま静的パスにフォールバックし、そちらで conflict が検出可能になっていたに過ぎない。`skills/review/SKILL.md` のみを修正し `workflow-guidance.md` を素通りさせると、Workflow ツールが利用可能な通常時には本 Issue が対処しようとしている conflict 見落としがそのまま再発しうる。そのため AC1 の rubric が直接検証する対象ではないが、「conflict 事前検査ステップ」という要件を `/review` の実際の実行経路 (static / Workflow の両方) に一貫させるための How の一部として Changed Files に含めた。AC の文言・件数は変更していない (Issue body の Pre-merge 4 件を検証コマンドとして verbatim 転記、追加の verify command は導入しない)。

### `docs/workflow.md` 更新は不要と判断

`docs/workflow.md` の `/review` セクション (§4, 67-93行) は Size ベースのレビュー深度・外部レビューツール連携・`--review-only` など高レベルな挙動のみを記載しており、Step 7-14 の内部ステップ番号や個々のサブステップ内容には触れていない (grep で該当箇所を確認済み)。今回追加する事前検査は `/review` 内部の品質強化であり、フェーズの境界・Size ルーティング・フラグを変えるものではないため、対象外とした。`docs/`, `tests/`, `scripts/` 配下を `merge-tree` / `changed in both` / `git merge-base` で横断 grep したが、本変更に追従が必要な既存ドキュメント・テスト・スクリプトへの参照は見つからなかった (`docs/spec/issue-1069-*.md` 等の過去 Spec ファイルの retrospective 記述のみがヒットしたが、これらは履歴記録であり同期対象ではない)。

### Post-merge 手動検証時の既知の交絡要因

単一アカウント運用では `scripts/gh-pr-review.sh` が MUST 指摘時に選択する `event=REQUEST_CHANGES` を GitHub API が 422 (`Can not request changes on your own pull request`) で拒否する既知の問題があり、別 Issue #1102 で追跡中 (未解決)。Post-merge の手動検証 (「conflict が MUST 指摘として検出されることを確認する」) を実施する際は、レビュー本文/コメントに MUST 指摘の内容自体が含まれているかで判定し、`event=REQUEST_CHANGES` の投稿可否 (#1102 のスコープ) とは分けて評価すること。

### Domain Classification

`/issue` フェーズで Core (`skills/review/SKILL.md`) 対象と確定済み (`skills/review/skill-dev-recheck.md` は `scripts/validate-skill-syntax.py` が存在する skill 開発リポジトリ限定の Domain file であり対象外)。本 Spec も同じ判断を継承する。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜4 をそのままの順序・挿入位置で実装した。

### Design Gaps/Ambiguities

- Implementation Steps 3/4 の「conflict context をプロンプトに追記する」は、`.tmp/base-conflict-context-$NUMBER.md` が存在しない場合の扱いを明示していなかった。実装では各 Task プロンプト文字列に `[, base branch conflict context: <contents ..., if present>]` という条件付き断片を埋め込み、ファイル不在時は何も追記されない形にした (Workflow パス側は `args.conflictContext` が空文字列なら `CONFLICT_SUFFIX` も空文字列になる同等のロジック)。プロンプト文字列自体は静的なテンプレートであり実行時分岐を書けないため、この表現が妥当と判断した。

### Rework

N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Base Branch Conflict Pre-check を Step 10 の分岐点 (light/full/Workflow) より前に無番号セクションとして挿入し、どの経路でも共通実行されるようにした (Spec Implementation Steps 2 の指示通り)
- `git merge-tree` は非推奨の 3 引数 `--trivial-merge` 形式を意図的にそのまま使用 (`--write-tree` 2 引数形式には置き換えない) — `changed in both` 文字列の検出に依存する AC2 のため
- conflict context をプロンプトに渡す際は、`.tmp/base-conflict-context-$NUMBER.md` の有無で分岐する条件付きテンプレート断片として各 Task プロンプト文字列 (static 側 10.0/10.2 の3箇所、Workflow 側 finderPrompts の3箇所、計6箇所) に埋め込んだ

### Deferred Items
- Post-merge の手動検証 (「ベースブランチ側と同一行を変更する PR を実際にレビューし、conflict が MUST 指摘として検出されることを確認する」) は本 PR のマージ後に人手で実施する
- `docs/workflow.md` の更新は Spec Notes で不要と判断済み (フェーズ境界やルーティングを変えない内部品質強化のため)

### Notes for Next Phase
- AC4 (`github_check "gh pr checks" "Run bats tests"`) は PR 作成前は UNCERTAIN (対象 PR が存在しないため) — PR #1145 作成後の CI 結果で確認すること
- ローカルで `bats tests/` を実行し 1325 件全て pass を確認済み (behavioral change 検出により full suite 実行)
- Post-merge 手動検証時は Issue #1102 (`event=REQUEST_CHANGES` の 422 既知問題) と評価軸を分けること (Spec Notes 参照)
