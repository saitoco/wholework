# Issue #304: verify: CLOSED 経路で Post-merge 条件が未チェックでも phase/done 遷移する回帰を修正

## Overview

#289 の修正 (PR #291) で `skills/verify/SKILL.md` の CLOSED 経路判定が「auto-verification 全 PASS/SKIPPED → 常に `phase/done`」へ単純化された結果、Post-merge に未チェックの opportunistic/manual 条件が残る Issue も `phase/done` に遷移する回帰が発生した。OPEN 経路 (L413-425) は旧挙動（未チェック opportunistic/manual 残 → `phase/verify`）を保っているため、CLOSED と OPEN で判定ロジックが矛盾している。本 Issue では CLOSED 経路の判定を OPEN 経路と同型に揃え、Post-merge 未チェック時は `phase/verify` を維持、全 checked 時のみ `phase/done` へ遷移する挙動に戻す。

## Reproduction Steps

1. Issue を作成し `## Acceptance Criteria > Post-merge` に `<!-- verify-type: manual -->` タグ付きの未チェック条件を 1 件以上含める
2. `/spec` → `/code` → `/review` → `/merge` を実行し PR を `closes #N` 付きでマージ（Issue が CLOSED になる）
3. `/verify $NUMBER` を実行
4. auto-verification 全条件が PASS/SKIPPED でも、CLOSED 経路は現状「常に `phase/done`」のため、未チェックの manual 条件を残したまま `phase/done` に遷移してしまう
5. `gh issue view $NUMBER --json labels` で `phase/done` が確認でき、本来は `phase/verify` であるべき状態と乖離する

期待挙動: 未チェックの opportunistic/manual 条件が残る場合は `phase/verify` を維持（Issue CLOSED のまま）。全 checked で初めて `phase/done` に遷移する。

## Root Cause

`skills/verify/SKILL.md` L348-354 の CLOSED 経路が「auto-verification 全 PASS/SKIPPED → 常に `phase/done`」に単純化されており、Post-merge セクション内の未チェック opportunistic/manual 条件を見ていない。一方 OPEN 経路 L413-425 は同じ条件下でも「未チェック opportunistic/manual が残る → `phase/verify`」「全 checked → `phase/done` + `gh issue close`」の 2 分岐を保持しており、両経路で判定が不整合。

修正は CLOSED 経路に OPEN 経路と同等の分岐を移植する。違いは Issue 状態のみ: OPEN 経路は `phase/done` 時に `gh issue close` を呼ぶが、CLOSED 経路では Issue 既に CLOSED のため close 呼び出しは不要（未 close の XL 親 Issue フォールバックは既存挙動のまま維持）。

## Changed Files

- `skills/verify/SKILL.md`: CLOSED 経路 (L344-354) の判定を OPEN 経路 (L413-425) と同型の分岐に変更。「auto-verification 全 PASS/SKIPPED」ブロック内で Post-merge セクションの未チェック opportunistic/manual 条件を判定し、残れば `phase/verify` 維持、全 checked なら `phase/done` に遷移する形に再構成。XL 親 Issue 等で未 close の場合の `gh issue close` フォールバックは保持
- `docs/workflow.md`: L169 「phase/done の Assigned by 列」と L195 「Standard Flow via `closes #N` の PASS 分岐記述」を新挙動に同期
- `docs/ja/workflow.md`: L162, L188 を英語版と同内容で同期（Japanese mirror）
- `tests/gh-label-transition.bats`: regression test ケースを追加 — `gh-label-transition.sh $N verify` 呼び出しで `--remove-label phase/done` が含まれること（既に `phase/done` の Issue を `phase/verify` に戻す挙動の下位保証）。bash 3.2+ 互換

## Implementation Steps

1. `skills/verify/SKILL.md` L344-354 の CLOSED 経路を修正 (→ 受入条件 A)
   - 「All auto-verification target conditions are PASS or SKIPPED」ブロックを OPEN 経路 L413-425 と同型の入れ子分岐に変更
   - サブ分岐 (a): Post-merge セクションに未チェックの `<!-- verify-type: opportunistic -->` または `<!-- verify-type: manual -->` 条件が残るか判定
   - サブ分岐 (a-1) 残る場合: `gh-label-transition.sh "$NUMBER" verify` を呼び `phase/verify` を付与（Issue CLOSED のまま）。ユーザー通知メッセージは OPEN 経路と同文言で統一
   - サブ分岐 (a-2) 全 checked の場合: `gh-label-transition.sh "$NUMBER" done` を呼び `phase/done` を付与。既存の「Confirm the Issue is closed. If not closed, close with `gh issue close ...`」ブロックは XL 親 Issue フォールバックとして維持
   - 既存ガイド「Even if post-merge conditions without hints are unchecked, do not reopen the Issue」は (a-2) 内に残置
2. `docs/workflow.md` を新挙動に同期 (after 1) (→ 受入条件 A)
   - L169 phase label 表: `Assigned by` 列を「`/verify` (on all auto-verify PASS/SKIPPED)」から「`/verify` (on all auto-verify PASS + all post-merge conditions checked)」へ変更
   - L185-197 Standard Flow via `closes #N` の PASS 分岐を、L221-225 Auto-close Disabled フローと同形式の 2 分岐で書き換え（「All auto-verify PASS + all conditions checked → phase/done」「All auto-verify PASS + opportunistic/manual unchecked → phase/verify (Issue stays CLOSED)」）
3. `docs/ja/workflow.md` を英語版と同じ変更で同期 (parallel with 2) (→ 受入条件 A)
   - L162 phase label 表の `/verify` 付与条件を更新
   - L178-190 `closes #N` 標準フローの PASS 分岐を 2 分岐に書き換え
4. `tests/gh-label-transition.bats` に regression test を追加 (parallel with 1) (→ 受入条件 B)
   - テスト名: `@test "regression (#304): transition to verify removes phase/done"`
   - 挙動: `bash "$SCRIPT" 304 verify` を実行し、`GH_CALL_LOG` に `--add-label phase/verify` と `--remove-label phase/done` の両方が含まれることを grep で確認
   - 既存 `regression (#289)` テストの隣に配置。bash 3.2+ 互換（`declare -A` / `mapfile` 不使用）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md の『When Issue is CLOSED』セクションが、auto-verification 全 PASS の場合でも未チェックの opportunistic/manual 条件が残るなら phase/verify を維持し、全 checked の場合のみ phase/done へ遷移する挙動に修正されている。OPEN 経路 (L413-425) の条件分岐ロジックと整合していること" --> CLOSED 経路の判定が「全 auto-verification PASS + 全 Post-merge 条件 checked → `phase/done`」「Post-merge 条件に unchecked あり → `phase/verify` 維持」に修正され、OPEN 経路と整合している
- <!-- verify: rubric "tests/gh-label-transition.bats に、CLOSED + 未チェックの opportunistic/manual 条件が残る場合に phase/verify が維持される（phase/done に遷移しない）ことを検証する新しい bats 回帰テストケースが追加されている" --> CLOSED + 未チェック opportunistic/manual → `phase/verify` 維持を検証する bats 回帰テストが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI の `Run bats tests` ジョブが PASS

### Post-merge

- 本 Issue マージ後 1 週間以内に、新規 CLOSED され Post-merge に未チェックの opportunistic/manual 条件が残る Issue が `phase/verify` に留まることを 1 件以上実例で確認

## Code Retrospective

### Deviations from Design

- なし。Spec の実装ステップを順序通りに実行した。

### Design Gaps/Ambiguities

- CLOSED 経路の「Even if post-merge conditions without hints are unchecked, do not reopen the Issue」の注記を (a-2) 全 checked ブロック内に配置した。Spec は「(a-2) 内に残置」と記載しており整合している。
- Step 10 の verify コマンド整合性チェックで `github_check "gh pr checks"` が PR 未作成のため UNCERTAIN となったが、これは pr route では通常の挙動（PR 作成後に CI が実行される）。

### Rework

- なし。

## review retrospective

### Spec vs. implementation divergence patterns

なし。CLOSED 経路への OPEN 経路同型ロジックの移植は Spec 記載の実装ステップと完全に一致しており、構造的な乖離は見られなかった。

### Recurring issues

なし。単一の CLOSED/OPEN 経路不整合を修正する明確なスコープで、同種の指摘が重複する箇所はなかった。

### Acceptance criteria verification difficulty

なし。`rubric` verify がセマンティックな検証を担い、`github_check` が CI 状態を確認する 2 段構えにより、3 条件すべてが PASS と判定できた。UNCERTAIN 発生もなく、verify コマンドの精度は適切だった。

## Notes

- **bats テストが LLM 経路を直接検証できない制約**: SKILL.md の CLOSED/OPEN 経路判定は LLM 解釈のため bats で直接再現できない。代わりに (a) pre-merge の `rubric` verify で SKILL.md 修正の意味的検証、(b) bats 回帰テストで下位 script (`gh-label-transition.sh`) の `--remove-label phase/done` 挙動を保証する二段構え。#289 Spec Notes の設計方針を踏襲
- **OPEN 経路は変更しない**: L413-425 の OPEN 経路は本 Issue で目標とする挙動のリファレンスそのものなので変更不要
- **XL 親 Issue close フォールバック**: CLOSED 経路の「Confirm the Issue is closed. If not closed, close with `gh issue close ...`」は XL 親 Issue が PR の `closes #N` で自動クローズされないケース向けの既存挙動。新挙動の `phase/done` 遷移ブロック (a-2) 内に残置
- **「phase/verify 滞留」問題への本質対処は別 Issue**: #289 が解決しようとした manual 条件による滞留問題は本 Issue では戻さない。長期滞留監視や manual 条件の AC 設計見直し等は follow-up Issue で扱う
- **既 `phase/done` 誤遷移 Issue の復旧は Non-Goal**: 既にセッションで手動復旧済み（17 件の `phase/verify` 戻し + 12 件の `phase/done` 正当化）。本 Issue のスコープ外
- **Reference 先行例**: #289 (今回の回帰を導入した Issue), #39 (patch route の phase/done ラベル遷移), #132 (gh-label-transition の target ラベル消失バグ)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の root cause（CLOSED/OPEN 経路不整合）が明確で、修正アプローチ（OPEN 経路ロジックの移植）は最小変更で最大効果。Auto-Resolved Ambiguity Points セクションで実装時の判断揺れを事前解消しており、spec 品質は高かった。

#### design
- CLOSED 経路を OPEN 経路と同型にする設計は明快で、実装と 1:1 に対応。docs/workflow.md / docs/ja/workflow.md の同期も scope に含まれており、ドキュメント整合性が保たれた。

#### code
- git log --oneline で fixup/amend パターンなし。単一コミット (90dd53b) でクリーンな実装。Spec の実装ステップを順序通りに実行し、設計逸脱なし。

#### review
- Code Retrospective, Review Retrospective ともに "なし"。rubric verify が SKILL.md 修正の意味的検証を担い、github_check が CI 状態を確認する 2 段構えが機能した。レビュー指摘の見落としなし。

#### merge
- 単一 PR #305、コンフリクト解消の痕跡なし。クリーンなマージ。

#### verify
- 初回 verify 実行（前回）: 全 Pre-merge 条件 PASS。Post-merge `<!-- verify-type: manual -->` 条件が未チェックのため `phase/verify` を維持（Issue CLOSED のまま）。これは修正の正しさを動的に確認する実例となった。
- 2 回目 verify 実行（今回）: Post-merge 手動条件が `[x]` 確認済みとなり、全条件 PASS で `phase/done` へ遷移。修正サイクル全体が正常完了。
- 2 段階の verify 実行（手動確認待ち → 確認完了）が意図通りのフローを証明した。

### Improvement Proposals
- N/A
