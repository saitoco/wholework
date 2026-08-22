# Issue #1154: spec: Uncertainty 節の解決内容と Implementation Steps の整合セルフチェックを追加

## Overview

`/spec` Step 8 (Identify Uncertainty) は、あいまい点を `## Uncertainty` 節に narrative (非拘束) として記録するが、実装が実際に従う `## Implementation Steps` (AC に紐づく拘束力あり) との整合を確認する手順が存在しない。Issue #995 / PR #999 では、Uncertainty 節が「2 ファイルの両方に明記する」と解決したにもかかわらず Implementation Steps が 1 ファイルのみに限定しており、review の adversarial verification が「Spec の権威ある Implementation Steps に従っているため false positive」と判定して見逃した実例がある。

`skills/spec/SKILL.md` Step 8 の `**Response:**` 番号付きリスト (1-4) に `5.` を追記し、Uncertainty 節で解決した項目が Implementation Steps に過不足なく転記されているかを確認するセルフチェック手順を追加する。

## Changed Files

- `skills/spec/SKILL.md`: Step 8 (Identify Uncertainty, 現行 L279-298) の `**Response:**` 番号付きリストに `5.` を追記

## Implementation Steps

1. `skills/spec/SKILL.md` Step 8 の `**Response:**` 番号付きリスト (1-4) に `5.` を追記し、以下を規定するセルフチェック手順を追加する: Uncertainty 節で解決した各項目が `## Implementation Steps` に過不足なく転記されているかを照合すること。解決内容が複数の対象ファイル・複数の変更箇所を含む場合は、そのすべてが個別に Implementation Steps の該当ステップとして列挙されているかを確認すること (部分的な転記は不可とする)。不整合を検出した場合の対処として (a) Implementation Steps 側への追記、(b) Uncertainty 節の解決記述を実装スコープに合わせて訂正する、の両方向を規定し、選択した対処を Spec の `## Notes` 節に記録する旨を明記する (→ AC1, AC2, AC3)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Step 8 (Identify Uncertainty) に、Uncertainty 節で解決した項目が ## Implementation Steps に過不足なく転記されているかを確認するセルフチェック手順が追加されている。特に、解決内容が複数の対象ファイル・複数の変更箇所を含む場合にそのすべてが Implementation Steps に列挙されているかを照合する旨が明記されていること" --> `/spec` Step 8 に Uncertainty → Implementation Steps の整合セルフチェックが追加されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "Step 8: Identify Uncertainty" "Implementation Steps" --> Step 8 のセクション内に `Implementation Steps` という語が含まれている (rubric の機械的裏付け)
- <!-- verify: rubric "追加されたセルフチェックが、不整合を検出した場合の対処 (Implementation Steps 側に追記する / Uncertainty 節の記述をスコープに合わせて訂正する) を両方向とも規定している" --> 不整合検出時の対処が両方向とも規定されている
- <!-- verify: command "bats tests/run-spec.bats" --> `tests/run-spec.bats` が PASS する

### Post-merge

- 次回 Uncertainty 節を持つ Issue の `/spec` 実行時、Implementation Steps との整合チェックが実施されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **精度確認 (codebase investigation)**: 引用元 `docs/spec/issue-995-operate-route.md:124` の Uncertainty 節 (「`skills/code/SKILL.md` と `docs/workflow.md` の両方に明記する」) と、同ファイル L267/L300/L321 の retrospective 記述 (Implementation Steps が `docs/workflow.md` のみに限定されていたこと、review の adversarial verification が false positive 判定したこと) を grep で確認済み。Issue #1154 の Background の実例引用は正確。
- **行番号引用の正確性**: Issue 本文 Background が引用する現行行番号 (Step 8: L279-298、個別パターンチェック群: L455/L461/L477/L565) は本 Spec 作成時点の `skills/spec/SKILL.md` と一致することを grep で確認済み (`/issue` フェーズの Retrospective コメントで既に一度補正されている)。
- **bats 新規テストケース不要の判断**: 本 Issue の変更は `skills/spec/SKILL.md` Step 8 のプローズ (LLM 実行手順) への追記であり、`scripts/run-spec.sh` (bats でテストされるラッパースクリプト本体) には変更を加えない。`tests/run-spec.bats` はラッパーの分岐ロジック (モデル選択・retry・emit event 等) を検証する構成で、Step 8 のプローズ内容は対象外。`modules/spec/SKILL.md` §10 の「新規分岐ロジックへの新規テストケース要求」チェックのスキップ条件 (「ドキュメントのみの変更」) に該当するため、新規 bats テストケースは追加しない。AC4 の `bats tests/run-spec.bats` は既存スイートの回帰確認として機能する。
- **Steering Docs sync candidate 確認**: `docs/workflow.md` L48 の `/spec` 概要記述 (「`--light` で曖昧解決・不確実性検出・self-review 等を省略」) は、light/full の対象範囲自体は変更しないため更新不要と判断 (grep で該当箇所を確認済み、他に `Uncertainty`/`Step 8` を参照するドキュメントは `docs/`, `modules/`, `tests/`, `scripts/` 配下に見つからず)。
- **SPEC_DEPTH=light の適用**: Size=S のため `/spec` 自身の Step 7 (Ambiguity Resolution) と Step 8 (Identify Uncertainty) はスキップされる。Issue 本文の `## Auto-Resolved Ambiguity Points` (セルフチェックの Step 8 内配置形式) は `/issue` フェーズで解決済みの内容であり、本 Spec の Implementation Steps は Issue 本文の推奨 (`**Response:**` の延長として `5.` を追記) にそのまま従っている。

## Consumed Comments

`/issue` フェーズが `phase/issue` ラベル付与後に投稿した Issue Retrospective コメント 2 件を確認 (いずれも `saito` / MEMBER / first-class)。

1. [2026-08-21T08:57:50Z](https://github.com/saitoco/wholework/issues/1154#issuecomment-5367778781) — `--non-interactive` 実行時の AC 分類・verify command 整合性 audit 結果と Auto-Resolve Log (セルフチェックの Step 8 内配置形式を `5.` 追記として推奨)。内容は Issue 本文に反映済み。
2. [2026-08-21T09:02:31Z](https://github.com/saitoco/wholework/issues/1154#issuecomment-5367823953) — Step 15 audit で発見した自己生成 rubric 補助チェック (`section_contains` の heading 引数) の `###` 除去修正。内容は Issue 本文に反映済み (現行 AC は修正後の形式)。

いずれも Issue 本文更新として既に反映済みのため、本 Spec 作成にあたり追加のアクションは不要。

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1154#issuecomment-5368191727
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1154#issuecomment-5369692599
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1154#issuecomment-5378423701
## Code Retrospective

### Deviations from Design
N/A — Implementation Steps の記載どおり、`skills/spec/SKILL.md` Step 8 の `**Response:**` 番号付きリストに `5.` を追記した。

### Design Gaps/Ambiguities
N/A

### Rework
N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implementation Steps の指示どおり、`skills/spec/SKILL.md` Step 8 の `**Response:**` 番号付きリスト (1-4) に `5.` として自己チェック手順を追記した。既存フォーマット (番号付き手順) との整合を優先し、Step 6 の個別パターン群のような独立見出しは採用しなかった (Issue 本文の Auto-Resolved Ambiguity Points の推奨どおり)。
- 新規 bats テストケースは追加していない — Spec Notes の判断 (`scripts/run-spec.sh` 本体を変更しないプローズのみの追記であるため) をそのまま踏襲した。
- behavioral change 判定 (`tests/check-file-overlap.bats` / `tests/operate-route.bats` が `skills/spec/SKILL.md` を参照) によりフルテストスイートを並列実行し、1908件全て PASS を確認した。

### Deferred Items
- None

### Notes for Next Phase
- 4件の Pre-merge AC (rubric x2, section_contains, command) は `/code` フェーズ内で全て PASS 済みでチェック済み。`/review` では追加の逸脱がないことの確認で足りる想定。
- Post-merge の observation AC (`event=auto-run session=next`) は次回 Uncertainty 節を持つ Issue の `/spec` 実行時に観察されるべき項目 — `/verify` 実行時点ではまだ発火していない可能性が高い。
