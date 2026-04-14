[English](../figma-best-practices.md) | 日本語

# Figma ベストプラクティスガイド

本ガイドは、AI エージェント（Claude + Figma MCP）によるコード生成精度を最大化するため、UI デザイナーが Figma デザインファイルを作成する際のベストプラクティスをまとめたものです。

## なぜ Figma ファイル構造が重要なのか

Figma MCP は `get_design_context` ツールを使ってデザインを React + Tailwind のコード表現に変換します。Figma ファイルの構造がそのままコード構造に反映されるため、整理されたファイルはクリーンなコードを生成し、散らかったファイルは冗長なコードを生成します。

## 1. コンポーネント構造化

再利用される UI 要素は必ず Figma コンポーネント化します。

### 良い例

- ボタン、カード、入力フィールド、モーダルなど共通 UI をコンポーネント化
- コンポーネントにバリアントを定義（Primary / Secondary / Ghost など）
- コンポーネントにプロパティを設定（テキスト、アイコン、状態）

```
Components/
  Button/
    Primary (variant)
    Secondary (variant)
    Ghost (variant)
  Card/
    Default (variant)
    Highlighted (variant)
  Input/
    Text (variant)
    Password (variant)
```

### 悪い例

- 同じボタンデザインを各画面にコピペ
- variant の代わりに別コンポーネントを作成する（`ButtonRed`、`ButtonBlue`）
- インスタンスを detach してローカル修正を適用

**影響**: コンポーネント化されていないと MCP は各要素を独立に認識し、重複コードを生成します。

## 2. 意味のあるレイヤー名

機能を示す意味のある名前をレイヤーに付けます。

### 良い例

```
LoginForm
  EmailInput
  PasswordInput
  SubmitButton
  ForgotPasswordLink
```

### 悪い例

```
Frame 1
  Rectangle 5
  Text 12
  Group 3
    Vector 7
```

**影響**: MCP はレイヤー名をそのままコンポーネント名や変数名として使います。`Frame 1` のような名前は生成コードの可読性を大きく損ないます。

## 3. 変数の使用

色、spacing、border radius、タイポグラフィには Figma variable を使います。

### 良い例

- 色: `colors/primary/500`、`colors/neutral/100`
- Spacing: `spacing/sm`（8px）、`spacing/md`（16px）、`spacing/lg`（24px）
- Border radius: `radius/sm`（4px）、`radius/md`（8px）
- タイポグラフィ: `text/heading/lg`、`text/body/md`

### 悪い例

- 色を直接指定: `#3B82F6` をハードコード
- Spacing を個別の px 値で指定: 16px、17px、15px がバラバラに点在
- 同じ色に複数の値をファイル内の複数箇所で使う

**影響**: `get_variable_defs` はファイル内で使われている variable を抽出します。variable が無いとハードコード値がそのままコードに反映され、デザインシステムとの一貫性が失われます。

## 4. Auto Layout の活用

Auto Layout を使ってレスポンシブの意図を伝えます。

### 良い例

- カードリスト: 水平 Auto Layout + Wrap
- フォーム: 垂直 Auto Layout + Fill container
- ヘッダー: 水平 Auto Layout + Space between
- リサイズ時の挙動が意図通りかを確認する

### 悪い例

- 要素を絶対座標で手動配置する
- 固定サイズフレーム内に要素を重ねる
- Auto Layout の代わりに Group で要素をまとめる

**影響**: Auto Layout 情報はそのまま flexbox / grid コードに変換されます。絶対座標配置は `position: absolute` だらけのコードを生成し、レスポンシブデザインを困難にします。

## 5. アノテーションの追加

視覚的に伝えきれない挙動や意図はアノテーションで補います。

### 追加する情報

- インタラクション: hover アニメーション、クリック時の遷移先
- アニメーション: 遷移タイプと duration
- レスポンシブ: ブレークポイントごとの表示切替ルール
- 状態: loading、error、empty 状態
- アクセシビリティ: スクリーンリーダーの読み上げ順序

Figma の Dev Resources 機能を使ってフレームにリンクとメモを添付します。

## 6. ファイル整理ガイドライン

### 推奨構造

```
Page: Design System
  Frame: Colors
  Frame: Typography
  Frame: Icons
  Frame: Components

Page: Login Flow
  Frame: Login Screen
  Frame: Registration Screen
  Frame: Password Reset

Page: Dashboard
  Frame: Overview
  Frame: Settings
  Frame: Profile
```

### 避けるべき構造

- すべての画面を 1 ページに配置する
- コンポーネント定義と画面デザインを混在させる
- 使われていないフレームやレイヤーが大量に残っている

**影響**: MCP でノードを指定するとき、整理されたファイルなら対象フレームがすぐ特定でき、不要なコンテキスト混入を防げます。

## チェックリスト

`/spec` で使う前に以下を確認してください:

- [ ] 再利用される UI 要素がコンポーネント化されている
- [ ] レイヤーが意味のある名前を持つ（`Frame 1` が無い）
- [ ] 色、spacing、タイポグラフィに variable が使われている
- [ ] Auto Layout が構造上でレスポンシブ意図を伝えている
- [ ] 対象フレームのリサイズが意図通りに動く
- [ ] 不要なレイヤーや detach 済みインスタンスがクリーンアップされている
