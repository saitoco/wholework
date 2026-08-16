# Issue #1302: spec/review: 監査・実査レポートの判断根拠に現れる識別子を実在確認する工程を定着

## Overview

監査・実査系 Issue (#1270 の sub-issue #1274 / #1276) が生成するレポートに、実在しない参照 (削除済み関数・存在しないパス・存在しない節名) が判断根拠として書き込まれる事象が独立に 2 件発生した。いずれも `/review` が事後に検出しているが、記述前に実在確認する工程が定着していないため再発リスクが残る。

Issue 本文が示す対応方針のうち、(a) を本筋として採用する: `/spec` の Step 6 (Codebase Investigation) に、対象 Issue を「監査・実査系」と判定する基準と、判定時に Implementation Steps へ識別子実在確認工程を自動的に含める仕組みを追加する。(b) を補強として採用する: `agents/review-spec.md` の Perspective 1 (Spec Deviation Check) に、監査・実査系 Issue を対象とした「引用参照の実在確認」チェックを明文化する。(c) (バッククォート識別子を機械的に一括検証するスクリプト) は Issue 本文の指示通り、誤検出 (外部ツール名・将来提案など) の扱いに設計が必要なため、(a)(b) の効果測定後に別 Issue で判断するスコープ外項目とする。

## Changed Files

- `skills/spec/SKILL.md`: Step 6 (Codebase Investigation) の「Fail-safe critical script identification」直後・Step 7 直前に、「Audit/investigation-type Issue identifier verification requirement」サブチェックを追加する
- `agents/review-spec.md`: Perspective 1 (Spec Deviation Check) の「2.5. Enum coverage check」直後・「3. Uncertainty verification check」直前に、「2.6. Cited reference existence check」を追加する

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 6 (Step 220 付近、"Fail-safe critical script identification" ブロックの直後、Step 7 見出しの直前) に、以下の内容 (英語) でサブチェックを追加する: (→ acceptance criteria 1, 2)

   ```markdown
   **Audit/investigation-type Issue identifier verification requirement (regardless of SPEC_DEPTH; only when applicable):**

   Judge the target Issue as **audit/investigation-type** when it meets both of the following:
   - (a) Its purpose is to investigate and classify multiple existing items (acceptance-condition lines, functions, code paths, configuration entries, etc.) against defined categories — not to build new functionality.
   - (b) The classification's per-item judgment rationale is recorded in a persistent artifact (Issue body, Spec, or a `docs/reports/*.md`-style report) that a later process — automated (`/verify`, `/audit`) or human — will read as the basis for a decision, rather than for one-time human reading only.

   Signals (use together with the criteria above, not as a standalone trigger): the Issue title/body uses 実査/監査/audit/分類-type language, and Implementation Steps call for producing a per-item table or list with a judgment column (e.g., A/B/C/D classification, PASS/FAIL, retire/keep).

   Steps:
   1. When judged audit/investigation-type, add an Implementation Step (or extend the relevant investigation step) requiring: any concrete identifier written as judgment rationale — function name, file path, section heading, configuration key, etc. — must be existence-verified with `grep -rn` / `Read` against the current codebase before being written, with specific attention to whether a later implementation change removed the referenced target.
   2. Record the judgment (audit/investigation-type: yes/no, with rationale) in the Spec's "Notes" section.

   **Example (#1274, #1276, sub-issues of #1270)**: both independently cited nonexistent references as judgment rationale in their audit reports. #1274 cited a function already deleted by #1181 (`_write_tier2_recovery_to_spec()` / `_write_manual_recovery_to_spec()`); #1276 cited a path and a section heading that never existed (`.tmp/auto-checkpoint-*.json`, `workflow-guidance.md § Completion Report Addition`). Both were transcribed from memory/assumption rather than grep-confirmed, and both reached the report before `/review` caught them. Requiring existence verification before writing would have surfaced both at spec/code time instead.

   **Reinforcement**: `agents/review-spec.md` Perspective 1 additionally checks cited-reference existence for audit/investigation-type Issues as a second line of defense (see that file's "Cited reference existence check").

   **Skip** if the Issue is not judged audit/investigation-type.
   ```

2. `agents/review-spec.md` の Perspective 1 内 (54-58 行付近、"2.5. Enum coverage check" 直後、"3. Uncertainty verification check" 直前) に、以下の内容 (英語) でサブチェックを追加する。既存の暗黙的な検出 (review-bug×2 + review-spec が #1276 で共通検出、review が #1274 を検出) を明文化する。 (parallel with 1) (→ Notes の (b) 補強)

   ```markdown
   2.6. **Cited reference existence check** (execute only for audit/investigation-type Issues — see `skills/spec/SKILL.md` § "Audit/investigation-type Issue identifier verification requirement" for the judgment criteria):
      - Judge whether the Issue is audit/investigation-type using the same criteria as `/spec`: it investigates/classifies multiple existing items against defined categories, and the per-item judgment rationale is recorded in a persistent artifact that a later process will read as a decision basis.
      - When judged audit/investigation-type, for each concrete identifier (function name, file path, section heading, configuration key) cited in the PR diff as judgment rationale, verify with Grep/Read that the identifier still exists in the current codebase.
      - Flag any identifier that cannot be found (e.g., a function deleted by a later Issue, a path never created, a section heading that does not exist) as a MUST finding.
   ```

3. 実装後、`python3 scripts/validate-skill-syntax.py skills/spec/SKILL.md` と `bash scripts/check-forbidden-expressions.sh` を実行し、half-width `!` や forbidden expressions が混入していないことを確認する。 (after 1, 2) (→ 実装品質確認)

## Verification

### Pre-merge
- <!-- verify: rubric "skills/spec/SKILL.md または関連 module に、監査・実査系 Issue の Implementation Steps へ識別子の実在確認工程を含める旨が記述されている" --> 実査・監査系 Issue の Implementation Steps に、判断根拠の識別子を実在確認する工程が含まれる仕組みが定義されている
- <!-- verify: rubric "実査・監査系 Issue の判定基準が記述されており、適用範囲が曖昧でない" --> 上記の仕組みが「どの Issue を実査・監査系と判定するか」の基準とともに記述されている
- <!-- verify: rubric "本 Issue の Background が挙げた 2 例について、提案する工程で検出可能であることが Spec または実装内で確認されている" --> 既存の `docs/reports/observation-ac-audit-*.md` を対象に、この工程を適用した場合に #1274 / #1276 の欠陥が検出できることが確認されている

### Post-merge
- 次に実査・監査系 Issue が実行されたとき、レポート内の参照が実在確認を経ていることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

### 監査・実査系 Issue の判定基準 (要約)

`skills/spec/SKILL.md` に追加する判定基準 (英語) は以下 2 条件の AND:
- (a) 目的が既存の複数項目 (AC 行・関数・コードパス・設定項目など) を定義済みカテゴリに分類・実査することであり、新機能構築ではない
- (b) 分類結果の項目ごとの判断根拠が、将来の自動処理 (`/verify`・`/audit`) または人間が判定材料として参照する永続的な成果物 (Issue 本文・Spec・`docs/reports/*.md` 形式のレポート) に記録される (その場限りの人間による一読用ではない)

補助シグナル (上記 2 条件と併用し、単独では判定条件としない): タイトル/本文に「実査」「監査」「audit」「分類」等の語があり、Implementation Steps が判定列 (A/B/C/D 分類、PASS/FAIL、retire/keep 等) を持つ項目別の表・リストを生成物として要求している。

適用範囲の明確化: #1274 / #1276 / 親 #1270 (いずれも「observation AC を実査し分類・retire する」ことが目的で、分類結果を `docs/reports/observation-ac-audit-*.md` に永続化し将来の `/verify`/`/audit` 判断材料とする) は上記 2 条件をいずれも満たすため対象。一方、通常の機能実装 Issue (新機能構築が目的、または判断根拠を永続化しない一時的な調査) は (a) または (b) のいずれかを満たさないため対象外。

### Pre-merge AC 3 の実在確認ウォークスルー (Background の 2 例)

- **#1274**: 分類 A の判断根拠として `_write_tier2_recovery_to_spec()` / `_write_manual_recovery_to_spec()` を引用していたが、これらは #1181 で削除済み (`modules/orchestration-fallbacks.md` に削除記録あり)。新設する工程に従い記述前に `grep -rn "_write_tier2_recovery_to_spec\|_write_manual_recovery_to_spec" .` を実行すればヒット 0 件 (現在のリポジトリで実行し確認済み — `docs/sessions/*/session.md` 内の過去ログにのみ言及が残り、`scripts/`・`modules/` の実装コードには存在しない) となり、引用時点で誤りに気付ける。実際には `/review` (PR #1297) が事後に検出し D (retire) へ再分類した。
- **#1276**: Spec 本文が判断根拠としてパス `.tmp/auto-checkpoint-*.json` と節名 `workflow-guidance.md § Completion Report Addition` を引用していたが、いずれも実在しない (実際のチェックポイントファイルは `scripts/auto-checkpoint.sh` が書く `.tmp/auto-state-*.json` / `.tmp/auto-batch-state*.json` であり `auto-checkpoint-*.json` という命名のファイルは存在しない。`skills/review/workflow-guidance.md` は実在するが見出しは Purpose / Find/Filter Separation Contract / Pre-flight / Processing Steps / Inline Workflow Script / Cost Transparency のみで `Completion Report Addition` という節は存在しない — いずれも現在のリポジトリで確認済み)。新設する工程に従い記述前に該当パスの `grep -rn` および `workflow-guidance.md` の `Read`/節名 `grep` を行えば、パス・節名ともに 0 件でヒットせず、引用時点で誤りに気付ける。実際には review-bug×2 + review-spec が事後に共通検出した。

上記 2 例により、新設する工程が Background の欠陥を検出可能であることを確認した (Pre-merge AC 3 に対応)。

### スコープ外

- (c) 機械的な検証スクリプト (レポート内のバッククォート識別子を抽出し一括で実在チェックする) は、誤検出 (外部ツール名・将来提案など) の扱いに設計が必要なため、Issue 本文の方針通り本 Issue のスコープ外とする。(a)(b) の効果測定後に別 Issue で判断する。
- `agents/review-light.md` (Size XS/S 等で使う軽量レビュー) への同等追加は、Issue 本文の (b) が review-spec に限定して言及しているため本 Issue のスコープに含めない。監査・実査系 Issue が light レビュー経路を通ることが実測で確認されれば、フォローアップ Issue で検討する。
- `modules/review-type-weighting.md` の Type 別重み付け表は変更しない。今回追加する判定基準は Issue Type (Bug/Feature/Task) ではなく Issue の目的・構造 (実査・分類レポートかどうか) に基づく直交する軸であるため。

### 判断根拠 (auto-resolve, non-interactive — SPEC_DEPTH=light のため Step 7 の Ambiguity Resolution は適用外。以下に本 Spec 独自の判断根拠を記録する)

- 挿入位置は `skills/spec/SKILL.md` Step 6 内の既存パターン ("Fail-safe critical script identification" 等、「regardless of SPEC_DEPTH; only when applicable」形式の条件付きチェック) に倣った。理由: 本チェックも「対象 Issue が特定の性質を満たす場合のみ Implementation Steps に定型文言を追加する」という同型の構造を持つため。
- `agents/review-spec.md` 側の挿入位置は Perspective 1 内の「2.5. Enum coverage check」直後とした。理由: 2.5 も「Spec/PR が特定条件を満たす場合のみ実行する PR diff 横断チェック」という同型の構造であり、既存の「3. Uncertainty verification check」とは検証対象が異なる (Spec の Uncertainties セクション vs. 判断根拠として引用された識別子) ため、3 の前に独立した番号で追加した。
- 判定基準・チェック文言は英語で記述する方針とした。`skills/spec/SKILL.md`/`agents/review-spec.md` は CLAUDE.md の言語規約上 Documentation カテゴリ (英語) に該当するため。
- Issue 本文は (a) を本筋・(b) を補強と位置づけているが、Issue タイトル自体が「spec/review:」と両方を明示していること、および (b) が「既に暗黙には機能しているが明文化すると安定する」という積極的な理由を伴っていることから、(a)(b) 両方を本 Issue のスコープに含めた。(c) のみ Issue 本文の指示に従い明確に除外した。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
N/A — Implementation Steps 1・2 は Spec の記述内容をそのまま `skills/spec/SKILL.md` / `agents/review-spec.md` の挿入位置に反映した。挿入位置・文言ともに Spec 通り。

### Design Gaps/Ambiguities
- Pre-merge AC 3 の rubric grader は Spec ファイルを入力対象外とする (`modules/verify-executor.md` § Rubric Command Semantics)。Spec の Notes に書いた #1274/#1276 の実在確認ウォークスルーは grader からは見えないため、rubric テキストが要求する「Spec または実装内で確認されている」を満たすには、実装 (`skills/spec/SKILL.md` の新設 Example パラグラフ) 側にも #1274/#1276 の具体的な誤参照と検出可能性の説明を書く必要があった。Implementation Steps 1 の Example にその説明を含めることで対応した。

### Rework
N/A — 手戻りなし。

## Smoke Test
N/A — Spec に `## Smoke Test` セクションなし。

## Test Results
`bats --jobs 18 tests/`: 1802/1803 PASS。1件の FAIL (`tests/code.bats` "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route") は、本PRの変更 (`skills/spec/SKILL.md` / `agents/review-spec.md`) を `git stash` で除去した状態でも再現することを確認済みの既存の不整合であり、本 Issue の実装とは無関係。Follow-up Issue #1377 として既に追跡されている (重複作成はスキップ)。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1・2 の文言をそのまま `skills/spec/SKILL.md` Step 6 (Step 7 見出し直前) と `agents/review-spec.md` Perspective 1 (2.5 直後・3 直前) に反映した。挿入位置・文言ともに Spec の指示通りで、追加の判断は不要だった。
- Pre-merge AC 3 (rubric) は grader が Spec ファイルを読まないため、Spec の Notes に書いた #1274/#1276 の実在確認ウォークスルーとは別に、`skills/spec/SKILL.md` の Example パラグラフ自体に両ケースの具体的な誤参照を明記する形で満たした。

### Deferred Items
- `tests/code.bats` の既存 FAIL (Step 10 の期待文字列と `skills/code/SKILL.md` の実際の文言の乖離) は本 Issue のスコープ外・既存の不整合として特定し、重複起票を避けて既存の Follow-up Issue #1377 に委ねた。本 PR では対処しない。

### Notes for Next Phase
- `/review` は本 PR で新設した `agents/review-spec.md` の "2.6. Cited reference existence check" 自身が正しく機能するかも間接的に検証対象になる (review-spec 自身のロジック変更のため、通常の Spec Deviation Check の一部として評価される)。
- Post-merge AC (observation, `event=auto-run session=next`) は次に監査・実査系 Issue が実行されたときに評価される。`/verify` 初回実行時点ではまだ発火していない可能性が高い (SKIPPED 想定)。
