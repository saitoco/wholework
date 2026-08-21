# Issue #1241: size-workflow-table: XL 分割後も親が集約成果物を持つパターンの経路を定義

## Overview

XL Issue の Pre-merge AC が `rubric` 型で、かつ複数 sub-issue を横断する集約成果物 (例: 集約レポート、fan-out 前の baseline 計測) を必要とする場合、`modules/size-workflow-table.md` (XL 行: Verify "—"、追跡専用が前提) と `skills/auto/SKILL.md` の XL route (親自身の `/code` を回す経路を持たない) の間に齟齬がある。#1158 (fan-out 後の集約が欠落) と #1270 (fan-out 前の前提作業が欠落・回復不可) の 2 件で顕在化した。

対応方針は Issue 本文が提示する A / A' / B / C から選択する。本 Spec では **方針 C (前提作業・集約作業をいずれも level-0/依存先の sub-issue としてモデル化し、`blocked_by` で fan-out 内の順序を機械的に保証する)** を採用する。理由は `## Notes` の方針比較を参照。

## Changed Files

- `modules/size-workflow-table.md`: `### Size-to-Workflow Mapping Table` 直後 (`### ALWAYS_PR Override` の直前) に `#### XL Parent Aggregate Deliverables (集約成果物)` 節を追加し、集約成果物を親の Changed Files ではなく sub-issue 側 (`blocked_by` 配置) で扱う経路を明記する
- `skills/auto/SKILL.md`: `### Step 4d: XL Sub-issue Verify (XL route only)` セクション末尾 (`### Step 4c: XL Parent Issue Close Flow (XL route only)` 見出し直前) に、親が集約成果物を要する場合の sub-issue 化ガイダンスを追加する
- [Steering Docs sync candidate] keyword "size-workflow-table.md" skipped: matched 46 files (no discriminating power)
- [Steering Docs sync candidate] keyword "auto" (bare skill name) skipped: matched 948 files (no discriminating power)

## Implementation Steps

1. `modules/size-workflow-table.md` の `### Size-to-Workflow Mapping Table` 表の直後、`### ALWAYS_PR Override` 見出しの直前に、以下相当の `####` 節を追加する (`###` ではなく `####` にすること — `section_contains` の検証対象が `### Size-to-Workflow Mapping Table` 節のスコープ内に留まるようにするため、同格以上の見出しで節を終端させない):

   ```markdown
   #### XL Parent Aggregate Deliverables (集約成果物)

   The XL row's Verify column ("—") assumes the parent Issue stays tracking-only, with an empty `## Changed Files`. A design that gives the XL parent its own cross-cutting `rubric` Pre-merge acceptance condition — one that needs an aggregate artifact (集約成果物), such as a report synthesizing sibling sub-issue outputs, or a baseline measurement that must predate the fan-out — breaks that assumption, since the XL route has no parent-level code phase to produce the artifact (see Issue #1158, #1270).

   Do not add the artifact to the parent's own Changed Files. Instead, model the artifact-producing work as an ordinary sub-issue placed in the dependency graph via `blocked_by` (`docs/guide/xl-decomposition.md`), and move the corresponding acceptance condition — including its `rubric`/`file_*` verify command, naming the sub-issue's own output file per `modules/verify-executor.md` § "Primary evidence outside git diff / Issue body" — onto that sub-issue's own Issue body:

   - **Post-fan-out aggregation** (#1158-type: the artifact synthesizes sibling sub-issue outputs, needed only after they land): create a sub-issue `blocked_by` every domain sub-issue it aggregates, so it runs in the dependency graph's last level.
   - **Pre-fan-out prerequisite** (#1270-type: the artifact must exist, unmodified, before any domain sub-issue starts): create a sub-issue with no `blocked_by` (level 0), and make every domain sub-issue `blocked_by` it, so it completes first.

   Both shapes execute through the XL route's existing level-ordered `blocked_by` resolution (`skills/auto/SKILL.md`) with no change to that route's mechanics — they are ordinary sub-issues, not a new parent-level phase. This keeps the parent's `## Changed Files` empty and its Verify column ("—") accurate for every XL parent, including ones with cross-cutting acceptance conditions.
   ```

   (→ acceptance criteria AC1, contributes to AC3/AC4)

2. (after 1) `skills/auto/SKILL.md` の `### Step 4d: XL Sub-issue Verify (XL route only)` セクション末尾 — 「Continue to the next issue even if one verify invocation ends in FAIL or MAX_ITERATIONS_REACHED — the close flow in Step 4c will assess the final state.」の直後、`### Step 4c: XL Parent Issue Close Flow (XL route only)` 見出しの直前 — に以下相当の段落を追加する:

   ```markdown
   **Parent (親) cross-cutting artifacts**: the parent Issue's own verify call above (last in this step's list) assumes the parent stays tracking-only, per `modules/size-workflow-table.md`'s XL row (empty `## Changed Files`, Verify: "—"). If the parent's Pre-merge acceptance criteria include a condition needing an aggregate artifact (集約成果物), that artifact must come from a dedicated sub-issue in the dependency graph — not a parent-level code phase, which this route does not have (see `modules/size-workflow-table.md` § "XL Parent Aggregate Deliverables" for the full pattern): a sub-issue `blocked_by` every contributing sub-issue for post-fan-out aggregation (#1158-type), or a level-0 sub-issue that every domain sub-issue is `blocked_by`, for a pre-fan-out prerequisite (#1270-type). Both shapes run through this same level-ordered loop (Step 4) with no XL route changes — by the time this step's parent (親) verify call runs, any aggregation sub-issue has already completed in an earlier level.
   ```

   (→ acceptance criteria AC2, AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/size-workflow-table.md の Size-to-Workflow Mapping Table の XL 行または直後の注記に、XL 親が集約成果物 (Changed Files) を持つ場合の経路が明記されている" --> <!-- verify: section_contains "modules/size-workflow-table.md" "Size-to-Workflow Mapping Table" "集約成果物" --> `modules/size-workflow-table.md` の Size-to-Workflow Mapping Table の XL 行または直後の注記に、親が集約成果物を持つ場合の経路が明記されている
- <!-- verify: rubric "skills/auto/SKILL.md の XL route (Step 4 / Step 4c / Step 4d 周辺) に選択した方針の実行手順が反映されており、fan-out 後の集約ケースと fan-out 前の前提作業ケースのうちどちらに対応するかが明記されている" --> <!-- verify: section_contains "skills/auto/SKILL.md" "Step 4d: XL Sub-issue Verify (XL route only)" "親" --> 選択した方針が `skills/auto/SKILL.md` の XL route に反映されており、#1158 型 (fan-out 後の集約) と #1270 型 (fan-out 前の前提作業) のうち選択した方針が対応する範囲がそれぞれ明記されている
- <!-- verify: rubric "方針 C が選択されており、XL route (skills/auto/SKILL.md) に親 code フェーズという概念自体が追加されておらず、modules/size-workflow-table.md が集約成果物を親の Changed Files ではなく sub-issue 側で扱う設計を明記しており、既存の追跡専用 XL 挙動 (親 Changed Files 空、Verify: —) が保たれることが両ファイルに明記されている" --> 方針 A または A' を選んだ場合の要件 (親 Spec に集約対象の成果物が無いときは親 code フェーズを skip すること) は方針 C の選択により非該当。既存の追跡専用挙動 (親 Changed Files 空、Verify: —) が無条件に保たれることが両ファイルに明記されている
- <!-- verify: rubric "Spec に検討した全方針 (A/A'/B/C 等) の比較と選択理由が記載されており、#1158 型 (fan-out 後の集約) と #1270 型 (fan-out 前の前提作業) それぞれへの対応可否への言及が含まれている" --> 方針の選択理由と却下した方針が Spec (本ファイル `## Notes`) に記録されている。#1158 型・#1270 型それぞれへの対応可否を比較した記述を含む

### Post-merge

- 次回 XL Issue の `/auto` 実行で、親が成果物を持つ場合 (#1158 型・#1270 型いずれか) に手動介入なく完走することを確認する (`verify-type: observation event=auto-run session=next`)

## Notes

### 方針比較 (A / A' / B / C)

- **方針 A (不採用)**: Step 4d 完了後・親 verify 前に親 code フェーズを追加。#1158 型のみ対応、#1270 型 (fan-out 前) は救えない。Issue 本文の AC 自体が両型対応を要求しているため不採用。
- **方針 A' (不採用)**: 方針 A を拡張し、親 Spec の Implementation Steps を fan-out 前後に分割。両型に対応可能だが、(1) Spec 側に「fan-out 前/後」を区別する新しいマーカー記法、(2) `/code` がその区別に応じて Implementation Steps の部分集合のみを実行する新しい起動モード、(3) 親レベルのフェーズという `/auto --resume` が現状扱わない新しい checkpoint 軸、の 3 点で新規メカニズムが必要になり、実装・保守コストが高い。
- **方針 B (不採用)**: 親の Changed Files を強制的に空にする制約のみを追加。Issue 本文が自認する通り「rubric 型の横断 AC をどう評価するかの代替手段」と「fan-out 前の前提作業をどこに置くか」が未解決のまま残る — 方針 C はこの両方に具体的な答え (sub-issue 化 + `blocked_by` 配置) を与えるため、B は C の下位互換 (制約のみで解決策を欠く) と判断した。
- **方針 C (採用)**: 前提作業・集約作業をいずれも通常の sub-issue としてモデル化し、`blocked_by` で fan-out 内の順序を保証する。
  - **#1158 型 (fan-out 後の集約) への対応**: 集約 sub-issue を全 domain sub-issue に `blocked_by` させ、依存グラフの最終レベルで実行させる。`skills/auto/SKILL.md` Step 4 の levelごと順次実行 (`execution_order`) により、親自身の verify (Step 4d 内、リストの末尾) が走る時点で集約 sub-issue は既に `phase/done` に到達している。
  - **#1270 型 (fan-out 前の前提作業) への対応**: 前提 sub-issue を `blocked_by: []` (level 0) とし、全 domain sub-issue をそれに `blocked_by` させる。`get-sub-issue-graph.sh` の `execution_order` により前提 sub-issue が確実に先行レベルで完了してから domain sub-issue が着手される — Background に記載された「プロースによるガードは防御にならない」問題を、実際の `blocked_by` エッジ (機械的に強制) に置き換えることで解消する。
  - **既存メカニズムの再利用**: `docs/guide/xl-decomposition.md` の `sub_issues[].blocked_by` は既に任意の依存関係を表現できる汎用機構であり、「baseline 計測」や「集約レポート」を sub-issue 化するために `skills/auto/SKILL.md` の実行ロジックや `/code`/`/spec` に新しいコードパスを追加する必要がない。`docs/tech.md` の "#437 の教訓 (既存パターンの拡張を新メカニズム導入より優先する)" と同じ判断軸に沿う。
  - **副次的な利点**: 親 Issue は常に Changed Files 空・Verify "—" のままとなり、`modules/size-workflow-table.md` の XL 行が全ての XL 親に対して例外なく成立する (追跡専用という前提が壊れない)。
  - **トレードオフ (Issue 本文が指摘)**: 小さな計測/集約作業のためだけに issue→spec→code→review(不要な場合はpatch route)→verify の一周が走る。ただし XS/S サイズであれば patch route (PR/review 省略) になるため、既存の domain sub-issue と同じ重さであり、fan-out 内の他の小さな sub-issue と比べて特別重いわけではないと判断した。実測で問題が顕在化した場合は別 Issue で再評価する。

### Issue 本文への Spec フェーズ中の反映 (Auto-Resolve Log 相当)

非対話モードのため AskUserQuestion は使用せず、以下は least-risk かつ Issue 本文が既に示唆していた内容の踏襲として判断した。

- **AC1・AC2 の `section_contains` heading 引数から `###` を除去** — reason: 2026-08-21 の triage AC audit コメントが Pattern 6 (常時 UNCERTAIN) を指摘済みで、修復案 (heading 引数から先頭 `###` を除去) も提示されていたため、そのまま適用した。
  - Other candidates: 修復せず Spec 側でのみ回避する案 — Issue 本文と Spec の verify command が乖離し、後続フェーズでの再監査コストが生じるため採用しなかった。
- **AC3 (方針 A/A' 選択時のみ有効な AC) を方針 C 非該当として文言修正** — reason: AC3 は Issue 本文の対応方針セクション自体が「方針の選択は spec フェーズで決定する」と明記した条件付き AC であり、方針 C を選択した時点で前提条件 (A または A') が偽になる。そのまま放置すると `/code`/`/review`/`/merge` が満たせない AC で必ずブロックされるため、AC が保護しようとしていた不変条件 (既存の追跡専用 XL 挙動を壊さないこと) を維持する形に文言・verify command を更新した。
  - Other candidates: AC3 を削除する案 — Issue 本文の条件付き記述の意図 (どの方針が選ばれても既存挙動の非破壊を検証したい) を消してしまうため、削除ではなく条件分岐後の文言に更新する方を採用した。

### 新規分岐ロジックの要否

Implementation Steps はいずれも `modules/size-workflow-table.md`・`skills/auto/SKILL.md` への説明文追加であり、既存スクリプト/モジュールへの新しい条件分岐を追加するものではない (`blocked_by` の順序保証は `get-sub-issue-graph.sh`/`skills/auto/SKILL.md` Step 4 が既に実装済み)。新規テストケース追加は不要と判断した。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 方針 A'/C の追加と verify command (rubric + section_contains) 修正の判断根拠 / https://github.com/saitoco/wholework/issues/1241#issuecomment-5373035513
- saito / MEMBER / first-class / Triage AC audit: `section_contains` の heading 引数から先頭 `###` を除去する修復案 (AC1・AC2 に適用済み、Notes 参照) / https://github.com/saitoco/wholework/issues/1241#issuecomment-5373071696
- No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1・2 とも Spec 記載の挿入位置・見出しレベル (`####`)・本文をそのまま実装した。手順の並べ替え・省略・別方式への変更は発生していない。

### Design Gaps/Ambiguities
- AC4 (方針比較の記録) の rubric verify command は Spec ファイルへの言及のみで、`modules/verify-executor.md` § "Primary evidence outside git diff / Issue body" が求める明示的なファイルパス指名を欠く。rubric grader の既定スコープ (Issue 本文 + git diff + 名指しされたファイル) には Spec が含まれないため、独立した grader 呼び出しでは UNCERTAIN になり得る。本フェーズでは Spec 内容 (`## Notes` の方針比較) を直接確認した上で PASS と判定したが、AC 自体の verify command 品質としては改善余地がある。Step 10 の AC 整合性チェックは refactor 起因の乖離修正のみを対象とするため、本 Issue の scope 外として記録に留めた。

### Rework
- N/A — 手戻りは発生していない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1・2 を修正なしでそのまま実装した (方針 C: 前提作業・集約作業を通常の sub-issue として `blocked_by` でモデル化)。
- `modules/size-workflow-table.md` の `### Size-to-Workflow Mapping Table` 節に `####` レベルで新セクションを追加し、`section_contains` の検証スコープが `### ALWAYS_PR Override` (次の `###` 見出し) で正しく終端されることを確認した。
- Pre-merge AC 4 件 (rubric + section_contains) を Step 10 で全て PASS と判定し、Issue チェックボックスを更新した。post-merge AC (observation event=auto-run session=next) は次回 XL Issue 実行時の確認待ちのまま残した。

### Deferred Items
- Post-merge AC「次回 XL Issue の `/auto` 実行で、親が成果物を持つ場合に手動介入なく完走することを確認する」は `verify-type: observation event=auto-run session=next` のため未評価のまま — 次回該当パターンの XL Issue が `/auto` で走るまで判定不可。
- AC4 の rubric verify command が Spec ファイルパスを明示的に名指ししていない点 (Design Gaps/Ambiguities 参照) — 本 Issue の scope 外として未修正。

### Notes for Next Phase
- `/verify` は Pre-merge 4 件が既にチェック済みであることを踏まえ、Post-merge の observation AC のみが未判定である点に注意する。
- AC4 の rubric スコープ gap は次回同様の rubric AC を書く際の参考情報として `modules/verify-executor.md` § "Primary evidence outside git diff / Issue body" と合わせて参照するとよい。
