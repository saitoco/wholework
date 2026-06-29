# Issue #867: tech.md に safe/full mode narrative 追加と spec SKILL.md フラグ文書化

## Overview

`/doc sync --deep` の narrative drift check で検出された 2 つのドキュメント乖離を修正する。

1. **C10** — `docs/tech.md` Architecture Decisions の fork-context テーブル周辺に safe mode / full mode の narrative が存在しないため、tech.md 単独で実行モデルの安全性が把握できない
2. **C5** — `skills/spec/SKILL.md` Step 0 の引数説明に `--opus` / `--fable` / `--max` フラグが文書化されておらず、ユーザーの discover-ability が低い

## Changed Files

- `docs/tech.md`: Architecture Decisions セクションに safe vs full mode の narrative bullet を追加 (fork-context テーブル末尾の `modules/execution-context.md` 参照行の直後、`/auto` skill bullet の前)
- `skills/spec/SKILL.md`: Step 0 の `--light`/`--full` リストの直後 (`**Input**` 行の前) に **Model selection flags** サブセクションを追記
- `docs/ja/tech.md`: `## アーキテクチャ決定` セクションに safe/full mode narrative の日本語翻訳 bullet を追加 (fork-context テーブル末尾行の直後、`/auto` スキル bullet の前)

## Implementation Steps

1. `docs/tech.md` line 51 (空行) の後、line 52 (`- **\`/auto\` skill**:`) の前に以下を挿入 (→ AC 1):
   ```
   - **Verify command execution mode (safe vs full)**: `/review` runs in **safe mode** (pre-merge): external commands and side-effectful verify command types fall back to CI reference, and conditions that cannot be safely evaluated pre-merge return UNCERTAIN. `/verify` runs in **full mode** (post-merge): all verify command types execute including shell commands and external service calls. This split ensures pre-merge reviews stay reproducible while post-merge verification can exercise real side effects. SSoT and per-mode policy: [`modules/execution-context.md`](../modules/execution-context.md).
   ```

2. `skills/spec/SKILL.md` line 43 (`3. Explicit...`) と line 45 (`**Input**: ARGUMENTS...`) の間に以下を挿入 (→ AC 2):
   ```
   
   **Model selection flags (L-size only)**:
   - `--opus`: Use Opus 4.x instead of the default Sonnet for design quality on L-size specs
   - `--fable`: Use Fable 5 (Mythos class; opt-in, cost-sensitive — see `docs/tech.md` § Phase-specific model and effort matrix for cost/retention constraints)
   - `--max`: Override effort to `max` (Opus / Fable 5 only)
   ```

3. `docs/ja/tech.md` line 41 (execution-context.md 参照行) の後、line 43 (`- **\`/auto\` スキル**:`) の前に以下を挿入 (→ AC 3):
   ```
   
   - **verify command 実行モード（safe vs full）**: `/review` は **safe mode**（プリマージ）で動作する: 外部コマンドや副作用のある verify command タイプは CI 参照にフォールバックし、プリマージで安全に評価できない条件は UNCERTAIN を返す。`/verify` は **full mode**（ポストマージ）で動作する: shell コマンドや外部サービス呼び出しを含む全 verify command タイプが実行される。この分離により、プリマージのレビューは再現性が保たれ、ポストマージの検証は実際の副作用を発揮できる。SSoT とモード別ポリシー: [`modules/execution-context.md`](../modules/execution-context.md)。
   ```

## Verification

### Pre-merge

- `docs/tech.md` Architecture Decisions に safe mode / full mode の narrative bullet (両モードの違いと利用フェーズの説明) が追加されている <!-- verify: rubric "docs/tech.md の Architecture Decisions セクションに、safe mode と full mode を主題とする narrative bullet が存在し、/review が safe / /verify が full である旨と、両モードの違い (external command 実行制限 / UNCERTAIN 返却など) が説明されている" --> <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "safe mode" -->
- `skills/spec/SKILL.md` に `--opus` / `--fable` / `--max` フラグの説明が含まれている <!-- verify: rubric "skills/spec/SKILL.md の引数説明セクションに、--opus / --fable / --max の 3 つのフラグの存在と用途が記載されている" --> <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 0" "--opus" -->
- `docs/ja/tech.md` の `## アーキテクチャ決定` セクションに safe mode / full mode の narrative が反映されている <!-- verify: section_contains "docs/ja/tech.md" "## アーキテクチャ決定" "safe mode" -->

### Post-merge

- 次回 `/spec --help` 実行時に `--opus` / `--fable` / `--max` のフラグ説明が表示される <!-- verify-type: opportunistic -->
- 次回 `/doc sync --deep` narrative drift check で C5 / C10 が解消されている <!-- verify-type: manual -->

## Notes

- docs-only の変更 (A) と SKILL.md 編集 (B) の組み合わせ
- safe / full mode は `docs/product.md` § Terms で定義済み。tech.md への追加は「実装モデルとしての位置づけ」を補足するもので重複ではない
- `--max` は `--opus` または `--fable` と組み合わせた場合のみ有効 (Opus / Fable 5 専用) の注記を SKILL.md に含める
- SKILL.md の挿入位置: Step 0 の `--light`/`--full` フラグ説明直後 (スタイル一貫性を優先)
- `docs/ja/tech.md` は `/doc translate` 自動生成対象ではなく手動翻訳ファイル — AC に追加して `section_contains` で verify

## issue retrospective

### 自動解決した曖昧ポイント (Auto-Resolve Log)

**1. docs/ja/tech.md のスコープ**
- **選択**: AC に追加し `section_contains "docs/ja/tech.md" "## アーキテクチャ決定" "safe mode"` で verify
- **理由**: Proposal に「翻訳ミラー (`docs/ja/tech.md`): A の追加を反映する」と明記されている。docs/ja/tech.md は `/doc translate` で自動生成されるファイルではなく手動翻訳ファイルと判断。verify-classifier.md の "Translation File Condition Verification" ガイドラインに従い `file_contains` / `section_contains` で `auto` 検証可能。
- その他候補: AC に含めず Proposal のみの記述とする (→ 採用せず: Proposal 明記事項を AC に反映するのが一貫性を保つ)

**2. `--max` フラグの適用条件**
- **選択**: "Opus / Fable 5 のみ有効" の注記を SKILL.md の引数説明に含める
- **理由**: `docs/tech.md` L86 に「Opus: xhigh (default), max (explicit `--max`)」と記載されており、`--max` が Opus / Fable 5 専用の effort override である旨が SSoT で確定している。実装の正確性を担保するため注記を明示する。
- その他候補: 注記なしで `--max` のみ記載 (→ 採用せず: 適用条件が不明確になる)

**3. SKILL.md フラグ挿入位置**
- **選択**: Step 0: Mode Detection 内の既存 `--light` / `--full` リストの直後に追記
- **理由**: `--light` / `--full` と同様にモード選択フラグであり、同一箇所に集約するのがユーザーの discovery-ability に最も効果的。`skill-help.md` の help 生成が SKILL.md body から `--` フラグを抽出するため、Step 0 への追記で `--help` 出力に自動反映される。
- その他候補: 別サブセクション "Model flags" を設ける (→ 採用せず: 現在 SKILL.md に専用セクションはなく、過剰な構造化になる)

### AC 変更内容

- **追加 (Pre-merge)**: `docs/ja/tech.md` 翻訳ミラー更新の AC を追加 (Proposal 明記事項を反映)
- **補強**: 各 rubric AC に `section_contains` 補完 verify command を追加 (機械的な安全網)
- **変更 (Post-merge)**: `/spec --help` 確認条件を `verify-type: manual` → `verify-type: opportunistic` に変更 (実行パターンが "スキル実行時に検証" であり opportunistic 基準に合致)

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (auto-resolved ambiguity points + AC changes) / https://github.com/saitoco/wholework/issues/867#issuecomment-4831439439
  - `docs/ja/tech.md` スコープ: 手動翻訳ファイルと判断、AC に追加し `section_contains` で verify
  - `--max` フラグ適用条件: "Opus / Fable 5 のみ有効" の注記を SKILL.md に含める
  - SKILL.md 挿入位置: `--light`/`--full` リストの直後
  - Pre-merge rubric AC に `section_contains` 補完 verify command を追加済み
  - Post-merge `/spec --help` 条件を `verify-type: manual` → `verify-type: opportunistic` に変更済み

## spec retrospective

### Minor observations
- Nothing to note.

### Judgment rationale
- Issue retrospective コメントに 3 つの曖昧ポイントの解決策が明記されていたため、spec フェーズでの追加判断は不要だった。コメント内容をそのまま Spec に転記することで設計の一貫性を維持した。
- SPEC_DEPTH=light (Size S) のため、詳細な曖昧点分析 (Step 7/8) をスキップ。Issue retrospective が代替情報源として機能し問題なかった。

### Uncertainty resolution
- Nothing to note.

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- `docs/tech.md` の safe/full mode narrative bullet は fork-context テーブルの直後 (`/auto` skill bullet の前) に配置。`modules/execution-context.md` への参照を重複させず、SSoT として参照するリンクを付ける形を採用した。
- `skills/spec/SKILL.md` の model flags は Step 0 の `--light`/`--full` リスト直後に挿入。`--help` 出力への自動反映を優先した。
- `docs/ja/tech.md` は `/doc translate` 自動生成ではなく手動翻訳ファイルのため、AC に含めて `section_contains` で verify する方針を採用。

### Deferred Items
- None

### Notes for Next Phase
- 3 ファイルへの変更はすべて純粋な追記 (既存コードの変更なし) — コンフリクトリスクは低い
- SKILL.md は `.claude/` 外ファイルのため Edit ツールで直接編集可能
- `docs/ja/tech.md` の挿入位置は line 41 末尾の後、line 43 (`/auto` スキル bullet) の前
