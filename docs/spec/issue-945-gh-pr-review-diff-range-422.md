# Issue #945: review: gh-pr-review.shのdiff範囲外行422エラーを修正

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 要旨: Issue Retrospective。2点の曖昧さ (実装箇所は `gh-pr-review.sh` に一本化／フォールバック方式は General Comments 統合を採用) の自動解決根拠を説明。Issue body の「Auto-Resolved Ambiguity Points」と同内容だが、既存パターン調査に基づく判断根拠がより詳細 / URL: https://github.com/saitoco/wholework/issues/945#issuecomment-4887933121

## Overview

`/auto` 実行中の review phase (Issue #934, PR #943) で、review-light エージェントが「既存箇所の未更新」(diff に含まれない pre-existing 行) を指摘した際、`gh-pr-review.sh` が GitHub Review API から `422 Line could not be resolved` を受けて失敗した。GitHub の Pull Request Review API は、コメント対象の `line` が PR diff のハンク範囲内 (diff に実際に表示されている行) でなければ受け付けない制約があり、この失敗パターンは「既存箇所の未更新」を指摘するレビューの性質上、繰り返し発生しうる。

本 Issue では `gh-pr-review.sh` に、line comments の各エントリが PR diff のハンク範囲内かを事前チェックする仕組みを追加し、範囲外の場合は API 送信対象の `comments[]` から除外し、レビュー本文の General Comments セクションにテキストとして統合するフォールバックを実装する (Issue Retrospective で自動解決済みの方針: 実装箇所は `gh-pr-review.sh` に一本化、フォールバック方式は `skills/review/SKILL.md` Step 11 の既存 General Comments パターンを再利用)。

## Reproduction Steps

1. `/review` 実行中、レビューエージェント (review-light 等) が既存コード (今回の diff に含まれない pre-existing 行) の未更新を指摘する — この際 `path` は特定できるが `line` は diff に含まれない
2. `skills/review/SKILL.md` Step 10 の統合フェーズは `path` が non-null かどうかのみを判定しており、diff ハンク範囲内かは判定しないため、この指摘は line comments 配列 (`side: "RIGHT"`) に含められる
3. Step 11 で `scripts/gh-pr-review.sh $NUMBER .tmp/review-body-$NUMBER.md .tmp/review-comments-$NUMBER.json` が呼ばれ、`gh api repos/{owner}/{repo}/pulls/{PR}/reviews` に POST される
4. GitHub Review API は "Pull request review thread line must be part of the diff" として当該行を拒否し、`422` を返す。これが Issue body に記載された `422 Line could not be resolved` エラーである。line comments 配列内の1件でも範囲外だとレビュー全体の POST が失敗する (該当コメントだけが失敗するのではない)
5. 実際の発生例: Issue #934 の `/auto` review phase (PR #943) で `modules/observation-trigger.md:26` (既存の一次 Arguments テーブル) を指摘した際にこの失敗が発生し、diff 内の関連する新規行に手動で付け替えて解消した (`docs/spec/issue-934-observation-condition-gate.md` に記録)

## Root Cause

`gh-pr-review.sh` (および呼び出し元の `skills/review/SKILL.md` Step 10 の line/path 振り分けロジック) は、line comments の `path`/`line` が実際に PR diff のハンク範囲内かどうかを一切チェックしていない。GitHub の Pull Request Review API は、コメント対象の行が diff のハンク (`@@ ... @@` で示される変更範囲) に含まれない場合 "Pull request review thread line must be part of the diff" として `422` を返す制約があり ([GitHub REST API docs](https://docs.github.com/en/rest/pulls/reviews) および community reports で確認済み)、これは公式ドキュメントに明文化された固有のエラーメッセージではなく、実運用で観測される制約である。Step 10 は `path !== null` のみをゲート条件としているため、「既存箇所の未更新」のように path は特定できるが line が diff 範囲外という指摘が、そのまま API 送信対象に混入し、レビュー全体の POST 失敗を招く。

## Changed Files

- `scripts/gh-pr-review.sh`: line comments 処理時に `gh pr diff "$PR_NUMBER"` を取得して diff ハンク範囲 (`path` → `[(new_start, new_end), ...]`) をパースし、範囲外の行を `comments[]` から除外してレビュー本文の General Comments セクションにテキスト統合するフォールバックを追加。ヘッダーコメント (Line comments JSON format 説明) にこの挙動を追記。bash 3.2+ 互換 (レンジ判定は既存同様 python3 heredoc で実装、bash 側は `mktemp` 経由の一時ファイル読み込みのみ)
- `tests/gh-pr-review.bats`: `setup()` の `gh` モックに `gh pr diff` 分岐を追加し、diff 範囲外行の General Comments フォールバックおよび範囲内行が従来通り line comment として POST されることを検証するテストケースを追加。bash 3.2+ 互換 (既存ファイルと同じ bats/bash パターンを踏襲)
- `docs/structure.md`: [Steering Docs sync candidate] `gh-pr-review.sh` の一行説明 ("post PR reviews") が変更後も正確か確認。挙動追加は内部実装でありユーザー向け説明文の変更は不要と判断 (最終確認は `/code` に委ねる)
- `docs/ja/structure.md`: [Steering Docs sync candidate] 上記の日本語ミラー、同様の確認
- `docs/migration-notes.md`: [Steering Docs sync candidate] `### gh-pr-review.sh` セクション ("Interface changes: None") が変更後も正確か確認。CLI 引数 (`pr-number`/`review-body-file`/`line-comments-json-file`) は変更しないため "None" のまま正確と判断 (最終確認は `/code` に委ねる)
- `docs/ja/migration-notes.md`: [Steering Docs sync candidate] 上記の日本語ミラー、同様の確認

## Implementation Steps

1. `scripts/gh-pr-review.sh`: line comments ファイルが指定され JSON バリデーションを通過した後、`gh pr diff "$PR_NUMBER"` の出力を `mktemp` で作成した一時ファイルに保存する (取得失敗時は `Error: failed to fetch PR diff for #$PR_NUMBER` を stderr に出力し exit 1、既存の `REPO` 取得失敗時と同様のエラーハンドリング形式)。一時ファイルは `trap ... EXIT` で確実に削除する (→ 受け入れ基準1)
2. (after 1) 取得した diff テキストをパースし、unified diff のハンクヘッダー (`@@ -o,p +n,q @@`) と各ファイルの `+++ b/<path>` 行から `path → [(new_start, new_end), ...]` の範囲マップを構築する。ハンクヘッダーの count 省略時は 1 として扱う (unified diff 仕様上 `,s` 部分は s=1 のとき省略可)。`+++ /dev/null` (削除ファイル) は範囲マップの対象外とする (→ 受け入れ基準1)
3. (after 2) 既存の REVIEW_PAYLOAD 構築用 python ステップ内で、`required_keys` フィルタ済みの `clean_comments` をさらに「範囲内 (`side: RIGHT` の `line` が Step 2 の範囲マップ内)」と「範囲外」に振り分ける。範囲内のコメントは従来通り `comments[]` に残す。範囲外のコメントは `comments[]` から除外し、`- **{path}:{line}**: {body}` 形式の Markdown 箇条書きに変換したうえでレビュー本文に統合する — 本文中に `### General Comments` 見出し (前方一致、末尾の補足テキストは許容) が存在すればその直後に追記し、存在しなければ本文末尾に `### General Comments (auto-added: line outside PR diff range)` セクションを新設して追記する。`HAS_MUST` 判定は変更しない (元の `$LINE_COMMENTS_FILE` 全件を対象にした既存ロジックのままとし、範囲外へ振り分けられた MUST コメントも `REQUEST_CHANGES` 判定に引き続き寄与させる)。スクリプト冒頭のヘッダーコメントにもこのフォールバック挙動を追記する (→ 受け入れ基準1)
4. (after 3) `tests/gh-pr-review.bats` の `setup()` 内 `gh` モックに `gh pr diff` 分岐を追加し (固定のフィクスチャ diff テキストを返す)、(a) diff 範囲外の `line` を持つコメントが `comments[]` から除外されレビュー本文に文字列として出現すること、(b) 範囲内のコメントは従来通り line comment として POST されること (回帰確認) を検証するテストケースを追加する (→ 受け入れ基準2)

## Verification

### Pre-merge
- <!-- verify: rubric "gh-pr-review.shが、line commentsの各エントリについてdiff hunk範囲内かを事前チェックし、範囲外の場合はcomments配列から除外してレビュー本文にGeneral Commentsとしてマージする機構を持つ" --> `gh-pr-review.sh` に、diff hunk 範囲外行の自動フォールバック (comments 配列からの除外 + レビュー本文への General Comments 統合) が実装されている
- <!-- verify: rubric "tests/gh-pr-review.batsに、diff範囲外行を指定した場合にGeneral Commentsへフォールバックする動作を検証するテストが含まれる" --> `tests/gh-pr-review.bats` に、diff 範囲外行指定時の General Comments フォールバック動作を検証するテストが追加されている

### Post-merge
- 次回 review エージェントが既存箇所の未更新を指摘した際、422 エラーによる手戻りが発生しないことを観察

## Notes

- **bats テスト入力データ形式**: `setup()` の `gh` モック (`$MOCK_DIR/gh`) は現在 `repo view` と `api --input` の2分岐のみ。新規追加する `gh pr diff` 分岐は `"$1" = "pr"` かつ `"$2" = "diff"` を条件に、固定のフィクスチャ unified diff テキスト (例: `--- a/scripts/example.sh` / `+++ b/scripts/example.sh` / `@@ -8,3 +8,4 @@` のようなヘッダーを含む数行) を標準出力に返すこと。範囲外テストケースの line comments JSON は、このフィクスチャ diff のハンク範囲外の行番号 (例: ハンク範囲が 8-11 なら line=50 等) を指定する
- 範囲内/範囲外の判定は `side: "RIGHT"` のみを対象とする。現行コードベースでは `skills/review/SKILL.md` の Step 10 が line comments に常に `side: "RIGHT"` を設定しており (`grep -n '"side"' skills/review/SKILL.md` で確認済み、`LEFT` の使用箇所なし)、`side: LEFT` (削除行への旧側コメント) は現状のユースケースに存在しないため本 Issue のスコープ外とする
- **外部仕様依存チェック**: GitHub REST API 公式ドキュメント (`docs.github.com/en/rest/pulls/reviews`) では `line`/`side`/`start_line`/`start_side` フィールドの詳細な制約は明記されていない。422 発生条件 ("Pull request review thread line must be part of the diff") は公式ドキュメントに明文化されたエラーメッセージではなく、実運用時の community reports (GitHub Discussions) および Issue #934 での実際の発生事例から確認した。この点は `gh-pr-review.sh` の実装が「未文書化だが実運用で確認された API 制約」に依拠することを意味し、将来 GitHub 側の挙動が変わった場合は本ロジックの見直しが必要になりうる
- **diff の取得方法**: `skills/review/SKILL.md` は `gh pr diff "$NUMBER"` (オプションなし、素の unified diff 形式) を既に Step 10 で使用しており (`.tmp/pr-diff-$NUMBER.txt` に保存)、本 Issue の `gh-pr-review.sh` 内実装もこの既存呼び出し規約と同一のコマンド形式 (`gh pr diff "$PR_NUMBER"`) を用いる
- **doc-checker Impact Assessment**: Change Type 表 (workflow phase changes / project structure changes) にはいずれも該当しない (スクリプト内部ロジックの堅牢化であり、ワークフローフェーズやディレクトリ構成の変更を伴わない)。Steering Docs sync candidate として列挙した4ファイルは、いずれも `gh-pr-review.sh` の一行説明・Interface changes 記載のみを含み、本 Issue の変更 (内部フォールバック機構の追加) では記載内容の実質的な変更は不要と判断したが、最終確認は `/code` に委ねる

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜4 の順序・範囲通りに実装した (再構成・省略なし)

### Design Gaps/Ambiguities
- Spec Notes は新設する `gh pr diff` モック分岐のフィクスチャ diff について、範囲外テストケースの line 番号選定にのみ言及していたが、実装時に判明した点として、`gh-pr-review.sh` は line comments が存在する限り無条件で `gh pr diff` を呼ぶようになるため、既存5テストケース (`scripts/example.sh:10/42`、`scripts/other.sh:10/20`、`scripts/valid.sh:5`) を壊さないよう、フィクスチャの各ファイルのハンク範囲を `1-50` まで広げる必要があった。既存テストとの整合性確保は Spec に明記されておらず、実装時の判断で対応した

### Rework
- N/A —手戻りは発生しなかった

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 実装箇所は Issue Retrospective で自動解決済みの方針通り `scripts/gh-pr-review.sh` に一本化した
- diff ハンク範囲のパースは python3 heredoc 内で正規表現 (`^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@`) により実装し、bash 側は `mktemp` + `trap EXIT` での一時ファイル管理のみに留めた (既存コードスタイルと統一)
- General Comments へのマージは、本文中に `### General Comments` 見出しが既にあればその直後に追記、なければ `### General Comments (auto-added: line outside PR diff range)` を新設するロジックとした (`skills/review/SKILL.md` Step 11 の既存パターンを再利用)
- `HAS_MUST` (REQUEST_CHANGES 判定) は変更せず、`$LINE_COMMENTS_FILE` 全件を対象にした既存ロジックのまま維持し、範囲外へ振り分けられた MUST コメントも判定に引き続き寄与させた

### Deferred Items
- Post-merge の "422 エラーによる手戻りが発生しないことを観察" は `/verify` フェーズに委ねる (opportunistic verify-type)
- `side: LEFT` のケースは Spec Notes 記載の通りスコープ外のまま (現行コードベースに使用箇所なし)

### Notes for Next Phase
- `tests/gh-pr-review.bats` は新規3ケース (範囲外フォールバック単体・範囲内範囲外混在・既存 General Comments 見出しへの追記) と回帰用の `gh pr diff` 失敗ケース1件を追加し、既存5ケースを含む全17ケースが PASS
- Issue #945 の Pre-merge AC 2件は `rubric` 判定で PASS 済みでチェック済み、Issue body 更新済み
- PR #950 (base: main) 作成済み。ドキュメント同期は不要と判断済み (`docs/structure.md` / `docs/migration-notes.md` および ja ミラーの記載は変更なしで正確)
