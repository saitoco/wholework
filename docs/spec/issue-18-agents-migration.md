# Issue #18: agents: Migrate from private repo with English conversion

## 概要

claude-config（private repo）にのみ存在する 6 つのエージェント定義ファイルを wholework の `agents/` ディレクトリに移植する。Migration Guidelines に従ってすべての日本語テキスト（frontmatter の `description` フィールド、セクション見出し、本文、コードブロック内の例示テキスト）を英語に変換する。Issue #16 modules 移植と同じ方針で、明らかに冗長な記述を機会主義的に簡素化する（動作維持を最優先）。

**移植対象（`~/src/claude-config/agents/` → `agents/`）:**
- `review-bug.md` (118 lines) — バグ/ロジックエラー検出エージェント
- `review-light.md` (110 lines) — 軽量統合レビューエージェント
- `review-spec.md` (125 lines) — 仕様・ドキュメント系レビューエージェント
- `scope-agent.md` (86 lines) — スコープ調査エージェント
- `risk-agent.md` (83 lines) — リスク調査エージェント
- `precedent-agent.md` (83 lines) — 前例調査エージェント

合計: 6 ファイル、605 行（`ls ~/src/claude-config/agents/*.md | xargs wc -l` で計測）

## 変更対象ファイル

- `agents/review-bug.md`: 新規作成（英語化 + 簡素化）
- `agents/review-light.md`: 新規作成（英語化 + 簡素化）
- `agents/review-spec.md`: 新規作成（英語化 + 簡素化）
- `agents/scope-agent.md`: 新規作成（英語化 + 簡素化）
- `agents/risk-agent.md`: 新規作成（英語化 + 簡素化）
- `agents/precedent-agent.md`: 新規作成（英語化 + 簡素化）
- `docs/migration-notes.md`: Issue #18 セクションを追加

**変更不要（事前確認済み）:**
- `docs/structure.md`: `agents/` ディレクトリの説明・インストールターゲット・Key Files セクションがすでに記載済み（`grep "agents" docs/structure.md` で 8 箇所確認）
- `README.md`: `agents/` インストール先テーブルがすでに記載済み（27 行目）
- `install.sh`: `agents/` シンボリックリンク作成処理がすでに実装済み（43–45 行目）

## 実装ステップ

1. `agents/review-bug.md` を作成 — `~/src/claude-config/agents/review-bug.md` を英訳・簡素化して移植（→ 受け入れ条件1, 2, 4）
2. `agents/review-light.md` を作成 — 同上（→ 受け入れ条件1）
3. `agents/review-spec.md` を作成 — 同上（→ 受け入れ条件1）
4. `agents/scope-agent.md` を作成 — 同上（→ 受け入れ条件1, 3）
5. `agents/risk-agent.md` を作成 — 同上（→ 受け入れ条件1）
6. `agents/precedent-agent.md` を作成 — 同上（→ 受け入れ条件1）
7. `docs/migration-notes.md` に Issue #18 セクションを追加 — 各エージェントのインターフェース変更記録（→ 受け入れ条件7）

## 検証方法

### マージ前

- <!-- verify: dir_exists "agents" --> `agents/` ディレクトリが作成されている
- <!-- verify: file_exists "agents/review-bug.md" --> 全 6 agents が移植されている（代表: `review-bug.md`）
- <!-- verify: file_exists "agents/scope-agent.md" --> 調査系エージェントが移植されている（代表: `scope-agent.md`）
- <!-- verify: file_not_contains "agents/review-bug.md" "レビュー" --> 日本語テキストが英語に変換されている（代表: `review-bug.md`）
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: grep "agents" "docs/structure.md" --> `docs/structure.md` に `agents/` ディレクトリが記載されている
- <!-- verify: grep "Issue #18" "docs/migration-notes.md" --> インターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- `install.sh` を実行し `~/.claude/agents/wholework/` に 6 つのエージェントファイルがシンボリックリンクされることを確認
- Claude Code から `Agent` ツールでエージェント（例: `review-bug`）が利用可能になることを確認

## 注意事項

**英語化チェックリスト（`docs/migration-notes.md` の English Conversion Checklist に準拠）:**
- Frontmatter の `description` フィールド（エージェントの呼び出し条件説明）
- セクション見出し（`## 目的` → `## Purpose`、`## 入力` → `## Input`、`## 処理手順` → `## Processing Steps`、`## 出力フォーマット` → `## Output Format`）
- サブセクション見出し（`### 0. 事前準備` → `### 0. Preparation` 等）
- 本文テキスト（箇条書き、テーブル、説明文）
- コードブロック内の例示テキスト（出力フォーマット例内の日本語見出し・説明文）
- `file_not_contains "agents/review-bug.md" "レビュー"` が PASS するまですべての日本語を除去すること

**モジュールパス参照:**
- エージェントファイル内の `~/.claude/modules/xxx.md` パス参照はそのまま維持する
- wholework のモジュールは `~/.claude/skills/wholework/modules/` にインストールされるが、ユーザーシステムでは `~/.claude/modules/` にも同名ファイルが存在するため参照が解決される
- 具体的な参照例: `~/.claude/modules/review-type-weighting.md`、`~/.claude/modules/review-output-format.md`、`~/.claude/modules/doc-checker.md`

**簡素化の方針（機会主義的 · Issue #16 準拠）:**
- 冗長な番号付き Bash/Grep ステップ列を intent-level 記述に簡素化する
- テーブル形式のマッピング定義はそのまま維持する
- Issue 番号ガードレール（`occurred in #509` 等）はトレーサビリティのために維持する
- claude-config 固有のパス参照・内部参照が含まれていないことを確認する（Issue #16 移植時に「None found」で問題なし）

**自動解決済みの曖昧ポイント:**
1. モジュールパス形式 → `~/.claude/modules/` を使用（コードベース全体の既存パターンに準拠）
2. 簡素化の範囲 → Issue #16 modules 移植と同じアプローチ
3. コードブロック内日本語 → すべて英訳対象（`file_not_contains` 受け入れ条件で検証）

## code レトロスペクティブ

### 設計からの逸脱

- 特になし

### 設計の不備・曖昧さ

- 特になし。Spec の注意事項に英語化チェックリストが詳細に記載されていたため、変換対象の漏れなく実施できた。

### 手戻り

- 特になし

---

## spec レトロスペクティブ

### 軽微な観察

- `docs/structure.md`、`README.md`、`install.sh` はすべて Issue #2（repo structure foundation）で事前に実装済みであり、今回の移植では変更不要。移植前に構造が整備されていたため、実装ステップをシンプルに保てた。
- `validate-skill-syntax.py` は `skills/*/SKILL.md` のみを対象としており、`agents/*.md` はバリデーション対象外。agents ファイルは SKILL.md とは異なるフロントマター（`tools` フィールド使用、`allowed-tools` は使用しない）を持つため、このスコープ設計は適切。

### 判断経緯

- `--non-interactive` フラグによりすべての曖昧ポイントを自動解決。モジュールパス参照の方針（`~/.claude/modules/` 維持）は、modules/ 内の既存ファイル（`modules/adapter-resolver.md` 等）が同じパターンを使用しており、既存コードベースとの一貫性から自明に決定できた。

### 不確定要素の解決

- 不確定要素なし。6 ファイルの移植範囲・英語化要件・インターフェース変更の記録方法はすべて Issue 本文と既存移植事例（Issue #16）から明確に導出できた。
