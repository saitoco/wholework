[English](../../guide/figma-best-practices.md) | 日本語

# Figma ベストプラクティスガイド

このガイドは、AI agent (Claude + Figma MCP) によるコード生成精度を最大化するために、
UI デザイナーが Figma デザインファイルを作成する際のベストプラクティスをまとめたものです。

## Figma ファイル構造が重要な理由

Figma MCP は `get_design_context` ツールを使って、デザインを React + Tailwind コード表現に変換します。
Figma ファイルの構造がそのままコード構造に反映されるため、整理されたファイルはクリーンなコードを、
乱雑なファイルは冗長なコードを生成します。

## 1. コンポーネント構造化

再利用される UI 要素は必ず Figma コンポーネントにする。

### 良い例

- ボタン、カード、入力フィールド、モーダルなど共通 UI をコンポーネント化する
- コンポーネントに variant を定義する (Primary / Secondary / Ghost など)
- コンポーネントに property を設定する (テキスト、アイコン、state)

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

- 同じボタンデザインを各画面にコピー&ペーストする
- variant を使わず別々のコンポーネントを作る (`ButtonRed`、`ButtonBlue`)
- インスタンスを detach してローカルに修正を加える

**影響**: コンポーネント化しないと、MCP は各要素を独立したものとして認識し、重複したコードを生成する。

## 2. 意味のあるレイヤー名

レイヤーには、その機能を示す意味のある名前を付ける。

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

**影響**: MCP はレイヤー名をそのままコンポーネント名や変数名として使用する。`Frame 1` は
生成されるコードの可読性を著しく低下させる。

## 3. 変数の利用

色、間隔、border radius、タイポグラフィには Figma 変数を使う。

### 良い例

- 色: `colors/primary/500`、`colors/neutral/100`
- 間隔: `spacing/sm` (8px)、`spacing/md` (16px)、`spacing/lg` (24px)
- Border radius: `radius/sm` (4px)、`radius/md` (8px)
- タイポグラフィ: `text/heading/lg`、`text/body/md`

### 悪い例

- 色を直接指定する: `#3B82F6` をハードコードする
- 間隔をピクセル値で個別に指定する: 16px、17px、15px が要素ごとにばらばらに散在する
- 同じ色をファイル内の複数箇所で異なる値として使う

**影響**: `get_variable_defs` はファイル内で使われている変数を抽出する。変数を使わないと、
ハードコードされた値がそのままコードに反映され、デザインシステムとの一貫性が失われる。

## 4. Auto Layout の活用

Auto Layout を使ってレスポンシブな意図を伝える。

### 良い例

- カードリスト: 水平 Auto Layout + Wrap
- フォーム: 垂直 Auto Layout + Fill container
- ヘッダー: 水平 Auto Layout + Space between
- リサイズ時に意図通りの挙動になることを確認する

### 悪い例

- 要素を絶対座標で手動配置する
- 固定サイズのフレーム内に要素をレイヤーする
- Auto Layout ではなく Group で要素をグループ化する

**影響**: Auto Layout の情報は flexbox / grid のコードに直接変換される。絶対座標での配置は
`position: absolute` だらけのコードを生成し、レスポンシブデザインを困難にする。

## 5. 注釈の追加

視覚的に伝えられない挙動や意図は注釈で補足する。

### 追加すべき情報

- インタラクション: hover アニメーション、クリック時の遷移先
- アニメーション: トランジションの種類と duration
- レスポンシブ: ブレークポイントごとの表示切り替えルール
- State: loading、error、empty state
- アクセシビリティ: スクリーンリーダー向けの読み上げ順序

Figma の Dev Resources 機能を使い、フレームにリンクとメモを添付する。

## 6. ファイル構成のガイドライン

### 推奨される構造

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

- すべての画面を 1 つのページに配置する
- コンポーネント定義と画面デザインを混在させる
- 未使用のフレームやレイヤーが大量に残っている

**影響**: MCP でノードを指定する際、整理されたファイルは対象フレームを素早く特定でき、
不要なコンテキストが混入するのを防げる。

## チェックリスト

`/spec` でデザインを使う前に、以下を確認する:

- [ ] 再利用される UI 要素がコンポーネント化されている
- [ ] レイヤーに意味のある名前が付いている (`Frame 1` のような名前がない)
- [ ] 色、間隔、タイポグラフィに変数が使われている
- [ ] Auto Layout が構造の中でレスポンシブな意図を伝えている
- [ ] 対象フレームをリサイズすると意図通りに動作する
- [ ] 不要なレイヤーや detach されたインスタンスが整理されている
