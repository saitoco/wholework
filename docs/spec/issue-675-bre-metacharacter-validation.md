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
<!-- phase: merge -->

### Key Decisions
- PR #682 は mergeable=true（CI success / review approved）でコンフリクトなし。スカッシュマージを即時実行。
- base branch は `main` なので `closes #675` による Issue 自動クローズが有効。
- 非インタラクティブモードで実行。AskUserQuestion なし、すべて自動解決。

### Deferred Items
- post-merge verify: opportunistic（次回 `/issue` または `/spec` 実行で BRE pattern 含む verify command が AC にあった際に警告が表示されるか観測）。
- CONSIDER: ERE リテラル `|` マッチ目的の verify command に対して誤検出警告が発生しうる（極めて稀、許容範囲）。

### Notes for Next Phase
- `/verify 675` を実行して post-merge verify command を確認すること。
- post-merge 条件は `verify-type: opportunistic` なので、verify skill 実行時に通常の verify command はなし（opportunistic フラグとして扱う）。
- 全 pre-merge AC は PR マージ前に PASS 確認済み。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. 実装は Spec の挿入箇所・内容・フォーマットを厳密に踏襲しており、逸脱なし。

### Recurring issues

Nothing to note. MUST/SHOULD 指摘なし。全4アスペクトでクリーンな実装。

### Acceptance criteria verification difficulty

Nothing to note. 4条件すべて auto-verified（PASS 3件、rubric PASS 1件）。UNCERTAIN なし。AC の verify command は適切に設計されており、`grep "BRE metacharacter"` が具体的で誤検出リスクが低い点も良好。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 設計品質は高い。AC #1〜#3 は具体的な文字列マッチ（"BRE metacharacter"）を要求し、誤検出リスクが低い。AC #4 の rubric は両 skill の論理定義を統合検証する適切な抽象度。
- Auto-Resolved Ambiguity Points が3件すべて妥当な判断（BRE → "BRE metacharacter" の false-PASS リスク回避、spec skill のスコープ追加、observation event=issue-create 不正 → opportunistic へ修正）で、verify phase で再検証する必要なし。

#### design
- Insertion point の判断（issue/SKILL.md Step 4 末尾、spec/SKILL.md Step 10 中段）が適切。Existing Issue フロー Step 6 が「Follow the full procedure defined in 'New Issue Creation → Step 4'」と書かれている点を Notes で明示しており、二重実装を未然に防いだ。

#### code
- 一発実装で bats 853 件全 PASS、skill syntax validation・forbidden expressions check も PASS。Rework なし。
- ただし code-pr phase で 1 回 Tier 3 recovery が発火（watchdog kill exit 143、worktree-code+issue-675 は空コミット状態）。retry で成功。これは API stall による transient hang と判断され、root cause は環境側にある（実装側の問題ではない）。

#### review
- light review で MUST/SHOULD 指摘なし、全 4 アスペクトでクリーン。Spec deviation なし。

#### merge
- PR #682 は mergeable=true でスカッシュマージ即時実行。コンフリクトなし。
- ただし `docs/reports/orchestration-recoveries.md` の追記が code-pr phase recovery 後に未コミットのまま残り、parent session が `/verify 675` 実行時に手動コミット（commit `8cb82e6`）。これは #677 で追跡中の既知の batch-route recovery log auto-commit gap。

#### verify
- 全 pre-merge AC（4/4）PASS。`grep "BRE metacharacter"` パターンが false-PASS リスクなく動作。rubric も両 skill の整合性を正しく検証。
- post-merge AC（1件、opportunistic）は次回 `/issue` または `/spec` 実行時に観測予定。`phase/verify` 維持。
- verify command の品質は高い：AC #1/#3 は line 176-192（issue）/461-477（spec）で具体的に matched、AC #2 は `file_contains "ERE"` で 5 occurrences matched、AC #4 rubric は両 skill の論理定義の存在を正しく検出。

### Improvement Proposals

- N/A — 本 Issue 自身が verify command 起票時バリデーション（BRE 検出）の改善を実装したものであり、本 verify phase での追加改善提案は不要。
- 関連既存 Issue: #677（batch-route recovery log auto-commit gap）は merge phase で再観測されたが既起票済み、追加対応不要。
