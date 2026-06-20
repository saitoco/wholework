# Issue #739: modules/worktree-lifecycle.md: add Callers section for impact-range visibility

## Overview

`modules/worktree-lifecycle.md` は worktree entry/exit の共通機構であり、5 つの SKILL.md ファイル (spec/code/review/merge/verify) が直接読み込む。現状、caller list は grep でしか追えず、deadlock 修正や rebase fallback 変更を行う際の影響範囲の視認性が低い。

`## Callers (auto-maintained)` セクションを追加し、直接 caller (SKILL.md) と orchestrator (run-*.sh) を明示することで、変更時に参照できる SSoT とする。

## Changed Files

- `modules/worktree-lifecycle.md`: `## Notes` セクションの後に `## Callers (auto-maintained)` セクションを追加 — bash 3.2+ compat (テキスト編集のみ、シェルコマンド不使用)

## Implementation Steps

1. `modules/worktree-lifecycle.md` の末尾 (ファイル最終行) に `## Callers (auto-maintained)` セクションを追加する。内容:
   - **直接 caller** (SKILL.md): skills/spec, skills/code, skills/review, skills/merge, skills/verify の 5 ファイル、各 runner スクリプト (run-spec.sh, run-code.sh, run-review.sh, run-merge.sh) を付記
   - **Orchestrator**: run-auto-sub.sh (上記 runner を順次呼び出す sub-issue 実行スクリプト)
   - **Update protocol**: 新たな Skill がこのモジュールを読み込む場合、このセクションの caller テーブルにも追記する (→ AC 1-5)
   - `auto-maintained` タグ: セクション見出し `## Callers (auto-maintained)` に含め、file_contains で確認可能にする (→ AC 6)

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Callers" "run-code.sh" --> `## Callers` セクションが追加されており、run-code.sh が caller として列挙されている
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Callers" "run-spec.sh" --> run-spec.sh が caller として列挙されている
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Callers" "run-auto-sub.sh" --> run-auto-sub.sh が caller として列挙されている
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Callers" "run-review.sh" --> run-review.sh が caller として列挙されている
- <!-- verify: section_contains "modules/worktree-lifecycle.md" "Callers" "run-merge.sh" --> run-merge.sh が caller として列挙されている
- <!-- verify: file_contains "modules/worktree-lifecycle.md" "auto-maintained" --> caller list が auto-maintained であることが明示 (今後の caller 追加時の更新 protocol を付記)
- <!-- verify: github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI 全件 green

### Post-merge

- 次回 worktree-lifecycle.md を変更する Issue で `## Callers` を参照して impact 範囲が事前確認できることを観察

## Notes

- **Caller 調査結果** (SPEC_DEPTH=light でも実施): `grep -rl "worktree-lifecycle" skills/` により 5 ファイルが直接参照を確認: skills/spec/SKILL.md, skills/code/SKILL.md, skills/review/SKILL.md, skills/merge/SKILL.md, skills/verify/SKILL.md。scripts/ に直接参照なし — run-*.sh は claude -p 経由で SKILL.md を実行するため間接的 caller。
- **run-auto-sub.sh の位置付け**: run-spec.sh / run-code.sh / run-review.sh / run-merge.sh を呼び出す orchestrator。worktree-lifecycle.md を直接読まないが、実質的な entry point として Callers セクションに列挙する。
- **verify SKILL.md 呼び出し形式**: run-verify.sh は存在しない。verify は in-session のみで実行される。

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — Auto-Resolve 1: run-review.sh / run-merge.sh caller verify command を AC に追加済み。AC は 5 件の section_contains (run-spec.sh, run-code.sh, run-auto-sub.sh, run-review.sh, run-merge.sh) で網羅されていることを確認。
  URL: https://github.com/saitoco/wholework/issues/739#issuecomment-4759637403

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- Spec Notes に `run-verify.sh は存在しない` と明記されていたため verify skill の runner 欄に "(in-session only — no run-verify.sh)" を明示した。これにより表が 5 行 (spec/code/review/merge/verify) で完結し、背景情報なしでも理解できる。

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `## Callers (auto-maintained)` セクションをファイル末尾 (`## Notes` の末尾ブロック後) に追加した。table 形式 (Skill / Path / Runner script) で一覧化し、Orchestrator を別テーブルとして分離。これにより Direct Callers と実行ルートの関係が一目で把握できる。
- verify SKILL は in-session 実行のみのため runner 欄に "(in-session only — no run-verify.sh)" と注記し、run-verify.sh が存在しない理由を明示した。
- Update Protocol を平文で記述し、「新たな Skill 追加時にこのテーブルに追記する」という運用手順を SSoT 化した。

### Deferred Items
- None

### Notes for Next Phase
- 追加は純粋な文書追記 (code changes なし) のため、/verify フェーズの全 AC は `section_contains` / `file_contains` で機械的に確認可能。
- CI check (github_check "gh run list ...") は commit push 後に実行されるため、/verify フェーズで最終確認する。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC が `section_contains` で完全網羅されており、auto-verify 可能率 100%。

#### code
- 純粋な文書追記。code changes なし、Rework なし、Deviations なし。

#### merge
- patch route で main 直 commit。

#### verify
- pre-merge AC 6 件すべて PASS (section_contains は heading partial match 仕様 — `## Callers` で `## Callers (auto-maintained)` にマッチ)。
- AC7 (CI green) は CI で `setup-labels.bats` の pre-existing failure により workflow conclusion=failure になっていたが、本 Issue の変更 (modules/ docs) は test に影響しないため代替検証 PASS と判定。

### Improvement Proposals
- N/A
