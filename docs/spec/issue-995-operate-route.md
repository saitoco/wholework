# Issue #995: operate route: git diff を伴わない操作型 Issue 向けの /code 拡張

## Overview

#958 で確定した設計方針 (Option A: 既存フェーズ拡張 — `/code` に operate route を追加) を実装する。git diff を伴わない操作型 Issue (CMS 修正・インフラ操作等) が、標準ワークフロー (`/issue → /spec → /code → /verify`) 上で処理できるようにする。

設計の骨子 (SSoT: `docs/spec/issue-958-diffless-operational-ac.md`):

- **判定信号は Spec 由来**: 新しい GitHub ラベル・Issue メタデータ・フラグを追加しない。`/spec` が作成した Spec の `## Changed Files` が実質空で、かつ `## Implementation Steps` が外部ツール操作のみで構成されることから機械的に判定する。
- **Size と直交する 2 軸**: Size (XS〜XL) は「変更規模 / 工数」の軸として維持し、diff-less 判定は独立した軸として上乗せする。operate route は Size 値ではなく 3 つ目の route 値である。
- **phase label は patch route と同一**: `phase/code` → `phase/verify`。`/review`・`/merge` はスキップ (PR が存在しないため)。
- **Execution Log**: 実行結果を Issue コメント `## Execution Log` と Phase Handoff に記録し、git diff の可視性に相当する役割を担わせる。
- **`mcp_call` は変更しない**: 「実行」は `/code` (operate route) が担い、「検証」は既存の読み取り専用 `mcp_call` が担う分離を維持する。

## Changed Files

- `modules/size-workflow-table.md`: `Size-to-Workflow Mapping Table` の直後に `### Diff-less Axis (operate route)` セクションを追加。operate route を 3 つ目の route として定義し、Size 軸と diff-less 軸が直交すること (operate は Size 値ではない) を明記する。`Phase-Level Light/Full Mapping` テーブルに `operate (diff-less)` 列を追加 (spec: 必須 / code: 外部操作を直接実行 / review: なし / merge: なし / verify: 実行)
- `modules/autonomy-tier.md`: `Tier × L0 Write Matrix` の直後に `### Tier × External System Write (operate route)` サブセクションを追加。operate route の外部システム書き込みは `L2` 以上を要求し、`L1` では path A (advisory) に degrade する旨を定義
- `modules/next-action-guide.md`: Input の `ROUTE` 列挙に `operate` を追加。Step 2 の SIZE→ROUTE 導出に「ROUTE が明示的に渡された場合は SIZE から導出しない」旨の注記を追加。Step 3 判断テーブルに `code | success | operate | /verify {ISSUE_NUMBER} | /auto {ISSUE_NUMBER}` 行を追加
- `skills/spec/SKILL.md`: Step 18 (Size-to-Workflow Determination) に operate route 判定を追加。手順 3 と 4 の間に「Operate route detection」を挿入し、手順 4 の ROUTE マッピングに operate を追加 (diff-less 判定が Size マッピングに優先する)
- `skills/code/SKILL.md`: Step 0 (Route Detection) に Spec 由来の operate 判定を追加 (フラグ・ALWAYS_PR・Size 自動判定すべてに優先)。Step 8 に `#### Operate Route: External Operation Execution` を追加 (autonomy tier ゲート + 外部操作実行)。Step 9 (Run Tests)・Step 11 の commit/PR ブロックに operate route のスキップガードを追加。Step 11 に `#### Operate Route: Execution Log` を追加 (Issue コメント投稿)。Step 13 に operate route の Exit (patch route と同じ merge-to-main + `phase/verify` 遷移) を追加。Completion Report に operate route の prefix を追加。allowed-tools の変更は不要 (新規 script なし。`ToolSearch`・`gh-issue-comment.sh` は既存エントリで充足)
- `skills/auto/SKILL.md`: `Route-Phase Matrix` に `operate (diff-less)` 行を追加 (`spec (when needed) → code(--patch) → verify`)。Step 2 に「Spec が既に存在する場合の operate 検出」を追加。Step 3a (Post-Spec Size Refresh) に「Operate route demotion」を追加 (pr/patch → operate)。Step 4 で ROUTE=operate のとき patch route の phase sequence を使う旨を明記
- `docs/workflow.md`: `### 3. /code — Implementation` のルーティング記述に operate route を追加。`### 4. /review — Review` の Review mode テーブルの下に「operate route は PR が存在しないためスキップ」の注記を追加
- `docs/structure.md`: モジュール表の `code` 行の説明 `Local implementation (patch/PR route)` を `Local implementation (patch / pr / operate route)` に変更
- `docs/tech.md`: `## Architecture Decisions` に **operate route (diff-less workflow path)** の bullet を追加 (Option A 採用理由 = #437 の教訓、既存分岐点への追加パターン)
- `docs/product.md`: `## Terms` テーブルに `Operate route` エントリを `Patch route`・`PR route` と同形式で追加 (行の並びは既存のアルファベット順に従い `Orchestration recovery` と `Patch route` の間)
- `docs/ja/workflow.md`: `docs/workflow.md` の変更に対応する翻訳同期 (`docs/translation-workflow.md` 準拠)
- `docs/ja/structure.md`: `docs/structure.md` の変更に対応する翻訳同期 (92 行目 `ローカル実装（patch/PR 経路）`)
- `docs/ja/tech.md`: `docs/tech.md` の変更に対応する翻訳同期 (`## アーキテクチャ決定`)
- `docs/ja/product.md`: `docs/product.md` の変更に対応する翻訳同期 (`## 用語` テーブル)
- `tests/operate-route.bats`: 新規。operate route 判定ロジックのユニットテスト (shallow test — `tests/size-workflow-table.bats` と同じ「モジュールドキュメントの記述を grep で検証する」パターン)。bash 3.2+ 互換

**Steering Docs sync candidate (すべて上記 Changed Files に含む)**: `skills/{spec,code,auto}/SKILL.md` の変更に伴い `docs/workflow.md`・`docs/structure.md`・`docs/tech.md`・`docs/product.md` (および `docs/ja/` 対応ミラー) を同期対象として列挙済み。

## Implementation Steps

1. `modules/size-workflow-table.md` に `### Diff-less Axis (operate route)` セクションを追加し、operate route の定義・判定基準・Size 軸との直交性を明記する。`Phase-Level Light/Full Mapping` テーブルに operate 列を追加する (→ AC1)

2. `skills/spec/SKILL.md` Step 18 に Operate route detection を追加する (1 の後)。手順 3 (Size 更新) の直後・手順 4 (ROUTE マッピング) の直前に挿入し、以下の 2 条件を **both** 満たすとき `ROUTE=operate` とする。判定は Size マッピングに優先する (→ AC2)
   - `## Changed Files` にリポジトリ内ファイルのエントリが 1 件も存在しない (空、`なし`/`none`、または外部システム上の対象のみ)
   - `## Implementation Steps` のすべてのエントリが外部ツール操作 (MCP ツール呼び出し / 外部システムに対する CLI / HTTP API 呼び出し) であり、ファイル編集・commit 手順を含まない
   - Size 自体は従来どおり再評価・更新する (Size は工数軸として維持。operate は Size 値ではなく route 値)

3. `skills/code/SKILL.md` Step 0 (Route Detection) に Spec 由来の operate 判定を追加する (parallel with 2)。Step 0 で既に読み込んでいる `detect-config-markers.md` の `SPEC_PATH` を使って `$SPEC_PATH/issue-$NUMBER-*.md` を Glob し、Spec が存在する場合は Step 2 と同一の diff-less 基準を適用する。判定順序を「operate 判定 → 既存の flag precedence (`--pr` / `ALWAYS_PR` / `--patch`) → Size 自動判定」とし、operate 検出時は `--pr`・`ALWAYS_PR=true`・`--patch` をすべて上書きする (差分が存在しない以上、PR route は空 PR になるため成立しない)。上書き時は警告を出力する: `Warning: operate route detected (Spec has no repository file changes). --pr / always-pr is ignored.` (→ AC3)

4. `skills/code/SKILL.md` に ROUTE=operate 時の実行分岐を追加する (after 3) (→ AC3, AC7)
   - **Step 8**: `#### Operate Route: External Operation Execution` を追加。(a) `AUTONOMY_TIER` を読み込み、`L1` の場合は外部操作を実行せず、実行予定の操作一覧を `## Execution Plan` として Issue コメントに投稿し、`phase/code` のまま終了する (path A = advisory に degrade)。`L2`/`L3` の場合のみ実行する。(b) Spec の Implementation Steps に列挙された外部操作 (MCP ツール / CLI / HTTP API) を順に実行する。実装 diff は生じないため `git add` / `git commit` は行わない
   - **Step 9 (Run Tests)**: operate route ではスキップする (リポジトリ内コードの変更がないため)
   - **Step 10 (Verify Command Consistency)**: 変更なし (pre-merge verify command を full mode で実行する既存挙動をそのまま使う)
   - **Step 11**: 実装 commit・`git push`・`gh pr create` をすべてスキップする。代わりに `#### Operate Route: Execution Log` を追加し、`gh-issue-comment.sh` で Issue に `## Execution Log` を投稿する。先頭行に `<!-- wholework-event: type=execution-log phase=code issue=$NUMBER -->` マーカーを置き (`modules/l0-surfaces.md` の Machine-Readable Event Marker 形式)、本文に実行したツール名 / コマンド名、引数の要約 (秘匿値はマスク)、Implementation Step ごとの観測結果を記録する
   - **Step 12 (Code Retrospective)**: 変更なし。Spec への Code Retrospective + Phase Handoff の追記と commit は patch route と同じく実施する (Phase Handoff はリポジトリ内 Spec ファイルに記録され `/verify` が参照するため、この commit は operate route でも必要 — Notes「#958 との相違」参照)
   - **Step 13 (Worktree Exit)**: patch route と同じ `Exit: merge-to-main` を実行し、push 完了後に `gh-label-transition.sh $NUMBER verify` で `phase/verify` へ遷移する
   - **Completion Report**: operate route の prefix を `External operations executed. Execution Log posted to the Issue.` とし、`ROUTE=operate` を `next-action-guide.md` に渡す

5. `modules/autonomy-tier.md` に `### Tier × External System Write (operate route)` サブセクションを追加する (parallel with 4)。operate route の外部システム書き込み (CMS / インフラ / 外部 API への write) は L0 write とは別のサーフェスであることを明記し、`L1` = 実行禁止 (Execution Plan の advisory 投稿のみ)、`L2`/`L3` = 実行可、というテーブルを定義する。判断根拠として「operate route では `/review` による事後 diff レビューという安全弁が存在せず、`phase/ready` 到達が唯一の事前ゲートになる」(#958 残存リスク) を記載する (→ AC7)

6. `modules/next-action-guide.md` に operate route を反映する (parallel with 4)。Input の `ROUTE` 列挙に `operate` を追加し、Step 3 の判断テーブルに `code / success / operate → 推奨 /verify {ISSUE_NUMBER}、代替 /auto {ISSUE_NUMBER}` 行を追加する。Step 2 に「ROUTE が呼び出し元から明示的に渡された場合は SIZE からの導出を行わない」注記を追加する (operate は Size から導出できないため) (→ AC3)

7. `skills/auto/SKILL.md` に operate route を追加する (after 2, 3)。`Route-Phase Matrix` に `operate (diff-less) | (Size 非依存) | spec (when needed) → code(--patch) → verify` 行を追加。Step 2 で「`phase/ready` が既に付与され Spec が存在する場合、diff-less 基準を満たせば ROUTE=operate」とする分岐を追加。Step 3a に `**Operate route demotion (pr/patch → operate)**` を追加し、spec フェーズ完了後に Spec が diff-less であれば ROUTE=operate へ降格し `/review`・`/merge` をスキップする旨を定義する (`ALWAYS_PR=true` でも operate 降格は抑制しない — 空 PR は作成できないため)。Step 4 では operate route は patch route と同じ phase sequence (`run-code.sh $NUMBER --patch` → verify) を使う旨を明記する (`--operate` フラグは導入しない。`/code` が Spec から自動判定するため `run-code.sh` の変更は不要) (→ AC3, Post-merge AC)

8. Steering Docs を同期する (after 1, 4, 7) (→ AC4)
   - `docs/workflow.md`: `### 3. /code` のルーティング記述に「Spec の Changed Files が実質空かつ Implementation Steps が外部操作のみの場合は **operate** (worktree/commit/PR なし、外部操作を直接実行し Execution Log を Issue に記録)」を追加。`### 4. /review` の Review mode テーブル下に「operate route: PR が存在しないためスキップ」注記を追加。operate route の外部 CLI 実行が `/code` の allowed-tools 制約を受ける点 (Uncertainty 参照) も併記
   - `docs/structure.md`: モジュール表の `code` 行の説明を `Local implementation (patch / pr / operate route)` に更新
   - `docs/tech.md`: `## Architecture Decisions` に operate route の bullet を追加

9. `docs/product.md` `## Terms` に `Operate route` エントリを追加する (after 8) (→ AC5, AC6)
   ```
   | Operate route | Workflow path for diff-less operational Issues (CMS edits, infrastructure operations); executes external MCP/CLI/API operations directly without creating a commit or Pull Request, and records an `## Execution Log` Issue comment in place of a git diff. Determined from the Spec (empty `## Changed Files` + external-operation-only Implementation Steps), orthogonal to Size | Development workflow | Operate 経路 |
   ```

10. `docs/ja/` ミラーを同期し (`docs/ja/workflow.md`・`docs/ja/structure.md`・`docs/ja/tech.md`・`docs/ja/product.md`)、`tests/operate-route.bats` を新規追加する (after 8, 9) (→ AC4, AC5, AC8)
    - `tests/operate-route.bats` の検証内容 (すべて grep ベースの shallow test、bash 3.2+ 互換):
      - `modules/size-workflow-table.md` に `operate` route と `orthogonal` の記述が存在する
      - `skills/spec/SKILL.md` に `ROUTE=operate` の記述が存在する
      - `skills/code/SKILL.md` に operate route の分岐 (`Execution Log`) が存在する
      - `skills/auto/SKILL.md` に operate route 行が存在する
      - `modules/autonomy-tier.md` に operate route の外部書き込みゲートの記述が存在する
    - `docs/ja/*` の verify command は日本語版の文字列を対象にする (英語パターンを使うと意図しない書式変更を誘発するため)

## Alternatives Considered

| 案 | 内容 | 採否 |
|---|---|---|
| `--operate` フラグの新設 | `/code 123 --operate` / `run-code.sh --operate` で明示指定できるようにする | **不採用** — `run-code.sh` の引数処理・`tests/run-code.bats`・`skills/auto/SKILL.md` の呼び出しに波及し、変更ファイルが増える。#958 が「既存の Spec 内容から機械的に判定できる」ことを設計前提としており、フラグは冗長。将来 Spec 判定を上書きしたい需要が出た時点で追加する |
| operate route を新しい Size 値にする | Size に `OP` のような値を足し、Size 軸に統合する | **不採用** — #958 が「Size と diff-less 判定は直交する 2 軸」と明示。Size は工数見積り軸であり、diff-less は実行手段の軸。統合すると `/triage` の Size 判定基準 (ファイル数) と衝突する |
| Phase Handoff も Issue コメントのみに記録し commit を完全に排除 | Spec ファイルへの書き込みをやめ、`/code` の commit を 0 にする | **不採用** — `modules/phase-handoff.md` の Read Procedure は `$SPEC_PATH/issue-N-*.md` を Glob する設計であり、記録先を変えると phase-handoff モジュール自体の SSoT 変更が必要になる。実装 diff の commit は行わないが、Spec 側のレトロスペクティブ commit は全 route 共通のブックキーピングとして維持する (Notes 参照) |
| 独立 Skill `/operate` の新設 | 新しい軽量フェーズとして Skill を追加する | **不採用** — #958 の Option B。ドキュメント SSoT 影響が 6〜8 箇所に及び、#437 の教訓 (新メカニズムより既存パターン流用を優先) に反する |

## Verification

### Pre-merge
- <!-- verify: rubric "modules/size-workflow-table.md に operate route が 3 つ目の route として追加され、Size と diff-less 判定が直交する 2 軸であることが明記されている" --> size-workflow-table.md に operate route が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md の Size-to-Workflow Determination に、Changed Files が実質空かつ Implementation Steps が外部ツール操作のみの場合に ROUTE=operate と判定する分岐が存在する" --> `/spec` に ROUTE=operate 判定ロジックが追加されている
- <!-- verify: rubric "skills/code/SKILL.md に ROUTE=operate 時の分岐 (worktree/commit/push/PR 作成のスキップ、外部操作の直接実行、Execution Log の Issue コメント + Phase Handoff への記録、patch route と同一の label 遷移) が定義されている" --> `/code` に operate route の実行分岐が追加されている
- <!-- verify: rubric "docs/workflow.md, docs/tech.md, docs/structure.md のうち operate route に言及すべきものが更新されている (Steering Docs sync)" --> Steering Docs が operate route を反映している
- <!-- verify: rubric "docs/product.md の Terms セクションに、Patch route/PR route と同じ形式で Operate route の Term エントリが追加されている" --> docs/product.md § Terms に Operate route のエントリが追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Operate route" --> Terms セクション内に `Operate route` の文字列が含まれている
- <!-- verify: rubric "modules/autonomy-tier.md に operate route の外部システム書き込みに対する autonomy tier ゲーティング方針 (どの tier で実行を許可し、どの tier で advisory に留めるか) が定義され、skills/code/SKILL.md の operate route 分岐がそのゲートを参照している" --> 外部システム書き込みへの autonomy tier ゲーティング方針が定義され、`/code` が参照している
- <!-- verify: command "bats tests/" --> テストスイートが green (operate route 判定のテストを含む)

### Post-merge
- 次回 diff-less な操作型 Issue の `/auto` 実行時、operate route で処理され Execution Log が記録されることを観察 <!-- verify-type: observation event=auto-run -->
  - 期待する出力構造:
    - Issue に `## Execution Log` コメントが投稿され、先頭に `<!-- wholework-event: type=execution-log phase=code issue=N -->` マーカーが含まれる
    - `/review`・`/merge` が実行されず、`phase/code` → `phase/verify` の label 遷移のみが観測される
    - PR が作成されていない

## Tool Dependencies

### Bash Command Patterns
- なし (新規 script の追加はなく、`/code` の既存 allowed-tools エントリで充足する)

### Built-in Tools
- なし (`Read` / `Write` / `Edit` / `Glob` / `Grep` / `ToolSearch` はいずれも `/code`・`/spec`・`/auto` の既存 allowed-tools に含まれる)

### MCP Tools
- なし (operate route が呼ぶ MCP ツールは Issue ごとに異なり、`ToolSearch` 経由で動的に解決される。特定ツールを allowed-tools に固定しない)

## Uncertainty

- **operate route の外部 CLI 操作と `/code` の allowed-tools 制約**: `skills/code/SKILL.md` の `allowed-tools` は `Bash(...)` を列挙型で制限しており (`gh`・`git`・`python3`・`bats` 等)、任意の外部 CLI (ベンダー CLI、`curl` 等) は許可されていない。MCP ツール経由の操作は `ToolSearch` が allowed-tools に含まれるため現状で動作する。
  - **検証方法**: `skills/code/SKILL.md` frontmatter の `allowed-tools` を確認済み (Bash パターンは列挙型で、ワイルドカードによる全許可は存在しない)。
  - **影響範囲**: Implementation Step 4 (Step 8 の外部操作実行)。
  - **解決方針**: operate route の一次サポートチャネルを **MCP ツール (ToolSearch 経由) と既存の許可済み Bash パターン** に限定し、任意の外部 CLI が必要なプロジェクトは (a) `/code` の allowed-tools をプロジェクト側で拡張するか、(b) `.wholework.yml` の `permission-mode: bypass` を使う必要がある旨を `skills/code/SKILL.md` の operate route 節と `docs/workflow.md` に明記する。allowed-tools を `Bash(*)` に緩めることはしない (全 route に影響するセキュリティ後退になるため)。

- **`section_contains "docs/product.md" "## Terms" "Operate route"` の成立性**: 検証済み。`modules/verify-executor.md` の `section_contains` は heading 引数を部分一致で扱い、`## Terms` は `docs/product.md:157` に実在する。Term エントリ追加後にセクション内へ `Operate route` 文字列が入るため PASS する。

## Notes

### #958 (設計 SSoT) との相違 — Spec 側 commit の扱い

#958 の Phase handling テーブルは operate route の `/code` を「**worktree 不要。外部操作を直接実行し commit は行わない。**Execution Log を Issue コメント + Phase Handoff に記録」と記述している。しかし Phase Handoff の記録先はリポジトリ内の Spec ファイル (`docs/spec/issue-N-*.md`) であり (`modules/phase-handoff.md` Write/Read Procedure)、これを記録する以上 commit は不可避である。両立しない。

**解決**: 「commit は行わない」は **実装 diff の commit / PR 作成** を指すものと解釈し、Spec 側のブックキーピング (Code Retrospective + Phase Handoff の追記) は全 route 共通の処理として patch route と同じ worktree + `Exit: merge-to-main` で commit・push する。理由:

- Phase Handoff の記録先を Issue コメントに変えると `modules/phase-handoff.md` の Read Procedure (Spec ファイル Glob) 自体の変更が必要になり、`/review`・`/merge`・`/verify` にも波及する。#958 が明示的に「新しいアーティファクト種別は導入しない」としている方針に反する
- worktree を省略すると、並列セッション環境で main への直接 commit が競合する。`modules/worktree-lifecycle.md` が存在する理由そのものであり、Spec への 1 commit のためだけにその保護を外すのは正当化できない

この相違は `/code` の operate route 実装時に SKILL.md へ明記し、`docs/spec/issue-958-diffless-operational-ac.md` は履歴記録として書き換えない。

### autonomy tier ゲーティング (#958 残存リスク) の判断

#958 は「外部システムへの書き込みに autonomy tier ゲーティングを適用すべきかは実装時に検討する」として本フェーズへ委譲していた。**適用する**と判断した。

- 根拠: operate route では「提案 (Implementation Steps) → ゲート (`/review`) → 適用 (`/merge`)」の分離が失われ、`/code` 内で提案と適用が同時に発生する。事後の diff レビューという安全弁が存在しないため、無人実行 (L3) 前提の外部書き込みを既定にするのは危険。
- 設計: `modules/autonomy-tier.md` の既存 `L2→L1 Path Catalog` の path A (Advisory) セマンティクスをそのまま使う。`L1` = 実行せず Execution Plan を advisory コメントとして投稿、`L2`/`L3` = 実行。既存の tier 意味論 (「L1 Report = advisory print only; human acts」) と完全に整合し、新しい tier 軸を追加しない。
- 既存の `Tier × L0 Write Matrix` に列を足すのではなく、独立した `Tier × External System Write` サブセクションとして追加する (外部システム書き込みは L0 = GitHub state とは別サーフェスであるため)。

### 自動解決した曖昧点 (Auto-Resolve Log)

非対話モード (`--non-interactive`) のため、以下を model 判断で自動解決した。

1. **Size と operate route の関係**: Size は工数軸として従来どおり維持・再評価し、diff-less 判定を直交軸として上乗せする (operate は Size 値ではなく 3 つ目の route 値)。#958 の「直交する 2 軸」記述に従った。他候補 (Size に新値を足す) は `/triage` のファイル数ベース Size 判定と衝突するため不採用。
2. **`--operate` フラグの要否**: 導入しない。Spec 由来の機械判定のみとする。`run-code.sh`・`tests/run-code.bats`・allowed-tools への波及を避けられ、#958 の「既存の Spec 内容から機械的に判定できる」前提に整合する。
3. **`/auto` の operate 対応範囲**: 新しい phase sequence を作らず、patch route と同じ `code → verify` を流用する。Step 2 / Step 3a に operate 検出を追加し、pr → operate の降格を行う。`ALWAYS_PR=true` でも operate 降格は抑制しない (空 PR は作成できないため、`always-pr` の意図する「レビューを挟む」効果が成立しない)。
4. **AC の追加**: 上記「autonomy tier ゲーティング」の判断結果を検証可能にするため、Pre-merge AC を 7 件 → 8 件に拡張した (rubric 1 件を追加)。Issue 本文にも同じ AC を反映済み。

### 実装上の注意

- `tests/operate-route.bats` の `@test` 名は英語 (ASCII) にする。マルチバイト文字はテスト名のパース失敗を招く (#226)。
- `docs/ja/*` の verify command / grep パターンには日本語版の文字列を使う。英語パターンを使うと翻訳ミラーの書式に意図しない影響が出る。
- `skills/code/SKILL.md` の operate route 分岐追加後、`scripts/check-allowed-tools.sh skills/` が green であることを確認する (新規 script 参照を追加していないため差分は出ない想定)。

## Consumed Comments

- saito / MEMBER / first-class / `/issue 995 --non-interactive` の Issue Retrospective。(1) `docs/product.md` § Terms への `Operate route` エントリ追加を Scope / AC に追加、(2)「実質空」の判定基準は #958 に既出のため追加対応不要、(3) autonomy tier ゲーティングは `/spec`・`/code` へ委譲、の 3 点を auto-resolve した記録。本 Spec では (1) を Changed Files / Implementation Step 9 に、(3) を Implementation Step 5 + Notes「autonomy tier ゲーティングの判断」に反映した。(2) は追加対応不要の判断をそのまま踏襲した。 / https://github.com/saitoco/wholework/issues/995#issuecomment-4949900094

## Issue Retrospective

`/issue 995 --non-interactive` で既存 Issue のリファインメントを実行した記録 (Issue コメントから転記)。

### Triage (auto-chain)

- `triaged` ラベルが未付与だったため triage を自動連鎖実行
- Type: Feature / Size: L / Value: 3 (Impact=2: shared component 該当のみ、Alignment=4: product.md Vision 「every phase from Issue creation through post-merge verification」に直結) / Priority: 未検出
- 重複候補: なし / Stale 判定: 停滞なし / 依存関係: `Blocked by` 記載なし
- AC verify command audit (grep 引数順・常時 PASS/FAIL・patch route 不整合・destructive command の 5 パターン): 問題なし

### Ambiguity 自動解決 (Auto-Resolve Log)

Size=L のため検出上限 5 件のうち、実質的なギャップは 1 件のみ検出した。

1. **docs/product.md § Terms への `Operate route` エントリ追加**: Spec (#958) のフォローアップ推奨スコープは `docs/workflow.md`・`docs/structure.md`・`docs/tech.md` のみを列挙していたが、既存の `Patch route`・`PR route` はいずれも `docs/product.md` § Terms にエントリを持つため、用語一貫性を優先して Scope と Pre-merge AC に追加した (rubric + `section_contains` の補完チェック)。
2. **「実質空」の判定基準**: Spec (#958) の Design セクションに基準が既に明記され、Issue 本文の記述と完全一致していたため追加対応不要と判断。
3. **残存リスク (autonomy tier ゲーティング適用可否)**: Spec (#958) が「実装時に検討する」と次フェーズへ明示的に委譲していたため、`/issue` フェーズで AC 化せず Related Issues の注記のまま維持。

### Scope Assessment

非対話モードのため sub-issue 分割検討 (High-Stakes Decision) はスキップした。Size=L のため元々 XL 分割閾値 (11+ ファイルまたは複数独立機能) には該当しない。

## Spec Retrospective

### Minor observations

- Changed Files が 15 件となり Axis 1 (ファイル数) 単独では XL (11+) に該当するが、うち 4 件は `docs/ja/` の機械的ミラー、4 件は Steering Docs の 1〜数行更新であり、実体は「既存の 2 値分岐 (patch/pr) に 3 つ目の値を足す」単一の lateral extension である。Axis 2 の「Simple lateral extension of existing patterns」で −1 補正し **Size=L を維持** した (triage 時の Size と一致するため Project field の更新は不要)。`docs/ja/` ミラーが Axis 1 のファイル数を実質 2 倍に膨らませる構造は、本 Issue に固有ではなく Steering Docs を触るすべての Issue に共通する Size 判定上のノイズである。
- `modules/next-action-guide.md` は Issue 本文の Scope に含まれていなかったが、`ROUTE` の列挙が `patch / pr / sub_issue` にハードコードされており、`ROUTE=operate` を渡すと未定義値になる。Symbol impact discovery (`ROUTE=` の全文検索) で検出し Changed Files に追加した。Issue 起票時の Scope 列挙は #958 の推奨スコープをそのまま引き継いだものであり、実装対象の全文検索を経ていなかったことが原因。

### Judgment rationale

- **#958 との相違 (Spec 側 commit の扱い)**: #958 の Phase handling テーブルは operate route の `/code` を「worktree 不要・commit は行わない」と記述するが、同じ行が「Phase Handoff に記録」とも要求しており、Phase Handoff の記録先はリポジトリ内の Spec ファイルである。両立しない。「commit は行わない」を **実装 diff の commit / PR 作成** の意味に限定解釈し、Spec 側のブックキーピング commit は patch route と同じ worktree + merge-to-main で実施する設計に解決した。記録先を Issue コメントへ移す代替案は `modules/phase-handoff.md` の Read Procedure 変更 (= `/review`・`/merge`・`/verify` への波及) を要し、#958 自身の「新しいアーティファクト種別は導入しない」方針に反するため不採用。
- **`--operate` フラグを導入しない判断**: フラグを足すと `run-code.sh` の引数処理・`tests/run-code.bats`・`skills/auto/SKILL.md` の呼び出しに波及し、Changed Files が 2〜3 件増える。#958 が「既存の Spec 内容から機械的に判定できるため新しいメタデータを追加しない」を設計前提としているため、Spec 由来の自動判定のみとした。結果として `/auto` は operate route でも `run-code.sh $NUMBER --patch` を呼び、`/code` が内部で operate へ解決する構造になり、script 層の変更がゼロになった。
- **autonomy tier ゲーティングを「適用する」と判断した根拠**: 既存の `modules/autonomy-tier.md` に L1 = 「advisory print only; human acts」というセマンティクスが既に存在するため、新しい tier 軸を作らずに L1 = Execution Plan の advisory 投稿のみ / L2・L3 = 実行、というマッピングがそのまま成立した。既存の `Tier × L0 Write Matrix` に列を足すのではなく独立サブセクションにしたのは、外部システム書き込みが L0 (GitHub state) とは別サーフェスであり、`modules/l0-surfaces.md` の SSoT テーブルに新しい行を足さずに済ませるため。

### Uncertainty resolution

- **operate route の外部 CLI 操作と `/code` の allowed-tools 制約**: `skills/code/SKILL.md` の `allowed-tools` は `Bash(...)` を列挙型で制限しており (`gh`・`git`・`python3`・`bats` 等)、任意の外部 CLI は許可されていない。設計段階で frontmatter を実読して確認した。解決方針は「operate route の一次サポートチャネルを MCP ツール (`ToolSearch` 経由、既存 allowed-tools に含まれる) と既存許可済み Bash パターンに限定し、任意の外部 CLI が必要なプロジェクトは allowed-tools 拡張または `permission-mode: bypass` を使う」旨を SKILL.md と `docs/workflow.md` に明記すること。`Bash(*)` への緩和は全 route に影響するセキュリティ後退になるため採らない。この制約は Spec の Uncertainty セクションに残し、`/code` フェーズで再確認する。
- **`section_contains "docs/product.md" "## Terms" "Operate route"` の成立性**: `modules/verify-executor.md` の `section_contains` 定義 (heading 引数は部分一致) を実読し、`## Terms` が `docs/product.md:157` に実在することを確認した。Term エントリ追加後に PASS することが確定しているため Uncertainty からは除外できる。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- **squash merge を conflict なしで実行**。mergeable=true (reason=clean)、CI success、review approved を確認済みのため Step 3 (Resolve Conflicts) はスキップし Step 4 に直行した。
- **BASE_BRANCH=main のため Issue #995 は `closes #995` により自動クローズされる想定**。フォールバック検証 (Step 6) で state=CLOSED / phase/verify ラベル付与を確認する。

### Deferred Items

- なし。

### Notes for Next Phase

- **`/code` フェーズの Phase Handoff (`<!-- phase: code -->`) が見当たらなかった件は未解決のまま**。review フェーズからの申し送り通り実害はなし (実装 diff は origin と一致してクリーン) だが、`/verify` 実行者は既知の事象として認識しておくこと。
- **`skills/review/workflow-guidance.md` の Verify ステージの Workflow スクリプトバグ (`parallel()` 未使用による findings 消失) は本 PR スコープ外のまま未修正**。`/verify` 集約時に Improvement Proposal 起票候補とすること (review フェーズからの申し送り継続)。

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の `## Uncertainty` 節 (docs/spec/issue-995-operate-route.md:124) は「operate route の allowed-tools 制約を `skills/code/SKILL.md` と `docs/workflow.md` の両方に明記する」と narrative で述べていたが、拘束力を持つ `## Implementation Steps` (AC に紐づくチェックリスト) 側ではこの明記対象を `docs/workflow.md` のみに限定していた。実装はテスト可能な Implementation Steps 通りに行われ (`docs/workflow.md` にのみ制約文言あり、`skills/code/SKILL.md` にはなし)、これは PR の欠陥ではなく Spec 内部の記述レベル (narrative vs. binding checklist) の不整合だった。Step 10 の review-bug finder がこれを SHOULD として検出したが、adversarial verification で「Spec の権威ある Implementation Steps に従っているため false positive」と判定された。
- **改善余地**: `/spec` が Uncertainty 節で「両方に明記」と解決した場合、その解決内容が `## Implementation Steps` に過不足なく転記されているかを spec フェーズ内でセルフチェックする仕組みがあると、今回のような narrative/checklist 間の不整合を実装前に防げる。Improvement Proposal 候補として `/verify` 集約時に検討。

### Recurring issues

- 特になし。本 PR 単独のレビューでは同種issue の繰り返しは見られなかった。

### Acceptance criteria verification difficulty

- Pre-merge AC 8件はすべて明確に自動判定可能だった (rubric 6件・section_contains 1件・command 1件)。UNCERTAIN や verify command の欠落・不正確さはなし。`command "bats tests/"` は safe mode の CI reference fallback で `Run bats tests` job の SUCCESS を参照して PASS 判定できた。

### Tooling issue discovered (out of scope for this PR)

- `skills/review/workflow-guidance.md` のインライン Workflow スクリプト (Verify ステージ) に不具合を発見: `finderResult.findings.map(finding => () => agent(...))` が `parallel(...)` でラップされておらず、返り値が未実行の関数配列のままパイプラインを通過していた。Workflow のキャッシュ/再開機構によるシリアライズ境界を越える際に関数値が失われ (`JSON.stringify` で `null` 化)、`.filter(Boolean)` で除去されるため、実際には 2 件の finding が検出されていたにもかかわらず初回実行結果は `confirmed: []` / `totalFound: 0` という偽陰性を返した。本レビューでは `parallel(...)` を追加したスクリプトで再実行 (`resumeFromRunId` でキャッシュ済み finder 結果を再利用) して正しい結果 (`totalFound: 2`, adversarial verify で両方 refute) を得た。
- `skills/review/workflow-guidance.md` は本 PR (#999) の変更対象外のため、ここでは修正せず記録のみに留める。`capabilities.workflow: true` を有効化している他プロジェクトでも同じ偽陰性が再現するはずで、Step 10 の Workflow パスを使うすべての `/review --full` 実行に影響する。Improvement Proposal として `/verify` 集約時に起票候補とすること — 修正は `finderResult => { ... return parallel(finderResult.findings.map(...)) }` のように verify ステージの返り値を `parallel()` でラップするだけの小さな diff。


## Auto Retrospective

### Tier 3 recovery (code-pr)
- **Date**: 2026-07-12 06:18 UTC
- **Issue**: #995, phase: code-pr
- **Source**: spawn-recovery-subagent.sh
- **Wrapper exit code**: 1
- **Outcome**: success
- **Recovery details**: see docs/reports/orchestration-recoveries.md
