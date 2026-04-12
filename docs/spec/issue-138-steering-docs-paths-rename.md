# Issue #138: refactor: STEERING_DOCS_PATHS 複数形変数を別名にリネームし命名衝突を解消

## Overview

`STEERING_DOCS_PATHS`（複数形、カンマ区切りファイルリスト）を `STEERING_DOCS_FILES` にリネームし、`STEERING_DOCS_PATH`（単数形、ディレクトリパス）との命名衝突を解消する。

変更対象は `skills/review/SKILL.md`（4箇所）と `skills/issue/SKILL.md`（1箇所）のみ。`modules/detect-config-markers.md` の `STEERING_DOCS_PATH`（単数形）は変更しない。

## Changed Files

- `skills/review/SKILL.md`: `STEERING_DOCS_PATHS` → `STEERING_DOCS_FILES`（4箇所: L286, L294, L326, L338）
- `skills/issue/SKILL.md`: `STEERING_DOCS_PATHS` → `STEERING_DOCS_FILES`（1箇所: L324）

## Implementation Steps

1. `skills/review/SKILL.md` の `STEERING_DOCS_PATHS` を `STEERING_DOCS_FILES` に一括置換（4箇所）（→ 受入基準1,3）
2. `skills/issue/SKILL.md` の `STEERING_DOCS_PATHS` を `STEERING_DOCS_FILES` に一括置換（1箇所）（→ 受入基準2,4）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/review/SKILL.md" "STEERING_DOCS_PATHS" --> `skills/review/SKILL.md` から `STEERING_DOCS_PATHS`（複数形）が削除されている
- <!-- verify: file_not_contains "skills/issue/SKILL.md" "STEERING_DOCS_PATHS" --> `skills/issue/SKILL.md` から `STEERING_DOCS_PATHS`（複数形）が削除されている
- <!-- verify: grep "STEERING_DOCS_FILES" "skills/review/SKILL.md" --> `skills/review/SKILL.md` で新名 `STEERING_DOCS_FILES` が使用されている
- <!-- verify: grep "STEERING_DOCS_FILES" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` で新名 `STEERING_DOCS_FILES` が使用されている
- <!-- verify: grep "STEERING_DOCS_PATH" "modules/detect-config-markers.md" --> `STEERING_DOCS_PATH`（単数、設定由来）は `modules/detect-config-markers.md` で引き続き定義されている
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> 変更後の全 SKILL.md が構文検証を PASS する

### Post-merge

- `/review` や `/issue` の実行時に Steering Documents が正しく渡される（ログ確認）

## Notes

- `skills/review/SKILL.md` の L178、L285、L325 にある `STEERING_DOCS_PATH`（単数形）は変更対象外
- `skills/issue/SKILL.md` の L26、L30、L31 にある `STEERING_DOCS_PATH`（単数形）は変更対象外
- `agents/*.md` に `STEERING_DOCS_PATHS` 参照なし（grep 確認済み）、更新不要
- ドキュメントファイル（README.md 等）に `STEERING_DOCS_PATHS` 参照なし、更新不要
- 後方互換性不要（内部変数、他プロジェクトへの影響なし）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件が全て verify コマンド付きで明確に定義されており、曖昧さなし
- Issue body 内の "Auto-Resolved Ambiguity Points" で agents/*.md の扱いと後方互換性を事前に文書化しており、実装時の判断コストがゼロ

#### design
- Spec が変更対象ファイル・行番号・箇所数まで明記しており、実装と完全に一致
- post-merge 検証条件（`/review` や `/issue` 実行時の動作確認）は verify コマンドなしのため自動化できない点は許容範囲内

#### code
- 単一パッチコミット `0f4bcbb`。fixup/amend なし、リワークなし
- Code Retrospective が全 N/A であることからも、設計通りのストレートな実装が確認できる

#### review
- パッチルートのため PR レビューなし。2ファイル・計5箇所のリネームのみという最小スコープにより妥当

#### merge
- パッチルートで main 直接コミット。コンフリクトなし

#### verify
- 6条件全て PASS。FAIL/UNCERTAIN ゼロ
- `command` 検証コマンド（`python3 scripts/validate-skill-syntax.py skills/`）も含め全自動検証が機能した

### Improvement Proposals
- N/A
