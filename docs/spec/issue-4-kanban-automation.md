# Issue #4: kanban: Add GitHub Actions workflow for phase label automation

## 概要

`phase/*` ラベルの変更をトリガーに GitHub Projects の Status カラムを自動同期する GitHub Actions ワークフローを作成する。参照実装として `~/src/claude-config/.github/workflows/kanban-automation.yml` を使用し、wholework プロジェクト向けにカスタマイズする。

## 変更対象ファイル

- `.github/workflows/kanban-automation.yml`: 新規作成 — phase ラベル→Projects Status カラム同期ワークフロー

## 実装ステップ

1. Step 1: `.github/workflows/` ディレクトリを作成し、`kanban-automation.yml` を新規作成する（→ 受け入れ条件 全項目）
   - claude-config の参照実装をベースに以下をカスタマイズ:
     - `on: issues: types: [labeled]` トリガー
     - `phase/issue` と `phase/spec` を個別カラムにマッピング（参照元では同一カラム）
     - `phase/verify` マッピングを追加（参照元には存在しない）
     - PROJECT_ID: `PVT_kwDOAT8ukc4BT2qC`
     - FIELD_ID (Status): `PVTSSF_lADOAT8ukc4BT2qCzhBCrns`
     - secret: `secrets.PROJECT_PAT`
   - label→option_id マッピング:
     - `phase/issue` → `cefd394b` (Issue)
     - `phase/spec` → `511e5084` (Spec)
     - `phase/ready` → `61e4505c` (Ready)
     - `phase/code` → `47fc9ee4` (Code)
     - `phase/verify` → `df73e18b` (Verify)
     - `phase/done` → `98236657` (Done)

## 検証方法

### マージ前
- <!-- verify: file_exists ".github/workflows/kanban-automation.yml" --> `.github/workflows/kanban-automation.yml` が作成されている
- <!-- verify: grep "issues:" ".github/workflows/kanban-automation.yml" --> ワークフローのトリガーが `issues` の `labeled` イベントである
- <!-- verify: grep "phase/issue" ".github/workflows/kanban-automation.yml" --> `phase/issue` → Issue カラム（option_id: `cefd394b`）のマッピングが定義されている
- <!-- verify: grep "phase/spec" ".github/workflows/kanban-automation.yml" --> `phase/spec` → Spec カラム（option_id: `511e5084`）のマッピングが定義されている
- <!-- verify: grep "phase/ready" ".github/workflows/kanban-automation.yml" --> `phase/ready` → Ready カラム（option_id: `61e4505c`）のマッピングが定義されている
- <!-- verify: grep "phase/code" ".github/workflows/kanban-automation.yml" --> `phase/code` → Code カラム（option_id: `47fc9ee4`）のマッピングが定義されている
- <!-- verify: grep "phase/verify" ".github/workflows/kanban-automation.yml" --> `phase/verify` → Verify カラム（option_id: `df73e18b`）のマッピングが定義されている
- <!-- verify: grep "phase/done" ".github/workflows/kanban-automation.yml" --> `phase/done` → Done カラム（option_id: `98236657`）のマッピングが定義されている
- <!-- verify: grep "PROJECT_PAT" ".github/workflows/kanban-automation.yml" --> `secrets.PROJECT_PAT` を使用して Projects API にアクセスしている
- <!-- verify: grep "PVT_kwDOAT8ukc4BT2qC" ".github/workflows/kanban-automation.yml" --> wholework プロジェクトの PROJECT_ID が設定されている
- <!-- verify: grep "PVTSSF_lADOAT8ukc4BT2qCzhBCrns" ".github/workflows/kanban-automation.yml" --> Status フィールドの FIELD_ID が設定されている

### マージ後
- Repository secrets に `PROJECT_PAT`（`project:write` スコープ付き PAT）が設定されている
- Issue に `phase/code` ラベルを付与し、Projects の Status カラムが Code に自動更新されることを確認

## spec レトロスペクティブ

（spec フェーズでの振り返りはなし）

## code レトロスペクティブ

### 設計からの逸脱
- 特になし

### 設計の不備・曖昧さ
- 受け入れチェック `grep "on:.*issues"` が標準的な YAML 複数行フォーマット（`on:` と `issues:` が別行）にマッチしない。`grep "issues:"` に修正した

### 手戻り
- 特になし

## 注意事項

- 参照実装との主な差分: (1) `phase/issue` と `phase/spec` の個別カラムマッピング、(2) `phase/verify` マッピング追加、(3) wholework 固有の ID 群
- `GITHUB_TOKEN` には Projects スコープがないため、`PROJECT_PAT` (Fine-grained PAT with `project:write`) を Repository secret として設定する必要がある
- GraphQL mutation の構造は参照実装と同一（`addProjectV2ItemById` + `updateProjectV2ItemFieldValue`）

## verify レトロスペクティブ

### 各フェーズの振り返り

#### spec
- 受け入れ条件はすべて `file_exists` / `grep` による自動検証可能な形式で記述されており品質良好
- マージ後の manual 条件も `<!-- verify-type: manual -->` で明示されており、自動/手動の分類が明確

#### design
- 特になし（spec レトロスペクティブにも記録なし）

#### code
- `grep "on:.*issues"` という受け入れチェックパターンが YAML 複数行フォーマットにマッチしないことが実装中に判明し、`grep "issues:"` に修正された（Specの受け入れチェック記述の問題。Issue 本文とSpecの両方が修正された）
- patch ルートで直接 main にコミット（PR なし）。commit `1518b6b` と `a871b02` の2コミットで完了

#### review
- patch ルートのため正式なレビューは実施されていない。コードはシンプルな YAML ファイルのため問題なし

#### merge
- patch ルート（直接 main コミット）。コンフリクトなし

#### verify
- 自動検証対象11件すべてPASS
- マージ後2件は `verify-type: manual` のため自動検証対象外（ユーザー手動検証が必要）

### 改善提案
- 特になし
