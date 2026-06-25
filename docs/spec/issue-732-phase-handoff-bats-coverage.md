# Issue #732: test: add bats coverage for modules/phase-handoff.md

## Overview

`modules/phase-handoff.md` は cross-phase context carry-over の中核 module で、`spec`/`code`/`review`/`merge`/`verify` の各 phase が retrospective や Phase Handoff section を Spec に書き残す。dedicated test が存在しないため、phase ordering / handoff section detection の regression risk がある。

`tests/test-runner.bats` (#731) の shallow documentation test パターンに倣い、module の構造と契約用語の存在を確認する bats test を新規作成する。`modules/phase-handoff.md` は LLM 実行の手順書 (markdown module) であり実行可能スクリプトではないため、文書構造・write/read 契約・rotation 挙動の存在確認テストを採用する。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved 2 ambiguity points (AC2 verify command を 3 シナリオ別 grep に分割、AC4 `--commit=` 引数削除) — [issue comment](https://github.com/saitoco/wholework/issues/732#issuecomment-4804994158)

## Changed Files

- `tests/phase-handoff.bats`: new file — shallow documentation tests for `modules/phase-handoff.md` (bash 3.2+ compatible)
- `docs/structure.md`: update tests/ file count "(85 files)" → "(86 files)"
- `docs/ja/structure.md`: update "（85 ファイル）" → "（86 ファイル）" (translation sync per docs/translation-workflow.md)

## Implementation Steps

1. Create `tests/phase-handoff.bats` — follow the `tests/test-runner.bats` pattern with `PROJECT_ROOT` + module path setup. Add @test cases covering: (a) `## Purpose` section existence, (b) `## Write Procedure` section existence (→ `grep "@test.*write"` AC), (c) `## Read Procedure` section existence (→ `grep "@test.*read"` AC), (d) rotation boundary detection documentation (`rotation` keyword) (→ `grep "@test.*rotat"` AC), (e) Phase Handoff section format documentation (`<!-- phase:` marker), (f) Phase Position Asymmetry table existence. Each @test uses `grep -q "PATTERN" "$PHASE_HANDOFF"` form. (→ AC1-5)

2. Update file count in `docs/structure.md` and `docs/ja/structure.md`: "(85 files)" → "(86 files)" / "（85 ファイル）" → "（86 ファイル）" (→ SHOULD-level doc sync)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/phase-handoff.bats" --> `tests/phase-handoff.bats` が新規作成されている
- <!-- verify: grep "@test.*write" "tests/phase-handoff.bats" --> handoff write テストケースを含む (最低 1 件)
- <!-- verify: grep "@test.*read" "tests/phase-handoff.bats" --> handoff read テストケースを含む (最低 1 件)
- <!-- verify: grep "@test.*rotat" "tests/phase-handoff.bats" --> phase rotation テストケースを含む (最低 1 件)
- <!-- verify: command "bats tests/phase-handoff.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green
- <!-- verify: grep "(86 files)" "docs/structure.md" --> tests/ file count updated in structure.md
- <!-- verify: grep "86 ファイル" "docs/ja/structure.md" --> tests/ file count updated in Japanese structure.md

### Post-merge

- 次回 phase-handoff.md を変更する Issue で `bats tests/phase-handoff.bats` が regression を検出することを観察 <!-- verify-type: manual -->

## Notes

- **Shallow documentation test パターン**: `tests/test-runner.bats` と同じ方針 — LLM 実行 module の動作 mock は困難なため、文書構造・契約用語の存在確認で担保する
- **@test 名の命名方針**: verify command の `grep "@test.*write"` / `grep "@test.*read"` / `grep "@test.*rotat"` にマッチするよう、@test 名に "write" / "read" / "rotation" を含める
- **Pre-merge verification count**: 8 items (Issue 起票済み 6 + docs sync 2); light 上限 5 を超えるが、Issue 側 AC は変更不可のため Notes に記録して続行
- **AC pattern uncertainty**: `tests/phase-handoff.bats` は未作成のため、`grep "@test.*write"` 等は実装後に確定する。実装時は上記 @test 名命名方針に従うこと
- **Auto-Resolve Log** (Issue コメントより転記):
  1. AC2 verify command → 3 シナリオ別 grep に分割: `grep "@test.*write"` / `grep "@test.*read"` / `grep "@test.*rotat"`
  2. AC6 `--commit=` 引数削除 → `--limit=1` 標準形に変更 (merge commit 誤指定リスク回避)

## Code Retrospective

### Deviations from Design

- N/A — Spec implementation steps followed exactly. `tests/test-runner.bats` pattern applied without modification.

### Design Gaps/Ambiguities

- Spec Notes listed "AC pattern uncertainty" for @test name matching against `grep "@test.*write"` etc. — resolved cleanly by embedding "write", "read", "rotation" in @test names as specified.

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Followed shallow documentation test pattern from `tests/test-runner.bats` exactly: `PROJECT_ROOT` + module path setup, `grep -q` assertions on section headings and contract keywords.
- @test names designed to match AC verify commands (`grep "@test.*write"` / `grep "@test.*read"` / `grep "@test.*rotat"`).
- 6 @test cases cover: Purpose, Write Procedure, Read Procedure, rotation, `<!-- phase:` marker, Phase Position Asymmetry table.

### Deferred Items
- CI green verification (AC6: `github_check "gh run list --workflow=test.yml"`) deferred to post-push CI run.

### Notes for Next Phase
- All 7 locally-verifiable AC items confirmed PASS before commit.
- Patch route: merged directly to main via worktree-merge-push.sh; no PR needed.
- `bats tests/phase-handoff.bats` all 6 green locally.
