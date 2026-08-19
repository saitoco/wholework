[English](../../guide/scripting.md) | 日本語

# スクリプティングガイド

Wholework でシェルスクリプトを書く際の規約とパターン。

---

## jq パターン

### `.[0].field` に対する `// empty` ガード

`gh ... --json X --jq '.[0].field'` を使って最初の要素を取り出す際は、**必ず `// empty` を付ける**:

```bash
# Bad: 結果が空配列のとき、文字列リテラル "null" が返る
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" ]]; then  # "null" は非空 — 誤って処理が進んでしまう
  ...
fi

# Good: 結果が空配列のとき、空文字列が返る
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId // empty')
if [[ -n "$VALUE" ]]; then  # 空文字列 — 正しくスキップされる
  ...
fi
```

**なぜ `// empty` なのか?** 入力配列が `[]` のとき、jq は `.[0]` を `null` と評価し、
`null.field` も `null` になる。jq はその後、標準出力に文字列 `"null"` を出力する。
続く `[[ -n "$var" ]]` のチェックは `"null"` を非空文字列として扱うため、
結果が返っていないにもかかわらず条件が true と評価されてしまう。

`// empty` は jq の代替演算子で、左辺が `null` または `false` の場合、jq は
出力を一切生成しない (改行すら出さない)。Bash はその結果として空文字列を捕捉し、
`[[ -n "$var" ]]` は正しく false と評価される。

**ルール**: 非空チェックに結果を使うすべての `.[0].field` (または `.[N].field`) の
jq 式に `// empty` を付けること。

### 代替案: `!= "null"` 文字列チェック

`// empty` を追加できない場合 (jq 式が出力を必要とするコンテキストにある場合など) は、
代わりに明示的な文字列比較でガードする:

```bash
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" && "$VALUE" != "null" ]]; then
  ...
fi
```

`!= "null"` チェックより `// empty` を優先すること — 発生源で `"null"` 文字列を
排除でき、下流のチェックをシンプルに保てる。

### フィルタ済み配列に対する `first // empty`

`select()` でフィルタして最初のマッチを取る場合は、`first // empty` を使う:

```bash
# Good: マッチするラベルが存在しない場合、空文字列が返る
LABEL=$(gh issue view "$NUMBER" --json labels \
  -q '[.labels[].name | select(startswith("type/"))] | first // empty')
```

---

## エラーハンドリング

### オプショナルな lookup では stderr を抑制する

不在が想定され、スクリプトの失敗を引き起こすべきでない lookup では、
`2>/dev/null || true` (または `2>/dev/null || echo ""`) を使う:

```bash
VALUE=$(gh issue view "$NUMBER" --json labels \
  -q '...' 2>/dev/null || true)
```

---

## 関連

- Issue #355 — `.[0].field` が空配列に対して `"null"` を返す問題の最初の発見
- `scripts/get-issue-type.sh` — GraphQL とラベル lookup の両方で `// empty` を使う例
- `scripts/run-merge.sh` — `.[0].databaseId // empty` を使う例
