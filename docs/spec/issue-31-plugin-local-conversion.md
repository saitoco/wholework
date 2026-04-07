# Issue #31: plugin: Convert wholework to local plugin for namespaced skill discovery

## 概要

wholework を Claude Code のローカルプラグイン（`--plugin-dir` 形式）に対応させる。
`install.sh` を廃止し、`claude --plugin-dir ~/src/wholework` で起動することでスキルが `wholework:<skill-name>` の名前空間で発見されるようにする。
あわせて、skills/modules/agents 内の `~/.claude/modules/` および `~/.claude/scripts/` 参照パスをプラグイン互換の `${CLAUDE_PLUGIN_ROOT}/` パスに全置換する。

## 変更対象ファイル

**新規作成:**
- `.claude-plugin/plugin.json`: プラグインマニフェスト（`name: "wholework"` 等を定義）

**削除:**
- `install.sh`: シンボリックリンク方式のインストーラー → 廃止
- `tests/install.bats`: install.sh のテスト → 廃止

**パス更新（21 ファイル）— `~/.claude/` → `${CLAUDE_PLUGIN_ROOT}/` に全置換:**
- `skills/merge/SKILL.md`（body + allowed-tools frontmatter）
- `skills/verify/SKILL.md`（body + allowed-tools frontmatter）
- `skills/verify/browser-verify-phase.md`（body）
- `skills/auto/SKILL.md`（body + allowed-tools frontmatter）
- `skills/spec/SKILL.md`（body + allowed-tools frontmatter）
- `skills/code/SKILL.md`（body + allowed-tools frontmatter）
- `skills/triage/SKILL.md`（body + allowed-tools frontmatter）
- `skills/audit/SKILL.md`（body + allowed-tools frontmatter）
- `skills/issue/SKILL.md`（body + allowed-tools frontmatter）
- `skills/issue/mcp-call-guidelines.md`（body）
- `skills/review/SKILL.md`（body + allowed-tools frontmatter）
- `skills/review/external-review-phase.md`（body）
- `skills/doc/SKILL.md`（body + allowed-tools frontmatter）
- `modules/opportunistic-verify.md`（body）
- `modules/adapter-resolver.md`（body）
- `modules/verify-executor.md`（body）
- `modules/project-field-update.md`（body）
- `modules/browser-adapter.md`（body）
- `agents/review-light.md`（body）
- `agents/review-spec.md`（body）
- `agents/review-bug.md`（body）

**バリデーター更新:**
- `scripts/validate-skill-syntax.py`: `SCRIPT_PATH_PATTERN` / `MODULES_REF_PATTERN` / 内部文字列を `${CLAUDE_PLUGIN_ROOT}` パターンに更新
- `tests/validate-skill-syntax.bats`: フィクスチャデータの `~/.claude/scripts/` を `${CLAUDE_PLUGIN_ROOT}/scripts/` に更新

**ドキュメント更新:**
- `README.md`: インストール手順を `./install.sh` から `--plugin-dir` 方式に変更
- `docs/structure.md`: directory layout から `install.sh` を削除し `.claude-plugin/` を追加、Install セクションを更新

## 実装ステップ

1. `.claude-plugin/` ディレクトリを作成し、`plugin.json` を新規作成する（`{"name": "wholework"}`）（→ 受け入れ条件1, 2）

2. `install.sh` と `tests/install.bats` を削除する（→ 受け入れ条件3）

3. skills/ (13ファイル) ・modules/ (5ファイル) ・agents/ (3ファイル) の合計21ファイルについて、`~/.claude/modules/` を `${CLAUDE_PLUGIN_ROOT}/modules/` に、`~/.claude/scripts/` を `${CLAUDE_PLUGIN_ROOT}/scripts/` にそれぞれ全置換する（body テキストおよび allowed-tools frontmatter の両方を対象とする）（→ 受け入れ条件5）

4. `scripts/validate-skill-syntax.py` の `SCRIPT_PATH_PATTERN`（line 71）を `r'\$\{CLAUDE_PLUGIN_ROOT\}/scripts/([a-zA-Z0-9_-]+\.sh)'` に更新し、`MODULES_REF_PATTERN`（line 74）を `r'\$\{CLAUDE_PLUGIN_ROOT\}/modules/([a-zA-Z0-9_-]+\.md)'` に更新し、line 809 の内部文字列 `f'~/.claude/scripts/{script_name}'` を `f'${{CLAUDE_PLUGIN_ROOT}}/scripts/{script_name}'` に更新する。あわせて `tests/validate-skill-syntax.bats` のフィクスチャ内 `~/.claude/scripts/` を `${CLAUDE_PLUGIN_ROOT}/scripts/` に更新する（→ 受け入れ条件4）

5. `README.md` の Install セクションをプラグイン方式（`claude --plugin-dir ~/src/wholework`）に更新し、`docs/structure.md` の directory layout と Install セクションを更新する（→ 受け入れ条件6）

## 検証方法

### マージ前

- <!-- verify: file_exists ".claude-plugin/plugin.json" --> `.claude-plugin/plugin.json` が作成されている
- <!-- verify: json_field ".claude-plugin/plugin.json" ".name" "wholework" --> plugin.json の name フィールドが `wholework` に設定されている
- <!-- verify: file_not_exists "install.sh" --> `install.sh` が削除されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> validate-skill-syntax.py が全スキルで PASS する
- <!-- verify: command "! grep -rl '~/.claude/modules/\|~/.claude/scripts/' skills/ modules/ agents/ 2>/dev/null | grep -q ." --> skills/, modules/, agents/ 内に `~/.claude/modules/` や `~/.claude/scripts/` の参照が残っていない
- <!-- verify: grep "plugin-dir" "README.md" --> README.md にプラグインとしてのインストール方法が記載されている

### マージ後

- `claude --plugin-dir ~/src/wholework` で起動し、`/wholework:review` 等の名前空間付きスキルが `/skills` 一覧に表示されることを確認
- agents がプラグイン経由で正しく発見されることを確認（`/agents` 一覧に表示）
- modules, scripts がスキル内から正しく参照されることを確認（代表的なスキルを1回実行）

## 注意事項

- **`${CLAUDE_PLUGIN_ROOT}` の動作**: Claude Code がプラグイン実行時に設定する環境変数。Bash コードブロック内では自動展開される。スキル body テキスト（Read 指示等）中の `${CLAUDE_PLUGIN_ROOT}` も Claude Code が展開してコンテキストに渡す。
- **allowed-tools frontmatter の env var 展開**: `${CLAUDE_PLUGIN_ROOT}/scripts/xxx.sh:*` のような env var 付きパスが allowed-tools で機能するかは、Claude Code のプラグイン env var 展開の仕様に依存する。実際のプラグイン実行でテストが必要（マージ後条件で確認）。
- **anthropics/claude-code#29360**: `--plugin-dir` 使用時に `allowed-tools` の MCP ツール名に名前空間プレフィックスが追加されるバグあり。影響が確認された場合は別 Issue で対応する。
- **`scripts/` → `bin/` リネーム**: `bin/` にリネームすると Claude Code プラグインが自動的に PATH に追加するが、本 Issue のスコープ外。別途 Issue で検討する。
- **plugin.json の追加フィールド**: `version`、`description` 等の追加フィールドが必要な場合は実装時に確認する。受け入れ条件は `name: "wholework"` のみを要求。
