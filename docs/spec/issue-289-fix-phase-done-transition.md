# Issue #289: verify: CLOSED 時の phase/done 遷移抜けを修正

## Overview

`/audit stats --since 2026-04-13` で、直近の CLOSED Issue 116 件のうち 60 件 (51.7%) が `phase/verify` のまま `phase/done` へ到達していないことが検出された。`/verify` の CLOSED 経路で「post-merge に未チェックの opportunistic / manual 条件が残っていると `phase/verify` を維持する」ロジックが原因。この設計により、auto-verification は全 PASS しているにもかかわらず strict First-try メトリクス (44.9%) が pragmatic 実態 (96.6%) と乖離する。本 Issue では `/verify` の CLOSED 経路判定を「Issue CLOSED + 全 auto-verification PASS → 常に `phase/done`」へ変更し、metric を実際の品質に整合させる。

## Reproduction Steps

1. Issue を作成し、`## Acceptance Criteria > Post-merge` に `<!-- verify-type: opportunistic -->` または `<!-- verify-type: manual -->` タグ付きの未チェック条件を 1 件以上含める
2. `/spec` → `/code` → `/review` → `/merge` を実行し PR をマージ（`closes #N` により Issue が CLOSED になる）
3. `/verify $NUMBER` を実行
4. Auto-verification の全条件が PASS/SKIPPED であっても、未チェックの opportunistic / manual 条件が残っているため、Issue が `phase/verify` ラベル付きで CLOSED 状態のまま留まる
5. `gh issue view $NUMBER --json state,labels` で `state: CLOSED` かつ `labels: phase/verify` が確認できる

期待挙動: auto-verification が全 PASS していれば、opportunistic / manual の未チェックに関わらず `phase/done` へ遷移し CLOSED のまま完了する。

## Root Cause

`skills/verify/SKILL.md` の CLOSED 経路判定（概ね L347-358、"When Issue is CLOSED (standard flow via `closes #N`)" セクション）が「未チェックの opportunistic / manual 条件が残る場合は `phase/verify` を維持」と規定している。この判定は「opportunistic / manual も全てチェック済みでないと `phase/done` に到達できない」ことを意味し、次の 2 点から 51.7% の滞留を生む:

1. **manual 条件**: 人間の観察記録が前提のため、merge 後に自動でチェックされる経路が無い
2. **opportunistic 条件**: `modules/opportunistic-verify.md` で事後チェックされるが、条件が特定の skill 実行文脈（例: `/auto` で CI 進行中の観測）を要求する場合は自然に満たされない

いずれも「auto-verification で品質保証済 = workflow 完了」という `phase/done` の本来意味と独立した状況であり、`phase/verify` に留め続けるのは strict metric の歪みを生む。修正は CLOSED 経路判定を単純化し「Issue CLOSED + 全 auto-verification PASS/SKIPPED → 常に `phase/done`」とする。opportunistic 条件は `opportunistic-verify.md` が従来通り post-hoc でチェックボックス更新を行い、manual 条件は informational として残す。

## Changed Files

- `skills/verify/SKILL.md`: CLOSED 経路の判定を修正。"When Issue is CLOSED" セクション（L347-358 周辺）の「unchecked opportunistic or manual conditions」分岐を削除し、Issue CLOSED + 全 auto-verification PASS/SKIPPED → `phase/done` 遷移へ単純化。OPEN 経路（L412-429 周辺、auto-close 無効シナリオ）は変更しない
- `docs/workflow.md`: 新挙動に合わせて文言更新
  - L228-229: Auto-close Disabled セクションの CLOSED 挙動記述は OPEN 経路のため現状維持
  - L193-197: Standard Flow via `closes #N` 図の「PASS → Complete」記述は既に新挙動と整合するので補足コメント追加程度
  - 必要であれば L168-169 の Phase Label 表に「`/verify` (on all auto-verify PASS/SKIPPED)」と明確化
- `docs/ja/workflow.md`: 上記の日本語ミラーを同期（L188 周辺、L222 周辺）
- `tests/gh-label-transition.bats`: `done` 遷移で `phase/verify` が明示的に除去されることの regression test を追加（新テストケース 1 件、bash 3.2+ 互換）

## Implementation Steps

1. `skills/verify/SKILL.md` L347-358 の "When Issue is CLOSED" セクションを修正 (→ 受入条件 A)
   - `If unchecked opportunistic or manual conditions remain` 分岐を削除
   - `All auto-verification target conditions are PASS or SKIPPED` ブロック直下を「remove all `phase/*` labels and assign `phase/done`」に単純化し、`gh-label-transition.sh "$NUMBER" done` を常に呼ぶよう変更
   - 「Even if post-merge conditions without hints are unchecked, do not reopen the Issue」の既存ガイドは残置（`phase/done` 到達後も不要な reopen を起こさないため）
   - 変更意図を 1-2 行のコメントで補足（opportunistic は opportunistic-verify.md が事後チェック、manual は informational）
2. `docs/workflow.md` を新挙動に同期 (→ 受入条件 A)
   - L228-229: Auto-close 無効時の CLOSED 挙動は OPEN 経路なので現状維持（こちらは fix 対象外）
   - L193-197 付近: CLOSED Standard Flow の PASS 挙動が「opportunistic/manual 残存の有無に関わらず `phase/done`」と読める文言に調整
   - 必要なら opportunistic / manual 条件が事後的に checkbox 更新される旨を 1 行追記
3. `docs/ja/workflow.md` を同趣旨で更新 (→ 受入条件 A)
   - 英語版の変更ブロックに対応する日本語記述を同期（本文行数・記述スタイルは既存ミラーに準拠）
4. `tests/gh-label-transition.bats` に regression test を追加（after 1） (→ 受入条件 B)
   - テスト名: `@test "regression (#289): transition to done removes phase/verify"`
   - 既存の "success: transition to done phase" が add-label 中心のため、`--remove-label phase/verify` の明示的存在を `grep` でアサート
   - bash 3.2+ 互換（`declare -A` 不使用、`mapfile` 不使用）

## Verification

### Pre-merge

- <!-- verify: rubric "CLOSED 状態で phase/verify ラベルのまま残る経路の原因が特定され、/verify, /auto, run-verify.sh, gh-label-transition.sh のうち該当するファイルに phase/done 遷移を確実化する修正が反映されている" --> `phase/verify → phase/done` 遷移の抜け箇所を特定し、該当する全ての経路を修正
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> `phase/verify` のまま CLOSED される経路が存在しないことを担保する bats 回帰テストを追加し、CI の bats ジョブが PASS

### Post-merge

- 本 Issue マージ後 1 週間以内に新規 CLOSED された Issue について、`/audit stats` を実行して `phase/done` 到達率が 95% 以上に改善していることを確認

## Notes

- **修正範囲の限定**: `/auto` の XL 親 Issue close フロー（`skills/auto/SKILL.md` L247-272）は独立した cross-cutting 条件判定のため本 Issue の対象外。XL 親は未チェック条件がある場合に `phase/verify` へ遷移してユーザーに `/verify $NUMBER` 実行を促す設計であり、そこで本 Issue の修正後 `/verify` が呼ばれれば同じく `phase/done` に到達する（間接的に整合）
- **OPEN 経路は変更しない**: `skills/verify/SKILL.md` L412-429 の OPEN 経路（auto-close 無効シナリオ）は、Issue がまだ OPEN である限りユーザーの手動検証意図を尊重する必要があるため `phase/verify` + Issue OPEN 維持の既存挙動を保持
- **既存 60 件のバックフィルは対象外**: Issue の Non-Goals に明記済み
- **bats テストが LLM 経路を直接検証できない制約**: `/verify` SKILL.md の判定ロジックは LLM 解釈のため bats で直接再現できない。代わりに (a) pre-merge の `rubric` verify command で SKILL.md への修正反映を意味レベルで検証、(b) bats 回帰テストで下位 script (`gh-label-transition.sh`) の `phase/verify` 除去が不変であることを保証
- **参考先行例**: #39 (patch route の phase/done ラベル遷移), #132 (gh-label-transition: target ラベル消失バグ)

## Code Retrospective

### Deviations from Design

- なし。実装ステップ 1〜4 をすべて Spec 通りに実施した。

### Design Gaps/Ambiguities

- Spec の Changed Files には `docs/workflow.md` の L168-169 「必要であれば明確化」と記載されていたが、実際に読んでみると phase/done の Assigned by 列「/verify (no post-merge conditions)」が旧挙動を示していたため、明確化ではなく修正（「/verify (on all auto-verify PASS/SKIPPED)」）が必要だった。

### Rework

- なし。

## review retrospective

### Spec vs. implementation divergence patterns

特記なし。Spec の実装ステップ 1〜4 が PR diff と完全に対応しており、構造的な乖離は検出されなかった。

### Recurring issues

特記なし。4つの観点（Spec乖離・バグ/ロジック・steering document整合性・ドキュメント整合性）すべてで問題は検出されなかった。同種の問題の繰り返しはなし。

### Acceptance criteria verification difficulty

特記なし。`rubric` verify command は Spec 記載内容と diff を照合して問題なく判定できた。`github_check` は CI ステータス直接確認で明確に PASS。UNCERTAIN 判定はゼロ。verify command の精度は良好。
