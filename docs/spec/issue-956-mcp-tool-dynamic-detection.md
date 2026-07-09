# Issue #956: issue: MCPツール検知にセッション動的検知を追加

## Overview

`/issue` の `mcp_call` 提案ロジックは、`.wholework.yml` の `capabilities.mcp` による静的宣言 (`MCP_TOOLS`) のみに依存しており、宣言が空の場合はセッションで実際に MCP ツールが利用可能でも `mcp_call` 提案が完全にスキップされる (tofas #250 で実際に発生し、Sanity CMS の記事タイトル修正が `verify-type: manual` の Post-merge 条件として書かれてしまった)。

`docs/environment-adaptation.md` § Layer 2 (`### MCP Tool Detection: Declaration-first Fallback`) には、「宣言優先 → 宣言なし時 ToolSearch 動的検知 → 両方なしで非提案」という 3 段階フローが既にアーキテクチャ SSoT として文書化されている。しかし実装側の `skills/issue/mcp-call-guidelines.md` は Step 1 (宣言優先) のみを実装しており、`skills/issue/SKILL.md` (Step 4 「MCP tool detection and mcp_call proposal」) も「宣言が空なら mcp_call を非提案」で止まっている。本 Issue は新規メカニズムの設計ではなく、既存の Layer 2 アーキテクチャを実装側に反映する **drift 修正**である。

## Changed Files

- `skills/issue/mcp-call-guidelines.md`: frontmatter から `load_when: capability: mcp` を削除 (無条件ロードに変更)。本文を書き換え、`docs/environment-adaptation.md` § Layer 2 と整合する 3 段階の Declaration-first Fallback (1. 宣言あり→宣言を信頼、ToolSearch 実行なし。2. 宣言なし→セッション内に見えている `mcp__` 接頭辞ツール名を ToolSearch `select:<tool_name>` で存在確認・読み取り専用性確認した上で提案。3. どちらもなし→ `mcp_call` 非提案) を記載する
- `skills/issue/SKILL.md`: New Issue Creation Step 4 (「Classify Acceptance Criteria and Assign Verify Commands」) の "**MCP tool detection and mcp_call proposal (conditional):**" 小見出し直下の指示文を、"If non-empty, read `skills/issue/mcp-call-guidelines.md` and follow the "Declaration Priority" section. If empty, skip `mcp_call` hints." から「常に `mcp-call-guidelines.md` を読み Declaration-first Fallback 手順に従う」形の記述に変更 (Existing Issue Refinement Step 7 はこのブロックに委譲する一文のみのため、変更対象はここ1箇所)
- `docs/environment-adaptation.md`: Layer 3 「Domain Files (exhaustive)」表の `skills/issue/mcp-call-guidelines.md` 行 (Load Condition / `load_when` 列) を、`skills/spec/figma-design-phase.md` 行と同じ "_(none — runtime-detected)_" パターンに更新 (frontmatter 変更との整合性維持)
- `docs/ja/environment-adaptation.md`: [Steering Docs sync candidate] 上記と同じ Domain Files 表の該当行を日本語側でも同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

## Implementation Steps

1. `skills/issue/mcp-call-guidelines.md` の frontmatter と本文を書き換える。frontmatter から `load_when: capability: mcp` を削除し、本文に 3 段階の Declaration-first Fallback 手順 (宣言優先 / ToolSearch 動的検知 / 非提案) を `docs/environment-adaptation.md` § Layer 2 への参照付きで記載する (→ AC1, AC2, AC3, AC4)
2. `skills/issue/SKILL.md` の「MCP tool detection and mcp_call proposal (conditional)」指示文を更新し、Step 2 で取得済みの `MCP_TOOLS` の空/非空にかかわらず常に `mcp-call-guidelines.md` を読み、その Declaration-first Fallback 手順に従うよう変更する (after 1) (→ AC3)
3. `docs/environment-adaptation.md` と `docs/ja/environment-adaptation.md` の Domain Files 表にある `mcp-call-guidelines.md` 行を、ステップ1の frontmatter 変更と整合する形に更新する (after 1) (→ AC3 の SSoT 整合性維持のための付随修正)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/issue/mcp-call-guidelines.md が、MCP_TOOLS が未宣言 (空) の場合に ToolSearch 等でセッション内の MCP ツールを動的に検知するフォールバック手順を記載している" --> `skills/issue/mcp-call-guidelines.md` に動的検知フォールバックの手順が追記されている (`load_when` ゲーティングにより空宣言時にファイル自体が読み込まれない問題への対処を含む)
- <!-- verify: file_contains "skills/issue/mcp-call-guidelines.md" "ToolSearch" --> 動的検知手順が ToolSearch を用いる形で記載されている
- <!-- verify: rubric "MCP_TOOLS の解決ロジックが docs/environment-adaptation.md § Layer 2 の宣言優先フォールバック (宣言あり→ToolSearch skip、宣言なし→ToolSearch動的検知、両方なしでmcp_call非提案) と整合する優先順位で skills/issue/mcp-call-guidelines.md および skills/issue/SKILL.md に定義されている" --> 静的宣言と動的検知の優先順位が `docs/environment-adaptation.md` の既存 SSoT と整合する形で明記されている
- <!-- verify: file_contains "skills/issue/mcp-call-guidelines.md" "environment-adaptation.md" --> 実装が `docs/environment-adaptation.md` の Layer 2 定義を参照している (SSoT からの乖離防止)

### Post-merge
なし

## Notes

- Size=S (patch route) のため SPEC_DEPTH=light。Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。曖昧点解決は `/issue` フェーズで既に Auto-Resolve 済み (Issue 本文 "Auto-Resolved Ambiguity Points" 参照)。Issue 本文の背景記述はコードベース調査で実際のファイル内容と照合済みであり、矛盾は検出されなかった
- **frontmatter `load_when` は `/issue` 上では機械的に評価されていない**: `modules/domain-loader.md` を呼び出すのは `/spec`, `/code`, `/review`, `/verify` のみで `/issue` は含まれない (`docs/environment-adaptation.md` 165行目)。そのため `mcp-call-guidelines.md` の `load_when` frontmatter は実際には `/issue` 上で機械的なゲーティングを行っておらず、実際のゲートは `skills/issue/SKILL.md` 内の平文の条件分岐 ("If non-empty, read... If empty, skip") が担っている。したがって機能的な修正の主眼は SKILL.md 側 (Implementation Step 2) であり、`mcp-call-guidelines.md` の frontmatter 変更 (Implementation Step 1 の一部) と `docs/environment-adaptation.md` 側の表更新 (Implementation Step 3) は、SSoT ドキュメントとの整合性維持を目的とした付随的修正である
- **ToolSearch の実際の挙動**: ToolSearch は「未知の MCP ツールを空クエリで列挙する」機能ではなく、既にセッションのシステムリマインダー等で名前が可視化されているツールに対して `select:<tool_name>` 等のクエリでスキーマを取得する検索ツールである。したがって Step 2 (動的検知) の実装は「セッションコンテキストに `mcp__` 接頭辞のツール名が見えているか」をまず確認し、見つかった場合に ToolSearch で存在・読み取り専用性を確認する、という手順になる (`skills/issue/SKILL.md` の既存ガイダンス "use ToolSearch with `select:<tool_name>` to confirm existence and read-only nature" と同じ確認ステップを踏襲)

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective。`docs/environment-adaptation.md` § Layer 2 が本 Issue の要求する 3 段階フローを既に SSoT として文書化済みと判明したことを記録し、Auto-Resolved Ambiguity Points (変更対象ファイル、優先順位/マージ方針) を記載 (内容は Issue 本文の Notes / Auto-Resolved Ambiguity Points に反映済み) / https://github.com/saitoco/wholework/issues/956#issuecomment-4923722416

## Code Retrospective

### Deviations from Design
- N/A（Implementation Steps 1〜3 と Changed Files の4ファイルを完全に一致させて実装した）

### Design Gaps/Ambiguities
- `worktree-lifecycle.md` の Entry section (`own`/`foreign`/`none` 判定) は、同名ブランチのワークツリーが既に存在するが起動プロセスが終了済み (stale lock) のケースを想定していない。本 Issue では前回セッションが crash した際の未コミット実装 (Implementation Steps 1〜3 と完全一致) が `.claude/worktrees/code+issue-956` に残っていたため、ロックファイルの PID (`ps -p`) でプロセス終了を確認したうえで `EnterWorktree(path: ...)` により手動で再開した。今回は内容が Spec と一致していたため再利用できたが、内容が不完全・矛盾していた場合の判断基準 (再利用 vs 破棄) は明文化されていない。

### Rework
- N/A（前回セッションの未コミット実装をそのまま再利用し、修正は不要だった）

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 前回セッション (crash) が `.claude/worktrees/code+issue-956` に残した未コミット実装 (4ファイル) が Spec の Implementation Steps と完全一致していたため、再実装せずそのまま検証・コミットして再利用した
- Pre-merge AC (rubric ×2, file_contains ×2) を verify-executor full mode で実行し全件 PASS を確認、Issue のチェックボックスを更新済み

### Deferred Items
- None

### Notes for Next Phase
- `/verify` は Post-merge AC が「なし」のため、実質的にチェックすべき項目はない
- 本実装は `skills/issue/mcp-call-guidelines.md` の `load_when` frontmatter を削除し無条件ロードに変更しているため、`/issue` を実行する既存プロジェクトすべてで本ファイルが読み込まれるようになる (挙動変化は Declaration-first Fallback 内で `MCP_TOOLS` 分岐により吸収される設計)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- N/A — Issue 本文の Auto-Resolved Ambiguity Points (対象ファイル選定、優先順位/マージ方針) が SPEC_DEPTH=light の Spec にそのまま反映されており、齟齬はなかった。

#### design
- N/A — Changed Files (4ファイル) と Implementation Steps (3ステップ) の対応が一貫しており、設計上の抜け漏れは見当たらなかった。

#### code
- Design Gaps/Ambiguities で記録された通り、前回セッションが crash して `.claude/worktrees/code+issue-956` に未コミット実装を残した状態からの再開が発生した。`worktree-lifecycle.md` の Entry section は `own`/`foreign`/`none` の3判定のみを持ち、「プロセス終了済みの stale worktree に、Spec と一致する未コミット実装が残っている」ケースの扱い (再利用 vs 破棄) を明文化していない。今回はロックファイルの PID 確認 + 手動 `EnterWorktree(path: ...)` + Spec との内容一致確認という即興対応で正しく再利用できたが、内容が不完全・矛盾していた場合の判断基準がなく、`worktree-lifecycle.md` は spec/code/review/merge/verify 全スキルの共有モジュールであるため再発時の影響範囲は広い (Improvement Proposals 参照)。

#### review
- N/A — Size=S (patch route) のため review フェーズなし。

#### merge
- N/A — Size=S (patch route) のため merge フェーズなし (main 直コミット)。

#### verify
- Pre-merge 4件 (rubric ×2, file_contains ×2) はいずれも UNCERTAIN なく一発 PASS。`docs/environment-adaptation.md` § Layer 2 の記述と実装内容 (`mcp-call-guidelines.md`, `SKILL.md`) を直接照合し、rubric 条件文が要求する3段階フローとの整合性を確認した。Post-merge 条件はなし。verify command 自体の不整合は検出されなかった。

### Improvement Proposals
- **`worktree-lifecycle.md` に stale worktree 再開時の再利用/破棄判断基準を追加**: 現在の Entry section は `detect-foreign-worktree.sh` による `own`/`foreign`/`none` の3値判定のみを持ち、「起動プロセスが終了済み (stale lock) だが worktree ディレクトリに未コミット実装が残っている」ケースを扱う手順がない。判断基準の例: (a) 残存内容が対象 Issue の Spec Implementation Steps と一致するかを確認し、一致すれば再利用、(b) 不一致または確認不能なら破棄して `run-code.sh`/`run-spec.sh` 等を最初からやり直す。`worktree-lifecycle.md` は spec/code/review/merge/verify の全スキルが参照する共有モジュールのため、影響範囲が広く再発性もある構造的な gap (Tier 1 相当)。
