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

## Code Retrospective

### Deviations from Design
- N/A: 実装は Spec の実装ステップ 1 に完全に準拠。挿入位置（WHOLEWORK_SCRIPT_DIR ブロック後、Mermaid ブロック前）も Spec 指定通り。

### Design Gaps/Ambiguities
- 挿入ブロック内の引用形式（`> Pytest fixture...`）が Spec のテキストに含まれていたため、フォーマットの解釈が不要だった。Spec に完全なブロック内容が記載されていたのは実装容易性に有効だった。

### Rework
- N/A: テスト（bats 816件）・構文検証・禁止表現チェックすべて一発 PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec のステップ 1 をそのまま実装: WHOLEWORK_SCRIPT_DIR ブロックの直後に pytest fixture path check ブロックを挿入
- ブロック内容は Spec に記載された完全テキストを使用（変更なし）

### Deferred Items
- Post-merge AC（テスト追加 Issue で `/spec` 実行→ Spec Notes に `Path(__file__).parent` が記載されることを確認）は opportunistic verify として `/verify` フェーズに委ねる

### Notes for Next Phase
- 変更は `skills/spec/SKILL.md` の 1 ファイルのみ、6 行追加のみ
- 全 verify command PASS（file_contains / section_contains / rubric / command）
- bats 816 件全 PASS、構文検証・禁止表現チェック PASS

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| spec  | patch | SUCCESS | Spec 作成 commit |
| code (initial) | patch | FAILED (silent no-op) | run-code.sh exit 1, reconcile commits_found=false |
| code (retry)   | patch | SUCCESS | Tier 3 recovery action=retry で再実行、AC 全 PASS |
| verify | -    | SUCCESS | Pre-merge 全 3 件 PASS、Post-merge opportunistic SKIPPED |

### Orchestration Anomalies
- **Tier 3 recovery (retry) 成功**: 初回 code phase は silent no-op (Claude exited 0 but no commit) で wrapper exit 1。recovery sub-agent が `action=retry, rationale="working tree clean, single retry minimal safe recovery"` を返却し、再実行で正常 commit。記録は `docs/reports/orchestration-recoveries.md` の "2026-06-14 16:01 UTC: code-patch-tier3-recovery" 参照。

### Improvement Proposals
- N/A (recovery sub-agent + retry pattern が想定どおり機能した。Tier 3 recovery の効果実証ケース)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC1 (file_contains), AC2 (rubric + section_contains "Step 10" "pytest"), AC3 (command syntax check) の三段構成。file_contains は最小限の存在確認、rubric+section_contains は条件付き記述の意味検証、command は構文ガードと役割分担が明確。

#### design
- 既存 "WHOLEWORK_SCRIPT_DIR mock addition check" ブロック直後への挿入位置選定が適切。"test"/"pytest"/"fixture" キーワード検出条件付き適用で既存 Spec 挙動への影響なし。

#### code
- 初回 silent no-op → Tier 3 retry で成功という rework パターン。Tier 3 sub-agent の判断 "single retry is the minimal safe recovery" が妥当だった。最終的に bats 816 件 PASS。

#### review
- patch route のため非実行 (N/A)。

#### merge
- patch route のため非実行。worktree-merge-push.sh で main 直マージ成功。

#### verify
- Pre-merge 全 3 件 PASS、Post-merge opportunistic は `phase/verify` 維持で他 skill 実行時に検証。

### Improvement Proposals
- N/A

