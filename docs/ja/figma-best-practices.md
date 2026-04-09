# Figma ベストプラクティスガイド

本ガイドは、AI エージェント（Claude + Figma MCP）によるコード生成精度を最大化するための、UI デザイナーが Figma デザインファイルを作成する際のベストプラクティスをまとめたものです。

## Figma ファイル構造が重要な理由

Figma MCP は `get_design_context` ツールを使ってデザインを React + Tailwind のコード表現に変換します。Figma ファイルの構造がそのままコード構造に反映されるため、整理されたファイルはクリーンなコードを、乱雑なファイルは冗長なコードを生み出します。

## 1. コンポーネント化

再利用される UI 要素は必ず Figma のコンポーネントにします。

### 良い例

- ボタン、カード、入力欄、モーダルなどの共通 UI をコンポーネント化する
- コンポーネントにバリアントを定義する（Primary / Secondary / Ghost など）
- コンポーネントにプロパティを設定する（text、icon、state）

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

- 同じボタンデザインを画面ごとにコピー&ペーストする
- バリアントを使わず別コンポーネントを作る（`ButtonRed`、`ButtonBlue`）
- インスタンスを detach してローカル修正する

**影響**: コンポーネント化されていないと、MCP は各要素を独立したものとして認識し、重複コードが生成されます。

## 2. レイヤー名にセマンティクスを

レイヤーには機能を示す意味のある名前を付けます。

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

**影響**: MCP はレイヤー名をそのままコンポーネント名や変数名として使用します。`Frame 1` のような名前は生成コードの可読性を大きく損ないます。

## 3. Variables の活用

色、スペーシング、角丸、タイポグラフィには Figma Variables を使用します。

### 良い例

- Colors: `colors/primary/500`、`colors/neutral/100`
- Spacing: `spacing/sm`（8px）、`spacing/md`（16px）、`spacing/lg`（24px）
- Border radius: `radius/sm`（4px）、`radius/md`（8px）
- Typography: `text/heading/lg`、`text/body/md`

### 悪い例

- 色を直接指定する: `#3B82F6` をハードコード
- スペーシングをピクセル値で個別指定する: 16px、17px、15px が要素ごとに散在
- ファイル内の複数箇所で同じ色を異なる値で使用する

**影響**: `get_variable_defs` はファイルで使用される変数を抽出します。Variables がないとハードコード値がそのままコードに反映され、デザインシステムとの一貫性が失われます。

## 4. Auto Layout の活用

レスポンシブの意図を伝えるために Auto Layout を使用します。

### 良い例

- カードリスト: horizontal Auto Layout + Wrap
- フォーム: vertical Auto Layout + Fill container
- ヘッダー: horizontal Auto Layout + Space between
- リサイズが意図通りに振る舞うことを確認する

### 悪い例

- 要素を絶対座標で手動配置する
- 固定サイズのフレーム内に要素を重ねる
- Auto Layout の代わりに Group で要素をまとめる

**影響**: Auto Layout の情報はそのまま flexbox / grid コードに変換されます。絶対座標での配置は `position: absolute` だらけのコードを生成し、レスポンシブ対応を困難にします。

## 5. アノテーションの追加

視覚的に伝えられない振る舞いや意図は、アノテーションで補足します。

### 追加する情報

- インタラクション: ホバーアニメーション、クリック時の遷移先
- アニメーション: トランジションの種類と持続時間
- レスポンシブ: ブレークポイントごとの表示切替ルール
- 状態: ローディング、エラー、空状態
- アクセシビリティ: スクリーンリーダー向けの読み上げ順序

Figma の Dev Resources 機能でフレームにリンクやメモを付けます。

## 6. ファイル整理のガイドライン

### 推奨構成

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

### 避けるべき構成

- すべての画面を 1 ページに配置する
- コンポーネント定義と画面デザインを混在させる
- 大量の未使用フレームやレイヤーが残っている

**影響**: MCP でノードを指定する際、整理されたファイルは対象フレームを素早く特定でき、不要なコンテキストの混入を防げます。

## チェックリスト

デザインを `/spec` で使用する前に、以下を確認します:

- [ ] 再利用される UI 要素がコンポーネント化されている
- [ ] レイヤー名がセマンティックである（`Frame 1` がない）
- [ ] 色・スペーシング・タイポグラフィに Variables が使われている
- [ ] Auto Layout がレスポンシブの意図を構造で表現している
- [ ] 対象フレームのリサイズが意図通りに振る舞う
- [ ] 不要なレイヤーや detach 済みインスタンスが整理されている
