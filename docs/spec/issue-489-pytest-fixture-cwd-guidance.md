# Issue #489: spec: pytest fixture ファイルの CWD 非依存パスガイダンスを Step 10 に追加

## Overview

`/wholework:spec` が生成する Spec の Notes セクションに、pytest fixture ファイル参照の CWD 独立化パターン（`Path(__file__).parent / "fixtures" / "..."`）に関するガイドラインが欠けている。これにより `/code` 実装フェーズで CWD 相対パスが使われ、worktree 環境などで `FileNotFoundError` が発生する rework が生じていた。

`skills/spec/SKILL.md` の Step 10 に、テスト追加系 Issue（pytest / fixture キーワードを含む）を検出した場合に Spec Notes へ上記パターンを記載するよう促す条件付きガイダンスを追加する。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の WHOLEWORK_SCRIPT_DIR mock addition check ブロックの後に「**pytest fixture path CWD independence check**」ブロックを追加

## Implementation Steps

1. `skills/spec/SKILL.md` の `### Step 10: Create Spec` 内、「WHOLEWORK_SCRIPT_DIR mock addition check」ブロック（If implementation steps include adding a new script... の段落）の直後（"**Mermaid diagram node ID naming check:**" の前）に以下のブロックを挿入する（→ 受入条件 1, 2）：

```
**pytest fixture path CWD independence check:**

When the Issue involves adding pytest tests that reference fixture files (detected by "test", "pytest", or "fixture" keywords in the Issue title/body, or when Acceptance Criteria describe pytest fixture file access), add the following note to the Spec's Notes section:

> Pytest fixture file references must use `Path(__file__).parent / "fixtures" / "file"` (not CWD-relative paths like `Path("tests/fixtures/file")`). This ensures the test works regardless of the working directory at pytest invocation time — required in worktree environments and when pytest is run from a directory other than the repository root.
```

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/spec/SKILL.md" "Path(__file__).parent" --> `skills/spec/SKILL.md` に、pytest fixture ファイルを使うテスト追加 Issue の場合に Spec Notes へ `Path(__file__).parent` パターンを記載するガイダンスが追加される
- <!-- verify: rubric "skills/spec/SKILL.md の pytest fixture path ガイダンスが、pytest や fixture ファイルを含む Issue の場合にのみ適用される条件付き記述であり、非テスト系 Issue のデフォルト処理フローに追加処理が挿入されていない" --> <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 10: Create Spec" "pytest" --> 既存の非テスト系 Spec の挙動には影響しない（後方互換）
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/spec/SKILL.md" --> `skills/spec/SKILL.md` の構文検証（半角 `!` 検出、frontmatter 検証）が通る

### Post-merge

- テスト追加 Issue で `/spec` を実行し、Spec Notes に `Path(__file__).parent` パターンが記載されることを確認（opportunistic）

## Notes

- 挿入位置は "WHOLEWORK_SCRIPT_DIR mock addition check" ブロックの直後、"Mermaid diagram node ID naming check:" の前。周辺コンテキスト（"If implementation steps include adding a new script..."）を使って特定する
- 適用条件はキーワードベース（"test"/"pytest"/"fixture" を Issue title/body に含む、またはAC に pytest fixture アクセスが記述されている場合）— 非テスト系 Issue には影響しない
- 対象言語スコープ: Python pytest のみ
- Step 10 の簡潔性ルール（light: 実装ステップ 5 以内、検証項目 5 以内）を遵守
