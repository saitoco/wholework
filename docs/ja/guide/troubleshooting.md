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

スキル実行時に `${CLAUDE_PLUGIN_ROOT}` が設定されていることを確認してください — これは `--plugin-dir` または marketplace install 使用時に Claude Code が自動設定します。

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

## さらに助けが必要なとき

- [github.com/saitoco/wholework](https://github.com/saitoco/wholework/issues) で issue を開く
- 類似問題が既存 issue にないかを確認
- [ユーザーガイド](index.md) — ガイドページ一覧
