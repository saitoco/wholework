# Issue #750: environment-adaptation.md: Domain Files exhaustive 表に 2 ファイル追加 (spec-test-guidelines / skill-dev-verify-audit)

## Overview

`/audit drift` で検出された `docs/environment-adaptation.md` § Domain Files 表の exhaustive 主張と実態の差。表は "Domain Files (exhaustive)" と明示しているが、以下 2 ファイルが未掲載と報告された:

- `skills/issue/spec-test-guidelines.md` — `/issue` の AC verify command audit (spec test 設計)
- `skills/triage/skill-dev-verify-audit.md` — `/triage` の AC verify command audit

ただし、コードベース調査の結果、**両ファイルはすでに表に掲載済み** であることを確認した (詳細は Notes 参照)。実装は完了しており、/verify を直接実行して AC を確認するだけでよい。

## Changed Files

- なし (実装済み)

## Implementation Steps

1. /verify 750 を実行して AC をすべて確認する (→ 受け入れ条件 AC1〜AC4)

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/environment-adaptation.md" "spec-test-guidelines" --> spec-test-guidelines.md が表に追加されている
- <!-- verify: file_contains "docs/environment-adaptation.md" "skill-dev-verify-audit" --> skill-dev-verify-audit.md が表に追加されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "Domain Files" "spec-test-guidelines" --> Domain Files セクション配下に spec-test-guidelines.md が追加されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "Domain Files" "skill-dev-verify-audit" --> Domain Files セクション配下に skill-dev-verify-audit.md が追加されている

### Post-merge

- なし

## Consumed Comments

- saito / MEMBER / first-class / Issue retrospective: AC を grep → file_contains に変更 & 両ファイルはすでに表に掲載済みと確認 / https://github.com/saitoco/wholework/issues/750#issuecomment-

## Notes

**実装済み確認 (2026-06-27 コードベース調査):**

`docs/environment-adaptation.md` の Domain Files 表 (§ Layer 3) を調査した結果、両ファイルはすでに掲載済みであることを確認した:

- `skills/issue/spec-test-guidelines.md` — 行 148 に掲載 (Load Condition: `validate-skill-syntax.py` exists)
- `skills/triage/skill-dev-verify-audit.md` — 行 161 に掲載 (Load Condition: always (unconditional))

MEMBER コメント (saito, 2026-06-27) の通り:
- `spec-test-guidelines.md` は 2026-04-07 の初期 commit から掲載済み (Issue 作成前から存在)
- `skill-dev-verify-audit.md` は 2026-06-26 の commit 46d47d4 (#749) で追加済み

`/audit drift` の `spec-test-guidelines.md` 検出は false positive だった可能性が高い。

**AC verify コマンド変更 (MEMBER コメントより引用):**

issue 起票時の AC1/AC2 は `grep` 形式だったが、`verify-patterns.md` ガイドラインに従い `file_contains` に変更済み。本 Spec の Verification セクションは変更後の形式を採用している。

## Code Retrospective

### Deviations from Design

- 実装ステップ "1. /verify 750 を実行して AC をすべて確認する" は /code フェーズ内では /verify を直接呼び出せないため、verify-executor.md の手順に従い verify コマンドをインライン実行して AC PASS を確認した。実質的に同等の確認が完了しており、Spec の意図 (AC をすべて確認する) は達成されている。
- Changed Files が「なし」であるため Step 11 の implementation commit は不要と判断しスキップした。`closes #750` はリトロスペクティブコミットに付与する。

### Design Gaps/Ambiguities

- Spec の Implementation Steps が "/verify 750 を実行" という外部スキル呼び出し形式になっており、/code フェーズ内から呼び出せない。Spec 作成時に /code 実行手順として /verify 相当の verify-executor インライン実行を明記するとより明確になる。

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 実装変更なし。両ファイルはすでに `docs/environment-adaptation.md` の Domain Files 表に掲載済みであることを grep で確認した。
- AC 4 件すべて PASS (file_contains × 2、section_contains × 2)。Issue チェックボックスを更新済み。
- implementation commit をスキップし、リトロスペクティブコミットで `closes #750` を付与してクローズする。

### Deferred Items
- None

### Notes for Next Phase
- /verify フェーズでは verify コマンドを再実行すれば PASS が確認できる。実装変更がないため diff レビューは不要。
- Domain Files 表の行番号 (148, 161) は #749 以降変化している可能性があるため、実際の行番号でなくファイル名で検索すること。
