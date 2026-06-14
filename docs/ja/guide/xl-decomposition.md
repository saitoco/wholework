[English](../../guide/xl-decomposition.md) | 日本語

# XL Decomposition ガイド

このガイドでは、`/issue --from-decomposition-file <path>` を使い、ユーザーが定義した YAML ファイルから XL 親 Issue の sub-issue を一括起票する方法を説明します。

## 使用場面

XL 親 Issue に対して 10 件以上の sub-issue を作成する場合、`gh issue create` を 1 件ずつ実行すると 4〜8 時間の手作業が必要です。decomposition ファイルモードを使えば、すべての sub-issue を 1 つの YAML ファイルに定義し、親子関係と blocked-by 依存関係を含めて 1 コマンドで作成できます。

## コマンド構文

```
/issue --from-decomposition-file <path-to-yaml>
```

例:

```
/issue --from-decomposition-file examples/decomposition/nuxt-to-next.yml
```

## YAML スキーマ

```yaml
parent: 1000           # 必須: 整数 — XL 親 Issue 番号
sub_issues:            # 必須: 1 件以上のリスト
  - id: foundation                    # 必須: YAML 内でユニークな文字列（blocked_by で参照）
    title: "next-init: Next.js プロジェクト初期化 + routing 設定 + middleware 移植"  # 必須
    background: |                     # 任意: 省略すると TBD skeleton が使われる
      Nuxt → Next 移行の foundation phase。
    purpose: |                        # 任意: 省略するとタイトル要約が使われる
      Next.js プロジェクトをセットアップし、基盤を整備する。
    acceptance_criteria:              # 任意: 省略すると "- [ ] TBD" が使われる
      - condition: Next.js プロジェクトが初期化されている
        verify: file_exists "next.config.js"
      - condition: middleware が移植されている
        verify: grep "middleware" "next.config.js"
    blocked_by: []                    # 任意: sub_issues 内の id 文字列のリスト

  - id: theme
    title: "next-theme: 共通レイアウト・スタイル移植"
    blocked_by: [foundation]          # この sub-issue は "foundation" にブロックされる

  - id: page-home
    title: "next-page: トップページを Next.js へ移植"
    blocked_by: [theme]
```

### フィールド一覧

| フィールド | 型 | 必須 | 説明 |
|-----------|-----|------|------|
| `parent` | 整数 | 必須 | XL 親 Issue 番号 |
| `sub_issues` | リスト | 必須 | sub-issue エントリのリスト（1 件以上） |
| `sub_issues[].id` | 文字列 | 必須 | YAML ファイル内でユニークな識別子。`blocked_by` 参照キーとして使用 |
| `sub_issues[].title` | 文字列 | 必須 | Issue タイトル。component prefix + 動詞始まり形式を推奨 |
| `sub_issues[].background` | 文字列 | 任意 | Issue 背景テキスト。省略時は TBD skeleton を使用 |
| `sub_issues[].purpose` | 文字列 | 任意 | Issue 目的テキスト。省略時はタイトル要約を使用 |
| `sub_issues[].acceptance_criteria` | リスト | 任意 | `{condition, verify}` エントリのリスト。省略時は `- [ ] TBD` |
| `sub_issues[].blocked_by` | id 文字列のリスト | 任意 | 依存関係。参照する `id` はすべて `sub_issues` 内に存在している必要がある |

### スキーマ検証ルール

- `parent` は正の整数であること
- `sub_issues` は 1 件以上のエントリを含むこと
- 各 `id` は YAML ファイル内でユニークであること
- `blocked_by` の各要素は `sub_issues` 内に存在する `id` を参照していること
- 循環依存は DFS で検出され、エラーになる — Issue は一切作成されない

## Skeleton フォーマット

`background` または `purpose` を省略した場合、以下の skeleton が生成されます:

```markdown
## 背景

(TBD — XL parent #{parent} の sub-issue として {id} を起票)

## 目的

{タイトル要約}

## Acceptance Criteria

### Pre-merge (auto-verified)

- [ ] TBD

### Post-merge

なし
```

各 sub-issue は後から `/issue <N>` で詳細化できます。

## 動作フロー

1. YAML ファイルを読み込みスキーマを検証する（不正な場合は中断）
2. DFS で循環依存を検出する（循環がある場合は中断）
3. 各 sub-issue を `gh issue create` でスケルトン本文付きで起票する
4. `add-sub-issue` GraphQL mutation で親子関係を設定する
5. `add-blocked-by` GraphQL mutation で `blocked_by` 関係を設定する（全 Issue 作成後にセカンドパスで処理）
6. サマリーを出力する: Issue 番号・タイトル・依存関係グラフ

## スコープ除外事項

以下は本機能のスコープ外であり、別途対応されます:

- **LLM による自動 decomposition**: コードベースを解析して YAML ファイルを自動生成する機能は follow-up 予定
- **YAML 更新時の再同期**: YAML 更新後に sub-issue を再同期する機能は未対応。本モードは初回一括起票のみ
- **依存関係グラフの可視化**: ビジュアルグラフ描画は `/audit progress`（#588 参照）で対応
- **YAML lint の詳細**: バリデーションエラーはメッセージ出力のみ（自動修正なし）

## サンプル: Nuxt → Next.js 移行

`examples/decomposition/nuxt-to-next.yml` に `foundation → theme → page-home` の依存チェーンを含む 3 件の sub-issue サンプルがあります。

## ワークフロー統合

一括起票後、各 sub-issue は `phase/issue` の状態から始まります。`/spec <N>` で実装 Spec を作成し、`/auto <N>` でフル開発ワークフローを実行してください。

XL 親 Issue の進捗は `/audit progress <N>` で確認できます（sub-issue の完了状態とブロック依存関係を表示）。
