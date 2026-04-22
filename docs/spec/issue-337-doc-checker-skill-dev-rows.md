# Issue #337: doc-checker: Extract skill-dev-specific Change Types Rows to skill-dev-doc-impact.md

## Overview

`modules/doc-checker.md` の Change Types 表（L33–L37、全 5 行）のうち skill-dev 固有の 3 行（Skill / Agent-shared-module / Script）を新 Domain file `modules/skill-dev-doc-impact.md` へ移譲する。

- doc-checker.md 本体は汎用 2 行（Workflow phase changes / Project structure changes）のみ残存
- 新 Domain file は `type: domain` + `load_when: file_exists_any: [scripts/validate-skill-syntax.py]` の frontmatter を持つ
- doc-checker.md の Impact Determination Criteria セクションに条件付きロード指示を追加し、/spec・/code の既存呼び出し経路から新 Domain file が参照されるよう整備する
- `docs/environment-adaptation.md` Layer 3 Domain Files 表に新エントリを追加する

## Changed Files

- `modules/skill-dev-doc-impact.md`: new file — skill-dev 固有 Change Types 3 行を含む Domain file
- `modules/doc-checker.md`: Change Types 表から 3 行削除 + 条件付きロード指示追加
- `docs/environment-adaptation.md`: Layer 3 Domain Files 表に新 Domain file 行追加
- `docs/ja/environment-adaptation.md`: 翻訳同期（新 Domain file 行をアルファベット順挿入）

## Implementation Steps

1. `modules/skill-dev-doc-impact.md` を新規作成（→ 検収 A, B, C, D）
   - frontmatter: `type: domain`、`load_when: file_exists_any: [scripts/validate-skill-syntax.py]`
   - `skill:` フィールドは省略可（domain-loader の Glob 対象外のため純粋に文書用）
   - 既存パターン（`skills/review/skill-dev-recheck.md`）に準拠したヘッダ文「This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.」を冒頭に記述
   - doc-checker.md の L33, L34, L37 の 3 行（Skill / Agent-shared-module / Script Change Types）を "## Change Types" セクションとして記述
   - コンテンツは doc-checker.md に合わせて `(exhaustive)` マーカー付きテーブル形式を踏襲

2. `modules/doc-checker.md` の Change Types 表を更新（after 1）（→ 検収 E）
   - L33（Skill）, L34（Agent/shared module）, L37（Script）の 3 行を削除
   - 表ラベルを `**Change Types (generic, exhaustive):**` に変更（skill-dev 固有行が別ファイルに移譲された旨を示す）
   - 表の直後に以下の条件付きロード指示を追加（行頭を空行で区切る）：
     ```
     **Skill-dev supplement**: If `scripts/validate-skill-syntax.py` exists, additionally read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-doc-impact.md` and apply its Change Type entries.
     ```

3. `docs/environment-adaptation.md` の Layer 3 Domain Files 表に新行を追加（after 1）（→ 検収 F）
   - 挿入位置: `skills/review/skill-dev-recheck.md` 行の直後（validate-skill-syntax.py 条件のグループに揃える）
   - 新行:
     ```
     | `modules/skill-dev-doc-impact.md` | `/spec`, `/code` (via `doc-checker.md`) | `validate-skill-syntax.py` exists | `file_exists_any: [scripts/validate-skill-syntax.py]` | Skill development project-specific Change Types |
     ```

4. `docs/ja/environment-adaptation.md` の翻訳同期（after 3）
   - 同一位置（skill-dev-recheck.md 行の直後）に対応する日本語行を追加:
     ```
     | `modules/skill-dev-doc-impact.md` | `/spec`、`/code`（`doc-checker.md` 経由） | `validate-skill-syntax.py` が存在 | `file_exists_any: [scripts/validate-skill-syntax.py]` | スキル開発プロジェクト固有 Change Types |
     ```

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/skill-dev-doc-impact.md" --> 新 Domain file が作成されている
- <!-- verify: file_contains "modules/skill-dev-doc-impact.md" "type: domain" --> 新 Domain file に frontmatter が宣言されている
- <!-- verify: rubric "modules/skill-dev-doc-impact.md load_when uses file_exists_any: [scripts/validate-skill-syntax.py]" --> load_when が validate-skill-syntax.py 存在条件で記述されている
- <!-- verify: rubric "modules/skill-dev-doc-impact.md contains the Change Types rows for skill, agent/shared module, and script previously at modules/doc-checker.md L33-L37" --> skill/agent/module/script の 3 種 Change Types エントリが Domain file に移譲されている
- <!-- verify: rubric "modules/doc-checker.md Change Types table no longer lists skill-dev-specific rows (skill addition/change/deletion; agent/shared module; script) — retains only generic rows (workflow phase, project structure)" --> doc-checker.md 本体から skill-dev 固有行が除去されている
- <!-- verify: rubric "docs/environment-adaptation.md Layer 3 Domain Files table lists skill-dev-doc-impact.md with its load_when conditions" --> environment-adaptation.md の Domain Files 表に新 Domain file が追加されている

### Post-merge

- 非 skill-dev プロジェクトで `/spec` 実行時に skill/agent/module/script 変更の Change Types 判定が混入しないことを手動確認
- wholework 本体で `/spec` 実行時に skill 追加の Change Type が Domain 経由で適用されることを手動確認

## Notes

- `modules/skill-dev-doc-impact.md` は `modules/` 配下に置くため domain-loader の Phase 1 Glob（`skills/{SKILL_NAME}/*.md`）には引っかからない。そのため `load_when` frontmatter はロード条件の文書化目的であり、実際のロードは doc-checker.md の条件付きロード指示で行われる。
- /doc skill は現在 doc-checker.md を直接参照しておらず、今 Issue のスコープには含めない。
- `/doc` が将来 doc-checker.md を利用するようになった場合、同一のロード経路が自動的に適用される。
- Pre-merge 検収 6 項目は light limit（5 項）をわずかに超えるが、Issue body の受け入れ基準をそのまま転記したため維持する。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は簡潔かつ実装と一致。受け入れ条件 6 項目すべてに verify コマンドが付与されており、自動検証率が高かった。
- Post-merge 条件がすべて手動確認（manual/opportunistic）であり、verify コマンドなしで自動判定不可。これは設計上の妥当な決定（実行環境依存の動作確認のため）。

#### design
- 設計通りに 4 ファイルが変更され、逸脱なし。
- Spec の Notes セクションで `load_when` が文書化目的であることが明記されており、実際のロード経路（doc-checker.md の条件付きロード指示）との関係が明確に整理されている。

#### code
- 単一コミット（7ab6175）で実装完了。fixup/amend パターンなし。
- Code Retrospective の Deviations/Rework がすべて N/A であり、実装は設計通りにスムーズに完了した。

#### review
- パッチルートのため PR レビューなし。コードの変更量が小さく（24 行追加・4 行削除）、レビューなしでもリスクは低い。

#### merge
- パッチルート（main 直コミット）。マージコンフリクトなし、CI なし。

#### verify
- 全 6 Pre-merge 条件が PASS。`rubric` コマンドによるセマンティック判定が有効に機能した。
- Post-merge の manual/opportunistic 条件（2 項）が未確認のまま残存。`phase/verify` を付与し再実行待ち。

### Improvement Proposals
- N/A
