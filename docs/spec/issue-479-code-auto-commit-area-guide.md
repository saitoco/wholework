# Issue #479: code: 外部ツールが非同期コミットする領域（Obsidian Git 等）の編集解釈をガイドライン化

## Overview

downstream プロジェクトの `/auto` 実運用で、`/code` が Spec Notes の「git commit 手順に含めない」という指示を「**ファイル自体を編集しない**」と誤解し、AC が FAIL するパターンが発生した。正しい解釈は「**編集は実装する・git add/commit は外部ツールに任せる**」であるが、`/code` のガイドラインに明文化されていなかった。

本 Issue では `skills/code/SKILL.md` の2箇所に外部ツール自動コミット領域の取り扱いガイドラインを追加する:
1. `## Notes` セクション — 一般ルールとして外部ツール自動コミット領域の扱いを明記
2. Step 5「Review notes section」— Spec Notes の推奨表現と標準解釈ガイドを追加

## Changed Files

- `skills/code/SKILL.md`: `## Notes` セクションに外部ツール自動コミット領域の一般ルールを追加; Step 5 "Review notes section" に Spec Notes 推奨表現の解釈ガイドを追加 — bash 3.2+ 互換なし（Markdown のみ）

## Implementation Steps

1. `skills/code/SKILL.md` の `## Notes` セクション末尾に以下の箇条書きを追加する (→ AC1, AC2):

   ```
   - **External auto-commit areas** (directories committed asynchronously by external tools such as Obsidian Git or IDE auto-commit): **edit the files** as required to satisfy ACs, but **skip `git add` / `git commit`** for those specific paths. The external tool handles committing. A Spec Notes instruction like "do not include in git commit procedure" is a commit-skip instruction only — not skip-implementation.
   ```

2. `skills/code/SKILL.md` の Step 5 `**Review notes section (only if present in Spec):**` ブロック末尾（Step 5 "Phase Handoff read" の前）に以下を追加する (→ AC1, AC2, AC3):

   ```
   **External auto-commit area interpretation:**

   When Spec Notes contains phrases such as the following, interpret as: **edit the files to implement the required changes; skip `git add` / `git commit` for those specific paths** (the external tool, e.g., Obsidian Git or IDE auto-commit, handles committing asynchronously):

   - "Do not include `<path>` in `git add`/`git commit` — external tool auto-commit area"
   - "Edit the file as required; skip `git add`/`git commit` for this path (external auto-commit)"
   - "External tool auto-commit area (e.g., Obsidian Git handles `vault/`)"

   These are commit-skip instructions, not skip-implementation instructions. The files must be edited to satisfy ACs.
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "/code の skill ガイドラインに、外部ツール自動コミット領域（vault/ 等）への変更で『編集は実装するが git add/commit はスキップする』という標準解釈が明文化されている" --> 外部ツール自動コミット領域の解釈が明文化されている
- <!-- verify: grep "auto-commit" "skills/code/SKILL.md" --> `skills/code/SKILL.md` に外部ツール自動コミット関連キーワードが存在する
- <!-- verify: rubric "Spec → /code への指示パターン（『git commit 手順に含めない』『編集はする』の表現）の推奨形式が例文付きで記載されている" --> Spec 表現パターンが標準化されている

### Post-merge

- 次回 vault 領域に触れる `/code` 実行で、ファイル編集が実装されること（commit は外部ツールに委ねる）を確認 <!-- verify-type: manual -->

## Notes

- Step 5 への追加位置: `**Review notes section (only if present in Spec):**` ブロック内 — 現在の末尾（"Skip this step if there is no "Notes" section." の後）に追加する。具体的には `**Phase Handoff read (after loading Spec):**` の直前に挿入する
- "auto-commit" キーワードを両箇所に明示的に含めることで AC2 `grep` を確実に PASS させる
- 姉妹 Issue #480（verify と外部ツール自動コミット領域の uncommitted 衝突）はスコープ外
- Spec Notes に「外部ツール自動コミット領域」と書く側（/spec）への追加は対象外（Issue の自動解決済み曖昧ポイントより）

## Code Retrospective

### Deviations from Design
- None — Spec の実装ステップ通りに2箇所（Step 5 と `## Notes`）を追加した

### Design Gaps/Ambiguities
- None — Spec の Notes に挿入位置が明確に指定されており（「`**Phase Handoff read (after loading Spec):**` の直前に挿入する」）、実装上の曖昧さはなかった

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `## Notes` セクションと Step 5 "Review notes section" の2箇所を変更対象とした（単一ルール + 消費側ガイドの分離）
- "auto-commit" キーワードを両ブロックに明示的に含め、grep AC が確実に通るよう設計した
- 追加テキストに半角 `!` は含まれていないことを確認（Forbidden Expression 回避済み）

### Deferred Items
- 姉妹 Issue #480（verify フェーズと外部ツール自動コミット領域の uncommitted 衝突）はスコープ外・未着手
- `/spec` 側への Spec Notes 推奨表現追加は Issue の自動解決済み曖昧ポイントにより対象外

### Notes for Next Phase
- verify phase は `rubric` 2件と `grep` 1件を実行する — rubric はセマンティック判定なのでモデルの解釈次第だが、実装内容は明確に「edit は必要・git add/commit はスキップ」を明記しており PASS が期待される
- Smoke Test セクションなし・Phase/ready ラベルなし（XS）のため verify コマンドのみ確認すればよい

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 2 rubric AC + 1 grep AC の構成。grep "auto-commit" でキーワード存在を確保し、rubric で意味検証する設計が機能。Size S → XS demotion 成功。

#### design
- Step 5 (Spec Notes 解釈) と Step 12.2 (commit) の 2 箇所に挿入で論理的に整合。例文 3 種が grader 解釈をサポート。

#### code
- 1 回の Edit で完了、rework なし。"auto-commit" を両ブロックに明示で grep AC 通過を確実化。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。worktree-merge-push.sh で main 直マージ成功。

#### verify
- Pre-merge 全 3 件 PASS。Post-merge manual は実 vault 領域での `/code` 実行待ちで `phase/verify` 維持。

### Improvement Proposals
- N/A

