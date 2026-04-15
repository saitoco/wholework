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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Verify command の escape artifact（`\\"` 等）が Issue 作成時に混入し、後から修正が必要になった。Issue Retrospective に記録済み。
- Section heading を `**Label assignment:**`（bold text）と誤認していた点が `/code` 時に発覚。`section_contains` は Markdown heading のみ対象のため、実際の heading (`### Step 5: Issue Generation`) に修正された。Spec 作成時により慎重に heading 種別を確認する必要がある。

#### design
- N/A（設計フェーズなし、XS スコープ）

#### code
- パッチルート（直接 main コミット）。`09cf274` の1コミットで完了。リワーク不要。
- Spec の Change Tracking に verify command heading 修正が記録されており、code フェーズでの品質確認が適切に機能した。

#### review
- PR なし（パッチルート）。コードレビューは実施されなかった。
- XS スコープのため影響範囲が限定的でリスクは低かった。

#### merge
- パッチルートで main 直接コミット。マージコンフリクトや CI 失敗なし。

#### verify
- 全3条件がPASS。`section_contains` と `file_contains` が正しく動作することを確認。
- Post-merge に `<!-- verify-type: manual -->` の未チェック条件が1件残存。将来の skill 追加時に `docs/tech.md` Forbidden Expressions が参照されることを手動で確認する必要がある。
- パッチルートのため PR チェックではなく `git log` での確認が主な手段となった。

### Improvement Proposals
- N/A
