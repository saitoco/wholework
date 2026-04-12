# Issue #141: workflow: /verify FAIL 由来の post-verify fix cycle を Size 保持のまま skill 経路で流す

## Overview

`/verify` で FAIL した Issue の修正サイクルを skill 経路で流すための `fix-cycle` 機構を導入する。`/verify` Step 9 で FAIL 検出時に `fix-cycle` ラベルを付与し、`/code` と `/auto` がこのラベルを検出したら **元 Size に関わらず patch route を強制**する。さらに `/code` は実装コミット後に Spec へ `## Post-verify fix` セクションを append し、fix cycle の判断根拠を cross-phase memory として記録する。Size は `get-issue-size.sh` の既存二層ルックアップ(Project field → `size/*` label)で reopen を跨いで保持されるため新規機構は不要。ラベルは `phase/*` 名前空間に含めないことで `gh-label-transition.sh` の PHASE_LABELS (L13) に非干渉とし、既存の phase 状態機械を壊さない。

## Changed Files

- `scripts/setup-labels.sh`: LABELS 配列 (L13–24) に `fix-cycle|#c5def5|Post-verify fix cycle marker — preserves original Size while routing through patch` エントリを追加 (11 番目、末尾)
- `tests/setup-labels.bats`: "creates 10 labels" テスト (L28) の期待値を 11 に更新、ラベル名リストテスト (L44) に `fix-cycle` を追加
- `skills/verify/SKILL.md`: Step 9 (L295–299) の `gh issue reopen` 直後、`gh-label-transition.sh` 呼び出しの前に `gh issue edit "$NUMBER" --add-label "fix-cycle"` を idempotent に追加。`gh label create fix-cycle` フォールバックを同ブロックで記述 (`retro/verify` 付与と同型パターン)
- `skills/code/SKILL.md`: Step 0 route detection (L76–89) の先頭に「Fix-cycle Detection」サブセクションを挿入。`gh issue view $NUMBER --json state,labels` で `(state==OPEN) && (fix-cycle label present)` を検出したら ROUTE=patch を強制し、XL guard / phase/ready チェック / Size-based routing をスキップ。`--patch`/`--pr` 明示時は検出をスキップ(ユーザ意図優先)。Step 10 (commit 直後、push 前) に `## Post-verify fix` セクション append ロジックを追加
- `skills/auto/SKILL.md`: Step 3 先頭に Fix-cycle Pre-check を挿入。fix-cycle ラベル検出時は phase/* 判定より前に ROUTE=patch で run-code.sh --patch に直行し XL sub-issue graph 展開をバイパス。Step 4 XL route の `get-sub-issue-graph.sh` 呼び出し (L94) 前にも防御的チェックを追加
- `skills/spec/SKILL.md`: Step 10 full template の Task テンプレ直後に `## Post-verify fix` セクション定義を追加(Spec 構造の SSoT として)。フォーマット: `### Fix Cycle N` サブセクション + `- **対象 AC**:` / `- **修正内容**:` / `- **コミット**: <sha>` / `- **判断根拠**:` の 4 項目
- `modules/size-workflow-table.md`: Option System 表 (L64–72) の `/code` 行を維持した上で、新セクション "Fix-cycle Override" を Size-to-Workflow Mapping (L44–52) の直後に追加。「fix-cycle label present → patch route (Size 無関係)」を明記
- `docs/workflow.md`: Label Transition Map (L123–132) に `fix-cycle` 行を追加(`Assigned by: /verify (on FAIL)`、`Removed by: (manual / future cleanup)`)。"Details" セクション末尾に "Post-verify fix cycle" 節を追加し、reopen → fix-cycle label → `/code --patch` または `/auto` → `/verify` の流れを説明
- `docs/product.md`: Terms テーブル (L156–179) に `Fix cycle` エントリをアルファベット順で挿入(Drift と Fork context の間、または Domain file 直後)。定義: "A post-verify modification cycle for an Issue marked with the `fix-cycle` label. Preserves the original Size metadata and routes through patch to avoid polluting Size-based throughput analysis" / Context: `/verify`, `/code` / 日本語訳: Fix cycle
- `modules/next-action-guide.md`: L57 の `verify | fail` 行の Recommended action 文言は据え置き (`/code {ISSUE_NUMBER}` のまま、内部で fix-cycle 検出)。コメント列に "fix-cycle label auto-applied by /verify" を追記

## Implementation Steps

**Step recording rules followed**: integer step numbers, dependency notation, AC mapping, context-based insertion.

1. `scripts/setup-labels.sh` の LABELS 配列末尾に `"fix-cycle|#c5def5|Post-verify fix cycle marker — preserves original Size while routing through patch"` を追加。同時に `tests/setup-labels.bats` の "creates 10 labels" アサートを 11 に、label-names 列挙テストに `fix-cycle` を加える (→ 受入条件 #5, #10)
2. `skills/verify/SKILL.md` Step 9 (L295–299) で `gh issue reopen "$NUMBER"` 直後、`gh-label-transition.sh` 呼び出し前に以下を挿入: `gh label list --search fix-cycle | grep -q '^fix-cycle' || gh label create fix-cycle --color c5def5 --description "Post-verify fix cycle marker"` その後 `gh issue edit "$NUMBER" --add-label "fix-cycle"` を呼ぶ。冪等性: `--add-label` は既存ラベル付与済みなら no-op (after 1) (→ 受入条件 #2)
3. `scripts/gh-label-transition.sh` の PHASE_LABELS (L13) は **変更しない**。変更しないことを verify 条件で保証 (→ 受入条件 #6)
4. `skills/code/SKILL.md` Step 0 (L76–89) の先頭に「### Step 0.5: Fix-cycle Detection」相当のサブセクション追加。ただし decimal step 禁止制約のため実装は **Step 1 として挿入し既存 Step を後ろ倒し**。新 Step 1 内容: `gh issue view $NUMBER --json state,labels -q '{state,labels:[.labels[].name]}'` 取得 → `state=="OPEN" && labels has "fix-cycle" && ARGS に --patch/--pr が無い` なら `ROUTE=patch` 強制、後続の Size / XL / phase/ready チェックをスキップ (parallel with 2) (→ 受入条件 #1)
5. `skills/code/SKILL.md` Step 10 (commit 直後、push 前) に `## Post-verify fix` append ロジックを追加。Spec 存在時: `grep -q "^## Post-verify fix" $SPEC_PATH` で既存確認 → 既存時は `### Fix Cycle N` 連番サブセクション、初回時は `## Post-verify fix` 新規セクションを Edit tool で append。記録項目: 対象 AC / 修正内容サマリ / コミット sha / 判断根拠。Spec 不在時は warning 出してスキップ。追加コミット: `git commit -m "Add post-verify fix log for issue #$NUMBER"` (after 4) (→ 受入条件 #1, Post-merge #2)
6. `skills/auto/SKILL.md` Step 3 の先頭に Fix-cycle Pre-check を追加。`gh issue view $NUMBER --json state,labels` で fix-cycle ラベル + OPEN 検出時、phase/* 判定をスキップして `run-code.sh $NUMBER --patch` に直行 (XL sub-issue graph 展開バイパス)。また Step 4 XL route の `get-sub-issue-graph.sh` 呼び出し (L94) 前にも同じ防御的チェックを追加 (parallel with 5) (→ 受入条件 #3)
7. `skills/spec/SKILL.md` Step 10 full テンプレ内の Task テンプレ直後に `## Post-verify fix` セクション仕様を追加。フォーマット例を記述: `### Fix Cycle 1 / **対象 AC**: #3 / **修正内容**: Terms テーブルに Domain file エントリ追加 / **コミット**: 93b671b / **判断根拠**: cross-cutting AC の単純な 1 行追加` (after 5) (→ 受入条件 #4)
8. `modules/size-workflow-table.md` に "Fix-cycle Override" セクションを Size-to-Workflow Mapping Table 直後 (既存 L52 直後) に新規追加。内容: "When an Issue has the `fix-cycle` label and is OPEN, the route resolves to `patch` regardless of Size. This override is scoped to post-verify fix cycles and does not affect XL split guidance for new work." (parallel with 7) (→ 受入条件 #9)
9. `docs/workflow.md` Label Transition Map (L123–132) に `fix-cycle` 行を追加 (`Assigned by: /verify (on FAIL)`, `Removed by: (manual)`)。Details セクションに "Post-verify fix cycle" 節を追加 (reopen → ラベル付与 → `/code --patch` 自動経路 → `/verify` の流れと、元 Size が保持される点を明記)。同時に `modules/next-action-guide.md` L57 行のコメント列に "fix-cycle label auto-applied by /verify" 追記 (parallel with 7, 8) (→ 受入条件 #7)
10. `docs/product.md` Terms テーブル (L156–179) に "Fix cycle" エントリをアルファベット順で挿入(Drift と Fork context の間を想定)。定義/Context/日本語訳を記述 (parallel with 7, 8, 9) (→ 受入条件 #8)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/code/SKILL.md" "fix-cycle" --> `/code` SKILL.md に fix-cycle 検出分岐が記述されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "fix-cycle" --> `/verify` SKILL.md に FAIL 時の `fix-cycle` ラベル付与処理が記載されている
- <!-- verify: file_contains "skills/auto/SKILL.md" "fix-cycle" --> `/auto` SKILL.md に XL bypass の fix-cycle 分岐が記載されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "Post-verify fix" --> `/spec` SKILL.md に `## Post-verify fix` セクション仕様が記述されている
- <!-- verify: file_contains "scripts/setup-labels.sh" "fix-cycle" --> `setup-labels.sh` に `fix-cycle` ラベル定義が追加されている
- <!-- verify: file_not_contains "scripts/gh-label-transition.sh" "fix-cycle" --> `gh-label-transition.sh` は `fix-cycle` を触らない (`PHASE_LABELS` 非含有、変更なし)
- <!-- verify: file_contains "docs/workflow.md" "fix-cycle" --> `docs/workflow.md` の Label Transition Map に `fix-cycle` が記載されている
- <!-- verify: file_contains "docs/product.md" "Fix cycle" --> `docs/product.md` Terms テーブルに "Fix cycle" エントリが追加されている
- <!-- verify: file_contains "modules/size-workflow-table.md" "fix-cycle" --> `size-workflow-table.md` に fix-cycle routing 記述が追加されている
- <!-- verify: command "bash tests/setup-labels.bats" --> `tests/setup-labels.bats` が PASS (新ラベル追加 regression なし)

### Post-merge

- 実際に reopen 状態の XL Issue で `/code N` を実行し、`fix-cycle` ラベル検出により Size=XL 保持のまま patch route で修正コミットされる
- 該当 Issue の Spec に `## Post-verify fix` セクションが append されている
- `/audit stats` の Outcome セクションで fix cycle を経た Issue が `First-try success=false` / `Completed=true` として分類される
- 既存の reopen + label 無し Issue で `/code N` を実行し従来どおりの Size-based routing が動作する(下位互換)

## Tool Dependencies

### Bash Command Patterns
- `gh label create:*`: `fix-cycle` ラベル作成フォールバック(既に `/verify` の allowed-tools で `gh label create:*` 認可済み、新規追加不要)
- `gh label list:*`: fix-cycle ラベル存在確認。`/verify` allowed-tools に **未認可のため追加必要**
- `gh issue edit:*`: fix-cycle ラベル付与(既に allowed-tools で認可済み)
- `gh issue view:*`: state + labels 取得(既に各 SKILL で認可済み)

### Built-in Tools
- `Read`, `Edit`, `Write`, `Grep`, `Glob`: 既存許可
- Additional permissions for this Issue: **`gh label list:*` を `skills/verify/SKILL.md` allowed-tools に追加**

### MCP Tools
- none

## Notes

### Auto-Resolved Ambiguity Points

- **patch→PR フォールバック閾値**: 閾値制御は導入しない方針に変更。理由: FAIL 件数が多い場合でも patch で複数 commit 積めば対応可能、閾値ロジックは実装複雑度の割に使用頻度が低い。代わりにユーザが `--pr` フラグで明示上書きできる運用とする。
- **`/auto` fix-cycle 自動ループ可否**: 現行の `skills/auto/SKILL.md` L294 "verify FAIL is auto stop" 方針を維持。fix-cycle 検出で `/auto N` を再実行した場合のみ fix 経路が走る(ユーザ明示呼び出しまでで停止)。無限ループを防ぐための安全弁。
- **`/audit stats` Work Origin に fix-cycle segment 追加**: 不要。fix-cycle は Work Origin (Issue 由来) ではなく state (reopen 後の状態) のため既存分類(audit/drift / audit/fragility / retrospective / manual)と直交。First-try success rate は既存の reopen history 検出で fix cycle を経た Issue を正しく分類可能(reopen されているため自動的に First-try=false)。
- **Spec の `## Post-verify fix` フォーマット**: `### Fix Cycle N` 連番サブセクション採用。記録項目は 4 固定(対象 AC / 修正内容 / コミット sha / 判断根拠)。理由: 複数回の FAIL→fix サイクル発生時に重複セクション生成を避けつつ時系列で追えるようにするため。
- **fix-cycle ラベル検出タイミング**: `--patch`/`--pr` 明示フラグ時はスキップ。ユーザ意図を silent に上書きしないため。
- **Spec 不在時の append 挙動**: warning 出してスキップ。既存 `/code` Step 5 の「no Spec」分岐と整合。

### 実装上の注意

- **decimal step number 禁止制約**: `/code` SKILL.md に fix-cycle 検出を Step 0 と Step 1 の間に挿入する際、`Step 0.5` は MUST 制約違反 (`validate-skill-syntax.py` で検出される)。既存 Step を 1 つずつ後ろ倒して integer step を維持する必要あり。Step 10 付近の Post-verify fix append も同様。
- **`gh-label-transition.sh` 無変更の保証**: Pre-merge verify `file_not_contains "fix-cycle"` で静的に保証。implementation で `gh-label-transition.sh` を誤って編集しない運用規律が必須。
- **ラベル作成の idempotent パターン**: `gh label list --search | grep -q || gh label create` は `retro/verify` 追加時 (#76, #95) と同型。fix-cycle も同パターンで実装。
- **bats test の期待値**: setup-labels.bats の "creates 10 labels" は単純な count アサート。11 に更新するだけで regression は発生しないが、完全パスの確認のため明示的な bats 実行を pre-merge AC に含めた。
- **`tests/run-code.bats` / `tests/run-verify.bats`** への fix-cycle シナリオ追加は **本 Issue のスコープ外**(optional)。新経路の回帰検知は Post-merge AC #1 (実運用の XL Issue で patch 動作確認) でカバー。将来的に bats テスト追加 Issue を別途切る。

### Docs/ja translation

- `docs/ja/workflow.md` / `docs/ja/product.md` は `/doc translate ja` による自動生成。本 Spec の Changed Files には含めない(verify retrospective #135 Spec と同判断)。

### Codebase investigation summary (agent 調査結果)

| Item | Location |
|------|----------|
| `/verify` FAIL → reopen | `skills/verify/SKILL.md` L295–299 |
| `/code` Size/phase/ready/XL guard | `skills/code/SKILL.md` L66–89, L113–123 |
| `/auto` XL sub-issue graph | `skills/auto/SKILL.md` L94 |
| `/auto` no-phase → run-issue.sh | `skills/auto/SKILL.md` L66–78 |
| `setup-labels.sh` LABELS 配列 | `scripts/setup-labels.sh` L13–24 |
| `gh-label-transition.sh` PHASE_LABELS | `scripts/gh-label-transition.sh` L13 (変更なし) |
| `get-issue-size.sh` 二層ルックアップ | `scripts/get-issue-size.sh` L32–65 (reopen 耐性あり、変更なし) |
| `size-workflow-table.md` Mapping | `modules/size-workflow-table.md` L44–52, L64–72 |
| `docs/workflow.md` Label Transition Map | L123–132 |
| `docs/product.md` Terms | L156–179 |
| `next-action-guide.md` verify FAIL 行 | L57 |
| Spec append テンプレ (`/auto` Steps 4a/4b) | `skills/auto/SKILL.md` L189–196, L236–243 |
| 既存 `## Post-verify fix` 出現 | ゼロ (新規) |
