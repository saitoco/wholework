# Issue #1039: spec: Steering Docs sync candidate 洗い出しに grep -rn cross-search を手順化

## Consumed Comments

- saito (MEMBER / first-class) — `/issue` フェーズの Issue Retrospective コメント (triage 判定根拠、曖昧性の自動解決ログ、スコープ評価スキップの記録)。内容は既に Issue 本文の `## Autonomous Auto-Resolve Log` に反映済みであり、本 Spec に追加で取り込むべき新規要求はなし。
  URL: https://github.com/saitoco/wholework/issues/1039#issuecomment-5048163607

## Overview

`skills/spec/SKILL.md` Step 10 の「Steering Docs sync candidate check」節 (L275-291) を修正する。現行の `grep -l "<keyword>" docs/*.md docs/ja/*.md` は非再帰 glob であり、`docs/guide/customization.md` のような 2 階層目のファイルを走査対象に含めない。これが #1035 で config-reference table の sync 漏れが発生した一因になった。加えて、対象ファイルが正しく特定された場合でも prose 箇条書きのみを sync し、テーブル/リファレンス表セルの陳腐化を見落とすというフォーマット網羅不足も #1035 の review retrospective で確認されている。

Issue Proposal の Option A (grep -rn への修正 + 対象キー拡張 + フォーマット網羅の明示化) と Option D (docs + tests + scripts への横断範囲拡張) を採用し、`skills/spec/SKILL.md` 1 ファイルの修正で対応する (詳細な採否理由は Notes 参照)。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 の「Steering Docs sync candidate check」節 (L275-291) を、recursive `grep -rn` + docs/tests/scripts 横断 + フォーマット網羅の明示化を含む手順に置き換える

## Implementation Steps

1. `skills/spec/SKILL.md` の「**Steering Docs sync candidate check (when Changed Files includes SKILL.md or scripts/):**」節 (現行 L275-291。`doc-checker.md` 参照行の直後、`**\`docs/ja/\` translation sync check:**` の手前) を以下の内容に置き換える (→ AC1, AC2):

   ```
   **Steering Docs sync candidate check (when Changed Files includes SKILL.md or scripts/):**

   When the Spec's Changed Files section includes `SKILL.md` files (e.g., `skills/auto/SKILL.md`) or files under `scripts/`, run a recursive `grep -rn` cross-search across `docs/`, `tests/`, and `scripts/` to find files that reference the changed skill/script name, or any config key / marker name / function name this Issue introduces or changes. List found files as sync candidates in the Changed Files section.

   Steps:
   1. Extract target keywords from each changed file:
      - `skills/{name}/SKILL.md` → keyword: `{name}` (e.g., `auto`, `spec`)
      - `scripts/{script-name}.sh` → keyword: `{script-name}.sh` (e.g., `run-code.sh`)
      - Also extract any config key, marker name (`type=...`), or function name this Issue introduces or changes (e.g., `capabilities.pr-preview`, `type=preview-ac-unverified`) — these are often more specific sync-relevant terms than the skill/script name alone
   2. For each keyword, run:
      ```bash
      grep -rn "<keyword>" docs/ tests/ scripts/ 2>/dev/null
      ```
      Unlike a `docs/*.md`-style non-recursive glob (which misses second-level files such as `docs/guide/customization.md`), this reaches every file under the three directories. The `-n` output shows each matching line's content, not just the filename, so a prose bullet and a table cell are both visible in one pass.
   3. For each file found, add a **Steering Docs sync candidate** entry to the Changed Files section, checking category-specific patterns:
      - **docs/**: check ALL occurrence formats (prose bullets, config-reference tables, variable tables, code blocks) — a table cell can go stale independently of a prose paragraph describing the same key elsewhere in the same file
      - **tests/**: check whether another `.bats` file targets the same script/behavior (e.g., both `tests/run-verify.bats` and `tests/verify.bats` may need the same update)
      - **scripts/**: check whether a helper script called by the changed script also references the keyword

      e.g., `docs/guide/customization.md`: [Steering Docs sync candidate] verify `<keyword>` description is current across prose and config-reference table occurrences; update if needed
   4. The `/code` phase makes the final include/exclude decision by reading each candidate; listing them here prevents silent omission at implementation time

   **Skip** if Changed Files does not include SKILL.md files or files under `scripts/`.
   ```

## Verification

### Pre-merge

- `skills/spec/SKILL.md` (または `modules/detect-config-markers.md`) に Steering Docs sync candidate 洗い出し時の `grep -rn` cross-search 手順が明示的に文書化されている <!-- verify: rubric "skills/spec/SKILL.md または modules/detect-config-markers.md に、Spec Notes で対象キーを grep -rn で全出現箇所を洗い出しテーブル/リファレンス表も sync 対象に含める手順が明示的に文書化されている" -->
- 選択した方針に対応する挙動が実装されている <!-- verify: rubric "Proposal で選択した A/B/C/D の方針が対応する SKILL.md または module の手順として整合的に実装されている" -->

### Post-merge

- 次回の Spec Notes 記述で config key/marker/function name の cross-search が実施されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

### Proposal 選択理由 (Option A + D 採用)

- **採用: Option A** (`skills/spec/SKILL.md` の Steering Docs sync candidate 節への追記) — 根本原因 (非再帰 glob) が同節内にあるため直接修正できる。加えて対象キーを skill/script 名だけでなく config key/marker/function name にも広げ、prose/table 両フォーマットの網羅を明示する (Issue Proposal Option A の記述どおり)。
- **採用: Option D** (docs + tests + scripts 横断) — #1037 フォローアップで既にユーザーから明示的に追加推奨されており (Issue の `## Related` 参照)、#1037 Verify Retrospective の Improvement Proposal でも test ファイル側の同種再発 (`tests/run-verify.bats` の Changed Files 遺漏) が報告済み。docs 単独ではなく tests/scripts も同じ節でカバーする。
- **不採用: Option B** (`modules/detect-config-markers.md` への集約) — 「Steering Docs sync candidate」という語は現状 `skills/spec/SKILL.md` にのみ存在し (`grep -rln "Steering Docs sync candidate" .` で確認、他のヒットはすべて `docs/spec/issue-*.md` の disposable な過去 Spec)、他スキルとの共有は発生していない。共有モジュール化は 2 つ目の消費者が現れた時点で判断するのが妥当であり、現時点では時期尚早と判断した。
- **不採用: Option C** (`/review` の review-spec への自動 cross-search 組み込み) — Issue の Purpose は明示的に「Spec フェーズでの早期発見」であり、`/review` 側の自動化は `agents/review-spec.md` 等の追加変更を要し、triage 判定の Size=S (SKILL.md/module 1-2 ファイル規模) から逸脱する。review 側の safety net は既に機能しており (#1028, #1035 とも review-spec が catch 済み)、実害は最小限のため見送る。

### 根本原因の確認 (dogfooding)

- `grep -rln "Steering Docs sync candidate" .` を実行し、本節の記述が `skills/spec/SKILL.md` にのみ存在すること (他は `docs/spec/issue-*.md` の過去 disposable Spec のみ) を確認した。これにより、本 Issue自身の変更 (Changed Files: `skills/spec/SKILL.md` のみ) について `docs/structure.md` / `docs/tech.md` / `docs/workflow.md` 側の sync 候補が存在しないことを検証済み ("No change needed" pre-verification rule 準拠)。#858 Spec の doc-checker 判定 (内部処理サブステップ変更のため外部インターフェース記述は不要) と同じ結論に至った。
- #1035 の実際の Spec (`docs/spec/issue-1035-preview-ac-marker-staleness.md`) を確認したところ、config-reference table の見落としは「ファイルグロブが 2 階層目に届かなかった」ことだけでなく、「`docs/guide/*.md` を明示的にスコープへ加えた後でも、prose 箇条書きの sync は行いテーブルセルの sync は見落とした」というフォーマット網羅不足も同時に発生していたことを確認した。そのため本 Spec の実装は非再帰 glob の修正だけでなく、フォーマット網羅の明示的なチェックリスト化 (Implementation Steps 手順 3) の両方を含めている。

### Simplicity check

- Changed Files: 1 ファイル (制限 5 以内 ✓)
- Implementation Steps: 1 ステップ (制限 5 以内 ✓)
- Verification Pre-merge: 2 項目 (制限 5 以内 ✓)

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 記載の置き換え内容をそのまま `skills/spec/SKILL.md` L275-291 に適用した。逸脱なし。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps どおり `skills/spec/SKILL.md` 1 ファイルのみを修正し、Option B (`modules/detect-config-markers.md` への集約) は不採用のまま維持した — Spec Notes の不採用理由 (共有モジュール化は 2 つ目の消費者が現れてから判断) を継承
- 変更ファイルが `skills/spec/SKILL.md` のみで、かつ `tests/check-file-overlap.bats` / `tests/run-spec.bats` / `tests/operate-route.bats` の複数ファイルが同ファイルを参照していたため、Behavioral Change Detection の基準に従い `bats tests/` full suite を実行 (1230 件 PASS、FAIL 0)
- pre-merge AC 2 件はいずれも rubric 条件のため、diff を根拠に adversarial に自己評価し両方 PASS と判定、Issue checkbox を更新した

### Deferred Items
- Post-merge の observation AC (`次回の Spec Notes 記述で config key/marker/function name の cross-search が実施されることを観察`) は定義上、次回の `/spec` 実行時に事後観察されるものであり、本フェーズでは検証不可 — `/verify` は通常実行時にスキップし、`event=auto-run` 発火時に再評価される

### Notes for Next Phase
- patch route (Size S) のため PR は作成されない。`/verify` は merge-to-main 後の main ブランチに対して直接実行される
- Spec 本文の "根本原因の確認 (dogfooding)" セクションで、本 Issue 自身の変更について Steering Docs 側の sync candidate が存在しないことを既に検証済み (`grep -rln "Steering Docs sync candidate" .` で `skills/spec/SKILL.md` のみヒットを確認) — `/verify` 側で追加の doc sync 確認は不要
