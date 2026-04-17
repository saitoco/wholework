# Issue #241: Add retro/code label and /code follow-up Issue pattern

## Overview

`retro/verify` ラベルに倣い `retro/code` ラベルを新設する。`/code` 実装中にスコープ外と判断した remediation を follow-up Issue として追跡可能にし、`gh issue list --label retro/code` で一覧化できる運用を確立する。

変更内容:
- `scripts/setup-labels.sh` ALWAYS_LABELS に `retro/code` エントリ追加 (色 `5319E7`)
- `tests/setup-labels.bats` に `retro/code` テストケース追加・件数アサーション更新
- `skills/code/SKILL.md` Step 8 に follow-up Issue 作成サブセクション新設
- `docs/tech.md` / `docs/ja/tech.md` ラベルインベントリ更新 (11 → 12)

## Changed Files

- `scripts/setup-labels.sh`: add `retro/code|5319E7|Code retrospective follow-up` entry after `retro/verify` in ALWAYS_LABELS; update header comment (Always-group 11 → 12 labels, add `retro/code`) — bash 3.2+ compatible
- `tests/setup-labels.bats`: update always-group count assertions (11 → 12); add `label_created "retro/code"` to always-group non-phase test; update env=none total count assertion (28 → 29); update `--force` test mock output (add `echo "retro/code"`) and count assertions (11 → 12); update `--no-fallback` count assertion (11 → 12); update completion message count check (`"11"` → `"12"`)
- `skills/code/SKILL.md`: add `gh issue create:*` to Bash allowed-tools; add follow-up Issue creation sub-section to Step 8 (Implement)
- `docs/tech.md`: update Always-group row — count 11 → 12, add `` `retro/code` `` to label list
- `docs/ja/tech.md`: update 常時 group row — count 11 → 12, add `` `retro/code` `` to label list

## Implementation Steps

1. Update `scripts/setup-labels.sh`: add `"retro/code|5319E7|Code retrospective follow-up"` after the `retro/verify` line in ALWAYS_LABELS; update header comment L13 ("Always-group (11 labels):" → "(12 labels):", add "retro/code" to the list) (→ acceptance criteria 1, 2)

2. Update `tests/setup-labels.bats` (after 1): update 6 locations — (a) `env=full` count `-eq 11` → `-eq 12`; (b) add `label_created "retro/code"` after `label_created "retro/verify"` in always-group non-phase test; (c) `env=none` total count `-eq 28` → `-eq 29`; (d) `--force` mock: add `echo "retro/code"` before `echo "audit/drift"`, both `-eq 11` → `-eq 12`; (e) `--no-fallback` count `-eq 11` → `-eq 12`; (f) completion message check `"11"` → `"12"` (→ acceptance criteria 3)

3. Update `skills/code/SKILL.md` (parallel with 1, 2): (a) add `gh issue create:*` to the Bash allowed-tools frontmatter; (b) add follow-up Issue creation sub-section at the end of Step 8 (Implement), before Step 9 — document creation condition (scope-out remediations identified during implementation), command (`gh issue create --label "retro/code"` with title, background, purpose, acceptance conditions format), and policy (do not add `triaged`; assigned by `/triage` afterward) (→ acceptance criteria 4, 5)

4. Update `docs/tech.md` (parallel with 1, 2, 3): in `### Label Groups` table, change Always row — `| Always | 11 |` → `| Always | 12 |` and add `` `retro/code` `` after `` `retro/verify` `` in the label list (→ acceptance criteria 6, 7)

5. Update `docs/ja/tech.md` (parallel with 4): in ラベルグループ table, change 常時 row — `| 常時 | 11 |` → `| 常時 | 12 |` and add `` `retro/code` `` after `` `retro/verify` `` in the label list

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/setup-labels.sh" "retro/code" --> `scripts/setup-labels.sh` `ALWAYS_LABELS` に `retro/code` が追加されている
- <!-- verify: grep "retro/code.*5319E7" "scripts/setup-labels.sh" --> `retro/code` の色指定が `5319E7` で `retro/verify` と同系統
- <!-- verify: file_contains "tests/setup-labels.bats" "retro/code" --> `tests/setup-labels.bats` に `retro/code` のテストケースが追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "retro/code" --> `skills/code/SKILL.md` に `retro/code` ラベル付与を含む follow-up Issue 作成パターンが追加されている
- <!-- verify: file_contains "skills/code/SKILL.md" "gh issue create" --> `skills/code/SKILL.md` に `gh issue create` コマンドの明示的記述が追加されている
- <!-- verify: file_contains "docs/tech.md" "retro/code" --> `docs/tech.md` ラベルインベントリに `retro/code` が追加されている
- <!-- verify: section_contains "docs/tech.md" "## Labels" "12" --> `docs/tech.md` Always-group 件数が 11 → 12 に更新されている

### Post-merge

- 任意の `/code` 実行で follow-up Issue が生成された場合、`gh issue view N --json labels` で `retro/code` ラベルが確認できる
- `scripts/setup-labels.sh` を新規リポジトリで実行すると `retro/code` が自動作成される

## Notes

- `section_contains "docs/tech.md" "## Labels" "12"` — tech.md の実際の見出しは "## Wholework Label Management" であり "## Labels" とは完全一致しない。verify-executor は heading の部分一致マッチを使用するため "Labels" (複数形) が "Label Management" の "Label" と一致しない可能性がある。`/verify` 時に UNCERTAIN になった場合はポストマージ確認で補完すること。
- `docs/ja/tech.md` の更新はアクセプタンス基準に検証コマンドがないため自己チェックのみ。
- `retro/code` ラベルは setup-labels.sh の auto-bootstrap 機構 (gh-label-transition.sh 経由) により初回スキル実行時に自動作成される。SKILL.md に個別のラベル存在チェックは不要。

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- `section_contains "docs/tech.md" "## Labels" "12"` の verify command は Spec Notes 通り UNCERTAIN となった。実際の見出しは `## Wholework Label Management` であり、"Labels" (複数形) と部分一致しない。/verify 時にポストマージ確認で補完する予定。

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance condition 7 (`section_contains "docs/tech.md" "## Labels" "12"`) の verify command で `"## Labels"` が実際の見出し `"## Wholework Label Management"` と一致しない問題を Spec の Notes セクションで事前に警告していた。設計品質として適切な自己チェックが機能していた。

#### design
- 設計通りの実装。変更対象ファイルと手順が明確に定義されており、実装との乖離なし。

#### code
- パッチルート（直コミット）で実装。fixup/amend なし。`closes #241` による自動クローズが機能。

#### review
- パッチルートのため PR レビューなし。`retro/code` ラベル付与のような軽微な変更には適切な判断。

#### merge
- 直コミットによるパッチルート。コンフリクトなし。

#### verify
- 条件7の `section_contains "docs/tech.md" "## Labels" "12"` は Spec の予測通り直接実行できず、`grep` による代替検証で PASS 判定。`section_contains` の部分一致ロジックが `"Labels"` と `"Label Management"` を一致させない既知問題の再確認。
- 条件8（opportunistic）は `/code` の実際の実行が必要なため UNCERTAIN。これは想定内の結果。
- 自動検証対象（Pre-merge 7条件）はすべて PASS。

### Improvement Proposals
- `section_contains` verify command の見出し部分一致ロジックを改善し、`"## Labels"` が `"## Wholework Label Management"` にマッチするようサブストリング一致をサポートすること（現状は完全な見出しレベルでのマッチが要求されている可能性がある）。該当モジュール: `modules/verify-executor.md`
