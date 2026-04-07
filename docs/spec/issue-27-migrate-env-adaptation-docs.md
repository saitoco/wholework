# Issue #27: adapters: Migrate environment adaptation architecture and adapter contract to docs/

## 概要

private リポジトリに散在する環境適応アーキテクチャドキュメント（4層アーキテクチャ設計書）と adapter 契約テンプレート（カスタム adapter 作成ガイド）を統合し、`docs/environment-adaptation.md` として1ファイルに英語化して移植する。

**移植元:**
- `~/src/claude-config/docs/environment-adaptation.md` — 4層アーキテクチャ設計ドキュメント（Japanese）
- `~/src/claude-config/.wholework/adapters/README.md` — adapter 契約テンプレート（Japanese）

**統合構成:** Layer 4（実行レイヤー）のサブセクションとして adapter 契約テンプレートを収録する。

## 変更対象ファイル

- `docs/environment-adaptation.md`: 新規作成
- `docs/structure.md`: directory layout 内の `docs/` ディレクトリ一覧に `environment-adaptation.md` の参照を追加

## 実装ステップ

1. Create `docs/environment-adaptation.md` with merged English content（→ 受け入れ条件1〜10のうち1〜2, 4〜10）
   - Frontmatter: `type: project`, `ssot_for: [environment-adaptation-architecture]`
   - Layer 1: Declaration (`.wholework.yml`)
   - Layer 2: Detection (detect-config-markers + ToolSearch + CLI detection) — references to `modules/detect-config-markers.md`
   - Layer 3: Disclosure Control (Core/Domain separation) — Domain Files table
   - Layer 4: Execution (verify-executor + adapter) — includes:
     - safe/full mode branching table
     - command-by-environment table
     - adapter pattern description (3-layer resolution) — references to `modules/adapter-resolver.md`
     - Layer 4 subsection: **Adapter Contract Template** (migrated from `adapters/README.md`): required sections (detection procedure, command conversion table, fallback), optional sections, file structure template — references to `modules/browser-adapter.md`
     - `--when` modifier (planned, not yet implemented — preserve the note from source)
   - Inter-layer relationship diagram (from source)
   - Extension guide (adding new capabilities / Domain logic)
   - All text must be in English; no Japanese headings or body text

2. Update `docs/structure.md` — add `environment-adaptation.md` entry to directory layout docs section（→ 受け入れ条件3）
   ```
   │   ├── environment-adaptation.md # Environment adaptation architecture (4-layer)
   ```

## 検証方法

### マージ前

- <!-- verify: file_exists "docs/environment-adaptation.md" --> `docs/environment-adaptation.md` が作成されている
- <!-- verify: file_not_contains "docs/environment-adaptation.md" "概要" --> ドキュメントが英語で記述されている（日本語の見出しが含まれない）
- <!-- verify: grep "environment-adaptation" "docs/structure.md" --> `docs/structure.md` に `environment-adaptation.md` への参照が追加されている
- <!-- verify: grep "Layer 1" "docs/environment-adaptation.md" --> 4層アーキテクチャ（Layer 1〜4）の構造が含まれている
- <!-- verify: grep "Layer 2" "docs/environment-adaptation.md" --> 検出メカニズム（detect-config-markers, ToolSearch, CLI 検出）が記載されている
- <!-- verify: grep "Layer 3" "docs/environment-adaptation.md" --> Core/Domain 分離パターンが記載されている
- <!-- verify: grep "Contract Template\|contract template" "docs/environment-adaptation.md" --> adapter 契約テンプレート（検出手順・コマンド変換テーブル・フォールバック）が Layer 4 のサブセクションとして含まれている
- <!-- verify: grep "browser-adapter" "docs/environment-adaptation.md" --> リファレンス実装（`modules/browser-adapter.md`）への参照が含まれている
- <!-- verify: grep "adapter-resolver" "docs/environment-adaptation.md" --> `modules/adapter-resolver.md`（3層解決順序）への参照が含まれている
- <!-- verify: grep "detect-config-markers" "docs/environment-adaptation.md" --> `modules/detect-config-markers.md` への参照が含まれている

### マージ後

- `docs/environment-adaptation.md` が GitHub 上で正常にレンダリングされることを確認する

## ツール依存関係

### 組み込みツール
- `Read`: ソースファイル読み取り
- `Write`: 新規ファイル作成
- `Edit`: `docs/structure.md` 編集

## 注意事項

- **翻訳方針**: 見出し・本文・テーブルのすべてを英語に翻訳する。`概要` は "Overview"、`検出` は "Detection"、`開示制御` は "Disclosure Control"、`実行` は "Execution" に対応する
- **adapter 契約テンプレートの配置**: `adapters/README.md` のコンテンツは Layer 4 内のサブセクション（例: `### Adapter Contract Template`）として組み込む。独立したセクションとして追加しない
- **`--when` 修飾子**: source に "未実装" と明記されている。英語で "(planned, not yet implemented)" と注記して保持する
- **ソースファイルの frontmatter**: source の `environment-adaptation.md` は `type: project` を持つ。新規ファイルも `type: project` を使用する
- **モジュール参照パス**: ドキュメント内でモジュールを参照する際は相対パス（`modules/xxx-adapter.md`）形式で記述する（インストール先ではなくリポジトリ相対パス）
- **Domain Files テーブルの注記**: Layer 3 の Domain Files テーブルは現時点の状態であり、`(exhaustive)` と注記する

## issue レトロスペクティブ

### 判断経緯
- ファイル配置先を `docs/adapter-contract.md` とした（adapter は modules/ に実装があるが、契約テンプレートはユーザー向けドキュメントのため docs/ が適切）
- 「移植」の範囲は CLAUDE.md の Migration Guidelines に従い、英語翻訳 + wholework 向けリファクタリングとした

### 重要な方針決定
- ユーザーが `docs/` にドキュメントとして配置する方針を選択

### 受け入れ条件の変更理由
- 特になし（初回作成のため変更なし）

## code レトロスペクティブ

### 設計からの逸脱
- 特になし

### 設計の不備・曖昧さ
- 特になし

### 手戻り
- 特になし

## spec レトロスペクティブ

### 軽微な観察
- issue レトロスペクティブで「`docs/adapter-contract.md`」という配置先が言及されているが、Issue 本文の受け入れ条件は `docs/environment-adaptation.md` を参照している。Issue タイトルも "to docs/" となっており、最終的には `docs/environment-adaptation.md` として統合する方針が Issue 本文で確定している

### 判断経緯
- `--when` 修飾子は source に "未実装（#825）" と明記されている。アーキテクチャ全体像を伝えるドキュメントとして、計画中の機能も注記付きで含めることを自動解決した
- adapter 契約テンプレートを Layer 4 のサブセクションとして統合する構成は Issue 本文に明示されており、設計の曖昧さなし

### 不確定要素の解決
- 特になし（ソースファイルが private repo に存在し、受け入れ条件も明確に定義されていた）
