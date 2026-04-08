# Issue #34: settings: Add .claude/settings.json for plugin self-hosting

## Issue Retrospective

### Ambiguity Resolution

- **`~/.claude/scripts/` パスの除外**: claude-config の settings.json には `scripts/` と `~/.claude/scripts/` の2系統が登録されていたが、プラグイン化により wholework 内 `scripts/` に統一されたため `~/.claude/scripts/` は不要と判断
- **`setup-labels.sh` / `test-skills.sh`**: スキルからの自動呼び出しがないため permissions.allow 不要と自動解決
- **`for n in *`**: claude-config 固有のパターンで wholework では使用されないため除外
- **`run-auto.sh`**: wholework に未存在。移植漏れとして別 Issue 対応をユーザーが選択

### Key Decisions

- PermissionRequest hook を含める（ユーザー選択）
- hook の command パスは `$CLAUDE_PROJECT_DIR/scripts/log-permission.sh` 形式（claude-config と同じ）

## Issue Refinement Retrospective

### Changes from Initial Issue

- **`json_field` → `grep` 変更**: `json_field ".claude/settings.json" ".hooks.PermissionRequest" "non-null"` を `grep "PermissionRequest"` に変更。`json_field` の `"non-null"` 比較は配列値に対して動作が不明確なため、より確実な `grep` に統一。
- **`run-auto.sh` 条件削除**: 会話中に `run-auto.sh` は実ファイルが存在しないゴミエントリと判明。`file_not_contains` 条件と Related Issues セクションを削除し、Auto-Resolved に事実を記録。
- **Triage 実行**: Type=Task, Priority=medium, Size=XS, Value=2 を設定。

### Ambiguity Auto-Resolution

- hook の command パスは実装裁量があるため受入条件化せず（Auto-Resolved に記録済み）
