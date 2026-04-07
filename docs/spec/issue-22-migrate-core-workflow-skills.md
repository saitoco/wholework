# Issue #22: Migrate core workflow skills (issue, spec, review)

## 概要

親 Issue #20 の sub-issue。claude-config の issue, spec, review の 3 スキル（10 ファイル）を wholework に移植する。各 SKILL.md のスタブを本体で置換し、7 つのサブファイルを新規作成する。日本語テキストをすべて英語に変換する。#21 で確立した移植パターンに従う。

**移植対象ファイル（ソース: `~/src/claude-config/skills/`）:**

| スキル | ファイル | ソース行数 | 日本語行数 |
|-------|---------|-----------|-----------|
| issue | SKILL.md | 658 | 356 |
| issue | mcp-call-guidelines.md | 9 | 5 |
| issue | spec-test-guidelines.md | 150 | 58 |
| spec | SKILL.md | 865 | 500 |
| spec | codebase-search.md | 49 | 30 |
| spec | external-spec.md | 49 | 31 |
| spec | figma-design-phase.md | 91 | 46 |
| review | SKILL.md | 779 | 390 |
| review | external-review-phase.md | 126 | 64 |
| review | skill-dev-recheck.md | 21 | 9 |

**現状:** `skills/issue/`, `skills/spec/`, `skills/review/` にはそれぞれ 3〜10 行のスタブ SKILL.md が存在する。サブファイルは未作成。

## 変更対象ファイル

- `skills/issue/SKILL.md`: スタブを本体に置換
- `skills/issue/mcp-call-guidelines.md`: 新規作成
- `skills/issue/spec-test-guidelines.md`: 新規作成
- `skills/spec/SKILL.md`: スタブを本体に置換
- `skills/spec/codebase-search.md`: 新規作成
- `skills/spec/external-spec.md`: 新規作成
- `skills/spec/figma-design-phase.md`: 新規作成
- `skills/review/SKILL.md`: スタブを本体に置換
- `skills/review/external-review-phase.md`: 新規作成
- `skills/review/skill-dev-recheck.md`: 新規作成
- `docs/migration-notes.md`: Issue #22 セクションを追加

## 実装ステップ

1. `skills/issue/SKILL.md` を claude-config ソースから英語化して置換し、`mcp-call-guidelines.md` と `spec-test-guidelines.md` を英語化して新規作成する（→ 受け入れ条件 A, B）

2. `skills/spec/SKILL.md` を claude-config ソースから英語化して置換し、`codebase-search.md`、`external-spec.md`、`figma-design-phase.md` を英語化して新規作成する（1と並行可）（→ 受け入れ条件 C, D）

3. `skills/review/SKILL.md` を claude-config ソースから英語化して置換し、`external-review-phase.md` と `skill-dev-recheck.md` を英語化して新規作成する（1, 2と並行可）（→ 受け入れ条件 E, F）

4. `python3 scripts/validate-skill-syntax.py skills/issue skills/spec skills/review` を実行し、全スキルの構文バリデーションを通過させる。失敗があれば修正する（1, 2, 3の後）（→ 受け入れ条件 G）

5. `docs/migration-notes.md` に Issue #22 セクションを追加する。前回 #21 と同じフォーマットで、フロントマター description 翻訳、セクション見出し翻訳、プライベートリポジトリ参照の処理、インターフェース変更を記録する（4と並行可）（→ 受け入れ条件 H）

## 検証方法

### マージ前

- <!-- verify: file_exists "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/issue/mcp-call-guidelines.md" --> issue のサブファイルが移植されている
- <!-- verify: file_exists "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/spec/codebase-search.md" --> spec のサブファイルが移植されている
- <!-- verify: file_exists "skills/review/SKILL.md" --> `skills/review/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/review/external-review-phase.md" --> review のサブファイルが移植されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: grep "Issue #22" "docs/migration-notes.md" --> インターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- `validate-skill-syntax.py` が CI で PASS することを確認する

## ツール依存関係

### Bash コマンドパターン

issue, spec, review の `allowed-tools` フロントマターで使用されるパターンはすべて既存のもの（`gh issue view:*`, `gh pr view:*`, `~/.claude/scripts/xxx.sh:*`, `git add:*` 等）。KNOWN_TOOLS に未登録のツールはない。

### 組み込みツール

`allowed-tools` に列挙されるツール（Read, Write, Edit, Glob, Grep, WebFetch, WebSearch, ToolSearch, EnterWorktree, ExitWorktree, Task, TaskCreate, TaskUpdate, TaskList, TaskGet）はすべて KNOWN_TOOLS に登録済み。

### MCP ツール

spec の `allowed-tools` に含まれる `mcp__plugin_figma_figma__*` パターンは `mcp__` プレフィックス付きのため KNOWN_TOOLS チェックをバイパスする。

## 注意事項

### 英語化ガイドライン

前回の移植（#21: merge, code, auto, verify）と同じ方針に従う:

- セクション見出し: `手順` → `Steps`, `目的` → `Purpose`, `入力` → `Input`, `処理手順` → `Processing Steps`, `出力` → `Output`
- フロントマター `description` フィールド: 日本語全体を英訳
- ステップ名・本文・コメント: すべて英語化
- `~/.claude/modules/xxx.md` パス参照はそのまま維持（install.sh でシンボリックリンク経由で同じ場所に配置されるため）
- `~/.claude/scripts/xxx.sh` パス参照もそのまま維持
- 機会主義的簡素化（verbose なステップシーケンスを意図記述に圧縮）を適用可

### validate-skill-syntax.py の既知の制約

- 半角 `!` は SKILL.md 本文（コードフェンス・インラインコード・HTML コメント外）で禁止。英語化時に感嘆符を使わないこと
- `Write`, `Read` 等の一般的な英単語がツール名として誤検出される可能性あり（#21 で `Write` が検出された前例）。文脈で回避するか、対象ファイルを確認して必要に応じてワーディングを調整する
- frontmatter の `description` は1行で記述する（YAML block scalar 非対応）

### context: fork フィールド

`review/SKILL.md` のフロントマターには `context: fork` フィールドが含まれる。これは `VALID_CONTEXTS = {'fork'}` で許可されているため、そのまま維持する。

### allowed-tools パスの維持

3スキルの `allowed-tools` フロントマターには `~/.claude/scripts/xxx.sh:*` 形式のパスが含まれる。これらは wholework の `install.sh` でシンボリックリンク経由で同じ場所に配置されるため、変更不要。

### サブファイルの相互参照

- `spec/SKILL.md` は `skills/spec/codebase-search.md`、`skills/spec/external-spec.md`、`skills/spec/figma-design-phase.md` を Read 指示で参照している
- `review/SKILL.md` は `skills/review/external-review-phase.md`、`skills/review/skill-dev-recheck.md` を Read 指示で参照している
- `issue/SKILL.md` は `skills/issue/mcp-call-guidelines.md`、`skills/issue/spec-test-guidelines.md` を Read 指示で参照している
- これらの参照パスは SKILL.md 内で相対パスではなく `skills/xxx/yyy.md` 形式で記述されているため、ディレクトリ構造が同じである限り変更不要

## code レトロスペクティブ

### 設計からの逸脱
- 特になし。Spec の実装ステップ（1→2→3→4→5）の順序通りに実施した

### 設計の不備・曖昧さ
- `review/SKILL.md` のコミットメッセージの Co-Author タグが Spec では `Sonnet 4.5` だったが、実際は `Sonnet 4.6` が正しいため修正して実装した（migration-notes.md にも記録済み）
- Spec には「機会主義的簡素化を適用可」とあったが、具体的にどの箇所を簡素化するかは実装者の判断に委ねられており、一部の詳細手順（sub-issue 作成フローの GraphQL コマンドなど）は原文を圧縮して記述した

### 手戻り
- 特になし。バリデーション（`validate-skill-syntax.py`）は初回で全PASS

## spec レトロスペクティブ

### 軽微な観察
- 3 SKILL.md（合計 2,302 行）+ 7 サブファイル（合計 495 行）で、#21（5ファイル, 1,355行）より大幅に規模が大きい。日本語行数も合計 1,489 行あり英語化の作業量が多い
- #21 のレトロスペクティブで「`grep -r "[\u3000-\u9fff]" skills/` 形式の全ファイル日本語残留チェックを追加する」提案があったが、今回の受け入れ条件には反映されていない。Issue 本文の受け入れ条件をそのまま維持した

### 判断経緯
- `allowed-tools` パスや `~/.claude/` パス参照は変更不要と判断。install.sh のシンボリックリンク設計により、private repo と同じパスで動作する
- `validate-skill-syntax.py` の KNOWN_TOOLS に追加が必要なツールはないと確認済み
- `context: fork` フィールド（review のみ）は既存バリデーターで許可されていることを確認済み

### 不確定要素の解決
- 特になし。#21 で同一パターンが確立済みのため不確定要素は発生しなかった

## review レトロスペクティブ

### 設計と実装の乖離パターン

特になし。Spec の変更対象ファイル11件がすべて PR に含まれており、受け入れ条件8件すべて PASS。乖離は検出されなかった。

### 頻出する指摘事項

`skills/review/SKILL.md` にステップ番号の系統的ずれが検出された（`## Step N` 見出しと内部サブステップ番号が1ずれ）。さらに本文内のクロスリファレンスも旧番号体系に基づいており、実行時の混乱を招く可能性がある。また `skills/review/external-review-phase.md` の Step 7.4 に "same procedure as 6.2" という存在しないステップへの参照誤りが検出された（正: 7.2）。両方とも SHOULD 指摘であり MUST ではないため今回は修正せず、別 Issue での対応を推奨する。

### 受け入れ条件の検証困難さ

UNCERTAIN 件数: 0件（全件 PASS 判定済み）。`command` ヒントを持つ条件（validate-skill-syntax.py 実行）は CI ジョブ `Validate skill syntax` の SUCCESS で代替検証できた。受け入れチェックの設計は適切だった。

## verify レトロスペクティブ

### 各フェーズの振り返り

#### spec
- 3 SKILL.md + 7 サブファイル（合計 2,797 行）と #21 より大幅に規模が大きかったが、#21 で確立したパターンの適用で不確定要素は発生しなかった
- #21 レトロスペクティブで提案された「全ファイル日本語残留チェック（`grep -r "[あ-ん]" skills/`）」が今回の受け入れ条件に反映されなかった。次回の移植タスクで受け入れ条件に追加する価値がある

#### design
- 特になし。Spec は変更対象11ファイルを網羅しており、実装との乖離なし

#### code
- 設計通りの順序で実装が完了し、validate-skill-syntax.py も初回でフルPASS
- Spec の Co-Author タグ（`Sonnet 4.5`）が実装時に `Sonnet 4.6` に修正されたが、Spec 本体の更新は行われなかった（軽微）

#### review
- `skills/review/SKILL.md` に `## Step N` 見出しと内部サブステップ番号の系統的ずれ（1オフセット）が検出された。本文中のクロスリファレンスも旧番号体系のままで、実行時の混乱を招く可能性がある（SHOULD）
- `skills/review/external-review-phase.md` の Step 7.4 に「same procedure as 6.2」という誤参照（正: 7.2）が存在する（SHOULD）
- `docs/structure.md` の Directory Layout がサブファイルパターンを反映していない（CONSIDER、Issue #21 から引き継いだ既存乖離）

#### merge
- FF マージで問題なし。コンフリクトなし

#### verify
- 全8条件 PASS。FAIL/UNCERTAIN ゼロ。受け入れチェックの `file_exists` + `command` + `grep` の組み合わせが適切に機能した

### 改善提案
- `skills/review/SKILL.md` のステップ番号ずれと `external-review-phase.md` の誤参照を修正する別 Issue を作成する（review レトロスペクティブの SHOULD 指摘）
- `docs/structure.md` の Directory Layout にサブファイルパターン（`skills/*/SKILL.md` + 補助 `.md`）を追記する Issue を作成する
- 移植タスクの受け入れ条件に日本語残留チェック（`grep -r "[あ-ん]" skills/`）を標準追加することを検討する
