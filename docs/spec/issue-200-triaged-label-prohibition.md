# Issue #200: skills: Issue 作成時に triaged ラベル付与を禁止（/audit, /verify）

## Issue Retrospective

### 主要な変更
- **Verify command の escape artifact 除去**: 前回のheredoc 記法で発生した `\\\"` 等のエスケープ記号を削除し、 `section_contains` / `file_contains` が実際に動作する形式に修正
- **曖昧 Post-merge 条件の Pre-merge 化**: 「規約の所在が明確」という主観条件を、`docs/tech.md` Forbidden Expressions への具体的なエントリ追加という検証可能条件に変更

### 自動解決した曖昧性
- **規約の集約先**: 新規モジュール作成ではなく既存の `docs/tech.md` Forbidden Expressions セクションに追加する方針を採用（skill 横断規約の既存集約場所）

### Triage 結果
Type: Task / Size: XS / Priority: medium / Value: 3

### その他
Not planned for split (single-scope, XS)

## Change Tracking (by /code)

### Changes Made
- verify command 1 のヒントを修正: `section_contains "skills/audit/SKILL.md" "Label assignment" "triaged"` → `section_contains "skills/audit/SKILL.md" "Issue Generation" "triaged"` — `**Label assignment:**` が Markdown heading ではなく bold text のため `section_contains` がセクションを発見できなかった。実際の記述が含まれる heading `### Step 5: Issue Generation` を対象に変更した。
- Pre-merge チェックボックスを全件 PASS でチェック済みに更新
