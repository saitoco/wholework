# Issue #1266: spec: allowed-tools impact chain check の発火条件に modules/*.md への新規スクリプト呼び出しを追加

## Overview

`skills/spec/SKILL.md` Step 10 の `#### allowed-tools impact chain check` (#721 で導入) は、Spec の Changed Files に**新規** `scripts/*.sh` が含まれる場合のみ発火し、「既存スクリプトへの新規呼び出しを共有モジュール (`modules/*.md`) に追加する」変更を素通りさせる構造的ギャップを持つ。`modules/*.md` は複数 skill から "Read and follow" される共有面であり、1 モジュールへの 1 スクリプト呼び出し追加が、そのモジュールを読む全 skill の `allowed-tools` 更新を要求する。

2026-08-07 の同一セッションで #1236 (`modules/opportunistic-verify.md` への `scripts/emit-event.sh` 呼び出し追加、2 skill 漏れ) と #1239 (同モジュールへの `scripts/collect-run-facts.sh` 呼び出し追加、5 skill 漏れ) が連続再発し、いずれも `/spec` 段階では検出されず `scripts/validate-skill-syntax.py` のクロスファイル検証が code フェーズで初めて捕捉した。

本 Issue は、`allowed-tools impact chain check` の発火条件を `modules/*.md` の変更にも拡張し、`/spec` 段階で呼び出し元 SKILL.md の `allowed-tools` 漏れを検出できるようにする。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective — AC3 の検証コマンドを自己一致していた `"skills/*/SKILL.md"` パターンから `"grep -rl"` に修正済み、Post-merge AC に `session=next` を付与済みであることを確認。曖昧性検出・タイトルドリフトともになし。(https://github.com/saitoco/wholework/issues/1266#issuecomment-5226595466)

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の `#### allowed-tools impact chain check` サブ節を拡張 — 発火条件に `modules/*.md` を追加し、"Case 1" (既存の新規スクリプト判定、変更なし) と "Case 2" (module 経由の新規呼び出し判定) に分割、skip 条件を更新 — bash 3.2+ 互換 (対象は Markdown 文書のみで bash コードは含まないため該当なし)

## Implementation Steps

1. `skills/spec/SKILL.md` の `#### allowed-tools impact chain check` サブ節 (現行 572-581 行目) を以下の内容に置き換える (→ AC1, AC2, AC3)
   - 発火条件を「Changed Files に新規 `scripts/*.sh` を含む」**または**「Changed Files に `modules/*.md` を含む」の 2 条件に拡張
   - 既存の 4 ステップ手順を "Case 1 — new `scripts/*.sh` files" として維持 (内容変更なし)
   - "Case 2 — `modules/*.md` changes" を新設: (a) 変更対象モジュールの新規/変更内容が `scripts/*.sh` への参照を含むかを確認する軽量ゲート、(b) 含む場合のみ `grep -rl "modules/<name>\.md" skills/*/SKILL.md` で読者 (呼び出し元 skill) を洗い出す、(c) 各読者の `allowed-tools` frontmatter に対象スクリプトの literal エントリがあるか確認、(d) 漏れがあれば Case 1 と同じ形式で Notes に記録するか Changed Files に追加
   - wildcard 不可の注記は Case 1 の既存 4 ステップを逐語的に維持したまま、Case 2 側のステップに「Case 1 step 4 と同じ wildcard 不可ルールがここにも適用される」という参照文を追加する形で両 Case に共通適用させる (Deviations from Design 参照)
   - skip 条件を「Changed Files に新規 `scripts/*.sh` も `modules/*.md` も含まれない場合のみ skip」に更新
   - 背景注記として #1236 / #1239 の再発事例を1文で残す (既存の "Feature deletion impact chain check" 等と同じ *斜体背景* 引用スタイル)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の allowed-tools impact chain check セクションが、新規 scripts/*.sh の追加だけでなく、modules/*.md に既存スクリプトへの新規呼び出しを追加するケースも検出対象としている" --> `skills/spec/SKILL.md` の `allowed-tools impact chain check` が、`modules/*.md` への新規スクリプト呼び出し追加を発火条件に含めている
- <!-- verify: rubric "skills/spec/SKILL.md の当該 skip 条件が、modules/*.md 経由のケースを誤って skip しない記述になっている" --> 現行の `**Skip** if no new scripts/*.sh files are being added.` が新しい発火条件を反映した記述に更新されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "allowed-tools impact chain check" "grep -rl" --> 呼び出し元 skill の洗い出し手順 (`grep -rl "modules/<name>\.md" skills/*/SKILL.md` 相当) が明記されている
- <!-- verify: rubric "modules/*.md 変更時の発火粒度 (全 module 変更で発火 / 新規スクリプト呼び出しを含む場合のみ発火) についての判断と理由が Spec に記載されている" --> 過剰発火を許容するか抑制するかの判断とその理由が Spec に記録されている

### Post-merge

- 次に `modules/*.md` へ新規スクリプト呼び出しを追加する Issue の `/spec` 実行時、呼び出し元 SKILL.md の `allowed-tools` が Changed Files または Notes に記録されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

**過剰発火の許容/抑制粒度の判断 (AC4):** 外側の発火条件は「Changed Files に `modules/*.md` が 1 件でも含まれる」で機械的に判定する (既存の新規 `scripts/*.sh` 条件と同じ Changed-Files ベースの機械判定スタイル)。一方、コストの高い処理 (`grep -rl` による読者洗い出し + 各読者の `allowed-tools` 確認) は、Case 2 step (a) の軽量ゲート — 「変更対象モジュールの新規/変更内容が `scripts/*.sh` への参照を含むか」という文字列存在チェック — の後段でのみ実行する。

このゲートを意図的に「作者が新規呼び出し追加を意図したか」という意味論的判断にしなかった理由: この check が防ごうとしている #1236 / #1239 はいずれも、まさにその種の意図判断が見落とされたことで発生した再発である。ゲート自体を同種の意味論的判断にすると、見落としリスクを再導入することになる。文字列存在チェックによる過剰発火 (スクリプト呼び出しを追加しないモジュール変更が `scripts/` という語を偶然含む場合など) のコストは `grep -rl` 一発と「漏れなし」の一行メモ程度だが、見逃しのコストは #1236 (2 skill 漏れ) / #1239 (5 skill 漏れ) と同種の code フェーズ手戻りである。非対称性から過剰発火を許容する側を採用した。

**`/code` フェーズの既存セーフティネットとの関係 (#857):** `scripts/check-allowed-tools.sh` (#857 で導入、`skills/code/SKILL.md` Step 8 から呼び出し) は、SKILL.md を変更する中間コミット前に `skills/` 配下全体を `allowed-tools` と突き合わせて再検証する既存の安全網である。この機構は `modules/*.md` 自体を読まないため `/spec` 段階のギャップを代替できないが、本 Issue の Spec 時点チェックが見逃した場合の最終防波堤として引き続き独立に機能する。`check-allowed-tools.sh` / `skills/code/SKILL.md` への変更は本 Issue のスコープ外であり、実施しない。

## Code Retrospective

### Deviations from Design

- Implementation Steps は「wildcard 不可の注記を両 Case 共通の文言に更新する」ことと「既存の 4 ステップ手順を Case 1 として内容変更なしで維持する」ことの両方を求めていた。文字通り両立させるため、Case 1 の 4 ステップは一切変更せず、Case 2 側の該当ステップに「Case 1 step 4 と同じ wildcard 不可ルールがここにも適用される」という参照文を追加する形にした (独立した共通段落へ抽出する案は Case 1 の逐語的な内容不変という制約と衝突するため採らなかった)。

### Design Gaps/Ambiguities

- `/code` 開始時点で Issue のラベルは `phase/ready` ではなく既に `phase/code` だった (`reconcile-phase-state.sh --check-precondition code-patch` は `matches_expected: false` を返した)。Spec (`docs/spec/issue-1266-spec-allowed-tools-modules.md`) 自体は存在していたため、non-interactive mode の既定動作 (warn し続行) に従って実装を進めた。ラベルタイムラインを確認すると `phase/ready` 付与と `phase/code` への遷移が同一タイムスタンプ (2026-08-08T15:04:31Z) で発生しており、原因 (前回セッションでの部分実行か、`/spec` が `phase/ready` を経由せず直接遷移する設計上の挙動か) は未調査。本 Issue のスコープ外として深追いしていない。

### Rework

- N/A

## Autonomous Auto-Resolve Log

- **Step 3 (`phase/ready` ラベル不在の precondition mismatch) — 実装を継続** — 理由: `reconcile-phase-state.sh` の `matches_expected: false` は「Spec 不在」ではなく「ラベルが `phase/ready` を経由せず `phase/code` に進んでいる」ことに起因しており、Spec 自体 (`docs/spec/issue-1266-spec-allowed-tools-modules.md`) は存在し内容も本 Issue の要件と一致していたため、warn して続行する非対話モードの既定動作を採用した。
  - Other candidates: 実装を中断してユーザー確認を待つ (hard-error abort) — 対話不可のためこのセッションでは選択不可

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `allowed-tools impact chain check` を Case 1 (既存の新規 `scripts/*.sh` 判定、内容不変) と Case 2 (`modules/*.md` 変更 + 軽量ゲート + 読者洗い出し) の二本立てにし、Case 1 の逐語的維持と wildcard 注記の共通化を両立させるため、Case 2 側から Case 1 step 4 を参照する形にした。
- AC4 (過剰発火の許容/抑制粒度) は Spec 作成時点の Notes セクションで既に判断・記録済みだったため、SKILL.md 側の追加変更は不要と判断した。

### Deferred Items
- Post-merge AC (`session=next` observation) — 次回 `modules/*.md` へ新規スクリプト呼び出しを追加する Issue の `/spec` 実行時に、本 Case 2 ロジックが実際に発火し、呼び出し元 SKILL.md の allowed-tools 漏れを検出できるかを観察する。

### Notes for Next Phase
- `/review` では、Case 2 の軽量ゲート (文字列存在チェック) が意図的に「意味論的判断ではない」設計になっている点 (Notes 参照) を踏まえてレビューすること — 過剰発火を許容する非対称性のトレードオフが再度指摘されないよう、Spec Notes の記載を確認してほしい。
