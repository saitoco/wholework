# Issue #958: git diff を伴わない操作型 AC (CMS修正・インフラ操作等) の置き場所がなく Post-merge manual に落ちる

## Overview

本 Issue は実装を伴わない設計検討 Issue である。Acceptance Criteria の3件はすべて本 Spec 自身の内容を対象にした `rubric` 検証であり、完了条件は「設計方針が Spec に記録されること」そのものである (Issue 本文「完了条件」参照)。以下、比較検討 → 決定 → フェーズ別の扱い → フォローアップの順に記録する。

### 背景の要約

Wholework の標準ワークフロー (`/issue → /spec → /code → /review → /merge → /verify`) は「`/code` は git diff を生成する」ことを構造的前提としている。Size 判定 (`modules/size-workflow-table.md`) も変更ファイル数を第一軸とする。CMS コンテンツ修正・インフラ操作のように MCP ツール・CLI・API のみで完結し git diff を伴わない「操作型」タスクはこの前提に当てはまらないため置き場所がなく、`verify-type: manual` の Post-merge 条件に落ちる傾向がある (再現元: tofas #250)。

### Option Comparison: 既存フェーズ拡張案 vs 新設の軽量フェーズ案

比較軸: Issue 本文が指定する通り、#437 (`visual_diff` verify command 設計) の教訓 — 新メカニズムより既存パターンの流用を優先する — を第一の判断軸とする。`docs/environment-adaptation.md` § Extension Guide の Step 0 (新設前に既存パターンの流用可否を必ず調査する) も同じ原則を明文化しており、本検討はこの手順に従う。

| 観点 | Option A: 既存フェーズ拡張 (`/code` に operate route を追加) | Option B: 新設の軽量フェーズ (独立 Skill、例: `/operate`) |
|---|---|---|
| ユーザーが覚えるコマンド | 増えない (`/code` のまま) | 増える — 新コマンド名の学習コストが発生 |
| フェーズラベル | 既存の `phase/code` → `phase/verify` 遷移を流用可能 (patch route と同一) | 新しいラベル遷移を設計するか既存ラベルを流用するかの追加判断が必要 |
| ドキュメント SSoT 影響 | `modules/size-workflow-table.md` に route を1行追加するのみ | `docs/workflow.md`・`docs/tech.md` の fork context 表・`modules/execution-context.md` の per-skill 表・`modules/autonomy-tier.md` の tier 表・`kanban-automation.yml` など6〜8箇所に新規行が必要 |
| 既存共有モジュールの再利用 | `modules/phase-handoff.md`・`modules/l0-surfaces.md`・`modules/verify-executor.md` の `mcp_call` をそのまま利用 | 同じモジュール群は利用できるが、`worktree-lifecycle.md` は不要になる (git 操作がないため) — この点は Option A でも同じ分岐が増えるだけで差はない |
| `/code` 内部の複雑化 | 既存の patch/pr 分岐と同型の3値分岐が増える (SKILL.md 各ステップに operate route のガードを追加) | `/code` 自体は変更不要 |
| 概念的明快さ | 「`/code` は実装を行う」役割は変わらず、実装手段が git commit か外部操作かが変わるだけ | 「コードを書く `/code`」と「外部操作を行う `/operate`」を明確に分離できる |
| 事前調査の教訓との整合 | #437 の F 案 (adapter-resolver 流用) と同型の「既存の分岐点に1値を足す」パターン | #437 で一度採用されかけて棄却された「新メカニズム新設」パターンに近い |

いずれの案も、`mcp_call` (読み取り専用検証) や Phase Handoff (フェーズ間引き継ぎ) など Layer 4 の既存プリミティブ自体は変更せずに利用できる点は共通している。差はもっぱら「実行主体をどのフェーズ (どの Skill) に置くか」にある。

### Decision: Option A (既存フェーズ拡張) を採用

理由:

1. **#437 の教訓との整合**: #437 は「新メカニズムより既存パターンの流用」を3段階の再考の末に確立した。Option B は新しい Skill・新しいラベル遷移・新しい SSoT 行を複数箇所に要求する点で、#437 が棄却した「新設」パターンに近い。Option A は `/code` の既存の route 分岐 (patch/pr) に3つ目の値 (operate) を足すだけであり、#437 最終案 (F 案: adapter-resolver 流用) と同型の「既存の分岐点への追加」である。
2. **ドキュメント SSoT 影響範囲の非対称性**: Option B は `docs/workflow.md`・`docs/tech.md`・`modules/execution-context.md`・`modules/autonomy-tier.md`・`kanban-automation.yml` など、新しい Skill の存在を前提にした6〜8箇所の SSoT 更新が必要になる。Option A は `modules/size-workflow-table.md` に route を1行追加し、`/code` の既存ステップに operate route のガードを挿入するだけで済む。
3. **フェーズラベルの流用可能性**: operate route は「diff がない」だけであり、「実装が完了し検証を待つ」という phase 上の意味は patch route と変わらない。既存の `phase/code` → `phase/verify` 遷移をそのまま流用でき、新しいラベル体系を設計する必要がない。
4. **概念的な役割は変わらない**: `/code` の役割は一貫して「Spec の Implementation Steps を実行する」ことであり、実行手段が「ファイルを変更して commit する」か「MCP/CLI/API を呼び出す」かは実装上の詳細に過ぎない。この差を Skill の分割理由にする必然性は薄い。

不採用理由 (Option B): 独立 Skill 化による「コマンド名の明快さ」というメリットはあるが、上記のドキュメント影響範囲の大きさに見合わない。将来 operate route の実行ロジックが十分に複雑化し `/code` の SKILL.md が可読性を失った場合は、その時点で `skills/code/operate-phase.md` のような Domain file への切り出し (progressive disclosure、`docs/tech.md` に既存の原則) で対応可能であり、独立 Skill 化を今すぐ選ぶ理由にはならない。

### Design: "operate route" の概要

Option A の具体化として以下の設計を採る (詳細実装は本 Issue の完了条件外であり、フォローアップ Issue のスコープとする — 後述「フォローアップアクション」参照)。

- **route 判定信号**: 既存の Size (`XS`〜`XL`) は「変更規模」を表す軸のまま維持し、新たに直交する軸として「diff-less 判定」を導入する。判定は `/spec` が作成する Spec の `## Changed Files` セクションが実質空 (対象がリポジトリ内ファイルではなく外部システム操作のみ) であることに基づく。新しい GitHub ラベルや Issue メタデータは追加しない — 既存の Spec 内容から機械的に判定できるため、`modules/l0-surfaces.md` に新しい L0 write を追加する必要がない。
- **`/spec` Step 18 (Size-to-Workflow Determination) の拡張**: 既存の「Changed Files のファイル数から Size を再評価する」ロジックに、「ファイル数が実質0かつ Implementation Steps が外部ツール操作のみで構成される場合は ROUTE=operate とする」分岐を追加する。
- **`/code` の拡張**: ROUTE=operate の場合、worktree 作成・commit・push・PR 作成をすべてスキップし、Implementation Steps に列挙された MCP/CLI/API 呼び出しをそのまま実行する。実行結果は次の2箇所に記録する (新しいアーティファクト種別は導入しない)。
  - Issue コメントとして `## Execution Log` (実行したツール名・引数の要約・観測結果) を投稿する — git diff の可視性に相当する役割を担う
  - `modules/phase-handoff.md` の既存フォーマットに実行結果を記録し、`/verify` が参照できるようにする
  - phase label は patch route と同じ遷移 (`phase/code` → `phase/verify`、`/review` を経由しない) を流用する
- **`mcp_call` は変更しない**: 「実行」は `/code` (operate route) が担い、「検証」は既存の `mcp_call` (読み取り専用) が担うという分離を維持する。Issue 本文 Notes が問うていた「実行ログとして記録する仕組み」は、`mcp_call` 自体を書き込み可能に拡張するのではなく、上記の Execution Log (Issue コメント + Phase Handoff) で満たす。これにより `mcp_call` の「書き込み・削除・外部送信の可能性があるツールは呼ばない」という既存の安全設計 (`modules/verify-executor.md`) を一切緩めずに済む。

### Phase handling for diff-less Issues (PR が存在しない場合の代替フロー)

| フェーズ | 通常の PR route (M/L) | 既存の patch route (XS/S) | 提案する operate route (diff-less) |
|---|---|---|---|
| `/code` | branch 作成 + commit + push + PR 作成 | worktree 経由で main へ直接 commit | worktree 不要。外部操作を直接実行し commit は行わない。Execution Log を Issue コメント + Phase Handoff に記録 |
| `/review` | full/light レビュー実行 | スキップ — 早期終了、"review not required" | **スキップ** — patch route と同じ理由 (PR が存在しない) に加え、そもそも diff が存在しないため事後レビューという概念自体が成立しない |
| `/merge` | squash merge 実行 | 実行なし — 直接 commit 済みのため merge 対象がない | **実行なし** — ブランチが存在しないため merge 対象がない (patch route と同一理由) |
| `/verify` | 実行 — post-merge AC 検証 | 実行 | **変更なし。そのまま実行** — 既存の verify command (`mcp_call` 等) が外部システムの状態を検証する。PR が存在しないことは `/verify` の動作に影響しない (patch route で既に確認済みの経路) |

**残存リスク (フォローアップで検討)**: PR route では「diff を作る (`/code`) → diff をレビューする (`/review`) → 反映する (`/merge`)」という「提案 → ゲート → 適用」の分離が git diff によって構造的に担保されている。operate route ではこの提案 (Implementation Steps に列挙された外部操作) と適用 (実際の MCP/CLI/API 呼び出し) が `/code` 内で同時に発生し、事後の diff レビューに相当する安全弁が存在しない。したがって `/spec` 時点で Implementation Steps に実行対象の外部操作を過不足なく列挙し、Issue が `phase/ready` に到達すること自体が実質的な唯一の事前ゲートになる。この非対称性は operate route 固有のリスクであり、既存の autonomy tier (`modules/autonomy-tier.md`) による L0 write 相当のゲーティングを外部システムへの書き込みにも適用すべきかは、フォローアップ Issue で検討する。

### フォローアップアクション

実装が必要と判断する。以下の内容でフォローアップ実装 Issue を1件起票することを推奨する (本 Issue のスコープには含めない — Issue 本文の完了条件は本 Spec への設計方針記録までであるため)。

**推奨タイトル**: `operate route: git diff を伴わない操作型 Issue 向けの /code 拡張`

**推奨スコープ (変更対象ファイル)**:
- `modules/size-workflow-table.md`: operate route を3つ目の route として追加。Size と diff-less 判定が直交する2軸である旨を明記する
- `skills/spec/SKILL.md` Step 18: Changed Files が実質空の場合に ROUTE=operate と判定するロジックを追加する
- `skills/code/SKILL.md`: ROUTE=operate 時の分岐 (worktree/commit/push/PR 作成のスキップ、外部操作の直接実行、Execution Log 記録、patch route と同一の label 遷移) を追加する
- `docs/workflow.md`・`docs/structure.md`・`docs/tech.md`: operate route の追加を反映する (Steering Docs sync)
- テスト: operate route 判定ロジックのユニットテストを追加する

**Size 見積り**: M〜L — 新しいアーキテクチャパターンの導入軸に該当するため Axis 2 で+1 調整が入る可能性が高い。正確な Size は当該 Issue の `/triage` 時に確定する。

**起票要否の位置づけ**: 本 Spec 作成 (`/spec`) の責務は設計方針の記録までであり、Issue 起票自体は行わない。`skill-proposals: true` が設定されているため、`/verify` の retrospective 集約ステップ (`modules/retro-proposals.md`) がこの推奨を Improvement Proposal として拾い上げる可能性がある。拾われなかった場合はユーザーが `/issue` で手動起票する。

## Changed Files

- `docs/spec/issue-958-diffless-operational-ac.md`: 本 Spec ファイル自身 (Issue の完了条件を満たす唯一の成果物。他に変更対象ファイルはない — 設計方針の実装はフォローアップ Issue のスコープ)

## Implementation Steps

1. 本 Spec の Overview セクション (Option Comparison / Decision / Design / Phase handling / フォローアップアクション) が Pre-merge の3件の rubric AC を過不足なく満たしていることを確認する。コード・ドキュメントへの変更は本 Issue のスコープに含まれない (→ AC1, AC2, AC3)

## Verification

### Pre-merge
- <!-- verify: rubric "Spec (docs/spec/issue-958-*.md) が、git diff を伴わない操作型タスクを『既存フェーズ (/code 等) の拡張』案と『新設の軽量フェーズ』案の両方について比較検討し、採用する設計方針とその選定理由を明記している" --> 既存フェーズ拡張 vs 新設フェーズの比較検討結果が Spec に記録されている
- <!-- verify: rubric "Spec が、採用方針のもとで git diff を伴わない Issue に対する /review・/merge・/verify フェーズの扱い (PR が存在しない場合の代替フローを含む) を具体的に定義している" --> PR が存在しない操作型 Issue に対する `/review`・`/merge`・`/verify` の扱いが Spec に定義されている
- <!-- verify: rubric "Spec が、採用方針に基づく次のアクション (実装 Issue の起票内容、または起票不要と判断した理由) を明記している" --> 採用方針に基づくフォローアップアクション (実装 Issue 起票の要否とその理由) が Spec に記録されている

### Post-merge
なし

## Notes

- Size=S (patch route) のため SPEC_DEPTH=light。Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップした。曖昧点解決は `/issue` フェーズで既に auto-resolve 済み (Issue 本文「Autonomous Auto-Resolve Log」参照)。
- Issue 本文の背景記述はコードベース調査で照合済みで、矛盾は検出されなかった。特に以下を実ファイルで確認した — `mcp_call` verify command は現在も読み取り専用検証に限定されていること (`modules/verify-executor.md`)、sibling issue #956・#957 はいずれも `phase/done` で解決済みであること、#437 が「adapter-resolver 流用」を最終決定として3段階の再考を経ていること (`docs/environment-adaptation.md` § Extension Guide Step 0 として明文化されている)。
- 本 Issue には Post-merge 条件がなく、`/review`・`/merge` は Size=S (patch route) につき通常通りスキップされる。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective。Acceptance Criteria が `TBD` のまま起票されていたため、Spec に設計方針が記録された時点を完了条件とする3件の rubric AC への具体化、比較検討軸 (#437 の教訓) の明記、sibling issue 番号 (#956・#957) の補完を自動解決 (auto-resolve) した記録。内容は既に Issue 本文 (Autonomous Auto-Resolve Log) に反映済みであり、本 Spec の設計内容に追加の対応は不要と判断した。 / https://github.com/saitoco/wholework/issues/958#issuecomment-4949567063

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps は「Spec の Overview が3件の rubric AC を満たすことの確認」のみであり、Spec は `/spec` フェーズの時点で既に全内容 (Option Comparison / Decision / Phase handling / フォローアップアクション) を含んで確定していたため、`/code` フェーズでの追加編集は発生しなかった。

### Design Gaps/Ambiguities
- N/A — 3件の rubric AC を full mode で個別に adversarial 判定した結果、いずれも Spec 内の該当セクション (Option Comparison/Decision、Phase handling for diff-less Issues、フォローアップアクション) で具体的に充足されており、gap は検出されなかった。

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec が既に3件の Pre-merge rubric AC を満たす内容で確定していたため、コード・ドキュメントへの追加変更は行わず、AC 充足の確認のみを実施した (Issue 本文「完了条件」および Spec Implementation Steps の記述に整合)。
- 3件の rubric AC はいずれも `docs/spec/issue-958-*.md` を明示的に対象とする特殊形であり、`verify-executor.md` の「rubric テキストに明示された file は grader 入力に含む」規定に基づき Spec 内容を直接判定した。

### Deferred Items
- フォローアップ実装 Issue (`operate route: git diff を伴わない操作型 Issue 向けの /code 拡張`) の起票は本 Issue のスコープ外。`skill-proposals: true` により `/verify` の retrospective 集約ステップが拾い上げる可能性がある (Spec 「起票要否の位置づけ」参照)。
- operate route 設計自体の実装 (`modules/size-workflow-table.md`・`skills/spec/SKILL.md`・`skills/code/SKILL.md` 等への反映) は上記フォローアップ Issue のスコープ。

### Notes for Next Phase
- 本 Issue には Post-merge 条件がなく、Size=S (patch route) につき `/review`・`/merge` は通常通りスキップされる。
- `/verify` は post-merge AC が存在しないため実質的にスキップとなる想定 (Spec Notes 参照)。

## Verify Retrospective

### Phase-by-Phase Review

#### issue / spec
- 設計検討 Issue の完了条件を「Spec への設計方針記録」とする 3 rubric AC への具体化 (#437 の「考察と判断の親 Issue」パターン踏襲) が機能し、pre-merge 3 件とも UNCERTAIN なく PASS 判定できた。

#### code / verify
- patch route で Spec (設計記録) を main へ直接コミット。全 AC PASS、post-merge 条件なしで phase/done へ遷移。

### Improvement Proposals
- operate route: git diff を伴わない操作型 Issue 向けの /code 拡張 — Spec のフォローアップアクション推奨に基づく実装 Issue。スコープ: modules/size-workflow-table.md (operate route 追加、Size と diff-less 判定の直交 2 軸を明記)、skills/spec/SKILL.md Step 18 (Changed Files 実質空 → ROUTE=operate 判定)、skills/code/SKILL.md (worktree/commit/push/PR スキップ + 外部操作直接実行 + Execution Log 記録 + patch route 同一 label 遷移)、docs/workflow.md・docs/structure.md・docs/tech.md の Steering Docs sync、判定ロジックのユニットテスト。Size 見積り M〜L。残存リスク (提案→ゲート→適用分離の喪失に対する autonomy tier ゲーティング適用可否) の検討も含む。
