[English](../../guide/troubleshooting.md) | 日本語

# 🔧 トラブルシューティング

よくある問題とその解決方法。

## GitHub CLI 認証

**症状**: スキルが `gh: command not found` や `HTTP 401` エラーで失敗する。

**修正**:

```bash
# gh がインストール済みか確認
gh --version

# 必要なら認証
gh auth login

# 認証を確認
gh auth status
```

Wholework は `gh` がインストール済みで対象リポジトリにアクセスできる認証状態を要求します。GitHub App やトークンを使う場合、`repo` スコープ（Issues、PRs、Contents）が必要です。

## Fine-Grained PAT に GitHub Projects V2 の権限が不足している

**症状**: fine-grained personal access token を使う GitHub Actions workflow（またはスクリプト）が、GraphQL API (`addProjectV2ItemById` → `updateProjectV2ItemFieldValue`) で Organization 所有の GitHub Projects V2 ボードを更新しようとすると、トークンに Projects へのアクセス権が設定されているように見えても `Resource not accessible by personal access token` エラーで失敗する。

**修正**: Organization 所有の Projects V2 ボードへの書き込みには、fine-grained PAT に以下の**両方**の権限が必要です:

- **Organization permissions**: `Projects: Read and write`
- **Repository permissions**: `Issues: Read`（PR を対象にする場合は `Pull requests: Read`）— 対象コンテンツのノード ID を解決するために必要

どちらか一方が欠けていても同じ `Resource not accessible by personal access token` エラーになるため、トークンスコープや classic PAT の制限の問題と誤診断しやすい。

**補足**: Organization の「Restrict access via personal access tokens (classic)」設定は fine-grained token とは無関係です — 別の設定画面にあり、この権限要件には影響しません。

## Plugin インストール失敗

**症状**: `/wholework:code` が認識されない、スキルが利用不可と表示される。

**修正**:

```
# Claude Code でインストールステップを再実行
/plugin marketplace add saitoco/wholework
/plugin install wholework@saitoco-wholework
```

それでも解決しない場合は development install を試します:

```bash
git clone https://github.com/saitoco/wholework.git
cd wholework
./install.sh
# その後 Claude Code を起動:
claude --plugin-dir /path/to/wholework
```

スキルはスクリプトやモジュールを `${CLAUDE_PLUGIN_ROOT}` (plugin ディレクトリ) 経由で参照します。`--plugin-dir` または marketplace install を使うと、Claude Code は Skill の内容を読み込むときにこれをその場で置換し、hook プロセスには環境変数として渡します。Bash ツールの環境には設定されないため、Bash 呼び出しで `$CLAUDE_PLUGIN_ROOT` が空なのは想定どおりで、インストールの不具合ではありません。`run-*.sh` wrapper が起動する headless セッション (`/auto` が起動するフェーズ) では Claude Code の置換が働かないため、wrapper 自身がパスを解決して `CLAUDE_PLUGIN_ROOT` を export します (`scripts/plugin-root.sh`、#1546)。

## Verify Command 失敗の読み方

**症状**: `/verify` がある受入条件について FAIL または UNCERTAIN を報告する。

**出力の意味**:

- `PASS` — verify command が成功、条件が満たされた
- `FAIL` — verify command は実行されたが、期待する内容や状態が見つからなかった
- `UNCERTAIN` — verify command が実行できなかった（構文エラー、ファイル欠如など）

**FAIL の診断手順**:

1. Issue で失敗している条件を見る — `<!-- verify: ... -->` コメントが何をチェックしたかを示す
2. よくあるタイプ:
   - `file_exists "path/to/file"` — ファイルがまだ存在しない
   - `file_contains "path" "text"` — ファイルは存在するが期待文字列が無い
   - `section_contains "path" "Section" "text"` — セクションは存在するが文字列が無い
   - `command "bash script.sh"` — コマンドが非ゼロの exit code を返した

3. 根本原因を修正し `/verify N` を再実行

**verify command 自体が誤っている場合**（ファイルパスが違う、期待文字列が違うなど）:

`/code N` を実行して fix サイクルに入ります。実装中、Wholework は誤った verify command を検出して補正してから再検証を実行します。

## スキルがハング・タイムアウトする

**症状**: スキルが出力なく長時間動作する。

**修正**: Ctrl+C で停止。以下を確認:

- issue に `size/*` ラベル、または GitHub Projects の Size は設定されているか? 未サイズ issue は対話モードでユーザー入力を求める
- 応答待ちの未処理確認がないか?

`/auto` による無人実行の場合、開始前に issue が triage 済み（`phase/*` か `triaged` ラベルあり）であることを確認してください。

## スキル更新がセッション中に反映されない

**症状**: `SKILL.md` ファイルを編集した後（または `git pull` で新しい skill バージョンを取得した後）、同一セッション内でそのスキルを呼び出すと旧バージョンのまま動作する。新しく追加されたフラグ・サブコマンド・ステップがスキルの挙動に反映されない。

**原因**: Claude Code はセッション開始時（または `claude -p` サブプロセス起動時）に `SKILL.md` の内容を LLM システムプロンプトへスナップショットする。セッション中にディスク上で行われた変更は、新しいセッションが開始されるまで反映されない。

**修正**: Claude Code セッションを再起動する（閉じて開き直す、または `claude -p` サブプロセスの場合は次回起動時に更新済みファイルが読み込まれる）。セッション内でのホットリロードコマンドは存在しない。

詳細と reload トリガーの一覧表は `docs/reports/skill-loader-cache-behavior.md`（Issue #673 の調査結果）を参照。

## Plugin ディレクトリが upstream より遅れている

**症状**: Skill の開始時に、wholework の plugin ディレクトリが upstream (例: `origin/main`) より N コミット遅れているという警告が出る。

**原因**: `claude --plugin-dir <checkout>` で読み込むと、実行される Skill・module・script はその checkout のものになり、何もそれを更新しない。誰も pull しない checkout は古い版のまま動くので、upstream にマージされた修正が手元では効かない。Skill の開始時 (`modules/phase-banner.md`) に、Wholework は checkout の `HEAD` と upstream ブランチを比べ、upstream が進んでいれば警告する。

**修正**: ほかの Claude Code セッションがその checkout を使っていないときに checkout を更新し (実行中のスクリプトがそのセッションの下で変わるため)、更新後の `SKILL.md` の内容を読み込ませるために新しいセッションを開始する (「スキル更新がセッション中に反映されない」を参照):

```bash
git -C /path/to/wholework pull --ff-only
```

Wholework が代わりに pull することはない。

**補足**:

- 比較には最後に `git fetch` した時点の upstream ブランチを使い、ネットワークには出ない。そのため、長く fetch していない checkout は最新に見えることがある。警告を正確に保つには、`git -C /path/to/wholework fetch` を時々 (例: 定期ジョブで) 実行する。
- marketplace からの install (git の checkout ではない)、detached HEAD、upstream の無いブランチ、チェックが実行できない場合は、警告は出ない。意図して固定した checkout で警告を止めるには、`git -C /path/to/wholework branch --unset-upstream` を実行する。

## フェーズ作業ディレクトリが残っている

**症状**: フェーズ (`/spec`・`/code`・`/verify`) の開始時に、`${XDG_CACHE_HOME:-~/.cache}/wholework/work/` 配下のディレクトリがサイズ付きで警告として一覧される。または、作業ディレクトリが使えないために検証が UNCERTAIN として記録される。

**原因**: フェーズは大きな検証用の作業ファイル (リポジトリのコピー・`node_modules`・ビルド成果物・ブラウザのプロファイル) を Issue・フェーズごとの作業ディレクトリに置き、終了時に削除する。強制停止 (watchdog・OOM killer・クラッシュ) ではこの削除が行われない。フェーズ開始時の sweep は、同じリポジトリ・Issue・フェーズの残骸は削除するが、他の Issue・フェーズ・リポジトリのディレクトリは並行して動いているセッションのものかもしれないため、警告するだけにとどめる。

**修正**: 一覧された Issue・フェーズを処理中のセッションがないことを確認してから、不要になったディレクトリを削除する。Wholework がこれらを自動で削除することはなく、判断はユーザーに委ねられる。基準ディレクトリを移すには、`XDG_CACHE_HOME` を絶対パスで設定する。

**補足**: 基準ディレクトリはディスク上にある必要がある。tmpfs や ramfs 上にある場合 (または作成できない場合)、フェーズはそれを使わず、`/tmp` にもフォールバックしない。コピーを必要とする検証は理由を添えて UNCERTAIN として記録される。`modules/phase-work-dir.md` を参照。

## さらに助けが必要なとき

- [github.com/saitoco/wholework](https://github.com/saitoco/wholework/issues) で issue を開く
- 類似問題が既存 issue にないかを確認
- [ユーザーガイド](index.md) — ガイドページ一覧
