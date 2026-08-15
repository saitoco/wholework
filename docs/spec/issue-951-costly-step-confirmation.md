# Issue #951: spec/code: costly/irreversible な実行ステップの /code フェーズ明示確認を導入

## Overview

`/spec` は Implementation Step 内で costly (実費/トークン消費を伴う)・irreversible (取り消し不能な副作用を伴う) な実行を pre-authorize することがあるが、`/code` は非対話 (`run-*.sh` 経由、AskUserQuestion 不可) で実行され、その pre-authorization を独自判断で再検討・見送ることがある。過去 2 回 (#903, #939) この構造が再発しており、AC は「実行された前提」で書かれたまま `/code` が deferral したため verify FAIL → auto-retry loop 候補になった。

本 Issue は、`/spec` が costly/irreversible な Implementation Step に明示マーカー (`spec-approval-needed`) を付与し、対応する Deferral Protocol を Notes に必須記載する producer 側の変更と、`/code` がそのマーカーを検出して既存の non-interactive 三層ポリシー (`modules/ambiguity-detector.md` の High-Stakes Decisions / skip tier) に従い明示的に deferral する consumer 側の変更を導入する。deferral は `## Code Retrospective` > `### Deviations from Design` に記録するため、`/verify` 側の documented deferral detection (#947, Step 11(b)) が新規実装なしにそのまま検出できる。

## Changed Files

- `modules/costly-step-protocol.md`: 新規作成 — `spec-approval-needed` マーカー形式、`/spec` producer contract、`/code` consumer contract、Deferral Protocol 必須記載ルールの SSoT。#903 / #939 precedent と #947 との関係を明記
- `docs/structure.md`: 「Key modules」箇条書きに `modules/costly-step-protocol.md` を追加
- `docs/ja/structure.md`: 上記と同内容を日本語で同期 (`docs/translation-workflow.md` 準拠)
- `modules/ambiguity-detector.md`: `## Non-Interactive Mode Handling` の「High-Stakes Decisions (exhaustive list — skip these in non-interactive mode)」に 1 項目追加
- `skills/spec/SKILL.md`: Step 10 に「Costly/irreversible step marking」小節を追加
- `skills/code/SKILL.md`: Step 8 に「Costly/irreversible step handling」小節を追加
- `docs/tech.md`: `## Architecture Decisions` に、採用アプローチ (a)+(c) と (b) 不採用の判断根拠を記録する箇条書きを追加 (#903 / #939 / #947 を引用)
- `docs/ja/tech.md`: 上記と同内容を日本語で同期 (`docs/translation-workflow.md` 準拠)

## Implementation Steps

1. `modules/costly-step-protocol.md` を新規作成し、`docs/structure.md` の「Key modules」箇条書きに登録する (`docs/ja/structure.md` も同期) (→ acceptance criteria AC1, AC3)
   - 記載内容の詳細は Notes の「costly-step-protocol.md 記載内容アウトライン」を参照
2. `modules/ambiguity-detector.md` の「High-Stakes Decisions (exhaustive list — skip these in non-interactive mode)」に 1 項目追加する (after 1) (→ acceptance criteria AC1)
   - 追加項目: costly/irreversible Implementation Step の実行 (`spec-approval-needed` マーカー付きステップ、`modules/costly-step-protocol.md` 参照) — non-interactive mode では skip し、Spec の Deferral Protocol に従う
3. `skills/spec/SKILL.md` Step 10 に「Costly/irreversible step marking」小節を追加する (after 1) (→ acceptance criteria AC1, AC2)
   - 挿入位置: 「Side-effect direction anti-patterns in implementation steps」小節の直後、「SHOULD-level acceptance criteria consideration:」の直前
   - 内容: 各 Implementation Step について、実行が実費/トークン消費または production/irreversible な副作用を伴うか評価し、該当する場合は `modules/costly-step-protocol.md` を読んでマーカー付与 + Deferral Protocol 記載を行う指示
4. `skills/code/SKILL.md` Step 8 に「Costly/irreversible step handling」小節を追加する (after 1, 2) (→ acceptance criteria AC1, AC2)
   - 挿入位置: 「Omitting a step because its AC is post-merge manual is an implementation error.」の直後、「- Use TaskCreate/TaskUpdate to manage tasks while working」箇条書きの直前
   - 内容: `spec-approval-needed` マーカー付きステップの実行前に `modules/costly-step-protocol.md` の consumer contract を適用する指示 (interactive → AskUserQuestion、non-interactive → `modules/ambiguity-detector.md` の skip tier)。直前の「all Spec steps are required」原則に対する唯一の例外である旨を明記
5. `docs/tech.md` の `## Architecture Decisions` に箇条書きを追加する (`docs/ja/tech.md` も同期) (after 1-4) (→ acceptance criteria AC2, AC3)
   - 挿入位置: 「code-side auto-retry (silent no-op)」箇条書きの直後、「`recoveries-auto-fire` default opt-out (#1179)」箇条書きの直前
   - 内容: 採用アプローチ (a マーカー + c Deferral Protocol 必須化)、(b) interactive fallback を不採用とした根拠、#903 / #939 / #947 の引用 (詳細は Notes 参照)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md, skills/code/SKILL.md, または関連する modules/*.md のいずれかに costly/irreversible step の explicit confirmation mechanism (marker 導入 / interactive fallback / deferral protocol 必須化 のいずれか) が実装されている" --> spec/code の costly step confirmation mechanism が実装されている
- <!-- verify: rubric "実装アプローチ (a)/(b)/(c) のうちどれを採用したか、および他を採用しなかった場合の判断根拠が Spec または docs に記録されている" --> 採用アプローチと判断根拠が記録されている
- <!-- verify: rubric "#903 / #939 precedent への言及が実装関連ファイル (SKILL.md, modules, docs) の該当箇所にコメント/参照として存在する" --> 過去 precedent への参照が実装に組み込まれている

### Post-merge

- 次回 costly step を含む Issue の spec → code フェーズで、確認/deferral protocol が発火することを観察

## Notes

### costly-step-protocol.md 記載内容アウトライン

- **Purpose / Background**: #903 (Sonnet 5 watchdog 再較正)・#939 (Fable 5 spec silent window 実測) の 2 precedent を引用し、「`/spec` が costly/irreversible な実行を pre-authorize → `/code` (非対話) が独自判断で deferral → AC は実行前提のまま → verify FAIL → auto-retry loop 候補」という再発パターンを説明。#947 (documented deferral escape hatch、`/verify` Step 11(b)) との関係を明記: #947 は `/verify` 時点の reactive detection、本モジュールは `/spec`/`/code` 時点の proactive prevention であり、両者は補完関係
- **マーカー形式**: `<!-- spec-approval-needed: cost=<low|high>, reversibility=<low|high> -->` を対象 Implementation Step の行末に付与。Issue #951 本文の approach (a) 記載例 (`cost=high, reversibility=low`) に合わせ 2 値スケールとする (3 値以上への拡張は本 Issue のスコープ外)
  - タグ付け基準: `cost=high` または `reversibility=low` のいずれかに該当する場合のみ付与 (通常の git commit・ファイル編集・実費を伴わない CLI 呼び出しは対象外)
- **Producer contract (`/spec`)**: Implementation Step 作成時、実費/トークン消費を伴う新規実行 (例: 新規 `--fable` run、新規 `--opus` run 等の costed model 実行) または production/irreversible な副作用 (例: 本番 API への mutating call) を伴うステップにはマーカーを付与し、Spec の `## Notes` に対応する「Deferral Protocol」項目 (deferral 時に何を代替として行うか — 例: 実行予定コマンド/引数を Code Retrospective に記録し実行はしない、等) を必須記載する
- **Consumer contract (`/code`)**: マーカー付きステップの実行前に:
  - interactive mode: AskUserQuestion で確認
  - non-interactive mode: `modules/ambiguity-detector.md` の High-Stakes Decision (skip tier) として扱う — 実行せず、Spec の Deferral Protocol に従い、`## Code Retrospective` > `### Deviations from Design` に deferral を明記 (「(deferred — spec-approval-needed)」等のタグを付す)。これにより該当 AC を偽って PASS 扱いにしない
  - 上記の記録先は `/verify` Step 11(b) の Documented deferral detection が既に参照する情報源 (`## Code Retrospective` > `### Deviations from Design`) と同一であるため、`skills/verify/SKILL.md` 側の変更は不要 (Changed Files に含めない — 既存の generic な detection ロジックがそのまま機能する)

### 採用アプローチと判断根拠 (→ AC2)

**採用: (a) マーカー導入 + (c) Deferral Protocol 必須化。(b) interactive fallback は不採用。**

- (b) を不採用とした理由: `/code` の非対話実行 (`run-code.sh` 経由の `claude -p`) は、interactive な親セッションが存在する保証がない設計 (`/auto --batch` やスケジュール実行など、監視中の human がいないケースが正常系に含まれる)。「親セッションへの interactive fallback」という新チャネルを導入すると非対話実行の前提そのものと矛盾する。一方、`modules/ambiguity-detector.md` の Three-Tier Policy (auto-resolve / skip / hard-error) は既にこの種の「非対話では実行できない高リスク判断」を skip tier として扱う仕組みを持っており (High-Stakes Decisions の既存 4 項目と同種)、新規メカニズムを発明せず既存パターンを 1 項目拡張するだけで済む。「Shared module pattern」(`docs/tech.md`) の精神にも合致する
- (a)+(c) の組み合わせを採用した理由: (a) 単独では `/code` が「マーカーを検出したが具体的に何をすべきか」の記述がなく再度独自判断の余地が残る。(c) 単独では機械可読なマーカーがなく `/code` が検出漏れするリスクが残る。両者を組み合わせることで、`/spec` が「何が costly/irreversible か」と「deferral 時に何をすべきか」を確定し、`/code` は判断せず従うだけで済む

### 実装対象外と判断した項目

- **`docs/workflow.md`**: `modules/skill-dev-doc-impact.md` は shared module 追加時に `docs/workflow.md` (modules/agents list table) への反映を挙げるが、現状の `docs/workflow.md` に汎用モジュールを列挙する table は存在しない (個別トピックの本文中で `modules/size-workflow-table.md` 等を都度参照する構成)。本 Issue の追加内容 (spec/code 内部の Implementation Step marking 規約) もどのトピック本文にも該当しないため、Changed Files に含めない
- **`skills/verify/SKILL.md`**: AC1 の rubric は「spec/code の confirmation mechanism」を求めるが、`/verify` 側の Documented deferral detection (Step 11(b)) は既に `## Code Retrospective` > `### Deviations from Design` を汎用的に参照する設計であり、本 Issue が導入する deferral 記録先と完全に一致する。`/verify` 自体の記述を変更する必要はない

### Background の事実確認 (補足)

Issue 本文 Background は `/spec`・`/code` を「`run-*.sh` で `claude -p --dangerously-skip-permissions`」と記述するが、実際は `.wholework.yml` の `permission-mode` 設定に依存し (`bypass` のとき `--dangerously-skip-permissions`、既定/`auto` のとき `--permission-mode auto`。本リポジトリ自身は `permission-mode: auto` を設定済み)、`scripts/run-code.sh`/`scripts/run-spec.sh` で確認した。いずれのモードでも「非対話実行中は live な human 確認を得られない」という本 Issue の前提自体は変わらないため、この差異は設計に影響しない。Issue retrospective (#951 コメント) で既に advisory pass 済み・本文修正なしと判断されており、本 Spec でも本文への追加修正は行わない

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 意図: `/issue` フェーズの Issue Retrospective コメント — AC1 rubric 対象範囲を `modules/*.md` まで拡張した自動解決の根拠を記録 (Issue 本文には既に反映済みのため本 Spec での追加対応は不要) / URL: https://github.com/saitoco/wholework/issues/951#issuecomment-5303035979

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1〜5 を Spec の記載順・挿入位置指定どおりに実装した。

### Design Gaps/Ambiguities

N/A

### Rework

N/A

## review retrospective

### Spec vs. implementation divergence patterns

Spec の Implementation Steps は忠実に実装されていた (deviation なし) が、レビューで確認された実質的な問題はいずれも「新規メカニズム (marker/deferral record) と、同一 skill file 内に既存の汎用ルール (Step 12 の Spec 同期ルール、Step 10 の checkbox-flip ループ) との間の意図しない相互作用」だった。Spec 自体にはこの相互作用への言及がなく、Implementation Steps は新規追加箇所の記述にとどまっていた。新しい marker/annotation を導入する Spec を書く際は、Implementation Steps に「同一 skill file 内の既存の汎用 sync/normalize/flip 系ルールが新しい record を意図せず上書き・無視しないか」を明示的な確認項目として含めることが望ましい。

### Recurring issues

review-bug の 2 エージェント (diff-bug scan / security scan) が、異なる着眼点から独立に同一の欠陥 (Step 12 が marker を削除してしまう) を発見した。review-spec も独立に並行する欠陥 (checkbox-flip ループが deferral された AC を除外しない) を発見しており、いずれも根は同じ形状 — 「新しい宣言的記録が、隣接する既存の汎用正規化ロジックによって明示的な除外なしに黙って上書き・無視されるリスク」。本 Issue のスコープ自体がまさにこの形状の再発防止 (#903/#939) だったことを踏まえると、実装フェーズでも同型の再発が起きたことは示唆的であり、`/verify` の documented-deferral detection や類似の新規 record 型を追加する将来の Issue では、レビューチェックリスト項目として明示的に確認する価値がある。

### Acceptance criteria verification difficulty

Pre-merge AC 3件はすべて `rubric` (mode-independent) で、`/code` の自己判定と本レビューでの独立再判定がいずれも PASS で一致し、UNCERTAIN や verify command 品質の問題はなかった。rubric 文言が十分に精密だったことを示唆している。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC 3件は全て checked 済みで、review-incomplete-fallback も検出されなかったため、pre-merge AC gate をそのまま通過して squash merge を実行した
- PR #1367 は conflict なし (mergeable=true, reason=clean) だったため、Step 3 のコンフリクト解消手順は不要だった

### Deferred Items
- code-side auto-retry の documented-deferral escape hatch 未対応の件は review フェーズからの引き継ぎのまま — 発生が観測された場合の follow-up Issue 候補として維持
- `modules/ambiguity-detector.md` の Purpose 文陳腐化 (CONSIDER) も未修正のまま持ち越し

### Notes for Next Phase
- `/verify` では post-merge AC (`verify-type: opportunistic`) の「次回 costly step を含む Issue の spec → code フェーズで確認/deferral protocol が発火することを観察」を確認する
- ISSUE_NUMBER=951, BASE_BRANCH=main のため `closes #951` により Issue は自動クローズされる見込み
