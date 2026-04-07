# Issue #23: skills: Migrate utility skills (triage, audit, doc)

## 概要

`claude-config` リポジトリの triage・audit・doc スキル（6ファイル）を wholework に移植する。
全ファイル新規作成。CLAUDE.md の移植ガイドラインに従い、英語化・機会主義的簡素化を適用する。

## 変更対象ファイル

| ファイル | 変更種別 |
|---------|---------|
| `skills/triage/SKILL.md` | 新規作成（818行 → 英語化、小数ステップ修正、プライベートパス除去） |
| `skills/audit/SKILL.md` | 新規作成（376行 → 英語化） |
| `skills/doc/SKILL.md` | 新規作成（716行 → 英語化、`claude-config` 参照の汎用化） |
| `skills/doc/product-template.md` | 新規作成（日本語プレースホルダーを英語化） |
| `skills/doc/tech-template.md` | 新規作成（日本語プレースホルダーを英語化） |
| `skills/doc/structure-template.md` | 新規作成（内容確認済み・最小変更） |
| `docs/migration-notes.md` | 変更（追記: Issue #23 セクション） |

## 実装ステップ

1. `skills/triage/SKILL.md` を新規作成する（→ 受け入れ条件A）
   - `~/src/claude-config/skills/triage/SKILL.md` を参照元として英語に翻訳する
   - フロントマターの `description` を英語に翻訳する
   - `allowed-tools` から絶対パス（`/Users/saito/.claude/scripts/...`）を除去し、`~/.claude/scripts/...` 形式のみ残す
   - `### 1.5. 重複候補検出` → `### Step 2: Duplicate Candidate Detection` にリネームし、後続の `### 2.` 以降をすべて1ずつ繰り下げて `### Step N:` 形式に統一する
   - `### 1.`〜`### 9.` 等のすべての数値見出しを `### Step N: Title` 形式に変換する
   - 機会主義的簡素化を適用する（冗長な手順を意図レベルの説明に圧縮、動作に影響しない範囲で）

2. `skills/audit/SKILL.md` を新規作成する（→ 受け入れ条件B）
   - `~/src/claude-config/skills/audit/SKILL.md` を参照元として英語に翻訳する
   - フロントマターの `description` を英語に翻訳する
   - 機会主義的簡素化を適用する

3. `skills/doc/SKILL.md` を新規作成する（→ 受け入れ条件C）
   - `~/src/claude-config/skills/doc/SKILL.md` を参照元として英語に翻訳する
   - フロントマターの `description` を英語に翻訳する
   - `claude-config リポジトリが正しくセットアップされているか確認してください` → `wholework is not correctly installed. Run install.sh first.` に置換（2箇所）
   - `claude-config 管理ディレクトリ: skills/、modules/、agents/` → `wholework-managed directories: skills/, modules/, agents/` に置換（1箇所）
   - 機会主義的簡素化を適用する

4. doc サブテンプレートを新規作成する（→ 受け入れ条件D）
   - `skills/doc/product-template.md`: 参照元の日本語プレースホルダー（`プロジェクトの目的・ゴールを記述する` 等）をすべて英語化（例: `Describe the project purpose and goals.`）
   - `skills/doc/tech-template.md`: 同様に英語化
   - `skills/doc/structure-template.md`: 参照元を確認し、日本語があれば英語化

5. `docs/migration-notes.md` を更新する（→ 受け入れ条件E）
   - 末尾に `## Issue #23: Utility Skills Migration (triage, audit, doc)` セクションを追記する
   - インターフェース変更点（フロントマター `description` の翻訳、`allowed-tools` の変更、セクション見出しの翻訳、`claude-config` 参照の汎用化）を記録する

## 検証方法

### マージ前

- <!-- verify: file_exists "skills/triage/SKILL.md" --> `skills/triage/SKILL.md` が作成されている
- <!-- verify: file_exists "skills/audit/SKILL.md" --> `skills/audit/SKILL.md` が作成されている
- <!-- verify: file_exists "skills/doc/SKILL.md" --> `skills/doc/SKILL.md` が作成されている
- <!-- verify: file_exists "skills/doc/product-template.md" --> doc のサブファイルが移植されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: grep "Issue #23" "docs/migration-notes.md" --> インターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- `/triage` スキルが利用可能になること
- `/audit` スキルが利用可能になること
- `/doc` スキルが利用可能になること

## 注意事項

- **小数ステップ (`### 1.5.`)**: triage/SKILL.md のソースに `### 1.5. 重複候補検出` が存在する。バリデーター検出パターンは `### Step N.M:` 形式のみだが、移植時に `### Step N:` 形式へ統一する（小数ステップ禁止の MUST 制約に準拠するため）。後続ステップも繰り下げが必要。
- **絶対パス**: triage ソースの `allowed-tools` に `/Users/saito/.claude/scripts/...` が含まれる。これはプライベートリポジトリ固有の設定で、移植時に削除する（`~/.claude/scripts/...` 形式のみ残す）。
- **claude-config 参照**: doc/SKILL.md の3箇所に "claude-config リポジトリ" への言及がある。wholework インストール手順（`install.sh`）への参照に置換する。
- **model フィールド**: triage ソースに `model: sonnet` がある。`validate-skill-syntax.py` の `KNOWN_FIELDS` に含まれるため、そのまま移植してよい。
- **template ファイルの英語化**: 日本語プレースホルダーは実際にユーザーが参照するため英語化が必要。既存の `docs/structure.md` や `docs/migration-notes.md` の文体を参考にする。
- **settings.json 不在**: このリポジトリに `.claude/settings.json` は存在しないため、Skill パーミッション追加は不要。
