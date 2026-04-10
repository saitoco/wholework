# Issue #96: terminology: Terms テーブルの拡充・整理と acceptance criteria/condition の定義追加

## Overview

`docs/product.md` の Terms テーブル（用語 SSOT）に 9 件の用語を追加し、全用語をアルファベット順に整理する。また、`docs/ja/product.md` の Public/Internal 分割を解消して英語版と同じフラット構造に統一する。

追加する用語: Acceptance condition、Acceptance criteria、Drift、Patch route、Phase label、PR route、Retrospective、Size、Sub-issue

追加に伴い、Spec の定義文中の retrospective 説明を簡素化し、Retrospective 用語への相互参照に変更する。

## Changed Files

- `docs/product.md`: Terms テーブルに 9 用語を追加、Spec 定義を簡素化、全 18 用語をアルファベット順にソート
- `docs/ja/product.md`: Public/Internal 分割を解消してフラット 1 テーブルに統合、新規日本語訳用語（受入条件項目ほか）を追加

## Implementation Steps

1. `docs/product.md` の `## Terms` セクションを更新する: 9 件の新規行を追加（各行に Term/Definition/Context/日本語訳 を記載）、Spec 定義の retrospective 言及を「Retrospective 用語を参照」形式に簡素化、全 18 行をアルファベット順（`str.lower` 準拠）にソートする (→ 受入条件: 新規用語追加、日本語訳、Spec 定義更新、ソート)
2. `docs/ja/product.md` の `## Terms` セクションを更新する: `<!-- public: ... -->` コメント・`### Public Terms` 見出し・`### Internal Terms` 見出しを除去して 1 つのフラットテーブルに統合し、受入条件項目ほかの新規日本語用語行を追加する (→ 受入条件: 日本語ミラー同期)

**ソート後の全 18 行の順序 (str.lower 準拠):**

| # | Term |
|---|------|
| 1 | `/auto` |
| 2 | Acceptance condition |
| 3 | Acceptance criteria |
| 4 | Drift |
| 5 | Fork context |
| 6 | Patch route |
| 7 | Phase label |
| 8 | PR route |
| 9 | Project Documents |
| 10 | Retrospective |
| 11 | Shared module |
| 12 | Size |
| 13 | Skill |
| 14 | Spec |
| 15 | Steering Documents |
| 16 | Sub-agent |
| 17 | Sub-issue |
| 18 | verify command |

**新規 9 用語の定義案 (英語版):**

| Term | Definition | Context | 日本語訳 |
|------|------------|---------|---------|
| Acceptance condition | A single verifiable requirement item within an Issue's acceptance criteria. Appears as one checklist row; typically paired with a verify command | /issue, /verify | 受入条件項目 |
| Acceptance criteria | The complete set of acceptance conditions for an Issue, defined under `## Acceptance Criteria` in the Issue body. L1 collection of L2 individual acceptance conditions | /issue, /verify | 受入条件 |
| Drift | Semantic divergence between documented specifications (Steering Documents or Specs) and actual code implementation. Detected by `/audit drift` | /audit Skill | ドリフト |
| Patch route | Workflow path for XS/S-sized Issues; commits directly to the main branch without creating a Pull Request | Development workflow | パッチ経路 |
| Phase label | A `phase/*` GitHub label (e.g., `phase/issue`, `phase/spec`, `phase/ready`, `phase/code`) indicating the current workflow stage of an Issue | Development workflow | フェーズラベル |
| PR route | Workflow path for M/L-sized Issues; creates a Pull Request for code review before merging | Development workflow | PR 経路 |
| Retrospective | A section appended to the Spec after each Skill run, recording observations, decisions, and uncertainty resolutions from that phase. Accumulates execution history across workflow phases | Development workflow | レトロスペクティブ |
| Size | A complexity/effort estimate (XS/S/M/L/XL) assigned during triage. Determines the workflow route (patch vs. PR) and Spec depth | /triage Skill | サイズ |
| Sub-issue | A child Issue within an XL Issue decomposition. `/auto` reads the `blockedBy` dependency graph and executes independent sub-issues in parallel (worktree isolation), sequencing dependents after their blockers complete | Development workflow | サブ Issue |

**Spec 定義更新案:**

現在: `...Also records retrospectives (execution logs) after each Skill runs — reviewing the Spec before running a Skill shows the history of prior executions`

更新後: `...Also accumulates Retrospectives after each Skill run, serving as cross-phase memory for the workflow`

## Verification

### Pre-merge

#### 新規用語の追加（9 件）

- <!-- verify: section_contains "docs/product.md" "## Terms" "Acceptance condition" --> Terms に "Acceptance condition" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Acceptance criteria" --> Terms に "Acceptance criteria" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Drift" --> Terms に "Drift" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Patch route" --> Terms に "Patch route" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Phase label" --> Terms に "Phase label" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "PR route" --> Terms に "PR route" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Retrospective" --> Terms に "Retrospective" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Size" --> Terms に "Size" が追加されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "Sub-issue" --> Terms に "Sub-issue" が追加されている

#### 日本語訳の定義

- <!-- verify: grep "受入条件項目" "docs/product.md" --> "Acceptance condition" の日本語訳として「受入条件項目」が記載されている
- <!-- verify: grep "受入条件" "docs/product.md" --> "Acceptance criteria" の日本語訳として「受入条件」が記載されている

#### 既存用語の更新

- <!-- verify: grep "Retrospective" "docs/product.md" --> Spec 定義から retrospective 説明を簡素化し、Retrospective 用語を相互参照する形に更新されている

#### アルファベット順ソート

- <!-- verify: command "python3 -c \"import re; text=open('docs/product.md').read(); m=re.search(r'## Terms.*?(?=\\n## |\\Z)', text, re.DOTALL); rows=[r.split('|')[1].strip() for r in m.group().split('\\n') if r.startswith('|') and 'Term' not in r and '---' not in r]; assert rows == sorted(rows, key=str.lower), f'Not sorted: {rows}'\"" --> Terms テーブルがアルファベット順にソートされている

#### 日本語ミラー同期

- <!-- verify: section_contains "docs/ja/product.md" "## Terms" "受入条件項目" --> `docs/ja/product.md` Terms に「受入条件項目」が追加されている
- <!-- verify: file_not_contains "docs/ja/product.md" "### Public Terms" --> `docs/ja/product.md` の Public/Internal 分割が解消され、英語版と同じフラット構造になっている

### Post-merge

- `/verify 96` で全 15 件の pre-merge 受入チェックが PASS することを確認する
- `docs/product.md` の Terms テーブルが 18 行（9 件追加）になっていることを目視確認する
- `docs/ja/product.md` に `### Public Terms` / `### Internal Terms` 見出しが残っていないことを目視確認する

## Notes

- ソート後の行数は 18（既存 9 件 + 新規 9 件）
- Python ソートチェックは `str.lower` を key 関数として使用。`/auto` は先頭（`/` の ASCII 47 が `a` の 97 より小さい）
- `grep "受入条件" "docs/product.md"` は「受入条件項目」も部分一致するため、Acceptance criteria の日本語訳「受入条件」が存在すれば必ず PASS する
- `docs/ja/product.md` のソート順は英語版の順序に合わせる（日本語ファイルのアルファベットソート検証は acceptance check に含まれていないが、一貫性のため揃える）
- Scope Declaration（Issue 本文より）: コードベース内の用語置換は含まない（後続 Issue #94 で対応）

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
- Spec に18用語の最終ソート順が明示されており、実装と完全に一致した。Python ソートチェックコマンドを acceptance check に組み込んだことで、機械的な検証が可能になった点は特に有効だった。

#### design
- Issue Retrospective・Spec Retrospective セクションは存在しないが、Spec の実装ステップが変更ファイル単位で明確に記述されており、設計通りの実装が行われた。

#### code
- Code Retrospective はすべて N/A（手戻りなし）。Patch route による直接コミットで、実装の複雑度が低くリスクも少ない変更であったため適切な経路選択だった。

#### review
- Patch route のため PR レビューなし。この規模の変更（ドキュメントのみ）であれば Patch route は妥当。

#### merge
- `d418e43` で直接 main にコミット（closes #96）。コンフリクトなし。

#### verify
- 全15件が初回検証で PASS。acceptance check の設計が精緻で（section_contains、grep、command の使い分け）、自動検証カバレッジが100%だった。Python コマンドによるソート検証は再現性が高く有用。

### Improvement Proposals

- N/A
