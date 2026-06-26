# Issue #755: modules/execution-context: skill 実行 context (fork / main) 判定を reusable module 化

## Overview

`docs/tech.md` には fork context / main context の 2 モードと safe/full verify command mode policy が定義されているが、判定ロジックは各 skill の caller context 経由でのみ伝わっており、reusable な module が存在しない。新 skill 作成時に "fork context safe mode 制約" の意識が薄れるリスクを除去するため、`modules/execution-context.md` を新規作成し、各 skill SKILL.md で declarative に参照できる判定基準と制約の SSoT にする。

## Changed Files

- `modules/execution-context.md`: 新規作成 — fork context / main context 判定基準、verify command mode (safe/full) との対応、各 skill の context 対応表を文書化 — bash 3.2+ 非依存 (shell script なし)
- `docs/tech.md`: "fork context vs main context" 節のテーブル直後に `modules/execution-context.md` へのクロスリファレンスを追加
- `docs/structure.md`: modules/ ファイルカウントを "(38 files)" → "(40 files)" に更新、Key Files > Modules セクションに execution-context.md エントリ追加
- `docs/ja/tech.md`: translation sync — "fork context vs main context" テーブル直後に日本語クロスリファレンスを追加
- `docs/ja/structure.md`: translation sync — ファイルカウントと Key Files > Modules セクション更新

## Implementation Steps

1. `modules/execution-context.md` を新規作成する (→ AC1, AC2, AC3, AC4)
   - Purpose セクション: skill execution context (fork vs main) の判定基準と各コンテキストでの制約の SSoT
   - Context 判定基準: ARGUMENTS に `--non-interactive` フラグがある → fork context (run-*.sh 経由の headless 実行)、ない → main context (in-session 実行)
   - Per-skill context 対応表: skill / context / verify mode / AskUserQuestion の 4 列。tech.md の fork context 表をコンパクトに参照可能な形で再掲
   - Context 制約セクション:
     - Fork context: AskUserQuestion 使用不可、verify-executor は safe mode で呼び出す (`command`/`build_success` は UNCERTAIN)
     - Main context: AskUserQuestion 使用可、verify-executor は full mode で呼び出す (全 verify command 実行可能)
   - "How to reference" セクション: "Read `${CLAUDE_PLUGIN_ROOT}/modules/execution-context.md` and determine current context based on ARGUMENTS" パターン
   - Callers セクション: 初期値として "none (SSoT reference)" を記録

2. `docs/tech.md` に cross-reference を追加する (after Step 1) (→ AC5)
   - 追加位置: "fork context vs main context" bullet 内のスキル対応テーブルの直後 (tech.md の `doc | No | ...` 行の後、次の bullet が始まる前の空行の後)
   - 追加テキスト: `  For context determination criteria and per-context constraints, see [\`modules/execution-context.md\`](../modules/execution-context.md).`

3. `docs/structure.md` を更新する (after Step 1)
   - Directory Layout の "(38 files)" → "(40 files)" に変更 (現在の実カウントは 39 で既に 1 乖離あり; 本 PR 追加後は 40)
   - Key Files > Modules セクションに追加 (alphabetical 位置: `domain-loader.md` エントリと `filesystem-scope.md` エントリの間):
     `- \`modules/execution-context.md\` — execution context (fork vs main) determination criteria and per-context constraints (verify command safe/full mode policy)`

4. `docs/ja/tech.md` と `docs/ja/structure.md` を translation sync する (after Steps 2, 3)
   - `docs/ja/tech.md`: fork context 表直後に対応する日本語クロスリファレンスを追加
   - `docs/ja/structure.md`: ファイルカウントと execution-context.md エントリを日本語で追加

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/execution-context.md" --> `modules/execution-context.md` が新規作成されている
- <!-- verify: rubric "modules/execution-context.md が fork context と main context の判定基準と、各コンテキストでの制約 (verify command の safe/full mode 含む) を明示している" --> module が context 判定基準と制約を網羅している
- <!-- verify: file_contains "modules/execution-context.md" "fork context" --> execution-context.md に fork context への言及がある (rubric 補完)
- <!-- verify: file_contains "modules/execution-context.md" "safe mode" --> execution-context.md に safe mode 制約への言及がある (rubric 補完)
- <!-- verify: grep "execution-context" "docs/tech.md" --> `docs/tech.md` が `modules/execution-context.md` への参照を含む

### Post-merge

- 次回新 skill 作成時に execution-context.md を参照して context check が標準化されることを観察 (verify-type: manual)

## Notes

- `docs/structure.md` のモジュールカウントは現在 "(38 files)" だが実際の modules/ 配下は 39 ファイル (1 乖離あり)。本 PR で execution-context.md を追加した後は 40 が正しい値となるため、直接 "(40 files)" に更新する。
- tech.md cross-reference の追加位置は "fork context vs main context" bullet 内テーブルの closing 行 (`doc | No | ...` 行) の直後。`- **\`/auto\` skill**: ...` 次 bullet が始まる前の空行に挿入する。
- Auto-resolve: Issue comment (2026-06-26T02:59:33Z) に記録された 3 点の Auto-Resolve Log に従い実装する。(1) 新規ファイル作成 (verify-executor.md 拡張ではない)、(2) ファイル名は `modules/execution-context.md` に固定、(3) AC3 は rubric ではなく `grep "execution-context" "docs/tech.md"` を使用。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective コメント (2026-06-26T02:59:33Z): Auto-Resolve Log (3 点) と AC 変更サマリーを含む。判断根拠を Spec の Notes セクションと Implementation Steps に反映済み。

## Code Retrospective

### Deviations from Design

- N/A (Spec の実装ステップをそのまま実行)

### Design Gaps/Ambiguities

- `docs/structure.md` のモジュールカウント表記は "(38 files)" だったが実態は 39 ファイル (既存の 1 乖離)。Spec の Notes に事前記載あり。本 PR で execution-context.md を追加した後の正しい値 40 を直接設定した。
- `execution-context.md` の Callers セクションに初期値として "none (SSoT reference)" と記録したが、skills が `--non-interactive` 検出パターンを用いて暗黙的に参照する構造であるため、この表現は正確。明示的に Read するスキルが増えた場合は更新が必要。

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `modules/execution-context.md` が「SSoT」を謳うにもかかわらず、safe mode で実行可能なコマンドの列挙が `verify-executor.md` と乖離していた。新規 SSoT モジュール作成時は、参照先 (verify-executor.md) と対象箇所 (Context Constraints テーブル) の双方向整合を確認する必要がある。
- "How to Reference" セクションの例示コード (code skill の参照パターン) が不正確だった。参照元に存在しない `(Step 0)` への言及が混入。例示は実装から逆引きするのではなく、Callers セクションと同期して記述するか、抽象的なパターンのみ示すべき。

### Recurring Issues

- 2件の SHOULD 問題はいずれも「SSoT を謳うモジュールの記述と実際の実装との乖離」という同一パターン。新規 SSoT module を作成する際は、参照元ドキュメントとのクロスチェック (実際のコマンドリスト、参照例の正確性) を実装チェックリストに加えることを検討する。

### Acceptance Criteria Verification Difficulty

- 5 件すべて PASS (UNCERTAIN ゼロ)。`file_exists`, `file_contains`, `grep` は機械的検証が可能で、rubric も明確な判定基準だったため UNCERTAIN なし。AC 設計として良好。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #757 をスカッシュマージ (`mergeable=true`, CI SUCCESS, approved)。コンフリクトなし。
- `closes #755` を含む PR が `main` にマージされたため、Issue #755 は自動クローズ。
- Phase Handoff を `merge` フェーズとして更新 (review フェーズの handoff を rotation で置換)。

### Deferred Items
- 既存スキルへの `Read execution-context.md` 追加は本 Issue のスコープ外 (review フェーズから引継ぎ)
- 次回新 skill 作成時に execution-context.md を参照して context check が標準化されることを観察 (post-merge 観察事項)

### Notes for Next Phase
- マージ済み。verify フェーズは post-merge AC のみ (手動観察)。
- `modules/execution-context.md` は main ブランチに含まれる。verify command は file_exists / file_contains / grep の 3 種。
- None (特記なし)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC 設計が良好 (file_exists / file_contains / grep / rubric を組み合わせ機械的検証可能、UNCERTAIN ゼロ)。
- Auto-Resolved Ambiguity Points (3 点) を Issue 段階で解決し、Spec に Notes として継承した運用が機能。

#### code
- `docs/structure.md` の "(38 files)" 既存乖離を本 PR 内で同時修正 (38 → 40)。Spec の Notes に事前記載されていたため、code phase で意識的に対応できた。

#### review
- 2 件の SHOULD: (a) Context Constraints テーブルの safe-mode コマンド列挙が `verify-executor.md` と乖離、(b) "How to Reference" 例示に存在しない `(Step 0)` 言及が混入。いずれも修正済 (review phase で graft)。
- 共通パターン: 「SSoT を謳うモジュールの記述と実装との乖離」。新規 SSoT モジュール作成時のクロスチェックが弱い。

#### merge
- スカッシュマージ正常、コンフリクトなし、CI SUCCESS。観察事項なし。

#### verify
- pre-merge 5 件すべて自動 PASS、UNCERTAIN ゼロ。AC 設計の効果を確認。
- post-merge は manual observation 1 件のみ (将来 skill 作成時の参照標準化を観察)。

### Improvement Proposals

- **新規 SSoT モジュール作成時のクロスチェック checklist**: `/code` または `/spec` の SKILL.md に、新規 SSoT モジュール (`modules/<name>.md` で "SSoT" / "authoritative reference" を謳うもの) を作成する場合の implementation checklist を追加する。最低限以下の項目を含める:
  1. 参照元ドキュメント (e.g., `verify-executor.md` の command list) と SSoT モジュール内の関連テーブル/列挙の整合性確認
  2. "How to Reference" 等の例示コードは Callers セクションと同期、または抽象パターンのみ示す (実装からの逆引きで誤情報を混入しない)
  - 動機: #755 review で発覚した 2 件の SHOULD は同一パターン「SSoT モジュールの記述と実装との乖離」。SSoT モジュールは下流の参照基準として機能するため、初版の正確性が後続スキル開発の品質を左右する。
  - 対象 skill: `/code` (実装段階での checklist)、または `/spec` (設計段階でのクロスリファレンス計画)。
