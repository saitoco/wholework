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

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (auto-resolved ambiguity points + AC changes) / https://github.com/saitoco/wholework/issues/867#issuecomment-4831439439
  - `docs/ja/tech.md` スコープ: 手動翻訳ファイルと判断、AC に追加し `section_contains` で verify
  - `--max` フラグ適用条件: "Opus / Fable 5 のみ有効" の注記を SKILL.md に含める
  - SKILL.md 挿入位置: `--light`/`--full` リストの直後
  - Pre-merge rubric AC に `section_contains` 補完 verify command を追加済み
  - Post-merge `/spec --help` 条件を `verify-type: manual` → `verify-type: opportunistic` に変更済み
