# Issue #734: test: add bats coverage for scripts/validate-recovery-plan.sh safety checks

## Overview

`scripts/validate-recovery-plan.sh` validates recovery plan JSON produced by the Tier 3 orchestration-recovery sub-agent, checking schema correctness and safety constraints (required keys, action enum, forbidden ops, steps length limit). With no dedicated test file, future changes that inadvertently loosen validation logic cannot be caught as regressions. This Issue adds `tests/validate-recovery-plan.bats` to cover all 5 safety checks comprehensively.

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: auto-resolved 2 ambiguity points — (1) AC 2 verify commands split into 5 individual `file_contains`, (2) forbidden op scope limited to `op` field only / https://github.com/saitoco/wholework/issues/734#issuecomment-4759960920

## Changed Files

- `tests/validate-recovery-plan.bats`: new file — 6 @test cases covering all 5 safety checks (valid plan / missing required key / invalid action enum / forbidden op / steps limit exceeded / invalid JSON) — bash 3.2+ compatible (pure bats, no bash 4+ features)
- `docs/structure.md`: update `tests/` file count `(83 files)` → `(84 files)`
- `docs/ja/structure.md`: sync count update `（83 ファイル）` → `（84 ファイル）`

## Implementation Steps

1. Create `tests/validate-recovery-plan.bats` with the following 6 @test cases (→ all pre-merge ACs):
   - `@test "valid plan: all safety checks pass -> exit 0"` — submit minimal valid JSON (`action=skip`, `rationale`, `steps=[]`); assert `$status -eq 0`
   - `@test "missing required key: no action field -> exit 1"` — submit JSON without `action` key; assert `$status -ne 0`
   - `@test "action enum: unrecognized value -> exit 1"` — submit JSON with `action="destroy"`; assert `$status -ne 0`
   - `@test "forbidden op: force_push in op field -> exit 1"` — submit JSON with `steps[0].op="force_push"`; assert `$status -ne 0`
   - `@test "steps limit exceeded: 6 entries -> exit 1"` — submit JSON with 6-element `steps` array; assert `$status -ne 0`
   - `@test "invalid JSON: not parseable -> exit 1"` — submit non-JSON string; assert `$status -ne 0`

   Test design notes:
   - Use stdin input via `run bash "$SCRIPT" <<< '...'` — no temp file needed
   - No `WHOLEWORK_SCRIPT_DIR` mock required (script has no sibling script calls)
   - Script uses inline Python3; CI Ubuntu and macOS both have Python3 available
   - Script header confirms bash 3.2+ compatibility — test file must follow same constraint

2. Update `docs/structure.md`: change `(83 files)` → `(84 files)` in the `tests/` directory layout line

3. Update `docs/ja/structure.md`: change `（83 ファイル）` → `（84 ファイル）` in the `tests/` directory layout line

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/validate-recovery-plan.bats" --> direct test ファイルが新規作成されている
- <!-- verify: file_contains "tests/validate-recovery-plan.bats" "valid" --> valid plan を受け入れる @test が存在する
- <!-- verify: file_contains "tests/validate-recovery-plan.bats" "missing" --> required keys 欠落を拒否する @test が存在する
- <!-- verify: file_contains "tests/validate-recovery-plan.bats" "action" --> invalid action enum を拒否する @test が存在する
- <!-- verify: file_contains "tests/validate-recovery-plan.bats" "forbidden" --> forbidden op を拒否する @test が存在する
- <!-- verify: file_contains "tests/validate-recovery-plan.bats" "steps" --> steps 超過を拒否する @test が存在する
- <!-- verify: command "bats tests/validate-recovery-plan.bats" --> 追加した bats テストすべて green
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green

### Post-merge

- 次回 validate-recovery-plan.sh を変更する Issue で各 safety check の regression が test で検出されることを観察 <!-- verify-type: manual -->

## Notes

- **Auto-resolved ambiguity (Issue Retrospective, 2026-06-20)**:
  1. AC 2 verify command は 5 種 safety check 別の `file_contains` に分割 (valid, missing, action, forbidden, steps) — verify-patterns §1 に従い count-based check (`grep -c`, `wc -l`) は `/review` safe モードで UNCERTAIN になるため非採用
  2. "forbidden op" テストのスコープは `op` フィールドの forbidden ops リスト (`force_push`, `reset_hard`, `close_issue`, `merge_pr`, `direct_push_main`) のみ。`run_command` ステップの forbidden cmd patterns テストは追加カバレッジとして実装者の裁量に委ねる
- `validate-recovery-plan.sh` は sibling script を呼び出さないため、`WHOLEWORK_SCRIPT_DIR` mock 不要
- `docs/structure.md` の tests/ カウント更新は Key Files 維持規則に基づく (83→84)
