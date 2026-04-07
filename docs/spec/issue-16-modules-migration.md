# Issue #16: modules: Migrate from private repo with English conversion

## 概要

claude-config（private repo）の `modules/` 全 22 ファイル（計 1,716 行）を wholework に移植する。Migration Guidelines に従い全テキストを英語化し、saito/claude-config#845 の方針に基づいて明らかに冗長な逐次手順を高レベルの意図指示に機会主義的に簡素化する。

移植対象モジュールは skills が `~/.claude/modules/xxx.md` 形式で参照する共有コンポーネントであり、これらがないと wholework 単体でスキルが正しく動作しない。scripts 移植（#6, #7, #8, #9）に続く次の移植ステップ。

## 変更対象ファイル

### 新規作成（22 files）

**Verify/Review 関連:**
- `modules/verify-patterns.md`: 新規作成（153行 → 英語化＋簡素化）
- `modules/verify-classifier.md`: 新規作成（46行 → 英語化＋簡素化）
- `modules/verify-executor.md`: 新規作成（143行 → 英語化＋簡素化）
- `modules/review-output-format.md`: 新規作成（44行 → 英語化＋簡素化）
- `modules/review-type-weighting.md`: 新規作成（59行 → 英語化＋簡素化）
- `modules/opportunistic-verify.md`: 新規作成（89行 → 英語化＋簡素化）

**Issue/Triage 関連:**
- `modules/ambiguity-detector.md`: 新規作成（38行 → 英語化＋簡素化）
- `modules/title-normalizer.md`: 新規作成（49行 → 英語化＋簡素化）
- `modules/size-workflow-table.md`: 新規作成（79行 → 英語化＋簡素化）
- `modules/project-field-update.md`: 新規作成（81行 → 英語化＋簡素化）
- `modules/skill-help.md`: 新規作成（51行 → 英語化＋簡素化）

**Code/Infrastructure:**
- `modules/worktree-lifecycle.md`: 新規作成（91行 → 英語化＋簡素化）
- `modules/detect-config-markers.md`: 新規作成（64行 → 英語化＋簡素化）
- `modules/codebase-analysis.md`: 新規作成（58行 → 英語化＋簡素化）
- `modules/doc-checker.md`: 新規作成（95行 → 英語化＋簡素化）

**Browser/Testing:**
- `modules/browser-adapter.md`: 新規作成（102行 → 英語化＋簡素化）
- `modules/browser-verify-security.md`: 新規作成（72行 → 英語化＋簡素化）
- `modules/lighthouse-adapter.md`: 新規作成（49行 → 英語化＋簡素化）
- `modules/test-runner.md`: 新規作成（100行 → 英語化＋簡素化）
- `modules/measurement-scope.md`: 新規作成（48行 → 英語化＋簡素化）

**Other:**
- `modules/adapter-resolver.md`: 新規作成（61行 → 英語化＋簡素化）
- `modules/skill-dev-checks.md`: 新規作成（144行 → 英語化＋簡素化）

### 既存ファイル変更

- `docs/structure.md`: modules/ のキーファイル一覧を追加
- `docs/migration-notes.md`: Issue #16 のインターフェース変更記録を追加

## 実装ステップ

### Step 1: modules/ ディレクトリ作成と Verify/Review グループ移植（→ 受け入れ条件A,B,C,E）

`modules/` ディレクトリを作成し、Verify/Review 関連の 6 ファイルを移植する:
- `verify-patterns.md`, `verify-classifier.md`, `verify-executor.md`
- `review-output-format.md`, `review-type-weighting.md`, `opportunistic-verify.md`

各ファイルについて:
1. `~/src/claude-config/modules/{name}.md` を読み取る
2. 全テキストを英語に変換する（セクション見出し、説明文、テーブル内容、コメント）
3. 標準構造（Purpose / Input / Processing Steps / Output）のセクション見出しを英語で維持する
4. Read 指示の配置（見出し直後の最初の段落）は変更しない
5. テーブル形式のマッピング定義は維持する
6. 背景 Issue 番号付きの指示は維持する（ガードレール）
7. 明らかに冗長な逐次手順を高レベルの意図指示に書き換える（機会主義的）

### Step 2: Issue/Triage グループ移植（Step 1 と並行可）（→ 受け入れ条件D,F）

Issue/Triage 関連の 5 ファイルを同じ手順で移植する:
- `ambiguity-detector.md`, `title-normalizer.md`, `size-workflow-table.md`
- `project-field-update.md`, `skill-help.md`

### Step 3: Code/Infrastructure グループ移植（Step 1,2 と並行可）（→ 受け入れ条件B）

Code/Infrastructure 関連の 4 ファイルを同じ手順で移植する:
- `worktree-lifecycle.md`, `detect-config-markers.md`
- `codebase-analysis.md`, `doc-checker.md`

### Step 4: Browser/Testing グループ移植（Step 1,2,3 と並行可）（→ 受け入れ条件B）

Browser/Testing 関連の 5 ファイルを同じ手順で移植する:
- `browser-adapter.md`, `browser-verify-security.md`, `lighthouse-adapter.md`
- `test-runner.md`, `measurement-scope.md`

### Step 5: Other グループ移植（Step 1,2,3,4 と並行可）（→ 受け入れ条件B）

残り 2 ファイルを同じ手順で移植する:
- `adapter-resolver.md`, `skill-dev-checks.md`

### Step 6: docs/structure.md 更新（Step 1-5 の後）（→ 受け入れ条件H）

`docs/structure.md` の `### modules/` セクションにキーモジュールの一覧を追加する。既存の `### scripts/` セクションに `tests/` の記述パターンに合わせ、代表的なモジュールファイルを記載する。

### Step 7: docs/migration-notes.md 更新（Step 1-5 の後）（→ 受け入れ条件I）

`docs/migration-notes.md` に Issue #16 のセクションを追加する:
- 移植対象ファイル数（22 files）と概要
- リファクタリングによるインターフェース変更の記録（セクション見出しの英語化、逐次手順の簡素化等）
- 変更がない場合は「No interface changes」と記載

### Step 8: validate-skill-syntax.py 検証（Step 1-7 の後）（→ 受け入れ条件G）

`python3 scripts/validate-skill-syntax.py skills/` を実行し、全スキルが PASS することを確認する。modules/ が存在する状態で cross-file validation（modules 内で参照される scripts が skills の allowed-tools に含まれているか）も検証される。

## 検証方法

### マージ前

- <!-- verify: dir_exists "modules" --> `modules/` ディレクトリが作成されている
- <!-- verify: file_exists "modules/ambiguity-detector.md" --> 全 22 modules が移植されている（代表: `ambiguity-detector.md`）
- <!-- verify: file_exists "modules/verify-patterns.md" --> verify 関連モジュールが移植されている（代表: `verify-patterns.md`）
- <!-- verify: file_exists "modules/worktree-lifecycle.md" --> インフラ関連モジュールが移植されている（代表: `worktree-lifecycle.md`）
- <!-- verify: file_not_contains "modules/ambiguity-detector.md" "曖昧さ検出パターン" --> 日本語テキストが英語に変換されている（代表: `ambiguity-detector.md`）
- <!-- verify: file_not_contains "modules/title-normalizer.md" "タイトル正規化" --> 日本語テキストが英語に変換されている（代表: `title-normalizer.md`）
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: grep "modules" "docs/structure.md" --> `docs/structure.md` に `modules/` ディレクトリが記載されている
- <!-- verify: grep "Issue #16" "docs/migration-notes.md" --> リファクタリングによるインターフェース変更が `docs/migration-notes.md` に記録されている

### マージ後

- `/spec` `/code` `/review` `/verify` 等のスキルが modules を正しく参照できることを確認する（modules がスキルの SKILL.md から `~/.claude/modules/xxx.md` 形式で参照されるため、install.sh 実行後に動作確認）

## 注意事項

- **リファクタリング範囲**: saito/claude-config#845 の方針を参考に、明らかに冗長な逐次手順のみを機会主義的に簡素化する。テーブル形式のマッピング定義、背景 Issue 番号付きの指示（ガードレール）、Read 指示の配置は変更しない。行数の数値目標は設けない
- **標準構造の維持**: modules の標準構造（Purpose / Input / Processing Steps / Output）のセクション見出しは英語で維持する。日本語の「目的」→「Purpose」、「入力」→「Input」、「処理手順」→「Processing Steps」、「出力」→「Output」
- **private repo 参照**: 調査の結果、modules 内に claude-config 固有のパス参照は存在しなかった。移植時に改めて確認し、発見した場合は除去する
- **スキルからの参照パス**: 現在 wholework のスキルは modules を参照していない。modules 移植後も、スキルの SKILL.md 側の参照パス更新は本 Issue のスコープ外（スキルは `~/.claude/modules/xxx.md` パスで参照しており、install.sh が symlink を作成するため、modules ファイルが存在すれば動作する）
- **validate-skill-syntax.py の cross-file validation**: modules/ が存在する状態で初めて `validate_modules_scripts_in_allowed_tools` 関数が有効になる。modules 内の Bash コマンドパターン（`scripts/xxx.sh` 等）が skills の allowed-tools に含まれているかを検証するため、既存スキルで警告が出る可能性がある。その場合は警告内容を確認し、false positive であれば migration-notes に記録する

## issue レトロスペクティブ

### 判断経緯
- 22 ファイル（XL 基準）だがドキュメントのみの変更のため複雑度補正 -1 で L と判定。sub-issue 分割不要
- scripts 移植 (#6) と同じパターン（claude-config → wholework、英語化 + リファクタリング）のため、曖昧ポイントは全て自動解決

### 重要な方針決定
- scripts 移植時 (#6) の方針を踏襲: 英語化 + private repo 固有参照の除去 + migration-notes.md への変更記録
- ロジック改善はスコープ外（英語化と汎用化のみ）
- verify false positive 修正: `grep "modules" "docs/migration-notes.md"` → `grep "Issue #16" "docs/migration-notes.md"` に修正（既存ファイルに "modules/" が既出のため）

## spec レトロスペクティブ

### 軽微な観察
- 22 ファイルの移植は scripts 移植（#6, #7, #8, #9）と同一パターンのため、設計上の新規判断は少なかった
- modules 内に claude-config 固有のパス参照がなかったため、汎用化の作業負荷は低い見込み

### 判断経緯
- 実装ステップを機能グループ（Verify/Review, Issue/Triage, Code/Infrastructure, Browser/Testing, Other）に分割し、並行実行可能にした。22 ファイルを個別ステップにすると上限超過のため、5グループ + ドキュメント2件 + 検証1件 = 計8ステップに収めた
- ISSUE_TYPE=Task のため、代替案の検討・不確定要素・UIデザインセクションを省略

### 不確定要素の解決
- validate-skill-syntax.py の cross-file validation が modules 存在時にどう動作するかは、Step 8 で実行して初めて判明する。Spec 段階では注意事項として記録するにとどめた
