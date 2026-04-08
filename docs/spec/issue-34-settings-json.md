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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective にて `json_field` → `grep` への変更や `run-auto.sh` 条件削除など適切な受入条件の精査が行われた。受入条件は明確で自動検証可能な形式で記述されている。

#### design
- 設計フェーズは patch ルートのため省略。Issue Refinement Retrospective でスペックの変更点が適切に記録されている。

#### code
- 単一コミット `f293160` で実装完了。`.claude/settings.json`、`.gitignore`、`docs/structure.md` の3ファイルのみの変更でシンプル。リワークなし。

#### review
- patch ルート（size/XS）のため正式なレビューなし。受入条件が全8項目 PASS しており、実装品質に問題なし。

#### merge
- patch ルートにより main への直接コミット。PRなし。コンフリクトなし。

#### verify
- 全8条件 PASS。受入条件はすべて自動検証可能な `grep`/`file_exists` ヒントが付与されており、検証精度が高い。再実行時も全条件が確認できた。

### Improvement Proposals
- N/A
