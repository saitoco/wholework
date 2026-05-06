[English](../../guide/scripting.md) | 日本語

# スクリプトガイド

Wholework におけるシェルスクリプト記述の規約とパターン。

---

## jq パターン

### `.[0].field` には `// empty` ガードを必ず付ける

`gh ... --json X --jq '.[0].field'` で先頭要素を取り出す場合、**必ず `// empty` を付ける**:

```bash
# Bad: 結果が空配列のときにリテラル文字列 "null" が返る
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" ]]; then  # "null" は非空とみなされ、誤って分岐に入る
  ...
fi

# Good: 結果が空配列のときに空文字列が返る
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId // empty')
if [[ -n "$VALUE" ]]; then  # 空文字列なので正しくスキップされる
  ...
fi
```

**なぜ `// empty` か?** 入力配列が `[]` のとき、jq は `.[0]` を `null` と評価し、
`null.field` も `null` を生成します。jq は標準出力に文字列 `"null"` を出力します。
後続の `[[ -n "$var" ]]` は `"null"` を非空文字列として扱うため、結果が無くても条件が真になってしまいます。

`// empty` は jq の代替演算子で、左辺が `null` または `false` の場合は何も出力しません（改行すら出ません）。Bash は空文字列を捕捉し、`[[ -n "$var" ]]` は正しく false に評価されます。

**ルール**: `.[0].field`（または `.[N].field`）の jq 式の結果を非空チェックに使うすべての箇所で `// empty` を使うこと。

### 代替: `!= "null"` 文字列チェック

`// empty` を追加できない場合（jq 式が出力を必須とするコンテキストにある等）は、明示的な文字列比較でガードします:

```bash
VALUE=$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')
if [[ -n "$VALUE" && "$VALUE" != "null" ]]; then
  ...
fi
```

`!= "null"` チェックよりも `// empty` を優先してください — 発生源で `"null"` 文字列を取り除くことで下流のチェックを単純化できます。

### フィルタ済み配列には `first // empty`

`select()` でフィルタしてから先頭マッチを取り出す場合は `first // empty` を使います:

```bash
# Good: マッチするラベルが無い場合は空文字列を返す
LABEL=$(gh issue view "$NUMBER" --json labels \
  -q '[.labels[].name | select(startswith("type/"))] | first // empty')
```

---

## エラーハンドリング

### Optional な参照では stderr を抑制

存在しないことが想定され、それでスクリプトを失敗させたくない参照では `2>/dev/null || true`（または `2>/dev/null || echo ""`）を使います:

```bash
VALUE=$(gh issue view "$NUMBER" --json labels \
  -q '...' 2>/dev/null || true)
```

---

## 関連

- Issue #355 — `.[0].field` が空配列で `"null"` を返すことの最初の発見
- `scripts/get-issue-type.sh` — GraphQL とラベル参照の両方で `// empty` を使う例
- `scripts/run-verify.sh` — `.[0].databaseId // empty` を使う例
