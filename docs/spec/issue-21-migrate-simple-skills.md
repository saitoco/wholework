# Issue #21: Migrate simple skills (merge, code, auto, verify)

## 概要

親 Issue #20 の sub-issue。claude-config の merge, code, auto, verify の 4 スキル（5 ファイル）を wholework に移植する。各 SKILL.md のスタブを本体で置換し、日本語テキストをすべて英語に変換する。

**移植対象ファイル（ソース: `~/src/claude-config/skills/`）:**

| スキル | ファイル | ソース行数 | 日本語行数 |
|-------|---------|-----------|-----------|
| merge | SKILL.md | 221 | 117 |
| code | SKILL.md | 384 | 207 |
| auto | SKILL.md | 296 | 167 |
| verify | SKILL.md | 432 | 228 |
| verify | browser-verify-phase.md | 22 | 15 |

**現状:** `skills/merge/`, `skills/code/`, `skills/verify/` には 8 行スタブが存在する。`skills/auto/` ディレクトリは未作成。

## 変更対象ファイル

- `skills/auto/SKILL.md`: 新規作成（`skills/auto/` ディレクトリも作成）
- `skills/merge/SKILL.md`: スタブを本体に置換
- `skills/code/SKILL.md`: スタブを本体に置換
- `skills/verify/SKILL.md`: スタブを本体に置換
- `skills/verify/browser-verify-phase.md`: 新規作成
- `docs/migration-notes.md`: Issue #21 セクションを追加

## 実装ステップ

1. `skills/merge/SKILL.md` を claude-config ソースから英語化して置換（→ 受け入れ条件 file_exists + file_not_contains）
2. `skills/code/SKILL.md` を claude-config ソースから英語化して置換（→ 受け入れ条件 file_exists）
3. `skills/auto/` ディレクトリを作成し `skills/auto/SKILL.md` を claude-config ソースから英語化して新規作成（→ 受け入れ条件 file_exists）
4. `skills/verify/SKILL.md` と `skills/verify/browser-verify-phase.md` を claude-config ソースから英語化して作成（→ 受け入れ条件 file_exists × 2）
5. `docs/migration-notes.md` に Issue #21 セクションを追加（→ 受け入れ条件 grep）

## 検証方法

### マージ前

- <!-- verify: file_exists "skills/merge/SKILL.md" --> `skills/merge/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/code/SKILL.md" --> `skills/code/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/auto/SKILL.md" --> `skills/auto/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/verify/SKILL.md" --> `skills/verify/SKILL.md` が移植されている
- <!-- verify: file_exists "skills/verify/browser-verify-phase.md" --> `skills/verify/browser-verify-phase.md` が移植されている
- <!-- verify: file_not_contains "skills/merge/SKILL.md" "Squash merge" --> 日本語テキストが英語に変換されている（代表: `merge`）
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: grep "Issue #21" "docs/migration-notes.md" --> インターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- `validate-skill-syntax.py` が CI で PASS することを確認する

## 注意事項

### 英語化ガイドライン

前回の移植（Issue #16: modules, Issue #18: agents）と同じ方針に従う:

- セクション見出し: `目的` → `Purpose`, `入力` → `Input`, `処理手順` → `Processing Steps`, `出力` → `Output`
- フロントマター `description` フィールド: 日本語全体を英訳
- ステップ名・本文・コメント: すべて英語化
- `~/.claude/modules/xxx.md` パス参照はそのまま維持
- 機会主義的簡素化（verboseなステップシーケンスを意図記述に圧縮）を適用可

### Squash merge 表記の注意

受け入れ条件 `file_not_contains "skills/merge/SKILL.md" "Squash merge"` の制約として:

- 英語化後も "Squash merge"（大文字S + 小文字m）の組み合わせを避ける
- 代わりに "Squash Merge"（両方大文字）または "squash-merge" を使用する
- ソースで "# Squash Merge" → そのまま "# Squash Merge" で OK（大文字M のため条件を満たす）
- ソースの description: `PRをSquash mergeして...` → "Squash-merge a PR and delete the remote branch." に変換

### プライベートリポジトリ固有参照の処理

- `auto/SKILL.md` 内の `~/.claude/skills/` に関する説明 → wholework のインストール構造（`~/.claude/skills/wholework/`）に合わせて更新
- `verify/SKILL.md` 内の "claude-config のスキル基盤" 等の表現 → 汎用的な "the skill infrastructure" 等に変換

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- The `validate-skill-syntax.py` body tool usage check catches standalone occurrences of known tool names (e.g., `Write`) in body text after stripping code blocks and inline code. The phrase "Write new integrated code" in merge/SKILL.md triggered a false positive. Rewrote to "Create new integrated code" to avoid the false positive. This edge case was not mentioned in the spec.

### Rework
- One additional commit was needed to fix the `Write` false positive in merge/SKILL.md after the initial migration commit. The validator check was only discovered at validation time.

## review レトロスペクティブ

### 設計と実装の乖離パターン

CLAUDE.md の英語化ガイドライン（「すべての日本語テキストを英語化」）が `skills/code/SKILL.md:271` の PR title format 指示テキストに適用されておらず、"in Japanese" が残留していた。Example が英語タイトルを示しているため機能的影響は軽微だが、移植チェックリストに「指示文・説明テキストも含めて英語化確認」を明示するとよい。

### 頻出する指摘事項

指摘は1件（英語化漏れ）のみで、同種の指摘が複数箇所にあるパターンは確認されなかった。`validate-skill-syntax.py` が自動チェックしていない領域（指示文テキスト）での見落としが発生しやすいことが分かった。

### 受け入れ条件の検証困難さ

受け入れ条件はすべて自動チェック可能なヒント付きで、UNCERTAIN なし。`file_not_contains "skills/merge/SKILL.md" "Squash merge"` のように代表ファイルのみを検証対象にしている条件があるが、全ファイルの日本語残留を網羅的に検証するには不十分。次回移植 Issue では `grep -r "日本語パターン" skills/` 形式の包括的チェックコマンドを追加することを検討する。

## verify レトロスペクティブ

### 各フェーズの振り返り

#### spec
- 受け入れ条件はすべて自動検証可能なヒント付きで設計されており、品質は高い
- `file_not_contains` チェックが代表ファイル（merge）のみを対象としているため、全移植ファイルの日本語残留を網羅的に検証できない点が潜在的なギャップ

#### design
- `validate-skill-syntax.py` の本文中ツール名検出が "Write" 等の一般的な英単語と誤衝突するエッジケースが Spec に記載されていなかった
- このギャップは Code 手戻り（1コミット追加）の直接原因となった

#### code
- 初回コミット後、`Write` 偽陽性を修正する追加コミットが1件発生した（commit `4b50f93` → `2a36f04` でレトロスペクティブ追加の流れ）
- 手戻りは軽微だが、バリデータの挙動をより詳しく Spec に記載することで防止できた

#### review
- "in Japanese" テキスト残留を1件検出（`skills/code/SKILL.md:271`）— バリデータが自動チェックしない指示文領域での見落としを正しくキャッチした
- 同種の複数指摘はなく、レビュー精度は良好

#### merge
- PR #24 でスカッシュマージ、コンフリクトなし。クリーンなマージ（commit `21e8631`）

#### verify
- 全8条件 PASS、再実行確認済み
- `file_not_contains` が代表ファイルのみチェックするため、他ファイルの日本語残留は verify でも検出できない設計上の制約がある

### 改善提案
- 移植系 Issue の受け入れ条件に `file_not_contains` の代表チェックではなく、`grep -r "[\u3000-\u9fff]" skills/` 形式の全ファイル日本語残留チェックを追加することで、英語化漏れを網羅的に検出できるようにする
