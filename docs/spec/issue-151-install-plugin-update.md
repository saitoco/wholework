# Issue #151: install.sh に marketplace update と plugin update を統合

## Overview

`install.sh` に Claude Code CLI 経由の marketplace update と plugin update を追加し、開発マシン側の plugin 状態と `settings.json` を 1 コマンドで同期できるようにする。

現状の `install.sh` は `${HOME}` 展開による `settings.json` 生成のみ。追加する機能：
- `claude plugin marketplace update saitoco-wholework`（marketplace refresh）
- `claude plugin update wholework@saitoco-wholework`（plugin 更新）
- `--no-plugin` オプション（plugin 更新スキップ）
- `--marketplace NAME` オプション（marketplace 名の上書き）
- `command -v claude` チェックによる graceful skip（claude 不在時の異常終了を防止）
- 完了時に "Restart Claude Code" 案内を出力

後方互換：引数なし呼び出し（`./install.sh`）は従来と同様に動作。

## Changed Files

- `install.sh`: 引数パーサー追加 + plugin 更新ロジック追加 + 完了メッセージ変更
- `docs/structure.md`: `install.sh` の説明文（Directory Layout tree・"Why `./install.sh`?" 節）を新機能に合わせて更新

## Implementation Steps

1. `install.sh` に引数パーサーを追加（`MARKETPLACE=saitoco-wholework`, `NO_PLUGIN=false` をデフォルトとし、`--no-plugin` / `--marketplace NAME` を while ループで処理） (→ 受け入れ基準 3, 4)

2. `install.sh` の既存 settings.json 生成ロジック（`set -eu` 〜 `mv "$TMP_OUTPUT" "$OUTPUT"`）の後に、plugin 更新ブロックを追加：`NO_PLUGIN=false` のとき `command -v claude` を確認し、存在すれば `claude plugin marketplace update "$MARKETPLACE" || echo "Warning: ..."` および `claude plugin update "wholework@${MARKETPLACE}" || echo "Warning: ..."` を実行、不在時は warning を出力してスキップ (→ 受け入れ基準 1, 2, 5)

3. `install.sh` 末尾の完了メッセージに "Restart Claude Code" 案内行を追加（plugin 更新後は再起動が必要なため） (→ 受け入れ基準 6)

4. `docs/structure.md` の以下を更新（after 1-3）：
   - Directory Layout の `install.sh` 行コメント：`# Generate .claude/settings.json from template (run after clone)` → `# Sync settings.json, marketplace, and plugin (run after clone or pull)`
   - "Why `./install.sh`?" 節：新機能（marketplace update + plugin update）と `--no-plugin` オプションを追記 (→ ドキュメント整合性)

## Verification

### Pre-merge

- <!-- verify: file_contains "install.sh" "claude plugin marketplace update" --> `install.sh` が `claude plugin marketplace update` を実行するロジックを含む
- <!-- verify: file_contains "install.sh" "claude plugin update" --> `install.sh` が `claude plugin update` を実行するロジックを含む
- <!-- verify: file_contains "install.sh" "--no-plugin" --> `install.sh` が `--no-plugin` オプション (plugin 更新スキップ) をサポートしている
- <!-- verify: file_contains "install.sh" "--marketplace" --> `install.sh` が `--marketplace NAME` オプションで marketplace 名を差し替え可能
- <!-- verify: file_contains "install.sh" "command -v claude" --> `install.sh` が `claude` CLI 不在時に plugin 更新を graceful に skip する
- <!-- verify: file_contains "install.sh" "Restart Claude Code" --> `install.sh` 完了時に Claude Code 再起動必須の案内を出力する

### Post-merge

- wholework リポジトリで `./install.sh` を実行し、marketplace 更新 + plugin 更新 + settings.json 再生成がこの順序で完了することを確認
- `./install.sh --no-plugin` で plugin 更新がスキップされ settings.json のみ再生成されることを確認
- `claude` CLI をパス外にした状態で `./install.sh` を実行し、settings.json 再生成は成功、plugin 更新は warning 付きで skip されることを確認

## Notes

- `set -eu` を維持するため、plugin update は `|| echo "Warning: ..."` で囲みエラーを吸収する（片方失敗でも他方を実行する設計）
- `--marketplace NAME` のデフォルト値 `saitoco-wholework` は、Issue body の Auto-Resolved Ambiguity Points で確定済み
- plugin update 後の再起動は自動化しない（Issue body の Auto-Resolved: restart の自動化は行わず、メッセージで案内する方針）
- `docs/structure.md` の "Why `./install.sh`?" 節（line 188）は新機能について追記する（既存の `${HOME}` 展開説明は保持）

## Code Retrospective

### Deviations from Design

- N/A（Spec の実装手順をそのまま実施）

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Nothing to note. All 4 implementation steps in the Spec matched the PR diff exactly. The Code Retrospective also confirms no deviations.

### Recurring Issues

- Nothing to note. No repeated issue patterns observed. The change was a single-file shell script addition with clean separation of argument parsing and execution logic.

### Acceptance Criteria Verification Difficulty

- Nothing to note. All 6 pre-merge conditions used `file_contains` verify commands and resolved to PASS automatically. Verify command quality was high — no UNCERTAIN results occurred.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance conditions were clearly defined with `file_contains` verify commands covering all 6 functional requirements. No ambiguity in the conditions.
- Auto-Resolved Ambiguity Points in the issue body (default marketplace name, `claude` CLI absence behavior, restart policy) were well-documented, eliminating spec interpretation risk.

#### design
- Design matched implementation exactly per the Code Retrospective. No oversights or deviations were detected.
- The escape hatch approach (`--no-plugin`, `--marketplace NAME`, `command -v claude` guard) was well-designed for backward compatibility.

#### code
- No fixup/amend patterns in commit history. Single clean commit merged via PR #153.
- Implementation followed the 4-step spec plan precisely with no deviations.

#### review
- Review was effective. All pre-merge acceptance conditions were verifiable and passed. No missed issues.
- The review retrospective confirms no spec-vs-implementation divergences.

#### merge
- Clean squash merge via PR #153. No conflict markers or CI failures.

#### verify
- All 6 pre-merge conditions: PASS via `file_contains` verify commands.
- Post-merge 3 conditions: `verify-type: manual` with no verify commands — deferred to user verification as intended.
- Issue labeled `phase/verify` due to remaining unchecked manual conditions.

### Improvement Proposals
- N/A
