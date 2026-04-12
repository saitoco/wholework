# Issue #53: doc: ファイルのコミット・プッシュまでを範囲にする

## Overview

`/doc` 系のドキュメント書き出しサブコマンド（`init`, `product`, `tech`, `structure`, `sync`, `sync --deep`, `sync {doc}`, `add`, `project`）の末尾で、AskUserQuestion による commit/push ガイドを追加する。共有モジュール `modules/doc-commit-push.md` を新設し、各サブコマンドの終端から Read 指示で呼び出す。`translate` は既存実装のため対象外。

確定済み設計方針（Issue Q&A）:
- 対象範囲: ファイルを書き出す 9 サブコマンド全て（translate 除外）
- 実装パターン: 共有モジュール `modules/doc-commit-push.md` 新設
- Q&A 形式: `translate-phase.md` Step 5 の 2 択（"Yes, commit and push" / "No, skip"）
- コミットメッセージ: `docs: <SUMMARY>` + Co-Authored-By 行（SUMMARY は呼び出し側が input で指定）
- 変更なしスキップ: `git status --porcelain` 結果が空なら silent exit
- コミット粒度: 1 サブコマンド = 1 コミット
- `allowed-tools` 変更: 不要（既存宣言で充足）

## Changed Files

- `modules/doc-commit-push.md`: 新規作成。Purpose / Input (`SUMMARY` 変数) / Processing Steps (git status → AskUserQuestion → git add/commit/push) / Output の 4 節構造
- `skills/doc/SKILL.md`: `Individual Create/Update`, `init Wizard`, `sync Bidirectional Normalization` (reverse-generation 完了点 + normalization 完了点の両方), `sync Individual Reverse-Generation`, `add — Register Existing Document`, `project — Create New Project Document` の各セクション末尾に commit/push ガイドの Read 指示を追加
- `docs/structure.md`: Key Files > Modules リストに `modules/doc-commit-push.md` エントリを追加（既存の `doc-checker.md` エントリと対称配置）

## Implementation Steps

1. `modules/doc-commit-push.md` を新規作成（→ 受入条件 1, 2, 3）
   - 4 節標準構造（Purpose / Input / Processing Steps / Output）に従う
   - Purpose: `/doc` 系サブコマンドが書き出したファイル変更のコミット・プッシュをユーザーに確認・実行する
   - Input: `SUMMARY` — コミットメッセージ本文用のサマリー文字列（呼び出し側が設定、例: `"sync steering documents (reverse-generation)"`）
   - Processing Steps:
     1. `git status --porcelain` を実行し出力が空なら silent exit（「変更なし」）
     2. 変更サマリー（`git status` の短い表示）を表示
     3. AskUserQuestion で 2 択提示: "Yes, commit and push" / "No, skip"
     4. "No" 選択: "Changes left uncommitted. Run `git status` to review, or re-run the /doc command later." と表示して exit
     5. "Yes" 選択: `git add -A`（もしくは変更パスに限定）→ `git commit -m "docs: ${SUMMARY}\n\nCo-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"` → `git push origin HEAD` を実行
     6. コミットハッシュ・push 結果を表示して exit
   - Output: 副作用（コミット・プッシュ）のみ。戻り値なし

2. `skills/doc/SKILL.md` の対象 6 セクション末尾に commit/push ガイド Read 指示を追加（→ 受入条件 4）
   - 追加位置: 各セクションの最終 Step の直後、次の `---` セパレータ or `##` 見出しの直前
   - 追加形式: 新規 `### Step N: Commit and Push Guide` を追加し、内容は `Read \`${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md\` and follow the "Processing Steps" section with \`SUMMARY="<subcommand-specific summary>"\`.` とする
   - 対象セクションと SUMMARY 文字列（例）:
     - `Individual Create/Update` → `SUMMARY="update {doc}"` （{doc} は product/tech/structure）
     - `init Wizard` → `SUMMARY="init steering documents"`
     - `sync Bidirectional Normalization` (reverse-generation 出口) → `SUMMARY="sync (reverse-generation)"`
     - `sync Bidirectional Normalization` (normalization 出口) → `SUMMARY="sync (normalization)"`
     - `sync Individual Reverse-Generation` → `SUMMARY="sync {doc} (reverse-generation)"`
     - `add — Register Existing Document` → `SUMMARY="register {path} as project document"`
     - `project — Create New Project Document` → `SUMMARY="create project document {name}"`
   - sync Bidirectional Normalization は Step 5 末尾（reverse-generation 完了時）と Step 9 末尾（normalization 完了時）の両方に Read 指示を追加する

3. `docs/structure.md` の Key Files > Modules リストに新モジュールを追記（→ Changed Files 整合）
   - 追記位置: 既存行 `- \`modules/doc-checker.md\` — documentation consistency checker` の直後
   - 追記内容: `- \`modules/doc-commit-push.md\` — commit/push guide for /doc subcommand outputs`

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/doc-commit-push.md" --> 共有モジュール `modules/doc-commit-push.md` が作成されている
- <!-- verify: section_contains "modules/doc-commit-push.md" "## Processing Steps" "AskUserQuestion" --> `modules/doc-commit-push.md` の Processing Steps に AskUserQuestion による commit/push 確認フロー（Yes/No 選択肢）が記載されている
- <!-- verify: section_contains "modules/doc-commit-push.md" "## Processing Steps" "git push" --> `modules/doc-commit-push.md` に `git status` → `git add` → `git commit` → `git push` の実行手順が含まれている
- <!-- verify: file_contains "skills/doc/SKILL.md" "doc-commit-push.md" --> `skills/doc/SKILL.md` から `modules/doc-commit-push.md` を参照する Read 指示が追加されている
- <!-- verify: grep "doc-commit-push" "docs/structure.md" --> `docs/structure.md` の Modules リストに `modules/doc-commit-push.md` が追記されている

### Post-merge

- `/doc sync --deep` を実行してドキュメントを更新した直後、commit/push 確認の AskUserQuestion が表示され、Yes を選ぶと commit/push が完了することを確認 <!-- verify-type: opportunistic -->
- `/doc add {path}`, `/doc project`, `/doc tech` 等の他サブコマンド実行後も同様に commit/push 確認が表示されることを確認 <!-- verify-type: opportunistic -->

## Notes

- **既存実装との一貫性**: `skills/doc/translate-phase.md` Step 5〜6 が同等の Q&A → git commit/push パターンを持つ。本モジュールはその設計を抽出・一般化したもの。将来 `translate-phase.md` も本モジュールに移行する余地があるが本 Issue スコープ外。
- **`docs/ja/structure.md`**: 翻訳出力ファイル（`/doc translate ja` 生成）のため実装対象外。
- **SUMMARY 文字列の具体値**: 実装時に呼び出し側サブコマンドの context に応じて決定する。placeholders（`{doc}`, `{path}`, `{name}`）は呼び出し時点の実値で展開される想定。モジュール側は文字列を受け取ってそのままコミットメッセージ本文に埋め込むのみ。
- **`sync Bidirectional Normalization` の 2 出口**: reverse-generation (Steps 2–5) と normalization (Steps 6–9) の両フローで commit/push 機会があるため、それぞれの完了点に Read 指示を置く必要がある。どちらか一方の出口からは必ず commit/push ガイドを通過する設計。
- **`git add -A` vs 変更パス限定**: モジュール側で `git add -A` を使用（呼び出し側の変更が docs/ 以下に限定される前提で安全）。ユースケース拡張で限定が必要になった場合は Input を拡張できる余地を残す。
- **`AskUserQuestion` の挙動**: Claude Code 環境下でのみ動作。`claude -p --dangerously-skip-permissions` では自動的に「最初の選択肢」が選ばれる前提（既存 translate-phase.md と同方針）。

## Code Retrospective

### Deviations from Design

- `sync Bidirectional Normalization` の reverse-generation 完了点（Step 5 末尾）への追加は、Spec の「新規 `### Step N: Commit and Push Guide` を追加し」という形式ではなく、Step 5 の末尾にインライン追記する形を採用した。理由: Step 5（reverse-generation exit）と Step 6（normalization の開始）の間に新規ステップ番号を挿入すると既存の Steps 6–9 を全て繰り上げ変更する必要があり、変更範囲が大きくなるため。Notes 節の「Step 5 末尾に Read 指示を追加する」という表現がこのインライン方式を支持していると判断した。
- `init Wizard` の Step 5 の「and exit」を「and proceed to Step 6」に変更した上で Step 6 を追加した。Spec の「最終 Step の直後に追加」では既存 Step 5 の exit 記述と矛盾が生じるため、Step 5 も合わせて修正した。

### Design Gaps/Ambiguities

- Spec の「追加形式: 新規 `### Step N: Commit and Push Guide` を追加し」という指示と「Step 5 末尾（reverse-generation 完了時）と Step 9 末尾（normalization 完了時）の両方に Read 指示を追加する」という Notes 節の記述が若干矛盾していた（前者は新規ステップ、後者は既存ステップへの追記を示唆）。`sync Bidirectional Normalization` のケースで判断が必要だった。

### Rework

- 特になし

## review retrospective

### Spec vs. 実装の乖離パターン

`sync Bidirectional Normalization` の reverse-generation 出口において、Spec の「新規 `### Step N: Commit and Push Guide` を追加」指示と Notes 節の「Step 5 末尾にインライン追記」指示が矛盾していた。実装者は Notes 節の記述を優先してインライン方式を採用し、その理由をCode Retrospectiveに記録した。この種の Spec 内矛盾は、将来のSpec作成時に「既存ステップ番号への影響」を明示的に検討する設計ポイントとして意識するとよい。

### 繰り返し問題

特になし。

### 受入条件検証難易度

全5条件が `file_exists`, `section_contains`, `file_contains`, `grep` の静的コマンドで構成されており、safe mode での自動検証が完全に可能だった。UNCERTAINが0件で、verify commandの設計が適切だった。Post-merge条件は `opportunistic` タイプで適切に分類されている。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の受入条件は全て静的検証コマンドで構成されており、自動検証の設計精度が高かった。
- `sync Bidirectional Normalization` の2出口（reverse-generation と normalization）という複雑なケースも Spec 段階で明示的に言及されており、実装者の判断指針となった。

#### design
- Spec 内で「新規 `### Step N: Commit and Push Guide` を追加」という指示と「Step 5 末尾にインライン追記」を示唆する Notes 節が矛盾していた。既存ステップ番号への影響を考慮する観点が欠けていた。
- 改善提案: Spec 作成時に「既存ステップ番号への影響」を明示的に検討する設計チェックリスト項目を追加すると良い。

#### code
- `sync Bidirectional Normalization` の reverse-generation 完了点でインライン方式を採用（Spec の新規ステップ追加方式ではなく）。既存ステップ番号を繰り上げる変更範囲の大きさを避けるための合理的判断だった。
- `init Wizard` の Step 5 の exit 記述を修正してから Step 6 を追加するという Spec にない追加修正が発生したが、整合性維持のために必要だった。

#### review
- Spec 内矛盾（新規ステップ追加 vs インライン追記）について review で言及されており、将来の Spec 品質向上につながる観点が共有された。
- PR #139 はレビューコメント1件で完了。実装品質は高く、大きな問題は検出されなかった。

#### merge
- FF マージ（PR #139 → commit `6da7837`）で問題なく完了。コンフリクトなし。

#### verify
- 全5件の Pre-merge 条件が PASS。静的検証コマンドのみで構成されており UNCERTAIN 0件。
- Post-merge opportunistic 条件（2件）はユーザー検証待ち。これは適切な分類。
- 今回の検証で特段の問題は検出されなかった。

### Improvement Proposals
- N/A
