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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- 新規ファイル `modules/execution-context.md` を作成し、fork/main context の判定基準 (`--non-interactive` フラグ) と各 context の制約 (AskUserQuestion 可否・verify mode) を SSoT として文書化した
- `docs/tech.md` クロスリファレンスは fork context テーブルの closing 行直後に 1 行追加する方式を採用 (Spec Notes 通り)
- docs/structure.md のカウントは 38 → 40 に直接更新 (既存乖離 +1、本 PR 追加 +1 を同時修正)

### Deferred Items
- `execution-context.md` を明示的に Read するスキルが今後現れた場合は Callers セクションを更新する必要がある (現時点では "none (SSoT reference)")
- 既存スキルへの `Read execution-context.md` 追加は本 Issue のスコープ外 (将来の onboarding 改善 Issue に委ねる)

### Notes for Next Phase
- 全 5 つの pre-merge AC が verify-executor full mode で PASS 確認済み (file_exists, rubric, file_contains x2, grep)
- テスト 926/926 PASS、forbidden-expressions チェック PASS
- 変更対象は docs/ と modules/ のみ (scripts/・skills/ 変更なし)。/review での確認ポイントは docs/tech.md クロスリファレンスの位置と execution-context.md の内容品質が主
