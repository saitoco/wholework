---
type: project
ssot_for:
  - visual-reproduction-methodology
---

[English](../visual-reproduction.md) | 日本語

# UI 再現案件 Methodology

本ドキュメントは、UI 再現案件（UI を reference と一致させる作業。例: フレームワーク移行、Figma デザイン → 実装、CMS テーマ移行）における原則とワークフローを体系化したものです。

## 1. Failure Modes

実プロジェクトで繰り返し発生する 3 つの failure mode:

### A. PASS criteria が狭い（検証範囲選択バイアス）

検証者が一部の要素（computed styles、特定コンポーネント）を確認して「その部分が PASS」と宣言し、「全体 PASS」と誤認するパターン。

**根本原因**: 検証者が「何を確認するか」を選択するため、選択バイアスが生じる。確認しなかった要素は一切検証されない。

### B. 仕様書 vs reference の取り違え（reference 優先原則違反）

実装者がデザインドキュメント（デザインベースライン、Figma エクスポート、CMS spec）に従ったが、それがライブ reference と乖離していたパターン。検証者が仕様書を正とみなすが、実際の authority は異なる。

**根本原因**: reference > spec doc の原則が守られていない。両者が conflict した場合、ライブ reference が正解。

### C. 状態の網羅不足（state 直積不徹底）

default state（初期表示）のみ検証し、インタラクティブ state（hover、menu-open、focused、error）やナビゲーションコンテキスト（内部ページ、ログイン済み）のバグを見逃すパターン。

**根本原因**: state の列挙が体系的でなく、最も目立つ state で止まってしまう。

## 2. 原則

### 原則 1 — AI vision review が主証跡

`visual_diff`（3 パネル composite: Before / After / Diff highlight）と `frontend-visual-review` sub-agent の組み合わせが、UI 再現検証の**主証跡**。Computed style 検査（`getComputedStyle`、`file_contains`）は特定の critical プロパティの補助にとどめる。

**理由**: 選択バイアス（Failure Mode A）を排除できるのは、機械的なピクセル比較と diff 画像の AI 解釈だけ。

### 原則 2 — reference > spec doc（conflict 時の優先ルール）

ライブ reference URL とスペック文書（デザインベースライン、Figma spec）が conflict した場合、**ライブ reference URL が authoritative**。

各フェーズでこのルールを適用する:

- **Spec フェーズ**: AC はスペック文書ではなく reference URL から導出する。
- **Code フェーズ**: 実装判断が不明な場合は reference URL を直接確認する。
- **Verify フェーズ**: `visual_diff` は reference URL と比較する。ピクセルレベルの evidence をスペック文書で上書きしない。

### 原則 3 — state × context: 完全直積で網羅

すべての（state × viewport）の組み合わせを列挙し、各組み合わせを個別に検証する。「全体 PASS」の宣言は、`frontend-visual-review` sub-agent がスコープ内の全組み合わせで明示的に `zero_gaps_detected: true` を出力した場合にのみ有効。

列挙すべき state ディメンション（非網羅的）:

| ディメンション | 例 |
|--------------|---|
| インタラクション state | default、hover、active、focus、disabled |
| ナビゲーションコンテキスト | トップページ、内部ページ、モーダルopen |
| ユーザー state | 未ログイン、ログイン済み、管理者 |
| Viewport | モバイル（390 px）、タブレット（768 px）、デスクトップ（1440 px）|

## 3. Tooling 要件

| ツール | 役割 |
|-------|------|
| Playwright | 各 viewport・state での reference と implementation のスクリーンショット撮影 |
| sharp | 3 パネル composite 画像（Before / After / Diff highlight）の生成 |
| pixelmatch | reference と implementation のピクセル単位の差分を機械的に特定 |
| `visual_diff` verify command | スクリーンショット撮影 → composite 生成 → `frontend-visual-review` 起動を統合実行 |
| `frontend-visual-review` sub-agent | 3 パネル composite を解釈し `zero_gaps_detected: true/false` とギャップ一覧を出力 |

`visual_diff` は `.wholework.yml` の `capabilities.visual-diff: true` 宣言が必要。この宣言がない場合、`/verify` での `visual_diff` は UNCERTAIN となる。

## 4. Workflow

### Issue フェーズ

- ライブ reference と現在の実装を並べて観察する。
- 差分（レイアウト、色、余白、タイポグラフィ）を初期 AC リストとして列挙する。
- カバーすべき viewport と state を特定する。

### Spec フェーズ

- `skills/spec/visual-state-enumeration.md` の state enumeration scaffold を使い、（state × viewport）の全組み合わせを体系的に導出する。
- AC は主に `visual_diff` verify command として記述する:

  ```html
  <!-- verify: visual_diff "https://ref.example.com/page" "{{base_url}}/page"
       --viewports="390,1440" --states="default,menu-open" -->
  ```

- `getComputedStyle` 系の `command` チェックは critical な個別プロパティの補助としてのみ追加する。

### Code フェーズ

- スペック文書ではなく reference URL を基準に修正実装する。
- 大きな変更のたびに両 URL のスクリーンショットを撮り、リグレッションを早期に検知する。

### Verify フェーズ

- スコープ内のすべての（state × viewport）組み合わせで `visual_diff` を実行する。
- `frontend-visual-review` が `zero_gaps_detected: true` を出力した場合にのみ、その組み合わせを PASS とする。
- タスク全体の PASS 宣言は、**全**組み合わせで `zero_gaps_detected: true` が揃った場合にのみ有効。

## 5. Anti-patterns

### Anti-pattern 1 — `zero_gaps_detected: true` なしに「全 PASS」を宣言する

**問題例**: 一部要素の computed style を確認した後「6 件全 PASS」と宣言。

**なぜ問題か**: どの AI エージェントも `zero_gaps_detected: true` を明示していない。チェックは選択した要素のみを対象にしており、それ以外のレイアウトは未検証（Failure Mode A）。

**正しい方法**: 各 `visual_diff` 実行において、`frontend-visual-review` からの明示的な `zero_gaps_detected: true` 出力が必須。全（state × viewport）組み合わせでこの出力が揃って初めて PASS 宣言が有効になる。

### Anti-pattern 2 — スペック文書を reference より優先する

**問題例**: 「デザインベースラインに font-size: 16px とあるので 16px のままにした。reference は 14px だが仕様書に従った。」

**なぜ問題か**: reference が優先（原則 2）。ライブ reference が 14px でレンダリングしている場合、スペック文書が何と言っていても実装は 14px に合わせなければならない。

**正しい方法**: reference URL に直接比較する。reference とスペック文書が conflict する場合は Spec 本文に不一致を記録し、reference に従う。

### Anti-pattern 3 — default state のみで verify を構築する

**問題例**: `visual_diff` を `--states="default"` のみで実行し、インタラクティブ state（menu-open、focused、error）をテストしない。

**なぜ問題か**: non-default state のバグが本番まで検出されない（Failure Mode C）。

**正しい方法**: Spec フェーズで `visual-state-enumeration.md` を使いすべての（state × viewport）組み合わせを列挙し、全組み合わせで `visual_diff` を実行する。

## 6. Exemplar References

以下は汎用的なフレームワーク移行タスクにおける、well-formed な `visual_diff` AC の例示です。URL・名称はすべて架空のものです。

**シナリオ**: `example-shop.com` を WordPress から Next.js に移行。reference はライブ WordPress サイト。

**Spec 抜粋**（簡略）:

```markdown
## Acceptance Criteria

### Pre-merge

- [ ] <!-- verify: visual_diff "https://example-shop.com/" "{{base_url}}/"
         --viewports="390,768,1440" --states="default" -->
     全 viewport でホームページの visual parity を確認
- [ ] <!-- verify: visual_diff "https://example-shop.com/products/widget"
         "{{base_url}}/products/widget"
         --viewports="390,1440" --states="default,image-zoomed" -->
     製品詳細ページ（ズーム state を含む）
- [ ] <!-- verify: visual_diff "https://example-shop.com/" "{{base_url}}/"
         --viewports="390" --states="nav-open" -->
     モバイルナビゲーション drawer の visual parity

State mapping:
- `default`: 初期表示、ユーザー操作なし
- `image-zoomed`: 商品画像クリック済み、ズームオーバーレイ表示中
- `nav-open`: モバイルハンバーガーアイコンタップ済み、ナビゲーション drawer 表示中
```

**Verify 出力例**（PASS の場合):

```
visual_diff: ホームページ (default, 390px) — zero_gaps_detected: true
visual_diff: ホームページ (default, 768px) — zero_gaps_detected: true
visual_diff: ホームページ (default, 1440px) — zero_gaps_detected: true
visual_diff: 製品詳細 (default, 390px) — zero_gaps_detected: true
visual_diff: 製品詳細 (image-zoomed, 390px) — zero_gaps_detected: true
visual_diff: 製品詳細 (default, 1440px) — zero_gaps_detected: true
visual_diff: 製品詳細 (image-zoomed, 1440px) — zero_gaps_detected: true
visual_diff: Nav drawer (nav-open, 390px) — zero_gaps_detected: true
```

8 組み合わせすべてで `zero_gaps_detected: true` → 全体 PASS 宣言が有効。
