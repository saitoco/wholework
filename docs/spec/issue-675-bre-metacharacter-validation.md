# Issue #675: Add BRE Metacharacter Validation to Issue/Spec Skills

## Overview

`/issue` および `/spec` スキルが `<!-- verify: grep "PATTERN" ... -->` の PATTERN 部分に BRE metacharacter (`\|`, `\(`, `\)`, `\+`, `\?`) を検出した場合に terminal に警告を出力し、ERE 形式への書き換え候補を提示する。

背景：grep verify command は ripgrep をデフォルトで使用しており、ERE (Extended Regular Expressions) として解釈される。BRE の `\|` は ERE では literal `|` となり OR alternation として機能しない。`/verify 666` のレトロスペクティブで発見され、#638 AC #3 でも同様の事例が確認されている。

## Changed Files

- `skills/issue/SKILL.md`: Step 4 の「Assign verify-type tags to post-merge conditions」の後に BRE metacharacter 検出ステップを追加
- `skills/spec/SKILL.md`: Step 10 の「Verification conditions vs. Issue body acceptance criteria consistency check」の後、「Patch route verify command check」の前に BRE metacharacter 検出ステップを追加

## Implementation Steps

1. `skills/issue/SKILL.md` Step 4 末尾（「Assign verify-type tags to post-merge conditions」の後）に **BRE metacharacter detection** サブステップを追加: 全 `<!-- verify: grep "PATTERN" ... -->` コマンドを抽出し、PATTERN に `\|`, `\(`, `\)`, `\+`, `\?` が含まれる場合は terminal に警告と ERE 書き換え候補を出力する (→ AC #1, AC #2, AC #4)

2. `skills/spec/SKILL.md` Step 10 の「Verification conditions vs. Issue body acceptance criteria consistency check」の後、「Patch route verify command check」の前に、同様の BRE metacharacter 検出サブステップを追加 (→ AC #3, AC #4)

## Verification

### Pre-merge

- <!-- verify: grep "BRE metacharacter" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` に BRE metacharacter 検出ロジックの記述が追加されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "ERE" --> `skills/issue/SKILL.md` に ERE への書き換え推奨ガイダンスが含まれる
- <!-- verify: grep "BRE metacharacter" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に BRE metacharacter 検出ロジックの記述が追加されている
- <!-- verify: rubric "skills/issue/SKILL.md および skills/spec/SKILL.md で、Issue body の verify command に含まれる grep pattern が BRE metacharacter (\\|, \\(, \\), \\+, \\?) を含むかを検出し、検出した場合に警告を出すロジックが定義されている" --> 両 skill に BRE 検出・警告ロジックが定義されている

### Post-merge

- 次回 `/issue` または `/spec` 実行で BRE pattern を含む verify command が AC に紛れた際、警告が表示されることを確認 <!-- verify-type: opportunistic -->

## Notes

- `skills/issue/SKILL.md` の Existing Issue フロー Step 6 は「Follow the full procedure defined in 'New Issue Creation → Step 4'」と記述されているため、Step 4 に追加すれば Existing Issue フローにも自動的に適用される。Step 6 への別途追記は不要。
- BRE metacharacter 検出対象は `\|`, `\(`, `\)`, `\+`, `\?` の5種類
- `skills/issue/SKILL.md` には現状 "ERE" という文字列が存在しない（grep 0 件）。実装で追加することで AC #2 を満たす。
- `skills/spec/SKILL.md` の "ERE" 4件はすべて `ENTERED_WORKTREE` の部分文字列であり、ERE (Extended Regular Expressions) の略語としては存在しない。実装で追加することで AC #3 の rubric 要件を補完する。
- 挿入テキストは「BRE metacharacter」「ERE」両方を含む必要がある（AC #1〜#3 の verify patterns を満たすため）

## Code Retrospective

### Deviations from Design

- None: Spec の実装ステップ通りに実装完了。挿入箇所・検出対象 metacharacter 5種・出力フォーマットすべて設計通り。

### Design Gaps/Ambiguities

- `skills/spec/SKILL.md` Notes に「"ERE" 4件はすべて ENTERED_WORKTREE の部分文字列」と記載されていたが、確認するとその通りであり、実装で追加した ERE 記述が AC #2 相当の要件を補完する形になった。Notes の予測が正確で、実装時に改めて確認の手間なく進められた。

### Rework

- None: 一発実装で bats 853 件全 PASS。skill syntax validation・forbidden expressions check も PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `skills/issue/SKILL.md` Step 4 末尾（verify-type タグ割り当ての直後）に BRE 検出サブステップを追加した。Existing Issue フロー（Step 6）は "Follow Step 4" 参照なので Step 4 への追加で自動適用される。
- `skills/spec/SKILL.md` は Step 10 の「Verification conditions consistency check」直後、「Patch route verify command check」直前に追加した。Spec 生成フローの verify command 確定後に検出する配置が最適。
- 検出対象は5種類の BRE metacharacter (`\|`, `\(`, `\)`, `\+`, `\?`) に限定した（Spec 指示通り）。

### Deferred Items
- post-merge の実際の挙動確認（`/issue` または `/spec` 実行で警告が出るか）は `verify-type: opportunistic` で次回実行時に観測。
- `/review` 時に rubric AC #4 の詳細判定が行われる。rubric grader には worktree 上の最新コンテンツを参照させること。

### Notes for Next Phase
- AC #1〜#3 は grep/file_contains で自動 PASS 確認済み（pre-merge チェックボックスも更新済み）。
- PR #682 でブランチは `worktree-code+issue-675` → base `main`。
- rubric AC #4 は `/review` の safe mode rubric grader が評価する。grader に `skills/issue/SKILL.md` と `skills/spec/SKILL.md` の内容を PR ブランチから読み込ませること（main branch との混同に注意）。
